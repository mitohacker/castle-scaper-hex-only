class_name CFTri
extends RefCounted
## Triangulates a flat region (an outer loop and any holes) by ear clipping. Only the loop's own
## vertices are used (collinear ones too), so a triangulated ledge shares every vertex with the walls
## round it: no T-junctions.

const EPS_CROSS := 2e-6      # twice the area below which an ear is degenerate (m^2); Vector2 is 32-bit, keep clear of its noise
static var fails := 0         # polygons the clipper could not finish cleanly (read by the audit)


static func area(poly: PackedVector2Array) -> float:
	## Signed area: positive when the loop runs counter-clockwise in (x, y).
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func reversed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(poly[i])
	return out


static func triangulate(outer: PackedVector2Array, holes: Array = []) -> PackedVector2Array:
	## Counter-clockwise triangles (three points each) covering the outer loop minus the holes.
	if holes.is_empty() and outer.size() == 4 and area(outer) >= 0.0:
		var q := _quad(outer)
		if not q.is_empty():
			return q
	return _earclip(merge_holes(outer, holes))


static func _quad(o: PackedVector2Array) -> PackedVector2Array:
	## What _earclip makes of a counter-clockwise loop of four points, without its set-up: the first ear it meets (a corner
	## the fourth point is not inside), then what is left. Empty when it meets none (the general code then takes over).
	var out := PackedVector2Array()
	for i in 4:
		var ia := (i + 3) % 4
		var ic := (i + 1) % 4
		var a: Vector2 = o[ia]
		var b: Vector2 = o[i]
		var c: Vector2 = o[ic]
		if (b - a).cross(c - b) <= EPS_CROSS:
			continue
		# the only other point
		var p: Vector2 = o[(i + 2) % 4]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		var inside_box := floori(p.x / GRID) >= floori(lo.x / GRID) and floori(p.x / GRID) <= floori(hi.x / GRID) and floori(p.y / GRID) >= floori(lo.y / GRID) and floori(p.y / GRID) <= floori(hi.y / GRID)
		if inside_box and p.distance_squared_to(a) > 1e-10 and p.distance_squared_to(b) > 1e-10 and p.distance_squared_to(c) > 1e-10:
			var d1 := (b - a).cross(p - a)
			var d2 := (c - b).cross(p - b)
			var d3 := (a - c).cross(p - c)
			if d1 >= -2e-6 and d2 >= -2e-6 and d3 >= -2e-6:
				continue
		out.append(a)
		out.append(b)
		out.append(c)
		# the clipped corner is gone; what is left is a, c and the fourth point
		var pd: Vector2 = o[(i + 2) % 4]
		if (c - a).cross(pd - c) > EPS_CROSS:
			out.append(a)
			out.append(c)
			out.append(pd)
		return out
	return out


static func merge_holes(outer: PackedVector2Array, holes: Array) -> Array:
	## One weakly simple loop: the outer loop with every hole joined to it by a doubled bridge.
	var o := outer
	if area(o) < 0.0:
		o = reversed(o)
	var poly: Array = Array(o)
	var hs: Array = []
	for h in holes:
		var hh: PackedVector2Array = h
		if hh.size() < 3:
			continue
		if area(hh) > 0.0:
			hh = reversed(hh)
		hs.append(hh)
	hs.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return _max_x(a) > _max_x(b))
	for hi in hs.size():
		var h: PackedVector2Array = hs[hi]
		var mi := 0
		for i in h.size():
			if h[i].x > h[mi].x:
				mi = i
		var m := h[mi]
		var chosen := -1
		var dists := PackedFloat32Array()
		dists.resize(poly.size())
		for i in poly.size():
			dists[i] = (poly[i] as Vector2).distance_squared_to(m)
		var first := -1
		for _try in poly.size():
			var bi := -1
			var bd := INF
			for i in dists.size():
				if dists[i] < bd:
					bd = dists[i]
					bi = i
			if bi < 0:
				break
			if first < 0:
				first = bi
			dists[bi] = INF
			if _bridge_ok(poly, bi, m, h, hs, hi + 1):
				chosen = bi
				break
		if chosen < 0:
			chosen = maxi(first, 0)
			fails += 1
		var mid: Array = []
		for k in range(h.size() + 1):
			mid.append(h[(mi + k) % h.size()])
		poly = poly.slice(0, chosen + 1) + mid + poly.slice(chosen)
	return poly


static func _max_x(poly: PackedVector2Array) -> float:
	var m := -INF
	for p in poly:
		m = maxf(m, p.x)
	return m


