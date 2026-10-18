extends SceneTree
## What stands round the blocks whose skin has open edges: for each owner the weld audit names, its cell (sides, side lengths), the
## blocks of it and its neighbours, their tops, pieces, land and any flight of stairs on or up to it.
##   Godot --headless --path . --script res://tools/open_probe.gd -- --starter=random:6:70


func _init() -> void:
	var starter := "castle"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--starter="):
			starter = a.get_slice("=", 1)
	var grid := CSGrid.new()
	grid.generate()
	var town := CSTown.new()
	CSStarter.make(starter, grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	var owners := {}
	for s: String in au.get("open_info", []):
		var o := int(s.get_slice("owner ", 1).get_slice(" ", 0))
		owners[o] = int(owners.get(o, 0)) + 1
	print("%s: open %d, owners %s" % [starter, int(au.open_other), str(owners)])
	for o: int in owners:
		var v := o - 1
		_cell(grid, town, b, v, "OWNER")
		for u in grid.nbrs[v]:
			if town.top(u) >= 0:
				_cell(grid, town, b, u, "  nbr")
	quit(0)


func _cell(grid: CSGrid, town: CSTown, b: CSBuild, v: int, tag: String) -> void:
	var ol := grid.dual(v)
	var lens := []
	for i in ol.size():
		lens.append(snappedf(ol[i].distance_to(ol[(i + 1) % ol.size()]), 0.01))
	var levels := []
	for k in town.top(v) + 1:
		if town.has(v, k):
			levels.append(k)
	var kinds := {}
	for kk: int in b.kinds:
		if kk / 64 == v:
			kinds[kk % 64] = b.kinds[kk]
	var pcs := {}
	for kk: int in b.pieces:
		if kk / 64 == v:
			pcs[kk % 64] = b.pieces[kk]
	var st := []
	for s: Dictionary in b.stairs:
		if int(s.cell) == v or int(s.up) == v:
			st.append("cell %d up %d k %d" % [int(s.cell), int(s.up), int(s.k)])
	print("%s v %d at %s sides %d %s levels %s tops %s pieces %s land %s stairs %s" % [tag, v, str(grid.verts[v]), ol.size(), str(lens),
		str(levels), str(kinds), str(pcs), str(b.land.get(v, "-")), str(st)])
