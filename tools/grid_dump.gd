extends SceneTree
## Cells of a grid variant: how many, how many sides, sizes and the shortest side. Run: ... tools/grid_dump.gd -- --grid=layer --cell=1
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var t0 := Time.get_ticks_msec()
	var g := CSGrid.new()
	g.generate(1, 0, str(opt.get("grid", "dodeca")), CSGrid.parse_div(str(opt.get("cell", "1"))))
	print("%s: %d points in %d ms" % [str(opt), g.verts.size(), Time.get_ticks_msec() - t0])
	var by_n := {}
	var areas := []
	var short := INF
	var shorts := []
	var concave := 0
	var cells := 0
	for v in g.verts.size():
		if not g.buildable(v):
			continue
		cells += 1
		var d := g.dual(v)
		by_n[d.size()] = int(by_n.get(d.size(), 0)) + 1
		areas.append(CFTri.area(d))
		if not CSBuild.convex(d):
			concave += 1
		for i in d.size():
			var l := d[i].distance_to(d[(i + 1) % d.size()])
			short = minf(short, l)
			shorts.append(l)
	areas.sort()
	shorts.sort()
	print("cells %d, sides {%s}, concave %d" % [cells, str(by_n), concave])
	print("area min %.2f p10 %.2f median %.2f p90 %.2f max %.2f" % [areas[0], areas[areas.size() / 10], areas[areas.size() / 2], areas[areas.size() * 9 / 10], areas[areas.size() - 1]])
	print("side min %.3f p1 %.3f p10 %.3f median %.3f" % [shorts[0], shorts[shorts.size() / 100], shorts[shorts.size() / 10], shorts[shorts.size() / 2]])
	quit(0)
