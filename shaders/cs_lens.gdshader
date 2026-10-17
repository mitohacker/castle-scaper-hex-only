shader_type canvas_item;
render_mode unshaded;

// The lens (CSLook): one full-screen pass over the finished 3D picture, under the interface: a soft corner darkening, a trace of
// film grain in the mid tones, a hint of colour fringing at the frame's edge, local contrast ("clarity") and a little sharpening
// (the picture may have been upscaled). About 0.2 ms at 1080p. With every strength at 0 CSLook does not draw it at all.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette : hint_range(0.0, 1.0) = 0.2;
uniform float grain : hint_range(0.0, 0.1) = 0.012;
uniform float aberration : hint_range(0.0, 0.01) = 0.0008;
uniform float sharpen : hint_range(0.0, 1.0) = 0.25;
uniform float clarity : hint_range(0.0, 2.0) = 0.3;
uniform vec3 tint : source_color = vec3(1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = c * aberration * (0.2 + 4.0 * r2);
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	if (sharpen > 0.001) {
		vec3 n = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
			+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb + texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
		vec3 d = col - n * 0.25;
		float edge = clamp(dot(abs(d), vec3(0.3333)) * 6.0, 0.0, 1.0);
		col += d * sharpen * (1.0 - 0.6 * edge);
	}
	if (clarity > 0.001) {
		vec2 o = px * 3.5;
		vec3 m = texture(screen_tex, uv + vec2(o.x, o.y)).rgb + texture(screen_tex, uv + vec2(-o.x, o.y)).rgb
			+ texture(screen_tex, uv + vec2(o.x, -o.y)).rgb + texture(screen_tex, uv + vec2(-o.x, -o.y)).rgb;
		float dl = dot(col - m * 0.25, vec3(0.2126, 0.7152, 0.0722));
		col += vec3(dl * clarity);
	}
	float v = smoothstep(0.1, 0.62, r2 * 2.0);
	col *= 1.0 - vignette * v;
	col *= mix(vec3(1.0), tint, v * 0.5);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float g = (hash12(floor(FRAGCOORD.xy) + fract(TIME * 7.0) * 311.0) - 0.5) * grain * (1.0 - abs(l * 2.0 - 1.0) * 0.8);
	COLOR = vec4(clamp(col + g, 0.0, 1.0), 1.0);
}
