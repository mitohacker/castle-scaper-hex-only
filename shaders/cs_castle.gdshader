// Castle Scaper Realistic: the castle's skin as real materials, all procedural. Every face carries its metre frame (UV: u along
// the wall, v up it; paving uses x, z), a zone (CFMesh.Z_*), the block's palette index (COLOR.g * 16: which stone, render or brick
// that block is made of, CSBuild.colour_seed), flags, the distances to its real edges (CUSTOM0) and a tangent frame. Joints, block
// tones, pits, lichen, moss, rain streaks, salt, algae and barnacles at the sea line, worn edges are computed here; the pattern is
// filtered by the pixel's footprint so nothing shimmers at a distance. The block just added pops up from its foot (CUSTOM1).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float pop_id = -1.0;
uniform float pop_t = 1.0;
uniform float hover_id = -1.0;
uniform float land_y = 0.6;
uniform float castle_seed = 3.0;
uniform float moss = 0.55;        // 0..1 how green the damp places get
uniform float grime = 0.8;        // 0..1 rain streaks, soot, dirt
uniform float wear = 0.7;         // 0..1 chipped corners
uniform float wetness = 0.0;      // 0 dry .. 1 rained on: darker, glossier stone
uniform float time_of_wind = 0.0;

varying vec4 v_c0;
varying flat vec4 v_col;
varying flat float v_owner;
varying vec3 v_wpos;
varying vec3 v_wnrm;

// distance to the nearest joint of the course pattern, for the parallax search
float joint_dist(vec2 uv, float sd, int pat, float scale) {
	float dj;
	float tone;
	vec2 slope;
	float bid;
	if (pat == 2) {
		brick(uv, sd, dj, tone, slope, bid);
	} else {
		ashlar(uv, sd, scale, 1.1, dj, tone, slope, bid);
	}
	return dj;
}

// steep parallax: the joints are recessed 3 cm; walk the view ray down into them
vec2 parallax_uv(vec2 uv, vec3 vt, float sd, int pat, float scale, float seam_w) {
	const int N = 8;
	float depth_m = 0.03;
	vec2 delta = (vt.xy / max(vt.z, 0.15)) * depth_m / float(N);
	vec2 cur = uv;
	float layer = 0.0;
	float step_d = 1.0 / float(N);
	float hd = 1.0 - smoothstep(0.0, seam_w * 1.4, joint_dist(cur, sd, pat, scale));
	for (int i = 0; i < N; i++) {
		if (layer >= hd) {
			break;
		}
		cur -= delta;
		layer += step_d;
		hd = 1.0 - smoothstep(0.0, seam_w * 1.4, joint_dist(cur, sd, pat, scale));
	}
	return cur;
}

