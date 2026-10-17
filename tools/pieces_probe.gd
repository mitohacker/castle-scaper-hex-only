extends SceneTree
## Prints what holds up every block with nothing under it (arch / corbel / pillar), the stairs, and for each such block
## its neighbours one level down and every abutment pair the arch rule weighed (how opposite, how much room).
##   Godot --headless --path . --script res://tools/pieces_probe.gd -- --starter=castle [--v=123]


func _init() -> void:
	var starter := "castle"
	var only := -1
	var near := Vector2.INF
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			starter = a.get_slice("=", 1)
		elif a.begins_with("--v="):
			only = int(a.get_slice("=", 1))
		elif a.begins_with("--near="):
			var xz := a.get_slice("=", 1).split(",")
			near = Vector2(float(xz[0]), float(xz[1]))
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(starter, grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	print("== %s: pieces %s, stairs %d" % [starter, str(b.stats.get("pieces", {})), b.stairs.size()])
	if near != Vector2.INF:
		# the cells with a corner near the point: per level, # block, * arch fill, . empty; and the pieces of the plan there
		for v in grid.verts.size():
			var d := grid.dual(v)
			var hit := -1
			for i in d.size():
				if d[i].distance_to(near) < 0.6:
					hit = i
			if hit < 0 or not grid.buildable(v):
				continue
			var col := ""
			for k in range(0, 8):
				col += "#" if town.has(v, k) else ("*" if b.filled(v, k) else ".")
			var at := []
			for k in range(0, 4):
				var olk := b.level_outline(v, k)
				at.append("L%d (%.3f, %.3f)%s" % [k, olk[hit].x, olk[hit].y, " round" if b.is_round(v, k) else ""])
			var pcs := []
			for k in range(0, 8):
				if b.pieces.has(CSTown.key(v, k)):
					pcs.append("%d:%s" % [k, b.pieces[CSTown.key(v, k)]])
			print("  cell %d (%.2f, %.2f) corner %d at (%.3f, %.3f): levels 0-7 %s  %s, nbrs %s; %s" % [v, grid.verts[v].x, grid.verts[v].y, hit,
				d[hit].x, d[hit].y, col, str(pcs), str(grid.nbrs[v]), ", ".join(at)])
			for k in range(0, 3):
				print("     raw %s\n     L%d  %s" % [str(d), k, str(b.level_outline(v, k))])
		for st in b.plan.stacks.size():
			pass
		for li in b.plan.layer_count():
			var poly: PackedVector2Array = b.plan.lay_poly[li]
			for q in poly:
				if q.distance_to(near) < 0.6:
					var sd: Dictionary = b.plan.stacks[b.plan.lay_stack[li]]
					print("   layer %d %s op %d group %d owner %d y %.2f-%.2f pt (%.3f, %.3f)" % [li, sd.label, int(sd.op), int(sd.group), int(sd.owner),
						b.plan.lay_y0[li], b.plan.lay_y1[li], q.x, q.y])
					break
	for v: int in town.columns():
		if only >= 0 and v != only:
			continue
		for k in range(1, town.top(v) + 1):
			if not town.has(v, k) or town.has(v, k - 1):
				continue
			var nb: PackedInt32Array = grid.nbrs[v]
			var p := grid.verts[v]
			var below := []
			for i in nb.size():
				below.append("%d%s" % [nb[i], "#" if town.has(nb[i], k - 1) else ("*" if b.filled(nb[i], k - 1) else ".")])
			print("  block %d level %d at (%.1f, %.1f): %s; neighbours one down %s" % [v, k, p.x, p.y,
				b.pieces.get(CSTown.key(v, k), "-"), " ".join(below)])
			for i in nb.size():
				for j in range(i + 1, nb.size()):
					if not (town.has(nb[i], k - 1) and town.has(nb[j], k - 1)):
						continue
					var dd := (grid.verts[nb[i]] - p).normalized().dot((grid.verts[nb[j]] - p).normalized())
					var fi := grid.face(v, i)
					var fj := grid.face(v, j)
					var s := (grid.verts[nb[j]] - grid.verts[nb[i]]).normalized()
					var ti := maxf((fi[0] - p).dot(s), (fi[1] - p).dot(s))
					var tj := minf((fj[0] - p).dot(s), (fj[1] - p).dot(s))
					print("     pair %d,%d: dot %.2f, span %.2f m, half arch %.2f m" % [i, j, dd, tj - ti, (tj - ti) * 0.5 - CSBuild.ARCH_PIER])
	for kk: int in b._corbel_faces:
		if only < 0 or kk / 64 == only:
			var faces := []
			for i: int in b._corbel_faces[kk]:
				var u: int = grid.nbrs[kk / 64][i]
				var col := ""
				for k in range(0, 6):
					col += "#" if town.has(u, k) else ("*" if b.filled(u, k) else ".")
				faces.append("%d->%d %s" % [i, u, col])
			print("  corbels under %d level %d (%s): %s" % [kk / 64, kk % 64, "arch" if b.fills.has(kk) else "block", ", ".join(faces)])
	if only >= 0:
		for u in [only] + Array(grid.nbrs[only]):
			var col := ""
			for k in range(0, 8):
				col += "#" if town.has(u, k) else ("*" if b.filled(u, k) else ".")
			print("  column %d (%.2f, %.2f) %s round %s nbrs %s raw %s" % [u, grid.verts[u].x, grid.verts[u].y, col, str(b.col_round(u)), str(grid.nbrs[u]), str(grid.dual(u))])
	for s: Dictionary in b.stairs:
		print("  stairs on %d (level %d) up to %d: run %.2f m, gap %s" % [int(s.cell), int(s.k), int(s.up), float(s.run), str(s.gap)])
	quit(0)
