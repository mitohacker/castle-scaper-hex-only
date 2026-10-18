class_name CSBuild
extends RefCounted
## Turns the blocks into a castle. The player only stacks blocks; what each block becomes comes from its neighbours
## (Townscaper's way: its WFC picks modules from the 8 corners round each cell; here the same idea is written as a few
## rules over the welded layer engine CFPlan, every mesh made in code):
## - land: under every ground block, under every block that bridges over an empty cell (a gate passage), and in every
##   empty cell the sea cannot reach (a courtyard); the rest is sea;
## - a column two or more blocks tall that stands free from the ground up is a round tower; one that rises alone out of
##   a wall keeps its cell's many-sided shape (a mural tower); either way its top gets a cone roof, or (now and then,
##   seeded by its grid point) a ring of battlements;
## - a single block alone on the ground is a cottage under a pyramid roof;
## - tops that touch other tops at the same level are wall walks with battlements along their open edges;
## - open sides get arrow slits or windows; a ground block next to land gets a door;
## - a block with nothing under it is held up by what is round its cell one level down (the two-level pattern of its
##   neighbours, Townscaper's dual cells taken round one grid point): an ARCH when blocks stand on two opposite-ish
##   sides there, CORBELS on the sides it overhangs a wall, else a PILLAR down to the next solid;
## - a wall walk one level below another walk (or a courtyard below a walk at level 0) gets a flight of stairs up to it,
##   with a gap in the upper parapet where it arrives, never in front of a door.

const H := 4.0                  # level height (m); a cell is about 4 m across
const B := 0.6                  # top of the land above the sea (y = 0)
const FOOT := -1.6              # bottom of the land / footings
const PT := 0.45                # parapet thickness
const PH := 1.05                # parapet height
const MERLON_LOW := 0.45
const NOTCH_W := 0.6
const NOTCH_STEP := 1.45
const ROUND_SIDES := 16
const PINCH := 0.35             # a cell corner shared only with a diagonal block is pulled in this far (m)
const STUB_BITE := 0.15         # how far a parapet stub reaches into the taller block it ends against
const ARCH_PIER := 0.3          # the thinnest pier between an arch and the block it springs from (m)
const ARCH_MIN_W := 0.7         # the narrowest half span worth an arch
const ARCH_MAX_W := 2.0
const ARCH_BAND := 0.4          # solid band between an arch's crown and the block it carries
const ARCH_FR := [0.0, 0.35, 0.6, 0.78, 0.91, 1.0]          # stepped arch: heights of the courses (x the rise) ...
const ARCH_FR_SMALL := [0.0, 0.45, 0.7, 0.87, 1.0]          # ... fewer on narrow arches, so no course is under 4 cm
const CORBEL := [[1.0, 0.0, 0.35], [0.65, 0.35, 0.75], [0.3, 0.75, 1.1]]   # reach out of the wall, top and bottom below the block
const PILLAR_R := 0.5
const STAIR_STEPS := 10         # a flight climbs one level (4 m) in ten steps
const STAIR_HW := 0.6           # half its width
const STAIR_MIN_RUN := 2.2
const GAP_MARGIN := 0.12        # the parapet gap is this much wider than the flight on each side

var grid: CSGrid
var town: CSTown
var plan: CFPlan
var mesh := CFMesh.new()
var caps: Array = []
var land := {}                  # vertex -> "base" | "passage" | "court"
var kinds := {}                 # block key -> "tower" | "battle" | "cottage" | "walk" | "flat" (tops only)
var fills := {}                 # key(v, k) -> arch record: the arch under the block (v, k + 1) fills v's cell at level k
var pieces := {}                # key of a block with nothing under it -> "arch" | "corbel" | "pillar"
var stairs: Array = []          # {cell, face, up, k (level of the lower walk, -1 = the ground), run, ...}
var doors := {}                 # grid point -> the side (index in nbrs) its ground block has its door on
var openings: Array = []        # every door, slit and window cut (the prop layer keeps clear of them, CSProps)
var extras: Array = []          # {poly, y0, y1}: what corbels, pillars and stairs fill (the prop layer keeps clear too)
var hats := {}                  # block key -> the hat of a styled top: {kind, style, parts, top, rec, ...} (CSStyleBuild)
var stats := {}
var facades := 0                # facades found on the painted walls (CSFacades)
var _styled := false            # some block is not the castle's
var _top := {}
var _round := {}
var _fill_col := {}             # grid points whose column holds an arch
var _corbel_faces := {}         # block key -> sides with corbels
var _covered := {}              # key(v, k) * 16 + side -> true: something stands against that side (no opening there)
var _gaps := {}                 # walk area id -> {loop edge start point: [s0, s1] along that edge}


static func h01(a: int, b: int = 0, c: int = 0) -> float:
	var h: int = (a * 374761393 + b * 668265263 + c * 1013904223) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0x1000000)


static func colour_seed(c: int) -> float:
	## The plaster shader reads the block's palette index from the seed channel.
	return (float(c) + 0.5) / 16.0


static func warm(c: int) -> bool:
	return c in [0, 1, 2, 3, 4, 5, 11]


# --- queries ---------------------------------------------------------------------------------------

func top_of(v: int) -> int:
	if not _top.has(v):
		_top[v] = town.top(v)
	return _top[v]


func filled(v: int, k: int) -> bool:
	## A block, or the arch that fills the cell under a bridging block (it stands for a block to its neighbours).
	return k >= 0 and (town.has(v, k) or fills.has(CSTown.key(v, k)))


func isolated(v: int, k: int) -> bool:
	for u in grid.nbrs[v]:
		if filled(u, k):
			return false
	return true


func col_round(v: int) -> bool:
	## A free-standing column two or more blocks tall: no block beside any of its blocks (and no arch in it).
	if not _round.has(v):
		var r := top_of(v) >= 1 and not _fill_col.has(v)
		if r:
			for k in range(0, top_of(v) + 1):
				if town.has(v, k) and (town.style(v, k) != CSStyle.CASTLE or not isolated(v, k)):
					r = false
					break
		_round[v] = r
	return _round[v]


func castle_at(u: int, k: int) -> bool:
	## A castle block, or the arch that fills a cell under a bridging block (not a house, a pagoda ...).
	return (town.has(u, k) and town.style(u, k) == CSStyle.CASTLE) or fills.has(CSTown.key(u, k))


func is_round(v: int, k: int) -> bool:
	return town.has(v, k) and col_round(v)


func level_y(k: int) -> float:
	return float(k) * H + B


static func level_y_static(k: int) -> float:
	return float(k) * H + B


