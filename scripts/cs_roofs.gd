class_name CSRoofs
extends RefCounted
## Roofs and caps for the building styles (CSStyle), made as closed shells that sit on a block's walls instead of being welded into the plan.
## A shell is the whole "hat": the roof surface, the fascia round its eaves, the soffit under the overhang, and a hidden skirt and floor that
## reach 12 cm down INSIDE the wall (5 cm in from its face), so the hat is a closed solid on its own: every edge is shared by two of its own
## triangles, none lies on the walls' edges, and the weld audit (CFAudit) stays clean however the hats and walls are combined. Where two hats of
## neighbouring blocks meet, their edges stay 2 mm apart (a hat's edge that touches a neighbour is inset by INSET), so no two shells share an
## edge. All positions go through one vertex table (a point seen twice is one point), so the shared edges of a shell are exact.
##
## Two generators:
##   ridge()    gable and hip roofs over a convex outline: the roof is the lowest of one plane per eave edge (a hip, rising `slope` per metre from
##              that eave), edges flagged as gables have no plane and a vertical gable wall instead; per-edge overhangs.
##   pyramid()  radial roofs: rings from the eaves in to an apex (or a flat inner ring for a tier's pent roof), each ring at a height of a profile
##              curve; the eaves' corners can turn up (Chinese), the profile can bulge (onion domes) and the tip can bend (crooked spires).
## Both return a record with `height_at(p)` data for the props that stand on the roof.

const MERGE := 1e-5
const CELL := 5e-5               # the vertex table's cell: two points less than 3e-5 apart are one vertex (searching the cells next to it)
const INSET := 0.003            # an eave edge that touches a neighbour's is pulled in by this much
const WALL_IN := 0.05           # the hat's skirt stands this far inside the wall's face
const DEPTH := 0.12             # ... and reaches this far below the wall's top
const NO_EDGE := 100.0
## How a group's triangles are turned outward: by the point inside the shell (convex-ish solids), or by what the surface is: a roof faces up,
## a soffit or floor faces down, a fascia, gable or skirt faces away from the shell's axis (a concave roof's rim defeats the point test).
const O_CENTROID := 0
const O_UP := 1
const O_DOWN := 2
const O_OUT := 3
const O_IN := 4                 # a vertical face that looks toward the shell's axis (the inside of a parapet)
const O_FLIP := 5               # always turned over: triangles written (a, b, c) in ring order, which face down, are turned up (no heuristic on slivers)


