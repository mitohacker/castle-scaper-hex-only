class_name CSProps
extends RefCounted
## The prop layer (TOWNSCAPER_GAP item 2): small details as separate instanced meshes, never welded into the castle
## skin (Townscaper's props are rigid meshes placed after the base pieces, each kept only if nothing more important
## overlaps it). After CSBuild.build:
## 1. every block side and top proposes candidates: a kind, a cost, the boxes it would fill and the meshes it shows;
## 2. they are sorted by cost, ties broken by a hash of the grid point (deterministic), and kept greedily when their
##    boxes overlap nothing kept so far (the doors, slits and windows of CSBuild.openings are kept first), no block or
##    arch, no corbel, pillar or flight of stairs (CSBuild.extras), the land, a parapet or a roof: an independent set,
##    so no two props intersect and none sits inside the castle;
## 3. the kept props become, per mesh, a list of transforms + palette colours (multimeshes(), on the build thread),
##    shown by cs_main with one MultiMeshInstance3D each, popping in and out with their block (cs_props.gdshader).
## Wall props are made in a frame on the wall: x along it, y up, z out of it (z = 0 is the wall, or for a round tower
## the plane touching the circle round it); their meshes reach EMBED behind that plane, hidden in the masonry, while
## their boxes start at z = 0.

const EPS := 0.005              # boxes that overlap by less than this are apart (touching is fine)
const EMBED := 0.12             # how far a wall prop's mesh reaches behind its mount plane
const CELL := 2.0               # spatial hash cell (m)

enum { FRAME, SHUTTERS, FLOWERS, SHIELD, BANNER, TORCH, CHIMNEY, HOARDING, CORBELS, CRATES, BARRELS, BUNTING, STRING, IVY, ROOFGEAR, PAPER, TORII, AWNING }
const KINDS := ["frame", "shutters", "flowers", "shield", "banner", "torch", "chimney", "hoarding", "corbels", "crates",
	"barrels", "bunting", "string", "ivy", "roofgear", "paper", "torii", "awning"]
const CASTLE_KINDS := 14          # the first kinds are the castle's, the rest belong to the building styles (CSStyleProps)

# meshes (one MultiMesh each)
const M_FRAME := 0
const M_SHUTTER := 1
const M_FLOWERBOX := 2
const M_SHIELD := 3
const M_BANNER := 4
const M_TORCH := 5
const M_CHIMNEY := 6
const M_CHIMNEY_CAP := 7
const M_HOARDING := 8
const M_CORBEL := 9
const M_SLAB := 10
const M_CRATE := 11
const M_BARREL := 12
const M_ROPE := 13
const M_FLAG := 14
const M_HOOK := 15
const M_STRING := 16            # a moulded string course, 1 m long (scaled to the wall)
const M_IVY := 17               # a patch of ivy 1 m wide, 1 m high (scaled to the wall)
const MESH_COUNT := 26             # 0..17 here, 18..25 in CSStyleProps

# paint zones (COLOR.r * 255), read by shaders/cs_props.gdshader
const P_OWN := 0                # the block's colour (instance custom x)
const P_SECOND := 1             # the second colour (instance custom y)
const P_LIGHT := 2              # the block's colour lightened: frames, sills, string courses
const P_WOOD := 3               # planks
const P_DARKWOOD := 4           # beams, brackets, battens
const P_IRON := 5
const P_GLOW := 6               # a lantern's flame
const P_LEAF := 7
const P_BLOOM := 8              # flowers in the second colour
const P_DARK := 9               # a chimney's flue, loopholes
const P_ROPE := 10
const P_EARTH := 11
const P_SECOND_PLANKS := 12     # shutters: planks painted the second colour
const P_CLOTH := 13             # bunting: the block's colour, a little deeper (pastel walls make pale flags)
const P_PAPER := 14             # a paper lantern, lit from inside (colour b: 0 red, 1 white, 2 amber, 3 teal)
const P_LACQUER := 15           # vermilion lacquer
const P_METAL := 16             # galvanised sheet: air conditioners, tanks, masts
const P_GOLD := 17              # gilt
const P_CLOTH2 := 18            # an awning's second strip: colour b, as P_CLOTH is colour a

const SHUTTER_COLS := [8, 9, 7, 4, 11, 6, 2]
const BLOOM_COLS := [4, 5, 2, 6, 3, 0]
const HERALDRY := [[4, 0], [7, 0], [8, 1], [11, 1], [2, 7], [9, 0], [6, 1], [10, 4], [5, 7]]


class Box:
	var c := Vector3.ZERO       # centre
	var ax := Vector2.RIGHT     # first horizontal axis (unit)
	var az := Vector2.DOWN      # second horizontal axis (unit, perpendicular to ax)
	var he := Vector3.ZERO      # half extents along ax, up, az
	var r := 0.0                # horizontal bounding radius


class Cand:
	var kind := 0
	var cost := 0.0
	var tie := 0.0
	var id := 0
	var boxes: Array = []
	var inst: Array = []        # [mesh, Transform3D, colour a, colour b]
	var group := ""             # at most one candidate of a group is kept (alternative spots for one prop)
	var needs = null            # a Cand that must be kept first (shutters and flowers need their frame)
	var ok := false
	var owner := 0              # grid point + 1: pops with that column (the shader's pop_id)
	var key := -1               # the block it hangs on (it leaves with it)
	var key2 := -1              # bunting: the block at the other end
	var own_roof := -1          # a chimney: its own cottage's roof is not in its way
	var perch := Vector3.INF    # a bird may sit here


var b: CSBuild
var grid: CSGrid
var town: CSTown
var cands: Array = []
var kept: Array = []
var fixed: Array = []           # the openings' boxes (kept before any prop)
var counts := {}                # kind name -> props kept
var stats := {}
var _hash := {}                 # Vector2i -> [Box]: kept boxes and openings
var _solid := {}                # Vector2i -> [grid points with land or blocks whose cell reaches that hash cell]
var _rad := {}                  # grid point -> how far its cell reaches from it
var _pieces := {}               # block key -> its outline as convex pieces
var _land_p := {}               # grid point -> its land cell as convex pieces
var _outl := {}                 # block key -> level outline
var _ext := {}                  # top block key -> how far its parapet / roof / pole reaches above its top
var _caps := {}                 # block key -> CSBuild cap record (its roof)
var _extra := {}                # Vector2i -> [indices into CSBuild.extras]: corbels, pillars, stairs (arches count as blocks)


static func wall_basis(out: Vector2) -> Basis:
	## A wall prop's frame: x along the wall, y up, z = out (right-handed).
	var z := Vector3(out.x, 0.0, out.y).normalized()
	return Basis(Vector3(z.z, 0.0, -z.x), Vector3.UP, z)


static func box(o: Vector3, bas: Basis, lo: Vector3, hi: Vector3) -> Box:
	## The box lo..hi in a prop's frame (origin o, unit axes bas: x and z horizontal, y up).
	var bx := Box.new()
	var m := (lo + hi) * 0.5
	bx.c = o + bas.x * m.x + bas.y * m.y + bas.z * m.z
	bx.ax = Vector2(bas.x.x, bas.x.z).normalized()
	bx.az = Vector2(bas.z.x, bas.z.z).normalized()
	bx.he = (hi - lo) * 0.5
	bx.r = Vector2(bx.he.x, bx.he.z).length()
	return bx


static func overlap(a: Box, o: Box) -> bool:
	## Whether two boxes overlap by more than EPS (separating axes; both stand upright).
	if absf(a.c.y - o.c.y) >= a.he.y + o.he.y - EPS:
		return false
	var d := Vector2(o.c.x - a.c.x, o.c.z - a.c.z)
	if d.length() >= a.r + o.r - EPS:
		return false
	for u: Vector2 in [a.ax, a.az, o.ax, o.az]:
		var ra := a.he.x * absf(a.ax.dot(u)) + a.he.z * absf(a.az.dot(u))
		var ro := o.he.x * absf(o.ax.dot(u)) + o.he.z * absf(o.az.dot(u))
		if absf(d.dot(u)) >= ra + ro - EPS:
			return false
	return true


