extends SceneTree
## Straight walls stress test: random click-built castles with random straight walls laid across them (every heading, every length the
## rules allow), audited like hex_probe's towns, plus walls alone. Run: Godot --headless --path . --script res://tools/wall_probe.gd -- --towns=40 [--walls=3] [--from=0] [--clicks=30]

func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var towns := int(opt.get("towns", 40))
	var nwalls := int(opt.get("walls", 3))
	var first := int(opt.get("from", 0))
	var clicks := int(opt.get("clicks", 30))
	var grid := CSGrid.new()
	grid.generate(1, CSGrid.RINGS, str(opt.get("grid", "dodeca")))
	var bad := 0
	var total := 0
	var walls_made := 0
	for s in range(first, first + towns):
		var t := CSTown.new()
		if clicks > 0:
			CSStarter.random_growth(grid, t, s, clicks, -1 if s % 2 == 1 else 0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 9000 + s
		var tries := 0
		var made := 0
		while made < nwalls and tries < 40:
			tries += 1
			var v := rng.randi_range(0, grid.d_count - 1)
			if not grid.buildable(v):
				continue
			var deg := rng.randi_range(0, 11) * 30
			var dir := Vector2.from_angle(deg_to_rad(float(deg)))
			var stops := grid.line_stops(grid.verts[v], dir, 60.0)
			if stops.is_empty():
				continue
			var n := rng.randi_range(1, mini(stops.size(), 9))
			var len := stops[n - 1]
			# inside the island: every cell the wall crosses is a whole cell off the sea ring
			var ok_cells := true
			for u in grid.cells_along(grid.verts[v], grid.verts[v] + dir * len, false):
				if not grid.is_whole(u) or (grid.is_dodecagon(u) and not grid.buildable(u)):
					ok_cells = false
			if not ok_cells:
				continue
			if t.wall_add(v, deg, len, rng.randi_range(0, 11)):
				made += 1
		walls_made += made
		var b := CSBuild.new()
		b.build(grid, t)
		var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
		total += 1
		if int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions) > 0:
			bad += 1
			print("  defect: town %d (%d walls): open %d nm %d flipped %d T %d  walls %s" % [s, made, int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions), str(t.walls.map(func(w): return [w.v, w.deg, snappedf(w.len, 0.01)]))])
			if opt.has("info"):
				for e in au.nm_info:
					print("    nm ", e)
				for e in au.flip_info:
					print("    flip ", e)
	print("%d towns with %d walls, %d with defects" % [total, walls_made, bad])
	quit(0)
