# Castle Scaper Hex

Castle Scaper Realistic on an **organic hex grid**: a copy of `castle-scaper-realistic` (2026-10-18, Kevin: "duplicate castle-scaper-realistic
and experiment with a hex grid for an organic grid instead of the cube grids we have now ... just do hex grid organic randomness and build
castles and let me see how it looks"). Every cell is a hexagon (all of them: no pentagons or heptagons), irregular because every point of the lattice is nudged a little (`--cs-jitter=`, 0 is a perfect lattice), so towers are
hexagonal prisms and walls zig-zag; every cell corner is shared by three cells that all touch, so two blocks never meet at only a corner.
See SPEC section 0. `shots/hex_grid_plan.svg` is a plan of the cells (every one a hexagon). The other `shots/hex_*` pictures, `hex_gallery.jpg` among them,
were rendered before the flips were removed (their coasts still show pentagons and heptagons): re-take them with `tools/shots.ps1`.

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
| **left drag** | **paint**: hold the button and move, and a block goes on every new cell the mouse passes over (not stacked on what the stroke just built); one Ctrl+Z takes the whole stroke back |
| right click | take it away |
| W A S D (arrows) / Q E / Shift | move the view across the map / turn it / three times faster |
| right drag / middle drag / wheel | turn / move / zoom (a left drag paints, so it no longer moves the view; a right drag turns, so there is no drag-to-remove: right-click each block) |
| 1-0 - = or the swatches | material |
| Ctrl+Z / Ctrl+Y / Ctrl+S / Ctrl+N | undo / redo / save / empty sea |
| L / G | the light: golden hour, overcast, bright noon, dusk / the quality: low, medium, high, ultra |
| Tab / F1-F6 | what a click builds: castle, land, road, trees, rocks, mountains (the buttons above the swatches) |
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