static func _bridge_ok(poly: Array, i: int, m: Vector2, h: PackedVector2Array, hs: Array, from_hole: int) -> bool:
	var p: Vector2 = poly[i]
	if p.distance_squared_to(m) < 1e-10:
		return false
	var n := poly.size()
	if not _in_cone(poly[(i - 1 + n) % n], p, poly[(i + 1) % n], m):
		return false
	var x0 := minf(p.x, m.x) - 1e-6
	var x1 := maxf(p.x, m.x) + 1e-6
	var y0 := minf(p.y, m.y) - 1e-6
	var y1 := maxf(p.y, m.y) + 1e-6
	for j in n:
		var a: Vector2 = poly[j]
		var b: Vector2 = poly[(j + 1) % n]
		if (a.x < x0 and b.x < x0) or (a.x > x1 and b.x > x1) or (a.y < y0 and b.y < y0) or (a.y > y1 and b.y > y1):
			continue
		if _seg_blocks(p, m, a, b):
			return false
	for j in h.size():
		if _seg_blocks(p, m, h[j], h[(j + 1) % h.size()]):
			return false
	for k in range(from_hole, hs.size()):
		var oh: PackedVector2Array = hs[k]
		for j in oh.size():
			var a2 := oh[j]
			var b2 := oh[(j + 1) % oh.size()]
			if (a2.x < x0 and b2.x < x0) or (a2.x > x1 and b2.x > x1) or (a2.y < y0 and b2.y < y0) or (a2.y > y1 and b2.y > y1):
				continue
			if _seg_blocks(p, m, a2, b2):
				return false
	return true


static func _in_cone(prev: Vector2, p: Vector2, next: Vector2, m: Vector2) -> bool:
	## Is m inside the interior wedge at p of a counter-clockwise polygon (from the edge to next round to the edge to prev)?
	var u := next - p
	var v := prev - p
	var x := m - p
	var av := fposmod(atan2(u.cross(v), u.dot(v)), TAU)
	var ax := fposmod(atan2(u.cross(x), u.dot(x)), TAU)
	if av < 1e-9:
		av = TAU
	return ax > 1e-9 and ax < av - 1e-9


static func _seg_blocks(p: Vector2, m: Vector2, a: Vector2, b: Vector2) -> bool:
	## Does edge a-b cut the segment p-m anywhere but at p or m themselves?
	var at_p := a.distance_squared_to(p) < 1e-10 or b.distance_squared_to(p) < 1e-10
	var at_m := a.distance_squared_to(m) < 1e-10 or b.distance_squared_to(m) < 1e-10
	if at_p or at_m:
		return false
	var d := m - p
	var e := b - a
	var o1 := d.cross(a - p)
	var o2 := d.cross(b - p)
	var o3 := e.cross(p - a)
	var o4 := e.cross(m - a)
	var tol := 1e-6
	if ((o1 > tol and o2 < -tol) or (o1 < -tol and o2 > tol)) and ((o3 > tol and o4 < -tol) or (o3 < -tol and o4 > tol)):
		return true
	# an end of one lying on the other
	if absf(o1) <= tol and _on_seg(p, m, a):
		return true
	if absf(o2) <= tol and _on_seg(p, m, b):
		return true
	if absf(o3) <= tol and _on_seg(a, b, p):
		return true
	if absf(o4) <= tol and _on_seg(a, b, m):
		return true
	return false


static func _on_seg(a: Vector2, b: Vector2, q: Vector2) -> bool:
	var ab := b - a
	var t := (q - a).dot(ab) / maxf(ab.length_squared(), 1e-12)
	return t > 1e-6 and t < 1.0 - 1e-6


const GRID := 0.4
const SMALL := 24        # loops up to this many points are tested against every point instead of through the grid


