extends SceneTree
## Straight walls in the shapes a player draws: a closed hexagon of walls, an L, a T, a cross, a row of collinear walls meeting end to end, a zigzag, a
## star of walls from one cell. Each audited. Run: Godot --headless --path . --script res://tools/wall_shapes.gd

var grid := CSGrid.new()
var bad := 0


func _initialize() -> void:
	CFPlan.debug_default = OS.get_cmdline_user_args().has("--debug")
	grid.generate()
	var c := grid.nearest(Vector2.ZERO)
	var p := grid.verts[c]
	for n in [1, 2, 3]:
		_ring(c, 0, n)
		_ring(c, 30, n)
	_check("L", _walls_from([[c, 0, 3], [-1, 60, 2]]))
	_check("T", _walls_from([[c, 0, 4], [c, 60, 2], [c, 300, 2]]))
	_check("cross", _walls_from([[c, 0, 2], [c, 180, 2], [c, 90, 2], [c, 270, 2]]))
	_check("collinear row", _walls_from([[c, 0, 1], [-1, 0, 1], [-1, 0, 1], [-1, 0, 1]]))
	_check("zigzag", _walls_from([[c, 0, 2], [-1, 60, 2], [-1, 0, 2], [-1, 60, 2]]))
	_check("star", _walls_from([[c, 0, 2], [c, 60, 2], [c, 120, 2], [c, 180, 2], [c, 240, 2], [c, 300, 2]]))
	_check("star 30", _walls_from([[c, 30, 3], [c, 90, 3], [c, 150, 3], [c, 210, 3], [c, 270, 3], [c, 330, 3]]))
	_check("overlap", _walls_from([[c, 0, 2], [c, 0, 4]]))
	_check("parallel", _walls_from([[c, 0, 3], [grid.nbrs[c][2], 0, 3]]))
	print("%d shapes with defects" % bad)
	quit(0)


func _walls_from(spec: Array) -> CSTown:
	## spec: [cell (-1: the end of the last wall), heading, stops]
	var t := CSTown.new()
	var cur := -1
	for s: Array in spec:
		var v: int = s[0] if int(s[0]) >= 0 else cur
		var dir := Vector2.from_angle(deg_to_rad(float(s[1])))
		var stops := grid.line_stops(grid.verts[v], dir, 80.0)
		var len := stops[int(s[2]) - 1]
		CSWalls.add_from_cell(t, grid, v, float(s[1]), len, 3)
		cur = grid.nearest(grid.verts[v] + dir * len, false)
		if not grid.is_dodecagon(cur):
			cur = grid.nearest(grid.verts[v] + dir * len)
	return t


func _ring(c: int, base: int, n: int) -> void:
	## A closed hexagon of walls: six walls of n stops at headings base, base+60, ...
	var spec := []
	for i in 6:
		spec.append([c if i == 0 else -1, (base + 60 * i) % 360, n])
	_check("ring %d x%d" % [base, n], _walls_from(spec))


func _check(label: String, t: CSTown) -> void:
	var b := CSBuild.new()
	b.build(grid, t)
	var au := CFAudit.check(b.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
	var d := int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions)
	if d > 0:
		bad += 1
	print("%-16s %d walls  open %d nm %d flipped %d T %d  %s" % [label, t.walls.size(), int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions), "DEFECT" if d > 0 else "ok"])
