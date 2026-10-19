class_name CSWallJoints
extends RefCounted
## Where straight walls meet and where they end: the pieces that make a corner and an end clean.
##
## A wall is a plain rectangle, so two of them meeting at an angle leave a square notch on the outside of the bend and, when the angle is sharp, a thin
## wedge between them that no one could walk into. Two kinds of piece mend that (CSBuild._walls builds them with the walls):
##   TOWERS: a round tower (16 sides, a little higher than the walls, with its own battlements) stands on every free end of a wall and on every
##           bend, wide enough to cover the whole end of the rectangle (a wall's end is never a bare cut, a bend is never a square notch).
##           A wall too thick for a round tower (a merged one) ends in a flat cap instead; an end buried in another wall gets none.
##   FILLS:  where two walls meet at less than ANGLE_MAX degrees (an arm each side of a joint or a crossing), the wedge between them is filled
##           with a triangle up to the place where the gap is MIN_GAP wide: no sliver is left, the parapet turns round the filled corner.

static var off_towers := false      # (for the probes: build without the towers or without the fills)
static var off_fills := false
const ANGLE_MAX := 75.0         # degrees: a joint sharper than this gets its wedge filled
const MIN_GAP_K := 0.6          # the wedge is left open from this many thicknesses wide
const TOWER_MAX_K := 2.6        # towers only on walls up to this many thicknesses
const TOWER_ROUND := 0.15       # the tower's circle clears the corner of a wall's end by this much
const SIDES := 16                # a round tower is a 16-gon (CSBuild.ROUND_SIDES)
const GAP_TOWERS := 0.6         # towers closer than this (edge to edge) are one tower
const CLEAR := 0.3              # a tower's circle crosses another wall's side by at least this much, or stays at least this far from it
const ARM_MIN_K := 0.5          # a wall's arm past a joint counts when it is longer than this many thicknesses


static func compute(walls: Array, base: float) -> Dictionary:
	## {"towers": [{"c": Vector2, "r": float, "wi": int, "rot": float}], "fills": [{"poly": PackedVector2Array, "wi": int}]}
	return {"towers": [] if off_towers else towers(walls, base), "fills": [] if off_fills else fills(walls, base)}


static func _end(w: Dictionary, which: int) -> Vector2:
	var p := Vector2(float(w.x), float(w.z))
	return p if which == 0 else p + Vector2.from_angle(deg_to_rad(float(w.deg))) * float(w.len)


static func buried(walls: Array, i: int, e: Vector2) -> bool:
	## Is the point e (an end of wall i) inside the body of another wall (not at that wall's own end)?
	for j in walls.size():
		if j == i:
			continue
		var wj: Dictionary = walls[j]
		var u := Vector2.from_angle(deg_to_rad(float(wj.deg)))
		var rel := e - Vector2(float(wj.x), float(wj.z))
		var s := u.dot(rel)
		var lat := absf(u.cross(rel))
		var hw := float(wj.w) * 0.5
		if lat < hw - 0.05 and s > 0.05 and s < float(wj.len) - 0.05:
			return true
	return false


static func towers(walls: Array, base: float) -> Array:
	var out: Array = []
	for i in walls.size():
		var w: Dictionary = walls[i]
		if float(w.w) > TOWER_MAX_K * base:
			continue
		for which in 2:
			var e := _end(w, which)
			if buried(walls, i, e):
				continue
			var r := _clear_radius(walls, i, e, float(w.w) * 0.5 * sqrt(2.0) + TOWER_ROUND)
			var dup := -1
			for t in out.size():
				if (out[t].c as Vector2).distance_to(e) < 0.2:
					dup = t
					break
			if dup >= 0:
				out[dup].r = maxf(float(out[dup].r), r)
				continue
			out.append({"c": e, "r": r, "wi": i, "rot": deg_to_rad(float(w.deg))})
	for tw: Dictionary in out:
		tw["round"] = true
		tw["pts"] = _circle(tw.c, float(tw.r), float(tw.rot))
	# towers that overlap, or nearly touch, would leave a thin lens or a crack between them: they become one tower (the hull of both)
	var merged := true
	while merged:
		merged = false
		for a in out.size():
			for b in range(a + 1, out.size()):
				var ta: Dictionary = out[a]
				var tb: Dictionary = out[b]
				if (ta.c as Vector2).distance_to(tb.c) < float(ta.r) + float(tb.r) + GAP_TOWERS:
					var pts := PackedVector2Array()
					pts.append_array(ta.pts)
					pts.append_array(tb.pts)
					var hull := Geometry2D.convex_hull(pts)
					if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
						hull.remove_at(hull.size() - 1)
					var c: Vector2 = ((ta.c as Vector2) + (tb.c as Vector2)) * 0.5
					var r := maxf(float(ta.r), float(tb.r)) + (ta.c as Vector2).distance_to(tb.c) * 0.5
					out[a] = {"c": c, "r": r, "wi": mini(int(ta.wi), int(tb.wi)), "rot": ta.rot, "round": false, "pts": hull}
					out.remove_at(b)
					merged = true
					break
			if merged:
				break
	return out


static func _rect(w: Dictionary) -> PackedVector2Array:
	var u := Vector2.from_angle(deg_to_rad(float(w.deg)))
	var n := Vector2(-u.y, u.x) * (float(w.w) * 0.5)
	var a := Vector2(float(w.x), float(w.z))
	var b := a + u * float(w.len)
	return PackedVector2Array([a - n, b - n, b + n, a + n])


