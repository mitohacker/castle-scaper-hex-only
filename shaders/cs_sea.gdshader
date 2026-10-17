// Castle Scaper Realistic's sea: a see-through water surface. How much of the floor (and the rocks and the castle's feet) shows
// through, and in which colour, follows the thickness of water behind the surface (the depth texture): clear turquoise over the
// shallows, deep blue-green further out. Waves are a sum of travelling swells with analytic slopes (no texture, nothing repeats
// visibly), fading to a calm sheen with distance so they never shimmer. Foam collects where the water gets shallow (along the
// rocks and the walls) and on the steepest crests. Reflection of the sky is the engine's (fresnel from the sky's radiance); the
// sun's glitter is its specular highlight on the wave normals.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 deep_col : source_color = vec3(0.012, 0.085, 0.12);
uniform vec3 shallow_col : source_color = vec3(0.07, 0.3, 0.32);
uniform vec3 foam_col : source_color = vec3(0.92, 0.95, 0.95);
uniform vec3 sun_col : source_color = vec3(1.0, 0.8, 0.6);
uniform float clarity = 3.5;
uniform float chop = 0.55;
uniform sampler2D refl_tex : source_color, filter_linear, repeat_disable;
uniform float refl_on = 0.0;
uniform int debug_mode = 0;      // 1 water thickness, 2 alpha, 3 slope (a tool)

varying vec3 v_pos;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// one swell: direction angle, wavelength (m), steepness; returns the surface slope (dh/dx, dh/dz) and adds to the crest measure
vec2 swell(vec2 p, float ang, float wl, float amp, float speed, inout float crest) {
	vec2 d = vec2(cos(ang), sin(ang));
	float k = 6.2831853 / wl;
	float cr = dot(p, vec2(-d.y, d.x)) * k * 0.23;
	float ph = dot(p, d) * k + TIME * speed + 3.4 * sin(cr + 2.6 * sin(cr * 0.57 + ang * 3.0));   // curved, broken wave fronts
	// asymmetric: sharper crests, flatter troughs
	float s = sin(ph);
	float c = cos(ph + 0.35 * s);
	crest += amp * k * (0.5 + 0.5 * s);
	return d * c * amp * k;
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_pos.xz;
	float dist = length(v_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float fade = 1.0 - smoothstep(60.0, 420.0, dist);          // small waves die with distance
	float fade2 = 1.0 - smoothstep(25.0, 140.0, dist);
	// a slow domain warp so the swells never line up
	vec2 q = p + 8.0 * (vec2(vn(p * 0.04 + TIME * 0.02), vn(p * 0.04 + 9.0 - TIME * 0.02)) - 0.5) + 1.6 * (vec2(vn(p * 0.23 + 3.0), vn(p * 0.23 + 17.0 + TIME * 0.05)) - 0.5);
	float crest = 0.0;
	vec2 sl = vec2(0.0);
	sl += swell(q, 0.4, 38.0, 0.16 * chop, 0.9, crest);
	sl += swell(q, 1.1, 21.0, 0.10 * chop, 1.2, crest);
	sl += swell(q, -0.6, 12.0, 0.06 * chop, 1.5, crest) * mix(0.6, 1.0, fade);
	sl += swell(q, 2.2, 6.5, 0.035 * chop, 2.0, crest) * fade;
	sl += swell(q, -1.7, 3.4, 0.02 * chop, 2.6, crest) * fade;
	sl += swell(q, 0.8, 1.7, 0.012 * chop, 3.4, crest) * fade2;
	sl += swell(q, -2.6, 0.9, 0.008 * chop, 4.1, crest) * fade2;
	sl += (vec2(vn(p * 4.0 + TIME * 0.3), vn(p * 4.0 + 5.0 - TIME * 0.25)) - 0.5) * 0.05 * chop * fade2;
	vec3 nw = normalize(vec3(-sl.x, 1.0, -sl.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// the water in front of whatever is behind the surface
	float d = texture(depth_tex, SCREEN_UV).x;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -(ndc.xyz / ndc.w).z;
	float surf_z = -VERTEX.z;
	float thick = max(scene_z - surf_z, 0.0);
	float vert = max(thick * abs(dot(normalize(VIEW), NORMAL)), 0.0);   // about the depth below the surface
	float t = 1.0 - exp(-thick / clarity);
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 1.0, t));
	float alpha = clamp(1.0 - exp(-thick / (clarity * 0.45)), 0.0, 1.0);
	alpha = max(alpha, 0.35);

	// foam: along shallow edges, broken by noise that drifts, and on the steepest crests
	float edge = 1.0 - smoothstep(0.0, 0.9, thick);
	float fn = vn(p * 1.3 + vec2(TIME * 0.15, -TIME * 0.1)) * 0.6 + vn(p * 3.7 - TIME * 0.2) * 0.4;
	float lap = 0.5 + 0.5 * sin(TIME * 1.4 + fn * 6.0 + thick * 4.0);
	float shore = smoothstep(0.35, 0.0, thick - fn * 0.5 + lap * 0.25 - 0.1) * edge;
	float far_crest = smoothstep(0.7, 1.1, crest * 2.0 + fn * 0.2 - 0.1) * chop * fade * 0.2;
	float foam = clamp(shore + far_crest, 0.0, 1.0);
	col = mix(col, foam_col, foam);
	alpha = mix(alpha, 1.0, foam);

	// the castle's reflection (CSReflect): a mirrored camera's picture, shaken by the waves, by Fresnel
	vec3 refl = vec3(0.0);
	float refl_a = 0.0;
	if (refl_on > 0.5) {
		vec2 ruv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + nw.xz * (0.05 + 0.1 * fade2) * vec2(1.0, 1.4);
		vec4 rf = texture(refl_tex, ruv);
		float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float fres = 0.1 + 0.9 * pow(1.0 - ndv, 4.0);
		refl_a = rf.a * clamp(fres * 1.8, 0.0, 0.85) * (1.0 - foam);
		refl = rf.rgb;
	}

	// a little sub-surface glow in thin crests facing the sun
	vec3 glow = sun_col * smoothstep(0.35, 1.0, crest * 2.0) * 0.06 * (1.0 - foam);
	if (debug_mode == 1) {
		ALBEDO = vec3(thick / 20.0, scene_z / 400.0, surf_z / 400.0);
	} else if (debug_mode == 2) {
		ALBEDO = vec3(alpha);
	} else if (debug_mode == 3) {
		ALBEDO = vec3(length(sl) * 4.0);
	} else {
		ALBEDO = col * 1.0 + glow;
		EMISSION = col * 0.3 * (1.0 - foam) * (1.0 - refl_a) + refl * refl_a;
	}
	ROUGHNESS = mix(0.06, 0.55, foam);
	SPECULAR = 0.4;
	METALLIC = 0.0;
	ALPHA = max(alpha, refl_a);
}
