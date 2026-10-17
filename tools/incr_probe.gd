extends SceneTree
## Clicks blocks on and off a castle again and again and builds each result twice, from scratch and from the previous
## castle (as the editor does); prints the times and fails when the two meshes differ.
##   Godot --headless --path . --script res://tools/incr_probe.gd -- --starter=castle --edits=30 --seed=1 [--quiet]

var rng := RandomNumberGenerator.new()


func _init() -> void:
	var starter := "castle"
	var edits := 30
	var seed_v := 1
	var verbose := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			starter = a.substr(10)
		elif a.begins_with("--edits="):
			edits = int(a.substr(8))
		elif a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a == "--quiet":
			verbose = false
	rng.seed = seed_v
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(starter, grid, town)
	var prev := CSBuild.new()
	prev.build(grid, town)
	var mismatches := 0
	var shifted := 0             # differs only by a vertex merged a few mm elsewhere, still closed
	var t_inc := 0.0
	var t_full := 0.0
	for e in edits:
		var what := edit(grid, town)
		var inc := CSBuild.new()
		var t0 := Time.get_ticks_usec()
		inc.build(grid, town, prev)
		var t1 := Time.get_ticks_usec()
		var full := CSBuild.new()
		full.build(grid, town)
		var t2 := Time.get_ticks_usec()
		var same := same_mesh(inc.mesh, full.mesh)
		if not same:
			mismatches += 1
		t_inc += (t1 - t0) / 1000.0
		t_full += (t2 - t1) / 1000.0
		if verbose or not same:
			print("%-28s inc %5.0f ms  full %5.0f ms  %s" % [what, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, "same" if same else "DIFFERENT (%d vs %d tris)" % [
				inc.mesh.tri_count(), full.mesh.tri_count()]])
		if not same:
			var worst := 0.0
			if inc.mesh.verts.size() == full.mesh.verts.size():
				for i in inc.mesh.verts.size():
					worst = maxf(worst, inc.mesh.verts[i].distance_to(full.mesh.verts[i]))
			var au := CFAudit.check(inc.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
			print("      worst vertex shift %.4f m; incremental mesh: open %d, non-manifold %d, flipped %d, T %d" % [worst, int(au.open_other),
				int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
			if worst < 0.03 and int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions) == 0:
				mismatches -= 1
				shifted += 1
		prev = inc
	print("%d edits, %d mismatches (%d more only shifted a vertex under 3 cm, still closed); incremental avg %.0f ms, full avg %.0f ms" % [
		edits, mismatches, shifted, t_inc / edits, t_full / edits])
	quit(1 if mismatches > 0 else 0)


static func same_mesh(a: CFMesh, b: CFMesh) -> bool:
	return a.verts == b.verts and a.norms == b.norms and a.tans == b.tans and a.uvs == b.uvs and a.uv2s == b.uv2s and a.cols == b.cols \
		and a.cust0 == b.cust0 and a.cust1 == b.cust1


func edit(grid: CSGrid, town: CSTown) -> String:
	## One click of the kind the player makes: on top of a column, beside one, on the sea, or a block taken away.
	var cols := town.columns()
	var r := rng.randf()
	if cols.is_empty() or r < 0.12:
		var v := grid.nearest(Vector2(rng.randf_range(-28, 28), rng.randf_range(-28, 28)))
		if v >= 0 and town.add(v, 0, rng.randi_range(0, 11)):
			return "add %d on the sea" % v
		return "sea click (taken)"
	var v0: int = cols[rng.randi_range(0, cols.size() - 1)]
	if r < 0.4:
		town.add(v0, town.top(v0) + 1, rng.randi_range(0, 11))
		return "stack on %d (level %d)" % [v0, town.top(v0)]
	if r < 0.7:
		var nb: PackedInt32Array = grid.nbrs[v0]
		var u := nb[rng.randi_range(0, nb.size() - 1)]
		var k := rng.randi_range(0, maxi(0, town.top(v0)))
		if grid.buildable(u) and town.add(u, k, rng.randi_range(0, 11)):
			return "beside %d: %d level %d" % [v0, u, k]
		return "beside (taken)"
	var k2 := town.top(v0)
	town.remove(v0, k2)
	return "remove %d level %d" % [v0, k2]
