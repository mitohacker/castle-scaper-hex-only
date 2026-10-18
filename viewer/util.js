'use strict';
/* Small helpers shared by the page: DOM builders, number formatting, reveal-on-scroll, count-up, one animation ticker. */

/** The colours the scripts draw with (SVG and canvas can't always read the CSS variables): the white theme. Keep in step with style.css. */
const TH = {
	text: '#1b2430', muted: '#566377', dim: '#8793a4',
	cellFill: '#e9eef4', cellStroke: '#bccad9',            // a grid cell on a plan
	boxFill: '#ffffff', boxStroke: '#c2cedc',              // a labelled box in a diagram
	off: '#ffffff', offStroke: '#9aa9bc',                  // a square with no block
	on: '#8c98ad', onStroke: '#47566b',                    // a neighbour's block
	own: '#e0a94a', ownStroke: '#8a6212',                  // the block in question and its own column
	grid: '#dde4ec',                                       // gridlines of a chart
	tsDark: '#0e7c8b', gmDark: '#a85f00', amber: '#e39b1f', ink: '#1b2430',
	edgeFront: 'rgba(40,70,95,.82)', edgeBack: 'rgba(80,110,135,.42)',
	airFill: '#ffffff', airStroke: '#7f90a5', belowFill: '#d3dae3', belowStroke: '#93a2b4',
	sea: '#d9edf5', court: '#bfdcbf', courtStroke: '#9cc49c',
};

const $ = (sel, el) => (el || document).querySelector(sel);
const $$ = (sel, el) => Array.from((el || document).querySelectorAll(sel));
const SVGNS = 'http://www.w3.org/2000/svg';
const reduceMotion = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

function applyAttrs(el, attrs) {
	if (!attrs) return;
	for (const k of Object.keys(attrs)) {
		const v = attrs[k];
		if (v === false || v == null) continue;
		if (k === 'class') el.setAttribute('class', v);
		else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
		else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
		else if (k === 'html') el.innerHTML = v;
		else el.setAttribute(k, v === true ? '' : v);
	}
}

function appendKids(el, kids) {
	for (const kid of kids.flat(Infinity)) {
		if (kid == null || kid === false) continue;
		el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
	}
}

function h(tag, attrs, ...kids) {
	const el = document.createElement(tag);
	applyAttrs(el, attrs);
	appendKids(el, kids);
	return el;
}

function s(tag, attrs, ...kids) {
	const el = document.createElementNS(SVGNS, tag);
	applyAttrs(el, attrs);
	appendKids(el, kids);
	return el;
}

const fmt = n => Number(n).toLocaleString('en-US');
const pct = (a, b, d) => (100 * a / b).toFixed(d === undefined ? 0 : d) + '%';
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;
const ease = t => 1 - Math.pow(1 - clamp(t, 0, 1), 3);
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

/** One requestAnimationFrame loop for every animation on the page; callbacks get (dt seconds, time seconds). */
const Ticker = (() => {
	const fns = new Set();
	let raf = 0;
	let last = 0;
	function tick(now) {
		raf = 0;
		const dt = Math.min(0.1, (now - last) / 1000 || 0);
		last = now;
		for (const f of Array.from(fns)) f(dt, now / 1000);
		if (fns.size && !document.hidden) raf = requestAnimationFrame(tick);
	}
	function start() { if (!raf && !document.hidden) { last = performance.now(); raf = requestAnimationFrame(tick); } }
	document.addEventListener('visibilitychange', start);
	return {
		add(fn) { fns.add(fn); start(); return () => fns.delete(fn); },
		remove(fn) { fns.delete(fn); },
	};
})();

/** Calls cb(true/false) whenever the element enters or leaves the viewport (and once at the start). */
function watch(el, cb, threshold) {
	const io = new IntersectionObserver(es => { for (const e of es) cb(e.isIntersecting); }, { threshold: threshold === undefined ? 0.15 : threshold });
	io.observe(el);
	return io;
}

/** Calls cb once, the first time the element is on screen. */
function onceVisible(el, cb, threshold) {
	const io = new IntersectionObserver(es => {
		if (es.some(e => e.isIntersecting)) { io.disconnect(); cb(); }
	}, { threshold: threshold === undefined ? 0.2 : threshold });
	io.observe(el);
}

function revealAll() {
	const els = $$('.rv');
	if (reduceMotion || !('IntersectionObserver' in window)) { els.forEach(e => e.classList.add('in')); return; }
	const io = new IntersectionObserver(es => {
		for (const e of es) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
	}, { threshold: 0.12 });
	els.forEach(e => io.observe(e));
}

function countUp(el, to, ms, decimals) {
	if (reduceMotion) { el.textContent = fmt(to); return; }
	const t0 = performance.now();
	const dur = ms || 1400;
	const d = decimals || 0;
	function step(now) {
		const t = clamp((now - t0) / dur, 0, 1);
		const v = to * ease(t);
		el.textContent = d ? v.toFixed(d) : fmt(Math.round(v));
		if (t < 1) requestAnimationFrame(step);
	}
	requestAnimationFrame(step);
}

/** Horizontal bars; rows = [{label, value, text?, color?}]; the widths grow once the chart is on screen. */
function bars(host, rows, opts) {
	const o = opts || {};
	const max = o.max || Math.max(...rows.map(r => r.value), 1);
	host.classList.add('bars');
	host.innerHTML = '';
	const fills = [];
	for (const r of rows) {
		const fill = h('i', { style: { background: r.color || o.color || '' } });
		fills.push([fill, r.value / max]);
		host.append(h('div', { class: 'brow' },
			h('span', { class: 'lab', title: r.label }, r.label),
			h('span', { class: 'trk' }, fill),
			h('span', { class: 'val' }, r.text !== undefined ? r.text : fmt(r.value))));
	}
	const go = () => fills.forEach(([f, w], i) => setTimeout(() => { f.style.width = (Math.max(w, 0.004) * 100).toFixed(2) + '%'; }, reduceMotion ? 0 : i * 70));
	onceVisible(host, go, 0.2);
}

function legend(host, items) {
	host.innerHTML = '';
	for (const [color, text] of items) host.append(h('span', null, h('i', { style: { background: color } }), text));
}

function polyPoints(pts, tx) {
	return pts.map(p => { const q = tx(p); return q[0].toFixed(1) + ',' + q[1].toFixed(1); }).join(' ');
}

/** A transform that fits all the given point lists into a w x h box with a margin. */
function fitTransform(lists, w, hh, margin) {
	let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
	for (const pts of lists) for (const p of pts) { x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]); }
	const sc = Math.min((w - 2 * margin) / (x1 - x0), (hh - 2 * margin) / (y1 - y0));
	const ox = (w - (x1 - x0) * sc) / 2 - x0 * sc;
	const oy = (hh - (y1 - y0) * sc) / 2 - y0 * sc;
	const tx = p => [p[0] * sc + ox, p[1] * sc + oy];
	tx.scale = sc;
	return tx;
}

function centroid(pts) {
	let x = 0, y = 0;
	for (const p of pts) { x += p[0]; y += p[1]; }
	return [x / pts.length, y / pts.length];
}