func round_poly(v: int) -> PackedVector2Array:
	var p := grid.verts[v]
	var d := grid.dual(v)
	var r := INF
	for i in d.size():
		var a := d[i]
		var b := d[(i + 1) % d.size()]
		r = minf(r, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
	r *= 0.9
	var out := PackedVector2Array()
	var a0 := (grid.verts[grid.nbrs[v][0]] - p).angle()
	for i in ROUND_SIDES:
		var a := a0 + TAU * (float(i) + 0.5) / float(ROUND_SIDES)
		out.append(p + Vector2(cos(a), sin(a)) * r)
	return out


func round_radius(v: int) -> float:
	return round_poly(v)[0].distance_to(grid.verts[v])


static func convex(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var c := poly[(i + 2) % n]
		if (b - a).cross(c - b) < -1e-6:
			return false
	return true


func outline(v: int, filled: Callable) -> PackedVector2Array:
	## v's cell at one level: the quad centres round v, except that a centre shared only with a diagonal block (the quad's
	## opposite corner filled, its two other corners empty) is pulled towards v, so the two blocks stand apart instead of
	## touching along a single line (Townscaper's corner modules handle that case; here it becomes a narrow gap).
	var out := PackedVector2Array()
	var nb: PackedInt32Array = grid.nbrs[v]
	var rg: PackedInt32Array = grid.rings[v]
	var n := nb.size()
	for i in n:
		var q := rg[i]
		var c := grid.centers[q]
		var opp := -1
		if grid.fn == 4:                   # the hex grid's corners are shared by three mutual neighbours: never diagonal
			for kk in 4:
				if grid.quads[q * 4 + kk] == v:
					opp = grid.quads[q * 4 + (kk + 2) % 4]
		if opp >= 0 and filled.call(opp) and not filled.call(nb[i]) and not filled.call(nb[(i + 1) % n]):
			c += (grid.verts[v] - c).normalized() * PINCH
		out.append(c)
	return out


func polys_of(v: int, poly: PackedVector2Array) -> Array:
	## An outline as convex pieces: itself when convex, else the fan of triangles from v.
	if convex(poly):
		return [poly]
	var out := []
	var n := poly.size()
	for i in n:
		out.append(PackedVector2Array([grid.verts[v], poly[(i + n - 1) % n], poly[i]]))
	return out


func tier_scale(v: int, k: int) -> float:
	## How far level k of a styled column steps in from the level below (1 = not at all): only a block with nothing beside it and nothing hanging over its
	## top, on a styled block of its own column, in a style that tiers (CSStyle.TIERS), in the columns that do.
	if k < 1 or not town.has(v, k) or not town.has(v, k - 1):
		return 1.0
	var s := town.style(v, k)
	if s == CSStyle.CASTLE or town.style(v, k - 1) == CSStyle.CASTLE or not CSStyle.TIERS.has(s):
		return 1.0
	var tr: Array = CSStyle.TIERS[s]
	if k < int(tr[2]) or h01(v, 31) >= float(tr[1]):
		return 1.0
	if s == CSStyle.APARTMENT and town.has(v, k + 1):
		return 1.0
	if not isolated(v, k):
		return 1.0
	for u in grid.nbrs[v]:
		if filled(u, k + 1):
			return 1.0
		if castle_at(u, k - 1) and not filled(u, k):
			return 1.0                   # a castle wall walk beside it: its parapet ends against this wall, which has to stay on the cell's side
	return 1.0 - float(tr[0])


func level_outline(v: int, k: int) -> PackedVector2Array:
	var f := tier_scale(v, k)
	if f < 1.0:
		var base := level_outline(v, k - 1)
		var c := CSRoofs.centroid(base)
		var out := PackedVector2Array()
		for q in base:
			out.append(c + (q - c) * f)
		return out
	return outline(v, func(u: int) -> bool: return filled(u, k))


static func clip_half(poly: PackedVector2Array, o: Vector2, nrm: Vector2, d: float) -> PackedVector2Array:
	## The part of a convex outline with (q - o) . nrm <= d.
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var d0 := (p0 - o).dot(nrm) - d
		var d1 := (p1 - o).dot(nrm) - d
		if d0 <= 0.0:
			out.append(p0)
		if (d0 < 0.0 and d1 > 0.0) or (d0 > 0.0 and d1 < 0.0):
			out.append(p0 + (p1 - p0) * (d0 / (d0 - d1)))
	return out


func _clear_of(poly: PackedVector2Array, o: Vector2, nrm: Vector2, d: float, margin: float) -> bool:
	## Is the line (q - o) . nrm = d at least margin away from every corner of poly?
	for q in poly:
		if absf((q - o).dot(nrm) - d) < margin:
			return false
	return true


# --- build -----------------------------------------------------------------------------------------

func build(g: CSGrid, t: CSTown, prev: CSBuild = null) -> void:
	var t0 := Time.get_ticks_usec()
	grid = g
	town = t
	plan = CFPlan.new()
	mesh = CFMesh.new()
	caps.clear()
	hats.clear()
	_styled = false
	land.clear()
	kinds.clear()
	fills.clear()
	pieces.clear()
	stairs.clear()
	doors.clear()
	openings.clear()
	extras.clear()
	_top.clear()
	_round.clear()
	_fill_col.clear()
	_corbel_faces.clear()
	_covered.clear()
	_gaps.clear()
	_find_land()
	_find_supports()
	_find_doors()
	_ground()
	_bodies()
	_arches()
	_tops()
	_supports()
	_openings()
	var t1 := Time.get_ticks_usec()
	plan.run(mesh, prev.plan if prev != null else null)
	var t2 := Time.get_ticks_usec()
	_roofs()
	_hats()
	var pc := {}
	for kk: int in pieces:
		pc[pieces[kk]] = int(pc.get(pieces[kk], 0)) + 1
	stats = {"blocks": town.size(), "tris": mesh.tri_count(), "layers": plan.layer_count(), "ms": float(Time.get_ticks_usec() - t0) / 1000.0,
		"ms_rules": float(t1 - t0) / 1000.0, "ms_plan": float(t2 - t1) / 1000.0, "caps": caps.size(), "pieces": pc, "stairs": stairs.size(), "hats": hats.size(), "facades": facades}


func _find_land() -> void:
	## Ground blocks and the cells under bridges are land; so is every empty cell the sea cannot reach (a courtyard).
	var nv := grid.verts.size()
	var sea := PackedByteArray()
	sea.resize(nv)
	var stack: Array[int] = []
	for v in nv:
		if not grid.buildable(v):
			sea[v] = 1
			stack.append(v)
	var blocked := func(v: int) -> bool:
		return town.has(v, 0) or top_of(v) >= 1
	var guard := 0
	while not stack.is_empty() and guard < nv * 8:
		guard += 1
		var v: int = stack.pop_back()
		for u in grid.nbrs[v]:
			if sea[u] or blocked.call(u):
				continue
			sea[u] = 1
			stack.append(u)
	for v in nv:
		if not grid.buildable(v):
			continue
		if town.has(v, 0):
			land[v] = "base"
		elif top_of(v) >= 1:
			land[v] = "passage"
		elif not sea[v]:
			land[v] = "court"


func _find_supports() -> void:
	## What holds up each block with nothing under it, read from the blocks round its cell at its level and the level
	## below. Arches first and from the blocks alone (their fills then count as blocks for everything else, so no
	## arch depends on another); then corbels on the sides that overhang a wall, else a pillar.
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		for k in range(1, top_of(v) + 1):
			if town.has(v, k) and not town.has(v, k - 1):
				var a := _arch_fit(v, k)
				if not a.is_empty():
					fills[CSTown.key(v, k - 1)] = a
					_fill_col[v] = true
					pieces[CSTown.key(v, k)] = "arch"
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		for k in range(1, top_of(v) + 1):
			var kk := CSTown.key(v, k)
			if town.has(v, k - 1) or (not town.has(v, k) and not fills.has(kk)):
				continue
			if pieces.has(kk) and not fills.has(kk):
				continue                   # a block over an arch
			# corbels on every side over a wall one level down (an arch's feet too: its fill counts as a block)
			var faces := []
			if not col_round(v) and convex(level_outline(v, k)):
				var nb: PackedInt32Array = grid.nbrs[v]
				for i in nb.size():
					# a wall under the neighbour (a round tower stands back from its cell's sides: nothing to bear on)
					if town.has(nb[i], k - 1) and not col_round(nb[i]):
						faces.append(i)
			if not faces.is_empty():
				_corbel_faces[kk] = faces
			if fills.has(kk):
				continue                   # an arch stands on its abutments
			pieces[kk] = "pillar" if faces.is_empty() else "corbel"


func _arch_fit(v: int, k: int) -> Dictionary:
	## The arch under block (v, k): two neighbours on opposite-ish sides with blocks at level k - 1 (its abutments) and
	## room between them. Read from the blocks and the cell as the grid made it (the corners of an abutment side are
	## never pinched: the abutment fills one of the two cells beside them), so it does not depend on other arches.
	## Pairs whose arch opens on both sides win, then the most opposite.
	var kf := k - 1
	var nb: PackedInt32Array = grid.nbrs[v]
	var n := nb.size()
	var p := grid.verts[v]
	var best := {}
	var best_score := -INF
	for i in n:
		if not town.has(nb[i], kf):
			continue
		for j in range(i + 1, n):
			if not town.has(nb[j], kf):
				continue
			var dd := (grid.verts[nb[i]] - p).normalized().dot((grid.verts[nb[j]] - p).normalized())
			if dd > -0.4:
				continue
			var open_a := false
			var open_b := false
			for m in n:
				if m == i or m == j or town.has(nb[m], kf):
					continue
				if m > i and m < j:
					open_a = true
				else:
					open_b = true
			var score := float(int(open_a) + int(open_b)) * 10.0 - dd
			if score <= best_score:
				continue
			var fi := grid.face(v, i)
			var fj := grid.face(v, j)
			var s := (grid.verts[nb[j]] - grid.verts[nb[i]]).normalized()
			var ti := maxf((fi[0] - p).dot(s), (fi[1] - p).dot(s))
			var tj := minf((fj[0] - p).dot(s), (fj[1] - p).dot(s))
			var w := (tj - ti) * 0.5 - ARCH_PIER
			if w < ARCH_MIN_W:
				continue
			best_score = score
			best = {"i": i, "j": j, "s": s, "tc": (ti + tj) * 0.5, "w": minf(w, ARCH_MAX_W), "open": open_a or open_b}
	return best


func _find_doors() -> void:
	## The side of each ground block that gets its door: the first open side facing land (85%, seeded by the side). A house, pagoda or tower of
	## the styles always gets one if it has an open side long enough: the side facing land or a courtyard first, else the sea (a quay door).
	for v: int in town.columns():
		if not grid.buildable(v) or not town.has(v, 0):
			continue
		var nb: PackedInt32Array = grid.nbrs[v]
		var rnd := is_round(v, 0)
		var ol := level_outline(v, 0)
		if town.style(v, 0) != CSStyle.CASTLE:
			var best := -1.0
			for i in nb.size():
				if filled(nb[i], 0) or ol[(i + nb.size() - 1) % nb.size()].distance_to(ol[i]) < 2.6:
					continue
				var score := h01(v, i, 8) + (1.0 if land.has(nb[i]) else 0.0)
				if score > best:
					best = score
					doors[v] = i
			continue
		for i in nb.size():
			var u := nb[i]
			if filled(u, 0):
				continue
			if not rnd and ol[(i + nb.size() - 1) % nb.size()].distance_to(ol[i]) < 2.6:
				continue
			if land.has(u) and h01(v, i, 7) < 0.85:
				doors[v] = i
				break


func _arches() -> void:
	for kk: int in fills:
		_arch(kk / 64, kk % 64, fills[kk])


func _arch(v: int, kf: int, a: Dictionary) -> void:
	## The cell under a bridging block, filled, with a stepped arch cut through it (Castle Forge's gate arch): its
	## span runs between the two abutments, the passage across that line, the piers stand against the abutments.
	var k := kf + 1
	var p := grid.verts[v]
	var c := town.colour(v, k)
	var sty := town.style(v, k)
	var y0 := level_y(kf)
	var y1 := level_y(k)
	var ol := level_outline(v, kf)
	var info := {"zone": CSStyle.wall_zone(sty), "top_zone": CFMesh.Z_FLAG if sty == CSStyle.CASTLE else CSStyle.pave_zone(sty), "seed": colour_seed(c), "owner": v + 1, "prio": 10,
		"anchor": Vector3(p.x, y0, p.y), "label": "arch"}
	var st := plan.new_stack(CFPlan.OP_ADD, 10000 + v, info)
	if not convex(ol):
		for poly: PackedVector2Array in polys_of(v, ol):
			plan.add_layer(st, poly, y0, y1)
		return
	# (over a wall one level down, the arch's feet rest on corbels: _find_supports)
	var poly := ol
	plan.add_layer(st, poly, y0, y1)
	if not bool(a.open):
		return                         # shut in on every side: a plain filled cell
	var s: Vector2 = a.s
	var ax := Vector2(-s.y, s.x)
	var centre := p + s * float(a.tc)
	var hl := 0.0
	for q in poly:
		hl = maxf(hl, absf((q - centre).dot(ax)))
	hl += 0.3
	var w: float = a.w
	# every side line of the cut keeps clear of the fill's corners (the plan merges points 2 cm apart)
	var clear := false
	for _try in 8:
		var fr: Array = ARCH_FR_SMALL if w < 1.3 else ARCH_FR
		clear = true
		for m in fr.size() - 1:
			var hw := w * sqrt(maxf(1.0 - float(fr[m]) * float(fr[m]), 0.0))
			if not _clear_of(poly, centre, s, hw, 0.06) or not _clear_of(poly, centre, s, -hw, 0.06):
				clear = false
				break
		if clear:
			break
		w -= 0.07
	if not clear or w < ARCH_MIN_W - 0.2:
		return
	var frs: Array = ARCH_FR_SMALL if w < 1.3 else ARCH_FR
	var crown := y1 - ARCH_BAND
	var rv := minf(w, 1.8)
	var spring := crown - rv
	a["cut"] = [centre, s, w]           # the corbels under its feet keep to the piers (_corbel)
	var cut := plan.new_stack(CFPlan.OP_CUT, 10000 + v, {"owner": v + 1, "label": "arch"})
	plan.add_layer(cut, CFShapes.rect(centre, ax, hl, w), y0, spring + float(frs[1]) * rv)
	for m in range(1, frs.size() - 1):
		var hw := w * sqrt(maxf(1.0 - float(frs[m]) * float(frs[m]), 0.0))
		plan.add_layer(cut, CFShapes.rect(centre, ax, hl, hw), spring + float(frs[m]) * rv, spring + float(frs[m + 1]) * rv)


func _supports() -> void:
	for kk: int in _corbel_faces:
		for i: int in _corbel_faces[kk]:
			_corbel(kk / 64, kk % 64, i)
	for kk: int in pieces:
		if str(pieces[kk]) == "pillar":
			_pillar(kk / 64, kk % 64)


func _corbel(v: int, k: int, i: int) -> void:
	## A stepped corbel under what fills (v, k) (a block, or an arch's fill) on its side i, where the wall of the
	## neighbour one level down bears it: three courses, each reaching less far out of that wall, clipped from the
	## outline of what it holds (its walls run on down). Its back is that wall's own face: where the wall's corner is
	## pinched (a diagonal block at that level), the face leans a few degrees off the cell's side, and a corbel built on
	## the side would leave a sliver of air whose tip is a line two solids touch along.
	var ol := level_outline(v, k)
	var n := ol.size()
	var a := ol[(i + n - 1) % n]
	var b := ol[i]
	var dir := (b - a).normalized()
	var nin := Vector2(-dir.y, dir.x)
	var u: int = grid.nbrs[v][i]
	var iu := grid.index_of(u, v)
	var olu := level_outline(u, k - 1)
	var m := olu.size()
	var bb := olu[(iu + m - 1) % m]    # u's face runs the other way: from the corner at b to the corner at a
	var aa := olu[iu]
	var depth := 0.0
	for q in ol:
		depth = maxf(depth, (q - a).dot(nin))
	var p := grid.verts[v]
	var y := level_y(k)
	var ks := k if town.has(v, k) else k + 1
	var sty := town.style(v, ks)
	var cz := CFMesh.Z_STONE if sty == CSStyle.CASTLE else CSStyle.trim_zone(sty)
	var info := {"zone": cz, "top_zone": CFMesh.Z_FLAG if sty == CSStyle.CASTLE else cz, "seed": colour_seed(town.colour(v, ks)),
		"owner": v + 1, "prio": 10, "anchor": Vector3(p.x, y - 1.1, p.y), "label": "corbel"}
	var last := INF
	for step: Array in CORBEL:
		var r := minf(float(step[0]), depth * 0.45)
		for _t in 4:
			if _clear_of(ol, a, nin, r, 0.06):
				break
			r -= 0.08
		if r < 0.12 or r > last - 0.1:
			break
		last = r
		var poly := clip_half(ol, a, nin, r)
		if aa != a or bb != b:
			# the back from the wall's own corners: a, aa, bb, b in place of the side a -> b
			var ia := poly.find(a)
			var ib := poly.find(b)
			if ia < 0 or ib != (ia + 1) % poly.size():
				return
			var ext := PackedVector2Array()
			for j in poly.size():
				ext.append(poly[j])
				if j == ia:
					if aa != a:
						ext.append(aa)
					if bb != b:
						ext.append(bb)
			if not convex(ext):
				return                     # (never seen) the course would not be convex: no corbel on this side
			poly = ext
		# under an arch, only under its piers: under the passage the course's side would meet the underside of a block
		# beside it along a line, with air above the course and below that block
		var parts: Array = [poly]
		var fa: Dictionary = fills.get(CSTown.key(v, k), {})
		if fa.has("cut"):
			var cc: Array = fa.cut
			parts = []
			for sg in [-1.0, 1.0]:
				var half := clip_half(poly, cc[0], -(cc[1] as Vector2) * sg, -float(cc[2]))
				if half.size() >= 3 and CFTri.area(half) > 0.02:
					parts.append(half)
		# a stack per course: their sides run along the same lines and must be split at each other's corners
		for part: PackedVector2Array in parts:
			plan.add_layer(plan.new_stack(CFPlan.OP_ADD, 10000 + v, info), part, y - float(step[2]), y - float(step[1]))
			extras.append({"poly": part, "y0": y - float(step[2]), "y1": y - float(step[1])})


func _pillar(v: int, k: int) -> void:
	## A pillar under block (v, k) down to the next block in its column or the land: a base, a shaft and a capital,
	## round or square (seeded by the grid point).
	var p := grid.verts[v]
	var y_top := level_y(k)
	var y_bot := B
	var floor_ol := outline(v, func(u: int) -> bool: return land.has(u))
	for kb in range(k - 2, -1, -1):
		if town.has(v, kb):
			y_bot = level_y(kb + 1)
			floor_ol = round_poly(v) if is_round(v, kb) else level_outline(v, kb)
			break
	var room := INF
	for poly: PackedVector2Array in [round_poly(v) if is_round(v, k) else level_outline(v, k), floor_ol]:
		for i in poly.size():
			room = minf(room, Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p))
	var lim := room - 0.15              # no corner of the pillar nearer than this to a side of the cells it joins
	var r := clampf(room - 0.45, 0.25, PILLAR_R)
	var rc := minf(r + 0.25, lim)
	var rb := minf(r + 0.15, lim)
	var rnd := h01(v, k, 21) < 0.55
	var rot := (grid.verts[grid.nbrs[v][0]] - p).angle()
	var sty := town.style(v, k)
	var pz := CFMesh.Z_STONE if sty == CSStyle.CASTLE else CSStyle.trim_zone(sty)
	var info := {"zone": pz, "top_zone": CFMesh.Z_FLAG if sty == CSStyle.CASTLE else pz, "seed": colour_seed(town.colour(v, k)), "owner": v + 1,
		"prio": 10, "anchor": Vector3(p.x, y_bot, p.y), "label": "pillar"}
	if rnd:
		info["round"] = true
		info["center"] = p
		info["radius"] = r
		info["flags"] = CFMesh.F_ROUND
	var st := plan.new_stack(CFPlan.OP_ADD, 10000 + v, info)
	var shape := func(rad: float) -> PackedVector2Array:
		return CFShapes.circle(p, rad, 12, rot) if rnd else CFShapes.circle(p, minf(rad * 1.25, lim), 4, rot + PI * 0.25)
	plan.add_layer(st, shape.call(rb), y_bot, y_bot + 0.3)
	plan.add_layer(st, shape.call(r), y_bot + 0.3, y_top - 0.35)
	plan.add_layer(st, shape.call(rc), y_top - 0.35, y_top)
	extras.append({"poly": shape.call(maxf(rc, rb)), "y0": y_bot, "y1": y_top})


func _ground() -> void:
	for v: int in land:
		var st := plan.new_stack(CFPlan.OP_ADD, 10000 + v, {"zone": CFMesh.Z_RUBBLE, "top_zone": CFMesh.Z_FLAG, "seed": h01(v, 9),
			"owner": v + 1, "prio": 2, "label": "land"})
		for poly: PackedVector2Array in polys_of(v, outline(v, func(u: int) -> bool: return land.has(u))):
			plan.add_layer(st, poly, FOOT, B)


func _bodies() -> void:
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		var p := grid.verts[v]
		var k := 0
		var tk := top_of(v)
		while k <= tk:
			if not town.has(v, k):
				k += 1
				continue
			var val := town.value(v, k)
			var c := val & 15
			var sty := val >> 4
			_styled = _styled or sty != CSStyle.CASTLE
			var rnd := is_round(v, k)
			var shape := PackedVector2Array() if rnd else level_outline(v, k)
			var k1 := k
			while k1 + 1 <= tk and town.has(v, k1 + 1) and town.value(v, k1 + 1) == val and is_round(v, k1 + 1) == rnd 					and (rnd or level_outline(v, k1 + 1) == shape):
				k1 += 1
			var y0 := level_y(k)
			var info := {"zone": CSStyle.wall_zone(sty), "top_zone": CFMesh.Z_FLAG if sty == CSStyle.CASTLE else CSStyle.pave_zone(sty), "seed": colour_seed(c),
				"owner": v + 1, "prio": 10, "anchor": Vector3(p.x, y0, p.y), "label": "block"}
			if rnd:
				info["round"] = true
				info["center"] = p
				info["radius"] = round_radius(v)
				info["flags"] = CFMesh.F_ROUND
			var st := plan.new_stack(CFPlan.OP_ADD, 10000 + v, info)
			var polys: Array = [round_poly(v)] if rnd else polys_of(v, shape)
			for poly: PackedVector2Array in polys:
				plan.add_layer(st, poly, y0, level_y(k1 + 1))
			k = k1 + 1


func _tops() -> void:
	var walks := {}                     # level -> [vertices]
	var styled: Array = []              # tops of the building styles (their hats: CSStyleBuild)
	var tiers: Array = []               # blocks of the styles with a smaller block of their column on top (the roof between the two)
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		for k in range(0, top_of(v) + 1):
			if not town.has(v, k):
				continue
			if town.style(v, k) != CSStyle.CASTLE and town.has(v, k + 1) and tier_scale(v, k + 1) < 1.0:
				tiers.append(CSTown.key(v, k))
				continue
			if filled(v, k + 1):
				continue
			var kk := CSTown.key(v, k)
			if town.style(v, k) != CSStyle.CASTLE:
				styled.append(kk)
				continue
			# a neighbour higher, or a block of its own column floating above it (a pillar comes down onto it)
			var crowded := top_of(v) > k
			for u in grid.nbrs[v]:
				if filled(u, k + 1) or filled(u, k + 2):
					crowded = true
			if isolated(v, k) and top_of(v) >= 1:
				# a tower top: round when the column stands free, else the cell's own shape
				var poly := round_poly(v) if col_round(v) else level_outline(v, k)
				var rr := 0.0
				for q in poly:
					rr += q.distance_to(grid.verts[v])
				rr /= float(poly.size())
				if crowded or not convex(poly):
					kinds[kk] = "flat"
				elif h01(v, k, 3) < 0.72:
					kinds[kk] = "tower"
					_add_cap(v, k, poly, rr * (2.1 + 0.6 * h01(v, 5)), k >= 3 and h01(v, 11) < 0.6)
				else:
					kinds[kk] = "battle"
					_ring_battlement(v, k, poly, col_round(v))
			elif isolated(v, k):
				var d := level_outline(v, k)
				if crowded or not convex(d):
					kinds[kk] = "flat"
				else:
					kinds[kk] = "cottage"
					var rr := 0.0
					for q in d:
						rr += q.distance_to(grid.verts[v])
					_add_cap(v, k, d, rr / float(d.size()) * 1.05, false)
			else:
				kinds[kk] = "walk"
				if not walks.has(k):
					walks[k] = []
				(walks[k] as Array).append(v)
	var areas: Array = []               # {k, id, cells, loops}
	for k: int in walks:
		var left := {}
		for v: int in walks[k]:
			left[v] = true
		for v0: int in walks[k]:
			if not left.has(v0):
				continue
			var area := []
			var st: Array[int] = [v0]
			left.erase(v0)
			while not st.is_empty():
				var v: int = st.pop_back()
				area.append(v)
				for u in grid.nbrs[v]:
					if left.has(u):
						left.erase(u)
						st.append(u)
			areas.append({"k": k, "id": areas.size(), "cells": area, "loops": _walk_loops(area, k)})
	_choose_stairs(areas)
	for a: Dictionary in areas:
		_walk_battlements(a)
	for s: Dictionary in stairs:
		_stair(s)
	if not styled.is_empty():
		CSStyleBuild.tops(self, styled)
	if not tiers.is_empty():
		CSStyleBuild.tiers(self, tiers)


func _add_cap(v: int, k: int, poly: PackedVector2Array, h: float, banner: bool) -> void:
	var c := town.colour(v, k)
	var zone := CFMesh.Z_TILE if warm(c) else CFMesh.Z_SLATE
	var st := plan.new_stack(CFPlan.OP_CAP, 10000 + v, {"zone": zone, "owner": v + 1, "label": "cap"})
	var y := level_y(k + 1)
	var li := plan.add_layer(st, poly, y, y)
	if li >= 0:
		caps.append({"layer": li, "center": grid.verts[v], "h": h, "y": y, "owner": v + 1, "zone": zone, "banner": banner,
			"seed": h01(v, k, 13), "anchor": Vector3(grid.verts[v].x, level_y(k), grid.verts[v].y)})


func _parapet_piece(st: int, pa: Vector2, pb: Vector2, ib: Vector2, ia: Vector2, y0: float) -> void:
	var quad := PackedVector2Array([pa, pb, ib, ia])
	if convex(quad) and CFTri.area(quad) > 1e-4:
		plan.add_layer(st, quad, y0, y0 + PH)
		return
	for tri: PackedVector2Array in [PackedVector2Array([pa, pb, ib]), PackedVector2Array([pa, ib, ia])]:
		if CFTri.area(tri) > 1e-4:
			plan.add_layer(st, tri, y0, y0 + PH)


func _ring_battlement(v: int, k: int, outer: PackedVector2Array, rnd: bool) -> void:
	## Battlements round a lone tower's top (every side is open): the outline and its inset by PT, one piece per side,
	## a notch in every other side (in each side long enough when it is not round).
	var c := town.colour(v, k)
	var p := grid.verts[v]
	var y0 := level_y(k + 1)
	var g := 60000 + v
	var info := {"zone": CFMesh.Z_STONE, "top_zone": CFMesh.Z_STONE, "seed": colour_seed(c), "owner": v + 1, "prio": 11,
		"anchor": Vector3(p.x, level_y(k), p.y), "label": "battlement"}
	if rnd:
		info["round"] = true
		info["center"] = p
		info["radius"] = outer[0].distance_to(p)
		info["flags"] = CFMesh.F_ROUND
	var st := plan.new_stack(CFPlan.OP_ADD, g, info)
	var n := outer.size()
	var inner := PackedVector2Array()
	for i in n:
		var a := outer[(i + n - 1) % n]
		var b := outer[i]
		var cc := outer[(i + 1) % n]
		var d0 := (b - a).normalized()
		var d1 := (cc - b).normalized()
		var n0 := Vector2(-d0.y, d0.x) * PT
		var n1 := Vector2(-d1.y, d1.x) * PT
		var den := d0.cross(d1)
		var q := b + n1
		if absf(den) > 1e-4:
			q = (a + n0) + d0 * ((b + n1) - (a + n0)).cross(d1) / den
		inner.append(q)
	for i in n:
		_parapet_piece(st, outer[i], outer[(i + 1) % n], inner[(i + 1) % n], inner[i], y0)
	var cut := plan.new_stack(CFPlan.OP_CUT, g, {"owner": v + 1, "label": "notch"})
	for i in n:
		var a := outer[i]
		var b := outer[(i + 1) % n]
		var len := a.distance_to(b)
		if (rnd and i % 2 == 1) or (not rnd and len < NOTCH_W + 1.2):
			continue
		var dir := (b - a) / len
		var centre := (a + b) * 0.5 + Vector2(-dir.y, dir.x) * PT * 0.5
		plan.add_layer(cut, CFShapes.rect(centre, dir, minf(NOTCH_W * 0.5, len * 0.3), PT * 0.5 + 0.2), y0 + MERLON_LOW, y0 + PH + 0.3)


func _walk_loops(area: Array, k: int) -> Array:
	## The boundary of a wall walk's cells traced into loops: per loop its points, the grid point owning each edge,
	## whether the edge is open (nothing beside it at this level) and the inner points, where the lines offset by PT
	## inwards (the interior is on the left of a counter-clockwise loop) of neighbouring edges meet.
	var next := {}                      # start point -> [end point, owner vertex, open]
	for v: int in area:
		var nb: PackedInt32Array = grid.nbrs[v]
		var ol := level_outline(v, k)
		var n := nb.size()
		for i in n:
			var u := nb[i]
			if filled(u, k) and not filled(u, k + 1) and castle_at(u, k):
				continue               # the same walk (or a block whose top is level with it): inside the area
			# open: nothing beside it at this level nor where the parapet would stand (a block hanging over the edge
			# from the level above closes it like a taller block: the parapet ends against it in stubs); a house or
			# pagoda as high as the walk is something the parapet looks over, so that side is open too
			next[ol[(i + n - 1) % n]] = [ol[i], v, not filled(u, k + 1)]
	var loops: Array = []
	var guard := 0
	while not next.is_empty() and guard < 100000:
		guard += 1
		var start: Vector2 = next.keys()[0]
		var pts := PackedVector2Array()
		var owners: Array[int] = []
		var opens: Array[bool] = []
		var cur := start
		var steps := 0
		while next.has(cur) and steps < 4000:
			steps += 1
			var e: Array = next[cur]
			next.erase(cur)
			pts.append(cur)
			owners.append(int(e[1]))
			opens.append(bool(e[2]))
			cur = e[0]
			if cur == start:
				break
		var n := pts.size()
		if n < 3:
			continue
		var inner := PackedVector2Array()
		for i in n:
			var a := pts[(i + n - 1) % n]
			var b := pts[i]
			var c := pts[(i + 1) % n]
			var d0 := (b - a).normalized()
			var d1 := (c - b).normalized()
			var n0 := Vector2(-d0.y, d0.x) * PT
			var n1 := Vector2(-d1.y, d1.x) * PT
			var den := d0.cross(d1)
			var q := b + (n0 + n1).normalized() * PT
			if absf(den) > 0.05:
				q = (a + n0) + d0 * ((b + n1) - (a + n0)).cross(d1) / den
				if q.distance_to(b) > PT * 3.0:
					q = b + (n0 + n1).normalized() * PT
			inner.append(q)
		loops.append({"pts": pts, "owners": owners, "opens": opens, "inner": inner})
	return loops


static func _stub_ext(lp: Dictionary, i: int) -> Vector2:
	## How far the stubs run along closed edge i of a walk loop from its start (x) and its end (y): where an open
	## parapet meets a taller block, a stub one parapet thick runs one parapet thickness past the parapet's inner corner
	## (never ending within centimetres of that corner: the plan merges points 2 cm apart and the floor round a sliver breaks).
	var pts: PackedVector2Array = lp.pts
	var inner: PackedVector2Array = lp.inner
	var opens: Array[bool] = lp.opens
	var n := pts.size()
	var a := pts[i]
	var b := pts[(i + 1) % n]
	var dir := (b - a) / maxf(a.distance_to(b), 1e-6)
	var ls := maxf((inner[i] - a).dot(dir), 0.0) + PT if opens[(i + n - 1) % n] else 0.0
	var le := maxf((b - inner[(i + 1) % n]).dot(dir), 0.0) + PT if opens[(i + 1) % n] else 0.0
	return Vector2(ls, le)


func _walk_battlements(area: Dictionary) -> void:
	## Battlements along the open edges of a wall walk: an open edge gets a parapet piece between its points and the
	## inner points, an edge against a taller block is offset by 0, so the parapet ends flush on that block's face
	## (welded, not just touching). Where a flight of stairs arrives, the parapet has a gap instead of notches.
	var k: int = area.k
	var g := 50000 + int(area.id)
	var stacks := {}                    # colour -> stack
	var cut := plan.new_stack(CFPlan.OP_CUT, g, {"label": "notch"})
	var gaps: Dictionary = _gaps.get(int(area.id), {})
	var gap_cut := plan.new_stack(CFPlan.OP_CUT, g, {"label": "stair gap"}) if not gaps.is_empty() else -1
	var y0 := level_y(k + 1)
	for lp: Dictionary in area.loops:
		var pts: PackedVector2Array = lp.pts
		var owners: Array[int] = lp.owners
		var opens: Array[bool] = lp.opens
		var inner: PackedVector2Array = lp.inner
		var n := pts.size()
		if not opens.has(true):
			continue
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			var v: int = owners[i]
			var c := town.colour(v, k)
			if not stacks.has(c):
				stacks[c] = plan.new_stack(CFPlan.OP_ADD, g, {"zone": CFMesh.Z_STONE, "top_zone": CFMesh.Z_STONE, "seed": colour_seed(c),
					"owner": v + 1, "prio": 11, "anchor": Vector3(grid.verts[v].x, level_y(k), grid.verts[v].y), "label": "battlement"})
			if opens[i]:
				_parapet_piece(stacks[c], a, b, inner[(i + 1) % n], inner[i], y0)
				continue
			# an edge against a taller block: where the open parapet meets it, a stub one parapet thick runs along it, so
			# the battlement presses on the block's face (two solids meeting at a single line would not be manifold)
			# The taller block's face is not always on this edge: a corner it shares only diagonally with another block is
			# pinched in (outline()), so its face leans up to ~5 degrees away. The stub's wall side therefore slants from the
			# loop corner into the block by STUB_BITE, and the two solids overlap instead of touching along one line.
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 1e-6)
			var nrm := Vector2(-dir.y, dir.x) * PT
			var start_open: bool = opens[(i + n - 1) % n]
			var end_open: bool = opens[(i + 1) % n]
			var bite := -nrm / PT * STUB_BITE
			var se := _stub_ext(lp, i)
			var ls := se.x
			var le := se.y
			if ls + le > len - 0.3:
				var full := PackedVector2Array([a, (a + b) * 0.5 + bite, b, inner[(i + 1) % n], inner[i]])
				if convex(full):
					plan.add_layer(stacks[c], full, y0, y0 + PH)
				else:
					_parapet_piece(stacks[c], a, b, inner[(i + 1) % n], inner[i], y0)
				continue
			if start_open:
				_parapet_piece(stacks[c], a, a + dir * ls + bite, a + dir * ls + nrm, inner[i], y0)
			if end_open:
				_parapet_piece(stacks[c], b - dir * le + bite, b, inner[(i + 1) % n], b - dir * le + nrm, y0)
		# notches on open edges, clear of real corners, of the loop's points and of the ends of an open run
		var corner := PackedByteArray()
		corner.resize(n)
		for i in n:
			var d0 := (pts[i] - pts[(i + n - 1) % n]).normalized()
			var d1 := (pts[(i + 1) % n] - pts[i]).normalized()
			var turn := absf(d0.angle_to(d1)) > 0.35
			var run_end := opens[i] != opens[(i + n - 1) % n]
			corner[i] = 1 if (turn or run_end) else 0
		for i in n:
			if not opens[i]:
				continue
			var a := pts[i]
			var b := pts[(i + 1) % n]
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 1e-6)
			var nrm := Vector2(-dir.y, dir.x)
			if gaps.has(a):
				# a flight of stairs arrives here: the parapet opens over the whole width of the flight
				var gp: Array = gaps[a]
				var s0: float = gp[0]
				var s1: float = gp[1]
				plan.add_layer(gap_cut, CFShapes.rect(a + dir * ((s0 + s1) * 0.5) + nrm * PT * 0.5, dir, (s1 - s0) * 0.5, PT * 0.5 + 0.2),
					y0, y0 + PH + 0.3)
				continue
			var lo := 0.08 + NOTCH_W * 0.5 + (0.5 if corner[i] else 0.0)
			var hi := len - 0.08 - NOTCH_W * 0.5 - (0.5 if corner[(i + 1) % n] else 0.0)
			if hi < lo:
				continue
			var count := maxi(1, int((hi - lo) / NOTCH_STEP) + 1)
			for j in count:
				var s := lo + (hi - lo) * (float(j) + 0.5) / float(count)
				var centre := a + dir * s + nrm * PT * 0.5
				plan.add_layer(cut, CFShapes.rect(centre, dir, NOTCH_W * 0.5, PT * 0.5 + 0.2), y0 + MERLON_LOW, y0 + PH + 0.3)