static func _clear_radius(walls: Array, i: int, c: Vector2, r: float) -> float:
	## The tower's radius, made a little larger where its circle would only just touch the side of another wall (a thin lens of overlap, or a hair's
	## breadth of gap, is what the plan cannot weld): it either clears the wall by CLEAR or crosses its side by CLEAR.
	for _pass in 6:
		var moved := false
		for j in walls.size():
			if j == i:
				continue
			var poly := _rect(walls[j])
			for k in 4:
				var q := Geometry2D.get_closest_point_to_segment(c, poly[k], poly[(k + 1) % 4])
				var d := q.distance_to(c)
				if absf(d - r) < CLEAR:
					r = d + CLEAR
					moved = true
		if not moved:
			break
	return r


static func _circle(c: Vector2, r: float, rot: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in SIDES:
		var a := rot + TAU * (float(i) + 0.5) / float(SIDES)
		poly.append(c + Vector2(cos(a), sin(a)) * r)
	return poly


static func fills(walls: Array, base: float) -> Array:
	var out: Array = []
	var seen := {}
	var gap := MIN_GAP_K * base
	for i in walls.size():
		for j in range(i + 1, walls.size()):
			var a: Dictionary = walls[i]
			var b: Dictionary = walls[j]
			var ua := Vector2.from_angle(deg_to_rad(float(a.deg)))
			var ub := Vector2.from_angle(deg_to_rad(float(b.deg)))
			var den := ua.cross(ub)
			if absf(den) < 0.02:
				continue                        # parallel (a merge took the close ones): no joint
			var pa := Vector2(float(a.x), float(a.z))
			var pb := Vector2(float(b.x), float(b.z))
			var rel := pb - pa
			var s := rel.cross(ub) / den          # along a
			var t := rel.cross(ua) / den          # along b
			var sin_phi := absf(den)
			var tol_a := float(b.w) * 0.5 / sin_phi + 0.05
			var tol_b := float(a.w) * 0.5 / sin_phi + 0.05
			var la := float(a.len)
			var lb := float(b.len)
			if s < -tol_a or s > la + tol_a or t < -tol_b or t > lb + tol_b:
				continue
			var x := pa + ua * s
			# the arms of both walls past the joint: [direction, wall, how far they run]
			var arms: Array = []
			for q in 2:
				var wi := i if q == 0 else j
				var u := ua if q == 0 else ub
				var sp := s if q == 0 else t
				var l := la if q == 0 else lb
				if l - sp > ARM_MIN_K * base:
					arms.append([u, wi, l - sp])
				if sp > ARM_MIN_K * base:
					arms.append([-u, wi, sp])
			arms.sort_custom(func(m: Array, n: Array) -> bool: return (m[0] as Vector2).angle() < (n[0] as Vector2).angle())
			var na := arms.size()
			if na < 2:
				continue
			for k in na:
				var p0: Array = arms[k]
				var p1: Array = arms[(k + 1) % na]
				if int(p0[1]) == int(p1[1]):
					continue
				var d0: Vector2 = p0[0]
				var d1: Vector2 = p1[0]
				var phi := absf(d0.angle_to(d1))
				if phi > deg_to_rad(ANGLE_MAX) or phi < 0.05:
					continue
				var f := _fill(walls[int(p0[1])], walls[int(p1[1])], x, d0, d1, float(p0[2]), float(p1[2]), gap)
				if f.size() < 3:
					continue
				var key := Vector2i(roundi(f[0].x * 20.0), roundi(f[0].y * 20.0))
				if seen.has(key):
					continue
				seen[key] = true
				out.append({"poly": f, "wi": int(p0[1])})
	return out


static func _fill(wa: Dictionary, wb: Dictionary, x: Vector2, d0: Vector2, d1: Vector2, run0: float, run1: float, gap: float) -> PackedVector2Array:
	## The wedge between the arm d0 of wall wa and the arm d1 of wall wb from the joint x (`run` is how far each arm goes on from x): a triangle
	## from the point where their inner sides cross to where the gap between them is `gap` wide (or where an arm ends).
	var den := d0.cross(d1)
	if absf(den) < 1e-6:
		return PackedVector2Array()
	var side := 1.0 if den > 0.0 else -1.0
	var o0 := x + Vector2(-d0.y, d0.x) * side * float(wa.w) * 0.5            # a point of wa's inner side, the side towards the other arm
	var o1 := x + Vector2(-d1.y, d1.x) * -side * float(wb.w) * 0.5
	var t0 := (o1 - o0).cross(d1) / den              # along d0 from o0 to the crossing of the inner sides
	var ic := o0 + d0 * t0
	var u0 := (ic - o1).dot(d1)
	if t0 < 0.0 or u0 < 0.0:
		return PackedVector2Array()
	var half := sin(absf(d0.angle_to(d1)) * 0.5)
	var delta := minf(gap * 0.5 / maxf(half, 1e-3), minf(run0 - t0, run1 - u0))
	if delta < 0.15:
		return PackedVector2Array()
	var tri := PackedVector2Array([ic, ic + d0 * delta, ic + d1 * delta])
	var area := (tri[1] - tri[0]).cross(tri[2] - tri[0])
	if absf(area) < 1e-4:
		return PackedVector2Array()
	if area < 0.0:
		tri = PackedVector2Array([tri[0], tri[2], tri[1]])
	return tri
