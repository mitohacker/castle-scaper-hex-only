extends SceneTree
## Shrinks a random click-built town that audits with a defect to a minimal set of blocks that still does, and prints what the audit says about it.
## Run: Godot --headless --path . --script res://tools/defect_min.gd -- --town=3 --style=0   (or --starter=castle)


func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var grid := CSGrid.new()
	grid.generate(int(opt.get("grid", 1)))
	var t := CSTown.new()
	if opt.has("starter"):
		CSStarter.make(str(opt.starter), grid, t)
	else:
		CSStarter.random_growth(grid, t, int(opt.get("town", 0)), 70, int(opt.get("style", 0)))
	var keys: Array = t.blocks.keys()
	keys.sort()
	var r := _audit(grid, keys, t)
	print("start: %d blocks, open %d nm %d flipped %d T %d" % [keys.size(), r.open_other, r.non_manifold, r.flipped, r.t_junctions])
	if r.open_other + r.non_manifold + r.flipped + r.t_junctions == 0:
		quit(0)
		return
	var kind := "open_other" if r.open_other > 0 else ("non_manifold" if r.non_manifold > 0 else ("flipped" if r.flipped > 0 else "t_junctions"))
	var changed := true
	while changed:
		changed = false
		for k in keys.duplicate():
			var rest := keys.duplicate()
			rest.erase(k)
			var rr := _audit(grid, rest, t)
			if int(rr[kind]) > 0:
				keys = rest
				changed = true
	var fin := _audit(grid, keys, t)
	CFPlan.debug_default = true
	_audit(grid, keys, t)
	CFPlan.debug_default = false
	print("minimizing on: ", kind)
	print("minimal: %d blocks, open %d nm %d flipped %d T %d" % [keys.size(), fin.open_other, fin.non_manifold, fin.flipped, fin.t_junctions])
	for k: int in keys:
		var v := k / 64
		print("  block v=%d k=%d colour %d style %d  pos (%.2f, %.2f) nbrs %s" % [v, k % 64, t.colour(v, k % 64), t.style(v, k % 64), grid.verts[v].x, grid.verts[v].y, str(grid.nbrs[v])])
	for s: String in (fin.open_info as Array).slice(0, 12):
		print("  open: ", s)
	for s: String in (fin.nm_info as Array).slice(0, 6):
		print("  nm: ", s)
	for s: String in (fin.flip_info as Array).slice(0, 4):
		print("  flipped: ", s)
	quit(0)


func _audit(grid: CSGrid, keys: Array, src: CSTown) -> Dictionary:
	var t := CSTown.new()
	for k: int in keys:
		t.add(k / 64, k % 64, src.colour(k / 64, k % 64), src.style(k / 64, k % 64))
	var b := CSBuild.new()
	b.build(grid, t)
	return CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
