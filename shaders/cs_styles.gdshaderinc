// Castle Scaper Realistic: the materials of the building styles (house, apartment, Chinese, Japanese, fantasy, village), all procedural.
// Zones (CSStyle): wall 20 + style, roof 30 + style, trim 40 + style (fascia, soffit, door leaves, beams), paving 50 + style, gable 60 + style
// (the triangle of wall under a gable: the wall's material with an attic window). A palette index is style * 16 + colour; the colour is
// COLOR.g * 16. Walls are drawn in bays: CSFacades gives every wall triangle UV2 = (metres from the facade's left end, +-facade length; negative
// when the facade has the front door, which stands in the middle). Windows, frames, pillars, shutters, balconies are painted in those bays.

uniform vec4 style_wall[112];     // rgb = colour, a = pattern / 8
uniform vec4 style_roof[112];     // rgb = colour, a = roof cover / 8
uniform vec4 style_trim[112];     // rgb = colour

struct Surf {
	vec3 albedo;
	float rough;
	float metal;
	vec3 emis;
	float ao;
	vec2 grad;
	float spec;
};

vec3 pal_wall(int st, int ci) { return lin(style_wall[st * 16 + ci].rgb); }
int pal_pat(int st, int ci) { return int(style_wall[st * 16 + ci].a * 8.0 + 0.5); }
vec3 pal_roof(int st, int ci) { return lin(style_roof[st * 16 + ci].rgb); }
int pal_cover(int st, int ci) { return int(style_roof[st * 16 + ci].a * 8.0 + 0.5); }
vec3 pal_trim(int st, int ci) { return lin(style_trim[st * 16 + ci].rgb); }

float sdbox(vec2 p, vec2 hs) {
	vec2 d = abs(p) - hs;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float cover(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}

// the facade cut into bays
struct Bay {
	float bx;        // metres from the bay's middle, along the wall
	float bi;        // bay number
	float nb;        // bays on the facade
	float len;       // facade length (m)
	bool door;       // the facade has the front door, in the middle
	float end_d;     // metres to the nearer end of the facade
	float mid;       // number of the middle bay (door facades)
};

Bay make_bay(vec2 uv2, float bay_w, float min_bw) {
	Bay r;
	float len = abs(uv2.y);
	r.len = len;
	r.door = uv2.y < 0.0;
	float n = max(1.0, floor(len / bay_w + 0.5));
	if (r.door) {
		n = max(1.0, 2.0 * floor(len / (2.0 * bay_w) + 0.5) + 1.0);
	}
	for (int i = 0; i < 4; i++) {
		if (n > 1.0 && len / n < min_bw) {
			n -= (r.door ? 2.0 : 1.0);
		}
	}
	n = max(n, 1.0);
	float bw = len / n;
	r.nb = n;
	r.bi = clamp(floor(uv2.x / max(bw, 0.01)), 0.0, n - 1.0);
	r.bx = uv2.x - (r.bi + 0.5) * bw;
	r.end_d = min(uv2.x, len - uv2.x);
	r.mid = (n - 1.0) * 0.5;
	return r;
}

// an opening: shape 0 rectangle, 1 round-arched, 2 oval, 3 pointed arch
float opening_sd(vec2 q, vec2 hs, int shape) {
	if (shape == 1) {
		float r = hs.x;
		float d_rect = sdbox(q - vec2(0.0, -r * 0.5), vec2(hs.x, hs.y - r * 0.5));
		float d_circ = length(q - vec2(0.0, hs.y - r)) - r;
		return min(d_rect, d_circ);
	}
	if (shape == 2) {
		float m = min(hs.x, hs.y);
		return length(q / hs * m) - m;
	}
	if (shape == 3) {
		float r = hs.x * 1.6;
		float d_rect = sdbox(q - vec2(0.0, -hs.y * 0.25), vec2(hs.x, hs.y * 0.75));
		vec2 a = vec2(q.x - (hs.x - r), q.y - (hs.y - r * 1.2));
		vec2 b = vec2(q.x + (hs.x - r), q.y - (hs.y - r * 1.2));
		float d_arch = max(length(a) - r, length(b) - r);
		d_arch = max(d_arch, -(q.y - (hs.y - r * 1.2)) * 0.0 - 0.0 + (q.y - hs.y));
		return min(d_rect, d_arch);
	}
	return sdbox(q, hs);
}

// glass: dark, reflective, lit warm from inside at night; bars = 0 none, 1 cross, 2 grid, 3 lattice (diagonal)
void window_glass(vec2 q, vec2 hs, float d, float aa, vec3 frame_c, float lit, float seed, int bars, vec3 tint, float night, inout Surf s) {
	float inside = cover(d + 0.0, aa);
	float rev = smoothstep(0.0, 0.16, -d);
	vec3 gl = mix(vec3(0.015, 0.02, 0.028), tint * 0.5, 0.2 + 0.3 * smoothstep(-hs.y, hs.y, q.y));
	vec3 col = gl;
	float bar = 0.0;
	if (bars == 1) {
		bar = max(1.0 - smoothstep(0.012, 0.012 + aa, abs(q.x)), 1.0 - smoothstep(0.012, 0.012 + aa, abs(q.y - hs.y * 0.2)));
	} else if (bars == 2) {
		float gx = abs(fract(q.x / (hs.x * 0.66) + 0.5) - 0.5) * (hs.x * 0.66);
		float gy = abs(fract(q.y / (hs.y * 0.5) + 0.5) - 0.5) * (hs.y * 0.5);
		bar = max(1.0 - smoothstep(0.012, 0.012 + aa, gx), 1.0 - smoothstep(0.012, 0.012 + aa, gy));
	} else if (bars == 3) {
		float a1 = abs(fract((q.x + q.y) / 0.18 + 0.5) - 0.5) * 0.18;
		float a2 = abs(fract((q.x - q.y) / 0.18 + 0.5) - 0.5) * 0.18;
		bar = max(1.0 - smoothstep(0.014, 0.014 + aa, a1), 1.0 - smoothstep(0.014, 0.014 + aa, a2));
	}
	col = mix(col, frame_c, bar * 0.95);
	// warm light behind some panes at night (not behind the bars)
	vec3 glow = lin(vec3(1.0, 0.72, 0.38)) * (0.9 + 0.5 * vn2(q * 6.0 + seed * 9.0));
	vec3 e = glow * lit * night * 1.8 * (1.0 - bar);
	col = mix(s.albedo, col, inside);
	s.albedo = col;
	s.emis = mix(s.emis, e, inside);
	s.rough = mix(s.rough, 0.05, inside * (1.0 - bar));
	s.spec = mix(s.spec, 0.9, inside * (1.0 - bar));
	s.ao *= mix(1.0, 0.55 + 0.45 * rev, inside);
}

// stone / painted-wood frame ring round an opening (and a sill under it), in the trim colour
void window_frame(vec2 q, vec2 hs, float d, float aa, float fw, vec3 frame_c, float sill_w, inout Surf s) {
	float ring = smoothstep(-aa, aa, d) * (1.0 - smoothstep(fw - aa, fw + aa, d));
	s.albedo = mix(s.albedo, frame_c, ring);
	s.rough = mix(s.rough, 0.6, ring);
	s.ao *= 1.0 - 0.25 * ring * smoothstep(0.0, fw, d);
	s.grad += vec2(0.0, -0.35) * ring * step(0.0, q.y) * 0.5 + vec2(0.0, 0.35) * ring * step(q.y, 0.0) * 0.5;
	if (sill_w > 0.0) {
		float ds = sdbox(q - vec2(0.0, -hs.y - fw - 0.04), vec2(hs.x + fw + sill_w, 0.045));
		float sl = cover(ds, aa);
		s.albedo = mix(s.albedo, frame_c * 1.06, sl);
		s.grad += vec2(0.0, 0.4) * sl;
		s.ao *= 1.0 - 0.2 * cover(ds - 0.05, 0.05) * (1.0 - sl);
	}
}

// slatted shutters either side of an opening
void window_shutters(vec2 q, vec2 hs, float fw, float aa, vec3 col, inout Surf s) {
	float sw = hs.x * 0.52;
	float cx = hs.x + fw + 0.015 + sw;
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? -1.0 : 1.0;
		float d = sdbox(q - vec2(side * cx, 0.0), vec2(sw, hs.y + fw));
		float m = cover(d, aa);
		float louvre = 0.5 + 0.5 * sin(q.y * 38.0);
		vec3 c = col * (0.8 + 0.25 * louvre);
		s.albedo = mix(s.albedo, c, m);
		s.rough = mix(s.rough, 0.75, m);
		s.grad.y += (louvre - 0.5) * 0.35 * m;
		s.ao *= 1.0 - 0.3 * m * (1.0 - louvre) * 0.5;
	}
}

