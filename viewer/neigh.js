'use strict';
/* This game's side: the exhaustive neighbourhood table (every arrangement of the blocks round one grid point, built and classified by the game's own rules),
   an explorer over it, and the gallery of the outcomes. Bit layout of a pattern (the same as tools/combo_probe.gd):
   storey 1  : side i has below = 1<<(3i), same = 1<<(3i+1), above = 1<<(3i+2); own column below = 1<<12, above = 1<<13.
   ground    : side i has same = 1<<(2i), above = 1<<(2i+1); own column above = 1<<8. */

const TOP_COL = { walk: 'var(--walk)', tower: 'var(--tower)', battle: 'var(--battle)', cottage: 'var(--cottage)', flat: 'var(--flat)', '-': 'var(--covered)' };
const SUP_COL = { arch: 'var(--arch)', corbel: 'var(--corbel)', pillar: 'var(--pillar)' };
const TOP_NAME = { walk: 'Wall walk', tower: 'Tower, cone roof', battle: 'Tower, battlements', cottage: 'Cottage roof', flat: 'Flat top', '-': 'Covered' };

function parseSig(sig) {
	const p = sig.split('.');
	const o = { round: p[0] === 'R' };
	for (const q of p.slice(1)) { const i = q.indexOf('='); o[q.slice(0, i)] = q.slice(i + 1); }
	o.top = o.top || '-';
	o.sup = o.sup || '-';
	o.corbels = o.sup.startsWith('corbel') ? +o.sup.slice(6) : 0;
	if (o.corbels) o.sup = 'corbel';
	return o;
}

/** A plain-words description of a structural outcome: a title, coloured tags and the reason. */
function describe(sig) {
	const o = parseSig(sig);
	let title = o.round ? 'Round ' + (o.top === '-' ? 'column body' : TOP_NAME[o.top].toLowerCase()) : (o.top === '-' ? 'Covered by a block above' : TOP_NAME[o.top]);
	if (o.sup === 'arch') title += ', on an arch';
	else if (o.sup === 'corbel') title += ', on corbels';
	else if (o.sup === 'pillar') title += ', on a pillar';
	if (o.st === '1') title += ', with stairs';
	const tags = [{ text: o.top === '-' ? 'covered' : TOP_NAME[o.top].toLowerCase(), color: TOP_COL[o.top] }];
	if (o.round) tags.push({ text: 'round', color: '#5f6f86' });
	if (o.sup === 'arch') tags.push({ text: 'arch', color: SUP_COL.arch });
	if (o.sup === 'corbel') tags.push({ text: o.corbels + ' corbelled side' + (o.corbels > 1 ? 's' : ''), color: SUP_COL.corbel });
	if (o.sup === 'pillar') tags.push({ text: 'pillar', color: SUP_COL.pillar });
	if (o.st === '1') tags.push({ text: 'stairs', color: 'var(--stairs)' });
	const why = [];
	if (o.top === 'walk') why.push('Its top touches another top on the same storey, so the tops join into one paved walk with battlements on every open edge.');
	if (o.top === 'tower') why.push('Nothing stands beside the column, so it is a free-standing tower. Most get a cone roof; the grid point decides.');
	if (o.top === 'battle') why.push('A free-standing tower whose top is a ring of battlements (28% of towers, chosen by the grid point).');
	if (o.top === 'cottage') why.push('A single block alone on the ground gets a pyramid roof and a chimney.');
	if (o.top === 'flat') why.push('A neighbour is higher (or the cell is not convex), so the top stays flat.');
	if (o.top === '-') why.push('Another block sits on top of this one, so it is only a body.');
	if (o.sup === 'arch') why.push('Nothing under it, but two neighbours on opposite sides have walls one storey down: the cell below is filled and an arch is cut through it.');
	if (o.sup === 'corbel') why.push('Nothing under it, but a wall one storey down stands on ' + (o.corbels > 1 ? o.corbels + ' sides' : 'one side') + ': the block overhangs it on stepped corbels.');
	if (o.sup === 'pillar') why.push('Nothing to rest on, so a pillar goes down to the next block or the land.');
	if (o.st === '1') why.push('A flight of stairs climbs to it from a lower walk or a courtyard.');
	if (o.round) why.push('The whole column is free-standing, so it is built round.');
	return { title, tags, why: why.join(' '), o };
}

