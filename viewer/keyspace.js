'use strict';
/* Townscaper's corner keys. A cell has 8 corners (v0-v3 the bottom ring, v4-v7 the top ring above them). Each is air, ground, "below the world"
   or a colour. The lookup key hides every corner that is buried (itself and its three cube-edge neighbours all filled), renames the colours in order of
   first appearance, and is matched against the library in eight orientations (four turns, mirrored or not). This is a port of tools/townscaper_keyspace.py,
   which counted the numbers in DATA.townscaper from the rules in the decompile notes. */

const KS = (() => {
	const AIR = 18, ANY = 16, BELOW = 17, GROUND = 15;
	const nbOf = i => { const b = i & 4, k = i & 3; return [b + ((k + 1) & 3), b + ((k + 3) & 3), i ^ 4]; };

	function hiddenOf(vals) {
		return vals.map((v, i) => !(v === AIR || nbOf(i).some(j => vals[j] === AIR)));
	}

	function renorm(vals) {
		const ren = new Map();
		return vals.map(v => {
			if (v < 15) { if (!ren.has(v)) ren.set(v, ren.size); return ren.get(v); }
			return v;
		});
	}

	function keyOf(vals) {
		const hid = hiddenOf(vals);
		return renorm(vals.map((v, i) => hid[i] ? ANY : v));
	}

	const ORI = [];
	for (const mirror of [false, true]) {
		for (let r = 0; r < 4; r++) {
			const p = [];
			for (let i = 0; i < 8; i++) {
				const ring = i >> 2, k = i & 3;
				let k2 = mirror ? (4 - k) & 3 : k;
				k2 = (k2 + r) & 3;
				p.push(4 * ring + k2);
			}
			ORI.push(p);
		}
	}

	const applyPerm = (vals, p) => { const out = new Array(8); for (let i = 0; i < 8; i++) out[p[i]] = vals[i]; return out; };

	function orbit(key) {
		const set = new Set();
		for (const p of ORI) set.add(renorm(applyPerm(key, p)).join(','));
		return set;
	}

	const popcount = m => { let n = 0; for (let x = m; x; x >>= 1) n += x & 1; return n; };

	function canonShape(mask) {
		let best = 1e9;
		for (const p of ORI) {
			let m = 0;
			for (let i = 0; i < 8; i++) if (mask & (1 << i)) m |= 1 << p[i];
			best = Math.min(best, m);
		}
		return best;
	}

	/** The plain shapes: filled/empty corner patterns up to turning and mirroring, without the empty and the full cell. */
	function shapes() {
		const seen = new Set();
		for (let m = 1; m < 255; m++) seen.add(canonShape(m));
		return Array.from(seen).sort((a, b) => popcount(a) - popcount(b) || a - b);
	}

	return { AIR, ANY, BELOW, GROUND, nbOf, hiddenOf, keyOf, orbit, popcount, canonShape, shapes };
})();

/* --- drawing a cube with eight corner dots ------------------------------------------------------------------------ */

const CUBE_EDGES = [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]];
const CUBE_FACES = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]];
const COLOUR_FILL = ['#52c7d6', '#f2b24a', '#b58cf0'];

function cubePoints(yaw, pitch) {
	const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch);
	const pts = [];
	for (let i = 0; i < 8; i++) {
		const k = i & 3;
		const x = (k === 1 || k === 2) ? 1 : -1;
		const z = (k === 2 || k === 3) ? 1 : -1;
		const y = (i >> 2) ? 1 : -1;
		const x1 = x * cy + z * sy, z1 = -x * sy + z * cy;
		pts.push({ x: x1, y: y * cp - z1 * sp, z: y * sp + z1 * cp });
	}
	return pts;
}

