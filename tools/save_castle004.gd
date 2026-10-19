extends SceneTree
## Writes Kevin's castle_004 (30 straight walls, as saved by the earlier version: [cell, heading, length, colour] on the full-size 12-sided cells) for a
## screenshot or to load in the game, where the walls merge as it loads. Run: ... tools/save_castle004.gd -- --out=PATH [--merged]
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var t := CSTown.new()
	t.grid_div = 1
	for e: Array in preload("res://tools/castle004_list.gd").LIST:
		t.walls.append({"v": e[0], "deg": float(e[1]), "len": float(e[2]), "c": e[3]})
	if opt.has("merged"):
		var g := CSGrid.new()
		g.generate(1, 0, CSGrid.KIND_DODECA, 1)
		CSWalls.settle(t, g)
	t.save_json(str(opt.get("out", "/tmp/castle_004.json")))
	print("walls ", t.walls.size())
	quit(0)