function neighData() {
	const E = DATA.combos && DATA.combos.exh;
	if (!E) return null;
	const mk = L => {
		const map = new Map();
		const mult = new Map();
		L.canon.forEach((c, i) => { map.set(c, L.outcome[i]); mult.set(c, L.mult[i]); });
		return Object.assign({}, L, { map, multOf: mult });
	};
	return { cell: E.cell, k1: mk(E.k1), k0: mk(E.k0) };
}

function canonPattern(p, n, per) {
	const mask = (1 << per) - 1;
	const own = p >> (n * per);
	let best = -1;
	for (let mirror = 0; mirror < 2; mirror++) {
		for (let r = 0; r < n; r++) {
			let q = 0;
			for (let j = 0; j < n; j++) {
				const idx = mirror === 0 ? (r + j) % n : (((r - j) % n) + n) % n;
				q |= ((p >> (idx * per)) & mask) << (j * per);
			}
			q |= own << (n * per);
			if (best < 0 || q < best) best = q;
		}
	}
	return best;
}

/* --- the plan drawing: the real cell and its four neighbours, a stack of squares per neighbour ----------------------- */

class PlanView {
	constructor(svg, cell, o) {
		this.svg = svg;
		this.cell = cell;
		this.o = Object.assign({ interactive: false, mini: false, onToggle: null }, o || {});
		// turn the plan so that neighbour 0 is straight up: the cell then reads like a square with a neighbour on each side
		const pt = cell.pt, n0 = cell.nbrs[0];
		const delta = -Math.PI / 2 - Math.atan2(n0[1] - pt[1], n0[0] - pt[0]);
		const cs = Math.cos(delta), sn = Math.sin(delta);
		this.rot = p => [pt[0] + (p[0] - pt[0]) * cs - (p[1] - pt[1]) * sn, pt[1] + (p[0] - pt[0]) * sn + (p[1] - pt[1]) * cs];
		const polys = [cell.poly].concat(cell.nbr_polys).map(l => l.map(this.rot));
		const vb = svg.viewBox.baseVal;
		const fit = fitTransform(polys, vb.width, vb.height, this.o.mini ? 26 : 30);
		this.tx = p => fit(this.rot(p));
		this.txr = fit;
		this.level = 'k1';
		this.bits = 0;
		this.rects = [];
		this.build();
	}

	per() { return this.level === 'k1' ? 3 : 2; }