static func rect_poly(bx: Box, poly: PackedVector2Array) -> bool:
	## Whether a box's footprint and a convex polygon overlap by more than EPS.
	var c := Vector2(bx.c.x, bx.c.z)
	if _apart(c, bx, poly, bx.ax) or _apart(c, bx, poly, bx.az):
		return false
	var n := poly.size()
	for i in n:
		var e := poly[(i + 1) % n] - poly[i]
		if e.length_squared() < 1e-10:
			continue
		if _apart(c, bx, poly, Vector2(-e.y, e.x).normalized()):
			return false
	return true


static func _apart(c: Vector2, bx: Box, poly: PackedVector2Array, u: Vector2) -> bool:
	var rc := c.dot(u)
	var rr := bx.he.x * absf(bx.ax.dot(u)) + bx.he.z * absf(bx.az.dot(u))
	var lo := INF
	var hi := -INF
	for p in poly:
		var d := p.dot(u)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return hi <= rc - rr + EPS or lo >= rc + rr - EPS


static func corners(bx: Box) -> PackedVector2Array:
	var c := Vector2(bx.c.x, bx.c.z)
	var x := bx.ax * bx.he.x
	var z := bx.az * bx.he.z
	return PackedVector2Array([c - x - z, c + x - z, c + x + z, c - x + z])


# --- build -----------------------------------------------------------------------------------------

func build(cb: CSBuild) -> void:
	var t0 := Time.get_ticks_usec()
	b = cb
	grid = cb.grid
	town = cb.town
	_index()
	_fix_openings()
	_windows()
	_doors()
	_towers()
	_cottages()
	_houses()
	_walks()
	_courts()
	_bunting()
	_ornaments()
	CSStyleProps.build(self)
	var t1 := Time.get_ticks_usec()
	_solve()
	var t2 := Time.get_ticks_usec()
	stats = {"candidates": cands.size(), "kept": kept.size(), "ms": float(t2 - t0) / 1000.0, "ms_propose": float(t1 - t0) / 1000.0,
		"ms_solve": float(t2 - t1) / 1000.0}


func _cand(kind: int, cost: float, tie: float, v: int, key: int) -> Cand:
	var c := Cand.new()
	c.kind = kind
	c.cost = cost
	c.tie = tie
	c.id = cands.size()
	c.owner = v + 1
	c.key = key
	cands.append(c)
	return c


func _index() -> void:
	for kn: String in KINDS:
		counts[kn] = 0
	var pts := {}
	for v: int in town.columns():
		if grid.buildable(v):
			pts[v] = true
	for v: int in b.land:
		pts[v] = true
	for v: int in pts:
		var p := grid.verts[v]
		var r := 0.0
		for q in grid.dual(v):
			r = maxf(r, q.distance_to(p))
		_rad[v] = r
		for hk: Vector2i in _cells(Vector2(p.x, p.y), r):
			if not _solid.has(hk):
				_solid[hk] = []
			(_solid[hk] as Array).append(v)
	for xi in b.extras.size():
		var poly: PackedVector2Array = b.extras[xi].poly
		var lo := poly[0]
		var hi := poly[0]
		for q in poly:
			lo = lo.min(q)
			hi = hi.max(q)
		for hk: Vector2i in _cells((lo + hi) * 0.5, (hi - lo).length() * 0.5):
			if not _extra.has(hk):
				_extra[hk] = []
			(_extra[hk] as Array).append(xi)
	for rec: Dictionary in b.caps:
		var v: int = int(rec.owner) - 1
		var k := roundi((float(rec.y) - CSBuild.B) / CSBuild.H) - 1
		_caps[CSTown.key(v, k)] = rec
	for kk: int in b.kinds:
		var kind: String = b.kinds[kk]
		var e := 0.0
		if kind == "walk" or kind == "battle":
			e = CSBuild.PH + 0.02
		elif _caps.has(kk):
			var rec: Dictionary = _caps[kk]
			e = float(rec.h) + (2.6 if bool(rec.banner) else 1.05)
		_ext[kk] = e
	for kk: int in b.hats:
		var hh: Dictionary = b.hats[kk]
		_ext[kk] = float(hh.top) - CSBuild.level_y_static(int(hh.k) + 1) + 0.06


func _cells(c: Vector2, r: float) -> Array:
	var out := []
	for gx in range(floori((c.x - r) / CELL), floori((c.x + r) / CELL) + 1):
		for gz in range(floori((c.y - r) / CELL), floori((c.y + r) / CELL) + 1):
			out.append(Vector2i(gx, gz))
	return out


func _outline(v: int, k: int) -> PackedVector2Array:
	var kk := CSTown.key(v, k)
	if not _outl.has(kk):
		_outl[kk] = b.level_outline(v, k)
	return _outl[kk]


func _block_pieces(v: int, k: int) -> Array:
	var kk := CSTown.key(v, k)
	if not _pieces.has(kk):
		_pieces[kk] = [b.round_poly(v)] if b.is_round(v, k) else b.polys_of(v, _outline(v, k))
	return _pieces[kk]


func _land_pieces(v: int) -> Array:
	## The whole cell (the land's own outline lies inside it, so this errs on the safe side).
	if not _land_p.has(v):
		_land_p[v] = b.polys_of(v, grid.dual(v))
	return _land_p[v]


func _sides(v: int, k: int) -> Array:
	## The open sides of block (v, k): [i, middle, way out, length]. A round block's side is where the way to
	## neighbour i leaves the circle round the tower.
	var out := []
	var nb: PackedInt32Array = grid.nbrs[v]
	var n := nb.size()
	var p := grid.verts[v]
	if b.is_round(v, k):
		var r := b.round_radius(v)
		for i in n:
			if not b.filled(nb[i], k):
				var d := (grid.verts[nb[i]] - p).normalized()
				out.append([i, p + d * r, d, 2.0 * r])
		return out
	var ol := _outline(v, k)
	for i in n:
		if b.filled(nb[i], k):
			continue
		var f0 := ol[(i + n - 1) % n]
		var f1 := ol[i]
		var len := f0.distance_to(f1)
		if len < 1.2:
			continue
		var along := (f1 - f0) / len
		out.append([i, (f0 + f1) * 0.5, Vector2(along.y, -along.x), len])
	return out


static func _pick(list: Array, h: float, avoid: int) -> int:
	var i := int(h * float(list.size())) % list.size()
	if int(list[i]) == avoid:
		i = (i + 1) % list.size()
	return int(list[i])


# --- what each block proposes ----------------------------------------------------------------------

func _fix_openings() -> void:
	## Doors (with the step in front of them), slits and windows are kept before any prop.
	for op: Dictionary in b.openings:
		var p: Vector2 = op.p
		var o := Vector3(p.x, float(op.y0), p.y)
		var bas := wall_basis(op.out)
		var h := float(op.y1) - float(op.y0)
		var bx: Box
		match str(op.kind):
			"door":
				bx = box(o, bas, Vector3(-0.62, 0.0, 0.0), Vector3(0.62, h + 0.06, 1.0))
			"window":
				bx = box(o, bas, Vector3(-0.34, 0.0, 0.0), Vector3(0.34, h, 0.35))
			_:
				bx = box(o, bas, Vector3(-0.15, 0.0, 0.0), Vector3(0.15, h, 0.35))
		fixed.append(bx)
		_insert(bx)