class Shell:
	extends RefCounted
	var tris: Array = []        # [a, b, c, ua, ub, uc, group, sg] (positions Vector3, uvs Vector2)
	var groups: Array = []      # per group: [zone, flags]
	var count := 0
	var _sg := 7000

	func new_sg() -> int:
		_sg += 1
		return _sg

	func group(zone: int, flags: int = 0, orient: int = 0) -> int:
		groups.append([zone, flags, orient])
		return groups.size() - 1

	func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, g: int, sg: int = -1) -> void:
		if (b - a).cross(c - a).length_squared() < 1e-12:
			return
		tris.append([a, b, c, ua, ub, uc, g, sg])
		count += 1

	func poly(pts: Array, g: int, uv_fn: Callable, sg: int = -1) -> void:
		## A convex planar polygon (Vector3s, any winding), triangulated by the fan with the best-shaped triangles; uv_fn(p) -> Vector2.
		var n := pts.size()
		if n < 3:
			return
		var best := 0
		var best_min := -1.0
		for o in n:
			var mn := INF
			for i in range(1, n - 1):
				var a: Vector3 = pts[o]
				var b: Vector3 = pts[(o + i) % n]
				var c: Vector3 = pts[(o + i + 1) % n]
				mn = minf(mn, (b - a).cross(c - a).length())
			if mn > best_min:
				best_min = mn
				best = o
		for i in range(1, n - 1):
			var a: Vector3 = pts[best]
			var b: Vector3 = pts[(best + i) % n]
			var c: Vector3 = pts[(best + i + 1) % n]
			tri(a, b, c, uv_fn.call(a), uv_fn.call(b), uv_fn.call(c), g, sg)

	func emit(mesh: CFMesh, inside: Vector3, seed: float, owner: int, anchor: Vector3, label: String) -> void:
		## One vertex table for every position (bit-identical shared points), outward winding by the point `inside`, smooth normals inside
		## a smoothing group (sg >= 0), flat ones for the rest.
		var rep := {}                   # cell -> the points of that cell
		var snap := func(p: Vector3) -> Vector3:
			## the first point seen within 3e-5 m of p (searching the 27 cells round it, so a point on a cell boundary still finds its twin)
			var kx := floori(p.x / CSRoofs.CELL)
			var ky := floori(p.y / CSRoofs.CELL)
			var kz := floori(p.z / CSRoofs.CELL)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					for dz in range(-1, 2):
						var lst = rep.get(Vector3i(kx + dx, ky + dy, kz + dz))
						if lst != null:
							for q: Vector3 in lst:
								if q.distance_squared_to(p) < 9e-10:
									return q
			var key := Vector3i(kx, ky, kz)
			if not rep.has(key):
				rep[key] = []
			(rep[key] as Array).append(p)
			return p
		var fixed: Array = []
		for t: Array in tris:
			var pts: Array = []
			for k in 3:
				pts.append(snap.call(t[k] as Vector3))
			var gn := ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3))
			var cen := ((pts[0] as Vector3) + (pts[1] as Vector3) + (pts[2] as Vector3)) / 3.0
			var mode: int = int((groups[int(t[6])] as Array)[2])
			var flip := false
			match mode:
				1:
					flip = gn.y < 0.0
				2:
					flip = gn.y > 0.0
				3:
					var hv := Vector2(cen.x - inside.x, cen.z - inside.z)
					var gh := Vector2(gn.x, gn.z)
					flip = gh.dot(hv) < 0.0 if gh.length_squared() > 1e-12 else gn.dot(cen - inside) < 0.0
				5:
					flip = true
				4:
					var hv2 := Vector2(cen.x - inside.x, cen.z - inside.z)
					var gh2 := Vector2(gn.x, gn.z)
					flip = gh2.dot(hv2) > 0.0 if gh2.length_squared() > 1e-12 else gn.dot(cen - inside) > 0.0
				_:
					flip = gn.dot(cen - inside) < 0.0
			var rec := [pts[0], pts[1], pts[2], t[3], t[4], t[5], t[6], t[7], gn.normalized()]
			if flip:
				rec = [pts[0], pts[2], pts[1], t[3], t[5], t[4], t[6], t[7], -gn.normalized()]
			fixed.append(rec)
		var acc := {}                  # [sg, key] -> summed area-weighted normal
		for r: Array in fixed:
			var sg: int = r[7]
			if sg < 0:
				continue
			var a: Vector3 = r[0]
			var b: Vector3 = r[1]
			var c: Vector3 = r[2]
			var w := (b - a).cross(c - a)           # (length = twice the area), the face's normal side after the winding fix
			if w.dot(r[8]) < 0.0:
				w = -w
			for p: Vector3 in [a, b, c]:
				var k2 := Vector4i(sg, roundi(p.x / CSRoofs.MERGE), roundi(p.y / CSRoofs.MERGE), roundi(p.z / CSRoofs.MERGE))
				acc[k2] = Vector3(acc.get(k2, Vector3.ZERO)) + w
		var e := Vector4(CSRoofs.NO_EDGE, CSRoofs.NO_EDGE, CSRoofs.NO_EDGE, CSRoofs.NO_EDGE)
		var zone_save := mesh.zone
		var flags_save := mesh.flags
		for r: Array in fixed:
			var g: Array = groups[int(r[6])]
			mesh.begin(int(g[0]), seed, int(g[1]), owner, anchor, label)
			var a: Vector3 = r[0]
			var b: Vector3 = r[1]
			var c: Vector3 = r[2]
			var fn: Vector3 = r[8]
			var nrm: Array = [fn, fn, fn]
			var sg2: int = r[7]
			if sg2 >= 0:
				var ps: Array = [a, b, c]
				for k in 3:
					var p2: Vector3 = ps[k]
					var kk := Vector4i(sg2, roundi(p2.x / CSRoofs.MERGE), roundi(p2.y / CSRoofs.MERGE), roundi(p2.z / CSRoofs.MERGE))
					var s: Vector3 = acc.get(kk, fn)
					nrm[k] = s.normalized() if s.length_squared() > 1e-14 else fn
			# the tangent: the direction of increasing u in the triangle, and the handedness of the uv frame
			var ua: Vector2 = r[3]
			var ub: Vector2 = r[4]
			var uc: Vector2 = r[5]
			var e1 := b - a
			var e2 := c - a
			var du1 := ub - ua
			var du2 := uc - ua
			var det := du1.x * du2.y - du2.x * du1.y
			var tan_u := Vector3.RIGHT
			var wsign := 1.0
			if absf(det) > 1e-9:
				var tu := (e1 * du2.y - e2 * du1.y) / det
				var tv := (e2 * du1.x - e1 * du2.x) / det
				if tu.length_squared() > 1e-12:
					tan_u = tu.normalized()
					wsign = 1.0 if fn.cross(tan_u).dot(tv) >= 0.0 else -1.0
			else:
				tan_u = (fn.cross(Vector3.UP) if absf(fn.y) < 0.95 else Vector3.RIGHT).normalized()
			mesh.push_tri3(a, b, c, nrm[0], nrm[1], nrm[2], ua, ub, uc, tan_u, wsign, e, e, e, int(g[1]), fn)
		mesh.zone = zone_save
		mesh.flags = flags_save


# --- polygon helpers ---------------------------------------------------------------------------------

static func area2(poly: PackedVector2Array) -> float:
	var s := 0.0
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s


static func ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if area2(poly) >= 0.0:
		return poly
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(poly[i])
	return out


