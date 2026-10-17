// Trees and rocks of the landscape (CSScatter), instanced. COLOR.r * 255 = zone: 0 bark, 1 oak leaves, 2 pine needles, 3 willow, 4 blossom,
// 5 rock, 6 dressed stone; COLOR.g = a tone per part, COLOR.a = how high on the mesh (the wind bends the top more). INSTANCE_CUSTOM: x = a
// random tone per tree, y = snow on it (pines high up), z = how many levels the column's trees stand in (a forest is a little darker).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float autumn = 0.0;
uniform float wetness = 0.0;
uniform float night = 0.0;
varying flat vec4 v_inst;
varying vec3 v_wpos;
varying vec3 v_wnrm;
varying vec4 v_col;

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	v_col = COLOR;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float zone = COLOR.r * 255.0;
	float w = COLOR.a * COLOR.a;
	float lea = (zone > 0.5 && zone < 4.5) ? 1.0 : 0.0;
	vec3 sway = vec3(sin(TIME * 1.2 + wp.x * 0.35 + wp.z * 0.2), 0.0, cos(TIME * 0.95 + wp.z * 0.33)) * 0.07 * w;
	sway += lea * vec3(sin(TIME * 3.1 + wp.y * 2.0 + wp.x), 0.0, cos(TIME * 2.7 + wp.y * 1.7 + wp.z)) * 0.025;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * sway);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (INV_VIEW_MATRIX[3][1] < 0.0 && v_wpos.y < 0.0) {
		discard;
	}
	int zone = int(v_col.r * 255.0 + 0.5);
	vec3 P = v_wpos;
	vec3 n = normalize(v_wnrm);
	float tone = v_inst.x;
	float tn = v_col.g;
	float fine = vn3(P * 6.0);
	float coarse = vn3(P * 1.3);
	vec3 col = vec3(0.4);
	float rough = 0.85;
	float sss = 0.0;
	float metal_amt = 0.0;
	vec3 emis = vec3(0.0);
	if (zone == 0) {
		col = lin(vec3(0.24, 0.17, 0.12)) * (0.7 + 0.5 * vn3(vec3(P.x * 18.0, P.y * 2.0, P.z * 18.0)));
		rough = 0.95;
	} else if (zone == 1) {
		vec3 a = lin(vec3(0.17, 0.33, 0.08));
		vec3 b = lin(vec3(0.38, 0.54, 0.16));
		col = mix(a, b, clamp(tn * 0.6 + tone * 0.35 + (fine - 0.5) * 0.5 + (n.y - 0.2) * 0.35, 0.0, 1.0));
		col = mix(col, lin(vec3(0.62, 0.34, 0.1)), autumn * smoothstep(0.2, 0.8, tone + coarse * 0.4));
		sss = 0.35;
	} else if (zone == 2) {
		vec3 a = lin(vec3(0.08, 0.20, 0.12));
		vec3 b = lin(vec3(0.18, 0.34, 0.20));
		col = mix(a, b, clamp(tn + (fine - 0.5) * 0.7 + n.y * 0.3, 0.0, 1.0));
		float sn = v_inst.y * smoothstep(-0.2, 0.5, n.y + (fine - 0.5) * 0.5);
		col = mix(col, lin(vec3(0.93, 0.95, 0.98)), clamp(sn, 0.0, 1.0));
		sss = 0.15;
	} else if (zone == 3) {
		col = mix(lin(vec3(0.34, 0.45, 0.14)), lin(vec3(0.55, 0.6, 0.22)), clamp(tn + (fine - 0.5) * 0.5, 0.0, 1.0));
		col = mix(col, lin(vec3(0.7, 0.5, 0.15)), autumn * 0.7);
		sss = 0.4;
	} else if (zone == 4) {
		col = mix(lin(vec3(0.96, 0.8, 0.84)), lin(vec3(1.0, 0.95, 0.95)), tn);
		sss = 0.3;
	} else if (zone == 5) {
		float strata = sin(P.y * 7.0 + coarse * 4.0) * 0.5 + 0.5;
		col = mix(lin(vec3(0.40, 0.39, 0.38)), lin(vec3(0.62, 0.60, 0.55)), clamp(tn * 0.6 + strata * 0.3 + fine * 0.3, 0.0, 1.0)) * (0.8 + 0.3 * tone);
		float moss = smoothstep(0.55, 0.8, vn3(P * 2.0 + 3.0)) * smoothstep(0.3, 0.9, n.y);
		col = mix(col, lin(vec3(0.17, 0.27, 0.09)), moss * 0.7);
		rough = 0.92;
	} else if (zone == 7) {
		col = lin(vec3(0.06, 0.06, 0.065)) * (0.8 + 0.5 * fine);
		rough = 0.5;
		metal_amt = 0.7;
	} else if (zone == 8) {
		col = lin(vec3(1.0, 0.78, 0.45));
		emis = col * (1.4 + 2.4 * night) * (0.9 + 0.1 * sin(TIME * 7.0 + v_inst.x * 20.0));
	} else {
		col = mix(lin(vec3(0.66, 0.6, 0.5)), lin(vec3(0.74, 0.69, 0.58)), tn) * (0.9 + 0.15 * fine);
		rough = 0.88;
	}
	// the foot of anything standing in the grass is darker, and anything under the water is
	float low = smoothstep(1.4, 0.2, P.y);
	col *= mix(1.0, 0.7, clamp(low, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	METALLIC = metal_amt;
	EMISSION = emis;
	BACKLIGHT = col * sss;
	AO = 0.55 + 0.45 * smoothstep(0.0, 1.0, v_col.a * 1.6);
}
