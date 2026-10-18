class_name CSGrid
extends RefCounted
## Castle Scaper Hex: a REGULAR HEX GRID. A perfect triangle lattice cut to a hexagon; a block stands on a lattice point and
## fills that point's dual cell, the centroids of the six triangles round it: a regular hexagon (six equal sides, 120 degree
## corners), pointy-top (a flat side faces east and west). Every inner point has six neighbours, so every cell is a hexagon,
## also along the board's edge, and every cell corner is shared by exactly three cells that are all neighbours of each
## other: two blocks never touch at only a corner. The map's border points cannot be built on (sea only).
##
## (Earlier versions flipped random edges, which made pentagons and heptagons, then relaxed and jittered the lattice to
## look organic; Kevin asked for regular hexagons. The seed is kept for saved towns and does nothing.)

var step := 10.0                    # the lattice step is half of this: 5 m, so a cell has 2.89 m sides and ~21.7 m2
var radius := 10                    # hexagon radius, in `step`s (the lattice has twice as many)
var seed := 1
var verts := PackedVector2Array()   # lattice positions (m, x / z)
var border := PackedByteArray()     # 1 on the map's edge (pinned, not buildable)
var tris := PackedInt32Array()      # 3 point ids per triangle, counter-clockwise in (x, z)
var centers := PackedVector2Array() # per triangle (its centroid: a corner of the cells round its points)
var nbrs: Array = []                # per point: PackedInt32Array of neighbours, counter-clockwise
var rings: Array = []               # per point: PackedInt32Array, triangle i lies between nbrs[i] and nbrs[i+1] (-1: outside)
var _mid := {}                      # edge key -> midpoint
var _hash := {}                     # Vector2i (cells of `step`) -> [point ids]


func edge_key(a: int, b: int) -> int:
	return mini(a, b) * 1048576 + maxi(a, b)


func mid(a: int, b: int) -> Vector2:
	return _mid.get(edge_key(a, b), (verts[a] + verts[b]) * 0.5)


func generate(p_seed: int = 1, p_radius: int = 10, p_step: float = 10.0) -> void:
	seed = p_seed
	radius = p_radius
	step = p_step
	var r := radius * 2                       # lattice step = step / 2
	var s := step * 0.5
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var inside := func(a: int, b: int) -> bool:
		return absi(a) <= r and absi(b) <= r and absi(a + b) <= r
	# the triangle lattice cut to a hexagon
	var vid := {}
	var nv := 0
	verts.resize(0)
	border.resize(0)
	for a in range(-r, r + 1):
		for b in range(-r, r + 1):
			if inside.call(a, b):
				vid[Vector2i(a, b)] = nv
				nv += 1
				verts.append((e1 * float(a) + e2 * float(b)) * s)
				border.append(1 if (absi(a) == r or absi(b) == r or absi(a + b) == r) else 0)
	var qs := PackedInt32Array()
	for a in range(-r, r + 1):
		for b in range(-r, r + 1):
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1):
				qs.append_array([vid[Vector2i(a, b)], vid[Vector2i(a + 1, b)], vid[Vector2i(a, b + 1)]])
			if inside.call(a + 1, b) and inside.call(a + 1, b + 1) and inside.call(a, b + 1):
				qs.append_array([vid[Vector2i(a + 1, b)], vid[Vector2i(a + 1, b + 1)], vid[Vector2i(a, b + 1)]])
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
		var c := Vector2.ZERO
		for k in 3:
			c += verts[tris[q * 3 + k]]
		centers[q] = c / 3.0
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
		var hk := Vector2i(floori(verts[v].x / step), floori(verts[v].y / step))
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
	var hk := Vector2i(floori(p.x / step), floori(p.y / step))
	var best := -1
	var bd := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for v: int in _hash.get(Vector2i(hk.x + dx, hk.y + dz), []):
				if only_buildable and not buildable(v):
					continue
				var d := verts[v].distance_squared_to(p)
				if d < bd:
					bd = d
					best = v
	return best


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
