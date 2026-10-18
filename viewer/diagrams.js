'use strict';
/* The animated diagrams: how each game reads a click, Townscaper's ripple wave, and the hero background. Each runs on the page's one ticker
   and only while it is on screen. */

function hash2(a, b) {
	const x = Math.sin(a * 127.1 + b * 311.7) * 43758.5453;
	return x - Math.floor(x);
}

/** A small irregular quad grid (columns x rows of vertices) like Townscaper's relaxed one. Returns {V, cells}. */
function tsGrid(cols, rows, x0, y0, dx, dy, jit) {
	const V = [];
	for (let r = 0; r < rows; r++) {
		V.push([]);
		for (let c = 0; c < cols; c++) {
			const edge = r === 0 || c === 0 || r === rows - 1 || c === cols - 1;
			const j = edge ? jit * 0.4 : jit;
			V[r].push([x0 + c * dx + (hash2(r, c) - 0.5) * j * 2, y0 + r * dy + (hash2(c + 7, r + 3) - 0.5) * j * 2]);
		}
	}
	const cells = [];
	for (let r = 0; r < rows - 1; r++) for (let c = 0; c < cols - 1; c++) cells.push({ r, c, pts: [V[r][c], V[r][c + 1], V[r + 1][c + 1], V[r + 1][c]] });
	return { V, cells, cols, rows };
}

function miniCube(g, cx, cy, size) {
	/* a flat isometric cube with 8 corner dots; returns the dots */
	const a = size, b = size * 0.5, hgt = size * 0.95;
	const P = [
		[cx - a, cy + b * 0.2], [cx, cy + b * 1.2], [cx + a, cy + b * 0.2], [cx, cy - b * 0.8],
	];
	const pts = [];
	for (let i = 0; i < 4; i++) pts.push(P[i]);
	for (let i = 0; i < 4; i++) pts.push([P[i][0], P[i][1] - hgt]);
	const edges = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]];
	for (const [i, j] of edges) g.append(s('line', { x1: pts[i][0], y1: pts[i][1], x2: pts[j][0], y2: pts[j][1], stroke: i === 3 || j === 3 ? '#9db5c2' : '#3f6272', 'stroke-width': 1.6, 'stroke-dasharray': (i === 3 || j === 3) ? '3 3' : '' }));
	return pts.map(p => { const d = s('circle', { cx: p[0], cy: p[1], r: 5.5, fill: '#ffffff', stroke: '#2a9fb0', 'stroke-width': 1.6 }); g.append(d); return d; });
}

function runWhenVisible(el, fn) {
	let vis = false;
	watch(el, v => { vis = v; }, 0.05);
	return Ticker.add((dt, t) => { if (vis) fn(t, dt); });
}

/* --- Townscaper: what one cell reads --------------------------------------------------------------------------------- */

