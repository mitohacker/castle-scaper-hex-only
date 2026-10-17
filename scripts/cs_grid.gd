class_name CSGrid
extends RefCounted
## Townscaper's grid on a hexagonal map (read from Townscaper's own GridGenerator with REA + Ghidra, see
## C:\Dev\Prototypes\townscaper-re\notes\grid.md): a triangle lattice cut to a hexagon, random neighbouring
## triangles merged into quads, every face subdivided once (a quad into 4, a triangle into 3 quads; vertices keyed by
## integers, never merged by distance), then every quad pulled towards the best-fitting square round its own centre,
## the pulls summed per vertex and applied x0.4, 255 times. Vertices where 3, 5 or 6 quads meet give the hand-laid look.
##
## A block stands on a grid VERTEX (Townscaper's voxels live on corners) and fills that vertex's dual cell: the
## edge midpoints and quad centres round it. The map's border vertices are pinned and cannot be built on.

const RELAX_STEPS := 255
const PULL := 0.4

var step := 10.0                    # triangle side (m); one subdivision makes quads of about half that
var radius := 10                    # hexagon radius in triangles
var seed := 1
var verts := PackedVector2Array()   # relaxed positions (m, x / z)
var rest := PackedVector2Array()    # before relaxation
var border := PackedByteArray()     # 1 on the map's edge (pinned, not buildable)
var quads := PackedInt32Array()     # 4 per quad, counter-clockwise in (x, z)
var centers := PackedVector2Array() # per quad
var nbrs: Array = []                # per vertex: PackedInt32Array of neighbours, counter-clockwise
var rings: Array = []               # per vertex: PackedInt32Array, quad i lies between nbrs[i] and nbrs[i+1] (-1: outside)
var _mid := {}                      # edge key -> midpoint
var _hash := {}                     # Vector2i (cells of `step`) -> [vertex ids]