# --- stairs ----------------------------------------------------------------------------------------

func _choose_stairs(areas: Array) -> void:
	## One flight between each pair of walk areas a level apart that touch, and between each courtyard and each walk at
	## level 0 beside it: of the sides where a flight fits, the one its two grid points pick (seeded), one flight per cell.
	var area_of := {}                   # key(v, k) -> area index
	for ai in areas.size():
		for v: int in areas[ai].cells:
			area_of[CSTown.key(v, int(areas[ai].k))] = ai
	var court_of := {}                  # court cell -> courtyard number
	var ncourt := 0
	for v0: int in land:
		if land[v0] != "court" or court_of.has(v0):
			continue
		var st: Array[int] = [v0]
		court_of[v0] = ncourt
		var guard := 0
		while not st.is_empty() and guard < 100000:
			guard += 1
			var v: int = st.pop_back()
			for u in grid.nbrs[v]:
				if not court_of.has(u) and land.get(u, "") == "court":
					court_of[u] = ncourt
					st.append(u)
		ncourt += 1
	var cands: Array = []
	for bi in areas.size():
		var up: Dictionary = areas[bi]
		var ku: int = up.k
		for u: int in up.cells:
			for c in grid.nbrs[u]:
				if not grid.buildable(c):
					continue
				var pair := ""
				var low := {}
				if ku >= 1:
					var ai: int = area_of.get(CSTown.key(c, ku - 1), -1)
					if ai < 0 or top_of(c) != ku - 1:
						continue           # no walk a level down, or something stands above it (a pillar, a floating block)
					low = areas[ai]
					pair = "a%d:%d" % [ai, bi]
				elif land.get(c, "") == "court":
					pair = "c%d:%d" % [int(court_of[c]), bi]
				else:
					continue
				var cand := _stair_fit(c, u, ku - 1, low, up)
				if cand.is_empty():
					continue
				cand["pair"] = pair
				cand["score"] = h01(mini(c, u), maxi(c, u), 31)
				cands.append(cand)
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if float(x.score) != float(y.score):
			return float(x.score) < float(y.score)
		return int(x.cell) * 4096 + int(x.up) < int(y.cell) * 4096 + int(y.up))
	var done := {}
	var used := {}
	for cand: Dictionary in cands:
		if done.has(cand.pair) or used.has(cand.cell):
			continue
		done[cand.pair] = true
		used[cand.cell] = true
		stairs.append(cand)
		_covered[CSTown.key(int(cand.up), int(cand.k) + 1) * 16 + int(cand.up_face)] = true
		var aid: int = cand.area_up
		if not _gaps.has(aid):
			_gaps[aid] = {}
		(_gaps[aid] as Dictionary)[cand.gap_start] = cand.gap


