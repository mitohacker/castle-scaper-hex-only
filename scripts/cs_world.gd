class_name CSWorld
extends RefCounted
## The landscape the player builds beside the castle (CSTown.wild): plain land, roads, trees, rocks and mountains, each placed one grid
## cell at a time like the castle's blocks, and each turning into something different depending on what is round it.
##
## Ground. Every column with land, a height (mountain m / rock r levels), trees, or standing on a castle courtyard is a cell of one
## terrain mesh. A cell's centre has the height of its own levels; each of its corners (the centre of a triangle of the grid, shared by three
## columns) has one height for everybody, the mean of the three columns' heights, so the cells join without a crack. Between the centre
## and a corner the cell's own profile decides the shape: a mountain falls away fast from its summit, a rock keeps a plateau and ends in a
## cliff, plain land is a gentle swell; ridged noise roughens the slopes. A corner touching castle land is flat at the castle's ground
## height (CSBuild.B), so land meets the castle flush. Coast edges get a bank (beach) or a cliff, depending on how high the corner is.
##
## Everything else lives in the files this one calls: roads (CSRoads), trees and rocks (CSScatter). This file is the terrain, the shared
## context (neighbour counts, altitude, water, castle) and `height_at`.

const G := 0.6                  # ground height = CSBuild.B
const MT_LEVEL := 3.6           # one mountain level (m)
const RK_LEVEL := 1.7           # one rock level (m)
const RINGS := [0.0, 0.26, 0.5, 0.75, 1.0]
const SKIRT_D := [0.0, 0.5, 1.2, 2.2, 3.6]

var grid: CSGrid
var town: CSTown
var castle_land := {}           # v -> "base" | "passage" | "court" (CSBuild.land)
var ground := {}                # v -> true: wild columns with earth under them
var garden := {}                # v -> true: wild columns on a castle courtyard (flat, lifted a hair above the court's floor)
var deck := {}                  # v -> true: road-only columns over water (bridges and jetties)
var extra := {}                 # v -> height of the column above G
var sharp := {}                 # v -> share of rock in the column's height levels, 0..1
var corner := {}                # triangle id -> corner height above G
var cell_tris := {}             # v -> PackedVector3Array (flat triangle list) for height_at
var mesh_arrays := {}           # the terrain surface, filled by build_terrain
var faces := PackedVector3Array()   # triangles for the collision shape
var stats := {}
var road_segs: Array = []        # [a: Vector2, b: Vector2, half width] of every road ribbon (CSRoads fills it)
var _vi := {}                   # Vector3i -> vertex index (shared vertices)
var _pos := PackedVector3Array()
var _col := PackedColorArray()
var _ccount := PackedInt32Array()
var _idx := PackedInt32Array()
var _noise: FastNoiseLite


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.22
	_noise.fractal_octaves = 4
	_noise.seed = 5


## Builds everything derived from the landscape: the sets, the heights and the terrain mesh.
func build(g: CSGrid, t: CSTown, p_castle_land: Dictionary) -> void:
	grid = g
	town = t
	castle_land = p_castle_land
	_classify()
	_heights()
	_terrain()
	stats = {"ground": ground.size(), "garden": garden.size(), "deck": deck.size(), "tris": faces.size() / 3}


func _classify() -> void:
	for v: int in town.wild:
		if not grid.buildable(v) or town.top(v) >= 0:
			continue
		if castle_land.has(v):
			if str(castle_land[v]) == "court" and (town.wild_is_ground(v) or town.wild_road(v)):
				garden[v] = true
			continue
		if town.wild_is_ground(v):
			ground[v] = true
		elif town.wild_road(v):
			deck[v] = true
	# the little triangles between the dodecagons are no cells of the landscape, but the ground goes across them when two of the three
	# dodecagons round one have ground (or castle land) under them: no hole, no coast round a pit
	var tri_ground := {}
	for v: int in ground.keys():
		for u: int in grid.nbrs[v]:
			if grid.is_dodecagon(u) or not grid.is_whole(u) or castle_land.has(u) or tri_ground.has(u):
				continue
			var n := 0
			for d: int in grid.nbrs[u]:
				if ground.has(d) or garden.has(d) or castle_land.has(d):
					n += 1
			if n >= 2:
				tri_ground[u] = true
	for u: int in tri_ground:
		ground[u] = true


func is_land(v: int) -> bool:
	return ground.has(v) or garden.has(v) or castle_land.has(v)


func altitude(v: int) -> float:
	return float(extra.get(v, 0.0))


