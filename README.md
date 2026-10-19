# Castle Scaper Hex

Castle Scaper Realistic on a **12-sided grid**: a copy of `castle-scaper-realistic` (2026-10-18, Kevin: "duplicate castle-scaper-realistic
and experiment with a hex grid ... and build castles and let me see how it looks"; then "I want a double hex grid, meaning there are 12 sides",
"two regular hex grids overlaid, one rotated 30 degrees, so lines run in 12 directions", and, seeing the first version: "double not double the
size... just meaning double the edges and shape").

**The cells (2026-10-19, round 3).** Kevin: "I want smaller grid ... maybe double meaning more hex layered? experiment with it". The cell size is now a
setting: every building cell is still a regular **dodecagon (12 sides)**, by default at **half the area of the hexagon it started from** (10.8 m2, 3.7 m
across the flats, side 0.98 m; 2282 cells on the same island), and the **Cells** button / **H** also offers 1/3 of the area (7.2 m2) and the full size
(21.65 m2, side 1.39 m), and the plain hexagons at 1/2, 1/3 and the full size. `--cs-cell=1|2|3|4` and `--cs-grid=dodeca|hex` start the game on one; a saved
castle remembers its grid and size ("dodeca-2/2" = 12-sided cells at 1/2 of the area; older saves are the full size and still open). Heights stay (a level is
4 m); widths scale with the cell (doors, windows, arches, parapets, stairs, the straight wall's thickness), so every rule works at every size.
Two or more hexagon lattices layered at 0/30 and at 0/20/40 degrees were built and rendered as well (`--cs-grid=layer|layer3`, not in the H cycle): their
cells are irregular polygons of 4 to 12 sides of very different sizes, so they were dropped. `shots/cells_comparison.jpg` shows the same castle on each.
The cells are the truncated hexagonal tiling (3.12.12): dodecagons touch their six neighbours along a whole side, and in the gap between every three of them
is a little equilateral triangle, too small to build on (it stays in the grid so every corner is shared by exactly three cells and two blocks never touch at
only a corner). The sides of the cells run in 12 directions (multiples of 30 degrees). See SPEC section 0. `shots/hex_grid_plan.svg` is a plan of the cells at the
full size; the older `shots/hex_*` pictures were rendered on earlier grids.

**Switching cells.** The **Cells** button next to the build types, or **H** (Shift+H goes back; press twice: it starts a new empty sea), goes through
12-sided 1/2 (default), 12-sided 1/3, 12-sided full size, hexagons 1/2, 1/3, full size. Saved castles remember their grid.

**Straight walls.** With **Straight wall** on (the button next to the build types, or **T**), a drag lays **one continuous straight wall**
(one level high, a wall walk with battlements on top) from the cell you pressed on, in one of the **12, 16 or 24 directions** (**Directions** button or **R**;
every 30, 22.5 or 15 degrees; saved with the castle; 12 is the default and runs along the grid's lines), cutting across the cells it passes through instead of
following them. Walls laid **side by side merge into one thicker wall** (when the gap between them is under one wall thickness and they run end to end or overlap;
up to 8 thicknesses; a save's walls merge when it loads). **Corners**: a round **tower** (a little higher than the wall, with its own battlements) stands on every
end and bend of a wall, and the wedge between two walls that meet at less than 75 degrees is filled; a wall too thick for a round tower ends in a flat cap. Walls that meet or
cross are one walled shape with the parapet round its outline. `shots/wall_corners.jpg` shows the corners before and after. See the controls below and SPEC section 7.

The rest is Castle Scaper Realistic's:

Castle Scaper with a realistic look. The same Townscaper-style building (click a block onto an irregular grid on the sea; round towers, cone
roofs, wall walks with battlements, gate passages, courtyards, cottages, doors, windows, arches, corbels, stairs and a layer of details all come
out of what is around each block), drawn as a real stone castle on a rocky islet: procedural limestone, sandstone, render, granite and brick with
joints, cracks, lichen, moss and a weathered sea line; slate and clay-tile roofs; oak, iron and glass props; a see-through sea with waves, foam,
caustics on its floor and the castle's reflection, far islands on the horizon, smoke, gulls and a sailing boat; an analytic sky; real light, soft shadows, ambient occlusion and bounce light, god rays,
depth of field, a filmic grade and a lens. Four lights (golden hour, overcast, bright noon, dusk with lit windows) and four qualities (low to ultra, from 390 to 80 fps
at 1080p). Every texture is procedural; the look was fitted to Tripo image-gen mock-ups of the game's own castle (`../castle-scaper-realistic-art`).

Besides castle blocks you can build **land, roads, trees, rocks and mountains**: each click turns into something different depending on what is round it (oaks, pines, willows, orchards; cobbles, gravel, dirt; junctions, bridges, jetties; quarries, scree, snow) - the Kingdom starter shows them all round the castle (SPEC section 11).

Godot 4.7 (GDScript). A copy of Castle Scaper (which is unchanged). After pulling new scripts run `godot --headless --import --path .` once (both .bat files do).

```bat
launch-castle-scaper-hex.bat      :: import pass (class cache), then play
verify-castle-scaper-hex.bat      :: import pass, compile, core suite (headless), editor suite, look suite (windowed, memory guard)
```

| | |
|---|---|
| left click | put a block (on the sea, on top, or beside: the face under the mouse decides) |
| **left drag** | **preview, then build on release**: hold the button and move, and a translucent ghost shows every block the stroke would place (moving back over cells takes them off); nothing is built while the button is down. Release builds them all as one undo step. Esc or the right button cancels. A plain click still builds one block |
| **T** / the **Straight wall** button | **straight walls** (castle types): with it on, a left drag previews **one straight wall** from the cell you pressed on, along the nearest of the 12 / 16 / 24 wall directions (R), ending at the middle of the cell under the pointer on a grid line, or every half cell spacing off the grid's lines; the ghost follows the pointer (shorter when it comes back, another direction when it goes round), nothing is built while the button is down, the release builds the wall as one undo step, Esc or the right button cancels, a plain click still builds one block, a right-click on a wall takes it away. Off: the drag follows the pointer cell by cell as above. The status line says "Straight wall at N deg, M m long ..." while you drag |
| right click | take it away |
| W A S D (arrows) / Q E / Shift | move the view across the map / turn it / three times faster |
| right drag / middle drag / wheel | turn / move / zoom (a left drag previews and builds, so it no longer moves the view; a right drag turns, so there is no drag-to-remove: right-click each block) |
| 1-0 - = or the swatches | material |
| Ctrl+Z / Ctrl+Y / Ctrl+S / Ctrl+N | undo / redo / save / empty sea |
| L / G | the light: golden hour, overcast, bright noon, dusk / the quality: low, medium, high, ultra |
| Tab / F1-F6 | what a click builds: castle, land, road, trees, rocks, mountains (the buttons above the swatches; the Straight wall button sits next to them) |
| H / Shift+H | the cells: 12-sided or hexagons at 1/2, 1/3 or the full size (the Cells button; press twice, it starts a new empty sea) |
| R | how many directions a straight wall can take: 12, 16 or 24 (the Directions button; saved with the castle) |
| N / I | the pen: off, light, full (outlines, hatching, scribbles drawn over the picture) / what it colours in with: colour pencil, watercolour, marker, crayon, stipple, scribble, gouache, ink wash, none |
| B / P / F / Space | birds / details / frame / slow turn |

Design, rules, engine, the look and numbers: [SPEC.md](SPEC.md). What is left compared with Townscaper: [TOWNSCAPER_GAP.md](TOWNSCAPER_GAP.md).
How many things one click can become, measured against Townscaper's corner-key lookup: the combinations viewer (`viewer/index.html`, SPEC section 12): an
animated page with an explorer over every neighbourhood of a block and the 3D turntables the game rendered of each outcome.

Files: `scripts/cs_grid.gd`, `cs_town.gd`, `cs_build.gd`, `cs_props.gd`, `cs_starter.gd`, `cs_main.gd` + `cs_ui.gd` (Castle Scaper's);
`cs_world.gd` + `cs_roads.gd` + `cs_scatter.gd` (the landscape), `cs_look.gd` (lights and qualities), `cs_rocks.gd` (rock skirt and sea floor), `cs_reflect.gd` (the reflection); `cf_*.gd` (Castle Forge's engine,
triangulator, roofs, audit, birds); `shaders/cs_castle`, `cs_props`, `cs_rock`, `cs_sea`, `cs_seabed`, `cs_sky`, `cs_lens` `.gdshader` and
`cs_common.gdshaderinc`. `tools/shots.ps1` takes clean screenshots under the memory guard. The viewer's tools: `tools/combo_probe.gd` (counts every outcome and dumps
`viewer/data/combos.json`), `tools/townscaper_keyspace.py` (Townscaper's corner-key space), `tools/analysis_render.gd` + `tools/render_viewer.ps1` (the pictures, rendered
by the game), `tools/build_viewer_data.py` (-> `viewer/data.js`), `tools/serve_viewer.py` (the no-cache server).
