// The sea floor under the water: pale sand with ripples, weed and darker rock patches, and the web of light the waves throw onto it
// (caustics) in the shallows. Seen only through cs_sea.gdshader, which tints it with the water.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float sea_y = 0.0;
uniform float clarity = 3.5;
varying vec3 v_pos;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float caustic(vec2 p, float t) {
	vec2 a = p * 0.9;
	float c = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		a += vec2(sin(a.y * 1.3 + t * (0.6 + fi * 0.2) + fi), cos(a.x * 1.1 - t * (0.5 + fi * 0.3) + fi * 2.0)) * 0.55;
		c += abs(sin(a.x * 1.7 + a.y * 0.9));
	}
	return pow(1.0 - clamp(c / 3.0, 0.0, 1.0), 3.0);
}

void fragment() {
	vec2 p = v_pos.xz;
	float depth = sea_y - v_pos.y;
	float rip = vn2(vec2(p.x * 1.2 + vn2(p * 0.3) * 4.0, p.y * 3.4));
	float patch_n = fbm2(p * 0.18 + 4.0);
	vec3 sand = mix(lin(vec3(0.74, 0.68, 0.52)), lin(vec3(0.62, 0.56, 0.42)), rip * 0.6 + 0.2);
	vec3 rock = lin(vec3(0.24, 0.22, 0.2)) * (0.7 + 0.6 * vn2(p * 2.0));
	vec3 weed = lin(vec3(0.12, 0.2, 0.08));
	float rockm = smoothstep(0.52, 0.62, patch_n) + smoothstep(0.35, 0.8, -v_pos.y + 0.6) * 0.0;
	float weedm = smoothstep(0.62, 0.7, fbm2(p * 0.4 - 7.0)) * 0.7;
	vec3 col = mix(sand, rock, clamp(rockm, 0.0, 1.0));
	col = mix(col, weed, weedm * (1.0 - rockm));
	float shallow = 1.0 - smoothstep(0.5, 7.0, depth);
	float c = caustic(p, TIME * 0.7);
	col *= 1.0 + c * 2.2 * shallow;
	col *= exp(-2.0 * max(depth, 0.0) / clarity);   // the light the water has not absorbed on its way down and back
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	NORMAL = normalize(NORMAL + vec3((rip - 0.5) * 0.0, 0.0, 0.0));
}