static func centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(maxi(poly.size(), 1))


static func edge_normals(poly: PackedVector2Array) -> PackedVector2Array:
	## The unit inward normals of a counter-clockwise outline's edges (edge i runs from poly[i] to poly[i + 1]).
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var d := (poly[(i + 1) % n] - poly[i]).normalized()
		out.append(Vector2(-d.y, d.x))
	return out


static func offset_by_edges(poly: PackedVector2Array, off: PackedFloat32Array) -> PackedVector2Array:
	## The corners of the outline with edge i moved outward by off[i] (mitred; a sharp corner's spike is capped at four times the offset).
	var n := poly.size()
	var nrm := edge_normals(poly)
	var out := PackedVector2Array()
	for j in n:
		var i := (j + n - 1) % n
		var n1 := nrm[i]
		var n2 := nrm[j]
		var e1 := n1.dot(poly[i]) - off[i]
		var e2 := n2.dot(poly[j]) - off[j]
		var det := n1.x * n2.y - n1.y * n2.x
		var q := poly[j] - (n1 + n2).normalized() * (off[i] + off[j]) * 0.5
		if absf(det) > 1e-4:
			q = Vector2((e1 * n2.y - e2 * n1.y) / det, (n1.x * e2 - n2.x * e1) / det)
			var lim := maxf(absf(off[i]), absf(off[j])) * 4.0 + 0.05
			if q.distance_to(poly[j]) > lim:
				q = poly[j] + (q - poly[j]).normalized() * lim
		out.append(q)
	return out


static func clip_le(poly: PackedVector2Array, nrm: Vector2, c: float) -> PackedVector2Array:
	## The part of a convex outline with dot(p, nrm) <= c.
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		var d0 := p0.dot(nrm) - c
		var d1 := p1.dot(nrm) - c
		if d0 <= 0.0:
			out.append(p0)
		if (d0 < 0.0 and d1 > 0.0) or (d0 > 0.0 and d1 < 0.0):
			out.append(p0 + (p1 - p0) * (d0 / (d0 - d1)))
	return out


static func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


# --- gable and hip roofs -----------------------------------------------------------------------------

