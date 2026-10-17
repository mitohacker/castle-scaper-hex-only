// Roads, bridges and jetties (CSRoads). Ground ribbons: COLOR.r = cobble weight, COLOR.b = gravel weight (the rest is packed dirt), COLOR.g = 0..1
// across the road (the worn edge is cut by noise), COLOR.a = 0. Decks: COLOR.a = 0.4 plank top, 0.5 stone, 0.7 timber side; UV = (across, along) in metres.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float wetness = 0.0;
varying vec3 v_pos;
varying vec3 v_nrm;
varying vec4 v_col;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

void fragment() {
	if (INV_VIEW_MATRIX[3][1] < 0.0 && v_pos.y < 0.0) {
		discard;
	}
	vec3 P = v_pos;
	vec3 n = normalize(v_nrm);
	float a = v_col.a;
	float fw = max(length(fwidth(P)), 1e-4);
	float lod = smoothstep(0.02, 0.12, fw);
	vec3 col;
	float rough = 0.9;
	float ao = 1.0;
	vec2 grad = vec2(0.0);
	if (a < 0.1) {
		// ground road
		float u = v_col.g * 2.0 - 1.0;
		float edge_n = vn2(P.xz * 3.0) * 0.6 + vn2(P.xz * 9.0) * 0.4;
		if (abs(u) > 0.97 - 0.2 * edge_n) {
			discard;
		}
		float cobble_w = clamp(v_col.r, 0.0, 1.0);
		float gravel_w = clamp(v_col.b, 0.0, 1.0);
		// setts: rows of stones across the road, staggered, each rounded and its own grey
		vec2 q = P.xz * 4.2;
		float row = floor(q.y);
		float qx = q.x + 0.5 * mod(row, 2.0);
		vec2 cell = vec2(floor(qx), row);
		vec2 f = vec2(fract(qx), fract(q.y)) - 0.5;
		float stn = h21(cell);
		float dj = 0.5 - max(abs(f.x), abs(f.y));
		vec3 sett = mix(lin(vec3(0.42, 0.40, 0.38)), lin(vec3(0.62, 0.58, 0.52)), stn) * (0.85 + 0.25 * vn3(P * 12.0));
		float joint = smoothstep(0.04, 0.12, dj);
		vec3 cob = mix(lin(vec3(0.2, 0.19, 0.17)), sett, mix(1.0, joint, 1.0 - lod));
		grad += f * (1.0 - lod) * 0.5 * (stn - 0.5);
		// gravel: pale small stones in a sandy bed
		float peb = vn3(P * 26.0);
		vec3 grav = mix(lin(vec3(0.55, 0.50, 0.42)), lin(vec3(0.74, 0.70, 0.62)), smoothstep(0.35, 0.8, peb * 0.6 + vn3(P * 7.0) * 0.4));
		// packed earth with two wheel ruts and grass creeping in at the edges
		vec3 dirt = mix(lin(vec3(0.34, 0.26, 0.17)), lin(vec3(0.48, 0.38, 0.25)), vn3(P * 5.0));
		float rut = smoothstep(0.12, 0.0, abs(abs(u) - 0.42));
		dirt *= 1.0 - 0.28 * rut;
		float verge = smoothstep(0.5, 0.95, abs(u) + (edge_n - 0.5) * 0.4);
		dirt = mix(dirt, lin(vec3(0.24, 0.34, 0.12)), verge * 0.7);
		col = mix(mix(dirt, grav, gravel_w), cob, cobble_w);
		col = mix(col, lin(vec3(0.24, 0.34, 0.12)), smoothstep(0.82, 1.0, abs(u)) * (1.0 - cobble_w) * 0.6);
		// steps where it climbs: a riser line every 0.28 m of height
		float steep = 1.0 - clamp(n.y, 0.0, 1.0);
		if (steep > 0.1) {
			float st = fract(P.y / 0.28);
			float riser = smoothstep(0.0, 0.12, st) * (1.0 - smoothstep(0.88, 1.0, st));
			col *= mix(1.0, 0.55 + 0.45 * riser, smoothstep(0.1, 0.25, steep));
		}
		rough = mix(0.95, 0.8, cobble_w);
		ao = 0.9;
	} else if (a < 0.45) {
		// timber deck: planks across the path
		float along = UV.y * 3.6;
		float pr = floor(along);
		float pf = fract(along);
		float tone = h21(vec2(pr, 3.0));
		float grain = vn2(vec2(UV.x * 30.0 + tone * 9.0, UV.y * 3.0));
		col = mix(lin(vec3(0.36, 0.26, 0.17)), lin(vec3(0.5, 0.42, 0.3)), tone * 0.7 + grain * 0.3) * (0.8 + 0.3 * grain);
		col *= 0.55 + 0.45 * smoothstep(0.0, 0.08, pf) * smoothstep(1.0, 0.92, pf);
		col = mix(col, lin(vec3(0.5, 0.47, 0.42)), 0.2);
		rough = 0.8;
	} else if (a < 0.6) {
		// stone bridge: ashlar on its faces, flags on the roadway
		float dj;
		float tone;
		vec2 slope;
		float bid;
		ashlar(vec2(UV.y, n.y > 0.5 ? UV.x : P.y), 3.0, 1.1, 1.0, dj, tone, slope, bid);
		float seam = (1.0 - smoothstep(0.01, 0.03 + fw, dj)) * (1.0 - lod);
		col = mix(lin(vec3(0.60, 0.56, 0.50)), lin(vec3(0.74, 0.70, 0.62)), tone) * (0.85 + 0.25 * vn3(P * 9.0));
		col = mix(col, lin(vec3(0.3, 0.28, 0.25)), seam * 0.8);
		float moss = smoothstep(0.7, 1.4, 1.5 - P.y) * smoothstep(0.5, 0.8, vn3(P * 2.0));
		col = mix(col, lin(vec3(0.17, 0.27, 0.09)), moss * 0.5);
		rough = 0.9;
	} else {
		// timber side
		float grain = vn2(vec2(UV.y * 30.0, P.y * 3.0));
		col = lin(vec3(0.24, 0.17, 0.12)) * (0.7 + 0.5 * grain);
		rough = 0.85;
	}
	float wet = smoothstep(1.0, 0.1, P.y);
	col *= mix(1.0, 0.65, clamp(wet + wetness * 0.4, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	AO = ao;
	NORMAL = normalize(NORMAL + vec3(grad.x, 0.0, grad.y) * 0.5);
}
