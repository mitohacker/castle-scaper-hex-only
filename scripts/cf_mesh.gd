class_name CFMesh
extends RefCounted
## Collects the castle's faces with the attributes the stone shader reads:
##   UV       surface coordinates in metres (u along the wall, v up; flagstones: x, z)
##   COLOR    r: zone / 255, g: seed, b: flags / 255, a: free
##   CUSTOM0  xyzw: distance to the face's four nearest real edges (100 = not an edge)
##   CUSTOM1  xyz: pop anchor, w: owner node id (the shader grows a freshly added node out of its anchor)
##   TANGENT  e1, w = handedness (the shader's BINORMAL is then cross(normal, e1) * w)
## Godot's front faces are clockwise: every triangle is turned so its geometric normal opposes the wanted one.

const NO_EDGE := 100.0

# zones (COLOR.r * 255)
const Z_STONE := 0        # dressed ashlar: walls, towers
const Z_RUBBLE := 1       # rough footings, plinths
const Z_FLAG := 2         # flagstones: wall walks, floors, ledges
const Z_SLATE := 3        # slate roofs
const Z_TILE := 4         # clay tile roofs
const Z_TIMBER := 5       # dark oak: beams, doors, hoardings
const Z_PLASTER := 6      # lime plaster between timbers
const Z_IRON := 7         # portcullis, hinges, finials
const Z_DARK := 8         # slits and passages: deep shadow
const Z_DOOR := 9         # planked doors
const Z_CLOTH_A := 10     # banner, first colour
const Z_CLOTH_B := 11     # banner, second colour
const Z_GLOW := 12        # lit windows, torches
const Z_GOLD := 13        # finials, weathercocks
const Z_THATCH := 14      # thatched roofs of the small houses

# flags (COLOR.b * 255)
const F_PLAIN := 1        # no joints (smooth plaster, cloth)
const F_ROUND := 2        # a curved face (the shader may bend its joints)
const F_MOSS := 4         # moss allowed
const F_STEP := 8         # stepped-arch courses
const F_HIGH := 16        # a high course (finer stones)
const F_SOFT := 32        # soft edges (no wear)
const F_RUIN := 64        # crumbly edges

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var tans := PackedFloat32Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var cols := PackedColorArray()
var cust0 := PackedFloat32Array()
var cust1 := PackedFloat32Array()

# current attributes, set before adding faces
var zone := Z_STONE
var pseed := 0.0
var flags := 0
var owner := 0
var anchor := Vector3.ZERO
var flow := Vector3.UP             # e1 hint for add_poly
var label := ""


func begin(z: int, s: float, f: int, own: int, anc: Vector3, lab: String = "") -> void:
	zone = z
	pseed = s
	flags = f
	owner = own
	anchor = anc
	label = lab


func append_mesh(o: CFMesh) -> void:
	## Adds another collector's faces.
	if o == null:
		return
	verts.append_array(o.verts)
	norms.append_array(o.norms)
	tans.append_array(o.tans)
	uvs.append_array(o.uvs)
	uv2s.append_array(o.uv2s)
	cols.append_array(o.cols)
	cust0.append_array(o.cust0)
	cust1.append_array(o.cust1)


func vertex_count() -> int:
	return verts.size()


func tri_count() -> int:
	return verts.size() / 3


func push_tri(p: Array, n: Array, uv: Array, t: Vector3, w: float, c0: Array, fl: int, want: Vector3) -> void:
	## One triangle with per-vertex normals / uvs / edge distances (Vector4), turned to face `want`.
	push_tri3(p[0], p[1], p[2], n[0], n[1], n[2], uv[0], uv[1], uv[2], t, w, c0[0], c0[1], c0[2], fl, want)


func push_tri3(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2,
		t: Vector3, w: float, c0a: Vector4, c0b: Vector4, c0c: Vector4, fl: int, want: Vector3) -> void:
	## The same without the arrays (the walls and ledges make tens of thousands).
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-16:
		return   # only truly zero-area triangles are dropped (the triangulator's own limit is far above)
	var col := Color(float(zone) / 255.0, pseed, float(fl) / 255.0, 1.0)
	_vertex(a, na, ua, c0a, t, w, col)
	if cr.dot(want) > 0.0:
		_vertex(c, nc, uc, c0c, t, w, col)   # clockwise from the front
		_vertex(b, nb, ub, c0b, t, w, col)
	else:
		_vertex(b, nb, ub, c0b, t, w, col)
		_vertex(c, nc, uc, c0c, t, w, col)


func _vertex(p: Vector3, n: Vector3, uv: Vector2, c0: Vector4, t: Vector3, w: float, col: Color) -> void:
	verts.append(p)
	norms.append(n)
	tans.append(t.x)
	tans.append(t.y)
	tans.append(t.z)
	tans.append(w)
	uvs.append(uv)
	uv2s.append(Vector2.ZERO)
	cols.append(col)
	cust0.append(c0.x)
	cust0.append(c0.y)
	cust0.append(c0.z)
	cust0.append(c0.w)
	cust1.append(anchor.x)
	cust1.append(anchor.y)
	cust1.append(anchor.z)
	cust1.append(float(owner))


