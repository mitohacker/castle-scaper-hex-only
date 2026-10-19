extends SceneTree
## Kevin's latest autosave walls ([x, z, heading, length, width, level]) put through the merge: Godot --headless --path . --script res://tools/autosave_walls.gd -- [--cell=1]
const LIST := [[-20.7591,-8.9889,330,26.9668,1.9,1],[0,-17.9779,120,15.5693,1.9,1],[-20.7591,-8.9889,240,15.5693,1.9,1],[-28.5437,-22.4723,180,10.3795,1.9,1],[-38.9232,-22.4723,90,11.9852,1.9,1],[-36.3284,-8.9889,60,10.3795,1.9,1],[-44.113,-4.4945,60,15.5693,1.9,1],[-28.5437,4.4945,150,17.9779,1.9,1],[-44.113,13.4834,270,11.9852,1.9,1],[-44.113,13.4834,210,17.9779,1.9,1],[-31.1386,26.9668,180,10.3795,1.9,1],[-40.2207,26.9668,90,26.9668,14.8744,1],[-31.1386,26.9668,60,15.5693,1.9,1],[-23.3539,40.4502,0,10.3795,1.9,1],[-12.9744,40.4502,60,5.1898,1.9,1],[-10.3795,44.9447,150,8.9889,1.9,1],[-36.3284,26.9668,120,5.1898,1.9,1],[-31.1386,44.9447,30,8.9889,1.9,1],[-70.0618,31.4613,120,10.3795,1.9,1],[-64.8721,31.4613,120,15.5693,1.9,1],[-72.6567,35.9557,30,5.9926,1.9,1],[-44.113,58.4281,60,5.1898,1.9,1],[-80.4414,31.4613,300,20.7591,1.9,1],[-67.4669,17.9779,120,20.7591,1.9,1]]
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(1, 0, CSGrid.KIND_DODECA, CSGrid.parse_div(str(opt.get("cell", "1"))))
	var t := CSTown.new()
	for e: Array in LIST:
		t.walls.append({"x": e[0], "z": e[1], "deg": float(e[2]), "len": e[3], "w": e[4], "c": int(e[5])})
	var merges := CSWalls.settle(t, g)
	print("%d walls -> %d (%d merges)" % [LIST.size(), t.walls.size(), merges])
	for w: Dictionary in t.walls:
		print("  [%.2f, %.2f] %3d deg  %.2f long  %.2f wide" % [w.x, w.z, w.deg, w.len, w.w])
	quit(0)