func _heights() -> void:
	for v: int in ground:
		if not grid.is_dodecagon(v):
			# a triangle between three dodecagons: the mean height of those that have ground of their own
			var sx := 0.0
			var sr := 0.0
			var cnt := 0
			for d: int in grid.nbrs[v]:
				if ground.has(d) and grid.is_dodecagon(d):
					cnt += 1
			for d: int in grid.nbrs[v]:
				if ground.has(d) and grid.is_dodecagon(d):
					var hd := town.wild_heights(d)
					var ed := 0.0
					var rd := 0
					for i in hd.length():
						ed += MT_LEVEL if hd[i] == "m" else RK_LEVEL
						rd += 0 if hd[i] == "m" else 1
					sx += ed
					sr += float(rd) / float(hd.length()) if hd.length() > 0 else 0.0
			extra[v] = sx / float(maxi(cnt, 1))
			sharp[v] = sr / float(maxi(cnt, 1))
			continue
		var h := town.wild_heights(v)
		var e := 0.0
		var rocks := 0
		for i in h.length():
			if h[i] == "m":
				e += MT_LEVEL
			else:
				e += RK_LEVEL
				rocks += 1
		extra[v] = e
		sharp[v] = float(rocks) / float(h.length()) if h.length() > 0 else 0.0
	# a corner's height: the mean of the columns round the triangle's centre, flat where the castle's land touches
	for v: int in ground:
		for q in grid.rings[v]:
			if q < 0 or corner.has(q):
				continue
			var sum := 0.0
			var flat := false
			for i in 3:
				var u := grid.tris[q * 3 + i]
				if castle_land.has(u) or garden.has(u):
					flat = true
				sum += float(extra.get(u, 0.0))
			var c := sum / 3.0 * 1.3
			var mx := 0.0
			for i in 3:
				mx = maxf(mx, float(extra.get(grid.tris[q * 3 + i], 0.0)))
			corner[q] = 0.0 if flat else minf(c, mx)


# --- terrain ---------------------------------------------------------------------------------------

func _vertex(p: Vector3, col: Color) -> int:
	var key := Vector3i(roundi(p.x * 250.0), roundi(p.y * 250.0), roundi(p.z * 250.0))
	if _vi.has(key):
		var i: int = _vi[key]
		_col[i] += col
		_ccount[i] += 1
		return i
	var n := _pos.size()
	_vi[key] = n
	_pos.append(p)
	_col.append(col)
	_ccount.append(1)
	return n


func _tri(a: int, b: int, c: int) -> void:
	_idx.append_array([a, b, c])


func _cell_height(v: int, i: int, t: float, corner_h: float) -> float:
	var ex: float = extra[v]
	var rk: float = sharp.get(v, 0.0)
	var sm := pow(t, 0.7)
	var sr := smoothstep(0.55, 1.0, t)
	var s := lerpf(sm, sr, rk)
	return ex + (corner_h - ex) * s


