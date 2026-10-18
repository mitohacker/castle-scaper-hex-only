class_name CSGrid
extends RefCounted
## Castle Scaper Hex: the ORGANIC HEX GRID. A triangle lattice cut to a hexagon (every inner point has six neighbours, so
## EVERY cell is a hexagon), every triangle pulled towards the best-fitting equilateral triangle round its own centre
## (Townscaper's summed-pull relaxation, averaged per point), then every inner point nudged by a seeded random step so the
## hexagons come out irregular and organic. Every cell corner is shared by exactly three cells, all neighbours of each
## other, so two blocks never touch at only a corner.
##
## A block stands on a grid POINT (Townscaper's voxels live on corners) and fills that point's dual cell: the centroids of
## the triangles round it. The map's border points are pinned and cannot be built on.

const RELAX_STEPS := 255
const HEX_PULL := 0.8               # the averaged pull per step
const JITTER := 0.25                # how far an inner point wanders from the regular lattice, in lattice steps (0 = a perfect hex grid)

static var default_jitter := JITTER  # --cs-jitter=0.25 (0 .. 0.35 and the cells stay convex)
var jitter := default_jitter         # tools/grid_probe.gd sweeps this knob
var circ_blend := 0.0               # a cell corner from the triangle's centroid (0) towards its circumcentre (1)

var step := 10.0                    # lattice step is half of this (m); cells are about 22 m2
var radius := 10                    # hexagon radius, in `step`s (the lattice has twice as many)
var seed := 1
var verts := PackedVector2Array()   # relaxed positions (m, x / z)
var rest := PackedVector2Array()    # before relaxation
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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := radius * 2                       # lattice step = step / 2: cells ~22 m2
	var s := step * 0.5
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var inside := func(a: int, b: int) -> bool:
		return absi(a) <= r and absi(b) <= r and absi(a + b) <= r
	# 1. the triangle lattice cut to a hexagon
	var vid := {}
	var nv := 0
	rest.resize(0)
	border.resize(0)
	for a in range(-r, r + 1):
		for b in range(-r, r + 1):
			if inside.call(a, b):
				vid[Vector2i(a, b)] = nv
				nv += 1
				rest.append((e1 * float(a) + e2 * float(b)) * s)
				border.append(1 if (absi(a) == r or absi(b) == r or absi(a + b) == r) else 0)
	var tri: Array = []                       # [a, b, c] counter-clockwise
	for a in range(-r, r + 1):
		for b in range(-r, r + 1):
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1):
				tri.append([vid[Vector2i(a, b)], vid[Vector2i(a + 1, b)], vid[Vector2i(a, b + 1)]])
			if inside.call(a + 1, b) and inside.call(a + 1, b + 1) and inside.call(a, b + 1):
				tri.append([vid[Vector2i(a + 1, b)], vid[Vector2i(a + 1, b + 1)], vid[Vector2i(a, b + 1)]])
	# 2. every inner point keeps its six triangles, so every cell is a hexagon (no edge flips: they made pentagons and heptagons)
	var qs := PackedInt32Array()
	for tr: Array in tri:
		qs.append(tr[0])
		qs.append(tr[1])
		qs.append(tr[2])
	tris = qs
	# 3. relaxation: equilateral triangles of the mean area, fitted round each triangle's centre, border pinned
	var nt := tri.size()
	var area := 0.0
	for q in nt:
		area += absf((rest[tris[q * 3 + 1]] - rest[tris[q * 3]]).cross(rest[tris[q * 3 + 2]] - rest[tris[q * 3]])) * 0.5
	var side := sqrt(area / float(nt) * 4.0 / sqrt(3.0))
	var circ := side / sqrt(3.0)
	var c120 := cos(TAU / 3.0)
	var s120 := sin(TAU / 3.0)
	var p := rest.duplicate()
	var dsum := PackedVector2Array()
	dsum.resize(nv)
	# six to seven triangles pull each point: Townscaper's summed x0.4 would be a gain of 2.4 and oscillate, so the
	# pulls are averaged per point instead (gain HEX_PULL)
	var inv := PackedFloat32Array()
	inv.resize(nv)
	for q in nt:
		for k in 3:
			inv[tris[q * 3 + k]] += 1.0
	for i in nv:
		inv[i] = HEX_PULL / maxf(inv[i], 1.0)
	for _s in RELAX_STEPS:
		dsum.fill(Vector2.ZERO)
		for q in nt:
			var i0 := tris[q * 3]
			var i1 := tris[q * 3 + 1]
			var i2 := tris[q * 3 + 2]
			var a := p[i0]
			var b := p[i1]
			var c := p[i2]
			var m := (a + b + c) / 3.0
			var d1 := b - m
			var d2 := c - m
			# rotate b's offset back by 120 deg and c's by 240 deg into a's frame and sum
			var v := (a - m) + Vector2(d1.x * c120 + d1.y * s120, -d1.x * s120 + d1.y * c120) \
				+ Vector2(d2.x * c120 - d2.y * s120, d2.x * s120 + d2.y * c120)
			if v.length_squared() < 1e-12:
				continue
			var rr := v.normalized() * circ
			var rb := Vector2(rr.x * c120 - rr.y * s120, rr.x * s120 + rr.y * c120)
			var rc := Vector2(rb.x * c120 - rb.y * s120, rb.x * s120 + rb.y * c120)
			dsum[i0] += m + rr - a
			dsum[i1] += m + rb - b
			dsum[i2] += m + rc - c
		for i in nv:
			if not border[i]:
				p[i] += dsum[i] * inv[i]
	# 4. the organic part: every inner point is moved a seeded random step inside a disc of `jitter` lattice steps. The
	# topology stays a hexagon everywhere; only the shapes warp (the border stays pinned).
	if jitter > 0.0:
		var reach := jitter * s
		for i in nv:
			if border[i]:
				continue
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * reach
			p[i] += Vector2(cos(ang), sin(ang)) * rad
	verts = p
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
		if circ_blend > 0.0:
			centers[q] = centers[q].lerp(_circumcentre(verts[tris[q * 3]], verts[tris[q * 3 + 1]], verts[tris[q * 3 + 2]], centers[q]), circ_blend)
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


static func _circumcentre(a: Vector2, b: Vector2, c: Vector2, fallback: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-9:
		return fallback
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


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