static func ridge(sh: Shell, poly_in: PackedVector2Array, ys: float, o: Dictionary) -> Dictionary:
	## o: slope (rise per metre), gable (PackedByteArray per edge), ovh (PackedFloat32Array per edge, metres of eave beyond the wall; <= 0.01 = none),
	## tf (fascia height), zones {roof, side, soffit} (mesh zones), flags (mesh flags of the roof surface).
	var poly := ccw(poly_in)
	var n := poly.size()
	var slope: float = o.slope
	var gable: PackedByteArray = o.gable
	var ovh: PackedFloat32Array = o.ovh
	var tfv: float = o.get("tf", 0.14)
	var zr: Dictionary = o.zones
	var fl: int = int(o.get("flags", 0))
	var g_roof := sh.group(int(zr.roof), fl, O_UP)
	var g_side := sh.group(int(zr.side), 0, O_OUT)
	var g_gable := sh.group(int(zr.get("gable", zr.side)), 0, O_OUT)
	var g_soffit := sh.group(int(zr.soffit), 0, O_DOWN)
	var g_hidden := sh.group(int(zr.roof), 0, O_OUT)
	var g_floor := sh.group(int(zr.roof), 0, O_DOWN)
	var ni := edge_normals(poly)
	var e_line := PackedFloat32Array()      # the eave line of edge i: dot(p, ni) = e_line[i]
	var tf := PackedFloat32Array()
	var off_out := PackedFloat32Array()
	for i in n:
		var lim_ov: float = ovh[i] if ovh[i] > 0.01 else -INSET
		off_out.append(lim_ov)
		e_line.append(ni[i].dot(poly[i]) - lim_ov)
		tf.append(tfv if ovh[i] > 0.01 else 0.0)
	var outer := offset_by_edges(poly, off_out)
	var win_off := PackedFloat32Array()
	for i in n:
		win_off.append(-WALL_IN)
	var win := offset_by_edges(poly, win_off)
	var planes := []
	var hip_ids := []
	for i in n:
		if gable[i] == 0:
			hip_ids.append(i)
	if hip_ids.is_empty():
		return {}
	var height := func(p: Vector2) -> float:
		var h := INF
		for i: int in hip_ids:
			h = minf(h, ys + tf[i] + slope * (ni[i].dot(p) - e_line[i]))
		return h
	var regions := {}
	var apexes: Array[Vector2] = []
	var top := ys
	for i: int in hip_ids:
		var r := outer
		for j: int in hip_ids:
			if j == i:
				continue
			var m: Vector2 = ni[i] - ni[j]
			var rhs := (tf[j] - tf[i]) / slope + (e_line[i] - e_line[j])
			if m.length() < 1e-7:
				if rhs < -1e-9:
					r = PackedVector2Array()
				continue
			r = clip_le(r, m, rhs)
			if r.size() < 3:
				break
		if r.size() < 3 or absf(area2(r)) < 1e-6:
			continue
		# the planes of a regular outline all meet in one point, which every region finds with its own rounding: one point for them all
		for q in r.size():
			var found_q := false
			for seen: Vector2 in apexes:
				if seen.distance_to(r[q]) < 2e-3:
					r[q] = seen
					found_q = true
					break
			if not found_q:
				apexes.append(r[q])
		regions[i] = r
		planes.append([ni[i], e_line[i], tf[i]])
		var d_e := (poly[(i + 1) % n] - poly[i]).normalized()
		var pts: Array = []
		for p in r:
			var hh: float = height.call(p)
			top = maxf(top, hh)
			pts.append(v3(p, hh))
		var uvf := func(p3: Vector3) -> Vector2:
			var p2 := Vector2(p3.x, p3.z)
			return Vector2(d_e.dot(p2), (ni[i].dot(p2) - e_line[i]) * sqrt(1.0 + slope * slope))
		sh.poly(pts, g_roof, uvf)
	# the vertical faces up the eaves' edges: fascia boards and gable walls, from the soffit's height to the roof's rim
	for i in n:
		var a := outer[i]
		var b := outer[(i + 1) % n]
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 < 1e-9:
			continue
		var found: Array = []                   # [t along the edge, the roof's own vertex there]
		var sample := func(p3: Vector3) -> void:
			var t := (Vector2(p3.x, p3.z) - a).dot(ab) / l2
			if t < -1e-4 or t > 1.0 + 1e-4:
				return
			var q := a + ab * clampf(t, 0.0, 1.0)
			if q.distance_to(Vector2(p3.x, p3.z)) > 1e-4:
				return
			found.append([t, p3])
		for ri: int in regions:
			for p in (regions[ri] as PackedVector2Array):
				sample.call(v3(p, height.call(p)))
		sample.call(v3(a, height.call(a)))
		sample.call(v3(b, height.call(b)))
		found.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var mx := ys
		for f: Array in found:
			mx = maxf(mx, (f[1] as Vector3).y)
		if mx - ys < 1e-4:
			continue
		var pts2: Array = [v3(a, ys), v3(b, ys)]
		for fi in range(found.size() - 1, -1, -1):
			var pt: Vector3 = (found[fi] as Array)[1]
			if (pts2[pts2.size() - 1] as Vector3).distance_squared_to(pt) > 1e-9 and (pts2[0] as Vector3).distance_squared_to(pt) > 1e-9:
				pts2.append(pt)
		var dd := ab.normalized()
		sh.poly(pts2, g_gable if gable[i] != 0 else g_side, func(p3: Vector3) -> Vector2: return Vector2(dd.dot(Vector2(p3.x, p3.z)), p3.y - ys))
	# the soffit under the eaves (facing down), the hidden skirt and floor inside the wall
	var yb := ys - DEPTH
	for j in n:
		var j2 := (j + 1) % n
		var uvs := func(p3: Vector3) -> Vector2: return Vector2(p3.x, p3.z)
		sh.tri(v3(outer[j], ys), v3(outer[j2], ys), v3(win[j2], ys), uvs.call(v3(outer[j], ys)), uvs.call(v3(outer[j2], ys)), uvs.call(v3(win[j2], ys)), g_soffit)
		sh.tri(v3(outer[j], ys), v3(win[j2], ys), v3(win[j], ys), uvs.call(v3(outer[j], ys)), uvs.call(v3(win[j2], ys)), uvs.call(v3(win[j], ys)), g_soffit)
		var a3 := v3(win[j], ys)
		var b3 := v3(win[j2], ys)
		var c3 := v3(win[j2], yb)
		var d3 := v3(win[j], yb)
		var z := Vector2.ZERO
		sh.tri(a3, b3, c3, z, z, z, g_hidden)
		sh.tri(a3, c3, d3, z, z, z, g_hidden)
	var cw := centroid(win)
	for j in n:
		var j2 := (j + 1) % n
		sh.tri(v3(cw, yb), v3(win[j], yb), v3(win[j2], yb), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_floor)
	return {"kind": "ridge", "planes": planes, "ys": ys, "slope": slope, "top": top, "outer": outer, "inner": win, "poly": poly, "gable": gable,
		"centre": v3(cw, ys + (top - ys) * 0.35)}


static func ridge_height(rec: Dictionary, p: Vector2) -> float:
	## The roof's height at p (the lowest plane), for chimneys and the like.
	var h := INF
	for pl: Array in rec.planes:
		var nrm: Vector2 = pl[0]
		h = minf(h, float(rec.ys) + float(pl[2]) + float(rec.slope) * (nrm.dot(p) - float(pl[1])))
	return h


# --- radial roofs --------------------------------------------------------------------------------------

