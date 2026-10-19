# Castle Scaper Hex — design (Castle Scaper Realistic on a double hex grid)

**This is a copy of Castle Scaper (2026-10-17) with a realistic look**, asked for by Kevin: "make a copy of castle-scaper
and use realistic rendering and post processing, realistic textures for castle. use image gen from tripo if needed but use
procedural as much as possible for maximal flexibility. use a few mockups renders of full castle for final look and use it
as reference". Nothing of the rules, the engine or the props' placement changed except for the grid (section 0; sections 2-5 and 7 are
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

## 0b. Round 4 (2026-10-19): a quarter-area default cell, a ladder of sizes, walls that merge by cell width

Kevin tested round 3's build (a93f577) and wrote: "I want smaller grids.... new straight walls still need to merge". Two things were done.

**1. Smaller cells: the default is now 1/4 of the first area, with a ladder 1, 1/2, 1/4, 1/6, 1/8.** `CSGrid.DIVS = [1, 2, 4, 6, 8]`, `DEFAULT_DIV = 4`, `MAX_DIV = 8`
(`--cs-cell=N` takes 1..8; a save names its size in the grid tag, "dodeca-2/4"; older saves open as they were). The Cells button / H goes through
12-sided 1/4 (default), 1/6, 1/8, 1/2, 1/1, then the hexagons 1/4, 1/2, 1/1 (Shift+H the other way). The default cell is a dodecagon of 5.4 m2 (4681 cells on
the same island; 2.6 m across the flats, side 0.695 m). Measured on this build machine (4 vCPU, software only: **no GPU, so no frame time**; the CPU
numbers and the amount of geometry are what there is), starter castle plus one click on the open sea, CPU in ms (`tools/cost_probe.gd`):

| cell | cells | side | grid | a hover (`nearest`) | starter blocks | full build | **one click** (rules + plan) | props | + upload | castle tris | grid overlay tris |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1/1 | 1141 | 1.39 m | 109 | 37 us | 74 | 1.6 s | 237 (39 + 246) | 271 | 28 | 31 k | 14 k |
| 1/2 | 2269 | 0.98 m | 214 | 42 us | 125 | 2.8 s | 451 (61 + 378) | 383 | 55 | 52 k | 27 k |
| **1/4** | 4681 | 0.70 m | 440 | 42 us | 151 | 4.0 s | **618 (99 + 532)** | 523 | 84 | 67 k | 56 k |
| 1/6 | 7057 | 0.57 m | 701 | 42 us | 176 | 4.5 s | 710 (113 + 558) | 614 | 88 | 76 k | 85 k |
| 1/8 | 9577 | 0.49 m | 953 | 43 us | 176 | 4.5 s | 868 (135 + 664) | 611 | 104 | 76 k | 115 k |

A click's whole job on the worker thread is the incremental build + the props + the mesh and collision upload: about 0.54 s at 1/1, 0.89 s at 1/2, **1.2 s at 1/4**,
1.4 s at 1/6, 1.6 s at 1/8 on this machine (the editor stays responsive meanwhile: the build runs on `WorkerThreadPool`, the old castle is drawn until the new one is
ready). Before the cost work below, the same click was 2.2 s at 1/4 (build 0.78 s, props 1.4 s, upload 0.08 s; `nearest` 162 us). What was costing:
`CSGrid.nearest` and `cells_along` hashed points into cells of a fixed 6 m, so a lookup tested 4x more points at 1/4 (162 us; now the hash cell is 1.16 cell spacings
and a hover costs 42 us at every size, `_hs`); `CSBuild._find_land` flooded the sea over the whole island at every click (97 ms at 1/4; now only a box of the town
grown by two cell spacings, `CSGrid.points_in_rect`; the core suite checks it finds the same land as the whole-island flood, `tools/land_check.gd`); `CSProps._bunting`
cast a ray of `grid.nearest` calls from every side of every block (1062 ms at 1/4: a small cell has more sides but not more flags, so the share of sides that try is
`1 - 0.4 x cell` and the ray step grows as the cell shrinks; now 207 ms) and `_sides` is memoised. Left: the plan's own fixed cost per click (it walks all 2679 layers
of the starter castle and reuses 2673 of them: register 61, pairs 39, split 85, sub 48, classify 29, walls 35, ledges 139 ms at 1/4; `tools/plan_profile.gd`), the props'
`_solve` (214 ms) and `_bunting` (207 ms). Not measured (no GPU): the frame time. What there is to draw grows from 67 k castle triangles (1/4) against 52 k (1/2); the
always-visible grid overlay (one fan per cell side, faded out away from the pointer) from 27 k to 56 k triangles at 1/4 and 115 k at 1/8, one alpha-blended
unshaded mesh, and the prop instances 1331 -> 1571 at 1/4: that is a modest load for a real GPU, but it is the first thing to look at if a frame is slow.