static func _earclip(poly: Array) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	if n < 3:
		return out
	var prv := PackedInt32Array()
	var nxt := PackedInt32Array()
	var alive := PackedByteArray()
	prv.resize(n)
	nxt.resize(n)
	alive.resize(n)
	var grid := {}
	var small := n <= SMALL
	for i in n:
		prv[i] = (i - 1 + n) % n
		nxt[i] = (i + 1) % n
		alive[i] = 1
		if small:
			continue
		var p: Vector2 = poly[i]
		var key := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var remaining := n
	var cur := 0
	var guard := 0
	while remaining > 3 and guard < n * 4 + 20:
		guard += 1
		var found := false
		var i := cur
		for _step in remaining:
			if (_is_ear_small(poly, n, prv, nxt, alive, i) if small else _is_ear(poly, prv, nxt, alive, grid, i)):
				var a := prv[i]
				var c := nxt[i]
				out.append(poly[a])
				out.append(poly[i])
				out.append(poly[c])
				nxt[a] = c
				prv[c] = a
				alive[i] = 0
				remaining -= 1
				cur = a
				found = true
				break
			i = nxt[i]
		if found:
			continue
		# no clean ear: clip the most convex vertex anyway, or drop a flat one
		fails += 1
		var best := -1
		var best_cr := EPS_CROSS
		var j := cur
		for _step in remaining:
			var pa: Vector2 = poly[prv[j]]
			var pb: Vector2 = poly[j]
			var pc: Vector2 = poly[nxt[j]]
			var cr := (pb - pa).cross(pc - pb)
			if cr > best_cr:
				best_cr = cr
				best = j
			j = nxt[j]
		if best < 0:
			best = cur
			var a0 := prv[best]
			var c0 := nxt[best]
			nxt[a0] = c0
			prv[c0] = a0
			alive[best] = 0
			remaining -= 1
			cur = a0
			continue
		var a1 := prv[best]
		var c1 := nxt[best]
		out.append(poly[a1])
		out.append(poly[best])
		out.append(poly[c1])
		nxt[a1] = c1
		prv[c1] = a1
		alive[best] = 0
		remaining -= 1
		cur = a1
	if remaining == 3:
		var a2 := cur
		var b2 := nxt[a2]
		var c2 := nxt[b2]
		var pa2: Vector2 = poly[a2]
		var pb2: Vector2 = poly[b2]
		var pc2: Vector2 = poly[c2]
		if (pb2 - pa2).cross(pc2 - pb2) > EPS_CROSS:
			out.append(pa2)
			out.append(pb2)
			out.append(pc2)
	return out


static func _is_ear_small(poly: Array, n: int, prv: PackedInt32Array, nxt: PackedInt32Array, alive: PackedByteArray, i: int) -> bool:
	## _is_ear for a short loop: every point is looked at, but only those the grid would have shown (the cells under the triangle's box).
	var ia := prv[i]
	var ic := nxt[i]
	var a: Vector2 = poly[ia]
	var b: Vector2 = poly[i]
	var c: Vector2 = poly[ic]
	if (b - a).cross(c - b) <= EPS_CROSS:
		return false
	var lo := a.min(b).min(c)
	var hi := a.max(b).max(c)
	var cx0 := floori(lo.x / GRID)
	var cx1 := floori(hi.x / GRID)
	var cy0 := floori(lo.y / GRID)
	var cy1 := floori(hi.y / GRID)
	for k in n:
		if alive[k] == 0 or k == ia or k == i or k == ic:
			continue
		var p: Vector2 = poly[k]
		var kx := floori(p.x / GRID)
		if kx < cx0 or kx > cx1:
			continue
		var ky := floori(p.y / GRID)
		if ky < cy0 or ky > cy1:
			continue
		# a duplicate of a corner (keyhole bridges) is not a blocker
		if p.distance_squared_to(a) > 1e-10 and p.distance_squared_to(b) > 1e-10 and p.distance_squared_to(c) > 1e-10:
			var d1 := (b - a).cross(p - a)
			var d2 := (c - b).cross(p - b)
			var d3 := (a - c).cross(p - c)
			if d1 >= -2e-6 and d2 >= -2e-6 and d3 >= -2e-6:
				return false
	return true


static func _is_ear(poly: Array, prv: PackedInt32Array, nxt: PackedInt32Array, alive: PackedByteArray, grid: Dictionary, i: int) -> bool:
	var ia := prv[i]
	var ic := nxt[i]
	var a: Vector2 = poly[ia]
	var b: Vector2 = poly[i]
	var c: Vector2 = poly[ic]
	if (b - a).cross(c - b) <= EPS_CROSS:
		return false
	var lo := a.min(b).min(c)
	var hi := a.max(b).max(c)
	for cx in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
		for cy in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
			var cell = grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for k: int in cell:
				if alive[k] == 0 or k == ia or k == i or k == ic:
					continue
				var p: Vector2 = poly[k]
				# a duplicate of a corner (keyhole bridges) is not a blocker
				if p.distance_squared_to(a) > 1e-10 and p.distance_squared_to(b) > 1e-10 and p.distance_squared_to(c) > 1e-10:
					var d1 := (b - a).cross(p - a)
					var d2 := (c - b).cross(p - b)
					var d3 := (a - c).cross(p - c)
					if d1 >= -2e-6 and d2 >= -2e-6 and d3 >= -2e-6:
						return false
	return true
