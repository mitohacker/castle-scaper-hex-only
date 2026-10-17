class_name CSPen
extends CompositorEffect
## Pen and colour pencil drawn over the finished realistic picture (the look Kevin starred in castle-scaper-realistic-art round 3, "light"):
## thin, slightly wobbly black pen outlines on the castle's silhouettes and creases, on the horizon and on the clouds' edges, and loose
## coloured-pencil scribbles in the sky and along the waves, never on the castle. A compute pass after the transparent pass (before tone
## mapping), reading the resolved colour and depth buffers. Silhouettes come from the inverse depth (1 / distance is affine across a flat
## surface, so only real steps and creases light up); the sky scribbles are pinned to the sky dome and the sea strokes to the water plane,
## so they move with the world, not with the screen.
##
## mode: 0 off, 1 light, 2 full (heavier line, creases drawn, more scribbles).

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(push_constant, std430) uniform Params {
	vec4 a;      // width, height, time, ink
	vec4 b;      // pencil, pen width, density, creases
	vec4 c;      // projection a, projection b, tan half fov x, tan half fov y
	vec4 d;      // sea level, hatch, wash, 0
	vec4 right;
	vec4 up;
	vec4 back;
	vec4 pos;
} P;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec2 h22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float view_z(ivec2 q) {
	float d = texelFetch(depth_tex, q, 0).r;
	if (d <= 0.0) { return 1e6; }
	return abs(P.c.y / (d + P.c.x));
}

float inv_depth(ivec2 q) {
	float z = view_z(q);
	return z >= 1e5 ? 0.0 : 1.0 / z;
}

