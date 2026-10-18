'use strict';
/* Wires the page: the data, then every section, the nav highlight and the reveal-on-scroll. */

function boot() {
	if (!window.DATA || !DATA.combos) {
		document.body.prepend(h('div', { class: 'err', style: { margin: '80px 22px' } }, 'viewer/data.js is missing or empty. Run: python tools/build_viewer_data.py (after tools/combo_probe.gd has written viewer/data/combos.json).'));
		return;
	}
	const steps = [initHeroBg, initHero, initDgTs, initDgGm, initKeyExplorer, initTsLibrary, initHeadToHead, initNeighExplorer, initGallery, initCastles, initDgWave, initRipple, initLandscape, initNext];
	for (const f of steps) {
		try { f(); } catch (e) { console.error(f.name, e); document.body.append(h('div', { class: 'err', style: { margin: '10px 22px' } }, f.name + ' failed: ' + e.message)); }
	}
	$('#built').textContent = 'Data built ' + (DATA.built || '') + '. Everything here can be regenerated: tools/combo_probe.gd, tools/analysis_render.gd, tools/build_viewer_data.py.';
	revealAll();
	// the nav: highlight the section on screen, and a progress bar
	const links = $$('.nav a[href^="#"]').filter(a => a.getAttribute('href') !== '#top');
	const secs = links.map(a => $(a.getAttribute('href'))).filter(Boolean);
	const bar = $('#navbar');
	function onScroll() {
		const y = window.scrollY + 120;
		let cur = -1;
		secs.forEach((sc, i) => { if (sc.offsetTop <= y) cur = i; });
		links.forEach((a, i) => a.classList.toggle('on', i === cur));
		const max = document.documentElement.scrollHeight - window.innerHeight;
		bar.style.width = (max > 0 ? 100 * window.scrollY / max : 0) + '%';
	}
	window.addEventListener('scroll', onScroll, { passive: true });
	onScroll();
}

document.addEventListener('DOMContentLoaded', boot);
