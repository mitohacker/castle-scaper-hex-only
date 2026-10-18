"""Merges the viewer's data into viewer/data.js (window.DATA), so viewer/index.html also works opened straight from the disk:
  viewer/data/combos.json   from tools/combo_probe.gd   (the counts, the exhaustive neighbourhood table, the plans, the ripple cases)
  viewer/img/renders*.json  from tools/analysis_render.gd (the sprite sheets: file, grid, frames, annotations)
  Townscaper's corner-key numbers                        computed here with tools/townscaper_keyspace.py
Run:  python tools/build_viewer_data.py
"""
import glob
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VIEWER = os.path.join(ROOT, 'viewer')
sys.path.insert(0, HERE)
import townscaper_keyspace as tk  # noqa: E402


def load(path, default):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def main():
    combos = load(os.path.join(VIEWER, 'data', 'combos.json'), {})
    renders = {}
    for p in sorted(glob.glob(os.path.join(VIEWER, 'img', 'renders*.json'))):
        tag = os.path.basename(p)[len('renders'):-len('.json')].lstrip('_') or 'real'      # renders.json -> real, renders_pen.json -> pen
        renders[tag] = load(p, {})
    t0 = time.time()
    ts = tk.compute()
    ts['library'] = load(os.path.join(VIEWER, 'data', 'townscaper_library.json'), None)      # counts read from the game's own library asset (tools: townscaper-re/tools/library_stats.py)
    data = {'combos': combos, 'renders': renders, 'townscaper': ts, 'built': time.strftime('%Y-%m-%d %H:%M')}
    out = os.path.join(VIEWER, 'data.js')
    with open(out, 'w', encoding='utf-8') as f:
        f.write('window.DATA = ')
        json.dump(data, f, separators=(',', ':'))
        f.write(';\n')
    n_img = sum(len(r) for r in renders.values())
    print('wrote %s (%.0f KB): combos %s, %d render records, Townscaper keys %d (%.1f s)' % (
        out, os.path.getsize(out) / 1024.0, 'yes' if combos else 'MISSING', n_img, ts['total_keys'], time.time() - t0))


if __name__ == '__main__':
    main()
