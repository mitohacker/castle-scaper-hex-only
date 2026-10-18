'use strict';
/* The numbers, drawn: the hero, the random-castle statistics, the plan maps, the click ripple, the landscape matrix and the levers. */

const KIND_ORDER = ['walk', 'tower', 'battle', 'cottage', 'flat'];

function topCounts(T) {
	const t = (T.castle.tallies && T.castle.tallies.top) || {};
	const rows = KIND_ORDER.map(k => [k, t[k] || 0]);
	const total = rows.reduce((a, r) => a + r[1], 0);
	return { rows, total, walkPct: total ? 100 * (t.walk || 0) / total : 0 };
}

/* --- hero ------------------------------------------------------------------------------------------------------------- */

function initHero() {
	const C = DATA.combos, TS = DATA.townscaper;
	if (!C || !TS || !C.exh) { $('#funnels').append(h('div', { class: 'err' }, 'No data yet: run tools/combo_probe.gd, then tools/build_viewer_data.py.')); return; }
	const E = C.exh.k1;
	const lib = TS.library;
	const tsKeys = lib ? lib.keys : TS.total_keys, tsOrbits = lib ? lib.keys_orbits : TS.total_orbits;
	const maxV = Math.max(E.raw, tsKeys);
	const wOf = v => 30 + 70 * Math.log(v) / Math.log(maxV);
	const mk = (cls, title, steps) => {
		const bars = steps.map(st => {
			const b = h('b', null, '0');
			const bar = h('div', { class: 'fbar' }, b, h('span', null, st[1]));
			return { bar, b, v: st[0], w: wOf(st[0]) };
		});
		const el = h('div', { class: 'funnel ' + cls + ' rv' }, h('h3', null, title), bars.map(x => h('div', { class: 'fstep' }, x.bar)));
		onceVisible(el, () => bars.forEach((x, i) => setTimeout(() => { x.bar.style.width = x.w.toFixed(1) + '%'; countUp(x.b, x.v, 1300); }, reduceMotion ? 0 : 150 + i * 330)), 0.3);
		return el;
	};
	const shapes = Math.max.apply(null, TS.layers.map(l => l.shapes));
	const f1 = mk('ts', 'Townscaper', [[tsKeys, 'corner keys in its lookup'], [tsOrbits, 'distinct, turned and mirrored'], [shapes, 'plain filled / empty shapes']]);
	const f2 = mk('gm', 'This game', [[E.raw, 'neighbour patterns round one block, one storey'], [E.classes, 'distinct, turned and mirrored'], [E.outcomes.length, 'things a block becomes']]);
	f1.append(h('div', { class: 'note' }, lib ? 'Counted in the game\u2019s own library file, which also holds ' + fmt(lib.modules) + ' modules (pieces) and ' + fmt(lib.decor_modules) + ' decor modules.' : 'Counted from the corner-key rules.'));
	f2.append(h('div', { class: 'note' }, 'Built and classified by the game’s own rules, every one of them.'));
	$('#funnels').append(f1, f2);
	const tc = topCounts(C);
	const stats = [[tc.walkPct.toFixed(0) + '%', 'of the tops in real castles are the same battlemented wall walk'], [C.ripple.mean_struct.toFixed(1), 'other blocks change shape when you click once (Townscaper re-keys 8 cells)'], ['21 vs 3', 'pairs of types that react to each other (landscape layer vs Townscaper)']];
	stats.forEach(st => $('#stats').append(h('div', { class: 'stat rv' }, h('b', null, st[0]), h('span', null, st[1]))));
}

/* --- head to head: castle and ocean only --------------------------------------------------------------------------------- */

