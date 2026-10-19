extends SceneTree
## What a cell size costs, one line per size (CPU only: no GPU is involved, so frame time is not measured; the numbers that decide it are listed):
## the grid, the lookups a click and a hover do, the starter castle's full build, one click's incremental build (median of 3), the props, the mesh upload,
## and how much there is to draw (castle triangles, prop instances, the grid overlay's triangles).
## Run: Godot --headless --path . --script res://tools/cost_probe.gd -- --cell=4
func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var div := CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV))))
	var t0 := Time.get_ticks_usec()
	var g := CSGrid.new()
	g.generate(1, 0, CSGrid.KIND_DODECA, div)
	var ms_grid := (Time.get_ticks_usec() - t0) / 1000.0
	var cells := 0
	var overlay_tris := 0
	for v in g.verts.size():
		if g.buildable(v):
			cells += 1
			overlay_tris += g.dual(v).size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	t0 = Time.get_ticks_usec()
	for _i in 3000:
		g.nearest(Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80)))
	var us_nearest := (Time.get_ticks_usec() - t0) / 3000.0
	var t := CSTown.new()
	t.grid_div = div
	CSStarter.make("castle", g, t)
	t0 = Time.get_ticks_usec()
	var b0 := CSBuild.new()
	b0.build(g, t)
	var ms_full := (Time.get_ticks_usec() - t0) / 1000.0
	var incs: Array = []
	var last: CSBuild = b0
	for k in 3:
		var v := g.nearest(Vector2(60.0 + 4.0 * k, 10.0))
		t.add(v, 0, 3)
		t0 = Time.get_ticks_usec()
		var b1 := CSBuild.new()
		b1.build(g, t, last)
		incs.append((Time.get_ticks_usec() - t0) / 1000.0)
		last = b1
	incs.sort()
	t0 = Time.get_ticks_usec()
	var pr := CSProps.new()
	pr.build(last)
	var ms_props := (Time.get_ticks_usec() - t0) / 1000.0
	var inst := 0
	for k: String in pr.counts:
		inst += int(pr.counts[k])
	t0 = Time.get_ticks_usec()
	var m := ArrayMesh.new()
	last.mesh.commit(m, null)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(last.mesh.verts)
	var ms_commit := (Time.get_ticks_usec() - t0) / 1000.0
	var sp := ""
	for k: String in last.stats.ms_split:
		sp += " %s %.0f" % [k, float(last.stats.ms_split[k])]
	print("   rules split (ms):" + sp)
	print("1/%d: %d cells of %.1f m2 (side %.2f m), %d points | grid %.0f ms, nearest %.1f us | castle %d blocks: full build %.0f ms, one click %.0f ms (rules %.0f, plan %.0f), props %.0f ms (%d), commit+shape %.0f ms | %d castle tris, overlay %d tris" % [
		div, cells, CSGrid.BASE_AREA / float(div), g.side, g.verts.size(), ms_grid, us_nearest, t.size(), ms_full, float(incs[1]), float(last.stats.ms_rules), float(last.stats.ms_plan), ms_props, inst, ms_commit, last.mesh.tri_count(), overlay_tris])
	quit(0)
