extends SceneTree
## Builds a town given as --blocks=v,k,colour,style;... on a grid (--cell=, --grid=) and prints what the rules made of it. Run: ... -- --cell=3 --blocks=1542,1,6,0;1543,2,11,0
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(1, 0, str(opt.get("grid", "dodeca")), CSGrid.parse_div(str(opt.get("cell", "1"))))
	var t := CSTown.new()
	for part in str(opt.get("blocks", "")).split(";"):
		var f := part.split(",")
		if f.size() >= 3:
			t.add(int(f[0]), int(f[1]), int(f[2]), int(f[3]) if f.size() > 3 else 0)
	var b := CSBuild.new()
	b.build(g, t)
	print("kinds ", b.kinds, " pieces ", b.pieces, " fills ", b.fills.keys())
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	print("audit open %d nm %d flipped %d T %d" % [int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
	for k in ["open_info", "nm_info", "flip_info"]:
		for e in (au[k] as Array).slice(0, 3):
			print("  ", k, " ", str(e).substr(0, 200))
	quit(0)