function initDgTs() {
	const svg = $('#dgTs');
	if (!svg) return;
	const G = tsGrid(7, 6, 40, 46, 56, 54, 7);
	const cell = (r, c) => G.cells[r * (G.cols - 1) + c];
	for (const q of G.cells) svg.append(s('polygon', { points: q.pts.map(p => p.join(',')).join(' '), fill: TH.cellFill, stroke: TH.cellStroke, 'stroke-width': 1.2 }));
	const vr = 3, vc = 3;                                   // the clicked vertex
	const four = [cell(vr - 1, vc - 1), cell(vr - 1, vc), cell(vr, vc - 1), cell(vr, vc)];
	const hl = four.map(q => { const p = s('polygon', { points: q.pts.map(p => p.join(',')).join(' '), fill: '#52c7d6', opacity: 0, stroke: '#52c7d6', 'stroke-width': 2 }); svg.append(p); return p; });
	const v = G.V[vr][vc];
	const ring = s('circle', { cx: v[0], cy: v[1], r: 4, fill: 'none', stroke: TH.ink, 'stroke-width': 2, opacity: 0 });
	const dot = s('circle', { cx: v[0], cy: v[1], r: 5, fill: TH.ink });
	svg.append(ring, dot);
	svg.append(s('text', { x: v[0] + 10, y: v[1] - 10, fill: TH.ink, 'font-size': 13, 'font-weight': 700 }, 'click'));
	// the cell's cube at the right
	const g = s('g');
	svg.append(g);
	const dots = miniCube(g, 456, 150, 38);
	svg.append(s('text', { x: 456, y: 208, 'text-anchor': 'middle', fill: TH.tsDark, 'font-size': 13 }, 'one cell:'));
	svg.append(s('text', { x: 456, y: 225, 'text-anchor': 'middle', fill: TH.tsDark, 'font-size': 13 }, '8 corners'));
	const arrow = s('path', { d: 'M ' + (v[0] + 70) + ' ' + (v[1] - 40) + ' C 330 80, 380 110, 412 130', fill: 'none', stroke: '#52c7d6', 'stroke-width': 2, 'stroke-dasharray': '5 4', opacity: 0 });
	svg.append(arrow);
	const t1 = s('text', { x: 40, y: 366, fill: TH.tsDark, 'font-size': 14 }, '4 cells × 2 storeys = 8 cells re-keyed by the click');
	const t2 = s('text', { x: 40, y: 18, fill: TH.muted, 'font-size': 12 }, 'plan view: the grid points are the corners of the cells');
	svg.append(t1, t2);
	runWhenVisible(svg, t => {
		const u = (t % 7) / 7 * 7;                           // seconds into the loop
		ring.setAttribute('r', 4 + 22 * clamp(u / 0.7, 0, 1));
		ring.setAttribute('opacity', u < 0.7 ? 1 - u / 0.7 : 0);
		hl.forEach((p, i) => p.setAttribute('opacity', 0.42 * smooth(0.5 + i * 0.18, 0.9 + i * 0.18, u) * (1 - smooth(6.2, 6.9, u))));
		arrow.setAttribute('opacity', smooth(1.5, 2.0, u) * (1 - smooth(6.2, 6.9, u)));
		dots.forEach((d, i) => { const a = smooth(2.0 + i * 0.16, 2.2 + i * 0.16, u) * (1 - smooth(6.2, 6.9, u)); d.setAttribute('fill', a > 0.5 ? '#52c7d6' : '#ffffff'); d.setAttribute('r', 5.5 + 2 * a); });
		t1.setAttribute('opacity', smooth(1.2, 1.8, u) * (1 - smooth(6.2, 6.9, u)));
	});
}

/* --- Townscaper: the wave ----------------------------------------------------------------------------------------------- */

function initDgWave() {
	const svg = $('#dgWave');
	if (!svg) return;
	const G = tsGrid(9, 7, 28, 30, 58, 52, 6);
	const cell = (r, c) => G.cells[r * (G.cols - 1) + c];
	const vr = 3, vc = 4;
	const rings = [];                                       // cell -> ring number (0 = the four round the click)
	for (const q of G.cells) {
		const dr = Math.max(vr - 1 - q.r, q.r - vr, 0), dc = Math.max(vc - 1 - q.c, q.c - vc, 0);
		q.ring = Math.max(dr, dc);
		q.el = s('polygon', { points: q.pts.map(p => p.join(',')).join(' '), fill: TH.cellFill, stroke: TH.cellStroke, 'stroke-width': 1.2 });
		svg.append(q.el);
		// whether the wave reaches this cell: the faces differ only for some cells (a fixed pseudo-random pick)
		q.goes = q.ring === 0 || (q.ring === 1 && hash2(q.r, q.c) < 0.62) || (q.ring === 2 && hash2(q.r + 5, q.c + 2) < 0.28);
	}
	const v = G.V[vr][vc];
	const ring = s('circle', { cx: v[0], cy: v[1], r: 4, fill: 'none', stroke: TH.ink, 'stroke-width': 2, opacity: 0 });
	svg.append(ring, s('circle', { cx: v[0], cy: v[1], r: 5, fill: TH.ink }));
	const lab = s('text', { x: 16, y: 372, fill: TH.tsDark, 'font-size': 13 }, '');
	svg.append(lab);
	const msgs = [[0.5, 'click: the 4 cells round the point are re-keyed'], [2.4, 'ring 1: re-solved where the faces could differ'], [3.6, 'ring 2: only a few cells change'], [4.8, 'the wave stops where faces agree']];
	runWhenVisible(svg, t => {
		const u = t % 7;
		ring.setAttribute('r', 4 + 22 * clamp(u / 0.7, 0, 1));
		ring.setAttribute('opacity', u < 0.7 ? 1 - u / 0.7 : 0);
		const fade = 1 - smooth(6.3, 6.9, u);
		for (const q of G.cells) {
			const start = 0.6 + q.ring * 1.25;
			let a = 0;
			if (q.goes) a = smooth(start, start + 0.5, u) * (q.ring === 0 ? 0.55 : q.ring === 1 ? 0.34 : 0.2);
			else if (q.ring <= 3) a = smooth(start + 0.2, start + 0.5, u) * (1 - smooth(start + 0.5, start + 0.9, u)) * 0.12;   // a flicker: checked, agrees
			q.el.setAttribute('fill', '#52c7d6');
			q.el.setAttribute('fill-opacity', (a * fade).toFixed(3));
		}
		let msg = msgs[0][1];
		for (const m of msgs) if (u >= m[0]) msg = m[1];
		lab.textContent = msg;
	});
}

