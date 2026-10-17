extends SceneTree
## Which layers pass through a point when a starter is built: godot ... --script res://tools/probe.gd -- --starter=castle --at=x,z,y0,y1 [--r=0.1]


func _init() -> void:
	var starter := "castle"
	var at := Vector4.ZERO
	var r := 0.1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			starter = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			var q := a.get_slice("=", 1).split(",")
			at = Vector4(float(q[0]), float(q[1]), float(q[2]), float(q[3]))
		elif a.begins_with("--r="):
			r = float(a.get_slice("=", 1))
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(starter, grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	var pl := b.plan
	var p := Vector2(at.x, at.y)
	var v := grid.nearest(p, false)
	print("nearest vertex %d at %s, top %d, nbrs %s" % [v, grid.verts[v], town.top(v), str(grid.nbrs[v])])
	# the cells that have this point as a corner, with their columns and the kinds of their tops
	for u in grid.verts.size():
		if not grid.buildable(u):
			continue
		for c in grid.dual(u):
			if c.distance_to(p) < 0.02:
				var lv := []
				for k in range(0, 8):
					if town.has(u, k):
						lv.append("%d:%s" % [k, b.kinds.get(CSTown.key(u, k), "-")])
				print("  corner of cell %d (%s) round %s nbrs %s" % [u, " ".join(lv), b.col_round(u), str(grid.nbrs[u])])
	for li in pl.lay_stack.size():
		if pl.lay_y1[li] < at.z - 0.01 or pl.lay_y0[li] > at.w + 0.01:
			continue
		var vids: PackedInt32Array = pl.lay_vids[li]
		var best := INF
		for k in vids.size():
			var a := pl.vpos[vids[k]]
			var c := pl.vpos[vids[(k + 1) % vids.size()]]
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, c).distance_to(p))
		if best < r:
			var st: Dictionary = pl.stacks[pl.lay_stack[li]]
			var txt := ""
			for q in vids:
				txt += "(%.3f,%.3f) " % [pl.vpos[q].x, pl.vpos[q].y]
			print("layer %d op %d '%s' group %d owner %d y %.2f-%.2f dist %.4f\n   %s" % [li, pl.lay_op[li], st.label, st.group, st.owner,
				pl.lay_y0[li], pl.lay_y1[li], best, txt])
	quit(0)
