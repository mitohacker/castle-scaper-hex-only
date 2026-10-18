extends SceneTree
## Builds roofs of CSRoofs over several outlines and audits each shell (open edges, non-manifold, flipped, T-junctions): every roof must be a closed
## solid on its own, alone and next to another one sharing an edge (the neighbours' edges stay apart).
## Run: Godot --headless --path . --script res://tools/roof_probe.gd

var fails := 0


func _mesh_for(build: Callable, label: String, n_shells: int = 1) -> void:
	var m := CFMesh.new()
	build.call(m)
	var au := CFAudit.check(m, [])
	var bad := int(au.open_other) + int(au.open_ground) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions) + int(au.bad_normal) + int(au.dup_tris)
	if bad > 0:
		fails += 1
	print("%s %-44s tris %5d open %d (+ground %d) nm %d flipped %d tj %d bad_normal %d dup %d" % [
		"ok  " if bad == 0 else "FAIL", label, au.tris, au.open_other, au.open_ground, au.non_manifold, au.flipped, au.t_junctions, au.bad_normal, au.dup_tris])
	if bad > 0:
		for s: String in (au.open_info as Array).slice(0, 3):
			print("      open ", s)
		for s: String in (au.nm_info as Array).slice(0, 3):
			print("      nm ", s)
		for s: String in (au.flip_info as Array).slice(0, 4):
			print("      flipped ", s)


func _groups(_sh: CSRoofs.Shell) -> Dictionary:
	return {"zones": {"roof": CFMesh.Z_TILE, "side": CFMesh.Z_TIMBER, "soffit": CFMesh.Z_TIMBER}}


