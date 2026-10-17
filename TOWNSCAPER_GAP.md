# Castle Scaper vs Townscaper: what is left

Written 2026-10-17 from the Townscaper study (`C:\Dev\Prototypes\townscaper-re`, local only: feature-level notes here, no
decompiled code) and the state of Castle Scaper at its first commit.

## Why Townscaper gives so many outcomes from one click

1. **It decides per corner, not per block.** Each cell between four grid columns and two heights has 8 corners (filled,
   air, ground, which colour). That pattern, read with symmetry and with colours renamed "first, second...", picks a piece
   from a library, and neighbouring pieces must have matching side profiles. Every different arrangement of neighbours
   gives a different piece: inner and outer corners, overhangs, arches, roof edges, seams where colours change.
2. **The variety lives in data.** The game's code has no rule for arches, stairs, roofs or railings: they are simply the
   cheapest library pieces that fit "filled above, air below, filled on both sides" and so on. Hundreds of authored
   pieces x 8 orientations.
3. **A decor layer on top**: after the base piece is chosen, a second pass keeps every non-overlapping detail that fits
   (cheapest first), and details that cross a cell face must be matched by the neighbour.
4. **Props with a priority solver**: lamps, plants, chimneys, bunting and laundry lines strung between facing walls (in
   the two walls' colours), each switched on only if nothing more important overlaps it.
5. **Life and feel**: birds, butterflies over flowers, a dust or splash puff in the block's colour, a springy dent at
   the clicked point, a bounce of the changed cells, click notes that climb a scale as you build a row, waves and gulls,
   soft contact shadows baked from a top-down occlusion map, a sandy shoreline band.
6. **Ground is its own thing**: the first click on the sea makes land (a quay/plaza tile), not a house. Houses start one
   level up, so islands, plazas, gardens and harbours appear naturally.
7. **An endless map**: the grid is generated in patches around the camera, so the town is never boxed in.

## Castle Scaper today

About ten outcomes from coarse per-block rules: round or mural **tower** (cone roof or battlements), **flat** crowded
top, **cottage** (pyramid roof), **wall walk** with notched battlements, land as **base / passage / courtyard**, and
**door / slit / window** openings. Since the corner-pieces branch (2026-10-17), what holds up a block with nothing under
it is read from the blocks round its cell at two levels: a stepped **arch** between two walls, stepped **corbels** on a
wall it overhangs, a **pillar** down to the next solid; and **stairs** climb between wall walks a level apart and from
courtyards to low walks (SPEC 3a). One welded skin from Castle Forge's layer engine (audited closed), pastel paint, birds,
foam ring, pop of the new block, ghost, grid overlay, undo, save, starters. Fixed hexagon map (~1200 grid points).

Since 2026-10-17 (branch `props`): a **prop layer** (`scripts/cs_props.gd`, SPEC section 5) of instanced details chosen
like Townscaper's props: candidates per block side and top, sorted by cost with a grid-point hash tie-break, kept when they
overlap nothing kept (openings first), no block, arch, corbel, pillar, stairs, land, parapet or roof. Window frames, shutters, flower boxes, lanterns by
doors, shields and banners on towers, chimneys on cottages and small flat houses, hoardings and machicolation corbels
under parapets, crates and barrels in courtyards, bunting between facing blocks in their two colours; they pop in and out
with their block, birds sit on chimneys.

## The gap, ranked by how much it adds

| # | area | Townscaper | Castle Scaper now | what to build | effort |
|---|---|---|---|---|---|
| 1 | **Corner-pattern pieces** | piece per 8-corner pattern | per-block rules; **done**: arches under bridges, corbels under overhangs, pillars under floating blocks (two-level pattern per grid point, SPEC 3a) | left: inner/outer corner trims, buttresses at level changes, arches deeper than one level (piers to the ground under high bridges), wider spans (a row of arches under a long bridge instead of corbels + pillars), a parapet corner that meets a block one level up diagonally (pinch at the parapet's level) | M |
| 2 | **Decor / props layer** | decor pass + props with overlap solver | **built** (prop layer, 12 kinds, greedy independent set) | left: decor matched across a cell face (a balcony or awning running over two blocks), laundry lines (bunting's twin), lamps on posts in plazas, more variety per kind (doors' surrounds, signs, wells); props that glow at night come with 9 | S-M |
| 3 | **Ground tile first** | level 0 = land | level 0 = a full 4 m block | option: first click on the sea makes land (quay/plaza), the next click builds; land gets steps down to the water | M |
| 4 | **Courtyard life** | grass, gardens, trees, flowers + butterflies | paved court | courtyards and plazas grow grass, a tree, a well; butterflies over flowers | M |
| 5 | **Click juice + sound** | puffs, spring dent, bounce, pitch scale, ambience | pop animation only | colour puff / water splash, spring dent at the click, neighbours bounce, rising click notes, waves, gulls (local audio tools exist) | S-M |
| 6 | **Roof vocabulary** | gables, hips, terraces, railings, spires, domes | cone, pyramid | gable roofs along runs of two-plus blocks, hip roofs on halls, railed roof terraces, spires on tall towers, onion domes by colour | M |
| 7 | **Stairs** | stairs at level changes | **done**: a flight between walks a level apart and from a courtyard to a walk at level 0 (SPEC 3a) | left: flights along a wall (two cells' run), switchbacks for two levels, stairs down to the water / land, stairs inside towers | S-M |
| 8 | **Shoreline** | soft sand band + foam | foam ring | sand/rock band under the plinth, foam lines that move | S |
| 9 | **Night** | lit windows, lamps | glow zone unused | a time-of-day slider; windows and torches glow | S-M |
| 10 | **Contact shadows** | baked top-down occlusion | SSAO + ground darkening | a baked occlusion map of the blocks (soft dark in corners and under overhangs) | M |
| 11 | **Bigger map** | endless, generated around the camera | fixed hexagon | larger radius first (cheap), patches on demand later | S / L |
| 12 | **Editor extras** | 15 colours, paint, long-press colour pick, photo mode, share codes | 12 colours, add/remove | paint mode (recolour a block), eyedropper, hide-UI photo key, top view, town as a short text code | S each |

## Engine notes (what makes each step cheap or costly)

- **Welded skin vs pieces.** Every masonry shape must go through CFPlan and pass the audit (no features under 2 cm,
  no edges 2 mm-4 cm apart, no solids touching along a line). That is the price of one closed skin. So: keep the skin for
  walls, towers, roofs, arches and stairs (1, 6, 7), and put everything small in a **prop layer** of separate instanced
  meshes (2, 4, 9). Townscaper does the same: its props are rigid meshes placed in the bent cells, not welded.
- **Corner patterns fit the layer engine.** A dual-cell piece is still flat convex outlines between heights: an arch is a
  CUT stepped like Castle Forge's gate arch, a corbel a few ADD layers, a pillar a narrow column. The per-corner decision
  replaces `_tops` and part of `_bodies`; the audit suites stay the net.
- **Rebuild time scales with the castle.** A full build is ~0.3 s for 82 blocks; incremental reuse gives ~0.05-0.25 s.
  A large town (500+ blocks) needs per-region rebuilds (chunks of the map with their own plans) before the map grows much.
- **Determinism**: choices seeded by grid point (as now), so undo and saved towns rebuild the same.

## Suggested order

1. Click juice + sound (5) and shoreline (8): quick, and they make every click feel like Townscaper.
2. ~~Prop layer (2)~~ built on branch `props`; its leftovers (decor across faces, laundry lines) when convenient.
3. Ground tile first (3) + courtyard life (4): islands, plazas and gardens; changes how towns grow.
4. Corner-pattern pieces (1) with arches, supports and stairs (7) -- the first pass is done (branch corner-pieces) --
   then the roof vocabulary (6): the deep work that gives Townscaper-level variety.
5. Night (9), contact shadows (10), bigger map with chunked rebuilds (11), editor extras (12).