*Defects at each size* (`tools/cell_stress.gd`: the 14 starters + 16 random click-built 70-click towns, half with a random style per click; defects = open edges + non-manifold
+ flipped + T-junctions of the audit; hexagons likewise): **1/1 (the core suite) and 1/2 (22 towns): none; 1/4 (the default): 0 in all 30 towns; hexagons 1/4 and 1/2: 0 in 30; 1/6: 3 towns of 30
(the castle and kingdom starters 9 open edges each, one random castle 12); 1/8: 20 towns of 30, 7169 defects (the castle starter's courtyard ground is open, `shots/cells_ladder.jpg`,
bottom row, shows the white floor)**. The practical minimum is therefore **1/4** (the default): below it blocks still build and can be played, but the skin has small cracks in
a tenth (1/6) to two thirds (1/8) of the towns and the doors are 0.34 / 0.30 m wide; 1/6 and 1/8 stay in the ladder as experimental steps (not chased: SPEC section 10 lists them).
What made 1/4 clean (they had 6 of 22 towns with 740 defects): the arrow slit's half width was a constant 8 cm, so on a side of 0.70 m its edge fell 3.2 cm from the
parapet's inner corner on the shared side (`2 x PT`; at full size the two lie 1.5 cm apart and weld, the weld distance `CFPlan.SNAP` is 3.5 cm) and the plan kept two
vertices 3.7 cm apart: `SLIT_HW = 0.08 x FS` keeps the ratio. Recess and door depth (`0.5` and `0.55` x FS: two windows of neighbouring sides cut into each other), the door
leaf's thickness, the notch's reach past the parapet (`NOTCH_EXT`), the parapet stub's bite (`STUB_BITE`) and the margin at the notch ends scale with the cell too. Heights
do not scale (a level is 4 m: a block is a post 2.6 m across and 4 m a level, so the castle is made of more, slimmer towers; the same castle at 1/2, 1/4, 1/6, 1/8 is in
`shots/cells_ladder.jpg`, rendered with software OpenGL at medium quality, not with the real look's Forward+ GPU path): the wall is 0.95 m thick, the parapet 0.15 m, a crenel
0.22 m, a door 0.42 m wide and 2.3 m tall, a window 0.34 m wide. The layered hexagon lattices (`--cs-grid=layer|layer3`) stay as an experiment switch, not in the H cycle.

**2. Walls that lie together merge: the rule is in CELL WIDTHS.** `CSWalls` (`scripts/cs_walls.gd`). W is a cell width, the distance between the middles of two
neighbouring cells (5.19 m at 1/1, 3.67 at 1/2, **2.60 m at 1/4**; a single wall is 1.9 m x cell thick: 0.95 m at 1/4). Two walls merge when they are parallel (within 0.6 degrees,
either way round) and

* **side by side:** the lines of two single walls are at most **1.5 W** apart centre to centre (7.8 m at 1/1, 3.9 m at 1/4; for thicker walls: the gap between the strips at most 1.5 W
  minus one wall thickness, so a rampart keeps taking the walls beside it) **and their spans overlap or touch;**
* **end to end:** the spans are at most **1 W** apart (5.2 m at 1/1) when the strips touch; the nearer the strips are (the smaller the side gap), the larger the gap along the
  line that still counts, falling linearly from 1 W to nothing as the side gap grows from 0 to its 1.5 W limit (two walls that are beside each other AND a cell past each
  other's ends do not make a slab of empty ground);
* the merged wall is at most **3 W** wide (15.6 m at 1/1, 7.8 m at 1/4: about eight single walls); a wall that would push it past that stays a separate wall;
* the merged wall is the bounding rectangle of the two in their common direction: **width = the union of the two strips, length = the union of the spans**, heading the first wall's (so
  it stays on one of the 12 / 16 / 24 directions); a third wall merges into the thick one and widens it, up to the 3 W; two walls laid end to end on one line become one longer wall; the
  colour is the longer wall's. The closest pair merges first (`CSWalls.merge_list`, bounded: 400 rounds), until nothing merges. Walls at an angle never merge: they stay separate with one joined
  outline and the corner towers (round 3).

It runs (a) when a wall is built (`add_wall`, one undo step restores both walls); (b) **in the drag preview**: `CSWalls.with_new(walls, new, base)` returns what the wall being
dragged will be once built ("wall", "absorbed"), the ghost prism is that merged wall (`CSMain._stroke_merged`, cached per pointer stop) and the status line says
"Straight wall at 30 deg (12 directions), 7.8 m long: joins 1 wall into one 3.2 m thick wall of 9.1 m. Release to build it ..."; (c) when a save loads (`CSWalls.settle`, so walls of an old
save, laid when the rule was a wall thickness, merge too). The merge distance scales with the cell because the rule is in W: a save's walls are on the cell size the save names.

*Kevin's latest autosave* (24 walls, `tools/autosave_walls.gd`, `KEVIN_WALLS` in the core suite): the three heading-120 walls at (-70.06, 31.46), (-64.87, 31.46) and (-67.47, 17.98) (4.49 m
and 4.49 m apart, 2.6 m between their strips) and the 300-degree wall at (-80.44, 31.46) laid the other way round beside them become **one wall 28.5 m long and 15.4 m thick**; the rest do
not merge under this rule: 24 walls become 21. (The other parallel pairs are at least 5.2 m apart along their line (e.g. the 60-degree pairs at 4.49 m side distance but 18 m end to end), at 8.99 m or more
side distance (two cells), or the same line at an angle; the walls that start at (-44.11, 13.48) are at 270 and 210 degrees, so they stay two walls with a tower on their joint.) The core suite checks
that every original wall lies inside one remaining wall (a merged wall is at least the union), that no two parallel walls remain within the merge distance (computed independently of `CSWalls`), that the
same walls scaled by the cell merge the same way on 1/4 cells, and that the result builds closed. castle_004 (round 3's 30 walls) is still 30 -> 18.

**3. Kept:** drag preview then build on release, a plain click builds one block, Esc or the right button cancels, the straight wall button / T, 12 / 16 / 24 directions, the Cells switch (button / H), corner towers.

**Tests:** core 0 failed (`_cell_sizes` over the ladder 1, 2, 4, 6, 8, scale of the sizes, 1/4 and 1/2 closed, 1/6 and 1/8 tower starters build; `_land_box`; `_merging`: the numbers above, the
preview, Kevin's list), editor 0 failed (the merge by a second drag one cell beside the first: the preview is the merged wall, the release builds ONE wall 3.2 m thick (the strips are 2.25 m apart at 1/4: union 3.2 m, more than double the 0.95 m of one),
one undo step, closed; the Cells switch through the new ladder).

## 0a. Round 3 (2026-10-19): smaller cells, merged walls, corners, wall directions

Kevin tested the round-2 build (12-sided cells at the hexagon's size, free straight walls) and found it "not quite there yet": the cells are still too big
("I want smaller grid... maybe double meaning more hex layered? experiment with it"), walls laid in layers should merge into a thicker one, the corners
look wrong, and "I want 12 directions (is 12 okay? how about 16)". What was done, in his order:

**1. The cell size is a setting (`CSGrid.div`, `CSTown.grid_div`, `--cs-cell=N`, saved in the grid tag as "dodeca-2/N").** A cell has 1 / div of the area of the
round-2 cell (21.65 m2): its side and spacing scale by `cell = 1 / sqrt(div)`, the island stays as big (`radius = RINGS / cell` rings), so a smaller cell
means more of them (div 2: 2282 buildable cells of 10.8 m2, side 0.98 m; div 3: 3423 of 7.2 m2, side 0.80 m). `CSBuild.set_scale(side, cell)` (every build)
turns what used to be constants into variables scaled by `FS = clamp(side / 1.3906, 0.2, 1)`: the parapet, crenels, doors, windows, arches (pier,
span limits, fewer courses on narrow arches: `ARCH_FR_SMALL`, `ARCH_FR_TINY`), pillars, stairs, the prop layer's thresholds and the straight wall's
thickness (`WALL_THICK = 1.9 * cell`). Heights do not scale (a level is 4 m). The arch rule gained "an abutment that hangs is not an abutment" (an arch next
to a corbelled block was left in the air at the small sizes). Both cell kinds scale (hexagons too).
*Experiments, same castle, `shots/cells_comparison.jpg`:* 12-sided at 1/1, 1/2, 1/3 (clean; the castle reads best at 1/2, the walls are 3.7 m across and
still take doors and windows; at 1/3 the cells are 2.7 m across and a block is a post: it works, the starter castle is simply made of more, smaller
towers); hexagons at 1/2 (clean, but the sides are 1.7 m and the ring of towers looks coarser than the dodecagons); **layered hexagon lattices**
(`--cs-grid=layer`: lattices turned 0 and 30 degrees; `layer3`: 0, 20 and 40 degrees; a block in the Voronoi cell of every point of the union, built with
`CSGrid._generate_layered`): the cells come out as irregular 4- to 12-sided polygons of 19-81 m2 (layer) or 21-202 m2 (layer3) with sides from 0 to
12 m, slivers need pruning and some stay, so no uniform size and no regular look: not viable, kept only as `--cs-grid=layer|layer3`, not in the H cycle.
**(Round 3: the default was the 12-sided cell at 1/2 of the area, `DEFAULT_DIV = 2`, and the H cycle 12-sided 1/2, 1/3, 1/1, hexagons 1/2, 1/3, 1/1; round 4 (0b) made it 1/4 and the ladder 1, 1/2, 1/4, 1/6, 1/8.)** Saved castles
remember grid and size; a save from round 2 ("dodeca-2") is div 1 and opens as it was.

**2. Merging walls (`scripts/cs_walls.gd`, `CSWalls`).** A wall is `{x, z, deg, len, w, c}` (a save of round 2, `{v, deg, len, c}`, is put on the grid it
names by `CSWalls.normalize`: from the middle of cell v, one thickness wide). Two walls merge when they are parallel (within 0.6 degrees, either way
round) **and lie close (round 3: a wall thickness apart; round 4 changed the rule to 1.5 cell widths side by side and 1 cell width end to end, section 0b)**, and the result is at most 3 cell widths wide. The merged wall is
the bounding rectangle of the two in their common direction: width = the union of the two widths, length = the union of the spans, heading kept (so it
stays on the active direction). The closest pair merges first, repeated until nothing merges (`CSWalls.merge`); it runs when a wall is added
(`main.add_wall`: one undo step restores both) and when a save loads (`CSWalls.settle`, in `_adopt_grid` and at start). Walls at an angle never merge; their
parapets follow the outline of the union (`_wall_loops`). *castle_004* (Kevin's 30 walls, `tools/castle004_list.gd`, `tools/merge_probe.gd`):
30 -> 18 walls, one of them 14.9 m thick (eight of his collinear walls in layers at heading 90/270); the rest are single walls at other angles or too far
apart (a row's spacing is more than a wall thickness plus the gap).

**3. Corners (`scripts/cs_wall_joints.gd`, `CSWallJoints`; built by `CSBuild._walls`).** A wall is a rectangle, so a bend left a square notch outside and a
thin wedge inside, and ends were bare cuts. Now: a **round tower** (16 sides, a circle that covers the whole squared end: radius = half the thickness x sqrt 2
+ 15 cm, kept 30 cm clear of the sides of other walls: `_clear_radius`, a thin lens of overlap or a hair-thin gap cannot be welded) stands on every free end
and bend of a wall that is at most 2.6 thicknesses wide, one level high + `TOWER_RISE` 1.4 m, with its own ring of battlements (`_ring_top`, shared with the
lone-tower battlements); two towers whose circles come within 60 cm of each other become one (the hull of both); an end buried in another wall gets none; a
merged thick wall ends in a flat capped end. **Fills:** where two walls meet or cross at less than 75 degrees (`_fill`: arms either side of the joint,
neighbours by angle) the wedge between their inner sides is filled by a triangle from the point where the inner sides cross to where the gap is 0.6
thicknesses wide, so no sliver remains and the parapet turns round the filled corner. Notches are not cut within a tower's circle (`near_tower`) or over a block
(`_over_block`: a notch is a CUT and would cut into a block the wall runs through). `CSWalls.robust` lengthens a wall by 6 cm steps where a corner of it comes within 10 cm of
another wall's side without being on it (the outlines would meet in a sliver edge that cannot be welded); the saved wall is untouched. Round tower was
chosen over a hexagon or a mitre: it hides the end of the rectangle at every angle (a mitre only mends a bend, not an end, and fails under 30 degrees),
and it is the shape of the game's other towers. `tools/corner_gallery.gd` writes the picture town (`shots/wall_corners.jpg`: before / after),
`tools/corner_probe.gd` audits every bend, crossing and T at every angle of the 12, 16 and 24 direction sets at several places on the grid.

**4. Wall directions (`CSTown.wall_dirs` 12 | 16 | 24, `CSGrid.DIR_COUNTS`, key R, the Directions button, `--cs-dirs=`).** `CSGrid.snap_direction(d, count)` snaps to
multiples of 360 / count degrees. Along a grid line (a multiple of 30 degrees) the wall ends where the middle of a cell lies on the line (`line_stops`),
as before; along any other heading (22.5, 45, 67.5 ... with 16; 15, 45, 75 ... with 24) it ends every half cell spacing (`CSGrid.wall_stops`). The count is a
setting of the castle: saved ("wall_dirs"), kept by undo, shown on the button ("Directions: 16 (R)") and in the cue while dragging ("Straight wall at 22.5 deg (16
directions), 11.0 m long"). Walls are independent of the cells, so merging, corners and the towers work at every heading; what a non-lattice heading
changes is only where a wall's sides fall against the cells' corners and a castle's battlements: 12 and 16 directions audit clean (0 defects in 80 towns x 5
walls each) before the notch rule, and 4-5 of 100 towns x 5 walls at 16 directions and 2-3 at 24 afterwards (a wall off the grid's lines through a castle can meet a block's land or battlements in a sliver; at 12 directions the same probe finds none): walls through castles at 16 and 24 directions are about 1 in 130 walls with a rebuild defect, a few cm of stray geometry rather than a hole in the castle. Lone walls, bends, crossings and Ts at every angle of every direction count are clean (`tools/corner_probe.gd`, 490 shapes).

## 0. The double hex grid (2026-10-19)

History: Kevin first wanted an organic grid, then regular hexagons (2026-10-18), then (2026-10-19): "I want a double hex grid, meaning there
are 12 sides" and, asked what he meant, "two regular hex grids overlaid, one rotated 30 degrees, so lines run in 12 directions". My first version
made the cells regular dodecagons of side 2.887 m (93 m2), four times the hexagons they replaced; Kevin: "double not double the size..... just
meaning double the edges and shape". **Read as: twice the edges (12 sides instead of 6), the same size**, so the dodecagon was rescaled to the
area of the old regular hexagon and the rest of this section is about that grid. (If "shape" also meant the plain hexagon should stay available:
it does, see "Plain hexagons" below.)

**The cells: the truncated hexagonal tiling (3.12.12), scaled so a dodecagon is 21.65 m2.** A building cell is a regular **dodecagon**: 12 sides,
150 degree corners, side `SIDE` = 1.3906 m, 5.19 m across the flats, 21.65 m2: the same area as the regular hexagon of side 5 / sqrt(3) it replaces,
and about the same width (5.19 m across against 5.0), so a tower, a house, a wall walk, a courtyard and the board itself are the size they were:
`RINGS = 20` rings of dodecagons round the middle one (spacing `D_SPACING` = 5.19 m), the outer ring sea, **1141 buildable cells** (exactly as many
as the hexagon grid had) in 1261 dodecagons. The dodecagons touch their six lattice neighbours along a whole shared side, and in the gap between
every three of them is an equilateral **triangle** of the same side (0.84 m2): 2400 of them. A dodecagon has 12 neighbours (6 dodecagons and 6
triangles, alternating), a triangle 3. The sides run in 12 directions (a dodecagon's 12 sides are 30 degrees apart; the six orientations 0, 30,
... 150 degrees), the lines of a hexagon grid and of the same grid turned 30 degrees.

**The triangles are not buildable: I chose non-buildable filler, not merging.** At 0.84 m2 (a 1.4 m triangular post) a triangle is too small to
hold a block, and a merged cell (a dodecagon with the triangles at some of its corners) would not be convex and would break the rule that every
corner is shared by exactly three cells that all touch (two blocks never touch at only a corner). So the triangles stay in the grid, as points
of the graph with three neighbours (`buildable` is false for them, a click over one goes to the nearest dodecagon, `nearest(p, false)` finds
the cell itself) and they are little pits between the blocks: `CSBuild.fill` fills a pit with land (a footing at the water, ground at the shore)
when two of the three cells round it are land, so the shore has no notches (`land_all()` is what the shore and the landscape see); the landscape
(`CSWorld`) lays ground across a pit when two of its three dodecagons have ground, and its neighbour counts (`ctx`) ignore triangles; roads
join only dodecagons. Every wall of a block that faces a pit is an ordinary open side (windows, crenels).

*Why this and not the faces of the full overlay.* Drawn in full, two regular hexagon outline sets turned 30 degrees against each other
cross in 4- and 6-valent points at irregular places and cut the plane into many small faces of different shapes (triangles, kites, squares,
irregular pentagons, slivers of a few cm). The block rules need: (1) every cell a clean convex polygon; (2) every cell corner shared by
exactly three cells that all touch each other (a crossing of four lines would be a corner shared by four cells, two of which only touch at that
point: the "pinch" case this project removed); (3) a board that is a hexagon-ish island; (4) no feature of a few cm, because the layer engine
merges vertices closer than 3.5 cm and a sliver cell would be lost or leave a crack. The 3.12.12 tiling is the one 12-sided pattern that
meets all four: its edges lie on the 12 directions of the two overlaid grids, it is regular (all sides equal, two corner angles), and every
corner is trivalent.

**Blocks stand on grid points** (the dodecagons' centres come first: `d_count`, then the triangles'). Queries: `nearest` (the cell that contains
the point, `_in_cell`), `dual` / `cells[v]` (the cell polygon), `face`, `wedge`, `neighbour_towards`, `index_of`, `buildable`, `is_dodecagon` (a
building cell), `is_whole` (a cell off the sea ring, triangles included), a spatial hash (`HASH` = 6 m) for picking, and for lines `snap_direction(d)`
(the grid direction, a multiple of 30 degrees, nearest to a vector), `cells_along(a, b)` (the cells a segment passes through or runs along, in
order, with a 2 cm tolerance so a line along a shared side takes the cells on both sides) and `line_stops(a, dir, max)` (where a straight wall may end,
below). Saved towns carry `"grid": "dodeca-2"` (or `"hex-2"`); a save from another grid loads as an empty sea instead of meaning other cells.

**Plain hexagons too.** `CSGrid.generate(seed, rings, CSGrid.KIND_HEX)` makes the grid of before (regular pointy-top hexagons, side 2.887 m,
21.65 m2, 1141 cells, six neighbours): the Cells button next to the build types, the key **H** (it asks twice, because it starts a new empty sea: a
block of one grid means nothing on the other) and `--cs-grid=hex` switch to it and back; `CSTown.grid_kind` remembers it in a save. The default
is the 12-sided grid.

**Straight walls are not cells.** A straight wall (SPEC section 7) is one rectangle `WALL_THICK` = 1.9 m wide along a grid direction that cuts across
the cells it passes; it ends at the middle of a cell (`line_stops`: along a row of dodecagons every 5.19 m, along the 30 degree lines, which run
along the sides between two rows, every 3 m or so), so its end face and its two sides keep at least 0.25 m clear of every corner of the grid (the
corners of the grid lie 0.70, 1.2, 1.9 and 2.6 m off such a line; 0.95 m is between the first two): no sliver the layer engine would merge.

What follows downstream (the rules were written for hexagons with 2.887 m sides; cells with 1.39 m sides and 150 degree corners need):
- **Thinner parapets and shorter features.** The parapet is `PT` = 0.3 m thick (0.45 m left open edges and two-cell walks defective: its inner
  offset against 1.39 m sides); stubs run `STUB_RUN` = 0.18 m past the parapet's inner corner; a crenel is `NOTCH_W` = 0.45 m, one in the middle of
  a side, 0.2 m from a corner (and every other side of a lone tower's ring); a door is `DOOR_HW` = 0.42 m half wide, a window 0.34, both needing
  a side of `MIN_SIDE` = 1.3 m; a flight of stairs 1.0 to 1.1 m wide fits the same side with 0.2 m clear at each end (the flights between two walk
  levels do not fit between the parapets of a 1.39 m side: stairs come from courtyards only); lanterns stand 0.6 to 0.7 m from a door.
- **Props sized to a 1.39 m side:** shields on sides of 1.2 m, hoardings and corbels over 1.3 m, one crate or barrel spot in the middle of a side
  (two on a side of 4 m), ivy 0.6 to 1.4 m wide, torii in front of sides of 1.3 m.
- **150 degree corners.** A roof's eave overhang pushed out on one side and not on its neighbours pulls the side in at both ends by 1.7 times the
  overhang, so the outline could fold over itself (a facet wound the wrong way); `CSStyleBuild._fit` scales the overhangs down until every side still
  runs the way it did. The cap on an overhang is a share (`EAVE_FRAC` = 0.3) of the room to the neighbouring block, one value for the whole cell.
- **Starter castle:** the curtain is the 18 cells in the band 14.5-20.5 m (a closed ring: the cells touch side to side), four towers, a gate,
  a keep of the middle cell and two opposite big neighbours (three arms on the hexagon grid), cottages in the courtyard.
- The grid overlay draws the cells' own outlines (a fan per cell); `--cs-showgrid` shows all of it, lifted over the swell, also in shots.
- Not copied: the combinations viewer (its numbers were measured on another grid and do not hold for this one).

**What a regular grid broke, and the fixes** (found with `tools/hex_probe.gd`, minimised with `tools/defect_min.gd`; these were found on the regular hexagon grid, the double grid is the same lattice-exact case). The old grids were
irregular, so nothing ever lined up; on a perfect lattice points, edges and passages are exactly collinear or exactly touching, and the
plan engine met cases a random grid hardly shows. With jitter 0 and no changes 30 of 105 random castles had a defect (the audit: open
edges, non-manifold edges, flipped faces, T-junctions); now none of 1612 do (800 towns of one style and 800 of mixed styles in four ranges of seeds, plus
the board-edge rings, `tools/hex_probe.gd --towns=200 --from=0|1000|2000|3000`). Each fix below was needed: taking it out again brings defects back
(measured: SNAP 120 of 403 towns, `ARCH_MAX_W` 15, the clipper's chord test and the sliver rule together 14 of 1209):
- **Point in polygon.** `Geometry2D.is_point_in_polygon` triangulates its polygon first, and a layer's outline with split vertices along a
  straight run can come out of that triangulation with a gap: a point in the middle of the layer was reported outside it, one side of a wall
  was classified as empty and a block's underside vanished (1 town in ~250). `CFPlan._pip` is a plain crossing-number test.
- **Two features 2.3 cm apart.** A corbel's clip line and a parapet stub corner fell 2.3 cm apart on a cell side, just outside the plan's 2 cm
  vertex merge (`CFPlan.SNAP`): two vertices where one was meant, an unbalanced ledge edge, and the whole underside of the block lost.
  `SNAP` is now 3.5 cm (no feature the rules make is that small: their clearances are 6 cm and up).
- **Chords through collinear points.** The ear clipper (`CFTri`) tests whether a loop point blocks an ear with cross products and a
  tolerance of 2e-6, far below the float noise of a 20 m chord, so a chord along a straight run of cell corners (a row of land cells)
  could miss a corner by a fraction of a mm and leave a crack. An ear is now also blocked by a loop point within 2 mm of its chord.
- **Slivers.** A corner of a straight run clipped as an ear is a triangle with a tip within a mm of its chord; it was dropped as
  "zero area" or oriented by float noise, which left the edges to its middle point open or flipped. A sliver (height under 3 mm) is now
  kept and wound as the triangulator made it (`CFPlan._emit_ledge_tri`, `CFMesh.push_tri3(order)`).
- **Neighbouring arches.** Two arches side by side with parallel passages each cut a half-width of up to 2 m in cells 2.5 m apart, so
  their crown courses met exactly on the shared wall (four faces on one edge). `ARCH_MAX_W` is 1.1 m: a wall of at least 0.3 m is left
  between any two passages.
- **Stairs from a courtyard** (not a defect, a lost feature): the 1.5 m clearance from a door was measured to the door side's whole line,
  and on a regular hexagon the doors of the two sides next to the flight's side are 0.73 m from the flight's edge, so no flight from
  the ground ever fitted. Those two sides now need 0.7 m, every other door side 1.5 m as before.

**What the 12-sided cells broke, and the fixes** (same tools; `tools/defect_min.gd --town=N --style=S [--at=x,y,z]` also lists the plan's layers round
any point of the minimal town). Cells with 12 sides, 150 degree corners and sides of 1.39 m broke rules that had only ever met six sides of 2.887 m;
each is fixed at the source, none is a special case for the audit (the whole list of retuned sizes is in the list above):
- **Parapet thickness**: with `PT` = 0.45 m nearly every two-cell wall walk had open edges (every town of a first sample of 15 had a defect); 0.3 m
  and everything else equal: none. The parapet's inner offset against sides of 1.39 m is what failed.
- **The sea reaches the triangles from the cells beside them**, not from every unbuildable point, so courtyards are still enclosed
  (`_find_land`); a pit between cells never counts as land of a cell (no door opens on a pit).
- **Eaves**: one cap for the whole cell (`EAVE_FRAC`), and `_fit` scales overhangs down until no side folds over. The outline of a roof whose open
  side lies between closed ones was a bow tie on a 150 degree corner (a facet wound the wrong way).
- **Roof apexes**: the planes of a regular outline meet in one point that every facet computed with its own rounding, 2e-5 m apart (non-manifold
  and flipped faces at the apex of a hip roof); the facets of `CSRoofs.ridge` now share one point, and a pyramid's last ring is its inner
  outline itself, not a lerp to it.
- **Arches**: a cell with a hanging block of its own, or whose neighbour hangs, gets no arch (`_hangs`, `_mouth_blocked`): the corbels of the
  hanging block and the passage's mouth would cross on the shared side.
- **Pillars** fit the room of a small cell (radius `room - 0.6`, clear of the parapet's inner line); **stairs** are found by marching a segment
  along the side (`_ray_in`) instead of probing points, which lost every flight on a 150 degree corner.
- **Corbels**: each course is cut to its own side's wedge (the bisector lines at its two corners), so two courses meet along the bisector
  instead of overlapping, and no two courses cross inside a cell.
- **Straight walls**: a union of rectangles chained into loops by position within 3 mm (rounding to a millimetre failed when a corner fell on .5).

**Stress numbers** (`tools/hex_probe.gd --towns=150 --styles=0,-1 --from=N`: 150 click-built 70-click castles of one style and 150 of mixed styles, plus the
board-edge rings, 303 audited towns per range). 12-sided grid: ranges N = 0, 1000, 2000, 3000, 4000, 5000, 6000, 7000 and 8000, 2727 towns, **0 defects** (a
first sample of 15 towns had a defect in every one before `PT` came down to 0.3 m; after that none was seen, and only the first 60 towns were looked at
while tuning). Hexagon grid (`--grid=hex`, 100 towns of each kind): 203 audited, 0 defects. Straight walls (`tools/wall_probe.gd`: 3 random walls of
random heading and length over a 40-click random castle, 120 towns, 360 walls): **1 town with a defect, town 15** (non-manifold 2, flipped 4: a crenel's
corner of a wall falls exactly on a crenel's corner of a block the wall runs through, the wall's parapet over the block's roof); walls alone (40 towns of 4
random walls each, crossing at any angle): 1 in 60 (town 18: two walls cross at 30 degrees, a thin wedge of parapet); the shapes a player draws
(`tools/wall_shapes.gd`: rings, L, T, cross, star, end to end, on top of each other) all closed.



## 1. The grid (`scripts/cs_grid.gd`, `CSGrid`)

Section 0 is the grid: the double hex grid, dodecagons and triangles of one side length, blocks on their centres, every cell corner shared
by three cells.

## 2. The blocks (`scripts/cs_town.gd`, `CSTown`)

A dictionary `key(v, k) = v * 64 + k -> colour (0..11)`. Levels 0..15, 4 m each. Saved as JSON with the grid's seed and
radius. That is the whole game state; undo keeps whole copies (300 steps).

## 3. The rules (`scripts/cs_build.gd`, `CSBuild`)

A block becomes what its neighbours make it. Rebuilt from scratch (or incrementally, see 4) after every click.

- **Land and sea.** A flood fill from the border: an empty cell the sea cannot reach is a **courtyard**; a cell under a
  block that bridges over it is a **passage** (a gate); a ground block stands on **land**. Land is a low sandstone
  plinth 0.6 m above the sea; everything else is sea.
- **Cell shape.** A cell is the grid point's dual cell (section 0), and its corners are never shared with a diagonal block. Same
  colour, same shape and same roundness stack into one body.
- **Tower.** A column of two or more blocks whose top touches no other top is a tower. Free-standing from the ground up
  it is round (16 sides); rising out of a wall it keeps its cell's shape. Its top gets a cone roof (72%, seeded by the
  grid point; red tile on warm colours, blue slate on cool ones; a pole, and a banner on the tall ones) or a ring of
  battlements (28%). A crowded top (a neighbour higher) stays flat.
- **Cottage.** A single block alone on the ground gets a pyramid roof.
- **Wall walk.** Tops that touch other tops at the same level form a walk: paved, with battlements (0.45 m thick,
  1.05 m high, notches every ~1.45 m away from corners) along every open edge. Where the parapet meets a taller block, a
  stub runs a parapet's width along that block and bites 0.15 m into it (`STUB_BITE`), so the solids overlap rather
  than touch along one line.
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
  blocks alone; the fill then counts as a block (`filled()`) for everything else: its neighbours' outlines, walk edges, openings, round columns. A fill shut in on every side stays solid. The castle starter's
  gate passage is one; a bridge between two towers higher up is one too (its piers hang from the towers).
- **Corbels.** Every other side whose neighbour has a block one level down (the block overhangs that wall) gets a
  stepped corbel: three courses reaching 1.0 / 0.65 / 0.3 m out of the wall (at most 45% of the cell's depth), over the
  top 1.1 m under the block, clipped from the block's own outline so its walls run on down. Its back is the wall's **own
  face**, which the corbel meets flush (a sliver of air would leave a tip that is a line two solids touch along). An arch's feet over a wall one level down get corbels too, clipped to the piers (under the passage a course's
  side would meet the underside of a block beside it along a line). Round columns bear nothing (they stand back from
  their sides).
- **Pillar.** No neighbour with a wall below: a pillar down to the next block of its column or to the land (every
  column has land under it): a base, a shaft of 0.5 m radius (less in small cells), a capital, round or square (55 / 45,
  seeded). A top with a block floating above it in its own column is flat (no roof or battlements under the pillar).
- **Stairs.** One flight between each pair of wall walks a level apart that touch, and between each courtyard and each
  walk at level 0 beside it: ten steps of 0.4 m climbing straight up to the higher block's side on the lower floor,
  1.2 m wide, running 2.2-4 m into the cell (inside its floor, 0.6 m clear of its parapets and taller walls, 1.5 m clear
  of doors and arches), never on a door's side, never on a cell with anything above it, never where the faces
  would not meet flush, never within the lower walk's parapet stubs or the upper parapet's corners.
  The upper parapet has a gap the width of the flight + 12 cm a side where it arrives (no notches on that side), and
  the higher block gets no opening on that side. Of the sides where a flight fits, the one its two grid points pick
  (seeded); one flight per cell. Each step and each corbel course is a stack of its own: the plan splits an outline
  only at other stacks' corners, and their sides run along the same lines.
- A walk edge under a block hanging over it from the level above (its bottom at the walk's floor) is closed, like an
  edge against a taller block: the parapet ends against it in stubs.

## 4. The engine (Castle Forge's `cf_plan.gd`, unchanged)

Every part is a flat convex outline between two heights (a layer: ADD, CUT or CAP) in stacks and groups. The plan snaps
to 1 mm, merges vertices within 3.5 cm, splits every edge at every crossing, classifies each piece of edge on both sides at
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
| left drag | preview, then build on release: a ghost of every block (or land, tree, road...) the stroke would place, built when the button is let go as one undo step; Esc or the right button cancels |
| T, or the Straight wall button next to the build types | straight walls on / off: a left drag then previews a straight row along the nearest grid direction and the release builds it (below) |
| right click | take that block away |
| right drag | turn the camera |
| middle drag | move the camera |
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

**Drag (left button): preview, then build on release.** A left press that moves more than 6 px starts a stroke. While the button is down
nothing is built: the mouse path (sampled every 6 px, so a fast drag leaves no gaps) is picked like a click, and the targets a click would
build on form a **preview** drawn with the hover ghost's material (a translucent white prism per target, `stroke_mi`; the single hover
ghost steps aside, and the status line says how many are previewed). The preview is a path: a new column is added to its end, and when the
pointer comes back to a column already in it, everything after that column is dropped, so moving back over the cells takes them off
(at most one target per column). The release builds the previewed targets in order with the same `add_block` / `add_wild` as a click
(the landscape types refuse quietly where a click would complain), as ONE undo step (`stroke_committing`: the first edit saves the state,
later ones do not). Esc, the right button, a change of build type or the window losing focus cancels the stroke: the preview goes,
nothing is built and the rest of the drag does nothing. A press moved less than 6 px is a click and builds one block as before. Right drag
stays the camera's turn, so there is no drag-to-remove; middle drag and W A S D move the camera. Cues: the help line, the status line
while previewing, a message when the stroke is built or cancelled.

**Straight walls (T, or the Straight wall button).** A toggle button after the build-type buttons (`CSUi.b_straight`, text "Straight wall (T)" /
"Straight wall: On (T)", blue and larger when on) and the key T (not with Ctrl) switch `main.straight_mode` (`set_straight`); changing the mode
cancels a stroke in progress, and the help line names the key. It applies to the castle types (the landscape types keep their cell by cell drag).
With it on, a left press that moves more than 6 px starts a straight stroke instead of the cell-by-cell one. The stroke begins in the middle of the
cell a click at the press would build on, at the sea level (pressing on top of a block says so and does nothing); its direction is
`CSGrid.snap_direction(d, town.wall_dirs)` of the vector from there to where the pointer is on the ground, one of the 12, 16 or 24 wall directions
(R, the Directions button; 12 = multiples of 30 degrees: the grid's lines); its length is the one of `CSGrid.wall_stops` (on a grid line: `line_stops`, the distances
at which the middle of a cell lies exactly on the line; on any other heading every half cell spacing) nearest to the pointer's shadow on the line (no wall before the pointer has gone half way to the first stop), shortened until every cell the wall
crosses is on the island. What it previews and builds is **one straight wall**, not cells: `town.walls` holds `{x, z, deg, len, w, c}` (section 0a); the ghost is one
translucent prism the shape of the wall (`CSBuild.wall_poly`), re-made at every pointer move (shorter when the pointer comes back, another heading
when it goes round); the status line says "Straight wall at N deg, M m long. Release to build it, Esc or the right button to cancel" (and, when the wall lies against others, "... joins 1 wall into one 3.2 m thick wall of 9.1 m", section 0b: the ghost is then the merged wall). Nothing is built while
the button is down; the release adds the wall (`add_wall`) as ONE undo step; Esc, the right button, a change of build type or of mode, or the window
losing focus cancels. A press moved less than 6 px is a click and builds one block, in either mode. A right-click on a wall (the collision mesh gives it
its own owner id, `CSBuild.WALL_OWNER + i`, `pick().wall`) takes it away, one undo step; a click on a wall's face builds on the cell beside it.

*What a wall is* (`CSBuild._walls`): a footing and a body of its own, one level high, a rectangle `w` wide (`WALL_THICK` = 1.9 m x cell, 0.95 m at the default cell size; thicker once walls merged) from where it starts to where it ends, whatever cells it crosses (no rule of the cells applies to it: no door, no arch, no corbel under it, the prop
layer keeps clear of it as of a block). The parapet is made for all the walls together, along the boundary of the walls' union
(`_wall_loops`: every rectangle's edges cut where the others cross them, the pieces inside another rectangle dropped, collinear overlaps kept once,
the rest chained into loops), so where walls meet or cross the parapet goes round the joint and not across the walk, a ring of walls has an inner
parapet and an outer one, and walls end to end are one long wall; a crenel in the middle of each straight stretch, as on a wall walk. Walls
overlapping blocks are unioned with them by the plan; the parapet of the wall stays over the block's roof there (cosmetic).

Starters (`scripts/cs_starter.gd`): castle (a closed curtain of the 18 cells of the band 14.5-20.5 m, four towers, a gate
passage, a keep of the middle cell and two opposite neighbours (three on the hexagon grid) with a round tower, cottages in the courtyard), village, one tower, harbour (quay, houses, striped lighthouse), bridges (two towers joined
high up by one block on an arch, an oriel on corbels, a balcony on a pillar, a wall walk stepping down a level; on the 12-sided
grid its sides are too short for the flight between the two walks). Only blocks: every tower, roof, arch and stair in them comes from the rules. The starter closes the wall on the gate's far side
so the gate block bridges two walls and gets its arch.

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

`verify-castle-scaper-realistic.bat`: every script compiles; `tests/verify_cs_core.gd` (312 headless checks on the double grid; at first 159, 37 of them new for this copy: every light and quality row complete with sane numbers, the rock skirt and the sea floor finite, bounded and fast; the others: the grid's shape and
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

**The double grid's tests (2026-10-19).** `tests/verify_cs_core.gd`: `_grid()` / `_grid_lines()`: 1141 buildable cells, every one a dodecagon with 12
neighbours that alternate dodecagon, triangle; the triangles in the grid (2400) but not buildable; every side 1.3906 m, corners 150 and 60 degrees,
areas 21.65 and 0.84 m2 (a dodecagon as big as the regular hexagon it replaces), the 12 headings of the sides, a flat side facing east on every
dodecagon, every cell convex and counter-clockwise, every cell corner shared by exactly three mutually adjacent cells, `nearest` right next to corners
and over a triangle; `snap_direction` (multiples of 30 degrees, ties, tiny vectors) and `cells_along`. `_hex_grid()`: the plain hexagon grid (1141
regular hexagons of 21.65 m2, the save tags, the castle starter, six random castles and a wall on it, all closed). `_walls()`: where a wall may end
(`line_stops`), the wall rectangle and its clearance from every corner, the save round trip, and walls at 0, 30, 60, 90 and 150 degrees built, closed
and straight (every vertex of the wall's mesh on one of its four parallel lines, 1.9 m thick), the shapes a player draws (a ring of six walls along
either kind of line, an L, a T, a cross, walls end to end, two walls on top of each other) and a wall beside the castle, all closed.
`tests/verify_cs_editor.gd` (1600x900 or larger: a smaller window exits with code 4 and says so): the straight wall: the button and the T key turn the mode on and
off and show it; a drag from a free sea cell previews one wall, snapped to the grid heading although the pointer is a few degrees off, as long as the
stop nearest the pointer, the ghost one prism within the wall's width of its grid line, the status line says "Straight wall at N deg"; it shortens when
the pointer comes back and swings to another heading when it goes round; nothing is built while the button is down; the release builds the one
wall as ONE undo step; its built mesh is straight (every vertex on four parallel lines within 1.2 cm, 1.9 m thick, as long as the preview said);
a click on it picks it, a right-click takes it away (one undo step), Ctrl+Z / Ctrl+Y; Esc and the right button cancel (and the release after builds
nothing); a plain click builds one block; with the mode off the drag is the ordinary paint preview again.

**The editor suite's budget (2026-10-19, after Kevin's run on a real GPU).** A cap in frames (the old `FRAME_CAP := 4000`) does not work: a real GPU draws a frame
in a few ms while one click's rebuild on the worker takes about 1.3 s at the default cell size (incremental plan 0.4-0.6 s, props 0.5 s; 0.75 s at the full size), so a step spends hundreds of
frames waiting. The suite now caps wall-clock time (`TIME_CAP_MS`, 25 min) and each wait for the build is by time (`SETTLE_CAP_MS`, 2 min), not by frames. Quitting while
the worker thread still ran crashed on exit (access violation): `CSMain.shutdown_build()` waits for the task and is called from `_exit_tree`, before a shot's quit and
from the suite's own `_quit`. The launch and verify `.bat` files run `Godot --headless --import` first, so new `class_name` scripts are in the class cache.

**Round 4's tests (2026-10-19).** See section 0b ("Tests"). New tools: `tools/cell_stress.gd` (defects and build time per cell size over the starters and random castles), `tools/cost_probe.gd`, `tools/props_profile.gd`, `tools/plan_profile.gd`, `tools/land_check.gd`, `tools/autosave_walls.gd`, `tools/layer_dump.gd`, `tools/defect_blocks.gd`. `tests/verify_cs_editor.gd --cap=SECONDS` raises the time cap (a software renderer draws a frame in seconds: `xvfb-run godot --path . --resolution 1600x900 --script res://tests/verify_cs_editor.gd -- --cs-fresh --cs-quality=low --cap=3300` runs the whole suite in about 11 minutes).

**Round 3's tests (2026-10-19).** `tests/verify_cs_core.gd` gained: `_merging()` (Kevin's exact castle_004 list loaded as a round-2 save: 30 walls merge into at most 20,
the merged ones are thicker than a single wall, no two parallel walls are left closer than the merge threshold, the merged castle builds closed, walls at
different angles stay separate; two strips side by side merge into one twice as thick, one half a thickness further joins, ten metres apart / end to end far apart /
crossing do not; three strips make a wall three times as thick, built closed, and it round-trips a save as one wall), `_corners()` (a lone wall has a round 16-sided
tower on each end that covers the whole squared end and stands above the wall; bends of 30, 60, 90, 120, 150, 210, 270 and 330 degrees have three towers and a
wedge fill exactly when under 75 degrees, the fill a proper convex triangle; a T has three towers (the stem's end is buried), a cross four, a ring of three three; a
merged thick wall ends flat; every one built closed), `_directions()` (snapping for 12, 16 and 24 directions, the grid's lines against 22.5 and 15 degrees,
`wall_stops`, the saved count and an unknown count loading as 12, one wall in each direction of each count merged and built closed, a wall at 22.5 degrees a
straight rectangle, the castle with walls at 22.5 and 105 degrees beside it) and `_cell_sizes()` (1/1, 1/2, 1/3, 1/4: every cell regular with the right area and
the island as big; the tag and the saved size; the default; the castle starter, four random castles and two walls closed on 12-sided 1/2 and 1/3 and hexagons 1/2).
The "wall is straight" check ignores the vertices of the two end towers. `tests/verify_cs_editor.gd` gained: the Directions button and R (12 -> 16 -> 24 -> 12, saved,
undo leaves it alone), a drag at 16 directions snapping to 22.5 degrees and ending a whole number of half cell spacings along it, built closed; walls merging through
`add_wall` (a second wall half a thickness beside the first: one wall 1.5 thick and the union long, Ctrl+Z splits them); the Cells switch through 12-sided 1/2 (default),
1/3, the full size, hexagons 1/2, and Shift+H back. New tools: `tools/corner_probe.gd`, `tools/corner_gallery.gd`, `tools/wall_one.gd` (one town of walls from the command
line, with `--at=x,z` listing the plan layers there), `tools/merge_probe.gd`, `tools/save_castle004.gd`, `tools/grid_dump.gd`, `tools/mini_town.gd`, `tools/time_probe.gd`;
`tools/wall_probe.gd` and `hex_probe.gd` take `--cell=` and `--dirs=`.

Tools: `tools/grid_probe.gd` (cell shapes of the double grid, `--svg=` writes the plan `shots/hex_grid_plan.svg`), `tools/hex_probe.gd` (the stress test: click-built
castles and the board-edge rings audited; `--grid=hex` on the hexagon grid), `tools/wall_probe.gd` (random straight walls over random castles), `tools/wall_shapes.gd`
(walls in the shapes a player draws), `tools/stops_probe.gd`, `tools/ring_probe.gd`, `tools/ui_probe.gd` (where the UI bars sit), `tools/defect_min.gd` (shrinks a defective town to a few blocks and lists the plan layers near it), `tools/starter_probe.gd`
(a starter's land kinds and prop counts, `--cells` lists its cells), `tools/smoke.gd` (stats + audit of every starter and random castles, and each castle's props;
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
  cottage roofs only on single ground blocks.
- Corner pieces (section 3a): an arch only between two abutments one level down (a block held from one side gets
  corbels, a long bridge gets corbels at its ends and pillars between); arches one level deep (a bridge high up has an
  arched underside hanging between its towers, not piers to the ground); corbels on every side over a wall; pillars to
  the ground however tall; stairs rising straight towards the higher wall (not along it: a cell side is too short for
  a 4 m climb along it), one flight per pair of walks, none from the ground to walks above level 0; the castle starter
  gained one block to make its gate a real bridge; a showcase starter (bridges) in the Castles menu.
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

## 12. The combinations viewer (how many things can one click become?)

Kevin 2026-10-18: "Can you analyze the combinations of this right now compared to the original Townscaper game?", then "can you do this analysis on a web page
with drawings? even with 3d renders ... animations will be better too ... create a batch launcher for the viewer". `viewer-castle-scaper-realistic.bat` rebuilds
`viewer/data.js`, serves `viewer/` (`tools/serve_viewer.py`: static and no-cache, the port is `castle-scaper-realistic-viewer` in the register) and opens `index.html`;
`dump` counts everything again (headless, ~4 min), `render` redraws every picture (hidden Godot window, ~10 min). `viewer/` has a `.gdignore`: Godot never imports it.

**The page** (plain HTML / CSS / JS, no libraries; white background since Kevin's 2026-10-18 request - the CSS variables in `style.css` plus `TH` in `util.js` for the colours the scripts draw with; `util.js`, `turntable.js`, `keyspace.js`, `neigh.js`, `charts.js`, `diagrams.js`, `main.js`): how each game reads a click
(two animated plan diagrams), Townscaper's lookup (a draggable cube whose corners you click, its key after hiding buried corners and renaming colours, the 53 plain shapes,
the colour histogram), this game's rules (an explorer over EVERY neighbourhood of a block: click the squares round it, or pick an outcome, and the real rule's answer
and its 3D turntable appear), the 22 outcomes as turntable cards, real castles (bars, the growth curve, plan maps coloured by top kind that grow storey by storey, a castle
turntable), one click (the game's own click-and-pop frames with rings on the blocks that changed, Townscaper's wave as an animation, a histogram), the landscape (a
21-pair matrix with a rule and a close-up per pair) and the levers. Turntables are sprite sheets drawn on a canvas: they turn by themselves while on screen, speed up
under the pointer, drag to turn by hand; swept views (near walls) play forward and back.

**Numbers (2026-10-18).** Townscaper, read from the game's own ModuleLibrary asset (counts only: `townscaper-re/tools/unity_objects.py` finds it in `sharedassets1.assets`, `library_stats.py --json viewer/data/townscaper_library.json` counts it): **4,769 corner keys** (755 turned/mirrored), **2,071 modules** (1,609 distinct mesh-part sets from 892 mesh parts; 1,483 reached by some key), **128 decor modules**, props on 98 modules (226 placements), 14,519 side profiles, 59,089 (module, orientation) candidates over the keys (12.4 per key, median 9, up to 740). My rules-based count (`tools/townscaper_keyspace.py`, from the corner-key rules in `townscaper-re/notes`) reproduced 4,764 of the 4,769 keys exactly and none that the asset lacks (the other 5: the empty cell and four odd diagonal corners); the per-layer counts 15 / 546 / 4,254 sum to 4,815 only because the same key occurs in more than one kind of cell. 94% of the upper keys involve two or more colours. This game (`tools/combo_probe.gd`), castle and ocean only: one 4-neighbour point, storey 1: 14 bits = 16,384 patterns -> 2,664 classes -> 22 structural outcomes (ground floor 512 -> 110 -> 5; a second, skewed cell gave the same numbers), so 2,774 classes; 6,083 random-castle blocks: 36 structural outcomes, 308 distinct shape + roof + openings (about 390 exist), 1,436 full looks with props (about 2,430 exist), 81% of tops are wall walks; the neighbourhood decides 89% of the structure and 29% of the look; 79 clicks on 25 castles: 1.2 other blocks change shape, 2.5 change look, the farthest 13 m away; landscape: 635 column states (149 seen), 97 column outcomes, all 21 pairs of types react. **Head to head, castle and ocean only:** Townscaper has about 5 times as many finished pieces (2,071 vs about 390) and about 58 times as many that the arrangement of blocks chooses (2,071 vs 36); this game's extra variety is random decoration.

**Pipeline.** `combo_probe.gd` (`--json=PATH`, `--phases=castle,ripple,exh,land,plans`, `--merge` to redo one phase) -> `viewer/data/combos.json`;
`render_viewer.ps1` -> `analysis_render.gd` (instantiates `main.tscn`, builds each town from the dumped bit patterns - the subject block honey, its neighbours granite -
and takes 24-frame turntables at 480x360 from a 960x720 window under the noon light; ripple cases replay the click with `pop_t0` set per frame, so the pop is
deterministic; landscape spots are found by rule in the kingdom, landscape and random-country towns, and `_plan_camera` ray-casts the physics world to pick the pitch and
the arc with room, so the camera never sits inside a wall or a mountain) -> `viewer/img/*.jpg` + `renders.json`; `build_viewer_data.py` -> `viewer/data.js`
(`window.DATA`, so the page also opens straight from the disk). 33 MB of pictures: not in git yet (Kevin's call).

**Gotchas.** A hidden preview pane throttles timers and IntersectionObserver: take two screenshots (the first forces a frame) before judging a section. `Object.assign`
of a JSON field named like a lookup map shadowed the map. Untested: two-storeys-up neighbours, colour seams.
A pen-drawing variant of the renders (`--cs-pen=light --tag=_pen`) would work with the same pipeline.

**Open after the double grid (2026-10-19).** Town 8121 style 0 (above): a window edge and a crenel edge 4 cm apart on the same short side; a rule that
places windows and crenels from the same side's grid (not widening the crenel, which moved the problem) would cure it. The 3.6 m2 triangle cells are slim
2.9 m towers and wall stubs: look and balance of the starters on them (a courtyard of three big cells, no cottages) were checked only in numbers (the tests and the stress runs) and the plan picture, never by eye in the game on a real GPU.

## 10. Open (realistic look)

**Open after round 4 (2026-10-19).** Not chased, listed: (1) 1/6 and 1/8 cells: 3 of 30 and 20 of 30 stress towns still have defects (the castle starter's courtyard ground at 1/8, a ring of
vertices 5-13 cm apart on a vertical line at a stair/parapet joint at 1/6: `tools/cell_stress.gd --cell=6`, then `defect_min.gd --town=12 --cell=6`); (2) no GPU here, so the frame time per size, the Forward+ look
at 1/4 (the picture is software OpenGL, medium) and the look suite were not run; (3) a click costs 1.2 s of CPU at 1/4 on this machine (the plan's per-layer fixed cost is most of it); (4) walls through
castles at 16 and 24 directions still have the rare stray-geometry defect of round 3; (5) the merge rule makes a bounding rectangle: two overlapping strips that only half overlap fill the corner
between them (the end-to-end allowance shrinks with the side gap to keep this small).

- Done in round 2 (see section 6): masonry parallax, string courses, ivy, window glazing, displaced waves, swash foam, cirrus, rays, far islands,
  a colour table per light, Dusk with lit windows, smoke, gulls, a boat, dust and splashes.
- Still not done: chipped, leaning masonry silhouettes (the walls are still clean planes, the parallax is only in the shading; a displaced mesh or
  merlon chips would need geometry in `cs_build`, risking the weld audit); a plinth flare; spray particles where waves break; rain and mist
  particles in Overcast; the sea has no horizontal Gerstner motion and no wind on the boat's sail; the dusk look has no Tripo mock-up; SDFGI is the
  dear part of Ultra; the boat does not avoid a large castle (it circles at 58 m).