func _terrain() -> void:
	var cols := ground.keys()
	cols.sort()
	var coast_n := {}               # corner key -> summed outward normals of the coast edges that meet there
	var coast_edges := []           # [v, i]
	for v: int in cols:
		var poly := grid.dual(v)
		var n := poly.size()
		var c0 := grid.verts[v]
		var tris := PackedVector3Array()
		var ex: float = extra[v]
		var rg: PackedInt32Array = grid.rings[v]
		var amp := 0.12 + ex * 0.14 * (1.0 - 0.6 * float(sharp.get(v, 0.0)))
		var forest := float(town.wild_trees(v)) / 3.0
		var rockf := float(sharp.get(v, 0.0))
		var colv := Color(rockf, forest, 0.0, 1.0)
		# the vertex rings
		var ring_idx: Array = []
		for k in RINGS.size():
			var t: float = RINGS[k]
			var row: Array = []
			if k == 0:
				var p0 := Vector3(c0.x, G + ex + _noise.get_noise_2d(c0.x, c0.y) * amp, c0.y)
				row.append(_vertex(p0, colv))
				ring_idx.append(row)
				continue
			for i in n:
				var cq: float = corner[rg[i]]
				var cp := poly[i]
				var xz := c0.lerp(cp, t)
				var h := _cell_height(v, i, t, cq)
				var nz := 0.0
				if t < 0.999:
					var rid := absf(_noise.get_noise_2d(xz.x * 1.9 + 31.0, xz.y * 1.9)) * 2.0 - 0.6        # ridged: crests and gullies
					nz = (_noise.get_noise_2d(xz.x, xz.y) + 0.5 * rid * (0.3 + rockf * 0.5)) * amp * (1.0 - pow(t, 3.0))
				row.append(_vertex(Vector3(xz.x, G + h + nz, xz.y), colv))
			ring_idx.append(row)
		# the triangles
		for i in n:
			var j := (i + 1) % n
			_tri_add(tris, ring_idx[0][0], ring_idx[1][i], ring_idx[1][j])
			for k in range(1, RINGS.size() - 1):
				var a: int = ring_idx[k][i]
				var b: int = ring_idx[k][j]
				var cc: int = ring_idx[k + 1][i]
				var d: int = ring_idx[k + 1][j]
				_tri_add(tris, a, cc, d)
				_tri_add(tris, a, d, b)
		cell_tris[v] = tris
		# coast edges: the side facing neighbour i is the edge between corners i - 1 and i
		for i in n:
			var u: int = grid.nbrs[v][i]
			if ground.has(u) or castle_land.has(u) or garden.has(u):
				continue
			var a := poly[(i + n - 1) % n]
			var b := poly[i]
			var out := (b - a).normalized().rotated(PI / 2.0)
			if out.dot(a.lerp(b, 0.5) - c0) < 0.0:
				out = -out
			for ck: Vector2 in [a, b]:
				var key := Vector2i(roundi(ck.x * 200.0), roundi(ck.y * 200.0))
				coast_n[key] = Vector2(coast_n.get(key, Vector2.ZERO)) + out
			coast_edges.append([v, i])
	_skirt(coast_edges, coast_n)
	# gardens: a flat patch of grass on the courtyard's floor
	for v: int in garden:
		var poly := grid.dual(v)
		var n := poly.size()
		var y := G + 0.03
		var tris := PackedVector3Array()
		var c0 := grid.verts[v]
		var cv := _vertex(Vector3(c0.x, y, c0.y), Color(0, float(town.wild_trees(v)) / 3.0, 0, 1))
		for i in n:
			var j := (i + 1) % n
			var a := _vertex(Vector3(poly[i].x, y, poly[i].y), Color(0, 0, 0, 1))
			var b := _vertex(Vector3(poly[j].x, y, poly[j].y), Color(0, 0, 0, 1))
			_tri_add(tris, cv, a, b)
		cell_tris[v] = tris
	# normals and the arrays
	var nrm := PackedVector3Array()
	nrm.resize(_pos.size())
	for t in range(0, _idx.size(), 3):
		var a := _pos[_idx[t]]
		var b := _pos[_idx[t + 1]]
		var c := _pos[_idx[t + 2]]
		var fn := (b - a).cross(c - a)
		for k in 3:
			nrm[_idx[t + k]] += fn
	var colors := PackedColorArray()
	colors.resize(_pos.size())
	for i in _pos.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 1e-14 else Vector3.UP
		if nrm[i].y < 0.0:
			nrm[i] = -nrm[i]
		colors[i] = _col[i] / float(maxi(_ccount[i], 1))
	for t in range(0, _idx.size(), 3):
		faces.append(_pos[_idx[t]])
		faces.append(_pos[_idx[t + 1]])
		faces.append(_pos[_idx[t + 2]])
	mesh_arrays = {"verts": _pos, "norms": nrm, "cols": colors, "idx": _idx}


func _tri_add(tris: PackedVector3Array, a: int, b: int, c: int) -> void:
	## One triangle of the cell, turned to face up (Godot's front faces are clockwise, seen from the front).
	var pa := _pos[a]
	var pb := _pos[b]
	var pc := _pos[c]
	var up := (pb - pa).cross(pc - pa).y
	if up < 0.0:
		_tri(a, b, c)
		tris.append_array([pa, pb, pc])
	else:
		_tri(a, c, b)
		tris.append_array([pa, pc, pb])


func _tri_out(a: int, b: int, c: int, want: Vector3) -> void:
	## One triangle turned to face `want` (clockwise from the front, Godot's rule).
	if (_pos[b] - _pos[a]).cross(_pos[c] - _pos[a]).dot(want) < 0.0:
		_tri(a, b, c)
	else:
		_tri(a, c, b)


func _skirt(edges: Array, coast_n: Dictionary) -> void:
	## A bank or a cliff down into the water along every coast edge, from the cell's corners outward.
	for e: Array in edges:
		var v: int = e[0]
		var i: int = e[1]
		var poly := grid.dual(v)
		var n := poly.size()
		var rg: PackedInt32Array = grid.rings[v]
		var ia := (i + n - 1) % n
		var ends := [ia, i]
		var eo := (poly[i] - poly[ia]).normalized().rotated(PI / 2.0)
		if eo.dot(poly[ia].lerp(poly[i], 0.5) - grid.verts[v]) < 0.0:
			eo = -eo
		var want := Vector3(eo.x, 0.35, eo.y)
		var rows: Array = []
		for ci: int in ends:
			var cp := poly[ci]
			var key := Vector2i(roundi(cp.x * 200.0), roundi(cp.y * 200.0))
			var dirn: Vector2 = Vector2(coast_n[key]).normalized()
			var hh: float = G + float(corner[rg[ci]])
			var cliff := hh > 2.4
			var row := []
			for k in SKIRT_D.size():
				var d: float = SKIRT_D[k]
				var hy: float
				if cliff:
					var hs := [hh, lerpf(hh, 0.0, 0.5), lerpf(hh, 0.0, 0.88) - 0.1, -1.0, -2.4]
					hy = hs[k]
				else:
					var hs := [hh, hh * 0.25, -0.35, -1.3, -2.4]
					hy = hs[k]
				var dd := d * (1.0 if cliff else 1.3)
				var p3 := Vector3(cp.x + dirn.x * dd, hy, cp.y + dirn.y * dd)
				row.append(_vertex(p3, Color(float(sharp.get(v, 0.0)), 0.0, 1.0 if not cliff else 0.5, 1.0)))
			rows.append(row)
		for k in range(SKIRT_D.size() - 1):
			var a: int = rows[0][k]
			var b: int = rows[1][k]
			var c: int = rows[0][k + 1]
			var d: int = rows[1][k + 1]
			_tri_out(a, c, d, want)
			_tri_out(a, d, b, want)