func _flat(n: int, v: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(n)
	a.fill(v)
	return a


func _fl(n: int, v: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a


func _ridge_case(m: CFMesh, poly: PackedVector2Array, gable: PackedByteArray, ovh: PackedFloat32Array, off := Vector2.ZERO, slope := 0.8, y := 4.0) -> void:
	var sh := CSRoofs.Shell.new()
	var o := _groups(sh)
	o["slope"] = slope
	o["gable"] = gable
	o["ovh"] = ovh
	var moved := PackedVector2Array()
	for p in poly:
		moved.append(p + off)
	var rec := CSRoofs.ridge(sh, moved, y, o)
	if rec.is_empty():
		print("  (ridge returned nothing)")
		return
	sh.emit(m, rec.centre, 0.3, 1, Vector3.ZERO, "roof")


func _pyr_case(m: CFMesh, poly: PackedVector2Array, ovh: PackedFloat32Array, extra: Dictionary, off := Vector2.ZERO, y := 4.0) -> void:
	var sh := CSRoofs.Shell.new()
	var o := _groups(sh)
	o["ovh"] = ovh
	o["H"] = 2.4
	o["profile"] = [Vector2(0, 0), Vector2(0.15, 0.06), Vector2(0.4, 0.28), Vector2(0.7, 0.65), Vector2(0.9, 0.9), Vector2(1, 1)]
	o["sub"] = 4
	for k: String in extra:
		o[k] = extra[k]
	var moved := PackedVector2Array()
	for p in poly:
		moved.append(p + off)
	if o.has("inner_fn"):
		o["inner"] = (o.inner_fn as Callable).call(moved)
	var rec := CSRoofs.pyramid(sh, moved, y, o)
	sh.emit(m, rec.centre, 0.3, 1, Vector3.ZERO, "roof")


func _slab_case(m: CFMesh, poly: PackedVector2Array, ovh: PackedFloat32Array, off := Vector2.ZERO, rim := 0.8, y := 4.0) -> void:
	var sh := CSRoofs.Shell.new()
	var moved := PackedVector2Array()
	for p in poly:
		moved.append(p + off)
	var rec := CSRoofs.slab(sh, moved, y, {"ovh": ovh, "rim": rim, "wall": 0.22, "deck": 0.1, "zones": {"roof": CFMesh.Z_FLAG, "side": CFMesh.Z_STONE, "soffit": CFMesh.Z_TIMBER}})
	sh.emit(m, rec.centre, 0.3, 1, Vector3.ZERO, "slab")


func _initialize() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var rect := PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 4), Vector2(0, 4)])
	var trap := PackedVector2Array([Vector2(0, 0), Vector2(5, 0.3), Vector2(4.2, 4.1), Vector2(0.4, 3.6)])
	var pent := CFShapes.circle(Vector2(2, 2), 2.2, 5, 0.3)
	var tri := CFShapes.circle(Vector2(2, 2), 2.4, 3, 0.1)
	var hex := CFShapes.circle(Vector2(2, 2), 2.3, 6, 0.0)
	var gab := _flat(4, 0)
	gab[1] = 1
	gab[3] = 1
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, sq, gab, _fl(4, 0.4)), "ridge square, gables, eaves 0.4")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, rect, gab, _fl(4, 0.4)), "ridge rectangle, gables")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, rect, _flat(4, 0), _fl(4, 0.4)), "ridge rectangle, hip all round")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, sq, _flat(4, 0), _fl(4, 0.4)), "ridge square, hip (pyramid)")
	var ov2 := _fl(4, 0.4)
	ov2[0] = 0.0
	ov2[2] = 0.0
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, rect, gab, ov2), "ridge rectangle, party edges, gables")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, trap, gab, _fl(4, 0.35)), "ridge trapezoid, gables")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, trap, _flat(4, 0), ov2), "ridge trapezoid, hip, two party edges")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, pent, _flat(5, 0), _fl(5, 0.3)), "ridge pentagon, hip")
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, tri, _flat(3, 0), _fl(3, 0.3)), "ridge triangle, hip")
	var ov0 := _fl(4, 0.0)
	_mesh_for(func(m: CFMesh) -> void: _ridge_case(m, sq, _flat(4, 0), ov0), "ridge square, no overhang at all")
	# two roofs side by side sharing an edge: no edge of one is an edge of the other
	_mesh_for(func(m: CFMesh) -> void:
		var o1 := _fl(4, 0.4)
		o1[1] = 0.0
		var o2 := _fl(4, 0.4)
		o2[3] = 0.0
		_ridge_case(m, sq, _flat(4, 0), o1)
		_ridge_case(m, sq, _flat(4, 0), o2, Vector2(4, 0)), "two ridge roofs sharing an edge")
	_mesh_for(func(m: CFMesh) -> void:
		var o1 := _fl(4, 0.4)
		o1[1] = 0.0
		var o2 := _fl(4, 0.4)
		o2[3] = 0.0
		var g1 := _flat(4, 0)
		g1[0] = 1
		g1[2] = 1
		_ridge_case(m, sq, g1, o1)
		_ridge_case(m, sq, g1, o2, Vector2(4, 0)), "two gabled roofs sharing an edge")
	# radial roofs
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, sq, _fl(4, 0.9), {"lift": 0.5}), "pyramid square, upturned corners")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, hex, _fl(6, 1.0), {"lift": 0.4}), "pyramid hexagon")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, tri, _fl(3, 0.8), {"lift": 0.3}), "pyramid triangle")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, trap, _fl(4, 0.8), {"lift": 0.4, "bend": Vector2(0.5, 0.2)}), "pyramid trapezoid, bent tip")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, sq, ov2, {"lift": 0.5}), "pyramid square, two party edges")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, sq, _fl(4, 1.1), {"lift": 0.4, "H": 0.9, "inner_fn": func(poly: PackedVector2Array) -> PackedVector2Array:
			var c := CSRoofs.centroid(poly)
			var out := PackedVector2Array()
			for p in poly:
				out.append(c + (p - c) * 0.8)
			return out}), "pyramid square, truncated (a tier's pent roof)")
	_mesh_for(func(m: CFMesh) -> void:
		_pyr_case(m, sq, _fl(4, 0.9), {"lift": 0.5})
		_pyr_case(m, sq, _fl(4, 0.9), {"lift": 0.5}, Vector2(6, 0)), "two pyramid roofs apart")
	_mesh_for(func(m: CFMesh) -> void:
		var sh := CSRoofs.Shell.new()
		var g := sh.group(CFMesh.Z_GOLD)
		CSRoofs.lathe(sh, Vector3(1, 1, 1), [Vector2(0.0, 0.0), Vector2(0.3, 0.0), Vector2(0.35, 0.3), Vector2(0.2, 0.7), Vector2(0.0, 0.9)], 10, g)
		sh.emit(m, Vector3(1, 1.4, 1), 0.3, 1, Vector3.ZERO, "finial"), "lathe finial (closed)")
	# flat roofs and boxes
	_mesh_for(func(m: CFMesh) -> void: _slab_case(m, sq, _fl(4, 0.0)), "slab square, parapet")
	_mesh_for(func(m: CFMesh) -> void: _slab_case(m, trap, _fl(4, 0.15)), "slab trapezoid, jutting edge")
	_mesh_for(func(m: CFMesh) -> void: _slab_case(m, pent, _fl(5, 0.1), Vector2.ZERO, 0.0), "slab pentagon, no parapet")
	_mesh_for(func(m: CFMesh) -> void: _slab_case(m, tri, _fl(3, 0.0)), "slab triangle, parapet")
	_mesh_for(func(m: CFMesh) -> void:
		_slab_case(m, sq, ov2)
		_slab_case(m, sq, ov2, Vector2(4, 0)), "two slabs sharing an edge")
	_mesh_for(func(m: CFMesh) -> void:
		var sh := CSRoofs.Shell.new()
		var inset := PackedVector2Array()
		for q in hex:
			inset.append(Vector2(2, 2) + (q - Vector2(2, 2)) * 0.5)
		var rec := CSRoofs.prism(sh, inset, 4.0, 6.0, CFMesh.Z_STONE, CFMesh.Z_FLAG)
		sh.emit(m, rec.centre, 0.3, 1, Vector3.ZERO, "prism"), "prism over a hexagon")
	# a Chinese hip roof: upturned corners, a ridge line for the top ring
	var ridge_in := {"axis": Vector2(1, 0), "along": 0.55, "across": 0.05}
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, rect, _fl(4, 1.0), {"lift": 0.5, "lift_u": 0.55, "ridge": ridge_in}), "pyramid rectangle, ridge line top, upturned")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, trap, _fl(4, 1.0), {"lift": 0.5, "lift_u": 0.55, "ridge": ridge_in}), "pyramid trapezoid, ridge line top, upturned")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, pent, _fl(5, 1.0), {"lift": 0.5, "lift_u": 0.55, "ridge": ridge_in}), "pyramid pentagon, ridge line top, upturned")
	_mesh_for(func(m: CFMesh) -> void: _pyr_case(m, tri, ov2.slice(0, 3), {"lift": 0.5, "lift_u": 0.55}), "pyramid triangle, party edges")
	print("%d failures" % fails)
	quit(1 if fails > 0 else 0)