	build() {
		const svg = this.svg, mini = this.o.mini, tx = this.tx, cell = this.cell;
		svg.innerHTML = '';
		const n = cell.nbrs.length, per = this.per();
		const levels = this.level === 'k1' ? [['one storey down', '−1'], ['same storey', '0'], ['one storey up', '+1']] : [['same storey', '0'], ['one storey up', '+1']];
		for (const poly of cell.nbr_polys) svg.append(s('polygon', { points: polyPoints(poly, tx), fill: TH.cellFill, stroke: TH.cellStroke, 'stroke-width': mini ? 2 : 1.3 }));
		svg.append(s('polygon', { points: polyPoints(cell.poly, tx), fill: 'rgba(242,178,74,.16)', stroke: '#d98f12', 'stroke-width': mini ? 3 : 2.4 }));
		const W = mini ? 27 : 44, Hh = mini ? 9 : 17, gap = mini ? 3 : 4;
		this.rects = [];
		const stack = (c, count, bitOf, own, nameOf) => {
			for (let j = 0; j < count; j++) {
				const row = count - 1 - j;                       // the highest level on top
				const y = c[1] + (row - (count - 1) / 2) * (Hh + gap) - Hh / 2;
				const g = s('g', { class: 'tog', style: this.o.interactive ? '' : 'pointer-events:none' });
				const r = s('rect', { x: c[0] - W / 2, y, width: W, height: Hh, rx: mini ? 2.5 : 5, 'stroke-width': mini ? 1.6 : 1.4 });
				g.append(r);
				if (!mini) g.append(s('text', { x: c[0], y: y + Hh / 2 + 3.8, 'text-anchor': 'middle', 'font-size': 10.5, fill: TH.text, 'pointer-events': 'none' }, nameOf(j)[1]));
				const bit = bitOf(j);
				if (this.o.interactive) {
					g.append(s('title', null, nameOf(j)[2] + ': click to put a block there or take it away'));
					g.addEventListener('click', () => this.o.onToggle && this.o.onToggle(bit));
				}
				svg.append(g);
				this.rects.push({ r, bit, own });
			}
		};
		for (let i = 0; i < n; i++) {
			const c = tx(cell.nbrs[i]);
			stack(c, levels.length, j => i * per + j, false, j => [levels[j][0], levels[j][1], 'Neighbour ' + (i + 1) + ', ' + levels[j][0]]);
		}
		// the subject block and its own column
		const c0 = tx(cell.pt);
		const own = this.level === 'k1' ? [['below', 'own column, one storey down'], ['above', 'own column, one storey up']] : [['above', 'own column, one storey up']];
		const sh = mini ? 11 : 24, sw = mini ? 29 : 64;
		svg.append(s('rect', { x: c0[0] - sw / 2, y: c0[1] - sh / 2, width: sw, height: sh, rx: mini ? 3 : 7, fill: TH.own, stroke: TH.ownStroke, 'stroke-width': mini ? 1.6 : 2 }));
		if (!mini) svg.append(s('text', { x: c0[0], y: c0[1] + 4, 'text-anchor': 'middle', 'font-size': 11.5, 'font-weight': 700, fill: '#2a1c05', 'pointer-events': 'none' }, this.level === 'k1' ? 'this block' : 'ground'));
		own.forEach((ow, j) => {
			const above = ow[0] === 'above';
			const y = above ? c0[1] - sh / 2 - gap - Hh : c0[1] + sh / 2 + gap;
			const g = s('g', { class: 'tog', style: this.o.interactive ? '' : 'pointer-events:none' });
			const r = s('rect', { x: c0[0] - sw / 2, y, width: sw, height: Hh, rx: mini ? 2.5 : 5, 'stroke-width': mini ? 1.6 : 1.4 });
			g.append(r);
			if (!mini) g.append(s('text', { x: c0[0], y: y + Hh / 2 + 3.8, 'text-anchor': 'middle', 'font-size': 10.5, fill: TH.text, 'pointer-events': 'none' }, above ? '+1 (own)' : '−1 (own)'));
			const bit = n * per + (this.level === 'k1' ? j : 0);
			if (this.o.interactive) {
				g.append(s('title', null, ow[1] + ': click to put a block there or take it away'));
				g.addEventListener('click', () => this.o.onToggle && this.o.onToggle(bit));
			}
			svg.append(g);
			this.rects.push({ r, bit, own: true });
		});
		this.setBits(this.bits);
	}

	setLevel(level) { this.level = level; this.bits = 0; this.build(); }

	setBits(bits) {
		this.bits = bits;
		for (const q of this.rects) {
			const on = (bits >> q.bit) & 1;
			q.r.setAttribute('fill', on ? (q.own ? TH.own : TH.on) : TH.off);
			q.r.setAttribute('stroke', on ? (q.own ? TH.ownStroke : TH.onStroke) : TH.offStroke);
			q.r.setAttribute('stroke-dasharray', on ? '' : '3 3');
			q.r.style.opacity = on ? '1' : (this.o.mini ? '.45' : '.9');
		}
	}
}

/* --- the explorer ---------------------------------------------------------------------------------------------------- */