function initHeadToHead() {
	const C = DATA.combos, TS = DATA.townscaper, lib = TS && TS.library;
	const host = $('#hh');
	if (!host || !C || !C.exh || !lib) { if (host) host.append(h('div', { class: 'err' }, 'Needs viewer/data/townscaper_library.json (townscaper-re/tools/library_stats.py --json) and combos.json.')); return; }
	const E = C.exh, K = C.castle;
	const gm = {
		classes: E.k1.classes + E.k0.classes, raw: E.k1.raw + E.k0.raw,
		struct: K.distinct.structural, pieces: K.pieces.observed, piecesEst: K.pieces.chao1, looks: K.distinct.full, looksEst: K.chao1,
	};
	const propKinds = Object.keys((K.tallies && K.tallies.prop) || {}).length;
	const logw = v => Math.max(8, 100 * Math.log10(Math.max(v, 1)) / 4.0);
	const line = (cls, who, v, big, small) => {
		const b = h('div', { class: 'hhbar' }, h('b', null, big), h('span', null, small));
		return { el: h('div', { class: 'hhline ' + cls }, h('div', { class: 'who' }, who), b), bar: b, w: logw(v) };
	};
	const rows = [
		['What the rules read: the situations they tell apart',
			line('ts', 'Townscaper', lib.keys, fmt(lib.keys), 'corner keys (' + fmt(lib.keys_orbits) + ' turned / mirrored)'),
			line('gm', 'This game', gm.classes, fmt(gm.classes), 'neighbourhood classes (from ' + fmt(gm.raw) + ' patterns)'),
			'A Townscaper cell reads its 8 corners; a block here answers 14 yes/no questions about its neighbours (9 on the ground floor).'],
		['What the arrangement of blocks decides: the pieces it chooses between',
			line('ts', 'Townscaper', lib.modules, fmt(lib.modules), 'modules (' + fmt(lib.modules_distinct_mesh_sets) + ' distinct shapes)'),
			line('gm', 'This game', gm.struct, fmt(gm.struct), 'structural outcomes: arches, corbels, pillars, stairs, towers, walks, cottages, flat tops'),
			'Townscaper picks one of about ' + Math.round(lib.candidates_per_key_mean) + ' candidate pieces per key (' + fmt(lib.candidate_pairs) + ' candidates in all).'],
		['Finished building pieces: with roofs, doors and windows',
			line('ts', 'Townscaper', lib.modules, fmt(lib.modules), 'modules: each already has its windows, doors and roofs'),
			line('gm', 'This game', gm.pieces, '≈' + fmt(gm.piecesEst), 'distinct shape + roof + openings (' + fmt(gm.pieces) + ' seen)'),
			'Here the roof tile or slate, the openings and the cone or battlement top are chosen by a hash of the grid point, not by the neighbours.'],
		['Decoration on top',
			line('ts', 'Townscaper', lib.decor_modules, fmt(lib.decor_modules), 'decor modules, plus props on ' + fmt(lib.modules_with_props) + ' modules'),
			line('gm', 'This game', propKinds, String(propKinds), 'prop kinds: window frames, shutters, flower boxes, chimneys, banners, shields, torches...'),
			'Both place decoration greedily so that nothing overlaps. Mixed with the random choices above this game shows about ' + fmt(gm.looksEst) + ' distinct looks (' + fmt(gm.looks) +
				' seen); Townscaper\u2019s total with decor and props is not counted here.'],
	];
	for (const [title, a, b, note] of rows) {
		host.append(h('div', { class: 'hhrow rv' }, h('h3', null, title), a.el, b.el, h('p', { class: 'hhnote' }, note)));
		onceVisible(a.el, () => { a.bar.style.width = a.w.toFixed(1) + '%'; setTimeout(() => { b.bar.style.width = b.w.toFixed(1) + '%'; }, 250); }, 0.4);
	}
	const r1 = lib.modules / gm.struct, r2 = lib.modules / gm.piecesEst;
	$('#hhNote').innerHTML = '<b>In short:</b> Townscaper has about <b class="ts">' + Math.round(r2) + ' times</b> as many finished pieces as this game\u2019s castle and ocean, and about <b class="ts">' +
		Math.round(r1) + ' times</b> as many that are chosen by what you build. Counting every random choice of window, door, roof and prop this game reaches about ' + fmt(gm.looksEst) +
		' looks, but those do not respond to your arrangement. Both counts are of kinds, not of the towns you can build: those are astronomically many in both.';
}

/* --- real castles -------------------------------------------------------------------------------------------------------- */