static func face_frame(n: Vector3, hint: Vector3) -> Array:
	## [e1, e2] for a face with normal n; e1 follows the hint projected on the face.
	var e1 := hint - n * hint.dot(n)
	if e1.length_squared() < 0.04:
		e1 = Vector3.RIGHT - n * n.x
		if e1.length_squared() < 0.04:
			e1 = Vector3.UP - n * n.y
	e1 = e1.normalized()
	var e2 := n.cross(e1)
	return [e1, e2]


func add_poly(loop: PackedVector3Array, n: Vector3 = Vector3.ZERO, edge_mask: int = -1) -> void:
	## A flat convex polygon turned to face n (or its own normal when n is zero), fan-triangulated.
	## edge_mask bit i = the edge loop[i] -> loop[i+1] is a real edge (wear, bevel line); -1 = all real.
	var cnt := loop.size()
	if cnt < 3:
		return
	var nn := Vector3.ZERO
	for i in range(1, cnt - 1):
		nn += (loop[i] - loop[0]).cross(loop[i + 1] - loop[0])
	if nn.length_squared() < 1e-14:
		return
	nn = nn.normalized()
	if n != Vector3.ZERO and nn.dot(n) < 0.0:
		nn = -nn
		var rev := PackedVector3Array()
		for i in range(cnt - 1, -1, -1):
			rev.append(loop[i])
		loop = rev
		edge_mask = _reverse_mask(edge_mask, cnt)
	var fr := face_frame(nn, flow)
	var e1: Vector3 = fr[0]
	var e2: Vector3 = fr[1]
	for i in range(1, cnt - 1):
		var a := loop[0]
		var b := loop[i]
		var c := loop[i + 1]
		var tn := (b - a).cross(c - a)
		var area2 := tn.length()
		if area2 < 1e-7:
			continue
		var ha := area2 / maxf((c - b).length(), 1e-6)
		var hb := area2 / maxf((c - a).length(), 1e-6)
		var hc := area2 / maxf((b - a).length(), 1e-6)
		var bc_real := (edge_mask >> i) & 1 == 1
		var ab_real := i == 1 and (edge_mask & 1) == 1
		var ca_real := i + 1 == cnt - 1 and ((edge_mask >> (cnt - 1)) & 1) == 1
		var ca := Vector4(ha if bc_real else NO_EDGE, 0.0 if ca_real else NO_EDGE, 0.0 if ab_real else NO_EDGE, NO_EDGE)
		var cb := Vector4(0.0 if bc_real else NO_EDGE, hb if ca_real else NO_EDGE, 0.0 if ab_real else NO_EDGE, NO_EDGE)
		var cc := Vector4(0.0 if bc_real else NO_EDGE, 0.0 if ca_real else NO_EDGE, hc if ab_real else NO_EDGE, NO_EDGE)
		push_tri([a, b, c], [nn, nn, nn], [Vector2(a.dot(e1), a.dot(e2)), Vector2(b.dot(e1), b.dot(e2)), Vector2(c.dot(e1), c.dot(e2))],
			e1, 1.0, [ca, cb, cc], flags, nn)


static func _reverse_mask(mask: int, cnt: int) -> int:
	## Edge i (loop[i] -> loop[i+1]) becomes edge cnt-2-i after the loop is reversed.
	if mask == -1:
		return -1
	var out := 0
	for i in cnt:
		if (mask >> i) & 1 == 1:
			var j := (cnt - 2 - i + cnt) % cnt
			out |= 1 << j
	return out


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3 = Vector3.ZERO) -> void:
	add_poly(PackedVector3Array([a, b, c, d]), n)


func add_smooth_tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, t: Vector3) -> void:
	## Smooth-shaded triangle (lathes, cylinders): no edge wear.
	var nf := (b - a).cross(c - a)
	if nf.length_squared() < 1e-14:
		return
	var e := Vector4(NO_EDGE, NO_EDGE, NO_EDGE, NO_EDGE)
	push_tri([a, b, c], [na, nb, nc], [ua, ub, uc], t, 1.0, [e, e, e], flags | F_SOFT, (na + nb + nc))


# --- solids -------------------------------------------------------------------------

