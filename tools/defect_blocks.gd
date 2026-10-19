extends SceneTree
## Audit a handful of blocks: Godot --headless --path . --script res://tools/defect_blocks.gd -- --cell=4 --blocks=2145:2,2146:1,2146:2
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
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	print("open %d nm %d flipped %d T %d" % [int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
	quit(0)