// a bundle of parallel pencil strokes in one cell of a 2D field; returns the coverage, outputs the pencil colour
float bundle(vec2 s, float cell, float seed, float px, float dens, out vec3 colour) {
	vec2 g = floor(s / cell);
	vec2 f = s / cell - g;
	vec2 h = h22(g + seed);
	colour = vec3(0.0);
	if (h.x > dens) { return 0.0; }
	float h3 = h21(g * 1.7 + seed + 4.0);
	vec2 centre = vec2(0.3 + 0.4 * h.y, 0.3 + 0.4 * h21(g.yx + seed));
	float ang = 0.35 + (h3 - 0.5) * 0.7;
	vec2 q = f - centre;
	q = vec2(cos(ang) * q.x + sin(ang) * q.y, -sin(ang) * q.x + cos(ang) * q.y);
	float el = (q.x * q.x) / (0.42 * 0.42) + (q.y * q.y) / (0.2 * 0.2);
	if (el > 1.0) { return 0.0; }
	float spacing = 0.04 + 0.015 * h3;
	float lines = abs(fract(q.y / spacing + h3 * 7.0) - 0.5) * spacing;      // distance to the nearest stroke, cell units
	float wd = px * 1.15 / cell;                                                // stroke half width, cell units
	float cov = 1.0 - smoothstep(wd * 0.6, wd * 1.4, lines);
	cov *= 1.0 - smoothstep(0.55, 1.0, el);                                     // strokes thin out at the ends
	float row = floor(q.y / spacing + h3 * 7.0);
	cov *= step(0.12, h21(vec2(row, g.x * 3.0 + g.y)));                         // some strokes skipped
	float pick = h21(g + seed + 9.0);
	if (pick < 0.38) { colour = vec3(0.55, 0.45, 0.78); }
	else if (pick < 0.7) { colour = vec3(0.46, 0.55, 0.78); }
	else if (pick < 0.86) { colour = vec3(0.95, 0.96, 1.0); }
	else { colour = vec3(0.3, 0.31, 0.36); }
	return cov;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(P.a.xy);
	if (px.x >= size.x || px.y >= size.y) { return; }
	vec4 col = imageLoad(color_image, px);
	float t = P.a.z;
	float ink = P.a.w;
	float pencil = P.b.x;
	float wdt = P.b.y;
	float dens = P.b.z;
	float creases = P.b.w;
	float sc = float(size.y) / 1080.0;
	vec2 fp = vec2(px) + 0.5;
	vec2 uv = fp / vec2(size);
	vec2 ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
	vec3 dir = normalize(P.right.xyz * ndc.x * P.c.z + P.up.xyz * ndc.y * P.c.w - P.back.xyz);
	float z0 = view_z(px);
	bool sky = z0 >= 1e5;
	float ang_px = 2.0 * P.c.w / float(size.y);                       // radians per pixel (vertical)

	// the sea: where the view ray reaches the water plane before anything solid
	bool sea = false;
	float tsea = 1e9;
	if (dir.y < -0.0005) {
		tsea = (P.d.x - P.pos.y) / dir.y;
		float dist_scene = z0 / max(dot(dir, -P.back.xyz), 0.05);
		// a solid pixel is water when its world height is within a wave's reach of the sea level (the water writes depth too)
		float wy = P.pos.y + dir.y * dist_scene;
		sea = sky || wy < P.d.x + 0.55 || z0 > 400.0;
	}
	bool open_air = sky || sea;

	// ---- pen: silhouettes and creases from the inverse depth, shaken a little
	vec2 wob = (vec2(vn(fp / 53.0 + 3.1), vn(fp / 53.0 + 9.7)) - 0.5) * 3.2 * sc;
	ivec2 q = clamp(ivec2(fp + wob), ivec2(0), size - 1);
	int r = max(1, int(round(1.5 * wdt * sc)));
	float wc = inv_depth(q);
	float e = 0.0;
	ivec2 offs[4] = ivec2[4](ivec2(r, 0), ivec2(-r, 0), ivec2(0, r), ivec2(0, -r));
	for (int i = 0; i < 4; i++) {
		ivec2 qn = clamp(q + offs[i], ivec2(0), size - 1);
		float wn = inv_depth(qn);
		float rel = (wc - wn) / max(wc, 1e-6);
		e = max(e, smoothstep(0.045, 0.11, rel) * (wc > 0.0 ? 1.0 : 0.0));
	}
	if (creases > 0.0 && wc > 0.0) {
		float wl = inv_depth(clamp(q - ivec2(r, 0), ivec2(0), size - 1));
		float wr = inv_depth(clamp(q + ivec2(r, 0), ivec2(0), size - 1));
		float wu = inv_depth(clamp(q - ivec2(0, r), ivec2(0), size - 1));
		float wd2 = inv_depth(clamp(q + ivec2(0, r), ivec2(0), size - 1));
		float cr = max(abs(wl + wr - 2.0 * wc), abs(wu + wd2 - 2.0 * wc)) / wc;
		e = max(e, creases * smoothstep(0.012, 0.03, cr));
	}
	// a hand-drawn line breaks now and then and is not the same weight all along
	e *= smoothstep(0.08, 0.3, vn(fp / 9.0 + 5.0) + 0.22) * (0.7 + 0.3 * vn(fp / 23.0 + 1.0));
	if (sea && !sky) { e = 0.0; }
	float line = e;

	// the horizon: one thin pen line
	if (open_air && abs(dir.y) < ang_px * 0.75 * wdt * sc) {
		line = max(line, 0.9 * smoothstep(0.05, 0.25, vn(vec2(fp.x / 40.0, 2.0)) + 0.3));
	}

	// the clouds' edges: where the sky's brightness changes fast, in loose dashes
	if (sky && ink > 0.0) {
		ivec2 o2 = ivec2(max(2, int(2.5 * sc)));
		float lx = lum(imageLoad(color_image, clamp(px + ivec2(o2.x, 0), ivec2(0), size - 1)).rgb) - lum(imageLoad(color_image, clamp(px - ivec2(o2.x, 0), ivec2(0), size - 1)).rgb);
		float ly = lum(imageLoad(color_image, clamp(px + ivec2(0, o2.y), ivec2(0), size - 1)).rgb) - lum(imageLoad(color_image, clamp(px - ivec2(0, o2.y), ivec2(0), size - 1)).rgb);
		float g = sqrt(lx * lx + ly * ly) / max(lum(col.rgb), 0.05);
		float dash = smoothstep(0.55, 0.7, vn(fp / 55.0 + 11.0)) ;
		line = max(line, smoothstep(0.22, 0.4, g) * dash * 0.55);
	}

	// ---- pencil: scribbles pinned to the sky dome and to the water, never on the castle
	vec3 pcol = vec3(0.0);
	float pcov = 0.0;
	if (pencil > 0.0) {
		if (sky && dir.y > 0.02) {
			vec2 s = vec2(atan(dir.x, dir.z) * 2.2, dir.y * 2.4);
			float pxs = ang_px * 2.4;
			vec3 c1;
			pcov = bundle(s, 0.5, 1.0, pxs * 1.1 * sc, 0.4 * dens, c1);
			pcol = c1;
			vec3 c2;
			float p2 = bundle(s * 1.5 + 13.0, 0.5, 7.0, pxs * 1.1 * sc * 1.5, 0.22 * dens, c2);
			if (p2 > pcov) { pcov = p2; pcol = c2; }
		} else if (sea && tsea < 700.0) {
			vec2 wxz = (P.pos.xz + dir.xz * tsea);
			float stroke_all = 0.0;
			vec3 sc_col = vec3(0.0);
			for (int ls = 0; ls < 2; ls++) {
				float a0 = ls == 0 ? 0.4 : 1.05;
				vec2 d0 = vec2(cos(a0), sin(a0));
				float u = dot(wxz, d0);
				float v = dot(wxz, vec2(-d0.y, d0.x));
				float rowh = (ls == 0 ? 3.6 : 5.2) + tsea * 0.012;
				float vj = v + 9.0 * vn(vec2(u * 0.02, float(ls) * 7.0));            // rows are not straight
				float row = floor(vj / rowh);
				float fv = fract(vj / rowh);
				float seg = 10.0 + 14.0 * h11(row + 3.0 + float(ls) * 11.0);
				float uu = u + 37.0 * h11(row + float(ls));
				float si = floor(uu / seg);
				float su = fract(uu / seg);
				float on = step(1.0 - (ls == 0 ? 0.42 : 0.2) * dens, h21(vec2(si, row + float(ls) * 31.0)));
				float centre = 0.5 + 0.15 * sin(uu * 0.22 + row * 2.1) + 0.05 * sin(uu * 0.6 + row);
				float pix_w = tsea * ang_px / max(-dir.y, 0.06) / rowh * 2.0 * sc;
				float st = 1.0 - smoothstep(pix_w * 0.5, pix_w * 1.4, abs(fv - centre));
				st *= smoothstep(0.0, 0.2, su) * (1.0 - smoothstep(0.75, 1.0, su)) * on;
				st *= 1.0 - smoothstep(300.0, 700.0, tsea);
				float pk = h21(vec2(si + 5.0, row + float(ls)));
				vec3 cc = pk < 0.58 ? vec3(0.2, 0.76, 0.82) : (pk < 0.82 ? vec3(0.93, 0.98, 1.0) : vec3(0.18, 0.34, 0.66));
				if (st > stroke_all) { stroke_all = st; sc_col = cc; }
			}
			pcol = sc_col;
			pcov = stroke_all;
		}
		// pencil has grain: the paper shows through
		float grain = 0.55 + 0.45 * h21(floor(fp / max(sc, 1.0)) + t * 0.0);
		pcov *= grain * pencil;
	}
	// ---- on the castle (anything solid above the water): pen hatching in the shadows and a coloured-pencil wash over the lit walls and roofs.
	// Both are laid in WORLD space (stripes of planes through the scene), so they stay on the stone when the camera moves, and they fade out
	// into a flat tone when a stroke gets thinner than a few pixels.
	if (!open_air && z0 < 1e5 && (P.d.y > 0.0 || P.d.z > 0.0)) {
		float dist = z0 / max(dot(dir, -P.back.xyz), 0.05);
		vec3 W = P.pos.xyz + dir * dist;
		float pf = max(dist * ang_px, 1e-4);                            // metres per pixel here
		float l = lum(col.rgb);
		// shadow hatching: strokes along one diagonal, cross strokes in the deepest shade
		float dark = 1.0 - smoothstep(0.05, 0.4, l);
		float sp = 0.16;
		float seen = smoothstep(2.2, 4.0, sp / pf);
		float ph1 = dot(W, normalize(vec3(0.55, -1.0, 0.45))) / sp + 0.45 * vn(W.xz * 1.3 + W.y * 0.9);
		float st1 = 1.0 - smoothstep(0.5 * (0.22 + 0.2 * dark), 0.5 * (0.32 + 0.3 * dark), abs(fract(ph1) - 0.5));
		st1 *= step(0.28, vn(vec2(floor(ph1) * 1.7, dot(W, vec3(0.8, 0.2, -0.6)) * 0.9)) + 0.18 * dark);    // strokes start and stop
		float ph2 = dot(W, normalize(vec3(-0.5, -0.9, 0.5))) / (sp * 1.15) + 0.6 * vn(W.zx * 1.1);
		float st2 = 1.0 - smoothstep(0.1, 0.17, abs(fract(ph2) - 0.5));
		float cover = st1 * smoothstep(0.1, 0.45, dark) + st2 * smoothstep(0.55, 0.9, dark);
		cover = mix(0.3 * dark, cover, seen);
		vec3 ink_col = vec3(0.03, 0.03, 0.05);
		col.rgb = mix(col.rgb, ink_col, clamp(cover * P.d.y * 0.7, 0.0, 0.85));
		// pencil wash: broad strokes that pull the surface's own colour a little further, lighter and warmer where it is lit
		float spw = 0.07;
		float seenw = smoothstep(2.0, 3.5, spw / pf);
		float phw = dot(W, normalize(vec3(0.7, -0.45, 0.55))) / spw + 0.5 * vn(W.xz * 0.7 + W.y * 0.5);
		float tone = h21(vec2(floor(phw), floor(dot(W, vec3(0.6, 0.3, -0.7)) * 0.6)));
		float sw = 1.0 - smoothstep(0.30, 0.5, abs(fract(phw) - 0.5));
		sw *= smoothstep(0.2, 0.55, vn(vec2(floor(phw) * 3.1, dot(W, vec3(0.8, 0.2, -0.6)) * 0.5)));
		vec3 sat = mix(vec3(l), col.rgb, 1.7) * (0.9 + 0.35 * tone);
		float lit = smoothstep(0.1, 0.5, l);
		col.rgb = mix(col.rgb, sat, clamp(sw * seenw * P.d.z * (0.35 + 0.35 * lit), 0.0, 0.7));
		col.rgb *= 1.0 + P.d.z * (h21(floor(fp)) - 0.5) * 0.06;                   // paper grain
	}
	col.rgb = mix(col.rgb, pow(pcol, vec3(2.2)), clamp(pcov, 0.0, 1.0) * 0.9);
	col.rgb = mix(col.rgb, vec3(0.025, 0.025, 0.035), clamp(line * ink, 0.0, 1.0));
	imageStore(color_image, px, col);
}
"""

var mode := 0
var time := 0.0
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var sampler: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	needs_normal_roughness = false
	enabled = false
	RenderingServer.call_on_render_thread(_init_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			rd.free_rid(shader)
		if sampler.is_valid():
			rd.free_rid(sampler)


func _init_compute() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = GLSL
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("CSPen shader: " + spirv.compile_error_compute)
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler = rd.sampler_create(ss)


func set_mode(m: int) -> void:
	mode = m
	enabled = m > 0


func _render_callback(p_type: int, p_render_data: RenderData) -> void:
	if rd == null or not pipeline.is_valid() or mode <= 0 or p_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	var buffers := p_render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := p_render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var proj: Projection = data.get_cam_projection()
	var tf: Transform3D = data.get_cam_transform()
	var light := mode == 1
	var pc := PackedFloat32Array([
		float(size.x), float(size.y), time, 0.9 if light else 1.0,
		0.85 if light else 1.0, 1.0 if light else 1.5, 1.0 if light else 1.8, 0.0 if light else 1.0,
		proj.z.z, proj.w.z, 1.0 / absf(proj.x.x), 1.0 / absf(proj.y.y),
		0.0, 0.55 if light else 1.0, 0.6 if light else 1.0, 0.0,
		tf.basis.x.x, tf.basis.x.y, tf.basis.x.z, 0.0,
		tf.basis.y.x, tf.basis.y.y, tf.basis.y.z, 0.0,
		tf.basis.z.x, tf.basis.z.y, tf.basis.z.z, 0.0,
		tf.origin.x, tf.origin.y, tf.origin.z, 0.0])
	var groups_x := (size.x - 1) / 8 + 1
	var groups_y := (size.y - 1) / 8 + 1
	for view in buffers.get_view_count():
		var img := RDUniform.new()
		img.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		img.binding = 0
		img.add_id(buffers.get_color_layer(view))
		var dep := RDUniform.new()
		dep.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		dep.binding = 1
		dep.add_id(sampler)
		dep.add_id(buffers.get_depth_layer(view))
		var us := UniformSetCacheRD.get_cache(shader, 0, [img, dep])
		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, us, 0)
		rd.compute_list_set_push_constant(cl, pc.to_byte_array(), pc.size() * 4)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_end()
