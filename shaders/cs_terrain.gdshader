// The landscape's ground (CSWorld): meadow, scree, rock, alpine tundra and snow, shingle and sand at the water. Everything is decided per pixel
// from the world position, the slope and the height, so a mountain built column by column reads as one mountain: green and wooded low down,
// grey bedded rock where it is steep, brown tundra above the trees, white where it is high and not too steep. Vertex colour: r = how much of
// the column's height is rock (cliffs and strata), g = forest floor (trees on the column), b = coast bank (1 beach, 0.5 cliff base).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/cs_common.gdshaderinc"

uniform float wetness = 0.0;
uniform float snow_line = 11.0;
uniform float tree_line = 8.5;
uniform float time_of_year = 0.0;       // 0 summer .. 1 autumn (a look's setting)
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
	float y = P.y;
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float fw = max(length(fwidth(P)), 1e-4);
	float lod = smoothstep(0.03, 0.25, fw);                  // pixel bigger than the detail: use the mean
	float big = fbm3(P * 0.07);
	float mid = fbm3(P * 0.6);
	float fine = mix(vn3(P * 9.0), 0.5, lod);
	// bedded rock: horizontal strata, tilted a little, with cracks
	float strata = sin(y * 2.7 + big * 7.0) * 0.5 + 0.5;
	float crack = smoothstep(0.0, 0.07, abs(fbm3(P * vec3(1.3, 0.8, 1.3) + 9.0) - 0.5));
	vec3 rock_a = lin(vec3(0.40, 0.39, 0.38));
	vec3 rock_b = lin(vec3(0.60, 0.58, 0.53));
	vec3 rock = mix(rock_a, rock_b, strata * 0.55 + mid * 0.45) * (0.78 + 0.35 * fine) * mix(0.6, 1.0, crack);
	float lich = smoothstep(0.7, 0.8, vn3(P * 3.0 + 4.0)) * (1.0 - slope);
	rock = mix(rock, lin(vec3(0.62, 0.55, 0.2)), lich * 0.35);
	// meadow: two greens in patches, flowers, a little straw in summer, red-brown in autumn
	vec3 g1 = lin(vec3(0.20, 0.36, 0.10));
	vec3 g2 = lin(vec3(0.33, 0.46, 0.14));
	vec3 meadow = mix(g1, g2, smoothstep(0.35, 0.7, big * 0.7 + mid * 0.5));
	meadow = mix(meadow, lin(vec3(0.55, 0.50, 0.24)), smoothstep(0.55, 0.85, fbm3(P * 0.11 + 7.0)) * 0.35);
	meadow = mix(meadow, lin(vec3(0.55, 0.33, 0.12)), time_of_year * smoothstep(0.3, 0.7, mid));
	float flower = step(0.985, h21(floor(P.xz * 14.0))) * (1.0 - lod);
	vec3 fcol = h21(floor(P.xz * 14.0) + 3.0) > 0.5 ? lin(vec3(0.95, 0.9, 0.5)) : lin(vec3(0.92, 0.92, 0.95));
	meadow = mix(meadow, fcol, flower * 0.8);
	meadow *= 0.8 + 0.3 * fine;
	// the forest floor: dark leaf mould under trees
	vec3 floor_c = lin(vec3(0.12, 0.16, 0.07)) * (0.8 + 0.4 * fine);
	meadow = mix(meadow, floor_c, clamp(v_col.g * 1.1, 0.0, 0.85));
	// tundra above the trees
	vec3 tundra = mix(lin(vec3(0.34, 0.34, 0.24)), lin(vec3(0.44, 0.43, 0.30)), mid) * (0.85 + 0.3 * fine);
	float above_trees = smoothstep(tree_line - 2.5, tree_line + 1.0, y + big * 3.0);
	vec3 soil = mix(meadow, tundra, above_trees);
	// rock where it is steep, where the column is rock, and on high ground
	float rocky = smoothstep(0.36, 0.6, slope + (big - 0.5) * 0.16) + v_col.r * 0.65 * smoothstep(0.35, 0.9, v_col.r + mid * 0.4);
	rocky = clamp(rocky + smoothstep(tree_line + 2.0, tree_line + 8.0, y) * 0.35, 0.0, 1.0);
	// scree between: loose pale stone
	vec3 scree = mix(rock * 1.15, soil, 0.35) * (0.85 + 0.3 * vn3(P * 5.0));
	vec3 base = mix(soil, scree, smoothstep(0.18, 0.34, slope) * (1.0 - rocky));
	base = mix(base, rock, rocky);
	// snow: high up, settling where it is gentle, broken at its edge by noise
	float snow_edge = y + (big - 0.5) * 3.5 + (mid - 0.5) * 1.2 - slope * 7.0;
	float snow = smoothstep(snow_line - 0.8, snow_line + 0.8, snow_edge);
	base = mix(base, lin(vec3(0.92, 0.94, 0.98)) * (0.92 + 0.1 * fine), snow);
	// the coast: sand and shingle at the water, wet and dark just above it
	float beach = smoothstep(0.5, 0.28, y + (mid - 0.5) * 0.16) * (1.0 - smoothstep(0.3, 0.6, slope));
	vec3 sand = mix(lin(vec3(0.78, 0.70, 0.52)), lin(vec3(0.62, 0.57, 0.46)), mid) * (0.85 + 0.25 * fine);
	base = mix(base, sand, beach * (1.0 - snow));
	float wet = smoothstep(0.55, 0.0, y) + wetness * 0.2;
	base *= mix(1.0, 0.55, clamp(wet, 0.0, 1.0));
	float algae = smoothstep(0.12, -0.5, y);
	base = mix(base, lin(vec3(0.12, 0.2, 0.07)), algae * 0.6);
	// relief
	vec3 gn = vec3(vn3(P * 3.5 + vec3(0.0, 1.0, 2.0)) - 0.5, 0.0, vn3(P * 3.5 + vec3(5.0, 3.0, 1.0)) - 0.5) * (0.25 + 0.5 * rocky) * (1.0 - lod);
	vec3 nw = normalize(n + gn);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = base;
	ROUGHNESS = mix(0.95, 0.35, clamp(wet, 0.0, 1.0) * 0.8) * mix(1.0, 0.7, snow);
	SPECULAR = 0.25 + 0.3 * snow;
	AO = 0.78 + 0.22 * smoothstep(-0.2, 0.6, y);
}
