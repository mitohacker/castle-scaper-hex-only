class_name CFRoofs
extends RefCounted
## Roofs and banners built on the very vertices of a CAP outline from the plan: a roof's eave is the
## whole chain of vertices of the masonry under it (corners and every split point), so the two are
## welded; the roof's own rings use only the outline's corners, so it never grows slivers.

const FLARE := [Vector2(1.0, 0.0), Vector2(0.93, 0.10), Vector2(0.70, 0.45), Vector2(0.38, 0.78)]   # (scale, height share)


static func _corner(loop: PackedVector2Array, cidx: PackedInt32Array, j: int) -> Vector2:
	return loop[cidx[j % cidx.size()]]


static func _edge_verts(loop: PackedVector2Array, cidx: PackedInt32Array, j: int) -> Array:
	## The loop's vertices from corner j to corner j+1, both included.
	var nc := cidx.size()
	var ia := cidx[j % nc]
	var ib := cidx[(j + 1) % nc]
	var out := []
	var i := ia
	for _k in loop.size() + 1:
		out.append(loop[i])
		if i == ib:
			break
		i = (i + 1) % loop.size()
	return out


static func cone(mesh: CFMesh, loop: PackedVector2Array, cidx: PackedInt32Array, y: float, c: Vector2, h: float, tip: float = 0.035) -> PackedVector3Array:
	## A flared conical roof over a convex outline; returns the small ring at the top (for a pole).
	var prof: Array = FLARE.duplicate()
	prof.append(Vector2(tip, 1.0))
	var nc := cidx.size()
	var r_eave := 0.0
	for p in loop:
		r_eave = maxf(r_eave, p.distance_to(c))
	var rings: Array = []
	var slant := PackedFloat32Array()
	var run := 0.0
	for k in prof.size():
		var pk: Vector2 = prof[k]
		var ring := PackedVector3Array()
		for j in nc:
			var q := c + (_corner(loop, cidx, j) - c) * pk.x
			ring.append(Vector3(q.x, y + h * pk.y, q.y))
		rings.append(ring)
		if k > 0:
			var pj: Vector2 = prof[k - 1]
			run += sqrt(pow((pj.x - pk.x) * r_eave, 2.0) + pow(h * (pk.y - pj.y), 2.0))
		slant.append(run)
	for k in range(prof.size() - 1):
		var pa: Vector2 = prof[k]
		var pb: Vector2 = prof[k + 1]
		var dy := h * (pb.y - pa.y)
		var dscale := pa.x - pb.x
		for j in nc:
			var j2 := (j + 1) % nc
			var top_a: Vector3 = (rings[k + 1] as PackedVector3Array)[j]
			var top_b: Vector3 = (rings[k + 1] as PackedVector3Array)[j2]
			var poly := []        # [position, v]
			if k == 0:
				for e: Vector2 in _edge_verts(loop, cidx, j):
					poly.append([Vector3(e.x, y, e.y), slant[0]])
			else:
				poly.append([(rings[k] as PackedVector3Array)[j], slant[k]])
				poly.append([(rings[k] as PackedVector3Array)[j2], slant[k]])
			poly.append([top_b, slant[k + 1]])
			poly.append([top_a, slant[k + 1]])
			_smooth_fan(mesh, poly, c, dscale, dy, r_eave)
	return rings[rings.size() - 1]


static func _smooth_fan(mesh: CFMesh, poly: Array, c: Vector2, dscale: float, dy: float, r_eave: float) -> void:
	## A convex facet of a cone as a triangle fan from its last vertex, with the cone's smooth normals.
	var n := poly.size()
	var pos := []
	var nrm := []
	var uvs := []
	var tans := []
	var a0 := 0.0
	for i in n:
		var p: Vector3 = poly[i][0]
		var rad := Vector2(p.x - c.x, p.z - c.y)
		var nv := Vector3.UP
		var tv := Vector3.RIGHT
		if rad.length() > 1e-4:
			var rl := rad.length()
			nv = _cone_normal(rad, dscale * rl, dy)
			var ang := atan2(rad.y, rad.x)
			if i == 0:
				a0 = ang
			else:
				ang = a0 + fposmod(ang - a0 + PI, TAU) - PI
			uvs.append(Vector2(-ang * r_eave, float(poly[i][1])))
			var rn := rad / rl
			tv = Vector3(rn.y, 0.0, -rn.x)
		else:
			uvs.append(Vector2(0.0, float(poly[i][1])))
		pos.append(p)
		nrm.append(nv)
		tans.append(tv)
	var no := CFMesh.NO_EDGE
	var e := Vector4(no, no, no, no)
	var base := n - 1
	for i in range(0, n - 2):
		var want: Vector3 = nrm[base] + nrm[i] + nrm[i + 1]
		mesh.push_tri([pos[base], pos[i], pos[i + 1]], [nrm[base], nrm[i], nrm[i + 1]], [uvs[base], uvs[i], uvs[i + 1]],
			tans[base], 1.0, [e, e, e], mesh.flags | CFMesh.F_ROUND, want)


