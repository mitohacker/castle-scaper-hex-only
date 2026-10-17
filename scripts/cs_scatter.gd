class_name CSScatter
extends RefCounted
## Trees and rocks standing on the landscape (CSWorld), instanced like the castle's props. What stands in a column depends on what is round it
## (CSWorld.ctx): the same single tree is an oak on open meadow, a pine on a mountain or beside rock, a willow by the water, a poplar lining
## a road, an orchard tree beside the castle, and a forest of pines and tall oaks when trees surround it; none stands above the tree line.
## Rocks are boulders on a rock column and scree on a mountain's steep slope, pebbles on the meadow beside them, cut blocks where a column of
## rock touches the castle (a quarry), a standing stone where a road comes to nothing.

enum { M_OAK, M_PINE, M_POPLAR, M_WILLOW, M_ORCHARD, M_BUSH, M_BOULDER_A, M_BOULDER_B, M_BOULDER_C, M_SLAB, M_BLOCK, M_DEAD }
const MESH_COUNT := 12
const TREE_LINE := 8.5
const SNOW_LINE := 11.0
# paint zones (COLOR.r * 255), read by shaders/cs_flora.gdshader
const Z_BARK := 0
const Z_OAK := 1
const Z_PINE := 2
const Z_WILLOW := 3
const Z_BLOSSOM := 4
const Z_ROCK := 5
const Z_DRESSED := 6

var world: CSWorld
var grid: CSGrid
var town: CSTown
var inst: Array = []            # [mesh, Transform3D, Color custom]
var counts := {}                # kind -> how many (for the tests and the stats line)
var species := {}               # column -> the tree species it grew ("oak", "pine", ...)
var _rng := RandomNumberGenerator.new()


func build(w: CSWorld) -> void:
	world = w
	grid = w.grid
	town = w.town
	for v: int in w.ground:
		_trees(v)
		_rocks(v)
	for v: int in w.garden:
		_trees(v)


func _count(kind: String) -> void:
	counts[kind] = int(counts.get(kind, 0)) + 1


func _seed(v: int, salt: int) -> void:
	_rng.seed = hash(v * 7919 + salt * 104729 + 12345)


func _points_in_cell(v: int, n: int, min_d: float, margin: float) -> Array:
	## Up to n points inside the cell at least min_d apart, margin away from the cell's sides, by dart throwing.
	var poly := grid.dual(v)
	var c := grid.verts[v]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var out := []
	var tries := 0
	while out.size() < n and tries < 90:
		tries += 1
		var p := Vector2(_rng.randf_range(lo.x, hi.x), _rng.randf_range(lo.y, hi.y))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var ok := true
		for i in poly.size():
			if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p) < margin:
				ok = false
				break
		if not ok:
			continue
		for q: Vector2 in out:
			if q.distance_to(p) < min_d:
				ok = false
				break
		if ok and world.road_clear(p, 1.4):
			out.append(p)
	return out


func species_for(v: int) -> String:
	var cx := world.ctx(v)
	var alt := world.altitude(v)
	var t := town.wild_trees(v)
	if alt > TREE_LINE:
		return ""
	if alt > 4.5 or int(cx.mount) >= 2 or (int(cx.mount) >= 1 and alt > 2.0):
		return "pine"
	if int(cx.castle) >= 1 and int(cx.road) == 0:
		return "orchard"
	if int(cx.road) >= 1 and t == 1:
		return "poplar"
	if int(cx.water) >= 2 and alt < 1.5:
		return "willow"
	if int(cx.rock) >= 1 and int(cx.tree) < 2:
		return "pine"
	if t == 3 and int(cx.tree) >= 3:
		return "forest"
	return "oak"


