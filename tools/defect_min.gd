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
	_layers_near(grid, keys, t, fin)
	if opt.has("at"):
		# --at=x,y,z: the layers near another point of the minimal town
		var rxa := RegEx.new()
		rxa.compile("\\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\)")
		var pa: PackedStringArray = str(opt.at).split(",")
		_layers_at(grid, keys, t, rxa, "(%s, %s, %s)" % [pa[0], pa[1], pa[2]])
	quit(0)


func _layers_near(grid: CSGrid, keys: Array, src: CSTown, fin: Dictionary) -> void:
	## Where the first defect is: every layer of the plan with a corner or an edge within 12 cm of it (label, owner, height, its own corners there).
	var infos := []
	for k in ["nm_info", "open_info", "flip_info"]:
		if (fin[k] as Array).size() > 0:
			infos.append(str((fin[k] as Array)[0]))
			break
	var rx := RegEx.new()
	rx.compile("\\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\)")
	for info: String in infos:
		_layers_at(grid, keys, src, rx, info)


func _layers_at(grid: CSGrid, keys: Array, src: CSTown, rx: RegEx, info: String) -> void:
	var m := rx.search(info)
	if m == null:
		return
	var pt := Vector2(float(m.get_string(1)), float(m.get_string(3)))
	var y := float(m.get_string(2))
	var t := CSTown.new()
	for kk: int in keys:
		t.add(kk / 64, kk % 64, src.colour(kk / 64, kk % 64), src.style(kk / 64, kk % 64))
	var b := CSBuild.new()
	b.build(grid, t)
	var pl := b.plan
	print("  layers near (%.3f, %.3f), y %.3f:" % [pt.x, pt.y, y])
	for li in pl.lay_y0.size():
		var poly: PackedVector2Array = pl.lay_poly[li]
		var near := false
		for j in poly.size():
			if Geometry2D.get_closest_point_to_segment(pt, poly[j], poly[(j + 1) % poly.size()]).distance_to(pt) < 0.12:
				near = true
		if not near:
			continue
		var st: Dictionary = pl.stacks[pl.lay_stack[li]]
		var own := ""
		for q in pl.lay_reg[li]:
			if q.distance_to(pt) < 0.25:
				own += " (%.3f %.3f)" % [q.x, q.y]
		print("    layer %d %s owner %s op %d y %.3f-%.3f own corners:%s" % [li, str(st.get("label", "")), str(st.get("owner", "")), pl.lay_op[li], pl.lay_y0[li], pl.lay_y1[li], own])


func _audit(grid: CSGrid, keys: Array, src: CSTown) -> Dictionary:
	var t := CSTown.new()
	for k: int in keys:
		t.add(k / 64, k % 64, src.colour(k / 64, k % 64), src.style(k / 64, k % 64))
	var b := CSBuild.new()
	b.build(grid, t)
	return CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