/** o = {yaw, pitch, zoom, corners: [{kind: 'air'|'ground'|'below'|'c0'|'c1'|'c2', hidden}], labels, hot}. Returns the projected corners (for hit tests). */
function drawCube(ctx, W, H, o) {
	ctx.clearRect(0, 0, W, H);
	const S = Math.min(W, H) * 0.285 * (o.zoom || 1);
	const raw = cubePoints(o.yaw, o.pitch);
	const pts = raw.map(p => { const f = 1 / (1 - p.z * 0.13); return { x: W / 2 + p.x * S * f, y: H / 2 - p.y * S * f, f, z: p.z }; });
	// faces, back to front
	const faces = CUBE_FACES.map(f => ({ f, z: f.reduce((a, i) => a + pts[i].z, 0) / 4 })).sort((a, b) => a.z - b.z);
	for (const fc of faces) {
		ctx.beginPath();
		fc.f.forEach((i, n) => n ? ctx.lineTo(pts[i].x, pts[i].y) : ctx.moveTo(pts[i].x, pts[i].y));
		ctx.closePath();
		ctx.fillStyle = fc.z > 0 ? 'rgba(59,191,208,.14)' : 'rgba(59,191,208,.07)';
		ctx.fill();
	}
	const zs = CUBE_EDGES.map(([a, b]) => (pts[a].z + pts[b].z) / 2).sort((a, b) => a - b);
	const zmid = zs[6];
	for (const [a, b] of CUBE_EDGES) {
		const back = (pts[a].z + pts[b].z) / 2 < zmid;
		ctx.beginPath();
		ctx.moveTo(pts[a].x, pts[a].y);
		ctx.lineTo(pts[b].x, pts[b].y);
		ctx.setLineDash(back ? [5, 5] : []);
		ctx.strokeStyle = back ? TH.edgeBack : TH.edgeFront;
		ctx.lineWidth = back ? 1.2 : 2;
		ctx.stroke();
	}
	ctx.setLineDash([]);
	const order = pts.map((p, i) => i).sort((a, b) => pts[a].z - pts[b].z);
	const R = Math.min(W, H) * (o.dot || 0.048);
	for (const i of order) {
		const p = pts[i];
		const c = o.corners[i];
		const r = R * p.f;
		ctx.beginPath();
		ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
		const k = c.kind;
		if (k === 'air') { ctx.fillStyle = TH.airFill; ctx.fill(); ctx.setLineDash([3, 3]); ctx.strokeStyle = TH.airStroke; ctx.lineWidth = 1.5; ctx.stroke(); ctx.setLineDash([]); }
		else if (k === 'below') { ctx.fillStyle = TH.belowFill; ctx.fill(); ctx.strokeStyle = TH.belowStroke; ctx.lineWidth = 1.5; ctx.stroke(); }
		else if (k === 'ground') { ctx.fillStyle = '#a07a45'; ctx.fill(); ctx.strokeStyle = '#5a4220'; ctx.lineWidth = 2; ctx.stroke(); }
		else { ctx.fillStyle = COLOUR_FILL[+k.slice(1)]; ctx.fill(); ctx.strokeStyle = 'rgba(20,40,60,.6)'; ctx.lineWidth = 1.6; ctx.stroke(); }
		if (c.hidden) {
			ctx.beginPath();
			ctx.arc(p.x, p.y, r + 5 * p.f, 0, Math.PI * 2);
			ctx.setLineDash([2, 4]);
			ctx.strokeStyle = 'rgba(30,50,70,.6)';
			ctx.lineWidth = 1.4;
			ctx.stroke();
			ctx.setLineDash([]);
			ctx.fillStyle = 'rgba(255,255,255,.62)';
			ctx.beginPath();
			ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
			ctx.fill();
		}
		if (o.hot === i) { ctx.beginPath(); ctx.arc(p.x, p.y, r + 7 * p.f, 0, Math.PI * 2); ctx.strokeStyle = TH.ink; ctx.lineWidth = 2; ctx.stroke(); }
		if (o.labels) {
			ctx.fillStyle = TH.text;
			ctx.font = (13 * p.f).toFixed(0) + 'px "Cascadia Mono", Consolas, monospace';
			ctx.textAlign = 'center';
			ctx.fillText('v' + i, p.x, p.y - r - 8 * p.f);
		}
	}
	return pts.map((p, i) => ({ x: p.x, y: p.y, r: R * p.f + 6 }));
}

/* --- the explorer -------------------------------------------------------------------------------------------------- */

