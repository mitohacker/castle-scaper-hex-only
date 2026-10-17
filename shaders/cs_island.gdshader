// A far island: bare rock and shingle at the water, forest in the middle in two greens, grey crags and a little snow-white lichen on the
// ridge; shaded by the engine's light and hazed by the fog (they stand 0.6 - 1.4 km away). World-space noise only.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (INV_VIEW_MATRIX[3][1] < 0.0 && v_pos.y < 0.0) {
		discard;
	}
	vec3 P = v_pos;
	vec3 n = normalize(v_nrm);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float h = P.y;
	float nz = fbm3(P * 0.05);
	float fine = vn3(P * 0.9);
	vec3 rock = mix(lin(vec3(0.36, 0.34, 0.31)), lin(vec3(0.55, 0.5, 0.43)), nz) * (0.8 + 0.4 * fine);
	vec3 forest = mix(lin(vec3(0.07, 0.16, 0.06)), lin(vec3(0.16, 0.26, 0.09)), vn3(P * 0.25 + 3.0));
	forest *= 0.7 + 0.6 * vn3(P * 1.7);
	float tree = smoothstep(2.5, 9.0, h + nz * 6.0) * (1.0 - smoothstep(0.32, 0.6, slope + nz * 0.15)) * (1.0 - smoothstep(60.0, 110.0, h));
	vec3 c = mix(rock, forest, tree);
	vec3 sand = lin(vec3(0.7, 0.64, 0.5));
	c = mix(c, sand, smoothstep(3.0, 0.3, h) * (1.0 - smoothstep(0.1, 0.4, slope)));
	c = mix(c, lin(vec3(0.7, 0.7, 0.66)), smoothstep(70.0, 110.0, h + nz * 20.0) * 0.4);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.8, tree);
	SPECULAR = 0.2;
}
