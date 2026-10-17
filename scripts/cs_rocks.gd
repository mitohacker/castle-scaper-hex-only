class_name CSRocks
extends RefCounted
## The ground the castle stands on, made in code: a rocky skirt round the foot of the land (talus and boulders running out into the
## water, shaded by cs_rock.gdshader) and the sea floor (sand, rock patches, falling away from the island). The skirt is built from
## the land's shore loops, from the same cell outlines CSBuild uses, and stays off the edges of gate passages so an arch still opens
## onto the water.

const RINGS := [[-0.45, 2.3], [0.0, 2.0], [0.45, 1.5], [1.0, 0.85], [1.6, 0.25], [2.3, -0.4], [3.1, -1.1], [4.1, -1.9], [5.4, -2.8], [7.0, -3.8]]   # [metres out, height]
const STEP := 0.5

static var _noise: FastNoiseLite


static func _n() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.35
		_noise.fractal_octaves = 4
		_noise.seed = 11
	return _noise


static func shore_loops(grid: CSGrid, land: Dictionary, skip_nb: Dictionary = {}) -> Array:
	## [{"pts": PackedVector2Array, "skip": PackedByteArray}]: closed loops round the land, outward normal = (d.y, -d.x).
	var next := {}
	for v: int in land:
		var nb: PackedInt32Array = grid.nbrs[v]
		for i in nb.size():
			if land.has(nb[i]):
				continue
			var f := grid.face(v, i)
			next[f[0]] = [f[1], 1 if (str(land[v]) == "passage" or skip_nb.has(nb[i])) else 0]
	var out := []
	var guard := 0
	while not next.is_empty() and guard < 20000:
		guard += 1
		var start: Vector2 = next.keys()[0]
		var pts := PackedVector2Array()
		var skip := PackedByteArray()
		var cur := start
		var steps := 0
		while next.has(cur) and steps < 4000:
			steps += 1
			var e: Array = next[cur]
			pts.append(cur)
			skip.append(e[1])
			next.erase(cur)
			cur = e[0]
			if cur == start:
				break
		if pts.size() >= 3:
			out.append({"pts": pts, "skip": skip})
	return out


