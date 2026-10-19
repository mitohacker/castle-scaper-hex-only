class_name CSGrid
extends RefCounted
## Castle Scaper Hex: the DOUBLE HEX GRID, "12 sides". The cells are regular dodecagons and equilateral triangles, all with the same side
## (the truncated hexagonal tiling, 3.12.12): dodecagons sit on a triangular lattice and touch their six lattice neighbours along a
## shared side; the gap between every three of them is a triangle. Side by side, a hexagon grid and the same grid turned by 30 degrees:
## the sides run in 12 directions (a dodecagon's sides are 30 degrees apart; every direction occurs on both kinds of cell).
##
## A block stands on a grid POINT and fills that point's cell. The points are the dodecagons' centres (12 neighbours each: 6 dodecagons
## and 6 triangles, alternating) and the triangles' centres (3 neighbours: the dodecagons round it). The faces of the point graph are the
## triangles (D, D', T), one per cell corner, and `centers[q]` is that corner's real position, not the face's centroid. Every corner is shared
## by exactly three cells that are all neighbours of each other, so two blocks never touch at only a corner. The outermost ring of dodecagons
## is sea (not buildable); a hexagon-shaped island of dodecagons and triangles stands inside it.
##
## (History: a random-flip hex grid, an organic jittered one, a regular hexagon grid. The seed is kept for saved towns and does nothing.)

const SIDE := 2.886751345948129      # the side of every cell (m): 5 / sqrt(3), the side of the earlier regular hexagons
const TURN := 3.7320508075688772     # 2 + sqrt(3): the distance between two dodecagon centres in sides
const D_SPACING := SIDE * TURN       # 10.77 m
const RINGS := 8                     # dodecagon rings round the middle one: 217 dodecagons, the outer ring is the sea
const GRID_ID := "dodeca-1"          # saved towns say which grid their column numbers belong to

var step := D_SPACING               # (the size of the hash cells of the lookup)
var radius := RINGS                 # rings of dodecagons round the middle one
var seed := 1
var verts := PackedVector2Array()   # the points: dodecagon centres first (d_count), then triangle centres (m)
var d_count := 0                    # how many of the points are dodecagon centres
var border := PackedByteArray()     # 1 on the sea ring (not buildable)
var tris := PackedInt32Array()      # 3 point ids per face, counter-clockwise in (x, z): dodecagon, dodecagon, triangle
var centers := PackedVector2Array() # per face: the cell corner it stands for (shared by the three cells round it)
var nbrs: Array = []                # per point: PackedInt32Array of neighbours, counter-clockwise
var rings: Array = []               # per point: PackedInt32Array, face i lies between nbrs[i] and nbrs[i+1] (-1: outside)
var cells: Array = []               # per point: its cell polygon (the corners of its faces, counter-clockwise)
var _mid := {}                      # edge key -> midpoint
var _hash := {}                     # Vector2i (cells of HASH metres) -> [point ids]

const HASH := 6.0


func edge_key(a: int, b: int) -> int:
	return mini(a, b) * 1048576 + maxi(a, b)


func mid(a: int, b: int) -> Vector2:
	return _mid.get(edge_key(a, b), (verts[a] + verts[b]) * 0.5)


func is_dodecagon(v: int) -> bool:
	return v < d_count


func generate(p_seed: int = 1, p_radius: int = RINGS, _p_step: float = 0.0) -> void:
	seed = p_seed
	radius = clampi(p_radius, 2, 20)
	var n := radius
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var inside := func(a: int, b: int) -> bool:
		return absi(a) <= n and absi(b) <= n and absi(a + b) <= n
	# the dodecagons: a triangular lattice cut to a hexagon
	var did := {}
	verts.resize(0)
	border.resize(0)
	for a in range(-n, n + 1):
		for b in range(-n, n + 1):
			if inside.call(a, b):
				did[Vector2i(a, b)] = verts.size()
				verts.append((e1 * float(a) + e2 * float(b)) * D_SPACING)
				border.append(1 if (absi(a) == n or absi(b) == n or absi(a + b) == n) else 0)
	d_count = verts.size()
	# a triangle in every gap between three dodecagons (the lattice triangles pointing up and down), and three faces round it
	var qs := PackedInt32Array()
	var lattice_tris: Array = []
	for a in range(-n, n + 1):
		for b in range(-n, n + 1):
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1):
				lattice_tris.append([did[Vector2i(a, b)], did[Vector2i(a + 1, b)], did[Vector2i(a, b + 1)]])
			if inside.call(a + 1, b) and inside.call(a + 1, b + 1) and inside.call(a, b + 1):
				lattice_tris.append([did[Vector2i(a + 1, b)], did[Vector2i(a + 1, b + 1)], did[Vector2i(a, b + 1)]])
	for lt: Array in lattice_tris:
		var t := verts.size()
		verts.append((verts[lt[0]] + verts[lt[1]] + verts[lt[2]]) / 3.0)
		border.append(0)
		for k in 3:
			qs.append_array([lt[k], lt[(k + 1) % 3], t])
	tris = qs
	_build_topology()