function initCastles() {
	const C = DATA.combos && DATA.combos.castle;
	if (!C) return;
	const tc = topCounts(DATA.combos);
	const tl = C.tallies;
	$('#castleLead').textContent = 'I built ' + C.random_towns + ' random castles of ' + C.clicks + ' clicks and the ' + C.starters + ' starters: ' + fmt(C.blocks) + ' blocks. For each block I recorded what the rules made of it.';
	const names = { walk: 'Wall walk', tower: 'Tower, cone roof', battle: 'Tower, battlements', cottage: 'Cottage roof', flat: 'Flat top' };
	bars($('#barsTop'), tc.rows.map(r => ({ label: names[r[0]], value: r[1], text: fmt(r[1]) + ' · ' + pct(r[1], tc.total, 1), color: TOP_COL[r[0]] })), { max: tc.total });
	const sup = tl.support || {};
	const supTotal = (sup.corbel || 0) + (sup.arch || 0) + (sup.pillar || 0);
	bars($('#barsSup'), [['corbel', 'Corbels'], ['arch', 'Arch'], ['pillar', 'Pillar']].map(([k, n]) => ({ label: n, value: sup[k] || 0, text: fmt(sup[k] || 0) + ' · ' + pct(sup[k] || 0, supTotal, 0), color: SUP_COL[k] })), { max: supTotal });
	const op = tl.opening || {};
	const pr = tl.prop || {};
	const opHost = $('#barsOp');
	opHost.classList.remove('bars');
	opHost.innerHTML = '';
	const a = h('div'), b = h('div', { style: { marginTop: '12px' } });
	opHost.append(a, b);
	bars(a, ['slit', 'window', 'door'].map(k => ({ label: k, value: op[k] || 0, color: 'var(--cottage)' })), {});
	const pkeys = Object.keys(pr).sort((x, y) => pr[y] - pr[x]);
	bars(b, pkeys.map(k => ({ label: k, value: pr[k], color: '#8fa2bb' })), {});
	// the curve
	drawCurve($('#curve'), C);
	legend($('#curveLegend'), [['#e39b1f', 'full looks (roof colour, openings, props)'], ['#b58cf0', 'neighbourhoods seen'], ['#ef6a6a', 'structural outcomes']]);
	const F = C.fanout_full, S = C.fanout_struct;
	const L = DATA.combos.landscape;
	bars($('#barsDecide'), [
		{ label: 'structural', value: S.modal_pct, text: S.modal_pct + '%', color: 'var(--gm)' },
		{ label: 'full look', value: F.modal_pct, text: F.modal_pct + '%', color: '#b58cf0' },
		{ label: 'landscape', value: L ? L.fanout.modal_pct : 0, text: L ? L.fanout.modal_pct + '%' : '-', color: '#58b89b' },
	], { max: 100 });
	$('#decideNote').textContent = 'For each neighbourhood: how often its commonest outcome is what the block really shows. The shape of a block follows its neighbours (' + S.modal_pct +
		'%); most of the rest of the look is hash luck: ' + fmt(C.once) + ' of ' + fmt(C.distinct.full) + ' full looks were seen only once, and about ' + fmt(C.chao1) + ' exist in all.';
	new Turntable($('#castleTT'), (DATA.renders.real || {}).castle_castle);
	initPlans();
}

