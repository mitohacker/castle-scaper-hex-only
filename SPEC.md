# Castle Scaper Realistic — design

**This is a copy of Castle Scaper (2026-10-17) with a realistic look**, asked for by Kevin: "make a copy of castle-scaper
and use realistic rendering and post processing, realistic textures for castle. use image gen from tripo if needed but use
procedural as much as possible for maximal flexibility. use a few mockups renders of full castle for final look and use it
as reference". Nothing of the rules, the grid, the engine or the props' placement changed (sections 1-5 and 7 are
Castle Scaper's); sections 6 (the look), 8 (tests, tools) and 9 changed, and 10 is new. Castle Scaper itself is untouched.
The look was fitted to Tripo image-gen mock-ups of the game's own castle (`castle-scaper-realistic-art`, round 1: three lights,
three cameras each, repaints of clean in-game frames) with `tools/side_by_side.py`. Every texture is procedural.


Build a castle the Townscaper way. There is one action: click to put a block down, right-click to take one away, pick
its colour. Everything else (round towers, cone roofs, banners, wall walks with battlements, gate passages, courtyards,
cottages, doors, windows) comes out of what is around each block. The grid is irregular, so the same few rules give a
different castle every time.

Copied from Castle Forge on 2026-10-17 (its welded layer engine, birds and mesh code); Castle Forge's node editor is
replaced by click-to-stack, its castle rules by block rules, its stone paint by plain pastel plaster. Castle Forge
itself is untouched. Townscaper was studied with REA + Ghidra (`C:\Dev\Prototypes\townscaper-re`, local only); its
ideas were re-implemented, no code or assets were copied.

## 1. The grid (`scripts/cs_grid.gd`, `CSGrid`)

Townscaper's recipe, on a hexagon:

1. A triangle lattice inside a hexagon of radius 10 steps (step 10 m), in integer twelfths.
2. Pairs of neighbouring triangles merge into quads, in a seeded random order (`generate(seed = 1)`); unmerged
   triangles stay.
3. Every face is subdivided once (a quad into four quads, a triangle into three), so everything is a quad.
4. 255 relaxation steps x 0.4 pull each quad towards a square of the mean area (Townscaper's
   `v = d0 + rot270(d1) - d2 + rot90(d3)`, normalised, scaled by the diagonal); the border stays pinned.

Result: 1327 grid points, 1266 quads, made in about 0.1 s. Blocks stand on grid **points**; a block's cell is the
polygon of the quad centres round its point (the dual grid), so cells have 3, 4, 5 or 6 sides (1207 buildable points:
1000 with 4, 116 with 3, 78 with 5, 13 with 6). Border points are sea only. Queries: `nearest`, `dual`, `face`,
`neighbour_towards`, `index_of`, a spatial hash for picking.

## 2. The blocks (`scripts/cs_town.gd`, `CSTown`)

A dictionary `key(v, k) = v * 64 + k -> colour (0..11)`. Levels 0..15, 4 m each. Saved as JSON with the grid's seed and
radius. That is the whole game state; undo keeps whole copies (300 steps).

## 3. The rules (`scripts/cs_build.gd`, `CSBuild`)

A block becomes what its neighbours make it. Rebuilt from scratch (or incrementally, see 4) after every click.

- **Land and sea.** A flood fill from the border: an empty cell the sea cannot reach is a **courtyard**; a cell under a
  block that bridges over it is a **passage** (a gate); a ground block stands on **land**. Land is a low sandstone
  plinth 0.6 m above the sea; everything else is sea.
- **Cell shape.** A cell corner shared only with a diagonal block (the two cells between them empty) is pulled 0.35 m
  in (`PINCH`), so the two blocks stand apart instead of touching along a line (Townscaper's corner modules handle
  that case). Same colour, same shape and same roundness stack into one body.
- **Tower.** A column of two or more blocks whose top touches no other top is a tower. Free-standing from the ground up
  it is round (16 sides); rising out of a wall it keeps its cell's shape. Its top gets a cone roof (72%, seeded by the
  grid point; red tile on warm colours, blue slate on cool ones; a pole, and a banner on the tall ones) or a ring of
  battlements (28%). A crowded top (a neighbour higher) stays flat.
- **Cottage.** A single block alone on the ground gets a pyramid roof.
- **Wall walk.** Tops that touch other tops at the same level form a walk: paved, with battlements (0.45 m thick,
  1.05 m high, notches every ~1.45 m away from corners) along every open edge. Where the parapet meets a taller block, a
  stub runs a parapet's width along that block and bites 0.15 m into it (`STUB_BITE`), so the solids overlap rather
  than touch along one line, even where that block's corner is pinched.
- **Openings.** A ground block facing land gets a planked door (85%); other open sides get arrow slits or windows, never
  on sides shorter than 2.6 m, never on a side an arch, a pier or a flight of stairs stands against.