function initNeighExplorer() {
	const D = neighData();
	if (!D) { const e = $('#game .wrap'); if (e) e.append(h('div', { class: 'err' }, 'No data: run tools/combo_probe.gd and tools/build_viewer_data.py.')); return; }
	const R = (DATA.renders && DATA.renders.real) || {};
	const n = D.cell.nbrs.length;
	const view = new PlanView($('#plan'), D.cell, { interactive: true, onToggle: bit => { stopPlay(); setBits(cur.bits ^ (1 << bit)); } });
	const cur = { level: 'k1', bits: 0, idx: -1 };
	const card = $('#outcomeCard');
	card.innerHTML = '';
	const ocTitle = h('h3'), ocTags = h('div', { class: 'tags' }), ocTT = h('div'), ocWhy = h('p', { class: 'muted', style: { marginTop: '12px' } }),
		ocShare = h('div', { class: 'share' }, h('i')), ocStat = h('p', { class: 'caption' });
	card.append(ocTitle, ocTags, ocTT, ocWhy, ocShare, ocStat);
	const tt = new Turntable(ocTT, null);
	const planNote = $('#planNote');
	const chipsHost = $('#outcomeChips');

	function rec(level, idx) { return R[level + '_' + String(idx).padStart(2, '0')]; }

	function lookup(level, bits) {
		const L = D[level];
		return L.map.get(canonPattern(bits, n, L.per_side));
	}

	function show() {
		const L = D[cur.level];
		const idx = lookup(cur.level, cur.bits);
		const info = L.outcomes[idx];
		const d = describe(info.sig);
		const changed = idx !== cur.idx;
		cur.idx = idx;
		ocTitle.textContent = d.title;
		ocTags.innerHTML = '';
		d.tags.forEach(t => ocTags.append(h('span', { class: 'tagc', style: { borderColor: t.color } }, t.text)));
		ocWhy.textContent = d.why;
		ocShare.firstChild.style.width = Math.max(0.5, 100 * info.patterns / L.raw).toFixed(1) + '%';
		ocStat.textContent = fmt(info.patterns) + ' of ' + fmt(L.raw) + ' patterns (' + (100 * info.patterns / L.raw).toFixed(1) + '%) end up here, in ' + fmt(info.classes) + ' classes. The picture shows the smallest neighbourhood that makes it.';
		if (changed) { tt.setRecord(rec(cur.level, idx)); card.classList.remove('flash'); void card.offsetWidth; card.classList.add('flash'); }
		const cls = canonPattern(cur.bits, n, L.per_side);
		planNote.textContent = 'This pattern is one of ' + fmt(L.multOf.get(cls)) + ' that look the same turned and mirrored (class ' + fmt(L.canon.indexOf(cls) + 1) + ' of ' + fmt(L.classes) + ').';
		$$('.ochip', chipsHost).forEach((c, i) => c.classList.toggle('on', i === idx));
	}

	function setBits(b) { cur.bits = b; view.setBits(b); show(); }

	function setLevel(level) {
		cur.level = level;
		cur.idx = -1;
		view.setLevel(level);
		$$('button', $('#levelSeg')).forEach(b => b.classList.toggle('on', b.dataset.level === level));
		chipsHost.innerHTML = '';
		D[level].outcomes.forEach((o, i) => {
			const d = describe(o.sig);
			chipsHost.append(h('button', { class: 'ochip', title: fmt(o.patterns) + ' patterns', onclick: () => { stopPlay(); setBits(o.rep); } }, d.title.replace('Covered by a block above', 'Covered')));
		});
		setBits(D[level].outcomes[1] ? D[level].outcomes[1].rep : 0);
	}

	const seg = $('#levelSeg');
	[['k1', 'Storey 1 (above the ground)'], ['k0', 'Ground floor']].forEach(([k, name]) => seg.append(h('button', { class: 'btn', 'data-level': k, onclick: () => { stopPlay(); setLevel(k); } }, name)));

	let timer = 0;
	function randomBits() {
		const L = D[cur.level];
		const nb = n * L.per_side + (cur.level === 'k1' ? 2 : 1);
		let b = 0;
		const p = 0.18 + Math.random() * 0.4;
		for (let i = 0; i < nb; i++) if (Math.random() < p) b |= 1 << i;
		return b;
	}
	function stopPlay() { if (timer) { clearInterval(timer); timer = 0; $('#nbPlay').textContent = '▶ Play through patterns'; } }
	$('#nbRandom').onclick = () => { stopPlay(); setBits(randomBits()); };
	$('#nbClear').onclick = () => { stopPlay(); setBits(0); };
	$('#nbPlay').onclick = () => {
		if (timer) { stopPlay(); return; }
		$('#nbPlay').textContent = '❚❚ Pause';
		setBits(randomBits());
		timer = setInterval(() => setBits(randomBits()), 2300);
	};
	watch($('#plan'), v => { if (!v) stopPlay(); }, 0.02);

	setLevel('k1');
	const raw = $('#gmRaw');
	onceVisible(raw, () => countUp(raw, D.k1.raw, 1500));
}

/* --- a small icon of a pattern: the block in the middle, a neighbour on each side with its three storeys as bars ------------ */

function cellChirality(cell) {
	/* true when neighbours 0, 1, 2, 3 run clockwise on the plan (the same turn PlanView draws) */
	const pt = cell.pt, a = cell.nbrs[0], b = cell.nbrs[1];
	return (a[0] - pt[0]) * (b[1] - pt[1]) - (a[1] - pt[1]) * (b[0] - pt[0]) > 0;
}

