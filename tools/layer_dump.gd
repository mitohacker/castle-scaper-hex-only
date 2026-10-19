extends SceneTree
## The polygons of every layer within --r of a point (default 0.35 m): Godot --headless --path . --script res://tools/layer_dump.gd -- --cell=4 --town=0 --keys=a,b,c --at=x,z [--r=0.35]
## --keys: block keys (v * 64 + k) as defect_min prints them (v=..., k=...): --blocks=2145:2,2146:1,2146:2
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var grid := CSGrid.new()
	grid.generate(1, 0, str(opt.get("grid", "dodeca")), CSGrid.parse_div(str(opt.get("cell", "1"))))
	var t := CSTown.new()
	for bl: String in str(opt.blocks).split(","):
		t.add(int(bl.get_slice(":", 0)), int(bl.get_slice(":", 1)), 0, 0)
	var b := CSBuild.new()
	b.build(grid, t)
	var at := Vector2(float(str(opt.at).get_slice(",", 0)), float(str(opt.at).get_slice(",", 1)))
	var r := float(opt.get("r", 0.35))
	var pl := b.plan
	for li in pl.lay_y0.size():
		var poly: PackedVector2Array = pl.lay_poly[li]
		var near := false
		for j in poly.size():
			if Geometry2D.get_closest_point_to_segment(at, poly[j], poly[(j + 1) % poly.size()]).distance_to(at) < r:
				near = true
		if not near:
			continue
		var st: Dictionary = pl.stacks[pl.lay_stack[li]]
		if opt.has("vertex"):
			var hit := false
			for q in poly:
				if q.distance_to(at) < float(opt.vertex):
					hit = true
			if not hit:
				continue
		var s := ""
		if opt.has("vertex"):
			var own := ""
			for q in pl.lay_reg[li]:
				if q.distance_to(at) < 0.1:
					own += " (%.4f,%.4f)" % [q.x, q.y]
			print("own %d %s:%s" % [li, str(st.get("label", "")), own])
			continue
		for q in poly:
			s += " (%.3f,%.3f)" % [q.x, q.y]
		print("layer %d %s op %d y %.2f-%.2f:%s" % [li, str(st.get("label", "")), pl.lay_op[li], pl.lay_y0[li], pl.lay_y1[li], s])
	quit(0)
