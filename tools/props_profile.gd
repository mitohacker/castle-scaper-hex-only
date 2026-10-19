extends SceneTree
## Where the prop layer's time goes at a cell size (the steps of CSProps.build timed one by one). Run: ... tools/props_profile.gd -- --cell=4
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(1, 0, CSGrid.KIND_DODECA, CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV)))))
	var t := CSTown.new()
	CSStarter.make(str(opt.get("starter", "castle")), g, t)
	var cb := CSBuild.new()
	cb.build(g, t)
	var pr := CSProps.new()
	pr.b = cb
	pr.grid = cb.grid
	pr.town = cb.town
	var steps := {"_index": pr._index, "_fix_openings": pr._fix_openings, "_windows": pr._windows, "_doors": pr._doors, "_towers": pr._towers, "_cottages": pr._cottages,
		"_houses": pr._houses, "_walks": pr._walks, "_courts": pr._courts, "_bunting": pr._bunting, "_ornaments": pr._ornaments, "style_props": func() -> void: CSStyleProps.build(pr), "_solve": pr._solve}
	var total := 0.0
	for name: String in steps:
		var t0 := Time.get_ticks_usec()
		(steps[name] as Callable).call()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		print("  %-14s %7.1f ms" % [name, ms])
	print("total %.0f ms, %d candidates, %d kept" % [total, pr.cands.size(), pr.kept.size()])
	quit(0)
