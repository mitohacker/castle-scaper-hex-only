class_name CSRoads
extends RefCounted
## Roads, bridges and jetties. A road column joins the road columns round it (and castle blocks, which it meets at their door with a paved apron),
## so one click makes a different piece depending on how many neighbours it has and what they are:
##   no road neighbour  -> a plaza with a ring of standing stones (a jetty platform if it stands over water)
##   one                -> a dead end: a round turning place, a milestone and a lamp (a jetty with a lamp at its end over water)
##   two                -> a bend or a straight, one smooth curve through the column (a bridge over water: a stone hump-back where it meets land,
##                         a timber trestle on piles where it only meets more bridge)
##   three or more      -> a junction: a hub, a signpost, and with four or more a well
## What the road is made of comes from the context: cobbles beside the castle, in a courtyard and at a junction; gravel climbing a mountain or beside
## rock (where the rock is held back with cut blocks); packed dirt through trees and plain meadow. Where it climbs, the shader cuts it into steps.
## The ribbon is laid on the terrain triangle by triangle (CSWorld.height_at), so it follows every swell.

enum { M_SIGN, M_WELL, M_LAMP, M_STONE, M_PILE, M_RAIL }
const MESH_COUNT := 6
const W := 1.7                  # road width (m)
const HUB := 0.9                # junction hub radius
const HOVER := 0.05
const SAMPLES := 9
const SURF_COBBLE := 0
const SURF_GRAVEL := 1
const SURF_DIRT := 2
const SURF_PLANK := 3
const SURF_STONE := 4

var world: CSWorld
var grid: CSGrid
var town: CSTown
var info := {}                  # column -> {"class", "conns", "surface"}
var inst: Array = []            # [mesh, Transform3D, Color custom] (signs, wells, lamps, stones, piles)
var counts := {}
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uvt := Vector2(1, 0)       # the path direction of the span being laid (deck uv: across, along)
var _collect := false
var _deck_faces := PackedVector3Array()


func build(w: CSWorld) -> void:
	world = w
	grid = w.grid
	town = w.town
	var cols := []
	for v: int in town.wild_columns():
		if town.wild_road(v) and (w.ground.has(v) or w.garden.has(v) or w.deck.has(v)):
			cols.append(v)
	cols.sort()
	for v: int in cols:
		info[v] = _classify(v)
	for v: int in cols:
		_build_column(v)
	_count_all()


func _count(k: String) -> void:
	counts[k] = int(counts.get(k, 0)) + 1


func _count_all() -> void:
	for v: int in info:
		_count(str((info[v] as Dictionary).cls))


func _mid(v: int, i: int) -> Vector2:
	var f := grid.face(v, i)
	return (f[0] + f[1]) * 0.5


func is_road(u: int) -> bool:
	return town.wild_road(u) and (world.ground.has(u) or world.garden.has(u) or world.deck.has(u))


func _classify(v: int) -> Dictionary:
	var conns := []
	var castle_conns := []
	var nb: PackedInt32Array = grid.nbrs[v]
	for i in nb.size():
		var u := nb[i]
		if not grid.buildable(u):
			continue
		if is_road(u):
			conns.append(i)
		elif town.has(u, 0):
			castle_conns.append(i)        # a castle block: the road runs up to its door
	var all := conns + castle_conns
	var cx := world.ctx(v)
	var over_water := world.deck.has(v)
	var cls := "plaza"
	match all.size():
		0:
			cls = "plaza"
		1:
			cls = "dead"
		2:
			cls = "through"
		_:
			cls = "junction"
	var surface := SURF_DIRT
	if over_water:
		var land_end := false
		for i: int in all:
			var u := nb[i]
			if world.ground.has(u) or world.garden.has(u) or town.has(u, 0) or world.castle_land.has(u):
				land_end = true
		if all.size() >= 2:
			cls = "bridge"
			surface = SURF_STONE if land_end else SURF_PLANK
		else:
			cls = "jetty"
			surface = SURF_PLANK
	else:
		var alt := world.altitude(v)
		if int(cx.castle) >= 1 or world.garden.has(v) or all.size() >= 3 or castle_conns.size() > 0:
			surface = SURF_COBBLE
		elif alt > 2.0 or int(cx.rock) >= 1 or int(cx.mount) >= 1:
			surface = SURF_GRAVEL
		else:
			surface = SURF_DIRT
	return {"cls": cls, "conns": all, "roads": conns, "castle": castle_conns, "surface": surface}


