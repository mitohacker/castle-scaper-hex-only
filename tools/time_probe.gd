extends SceneTree
## How long the grid and a castle take at a cell size. Run: ... tools/time_probe.gd -- --cell=2 [--grid=hex]
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var t0 := Time.get_ticks_msec()
	var g := CSGrid.new()
	g.generate(1, 0, str(opt.get("grid", "dodeca")), CSGrid.parse_div(str(opt.get("cell", "1"))))
	print("grid: %d points, %d ms" % [g.verts.size(), Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	var t := CSTown.new()
	CSStarter.make(str(opt.get("starter", "castle")), g, t)
	print("starter: %d blocks, %d ms" % [t.size(), Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	var b := CSBuild.new()
	b.build(g, t)
	print("build: %d ms (rules %.0f, plan %.0f), %d tris" % [Time.get_ticks_msec() - t0, float(b.stats.ms_rules), float(b.stats.ms_plan), b.mesh.tri_count()])
	t0 = Time.get_ticks_msec()
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	print("audit: %d ms, open %d nm %d flipped %d T %d" % [Time.get_ticks_msec() - t0, int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
	t0 = Time.get_ticks_msec()
	var pr := CSProps.new()
	pr.build(b)
	print("props: %d ms, %s" % [Time.get_ticks_msec() - t0, str(pr.counts)])
	quit(0)