static func _cone_normal(radial: Vector2, dr: float, dy: float) -> Vector3:
	var rad := radial.normalized()
	return (Vector3(rad.x, 0.0, rad.y) * dy + Vector3.UP * dr).normalized()


static func hip(mesh: CFMesh, loop: PackedVector2Array, cidx: PackedInt32Array, y: float, c: Vector2, ax: Vector2, half_l: float, half_w: float, h: float) -> void:
	## A hipped roof over a rectangle (a pyramid when it is square): every corner is joined to the ridge point
	## straight above its nearest ridge position; each side's facet takes all the eave's vertices.
	var nc := cidx.size()
	var ridge_half := maxf(half_l - half_w, 0.0)
	var up := Vector3.UP
	var save_flow := mesh.flow
	var tops := []
	for j in nc:
		var d := _corner(loop, cidx, j) - c
		var a := clampf(d.dot(ax), -ridge_half, ridge_half)
		var q := c + ax * a
		tops.append(Vector3(q.x, y + h, q.y))
	for j in nc:
		var j2 := (j + 1) % nc
		var face := PackedVector3Array()
		for e: Vector2 in _edge_verts(loop, cidx, j):
			face.append(Vector3(e.x, y, e.y))
		for w: Vector3 in [tops[j2], tops[j]]:
			if face[face.size() - 1].distance_squared_to(w) > 1e-8 and face[0].distance_squared_to(w) > 1e-8:
				face.append(w)
		if face.size() < 3:
			continue
		var pa := _corner(loop, cidx, j)
		var pb := _corner(loop, cidx, j2)
		var e2 := pb - pa
		mesh.flow = Vector3(e2.x, 0.0, e2.y).normalized() if e2.length() > 1e-6 else Vector3.RIGHT
		var mid := (pa + pb) * 0.5 - c
		var out := Vector3(mid.x, 0.0, mid.y).normalized()
		mesh.add_poly(face, (out + up * 0.9).normalized())
	mesh.flow = save_flow


static func pole(mesh: CFMesh, base: PackedVector3Array, height: float, cloth_zone: int, wind: Vector3, banner_len: float, with_cloth: bool) -> void:
	## A flag pole standing on a ring (the roof's tip): three rings, a cap, and a swallow-tailed banner.
	var m := base.size()
	if m < 3:
		return
	var c := Vector3.ZERO
	for p in base:
		c += p
	c /= float(m)
	var mid := PackedVector3Array()
	var top := PackedVector3Array()
	for p in base:
		mid.append(p + Vector3.UP * height * 0.55)
		top.append(p + Vector3.UP * height)
	var zone_save := mesh.zone
	var flags_save := mesh.flags
	mesh.zone = CFMesh.Z_TIMBER
	mesh.flags |= CFMesh.F_PLAIN
	mesh.add_loft([base, mid, top], false, true)
	if with_cloth:
		# the banner hangs from the pole vertex that faces the wind
		var best := 0
		var best_d := -INF
		for i in m:
			var d := (base[i] - c).dot(wind)
			if d > best_d:
				best_d = d
				best = i
		var w := wind.normalized()
		var p_top: Vector3 = top[best]
		var p_bot: Vector3 = mid[best]
		var pm := (p_top + p_bot) * 0.5
		var far_top := p_top + w * banner_len + Vector3.DOWN * 0.1
		var far_bot := p_bot + w * banner_len * 0.9 + Vector3.UP * 0.05
		var notch := pm + w * banner_len * 0.62
		mesh.zone = cloth_zone
		for side in [1.0, -1.0]:
			var nrm: Vector3 = Vector3.UP.cross(w) * side
			mesh.add_poly(PackedVector3Array([p_top, far_top, notch, pm]), nrm)
			mesh.add_poly(PackedVector3Array([pm, notch, far_bot, p_bot]), nrm)
	mesh.zone = zone_save
	mesh.flags = flags_save