static func pyramid(sh: Shell, poly_in: PackedVector2Array, ys: float, o: Dictionary) -> Dictionary:
	## o: ovh (per edge), H (height from the eaves to the apex or the inner ring), profile (Array of Vector2(u, hfrac), from (0, 0) to (1, 1)),
	## lift (how far the eaves' corners turn up), lift_p (sharpness of that), lift_u (the share of the profile the lift fades out over),
	## sub (segments per edge), tf (fascia height), inner (PackedVector2Array of the same corner count: a truncated roof closes on it; else an apex),
## ridge ({axis, along, across}: close on the eaves' outline squashed that way, a ridge line),
	## bend (Vector2: the tip leans this far), zones {roof, side, soffit} (mesh zones), flags (mesh flags of the roof surface).
	var poly := ccw(poly_in)
	var n := poly.size()
	var ovh: PackedFloat32Array = o.ovh
	var H: float = o.H
	var prof: Array = o.profile
	var lift: float = o.get("lift", 0.0)
	var lift_p: float = o.get("lift_p", 3.0)
	var lift_u: float = o.get("lift_u", 0.5)
	var m: int = o.get("sub", 4)
	var tfv: float = o.get("tf", 0.14)
	var bend: Vector2 = o.get("bend", Vector2.ZERO)
	var zr: Dictionary = o.zones
	var fl: int = int(o.get("flags", 0))
	var g_roof := sh.group(int(zr.roof), fl, O_FLIP)
	var g_fascia := sh.group(int(zr.side), 0, O_OUT)
	var g_soffit := sh.group(int(zr.soffit), 0, O_DOWN)
	var g_hidden := sh.group(int(zr.roof), 0, O_OUT)
	var g_floor := sh.group(int(zr.roof), 0, O_DOWN)
	var g_cap := sh.group(int(zr.roof), 0, O_FLIP)
	var off_out := PackedFloat32Array()
	var tfe := PackedFloat32Array()
	for i in n:
		off_out.append(ovh[i] if ovh[i] > 0.01 else -INSET)
		tfe.append(tfv if ovh[i] > 0.01 else 0.0)
	var outer := offset_by_edges(poly, off_out)
	var win_off := PackedFloat32Array()
	for i in n:
		win_off.append(-WALL_IN)
	var win := offset_by_edges(poly, win_off)
	var cen := centroid(poly)
	var rdg: Dictionary = o.get("ridge", {})
	var truncated: bool = (o.has("inner") and (o.inner as PackedVector2Array).size() == n) or not rdg.is_empty()
	var inner := PackedVector2Array()
	if not rdg.is_empty():
		# a ridge line instead of an apex: the eaves' outline squashed across `axis` (an affine image, so the rings never fold)
		var ax: Vector2 = rdg.axis
		var perp := Vector2(-ax.y, ax.x)
		var co := centroid(outer)
		for q in outer:
			var dq := q - co
			inner.append(co + ax * dq.dot(ax) * float(rdg.along) + perp * dq.dot(perp) * float(rdg.across))
	elif truncated:
		inner = o.inner
	else:
		for i in n:
			inner.append(cen)
	# corner lift weights: a corner turns up only where both its edges overhang
	var lc := PackedFloat32Array()
	var tfc := PackedFloat32Array()
	for j in n:
		var i := (j + n - 1) % n
		lc.append(1.0 if (ovh[i] > 0.01 and ovh[j] > 0.01) else 0.0)
		tfc.append(minf(tfe[i], tfe[j]))
	var K := prof.size()
	# ring points: rings[k][j * m + s]
	var rim_top := PackedVector3Array()
	var rim_bot := PackedVector3Array()
	var ring_u := PackedFloat32Array()
	var rings: Array = []
	var arc := 0.0
	var arcs := PackedFloat32Array()
	var p0s := PackedVector2Array()
	var pis := PackedVector2Array()
	for j in n:
		var j2 := (j + 1) % n
		for s in m:
			var t := float(s) / float(m)
			p0s.append(outer[j].lerp(outer[j2], t))
			pis.append(inner[j].lerp(inner[j2], t))
	var total := n * m
	for idx in total:
		arcs.append(arc)
		arc += p0s[idx].distance_to(p0s[(idx + 1) % total])
	for k in K:
		var pk: Vector2 = prof[k]
		var ring := PackedVector3Array()
		for idx in total:
			var j := idx / m
			var s := idx % m
			var t := float(s) / float(m)
			var w0 := pow(1.0 - t, lift_p) * lc[j] + pow(t, lift_p) * lc[(j + 1) % n]
			var fade := pow(maxf(0.0, 1.0 - pk.x / maxf(lift_u, 0.01)), 1.5)
			var tf_here := tfc[j] if s == 0 else tfe[j]
			# (the last ring is the inner outline itself, exactly: a lerp to 1.0 can differ from it by a rounding, and the apex of
			# a pyramid is one point that many triangles share)
			var q := (pis[idx] if pk.x >= 1.0 else p0s[idx].lerp(pis[idx], pk.x)) + bend * pk.y * pk.y
			ring.append(v3(q, ys + tf_here * (1.0 - pk.y) + H * pk.y + lift * w0 * fade))
		rings.append(ring)
	for idx in total:
		var j := idx / m
		var s := idx % m
		var tf_here := tfc[j] if s == 0 else tfe[j]
		rim_top.append((rings[0] as PackedVector3Array)[idx])
		rim_bot.append(Vector3(p0s[idx].x, (rings[0] as PackedVector3Array)[idx].y - tf_here, p0s[idx].y))
	# slant distance (v) along every column
	var slant: Array = []
	for k in K:
		var row := []
		row.resize(total)
		slant.append(row)
	for idx in total:
		var acc2 := 0.0
		slant[0][idx] = 0.0
		for k in range(1, K):
			acc2 += (rings[k][idx] as Vector3).distance_to(rings[k - 1][idx])
			slant[k][idx] = acc2
	# the roof surface
	for idx in total:
		var j := idx / m
		var idn := (idx + 1) % total
		var un := arcs[idn] if idn != 0 else arc
		for k in range(K - 1):
			var a: Vector3 = rings[k][idx]
			var b: Vector3 = rings[k][idn]
			var c: Vector3 = rings[k + 1][idn]
			var d: Vector3 = rings[k + 1][idx]
			var ua := Vector2(arcs[idx], slant[k][idx])
			var ub := Vector2(un, slant[k][idn])
			var uc := Vector2(un, slant[k + 1][idn])
			var ud := Vector2(arcs[idx], slant[k + 1][idx])
			sh.tri(a, b, c, ua, ub, uc, g_roof, j)
			sh.tri(a, c, d, ua, uc, ud, g_roof, j)
	# the fascia boards and the soffit
	for idx in total:
		var idn := (idx + 1) % total
		var un := arcs[idn] if idn != 0 else arc
		var a: Vector3 = rim_top[idx]
		var b: Vector3 = rim_top[idn]
		var c: Vector3 = rim_bot[idn]
		var d: Vector3 = rim_bot[idx]
		var ua := Vector2(arcs[idx], a.y)
		var ub := Vector2(un, b.y)
		var uc := Vector2(un, c.y)
		var ud := Vector2(arcs[idx], d.y)
		sh.tri(d, c, b, ud, uc, ub, g_fascia, -1)
		sh.tri(d, b, a, ud, ub, ua, g_fascia, -1)
		# soffit: from the lower edge of the fascia to the skirt ring at the wall
		var j := idx / m
		var s := idx % m
		var wring_a := win[j].lerp(win[(j + 1) % n], float(s) / float(m))
		var j3 := idn / m
		var s3 := idn % m
		var wring_b := win[j3].lerp(win[(j3 + 1) % n], float(s3) / float(m))
		var wa3 := v3(wring_a, ys)
		var wb3 := v3(wring_b, ys)
		sh.tri(d, c, wb3, Vector2(d.x, d.z), Vector2(c.x, c.z), Vector2(wb3.x, wb3.z), g_soffit)
		sh.tri(d, wb3, wa3, Vector2(d.x, d.z), Vector2(wb3.x, wb3.z), Vector2(wa3.x, wa3.z), g_soffit)
		# hidden skirt and floor
		var yb := ys - DEPTH
		var sa := v3(wring_a, yb)
		var sb := v3(wring_b, yb)
		sh.tri(wa3, wb3, sb, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_hidden)
		sh.tri(wa3, sb, sa, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_hidden)
		sh.tri(v3(centroid(win), yb), sa, sb, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_floor)
	# the closed top of a truncated roof (inside the wall above)
	if truncated:
		var cc := v3(centroid(inner), ys + H)
		var last: PackedVector3Array = rings[K - 1]
		for idx in total:
			var idn := (idx + 1) % total
			sh.tri(cc, last[idx], last[idn], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_cap)
	var apex_pt := v3(cen + bend, ys + H)
	var tips := PackedVector3Array()           # the lifted corners' lower edge, where a lantern hangs
	for j in n:
		if lc[j] > 0.5 and lift > 0.05:
			tips.append(v3(outer[j], ys + lift))
	return {"kind": "pyramid", "ys": ys, "H": H, "centre2": cen, "apex": apex_pt, "outer": outer, "inner": win, "poly": poly, "profile": prof,
		"top": ys + H, "tfv": tfv, "truncated": truncated, "centre": v3(cen, ys + H * 0.3), "tips": tips, "lift": lift}