func _loop_edge(area: Dictionary, start: Vector2, owner: int) -> Dictionary:
	for lp: Dictionary in area.loops:
		var pts: PackedVector2Array = lp.pts
		var owners: Array[int] = lp.owners
		for i in pts.size():
			if pts[i] == start and owners[i] == owner:
				return {"loop": lp, "i": i}
	return {}


static func _ray_in(ol: PackedVector2Array, lim: PackedFloat32Array, q: Vector2, d: Vector2) -> float:
	## How far q can move along d and stay at least lim[i] inside every side i (ol[i - 1] -> ol[i]) of a convex
	## counter-clockwise outline (0 when it starts outside): the half-planes themselves, so a margin wider than a narrow
	## cell cannot turn an inset outline inside out.
	var best := INF
	var n := ol.size()
	for i in n:
		var e0 := ol[(i + n - 1) % n]
		var de := (ol[i] - e0).normalized()
		var f0 := de.cross(q - e0) - lim[i]
		var fd := de.cross(d)
		if f0 < -1e-4:
			return 0.0
		if fd < -1e-9:
			best = minf(best, f0 / -fd)
	return best


func _stair_fit(c: int, u: int, kl: int, low: Dictionary, up: Dictionary) -> Dictionary:
	## A flight on cell c's floor (the top of its walk at level kl, or the courtyard when kl = -1) climbing straight up to
	## the walk of u at level kl + 1, its top step against u's side. {} when it does not fit: a pinched side (the faces
	## would not meet flush), a side under 3 m, a door, the lower walk's stubs or the upper parapet's corners in the way,
	## or less than 2.2 m of floor to run on.
	var ku := kl + 1
	var nbc: PackedInt32Array = grid.nbrs[c]
	var n := nbc.size()
	var ic := grid.index_of(c, u)
	var iu := grid.index_of(u, c)
	if ic < 0 or iu < 0:
		return {}
	var rgc: PackedInt32Array = grid.rings[c]
	var raw0 := grid.centers[rgc[(ic + n - 1) % n]]
	var raw1 := grid.centers[rgc[ic]]
	var floor_ol := level_outline(c, kl) if kl >= 0 else outline(c, func(x: int) -> bool: return land.has(x))
	if not convex(floor_ol) or floor_ol[(ic + n - 1) % n] != raw0 or floor_ol[ic] != raw1:
		return {}
	var m := (grid.nbrs[u] as PackedInt32Array).size()
	var olu := level_outline(u, ku)
	var g0 := olu[(iu + m - 1) % m]
	var g1 := olu[iu]
	if not ((g0 == raw1 and g1 == raw0) or (g0 == raw0 and g1 == raw1)):
		return {}
	if kl < 0 and int(doors.get(u, -1)) == iu:
		return {}                       # never in front of a door
	var len := raw0.distance_to(raw1)
	# hex cells have six shorter sides (~2.9 m) whose corners open at 120 deg: shorter sides and end margins do
	var hexg := grid.fn == 3
	if len < (2.6 if hexg else 3.0):
		return {}
	var dir := (raw1 - raw0) / len
	var nin := Vector2(-dir.y, dir.x)   # into c
	var lo := 0.0
	var hi := len
	if kl >= 0:
		var el := _loop_edge(low, raw0, c)
		if el.is_empty() or bool((el.loop.opens as Array)[int(el.i)]):
			return {}
		var se := _stub_ext(el.loop, int(el.i))
		lo = maxf(lo, se.x + 0.15)
		hi = minf(hi, len - se.y - 0.15)
	# the upper parapet opens over the flight (plus a margin), well inside its inner line
	var eu := _loop_edge(up, g0, u)
	if eu.is_empty() or not bool((eu.loop.opens as Array)[int(eu.i)]):
		return {}
	var pu: PackedVector2Array = eu.loop.pts
	var inu: PackedVector2Array = eu.loop.inner
	var j: int = eu.i
	var nu := pu.size()
	var si0 := (inu[j] - raw0).dot(dir)
	var si1 := (inu[(j + 1) % nu] - raw0).dot(dir)
	var span_lo := maxf(minf(si0, si1), 0.0) + 0.25 + GAP_MARGIN
	var span_hi := minf(maxf(si0, si1), len) - 0.25 - GAP_MARGIN
	var endm := 0.75 if hexg else 1.0
	lo = maxf(lo, maxf(span_lo, endm + GAP_MARGIN))
	hi = minf(hi, minf(span_hi, len - endm - GAP_MARGIN))
	var hw := minf(STAIR_HW, (hi - lo) * 0.5)
	if hw < 0.45:
		return {}
	var mid := (lo + hi) * 0.5
	# how far it can run into c: inside the floor, clear of the parapets and walls round it, well clear of doors
	var lim := PackedFloat32Array()
	lim.resize(n)
	for mm in n:
		var w := nbc[mm]
		if mm == ic:
			lim[mm] = 0.0
		elif fills.has(CSTown.key(w, ku)):
			lim[mm] = 1.5               # an arch beside it at this height: keep its passage clear
		elif kl >= 0:
			lim[mm] = 0.1 if (filled(w, kl) and not filled(w, kl + 1)) else PT + 0.15
		elif land.get(w, "") == "court":
			lim[mm] = 0.1
		elif int(doors.get(w, -1)) == grid.index_of(w, c):
			lim[mm] = 1.5
		else:
			lim[mm] = 0.15
	var b0 := raw0 + dir * (mid - hw)
	var b1 := raw0 + dir * (mid + hw)
	var run := minf(minf(_ray_in(floor_ol, lim, b0, nin), _ray_in(floor_ol, lim, b1, nin)), H) - 0.05
	if run < STAIR_MIN_RUN:
		return {}
	var du := (g1 - g0).normalized()
	var ga := (b0 - g0).dot(du)
	var gb := (b1 - g0).dot(du)
	return {"cell": c, "up": u, "face": ic, "up_face": iu, "k": kl, "b0": b0, "b1": b1, "nin": nin, "run": run,
		"area_up": int(up.id), "gap_start": g0, "gap": [minf(ga, gb) - GAP_MARGIN, maxf(ga, gb) + GAP_MARGIN]}