// weathering shared by the plastered and brick walls: stains, rain streaks, damp and moss near the ground, the sea line
vec3 sty_weather(vec3 b, vec3 P, float up, float d_top, float lod, float n_big, float n_mid, float uvx, float moss_k, float grime_k, float wet_k, float sd, inout float rough) {
	b *= 0.9 + 0.2 * smoothstep(0.25, 0.75, n_big);
	float streak = vn2(vec2(uvx * 2.4 + sd * 9.0, P.y * 0.3));
	float streak2 = vn2(vec2(uvx * 9.0 + sd * 5.0, P.y * 0.9));
	float below = smoothstep(2.6, 0.0, d_top);
	float gr = smoothstep(0.45, 0.95, n_big) * 0.35 + smoothstep(0.5, 0.92, streak) * (0.3 + 0.4 * streak2) * below + smoothstep(1.6, 0.0, P.y - 0.6) * 0.3;
	gr = clamp(gr * grime_k, 0.0, 1.0);
	b *= 1.0 - 0.38 * gr;
	float damp = smoothstep(3.5, 0.2, P.y) * 0.8 + wet_k * 0.3;
	float mo = smoothstep(0.55, 0.8, fbm3(P * 1.05 + vec3(sd, 0.0, 4.0)) + damp * 0.25 - 0.16) * moss_k;
	b = mix(b, lin(vec3(0.2, 0.3, 0.1)), mo * 0.5);
	float sea = smoothstep(1.7, -0.35, P.y);
	b = mix(b, b * 1.1 + 0.02, smoothstep(2.4, 1.0, P.y) * smoothstep(0.1, 1.0, P.y) * 0.4);
	float wet_band = smoothstep(1.0, -0.1, P.y);
	b *= mix(1.0, 0.55, wet_band);
	float algae = smoothstep(0.55, 0.2, P.y) * smoothstep(0.35, 0.65, vn3(P * vec3(3.0, 6.0, 3.0) + 1.0));
	b = mix(b, lin(vec3(0.12, 0.2, 0.06)), algae * 0.7);
	rough = mix(rough, 0.35, clamp(wet_band + wet_k * 0.8, 0.0, 1.0) * 0.7);
	return b * (1.0 + 0.0 * sea);
}

// the body of a wall: pattern 0 smooth, 1 brick, 2 boards, 3 stone (the meaning shifts a little per style, see wall_base)
vec3 wall_base(int st, int pat, vec3 col, vec3 P, vec2 uv, float fw, float lod, float sd, inout float rough, inout vec2 grad) {
	vec3 b = col;
	float dj;
	float tone;
	vec2 slope;
	float bid;
	float pat_fade = 1.0 - lod;
	float grain = vn3(P * 26.0 + sd);
	if ((st == 1 || st == 2 || st == 3 || st == 5 || st == 6) && pat == 1 && st != 3) {
		// brick
		brick(uv, sd, dj, tone, slope, bid);
		float seam = (1.0 - smoothstep(0.003, 0.006 + fw * 0.8, dj)) * pat_fade * 0.85;
		b = col * (0.78 + 0.4 * tone) * (0.95 + 0.1 * grain);
		b = mix(b, lin(vec3(0.66, 0.62, 0.55)), seam);
		grad += slope * 0.02 * pat_fade;
		rough = 0.92;
		return b;
	}
	if (st == 3 && pat == 2) {
		// grey brick, small and even
		brick(uv * vec2(1.25, 1.25), sd, dj, tone, slope, bid);
		float seam = (1.0 - smoothstep(0.003, 0.006 + fw * 0.8, dj / 1.25)) * pat_fade * 0.8;
		b = col * (0.8 + 0.35 * tone) * (0.95 + 0.1 * grain);
		b = mix(b, lin(vec3(0.62, 0.6, 0.56)), seam);
		grad += slope * 0.015 * pat_fade;
		rough = 0.9;
		return b;
	}
	if (pat == 2 && (st == 1 || st == 5 || st == 6)) {
		// weatherboards
		float bh = 0.17;
		float row = floor(uv.y / bh);
		float ly = fract(uv.y / bh);
		float shade = mix(0.62, 1.04, smoothstep(0.0, 0.3, ly)) * (0.92 + 0.12 * h21(vec2(row, sd)));
		b = col * mix(1.0, shade, pat_fade);
		float kn = vn2(vec2(uv.x * 22.0, uv.y * 2.0 + row * 3.0));
		b *= 0.93 + 0.1 * kn;
		grad.y += (0.5 - ly) * 0.35 * pat_fade;
		rough = 0.78;
		return b;
	}
	if (pat == 3 || (st == 6 && pat == 2)) {
		// rubble / ashlar stone
		if (st == 6) {
			vec2 w = uv + 0.2 * vec2(vn2(uv * 1.7 + sd), vn2(uv * 1.7 + 7.0));
			rubble(w * 2.2, sd, dj, tone, slope, bid);
			dj /= 2.2;
			float seam = (1.0 - smoothstep(0.01, 0.035 + fw * 0.8, dj)) * pat_fade * 0.7;
			b = col * (0.72 + 0.5 * tone) * (0.95 + 0.1 * grain);
			b = mix(b, col * 0.45, seam);
			grad += slope * 0.1 * pat_fade;
		} else {
			ashlar(uv, sd, 0.62, 1.1, dj, tone, slope, bid);
			float seam = (1.0 - smoothstep(0.004, 0.012 + fw * 0.8, dj)) * pat_fade * 0.6;
			b = col * (0.82 + 0.3 * tone) * (0.95 + 0.1 * grain);
			b = mix(b, col * 0.55, seam);
			grad += slope * 0.08 * pat_fade;
		}
		rough = 0.9;
		return b;
	}
	// smooth plaster: trowelled, stippled, a few hairline cracks
	float trowel = vn2(vec2(uv.x * 1.5, uv.y * 0.9) + sd);
	b = col * (0.93 + 0.12 * trowel) * (0.97 + 0.06 * vn3(P * 40.0));
	float cdj;
	float ctn;
	vec2 csl;
	float cid;
	rubble(uv * 1.05 + sd, sd, cdj, ctn, csl, cid);
	float cracked = step(0.9, h21(vec2(cid * 19.0, sd))) * smoothstep(0.42, 0.58, vn2(uv * 3.1 + sd));
	float crack = (1.0 - smoothstep(0.003, 0.003 + fw * 1.5, cdj / 1.05)) * cracked * (0.5 + 0.5 * vn2(uv * 7.0));
	b *= 1.0 - 0.2 * crack * (1.0 - lod);
	grad += (vec2(vn3(P * 18.0), vn3(P * 18.0 + 3.0)) - 0.5) * 0.05 * pat_fade;
	rough = 0.93;
	return b;
}

