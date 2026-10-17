// Castle Scaper Realistic's sky: an analytic clear atmosphere (Rayleigh blue overhead, Mie glow round a low sun, a warm
// horizon band) with one layer of clouds that are lit from the sun's side, thin and high or a heavy overcast. CSLook sets the
// uniforms per look (golden hour, overcast, bright noon). Below the horizon it continues as the sea's haze colour.
shader_type sky;
render_mode use_quarter_res_pass;

uniform vec3 sun_dir = vec3(0.45, 0.3, 0.7);
uniform vec3 sun_col : source_color = vec3(1.0, 0.82, 0.58);
uniform float sun_power = 4.0;
uniform vec3 zenith : source_color = vec3(0.11, 0.27, 0.6);
uniform vec3 horizon : source_color = vec3(0.74, 0.82, 0.92);
uniform vec3 glow_col : source_color = vec3(1.0, 0.6, 0.3);
uniform float glow_power = 0.5;
uniform vec3 ground_col : source_color = vec3(0.3, 0.5, 0.58);
uniform float cloud_cover = 0.5;
uniform float cloud_dark = 0.0;     // 0 white cumulus .. 1 slate overcast
uniform float cloud_height = 0.22;
uniform float haze = 0.6;
uniform float rays = 0.3;           // crepuscular rays round the sun
uniform float cirrus = 0.4;         // a thin high layer
uniform float stars = 0.0;          // 0 none .. 1 a dusk sky with its first stars

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return s;
}

float cloud_density(vec2 p) {
	float c = fbm(p + vec2(TIME * 0.003, 0.0));
	return smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, c);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float h = d.y;
	float sdot = max(dot(d, sd), 0.0);
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(1.0 - h, 0.0, 1.0), 2.4);
		col = mix(zenith, horizon, t);
		// Mie forward scattering round the sun, reddest low on the horizon
		float low = 1.0 - smoothstep(0.0, 0.5, sd.y);
		col += glow_col * (pow(sdot, 10.0) * 0.22 + pow(sdot, 60.0) * 0.5) * glow_power * mix(0.5, 1.0, low) * (1.0 - h * 0.6);
		col += sun_col * pow(sdot, 900.0) * sun_power;
		// clouds on a plane high above, brighter on the sun's side
		if (h > 0.01) {
			vec2 p = d.xz / (h + cloud_height) * 1.5;
			float c = cloud_density(p);
			vec2 toward = normalize(sd.xz + 1e-4) * 0.09;
			float c2 = cloud_density(p + toward);
			float lit = clamp(0.55 + (c - c2) * 3.0, 0.0, 1.0);
			lit = clamp(lit * (0.65 + 0.7 * fbm(p * 3.3 + 5.0)), 0.0, 1.0);   // billows inside the cloud
			vec3 bright = mix(vec3(1.0, 0.97, 0.92), sun_col * 1.3, low * 0.8);
			vec3 shadow = mix(vec3(0.55, 0.62, 0.74), vec3(0.28, 0.31, 0.36), cloud_dark);
			vec3 cc = mix(shadow, bright, lit * (1.0 - cloud_dark * 0.65));
			col = mix(col, cc, c * smoothstep(0.01, 0.12, h) * (0.9 - 0.1 * cloud_dark));
		}
		// stars: sparse points on the dome, brighter the higher and the further from the sun
		if (stars > 0.01 && h > 0.15) {
			vec3 sp = d * 120.0;
			vec3 cell = floor(sp);
			float hs = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
			vec3 f = fract(sp) - 0.5;
			float star = step(0.985, hs) * smoothstep(0.35, 0.0, length(f)) * (0.4 + 0.6 * fract(hs * 91.7));
			col += vec3(0.9, 0.93, 1.0) * star * stars * smoothstep(0.15, 0.6, h) * (1.0 - smoothstep(0.2, 0.7, sdot));
		}
		// a thin high layer of streaks, warm toward the sun
		if (h > 0.05 && cirrus > 0.01) {
			vec2 p2 = d.xz / (h + 0.6) * vec2(0.6, 2.4) + vec2(TIME * 0.002, 3.0);
			float c3 = smoothstep(0.52, 0.85, fbm(p2 * 1.3)) * cirrus;
			vec3 cc3 = mix(vec3(1.0), sun_col * 1.2, pow(sdot, 3.0));
			col = mix(col, cc3, c3 * smoothstep(0.05, 0.3, h) * 0.55);
		}
		// light shafts fanning out of the sun, broken by the clouds
		if (rays > 0.001 && sdot > 0.05) {
			vec3 up_ref = abs(sd.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 sr = normalize(cross(up_ref, sd));
			vec3 su = cross(sd, sr);
			float ang = atan(dot(d, su), dot(d, sr));
			float streak = vnoise(vec2(ang * 9.0, 3.0 + TIME * 0.01)) * 0.6 + vnoise(vec2(ang * 23.0, 9.0)) * 0.4;
			col += glow_col * pow(sdot, 4.0) * smoothstep(0.35, 0.8, streak) * rays * (0.4 + 0.6 * (1.0 - h));
		}
		// the haze band where the sea meets the sky
		col = mix(col, horizon, (1.0 - smoothstep(0.0, 0.08, h)) * haze);
	} else {
		col = mix(horizon, ground_col, smoothstep(0.0, 0.25, -h));
	}
	COLOR = col;
}
