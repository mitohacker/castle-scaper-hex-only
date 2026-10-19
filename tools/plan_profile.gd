extends SceneTree
## The plan's own phases for one incremental click at a cell size (CFPlan.stats). Run: ... tools/plan_profile.gd -- --cell=4
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(1, 0, CSGrid.KIND_DODECA, CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV)))))
	var t := CSTown.new()
	CSStarter.make("castle", g, t)
	var b0 := CSBuild.new()
	b0.build(g, t)
	var v := g.nearest(Vector2(60.0, 10.0))
	t.add(v, 0, 3)
	var b1 := CSBuild.new()
	b1.build(g, t, b0)
	var st: Dictionary = b1.plan.stats
	for k: String in st:
		if k != "inner":
			print("  %s: %s" % [k, str(st[k])])
	print("  inner: ", str(st.inner))
	quit(0)
