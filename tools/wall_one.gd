extends SceneTree
## One town of straight walls given on the command line, built and audited: --walls="x,z,deg,len[,w];x,z,deg,len" [--cell=2] [--from=SEED --clicks=N: random castle under them] [--debug]
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	CFPlan.debug_default = opt.has("debug")
	CSWallJoints.off_towers = opt.has("notower")
	CSWallJoints.off_fills = opt.has("nofill")
	var grid := CSGrid.new()
	grid.generate(1, 0, CSGrid.KIND_DODECA, CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV)))))
	var t := CSTown.new()
	if opt.has("starter"):
		CSStarter.make(str(opt.starter), grid, t)
	elif opt.has("clicks"):
		CSStarter.random_growth(grid, t, int(opt.get("from", 0)), int(opt.clicks), -1 if int(opt.get("from", 0)) % 2 == 1 else 0)
	var base := CSWalls.thickness(grid)
	for part in str(opt.get("walls", "")).split(";"):
		var f := part.split(",")
		if f.size() >= 4:
			t.wall_add(float(f[0]), float(f[1]), float(f[2]), float(f[3]), float(f[4]) if f.size() > 4 else base, 3)
	if not opt.has("nomerge"):
		CSWalls.merge(t, base)
	if opt.has("near"):
		for wi in t.walls.size():
			var poly := CSBuild.wall_poly(grid, t.walls[wi])
			for q in grid.centers.size():
				var c := grid.centers[q]
				for k in 4:
					var d := Geometry2D.get_closest_point_to_segment(c, poly[k], poly[(k + 1) % 4]).distance_to(c)
					if d < 0.12:
						print("  wall %d side %d: grid corner %d at (%.3f, %.3f), %.4f m off" % [wi, k, q, c.x, c.y, d])
	var b := CSBuild.new()
	CFPlan.debug_default = opt.has("at") or opt.has("debug")
	if opt.has("loops"):
		var rects: Array = []
		for w: Dictionary in CSWalls.robust(t.walls):
			rects.append(CSBuild.wall_poly(grid, w))
		for lp: Dictionary in b._wall_loops(rects):
			print("loop ", lp.pts.size(), " ", lp.pts, " owners ", lp.owners)
	b.build(grid, t)
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	print("walls %d: open %d nm %d flipped %d T %d" % [t.walls.size(), int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
	if opt.has("at"):
		var pa: PackedStringArray = str(opt.at).split(",")
		var pt := Vector2(float(pa[0]), float(pa[1]))
		var pl := b.plan
		print("  layers near (%.3f, %.3f):" % [pt.x, pt.y])
		for li in pl.lay_y0.size():
			var poly: PackedVector2Array = pl.lay_poly[li]
			var near := false
			for j in poly.size():
				if Geometry2D.get_closest_point_to_segment(pt, poly[j], poly[(j + 1) % poly.size()]).distance_to(pt) < 0.15:
					near = true
			if not near:
				continue
			var st: Dictionary = pl.stacks[pl.lay_stack[li]]
			var own := ""
			for q in pl.lay_reg[li]:
				if q.distance_to(pt) < 0.25:
					own += " (%.3f %.3f)" % [q.x, q.y]
			print("    layer %d %s owner %s op %d y %.3f-%.3f own corners:%s poly %s" % [li, str(st.get("label", "")), str(st.get("owner", "")), pl.lay_op[li], pl.lay_y0[li], pl.lay_y1[li], own, str(poly)])
	for e in au.get("open_info", []):
		print("  open ", e)
	for e in au.nm_info:
		print("  nm ", e)
	for e in au.flip_info:
		print("  flip ", e)
	quit(0)
