extends SceneTree
## Writes a town with straight walls for a screenshot: the castle starter with a ring of walls round it and an L beside it.
## Run: Godot --headless --path . --script res://tools/save_walls.gd -- --out=PATH [--grid=hex]
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var grid := CSGrid.new()
	grid.generate(1, 0, str(opt.get("grid", "dodeca")), CSGrid.parse_div(str(opt.get("cell", "1"))))
	var t := CSTown.new()
	t.grid_kind = grid.kind
	CSStarter.make("castle", grid, t)
	var c := grid.nearest(Vector2(0.0, 0.0))
	# a hexagon of walls round the castle: from the cell three steps out along 0 degrees
	var start := grid.nearest(Vector2(CSGrid.D_SPACING * 4.0, 0.0))
	var cur := start
	for i in 6:
		var deg := (120 + 60 * i) % 360
		var dir := Vector2.from_angle(deg_to_rad(float(deg)))
		var stops := grid.line_stops(grid.verts[cur], dir, 80.0)
		var len: float = stops[3]
		CSWalls.add_from_cell(t, grid, cur, deg, len, 4)
		cur = grid.nearest(grid.verts[cur] + dir * len)
	# an L with a 30 degree leg
	var o := grid.nearest(Vector2(-40.0, 30.0))
	var st := grid.line_stops(grid.verts[o], Vector2.from_angle(deg_to_rad(30.0)), 60.0)
	CSWalls.add_from_cell(t, grid, o, 30, st[3], 7)
	var e := grid.nearest(grid.verts[o] + Vector2.from_angle(deg_to_rad(30.0)) * st[3])
	var st2 := grid.line_stops(grid.verts[e], Vector2.from_angle(deg_to_rad(90.0)), 60.0)
	CSWalls.add_from_cell(t, grid, e, 90, st2[1], 7)
	t.save_json(str(opt.get("out", "/tmp/walls.json")))
	print("walls ", t.walls.size(), " blocks ", t.size())
	quit(0)