func _stair(s: Dictionary) -> void:
	## Ten steps of 0.4 m, each running a tenth less far out from the wall, all against the upper block's side.
	var c: int = s.cell
	var kl: int = s.k
	var y0 := level_y(kl + 1) if kl >= 0 else B
	var rise := H / float(STAIR_STEPS)
	var run: float = s.run
	var tread := run / float(STAIR_STEPS)
	var b0: Vector2 = s.b0
	var b1: Vector2 = s.b1
	var nin: Vector2 = s.nin
	var mid := (b0 + b1) * 0.5
	var info := {"zone": CFMesh.Z_STONE, "top_zone": CFMesh.Z_FLAG, "seed": colour_seed(town.colour(int(s.up), kl + 1)), "owner": c + 1,
		"prio": 11, "anchor": Vector3(mid.x, y0, mid.y), "label": "stairs"}
	for j in STAIR_STEPS:
		# a stack per step: the plan splits an outline only at other stacks' corners, and each step's sides end on the
		# sides of the step below
		var d := run - tread * float(j)
		plan.add_layer(plan.new_stack(CFPlan.OP_ADD, 80000 + c, info), PackedVector2Array([b0, b1, b1 + nin * d, b0 + nin * d]),
			y0 + rise * float(j), y0 + rise * float(j + 1))
	extras.append({"poly": PackedVector2Array([b0, b1, b1 + nin * run, b0 + nin * run]), "y0": y0, "y1": y0 + H})


