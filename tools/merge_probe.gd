extends SceneTree
## Kevin's castle_004 walls (the list as he reported it: [cell, heading, length, colour]) through the merge: how many walls are left and how thick.
## Run: Godot --headless --path . --script res://tools/merge_probe.gd
const CASTLE_004 := [[508,330,26.97,1],[707,120,15.57,1],[508,240,15.57,1],[505,180,10.38,1],[430,90,11.99,1],[397,60,10.38,1],[329,60,15.57,1],[332,150,5.99,1],[332,330,8.99,1],[268,270,11.99,1],[268,210,17.98,1],[268,330,5.99,1],[303,180,10.38,1],[240,90,8.99,1],[303,60,15.57,1],[306,0,10.38,1],[373,60,5.19,1],[374,150,8.99,1],[212,90,17.98,1],[241,270,3.0,1],[271,120,5.19,1],[241,90,20.97,1],[241,90,11.99,1],[271,90,26.97,1],[272,90,20.97,1],[272,270,3.0,1],[244,30,8.99,1],[211,90,20.97,1],[183,270,8.99,1],[183,90,11.99,1]]


func _initialize() -> void:
	var g := CSGrid.new()
	g.generate()
	var t := CSTown.new()
	for e in CASTLE_004:
		t.walls.append({"v": e[0], "deg": float(e[1]), "len": float(e[2]), "c": e[3]})
	var merged := CSWalls.settle(t, g)
	print("%d walls -> %d (%d merges)" % [CASTLE_004.size(), t.walls.size(), merged])
	for w in t.walls:
		print("  (%.2f, %.2f) %.0f deg  %.2f m long  %.2f m thick" % [w.x, w.z, w.deg, w.len, w.w])
	quit(0)
