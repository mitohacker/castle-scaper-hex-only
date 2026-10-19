extends SceneTree
## Wall corners at every angle the direction counts allow: two walls meeting end to end (a bend), crossing, as a T and a lone wall, at each of the
## 12, 16 and 24 directions, at several places on the grid (a wall's position against the cells matters), audited for open edges, non-manifold edges,
## flipped faces and T-junctions. Run: Godot --headless --path . --script res://tools/corner_probe.gd -- [--cell=2] [--places=4] [--dirs=12|16|24] [--debug]

var grid := CSGrid.new()
var bad := 0
var total := 0
var only := ""
var info := false


func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	CFPlan.debug_default = opt.has("debug")
	only = str(opt.get("only", ""))
	info = opt.has("info")
	var div := CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV))))
	grid.generate(1, 0, CSGrid.KIND_DODECA, div)
	var base := CSWalls.thickness(grid)
	var places := int(opt.get("places", 4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var counts: Array = [int(opt.dirs)] if opt.has("dirs") else CSGrid.DIR_COUNTS
	for n: int in counts:
		var step := 360.0 / float(n)
		for pl in places:
			var p := Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
			var len := 9.0 * grid.cell + 2.0
			_check("%d dirs, place %d: lone wall" % [n, pl], [[p.x, p.y, 0.0, len, base]])
			for k in range(1, n):
				var a := step * float(k)
				_check("%d dirs, place %d: bend of %.1f deg" % [n, pl, a], [[p.x, p.y, 0.0, len, base], [p.x, p.y, a, len, base]])
			for k in range(1, n / 2):
				var a := step * float(k)
				_check("%d dirs, place %d: crossing at %.1f deg" % [n, pl, a], [[p.x - len * 0.5, p.y, 0.0, len, base], [p.x, p.y, a, len, base]])
				var q := Vector2.from_angle(deg_to_rad(a))
				_check("%d dirs, place %d: T at %.1f deg" % [n, pl, a], [[p.x - len * 0.5, p.y, 0.0, len, base], [p.x + q.x * len * -0.5 + 1.0, p.y + q.y * len * -0.5, a, len * 0.5, base]])
	print("%d corner shapes, %d with defects" % [total, bad])
	quit(0)


func _check(label: String, spec: Array) -> void:
	if only != "" and not only in label:
		return
	var t := CSTown.new()
	for w: Array in spec:
		t.wall_add(float(w[0]), float(w[1]), float(w[2]), float(w[3]), float(w[4]), 3)
	var b := CSBuild.new()
	b.build(grid, t)
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	var d := int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions)
	total += 1
	if d > 0:
		bad += 1
		print("  defect: %s: open %d nm %d flipped %d T %d" % [label, int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
		if info:
			print("    spec ", spec)
			for e in au.nm_info:
				print("    nm ", e)
			for e in au.flip_info:
				print("    flip ", e)