static func skirt_mesh(loops: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var noise := _n()
	for loop: Dictionary in loops:
		var pts: PackedVector2Array = loop.pts
		var skip: PackedByteArray = loop.skip
		var n := pts.size()
		var nrm := PackedVector2Array()
		for i in n:
			var a := pts[(i + n - 1) % n]
			var c := pts[(i + 1) % n]
			var d := ((pts[i] - a).normalized() + (c - pts[i]).normalized()).normalized()
			nrm.append(Vector2(d.y, -d.x))
		# resample each edge, normals blended, then the rings
		for i in n:
			if skip[i] != 0:
				continue
			var j := (i + 1) % n
			var len := pts[i].distance_to(pts[j])
			var segs := maxi(1, int(ceil(len / STEP)))
			var base := verts.size()
			for sgi in segs + 1:
				var t := float(sgi) / float(segs)
				var p := pts[i].lerp(pts[j], t)
				var nn := nrm[i].lerp(nrm[j], t).normalized()
				for r in RINGS.size():
					var s: float = RINGS[r][0]
					var y: float = RINGS[r][1]
					var wp := Vector3(p.x + nn.x * s, 0.0, p.y + nn.y * s)
					var f := noise.get_noise_3d(wp.x * 0.9, y * 0.7, wp.z * 0.9)
					var f2 := noise.get_noise_2d(wp.x * 2.3 + 40.0, wp.z * 2.3)
					var big := noise.get_noise_2d(wp.x * 0.33 + 9.0, wp.z * 0.33)
					var grow := clampf(0.4 + s * 0.3, 0.0, 1.6)
					var out := s + (f * 0.9 + big * 0.9) * grow
					var hy := y + (f2 * 0.6 + f * 0.9 + big * 1.4) * grow
					if r == 0:
						out = s
						hy = y
					verts.append(Vector3(p.x + nn.x * out, hy, p.y + nn.y * out))
			var stride := RINGS.size()
			for sgi in segs:
				for r in stride - 1:
					var a := base + sgi * stride + r
					var b := base + (sgi + 1) * stride + r
					# the outward side is the front: (along the edge) x (up) points out
					idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	# smooth normals from the faces, turned to the open side
	var nr := PackedVector3Array()
	nr.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var fn := (b - a).cross(c - a)
		for k in 3:
			nr[idx[t + k]] += fn
	for i in nr.size():
		nr[i] = nr[i].normalized() if nr[i].length_squared() > 1e-12 else Vector3.UP
		if nr[i].y < 0.0:
			nr[i] = -nr[i]
	arr[Mesh.ARRAY_NORMAL] = nr
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func seabed_mesh() -> ArrayMesh:
	## A disc round the island, dense near it: rings spaced as r = R * (i / N)^2.
	var rings := 90
	var segs := 160
	var rmax := 900.0
	var noise := _n()
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var r := rmax * pow(float(i) / float(rings), 2.2)
		for j in segs:
			var a := TAU * float(j) / float(segs)
			var x := cos(a) * r
			var z := sin(a) * r
			var depth := 2.5 + 12.0 * smoothstep(25.0, 170.0, r) + 90.0 * smoothstep(170.0, 600.0, r)
			var lumps := (noise.get_noise_2d(x * 0.6, z * 0.6) * 0.5 + 0.5)
			lumps = smoothstep(0.55, 0.85, lumps) * 1.1 * (1.0 - smoothstep(30.0, 140.0, r))
			var ripple := noise.get_noise_2d(x * 2.5, z * 2.5) * 0.05
			verts.append(Vector3(x, -depth + lumps + ripple, z))
	for i in rings:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := (i + 1) * segs + j
			var d := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, b, c, b, d, c])
	nrm.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var fn := (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]])
		for k in 3:
			nrm[idx[t + k]] += fn
	for i in nrm.size():
		nrm[i] = nrm[i].normalized()
		if nrm[i].y < 0.0:
			nrm[i] = -nrm[i]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func sea_mesh() -> ArrayMesh:
	## The water surface: a disc 3 km across, rings spaced as r = R * (i / N)^2 so it is dense (about 1.5 m) at the island, where the
	## long swells lift it, and coarse far away (flat there: the shader fades the displacement out).
	var rings := 200
	var segs := 256
	var rmax := 3000.0
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var r := rmax * pow(float(i) / float(rings), 2.0)
		for j in segs:
			var a := TAU * float(j) / float(segs)
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in rings:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := (i + 1) * segs + j
			var d := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, c, b, b, c, d])
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-3000, -6, -3000), Vector3(6000, 12, 6000))
	return m


static func island_mesh(seed_i: int, radius: float, height: float) -> ArrayMesh:
	## A far island: a lumpy cone with ridges, reaching down below the sea floor so it stands in the water at any depth.
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.seed = seed_i
	nz.frequency = 1.0 / radius * 2.2
	nz.fractal_octaves = 5
	var n := 72
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for iz in n + 1:
		for ix in n + 1:
			var x := (float(ix) / float(n) * 2.0 - 1.0) * radius
			var z := (float(iz) / float(n) * 2.0 - 1.0) * radius
			var r := sqrt(x * x + z * z) / radius
			var body := clampf(1.0 - r * r, 0.0, 1.0)
			var h := height * pow(body, 0.9) * (0.55 + 0.9 * (nz.get_noise_2d(x, z) * 0.5 + 0.5))
			h += height * 0.18 * absf(nz.get_noise_2d(x * 2.3 + 40.0, z * 2.3)) * body
			verts.append(Vector3(x, h - 12.0 * (1.0 - body) - 8.0, z))
	for iz in n:
		for ix in n:
			var a := iz * (n + 1) + ix
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var fn := (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]])
		for k in 3:
			nrm[idx[t + k]] += fn
	for i in nrm.size():
		nrm[i] = nrm[i].normalized()
		if nrm[i].y < 0.0:
			nrm[i] = -nrm[i]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