func _build_topology() -> void:
	var nv := verts.size()
	var nq := tris.size() / 3
	centers.resize(nq)
	_mid.clear()
	var around: Array = []                    # per point: [face, prev neighbour, next neighbour]
	around.resize(nv)
	for i in nv:
		around[i] = []
	for q in nq:
		# the cell corner of face (dodecagon, dodecagon, triangle): on the shared side of the two dodecagons, half a side from its
		# middle towards the triangle (the other end of that side is the corner of the face on the triangle's other flank)
		var da := verts[tris[q * 3]]
		var db := verts[tris[q * 3 + 1]]
		var mid_ab := (da + db) * 0.5
		centers[q] = mid_ab + (verts[tris[q * 3 + 2]] - mid_ab).normalized() * (SIDE * 0.5)
		for k in 3:
			var v := tris[q * 3 + k]
			var nx := tris[q * 3 + (k + 1) % 3]
			var pv := tris[q * 3 + (k + 2) % 3]
			(around[v] as Array).append([q, nx, pv])
			var ek := edge_key(v, nx)
			if not _mid.has(ek):
				_mid[ek] = (verts[v] + verts[nx]) * 0.5
	nbrs.resize(nv)
	rings.resize(nv)
	cells.resize(nv)
	_hash.clear()
	for v in nv:
		var items: Array = around[v]
		# order the triangles round v counter-clockwise: triangle (v, nx, pv) spans nx -> pv going counter-clockwise
		items.sort_custom(func(x: Array, y: Array) -> bool:
			return (centers[x[0]] - verts[v]).angle() < (centers[y[0]] - verts[v]).angle())
		var nb := PackedInt32Array()
		var rg := PackedInt32Array()
		for it: Array in items:
			if nb.is_empty() or nb[nb.size() - 1] != int(it[1]):
				if not nb.is_empty():
					rg.append(-1)            # a gap (the map's edge)
				nb.append(int(it[1]))
			rg.append(int(it[0]))
			nb.append(int(it[2]))
		# a closed ring repeats its first neighbour at the end
		if nb.size() > 1 and nb[nb.size() - 1] == nb[0] and rg.size() == nb.size() - 1:
			nb.remove_at(nb.size() - 1)
		else:
			rg.append(-1)
		nbrs[v] = nb
		rings[v] = rg
		var poly := PackedVector2Array()
		for q in rg:
			if q >= 0:
				poly.append(centers[q])
		cells[v] = poly
		var hk := Vector2i(floori(verts[v].x / HASH), floori(verts[v].y / HASH))
		if not _hash.has(hk):
			_hash[hk] = []
		(_hash[hk] as Array).append(v)


# --- queries ---------------------------------------------------------------------------------------

func buildable(v: int) -> bool:
	if v < 0 or v >= verts.size() or border[v]:
		return false
	for q in rings[v]:
		if q < 0:
			return false
	return true


func nearest(p: Vector2, only_buildable: bool = true) -> int:
	## The point whose cell contains p (a dodecagon is far wider than a triangle, so the nearest centre is not the cell p is in). A p over a
	## cell that is not buildable (the sea ring) gives the nearest buildable point instead; one outside every cell, the nearest point.
	var hk := Vector2i(floori(p.x / HASH), floori(p.y / HASH))
	var best := -1
	var bd := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for v: int in _hash.get(Vector2i(hk.x + dx, hk.y + dz), []):
				if _in_cell(v, p) and (not only_buildable or buildable(v)):
					return v
				if only_buildable and not buildable(v):
					continue
				var d := verts[v].distance_squared_to(p)
				if d < bd:
					bd = d
					best = v
	return best