function initKeyExplorer() {
	const T = (window.DATA && DATA.townscaper) || null;
	const canvas = $('#cube');
	if (!canvas) return;
	const ctx = canvas.getContext('2d');
	const LAYERS = ['Ground cell', 'First storey', 'Upper storeys'];
	const SHAPES = KS.shapes();
	const S = { layer: 2, st: [0, 0, 0, 0, 0, 0, 0, 0], yaw: 0.72, pitch: 0.46, hover: false, drag: null, hot: -1, pts: [] };

	const kindOf = i => {
		if (S.layer === 0) return (i >> 2) ? 'toggle' : 'below';
		if (S.layer === 1) return (i >> 2) ? 'cycle' : 'toggle';
		return 'cycle';
	};
	const valsOf = () => S.st.map((v, i) => {
		const k = kindOf(i);
		if (k === 'below') return KS.BELOW;
		if (k === 'toggle') return v ? KS.GROUND : KS.AIR;
		return v ? v - 1 : KS.AIR;
	});
	const cornersOf = () => {
		const vals = valsOf();
		const hid = KS.hiddenOf(vals);
		return vals.map((v, i) => ({ kind: v === KS.AIR ? 'air' : v === KS.GROUND ? 'ground' : v === KS.BELOW ? 'below' : 'c' + v, hidden: hid[i] && v !== KS.BELOW }));
	};
	function setLayer(n) {
		S.layer = n;
		S.st = S.st.map((v, i) => kindOf(i) === 'toggle' ? (v ? 1 : 0) : kindOf(i) === 'below' ? 0 : v);
		$$('button', $('#layerSeg')).forEach((b, i) => b.classList.toggle('on', i === n));
		report();
	}
	function randomize() {
		S.st = S.st.map((v, i) => {
			const k = kindOf(i);
			if (k === 'below') return 0;
			if (k === 'toggle') return Math.random() < 0.55 ? 1 : 0;
			return Math.random() < 0.7 ? 1 + Math.floor(Math.random() * 3) : 0;
		});
		report();
	}
	function clear() { S.st = S.st.map(() => 0); report(); }

	function report() {
		const vals = valsOf();
		const key = KS.keyOf(vals);
		const chips = $('#chips');
		chips.innerHTML = '';
		key.forEach((v, i) => {
			const txt = v === KS.AIR ? 'air' : v === KS.ANY ? 'any' : v === KS.BELOW ? 'below' : v === KS.GROUND ? 'ground' : '#' + v;
			chips.append(h('div', { class: 'chip' + (v === KS.ANY ? ' any' : '') }, h('small', null, 'v' + i), txt));
		});
		const allAir = vals.every(v => v === KS.AIR);
		const interior = key.every(v => v === KS.ANY);
		const v = $('#verdict');
		const note = $('#keyNote');
		v.className = 'verdict';
		if (allAir) {
			v.classList.add('no');
			v.textContent = 'Empty cell: nothing is drawn.';
			note.textContent = 'Click the corners of the cube to fill them.';
		} else if (interior) {
			v.classList.add('no');
			v.textContent = 'Buried cell: every corner is hidden inside the building, so no piece is needed.';
			note.textContent = 'A corner counts only if it, or one of its three neighbours along the cube edges, is air.';
		} else {
			v.classList.add('ok');
			const L = T ? T.layers[S.layer] : null;
			const twins = KS.orbit(key).size;
			let t = 'A piece is chosen for this key.';
			if (L) t += ' It is one of the ' + fmt(L.keys) + ' keys the lookup answers (' + LAYERS[S.layer].toLowerCase() + ').';
			v.textContent = t;
			const mask = vals.reduce((m, x, i) => (x === KS.AIR || x === KS.BELOW) ? m : m | (1 << i), 0);
			const hidden = key.filter(x => x === KS.ANY).length;
			let n = 'Turned and mirrored it has ' + twins + ' twin' + (twins === 1 ? '' : 's') + ' in the lookup. ';
			if (S.layer > 0 && mask && mask !== 255) n += 'Plain shape ' + (SHAPES.indexOf(KS.canonShape(mask)) + 1) + ' of ' + SHAPES.length + '. ';
			if (hidden) n += hidden + ' hidden corner' + (hidden === 1 ? '' : 's') + ' ignored (dotted).';
			note.textContent = n;
		}
	}

	function frame(dt) {
		if (!S.drag && !S.hover && !reduceMotion) S.yaw += dt * 0.32;
		S.pts = drawCube(ctx, canvas.width, canvas.height, { yaw: S.yaw, pitch: S.pitch, corners: cornersOf(), labels: true, hot: S.hot });
	}
	let visible = false;
	watch(canvas, v => { visible = v; }, 0.05);
	Ticker.add(dt => { if (visible) frame(dt); });

	const toLocal = e => {
		const r = canvas.getBoundingClientRect();
		return [(e.clientX - r.left) * canvas.width / r.width, (e.clientY - r.top) * canvas.height / r.height];
	};
	const hit = (x, y) => {
		let best = -1, bz = -1;
		S.pts.forEach((p, i) => { if (Math.hypot(p.x - x, p.y - y) < p.r + 4 && p.r > bz) { best = i; bz = p.r; } });
		return best;
	};
	canvas.addEventListener('pointerenter', () => { S.hover = true; });
	canvas.addEventListener('pointerleave', () => { S.hover = false; S.hot = -1; });
	canvas.addEventListener('pointerdown', e => {
		canvas.setPointerCapture(e.pointerId);
		const [x, y] = toLocal(e);
		S.drag = { x: e.clientX, y: e.clientY, moved: false, hit: hit(x, y) };
	});
	canvas.addEventListener('pointermove', e => {
		const [x, y] = toLocal(e);
		if (!S.drag) { S.hot = hit(x, y); canvas.style.cursor = S.hot >= 0 && kindOf(S.hot) !== 'below' ? 'pointer' : 'grab'; return; }
		const dx = e.clientX - S.drag.x, dy = e.clientY - S.drag.y;
		if (Math.hypot(dx, dy) > 5) S.drag.moved = true;
		if (S.drag.moved) {
			S.yaw += dx * 0.01;
			S.pitch = clamp(S.pitch + dy * 0.008, -1.2, 1.2);
			S.drag.x = e.clientX;
			S.drag.y = e.clientY;
		}
	});
	canvas.addEventListener('pointerup', () => {
		const d = S.drag;
		S.drag = null;
		if (d && !d.moved && d.hit >= 0) {
			const k = kindOf(d.hit);
			if (k === 'toggle') S.st[d.hit] = S.st[d.hit] ? 0 : 1;
			else if (k === 'cycle') S.st[d.hit] = (S.st[d.hit] + 1) % 4;
			report();
		}
	});

	const seg = $('#layerSeg');
	LAYERS.forEach((name, i) => seg.append(h('button', { class: 'btn ts' + (i === S.layer ? ' on' : ''), onclick: () => setLayer(i) }, name)));
	$('#cubeRandom').onclick = randomize;
	$('#cubeClear').onclick = clear;
	S.st = [1, 2, 1, 0, 3, 1, 0, 2];
	report();

	// the numbers
	if (T) {
		const tot = $('#tsTotal');
		const tsKeys = T.library ? T.library.keys : T.total_keys;
		onceVisible(tot, () => countUp(tot, tsKeys, 1500));
		bars($('#tsLayers'), T.layers.map(L => ({ label: L.name, value: L.keys, text: fmt(L.keys) + ' keys, ' + fmt(L.orbits) + ' turned/mirrored', color: 'var(--ts)' })), { max: T.layers[2].keys });
		const bc = T.layers[2].by_colours;
		const rows = Object.keys(bc).map(n => ({ label: n + (n === '1' ? ' colour' : ' colours'), value: bc[n], color: n === '1' ? '#4a7f88' : 'var(--ts)' }));
		bars($('#tsColours'), rows, {});
		// the plain shapes
		const host = $('#shapes');
		SHAPES.forEach(m => {
			const c = h('canvas', { width: 160, height: 160 });
			const corners = [];
			for (let i = 0; i < 8; i++) corners.push({ kind: (m >> i) & 1 ? 'c0' : 'air', hidden: false });
			drawCube(c.getContext('2d'), 160, 160, { yaw: 0.72, pitch: 0.5, zoom: 1.0, corners, dot: 0.06 });
			host.append(h('div', { class: 'shape' }, c, h('small', null, KS.popcount(m) + ' filled')));
		});
		onceVisible(host, () => $$('.shape', host).forEach((el, i) => setTimeout(() => el.classList.add('in'), reduceMotion ? 0 : i * 28)), 0.1);
	}
}