func add_loft(rings: Array, cap_start: bool, cap_end: bool) -> void:
	## Rings of equal point count (PackedVector3Array each) joined by quads; optional end caps.
	var m := rings.size()
	if m < 1:
		return
	var k: int = rings[0].size()
	var axis_c := []
	for r in rings:
		var c := Vector3.ZERO
		for p in r:
			c += p
		axis_c.append(c / float(k))
	for j in range(m - 1):
		var ra: PackedVector3Array = rings[j]
		var rb: PackedVector3Array = rings[j + 1]
		var mid: Vector3 = (axis_c[j] + axis_c[j + 1]) * 0.5
		for i in k:
			var i2 := (i + 1) % k
			var quad := PackedVector3Array([ra[i], ra[i2], rb[i2], rb[i]])
			var qc := (ra[i] + ra[i2] + rb[i2] + rb[i]) * 0.25
			var out := qc - mid
			_add_quad_split(quad, out)
	if cap_start:
		var r0: PackedVector3Array = rings[0]
		var o0: Vector3 = axis_c[0] - (axis_c[1] if m > 1 else axis_c[0] + Vector3.FORWARD)
		add_poly(r0, o0.normalized())
	if cap_end:
		var r1: PackedVector3Array = rings[m - 1]
		var o1: Vector3 = axis_c[m - 1] - (axis_c[m - 2] if m > 1 else axis_c[0] - Vector3.FORWARD)
		add_poly(r1, o1.normalized())


func _add_quad_split(q: PackedVector3Array, out: Vector3) -> void:
	## A loft quad: one flat face when it is planar enough, else two triangles.
	var n1 := (q[1] - q[0]).cross(q[2] - q[0])
	var n2 := (q[2] - q[0]).cross(q[3] - q[0])
	var l1 := n1.length()
	var l2 := n2.length()
	if l1 < 1e-9 and l2 < 1e-9:
		return
	if l1 < 1e-9:
		add_poly(PackedVector3Array([q[0], q[2], q[3]]), out, 0b110)
		return
	if l2 < 1e-9:
		add_poly(PackedVector3Array([q[0], q[1], q[2]]), out, 0b011)
		return
	if (n1 / l1).dot(n2 / l2) > 0.995:
		add_poly(q, out)
	else:
		add_poly(PackedVector3Array([q[0], q[1], q[2]]), out, 0b011)
		add_poly(PackedVector3Array([q[0], q[2], q[3]]), out, 0b110)


func add_box(center: Vector3, ax: Vector3, ay: Vector3, az: Vector3, he: Vector3) -> void:
	## Oriented box (axes ax, ay, az unit, half extents he).
	var rings := []
	var prof := [Vector2(he.x, he.y), Vector2(-he.x, he.y), Vector2(-he.x, -he.y), Vector2(he.x, -he.y)]
	for s in [-1.0, 1.0]:
		var r := PackedVector3Array()
		for p in prof:
			r.append(center + ax * p.x + ay * p.y + az * (he.z * s))
		rings.append(r)
	var save := flow
	flow = az
	add_loft(rings, true, true)
	flow = save


func add_lathe(base: Vector3, axis: Vector3, prof: Array, segs: int) -> void:
	## Surface of revolution round axis from base; prof = [Vector2(radius, height), ...] in order.
	segs += segs % 2
	var ax := axis.normalized()
	var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var bx := ax.cross(ref).normalized()
	var by := bx.cross(ax).normalized()
	for j in range(prof.size() - 1):
		var p0: Vector2 = prof[j]
		var p1: Vector2 = prof[j + 1]
		var dr := p1.x - p0.x
		var dh := p1.y - p0.y
		var pn := Vector2(dh, -dr).normalized()
		if pn == Vector2.ZERO:
			continue
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := bx * cos(a0) + by * sin(a0)
			var d1 := bx * cos(a1) + by * sin(a1)
			var v00 := base + d0 * p0.x + ax * p0.y
			var v01 := base + d1 * p0.x + ax * p0.y
			var v10 := base + d0 * p1.x + ax * p1.y
			var v11 := base + d1 * p1.x + ax * p1.y
			var n0 := (d0 * pn.x + ax * pn.y).normalized()
			var n1 := (d1 * pn.x + ax * pn.y).normalized()
			var t0 := ax.cross(d0)
			var u0 := Vector2(a0 * maxf(p0.x, 0.05), p0.y)
			var u1 := Vector2(a1 * maxf(p0.x, 0.05), p0.y)
			var u2 := Vector2(a0 * maxf(p1.x, 0.05), p1.y)
			var u3 := Vector2(a1 * maxf(p1.x, 0.05), p1.y)
			if p0.x > 1e-5:
				add_smooth_tri(v00, v01, v11, n0, n1, n1, u0, u1, u3, t0)
			if p1.x > 1e-5:
				add_smooth_tri(v00, v11, v10, n0, n1, n0, u0, u3, u2, t0)


# --- output -------------------------------------------------------------------------

func commit(mesh: ArrayMesh, material: Material) -> int:
	## Adds the collected faces as one surface; returns the surface index or -1 when empty.
	if verts.is_empty():
		return -1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_CUSTOM0] = cust0
	arr[Mesh.ARRAY_CUSTOM1] = cust1
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | \
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	var idx := mesh.get_surface_count() - 1
	if material:
		mesh.surface_set_material(idx, material)
	return idx


func aabb() -> AABB:
	if verts.is_empty():
		return AABB()
	var lo := verts[0]
	var hi := verts[0]
	for p in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)
