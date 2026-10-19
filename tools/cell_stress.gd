extends SceneTree
## What a cell size costs and how clean it is: the grid, every starter, N random click-built castles (mixed styles) and a few castles with straight walls through
## them, each audited. One line per town, a summary at the end. Run: Godot --headless --path . --script res://tools/cell_stress.gd -- --cell=4 [--towns=16 | --seeds=0,4,6] [--starters=castle,tower] [--clicks=70]
## Defects = open edges + non-manifold + flipped + T-junctions of the audit (the same count the core suite's strict checks use).
const SKIP := [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B]


func _defects(b: CSBuild) -> int:
	var au := CFAudit.check(b.mesh, SKIP)
	return int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions)


func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var div := CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV))))
	var towns := int(opt.get("towns", 16))
	var clicks := int(opt.get("clicks", 70))
	var t0 := Time.get_ticks_msec()
	var g := CSGrid.new()
	g.generate(1, 0, str(opt.get("grid", "dodeca")), div)
	var n_cells := 0
	for v in g.verts.size():
		if g.is_dodecagon(v) and g.buildable(v):
			n_cells += 1
	print("div %d: %d points, %d buildable cells of %.2f m2 (side %.3f m), grid %d ms" % [div, g.verts.size(), n_cells, CSGrid.BASE_AREA / float(div), g.side, Time.get_ticks_msec() - t0])
	var bad_towns := 0
	var total := 0
	var worst_ms := 0.0
	var sum_ms := 0.0
	var count := 0
	var names: Array = CSStarter.NAMES if not opt.has("starters") else Array(str(opt.starters).split(","))
	for n: String in names:
		var t := CSTown.new()
		t.grid_div = div
		CSStarter.make(n, g, t)
		var b := CSBuild.new()
		b.build(g, t)
		var d := _defects(b)
		total += d
		bad_towns += 1 if d > 0 else 0
		worst_ms = maxf(worst_ms, float(b.stats.ms))
		sum_ms += float(b.stats.ms)
		count += 1
		print("  starter %-10s %4d blocks %6.0f ms %7d tris  defects %d" % [n, t.size(), float(b.stats.ms), b.mesh.tri_count(), d])
	var seeds: Array = []
	if opt.has("seeds"):
		for x: String in str(opt.seeds).split(","):
			seeds.append(int(x))
	else:
		for s in towns:
			seeds.append(s)
	for s: int in seeds:
		var t := CSTown.new()
		t.grid_div = div
		CSStarter.random_growth(g, t, s, clicks, -1 if s % 2 == 1 else 0)
		var b := CSBuild.new()
		b.build(g, t)
		var d := _defects(b)
		total += d
		bad_towns += 1 if d > 0 else 0
		worst_ms = maxf(worst_ms, float(b.stats.ms))
		sum_ms += float(b.stats.ms)
		count += 1
		print("  random %2d %s %4d blocks %6.0f ms %7d tris  defects %d" % [s, "mixed" if s % 2 == 1 else "plain", t.size(), float(b.stats.ms), b.mesh.tri_count(), d])
	print("div %d: %d towns, %d with defects (%d in all), build %.0f ms on average, %.0f ms at worst" % [div, count, bad_towns, total, sum_ms / maxf(float(count), 1.0), worst_ms])
	quit(0)