func _surf_vec(v: int) -> Vector3:
	## (cobble, gravel, dirt) weights of a column's surface, for blending across the edge between two road columns.
	var s: int = int((info.get(v, {}) as Dictionary).get("surface", SURF_DIRT))
	match s:
		SURF_COBBLE:
			return Vector3(1, 0, 0)
		SURF_GRAVEL:
			return Vector3(0, 1, 0)
		SURF_DIRT:
			return Vector3(0, 0, 1)
	return Vector3(0, 0, 0)


# --- geometry --------------------------------------------------------------------------------------

func _vert(p: Vector3, n: Vector3, c: Color) -> void:
	_v.append(p)
	_n.append(n)
	_c.append(c)
	_uv.append(Vector2(p.x * -_uvt.y + p.z * _uvt.x, p.x * _uvt.x + p.z * _uvt.y))
	if _collect:
		_deck_faces.append(p)


func _tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color, want: Vector3) -> void:
	## One triangle turned to face `want` (Godot's front faces are clockwise from the front).
	if (b - a).cross(c - a).dot(want) < 0.0:
		_vert(a, na, ca)
		_vert(b, nb, cb)
		_vert(c, nc, cc)
	else:
		_vert(a, na, ca)
		_vert(c, nc, cc)
		_vert(b, nb, cb)


func _quad_flat(a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-10:
		n = (c - a).cross(d - a)
	var nn := n.normalized()
	if nn.dot(want) < 0.0:
		nn = -nn
	_tri(a, b, c, nn, nn, nn, col, col, col, want)
	_tri(a, c, d, nn, nn, nn, col, col, col, want)


func _ground_y(p: Vector2) -> float:
	return world.height_at(p) + HOVER


func _curve(v: int, conns: Array) -> Array:
	## The centre line of the road through column v as a list of Vector2: a smooth curve for two connections, else spokes (handled by the caller).
	var c := grid.verts[v]
	var pts := []
	var a := _mid(v, conns[0])
	var b := _mid(v, conns[1])
	for k in SAMPLES + 1:
		var t := float(k) / float(SAMPLES)
		pts.append(a * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + b * t * t)
	return pts


func _ribbon(pts: Array, w: float, sa: Vector3, sb: Vector3, deck_y: Array) -> void:
	## A road ribbon along the points: five vertices across, a worn irregular edge (u = -1..1 in the colour), laid on the terrain (or at deck_y).
	var n := pts.size()
	for k in n - 1:
		var rows := []
		for kk in [k, k + 1]:
			var p: Vector2 = pts[kk]
			var tg: Vector2 = ((pts[mini(kk + 1, n - 1)] as Vector2) - (pts[maxi(kk - 1, 0)] as Vector2)).normalized()
			var nrm := Vector2(-tg.y, tg.x)
			var row := []
			var tt := float(kk) / float(n - 1)
			var sv := sa.lerp(sb, tt)
			for u: float in [-1.0, -0.6, 0.0, 0.6, 1.0]:
				var q := p + nrm * u * (w * 0.5 + 0.12)
				var y := (_ground_y(q) if deck_y.is_empty() else float(deck_y[kk]))
				var nn := world.normal_at(q) if deck_y.is_empty() else Vector3.UP
				row.append([Vector3(q.x, y, q.y), nn, Color(sv.x, u * 0.5 + 0.5, sv.y, 0.0), sv])
			rows.append(row)
		for j in 4:
			var a: Array = rows[0][j]
			var b: Array = rows[0][j + 1]
			var c: Array = rows[1][j + 1]
			var d: Array = rows[1][j]
			_tri(a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2], Vector3.UP)
			_tri(a[0], c[0], d[0], a[1], c[1], d[1], a[2], c[2], d[2], Vector3.UP)


func _disc(centre: Vector2, r: float, sv: Vector3, y_flat: float = -1000.0) -> void:
	var sides := 14
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := centre
		var p1 := centre + Vector2(cos(a0), sin(a0)) * r
		var p2 := centre + Vector2(cos(a1), sin(a1)) * r
		var y0 := (_ground_y(p0) if y_flat < -999.0 else y_flat) + 0.003
		var y1 := (_ground_y(p1) if y_flat < -999.0 else y_flat) + 0.003
		var y2 := (_ground_y(p2) if y_flat < -999.0 else y_flat) + 0.003
		var cm := Color(sv.x, 0.5, sv.y, 0.0)
		var ce := Color(sv.x, 1.0 if i % 2 == 0 else 0.0, sv.y, 0.0)
		var up := Vector3.UP
		_tri(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y1, p1.y), Vector3(p2.x, y2, p2.y), up, up, up, cm, Color(sv.x, 1.0, sv.y, 0.0), Color(sv.x, 1.0, sv.y, 0.0), Vector3.UP)
	# the edge of a disc is the worn edge of a ribbon seen from the centre: u = 1 at the rim


