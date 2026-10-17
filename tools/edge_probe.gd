extends SceneTree
## The triangles of a built starter that have an edge on the vertical line through (x, z) between two heights (for a
## vertical non-manifold edge the audit names): which owner, zone and facing each one has.
##   Godot --headless --path . --script res://tools/edge_probe.gd -- --starter=random:6:70 --at=x,z,y0,y1 [--d=0.003]


func _init() -> void:
	var starter := "castle"
	var at := PackedFloat32Array([0, 0, 0, 1])
	var d := 0.003
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			starter = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			at = PackedFloat32Array(Array(a.get_slice("=", 1).split(",")).map(func(s): return float(s)))
		elif a.begins_with("--d="):
			d = float(a.get_slice("=", 1))
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(starter, grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	var m := b.mesh
	var c := Vector2(at[0], at[1])
	var shown := 0
	for t in range(0, m.verts.size(), 3):
		var on := 0
		for j in 3:
			var q := m.verts[t + j]
			if Vector2(q.x, q.z).distance_to(c) < d and q.y > at[2] - 0.01 and q.y < at[3] + 0.01:
				on += 1
		if on < 2:
			continue
		var n := (m.verts[t + 1] - m.verts[t]).cross(m.verts[t + 2] - m.verts[t]).normalized()
		var txt := ""
		for j in 3:
			var q := m.verts[t + j]
			txt += "(%.3f,%.3f,%.3f) " % [q.x, q.y, q.z]
		print("tri %d zone %d owner %d normal (%.2f, %.2f, %.2f)  %s" % [t / 3, roundi(m.cols[t].r * 255.0), int(m.cust1[t * 4 + 3]), n.x, n.y, n.z, txt])
		shown += 1
		if shown > 40:
			break
	quit(0)