/** Townscaper's own library, as counts: what the keys choose from. */
function initTsLibrary() {
	const T = DATA.townscaper, lib = T && T.library, host = $('#tsLib');
	if (!host || !lib) { if (host) host.remove(); return; }
	host.append(h('h3', null, 'What those keys choose from ', h('span', { class: 'tag ts' }, 'read from the game\u2019s own library file')));
	host.append(h('p', { class: 'muted' }, 'My count of the keys from the decompiled rules matched ' + fmt(lib.keys_matched_by_my_rules) + ' of the ' + fmt(lib.keys) + ' entries exactly (the other ' + lib.keys_only_in_asset +
		': the empty cell and four odd diagonal corners). Each key lists the pieces that can stand there, in all eight orientations: on average ' + lib.candidates_per_key_mean + ' candidates (median ' +
		lib.candidates_per_key_median + ', up to ' + fmt(lib.candidates_per_key_max) + '), and then the neighbours\u2019 faces and a cost decide.'));
	const bx = h('div');
	host.append(bx);
	bars(bx, [
		{ label: 'modules', value: lib.modules, text: fmt(lib.modules), color: 'var(--ts)' },
		{ label: 'reached by a key', value: lib.modules_reached_by_a_key, text: fmt(lib.modules_reached_by_a_key), color: 'var(--ts)' },
		{ label: 'distinct shapes', value: lib.modules_distinct_mesh_sets, text: fmt(lib.modules_distinct_mesh_sets), color: 'var(--ts)' },
		{ label: 'mesh parts', value: lib.mesh_parts, text: fmt(lib.mesh_parts), color: '#7fd4df' },
		{ label: 'decor modules', value: lib.decor_modules, text: fmt(lib.decor_modules), color: '#7fd4df' },
		{ label: 'modules with props', value: lib.modules_with_props, text: fmt(lib.modules_with_props) + ' (' + lib.prop_placements + ' placements)', color: '#7fd4df' },
	], { max: lib.modules });
}