### 3a. What holds a block up, and stairs (Townscaper's corner pieces, TOWNSCAPER_GAP items 1 and 7)

A block with nothing under it is decided from the blocks round its cell at its own level and the level below (the
two-level pattern of the dual cells round its grid point), deterministically, by its grid point:

- **Arch.** Two neighbours on opposite-ish sides (directions at least 114° apart) have blocks one level down, with room
  for a half span of 0.7 m or more after 0.3 m piers: the cell under the block is **filled** and a stepped arch is CUT
  through it (Castle Forge's gate arch): its span runs between the two abutments, the passage across that line, the
  crown 0.4 m under the block, four or five courses (fewer on narrow arches so no course is under 4 cm), every side line
  kept 6 cm clear of the cell's corners. Pairs whose arch opens on both sides win, then the most opposite. Decided from the
  blocks alone; the fill then counts as a block (`filled()`) for everything else: its neighbours' outlines (no pinch
  against it), walk edges, openings, round columns. A fill shut in on every side stays solid. The castle starter's
  gate passage is one; a bridge between two towers higher up is one too (its piers hang from the towers).
- **Corbels.** Every other side whose neighbour has a block one level down (the block overhangs that wall) gets a
  stepped corbel: three courses reaching 1.0 / 0.65 / 0.3 m out of the wall (at most 45% of the cell's depth), over the
  top 1.1 m under the block, clipped from the block's own outline so its walls run on down. Its back is the wall's **own
  face**: where that wall's corner is pinched (a diagonal block at its level) the face leans a few degrees off the cell's
  side, and the corbel follows it (a corbel on the side would leave a sliver of air whose tip is a line two solids touch
  along). An arch's feet over a wall one level down get corbels too, clipped to the piers (under the passage a course's
  side would meet the underside of a block beside it along a line). Round columns bear nothing (they stand back from
  their sides).
- **Pillar.** No neighbour with a wall below: a pillar down to the next block of its column or to the land (every
  column has land under it): a base, a shaft of 0.5 m radius (less in small cells), a capital, round or square (55 / 45,
  seeded). A top with a block floating above it in its own column is flat (no roof or battlements under the pillar).
- **Stairs.** One flight between each pair of wall walks a level apart that touch, and between each courtyard and each
  walk at level 0 beside it: ten steps of 0.4 m climbing straight up to the higher block's side on the lower floor,
  1.2 m wide, running 2.2-4 m into the cell (inside its floor, 0.6 m clear of its parapets and taller walls, 1.5 m clear
  of doors and arches), never on a door's side, never on a cell with anything above it, never where either side is
  pinched (the faces would not meet flush), never within the lower walk's parapet stubs or the upper parapet's corners.
  The upper parapet has a gap the width of the flight + 12 cm a side where it arrives (no notches on that side), and
  the higher block gets no opening on that side. Of the sides where a flight fits, the one its two grid points pick
  (seeded); one flight per cell. Each step and each corbel course is a stack of its own: the plan splits an outline
  only at other stacks' corners, and their sides run along the same lines.