func commit(m: ArrayMesh, material: Material) -> void:
	if mesh_arrays.is_empty() or (mesh_arrays.verts as PackedVector3Array).is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = mesh_arrays.verts
	arr[Mesh.ARRAY_NORMAL] = mesh_arrays.norms
	arr[Mesh.ARRAY_COLOR] = mesh_arrays.cols
	arr[Mesh.ARRAY_INDEX] = mesh_arrays.idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)


func _tri_at(p: Vector2) -> PackedVector3Array:
	## The terrain triangle over the point p (empty when there is none).
	var v := grid.nearest(p)
	if v < 0:
		return PackedVector3Array()
	for u: int in [v] + Array(grid.nbrs[v]):
		if not cell_tris.has(u):
			continue
		var tris: PackedVector3Array = cell_tris[u]
		for t in range(0, tris.size(), 3):
			var a := Vector2(tris[t].x, tris[t].z)
			var b := Vector2(tris[t + 1].x, tris[t + 1].z)
			var c := Vector2(tris[t + 2].x, tris[t + 2].z)
			var bc := _bary(p, a, b, c)
			if bc.x >= -0.001 and bc.y >= -0.001 and bc.z >= -0.001:
				return PackedVector3Array([tris[t], tris[t + 1], tris[t + 2]])
	return PackedVector3Array()


## The terrain's height at a point of the map (m), or G where the point is not over any wild cell.
func height_at(p: Vector2) -> float:
	var tr := _tri_at(p)
	if tr.is_empty():
		var v := grid.nearest(p)
		return G + 0.03 if v >= 0 and garden.has(v) else G
	var bc := _bary(p, Vector2(tr[0].x, tr[0].z), Vector2(tr[1].x, tr[1].z), Vector2(tr[2].x, tr[2].z))
	return tr[0].y * bc.x + tr[1].y * bc.y + tr[2].y * bc.z


func normal_at(p: Vector2) -> Vector3:
	var tr := _tri_at(p)
	if tr.is_empty():
		return Vector3.UP
	var n := (tr[1] - tr[0]).cross(tr[2] - tr[0]).normalized()
	return n if n.y > 0.0 else -n


## What is round column v: how many neighbours are water, rock, mountain, road, castle, trees and plain land. Every build rule that
## depends on the surroundings reads this one table (the interactions between the types are the rules on top of it; see the SPEC).
func ctx(v: int) -> Dictionary:
	var c := {"water": 0, "rock": 0, "mount": 0, "road": 0, "castle": 0, "tree": 0, "land": 0, "deck": 0}
	for u: int in grid.nbrs[v]:
		if not grid.is_dodecagon(u):
			continue                         # the little triangles between the dodecagons are not neighbours of the landscape
		if not grid.buildable(u):
			c.water += 1
		elif town.top(u) >= 0 or (castle_land.has(u) and str(castle_land[u]) != "court"):
			c.castle += 1
		elif ground.has(u) or garden.has(u):
			c.land += 1
			var h := town.wild_heights(u)
			if h.contains("m"):
				c.mount += 1
			if h.contains("r"):
				c.rock += 1
			if town.wild_trees(u) > 0:
				c.tree += 1
			if town.wild_road(u):
				c.road += 1
		elif deck.has(u):
			c.deck += 1
			c.road += 1
		elif castle_land.has(u):
			c.castle += 1
		else:
			c.water += 1
	return c


## True when no road passes within r of p (roads are added by CSRoads; until then nothing is in the way).
func road_clear(p: Vector2, r: float) -> bool:
	for seg: Array in road_segs:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < r + float(seg[2]):
			return false
	return true


static func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-12:
		return Vector3(-1, -1, -1)
	var y := (d11 * d20 - d01 * d21) / den
	var z := (d00 * d21 - d01 * d20) / den
	return Vector3(1.0 - y - z, y, z)