func _openings() -> void:
	## Arrow slits and windows in the open sides, a door in a ground block next to land.
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		var p := grid.verts[v]
		var nb: PackedInt32Array = grid.nbrs[v]
		for k in range(0, top_of(v) + 1):
			if not town.has(v, k):
				continue
			var rnd := is_round(v, k)
			var r := round_radius(v) if rnd else 0.0
			var sty := town.style(v, k)
			var cs := plan.new_stack(CFPlan.OP_CUT, 10000 + v, {"zone": CFMesh.Z_DARK, "owner": v + 1, "label": "opening"})
			var y := level_y(k)
			for i in nb.size():
				var u := nb[i]
				if filled(u, k) or _covered.has(CSTown.key(v, k) * 16 + i):
					continue               # a block or an arch beside it, or a flight of stairs against it
				var out := (grid.verts[u] - p).normalized()
				var sp := p + out * r
				if not rnd:
					var ol := level_outline(v, k)
					var f := PackedVector2Array([ol[(i + nb.size() - 1) % nb.size()], ol[i]])
					if f[0].distance_to(f[1]) < 2.6:
						continue           # too short a side for a door or a window
					sp = (f[0] + f[1]) * 0.5
					var along := (f[1] - f[0]).normalized()
					out = Vector2(along.y, -along.x)      # straight out of the side (the cell is on its left)
				var roll := h01(v * 16 + i, k, 5)
				if sty != CSStyle.CASTLE:
					# a house, tower or pagoda: its windows are painted (CSFacades, the wall shader); only the front door is cut
					if k == 0 and int(doors.get(v, -1)) == i:
						_door(v, sp, out, y, sty)
						_note("door", v, k, i, sp, out, y, y + 2.3, 0.55, rnd, sty)
					continue
				if k == 0:
					if int(doors.get(v, -1)) == i:
						_door(v, sp, out, y)
						_note("door", v, k, i, sp, out, y, y + 2.3, 0.55, rnd)
					elif not land.has(u) and roll < 0.3:
						_recess(cs, sp, out, y + 1.4, 1.1, 0.08)
						_note("slit", v, k, i, sp, out, y + 1.4, y + 2.5, 0.08, rnd)
				else:
					if rnd and roll < 0.35:
						continue
					if roll < 0.45:
						_recess(cs, sp, out, y + 1.3, 1.4, 0.08)        # an arrow slit
						_note("slit", v, k, i, sp, out, y + 1.3, y + 2.7, 0.08, rnd)
					elif roll < 0.75:
						_recess(cs, sp, out, y + 1.4, 1.25, 0.34)       # a window
						_note("window", v, k, i, sp, out, y + 1.4, y + 2.65, 0.34, rnd)