static func pyramid_height(rec: Dictionary, p: Vector2) -> float:
	## The radial roof's height at p: the profile at the share u of the way from the eaves (0) to the centre (1), u = the smallest of the
	## relative inward distances from p to the eaves' edges.
	var oc := ccw(rec.outer)
	var c: Vector2 = rec.centre2
	var nrm := edge_normals(oc)
	var u := 1.0
	for i in oc.size():
		var den := (nrm[i] as Vector2).dot(c - oc[i])
		if absf(den) < 1e-6:
			continue
		u = minf(u, (nrm[i] as Vector2).dot(p - oc[i]) / den)
	u = clampf(u, 0.0, 1.0)
	var prof: Array = rec.profile
	for k in range(prof.size() - 1):
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		if u >= a.x and u <= b.x:
			var f := (u - a.x) / maxf(b.x - a.x, 1e-6)
			return float(rec.ys) + float(rec.H) * lerpf(a.y, b.y, f)
	return float(rec.ys) + float(rec.H)


# --- flat roofs and boxes ---------------------------------------------------------------------------------

static func slab(sh: Shell, poly_in: PackedVector2Array, ys: float, o: Dictionary) -> Dictionary:
	## A flat roof: a deck `deck` above the wall top with a parapet round it (`rim` high, `wall` thick, as tall as rim + deck above ys). ovh (per edge)
	## makes a slab edge jut out under the parapet. zones {roof (deck), side (parapet faces), soffit, cap (the parapet's top, default side)}.
	var poly := ccw(poly_in)
	var n := poly.size()
	var ovh: PackedFloat32Array = o.ovh
	var rim: float = o.get("rim", 0.9)
	var thick: float = o.get("wall", 0.25)
	var deck: float = o.get("deck", 0.12)
	var zr: Dictionary = o.zones
	var fl: int = int(o.get("flags", 0))
	var sfl: int = int(o.get("side_flags", 0))
	var g_roof := sh.group(int(zr.roof), fl, O_UP)
	var g_side := sh.group(int(zr.side), sfl, O_OUT)
	var g_inner := sh.group(int(zr.side), sfl, O_IN)
	var g_cap := sh.group(int(zr.get("cap", zr.side)), 0, O_UP)
	var g_soffit := sh.group(int(zr.soffit), 0, O_DOWN)
	var g_hidden := sh.group(int(zr.roof), 0, O_OUT)
	var g_floor := sh.group(int(zr.roof), 0, O_DOWN)
	var off_out := PackedFloat32Array()
	var off_in := PackedFloat32Array()
	var win_off := PackedFloat32Array()
	for i in n:
		off_out.append(ovh[i] if ovh[i] > 0.01 else -INSET)
		win_off.append(-WALL_IN)
	var outer := offset_by_edges(poly, off_out)
	var win := offset_by_edges(poly, win_off)
	for i in n:
		off_in.append(-thick)
	var inner := offset_by_edges(outer, off_in)
	# the parapet only if its inner line is a proper polygon of the same orientation, clear of the outer one
	var has_rim := rim > 0.05 and absf(area2(inner)) > 0.3 and area2(inner) > 0.0
	if has_rim:
		var on := edge_normals(outer)
		for j in n:
			if on[j].dot(inner[j] - outer[j]) < thick * 0.5:
				has_rim = false
				break
	var y_d := ys + deck
	var y_r := y_d + rim if has_rim else y_d
	var yb := ys - DEPTH
	# the outer faces up to the parapet's top (or to the deck's edge), the soffit, the hidden skirt and floor
	for j in n:
		var j2 := (j + 1) % n
		var a := outer[j]
		var b := outer[j2]
		var d := (b - a).normalized()
		var uf := func(p3: Vector3) -> Vector2: return Vector2(d.dot(Vector2(p3.x, p3.z)), p3.y - ys)
		sh.poly([v3(a, ys), v3(b, ys), v3(b, y_r), v3(a, y_r)], g_side, uf)
		sh.tri(v3(outer[j], ys), v3(outer[j2], ys), v3(win[j2], ys), Vector2(outer[j].x, outer[j].y), Vector2(outer[j2].x, outer[j2].y), Vector2(win[j2].x, win[j2].y), g_soffit)
		sh.tri(v3(outer[j], ys), v3(win[j2], ys), v3(win[j], ys), Vector2(outer[j].x, outer[j].y), Vector2(win[j2].x, win[j2].y), Vector2(win[j].x, win[j].y), g_soffit)
		var a3 := v3(win[j], ys)
		var b3 := v3(win[j2], ys)
		var c3 := v3(win[j2], yb)
		var d3 := v3(win[j], yb)
		var z := Vector2.ZERO
		sh.tri(a3, b3, c3, z, z, z, g_hidden)
		sh.tri(a3, c3, d3, z, z, z, g_hidden)
	var cw := centroid(win)
	for j in n:
		sh.tri(v3(cw, yb), v3(win[j], yb), v3(win[(j + 1) % n], yb), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_floor)
	var xz := func(p3: Vector3) -> Vector2: return Vector2(p3.x, p3.z)
	if has_rim:
		for j in n:
			var j2 := (j + 1) % n
			# the parapet's top, and its inner face down to the deck
			sh.poly([v3(outer[j], y_r), v3(outer[j2], y_r), v3(inner[j2], y_r), v3(inner[j], y_r)], g_cap, xz)
			var a := inner[j]
			var b := inner[j2]
			var d := (b - a).normalized()
			var uf := func(p3: Vector3) -> Vector2: return Vector2(d.dot(Vector2(p3.x, p3.z)), p3.y - ys)
			sh.poly([v3(a, y_d), v3(b, y_d), v3(b, y_r), v3(a, y_r)], g_inner, uf)
		var ci := centroid(inner)
		for j in n:
			sh.tri(v3(ci, y_d), v3(inner[j], y_d), v3(inner[(j + 1) % n], y_d), Vector2(ci.x, ci.y), Vector2(inner[j].x, inner[j].y), Vector2(inner[(j + 1) % n].x, inner[(j + 1) % n].y), g_roof)
	else:
		for j in n:
			sh.tri(v3(cw, y_d), v3(outer[j], y_d), v3(outer[(j + 1) % n], y_d), Vector2(cw.x, cw.y), Vector2(outer[j].x, outer[j].y), Vector2(outer[(j + 1) % n].x, outer[(j + 1) % n].y), g_roof)
	return {"kind": "slab", "ys": ys, "top": y_r, "deck": y_d, "poly": poly, "outer": outer, "inner": inner if has_rim else outer, "rim": has_rim,
		"centre": v3(cw, ys + (y_r - ys) * 0.5)}


