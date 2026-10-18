'use strict';
/* A turntable: a sprite sheet of pre-rendered frames (made by the game itself, tools/analysis_render.gd) played on a canvas.
   It turns by itself while on screen, speeds up under the pointer, and can be dragged to turn it by hand. */

const SHEETS = new Map();

function loadSheet(file) {
	if (!SHEETS.has(file)) {
		const p = new Promise((res, rej) => {
			const img = new Image();
			img.onload = () => res(img);
			img.onerror = () => rej(new Error('missing ' + file));
			img.src = 'img/' + file;
		});
		SHEETS.set(file, p);
	}
	return SHEETS.get(file);
}

class Turntable {
	constructor(host, rec, opts) {
		this.host = host;
		this.opts = Object.assign({ fps: 6, hint: true }, opts || {});
		this.pos = 0;
		this.visible = false;
		this.dragging = false;
		this.hover = false;
		this.idle = 0;
		this.rec = null;
		this.img = null;
		host.classList.add('tt');
		this.canvas = h('canvas');
		host.append(this.canvas);
		this.ctx = this.canvas.getContext('2d');
		if (this.opts.hint) host.append(this.hintEl = h('span', { class: 'hint' }, 'drag to turn'));
		this.bind();
		this.setRecord(rec);
		watch(host, v => { this.visible = v; if (v) this.draw(); }, 0.05);
		this.stop = Ticker.add(dt => this.tick(dt));
	}

	setRecord(rec) {
		if (this.missingEl) { this.missingEl.remove(); this.missingEl = null; }
		this.rec = rec || null;
		this.img = null;
		if (!rec) { this.missing('no render yet'); return; }
		this.canvas.width = rec.tw;
		this.canvas.height = rec.th;
		this.canvas.style.opacity = '.35';
		loadSheet(rec.file).then(img => {
			if (this.rec !== rec) return;
			this.img = img;
			this.canvas.style.opacity = '1';
			this.draw();
		}).catch(() => { if (this.rec === rec) this.missing('picture missing: ' + rec.file); });
	}

	missing(text) {
		this.missingEl = h('div', { class: 'missing' }, text);
		this.host.append(this.missingEl);
	}

	frame() {
		const n = this.rec ? this.rec.frames : 1;
		if (this.rec && this.rec.swing && n > 1) {
			// a swept view plays forward and back
			const period = 2 * (n - 1);
			const p = ((Math.floor(this.pos) % period) + period) % period;
			return p < n ? p : period - p;
		}
		return ((Math.floor(this.pos) % n) + n) % n;
	}

	draw() {
		if (!this.img || !this.rec) return;
		const r = this.rec;
		const f = this.frame();
		this.ctx.drawImage(this.img, (f % r.cols) * r.tw, Math.floor(f / r.cols) * r.th, r.tw, r.th, 0, 0, r.tw, r.th);
	}

	tick(dt) {
		if (!this.visible || !this.img || this.dragging) return;
		if (this.idle > 0) { this.idle -= dt; return; }
		if (reduceMotion) return;
		const before = this.frame();
		this.pos += dt * this.opts.fps * (this.hover ? 1.8 : 1);
		if (this.frame() !== before) this.draw();
	}

	bind() {
		const c = this.canvas;
		let lastX = 0;
		c.addEventListener('pointerenter', () => { this.hover = true; });
		c.addEventListener('pointerleave', () => { this.hover = false; });
		c.addEventListener('pointerdown', e => {
			this.dragging = true;
			lastX = e.clientX;
			c.setPointerCapture(e.pointerId);
			if (this.hintEl) this.hintEl.style.opacity = '0';
		});
		c.addEventListener('pointermove', e => {
			if (!this.dragging || !this.rec) return;
			const dx = e.clientX - lastX;
			lastX = e.clientX;
			this.pos -= dx / c.getBoundingClientRect().width * this.rec.frames;
			this.draw();
		});
		const up = () => { this.dragging = false; this.idle = 1.4; };
		c.addEventListener('pointerup', up);
		c.addEventListener('pointercancel', up);
	}
}