func _build_column(v: int) -> void:
	var inf: Dictionary = info[v]
	var conns: Array = inf.conns
	var c := grid.verts[v]
	var cls: String = inf.cls
	var sv := _surf_vec(v)
	var nb: PackedInt32Array = grid.nbrs[v]
	if cls == "bridge" or cls == "jetty":
		_deck_column(v, inf)
		return
	var w := W
	if cls == "junction":
		w = W * 1.1
	# the ends of every spoke take the average surface of the two columns it joins
	var ends := {}
	for i: int in conns:
		var u := nb[i]
		var se := sv
		if is_road(u):
			se = (sv + _surf_vec(u)) * 0.5
		ends[i] = se
	match cls:
		"plaza":
			_disc(c, 1.55, sv)
			world.road_segs.append([c, c + Vector2(0.01, 0.0), 1.5])
			_plaza_stones(v)
		"dead":
			var i: int = conns[0]
			var m := _mid(v, i)
			var pts := []
			for k in 6:
				pts.append(m.lerp(c, float(k) / 5.0))
			_ribbon(pts, w, ends[i], sv, [])
			_disc(c, w * 0.62, sv)
			world.road_segs.append([m, c, w * 0.5])
			_dead_end_props(v, m)
		"through":
			var pts2 := _curve(v, conns)
			_ribbon(pts2, w, ends[conns[0]], ends[conns[1]], [])
			for k in pts2.size() - 1:
				world.road_segs.append([pts2[k], pts2[k + 1], w * 0.5])
		_:
			for i: int in conns:
				var m2 := _mid(v, i)
				var pts3 := []
				for k in 6:
					pts3.append(m2.lerp(c, float(k) / 5.0))
				_ribbon(pts3, w, ends[i], sv, [])
				world.road_segs.append([m2, c, w * 0.5])
			_disc(c, HUB, sv)
			_junction_props(v)
	# a castle block on the edge: its door opens onto a paved apron
	for i: int in inf.castle:
		var m3 := _mid(v, i)
		var dirn := (m3 - c).normalized()
		var pts4 := []
		for k in 5:
			pts4.append(m3 - dirn * 0.9 + dirn * 1.8 * float(k) / 4.0)
		_ribbon(pts4, 2.7, Vector3(1, 0, 0), Vector3(1, 0, 0), [])
		world.road_segs.append([m3 - dirn * 0.9, m3 + dirn * 0.9, 1.3])
		_count("apron")
	# a column of rock beside the road is held back with cut blocks along the edge they share
	for i in nb.size():
		var u := nb[i]
		if world.ground.has(u) and town.wild_heights(u).contains("r") and world.altitude(u) > world.altitude(v) + 0.5:
			var m4 := _mid(v, i)
			var f := grid.face(v, i)
			for t in [0.3, 0.7]:
				var p: Vector2 = f[0].lerp(f[1], t)
				var dirn2 := (m4 - c).normalized()
				var pp := p - dirn2 * 0.1
				inst.append([M_STONE, Transform3D(Basis(Vector3.UP, atan2(dirn2.x, dirn2.y)).scaled(Vector3(0.9, 0.8, 0.9)), Vector3(pp.x, world.height_at(pp) - 0.05, pp.y)), Color(CSBuild.h01(v, i, int(t * 10.0)), 0.0, 0.0, 0.0)])
			_count("retaining")


func _plaza_stones(v: int) -> void:
	var c := grid.verts[v]
	for i in 5:
		var a := TAU * float(i) / 5.0 + CSBuild.h01(v, 1) * 3.0
		var p := c + Vector2(cos(a), sin(a)) * 1.5
		inst.append([M_STONE, Transform3D(Basis(Vector3.UP, a).scaled(Vector3(0.7, 1.0 + 0.3 * CSBuild.h01(v, i, 4), 0.7)), Vector3(p.x, world.height_at(p) - 0.1, p.y)), Color(CSBuild.h01(v, i), 0.0, 0.0, 0.0)])