func _windows() -> void:
	## A frame round every window; shutters and a flower box on some (not on round towers: the wall curves away).
	for op: Dictionary in b.openings:
		if str(op.kind) != "window":
			continue
		var v: int = op.v
		var k: int = op.k
		var slot: int = v * 16 + int(op.i)
		var p: Vector2 = op.p
		var o := Vector3(p.x, float(op.y0), p.y)
		var bas := wall_basis(op.out)
		var wall := town.colour(v, k)
		var kk := CSTown.key(v, k)
		var fr := _cand(FRAME, 1.0, CSBuild.h01(slot, k, 41), v, kk)
		fr.boxes = [box(o, bas, Vector3(-0.45, -0.04, 0.0), Vector3(-0.34, 1.25, 0.06)),
			box(o, bas, Vector3(0.34, -0.04, 0.0), Vector3(0.45, 1.25, 0.06)),
			box(o, bas, Vector3(-0.49, 1.25, 0.0), Vector3(0.49, 1.44, 0.11)),
			box(o, bas, Vector3(-0.51, -0.13, 0.0), Vector3(0.51, 0.0, 0.15))]
		fr.inst = [[M_FRAME, Transform3D(bas, o), wall, wall]]
		if bool(op.round):
			continue
		if CSBuild.h01(slot, k, 42) < 0.6:
			var sc := _pick(SHUTTER_COLS, CSBuild.h01(slot, k, 44), wall)
			var sh := _cand(SHUTTERS, 2.0, CSBuild.h01(slot, k, 45), v, kk)
			sh.needs = fr
			for s: float in [-1.0, 1.0]:
				var cx := 0.67 * s
				sh.boxes.append(box(o, bas, Vector3(cx - 0.17, 0.0, 0.0), Vector3(cx + 0.17, 1.25, 0.05)))
				sh.inst.append([M_SHUTTER, Transform3D(bas, o + bas.x * cx), wall, sc])
		if CSBuild.h01(slot, k, 43) < 0.5:
			var fc: int = BLOOM_COLS[int(CSBuild.h01(slot, k, 46) * float(BLOOM_COLS.size())) % BLOOM_COLS.size()]
			var fl := _cand(FLOWERS, 3.0, CSBuild.h01(slot, k, 47), v, kk)
			fl.needs = fr
			fl.boxes = [box(o, bas, Vector3(-0.44, -0.63, 0.0), Vector3(0.44, -0.13, 0.32))]
			fl.inst = [[M_FLOWERBOX, Transform3D(bas, o), wall, fc]]


func _mount(op: Dictionary, dx: float) -> Array:
	## A spot dx along the wall from an opening's middle: [point, way out]. On a round tower it walks round the circle.
	var out: Vector2 = op.out
	var v: int = op.v
	if bool(op.round):
		var r := b.round_radius(v)
		var d := out.rotated(-dx / r)
		return [grid.verts[v] + d * r, d]
	return [(op.p as Vector2) + Vector2(out.y, -out.x) * dx, out]


func _doors() -> void:
	## A lantern on a bracket beside every door, now and then one on each side.
	for op: Dictionary in b.openings:
		if str(op.kind) != "door" or int(op.get("style", 0)) != CSStyle.CASTLE:
			continue
		var v: int = op.v
		var k: int = op.k
		var slot: int = v * 16 + int(op.i)
		var first := 1.0 if CSBuild.h01(slot, k, 81) < 0.5 else -1.0
		for side: float in [first, -first]:
			if side != first and CSBuild.h01(slot, k, 82) > 0.35:
				continue
			var m := _mount(op, side * 0.95)
			var q: Vector2 = m[0]
			var o := Vector3(q.x, float(op.y0) + 2.05, q.y)
			var bas := wall_basis(m[1])
			var t := _cand(TORCH, 2.0 if side == first else 2.6, CSBuild.h01(slot, k, 83 + int(side > 0.0)), v, CSTown.key(v, k))
			t.boxes = [box(o, bas, Vector3(-0.14, -0.36, 0.0), Vector3(0.14, 0.1, 0.4))]
			t.inst = [[M_TORCH, Transform3D(bas, o), town.colour(v, k), 0]]


func _tower_spots(v: int, k: int, odd: bool) -> Array:
	## Where a shield or banner may hang on a tower block: [point, way out, slot]. A round tower offers eight ways
	## round its circle (every other side of its 16-gon, `odd` picks which half), a mural tower its open sides.
	var out := []
	if b.is_round(v, k):
		var p := grid.verts[v]
		var r := b.round_radius(v)
		var a0 := (grid.verts[grid.nbrs[v][0]] - p).angle()
		for j in 8:
			var s := 2 * j + (1 if odd else 0)
			var d := Vector2.from_angle(a0 + TAU * float(s) / 16.0)
			out.append([p + d * r, d, s])
		return out
	for sd: Array in _sides(v, k):
		if float(sd[3]) >= 1.4:
			out.append([sd[1], sd[2], int(sd[0])])
	return out


func _towers() -> void:
	## Shields on the top two levels of towers, a banner under the top of some.
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		var tk := b.top_of(v)
		var kind: String = b.kinds.get(CSTown.key(v, tk), "")
		if kind != "tower" and kind != "battle":
			continue
		var odd := CSBuild.h01(v, 56) < 0.5
		for k in range(tk, maxi(tk - 2, -1), -1):
			if not town.has(v, k) or not b.isolated(v, k):
				break
			var kk := CSTown.key(v, k)
			if CSBuild.h01(v, k, 51) < 0.7:
				var ha: Array = HERALDRY[int(CSBuild.h01(v, k, 52) * float(HERALDRY.size())) % HERALDRY.size()]
				for m: Array in _tower_spots(v, k, odd):
					var q: Vector2 = m[0]
					var o := Vector3(q.x, CSBuild.level_y_static(k) + 2.1, q.y)
					var bas := wall_basis(m[1])
					var sh := _cand(SHIELD, 3.0, CSBuild.h01(v * 16 + int(m[2]), k, 53), v, kk)
					sh.group = "shield %d" % kk
					sh.boxes = [box(o, bas, Vector3(-0.3, -0.42, 0.0), Vector3(0.3, 0.38, 0.13))]
					sh.inst = [[M_SHIELD, Transform3D(bas, o), int(ha[0]), int(ha[1])]]
			if k == tk and CSBuild.h01(v, 55) < 0.65:
				var hb: Array = HERALDRY[int(CSBuild.h01(v, k, 57) * float(HERALDRY.size())) % HERALDRY.size()]
				for m: Array in _tower_spots(v, k, not odd):
					var q: Vector2 = m[0]
					var o := Vector3(q.x, CSBuild.level_y_static(k) + 3.45, q.y)
					var bas := wall_basis(m[1])
					var bn := _cand(BANNER, 3.0, CSBuild.h01(v * 16 + int(m[2]), k, 58), v, kk)
					bn.group = "banner %d" % v
					bn.boxes = [box(o, bas, Vector3(-0.41, -1.42, 0.0), Vector3(0.41, 0.05, 0.13))]
					bn.inst = [[M_BANNER, Transform3D(bas, o), int(hb[0]), int(hb[1])]]


static func _profile(s: float) -> float:
	## CFRoofs.cone's flared profile: height share at scale s from the tip (0) to the eave (1).
	var pr: Array = CFRoofs.FLARE.duplicate()
	pr.append(Vector2(0.035, 1.0))
	if s >= 1.0:
		return 0.0
	for i in range(pr.size() - 1):
		var a: Vector2 = pr[i]
		var c: Vector2 = pr[i + 1]
		if s <= a.x and s >= c.x:
			return lerpf(a.y, c.y, (a.x - s) / (a.x - c.x))
	return 1.0


static func roof_y(rec: Dictionary, poly: PackedVector2Array, q: Vector2) -> float:
	## The height of a cone / pyramid roof (CFRoofs.cone over the cap outline) above q.
	var c: Vector2 = rec.center
	var d := q - c
	var n := poly.size()
	var s := 1.0
	for j in n:
		var a := poly[j] - c
		var e := poly[(j + 1) % n] - c
		var den := a.cross(e)
		if absf(den) < 1e-9:
			continue
		var u := d.cross(e) / den
		var w := a.cross(d) / den
		if u >= -1e-6 and w >= -1e-6:
			s = u + w
			break
	return float(rec.y) + float(rec.h) * _profile(s)