static func prism(sh: Shell, poly_in: PackedVector2Array, y0: float, y1: float, zone_wall: int, zone_top: int, flags: int = 0) -> Dictionary:
	## A closed box over a convex outline (a penthouse, a lantern, a tier's body): walls zone_wall (u along the wall, v height), a flat top zone_top.
	var poly := ccw(poly_in)
	var n := poly.size()
	var g_w := sh.group(zone_wall, flags, O_OUT)
	var g_t := sh.group(zone_top, 0, O_UP)
	var g_b := sh.group(zone_wall, 0, O_DOWN)
	var c := centroid(poly)
	for j in n:
		var j2 := (j + 1) % n
		var a := poly[j]
		var b := poly[j2]
		var d := (b - a).normalized()
		var uf := func(p3: Vector3) -> Vector2: return Vector2(d.dot(Vector2(p3.x, p3.z)), p3.y)
		sh.poly([v3(a, y0), v3(b, y0), v3(b, y1), v3(a, y1)], g_w, uf)
		sh.tri(v3(c, y1), v3(a, y1), v3(b, y1), Vector2(c.x, c.y), Vector2(a.x, a.y), Vector2(b.x, b.y), g_t)
		sh.tri(v3(c, y0), v3(a, y0), v3(b, y0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g_b)
	return {"kind": "prism", "ys": y0, "top": y1, "poly": poly, "centre": v3(c, (y0 + y1) * 0.5)}


# --- small solids ---------------------------------------------------------------------------------------

static func lathe(sh: Shell, base: Vector3, prof: Array, sides: int, g: int, rot: float = 0.0, tilt: Vector2 = Vector2.ZERO) -> void:
	## A closed surface of revolution round the vertical axis through `base` (profile = [Vector2(radius, height)] from the bottom up; the first
	## and last radii may be 0 for a point). A tilt (x, z) leans the top: every ring is shifted by tilt * (its height share)^2.
	var top_h: float = (prof[prof.size() - 1] as Vector2).y
	var sgl := sh.new_sg()
	var rows: Array = []
	for pr: Vector2 in prof:
		var ring := PackedVector3Array()
		var share := pr.y / maxf(top_h, 1e-6)
		var sh2 := Vector3(tilt.x, 0.0, tilt.y) * share * share
		for i in sides:
			var a := rot + TAU * float(i) / float(sides)
			ring.append(base + Vector3(cos(a) * pr.x, pr.y, sin(a) * pr.x) + sh2)
		rows.append(ring)
	for k in range(rows.size() - 1):
		var r0: PackedVector3Array = rows[k]
		var r1: PackedVector3Array = rows[k + 1]
		for i in sides:
			var i2 := (i + 1) % sides
			var uu := float(i) / float(sides) * TAU * maxf((prof[k] as Vector2).x, 0.05)
			var uu2 := float(i2) / float(sides) * TAU * maxf((prof[k] as Vector2).x, 0.05)
			sh.tri(r0[i], r0[i2], r1[i2], Vector2(uu, (prof[k] as Vector2).y), Vector2(uu2, (prof[k] as Vector2).y), Vector2(uu2, (prof[k + 1] as Vector2).y), g, sgl)
			sh.tri(r0[i], r1[i2], r1[i], Vector2(uu, (prof[k] as Vector2).y), Vector2(uu2, (prof[k + 1] as Vector2).y), Vector2(uu, (prof[k + 1] as Vector2).y), g, sgl)
	# caps (the first and last rings are flat discs when their radius is not 0)
	for end in [0, rows.size() - 1]:
		var ring2: PackedVector3Array = rows[end]
		if (prof[end] as Vector2).x < 0.01:
			continue
		var cc := Vector3.ZERO
		for p in ring2:
			cc += p
		cc /= float(ring2.size())
		for i in sides:
			sh.tri(cc, ring2[i], ring2[(i + 1) % sides], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, g, -1)