static func _key(k: Vector2i) -> int:
	return (k.x + 4096) * 16384 + (k.y + 4096)


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
	var r := radius
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var inside := func(a: int, b: int) -> bool:
		return absi(a) <= r and absi(b) <= r and absi(a + b) <= r
	# 1. the triangle lattice in twelfths of a lattice step (midpoints and centres stay integers)
	var tris: Array = []
	for a in range(-r, r + 1):
		for b in range(-r, r + 1):
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1):
				tris.append([Vector2i(a, b) * 12, Vector2i(a + 1, b) * 12, Vector2i(a, b + 1) * 12])
			if inside.call(a + 1, b) and inside.call(a + 1, b + 1) and inside.call(a, b + 1):
				tris.append([Vector2i(a + 1, b) * 12, Vector2i(a + 1, b + 1) * 12, Vector2i(a, b + 1) * 12])
	var edges := {}
	for t in tris.size():
		for k in 3:
			var ka := _key(tris[t][k])
			var kb := _key(tris[t][(k + 1) % 3])
			var ek: int = mini(ka, kb) * 268435456 + maxi(ka, kb)
			if not edges.has(ek):
				edges[ek] = []
			(edges[ek] as Array).append(t)
	# 2. random pairwise merges (Townscaper: until no neighbouring pair is left)
	var order: Array = range(tris.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var merged := PackedByteArray()
	merged.resize(tris.size())
	var polys: Array = []
	for t: int in order:
		if merged[t]:
			continue
		var tr: Array = tris[t]
		var cands: Array = []
		for k in 3:
			var ka := _key(tr[k])
			var kb := _key(tr[(k + 1) % 3])
			for u: int in edges[mini(ka, kb) * 268435456 + maxi(ka, kb)]:
				if u != t and not merged[u]:
					cands.append([u, k])
		if cands.is_empty():
			continue
		var pick: Array = cands[rng.randi_range(0, cands.size() - 1)]
		var ub: Array = tris[pick[0]]
		var k0: int = pick[1]
		var a0: Vector2i = tr[k0]
		var b0: Vector2i = tr[(k0 + 1) % 3]
		var c0: Vector2i = tr[(k0 + 2) % 3]
		var d0: Vector2i = ub[0]
		for q: Vector2i in ub:
			if q != a0 and q != b0:
				d0 = q
		polys.append([a0, d0, b0, c0])         # (a, b, c) + (b, a, d) -> (a, d, b, c), counter-clockwise
		merged[t] = 1
		merged[pick[0]] = 1
	for t in tris.size():
		if not merged[t]:
			polys.append(tris[t])
	# 3. one subdivision
	var vid := {}
	var keys: Array[Vector2i] = []
	var get_v := func(k: Vector2i) -> int:
		var kk := _key(k)
		if vid.has(kk):
			return vid[kk]
		vid[kk] = keys.size()
		keys.append(k)
		return keys.size() - 1
	var qs := PackedInt32Array()
	for poly: Array in polys:
		var n := poly.size()
		var sum := Vector2i.ZERO
		for q: Vector2i in poly:
			sum += q
		var e: int = get_v.call(sum / n)
		for k in n:
			var a: Vector2i = poly[k]
			var nx: Vector2i = poly[(k + 1) % n]
			var pv: Vector2i = poly[(k + n - 1) % n]
			qs.append(get_v.call(a))
			qs.append(get_v.call((a + nx) / 2))
			qs.append(e)
			qs.append(get_v.call((a + pv) / 2))
	quads = qs
	var nv := keys.size()
	rest.resize(nv)
	border.resize(nv)
	border.fill(0)
	for i in nv:
		var k := keys[i]
		rest[i] = (e1 * float(k.x) + e2 * float(k.y)) * step / 12.0
		# on the hexagon's edge: one of the three axial coordinates at +-r (in twelfths)
		var kz := -k.x - k.y
		if absi(k.x) == 12 * r or absi(k.y) == 12 * r or absi(kz) == 12 * r:
			border[i] = 1
	# 4. relaxation: squares of the mean quad area, border pinned
	var area := 0.0
	var nq := quads.size() / 4
	for q in nq:
		var a := rest[quads[q * 4]]
		var b := rest[quads[q * 4 + 1]]
		var c := rest[quads[q * 4 + 2]]
		var d := rest[quads[q * 4 + 3]]
		area += absf((c - a).cross(d - b)) * 0.5
	var side := sqrt(area / float(nq))
	var diag := side * sqrt(2.0) * 0.5
	var p := rest.duplicate()
	var dsum := PackedVector2Array()
	dsum.resize(nv)
	for _s in RELAX_STEPS:
		dsum.fill(Vector2.ZERO)
		for q in nq:
			var i0 := quads[q * 4]
			var i1 := quads[q * 4 + 1]
			var i2 := quads[q * 4 + 2]
			var i3 := quads[q * 4 + 3]
			var a := p[i0]
			var b := p[i1]
			var c := p[i2]
			var d := p[i3]
			var m := (a + b + c + d) * 0.25
			var d1 := b - m
			var d3 := d - m
			var v := (a - m) + Vector2(d1.y, -d1.x) - (c - m) + Vector2(-d3.y, d3.x)
			if v.length_squared() < 1e-12:
				continue
			var rr := v.normalized() * diag
			dsum[i0] += m + rr - a
			dsum[i1] += m + Vector2(-rr.y, rr.x) - b
			dsum[i2] += m - rr - c
			dsum[i3] += m + Vector2(rr.y, -rr.x) - d
		for i in nv:
			if not border[i]:
				p[i] += dsum[i] * PULL
	verts = p
	_build_topology()


func _build_topology() -> void:
	var nv := verts.size()
	var nq := quads.size() / 4
	centers.resize(nq)
	_mid.clear()
	var around: Array = []                    # per vertex: [quad, prev neighbour, next neighbour]
	around.resize(nv)
	for i in nv:
		around[i] = []
	for q in nq:
		var c := Vector2.ZERO
		for k in 4:
			c += verts[quads[q * 4 + k]]
		centers[q] = c * 0.25
		for k in 4:
			var v := quads[q * 4 + k]
			var nx := quads[q * 4 + (k + 1) % 4]
			var pv := quads[q * 4 + (k + 3) % 4]
			(around[v] as Array).append([q, nx, pv])
			var ek := edge_key(v, nx)
			if not _mid.has(ek):
				_mid[ek] = (verts[v] + verts[nx]) * 0.5
	nbrs.resize(nv)
	rings.resize(nv)
	_hash.clear()
	for v in nv:
		var items: Array = around[v]
		# order the quads round v counter-clockwise: quad (v, nx, ., pv) spans nx -> pv going counter-clockwise
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
	## The cell a block on v fills: the centres of the quads round v, counter-clockwise (Townscaper's dual grid). Two
	## neighbouring cells share the straight side between the two quad centres on their common edge.
	var out := PackedVector2Array()
	var rg: PackedInt32Array = rings[v]
	for i in rg.size():
		if rg[i] >= 0:
			out.append(centers[rg[i]])
	return out


func face(v: int, i: int) -> PackedVector2Array:
	## The side of v's cell facing neighbour i: from the centre of the quad before it to the centre of the quad after.
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