func _cottages() -> void:
	## A chimney through most cottage roofs, near one of its corners (alternatives: one per corner).
	for kk: int in b.kinds:
		if b.kinds[kk] != "cottage" or not _caps.has(kk):
			continue
		var v := kk / 64
		var k := kk % 64
		if CSBuild.h01(v, k, 61) > 0.85:
			continue
		var rec: Dictionary = _caps[kk]
		var poly := _outline(v, k)
		var c: Vector2 = rec.center
		var n := poly.size()
		for j in n:
			var e := (poly[(j + 1) % n] - poly[j]).normalized()
			var out := Vector2(e.y, -e.x)
			var q := c + (poly[j] - c) * 0.52
			var bas := wall_basis(out)
			var lo := INF
			var hi := -INF
			for sx: float in [-0.3, 0.3]:
				for sz: float in [-0.3, 0.3]:
					var y := roof_y(rec, poly, q + Vector2(bas.x.x, bas.x.z) * sx + out * sz)
					lo = minf(lo, y)
					hi = maxf(hi, y)
			var top := hi + 0.7
			var ch := _cand(CHIMNEY, 1.5, CSBuild.h01(v * 16 + j, k, 62), v, kk)
			ch.group = "chimney %d" % kk
			ch.own_roof = kk
			ch.boxes = [box(Vector3(q.x, 0.0, q.y), bas, Vector3(-0.3, lo, -0.3), Vector3(0.3, top + 0.13, 0.3))]
			var foot := lo - 0.3
			ch.inst = [[M_CHIMNEY, Transform3D(Basis(bas.x, bas.y * (top - foot), bas.z), Vector3(q.x, foot, q.y)), town.colour(v, k), 0],
				[M_CHIMNEY_CAP, Transform3D(bas, Vector3(q.x, top, q.y)), town.colour(v, k), 0]]
			ch.perch = Vector3(q.x, top + 0.13, q.y)


func _houses() -> void:
	## A chimney on most small flat-topped houses: a clump of up to six wall-walk tops at one level, three storeys at
	## most, that is not a curtain (no block of it has the sea on one side and a courtyard on another), one chimney
	## per house, on one of its cells' middles.
	var by_level := {}
	for kk: int in b.kinds:
		if b.kinds[kk] == "walk" and kk % 64 <= 2:
			if not by_level.has(kk % 64):
				by_level[kk % 64] = {}
			(by_level[kk % 64] as Dictionary)[kk / 64] = true
	for k: int in by_level:
		var left: Dictionary = by_level[k]
		for v0: int in left.keys():
			if not left.has(v0):
				continue
			var area: Array[int] = []
			var st: Array[int] = [v0]
			left.erase(v0)
			for _i in 4096:
				if st.is_empty():
					break
				var v: int = st.pop_back()
				area.append(v)
				for u in grid.nbrs[v]:
					if left.has(u):
						left.erase(u)
						st.append(u)
			var curtain := area.size() > 6
			for v: int in area:
				var sea := false
				var court := false
				for u in grid.nbrs[v]:
					sea = sea or not b.land.has(u)
					court = court or b.land.get(u, "") == "court"
				curtain = curtain or (sea and court)
			if curtain:
				continue
			area.sort()
			if CSBuild.h01(area[0], k, 66) > 0.8:
				continue
			var y := CSBuild.level_y_static(k + 1)
			for v: int in area:
				var p := grid.verts[v]
				var kk := CSTown.key(v, k)
				var bas := wall_basis((grid.verts[grid.nbrs[v][0]] - p).normalized())
				var top := y + 1.85
				var ch := _cand(CHIMNEY, 1.5, CSBuild.h01(v, k, 67), v, kk)
				ch.group = "house %d" % CSTown.key(area[0], k)
				ch.own_roof = kk
				ch.boxes = [box(Vector3(p.x, 0.0, p.y), bas, Vector3(-0.3, y, -0.3), Vector3(0.3, top + 0.13, 0.3))]
				ch.inst = [[M_CHIMNEY, Transform3D(Basis(bas.x, bas.y * (top - y + 0.05), bas.z), Vector3(p.x, y - 0.05, p.y)), town.colour(v, k), 0],
					[M_CHIMNEY_CAP, Transform3D(bas, Vector3(p.x, top, p.y)), town.colour(v, k), 0]]
				ch.perch = Vector3(p.x, top + 0.13, p.y)


func _walks() -> void:
	## Wooden hoardings or machicolation corbels under the parapet on some open sides of wall walks.
	for kk: int in b.kinds:
		if b.kinds[kk] != "walk":
			continue
		var v := kk / 64
		var k := kk % 64
		var y := CSBuild.level_y_static(k + 1)
		var wall := town.colour(v, k)
		for sd: Array in _sides(v, k):
			var i: int = sd[0]
			var len: float = sd[3]
			if len < 2.2:
				continue
			var roll := CSBuild.h01(v * 16 + i, k, 63)
			var mid: Vector2 = sd[1]
			var bas := wall_basis(sd[2])
			var o := Vector3(mid.x, y, mid.y)
			if roll < 0.24:
				var w := minf(len - 0.8, 3.4)
				if w < 1.4:
					continue
				var s := w / 2.0
				var hc := _cand(HOARDING, 4.0, CSBuild.h01(v * 16 + i, k, 64), v, kk)
				hc.boxes = [box(o, bas, Vector3(-1.08 * s, -1.25, 0.0), Vector3(1.08 * s, 1.0, 0.96))]
				hc.inst = [[M_HOARDING, Transform3D(Basis(bas.x * s, bas.y, bas.z), o), wall, wall]]
			elif roll < 0.55:
				var w := minf(len - 0.6, 3.8)
				if w < 1.0:
					continue
				var cc := _cand(CORBELS, 4.0, CSBuild.h01(v * 16 + i, k, 64), v, kk)
				cc.boxes = [box(o, bas, Vector3(-w * 0.5, -0.6, 0.0), Vector3(w * 0.5, 0.0, 0.33))]
				cc.inst.append([M_SLAB, Transform3D(Basis(bas.x * w, bas.y, bas.z), o), wall, wall])
				var nc := maxi(2, int(w / 0.55) + 1)
				for j in nc:
					var x := -w * 0.5 + 0.12 + (w - 0.24) * float(j) / float(nc - 1)
					cc.inst.append([M_CORBEL, Transform3D(bas, o + bas.x * x), wall, wall])