/* --- this game: what one block reads ------------------------------------------------------------------------------------- */

function initDgGm() {
	const svg = $('#dgGm');
	const D = neighData();
	if (!svg || !D) return;
	const inner = s('svg', { x: 0, y: 24, width: 336, height: 288, viewBox: '0 0 560 480' });
	svg.append(inner);
	const pv = new PlanView(inner, D.cell, { mini: false });
	// the answer boxes
	const L = D.k1;
	svg.append(s('text', { x: 14, y: 16, fill: TH.muted, 'font-size': 12 }, 'plan view: the block (gold) reads its neighbours, three storeys each'));
	svg.append(s('rect', { x: 352, y: 74, width: 156, height: 62, rx: 12, fill: TH.boxFill, stroke: TH.boxStroke }));
	svg.append(s('text', { x: 430, y: 100, 'text-anchor': 'middle', fill: TH.gmDark, 'font-size': 13, 'font-weight': 700 }, '14 yes/no answers'));
	const cnt = s('text', { x: 430, y: 122, 'text-anchor': 'middle', fill: TH.text, 'font-size': 13 }, '');
	svg.append(cnt);
	const arrow = s('path', { d: 'M 430 140 L 430 176', stroke: '#d98f12', 'stroke-width': 2.4, fill: 'none', 'marker-end': 'url(#arr)' });
	svg.append(s('defs', null, s('marker', { id: 'arr', markerWidth: 8, markerHeight: 8, refX: 6, refY: 4, orient: 'auto' }, s('path', { d: 'M0,0 L8,4 L0,8 z', fill: '#d98f12' }))));
	svg.append(arrow);
	const box = s('rect', { x: 352, y: 182, width: 156, height: 70, rx: 12, fill: TH.boxFill, stroke: '#d98f12', 'stroke-width': 1.6 });
	svg.append(box);
	svg.append(s('text', { x: 430, y: 202, 'text-anchor': 'middle', fill: TH.muted, 'font-size': 11.5 }, 'one of 22 roles'));
	const role = s('text', { x: 430, y: 228, 'text-anchor': 'middle', fill: TH.text, 'font-size': 13, 'font-weight': 700 }, '');
	const role2 = s('text', { x: 430, y: 244, 'text-anchor': 'middle', fill: TH.text, 'font-size': 11 }, '');
	svg.append(role, role2);
	// the whole-map passes: a band that sweeps across
	const band = s('rect', { x: -60, y: 24, width: 50, height: 290, fill: 'url(#bandg)', opacity: 0 });
	svg.append(s('defs', null, s('linearGradient', { id: 'bandg', x1: 0, x2: 1, y1: 0, y2: 0 },
		s('stop', { offset: 0, 'stop-color': '#f2b24a', 'stop-opacity': 0 }), s('stop', { offset: 0.5, 'stop-color': '#f2b24a', 'stop-opacity': 0.55 }), s('stop', { offset: 1, 'stop-color': '#f2b24a', 'stop-opacity': 0 }))));
	svg.append(band);
	const passes = s('text', { x: 14, y: 366, fill: TH.gmDark, 'font-size': 13 }, '');
	svg.append(passes);
	const passNames = ['sea flood fill: courtyards, gate passages', 'walk areas: one battlemented walk per touching tops', 'stairs and arches: paired across blocks', 'prop solver: windows, shields, chimneys...'];
	// a different outcome each time round: its smallest neighbourhood is lit bit by bit
	const picks = [1, 2, 3, 4, 7, 8, 10, 11].filter(i => i < L.outcomes.length);
	const order = [];
	for (let b = 0; b < 14; b++) order.push(b);
	let lastName = '';
	runWhenVisible(svg, t => {
		const loop = Math.floor(t / 9);
		const outcome = L.outcomes[picks[loop % picks.length]];
		const pat = outcome.rep;
		const u = t % 9;
		const lit = Math.floor(clamp((u - 0.4) / 3.2, 0, 1) * 14.001);
		let bits = 0;
		for (let i = 0; i < lit; i++) bits |= pat & (1 << order[i]);
		pv.setBits(bits);
		cnt.textContent = lit + ' of 14 read';
		const showRole = u > 3.9 && u < 8.4;
		arrow.setAttribute('opacity', u > 3.6 && u < 8.4 ? 1 : 0.15);
		box.setAttribute('stroke-opacity', showRole ? 1 : 0.25);
		const nm = describe(outcome.sig).title;
		role.textContent = showRole ? nm.split(',')[0].replace('Covered by a block above', 'Covered') : '';
		role2.textContent = showRole && nm.includes(',') ? nm.split(',').slice(1).join(',').trim() : '';
		// the band sweeps once the answers are in
		const bu = (u - 5.2) / 3.0;
		band.setAttribute('opacity', bu > 0 && bu < 1 ? 1 : 0);
		band.setAttribute('x', -60 + 580 * clamp(bu, 0, 1));
		const pi = bu > 0 ? Math.min(3, Math.floor(bu * 4)) : -1;
		const name = pi >= 0 ? 'then the whole map: ' + passNames[pi] : '';
		if (name !== lastName) { passes.textContent = name; lastName = name; }
		if (u < 0.4) { pv.setBits(0); }
	});
}