func _note(kind: String, v: int, k: int, i: int, sp: Vector2, out: Vector2, y0: float, y1: float, hw: float, rnd: bool, sty: int = 0) -> void:
	## An opening for the prop layer: on side i of block (v, k), centred on sp (on the wall, or on the circle round a
	## round tower), facing out, y0..y1, half as wide as hw.
	openings.append({"kind": kind, "v": v, "k": k, "i": i, "p": sp, "out": out, "y0": y0, "y1": y1, "hw": hw, "round": rnd, "style": sty})


func _recess(cut_stack: int, surface: Vector2, out: Vector2, y0: float, h: float, half_w: float, depth: float = 0.5) -> void:
	var centre := surface - out * (depth * 0.5 - 0.15)
	plan.add_layer(cut_stack, CFShapes.rect(centre, out, depth * 0.5 + 0.15, half_w), y0, y0 + h, CFMesh.Z_DARK)


func _door(v: int, surface: Vector2, out: Vector2, y: float, sty: int = 0) -> void:
	var cs := plan.new_stack(CFPlan.OP_CUT, 10000 + v, {"owner": v + 1, "label": "door", "zone": CSStyle.wall_zone(sty)})
	var depth := 0.55
	plan.add_layer(cs, CFShapes.rect(surface - out * (depth * 0.5 - 0.15), out, depth * 0.5 + 0.15, 0.55), y, y + 2.3)
	var lz := CFMesh.Z_DOOR if sty == CSStyle.CASTLE else CSStyle.trim_zone(sty)
	var leaf := plan.new_stack(CFPlan.OP_ADD, 70000 + v, {"zone": lz, "top_zone": lz, "owner": v + 1, "prio": 12,
		"flags": CFMesh.F_PLAIN, "label": "door leaf", "seed": colour_seed(town.colour(v, 0))})
	# its back face is the recess's own back wall: a leaf reaching 2 cm behind it puts two corners exactly one weld distance apart (castle doors did,
	# and on the hex grid's short sides that left a 2 cm sliver open)
	plan.add_layer(leaf, CFShapes.rect(surface - out * (depth - 0.07), out, 0.07, 0.55), y, y + 2.2)


