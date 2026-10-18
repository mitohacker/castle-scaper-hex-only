extends SceneTree
## Prints what stands round one grid point: --starter=NAME --v=INDEX (owner - 1 in the audit's lines).
##   godot --headless --path . --script res://tools/dbg_probe.gd -- --starter=random:12:70:-1 --v=200


func _init() -> void:
	var name := "castle"
	var v := 0
	var drops := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			name = a.get_slice("=", 1)
		elif a.begins_with("--v="):
			v = int(a.get_slice("=", 1))
		elif a.begins_with("--drop="):
			drops = a.get_slice("=", 1).split(",")
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(name, grid, town)
	for d: String in drops:
		town.remove(int(d.get_slice(":", 0)), int(d.get_slice(":", 1)))
	var b := CSBuild.new()
	b.build(grid, town)
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	print("audit: open %d nm %d flipped %d tj %d" % [au.open_other, au.non_manifold, au.flipped, au.t_junctions])
	for i in mini((au.open_info as Array).size(), 6):
		print("  open ", au.open_info[i])
	print("v %d at %s, land %s, door side %s" % [v, str(grid.verts[v]), str(b.land.get(v, "-")), str(b.doors.get(v, -1))])
	var cells := [v]
	for u in grid.nbrs[v]:
		cells.append(u)
	for c: int in cells:
		var line := "  cell %d%s at %s: " % [c, " (this)" if c == v else "", str(grid.verts[c])]
		for k in range(0, 6):
			if town.has(c, k):
				line += "[k%d %s c%d %s] " % [k, CSStyle.KEYS[town.style(c, k)], town.colour(c, k), str(b.kinds.get(CSTown.key(c, k), ""))]
			elif b.fills.has(CSTown.key(c, k)):
				line += "[k%d arch fill] " % k
		line += " land %s pieces %s" % [str(b.land.get(c, "-")), str([b.pieces.get(CSTown.key(c, 1), ""), b.pieces.get(CSTown.key(c, 2), "")])]
		print(line)
	var ol := b.level_outline(v, 0)
	var n := ol.size()
	var di := int(b.doors.get(v, -1))
	for i in n:
		print("   side %d%s: %s -> %s length %.3f" % [i, " DOOR" if i == di else "", str(ol[(i + n - 1) % n]), str(ol[i]), ol[(i + n - 1) % n].distance_to(ol[i])])
	print("openings of this column: ", b.openings.filter(func(o: Dictionary) -> bool: return int(o.v) == v).map(func(o: Dictionary) -> String: return "%s k%d i%d" % [o.kind, o.k, o.i]))
	quit(0)
