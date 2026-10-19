# Castle Scaper Hex

Castle Scaper Realistic on a **12-sided grid**: a copy of `castle-scaper-realistic` (2026-10-18, Kevin: "duplicate castle-scaper-realistic
and experiment with a hex grid ... and build castles and let me see how it looks"; then "I want a double hex grid, meaning there are 12 sides",
"two regular hex grids overlaid, one rotated 30 degrees, so lines run in 12 directions", and, seeing the first version: "double not double the
size... just meaning double the edges and shape").

**The cells.** Every building cell is a regular **dodecagon: 12 sides instead of a hexagon's 6, at the size of the hexagon it replaces** (21.65 m2,
5.2 m across the flats, side 1.39 m), so towers, houses, walls, stairs and the sea ring come out the size they were on the hexagon grid: 1141 cells
on the island, as before. It is the truncated hexagonal tiling (3.12.12): dodecagons touch their six neighbours along a whole side, and in the gap
between every three of them is a little equilateral triangle (0.84 m2, same side). The triangles are too small to build on: they stay in the grid
(so every corner is shared by exactly three cells and two blocks never touch at only a corner) but are not buildable, little pits between the
blocks that the shore and the landscape fill in. The sides of the cells run in 12 directions (multiples of 30 degrees), the lines of a hexagon
grid and of the same grid turned by 30 degrees. See SPEC section 0. `shots/hex_grid_plan.svg` is a plan of the cells (dodecagons dark, triangles light);
`shots/dodeca_castle.png` and `dodeca_castle_walls.png` are pictures of the castle starter and of straight walls on it (OpenGL compatibility renderer under
software GL, so the sea is washed out); the older `shots/hex_*` pictures were rendered on earlier grids.

**Plain hexagons too.** The **Cells** button next to the build types, or **H** (press twice: it starts a new empty sea), switches to the plain
regular hexagon grid of before, and back; `--cs-grid=hex` starts the game on it. Saved castles remember their grid.

**Straight walls.** With **Straight wall** on (the button next to the build types, or **T**), a drag lays **one continuous straight wall**
(1.9 m thick, one level high, a wall walk with battlements on top) along the grid direction nearest to the drag, from the cell you pressed on to the
cell the pointer is over, cutting across the cells it passes through instead of following them cell by cell. Walls that meet or cross are one
walled shape with the parapet round its outline. See the controls below and SPEC section 7.

The rest is Castle Scaper Realistic's:

Castle Scaper with a realistic look. The same Townscaper-style building (click a block onto an irregular grid on the sea; round towers, cone
roofs, wall walks with battlements, gate passages, courtyards, cottages, doors, windows, arches, corbels, stairs and a layer of details all come
out of what is around each block), drawn as a real stone castle on a rocky islet: procedural limestone, sandstone, render, granite and brick with
joints, cracks, lichen, moss and a weathered sea line; slate and clay-tile roofs; oak, iron and glass props; a see-through sea with waves, foam,
caustics on its floor and the castle's reflection, far islands on the horizon, smoke, gulls and a sailing boat; an analytic sky; real light, soft shadows, ambient occlusion and bounce light, god rays,
depth of field, a filmic grade and a lens. Four lights (golden hour, overcast, bright noon, dusk with lit windows) and four qualities (low to ultra, from 390 to 80 fps
at 1080p). Every texture is procedural; the look was fitted to Tripo image-gen mock-ups of the game's own castle (`../castle-scaper-realistic-art`).

Besides castle blocks you can build **land, roads, trees, rocks and mountains**: each click turns into something different depending on what is round it (oaks, pines, willows, orchards; cobbles, gravel, dirt; junctions, bridges, jetties; quarries, scree, snow) - the Kingdom starter shows them all round the castle (SPEC section 11).

Godot 4.7 (GDScript). A copy of Castle Scaper (which is unchanged).

```bat
launch-castle-scaper-hex.bat      :: play
verify-castle-scaper-hex.bat      :: compile, core suite (headless), editor suite, look suite (windowed, memory guard)
```

| | |
|---|---|
| left click | put a block (on the sea, on top, or beside: the face under the mouse decides) |
| **left drag** | **preview, then build on release**: hold the button and move, and a translucent ghost shows every block the stroke would place (moving back over cells takes them off); nothing is built while the button is down. Release builds them all as one undo step. Esc or the right button cancels. A plain click still builds one block |
| **T** / the **Straight wall** button | **straight walls** (castle types): with it on, a left drag previews **one straight wall** from the cell you pressed on, along the nearest of the grid's 12 directions (multiples of 30 degrees) so it lies on a grid line, ending at the middle of the cell under the pointer; the ghost follows the pointer (shorter when it comes back, another direction when it goes round), nothing is built while the button is down, the release builds the wall as one undo step, Esc or the right button cancels, a plain click still builds one block, a right-click on a wall takes it away. Off: the drag follows the pointer cell by cell as above. The status line says "Straight wall at N deg, M m long ..." while you drag |
| right click | take it away |
| W A S D (arrows) / Q E / Shift | move the view across the map / turn it / three times faster |
| right drag / middle drag / wheel | turn / move / zoom (a left drag previews and builds, so it no longer moves the view; a right drag turns, so there is no drag-to-remove: right-click each block) |
| 1-0 - = or the swatches | material |
| Ctrl+Z / Ctrl+Y / Ctrl+S / Ctrl+N | undo / redo / save / empty sea |
| L / G | the light: golden hour, overcast, bright noon, dusk / the quality: low, medium, high, ultra |
| Tab / F1-F6 | what a click builds: castle, land, road, trees, rocks, mountains (the buttons above the swatches; the Straight wall button sits next to them) |
| H | the cells: 12-sided (the default) or plain hexagons (the Cells button; press twice, it starts a new empty sea) |
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