func _trees(v: int) -> void:
	var t := town.wild_trees(v)
	if t <= 0:
		return
	var sp := species_for(v)
	if sp == "":
		return
	species[v] = sp
	_seed(v, 1)
	var n: int = [0, 1, 3, 7][t]
	var min_d: float = [0.0, 0.0, 1.9, 1.15][t]
	var margin := 0.7
	if sp == "orchard":
		n = [0, 1, 4, 6][t]
		min_d = 1.9
	var pts := _points_in_cell(v, n, min_d, margin)
	if sp == "poplar" or (sp == "orchard" and t == 1):
		# a lone roadside tree stands toward the road, an orchard tree toward the castle; the cell's middle is the fallback
		pass
	for p: Vector2 in pts:
		var alt := world.height_at(p) - CSWorld.G
		if alt > TREE_LINE:
			continue
		var kind := sp
		if sp == "forest":
			kind = "pine" if _rng.randf() < 0.45 else "oak"
		var mesh := M_OAK
		var scale := _rng.randf_range(0.85, 1.25)
		match kind:
			"pine":
				mesh = M_PINE
				scale *= (1.0 - clampf((alt - 3.0) / 9.0, 0.0, 0.45))
			"poplar":
				mesh = M_POPLAR
			"willow":
				mesh = M_WILLOW
			"orchard":
				mesh = M_ORCHARD
				scale *= 0.95
			_:
				mesh = M_OAK
		if sp == "forest":
			scale *= 1.18
		var y := world.height_at(p) - 0.12 * scale
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale * _rng.randf_range(0.92, 1.12), scale)), Vector3(p.x, y, p.y))
		var snow := smoothstep(SNOW_LINE - 3.0, SNOW_LINE, alt + CSWorld.G) if mesh == M_PINE else 0.0
		inst.append([mesh, xf, Color(_rng.randf(), snow, float(t) / 3.0, 0.0)])
		_count(kind)
	# a bush or two under a grove's trees
	if t >= 2 and sp != "pine" and sp != "orchard":
		for p: Vector2 in _points_in_cell(v, 2, 1.0, 0.6):
			var y2 := world.height_at(p)
			inst.append([M_BUSH, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3)), Vector3(p.x, y2 - 0.05, p.y)), Color(_rng.randf(), 0.0, 0.0, 0.0)])
			_count("bush")


func _rocks(v: int) -> void:
	var h := town.wild_heights(v)
	var cx := world.ctx(v)
	_seed(v, 2)
	var r_levels := 0
	for i in h.length():
		if h[i] == "r":
			r_levels += 1
	var alt := world.altitude(v)
	if r_levels > 0:
		# boulders and tumbled stones lie over a rock column, more of them the higher it stands; against the castle they are cut blocks
		var n := 3 + 2 * r_levels
		for p: Vector2 in _points_in_cell(v, n, 0.85, 0.35):
			var big := _rng.randf() < 0.3
			var s := _rng.randf_range(0.55, 1.0) * (1.4 if big else 1.0)
			var mesh: int = [M_BOULDER_A, M_BOULDER_B, M_BOULDER_C][_rng.randi() % 3]
			if int(cx.castle) >= 1 and _rng.randf() < 0.55:
				mesh = M_BLOCK
				s *= 0.9
			_place_rock(mesh, p, s)
			_count("boulder" if mesh != M_BLOCK else "block")
	elif alt > 3.0:
		# scree: a few crags standing out of a mountain's slope
		var n2 := clampi(int(alt / 6.0), 0, 3)
		for p: Vector2 in _points_in_cell(v, n2, 1.8, 0.3):
			var s2 := _rng.randf_range(0.35, 0.8)
			_place_rock([M_BOULDER_A, M_BOULDER_B, M_BOULDER_C][_rng.randi() % 3], p, s2)
			_count("crag")
	elif int(cx.rock) + int(cx.mount) >= 1 and alt < 0.5:
		# meadow beside rock: pebbles and a boulder fallen from it
		for p: Vector2 in _points_in_cell(v, 1 + (_rng.randi() % 2), 1.3, 0.4):
			_place_rock([M_BOULDER_A, M_BOULDER_B, M_BOULDER_C][_rng.randi() % 3], p, _rng.randf_range(0.35, 0.65))
			_count("pebbles")


func _place_rock(mesh: int, p: Vector2, s: float) -> void:
	var y := world.height_at(p) - 0.18 * s
	var up := world.normal_at(p)
	var b := Basis(Vector3.UP, _rng.randf() * TAU)
	var tilt := Quaternion(Vector3.UP, up).slerp(Quaternion.IDENTITY, 0.4)
	b = Basis(tilt) * b
	b = b.scaled(Vector3(s * _rng.randf_range(0.9, 1.3), s * _rng.randf_range(0.7, 1.1), s * _rng.randf_range(0.9, 1.3)))
	inst.append([mesh, Transform3D(b, Vector3(p.x, y, p.y)), Color(_rng.randf(), 0.0, 0.0, 0.0)])