/* --- the hero's background: an irregular grid with clicks rippling through it --------------------------------------------- */

function initHeroBg() {
	const cv = $('#bgfx');
	if (!cv) return;
	const ctx = cv.getContext('2d');
	let W = 0, H = 0, G = null;
	const clicks = [];
	function resize() {
		const r = cv.getBoundingClientRect();
		W = cv.width = Math.max(300, Math.floor(r.width));
		H = cv.height = Math.max(200, Math.floor(r.height));
		const dx = 62, dy = 54;
		G = tsGrid(Math.ceil(W / dx) + 2, Math.ceil(H / dy) + 2, -dx, -dy, dx, dy, 11);
	}
	resize();
	window.addEventListener('resize', resize);
	let next = 0.5;
	let vis = true;
	watch(cv, v => { vis = v; }, 0);
	Ticker.add((dt, t) => {
		if (!vis || reduceMotion) return;
		if (t > next) {
			clicks.push({ t0: t, x: Math.random() * W, y: Math.random() * H });
			next = t + 1.6 + Math.random() * 1.8;
		}
		while (clicks.length && t - clicks[0].t0 > 4) clicks.shift();
		ctx.clearRect(0, 0, W, H);
		ctx.lineWidth = 1;
		for (let r = 0; r < G.rows; r++) {
			for (let c = 0; c < G.cols; c++) {
				const p = G.V[r][c];
				let glow = 0;
				for (const k of clicks) {
					const d = Math.hypot(p[0] - k.x, p[1] - k.y);
					const front = (t - k.t0) * 150;
					glow = Math.max(glow, Math.exp(-Math.pow((d - front) / 34, 2)) * (1 - (t - k.t0) / 4));
				}
				const q1 = c + 1 < G.cols ? G.V[r][c + 1] : null, q2 = r + 1 < G.rows ? G.V[r + 1][c] : null;
				ctx.strokeStyle = glow > 0.02 ? 'rgba(242,178,74,' + (0.14 + glow * 0.6).toFixed(3) + ')' : 'rgba(50,80,110,.11)';
				ctx.beginPath();
				if (q1) { ctx.moveTo(p[0], p[1]); ctx.lineTo(q1[0], q1[1]); }
				if (q2) { ctx.moveTo(p[0], p[1]); ctx.lineTo(q2[0], q2[1]); }
				ctx.stroke();
				if (glow > 0.05) { ctx.fillStyle = 'rgba(242,178,74,' + (glow * 0.9).toFixed(3) + ')'; ctx.beginPath(); ctx.arc(p[0], p[1], 2 + glow * 2.5, 0, 7); ctx.fill(); }
			}
		}
	});
}
