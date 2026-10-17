// Castle Scaper Realistic's prop layer (CSProps), in the same real materials as cs_castle.gdshader: dressed stone frames and sills,
// weathered oak planks with grain, painted shutters, black iron, hemp rope, soil and leaves, glass, linen bunting, lantern flame.
// COLOR.r * 255 = paint zone (CSProps.P_*); INSTANCE_CUSTOM = (palette a, palette b as CSBuild.colour_seed, owner, 0); UV in metres.
// A prop springs out of its mount point just after its block pops up (pop_id = the block's grid point + 1, as for the castle);
// the props of a block taken away shrink away on a second set of instances (leave_t 0 -> 1).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float pop_id = -1.0;
uniform float pop_t = 1.0;
uniform float leave_t = -1.0;
uniform float wetness = 0.0;
uniform float night = 0.0;          // 0 day .. 1: windows and lanterns lit

varying flat vec4 v_inst;
varying vec3 v_wpos;
varying vec3 v_wnrm;

float spring(float t) {
	return t <= 0.0 ? 0.0 : pow(2.0, -9.0 * t) * sin((t * 9.0 - 0.75) * 2.0943951) + 1.0;
}

void vertex() {
	v_inst = INSTANCE_CUSTOM;
	float s = 1.0;
	if (leave_t >= 0.0) {
		s = 1.0 - smoothstep(0.0, 1.0, leave_t);
	} else if (pop_t < 1.0 && abs(INSTANCE_CUSTOM.z - pop_id) < 0.5) {
		s = spring(clamp((pop_t - 0.3) / 0.7, 0.0, 1.0));
	}
	VERTEX *= s;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// oak planks running along u: tone per plank, grain, a shrinkage groove between planks, silver weathering
vec3 planks(vec2 uv, float seed, float aged, out float groove, out float grain) {
	float pw = 0.17;
	float x = uv.x / pw;
	float px = floor(x);
	float lx = fract(x);
	float tone = h21(vec2(px, seed * 5.0));
	grain = vn2(vec2(uv.x * 50.0 + px * 7.0, uv.y * 3.0 + tone * 20.0));
	float ring = vn2(vec2(uv.x * 9.0 + px * 3.0, uv.y * 0.6 + tone * 9.0));
	vec3 c = lin(vec3(0.36, 0.28, 0.2)) * (0.65 + 0.7 * tone) * (0.8 + 0.3 * grain) * (0.9 + 0.2 * ring);
	groove = smoothstep(0.0, 0.08, lx) * smoothstep(1.0, 0.92, lx);
	c *= 0.5 + 0.5 * groove;
	return mix(c, lin(vec3(0.5, 0.47, 0.42)) * (0.8 + 0.4 * grain), aged);
}

void fragment() {
	// the mirrored camera (CSReflect) sits under the water: what is under the water is not part of the reflection
	if (INV_VIEW_MATRIX[3][1] < 0.0 && v_wpos.y < 0.0) {
		discard;
	}
	int zone = int(COLOR.r * 255.0 + 0.5);
	int ca = clamp(int(v_inst.x * 16.0), 0, 11);
	int cb = clamp(int(v_inst.y * 16.0), 0, 11);
	vec3 P = v_wpos;
	vec2 uv = UV;
	float n_mid = fbm3(P * 3.0);
	float n_fine = vn3(P * 20.0);
	float seed = v_inst.z * 0.37;
	vec3 base = lin(W_COL[ca]);
	float rough = 0.85;
	float metal = 0.0;
	float ao = 1.0;
	vec3 emis = vec3(0.0);
	float groove = 1.0;
	float grain = 0.5;
	float spec = 0.35;
	vec2 grad = vec2(0.0);
	if (zone == 0) {
		// the block's own stone or render
		base *= (0.9 + 0.2 * n_mid) * (0.94 + 0.12 * n_fine);
	} else if (zone == 1) {
		// painted wood: muted, flaking paint over bare oak
		vec3 paint = lin(mix(W_COL[cb], vec3(0.26, 0.38, 0.34), 0.55)) * 0.85;
		vec3 w = planks(uv, seed, 0.3, groove, grain);
		float flake = smoothstep(0.62, 0.8, n_mid + 0.15 * (1.0 - groove));
		base = mix(paint * (0.85 + 0.25 * grain), w, flake * 0.8);
		rough = 0.7;
		ao *= 0.6 + 0.4 * groove;
	} else if (zone == 2) {
		// dressed limestone frames and sills, pale and weathered
		base = lin(mix(W_COL[ca], vec3(0.9, 0.87, 0.8), 0.6)) * (0.88 + 0.2 * n_mid) * (0.95 + 0.1 * n_fine);
		rough = 0.9;
	} else if (zone == 3 || zone == 12) {
		base = planks(uv, seed, 0.6, groove, grain);
		rough = mix(0.78, 0.45, wetness);
		ao *= 0.6 + 0.4 * groove;
		if (zone == 12) {
			vec3 paint = lin(mix(W_COL[cb], vec3(0.26, 0.38, 0.34), 0.55)) * 0.85;
			base = mix(paint * (0.85 + 0.25 * grain), base, smoothstep(0.62, 0.8, n_mid));
			rough = 0.72;
		}
	} else if (zone == 4) {
		// beams and brackets: dark old oak
		base = lin(vec3(0.24, 0.16, 0.1)) * (0.7 + 0.5 * vn2(vec2(uv.x * 30.0, uv.y * 3.0))) * (0.8 + 0.4 * n_fine);
		rough = 0.8;
	} else if (zone == 5) {
		// hand-forged iron: nearly black, a little rust
		base = lin(vec3(0.07, 0.07, 0.075)) * (0.8 + 0.5 * n_fine);
		base = mix(base, lin(vec3(0.32, 0.15, 0.07)), smoothstep(0.65, 0.9, n_mid) * 0.5);
		metal = 0.75;
		rough = 0.55;
	} else if (zone == 6) {
		// a lantern: the glass lit from inside
		base = lin(vec3(1.0, 0.8, 0.5));
		emis = base * (1.2 + 2.2 * night) * (0.9 + 0.1 * sin(TIME * 6.0 + seed * 10.0));
	} else if (zone == 7) {
		base = lin(mix(vec3(0.16, 0.32, 0.1), vec3(0.3, 0.46, 0.16), n_fine)) * (0.8 + 0.4 * n_mid);
		rough = 0.75;
	} else if (zone == 8) {
		vec3 petal = h21(vec2(floor(P.x * 9.0), floor(P.z * 9.0))) > 0.5 ? vec3(0.8, 0.12, 0.12) : vec3(0.9, 0.78, 0.2);
		base = lin(mix(petal, W_COL[cb], 0.25));
		rough = 0.7;
	} else if (zone == 9) {
		// window glass: dark, glossy, with the sky in it; some panes lit warm from inside toward evening
		float lit = step(0.55, h11(seed * 7.0 + 3.0)) * night;
		base = lin(vec3(0.02, 0.03, 0.035));
		rough = 0.06;
		spec = 0.9;
		emis = lin(vec3(1.0, 0.7, 0.35)) * 1.6 * lit * (0.8 + 0.4 * n_mid);
		ao = 0.5;
	} else if (zone == 10) {
		base = lin(vec3(0.58, 0.48, 0.32)) * (0.7 + 0.6 * vn2(vec2(uv.x * 80.0, uv.y * 80.0)));
		rough = 1.0;
	} else if (zone == 11) {
		base = lin(vec3(0.2, 0.14, 0.09)) * (0.7 + 0.6 * n_fine);
		rough = 1.0;
	} else if (zone == 13) {
		// bunting: dyed linen with a weave
		vec3 c = lin(mix(W_COL[ca], vec3(0.55, 0.12, 0.1), 0.35)) * 0.9;
		float weave = 0.92 + 0.08 * sin(uv.x * 240.0) * sin(uv.y * 240.0);
		base = c * weave * (0.85 + 0.2 * vn2(uv * 18.0));
		rough = 0.95;
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emis;
	AO = ao;
	AO_LIGHT_AFFECT = 0.4;
}
