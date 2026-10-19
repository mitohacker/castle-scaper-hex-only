extends SceneTree
## What one click costs: the castle starter built, a block added on the sea, the incremental rebuild (the plan reuses what did not change) and the
## rest of the worker's job (props, world, roads, scatter), at a cell size. Run: ... tools/incr_time.gd -- --cell=2
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(1, 0, str(opt.get("grid", "dodeca")), CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV)))))
	var t := CSTown.new()
	CSStarter.make("castle", g, t)
	var b0 := CSBuild.new()
	b0.build(g, t)
	var v := g.nearest(Vector2(60.0, 10.0))
	t.add(v, 0, 3)
	var t0 := Time.get_ticks_msec()
	var b1 := CSBuild.new()
	b1.build(g, t, b0)
	print("incremental build: %d ms (rules %.0f, plan %.0f)" % [Time.get_ticks_msec() - t0, float(b1.stats.ms_rules), float(b1.stats.ms_plan)])
	t0 = Time.get_ticks_msec()
	var pr := CSProps.new()
	pr.build(b1)
	print("props: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var w := CSWorld.new()
	w.build(g, b1.town, b1.land_all())
	print("world: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var rd := CSRoads.new()
	rd.build(w)
	var sc := CSScatter.new()
	sc.build(w)
	print("roads + scatter: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var m := ArrayMesh.new()
	b1.mesh.commit(m, null)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(b1.mesh.verts)
	print("commit + collision shape: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var sk := CSRocks.skirt_mesh(CSRocks.shore_loops(g, b1.land_all(), {}))
	print("rock skirt: %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)