func _dead_end_props(v: int, m: Vector2) -> void:
	var c := grid.verts[v]
	var dirn := (c - m).normalized()
	var side := Vector2(-dirn.y, dirn.x)
	var p := c + dirn * 0.4 + side * 1.0
	inst.append([M_LAMP, Transform3D(Basis(Vector3.UP, atan2(side.x, side.y)), Vector3(p.x, world.height_at(p) - 0.02, p.y)), Color(CSBuild.h01(v, 2), 0.0, 0.0, 0.0)])
	var q := c - dirn * 0.2 - side * 1.0
	inst.append([M_STONE, Transform3D(Basis(Vector3.UP, atan2(dirn.x, dirn.y)).scaled(Vector3(0.5, 0.7, 0.5)), Vector3(q.x, world.height_at(q) - 0.05, q.y)), Color(0.5, 0.0, 0.0, 0.0)])


func _junction_props(v: int) -> void:
	var c := grid.verts[v]
	var n: int = (info[v] as Dictionary).conns.size()
	# a signpost on the corner of the hub that no spoke leaves from
	var best := 0.0
	var best_a := 0.0
	var angles := []
	var nb: PackedInt32Array = grid.nbrs[v]
	for i: int in (info[v] as Dictionary).conns:
		angles.append((_mid(v, i) - c).angle())
	for k in 24:
		var a := TAU * float(k) / 24.0
		var mind := PI
		for q: float in angles:
			mind = minf(mind, absf(angle_difference(a, q)))
		if mind > best:
			best = mind
			best_a = a
	var p := c + Vector2(cos(best_a), sin(best_a)) * (HUB + 0.35)
	inst.append([M_SIGN, Transform3D(Basis(Vector3.UP, best_a + PI * 0.5 + CSBuild.h01(v, 7) * 0.5), Vector3(p.x, world.height_at(p) - 0.03, p.y)), Color(CSBuild.h01(v, 3), 0.0, 0.0, 0.0)])
	_count("signpost")
	if n >= 4:
		inst.append([M_WELL, Transform3D(Basis.IDENTITY, Vector3(c.x, world.height_at(c) - 0.02, c.y)), Color(CSBuild.h01(v, 5), 0.0, 0.0, 0.0)])
		_count("well")


# --- bridges and jetties ---------------------------------------------------------------------------