void vertex() {
	v_col = COLOR;
	v_c0 = CUSTOM0;
	v_owner = CUSTOM1.w;
	if (pop_t < 1.0 && abs(CUSTOM1.w - pop_id) < 0.5) {
		float t = clamp(pop_t, 0.0, 1.0);
		float s = t <= 0.0 ? 0.0 : pow(2.0, -9.0 * t) * sin((t * 9.0 - 0.75) * 2.0943951) + 1.0;
		VERTEX = CUSTOM1.xyz + (VERTEX - CUSTOM1.xyz) * vec3(mix(1.0, s, 0.35), s, mix(1.0, s, 0.35));
	}
	int vz = int(COLOR.r * 255.0 + 0.5);
	if (vz == 10 || vz == 11) {
		// a banner in the wind: it ripples more the further it is from its pole
		float k = clamp(length(UV) / 2.6, 0.0, 1.0);
		float ph = TIME * 4.2 + VERTEX.x * 1.3 + VERTEX.z * 1.1 + VERTEX.y * 2.0;
		VERTEX += vec3(0.1 * sin(ph * 0.8), 0.1 * sin(ph + 1.3), 0.14 * cos(ph)) * k;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// the mirrored camera (CSReflect) sits under the water: what is under the water is not part of the reflection
	if (INV_VIEW_MATRIX[3][1] < 0.0 && v_wpos.y < 0.0) {
		discard;
	}
	int zone = int(v_col.r * 255.0 + 0.5);
	int ci = clamp(int(v_col.g * 16.0), 0, 11);
	int flg = int(v_col.b * 255.0 + 0.5);
	vec2 uv = UV;
	vec3 wn = normalize(v_wnrm);
	float up = wn.y;
	bool horizontal = abs(up) > 0.7;
	vec3 P = v_wpos;
	float fw = max(length(fwidth(uv)), 1e-4);
	float lod = smoothstep(0.018, 0.08, fw);
	float fine1 = 1.0 - smoothstep(0.005, 0.013, fw);   // 1.5 cm detail
	float fine2 = 1.0 - smoothstep(0.012, 0.03, fw);    // 7 cm detail          // 0 close .. 1 the pattern is below a pixel
	float d_edge = min(min(v_c0.x, v_c0.y), min(v_c0.z, v_c0.w));
	float d_top = v_c0.w;
	float tone_owner = h11(v_owner + castle_seed);

	vec3 albedo = vec3(0.5);
	float rough = 0.9;
	float metal = 0.0;
	vec3 emis = vec3(0.0);
	float ao = 1.0;
	vec2 grad = vec2(0.0);
	float n_big = fbm3(P * 0.19 + vec3(castle_seed * 1.3));
	float n_mid = fbm3(P * 1.6 + vec3(castle_seed * 0.7, 3.0, 1.0));
	float n_fine = vn3(P * 11.0);
	float sea = smoothstep(1.7, -0.35, P.y);          // 1 at the water line, 0 high above
	float splash = smoothstep(2.6, 0.2, P.y);

	if (zone == 0 || zone == 1 || zone == 2 || zone == 8) {
		vec3 base;
		vec3 joint_col;
		float dj = 1.0;
		float tone = 0.5;
		vec2 slope = vec2(0.0);
		float bid = 0.0;
		float seam_w = 0.012;
		float bump = 0.2;
		bool is_render = false;
		float sd = float(ci) * 3.7 + castle_seed;
		int pat = W_PAT[ci];
		if (zone == 1) {
			// the rock the castle stands on: big weathered stones, dark and wet toward the sea
			base = lin(vec3(0.46, 0.43, 0.38));
			joint_col = base * 0.35;
			if (horizontal) {
				flags(P.xz * 0.9, sd, dj, tone, slope);
				dj /= 0.9;
			} else {
				vec2 w = uv + 0.3 * vec2(vn2(uv * 1.3 + sd), vn2(uv * 1.3 + 7.0));
				rubble(w * 1.4, sd, dj, tone, slope, bid);
				dj /= 1.4;
				bump = 0.5;
			}
			seam_w = 0.05;
		} else if (zone == 2 || horizontal) {
			// paving and the level tops of walls: irregular dressed slabs laid in rows
			base = zone == 2 ? lin(vec3(0.56, 0.53, 0.48)) : lin(W_COL[ci]) * 0.9;
			joint_col = base * 0.55;
			ashlar(vec2(P.x, P.z), sd, 0.55, 1.25, dj, tone, slope, bid);
			seam_w = 0.016;
		} else {
			base = lin(W_COL[ci]);
			joint_col = mix(base * 0.8, lin(vec3(0.6, 0.57, 0.5)), 0.5);
			float pom = 1.0 - smoothstep(0.008, 0.03, fw);
			if (pom > 0.01 && (pat == 0 || pat == 2)) {
				vec3 vt = vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL));
				float sc = (flg & 16) != 0 ? 1.1 : 0.62;
				float sw = pat == 2 ? 0.006 : 0.012;
				uv = mix(uv, parallax_uv(uv, vt, sd, pat, sc, sw), pom);
			}
			if (pat == 0) {
				ashlar(uv, sd, (flg & 16) != 0 ? 1.1 : 0.62, 1.1, dj, tone, slope, bid);
			} else if (pat == 2) {
				brick(uv, sd, dj, tone, slope, bid);
				seam_w = 0.006;
				joint_col = lin(vec3(0.62, 0.58, 0.52));
			} else if (pat == 3) {
				vec2 w = uv + 0.2 * vec2(vn2(uv * 1.7 + sd), vn2(uv * 1.7 + 7.0));
				rubble(w * 2.2, sd, dj, tone, slope, bid);
				dj /= 2.2;
				bump = 0.4;
				seam_w = 0.035;
				joint_col = base * 0.5;
			} else {
				is_render = true;
			}
		}
		float pat_fade = 1.0 - lod;
		float seam = (1.0 - smoothstep(seam_w * 0.4, seam_w + fw * 0.8, dj)) * pat_fade * 0.6;
		vec3 b = base;
		float hue = h11(bid * 91.7 + 3.0);
		// fine grain, per stone: the same grain never repeats from block to block
		float grain = vn3(P * 26.0 + bid * 31.0);
		float grain2 = mix(0.5, vn3(P * 70.0 + bid * 11.0), fine1);
		if (is_render) {
			// lime render: trowelled, stippled, hairline cracks along cell edges, chipped back to rubble where it is knocked
			float trowel = vn2(vec2(uv.x * 1.6, uv.y * 0.9) + sd);
			b *= 0.9 + 0.2 * trowel;
			b *= 0.97 + 0.06 * grain2;
			float cdj;
			float ctn;
			vec2 csl;
			float cid;
			rubble(uv * 1.05 + sd, sd, cdj, ctn, csl, cid);
			float cracked = step(0.7, h21(vec2(cid * 19.0, sd))) * smoothstep(0.42, 0.58, vn2(uv * 3.1 + sd));
			float crack = (1.0 - smoothstep(0.004, 0.004 + fw * 1.5, cdj / 1.05)) * cracked * (0.5 + 0.5 * vn2(uv * 7.0));
			b *= 1.0 - 0.45 * crack * (1.0 - lod);
			float chip_n = fbm3(P * vec3(1.4, 2.0, 1.4) + sd) + 0.08 * vn2(uv * 9.0);
			float near = smoothstep(1.4, 0.0, P.y - land_y) * 0.6 + (1.0 - smoothstep(0.0, 0.45, d_edge)) * 0.5;
			float lost = smoothstep(0.7, 0.73, chip_n + near * 0.22) * (horizontal ? 0.0 : 1.0);
			float sdj;
			float stn;
			vec2 ssl;
			float sbid;
			rubble(uv * 2.4, sd + 5.0, sdj, stn, ssl, sbid);
			vec3 stone = lin(vec3(0.56, 0.52, 0.45)) * (0.7 + 0.5 * stn) * mix(0.5, 1.0, smoothstep(0.0, 0.05, sdj / 2.4));
			b = mix(b, stone, lost);
			grad += ssl * 0.12 * lost;
			rough = mix(0.93, 0.95, lost);
			ao *= mix(1.0, 0.9, lost);
		} else {
			b *= 0.86 + 0.28 * tone;
			b = mix(b, b * vec3(1.1, 1.0, 0.84), smoothstep(0.55, 0.95, hue) * 0.7);
			b = mix(b, b * vec3(0.92, 0.97, 1.05), smoothstep(0.45, 0.05, hue) * 0.5);
			float strata = vn2(vec2(uv.x * 0.35 + sd, uv.y * 7.0 + hue * 5.0));
			b *= 0.94 + 0.12 * strata;
			b *= 0.93 + 0.14 * grain;
			grad += slope * bump * 0.12 * pat_fade;
			// each stone is a little dished and tilted
			grad += vec2(h11(bid * 17.3 + 1.0) - 0.5, h11(bid * 29.1 + 2.0) - 0.5) * 0.22 * pat_fade;
			rough = mix(0.86, 0.97, grain2);
		}
		// surface relief at two scales (world-space noise gradient projected on the face's frame)
		{
			vec3 Tw = normalize((INV_VIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
			vec3 Bw = normalize((INV_VIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
			float e = 0.02;
			vec3 q = P * 14.0 + bid * 7.0;
			vec3 qx = q + Tw * e * 14.0;
			vec3 qy = q + Bw * e * 14.0;
			float h0 = vn3(q) * 0.65 + vn3(q * 2.7) * 0.35;
			float hx = vn3(qx) * 0.65 + vn3(qx * 2.7) * 0.35;
			float hy = vn3(qy) * 0.65 + vn3(qy * 2.7) * 0.35;
			float amp = (is_render ? 0.35 : 0.55) * fine2;
			grad += vec2(hx - h0, hy - h0) / e * 0.012 * amp;
		}
		float cavity = smoothstep(0.35, 0.8, vn3(P * 14.0 + bid * 7.0));
		b *= 0.94 + 0.08 * cavity;
		b *= 0.96 + 0.08 * h11(v_owner * 1.7 + castle_seed);
		float pit = smoothstep(0.66, 0.9, n_mid);
		b *= 1.0 - 0.16 * pit;
		// large-scale patina: sun-bleached and shaded patches over whole walls
		b *= 0.86 + 0.28 * smoothstep(0.25, 0.75, n_big);
		b = mix(b, b * vec3(1.06, 1.0, 0.9), smoothstep(0.45, 0.8, fbm3(P * 0.33 + 20.0)) * 0.6);
		// rain streaks under ledges and where the water runs; soot near the top
		float streak = vn2(vec2(uv.x * 2.6 + sd * 11.0, uv.y * 0.3));
		float streak2 = vn2(vec2(uv.x * 9.0 + sd * 5.0, uv.y * 0.9));
		float below = smoothstep(2.4, 0.0, d_top);
		float gr = smoothstep(0.42, 0.95, n_big) * 0.4 + smoothstep(0.5, 0.92, streak) * (0.35 + 0.35 * streak2) * below
			+ smoothstep(1.2, 0.0, P.y - land_y) * 0.3;
		gr = clamp(gr * grime, 0.0, 1.0);
		b *= 1.0 - 0.45 * gr;
		// lichen: dry, level or sunward surfaces, as small round colonies
		vec2 lq = horizontal ? P.xz : uv;
		float lich_n = vn2(lq * 5.5 + sd * 9.0);
		float lich = smoothstep(0.74, 0.8, lich_n * (0.5 + 0.7 * n_big)) * smoothstep(-0.3, 0.7, up) * (1.0 - sea);
		vec3 lcol = mix(vec3(0.62, 0.52, 0.16), vec3(0.50, 0.55, 0.38), h11(floor(lq * 5.5).x + floor(lq * 5.5).y * 7.0));
		b = mix(b, lin(lcol), lich * 0.5 * (1.0 - lod * 0.5));
		// moss: damp, low and level places, in the joints and on top
		float damp = smoothstep(4.0, 0.2, P.y) * 0.8 + smoothstep(0.55, 1.0, up) * 0.55 + wetness * 0.3;
		float mo = smoothstep(0.5, 0.78, fbm3(P * 1.05 + vec3(castle_seed, 0.0, 4.0)) + damp * 0.28 - 0.16) * moss;
		vec3 mcol = mix(vec3(0.16, 0.26, 0.08), vec3(0.30, 0.38, 0.12), grain);
		b = mix(b, lin(mcol), mo * (0.55 + 0.4 * seam));
		// the sea line: salt-bleached splash zone, then dark wet stone, algae, barnacles
		b = mix(b, b * 1.12 + 0.03, smoothstep(2.4, 1.0, P.y) * smoothstep(0.1, 1.0, P.y) * 0.5);
		float wet_band = smoothstep(1.0, -0.1, P.y);
		b *= mix(1.0, 0.5, wet_band);
		float algae = smoothstep(0.55, 0.2, P.y) * smoothstep(0.35, 0.65, vn3(P * vec3(3.0, 6.0, 3.0) + 1.0));
		b = mix(b, lin(vec3(0.12, 0.2, 0.06)), algae * 0.75);
		float barn = smoothstep(0.78, 0.84, h21(floor(vec2(uv.x, P.y) * 38.0))) * smoothstep(0.7, 0.0, P.y) * (1.0 - lod);
		b = mix(b, lin(vec3(0.75, 0.74, 0.68)), barn * 0.7);
		float wet = clamp(wet_band + wetness * 0.8, 0.0, 1.0);
		rough = mix(rough, 0.35, wet * 0.8);
		// joints and cavities
		vec3 j_col = joint_col * (0.8 + 0.4 * grain2);
		albedo = mix(b, j_col, seam * (is_render ? 0.0 : 1.0));
		ao *= 1.0 - seam * 0.5;
		// worn corners: lighter, chipped
		float ew = (1.0 - smoothstep(0.0, 0.035 + 0.07 * n_mid, d_edge)) * wear;
		albedo = mix(albedo, albedo * 1.14 + 0.012, ew * 0.5);
		ao *= mix(0.8, 1.0, smoothstep(0.0, 0.6, d_edge));
		if (zone == 8) {
			albedo = lin(vec3(0.05, 0.045, 0.04)) * (0.8 + 0.4 * grain2);
			ao = 0.35;
			rough = 1.0;
		}
	} else if (zone == 3) {
		// slate: overlapping rows of slates, each its own tone, mossy on the sheltered slopes
		float row_h = 0.26;
		float row = floor(uv.y / row_h);
		float ly = fract(uv.y / row_h);
		float off = h11(row + v_col.g * 7.0) * 2.0;
		float sw = 0.31;
		float x = uv.x / sw + off;
		float col = floor(x);
		float lx = fract(x);
		float tone = h21(vec2(col, row) + v_col.g * 3.0);
		vec3 base = lin(vec3(0.27, 0.32, 0.34)) * (0.6 + 0.8 * tone);
		base = mix(base, base * vec3(1.15, 1.0, 0.9), smoothstep(0.7, 1.0, h21(vec2(col, row) + 9.0)) * 0.6);
		float gap_v = smoothstep(0.0, 0.05, lx) * smoothstep(1.0, 0.95, lx);
		float lap = smoothstep(0.0, 0.2, ly);
		float shade = (0.5 + 0.5 * lap * gap_v);
		base *= mix(1.0, shade, 1.0 - lod * 0.6);
		float mo = smoothstep(0.5, 0.8, n_mid + 0.1 * (1.0 - up)) * moss * 0.8;
		base = mix(base, lin(vec3(0.22, 0.31, 0.1)), mo);
		base *= 1.0 - 0.35 * smoothstep(0.5, 0.95, n_big);
		albedo = base;
		rough = mix(0.78, 0.3, wetness * 0.8) + 0.1 * tone;
		grad = vec2((lx - 0.5) * 0.05, (0.5 - ly) * 0.4 * (1.0 - lap)) * (1.0 - lod);
		ao *= 0.78 + 0.22 * lap;
	} else if (zone == 4) {
		// clay tiles: pans and covers in rows, fired reds to browns, orange and green lichen
		float row_h = 0.34;
		float row = floor(uv.y / row_h);
		float ly = fract(uv.y / row_h);
		float off = h11(row + v_col.g * 3.0) * 0.5;
		float tw = 0.27;
		float x = uv.x / tw + off;
		float col = floor(x);
		float lx = fract(x);
		float tone = h21(vec2(col, row) + v_col.g);
		vec3 hot = lin(vec3(0.58, 0.30, 0.2));
		vec3 cool = lin(vec3(0.4, 0.22, 0.17));
		vec3 base = mix(cool, hot, tone) * (0.92 + 0.14 * n_mid);
		float barrel = sin(lx * 3.14159);
		base *= mix(1.0, 0.55 + 0.55 * barrel, 1.0 - lod * 0.7);
		base *= mix(1.0, 0.6 + 0.4 * smoothstep(0.0, 0.22, ly), 1.0 - lod * 0.7);
		base = mix(base, lin(vec3(0.34, 0.36, 0.16)), smoothstep(0.62, 0.9, n_mid) * 0.5 * moss);
		float lich = smoothstep(0.78, 0.84, vn2(uv * 6.0 + 3.0));
		base = mix(base, lin(vec3(0.62, 0.55, 0.22)), lich * 0.35);
		albedo = base;
		rough = mix(0.72, 0.4, wetness * 0.7);
		grad = vec2(cos(lx * 3.14159) * 0.3, (0.5 - ly) * 0.28) * (1.0 - lod);
		ao *= 0.72 + 0.28 * barrel;
	} else if (zone == 5 || zone == 9) {
		// timber: planks with grain, shrinkage cracks and iron nails (doors add the straps)
		float pw = 0.19;
		float x = uv.x / pw;
		float px = floor(x);
		float lx = fract(x);
		float tone = h21(vec2(px, v_col.g * 5.0));
		float grain = vn2(vec2(uv.x * 45.0 + px * 7.0, uv.y * 1.6 + tone * 20.0));
		float ring = vn2(vec2(uv.x * 8.0 + px * 3.0, uv.y * 0.5 + tone * 9.0));
		vec3 base = (zone == 9 ? lin(vec3(0.27, 0.17, 0.1)) : lin(vec3(0.33, 0.23, 0.14))) * (0.65 + 0.7 * tone) * (0.8 + 0.3 * grain) * (0.9 + 0.2 * ring);
		float groove = smoothstep(0.0, 0.07, lx) * smoothstep(1.0, 0.93, lx);
		base *= 0.5 + 0.5 * groove;
		base = mix(base, base * lin(vec3(0.6, 0.62, 0.6)) * 2.2, wetness * 0.2);
		float silver = smoothstep(0.55, 0.9, n_big) * 0.3;
		base = mix(base, lin(vec3(0.46, 0.43, 0.38)), silver);
		if (zone == 9) {
			float strap = 0.0;
			for (int k = 0; k < 3; k++) {
				float yy = 0.38 + float(k) * 0.8;
				strap = max(strap, 1.0 - smoothstep(0.045, 0.06 + fw, abs(uv.y - yy)));
			}
			float nail = (1.0 - smoothstep(0.012, 0.02 + fw, length(vec2(fract(uv.x / 0.19) - 0.5, 0.0) * 0.19 - 0.0))) * strap;
			base = mix(base, vec3(0.03, 0.03, 0.035), strap * 0.9);
			metal = strap * 0.7;
		}
		albedo = base;
		rough = zone == 9 ? 0.7 : 0.78;
		grad = vec2((lx - 0.5) * 0.28 * (1.0 - groove), (grain - 0.5) * 0.03);
		ao *= 0.55 + 0.45 * groove;
	} else if (zone == 6) {
		albedo = lin(vec3(0.82, 0.78, 0.68)) * (0.88 + 0.2 * n_big);
		rough = 0.95;
	} else if (zone == 7) {
		albedo = vec3(0.045, 0.045, 0.05) * (0.8 + 0.5 * n_fine);
		metal = 0.8;
		rough = 0.5;
	} else if (zone == 10 || zone == 11) {
		// banner: plain dyed linen with a visible weave
		vec3 c = zone == 10 ? lin(vec3(0.62, 0.1, 0.1)) : lin(vec3(0.12, 0.22, 0.5));
		float weave = 0.9 + 0.1 * sin(uv.x * 220.0) * sin(uv.y * 220.0);
		albedo = c * weave * (0.85 + 0.2 * vn2(uv * 20.0));
		rough = 0.95;
	} else if (zone == 12) {
		albedo = vec3(0.04, 0.03, 0.02);
		emis = vec3(1.0, 0.7, 0.35) * 2.4 * (0.85 + 0.15 * sin(TIME * 7.0 + v_col.g * 40.0));
	} else if (zone == 13) {
		albedo = lin(vec3(0.85, 0.65, 0.18));
		metal = 0.9;
		rough = 0.3;
	} else if (zone == 14) {
		float streak = vn2(vec2(uv.x * 14.0, uv.y * 2.2));
		albedo = lin(mix(vec3(0.5, 0.38, 0.18), vec3(0.7, 0.58, 0.3), streak)) * (0.8 + 0.3 * n_mid);
		rough = 1.0;
	}

	// the hovered block lifts a little
	if (abs(v_owner - hover_id) < 0.5 && zone != 1 && zone != 2) {
		emis += vec3(0.06, 0.05, 0.04);
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emis;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	SPECULAR = 0.35;
	NORMAL = normalize(NORMAL - TANGENT * grad.x - BINORMAL * grad.y);
}