func buffers() -> Array:
	var lists := []
	for _m in MESH_COUNT:
		lists.append([])
	for it: Array in inst:
		(lists[int(it[0])] as Array).append(it)
	var out := []
	for m in MESH_COUNT:
		var list: Array = lists[m]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 16)
		var j := 0
		for it: Array in list:
			var xf: Transform3D = it[1]
			var cd: Color = it[2]
			buf[j] = xf.basis.x.x
			buf[j + 1] = xf.basis.y.x
			buf[j + 2] = xf.basis.z.x
			buf[j + 3] = xf.origin.x
			buf[j + 4] = xf.basis.x.y
			buf[j + 5] = xf.basis.y.y
			buf[j + 6] = xf.basis.z.y
			buf[j + 7] = xf.origin.y
			buf[j + 8] = xf.basis.x.z
			buf[j + 9] = xf.basis.y.z
			buf[j + 10] = xf.basis.z.z
			buf[j + 11] = xf.origin.z
			buf[j + 12] = cd.r
			buf[j + 13] = cd.g
			buf[j + 14] = cd.b
			buf[j + 15] = cd.a
			j += 16
		out.append(buf)
	return out


func multimeshes(meshes: Array) -> Array:
	var out := []
	var bufs := buffers()
	for m in MESH_COUNT:
		var buf: PackedFloat32Array = bufs[m]
		if buf.is_empty():
			out.append(null)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[m]
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		out.append(mm)
	return out


# --- the meshes (made once, in code) ---------------------------------------------------------------