func _deck_column(v: int, inf: Dictionary) -> void:
	var conns: Array = inf.conns
	var c := grid.verts[v]
	var nb: PackedInt32Array = grid.nbrs[v]
	var stone: bool = int(inf.surface) == SURF_STONE
	var cls: String = inf.cls
	var path := []
	if conns.size() >= 2:
		path = _curve(v, [conns[0], conns[1]])
	elif conns.size() == 1:
		var m := _mid(v, conns[0])
		for k in SAMPLES + 1:
			path.append(m.lerp(c + (c - m).normalized() * 0.9, float(k) / float(SAMPLES)))
	else:
		for k in SAMPLES + 1:
			path.append(c + Vector2(-1.2, 0.0) + Vector2(2.4, 0.0) * float(k) / float(SAMPLES))
	# the deck height: where it meets land it meets the land's height, over open water it stands 1.0 m above the sea; a stone span arches a little
	var ya := 1.0
	var yb := 1.0
	if conns.size() >= 1:
		var ua := nb[conns[0]]
		if not world.deck.has(ua):
			ya = world.height_at(_mid(v, conns[0])) + 0.05
	if conns.size() >= 2:
		var ub := nb[conns[1]]
		if not world.deck.has(ub):
			yb = world.height_at(_mid(v, conns[1])) + 0.05
	var ys := PackedFloat32Array()
	var n := path.size()
	for k in n:
		var t := float(k) / float(n - 1)
		var y := lerpf(ya, yb, t) + (0.3 * sin(PI * t) if stone else 0.0)
		ys.append(y)
	var hw := 1.0
	var thick := 0.4
	var col_side := Color(0, 0.5, 0, 0.5 if stone else 0.7)
	var mat_top := Color(0.0, 0.0, 0.0, 0.5 if stone else 0.4)
	_collect = true
	for k in n - 1:
		var p0: Vector2 = path[k]
		var p1: Vector2 = path[k + 1]
		var t0 := (p1 - p0).normalized()
		var nl := Vector2(-t0.y, t0.x)
		var tprev := (p0 - (path[maxi(k - 1, 0)] as Vector2))
		var l0 := Vector2(-((path[mini(k + 1, n - 1)] as Vector2) - (path[maxi(k - 1, 0)] as Vector2)).normalized().y, ((path[mini(k + 1, n - 1)] as Vector2) - (path[maxi(k - 1, 0)] as Vector2)).normalized().x)
		var l1 := Vector2(-((path[mini(k + 2, n - 1)] as Vector2) - p0).normalized().y, ((path[mini(k + 2, n - 1)] as Vector2) - p0).normalized().x)
		var tt0 := float(k) / float(n - 1)
		var tt1 := float(k + 1) / float(n - 1)
		_uvt = t0
		# the soffit of a stone span is a shallow arch under the deck
		var b0: float = ys[k] - thick - (0.55 * sin(PI * tt0) if stone else 0.0)
		var b1: float = ys[k + 1] - thick - (0.55 * sin(PI * tt1) if stone else 0.0)
		var a_l := Vector3(p0.x + l0.x * hw, ys[k], p0.y + l0.y * hw)
		var a_r := Vector3(p0.x - l0.x * hw, ys[k], p0.y - l0.y * hw)
		var b_l := Vector3(p1.x + l1.x * hw, ys[k + 1], p1.y + l1.y * hw)
		var b_r := Vector3(p1.x - l1.x * hw, ys[k + 1], p1.y - l1.y * hw)
		_quad_flat(a_l, b_l, b_r, a_r, Vector3.UP, mat_top)
		_quad_flat(a_l, b_l, Vector3(b_l.x, b1, b_l.z), Vector3(a_l.x, b0, a_l.z), Vector3(nl.x, 0, nl.y), col_side)
		_quad_flat(a_r, b_r, Vector3(b_r.x, b1, b_r.z), Vector3(a_r.x, b0, a_r.z), Vector3(-nl.x, 0, -nl.y), col_side)
		_quad_flat(Vector3(a_l.x, b0, a_l.z), Vector3(b_l.x, b1, b_l.z), Vector3(b_r.x, b1, b_r.z), Vector3(a_r.x, b0, a_r.z), Vector3.DOWN, col_side)
		if stone:
			# parapets: a low wall on each side, 0.45 high and 0.24 thick
			for sgn in [1.0, -1.0]:
				var inner := hw - 0.24 if sgn > 0.0 else hw - 0.24
				var o0 := Vector3(p0.x + l0.x * hw * sgn, ys[k], p0.y + l0.y * hw * sgn)
				var o1 := Vector3(p1.x + l1.x * hw * sgn, ys[k + 1], p1.y + l1.y * hw * sgn)
				var i0 := Vector3(p0.x + l0.x * inner * sgn, ys[k], p0.y + l0.y * inner * sgn)
				var i1 := Vector3(p1.x + l1.x * inner * sgn, ys[k + 1], p1.y + l1.y * inner * sgn)
				var up := Vector3(0, 0.45, 0)
				_quad_flat(o0 + up, o1 + up, i1 + up, i0 + up, Vector3.UP, col_side)
				_quad_flat(o0, o1, o1 + up, o0 + up, Vector3(l0.x * sgn, 0, l0.y * sgn), col_side)
				_quad_flat(i0, i1, i1 + up, i0 + up, Vector3(-l0.x * sgn, 0, -l0.y * sgn), col_side)
		elif k % 2 == 0:
			# a timber rail: a post each side every other segment, rail between
			for sgn in [1.0, -1.0]:
				var po := Vector2(p0.x + l0.x * (hw - 0.06) * sgn, p0.y + l0.y * (hw - 0.06) * sgn)
				inst.append([M_RAIL, Transform3D(Basis(Vector3.UP, atan2(t0.x, t0.y)), Vector3(po.x, ys[k], po.y)), Color(0.0, 0.0, 0.0, 0.0)])
		# piles under the deck, one pair every other segment
		if k % 2 == 0:
			for sgn in [1.0, -1.0]:
				var pp := Vector2(p0.x + l0.x * (hw - 0.25) * sgn, p0.y + l0.y * (hw - 0.25) * sgn)
				inst.append([M_PILE, Transform3D(Basis.IDENTITY, Vector3(pp.x, ys[k] - thick, pp.y)), Color(CSBuild.h01(v, k, 3), float(ys[k] - thick + 2.5), 0.0, 0.0)])
		world.road_segs.append([p0, p1, 0.3])
	if cls == "jetty":
		var endp: Vector2 = path[n - 1]
		inst.append([M_LAMP, Transform3D(Basis.IDENTITY, Vector3(endp.x, ys[n - 1], endp.y)), Color(CSBuild.h01(v, 6), 0.0, 0.0, 0.0)])
		_count("jetty_lamp")
	_count("deck")
	_collect = false


