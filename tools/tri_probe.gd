extends SceneTree
## The triangles of a built starter that touch a segment at one height (for an open edge the audit names):
## godot ... --script res://tools/tri_probe.gd -- --starter=castle --seg=x0,z0,x1,z1,y [--d=0.05]


func _init() -> void:
	var starter := "castle"
	var seg := PackedFloat32Array([0, 0, 1, 0, 0])
	var d := 0.05
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			starter = a.get_slice("=", 1)
		elif a.begins_with("--seg="):
			seg = PackedFloat32Array(Array(a.get_slice("=", 1).split(",")).map(func(s): return float(s)))
		elif a.begins_with("--d="):
			d = float(a.get_slice("=", 1))
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(starter, grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	var m := b.mesh
	var p0 := Vector2(seg[0], seg[1])
	var p1 := Vector2(seg[2], seg[3])
	var y := seg[4]
	var shown := 0
	for t in range(0, m.verts.size(), 3):
		var near := 0
		for j in 3:
			var q := m.verts[t + j]
			if absf(q.y - y) < d and Geometry2D.get_closest_point_to_segment(Vector2(q.x, q.z), p0, p1).distance_to(Vector2(q.x, q.z)) < d:
				near += 1
		if near < 2:
			continue
		var txt := ""
		for j in 3:
			var q := m.verts[t + j]
			txt += "(%.3f,%.3f,%.3f) " % [q.x, q.y, q.z]
		print("tri zone %d owner %d  %s" % [roundi(m.cols[t].r * 255.0), int(m.cust1[t * 4 + 3]), txt])
		shown += 1
		if shown > 60:
			break
	# the battlement and walk layers within 1 m of the segment
	var pl := b.plan
	for li in pl.lay_stack.size():
		if pl.lay_y1[li] < y - 0.01 or pl.lay_y0[li] > y + 1.2:
			continue
		var st: Dictionary = pl.stacks[pl.lay_stack[li]]
		var vids: PackedInt32Array = pl.lay_vids[li]
		var best := INF
		for k in vids.size():
			var q := pl.vpos[vids[k]]
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, p0, p1).distance_to(q))
		if best < 1.0:
			var txt := ""
			for q in vids:
				txt += "(%.3f,%.3f) " % [pl.vpos[q].x, pl.vpos[q].y]
			print("layer %d stack %d op %d '%s' group %d owner %d y %.2f-%.2f\n   %s" % [li, pl.lay_stack[li], pl.lay_op[li], st.label, st.group,
				st.owner, pl.lay_y0[li], pl.lay_y1[li], txt])
	quit(0)
