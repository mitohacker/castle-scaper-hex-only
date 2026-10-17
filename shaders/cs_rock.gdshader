// The rocky skirt the castle stands on (CSRocks): weathered grey-brown stone shaped by 3D noise, bedded in strata, dark and wet
// toward the sea, green with algae just above the water, crusted with barnacles, bleached by salt higher up, orange lichen on top.
// All from the world position, so the pieces blend into one outcrop.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float wetness = 0.0;
varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float height(vec3 p) {
	// bedded strata cut by cracks, over a lumpy base
	float lump = fbm3(p * 0.9) * 0.7 + fbm3(p * 3.3) * 0.3;
	float strata = abs(sin(p.y * 7.0 + fbm3(p * 0.5) * 6.0)) * 0.15;
	float crack = smoothstep(0.0, 0.06, abs(fbm3(p * 1.7 + 11.0) - 0.5));
	return lump + strata * 0.6 + (1.0 - crack) * -0.25;
}

void fragment() {
	// the mirrored camera (CSReflect) sits under the water: what is under the water is not part of the reflection
	if (INV_VIEW_MATRIX[3][1] < 0.0 && v_pos.y < 0.0) {
		discard;
	}
	vec3 P = v_pos;
	vec3 n = normalize(v_nrm);
	float h = height(P);
	float e = 0.06;
	vec3 g = vec3(height(P + vec3(e, 0, 0)) - h, height(P + vec3(0, e, 0)) - h, height(P + vec3(0, 0, e)) - h) / e;
	g -= n * dot(g, n);
	vec3 nw = normalize(n - g * 1.7);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	float tone = fbm3(P * 0.6 + 3.0);
	vec3 base = mix(lin(vec3(0.40, 0.36, 0.30)), lin(vec3(0.70, 0.64, 0.54)), smoothstep(0.3, 0.8, tone));
	base *= 0.75 + 0.5 * vn3(P * 6.0);
	base = mix(base, base * vec3(1.15, 1.0, 0.8), smoothstep(0.55, 0.9, fbm3(P * 0.3 + 6.0)) * 0.7);
	float cav = smoothstep(0.55, 0.3, h);
	base *= 0.78 + 0.22 * (1.0 - cav);
	// lichen on the sunward upper surfaces
	float lich = smoothstep(0.7, 0.78, vn3(P * 3.2 + 2.0) * (0.4 + 0.8 * fbm3(P * 0.4))) * smoothstep(0.1, 0.8, nw.y) * smoothstep(0.1, 1.2, P.y);
	base = mix(base, lin(vec3(0.66, 0.54, 0.16)), lich * 0.5);
	// salt-bleached splash zone, then dark wet rock, algae and barnacles
	base = mix(base, base * 1.2 + 0.03, smoothstep(0.4, 1.4, P.y) * 0.4);
	float wet = smoothstep(0.45, -0.15, P.y);
	base *= mix(1.0, 0.5, wet);
	float algae = smoothstep(0.7, 0.25, P.y) * smoothstep(0.3, 0.7, vn3(P * vec3(2.5, 5.0, 2.5) + 1.0)) * smoothstep(-1.0, 0.0, P.y);
	base = mix(base, lin(vec3(0.1, 0.19, 0.05)), algae * 0.8);
	float barn = smoothstep(0.74, 0.8, h21(floor(P.xz * 14.0) + floor(P.y * 14.0) * 31.0)) * smoothstep(0.5, 0.0, P.y) * smoothstep(-0.5, 0.0, P.y);
	base = mix(base, lin(vec3(0.72, 0.72, 0.66)), barn * 0.6);
	ALBEDO = base;
	ROUGHNESS = mix(0.92, 0.3, clamp(wet + wetness * 0.6, 0.0, 1.0) * 0.85);
	SPECULAR = 0.35;
	AO = 0.7 + 0.3 * smoothstep(0.25, 0.65, h);
}