## Everything laid so far as a mesh arrays dictionary; the faces are added to the world's collision mesh.
func commit(m: ArrayMesh, material: Material) -> void:
	if _v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_TEX_UV] = _uv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)


func faces() -> PackedVector3Array:
	## The deck's triangles (bridges and jetties take clicks; the road ribbon on the ground does not need to: the terrain is under it).
	return _deck_faces


func buffers() -> Array:
	var lists := []
	for _m in MESH_COUNT:
		lists.append([])
	for it: Array in inst:
		(lists[int(it[0])] as Array).append(it)
	var out := []
	for m in MESH_COUNT:
		var list: Array = lists[m]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var j := 0
		for it: Array in list:
			var xf: Transform3D = it[1]
			var cd: Color = it[2]
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
			buf[j + 12] = cd.r
			buf[j + 13] = cd.g
			buf[j + 14] = cd.b
			buf[j + 15] = cd.a
			j += 16
		out.append(buf)
	return out


func multimeshes(meshes: Array) -> Array:
	var out := []
	var bufs := buffers()
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


static func make_meshes() -> Array:
	## Signpost, well, lamp, standing stone, pile, rail post: code-made, flora shader zones (0 bark / wood, 6 dressed stone, 5 rock, 7 iron, 8 flame).
	var out := []
	for m in MESH_COUNT:
		var mb := CSScatter.MB.new()
		var h := 3.0
		match m:
			M_SIGN:
				h = 2.6
				mb.trunk(0.0, 2.3, 0.07, 0.06, 6, 0)
				mb.box_block(Vector3(0.28, 2.05, 0.0), Vector3(0.45, 0.1, 0.03), 0, 0.5, 0.06, 301)
				mb.box_block(Vector3(-0.22, 1.72, 0.0), Vector3(0.38, 0.09, 0.03), 0, 0.3, 0.06, 302)
			M_WELL:
				h = 2.6
				for i in 10:
					var a0 := TAU * float(i) / 10.0
					var a1 := TAU * float(i + 1) / 10.0
					var pa := Vector3(cos(a0) * 0.55, 0.0, sin(a0) * 0.55)
					var pb := Vector3(cos(a1) * 0.55, 0.0, sin(a1) * 0.55)
					var up := Vector3(0, 0.65, 0)
					var nrm := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
					mb.add(pa, nrm, 6, 0.5)
					mb.add(pa + up, nrm, 6, 0.5)
					mb.add(pb, nrm, 6, 0.5)
					mb.add(pb, nrm, 6, 0.5)
					mb.add(pa + up, nrm, 6, 0.5)
					mb.add(pb + up, nrm, 6, 0.5)
				mb.trunk(0.0, 1.9, 0.05, 0.05, 5, 0)
				mb.box_block(Vector3(0.0, 1.9, 0.0), Vector3(0.7, 0.05, 0.05), 0, 0.5, 0.02, 303)
			M_LAMP:
				h = 2.8
				mb.trunk(0.0, 2.3, 0.05, 0.04, 6, 7)
				mb.box_block(Vector3(0.0, 2.45, 0.0), Vector3(0.14, 0.17, 0.14), 8, 0.5, 0.02, 304)
				mb.box_block(Vector3(0.0, 2.7, 0.0), Vector3(0.2, 0.04, 0.2), 7, 0.5, 0.0, 305)
			M_STONE:
				h = 2.0
				mb.box_block(Vector3(0, 0.8, 0), Vector3(0.32, 0.8, 0.2), 5, 0.5, 0.4, 306)
			M_PILE:
				h = 4.0
				mb.trunk(-2.5, 0.0, 0.11, 0.1, 7, 0)
			M_RAIL:
				h = 1.1
				mb.trunk(0.0, 0.85, 0.05, 0.045, 5, 0)
				mb.box_block(Vector3(0.0, 0.8, 0.5), Vector3(0.03, 0.04, 0.5), 0, 0.5, 0.02, 307)
		out.append(mb.commit(h))
	return out