func _on_court(u: int, pt: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(pt, grid.dual(u)):
		return true
	for x in grid.nbrs[u]:
		if b.land.get(x, "") == "court" and Geometry2D.is_point_in_polygon(pt, grid.dual(x)):
			return true
	return false


func _court_cand(kind: int, u: int, w: int, slot: int, group: String, items: Array) -> void:
	## items: [mesh, centre of its foot, basis, half size, height]; every foot must lie on the courtyard.
	var c := Cand.new()
	for it: Array in items:
		var bx := box(it[1], it[2], Vector3(-float(it[3]), 0.0, -float(it[3])), Vector3(float(it[3]), float(it[4]), float(it[3])))
		for q in corners(bx):
			if not _on_court(u, q):
				return
		c.boxes.append(bx)
		c.inst.append([it[0], Transform3D(it[2], it[1]), 0, 0])
	var cc := _cand(kind, 5.0, CSBuild.h01(slot, kind, 93), w, CSTown.key(w, 0))
	cc.group = group
	cc.boxes = c.boxes
	cc.inst = c.inst


func _courts() -> void:
	## Crates or barrels against the walls round a courtyard, two spots per side, most left empty.
	for u: int in b.land:
		if b.land[u] != "court":
			continue
		var nb: PackedInt32Array = grid.nbrs[u]
		for i in nb.size():
			var w := nb[i]
			if not grid.buildable(w) or not town.has(w, 0) or b.is_round(w, 0):
				continue
			var j := grid.index_of(w, u)
			if j < 0:
				continue
			var ol := _outline(w, 0)
			var n := ol.size()
			var f0 := ol[(j + n - 1) % n]
			var f1 := ol[j]
			var len := f0.distance_to(f1)
			if len < 1.8:
				continue
			var along := (f1 - f0) / len
			var out := Vector2(along.y, -along.x)
			for si in 2:
				var slot := u * 32 + i * 2 + si
				if CSBuild.h01(slot, 0, 91) > 0.55:
					continue
				var q := (f0 + f1) * 0.5 + along * (0.27 if si == 1 else -0.27) * len
				var g := "court %d" % slot
				var h := CSBuild.h01(slot, 0, 92)
				var yaw := (CSBuild.h01(slot, 0, 94) - 0.5) * 0.4
				var bas := wall_basis(out.rotated(yaw))
				var side := Vector3(bas.x.x, 0.0, bas.x.z)
				# 0.45 from the wall: a crate turned by up to 0.4 rad still keeps its corners off it
				var foot := Vector3(q.x, CSBuild.B, q.y) + Vector3(out.x, 0.0, out.y) * 0.45
				var crates := [[M_CRATE, foot, bas, 0.34, 0.66]]
				if h < 0.4:
					var b2 := wall_basis(out.rotated(yaw + (CSBuild.h01(slot, 0, 95) - 0.5) * 0.4))
					crates.append([M_CRATE, foot + Vector3(0.0, 0.66, 0.0), b2, 0.34, 0.66])
				elif h < 0.7:
					crates.append([M_CRATE, foot + side * 0.74, bas, 0.34, 0.66])
				_court_cand(CRATES, u, w, slot, g, crates)
				var barrels := [[M_BARREL, foot, bas, 0.35, 0.86]]
				if h > 0.5:
					barrels.append([M_BARREL, foot - side * 0.74, bas, 0.35, 0.86])
				_court_cand(BARRELS, u, w, slot, g, barrels)


func _ornaments() -> void:
	## A moulded string course below the parapet line of a level and patches of ivy climbing the lower walls: both on open
	## flat sides, dropped by the solver wherever a window, a hoarding, a lantern or anything dearer is in the way.
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		for k in range(0, town.top(v) + 1):
			if not town.has(v, k) or b.is_round(v, k):
				continue
			var wall := town.colour(v, k)
			var sty := town.style(v, k)
			var y0 := CSBuild.level_y_static(k)
			var y1 := CSBuild.level_y_static(k + 1)
			for sd: Array in _sides(v, k):
				var i: int = sd[0]
				var len: float = sd[3]
				if len < 1.8:
					continue
				var mid: Vector2 = sd[1]
				var bas := wall_basis(sd[2])
				var slot := v * 16 + i
				if sty == CSStyle.CASTLE and CSBuild.h01(slot, k, 91) < 0.7:
					var w := len - 0.35
					var o := Vector3(mid.x, y1 - 0.62, mid.y)
					var sc := _cand(STRING, 6.0, CSBuild.h01(slot, k, 92), v, CSTown.key(v, k))
					sc.boxes = [box(o, bas, Vector3(-w * 0.5, 0.0, 0.0), Vector3(w * 0.5, 0.12, 0.1))]
					sc.inst = [[M_STRING, Transform3D(Basis(bas.x * w, bas.y, bas.z), o), wall, wall]]
				if sty != CSStyle.APARTMENT and CSBuild.h01(slot, k, 93) < (0.34 if k <= 1 else 0.12):
					var iw := minf(len - 0.7, 1.6 + 1.4 * CSBuild.h01(slot, k, 94))
					if iw < 1.0:
						continue
					var ih := 2.0 + 1.6 * CSBuild.h01(slot, k, 95)
					var dx := (len - 0.7 - iw) * (CSBuild.h01(slot, k, 96) - 0.5)
					var o2 := Vector3(mid.x, y0 + 0.2, mid.y) + bas.x * dx
					var iv := _cand(IVY, 8.0, CSBuild.h01(slot, k, 97), v, CSTown.key(v, k))
					iv.boxes = [box(o2, bas, Vector3(-iw * 0.5, 0.0, 0.0), Vector3(iw * 0.5, ih, 0.14))]
					iv.inst = [[M_IVY, Transform3D(Basis(bas.x * iw, bas.y * ih, bas.z), o2), wall, wall]]


func _bunting() -> void:
	## A string of little flags between two blocks facing each other across a gap at the same level, the flags in
	## the two blocks' colours by turns. From some open sides a ray looks for the first block straight ahead.
	var done := {}
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		for k in range(0, b.top_of(v) + 1):
			if not town.has(v, k):
				continue
			for sd: Array in _sides(v, k):
				var i: int = sd[0]
				if CSBuild.h01(v * 16 + i, k, 71) > 0.6:
					continue
				var mid: Vector2 = sd[1]
				var out: Vector2 = sd[2]
				var w := -1
				for st in 20:
					var x := grid.nearest(mid + out * (2.4 + 0.6 * float(st)))
					if x < 0 or (not b.land.has(x) and b.top_of(x) < 0):
						break                   # off the map, or out over the sea
					if x != v and town.has(x, k):
						w = x
						break
				if w < 0:
					continue
				var pair := Vector2i(mini(CSTown.key(v, k), CSTown.key(w, k)), maxi(CSTown.key(v, k), CSTown.key(w, k)))
				if done.has(pair):
					continue
				var best: Array = []
				var bd := 0.8
				for s2: Array in _sides(w, k):
					var dd := -(s2[2] as Vector2).dot(out)
					if dd > bd:
						bd = dd
						best = s2
				if best.is_empty():
					continue
				var m2: Vector2 = best[1]
				var span := m2 - mid
				var L := span.length()
				if L < 3.4 or L > 18.0 or absf(out.cross(span)) > 1.6 or out.dot(span) <= 0.0 or (best[2] as Vector2).dot(-span) <= 0.0:
					continue
				done[pair] = true
				_string(v, k, i, w, mid, m2, out, best[2])


func _string(v: int, k: int, i: int, w: int, a2: Vector2, b2: Vector2, oa: Vector2, ob: Vector2) -> void:
	var y := CSBuild.level_y_static(k) + 3.2
	var pa := Vector3(a2.x, y, a2.y)
	var pb := Vector3(b2.x, y, b2.y)
	var L := a2.distance_to(b2)
	var sag := 0.035 * L + 0.12
	var dir := (b2 - a2) / L
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var ca := town.colour(v, k)
	var cb := town.colour(w, k)
	if town.style(v, k) != CSStyle.CASTLE or town.style(w, k) != CSStyle.CASTLE:
		# the flags are festive whatever the houses: castle palette colours
		ca = _pick([0, 4, 7, 2, 8, 5], CSBuild.h01(v, w, 74), -1)
		cb = ca
	if cb == ca:
		cb = _pick([0, 4, 7, 2, 8, 5], CSBuild.h01(v, w, 72), ca)
	var c := _cand(BUNTING, 2.5, CSBuild.h01(v * 16 + i, k, 73), v, CSTown.key(v, k))
	c.key2 = CSTown.key(w, k)
	var lb := wall_basis(Vector2(-dir.y, dir.x))        # x along the string, z across it
	var drop := func(s: float) -> float: return 4.0 * sag * s * (1.0 - s)
	# the boxes: the string's sag in pieces, from just off one wall to just off the other
	var s_a := 0.08 / L
	var s_b := 1.0 - 0.08 / L
	var nseg := maxi(3, ceili(L / 1.2))
	for j in nseg:
		var s0 := lerpf(s_a, s_b, float(j) / float(nseg))
		var s1 := lerpf(s_a, s_b, float(j + 1) / float(nseg))
		var d0: float = drop.call(s0)
		var d1: float = drop.call(s1)
		var dmax := maxf(d0, d1)
		if s0 < 0.5 and s1 > 0.5:
			dmax = drop.call(0.5)
		c.boxes.append(box(pa, lb, Vector3(s0 * L, -dmax - 0.45, -0.2), Vector3(s1 * L, -minf(d0, d1) + 0.03, 0.2)))
	# the meshes: a hook on each wall, the flags, the rope through them
	c.inst.append([M_HOOK, Transform3D(wall_basis(oa), pa), 0, 0])
	c.inst.append([M_HOOK, Transform3D(wall_basis(ob), pb), 0, 0])
	var nf := maxi(2, int((L - 1.2) / 0.5) + 1)
	var pts := [pa - d3 * 0.06]
	for j in nf:
		var s := (0.6 + (L - 1.2) * float(j) / float(nf - 1)) / L
		var dp: float = drop.call(s)
		var p := pa.lerp(pb, s) - Vector3(0.0, dp, 0.0)
		pts.append(p)
		c.inst.append([M_FLAG, Transform3D(lb, p), ca if j % 2 == 0 else cb, 0])
	pts.append(pb + d3 * 0.06)
	for j in range(pts.size() - 1):
		var p0: Vector3 = pts[j]
		var p1: Vector3 = pts[j + 1]
		var seg := p1 - p0
		var xu := seg.normalized()
		var z0 := xu.cross(Vector3.UP).normalized()
		c.inst.append([M_ROPE, Transform3D(Basis(seg, z0.cross(xu), z0), p0), 0, 0])


# --- the independent set ---------------------------------------------------------------------------

func _insert(bx: Box) -> void:
	for hk: Vector2i in _cells(Vector2(bx.c.x, bx.c.z), bx.r):
		if not _hash.has(hk):
			_hash[hk] = []
		(_hash[hk] as Array).append(bx)


func _hits_kept(bx: Box) -> bool:
	for hk: Vector2i in _cells(Vector2(bx.c.x, bx.c.z), bx.r):
		for o: Box in _hash.get(hk, []):
			if overlap(bx, o):
				return true
	return false


func _hits_solid(bx: Box, c: Cand) -> bool:
	## Whether a box reaches into a block or an arch (with the parapet, roof and pole above a top), into the land, or into
	## a corbel, a pillar or a flight of stairs.
	var y0 := bx.c.y - bx.he.y
	var y1 := bx.c.y + bx.he.y
	var c2 := Vector2(bx.c.x, bx.c.z)
	var seen_x := {}
	for hk: Vector2i in _cells(c2, bx.r):
		for xi: int in _extra.get(hk, []):
			if seen_x.has(xi):
				continue
			seen_x[xi] = true
			var ex: Dictionary = b.extras[xi]
			if y1 > float(ex.y0) + EPS and y0 < float(ex.y1) - EPS and rect_poly(bx, ex.poly):
				return true
	var seen := {}
	for hk: Vector2i in _cells(c2, bx.r):
		for u: int in _solid.get(hk, []):
			if seen.has(u):
				continue
			seen[u] = true
			if grid.verts[u].distance_to(c2) > float(_rad[u]) + bx.r:
				continue
			if b.land.has(u) and y0 < CSBuild.B - EPS and y1 > CSBuild.FOOT:
				for poly: PackedVector2Array in _land_pieces(u):
					if rect_poly(bx, poly):
						return true
			for k in range(0, b.top_of(u) + 1):
				if not b.filled(u, k):
					continue
				var kk := CSTown.key(u, k)
				var top := CSBuild.level_y_static(k + 1)
				if kk != c.own_roof:
					top += float(_ext.get(kk, 0.0))
				if y1 <= CSBuild.level_y_static(k) + EPS or y0 >= top - EPS:
					continue
				for poly: PackedVector2Array in _block_pieces(u, k):
					if rect_poly(bx, poly):
						return true
	return false


func _solve() -> void:
	var order := cands.duplicate()
	order.sort_custom(func(x: Cand, y: Cand) -> bool:
		if x.cost != y.cost:
			return x.cost < y.cost
		if x.tie != y.tie:
			return x.tie < y.tie
		return x.id < y.id)
	var groups := {}
	for c: Cand in order:
		if c.group != "" and groups.has(c.group):
			continue
		if c.needs != null and not c.needs.ok:
			continue
		var free := true
		for bx: Box in c.boxes:
			if _hits_kept(bx) or _hits_solid(bx, c):
				free = false
				break
		if not free:
			continue
		c.ok = true
		kept.append(c)
		for bx: Box in c.boxes:
			_insert(bx)
		if c.group != "":
			groups[c.group] = true
		counts[KINDS[c.kind]] = int(counts[KINDS[c.kind]]) + 1


# --- output ----------------------------------------------------------------------------------------

func buffers(only: Dictionary = {}) -> Array:
	## Per mesh (M_*), the MultiMesh buffer of the kept props: 12 floats of transform (rows of the 3x4 matrix) and 4 of
	## custom data (palette a, palette b as CSBuild.colour_seed, owner, 0). With `only`, just the props hanging on those
	## block keys (the ones that leave with a block taken away).
	var lists := []
	for _m in MESH_COUNT:
		lists.append([])
	for c: Cand in kept:
		if not only.is_empty() and not only.has(c.key) and not only.has(c.key2):
			continue
		for it: Array in c.inst:
			(lists[int(it[0])] as Array).append([it[1], int(it[2]), int(it[3]), c.owner])
	var out := []
	for m in MESH_COUNT:
		var list: Array = lists[m]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var j := 0
		for it: Array in list:
			var xf: Transform3D = it[0]
			buf[j] = xf.basis.x.x
			buf[j + 1] = xf.basis.y.x
			buf[j + 2] = xf.basis.z.x
			buf[j + 3] = xf.origin.x
			buf[j + 4] = xf.basis.x.y
			buf[j + 5] = xf.basis.y.y
			buf[j + 6] = xf.basis.z.y
			buf[j + 7] = xf.origin.y
			buf[j + 8] = xf.basis.x.z
			buf[j + 9] = xf.basis.y.z
			buf[j + 10] = xf.basis.z.z
			buf[j + 11] = xf.origin.z
			buf[j + 12] = CSBuild.colour_seed(int(it[1]))
			buf[j + 13] = CSBuild.colour_seed(int(it[2]))
			buf[j + 14] = float(it[3])
			buf[j + 15] = 0.0
			j += 16
		out.append(buf)
	return out


func multimeshes(meshes: Array, only: Dictionary = {}) -> Array:
	## One MultiMesh per prop mesh (null where none is kept); made on the build thread.
	var out := []
	var bufs := buffers(only)
	for m in MESH_COUNT:
		var buf: PackedFloat32Array = bufs[m]
		if buf.is_empty():
			out.append(null)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[m]
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		out.append(mm)
	return out


func instance_count() -> int:
	var n := 0
	for c: Cand in kept:
		n += (c.inst as Array).size()
	return n


func perches() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c: Cand in kept:
		if c.perch != Vector3.INF:
			out.append(c.perch)
	return out


static func add_perches(landings: Dictionary, extra: PackedVector3Array) -> void:
	## Birds may sit on the chimney tops too (CFBirds' landings, made on the build thread).
	if landings.is_empty() or extra.is_empty():
		return
	var pos: PackedVector3Array = landings.get("pos", PackedVector3Array())
	var flat: PackedByteArray = landings.get("flat", PackedByteArray())
	for p in extra:
		pos.append(p)
		flat.append(1)
	landings["pos"] = pos
	landings["flat"] = flat


# --- the meshes (made once, in code) ---------------------------------------------------------------

class MB:
	## A small mesh collector: faces with flat normals turned to face out, COLOR.r = paint zone, UV in metres.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var zone := 0

	func _uv(p: Vector3, n: Vector3) -> Vector2:
		if absf(n.y) > 0.5:
			return Vector2(p.x, p.z)
		return Vector2(p.dot(Vector3(-n.z, 0.0, n.x)), p.y)

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
		# Godot's front faces are clockwise seen from the front
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		var col := Color(float(zone) / 255.0, 0.0, 0.0, 1.0)
		for p: Vector3 in [a, b, c]:
			verts.append(p)
			norms.append(n)
			cols.append(col)
			uvs.append(_uv(p, n))

	func poly(pts: Array, centre: Vector3) -> void:
		## A flat convex face, turned away from centre.
		var n := Vector3.ZERO
		for i in range(1, pts.size() - 1):
			n += ((pts[i] as Vector3) - (pts[0] as Vector3)).cross((pts[i + 1] as Vector3) - (pts[0] as Vector3))
		n = n.normalized()
		var m := Vector3.ZERO
		for p: Vector3 in pts:
			m += p
		m /= float(pts.size())
		if n.dot(m - centre) < 0.0:
			n = -n
		for i in range(1, pts.size() - 1):
			tri(pts[0], pts[i], pts[i + 1], n)

	func hexa(p: Array, z: int) -> void:
		## Six faces of a box-like solid; p as box() orders them (bottom -z, +x, top, then the same at +z).
		zone = z
		var m := Vector3.ZERO
		for q: Vector3 in p:
			m += q
		m /= 8.0
		for f: Array in [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [3, 7, 6, 2], [0, 1, 5, 4]]:
			poly([p[f[0]], p[f[1]], p[f[2]], p[f[3]]], m)

	func box(lo: Vector3, hi: Vector3, z: int) -> void:
		hexa([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], z)

	func beam(a: Vector3, b: Vector3, w: float, z: int) -> void:
		## A square beam w thick from a to b.
		var d := (b - a).normalized()
		var s := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized() * w * 0.5
		var t := s.cross(d).normalized() * w * 0.5
		hexa([a - s - t, a + s - t, a + s + t, a - s + t, b - s - t, b + s - t, b + s + t, b - s + t], z)

	func prism(pts: PackedVector2Array, z0: float, z1: float, front: int, back: int, side: int) -> void:
		## A flat convex outline in the x-y plane, made solid from z0 to z1.
		var c := Vector3.ZERO
		for q in pts:
			c += Vector3(q.x, q.y, (z0 + z1) * 0.5)
		c /= float(pts.size())
		var f := []
		var bk := []
		for q in pts:
			f.append(Vector3(q.x, q.y, z1))
			bk.append(Vector3(q.x, q.y, z0))
		zone = front
		poly(f, c)
		zone = back
		poly(bk, c)
		zone = side
		var n := pts.size()
		for i in n:
			var j := (i + 1) % n
			poly([bk[i], bk[j], f[j], f[i]], c)

	func extrude_x(prof: Array, x0: float, x1: float, z: int) -> void:
		## A convex outline in the z-y plane (Vector2(z, y)), made solid from x0 to x1.
		zone = z
		var c := Vector3.ZERO
		for q: Vector2 in prof:
			c += Vector3((x0 + x1) * 0.5, q.y, q.x)
		c /= float(prof.size())
		var l := []
		var r := []
		for q: Vector2 in prof:
			l.append(Vector3(x0, q.y, q.x))
			r.append(Vector3(x1, q.y, q.x))
		poly(l, c)
		poly(r, c)
		var n := prof.size()
		for i in n:
			var j := (i + 1) % n
			poly([l[i], l[j], r[j], r[i]], c)

	func lathe(prof: Array, sides: int, z: int, org: Vector3 = Vector3.ZERO) -> void:
		## A surface of revolution round the y axis (through org), prof = [Vector2(radius, y)] going up, smooth normals.
		zone = z
		var col := Color(float(zone) / 255.0, 0.0, 0.0, 1.0)
		for k in range(prof.size() - 1):
			var p0: Vector2 = prof[k]
			var p1: Vector2 = prof[k + 1]
			var pn := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			for i in sides:
				var a0 := TAU * float(i) / float(sides)
				var a1 := TAU * float(i + 1) / float(sides)
				var q := [org + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x), org + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x),
					org + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x), org + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)]
				var nn := [Vector3(cos(a0) * pn.x, pn.y, sin(a0) * pn.x), Vector3(cos(a1) * pn.x, pn.y, sin(a1) * pn.x)]
				var uv := [Vector2(a0 * p0.x, p0.y), Vector2(a1 * p0.x, p0.y), Vector2(a1 * p1.x, p1.y), Vector2(a0 * p1.x, p1.y)]
				var fn := ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[2] as Vector3) - (q[0] as Vector3))
				var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
				var order := [0, 1, 2, 0, 2, 3] if fn.dot(out) < 0.0 else [0, 2, 1, 0, 3, 2]
				for o: int in order:
					verts.append(q[o])
					norms.append(nn[0] if o == 0 or o == 3 else nn[1])
					cols.append(col)
					uvs.append(uv[o])

	func disc(y: float, r: float, sides: int, up: bool, z: int) -> void:
		zone = z
		var n := Vector3.UP if up else Vector3.DOWN
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			tri(Vector3(0.0, y, 0.0), Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), n)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_TEX_UV] = uvs
		var m := ArrayMesh.new()
		if not verts.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func make_meshes() -> Array:
	## Every prop mesh, indexed by M_*. Wall props: x along the wall, y up, z out of it.
	var out := []
	for m in MESH_COUNT:
		var mb := MB.new()
		match m:
			M_FRAME:
				# jambs, lintel with a keystone, a deeper sill: round a 0.68 x 1.25 window whose sill is at y = 0
				mb.box(Vector3(-0.45, -0.04, -EMBED), Vector3(-0.34, 1.25, 0.06), P_LIGHT)
				mb.box(Vector3(0.34, -0.04, -EMBED), Vector3(0.45, 1.25, 0.06), P_LIGHT)
				mb.box(Vector3(-0.49, 1.25, -EMBED), Vector3(0.49, 1.38, 0.09), P_LIGHT)
				mb.box(Vector3(-0.07, 1.24, -EMBED), Vector3(0.07, 1.44, 0.11), P_LIGHT)
				mb.box(Vector3(-0.51, -0.13, -EMBED), Vector3(0.51, 0.0, 0.15), P_LIGHT)
				# a leaded pane set back in the opening, a mullion and a transom, a drip under the sill
				mb.box(Vector3(-0.34, 0.0, -0.1), Vector3(0.34, 1.25, -0.08), P_DARK)
				mb.box(Vector3(-0.025, 0.0, -0.1), Vector3(0.025, 1.25, 0.02), P_LIGHT)
				mb.box(Vector3(-0.34, 0.62, -0.1), Vector3(0.34, 0.67, 0.02), P_LIGHT)
				mb.box(Vector3(-0.48, -0.17, -EMBED), Vector3(0.48, -0.13, 0.1), P_LIGHT)
			M_STRING:
				mb.extrude_x([Vector2(-EMBED, 0.0), Vector2(0.1, 0.0), Vector2(0.1, 0.05), Vector2(0.06, 0.09), Vector2(0.03, 0.12), Vector2(-EMBED, 0.12)], -0.5, 0.5, P_LIGHT)
			M_IVY:
				var rng := RandomNumberGenerator.new()
				rng.seed = 7731
				# vines up the wall, then leaves, thicker low down, each a two-sided diamond turned a random way
				for vn in 7:
					var x0 := rng.randf_range(-0.42, 0.42)
					var xs := x0
					var yy := 0.0
					while yy < rng.randf_range(0.55, 1.0):
						var xn := clampf(xs + rng.randf_range(-0.07, 0.07), -0.5, 0.5)
						mb.beam(Vector3(xs, yy, 0.02), Vector3(xn, yy + 0.1, 0.02), 0.012, P_DARKWOOD)
						xs = xn
						yy += 0.1
				for j in 150:
					var yv := pow(rng.randf(), 1.6)
					var xv := rng.randf_range(-0.5, 0.5) * (1.0 - 0.3 * yv)
					var c := Vector3(xv, yv, 0.03 + 0.05 * rng.randf())
					var ang := rng.randf() * TAU
					var sz := rng.randf_range(0.03, 0.055)
					var a := Vector3(cos(ang), sin(ang), 0.0)
					var bb := Vector3(-a.y, a.x, 0.35 * (rng.randf() - 0.5))
					var leaf := [c + a * sz * 1.5, c + bb * sz, c - a * sz, c - bb * sz]
					mb.zone = P_LEAF
					mb.poly(leaf, c + Vector3(0.0, 0.0, -1.0))
					mb.poly(leaf, c + Vector3(0.0, 0.0, 1.0))
			M_SHUTTER:
				mb.box(Vector3(-0.17, 0.0, -0.01), Vector3(0.17, 1.25, 0.04), P_SECOND_PLANKS)
				mb.box(Vector3(-0.15, 0.2, 0.04), Vector3(0.15, 0.27, 0.05), P_SECOND_PLANKS)
				mb.box(Vector3(-0.15, 0.98, 0.04), Vector3(0.15, 1.05, 0.05), P_SECOND_PLANKS)
			M_FLOWERBOX:
				mb.box(Vector3(-0.42, -0.52, -0.05), Vector3(0.42, -0.28, 0.3), P_WOOD)
				mb.box(Vector3(-0.39, -0.28, -0.02), Vector3(0.39, -0.265, 0.27), P_EARTH)
				for j in 7:
					var x := -0.33 + float(j) * 0.11
					mb.box(Vector3(x - 0.06, -0.27, 0.02 + 0.03 * float(j % 3)), Vector3(x + 0.06, -0.17 - 0.03 * float(j % 2), 0.25), P_LEAF)
				for j in 6:
					var x := -0.28 + float(j) * 0.112
					var zz := 0.06 + 0.07 * float(j % 2)
					mb.box(Vector3(x - 0.045, -0.21 + 0.02 * float(j % 2), zz), Vector3(x + 0.045, -0.14, zz + 0.09), P_BLOOM)
				for sx: float in [-1.0, 1.0]:
					mb.box(Vector3(0.29 * sx - 0.025, -0.62, -EMBED), Vector3(0.29 * sx + 0.025, -0.52, 0.22), P_DARKWOOD)
			M_SHIELD:
				# a heater shield parted down the middle in two colours, a boss, a peg into the wall
				mb.prism(PackedVector2Array([Vector2(-0.28, 0.36), Vector2(0.0, 0.36), Vector2(0.0, -0.4), Vector2(-0.2, -0.2),
					Vector2(-0.28, 0.05)]), 0.02, 0.08, P_OWN, P_DARKWOOD, P_DARKWOOD)
				mb.prism(PackedVector2Array([Vector2(0.0, 0.36), Vector2(0.28, 0.36), Vector2(0.28, 0.05), Vector2(0.2, -0.2),
					Vector2(0.0, -0.4)]), 0.02, 0.08, P_SECOND, P_DARKWOOD, P_DARKWOOD)
				mb.box(Vector3(-0.055, 0.0, 0.08), Vector3(0.055, 0.11, 0.12), P_IRON)
				mb.box(Vector3(-0.05, 0.2, -EMBED), Vector3(0.05, 0.3, 0.02), P_DARKWOOD)
			M_BANNER:
				# a cloth parted in two colours with a swallow tail, from a rod on two brackets
				mb.box(Vector3(-0.37, -0.025, 0.07), Vector3(0.37, 0.025, 0.12), P_DARKWOOD)
				for sx: float in [-1.0, 1.0]:
					mb.box(Vector3(0.3 * sx - 0.02, -0.02, -EMBED), Vector3(0.3 * sx + 0.02, 0.02, 0.07), P_IRON)
					mb.box(Vector3(0.37 * sx - (0.0 if sx > 0.0 else 0.04), -0.04, 0.075), Vector3(0.37 * sx + (0.04 if sx > 0.0 else 0.0), 0.04, 0.115), P_IRON)
				mb.prism(PackedVector2Array([Vector2(-0.3, -0.03), Vector2(0.0, -0.03), Vector2(0.0, -1.12), Vector2(-0.3, -1.4)]), 0.078, 0.102, P_OWN, P_OWN, P_OWN)
				mb.prism(PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.3, -0.03), Vector2(0.3, -1.4), Vector2(0.0, -1.12)]), 0.078, 0.102, P_SECOND, P_SECOND, P_SECOND)
			M_TORCH:
				# a lantern hanging from an iron bracket
				mb.box(Vector3(-0.06, -0.09, -0.02), Vector3(0.06, 0.09, 0.012), P_IRON)
				mb.box(Vector3(-0.025, -0.025, -EMBED), Vector3(0.025, 0.025, 0.3), P_IRON)
				mb.box(Vector3(-0.012, -0.08, 0.27), Vector3(0.012, 0.0, 0.294), P_IRON)
				mb.box(Vector3(-0.11, -0.12, 0.17), Vector3(0.11, -0.08, 0.39), P_IRON)
				mb.box(Vector3(-0.05, -0.08, 0.23), Vector3(0.05, -0.04, 0.33), P_IRON)
				mb.box(Vector3(-0.07, -0.32, 0.21), Vector3(0.07, -0.12, 0.35), P_GLOW)
				for sx: float in [-1.0, 1.0]:
					for zc: float in [0.2, 0.36]:
						mb.box(Vector3(0.08 * sx - 0.012, -0.33, zc - 0.012), Vector3(0.08 * sx + 0.012, -0.12, zc + 0.012), P_IRON)
				mb.box(Vector3(-0.1, -0.35, 0.18), Vector3(0.1, -0.32, 0.38), P_IRON)
			M_CHIMNEY:
				mb.box(Vector3(-0.24, 0.0, -0.24), Vector3(0.24, 1.0, 0.24), P_OWN)
			M_CHIMNEY_CAP:
				mb.box(Vector3(-0.29, 0.0, -0.29), Vector3(0.29, 0.12, 0.29), P_LIGHT)
				mb.box(Vector3(-0.17, 0.12, -0.17), Vector3(0.17, 0.126, 0.17), P_DARK)
			M_HOARDING:
				# a timber gallery 2 m wide (scaled along x) hung under the parapet: floor, planked walls with
				# loopholes, a lean-to roof against the battlements, two struts down to the wall
				mb.box(Vector3(-1.0, -1.0, -EMBED), Vector3(1.0, -0.9, 0.8), P_DARKWOOD)
				mb.box(Vector3(-1.0, -0.9, 0.72), Vector3(1.0, 0.56, 0.8), P_WOOD)
				for sx: float in [-1.0, 1.0]:
					mb.box(Vector3(minf(0.94 * sx, sx), -0.9, -EMBED), Vector3(maxf(0.94 * sx, sx), 0.56, 0.72), P_WOOD)
					mb.beam(Vector3(0.75 * sx, -1.2, -0.05), Vector3(0.75 * sx, -0.93, 0.7), 0.08, P_DARKWOOD)
				for x: float in [-0.5, 0.0, 0.5]:
					mb.box(Vector3(x - 0.05, -0.45, 0.8), Vector3(x + 0.05, 0.05, 0.81), P_DARK)
				mb.hexa([Vector3(-1.08, 0.93, 0.0), Vector3(1.08, 0.93, 0.0), Vector3(1.08, 1.0, 0.0), Vector3(-1.08, 1.0, 0.0),
					Vector3(-1.08, 0.47, 0.96), Vector3(1.08, 0.47, 0.96), Vector3(1.08, 0.54, 0.96), Vector3(-1.08, 0.54, 0.96)], P_DARKWOOD)
			M_CORBEL:
				mb.extrude_x([Vector2(-EMBED, -0.6), Vector2(0.07, -0.6), Vector2(0.3, -0.14), Vector2(-EMBED, -0.14)], -0.09, 0.09, P_OWN)
			M_SLAB:
				mb.box(Vector3(-0.5, -0.14, -EMBED), Vector3(0.5, 0.0, 0.33), P_LIGHT)
			M_CRATE:
				mb.box(Vector3(-0.31, 0.02, -0.31), Vector3(0.31, 0.64, 0.31), P_WOOD)
				var e := 0.33
				var t := 0.05
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						var x := (e - t * 0.5) * sx
						var z := (e - t * 0.5) * sz
						mb.box(Vector3(x - t * 0.5, 0.0, z - t * 0.5), Vector3(x + t * 0.5, 0.66, z + t * 0.5), P_DARKWOOD)
				for y: float in [t * 0.5, 0.66 - t * 0.5]:
					for s: float in [-1.0, 1.0]:
						var off := (e - t * 0.5) * s
						mb.box(Vector3(-e, y - t * 0.5, off - t * 0.5), Vector3(e, y + t * 0.5, off + t * 0.5), P_DARKWOOD)
						mb.box(Vector3(off - t * 0.5, y - t * 0.5, -e), Vector3(off + t * 0.5, y + t * 0.5, e), P_DARKWOOD)
			M_BARREL:
				mb.lathe([Vector2(0.27, 0.0), Vector2(0.31, 0.14), Vector2(0.33, 0.42), Vector2(0.31, 0.7), Vector2(0.27, 0.84)], 14, P_WOOD)
				mb.lathe([Vector2(0.318, 0.09), Vector2(0.327, 0.17)], 14, P_IRON)
				mb.lathe([Vector2(0.327, 0.67), Vector2(0.318, 0.75)], 14, P_IRON)
				mb.disc(0.84, 0.27, 14, true, P_DARKWOOD)
				mb.disc(0.0, 0.27, 14, false, P_DARKWOOD)
			M_ROPE:
				mb.box(Vector3(0.0, -0.017, -0.017), Vector3(1.0, 0.017, 0.017), P_ROPE)
			M_FLAG:
				mb.prism(PackedVector2Array([Vector2(-0.2, 0.0), Vector2(0.2, 0.0), Vector2(0.0, -0.42)]), -0.005, 0.005, P_CLOTH, P_CLOTH, P_CLOTH)
			M_HOOK:
				mb.box(Vector3(-0.03, -0.03, -EMBED), Vector3(0.03, 0.04, 0.07), P_IRON)
			_:
				CSStyleProps.make_mesh(m, mb)
		out.append(mb.commit())
	return out
