extends SceneTree
## Writes a town of straight-wall corners for a screenshot: two walls meeting at 30, 60, 90, 120 and 150 degrees, a wall end, a T, a cross and a ring of
## three walls, in a row. Run: Godot --headless --path . --script res://tools/corner_gallery.gd -- --out=PATH [--cell=2] [--dirs=12]
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var div := CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV))))
	var grid := CSGrid.new()
	grid.generate(1, 0, CSGrid.KIND_DODECA, div)
	var t := CSTown.new()
	t.grid_div = div
	var base := CSWalls.thickness(grid)
	var x := -50.0
	for ang in [30, 60, 90, 120, 150]:
		# two walls from one point: one along 0 degrees (towards +x), one turned `ang` degrees from it
		var p := Vector2(x, -12.0)
		t.wall_add(p.x, p.y, 0.0, 10.0, base, 1)
		t.wall_add(p.x, p.y, float(ang), 10.0, base, 2)
		x += 22.0
	# the second row: a lone wall, a T, a cross, a ring of three, a zigzag
	var y := 14.0
	x = -50.0
	t.wall_add(x, y, 0.0, 10.0, base, 3)
	x += 22.0
	t.wall_add(x, y, 0.0, 12.0, base, 3)
	t.wall_add(x + 6.0, y, 90.0, 9.0, base, 3)
	x += 22.0
	t.wall_add(x - 5.0, y, 0.0, 10.0, base, 3)
	t.wall_add(x, y - 5.0, 90.0, 10.0, base, 3)
	x += 22.0
	var q := Vector2(x, y)
	for i in 3:
		var d := Vector2.from_angle(deg_to_rad(120.0 * float(i)))
		t.wall_add(q.x, q.y, 120.0 * float(i), 11.0, base, 4)
		q += d * 11.0
	x += 22.0
	t.wall_add(x, y, 30.0, 8.0, base, 5)
	t.wall_add(x + 6.9, y + 4.0, 330.0, 8.0, base, 5)
	t.wall_add(x + 13.8, y, 30.0, 8.0, base, 5)
	t.save_json(str(opt.get("out", "/tmp/corners.json")))
	print("walls ", t.walls.size())
	quit(0)