- A walk edge under a block hanging over it from the level above (its bottom at the walk's floor) is closed, like an
  edge against a taller block: the parapet ends against it in stubs. (It used to stand pressed against that block's face
  and left a non-manifold line where that face was pinched.)

## 4. The engine (Castle Forge's `cf_plan.gd`, unchanged)

Every part is a flat convex outline between two heights (a layer: ADD, CUT or CAP) in stacks and groups. The plan snaps
to 1 mm, merges vertices within 2 cm, splits every edge at every crossing, classifies each piece of edge on both sides at
every height and emits walls and ledges on shared vertices: **one welded skin**, audited by `CFAudit` (open edges,
non-manifold edges, flipped faces, T-junctions). Roofs are built on the cap layers' own vertices (`cf_roofs.gd`).

Groups: column `10000 + v` (its land, blocks, arch fill and cut, corbels, pillar), walk area `50000 + id` (battlements,
notches, stair gaps), a tower's ring of battlements `60000 + v`, door leaves `70000 + v`, stairs on cell v `80000 + v`.
Layers of one stack must never overlap (pieces that do go in separate stacks); never design edges 2 mm–4 cm apart.

Rebuilds pass the previous castle (`build(grid, town, prev)` -> `plan.run(mesh, prev.plan)`): layers whose content and
neighbours did not change take over their split outline and walls. A click rebuilds in ~50–250 ms instead of ~260–300 ms
(castle starter); `tools/incr_probe.gd` checks the result against a full build.

## 5. The prop layer (`scripts/cs_props.gd`, `CSProps`)

Small details are separate instanced meshes, never welded into the skin (Townscaper's props are rigid meshes too, each
kept only if nothing more important overlaps it). After `CSBuild.build`, on the same worker thread:

1. Every block side and top proposes **candidates**: a kind, a cost, the boxes it would fill and the meshes it shows.
   Wall props are made in a frame on the wall (x along it, y up, z out of it; on a round tower the plane touching the
   circle round it); their meshes reach 0.12 m behind that plane, hidden in the masonry, their boxes start at it.
2. They are sorted by cost, ties broken by a hash of the grid point, and **kept greedily** when none of their boxes
   overlaps a kept box (the doors with the step in front of them, the slits and the windows of `CSBuild.openings` are
   kept first), a block or an arch's fill, a corbel, a pillar or a flight of stairs (`CSBuild.extras`), the land, or what
   stands above a top (a parapet's height, a roof and its pole): an independent
   set, so no two props intersect and none sits inside the castle. Alternative spots for one prop share a group (only
   one is kept); shutters and flower boxes need their window's frame.
3. Per mesh, the kept instances become one **MultiMesh** (transform + palette a, palette b, owner) made on the worker;
   `cs_main` shows them with one MultiMeshInstance3D per mesh (16 meshes, all made in code: `CSProps.make_meshes`).

| prop | where | cost |
|---|---|---|
| window frame (jambs, lintel with a keystone, sill) | every window | 1 |
| chimney | most cottages (near a corner of the pyramid roof, one spot per corner) and most small flat houses (a clump of up to six wall-walk tops, at most three storeys, that is not a curtain: no block of it has the sea on one side and a courtyard on another) | 1.5 |
| shutters (planks in a second colour) | 60% of the windows on flat walls | 2 |
| lantern on a bracket | beside every door, sometimes on both sides | 2 / 2.6 |
| bunting | between two blocks at one level facing each other across a gap (3.4-18 m apart, sides within ~37 deg), sent from 60% of the open sides; 3.2 m above the level's floor, sagging; flags by turns in the two blocks' colours | 2.5 |
| flower box | 50% of the windows on flat walls | 3 |
| shield (parted in two heraldic colours) | the top two levels of 70% of the towers, one per level | 3 |
| banner on a rod | under the top of 65% of the towers | 3 |
| hoarding (a timber gallery under the parapet) / machicolation corbels and a string course | 24% / 31% of the open wall-walk sides 2.2 m or longer | 4 |
| crates (one, two side by side or two stacked) / barrels | two spots on every wall side round a courtyard, 55% of them tried | 5 |

The props pop with their block: `shaders/cs_props.gdshader` (the plaster's palette and light) scales each instance about
its mount point on the block pop's spring, starting 30% into it, for the column just added (`pop_id` = grid point + 1,
like the castle); the props that hung on a block taken away stay 0.3 s on a second set of MultiMeshes and shrink out.
Birds may perch on chimney tops (added to CFBirds' landings). The Details button or P hides the layer (`--cs-noprops`).

Numbers (2026-10-17, castle starter): 310 candidates, 200 props kept (41 frames, 24 shutters, 22 flower boxes, 6 shields,
4 banners, 30 lanterns, 5 chimneys, 9 hoardings, 23 corbel rows, 18 crates, 12 barrels, 6 bunting strings), 603
instances, ~45 ms; village, harbour and random 70-block castles 5-25 ms. The skin is untouched (every audit as before).

## 6. The look (realistic; fitted to the round-1 mock-ups)

Everything is a shader or generated in code; no image is in the project. Files:

- `shaders/cs_common.gdshaderinc`: hashes, value noise, fbm, the masonry patterns (`ashlar` courses of varying height in running bond,
  `brick`, `rubble` and `flags` Voronoi stones, `crack_field`) and the **palette table**: each of the 12 swatches is a material, not a paint:
  0 limestone ashlar, 1 cream lime render, 2 honey sandstone, 3 ochre render, 4 red sandstone, 5 pink render, 6 violet-grey stone,
  7 blue-grey limewash, 8 greenstone rubble, 9 sage render, 10 grey granite, 11 brick (`W_COL`, `W_PAT`). The UI's swatches show the same colours.
- `shaders/cs_castle.gdshader`: the castle's skin. Every face has its metre frame (UV), zone, palette index (`COLOR.g * 16`), flags,
  edge distances (CUSTOM0) and tangent frame (CFMesh). Stone: joints and bevels (anti-aliased by the pixel footprint, faded to the mean
  colour at a distance: no shimmer), block tone / hue / strata / per-block grain, 3-scale relief from world-space noise gradients,
  pits, large-scale patina, rain streaks under ledges, lichen colonies, moss in the damp, a sea line (salt-bleached splash zone, dark wet
  stone, algae, barnacles), worn corners. Render: trowel marks, stipple, hairline cracks along Voronoi cell edges, chips back to rubble near
  the ground and corners. Paving: dressed slabs in rows (`ashlar` on x, z). Slate and clay-tile roofs (rows, per-tile tone, lap shadow, moss,
  lichen), oak planks with grain and iron nails, linen banners that ripple in the vertex shader. `wetness` (rain) darkens and glosses it.
- `shaders/cs_props.gdshader`: the prop layer in the same materials (limestone frames, weathered oak, painted flaking shutters, iron,
  window glass that reflects the sky, lantern flame, hemp, linen bunting); `night` lights windows and lanterns (not driven yet).
- `shaders/cs_rock.gdshader` + `scripts/cs_rocks.gd` (`CSRocks`): the rocky skirt round the land (talus and boulders from the shore loops
  of the cell outlines, 10 rings out to 7 m, noise-lumpy, kept off gate passages) shaded as bedded weathered rock with algae and barnacles,
  and the sea floor (a polar disc, sand, rock patches, falling from 2.5 to 90 m deep). Built on the worker with the castle (`_finish`).
- `shaders/cs_sea.gdshader`: see-through water. Colour and opacity follow the water's thickness (the depth texture): turquoise over the
  shallows, deep blue-green out; seven travelling swells with analytic slopes and curved fronts (fading with distance), foam on shallow
  edges and steep crests, the sky's Fresnel reflection (the engine's), the sun's glitter. `shaders/cs_seabed.gdshader`: sand, ripples, weed,
  rock patches, caustics, light absorbed by the water above it. `scripts/cs_reflect.gd` (`CSReflect`): the castle's reflection, a mirrored
  camera into a transparent half-res SubViewport (sea and floor on render layer 2 stay out), laid on the water by Fresnel.
- `shaders/cs_sky.gdshader`: analytic sky (Rayleigh zenith, warm horizon, Mie glow round the sun, a sun disc, one lit cloud layer).
- `shaders/cs_lens.gdshader`: the lens pass (vignette and a cool/warm tint, grain, edge fringing, clarity, sharpening).
- `scripts/cs_look.gd` (`CSLook`): **three lights** (Golden hour, Overcast, Bright noon; L) and **four qualities** (Low, Medium, High, Ultra; G),
  both kept in `user://castle_scaper_realistic.cfg`. A light sets the sun (height, compass, colour, energy, softness), sky, ambient, haze,
  tone mapper / exposure / contrast / saturation, volumetric mist, the water's colours and clarity and chop, the stone's wetness / moss / grime
  and the lens. A quality sets render scale and FSR, anti-aliasing, shadow distance / cascades / softness, SSAO, SSIL, SDFGI, god rays and
  mist, depth of field (follows the camera's distance), the lens and the reflection. Overrides: `--cs-look=`, `--cs-quality=`,
  `--cs-look-set=key=value,...` (any key of a light, e.g. `tonemap=4`, `water_debug=1`).
- Birds (Castle Forge's `cf_birds.gd`) are unchanged. The pop-up of a new block, the hover highlight and the ghost are unchanged.

Cost (1920 x 1080, RTX 5070 Ti laptop, castle starter, `--cs-uncap`, GPU otherwise idle; 2026-10-17, final code): Low 468 fps, Medium 302,
High 175, Ultra 105 (peak private memory 1.4 -> 2.4 GB; Ultra's reflection is half resolution, at 0.75 it read 49). With another program using the
GPU (incremental-rts at 91 %) the same runs read 79 / 69 / 59 / 20: measure on a quiet machine (`Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage'`).

**Round 2 (2026-10-18, "do all" after an analysis of what still held the look back):**

- *Masonry depth*: steep **parallax** in `cs_castle.gdshader` (`parallax_uv`, 8 steps, joints recessed 3 cm; ashlar and brick, only within ~0.8 m / px footprints).
  New props: **string courses** (moulded bands under the parapet line of every level, `M_STRING`), **ivy** patches (150 two-sided leaves and vines,
  `M_IVY`, more on the lower levels), and a better **window**: a leaded glass pane set back, a mullion and transom, a drip under the sill. Cracks now
  break up along their Voronoi edges and the lost-render patches are fewer. Tile roofs and the rock lost their loud colour and marble veins.
- *Sea*: the water mesh is a 3 km polar disc (`CSRocks.sea_mesh`, dense at the island) and the three long swells **displace the surface**
  (`swell_h`, same phases as the normals, faded out from 200 m to 1.1 km); animated **swash foam** bands where the water laps the rocks; the reflection is
  **blurred** by distance and slope and renders every other frame (`UPDATE_ONCE`).
- *Sky and horizon*: a second high layer of **cirrus**, billowed clouds, **crepuscular rays** round the sun, **stars** (dusk); four **far islands**
  (`cs_island.gdshader`, `CSRocks.island_mesh`: forest, crags, a beach) at 0.6 - 1.9 km, hazed by the fog, ringed by the water's own shore foam.
- *Light*: a fourth light, **Dusk** (sun 4 deg, deep blue zenith, red horizon, stars, lit windows and lanterns through the props shader's `night`
  uniform, 0.9); every light has a **colour table** (`CSLook.lut_for`, a 16-cube split tone: shadows pushed toward `tone_shadow`, lights toward
  `tone_high`) in the environment's colour correction.
- *Life* (`scripts/cs_life.gd`, `CSLife`): smoke from every chimney (CPU particles, rebuilt with each castle), six gulls soaring on circles with
  flapping wings, a **sailing boat** circling the island 58 m out, and a **puff of dust** (a **splash** on the water) when a block goes down or comes away.
- Cost (same machine, GPU idle, with all of it): Low 386 fps, Medium 236, High 131, Ultra 81.

**Pen over the picture (2026-10-18, Kevin starred the round-3 "light" pen-and-pencil mock-ups of the overcast castle and said "use the ones I starred"):**
`scripts/cs_pen.gd` (`CSPen`, a `CompositorEffect` on the camera, a compute shader after the transparent pass, before tone mapping), setting Pen = Off / Light /
Full (key **N**, the top bar's Pen button, kept in the settings file, `--cs-pen=`). It reads the resolved colour and depth: **pen** = thin, shaken black
outlines from steps in the inverse depth (1/z is affine over a flat face, so only silhouettes light up; Full also draws creases from its second
difference), one wobbly horizon line, dashed cloud edges (from the sky's brightness), with breaks and uneven weight; **pencil** = scribble bundles in
the sky (pinned to the sky dome by the view direction) and long wavy strokes on the sea (pinned to the water plane by the ray-plane hit, two crossing
sets, fading out by 700 m), in lilac / blue / white / grey and teal / white / blue, never on the castle (the sea strokes stop at anything solid in front
of the water). No ink under the water (the sea floor's far edge drew a second horizon). Cost: High 151 -> 143 fps. Compared with the two starred pictures
in `castle-scaper-realistic-art/reference/compare/pen_*.jpg`. Round 2 of the pen (same day, Kevin: "yes, do" the hatching and wash): on every solid pixel above the water the pass now also draws **pen hatching in the
shadows** (diagonal strokes, cross strokes in the deepest shade, by luminance) and a **coloured-pencil wash** over the lit walls and roofs (broad strokes that
pull the surface's own colour further, a paper grain), both laid in WORLD space (planes through the reconstructed world position, so they stay on the stone
when the camera moves) and faded into a flat tone when a stroke is under ~3 px. Light = hatch 0.55 / wash 0.6, Full = 1.0 / 1.0 (heavier line, creases,
more scribbles). A solid pixel counts as water when its world height is within 0.55 m of the sea level (the water writes depth too: a ray-plane test
misclassified wave troughs and hatched the sea). Cost on High: 152 fps with Light, 115 with Full (Off 151 before; Light costs little).
**Pencil infill (Kevin: "I still want pencil infill"):** the world-space wash was replaced by a real infill in screen space (`cs_pen.gd`, after the hatching):
strokes 5 px wide and 90-220 px long that follow the form (their direction is the contour of the inverse depth, in 15-degree steps; flat faces use
a 50-degree default), each with its own pressure, a slight wave, a gap where the paper shows (about one stroke in eight is not drawn) and a paper tooth
that eats the stroke; coloured with the surrounding area's own colour (an 8-tap ring at 7 px) pushed to 1.9 x saturation; a second layer crosses at
36 degrees in the deeper tones; plus a faint flat tint under the strokes. Light uses 0.9, Full 1.3. Screen space, because pencil sits on the paper and
must look the same at any zoom (it does not move with the stone: pencil strokes slide a little under camera motion). Measured on High, quiet GPU: Light 173 fps, Full 170.

**Infill styles (Kevin: "can we have all different types of infills? as options"):** the Pen's infill is now a setting of its own (key **I**, the top bar's
Infill button, saved, `--cs-infill=`; `CSLook.INFILL_IDS`, `CSPen.style` -> push constant `d.w`). Nine: **Colour pencil** (fine directional strokes, tooth, cross
layer in the shade), **Watercolour** (a soft transparent wash pooled in blotches, pigment granulating in the paper, light lifted out), **Marker** (wide hard-edged
see-through strokes, darker where two overlap), **Crayon** (thick waxy strokes catching only the paper's peaks), **Stipple** (dots, more and bigger in the dark),
**Scribble** (looping lines, close in the dark and open in the light), **Gouache** (opaque flat tones in five bands with dry-brush streaks), **Ink wash**
(sepia brush tones with pooled edges) and **No infill** (outlines and hatching only). All take the area's own colour (`ring_mean`, 7-15 px), follow the form where
they have a direction (`stroke_layer`, the contour of the inverse depth), and are drawn in screen space. Pictures: `castle-scaper-realistic-art/reference/infills/`.
Frame rates measured per infill ranged 64-146 fps on High with another program on the GPU: not a ranking.

## 7. The editor (`scripts/cs_main.gd`, `scripts/cs_ui.gd`)

| input | does |
|---|---|
| left click | put a block: on the sea, on top of a block, or beside one (the face under the mouse decides) |
| right click | take that block away |
| right drag | turn the camera |
| left or middle drag | move the camera |
| wheel | zoom |
| 1–0, -, = or the swatches | colour |
| Ctrl+Z / Ctrl+Y | undo / redo |
| Ctrl+S / Ctrl+N | save (user://castles) / an empty sea |
| B / F / Space | birds / frame the castle / slow turn |
| P or the Details button | the prop layer on / off |

Top bar: New, Castles (the starters and saved castles), Save, Undo, Redo, Birds, Details, Turn. The castle and its props
build on a worker thread; clicks made meanwhile coalesce. Autosave to `user://castle_scaper_autosave.json`; the game opens on it, or on the
castle starter the first time.

Picking: a ray against the castle's collision mesh; the hit triangle's owner (CUSTOM1.w = grid point + 1) and normal
say which block and which face. A top face adds above, a side face adds the neighbour that way, a miss adds on the sea.

Starters (`scripts/cs_starter.gd`): castle (a ring of walls, four towers, a gate passage, a keep with a round tower,
cottages in the courtyard), village, one tower, harbour (quay, houses, striped lighthouse), bridges (two towers joined
high up by one block on an arch, an oriel on corbels, a balcony on a pillar, a wall walk stepping down a level with
stairs). Only blocks: every tower, roof, arch and stair in them comes from the rules. The castle's ring meets some of
its cells only corner to corner, so the starter closes the wall on the gate's far side (one block more than before):
the gate block then bridges two walls and gets its arch.

Picking on the pieces: a face inside a cell where its column has no block (an arch's passage, a pillar, a corbel's
front, a corbel's top in a passage) offers that empty cell; right-click takes away the block the piece holds up. A
piece's face on the cell's side (an arch's front) offers the neighbour, as a block's side does.

Command-line flags (after `--`): `--cs-starter=NAME`, `--cs-load=FILE`, `--cs-fresh` (empty, never autosaves),
`--cs-shot=PATH [--cs-views=name/yaw/pitch/dist/x/y/z,...] [--cs-wait=S]`, `--cs-cam=yaw,pitch,dist`,
`--cs-target=x,y,z`, `--cs-noui`, `--cs-nobirds`, `--cs-noprops`, `--cs-spin`, `--cs-scare=S`, `--cs-look=`, `--cs-quality=`,
`--cs-look-set=`, `--cs-uncap` (no frame cap, no vsync: the shot prints the fps). `tools/shots.ps1` takes a shot set under the memory guard
(hidden window: a minimized one does not render; the guard has `-WindowMode` for it). Keys: L light, G quality. A shot prints how many
prop instances are on screen (right after an edit of `cs_props.gdshader`, Godot may still be compiling it and skip the
props for a few seconds: take the shot again).

## 8. Tests and tools

`verify-castle-scaper-realistic.bat`: every script compiles; `tests/verify_cs_core.gd` (159 headless checks, 37 of them new for this copy: every light and quality row complete with sane numbers, the rock skirt and the sea floor finite, bounded and fast; the others: the grid's shape and
determinism, blocks and save round trip, the rules (cottage, round tower, wall walk with battlements, courtyard, passage,
doors, towers, the gate an arch), an arch under a block bridging two walls (open passage, piers, band over the crown,
stepped, no door into a pier, closed), corbels under a block hung on a tower and a pillar under one hung beyond it
(probed solid / air, closed), stairs from a courtyard and between two walk levels (steps, gap in the parapet, not in
front of a door, closed), every starter audited closed, 16 random 70-block castles nearly closed, under 3 s, with no
stairs in front of a door, growing arches, corbels, pillars and stairs between them, birds perch; the props: the skin
untouched, at least 2 of every kind on the castle starter, no two props (or a prop and an opening) overlapping and no
point of a prop inside a block, an arch, a corbel, a pillar, stairs or the land on the castle, village, harbour, tower,
bridges and six random castles, the same props every time, birds may sit on chimneys, a 70-block castle and its props
under 3 s); `tests/verify_cs_editor.gd` (19 checks in the windowed scene through the memory guard: real mouse and key
events, the props on screen, a click on the sea, on a roof, on a side, right-click, undo / redo, a drag, a swatch, ten
quick clicks during worker builds, and on the bridges starter a pillar offering the empty cell it stands in and the block
it carries).

Tools: `tools/smoke.gd` (stats + audit of every starter and random castles, and each castle's props;
`--starter=random:SEED:CLICKS` for the suite's 70-click castles), `tools/probe.gd` (layers through a point),
`tools/tri_probe.gd` (triangles along an edge the audit names), `tools/edge_probe.gd` (triangles on a vertical line the
audit names), `tools/pieces_probe.gd` (what holds up each block, the abutment pairs the arch rule weighed, the stairs;
`--near=x,z` the cells and layers round a corner, `--v=N` one column and its neighbours), `tools/incr_probe.gd`
(incremental vs full builds), `tools/pop_probe.gd` (windowed: frames of a block's props shrinking out and springing back,
`tmp/pop_*.png`), `tools/check_scripts.gd`.

Numbers (2026-10-17, with the corner pieces): every starter audits 0 open, 0 non-manifold, 0 flipped, 0 T-junctions
(castle: the gate arch and a flight from the courtyard; harbour: 5 flights; bridges: an arch, corbels, a pillar, a
flight); random castles `random:0-3` clean; 2 of 16 random 70-block castles keep 1 non-manifold edge each (before: 5
with 1-2), both an older case (see section 9). The 16 grow 19 arches, 55 corbelled blocks, 4 pillars and 66 flights.
Full build of the castle starter (84 blocks) ~0.30-0.34 s headless; `incr_probe` 0 mismatches (castle 30 edits,
bridges 25, random:5:70 25). Screenshots: `shots/corner_bridges_overview.png`, `_arch`, `_oriel`, `_stairs`,
`shots/corner_castle_gate.png`.

## 9. My calls (to confirm) and what is not there

- Realistic copy (this folder): golden hour is the default light (the mock-up I liked best: warm stone, teal sea); the two other lights are
  presets of the same scene. The 12 pastel swatches became 12 materials (limestone, sandstone, render, granite, brick ...); the swatches show
  the new colours, so a saved castle keeps its colour indices but looks different. Quoins (alternating corner stones) were tried from the
  edge distances and dropped: the distances also surround every opening, so they drew a zipper round each window slit.
- The mock-ups are image gen (Nano Banana 2 repaints of the game's frames): they say what the light, colour and materials should feel like,
  not what a rule must produce. The rock skirt is mine (the mock-ups all stand the castle on a rocky mound).

- A copy (`castle-scaper`), Castle Forge untouched; pastel plaster rather than stone (Kevin's choices).
- Cells ~4 m, levels 4 m; towers round only when free-standing; 72 / 28 cone vs battlements, banners on tall towers;
  cottage roofs only on single ground blocks; a blocked diagonal corner is pinched (a narrow gap) rather than given a
  corner module.
- Corner pieces (section 3a): an arch only between two abutments one level down (a block held from one side gets
  corbels, a long bridge gets corbels at its ends and pillars between); arches one level deep (a bridge high up has an
  arched underside hanging between its towers, not piers to the ground); corbels on every side over a wall; pillars to
  the ground however tall; stairs rising straight towards the higher wall (not along it: a cell side is too short for
  a 4 m climb along it), one flight per pair of walks, none from the ground to walks above level 0; the castle starter
  gained one block to make its gate a real bridge; a showcase starter (bridges) in the Castles menu.
- Left over: a parapet corner meeting a block one level up only diagonally (the two cells beside that corner empty)
  touches it along a vertical line (random 70-click castles 5 and 10, one edge each, older than the corner pieces):
  the parapet would need the pinch of the level above at that corner.
- Props: the costs and shares in the table above; chimneys also on small flat houses (the castle starter has no lone
  cottage); bunting only between blocks at the same level, its flags a little deeper than the wall colours (pale
  pastel flags vanished); shields and banners in heraldic colours, not the tower's own; hoardings in brown wood; the
  props of a block taken away shrink out in 0.3 s while the block itself goes at once.
- Not there: Townscaper's other per-corner pieces (inner/outer corner trims, roof variety), its decor matched across a
  cell face, laundry lines, lamps that glow at night, gardens, sound and click effects, night, a bigger map, GLB
  export: ranked in `TOWNSCAPER_GAP.md`.

## 11. The landscape: land, roads, trees, rocks and mountains

Kevin 2026-10-18: "I want different build types, road, trees, rocks, mountains, all have different combinations just like the castle, and they all
interact differently with each other for different combinations." The castle's one-action idea carries over: the player picks a **build type**
(the bar above the swatches; **Tab** / **Shift+Tab** or **F1-F6**: Castle, Land, Road, Trees, Rocks, Mountains) and clicks; what appears comes out of
what is round it. Right-click takes one level away; undo, redo, save and autosave cover it (`CSTown.wild`, saved as `"wild"`).

**Data** (`CSTown`): per grid column a record `{l: 1 plain land, h: "mrm.." height levels from the ground up (m mountain 3.6 m, r rock 1.7 m, up to 6),
t: tree levels 0-3 (a tree, a grove, a forest), d: 1 road}`. A click adds one level (`wild_add`): land once; trees up to three, **not in a road**; a road
**not through trees**; mountain / rock levels stack in the order clicked. A right-click (`wild_remove`) takes trees first, then the road, then the top height
level, then the land. A castle block on a column removes its landscape (`wild_clear`); landscape cannot go on castle ground (a courtyard takes land, trees
and a road: a garden).

**Terrain** (`cs_world.gd`, `CSWorld`, `shaders/cs_terrain.gdshader`): every column with earth is a fan of rings from its centre to the corners of its cell.
A corner has ONE height for the four columns round it (the mean of their altitudes, flat at castle ground where castle land touches), so neighbours join
without a crack and a ridge is just a run of mountain columns. A mountain falls away smoothly, a rock keeps a plateau and ends in a cliff; ridged noise
roughens the slope. Coasts get a bank (beach) or a cliff, a skirt reaching below the water. The shader reads height, slope and the column's rock / forest
share: meadow (flowers, patches, straw), forest-floor mould under trees, tundra above the tree line (8.5 m), bedded grey rock where it is steep or high, scree
between, snow above 11 m settling where it is gentle, sand and wet dark stone at the water. `height_at`, `normal_at` and `ctx(v)` (how many neighbours are
water, rock, mountain, road, castle, trees, land) are what every rule below reads.

**Trees and rocks** (`cs_scatter.gd`, `shaders/cs_flora.gdshader`): instanced, code-made meshes (lumpy leaf masses, pine cones, poplar, weeping willow, orchard
tree with blossom, bush, boulders, cut blocks), wind in the vertex stage, backlit leaves, snow on high pines. What stands in a column depends on its surroundings:

| round it | what grows / lies there |
| --- | --- |
| open meadow | oak (1 tree), a grove of oaks with bushes (2), a forest of tall oaks and pines (3 with forest all round) |
| mountain beside it, or high ground (over 4.5 m) | pine, smaller the higher, snowy; none above 8.5 m |
| rock beside it | pine rather than oak |
| castle beside it, no road | orchard tree with blossom |
| a road beside it, a single tree | poplar lining the road |
| water on two sides and low | weeping willow |
| a rock column | boulders (more the higher it stands); against the castle half are cut blocks (a quarry) |
| a mountain slope over 3 m | scree: a few crags |
| meadow next to rock or mountain | pebbles and a fallen boulder |

No tree stands in a road (`road_clear`), none above the tree line.

**Roads** (`cs_roads.gd`, `shaders/cs_road.gdshader`): a road column joins the road columns (and castle blocks) beside it, and what one click makes depends on
how many: **none** a plaza with a ring of standing stones; **one** a dead end (a round turning place, a lamp, a stone); **two** a smooth bend or straight
(a quadratic curve through the column between the edge midpoints); **three or more** a junction (a hub, a signpost, and with four a well). The surface comes
from the context: **cobbles** beside the castle, in a courtyard, at a junction and at a door's apron; **gravel** climbing a mountain or beside rock; **packed
dirt** with ruts and a grassy verge elsewhere; where the road climbs the shader cuts steps. Between a road and a higher rock column a **retaining wall** of cut
blocks. A road column with **no earth under it** is a **jetty** (a timber deck on piles, a lamp at the end) with one neighbour and a **bridge** with two: a
**hump-back stone bridge** with parapets where it meets land, a **timber trestle** with rail posts where it only meets more bridge; decks take clicks and
shadows, and a road next to a castle block makes a paved apron at its door.

**Castle meets landscape:** land is flat at the castle's ground, and the castle's rock skirt is left off wherever land touches it; a courtyard with land is a
lawn, with trees an orchard garden; a rock column against the castle makes a quarry; a road runs to a door; a mountain behind the castle shows over its roofs.

Starters: **landscape** (a mountain, rocks, a wood, a road) and **kingdom** (the castle in its country, with a bridge, a jetty, a willow shore and an orchard).
Tests: core 195 (the column rules, save round trip, flush heights, species by context, no tree in a road or above the line, roads by class, jetty, determinism,
under 1.5 s), editor 30 (Land / Trees / Road / Mountain picked and clicked with real events, refusals, undo, a castle block replacing them).
Costs on High (1080p, quiet GPU): the kingdom 98 fps (castle alone 131-175).
My calls to confirm: cells of land at the castle's level, 4 rings per cell, mountain 3.6 m a level, snow at 11 m; roads only between cell edge midpoints (no
diagonal shortcuts); no rivers, lakes or waterfalls yet (the water is the sea); trees keep their species by neighbours, not by a saved choice.

## 10. Open (realistic look)

- Done in round 2 (see section 6): masonry parallax, string courses, ivy, window glazing, displaced waves, swash foam, cirrus, rays, far islands,
  a colour table per light, Dusk with lit windows, smoke, gulls, a boat, dust and splashes.
- Still not done: chipped, leaning masonry silhouettes (the walls are still clean planes, the parallax is only in the shading; a displaced mesh or
  merlon chips would need geometry in `cs_build`, risking the weld audit); a plinth flare; spray particles where waves break; rain and mist
  particles in Overcast; the sea has no horizontal Gerstner motion and no wind on the boat's sail; the dusk look has no Tripo mock-up; SDFGI is the
  dear part of Ultra; the boat does not avoid a large castle (it circles at 58 m).