function drawCurve(svg, C) {
	const W = 560, H = 300, L = 46, B = 34, T = 14, R = 70;
	const cur = C.curve;
	const maxX = cur[cur.length - 1][0];
	const X = v => L + (W - L - R) * v / maxX;
	const lo = Math.log10(10), hi = Math.log10(2000);
	const Y = v => T + (H - T - B) * (1 - (Math.log10(Math.max(v, 10)) - lo) / (hi - lo));
	svg.innerHTML = '';
	for (const g of [10, 100, 1000]) {
		svg.append(s('line', { x1: L, x2: W - R, y1: Y(g), y2: Y(g), stroke: TH.grid, 'stroke-width': 1 }));
		svg.append(s('text', { x: L - 8, y: Y(g) + 4, 'text-anchor': 'end', fill: TH.muted, 'font-size': 11 }, fmt(g)));
	}
	for (let i = 0; i <= 3; i++) {
		const v = Math.round(maxX * i / 3 / 100) * 100;
		svg.append(s('text', { x: X(v), y: H - 12, 'text-anchor': 'middle', fill: TH.muted, 'font-size': 11 }, fmt(v)));
	}
	svg.append(s('text', { x: (L + W - R) / 2, y: H - 0, 'text-anchor': 'middle', fill: TH.muted, 'font-size': 11 }, 'blocks looked at'));
	const series = [[1, '#e39b1f'], [3, '#9a72e8'], [2, '#e0504f']];
	const paths = [];
	for (const [idx, col] of series) {
		const pts = cur.map(c => X(c[0]).toFixed(1) + ',' + Y(c[idx]).toFixed(1));
		const p = s('polyline', { points: pts.join(' '), fill: 'none', stroke: col, 'stroke-width': 2.6, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' });
		svg.append(p);
		const last = cur[cur.length - 1];
		svg.append(s('text', { x: X(last[0]) + 7, y: Y(last[idx]) + 4, fill: col, 'font-size': 12, 'font-weight': 700 }, fmt(last[idx])));
		paths.push(p);
	}
	onceVisible(svg, () => paths.forEach((p, i) => {
		if (reduceMotion) return;
		const len = p.getTotalLength();
		p.style.strokeDasharray = len;
		p.style.strokeDashoffset = len;
		p.getBoundingClientRect();
		p.style.transition = 'stroke-dashoffset 1.6s ease ' + (i * 0.25) + 's';
		p.style.strokeDashoffset = 0;
	}), 0.3);
}

/* --- plan maps ------------------------------------------------------------------------------------------------------------- */

function initPlans() {
	const plans = DATA.combos.plans;
	if (!plans || !plans.length) return;
	const svg = $('#planMap');
	const W = 640, H = 520;
	const names = ['Castle starter', 'Random castle', 'Village starter'];
	let cur = 0, els = [], P = plans[0], maxTop = 0, level = 0, timer = 0;
	const slider = $('#planLevel');
	const seg = $('#planSeg');
	names.forEach((n, i) => seg.append(h('button', { class: 'btn' + (i === 0 ? ' on' : ''), onclick: ev => { $$('button', seg).forEach(b => b.classList.remove('on')); ev.currentTarget.classList.add('on'); select(i); } }, n)));
	function colourOf(c) {
		const lv = c.levels[c.top];
		const kind = lv ? lv[2] : '';
		if (level < c.top) return 'hsl(214,14%,' + Math.max(52, 82 - 6 * Math.min(level, 6)) + '%)';
		return kind ? (TOP_COL[kind] || '#8a96a8') : '#8a96a8';
	}
	function select(i) {
		cur = i;
		P = plans[i];
		maxTop = Math.max.apply(null, P.columns.map(c => c.top));
		slider.max = maxTop;
		level = maxTop;
		slider.value = level;
		draw();
		const tops = P.tops || {};
		legend($('#planLegend'), KIND_ORDER.filter(k => tops[k]).map(k => [TOP_COL[k], TOP_NAME[k] + ' ' + tops[k]]).concat([[TH.court, 'courtyard'], ['hsl(214,14%,64%)', 'lower storeys']]));
	}
	function draw() {
		svg.innerHTML = '';
		svg.append(s('rect', { x: 0, y: 0, width: W, height: H, fill: TH.sea }));
		const polys = P.columns.map(c => c.poly).concat(P.courts.map(c => c.poly));
		const tx = fitTransform(polys, W, H, 28);
		for (const c of P.courts) svg.append(s('polygon', { points: polyPoints(c.poly, tx), fill: TH.court, stroke: TH.courtStroke, 'stroke-width': 1 }));
		els = P.columns.map(c => {
			const el = s('polygon', { points: polyPoints(c.poly, tx), fill: colourOf(c), stroke: c.round ? TH.ink : '#ffffff', 'stroke-width': c.round ? 1.8 : 1.2, style: 'transition: fill .5s' },
				s('title', null, 'top storey ' + c.top + (c.levels[c.top] && c.levels[c.top][2] ? ': ' + TOP_NAME[c.levels[c.top][2]] : '') + (c.round ? ' (round column)' : '')));
			svg.append(el);
			return el;
		});
		paint();
	}
	function paint() {
		P.columns.forEach((c, i) => {
			els[i].setAttribute('fill', colourOf(c));
			els[i].style.opacity = level < 0 ? 0 : 1;
		});
		$('#planLevelV').textContent = level;
	}
	slider.oninput = () => { stopPlay(); level = +slider.value; paint(); };
	function stopPlay() { if (timer) { clearInterval(timer); timer = 0; $('#planPlay').textContent = '▶ Grow'; } }
	$('#planPlay').onclick = () => {
		if (timer) { stopPlay(); return; }
		$('#planPlay').textContent = '❚❚ Stop';
		level = 0; slider.value = 0; paint();
		timer = setInterval(() => {
			if (level >= maxTop) { stopPlay(); return; }
			level++; slider.value = level; paint();
		}, 900);
	};
	select(0);
}

/* --- ripple ------------------------------------------------------------------------------------------------------------------ */

function initRipple() {
	const C = DATA.combos && DATA.combos.ripple;
	if (!C) return;
	$('#rippleLead').textContent = 'I made ' + C.clicks + ' random clicks on ' + C.towns + ' random castles and compared every other block before and after. On average ' + C.mean_struct.toFixed(1) +
		' other blocks change shape (' + C.zero_struct_pct.toFixed(0) + '% of clicks change none) and ' + C.mean_full.toFixed(1) + ' change their look; the farthest change was ' + C.reach_max.toFixed(0) + ' m away (a cell is about 4 m).';
	const R = DATA.renders.real || {};
	const cases = C.cases;
	const canvas = $('#rpCanvas'), svg = $('#rpSvg'), list = $('#rpList'), seg = $('#rpSeg');
	const ctx = canvas.getContext('2d');
	let cur = 0, rec = null, img = null, t0 = 0, marks = [], hot = -1, playing = true, vis = false;
	function label(c, i) { return 'Case ' + (i + 1) + ': ' + (c.cs ? c.cs + ' block' + (c.cs > 1 ? 's' : '') + ' change shape' : 'no shape changes') + (c.cf > c.cs ? ', ' + (c.cf - c.cs) + ' look' + (c.cf - c.cs > 1 ? 's' : '') : ''); }
	cases.forEach((c, i) => seg.append(h('button', { class: 'btn' + (i === 0 ? ' on' : ''), onclick: ev => { $$('button', seg).forEach(b => b.classList.remove('on')); ev.currentTarget.classList.add('on'); select(i); } }, label(c, i))));
	function select(i) {
		cur = i;
		const c = cases[i];
		rec = R['rip_' + i];
		img = null;
		const looks = c.cf - c.cs;
		$('#rpTag').textContent = (c.cs ? c.cs + ' shape' + (c.cs > 1 ? 's' : '') : '') + (c.cs && looks ? ' + ' : '') + (looks ? looks + ' look' + (looks > 1 ? 's' : '') : '') + ' changed';
		list.innerHTML = '';
		list.append(h('li', { class: 'click' }, 'You put one block down here.'));
		marks = [];
		svg.innerHTML = '';
		if (!rec) { list.append(h('li', null, 'No render for this case.')); return; }
		svg.setAttribute('viewBox', '0 0 ' + rec.tw + ' ' + rec.th);
		canvas.width = rec.tw; canvas.height = rec.th;
		rec.marks.forEach((m, j) => {
			const kind = m[0];
			const x = m[m.length - 2], y = m[m.length - 1];
			const col = kind === 'click' ? '#f2a526' : kind === 'struct' ? '#e0504f' : '#2aa9bb';
			const g = s('g', { opacity: 0 });
			const circ = s('circle', { cx: x, cy: y, r: 24, fill: 'none', stroke: col, 'stroke-width': 3, 'stroke-dasharray': kind === 'look' ? '5 4' : '' });
			g.append(circ);
			if (kind === 'click') g.append(s('path', { d: 'M ' + x + ' ' + y + ' l 0 26 l 7 -6 l 5 11 l 5 -2 l -5 -11 l 9 -1 z', fill: '#fff', stroke: '#222', 'stroke-width': 1.2, transform: 'translate(8 -2)' }));
			else {
				g.append(s('circle', { cx: x + 22, cy: y - 22, r: 11, fill: col }));
				g.append(s('text', { x: x + 22, y: y - 17.5, 'text-anchor': 'middle', fill: '#fff', 'font-size': 13, 'font-weight': 700 }, j));
			}
			svg.append(g);
			marks.push({ g, circ, kind, j, delay: kind === 'click' ? 0.9 : 3.0 + 0.28 * (j - 1) });
			if (kind === 'struct') list.append(h('li', { onmouseenter: () => { hot = j; }, onmouseleave: () => { hot = -1; } }, h('b', null, j + '. '), m[1] + ' → ' + m[2]));
			else if (kind === 'look') list.append(h('li', { class: 'look', onmouseenter: () => { hot = j; }, onmouseleave: () => { hot = -1; } }, h('b', null, j + '. '), 'same shape, but its roof colour, openings or props changed'));
		});
		if (rec) loadSheet(rec.file).then(im => { if (R['rip_' + i] === rec) img = im; });
		t0 = performance.now() / 1000;
	}
	function draw(t) {
		if (!img || !rec) return;
		const u = t - t0;
		let f = 0;
		if (u > 1.5 && u < 2.5) f = 1 + Math.min(rec.pops - 1, Math.floor((u - 1.5) / 1.0 * rec.pops));
		else if (u >= 2.5) f = rec.pops + 1;
		ctx.drawImage(img, (f % rec.cols) * rec.tw, Math.floor(f / rec.cols) * rec.th, rec.tw, rec.th, 0, 0, rec.tw, rec.th);
		for (const m of marks) {
			let a = 0;
			if (m.kind === 'click') a = smooth(m.delay - 0.2, m.delay, u) * (1 - smooth(2.2, 2.6, u));
			else a = smooth(m.delay, m.delay + 0.3, u);
			m.g.setAttribute('opacity', a.toFixed(2));
			const pulse = 1 + 0.12 * Math.sin(t * 5 + m.j) + (hot === m.j ? 0.35 : 0);
			m.circ.setAttribute('r', (m.kind === 'click' ? 16 + 14 * smooth(m.delay, m.delay + 0.6, u) : 24 * pulse).toFixed(1));
		}
	}
	watch(canvas, v => { vis = v; }, 0.1);
	Ticker.add((dt, t) => {
		if (!vis || !rec) return;
		const u = t - t0;
		const total = 3.0 + 0.28 * marks.length + 3.2;
		if (playing && u > total) t0 = t;
		draw(t);
	});
	$('#rpPlay').onclick = () => { t0 = performance.now() / 1000; };
	select(0);
	// the histogram
	const hs = C.hist_struct, hf = C.hist_full;
	const svgH = $('#rpHist');
	const W = 520, H = 190, L = 34, B = 30, T = 16;
	const mx = Math.max.apply(null, hs.concat(hf));
	const bw = (W - L - 10) / 8;
	svgH.innerHTML = '';
	const rects = [];
	for (let i = 0; i < 8; i++) {
		const x = L + i * bw;
		[[hs[i], '#e0504f', 0], [hf[i], '#e39b1f', 1]].forEach(([v, col, k]) => {
			const hh = (H - B - T) * v / mx;
			const r = s('rect', { x: x + 6 + k * (bw - 12) / 2, y: H - B, width: (bw - 12) / 2 - 2, height: 0, fill: col, rx: 3 });
			svgH.append(r);
			rects.push([r, hh, v]);
			svgH.append(s('text', { x: x + 6 + k * (bw - 12) / 2 + (bw - 12) / 4 - 1, y: H - B - hh - 4, 'text-anchor': 'middle', fill: TH.muted, 'font-size': 10 }, v || ''));
		});
		svgH.append(s('text', { x: x + bw / 2, y: H - 10, 'text-anchor': 'middle', fill: TH.muted, 'font-size': 11 }, i === 7 ? '7+' : i));
	}
	svgH.append(s('text', { x: W - 4, y: 12, 'text-anchor': 'end', fill: TH.muted, 'font-size': 11 }, 'clicks, by how many other blocks changed'));
	onceVisible(svgH, () => rects.forEach(([r, hh], i) => { r.style.transition = 'all 1s ease ' + (i * 40) + 'ms'; r.setAttribute('y', H - B - hh); r.setAttribute('height', hh); }), 0.3);
	svgH.parentNode.append(h('div', { class: 'legend' }, h('span', null, h('i', { style: { background: '#e0504f' } }), 'shape changed'), h('span', null, h('i', { style: { background: '#e39b1f' } }), 'any look changed')));
}

/* --- landscape ---------------------------------------------------------------------------------------------------------------- */

const LTYPES = ['Castle', 'Land', 'Road', 'Trees', 'Rocks', 'Mountain', 'Sea'];
const LRULES = [
	[0, 0, 'Block with block', 'The 34 structural outcomes of the castle rules: wall walks, towers, cottages, arches, corbels, pillars, stairs.', null],
	[1, 0, 'Castle × Land', 'Land is flat at the castle’s floor: the terrain drops to castle level wherever castle land touches, and the rock skirt is left off there. A courtyard with land becomes a lawn.', 'garden'],
	[2, 0, 'Castle × Road', 'A road column beside a castle block runs up to its door; its surface becomes cobbles and the door gets a paved apron.', 'road_to_door'],
	[3, 0, 'Castle × Trees', 'A tree beside the castle (and no road) becomes an orchard tree with blossom. Trees in a courtyard make an orchard garden.', 'orchard'],
	[4, 0, 'Castle × Rocks', 'Against the castle 55% of the boulders become cut blocks: a quarry.', 'quarry'],
	[5, 0, 'Castle × Mountain', 'A mountain slope falls to the castle’s floor level at the boundary, so a castle can sit against a mountain.', 'flatten'],
	[6, 0, 'Castle × Sea', 'The sea decides the plinth: ground blocks stand on a 0.6 m land plinth with a rocky skirt and foam; an empty cell the sea cannot reach (flood fill from the border) becomes a courtyard; a cell under a bridging block becomes a gate passage.', null],
	[1, 1, 'Land', 'Plain land is flat meadow. It is the base the other types build on.', null],
	[2, 1, 'Land × Road', 'A road on plain land is packed dirt with ruts and a grassy verge; on a slope it turns to gravel.', null],
	[3, 1, 'Land × Trees', 'One level a tree, two a grove with bushes, three a forest: oaks, with pines mixed in.', null],
	[4, 1, 'Land × Rocks', 'Meadow beside rock gets pebbles and a boulder fallen from it.', null],
	[5, 1, 'Land × Mountain', 'Meadow turns to tundra high up, bare rock where it is steep, scree between, snow above 11 m.', null],
	[6, 1, 'Land × Sea', 'Where land meets water the bank is a beach or a cliff, with a skirt that reaches below the surface.', null],
	[2, 2, 'Road', 'What one road click makes depends on how many road neighbours it has: none a plaza, one a dead end, two a bend, three or more a junction with a signpost.', 'junction'],
	[3, 2, 'Road × Trees', 'No tree grows in a road and a road cannot go through trees; a lone tree beside a road becomes a poplar lining it.', 'poplar'],
	[4, 2, 'Road × Rocks', 'Beside rock the road turns to gravel, and a retaining wall of cut blocks appears where a rock column stands higher.', null],
	[5, 2, 'Road × Mountain', 'Climbing a mountain the road is gravel and the shader cuts steps into it.', 'gravel_climb'],
	[6, 2, 'Road × Sea', 'A road with no earth under it is a jetty (one neighbour) or a bridge (two): a stone hump-back where it meets land, a timber trestle where it meets more bridge.', 'bridge'],
	[3, 3, 'Trees', 'A tree, a grove or a forest by level and by tree neighbours.', null],
	[4, 3, 'Trees × Rocks', 'A tree beside rock is a pine rather than an oak.', null],
	[5, 3, 'Trees × Mountain', 'Pines, smaller the higher they stand, snow on the high ones, none above the tree line (8.5 m).', 'pine_snow'],
	[6, 3, 'Trees × Sea', 'A tree with water on two sides on low ground is a weeping willow.', 'willow'],
	[4, 4, 'Rocks', 'Rock levels stack up to six; the higher the column, the more boulders.', null],
	[5, 4, 'Rocks × Mountain', 'Rock and mountain levels stack in the order clicked; a rock keeps a plateau and ends in a cliff, a mountain falls away smoothly.', null],
	[6, 4, 'Rocks × Sea', 'A rock column at the coast ends in a cliff rather than a beach.', null],
	[5, 5, 'Mountain', 'Mountain levels stack up to six, 3.6 m each; scree and snow appear with height.', null],
	[6, 5, 'Mountain × Sea', 'A mountain at the coast drops into the sea with a bank down to the water.', null],
	[6, 6, 'Sea', 'The sea is the empty ground everything stands in.', null],
];

function initLandscape() {
	const L = DATA.combos && DATA.combos.landscape;
	const svg = $('#matrix');
	const R = (DATA.renders && DATA.renders.real) || {};
	const x0 = 112, y0 = 92, cw = 56, chh = 50;
	const cells = {};
	let sel = null;
	LTYPES.forEach((n, j) => {
		const t = s('text', { x: x0 + j * cw + cw / 2 + 4, y: y0 - 10, fill: TH.muted, 'font-size': 13, transform: 'rotate(-38 ' + (x0 + j * cw + cw / 2) + ' ' + (y0 - 10) + ')' }, n);
		svg.append(t);
	});
	LTYPES.forEach((n, i) => svg.append(s('text', { x: x0 - 10, y: y0 + i * chh + chh / 2 + 5, 'text-anchor': 'end', fill: TH.muted, 'font-size': 13 }, n)));
	const rulebox = $('#ruleBox');
	const tt = { el: null };
	function show(rule) {
		sel = rule;
		Object.values(cells).forEach(c => c.classList.remove('sel'));
		rulebox.innerHTML = '';
		rulebox.append(h('h3', null, rule[2]), h('p', { class: 'muted' }, rule[3]));
		const rec = rule[4] ? R['spot_' + rule[4]] : null;
		if (rec) { const host = h('div'); rulebox.append(host); new Turntable(host, rec); }
		else rulebox.append(h('p', { class: 'dim' }, rule[4] ? 'Picture not rendered.' : 'This one has no close-up: it works through the shape of the ground itself.'));
		rulebox.append(h('p', { class: 'ts', style: { margin: '10px 0 0', fontSize: '.86rem' } }, 'Townscaper: no equivalent — it has blocks, ground and water only.'));
		const c = cells[rule[1] + ',' + rule[0]];
		if (c) c.classList.add('sel');
	}
	for (const r of LRULES) {
		const j = r[1], i = r[0];
		const cx = x0 + j * cw + cw / 2, cy = y0 + i * chh + chh / 2;
		const g = s('g', { class: 'cell', style: 'cursor:pointer' });
		const diag = i === j;
		g.append(s('rect', { x: cx - cw / 2 + 3, y: cy - chh / 2 + 3, width: cw - 6, height: chh - 6, rx: 9, fill: diag ? '#f3f6fa' : '#e9eef4', stroke: '#c9d4e1' }));
		g.append(s('circle', { class: 'dot', cx, cy, r: diag ? 9 : 14, fill: diag ? 'none' : '#f2b24a', stroke: '#f2b24a', 'stroke-width': diag ? 2.2 : 0 }));
		g.addEventListener('click', () => show(r));
		g.addEventListener('mouseenter', () => { if (sel !== r) g.style.filter = 'brightness(1.3)'; });
		g.addEventListener('mouseleave', () => { g.style.filter = ''; });
		g.append(s('title', null, r[2]));
		svg.append(g);
		cells[j + ',' + i] = g;
	}
	// the dots pop in one after another
	$$('.cell', svg).forEach((g, k) => g.querySelector('circle').style.setProperty('--d', (k * 0.06).toFixed(2) + 's'));
	onceVisible(svg, () => svg.classList.add('go'), 0.3);
	svg.append(s('text', { x: x0, y: 462, fill: TH.muted, 'font-size': 12 }, 'each dot: a rule in the code that reads the other type (the ring on the diagonal: how one type reads itself)'));
	show(LRULES[3]);
	// the numbers
	const ls = $('#landStats');
	if (L) {
		const tl = L.tallies || {};
		const mk = (title, big, text, rows, color) => {
			const bx = h('div');
			ls.append(h('div', { class: 'card rv' }, h('h3', null, title), h('div', { class: 'stat', style: { border: 0, padding: '0 0 10px', background: 'none' } }, h('b', null, big), h('span', null, text)), bx));
			bars(bx, rows, { color });
		};
		const top = (o, n) => Object.keys(o || {}).sort((a, b) => o[b] - o[a]).slice(0, n).map(k => ({ label: k, value: o[k] }));
		mk('Column states', fmt(L.states_possible), 'a column can be in about this many states (heights × trees × road); ' + L.states_seen + ' showed up in random countries', top(tl.terrain, 4), '#58b89b');
		mk('Outcomes', L.outcomes, 'different column outcomes (tree species and level, rocks, road class, surface)', top(tl.species, 6), '#6fcf97');
		mk('Roads and rocks', Object.keys(tl.road || {}).length + ' + ' + Object.keys(tl.rockkind || {}).length, 'kinds of road (class and surface) and kinds of rock', top(tl.road, 6), '#e9b97a');
	}
	// the close-ups
	const spots = $('#spots');
	const SP = [['orchard', 'Castle × Trees', 'An orchard tree with blossom beside the walls.'], ['quarry', 'Castle × Rocks', 'Cut blocks among the boulders: a quarry.'], ['flatten', 'Castle × Mountain', 'The slope drops to the castle’s floor.'],
		['garden', 'Castle × Land', 'A lawn in the courtyard.'], ['road_to_door', 'Castle × Road', 'The road is cobbled and runs to the door.'], ['poplar', 'Road × Trees', 'A lone tree beside a road becomes a poplar.'],
		['willow', 'Trees × Sea', 'Water on two sides: a weeping willow.'], ['pine_snow', 'Trees × Mountain', 'Pines, with snow high up.'], ['bridge', 'Road × Sea', 'A stone hump-back, then a timber trestle.'],
		['jetty', 'Road × Sea', 'One neighbour only: a jetty with a lamp.'], ['junction', 'Road × Road', 'Three roads meet: a hub and a signpost.'], ['gravel_climb', 'Road × Mountain', 'Gravel, with steps cut where it climbs.']];
	for (const [k, t, d] of SP) {
		const host = h('div');
		spots.append(h('div', { class: 'gcard rv' }, host, h('h4', null, t), h('div', { class: 'meta' }, d)));
		new Turntable(host, R['spot_' + k], { hint: false });
	}
}

/* --- next --------------------------------------------------------------------------------------------------------------------- */

function initNext() {
	const C = DATA.combos, E = C && C.exh;
	if (!E) return;
	const tc = topCounts(C);
	const TS = DATA.townscaper;
	const bc = TS.layers[2].by_colours;
	const multi = Object.keys(bc).filter(k => +k >= 2).reduce((a, k) => a + bc[k], 0);
	const levers = [
		['1', 'The top', tc.walkPct.toFixed(0) + '% of tops are the same wall walk; only ' + KIND_ORDER.length + ' kinds of top exist.',
			'More kinds of top: gables, hips, terraces, pagodas, onion domes, chosen by the corner pattern. The roof engine that was built for the six building styles does exactly this.'],
		['2', 'The corners', fmt(E.k1.classes) + ' neighbourhoods fold into ' + E.k1.outcomes.length + ' outcomes (' + Math.round(E.k1.classes / E.k1.outcomes.length) + ' to 1).',
			'Let the rules read diagonal neighbours and the storey above the neighbours, so inner and outer corners, buttresses and step-backs become pieces.'],
		['3', 'Colour', Math.round(100 * multi / TS.layers[2].keys) + '% of Townscaper’s upper keys involve two or more colours; here colour never changes a shape.',
			'Let a colour boundary pick a piece: a string course, a change of material, a different cornice.'],
	];
	levers.forEach(l => $('#levers').append(h('div', { class: 'lever rv' }, h('div', { class: 'rank' }, l[0]), h('h3', null, l[1]), h('p', { class: 'ev' }, l[2]), h('p', { class: 'muted', style: { marginBottom: 0 } }, l[3]))));
	const types = [['Castle', true], ['House', false], ['Apartment', false], ['Chinese', false], ['Japanese', false], ['Fantasy', false], ['Village', false], ['Land', true], ['Road', true], ['Trees', true], ['Rocks', true], ['Mountains', true]];
	types.forEach(([n, w]) => $('#board').append(h('div', { class: 'bchip ' + (w ? 'wired' : 'todo') }, n, h('em', null, w ? 'has rules' : 'not wired'))));
}