func _in_cell(v: int, p: Vector2) -> bool:
	## p inside v's convex cell (counter-clockwise polygon)?
	var poly: PackedVector2Array = cells[v]
	var n := poly.size()
	if n < 3:
		return false
	for i in n:
		if (poly[(i + 1) % n] - poly[i]).cross(p - poly[i]) < -1e-9:
			return false
	return true


static func snap_direction(d: Vector2) -> Vector2:
	## d turned to the nearest of the grid's 12 directions (multiples of 30 degrees): the lines of both hexagon grids.
	var step_angle := PI / 6.0
	return Vector2.from_angle(roundf(d.angle() / step_angle) * step_angle)


func cells_along(a: Vector2, b: Vector2, only_buildable: bool = true) -> PackedInt32Array:
	## The points whose cells the segment a-b passes through or runs along (a cell it only grazes within 2 cm counts), in the order it meets
	## them. Along the line through the middles of a row of dodecagons that is the row; along one of the 30 degree lines it goes through
	## dodecagon, triangle, then runs along the shared side of two dodecagons (both count) and on through the next triangle.
	var lo := a.min(b) - Vector2(HASH, HASH)
	var hi := a.max(b) + Vector2(HASH, HASH)
	var found: Array = []
	for cx in range(floori(lo.x / HASH), floori(hi.x / HASH) + 1):
		for cz in range(floori(lo.y / HASH), floori(hi.y / HASH) + 1):
			for v: int in _hash.get(Vector2i(cx, cz), []):
				if only_buildable and not buildable(v):
					continue
				var t := _enter(v, a, b)
				if t >= 0.0:
					found.append([t, v])
	found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt32Array()
	for f: Array in found:
		out.append(int(f[1]))
	return out


func _enter(v: int, a: Vector2, b: Vector2) -> float:
	## Where along a-b (0..1) the segment enters v's convex cell (widened by 2 cm); -1 when it misses the cell.
	var poly: PackedVector2Array = cells[v]
	var n := poly.size()
	if n < 3:
		return -1.0
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in n:
		var p := poly[i]
		var e := poly[(i + 1) % n] - p
		var nrm := Vector2(-e.y, e.x).normalized()          # into the cell (counter-clockwise polygon)
		var dist := (a - p).dot(nrm) + 0.02                 # >= 0: inside this side's half plane
		var slope := d.dot(nrm)
		if absf(slope) < 1e-9:
			if dist < 0.0:
				return -1.0
			continue
		var t := -dist / slope
		if slope > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return -1.0
	return t0


func dual(v: int) -> PackedVector2Array:
	## The cell a block on v fills: the centres of the triangles round v, counter-clockwise (Townscaper's dual grid). Two
	## neighbouring cells share the straight side between the two triangle centres on their common edge.
	var out := PackedVector2Array()
	var rg: PackedInt32Array = rings[v]
	for i in rg.size():
		if rg[i] >= 0:
			out.append(centers[rg[i]])
	return out


func face(v: int, i: int) -> PackedVector2Array:
	## The side of v's cell facing neighbour i: from the centre of the triangle before it to the centre of the triangle after.
	var rg: PackedInt32Array = rings[v]
	var n := rg.size()
	return PackedVector2Array([centers[rg[(i + n - 1) % n]], centers[rg[i]]])


func wedge(v: int, i: int) -> PackedVector2Array:
	## The triangle of v's cell towards neighbour i: v and that side's two ends (a fan, for cells that are not convex).
	var f := face(v, i)
	return PackedVector2Array([verts[v], f[0], f[1]])


func neighbour_towards(v: int, dir: Vector2) -> int:
	var best := -1
	var bd := -INF
	for u in nbrs[v]:
		var d := (verts[u] - verts[v]).normalized().dot(dir.normalized())
		if d > bd:
			bd = d
			best = u
	return best


func index_of(v: int, u: int) -> int:
	var nb: PackedInt32Array = nbrs[v]
	for i in nb.size():
		if nb[i] == u:
			return i
	return -1
