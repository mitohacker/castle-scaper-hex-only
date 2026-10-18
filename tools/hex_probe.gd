extends SceneTree
## Stress test of the regular hex grid: random click-built castles (and mixed-style towns), plus towers and walls on every cell along
## the board's edge, each audited for open edges, non-manifold edges, flipped faces and T-junctions.
## Run: Godot --headless --path . --script res://tools/hex_probe.gd -- --towns=40 [--clicks=70] [--styles=0,-1,1,2,3,4,5,6] [--from=0]


func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var towns := int(opt.get("towns", 40))
	var clicks := int(opt.get("clicks", 70))
	var first := int(opt.get("from", 0))
	var styles: Array = []
	for st in str(opt.get("styles", "0,-1")).split(","):
		styles.append(int(st))
	var total := 0
	var bad := 0
	var worst_open := 0
	var worst_nm := 0
	var pieces := {}
	var stairs := 0
	for gs in 1:
		var grid := CSGrid.new()
		grid.generate()
		for style in styles:
			for s in range(first, first + towns):
				var t := CSTown.new()
				CSStarter.random_growth(grid, t, s, clicks, style)
				var r := _audit(grid, t)
				total += 1
				worst_open = maxi(worst_open, r[0])
				worst_nm = maxi(worst_nm, r[1])
				if r[0] + r[1] + r[2] + r[3] > 0:
					bad += 1
					print("  defect: style %d town %d: open %d nm %d flipped %d T %d" % [style, s, r[0], r[1], r[2], r[3]])
				for k: String in (r[4] as Dictionary):
					pieces[k] = int(pieces.get(k, 0)) + int(r[4][k])
				stairs += int(r[5])
		# the board's edge: a tower on every other cell next to the border, a wall (two levels) on the rest
		var edge: Array = []
		for v in grid.verts.size():
			if grid.buildable(v):
				for u in grid.nbrs[v]:
					if grid.border[u]:
						edge.append(v)
						break
		for mode in 3:
			var t := CSTown.new()
			for i in edge.size():
				var v: int = edge[i]
				t.add(v, 0, 1)
				if mode == 0 and i % 2 == 0:
					for k in range(1, 4):
						t.add(v, k, 2)
				elif mode == 1:
					t.add(v, 1, 3)
				elif mode == 2 and i % 3 == 0:
					t.add(v, 1, 3)
					t.add(v, 2, 3)
			var r := _audit(grid, t)
			total += 1
			if r[0] + r[1] + r[2] + r[3] > 0:
				bad += 1
				print("  defect: edge ring mode %d (%d cells): open %d nm %d flipped %d T %d" % [mode, edge.size(), r[0], r[1], r[2], r[3]])
			worst_open = maxi(worst_open, r[0])
			worst_nm = maxi(worst_nm, r[1])
			stairs += int(r[5])
	print("%d towns, %d with defects, worst open %d, worst non-manifold %d, stairs %d, pieces %s" % [total, bad, worst_open, worst_nm, stairs, str(pieces)])
	quit(0)


func _audit(grid: CSGrid, t: CSTown) -> Array:
	var b := CSBuild.new()
	b.build(grid, t)
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	var pc := {}
	for kk in b.pieces:
		pc[b.pieces[kk]] = int(pc.get(b.pieces[kk], 0)) + 1
	return [int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions), pc, b.stairs.size()]
