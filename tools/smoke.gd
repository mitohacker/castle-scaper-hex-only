extends SceneTree
## Builds the starter castles (or --starter=name, random:N) headless and prints the stats and the weld audit.
##   godot --headless --path . --script res://tools/smoke.gd [-- --starter=castle]


func _init() -> void:
	var names := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			names.append(a.get_slice("=", 1))
	if names.is_empty():
		names = CSStarter.NAMES.duplicate()
		for s in 4:
			names.append("random:%d" % s)
	var t0 := Time.get_ticks_msec()
	var grid := CSGrid.new()
	grid.generate()
	var valence := {}
	for v in grid.verts.size():
		if grid.buildable(v):
			var n: int = (grid.nbrs[v] as PackedInt32Array).size()
			valence[n] = int(valence.get(n, 0)) + 1
	var nonconvex := 0
	for v in grid.verts.size():
		if grid.buildable(v) and not CSBuild.convex(grid.dual(v)):
			nonconvex += 1
	print("grid: %d verts, %d faces, %d ms; buildable valence %s; non-convex cells %d" % [grid.verts.size(), grid.tris.size() / 3,
		Time.get_ticks_msec() - t0, str(valence), nonconvex])
	for n in names:
		var town := CSTown.new()
		CSStarter.make(n, grid, town)
		var b := CSBuild.new()
		b.build(grid, town)
		var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
		var kinds := {}
		for kk in b.kinds:
			kinds[b.kinds[kk]] = int(kinds.get(b.kinds[kk], 0)) + 1
		var lands := {}
		for v in b.land:
			lands[b.land[v]] = int(lands.get(b.land[v], 0)) + 1
		print("== %s: %s" % [n, str(b.stats)])
		print("   tops %s land %s" % [str(kinds), str(lands)])
		var hk := {}
		for kk in b.hats:
			var hh: Dictionary = b.hats[kk]
			var key := "%s/%s" % [CSStyle.KEYS[int(hh.style)], str(hh.kind)]
			hk[key] = int(hk.get(key, 0)) + 1
		if not hk.is_empty():
			print("   hats %s facades %d" % [str(hk), b.facades])
		var oi: Array = au.get("open_info", [])
		var ni: Array = au.get("nm_info", [])
		au.erase("open_info")
		au.erase("nm_info")
		au.erase("components")
		print("   audit ", au)
		var pr := CSProps.new()
		pr.build(b)
		var nz := {}
		for kn: String in pr.counts:
			if int(pr.counts[kn]) > 0:
				nz[kn] = pr.counts[kn]
		print("   props %s %.0f ms" % [str(nz), float(pr.stats.ms)])
		for i in mini(oi.size(), 4):
			print("     open ", oi[i])
		for i in mini(ni.size(), 4):
			print("     nonman ", ni[i])
	quit(0)