// one window opening of a bay: size, shape, frame, shutters ... returns the signed distance for the caller's use
void paint_opening(vec2 q, vec2 hs, int shape, float aa, vec3 frame_c, float fw, float sill_w, bool shutters, vec3 shut_c, int bars, float lit, float seed, vec3 tint, float night, inout Surf s) {
	float d = opening_sd(q, hs, shape);
	if (d > 0.45) {
		return;
	}
	if (shutters) {
		window_shutters(q, hs, fw, aa, shut_c, s);
	}
	window_frame(q, hs, d, aa, fw, frame_c, sill_w, s);
	window_glass(q, hs, d, aa, frame_c, lit, seed, bars, tint, night, s);
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// walls

void surf_wall(int st, int ci, int flg, bool gable, vec3 P, vec2 uv, vec2 uv2, float up, float fw, float lod, float d_edge, float d_top, float n_big, float n_mid,
		float owner, float night, float moss_k, float grime_k, float wet_k, inout Surf s) {
	int pat = pal_pat(st, ci);
	vec3 col = pal_wall(st, ci);
	vec3 trim = pal_trim(st, ci);
	float sd = float(st) * 7.3 + float(ci) * 3.1 + owner * 0.37;
	float aa = max(fw * 1.1, 0.012);
	float hy = P.y - 0.6;
	bool nowin = (flg & 128) != 0;
	float flen = abs(uv2.y);
	bool has_fac = flen > 0.9 && !nowin;

	vec3 b = wall_base(st, pat, col, P, uv, fw, lod, sd, s.rough, s.grad);
	// lacquered / charred walls are their own materials
	if (st == 3 && pat == 1) {
		// red lacquer wall: flat vermilion, a faint gloss and brush streaks
		b = col * (0.9 + 0.14 * vn2(vec2(uv.x * 30.0, uv.y * 1.3) + sd));
		s.rough = 0.45;
		s.spec = 0.55;
	}
	if (st == 4 && pat == 1) {
		// shou sugi ban: charred boards, cracked into scales
		float bw = 0.19;
		float px = floor(uv.x / bw);
		float lx = fract(uv.x / bw);
		float ddj;
		float ttn;
		vec2 ssl;
		float bbid;
		rubble(vec2(uv.x * 4.0, uv.y * 1.6) + px * 3.0, sd, ddj, ttn, ssl, bbid);
		b = col * (0.55 + 0.7 * ttn) * (0.85 + 0.3 * vn2(vec2(uv.x * 60.0, uv.y * 3.0)));
		b *= 0.55 + 0.45 * smoothstep(0.0, 0.08, lx) * smoothstep(1.0, 0.92, lx);
		s.rough = 0.85;
		s.grad.x += (lx - 0.5) * 0.2;
	}
	if (st == 4 && pat == 2) {
		// earth plaster with straw flecks
		b *= 0.9 + 0.2 * vn2(uv * 5.0 + sd);
		b = mix(b, b * vec3(1.1, 1.0, 0.8), step(0.93, vn2(vec2(uv.x * 40.0, uv.y * 5.0))) * 0.7);
		s.rough = 0.97;
	}
	vec3 frame_c = trim;
	s.albedo = b;
	s.ao *= 1.0;
	if (has_fac) {
		float lvl = floor(hy / 4.0);
		float ly4 = hy - lvl * 4.0;
		if (st == 1) {
			// HOUSE: windows with frames, sills and often shutters; a plinth, a string course between the storeys, quoins at the corners
			Bay bay = make_bay(uv2, 2.25, 1.45);
			float lev = lvl;
			bool doorbay = bay.door && abs(bay.bi - bay.mid) < 0.5 && lev < 0.5;
			float hb = h21(vec2(bay.bi * 1.7 + lev * 5.3, bay.len * 3.1 + owner * 0.173));
			float hw = clamp(0.2 + 0.18 * bay.len / bay.nb * 0.4, 0.33, 0.46);
			vec2 hs = vec2(hw, 0.74 + 0.07 * h11(owner + lev));
			if (!doorbay && bay.end_d > 0.35) {
				vec2 q = vec2(bay.bx, ly4 - 2.05);
				int shape = hb > 0.82 ? 1 : 0;
				paint_opening(q, hs + vec2(0.0, 0.0), shape, aa, frame_c, 0.07, 0.07, hb < 0.5, mix(lin(vec3(0.2, 0.34, 0.3)), lin(vec3(0.5, 0.2, 0.18)), step(0.25, h21(vec2(owner, lev)))), (hb > 0.4 && hb < 0.62) ? 2 : 1,
					step(0.58, h21(vec2(bay.bi + lev * 3.0, owner * 0.7 + 4.0))), sd, vec3(0.4, 0.5, 0.6), night, s);
			}
			// corner pilasters (quoins), alternating long and short blocks
			float qd = bay.end_d;
			float qw = 0.2;
			if (qd < qw) {
				float qi = floor((hy + (uv2.x < bay.len * 0.5 ? 0.0 : 0.25)) / 0.5);
				float longq = mod(qi, 2.0);
				float qq = qd < qw * (0.78 + 0.22 * longq) ? 1.0 : 0.0;
				s.albedo = mix(s.albedo, frame_c * 1.03, qq);
				s.grad.x += qq * 0.2 * (uv2.x < bay.len * 0.5 ? -1.0 : 1.0);
			}
			// string course between storeys and a base course
			float sc = cover(abs(ly4 - 0.05) - 0.1, aa) * step(0.5, lvl);
			s.albedo = mix(s.albedo, frame_c, sc);
			s.grad.y += sc * 0.3 * (ly4 > 0.05 ? -1.0 : 1.0);
			float base_c = cover(hy - 0.55, aa);
			s.albedo = mix(s.albedo, mix(col * 0.6, lin(vec3(0.45, 0.42, 0.38)), 0.5), base_c * 0.85);
			// front door surround
			if (bay.door && lev < 0.5) {
				vec2 qd2 = vec2(uv2.x - bay.len * 0.5, hy);
				float dd = sdbox(qd2 - vec2(0.0, 1.2), vec2(0.7, 1.28));
				float dr = cover(dd, aa) - cover(dd + 0.15, aa);
				s.albedo = mix(s.albedo, frame_c, clamp(dr, 0.0, 1.0));
				float dl = sdbox(qd2 - vec2(0.0, 2.58), vec2(0.86, 0.1));
				s.albedo = mix(s.albedo, frame_c * 1.05, cover(dl, aa));
			}
		} else if (st == 2) {
			// APARTMENT: two floors to a storey, wide window bands, slab edges, balconies on some bays
			Bay bay = make_bay(uv2, 2.5, 1.7);
			float fl = floor(hy / 2.0);
			float ly2 = hy - fl * 2.0;
			bool doorbay = bay.door && abs(bay.bi - bay.mid) < 0.5 && fl < 0.5;
			float hb = h21(vec2(bay.bi * 1.3 + fl * 4.1, bay.len * 2.3 + owner * 0.21));
			if (pat == 2) {
				// glass curtain wall: a grid of glazing, spandrel panels at the slab edges
				float gx = bay.bx;
				float mull = min(abs(gx) , abs(abs(gx) - 0.0));
				float cw = bay.len / bay.nb;
				float edge = min(abs(gx + cw * 0.5), abs(gx - cw * 0.5));
				float mull_m = 1.0 - smoothstep(0.03, 0.03 + aa, edge);
				float span = 1.0 - smoothstep(0.0, 0.22, abs(ly2 - 0.0)) ;
				float glass_m = 1.0 - clamp(mull_m + span, 0.0, 1.0);
				vec3 tint = col * 0.9;
				vec3 gl = mix(vec3(0.01, 0.015, 0.02), tint * 0.5, 0.35 + 0.3 * smoothstep(0.0, 2.0, ly2));
				float lit = step(0.6, h21(vec2(bay.bi + fl * 7.0, owner * 0.3)));
				vec3 e = lin(vec3(1.0, 0.8, 0.5)) * lit * night * 1.4;
				s.albedo = mix(s.albedo, gl, glass_m);
				s.emis = mix(s.emis, e, glass_m);
				s.rough = mix(s.rough, 0.04, glass_m);
				s.spec = mix(s.spec, 0.95, glass_m);
				s.albedo = mix(s.albedo, trim * 0.8, clamp(mull_m + span, 0.0, 1.0) * (1.0 - glass_m));
				s.metal = mix(s.metal, 0.6, clamp(mull_m + span, 0.0, 1.0));
			} else {
				if (!doorbay && bay.end_d > 0.5) {
					vec2 q = vec2(bay.bx, ly2 - 1.1);
					vec2 hs = vec2(min(0.9, bay.len / bay.nb * 0.36), 0.52);
					float lit = step(0.6, h21(vec2(bay.bi + fl * 7.0, owner * 0.3)));
					paint_opening(q, hs, 0, aa, trim, 0.06, 0.0, false, trim, 1, lit, sd, vec3(0.45, 0.55, 0.65), night, s);
					// a balcony rail on some bays above the ground floor
					if (fl > 0.5 && hb > 0.7) {
						float rail = sdbox(q - vec2(0.0, -0.62), vec2(hs.x + 0.12, 0.34));
						float bars = 1.0 - smoothstep(0.012, 0.012 + aa, abs(fract(q.x / 0.14 + 0.5) - 0.5) * 0.14);
						float top = cover(sdbox(q - vec2(0.0, -0.3), vec2(hs.x + 0.12, 0.02)), aa);
						float r = cover(rail, aa);
						s.albedo = mix(s.albedo, trim * 0.7, r * bars * 0.9 + top);
						s.metal = mix(s.metal, 0.5, r);
					}
				}
			}
			// slab edges every storey
			float slab = cover(abs(ly2 - 0.0) - 0.07, aa) * step(0.5, fl);
			if (pat != 2) {
				s.albedo = mix(s.albedo, mix(col, trim, 0.4) * 0.85, slab);
			}
			if (bay.door && fl < 0.5) {
				vec2 qd2 = vec2(uv2.x - bay.len * 0.5, hy);
				float dd = sdbox(qd2 - vec2(0.0, 1.2), vec2(0.72, 1.3));
				s.albedo = mix(s.albedo, trim * 0.8, cover(dd, aa) - cover(dd + 0.14, aa));
				float cn = sdbox(qd2 - vec2(0.0, 2.7), vec2(1.1, 0.07));
				s.albedo = mix(s.albedo, trim * 0.7, cover(cn, aa));
			}
		} else if (st == 3) {
			// CHINESE: red pillars at the bay lines, a lattice window or a moon window between, a painted beam under the eaves
			Bay bay = make_bay(uv2, 2.3, 1.7);
			float lev = lvl;
			bool doorbay = bay.door && abs(bay.bi - bay.mid) < 0.5 && lev < 0.5;
			float bw = bay.len / bay.nb;
			float edge = min(abs(bay.bx + bw * 0.5), abs(bay.bx - bw * 0.5));
			vec3 red = pal_trim(st, ci);
			float pil = cover(edge - 0.15, aa);
			// pillars
			s.albedo = mix(s.albedo, red * (0.9 + 0.2 * vn2(vec2(uv.x * 40.0, uv.y)) ), pil);
			s.rough = mix(s.rough, 0.4, pil);
			s.grad.x += pil * (bay.bx > 0.0 ? 0.25 : -0.25) * smoothstep(0.0, 0.15, 0.15 - edge + 0.0);
			float hb = h21(vec2(bay.bi * 1.9 + lev * 6.1, owner * 0.27));
			if (!doorbay && edge > 0.3) {
				vec2 q = vec2(bay.bx, ly4 - 2.2);
				if (hb > 0.75) {
					// a round moon window
					float d = length(q) - 0.62;
					float ring = cover(d - 0.0, aa) - cover(d + 0.0, aa);
					window_frame(q, vec2(0.62), d, aa, 0.09, red, 0.0, s);
					window_glass(q, vec2(0.62), d, aa, red, 0.0, sd, 3, vec3(0.4, 0.5, 0.45), night, s);
				} else {
					vec2 hs = vec2(min(bw * 0.5 - 0.3, 0.75), 0.8);
					float lit = step(0.6, h21(vec2(bay.bi + lev * 5.0, owner * 0.7)));
					paint_opening(q, hs, 0, aa, red, 0.07, 0.0, false, red, 3, lit, sd, vec3(0.5, 0.45, 0.35), night, s);
				}
			}
			// the beam: red, with a band of blue and green painted patterns
			float beam = cover(abs(ly4 - 3.55) - 0.3, aa);
			float pat_b = 0.5 + 0.5 * sin(uv.x * 11.0) * sin(ly4 * 14.0);
			vec3 paint = mix(lin(vec3(0.1, 0.35, 0.55)), lin(vec3(0.15, 0.5, 0.35)), step(0.5, pat_b));
			s.albedo = mix(s.albedo, mix(red, paint, cover(abs(ly4 - 3.55) - 0.14, aa)), beam);
			// a plinth of grey stone
			s.albedo = mix(s.albedo, lin(vec3(0.46, 0.46, 0.45)) * (0.8 + 0.3 * vn2(uv * 6.0)), cover(hy - 0.5, aa));
			if (bay.door && lev < 0.5) {
				vec2 qd2 = vec2(uv2.x - bay.len * 0.5, hy);
				float dd = sdbox(qd2 - vec2(0.0, 1.2), vec2(0.7, 1.28));
				s.albedo = mix(s.albedo, red, cover(dd, aa) - cover(dd + 0.16, aa));
				float cn = sdbox(qd2 - vec2(0.0, 2.72), vec2(0.92, 0.1));
				s.albedo = mix(s.albedo, lin(vec3(0.8, 0.62, 0.15)), cover(cn, aa));
			}
		} else if (st == 4) {
			// JAPANESE: dark posts every bay, beams, shoji windows, lower boards, a namako band on the ground floor
			Bay bay = make_bay(uv2, 1.82, 1.2);
			float lev = lvl;
			bool doorbay = bay.door && abs(bay.bi - bay.mid) < 0.5 && lev < 0.5;
			float bw = bay.len / bay.nb;
			float edge = min(abs(bay.bx + bw * 0.5), abs(bay.bx - bw * 0.5));
			vec3 wood = pal_trim(st, ci);
			float hb = h21(vec2(bay.bi * 2.3 + lev * 5.7, owner * 0.31));
			if (!doorbay && edge > 0.12) {
				vec2 q = vec2(bay.bx, ly4 - 2.1);
				vec2 hs = vec2(bw * 0.5 - 0.17, 0.78);
				if (hb < 0.6 && bw > 1.3) {
					// shoji: paper in a fine wooden grid
					float d = sdbox(q, hs);
					float m = cover(d, aa);
					vec3 paper = lin(vec3(0.93, 0.9, 0.78)) * (0.9 + 0.1 * vn2(q * 20.0 + sd));
					float gx = abs(fract(q.x / (hs.x * 0.5) + 0.5) - 0.5) * (hs.x * 0.5);
					float gy = abs(fract(q.y / 0.36 + 0.5) - 0.5) * 0.36;
					float gridm = max(1.0 - smoothstep(0.012, 0.012 + aa, gx), 1.0 - smoothstep(0.012, 0.012 + aa, gy));
					vec3 sh = mix(paper, wood, gridm);
					window_frame(q, hs, d, aa, 0.06, wood, 0.0, s);
					s.albedo = mix(s.albedo, sh, m);
					float lit = step(0.55, h21(vec2(bay.bi + lev * 4.0, owner * 0.9)));
					s.emis = mix(s.emis, lin(vec3(1.0, 0.78, 0.45)) * lit * night * 1.3, m * (1.0 - gridm));
					s.rough = mix(s.rough, 0.9, m);
				} else if (hb < 0.82) {
					// a wooden lattice (koshi) over a dark room
					float d = sdbox(q, hs);
					float m = cover(d, aa);
					float gx = abs(fract(q.x / 0.09 + 0.5) - 0.5) * 0.09;
					float bars = 1.0 - smoothstep(0.016, 0.016 + aa, gx);
					s.albedo = mix(s.albedo, mix(vec3(0.02), wood, bars), m);
					window_frame(q, hs, d, aa, 0.07, wood, 0.0, s);
				}
			}
			// posts and beams
			float post = cover(edge - 0.07, aa);
			s.albedo = mix(s.albedo, wood * (0.85 + 0.3 * vn2(vec2(uv.x * 50.0, uv.y * 1.2))), post);
			for (int i = 0; i < 3; i++) {
				float by = i == 0 ? 0.12 : (i == 1 ? 3.0 : 3.88);
				float bm = cover(abs(ly4 - by) - (i == 2 ? 0.1 : 0.07), aa);
				s.albedo = mix(s.albedo, wood, bm);
			}
			// namako: black tiles with white raised joints on the lower wall of the ground floor
			float nam = cover(hy - 1.0, aa);
			if (lev < 0.5 && nam > 0.01) {
				vec2 g = uv * 3.4;
				float gj = min(abs(fract(g.x + g.y) - 0.5), abs(fract(g.x - g.y) - 0.5));
				float jm = 1.0 - smoothstep(0.0, 0.09, gj);
				s.albedo = mix(s.albedo, mix(lin(vec3(0.07, 0.07, 0.08)), lin(vec3(0.88, 0.86, 0.8)), jm), nam * 0.95);
				s.grad.x += (fract(g.x + g.y) - 0.5) * 0.15 * nam;
			}
			if (bay.door && lev < 0.5) {
				vec2 qd2 = vec2(uv2.x - bay.len * 0.5, hy);
				float dd = sdbox(qd2 - vec2(0.0, 1.2), vec2(0.7, 1.28));
				s.albedo = mix(s.albedo, wood, cover(dd, aa) - cover(dd + 0.12, aa));
			}
		} else if (st == 5) {
			// FANTASY: arched, pointed and round windows in fat frames, flower boxes, a crooked ribbon of trim
			Bay bay = make_bay(uv2, 2.0, 1.4);
			float lev = lvl;
			bool doorbay = bay.door && abs(bay.bi - bay.mid) < 0.5 && lev < 0.5;
			float hb = h21(vec2(bay.bi * 1.3 + lev * 4.7, owner * 0.19 + bay.len));
			if (!doorbay && bay.end_d > 0.3) {
				float wob = (h21(vec2(bay.bi, lev + owner)) - 0.5) * 0.35;
				vec2 q = vec2(bay.bx, ly4 - 2.1 + wob);
				int shape = hb < 0.34 ? 1 : (hb < 0.62 ? 3 : (hb < 0.8 ? 2 : 0));
				vec2 hs = shape == 2 ? vec2(0.45, 0.6) : vec2(0.38, 0.8);
				float lit = step(0.5, h21(vec2(bay.bi + lev * 3.0, owner * 0.7)));
				vec3 gl_tint = mix(vec3(0.3, 0.5, 0.8), vec3(0.8, 0.4, 0.6), h21(vec2(bay.bi, lev)));
				paint_opening(q, hs, shape, aa, frame_c, 0.1, 0.1, false, frame_c, hb > 0.6 ? 3 : 1, lit, sd, gl_tint, night, s);
				if (hb > 0.3) {
					// flower box
					float fb = sdbox(q - vec2(0.0, -hs.y - 0.3), vec2(hs.x + 0.1, 0.1));
					s.albedo = mix(s.albedo, lin(vec3(0.34, 0.2, 0.12)), cover(fb, aa));
					float fl = cover(fb - 0.09, aa) * step(0.15, fract(q.x * 9.0 + sd)) * step(0.0, q.y + hs.y + 0.25);
					s.albedo = mix(s.albedo, mix(lin(vec3(0.85, 0.2, 0.35)), lin(vec3(0.95, 0.8, 0.2)), step(0.5, h21(floor(q * 9.0)))), fl * 0.8);
				}
			}
			// a ribbon of trim winding up the wall between storeys
			float rib = cover(abs(ly4 - (0.15 + 0.12 * sin(uv.x * 2.2 + sd))) - 0.1, aa) * step(0.5, lvl);
			s.albedo = mix(s.albedo, frame_c, rib);
			if (pat == 1) {
				float stripe = step(0.5, fract(uv2.x / 0.9));
				s.albedo = mix(s.albedo, s.albedo * 0.8 + frame_c * 0.12, stripe);
			}
			if (bay.door && lev < 0.5) {
				vec2 qd2 = vec2(uv2.x - bay.len * 0.5, hy);
				float dd = opening_sd(qd2 - vec2(0.0, 1.18), vec2(0.72, 1.3), 1);
				s.albedo = mix(s.albedo, frame_c, cover(dd, aa) - cover(dd + 0.15, aa));
			}
		} else if (st == 6) {
			// VILLAGE: timber framing round plaster panels, small casements with shutters and flowers
			Bay bay = make_bay(uv2, 1.95, 1.3);
			float lev = lvl;
			bool doorbay = bay.door && abs(bay.bi - bay.mid) < 0.5 && lev < 0.5;
			float bw = bay.len / bay.nb;
			float edge = min(abs(bay.bx + bw * 0.5), abs(bay.bx - bw * 0.5));
			vec3 wood = pal_trim(st, ci);
			float hb = h21(vec2(bay.bi * 1.7 + lev * 5.1, owner * 0.23));
			if (pat == 0) {
				// half-timber: posts at the bay lines, rails at the floor, mid and top, braces in some bays
				float post = cover(edge - 0.07, aa);
				float rail = 0.0;
				for (int i = 0; i < 3; i++) {
					float ry = i == 0 ? 0.09 : (i == 1 ? 1.15 : 3.9);
					rail = max(rail, cover(abs(ly4 - ry) - 0.075, aa));
				}
				float brace = 0.0;
				if (hb > 0.5) {
					float dl = (bay.bx / bw + 0.5) * 3.0 * (hb > 0.75 ? 1.0 : -1.0);
					float yy = (ly4 - 1.15) / 2.75 * 3.0;
					brace = cover(abs((dl * 1.0 + (hb > 0.75 ? 0.0 : 3.0)) - yy) * 0.55 - 0.05, aa) * step(1.2, ly4) * step(ly4, 3.85) * step(0.1, edge);
				}
				float tim = max(max(post, rail), brace);
				s.albedo = mix(s.albedo, wood * (0.8 + 0.3 * vn2(vec2(uv.x * 40.0, uv.y * 3.0))), tim);
				s.grad.x += post * 0.2 * (bay.bx > 0.0 ? 1.0 : -1.0);
			}
			if (!doorbay && edge > 0.22) {
				vec2 q = vec2(bay.bx, ly4 - 2.05);
				vec2 hs = vec2(min(0.34, bw * 0.3), 0.42);
				float lit = step(0.5, h21(vec2(bay.bi + lev * 3.0, owner * 0.7)));
				paint_opening(q, hs, 0, aa, wood, 0.06, 0.08, hb < 0.6, mix(lin(vec3(0.22, 0.34, 0.3)), lin(vec3(0.5, 0.22, 0.16)), step(0.4, h21(vec2(owner, lev + 2.0)))), 2, lit, sd, vec3(0.4, 0.5, 0.55), night, s);
				if (hb > 0.4 && lev < 1.5) {
					float fb = sdbox(q - vec2(0.0, -hs.y - 0.22), vec2(hs.x + 0.1, 0.08));
					s.albedo = mix(s.albedo, lin(vec3(0.3, 0.19, 0.11)), cover(fb, aa));
					float fl = cover(fb - 0.07, aa) * step(0.0, q.y + hs.y + 0.18);
					s.albedo = mix(s.albedo, mix(lin(vec3(0.85, 0.22, 0.25)), lin(vec3(0.95, 0.85, 0.3)), step(0.5, h21(floor(q * 11.0)))), fl * 0.85);
				}
			}
			float base_c = cover(hy - 0.6, aa);
			s.albedo = mix(s.albedo, lin(vec3(0.42, 0.4, 0.36)) * (0.8 + 0.3 * vn2(uv * 8.0)), base_c * 0.85);
			if (bay.door && lev < 0.5) {
				vec2 qd2 = vec2(uv2.x - bay.len * 0.5, hy);
				float dd = sdbox(qd2 - vec2(0.0, 1.2), vec2(0.7, 1.28));
				s.albedo = mix(s.albedo, wood, cover(dd, aa) - cover(dd + 0.14, aa));
			}
		}
	} else if (gable && flen > 0.9) {
		// the triangle of wall under a gable roof: a round attic window in the middle
		vec2 q = vec2(uv2.x - flen * 0.5, uv.y - 0.95);
		float d = length(q) - 0.26;
		if (st == 4 || st == 3) {
			d = sdbox(q, vec2(0.22, 0.24));
		}
		paint_opening(q, vec2(0.26), 2, aa, frame_c, 0.06, 0.0, false, frame_c, 1, 0.5, sd, vec3(0.4, 0.5, 0.6), night, s);
	}
	b = s.albedo;
	b = sty_weather(b, P, up, d_top, lod, n_big, n_mid, uv.x, moss_k, grime_k, wet_k, sd, s.rough);
	s.albedo = b;
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// roofs

void surf_roof(int st, int ci, vec3 P, vec2 uv, float up, float fw, float lod, float n_big, float n_mid, float owner, float moss_k, float wet_k, inout Surf s) {
	int kind = pal_cover(st, ci);
	vec3 col = pal_roof(st, ci);
	float sd = float(st) * 5.1 + float(ci) * 2.3 + owner * 0.29;
	vec3 b = col;
	float aa = max(fw, 0.01);
	if (kind == 0 || kind == 3) {
		// clay tile (0) or glazed tile (3): pans and covers running down the slope
		float tw = kind == 3 ? 0.2 : 0.26;
		float x = uv.x / tw;
		float col_i = floor(x);
		float lx = fract(x);
		float barrel = sin(lx * 3.14159);
		float rh = kind == 3 ? 0.3 : 0.34;
		float row = floor(uv.y / rh);
		float ly = fract(uv.y / rh);
		float tone = h21(vec2(col_i, row) + sd);
		b = col * (kind == 3 ? 0.92 + 0.12 * tone : 0.78 + 0.45 * tone) * (0.93 + 0.14 * n_mid);
		b *= mix(1.0, 0.58 + 0.5 * barrel, 1.0 - lod * 0.7);
		b *= mix(1.0, 0.62 + 0.38 * smoothstep(0.0, 0.2, ly), 1.0 - lod * 0.7);
		float cr = smoothstep(0.62, 0.9, n_mid);
		b = mix(b, lin(vec3(0.34, 0.36, 0.16)), cr * 0.2 * moss_k);
		b = mix(b, lin(vec3(0.62, 0.55, 0.22)), smoothstep(0.8, 0.86, vn2(uv * 6.0 + 3.0)) * 0.1);
		s.rough = kind == 3 ? mix(0.22, 0.12, wet_k) : mix(0.72, 0.4, wet_k * 0.7);
		s.spec = kind == 3 ? 0.7 : 0.35;
		s.grad += vec2(cos(lx * 3.14159) * 0.3, (0.5 - ly) * 0.28) * (1.0 - lod);
		s.ao *= 0.74 + 0.26 * barrel;
	} else if (kind == 1) {
		// slate: rows of overlapping slates
		float row_h = 0.26;
		float row = floor(uv.y / row_h);
		float ly = fract(uv.y / row_h);
		float off = h11(row + sd) * 2.0;
		float x = uv.x / 0.31 + off;
		float c = floor(x);
		float lx = fract(x);
		float tone = h21(vec2(c, row) + sd);
		b = col * (0.65 + 0.7 * tone);
		float gap = smoothstep(0.0, 0.05, lx) * smoothstep(1.0, 0.95, lx);
		float lap = smoothstep(0.0, 0.2, ly);
		b *= mix(1.0, 0.5 + 0.5 * lap * gap, 1.0 - lod * 0.6);
		b = mix(b, lin(vec3(0.22, 0.31, 0.1)), smoothstep(0.55, 0.85, n_mid + 0.1 * (1.0 - up)) * moss_k * 0.3);
		b *= 1.0 - 0.3 * smoothstep(0.5, 0.95, n_big);
		s.rough = mix(0.78, 0.3, wet_k * 0.8) + 0.1 * tone;
		s.grad += vec2((lx - 0.5) * 0.05, (0.5 - ly) * 0.4 * (1.0 - lap)) * (1.0 - lod);
		s.ao *= 0.78 + 0.22 * lap;
	} else if (kind == 2) {
		// thatch: straw strands down the slope, laid in overlapping courses, mossy on the shaded side
		col = mix(col, vec3(dot(col, vec3(0.34))), 0.3);
		float strand = vn2(vec2(uv.x * 38.0, uv.y * 1.6 + sd));
		float strand2 = vn2(vec2(uv.x * 110.0, uv.y * 3.0 + sd * 2.0));
		float course = fract(uv.y / 0.42);
		float cour_m = smoothstep(0.0, 0.18, course);
		b = col * (0.65 + 0.55 * strand) * (0.85 + 0.3 * strand2);
		b *= 0.7 + 0.3 * cour_m;
		b = mix(b, lin(vec3(0.3, 0.34, 0.14)), smoothstep(0.6, 0.85, n_mid) * 0.5 * moss_k);
		b *= 1.0 - 0.2 * smoothstep(0.55, 0.95, n_big);
		s.rough = 1.0;
		s.spec = 0.1;
		s.grad += vec2((strand - 0.5) * 0.25, (0.5 - course) * 0.3) * (1.0 - lod);
		s.ao *= 0.8 + 0.2 * cour_m;
	} else if (kind == 4) {
		// zinc / membrane: standing seams down the slope
		float seam_d = abs(fract(uv.x / 0.5 + 0.5) - 0.5) * 0.5;
		float seam = 1.0 - smoothstep(0.008, 0.016 + aa, seam_d);
		b = col * (0.9 + 0.15 * vn2(vec2(uv.x * 3.0, uv.y * 0.4) + sd));
		b = mix(b, b * 1.4, seam);
		s.metal = 0.6;
		s.rough = 0.38;
		s.grad.x += (fract(uv.x / 0.5 + 0.5) - 0.5) * 0.05 * (1.0 - lod);
	} else if (kind == 8) {
		// kawara: grey-silver pan and cover tiles in long rows, a soft sheen, a darker edge to every tile
		float tw = 0.21;
		float x = uv.x / tw;
		float col_i = floor(x);
		float lx = fract(x);
		float barrel = sin(lx * 3.14159);
		float rh = 0.3;
		float row = floor(uv.y / rh);
		float ly = fract(uv.y / rh);
		float tone = h21(vec2(col_i, row) + sd);
		vec3 silver = col + lin(vec3(0.24)) * 0.7;
		b = silver * (0.8 + 0.3 * tone) * (0.94 + 0.12 * n_mid);
		b *= mix(1.0, 0.62 + 0.5 * barrel, 1.0 - lod * 0.7);
		b *= mix(1.0, 0.7 + 0.3 * smoothstep(0.0, 0.18, ly), 1.0 - lod * 0.7);
		b = mix(b, lin(vec3(0.3, 0.34, 0.2)), smoothstep(0.66, 0.9, n_mid) * 0.12 * moss_k);
		s.rough = mix(0.45, 0.2, wet_k);
		s.spec = 0.55;
		s.grad += vec2(cos(lx * 3.14159) * 0.28, (0.5 - ly) * 0.22) * (1.0 - lod);
		s.ao *= 0.78 + 0.22 * barrel;
	} else if (kind == 5) {
		// copper gone green in streaks
		float streak = vn2(vec2(uv.x * 14.0, uv.y * 0.8 + sd));
		b = mix(col, lin(vec3(0.3, 0.55, 0.45)), smoothstep(0.35, 0.8, streak));
		s.metal = 0.5;
		s.rough = 0.45;
	} else if (kind == 6) {
		// wood shingles
		float row_h = 0.2;
		float row = floor(uv.y / row_h);
		float ly = fract(uv.y / row_h);
		float x = uv.x / 0.16 + h11(row) * 3.0;
		float c = floor(x);
		float lx = fract(x);
		float tone = h21(vec2(c, row) + sd);
		b = col * (0.6 + 0.7 * tone) * (0.9 + 0.2 * vn2(vec2(uv.x * 30.0, uv.y * 4.0)));
		b *= mix(1.0, 0.55 + 0.45 * smoothstep(0.0, 0.25, ly) * smoothstep(0.0, 0.06, lx) * smoothstep(1.0, 0.94, lx), 1.0 - lod * 0.6);
		s.rough = 0.88;
		s.grad.y += (0.5 - ly) * 0.3 * (1.0 - lod);
	} else {
		// fish-scale tiles, glossy
		float sc = 0.24;
		vec2 g = vec2(uv.x / sc, uv.y / (sc * 0.62));
		float row = floor(g.y);
		g.x += mod(row, 2.0) * 0.5;
		vec2 f = fract(g) - vec2(0.5, 0.0);
		float dd = length(vec2(f.x, f.y - 0.12) * vec2(1.0, 1.0));
		float edge = smoothstep(0.52, 0.45, dd);
		float tone = h21(floor(g) + sd);
		b = col * (0.8 + 0.4 * tone);
		b *= 0.55 + 0.45 * edge;
		b = mix(b, b * 1.2 + 0.03, smoothstep(0.35, 0.0, dd) * 0.5);
		s.rough = 0.2;
		s.spec = 0.75;
		s.grad += (vec2(f.x, f.y - 0.3)) * 0.3 * (1.0 - lod);
	}
	s.albedo = b;
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// trim: fascia, soffit, door leaves, beams

void surf_trim(int st, int ci, int flg, vec3 P, vec2 uv, float up, float fw, float lod, float n_mid, float owner, float wet_k, inout Surf s) {
	vec3 col = pal_trim(st, ci);
	float sd = float(st) * 3.7 + float(ci) * 1.9 + owner * 0.13;
	vec3 b = col;
	bool leaf = (flg & 1) != 0 && abs(up) < 0.5;
	float grain = vn2(vec2(uv.x * 38.0 + sd, uv.y * 2.4));
	if (leaf) {
		// a door: panelled (house, village), glass and metal (apartment), lacquered (Chinese), plain boards (Japanese), studded (fantasy)
		vec2 q = vec2(uv.x * 1.0, P.y - 0.6);
		float u = fract(uv.x * 0.9);
		float dx = abs(fract((uv.x) / 0.55 + 0.5) - 0.5);
		float panel = smoothstep(0.1, 0.16, dx) * smoothstep(0.0, 0.05, abs(fract((P.y - 0.6) / 0.9) - 0.5));
		b = col * (0.9 + 0.2 * grain);
		if (st == 1 || st == 6) {
			b *= 0.7 + 0.3 * panel;
			s.rough = 0.55;
		} else if (st == 2) {
			b = mix(col * 0.6, vec3(0.03, 0.04, 0.05), smoothstep(0.55, 0.65, P.y - 0.6) * (1.0 - smoothstep(2.0, 2.1, P.y - 0.6)));
			s.metal = 0.5;
			s.spec = 0.8;
		} else if (st == 3) {
			float nail = smoothstep(0.045, 0.03, length(vec2(fract(uv.x / 0.22 + 0.5) - 0.5, fract((P.y - 0.6) / 0.22 + 0.5) - 0.5)) * 0.22);
			b = mix(col * (0.8 + 0.2 * grain), lin(vec3(0.85, 0.68, 0.2)), nail * 0.9);
			s.rough = 0.35;
		} else if (st == 4) {
			float lat = abs(fract(uv.x / 0.12 + 0.5) - 0.5);
			b = col * (0.7 + 0.5 * smoothstep(0.0, 0.08, lat)) * (0.9 + 0.2 * grain);
		} else {
			float stud = smoothstep(0.05, 0.035, length(vec2(fract(uv.x / 0.28 + 0.5) - 0.5, fract((P.y - 0.6) / 0.28 + 0.5) - 0.5)) * 0.28);
			b = mix(col, lin(vec3(0.9, 0.75, 0.3)), stud);
			s.metal = stud * 0.8;
		}
		s.grad.x += (fract(uv.x / 0.3) - 0.5) * 0.1;
	} else {
		// painted wood: fine grain under the paint; lacquer (Chinese) is glossy, Japanese wood is oiled
		if (st == 3) {
			s.rough = 0.35;
			s.spec = 0.55;
			b *= 0.9 + 0.15 * grain;
		} else if (st == 4) {
			b *= 0.75 + 0.5 * grain;
			s.rough = 0.7;
		} else if (st == 5) {
			s.rough = 0.25;
			s.spec = 0.7;
			b *= 0.92 + 0.15 * grain;
		} else if (st == 2) {
			s.metal = 0.5;
			s.rough = 0.45;
		} else {
			b *= 0.94 + 0.1 * grain;
			s.rough = 0.62;
		}
	}
	b *= 0.9 + 0.2 * smoothstep(0.3, 0.8, n_mid);
	s.albedo = b;
}

// ---------------------------------------------------------------------------------------------------------------------------------------
// paving: terraces, flat roofs, courtyards

void surf_pave(int st, int ci, vec3 P, float fw, float lod, float n_mid, float owner, float moss_k, float wet_k, inout Surf s) {
	vec3 col = pal_wall(st, ci) * 0.8;
	float sd = float(st) * 4.3 + float(ci) * 2.1;
	float dj;
	float tone;
	vec2 slope;
	vec3 b = col;
	if (st == 2) {
		// roof membrane and gravel
		float gv = vn3(P * 30.0);
		b = mix(lin(vec3(0.22, 0.22, 0.23)), lin(vec3(0.42, 0.41, 0.4)), gv) * (0.8 + 0.3 * n_mid);
		float panel = 1.0 - smoothstep(0.0, 0.03 + fw, min(abs(fract(P.x / 2.4) - 0.5), abs(fract(P.z / 2.4) - 0.5)) - 0.47);
		b = mix(b, b * 0.6, panel * 0.0);
		s.rough = 0.95;
	} else if (st == 4) {
		// raked gravel
		float rake = 0.5 + 0.5 * sin((P.x * 0.7 + P.z * 0.4) * 24.0 + vn2(P.xz * 0.6) * 4.0);
		b = lin(vec3(0.78, 0.76, 0.7)) * (0.82 + 0.25 * rake) * (0.9 + 0.2 * vn3(P * 50.0));
		s.rough = 0.95;
	} else if (st == 6) {
		// packed earth and cobbles
		flags(P.xz * 1.1, sd, dj, tone, slope);
		float seam = 1.0 - smoothstep(0.02, 0.07, dj / 1.1);
		b = lin(vec3(0.5, 0.45, 0.38)) * (0.65 + 0.5 * tone);
		b = mix(b, lin(vec3(0.3, 0.26, 0.2)), seam * 0.7);
		s.grad += slope * 0.15;
		s.rough = 0.95;
	} else {
		// flagstones, tinted by the style
		flags(P.xz * 0.8, sd, dj, tone, slope);
		dj /= 0.8;
		float seam = (1.0 - smoothstep(0.012, 0.03 + fw, dj)) * (1.0 - lod);
		b = col * (0.7 + 0.4 * tone) * (0.92 + 0.14 * vn3(P * 20.0));
		b = mix(b, col * 0.4, seam * 0.7);
		s.grad += slope * 0.06;
		s.rough = 0.88;
	}
	b = mix(b, lin(vec3(0.2, 0.3, 0.1)), smoothstep(0.55, 0.85, fbm3(P * 1.2 + sd)) * 0.4 * moss_k);
	s.rough = mix(s.rough, 0.4, wet_k * 0.6);
	s.albedo = b;
}
