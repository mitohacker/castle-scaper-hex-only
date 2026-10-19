extends SceneTree
## What a starter looks like to the prop rules: its land kinds and how many of each prop kind it gets.
## Run: Godot --headless --path . --script res://tools/starter_probe.gd -- --starter=castle

func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(str(opt.get("starter", "castle")), grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	var pr := CSProps.new()
	pr.build(b)
	var kinds := {}
	for v in b.land:
		kinds[b.land[v]] = int(kinds.get(b.land[v], 0)) + 1
	print("blocks %d, land %s" % [town.size(), str(kinds)])
	print("props %s" % str(pr.counts))
	if opt.has("cells"):
		for v in grid.verts.size():
			if grid.buildable(v) and grid.verts[v].length() < 30.0:
				print("%3d %s r=%5.1f %s  top %d  %s" % [v, "D" if grid.is_dodecagon(v) else "t", grid.verts[v].length(), str(grid.verts[v].snapped(Vector2(0.1, 0.1))), town.top(v), b.land.get(v, "")])
	quit(0)