function miniIcon(D, level, bits) {
	const svg = s('svg', { class: 'mini', viewBox: '0 0 100 100', width: 76, height: 76 });
	const per = level === 'k1' ? 3 : 2, n = 4;
	const cw = cellChirality(D.cell);
	const at = cw ? [[37, 5], [69, 37], [37, 69], [5, 37]] : [[37, 5], [5, 37], [37, 69], [69, 37]];
	const on = b => (bits >> b) & 1;
	const bar = (x, y, w, hh, isOn, own) => svg.append(s('rect', { x, y, width: w, height: hh, rx: 1.8, fill: isOn ? (own ? TH.own : TH.on) : TH.off, stroke: isOn ? (own ? TH.ownStroke : TH.onStroke) : TH.offStroke, 'stroke-width': 1, 'stroke-dasharray': isOn ? '' : '2 2' }));
	for (let i = 0; i < n; i++) {
		const [x, y] = at[i];
		svg.append(s('rect', { x, y, width: 26, height: 26, rx: 5, fill: TH.cellFill, stroke: TH.cellStroke, 'stroke-width': 1.2 }));
		const rows = level === 'k1' ? [[2, 4], [1, 10.5], [0, 17]] : [[1, 7], [0, 14]];      // [level index, y offset]: the highest storey on top
		for (const [li, dy] of rows) bar(x + 4, y + dy, 18, 5, on(i * per + li), false);
	}
	svg.append(s('rect', { x: 37, y: 37, width: 26, height: 26, rx: 5, fill: 'rgba(242,178,74,.16)', stroke: '#d98f12', 'stroke-width': 1.6 }));
	if (level === 'k1') { bar(41, 40, 18, 4.5, on(n * per + 1), true); bar(41, 46, 18, 6, true, true); bar(41, 55, 18, 4.5, on(n * per), true); }
	else { bar(41, 42, 18, 5, on(n * per), true); bar(41, 51, 18, 6, true, true); }
	return svg;
}

/* --- the gallery ----------------------------------------------------------------------------------------------------- */

function buildGallery(host, level, D, R, tagsOut) {
	const L = D[level];
	host.innerHTML = '';
	L.outcomes.forEach((o, i) => {
		const d = describe(o.sig);
		const svg = miniIcon(D, level, o.rep);
		const tt = h('div');
		const tags = [];
		if (d.o.top === 'walk') tags.push('walk');
		if (d.o.top === '-') tags.push('covered');
		if (d.o.top === 'tower' || d.o.top === 'battle' || d.o.top === 'cottage' || d.o.top === 'flat') tags.push('roofs');
		if (d.o.sup !== '-') tags.push(d.o.sup);
		if (d.o.st === '1') tags.push('stairs');
		const card = h('div', { class: 'gcard rv', 'data-tags': tags.join(' ') },
			tt,
			h('div', { style: { display: 'flex', gap: '10px', alignItems: 'flex-start', marginTop: '8px' } },
				h('div', { style: { flex: '1' } }, h('h4', { style: { margin: '2px 4px 2px' } }, d.title),
					h('div', { class: 'meta' }, fmt(o.classes) + ' classes · ' + (100 * o.patterns / L.raw).toFixed(o.patterns / L.raw < 0.01 ? 2 : 1) + '% of patterns')),
				svg),
			h('div', { class: 'share' }, h('i', { style: { width: Math.max(1.5, 100 * o.patterns / L.raw).toFixed(1) + '%' } })),
			h('div', { class: 'why' }, d.why));
		host.append(card);
		new Turntable(tt, R[level + '_' + String(i).padStart(2, '0')], { hint: false });
		if (tagsOut) d.tags.forEach(t => tagsOut.add(t.text));
	});
}

function initGallery() {
	const D = neighData();
	if (!D) return;
	const R = (DATA.renders && DATA.renders.real) || {};
	buildGallery($('#gallery'), 'k1', D, R);
	buildGallery($('#gallery0'), 'k0', D, R);
	$('#gmOut').textContent = D.k1.outcomes.length;
	$('#gmOut0').textContent = D.k0.outcomes.length;
	const f = $('#gfilters');
	const filters = [['all', 'All'], ['walk', 'Wall walks'], ['covered', 'Covered'], ['roofs', 'Towers & roofs'], ['arch', 'Arches'], ['corbel', 'Corbels'], ['pillar', 'Pillars'], ['stairs', 'Stairs']];
	filters.forEach(([k, name], i) => f.append(h('button', {
		class: 'btn' + (i === 0 ? ' on' : ''), onclick: ev => {
			$$('button', f).forEach(b => b.classList.remove('on'));
			ev.currentTarget.classList.add('on');
			$$('.gcard', $('#gallery')).forEach(c => c.classList.toggle('hide', k !== 'all' && !(c.dataset.tags || '').split(' ').includes(k)));
		},
	}, name)));
}