class MB:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var height := 6.0           # the mesh's height: vertex colour alpha = y / height (wind sway weight)

	func add(p: Vector3, n: Vector3, zone: int, tone: float) -> void:
		verts.append(p)
		norms.append(n)
		cols.append(Color(float(zone) / 255.0, tone, 0.0, clampf(p.y / height, 0.0, 1.0)))

	func tri_flat(a: Vector3, b: Vector3, c: Vector3, zone: int, tone: float) -> void:
		var n := (b - a).cross(c - a).normalized()
		# Godot's front faces are clockwise from the front: keep the triangle as is when its normal looks out of the solid's centre
		add(a, n, zone, tone)
		add(c, n, zone, tone)
		add(b, n, zone, tone)

	func blob(centre: Vector3, radii: Vector3, seed: int, zone: int, tone: float, lump: float, flat: bool) -> void:
		## A lumpy ellipsoid: an icosphere, once subdivided, every vertex pushed out or in by noise. Smooth shading (leaf masses) or facets (rock).
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var t := (1.0 + sqrt(5.0)) / 2.0
		var base := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
		var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8],
			[3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
		var pts := []
		for b: Vector3 in base:
			pts.append(b.normalized())
		var cache := {}
		var tris := []
		for f: Array in faces:
			var m: Array = []
			for k in 3:
				var a: int = f[k]
				var b: int = f[(k + 1) % 3]
				var key := mini(a, b) * 1000 + maxi(a, b)
				if not cache.has(key):
					pts.append(((pts[a] as Vector3) + (pts[b] as Vector3)).normalized())
					cache[key] = pts.size() - 1
				m.append(cache[key])
			tris.append([f[0], m[0], m[2]])
			tris.append([f[1], m[1], m[0]])
			tris.append([f[2], m[2], m[1]])
			tris.append([m[0], m[1], m[2]])
		var disp := []
		for p: Vector3 in pts:
			var k := 1.0 + (rng.randf() - 0.5) * lump
			disp.append(centre + Vector3(p.x * radii.x, p.y * radii.y, p.z * radii.z) * k)
		for tr: Array in tris:
			var a: Vector3 = disp[tr[0]]
			var b: Vector3 = disp[tr[1]]
			var c: Vector3 = disp[tr[2]]
			if flat:
				var n := (b - a).cross(c - a)
				if n.dot(a - centre) < 0.0:
					tri_flat(a, c, b, zone, tone)
				else:
					tri_flat(a, b, c, zone, tone)
			else:
				var na: Vector3 = ((pts[tr[0]] as Vector3) / radii).normalized()
				var nb: Vector3 = ((pts[tr[1]] as Vector3) / radii).normalized()
				var nc: Vector3 = ((pts[tr[2]] as Vector3) / radii).normalized()
				var fn := (b - a).cross(c - a)
				if fn.dot(a - centre) < 0.0:
					add(a, na, zone, tone)
					add(c, nc, zone, tone)
					add(b, nb, zone, tone)
				else:
					add(a, na, zone, tone)
					add(b, nb, zone, tone)
					add(c, nc, zone, tone)

	func cone(base: Vector3, r: float, h: float, sides: int, zone: int, tone: float, droop: float) -> void:
		## A pointed skirt of foliage: a ring at the base (drooping a little below it), the tip above.
		var tip := base + Vector3(0, h, 0)
		var ring: Array = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var rr := r * (1.0 + 0.18 * sin(a * 3.0 + base.y))
			ring.append(base + Vector3(cos(a) * rr, -droop, sin(a) * rr))
		for i in sides:
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i + 1) % sides]
			var nrm_a := Vector3(a.x - base.x, r * 0.55, a.z - base.z).normalized()
			var nrm_b := Vector3(b.x - base.x, r * 0.55, b.z - base.z).normalized()
			var nt := ((nrm_a + nrm_b) * 0.5 + Vector3(0, 0.8, 0)).normalized()
			add(a, nrm_a, zone, tone)
			add(tip, nt, zone, tone)
			add(b, nrm_b, zone, tone)
		# the underside
		for i in sides:
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i + 1) % sides]
			add(a, Vector3.DOWN, zone, tone * 0.7)
			add(b, Vector3.DOWN, zone, tone * 0.7)
			add(base + Vector3(0, -droop, 0), Vector3.DOWN, zone, tone * 0.7)

	func trunk(y0: float, y1: float, r0: float, r1: float, sides: int, zone: int) -> void:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p2 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p3 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			add(p0, n0, zone, 0.5)
			add(p3, n0, zone, 0.5)
			add(p1, n1, zone, 0.5)
			add(p1, n1, zone, 0.5)
			add(p3, n0, zone, 0.5)
			add(p2, n1, zone, 0.5)

	func box_block(c: Vector3, h: Vector3, zone: int, tone: float, chip: float, seed: int) -> void:
		## A cut stone: a box with slightly leaning faces.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var cs := []
		for i in 8:
			var sx := -1.0 if (i & 1) == 0 else 1.0
			var sy := -1.0 if (i & 2) == 0 else 1.0
			var sz := -1.0 if (i & 4) == 0 else 1.0
			cs.append(c + Vector3(sx * h.x, sy * h.y, sz * h.z) * (1.0 + (rng.randf() - 0.5) * chip))
		for f: Array in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
			var a: Vector3 = cs[f[0]]
			var b: Vector3 = cs[f[1]]
			var d: Vector3 = cs[f[2]]
			var e: Vector3 = cs[f[3]]
			var n := (b - a).cross(d - a)
			if n.dot(a - c) < 0.0:
				tri_flat(a, b, d, zone, tone)
				tri_flat(a, d, e, zone, tone)
			else:
				tri_flat(a, d, b, zone, tone)
				tri_flat(a, e, d, zone, tone)

	func commit(p_height: float) -> ArrayMesh:
		for i in cols.size():
			var c := cols[i]
			cols[i] = Color(c.r, c.g, c.b, clampf(verts[i].y / p_height, 0.0, 1.0))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		if not verts.is_empty():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func make_meshes() -> Array:
	var out := []
	for m in MESH_COUNT:
		var mb := MB.new()
		var h := 6.0
		match m:
			M_OAK:
				h = 5.2
				mb.trunk(0.0, 2.2, 0.24, 0.12, 7, Z_BARK)
				mb.trunk(1.6, 2.8, 0.12, 0.05, 5, Z_BARK)
				for b: Array in [[Vector3(0.0, 3.1, 0.0), Vector3(1.55, 1.25, 1.55)], [Vector3(1.0, 2.7, 0.3), Vector3(1.05, 0.95, 1.05)], [Vector3(-0.85, 2.8, -0.35), Vector3(1.1, 0.95, 1.1)],
						[Vector3(0.2, 3.9, 0.55), Vector3(1.0, 0.85, 1.0)], [Vector3(-0.35, 3.7, -0.75), Vector3(0.95, 0.8, 0.95)], [Vector3(0.7, 3.5, -0.8), Vector3(0.85, 0.75, 0.85)]]:
					mb.blob(b[0], b[1], 11 + int((b[0] as Vector3).x * 10.0), Z_OAK, 0.35 + 0.3 * float(absf((b[0] as Vector3).z)), 0.34, false)
			M_PINE:
				h = 6.4
				mb.trunk(0.0, 2.4, 0.2, 0.1, 6, Z_BARK)
				for c: Array in [[1.0, 1.5, 1.9, 0.5], [2.1, 1.25, 1.8, 0.45], [3.1, 1.0, 1.7, 0.4], [4.1, 0.75, 1.55, 0.35], [5.0, 0.45, 1.4, 0.3]]:
					mb.cone(Vector3(0, c[0], 0), c[1], c[2], 9, Z_PINE, 0.35 + 0.1 * c[0] / 5.0, c[3])
			M_POPLAR:
				h = 7.4
				mb.trunk(0.0, 1.8, 0.16, 0.1, 6, Z_BARK)
				mb.blob(Vector3(0, 4.2, 0), Vector3(0.8, 3.0, 0.8), 21, Z_OAK, 0.75, 0.3, false)
				mb.blob(Vector3(0.1, 3.4, 0.2), Vector3(0.7, 2.0, 0.7), 22, Z_OAK, 0.6, 0.3, false)
			M_WILLOW:
				h = 4.8
				mb.trunk(0.0, 1.9, 0.3, 0.16, 7, Z_BARK)
				mb.blob(Vector3(0, 3.0, 0), Vector3(2.2, 1.15, 2.2), 31, Z_WILLOW, 0.5, 0.25, false)
				for i in 9:
					var a := TAU * float(i) / 9.0
					mb.blob(Vector3(cos(a) * 1.85, 1.85, sin(a) * 1.85), Vector3(0.38, 1.25, 0.38), 40 + i, Z_WILLOW, 0.4 + 0.3 * float(i % 3) / 2.0, 0.3, false)
			M_ORCHARD:
				h = 3.6
				mb.trunk(0.0, 1.2, 0.13, 0.08, 6, Z_BARK)
				mb.blob(Vector3(0, 2.2, 0), Vector3(1.25, 1.0, 1.25), 51, Z_OAK, 0.8, 0.28, false)
				for i in 9:
					var a2 := TAU * float(i) / 9.0 + 0.4
					var py := 2.1 + 0.5 * sin(float(i) * 2.3)
					mb.blob(Vector3(cos(a2) * 1.12, py, sin(a2) * 1.12), Vector3(0.22, 0.2, 0.22), 60 + i, Z_BLOSSOM, 0.5, 0.2, false)
			M_BUSH:
				h = 1.2
				mb.blob(Vector3(0, 0.45, 0), Vector3(0.75, 0.55, 0.75), 71, Z_OAK, 0.3, 0.4, false)
				mb.blob(Vector3(0.4, 0.35, 0.2), Vector3(0.5, 0.4, 0.5), 72, Z_OAK, 0.6, 0.4, false)
			M_BOULDER_A:
				h = 1.4
				mb.blob(Vector3(0, 0.5, 0), Vector3(0.9, 0.55, 0.8), 81, Z_ROCK, 0.5, 0.45, true)
			M_BOULDER_B:
				h = 1.6
				mb.blob(Vector3(0, 0.6, 0), Vector3(0.7, 0.7, 0.95), 82, Z_ROCK, 0.3, 0.5, true)
				mb.blob(Vector3(0.7, 0.25, 0.2), Vector3(0.4, 0.28, 0.4), 83, Z_ROCK, 0.6, 0.4, true)
			M_BOULDER_C:
				h = 1.8
				mb.blob(Vector3(0, 0.65, 0), Vector3(0.8, 0.8, 0.7), 84, Z_ROCK, 0.7, 0.4, true)
				mb.blob(Vector3(-0.55, 0.25, 0.4), Vector3(0.45, 0.3, 0.4), 85, Z_ROCK, 0.4, 0.4, true)
			M_SLAB:
				h = 2.6
				mb.box_block(Vector3(0, 1.2, 0), Vector3(0.38, 1.2, 0.22), Z_ROCK, 0.5, 0.35, 91)
			M_BLOCK:
				h = 1.2
				mb.box_block(Vector3(0, 0.38, 0), Vector3(0.55, 0.38, 0.45), Z_DRESSED, 0.5, 0.12, 92)
				mb.box_block(Vector3(0.55, 0.28, 0.5), Vector3(0.4, 0.28, 0.35), Z_DRESSED, 0.3, 0.12, 93)
			M_DEAD:
				h = 3.6
				mb.trunk(0.0, 3.2, 0.2, 0.05, 6, Z_BARK)
				mb.trunk(1.6, 2.6, 0.08, 0.02, 4, Z_BARK)
		out.append(mb.commit(h))
	return out