func _hats() -> void:
	## The hats of the styled tops, closed shells appended to the skin; then the facades of the painted walls get their bay layout.
	for kk: int in hats:
		var h: Dictionary = hats[kk]
		for part: Dictionary in h.parts:
			var rm := CFMesh.new()
			(part.sh as CSRoofs.Shell).emit(rm, part.inside, h.seed, h.owner, h.anchor, "hat")
			mesh.append_mesh(rm)
	facades = 0
	if _styled:
		var fd: Array = []
		for op: Dictionary in openings:
			if str(op.kind) == "door" and int(op.get("style", 0)) != CSStyle.CASTLE:
				var s: int = op.style
				fd.append({"out": op.out, "p": op.p, "zone": CSStyle.wall_zone(s), "seed": colour_seed(town.colour(int(op.v), int(op.k))), "owner": int(op.v) + 1})
		facades = CSFacades.annotate(mesh, fd)


func _roofs() -> void:
	for rec: Dictionary in caps:
		var li: int = rec.layer
		var loop := plan.layer_loop(li)
		var cidx := plan.layer_corner_idx(li)
		if loop.size() < 3 or cidx.size() < 3:
			continue
		var rm := CFMesh.new()
		rm.begin(rec.zone, rec.seed, 0, rec.owner, rec.anchor, "roof")
		var tip := CFRoofs.cone(rm, loop, cidx, rec.y, rec.center, rec.h)
		if tip.size() >= 3:
			# the pole closes the cone's tip ring; only some towers fly a banner from it
			rm.begin(CFMesh.Z_TIMBER, rec.seed, 0, rec.owner, rec.anchor, "pole")
			CFRoofs.pole(rm, tip, 2.2 if rec.banner else 0.9, CFMesh.Z_CLOTH_A if float(rec.seed) < 0.5 else CFMesh.Z_CLOTH_B,
				Vector3(1, 0, 0.3), 1.3, bool(rec.banner))
		mesh.append_mesh(rm)
