// Castle Scaper Realistic: noise, hashes, masonry patterns and weathering helpers shared by the castle shader, the props
// shader and the sea. Everything is procedural (no textures): a pattern is a function of the face's own metre frame.

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float h31(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 h22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

// What each palette entry is made of: colour (sRGB), pattern (0 ashlar, 1 lime render, 2 brick, 3 rubble), block scale, roughness
const vec3 W_COL[12] = vec3[12](
	vec3(0.80, 0.72, 0.57), vec3(0.84, 0.78, 0.65), vec3(0.78, 0.60, 0.36), vec3(0.76, 0.58, 0.44),
	vec3(0.56, 0.31, 0.24), vec3(0.80, 0.58, 0.56), vec3(0.50, 0.46, 0.56), vec3(0.56, 0.64, 0.70),
	vec3(0.44, 0.54, 0.50), vec3(0.60, 0.66, 0.50), vec3(0.52, 0.53, 0.55), vec3(0.58, 0.30, 0.21));
const int W_PAT[12] = int[12](0, 1, 0, 1, 0, 1, 0, 1, 3, 1, 0, 2);

float vn2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float vn3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h31(i);
	float b = h31(i + vec3(1, 0, 0));
	float c = h31(i + vec3(0, 1, 0));
	float d = h31(i + vec3(1, 1, 0));
	float e = h31(i + vec3(0, 0, 1));
	float g = h31(i + vec3(1, 0, 1));
	float h = h31(i + vec3(0, 1, 1));
	float k = h31(i + vec3(1, 1, 1));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vn3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

float fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vn2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// slope of smoothstep(0, w, d) in d
float bevel_slope(float d, float w) {
	float t = clamp(d / w, 0.0, 1.0);
	return 6.0 * t * (1.0 - t) / w;
}

const float COURSE[4] = float[4](0.31, 0.46, 0.37, 0.53);

// Dressed stone: courses of varying height, blocks of varying length, running bond.
// dj = distance to the nearest joint (m), tone 0..1 per block, slope = bevel slope (u, v), bid = block id, bh = course height
void ashlar(vec2 uv, float sd, float scale, float len, out float dj, out float tone, out vec2 slope, out float bid) {
	vec2 p = uv * scale;
	float period = 1.67;
	float cyc = floor(p.y / period);
	float fy = p.y - cyc * period;
	float y0 = 0.0;
	float ch = COURSE[0];
	int ci = 0;
	for (int i = 0; i < 4; i++) {
		if (fy >= y0 && fy < y0 + COURSE[i]) {
			ci = i;
			ch = COURSE[i];
			break;
		}
		y0 += COURSE[i];
	}
	float course = cyc * 4.0 + float(ci);
	float ly = fy - y0;
	float dv = min(ly, ch - ly);
	float sv = ly < ch - ly ? 1.0 : -1.0;
	float off = h11(course * 1.37 + sd * 13.1) * 3.1;
	float L0 = len;
	float x = p.x + off;
	float k0 = floor(x / L0);
	float j0 = (h21(vec2(k0, course + sd)) - 0.5) * 0.75 * L0;
	float j1 = (h21(vec2(k0 + 1.0, course + sd)) - 0.5) * 0.75 * L0;
	float jm = (h21(vec2(k0 - 1.0, course + sd)) - 0.5) * 0.75 * L0;
	float b0 = k0 * L0 + j0;
	float b1 = (k0 + 1.0) * L0 + j1;
	float bm = (k0 - 1.0) * L0 + jm;
	float lo = b0;
	float hi = b1;
	float blk = k0;
	if (x < b0) {
		lo = bm;
		hi = b0;
		blk = k0 - 1.0;
	}
	float du = min(x - lo, hi - x);
	float su = (x - lo) < (hi - x) ? 1.0 : -1.0;
	bid = h21(vec2(blk, course) + sd);
	tone = bid;
	dj = min(du, dv) / scale;
	float w = 0.04;
	float hu = smoothstep(0.0, w, du);
	float hv = smoothstep(0.0, w, dv);
	slope = vec2(bevel_slope(du, w) * su * hv, bevel_slope(dv, w) * sv * hu);
}

// Brick in running bond: a course is 0.11 m, a brick 0.30 m; the mortar bed is thin.
void brick(vec2 uv, float sd, out float dj, out float tone, out vec2 slope, out float bid) {
	float bh = 0.115;
	float bl = 0.31;
	float row = floor(uv.y / bh);
	float ly = uv.y - row * bh;
	float x = uv.x + (mod(row, 2.0) * 0.5 + h11(row + sd) * 0.04) * bl;
	float col = floor(x / bl);
	float lx = x - col * bl;
	float du = min(lx, bl - lx);
	float dv = min(ly, bh - ly);
	float su = lx < bl - lx ? 1.0 : -1.0;
	float sv = ly < bh - ly ? 1.0 : -1.0;
	bid = h21(vec2(col, row) + sd);
	tone = bid;
	dj = min(du, dv);
	float w = 0.012;
	float hu = smoothstep(0.0, w, du);
	float hv = smoothstep(0.0, w, dv);
	slope = vec2(bevel_slope(du, w) * su * hv, bevel_slope(dv, w) * sv * hu);
}

// Rubble: Voronoi stones of about 0.4 m, each with its own tone and tilt. dj = distance to the joint, tone, slope, id
void rubble(vec2 p, float sd, out float dj, out float tone, out vec2 slope, out float bid) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 c1 = vec2(0.0);
	float id1 = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = h22(ip + g + sd) * 0.8 + 0.1;
			vec2 r = g + o - fp;
			r.y *= 1.5;   // stones lie wider than tall
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				c1 = r;
				id1 = h21(ip + g + sd * 3.0);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float edge = (sqrt(f2) - sqrt(f1)) * 0.5;
	dj = edge;
	tone = id1;
	bid = id1;
	float w = 0.14;
	float gs = bevel_slope(edge, w);
	vec2 dir = normalize(c1 + vec2(1e-4));
	slope = -dir * gs * 0.7;
	// a rounded top on each stone
	slope += -c1 * 0.25;
}

// Irregular paving: Voronoi slabs. dj = distance to the joint, tone = slab tone
void flags(vec2 p, float sd, out float dj, out float tone, out vec2 slope) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 c1 = vec2(0.0);
	float id1 = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = h22(ip + g + sd) * 0.8 + 0.1;
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				c1 = r;
				id1 = h21(ip + g + sd * 3.0);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float edge = (sqrt(f2) - sqrt(f1)) * 0.5;
	dj = edge;
	tone = id1;
	float w = 0.09;
	float gs = bevel_slope(edge, w);
	vec2 dir = normalize(c1 + vec2(1e-4));
	slope = -dir * gs * 0.6;
}

// A thin crack line field: 0 on a crack, 1 away from it (noise ridges)
float crack_field(vec2 p) {
	float n = vn2(p) + 0.5 * vn2(p * 2.1 + 7.0);
	return smoothstep(0.0, 0.05, abs(n - 0.72));
}
