extends SceneTree
## Headless checks: Townscaper's grid, the block model, the rules (what a block becomes from its neighbours), every
## starter and random click-built castles audited as one welded skin, what holds a block with nothing under it up (an
## arch, corbels, a pillar) and stairs, the birds' perches, the prop layer (no two props overlap, none sits inside a
## block, an arch, a corbel, a pillar or stairs, the same every time, every kind on the castle starter, quick enough).
## Run: Godot --headless --path . --script res://tests/verify_cs_core.gd   (exit code = failures)

const SKIP := [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B]
const CASTLE_004 := [[508,330,26.97,1],[707,120,15.57,1],[508,240,15.57,1],[505,180,10.38,1],[430,90,11.99,1],[397,60,10.38,1],[329,60,15.57,1],[332,150,5.99,1],[332,330,8.99,1],[268,270,11.99,1],[268,210,17.98,1],[268,330,5.99,1],[303,180,10.38,1],[240,90,8.99,1],[303,60,15.57,1],[306,0,10.38,1],[373,60,5.19,1],[374,150,8.99,1],[212,90,17.98,1],[241,270,3.0,1],[271,120,5.19,1],[241,90,20.97,1],[241,90,11.99,1],[271,90,26.97,1],[272,90,20.97,1],[272,270,3.0,1],[244,30,8.99,1],[211,90,20.97,1],[183,270,8.99,1],[183,90,11.99,1]]   # a player's castle_004: [cell, heading, length, colour]
const PROPS_MIN := 2                # the castle starter shows at least this many of every kind of prop

var fails := 0
var checks := 0
var grid := CSGrid.new()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL ", what)


func _init() -> void:
	print("== grid")
	_grid()
	print("== blocks")
	_town()
	print("== rules")
	_rules()
	print("== what holds blocks up, and stairs")
	_supports()
	_stairs()
	print("== straight walls")
	_walls()
	print("== walls laid side by side merge into a thicker wall")
	_merging()
	print("== wall corners and ends")
	_corners()
	print("== wall directions: 12, 16, 24")
	_directions()
	print("== the plain hexagon grid")
	_hex_grid()
	print("== smaller cells")
	_cell_sizes()
	print("== castles audited")
	_audits()
	print("== building styles")
	_styles()
	print("== birds")
	_birds()
	print("== props")
	_props()
	print("== landscape")
	_landscape()
	print("== look")
	_look()
	print("== rocks and sea floor")
	_rocks()
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails else 0)


func _complete(v: int) -> bool:
	## A point whose cell is a whole polygon (not on the board's edge).
	if grid.border[v]:
		return false
	for q in grid.rings[v]:
		if q < 0:
			return false
	return true


func _grid() -> void:
	var t0 := Time.get_ticks_msec()
	grid.generate()
	var ms := Time.get_ticks_msec() - t0
	var side := CSGrid.SIDE
	var nq := grid.tris.size() / 3
	ok(nq > 5000 and grid.verts.size() > 3000, "the double hex grid is a real grid (%d faces, %d points, %d of them dodecagon centres)" % [nq, grid.verts.size(), grid.d_count])
	ok(ms < 4000, "made in %d ms" % ms)
	var folded := 0
	for q in nq:
		var a := grid.verts[grid.tris[q * 3]]
		var b := grid.verts[grid.tris[q * 3 + 1]]
		var c := grid.verts[grid.tris[q * 3 + 2]]
		if (b - a).cross(c - a) <= 0.0:
			folded += 1
	ok(folded == 0, "every face of the point graph runs counter-clockwise (%d folded)" % folded)
	var val := {}
	var asym := 0
	var bad_cell := 0
	var buildable := 0
	var tri_buildable := 0
	var lost := 0
	var alternate_bad := 0
	var tri_lost := 0
	for v in grid.verts.size():
		for u in grid.nbrs[v]:
			if grid.index_of(u, v) < 0:
				asym += 1
		if not grid.is_dodecagon(v) and grid.buildable(v):
			tri_buildable += 1
		if not _complete(v):
			continue
		var nb: PackedInt32Array = grid.nbrs[v]
		val[nb.size()] = int(val.get(nb.size(), 0)) + 1
		var d := grid.dual(v)
		if d.size() != nb.size() or CFTri.area(d) <= 0.5:
			bad_cell += 1
		if grid.buildable(v):
			buildable += 1
			if grid.nearest(grid.verts[v]) != v:
				lost += 1
		if grid.nearest(grid.verts[v], false) != v:
			tri_lost += 1
		if grid.is_dodecagon(v):
			# a dodecagon's twelve neighbours alternate: dodecagon, triangle, dodecagon, ...
			for i in nb.size():
				if grid.is_dodecagon(nb[i]) != (i % 2 == (0 if grid.is_dodecagon(nb[0]) else 1)):
					alternate_bad += 1
		else:
			for u in nb:
				if not grid.is_dodecagon(u):
					alternate_bad += 1
	ok(asym == 0, "neighbours are mutual (%d one-way)" % asym)
	ok(buildable == 1141, "1141 buildable cells, as many as the regular hexagon grid had (%d)" % buildable)
	ok(tri_buildable == 0, "the small triangles between the dodecagons are not buildable (%d are)" % tri_buildable)
	var n12 := int(val.get(12, 0))
	var n3 := int(val.get(3, 0))
	ok(val.size() == 2 and n12 >= 1141 and n3 > n12, "every cell is a dodecagon (12 sides) or a triangle (3): %d and %d (%s)" % [n12, n3, str(val)])
	ok(alternate_bad == 0, "a dodecagon touches dodecagons and triangles in turn, a triangle only dodecagons (%d wrong)" % alternate_bad)
	# regular polygons with one side length: dodecagons 150 degree corners, triangles 60, the areas of 3 (2 + sqrt 3) t^2 and sqrt 3 / 4 t^2
	var dodeca_area := 3.0 * (2.0 + sqrt(3.0)) * side * side
	ok(absf(dodeca_area - 12.5 * sqrt(3.0)) < 0.01, "a dodecagon is as big as the regular hexagon of side 5 / sqrt 3 it replaces: %.2f m2 (side %.3f m)" % [dodeca_area, side])
	var side_lo := INF
	var side_hi := 0.0
	var ang_bad := 0
	var area_bad := 0
	var edge_cells := 0
	var shared_bad := 0
	var dirs := {}
	var east_dodecagons := 0
	var all_dodecagons := 0
	for v in grid.verts.size():
		if not _complete(v):
			continue
		var dv := grid.dual(v)
		var nd := dv.size()
		var want_area := dodeca_area if nd == 12 else sqrt(3.0) / 4.0 * side * side
		if absf(CFTri.area(dv) - want_area) > 0.01:
			area_bad += 1
		var has_east := false
		for i in nd:
			var e0 := dv[(i + 1) % nd] - dv[i]
			var e1 := dv[(i + 2) % nd] - dv[(i + 1) % nd]
			side_lo = minf(side_lo, e0.length())
			side_hi = maxf(side_hi, e0.length())
			var corner := 180.0 - rad_to_deg(absf(e0.angle_to(e1)))
			if absf(corner - (150.0 if nd == 12 else 60.0)) > 0.01:
				ang_bad += 1
			dirs[roundi(fposmod(rad_to_deg(e0.angle()), 360.0) * 10.0) % 3600] = true
			if nd == 12 and absf(e0.x) < 1e-4:
				has_east = true
		if nd == 12:
			all_dodecagons += 1
			if has_east:
				east_dodecagons += 1
		var touches_border := false
		for u in grid.nbrs[v]:
			if grid.border[u]:
				touches_border = true
		if touches_border:
			edge_cells += 1
		# a cell corner is shared by three cells that all touch: the face's other two points are neighbours of each other
		for q in grid.rings[v]:
			var t := [grid.tris[q * 3], grid.tris[q * 3 + 1], grid.tris[q * 3 + 2]]
			if grid.index_of(t[0], t[1]) < 0 or grid.index_of(t[1], t[2]) < 0 or grid.index_of(t[2], t[0]) < 0:
				shared_bad += 1
	ok(side_hi - side_lo < 2e-3 and absf(side_lo - side) < 2e-3, "every side of every cell is the same length, %.4f m (%.4f .. %.4f)" % [side, side_lo, side_hi])
	ok(ang_bad == 0, "every corner is 150 degrees (dodecagon) or 60 (triangle) (%d off)" % ang_bad)
	ok(area_bad == 0, "every dodecagon is %.2f m2 and every triangle %.2f m2 (%d off)" % [dodeca_area, sqrt(3.0) / 4.0 * side * side, area_bad])
	ok(dirs.size() == 12, "the sides run in 12 directions, 30 degrees apart (%d found)" % dirs.size())
	ok(east_dodecagons == all_dodecagons, "every dodecagon has a flat side facing east (%d of %d)" % [east_dodecagons, all_dodecagons])
	ok(edge_cells > 100, "cells stand along the board's edge too (%d)" % edge_cells)
	ok(shared_bad == 0, "every cell corner is shared by three cells that all touch (%d bad)" % shared_bad)
	var concave := 0
	for v in grid.verts.size():
		if _complete(v) and not CSBuild.convex(grid.dual(v)):
			concave += 1
	ok(concave == 0, "every cell is convex (%d)" % concave)
	ok(bad_cell == 0, "every cell is a closed counter-clockwise polygon (%d bad)" % bad_cell)
	ok(lost == 0 and tri_lost == 0, "the cell under a cell's own middle is that cell (%d dodecagons, %d triangles wrong)" % [lost, tri_lost])
	# the cell under a point: also near the corners, where the nearest centre is a different cell
	var wrong := 0
	for v in grid.verts.size():
		if not _complete(v):
			continue
		var cell: PackedVector2Array = grid.cells[v]
		var cen := CSRoofs.centroid(cell)
		for q in cell:
			var p := q + (cen - q).normalized() * 0.1
			if grid.nearest(p, false) != v:
				wrong += 1
	ok(wrong == 0, "a point just inside any corner of a cell is in that cell (%d wrong)" % wrong)
	# a click over a triangle goes to a dodecagon beside it
	var tri := -1
	for v in range(grid.d_count, grid.verts.size()):
		if _complete(v) and grid.verts[v].length() < 20.0:
			tri = v
			break
	var near := grid.nearest(grid.verts[tri])
	ok(tri >= 0 and grid.buildable(near) and (grid.nbrs[tri] as PackedInt32Array).has(near), "a point over a triangle names one of the three dodecagons round it")
	var g2 := CSGrid.new()
	g2.generate()
	ok(g2.verts == grid.verts, "the grid is the same every time")
	_grid_lines()


func _grid_lines() -> void:
	## The 12 directions, and the cells a line along one of them passes through.
	var eps := 1e-4
	var cases := {14.0: 0.0, 16.0: 30.0, 44.0: 30.0, 46.0: 60.0, 89.0: 90.0, 175.0: 180.0, -80.0: -90.0, -14.9: 0.0, -15.1: -30.0}
	var snap_ok := true
	for deg: float in cases:
		var d := CSGrid.snap_direction(Vector2.from_angle(deg_to_rad(deg)) * 7.0)
		if absf(angle_difference(d.angle(), deg_to_rad(float(cases[deg])))) > eps:
			snap_ok = false
	ok(snap_ok, "a direction snaps to the nearest multiple of 30 degrees")
	var c := grid.nearest(Vector2.ZERO)
	var p0 := grid.verts[c]
	ok(grid.is_dodecagon(c), "the middle of the map is a dodecagon")
	# along 0 degrees: the row of dodecagons, one every D_SPACING
	var row := grid.cells_along(p0, p0 + Vector2(CSGrid.D_SPACING * 3.0, 0.0))
	var row_ok := row.size() == 4
	for i in row.size():
		if not grid.is_dodecagon(row[i]) or grid.verts[row[i]].distance_to(p0 + Vector2(CSGrid.D_SPACING * float(i), 0.0)) > 1e-3:
			row_ok = false
	ok(row_ok, "along 0 degrees a line goes through the row of dodecagons and nothing else (%d cells)" % row.size())
	# along 30 degrees: the line leaves the first dodecagon through a triangle and then runs along the shared side of two dodecagons: both count
	var diag := grid.cells_along(p0, p0 + Vector2.from_angle(deg_to_rad(30.0)) * CSGrid.D_SPACING * 2.0)
	var all_d := true
	for u in diag:
		if not grid.is_dodecagon(u):
			all_d = false
	ok(diag.size() >= 4 and diag[0] == c and all_d, "along 30 degrees it goes through the dodecagons on both sides of the line (%d cells)" % diag.size())
	var with_tri := grid.cells_along(p0, p0 + Vector2.from_angle(deg_to_rad(30.0)) * CSGrid.D_SPACING * 2.0, false)
	ok(with_tri.size() > diag.size(), "and the triangles on it too when asked (%d)" % with_tri.size())
	# every cell it names is touched by the line, and the cells are in the order it meets them
	var touched := true
	var last_t := -1.0
	var in_order := true
	var a := p0
	var b := p0 + Vector2.from_angle(deg_to_rad(60.0)) * 40.0
	for u in grid.cells_along(a, b):
		var cell: PackedVector2Array = grid.cells[u]
		var dist := _seg_poly_distance(a, b, cell)
		if dist > 0.03:
			touched = false
		var t := (grid.verts[u] - a).dot((b - a).normalized())
		if t < last_t - CSGrid.D_SPACING:
			in_order = false
		last_t = maxf(last_t, t)
	ok(touched and in_order, "every cell along a 60 degree line is touched by it, in the order it meets them")
	var away := grid.cells_along(p0 + Vector2(0.0, 2.0), p0 + Vector2(0.5, 2.0))
	ok(away.size() == 1 and away[0] == c, "a short line inside a cell names only that cell")


func _seg_poly_distance(a: Vector2, b: Vector2, poly: PackedVector2Array) -> float:
	## How far the segment a-b is from a convex polygon (0 when it crosses or touches it).
	var n := poly.size()
	var best := INF
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		if Geometry2D.segment_intersects_segment(a, b, p, q) != null:
			return 0.0
		best = minf(best, minf(Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p), Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q)))
		best = minf(best, minf(Geometry2D.get_closest_point_to_segment(a, p, q).distance_to(a), Geometry2D.get_closest_point_to_segment(b, p, q).distance_to(b)))
	var inside := true
	for i in n:
		if (poly[(i + 1) % n] - poly[i]).cross(a - poly[i]) < 0.0:
			inside = false
	return 0.0 if inside else best


func _town() -> void:
	var t := CSTown.new()
	var v := grid.nearest(Vector2.ZERO)
	ok(t.add(v, 0, 3) and t.add(v, 2, 4) and not t.add(v, 0, 1), "add, and no two blocks in one place")
	ok(t.top(v) == 2 and t.columns() == [v], "top and columns")
	var t2 := CSTown.new()
	t2.from_dict(t.to_dict())
	ok(t2.blocks == t.blocks, "save and load keep every block and colour")
	ok(t.remove(v, 2) and t.top(v) == 0, "remove")


func _built(t: CSTown) -> CSBuild:
	var b := CSBuild.new()
	b.build(grid, t)
	return b


func _rules() -> void:
	var c := grid.nearest(Vector2.ZERO)
	# a single block: a cottage under a roof
	var t := CSTown.new()
	t.add(c, 0, 2)
	var b := _built(t)
	ok(b.kinds.get(CSTown.key(c, 0), "") == "cottage" and b.caps.size() == 1, "one block alone is a cottage with a roof")
	# a column of five: a round tower, its top a cone roof or battlements
	t.clear()
	for k in 5:
		t.add(c, k, 0)
	b = _built(t)
	var top_kind: String = b.kinds.get(CSTown.key(c, 4), "")
	ok(top_kind == "tower" or top_kind == "battle", "a tall lone column is a tower (%s)" % top_kind)
	ok(b.is_round(c, 2), "its shaft is round")
	# two blocks side by side: a wall walk with battlements, no roof
	t.clear()
	t.add(c, 0, 1)
	t.add(grid.nbrs[c][0], 0, 1)
	b = _built(t)
	ok(b.kinds.get(CSTown.key(c, 0), "") == "walk" and b.caps.is_empty(), "blocks side by side make a wall walk")
	var battle := 0
	for st: Dictionary in b.plan.stacks:
		if st.get("label", "") == "battlement":
			battle += 1
	ok(battle > 0, "the walk has battlements")
	# the castle starter: a courtyard, a gate passage, doors, towers
	t.clear()
	CSStarter.make("castle", grid, t)
	b = _built(t)
	var lands := {}
	for v in b.land:
		lands[b.land[v]] = int(lands.get(b.land[v], 0)) + 1
	ok(int(lands.get("court", 0)) > 10, "a ring of walls encloses a courtyard (%s)" % str(lands))
	ok(int(lands.get("passage", 0)) >= 1, "a block bridging a gap makes a gate passage")
	var doors := 0
	for st: Dictionary in b.plan.stacks:
		if st.get("label", "") == "door leaf":
			doors += 1
	ok(doors >= 3, "ground blocks facing the courtyard get doors (%d)" % doors)
	var towers := 0
	for kk in b.kinds:
		if b.kinds[kk] in ["tower", "battle"]:
			towers += 1
	ok(towers >= 3, "the corner columns rise into towers (%d)" % towers)
	var gate_arch := false
	for kk in b.pieces:
		if b.pieces[kk] == "arch" and b.land.get(kk / 64, "") == "passage":
			gate_arch = true
	ok(gate_arch, "the gate passage is an arch")


func _closed(b: CSBuild, what: String) -> void:
	var au := CFAudit.check(b.mesh, SKIP)
	ok(int(au.open_other) == 0 and int(au.non_manifold) == 0 and int(au.flipped) == 0 and int(au.t_junctions) == 0,
		"%s: closed (open %d, non-manifold %d, flipped %d, T %d)" % [what, int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])


func _solid(b: CSBuild, p: Vector2, y: float) -> bool:
	return b.plan.inside_point(Vector3(p.x, y, p.y))


func _supports() -> void:
	var c := grid.nearest(Vector2.ZERO)
	var nb: PackedInt32Array = grid.nbrs[c]
	var p := grid.verts[c]
	# a block bridging two walls: an arch under it, its span between them
	var bi := 0
	var bj := 1
	var best := 2.0
	for i in nb.size():
		for j in range(i + 1, nb.size()):
			var dd := (grid.verts[nb[i]] - p).normalized().dot((grid.verts[nb[j]] - p).normalized())
			if dd < best:
				best = dd
				bi = i
				bj = j
	var t := CSTown.new()
	for u in [nb[bi], nb[bj]]:
		t.add(u, 0, 1)
		t.add(u, 1, 1)
	t.add(c, 1, 2)
	var b := _built(t)
	ok(b.pieces.get(CSTown.key(c, 1), "") == "arch" and b.fills.has(CSTown.key(c, 0)), "a block bridging two walls stands on an arch")
	var rec: Dictionary = b.fills.get(CSTown.key(c, 0), {})
	if rec.has("cut"):
		var centre: Vector2 = rec.cut[0]
		var s: Vector2 = rec.cut[1]
		var w: float = rec.cut[2]
		ok(not _solid(b, centre, CSBuild.B + 1.0) and not _solid(b, centre, CSBuild.level_y_static(1) - 0.6),
			"its passage is open up to the crown")
		ok(_solid(b, centre, CSBuild.level_y_static(1) - 0.15), "a band of masonry over the crown carries the block")
		ok(_solid(b, centre - s * (w + 0.12), CSBuild.B + 1.0) and _solid(b, centre + s * (w + 0.12), CSBuild.B + 1.0),
			"its piers stand against the two walls")
		var stepped := 0
		for li in b.plan.layer_count():
			if b.plan.lay_op[li] == CFPlan.OP_CUT and str(b.plan.stacks[b.plan.lay_stack[li]].label) == "arch":
				stepped += 1
		ok(stepped >= 4, "the arch is stepped (%d courses)" % stepped)
	else:
		ok(false, "the arch is cut through its fill")
	ok(int(b.doors.get(nb[bi], -1)) != grid.index_of(nb[bi], c) and int(b.doors.get(nb[bj], -1)) != grid.index_of(nb[bj], c),
		"no door opens into an arch's pier")
	_closed(b, "the arch")
	# a block hung on a tower's side: corbels; one hung on that block, with no wall under it: a pillar
	t.clear()
	for k in 4:
		t.add(c, k, 0)
	var v1 := nb[0]
	var v2 := -1
	for u in grid.nbrs[v1]:
		if u != c and grid.index_of(u, c) < 0 and grid.buildable(u):
			v2 = u
			break
	t.add(v1, 2, 3)
	t.add(v2, 2, 5)
	b = _built(t)
	ok(b.pieces.get(CSTown.key(v1, 2), "") == "corbel", "a block hung on a wall stands on corbels (%s)" % b.pieces.get(CSTown.key(v1, 2), "-"))
	ok(b.pieces.get(CSTown.key(v2, 2), "") == "pillar", "a block with no wall under it stands on a pillar (%s)" % b.pieces.get(CSTown.key(v2, 2), "-"))
	var i1 := grid.index_of(v1, c)
	var f := grid.face(v1, i1)
	var fm := (f[0] + f[1]) * 0.5
	var into := (grid.verts[v1] - fm).normalized()
	var y2 := CSBuild.level_y_static(2)
	ok(_solid(b, fm + into * 0.3, y2 - 0.2) and _solid(b, fm + into * 0.15, y2 - 0.9) and not _solid(b, fm + into * 0.3, y2 - 1.5),
		"the corbel steps out of the tower's wall under the block")
	var q2 := grid.verts[v2]
	var corner := grid.dual(v2)[0]
	ok(_solid(b, q2, CSBuild.B + 2.0) and _solid(b, q2, y2 - 1.0) and not _solid(b, q2 + (corner - q2) * 0.6, CSBuild.B + 2.0),
		"the pillar runs from the ground up to the block, air round it")
	_closed(b, "corbels and a pillar")


func _ring_town(c: int, raise: bool) -> CSTown:
	## Blocks round c's cell (its six dodecagon neighbours, which touch each other side to side: the triangles are no cells to build on) at
	## level 0: a wall walk round a one-cell courtyard; with raise, three neighbours in a row one level higher.
	var t := CSTown.new()
	var nb: PackedInt32Array = grid.nbrs[c]
	var j := 0
	for i in nb.size():
		if not grid.is_dodecagon(nb[i]):
			continue
		t.add(nb[i], 0, 1)
		if raise and j <= 2:
			t.add(nb[i], 1, 1)
		j += 1
	return t


func _stairs() -> void:
	# a wall walk round a courtyard, part of it a level higher: stairs up from the courtyard and between the two walks
	var found := -1
	var b: CSBuild = null
	var near := []
	for v in grid.verts.size():
		if grid.buildable(v) and grid.verts[v].length() < 30.0 and (grid.nbrs[v] as PackedInt32Array).size() == 12:
			near.append(v)
	near.sort_custom(func(x: int, y: int) -> bool: return grid.verts[x].length() < grid.verts[y].length())
	for ci in mini(near.size(), 40):
		var c: int = near[ci]
		var bb := _built(_ring_town(c, true))
		var ground := false
		var walk := false
		for s: Dictionary in bb.stairs:
			if int(s.k) == -1 and int(s.cell) == c:
				ground = true
			if int(s.k) == 0:
				walk = true
		if ground and bb.land.get(c, "") == "court":
			found = c
			b = bb
			break
	ok(found >= 0, "a courtyard gets stairs up to its wall walk (round %d; a flight between two walks needs more side than a 1.39 m side leaves between the parapets of its neighbours, so there are none here)" % found)
	if b == null:
		return
	for s: Dictionary in b.stairs:
		var b0: Vector2 = s.b0
		var b1: Vector2 = s.b1
		var nin: Vector2 = s.nin
		var m := (b0 + b1) * 0.5
		var y_top := CSBuild.level_y_static(int(s.k) + 2) if int(s.k) >= 0 else CSBuild.level_y_static(1)
		var tread := float(s.run) / float(CSBuild.STAIR_STEPS)
		var label := "from the courtyard" if int(s.k) < 0 else "between the walks"
		ok(_solid(b, m + nin * tread * 0.5, y_top - 0.2) and not _solid(b, m + nin * tread * 1.5, y_top - 0.2) and \
			_solid(b, m + nin * (float(s.run) - tread * 0.5), y_top - CSBuild.H + 0.2),
			"stairs %s: ten steps, the top one against the higher block" % label)
		ok(not _solid(b, m - nin * CSBuild.PT * 0.5, y_top + 0.6), "stairs %s: the parapet opens where they arrive" % label)
		if int(s.k) < 0:
			ok(int(b.doors.get(int(s.up), -1)) != int(s.up_face), "stairs from the courtyard are not in front of a door")
	_closed(b, "stairs")


func _wall_town(spec: Array) -> CSTown:
	## spec: [cell (-1: where the last wall ended), heading, stops]
	var t := CSTown.new()
	var cur := -1
	for sp: Array in spec:
		var v: int = sp[0] if int(sp[0]) >= 0 else cur
		var dir := Vector2.from_angle(deg_to_rad(float(sp[1])))
		var stops := grid.line_stops(grid.verts[v], dir, 80.0)
		var len := stops[int(sp[2]) - 1]
		CSWalls.add_from_cell(t, grid, v, float(sp[1]), len, 3)
		cur = grid.nearest(grid.verts[v] + dir * len)
	return t


func _walls() -> void:
	# where a wall may end: along a row of dodecagons every D_SPACING, along the 30 degree lines every 3 m or so; never closer than half a cell
	var c := grid.nearest(Vector2.ZERO)
	var p0 := grid.verts[c]
	var st0 := grid.line_stops(p0, Vector2.RIGHT, 40.0)
	var st30 := grid.line_stops(p0, Vector2.from_angle(deg_to_rad(30.0)), 40.0)
	var step_ok := st0.size() >= 6 and st30.size() >= 8
	for i in st0.size():
		if absf(st0[i] - CSGrid.D_SPACING * float(i + 1)) > 1e-3:
			step_ok = false
	for i in range(1, st30.size()):
		if st30[i] - st30[i - 1] < 2.5 or st30[i] - st30[i - 1] > 5.3:
			step_ok = false
	ok(step_ok, "a wall may end at the middle of every dodecagon along a row (%d stops) and every 3 to 5 m along a 30 degree line (%d)" % [st0.size(), st30.size()])
	# a wall of its own: the rectangle, its clearance from every corner of the grid, the save round trip
	var t := _wall_town([[c, 0, 3]])
	var w: Dictionary = t.walls[0]
	var poly := CSBuild.wall_poly(grid, w)
	ok(poly.size() == 4 and CFTri.area(poly) > 0.0 and absf(CFTri.area(poly) - CSBuild.WALL_THICK * float(w.len)) < 1e-3, "a wall is a counter-clockwise rectangle %.1f m thick (%.2f m2)" % [CSBuild.WALL_THICK, CFTri.area(poly)])
	var near := INF
	for v in grid.verts.size():
		if grid.verts[v].distance_to(p0) < 30.0 and _complete(v):
			for q in grid.cells[v]:
				var off := absf((q - p0).cross(Vector2.RIGHT))
				near = minf(near, absf(off - CSBuild.WALL_THICK * 0.5)) if (q - p0).dot(Vector2.RIGHT) > 0.0 and (q - p0).dot(Vector2.RIGHT) < w.len else near
	ok(near > 0.2, "the sides of a wall along a row keep 0.2 m clear of every corner of the grid (%.2f m)" % near)
	var t2 := CSTown.new()
	t2.from_dict(t.to_dict())
	ok(t2.walls.size() == 1 and absf(float(t2.walls[0].x) - p0.x) < 1e-3 and absf(float(t2.walls[0].len) - float(w.len)) < 1e-3 and int(t2.walls[0].deg) == 0 and absf(float(t2.walls[0].w) - CSBuild.WALL_THICK) < 1e-3, "walls save and load")
	ok(not CSWalls.add_from_cell(t, grid, c, 0.0, float(w.len), 3) and t.wall_remove(0) and t.walls.is_empty() and not t.wall_remove(0), "no two walls alike; a wall comes away")
	# built: closed, straight (every vertex of its mesh on one of four parallel lines), thick as it should be
	for deg in [0, 30, 60, 90, 150]:
		var tw := _wall_town([[c, deg, 3]])
		var b := _built(tw)
		_closed(b, "a straight wall at %d degrees" % deg)
		var ww: Dictionary = tw.walls[0]
		var dir := Vector2.from_angle(deg_to_rad(float(deg)))
		var half := CSBuild.WALL_THICK * 0.5
		var offs := [-half, -(half - CSBuild.PT), half - CSBuild.PT, half]
		var tower_r := float((CSWallJoints.compute(tw.walls, CSWalls.thickness(grid)).towers[0] as Dictionary).r)
		var verts := 0
		var stray := 0
		var lo := INF
		var hi := -INF
		for tri in b.mesh.verts.size() / 3:
			if int(b.mesh.cust1[tri * 12 + 3]) != CSBuild.WALL_OWNER + 1:
				continue
			for k in 3:
				var q := b.mesh.verts[tri * 3 + k]
				var r := Vector2(q.x, q.z) - p0
				var perp := r.cross(dir)
				var al := r.dot(dir)
				if al < tower_r + 0.02 or al > float(ww.len) - tower_r - 0.02:
					continue                        # (the towers on the two ends are round)
				verts += 1
				lo = minf(lo, perp)
				hi = maxf(hi, perp)
				var on := false
				for o: float in offs:
					if absf(perp - o) < 0.012:
						on = true
				# (the end parapets are across the wall: their crenel's corners are at their inner face, 0.3 m from the end)
				if not on and not ((al < CSBuild.PT + 0.012 or al > float(ww.len) - CSBuild.PT - 0.012) and absf(perp) < half + 0.012):
					stray += 1
		ok(verts > 100 and stray == 0 and absf(lo + half) < 0.012 and absf(hi - half) < 0.012, "the wall at %d degrees is straight: %d vertices on four lines, %d off them, %.3f .. %.3f across" % [deg, verts, stray, lo, hi])
	# walls that meet: the shapes a player draws, closed
	var shapes := {
		"a ring of six walls": [[c, 0, 2], [-1, 60, 2], [-1, 120, 2], [-1, 180, 2], [-1, 240, 2], [-1, 300, 2]],
		"a ring along the 30 degree lines": [[c, 30, 3], [-1, 90, 3], [-1, 150, 3], [-1, 210, 3], [-1, 270, 3], [-1, 330, 3]],
		"an L": [[c, 0, 3], [-1, 60, 2]],
		"a T": [[c, 0, 4], [c, 60, 2], [c, 300, 2]],
		"a cross": [[c, 0, 2], [c, 180, 2], [c, 90, 2], [c, 270, 2]],
		"walls end to end": [[c, 0, 1], [-1, 0, 1], [-1, 0, 1]],
		"two walls on top of each other": [[c, 0, 2], [c, 0, 4]],
	}
	for label: String in shapes:
		_closed(_built(_wall_town(shapes[label])), label)
	# next to a castle: walls and blocks together
	var tc := CSTown.new()
	CSStarter.make("castle", grid, tc)
	var cw := grid.nearest(Vector2(30.0, -10.0))
	var dd := Vector2.from_angle(deg_to_rad(120.0))
	var stops := grid.line_stops(grid.verts[cw], dd, 60.0)
	CSWalls.add_from_cell(tc, grid, cw, 120.0, stops[2], 5)
	_closed(_built(tc), "the castle with a straight wall beside it")
	# a wall is shown by the collision mesh as its own owner: a ray at it finds it
	ok(CSBuild.WALL_OWNER > grid.verts.size(), "a wall's owner id is above every grid point")


func _merging() -> void:
	# a player's castle_004: 30 straight walls, many laid side by side. It loads on the full-size cells its save names and the walls merge.
	var g1 := CSGrid.new()
	g1.generate(1, 0, CSGrid.KIND_DODECA, 1)
	var t := CSTown.new()
	for e: Array in CASTLE_004:
		t.walls.append({"v": e[0], "deg": float(e[1]), "len": float(e[2]), "c": e[3]})
	var merges := CSWalls.settle(t, g1)
	var base := CSWalls.thickness(g1)
	var thick := 0
	var thickest := 0.0
	for w: Dictionary in t.walls:
		thickest = maxf(thickest, float(w.w))
		if float(w.w) > base * 1.5:
			thick += 1
	ok(t.walls.size() <= 20 and t.walls.size() < CASTLE_004.size() - 8 and merges == CASTLE_004.size() - t.walls.size(),
		"castle_004: 30 walls merge into %d (%d merges)" % [t.walls.size(), merges])
	ok(thick >= 1 and thickest > 3.0 * base, "the merged walls are thicker than a single wall (%d of them, the thickest %.1f m against %.1f m)" % [thick, thickest, base])
	# no two walls left that are parallel and closer than the merge threshold (apart from ones whose union would be thicker than the most allowed)
	var close := 0
	for i in t.walls.size():
		for j in range(i + 1, t.walls.size()):
			var a: Dictionary = t.walls[i]
			var b: Dictionary = t.walls[j]
			var ua := CSWalls.dir_of(a)
			var ub := CSWalls.dir_of(b)
			if absf(ua.cross(ub)) > 0.01:
				continue
			var na := Vector2(-ua.y, ua.x)
			var pa := Vector2(float(a.x), float(a.z))
			var pb := Vector2(float(b.x), float(b.z))
			var lat := absf(na.dot(pb - pa)) - (float(a.w) + float(b.w)) * 0.5
			var s0 := ua.dot(pb - pa)
			var s1 := s0 + ua.dot(ub) * float(b.len)
			var ax := maxf(minf(s0, s1) - float(a.len), -maxf(s0, s1))
			if lat < CSWalls.GAP_LAT_K * base and ax < CSWalls.GAP_AX_K * base:
				close += 1
	ok(close == 0, "no two parallel walls are left closer than %.1f m (%d pairs)" % [CSWalls.GAP_LAT_K * base, close])
	# the merged castle is one closed skin, and walls that cross or meet at an angle did not merge
	_closed(_built(t), "castle_004 after the merge, built")
	var angles := {}
	for w: Dictionary in t.walls:
		angles[int(roundf(fposmod(float(w.deg), 180.0)))] = true
	ok(angles.size() >= 4, "walls at different angles stay separate walls (%d directions)" % angles.size())
	# the merge in small: two strips side by side make one wall twice as thick; one a wall's width away too; ten metres away they stay two
	var t2 := CSTown.new()
	var c := g1.nearest(Vector2.ZERO)
	var p := g1.verts[c]
	t2.wall_add(p.x, p.y, 0.0, 10.0, base, 1)
	t2.wall_add(p.x, p.y + base, 0.0, 10.0, base, 1)
	CSWalls.merge(t2, base)
	ok(t2.walls.size() == 1 and absf(float(t2.walls[0].w) - 2.0 * base) < 1e-3 and absf(float(t2.walls[0].len) - 10.0) < 1e-3, "two strips side by side make one wall twice as thick")
	t2.wall_add(p.x + 2.0, p.y + 2.0 * base + 0.5 * base, 0.0, 6.0, base, 1)
	CSWalls.merge(t2, base)
	ok(t2.walls.size() == 1 and absf(float(t2.walls[0].w) - 3.5 * base) < 0.1, "one a half thickness beyond joins too (%.2f m thick)" % float(t2.walls[0].w))
	t2.wall_add(p.x, p.y + 10.0, 0.0, 10.0, base, 1)
	t2.wall_add(p.x + 12.0, p.y, 0.0, 10.0, base, 1)
	t2.wall_add(p.x + 3.0, p.y - 3.0, 90.0, 10.0, base, 1)
	var before := t2.walls.size()
	CSWalls.merge(t2, base)
	ok(before == 4 and t2.walls.size() == 4, "walls ten metres apart, end to end far apart, or crossing stay separate (%d)" % t2.walls.size())
	# merged and built: the parapet follows the outer edge of the thicker wall
	var t3 := CSTown.new()
	t3.wall_add(p.x, p.y, 0.0, 12.0, base, 1)
	t3.wall_add(p.x + 2.0, p.y + base, 0.0, 10.0, base, 2)
	t3.wall_add(p.x + 1.0, p.y + 2.0 * base, 0.0, 8.0, base, 1)
	CSWalls.merge(t3, base)
	ok(t3.walls.size() == 1 and absf(float(t3.walls[0].w) - 3.0 * base) < 1e-3, "three strips make a wall three times as thick (%.2f m)" % float(t3.walls[0].w))
	var b3 := _built(t3)
	_closed(b3, "a wall of three merged strips")
	# it round-trips through a save: still one wall
	var back := CSTown.new()
	back.from_dict(t3.to_dict())
	CSWalls.settle(back, g1)
	ok(back.walls.size() == 1 and absf(float(back.walls[0].w) - 3.0 * base) < 1e-3, "a merged wall saves and loads as one wall")


func _joint_town(spec: Array) -> CSTown:
	## spec: [x, z, heading, length]: walls of a single width at exact places (no merging).
	var t := CSTown.new()
	var base := CSWalls.thickness(grid)
	for w: Array in spec:
		t.wall_add(float(w[0]), float(w[1]), float(w[2]), float(w[3]), base, 3)
	return t


func _corners() -> void:
	var base := CSWalls.thickness(grid)
	var len := 9.0
	var p := Vector2(3.0, -4.0)
	# a lone wall: a tower at each end, none of the walls' squared ends left bare; towers stand above the wall and are round (16 sides)
	var lone := _joint_town([[p.x, p.y, 0.0, len]])
	var j := CSWallJoints.compute(lone.walls, base)
	ok(j.towers.size() == 2 and j.fills.is_empty(), "a lone wall has a tower on each end (%d towers, %d fills)" % [j.towers.size(), j.fills.size()])
	var cover := true
	for tw: Dictionary in j.towers:
		var poly: PackedVector2Array = tw.pts
		for corner: Vector2 in CSBuild.wall_poly(grid, lone.walls[0]):
			if corner.distance_to(tw.c) < 2.0 and not Geometry2D.is_point_in_polygon(corner, poly):
				cover = false
	ok(cover and (j.towers[0].pts as PackedVector2Array).size() == CSBuild.ROUND_SIDES and CSBuild.TOWER_RISE > 0.5, "a tower covers the whole squared end of its wall: round, 16 sides, %.1f m above the wall" % CSBuild.TOWER_RISE)
	var bl := _built(lone)
	_closed(bl, "a lone wall with its two end towers")
	var tower_layers := 0
	for e: Dictionary in bl.extras:
		if float(e.y1) > CSBuild.level_y_static(1) + CSBuild.TOWER_RISE:
			tower_layers += 1
	ok(tower_layers == 2, "the two towers are built higher than the wall (%d)" % tower_layers)
	# bends of 30, 60, 90, 120 and 150 degrees: one tower on the bend, one on each far end; sharp bends (under 75 degrees) get the wedge filled
	for a in [30, 60, 90, 120, 150, 210, 270, 330]:
		var bend := _joint_town([[p.x, p.y, 0.0, len], [p.x, p.y, float(a), len]])
		var jb := CSWallJoints.compute(bend.walls, base)
		var want_fill := minf(float(a), 360.0 - float(a)) < CSWallJoints.ANGLE_MAX
		ok(jb.towers.size() == 3 and (jb.fills.size() == 1) == want_fill and jb.fills.size() <= 1, "a bend of %d degrees: 3 towers (the bend's one is shared), %d fill" % [a, jb.fills.size()])
		for f: Dictionary in jb.fills:
			ok(CFTri.area(f.poly) > 0.1 and CSBuild.convex(f.poly), "the wedge fill of the %d degree bend is a proper triangle (%.2f m2)" % [a, CFTri.area(f.poly)])
		_closed(_built(bend), "a bend of %d degrees" % a)
	# a T: the stem's end is buried in the through wall (no tower there); a cross has four free ends; an X at 40 degrees
	var tee := _joint_town([[p.x - len * 0.5, p.y, 0.0, len], [p.x, p.y, 90.0, len * 0.5]])
	var jt := CSWallJoints.compute(tee.walls, base)
	ok(jt.towers.size() == 3, "a T has three towers: the stem's end is buried in the other wall (%d)" % jt.towers.size())
	_closed(_built(tee), "a T of walls")
	var cross := _joint_town([[p.x - len * 0.5, p.y, 0.0, len], [p.x, p.y - len * 0.5, 90.0, len]])
	ok(CSWallJoints.compute(cross.walls, base).towers.size() == 4, "a cross has four towers")
	_closed(_built(cross), "a cross of walls")
	# a ring of three: one tower on each corner, nothing sharp left
	var ring := _joint_town([[0.0, 0.0, 0.0, 11.0], [11.0, 0.0, 120.0, 11.0], [11.0 - 5.5, 11.0 * sin(PI / 3.0), 240.0, 11.0]])
	ok(CSWallJoints.compute(ring.walls, base).towers.size() == 3, "a ring of three walls has a tower on each corner")
	_closed(_built(ring), "a ring of three walls")
	# a merged thick wall gets a flat cap instead of a tower
	var thick := CSTown.new()
	thick.wall_add(0.0, 0.0, 0.0, 10.0, base * 4.0, 1)
	ok(CSWallJoints.compute(thick.walls, base).towers.is_empty(), "a wall four times as thick as a single one ends in a flat cap, not a round tower")
	_closed(_built(thick), "a thick wall")
	# two ends close together become one tower
	var near := _joint_town([[0.0, 0.0, 0.0, 9.0], [0.0, 1.4 * base, 0.0, 9.0]])
	ok(CSWallJoints.compute(near.walls, base).towers.size() <= 2, "walls ending side by side share their towers (%d)" % CSWallJoints.compute(near.walls, base).towers.size())
	_closed(_built(near), "two walls side by side, apart")


func _directions() -> void:
	# the snapping: every heading goes to the nearest of 12, 16 or 24 directions
	for n in CSGrid.DIR_COUNTS:
		var step := 360.0 / float(n)
		var worst := 0.0
		var off := 0
		for k in 360:
			var d := Vector2.from_angle(deg_to_rad(float(k) + 0.3))
			var sn := CSGrid.snap_direction(d, n)
			var ang := rad_to_deg(sn.angle())
			var q := ang / step
			if absf(q - roundf(q)) > 1e-3:
				off += 1
			worst = maxf(worst, absf(rad_to_deg(d.angle_to(sn))))
		ok(off == 0 and worst <= step * 0.5 + 1e-3, "%d directions: every heading snaps to a multiple of %s degrees (at most %.1f degrees off, %d wrong)" % [n, ("%d" % roundi(step) if absf(step - roundf(step)) < 0.01 else "%.1f" % step), worst, off])
	ok(CSGrid.on_lattice(Vector2.from_angle(deg_to_rad(150.0))) and not CSGrid.on_lattice(Vector2.from_angle(deg_to_rad(22.5))) and not CSGrid.on_lattice(Vector2.from_angle(deg_to_rad(15.0))) and CSGrid.on_lattice(Vector2.from_angle(deg_to_rad(90.0))),
		"the grid's own lines are the multiples of 30 degrees; 22.5 and 15 are not among them")
	# where a wall may end: along a grid line at the middle of a cell, along any other direction every half cell spacing
	var c := grid.nearest(Vector2.ZERO)
	var st12 := grid.wall_stops(grid.verts[c], Vector2.from_angle(deg_to_rad(30.0)), 40.0)
	var st16 := grid.wall_stops(grid.verts[c], Vector2.from_angle(deg_to_rad(22.5)), 40.0)
	ok(st12 == grid.line_stops(grid.verts[c], Vector2.from_angle(deg_to_rad(30.0)), 40.0) and st16.size() > 5 and absf(st16[1] - 2.0 * st16[0]) < 1e-3 and absf(st16[0] - grid.spacing * 0.5) < 1e-3,
		"stops: on a grid line where a cell's middle lies on it, off the lines every %.2f m" % st16[0])
	# a town remembers its direction count; the default is 12
	var t := CSTown.new()
	ok(t.wall_dirs == 12, "12 directions by default")
	for n in CSGrid.DIR_COUNTS:
		t.wall_dirs = n
		var back := CSTown.new()
		back.from_dict(t.to_dict())
		ok(back.wall_dirs == n, "a castle saved with %d directions loads with them" % n)
	var old := CSTown.new()
	old.from_dict({"grid": "dodeca-2", "blocks": [], "walls": [], "wall_dirs": 7})
	ok(old.wall_dirs == 12, "an unknown direction count loads as 12")
	# walls in each direction count: laid from a cell, merged, built, closed; a wall at 22.5 and one at 15 degrees
	var base := CSWalls.thickness(grid)
	for n in CSGrid.DIR_COUNTS:
		var step := 360.0 / float(n)
		var tw := CSTown.new()
		var made := 0
		for k in n:
			var deg := step * float(k)
			var dir := Vector2.from_angle(deg_to_rad(deg))
			var p := grid.verts[grid.nearest(dir.rotated(0.4) * 30.0)]
			var stops := grid.wall_stops(p, dir, 30.0)
			if stops.size() >= 3 and tw.wall_add(p.x, p.y, deg, stops[2], base, k % 12):
				made += 1
		CSWalls.merge(tw, base)
		var tb := _built(tw)
		_closed(tb, "%d walls, one in each of the %d directions (%d left after merging)" % [made, n, tw.walls.size()])
		# straight: the sides of a wall at 22.5 degrees are two lines (the vertices of its body lie on four straight lines)
	var w16 := CSTown.new()
	var q := grid.verts[grid.nearest(Vector2(5.0, 5.0))]
	w16.wall_add(q.x, q.y, 22.5, 14.0, base, 1)
	var poly := CSBuild.wall_poly(grid, w16.walls[0])
	var ux := Vector2.from_angle(deg_to_rad(22.5))
	ok(absf((poly[1] - poly[0]).angle() - deg_to_rad(22.5)) < 1e-5 and absf((poly[2] - poly[3]).angle() - deg_to_rad(22.5)) < 1e-5 and absf(poly[0].distance_to(poly[3]) - base) < 1e-4 and absf(ux.dot(poly[3] - poly[0])) < 1e-4, "a wall at 22.5 degrees is a straight rectangle")
	_closed(_built(w16), "a wall at 22.5 degrees")
	# a wall at 22.5 degrees through a castle (blocks and a wall together)
	var tc := CSTown.new()
	CSStarter.make("castle", grid, tc)
	tc.wall_add(-30.0, -35.0, 22.5, 30.0, base, 2)
	tc.wall_add(32.0, -30.0, 105.0, 24.0, base, 2)
	_closed(_built(tc), "the castle with walls at 22.5 and 105 degrees beside it (a wall through a castle at a heading off the grid's lines can meet a block's battlements within millimetres: see the probe's list)")


func _cell_sizes() -> void:
	# the cells at 1/2 and 1/3 of the area: the same island, more and smaller cells, every cell regular, the same rules
	var counts := {}
	for d in [1, 2, 3, 4]:
		var g := CSGrid.new()
		g.generate(1, 0, CSGrid.KIND_DODECA, d)
		var n := 0
		var bad := 0
		for v in g.verts.size():
			if g.is_dodecagon(v) and g.buildable(v):
				n += 1
				var poly := g.dual(v)
				if poly.size() != 12 or absf(CFTri.area(poly) - CSGrid.BASE_AREA / float(d)) > 0.02 or not CSBuild.convex(poly):
					bad += 1
		counts[d] = n
		ok(bad == 0 and g.div == d and absf(g.cell - 1.0 / sqrt(float(d))) < 1e-9, "12-sided cells at 1/%d of the area: %d cells of %.1f m2, %d wrong" % [d, n, CSGrid.BASE_AREA / float(d), bad])
		ok(CSGrid.div_of(CSGrid.id_of(CSGrid.KIND_DODECA, d)) == d and CSGrid.kind_of(CSGrid.id_of(CSGrid.KIND_DODECA, d)) == CSGrid.KIND_DODECA, "the tag of a town on 1/%d cells says so (%s)" % [d, CSGrid.id_of(CSGrid.KIND_DODECA, d)])
	ok(counts[2] > 1.7 * counts[1] and counts[3] > 2.5 * counts[1], "an island of the same size has twice and three times the cells (%d, %d, %d)" % [counts[1], counts[2], counts[3]])
	ok(CSGrid.variants()[0][1] == CSGrid.DEFAULT_DIV and CSTown.new().grid_div == CSGrid.DEFAULT_DIV and CSGrid.DEFAULT_DIV > 1, "a new town starts on the smaller cells")
	# a saved town remembers the cell size
	var st := CSTown.new()
	st.grid_div = 3
	var back := CSTown.new()
	back.from_dict(st.to_dict())
	ok(back.grid_div == 3 and back.grid_kind == CSGrid.KIND_DODECA, "a town saves its cell size")
	# the same rules on them: the castle starter and random castles are closed on 1/2 and 1/3 cells, 12-sided and hexagons
	for kd: Array in [[CSGrid.KIND_DODECA, 2], [CSGrid.KIND_DODECA, 3], [CSGrid.KIND_HEX, 2]]:
		var g := CSGrid.new()
		g.generate(1, 0, kd[0], kd[1])
		var t := CSTown.new()
		t.grid_kind = kd[0]
		t.grid_div = kd[1]
		CSStarter.make("castle", g, t)
		var b := CSBuild.new()
		b.build(g, t)
		_closed(b, "the castle starter on %s (%d blocks)" % [CSGrid.variant_name(kd[0], kd[1]), t.size()])
		var worst := 0
		for sd in 4:
			var tr := CSTown.new()
			CSStarter.random_growth(g, tr, sd, 40, -1 if sd % 2 == 1 else 0)
			var br := CSBuild.new()
			br.build(g, tr)
			var au := CFAudit.check(br.mesh, SKIP)
			worst = maxi(worst, int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions))
		ok(worst == 0, "four random castles on %s are closed (worst defects %d)" % [CSGrid.variant_name(kd[0], kd[1]), worst])
		var tw := CSTown.new()
		var c := g.nearest(Vector2.ZERO)
		var stops := g.line_stops(g.verts[c], Vector2.from_angle(deg_to_rad(30.0)), 40.0)
		CSWalls.add_from_cell(tw, g, c, 30.0, stops[2], 1)
		CSWalls.add_from_cell(tw, g, c, 90.0, stops[1], 1)
		var bw := CSBuild.new()
		bw.build(g, tw)
		_closed(bw, "two straight walls on %s (a wall %.2f m thick)" % [CSGrid.variant_name(kd[0], kd[1]), CSWalls.thickness(g)])


func _hex_grid() -> void:
	## The plain regular hexagon grid, also available: 1141 hexagons of 21.65 m2, six neighbours each, the same rules on it.
	var hg := CSGrid.new()
	hg.generate(1, CSGrid.RINGS, CSGrid.KIND_HEX)
	var cells := 0
	var bad := 0
	for v in hg.verts.size():
		if not hg.buildable(v):
			continue
		cells += 1
		var d := hg.dual(v)
		if d.size() != 6 or absf(CFTri.area(d) - 12.5 * sqrt(3.0)) > 0.01 or (hg.nbrs[v] as PackedInt32Array).size() != 6 or not CSBuild.convex(d):
			bad += 1
		for i in 6:
			if absf(d[i].distance_to(d[(i + 1) % 6]) - hg.side) > 1e-3:
				bad += 1
	ok(cells == 1141 and bad == 0 and hg.kind == CSGrid.KIND_HEX and CSGrid.kind_of(CSGrid.id_of(hg.kind)) == CSGrid.KIND_HEX, "the hexagon grid has %d regular hexagons of 21.65 m2, side %.3f m (%d wrong)" % [cells, hg.side, bad])
	ok(CSGrid.kind_of(CSGrid.GRID_ID) == CSGrid.KIND_DODECA and CSGrid.kind_of("quad-1") == "", "a saved town names its grid: dodecagons, hexagons, or another grid that loads as an empty sea")
	var saved := CSTown.new()
	saved.grid_kind = CSGrid.KIND_HEX
	var hv := hg.nearest(Vector2.ZERO)
	saved.add(hv, 0, 2)
	var back := CSTown.new()
	back.from_dict(saved.to_dict())
	var other := CSTown.new()
	other.from_dict({"grid": "dodeca-1", "blocks": [[5, 0, 3]]})
	ok(back.grid_kind == CSGrid.KIND_HEX and back.has(hv, 0) and other.size() == 0, "a town remembers its cells; one saved on another grid opens as an empty sea")
	# the same rules on it: the castle starter, random castles, a wall: closed
	var tc := CSTown.new()
	tc.grid_kind = CSGrid.KIND_HEX
	CSStarter.make("castle", hg, tc)
	var bc := CSBuild.new()
	bc.build(hg, tc)
	_closed(bc, "the castle starter on hexagons (%d blocks)" % tc.size())
	var worst := 0
	for sd in 6:
		var tr := CSTown.new()
		CSStarter.random_growth(hg, tr, sd, 50, -1 if sd % 2 == 1 else 0)
		var br := CSBuild.new()
		br.build(hg, tr)
		var au := CFAudit.check(br.mesh, SKIP)
		worst = maxi(worst, int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions))
	ok(worst == 0, "six random castles on hexagons are closed (worst defects %d)" % worst)
	var tw := CSTown.new()
	var hc := hg.nearest(Vector2.ZERO)
	var stops := hg.line_stops(hg.verts[hc], Vector2.from_angle(deg_to_rad(30.0)), 60.0)
	CSWalls.add_from_cell(tw, hg, hc, 30.0, stops[2], 1)
	var bw := CSBuild.new()
	bw.build(hg, tw)
	_closed(bw, "a straight wall on hexagons (stops every %.2f m)" % (stops[1] - stops[0]))


func _audit(t: CSTown, label: String, strict: bool) -> Dictionary:
	var b := _built(t)
	var au := CFAudit.check(b.mesh, SKIP)
	var nan := false
	for p in b.mesh.verts:
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			nan = true
			break
	ok(not nan and (b.mesh.tri_count() > 0 or label == "landscape"), "%s: a finite mesh (%d tris)" % [label, b.mesh.tri_count()])
	if strict:
		ok(int(au.open_other) == 0 and int(au.non_manifold) == 0 and int(au.flipped) == 0 and int(au.t_junctions) == 0,
			"%s: closed (open %d, non-manifold %d, flipped %d, T %d)" % [label, int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
	var stair_door := 0
	for s: Dictionary in b.stairs:
		if int(s.k) < 0 and int(b.doors.get(int(s.up), -1)) == int(s.up_face):
			stair_door += 1
	ok(stair_door == 0, "%s: no stairs in front of a door (%d)" % [label, stair_door])
	var pc: Dictionary = b.stats.get("pieces", {}).duplicate()
	pc["stairs"] = b.stairs.size()
	return {"au": au, "ms": float(b.stats.ms), "pieces": pc}


func _audits() -> void:
	for n in CSStarter.NAMES:
		var t := CSTown.new()
		CSStarter.make(n, grid, t)
		var r := _audit(t, n, true)
		print("   %s: %d blocks, %.0f ms" % [n, t.size(), r.ms])
	var worst_open := 0
	var worst_nm := 0
	var worst_ms := 0.0
	var defective := 0
	var seen := {}
	for s in 16:
		var t := CSTown.new()
		CSStarter.random_growth(grid, t, s, 70)
		var r := _audit(t, "random %d" % s, false)
		for kind in r.pieces:
			seen[kind] = int(seen.get(kind, 0)) + int(r.pieces[kind])
		var au: Dictionary = r.au
		worst_open = maxi(worst_open, int(au.open_other))
		worst_nm = maxi(worst_nm, int(au.non_manifold))
		worst_ms = maxf(worst_ms, float(r.ms))
		if int(au.open_other) + int(au.non_manifold) + int(au.t_junctions) > 0:
			defective += 1
	print("   (random castles: %d of 16 with defects, worst open %d, worst non-manifold %d, slowest %.0f ms; pieces %s)" % [defective, worst_open,
		worst_nm, worst_ms, str(seen)])
	ok(worst_open <= 20 and worst_nm <= 6, "random click-built castles stay (nearly) closed (open %d, non-manifold %d)" % [worst_open, worst_nm])
	ok(worst_ms < 3000.0, "a 70-block castle builds in %.0f ms" % worst_ms)
	ok(int(seen.get("arch", 0)) > 0 and int(seen.get("corbel", 0)) > 0 and int(seen.get("stairs", 0)) > 0,
		"click-built castles grow arches, corbels and stairs (%s)" % str(seen))


func _styles() -> void:
	## The six building styles: starters, click-built towns of one style (closed), mixed towns (as closed as the castles), the hats, facades, tiers, doors and props.
	var seen := {}                  # style -> {hat kind: count}
	var tiers := 0
	for n in ["houses", "apartments", "chinese", "japanese", "fantasy", "hamlet", "styles"]:
		var t := CSTown.new()
		CSStarter.make(n, grid, t)
		var b := _built(t)
		var tops := 0
		var doors_ok := true
		for kk: int in b.kinds:
			tops += 1
		ok(b.hats.size() >= 10, "%s: the tops have hats (%d hats, %d tops)" % [n, b.hats.size(), tops])
		ok(b.facades >= 20, "%s: the walls are laid out in facades (%d)" % [n, b.facades])
		var styled_ground := 0
		var with_door := 0
		for v: int in t.columns():
			if t.has(v, 0) and t.style(v, 0) != CSStyle.CASTLE:
				var has_open := false
				var nb: PackedInt32Array = grid.nbrs[v]
				var ol := b.level_outline(v, 0)
				for i in nb.size():
					if not b.filled(nb[i], 0) and ol[(i + nb.size() - 1) % nb.size()].distance_to(ol[i]) >= 2.6:
						has_open = true
				if has_open:
					styled_ground += 1
					if b.doors.has(v):
						with_door += 1
		doors_ok = with_door == styled_ground
		ok(doors_ok, "%s: every house, pagoda or tower on the ground with an open side has its door (%d of %d)" % [n, with_door, styled_ground])
		for kk: int in b.hats:
			var h: Dictionary = b.hats[kk]
			if not seen.has(h.style):
				seen[h.style] = {}
			seen[h.style][h.kind] = int(seen[h.style].get(h.kind, 0)) + 1
			if h.kind == "tier":
				tiers += 1
		var pr := CSProps.new()
		pr.build(b)
		_props_clean(b, pr, n)
	for s in range(1, CSStyle.COUNT):
		var kinds: Dictionary = seen.get(s, {})
		ok(kinds.size() >= 2, "%s: the starters grow at least two kinds of roof (%s)" % [CSStyle.KEYS[s], str(kinds)])
	ok(tiers > 0, "free-standing towers of the styles step in as they rise (%d tier roofs)" % tiers)
	# one style at a time: click-built towns stay closed
	var worst := 0
	for s in range(1, CSStyle.COUNT):
		for seed in 3:
			var t := CSTown.new()
			CSStarter.random_growth(grid, t, seed, 60, s)
			var b := _built(t)
			var au := CFAudit.check(b.mesh, SKIP)
			var bad := int(au.open_other) + int(au.non_manifold) + int(au.flipped) + int(au.t_junctions)
			worst = maxi(worst, bad)
			ok(bad == 0, "%s town %d: closed (open %d, non-manifold %d, flipped %d, T %d)" % [CSStyle.KEYS[s], seed, int(au.open_other), int(au.non_manifold), int(au.flipped), int(au.t_junctions)])
	# mixed towns: castle blocks and every style together
	var open_w := 0
	var nm_w := 0
	var defective := 0
	var kinds_all := {}
	for seed in 16:
		var t := CSTown.new()
		CSStarter.random_growth(grid, t, seed, 70, -1)
		var b := _built(t)
		var au := CFAudit.check(b.mesh, SKIP)
		open_w = maxi(open_w, int(au.open_other))
		nm_w = maxi(nm_w, int(au.non_manifold))
		if int(au.open_other) + int(au.non_manifold) + int(au.t_junctions) > 0:
			defective += 1
		for kk: int in b.kinds:
			kinds_all[b.kinds[kk]] = int(kinds_all.get(b.kinds[kk], 0)) + 1
		var nan := false
		for p in b.mesh.verts:
			if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
				nan = true
				break
		ok(not nan, "mixed town %d: a finite mesh" % seed)
	print("   (mixed towns: %d of 16 with defects, worst open %d, worst non-manifold %d; tops %s)" % [defective, open_w, nm_w, str(kinds_all)])
	ok(open_w <= 20 and nm_w <= 6, "mixed towns stay (nearly) closed (open %d, non-manifold %d)" % [open_w, nm_w])
	ok(kinds_all.size() >= 12, "mixed towns grow many kinds of top (%d kinds)" % kinds_all.size())
	# the same blocks give the same hats and the same props
	var t2 := CSTown.new()
	CSStarter.make("styles", grid, t2)
	var ba := _built(t2)
	var bb := _built(t2)
	var same := ba.hats.size() == bb.hats.size()
	for kk: int in ba.hats:
		same = same and bb.hats.has(kk) and str(bb.hats[kk].kind) == str(ba.hats[kk].kind) and absf(float(bb.hats[kk].top) - float(ba.hats[kk].top)) < 1e-6
	ok(same, "the same blocks give the same hats every time")
	var pa := CSProps.new()
	pa.build(ba)
	var pb := CSProps.new()
	pb.build(bb)
	ok(pa.buffers() == pb.buffers() and pa.kept.size() > 0, "the styles' props are the same every time (%d kept)" % pa.kept.size())


func _birds() -> void:
	var t := CSTown.new()
	CSStarter.make("castle", grid, t)
	var b := _built(t)
	var land := CFBirds.landings_from(b.mesh)
	var n := (land.pos as PackedVector3Array).size()
	ok(n > 40, "the castle has perches for birds (%d)" % n)
	var fl := CFBirds.new()
	fl.set_landings(land)
	for _i in 200:
		fl.step(0.05)
	ok(fl.perched_count() > 0, "birds settle on it (%d)" % fl.perched_count())
	fl.free()


func _in_solid(b: CSBuild, p: Vector3) -> bool:
	## Whether a point lies inside a block or an arch (its outline at that level), a corbel, a pillar, a flight of stairs
	## or the land.
	var q := Vector2(p.x, p.z)
	for ex: Dictionary in b.extras:
		if p.y > float(ex.y0) and p.y < float(ex.y1) and Geometry2D.is_point_in_polygon(q, ex.poly):
			return true
	var v0 := grid.nearest(q)
	if v0 < 0:
		return false
	var cells := {v0: true}
	for qd in grid.rings[v0]:
		if qd >= 0:
			for kk in 3:
				cells[grid.tris[qd * 3 + kk]] = true
	var k := floori((p.y - CSBuild.B) / CSBuild.H)
	for u: int in cells:
		if not grid.buildable(u):
			continue
		if k >= 0 and b.filled(u, k):
			var poly := b.round_poly(u) if b.is_round(u, k) else b.level_outline(u, k)
			if Geometry2D.is_point_in_polygon(q, poly):
				return true
		if p.y < CSBuild.B and b.land.has(u) and Geometry2D.is_point_in_polygon(q, grid.dual(u)):
			return true
	return false


func _country(name: String) -> Array:
	var t := CSTown.new()
	CSStarter.make(name, grid, t)
	var b := CSBuild.new()
	b.build(grid, t)
	var w := CSWorld.new()
	w.build(grid, t, b.land)
	var rd := CSRoads.new()
	rd.build(w)
	var sc := CSScatter.new()
	sc.build(w)
	return [t, b, w, rd, sc]


func _free_column(t: CSTown, land := true) -> int:
	for v in grid.verts.size():
		if grid.buildable(v) and t.top(v) < 0 and not t.has_wild(v):
			return v
	return -1


func _landscape() -> void:
	# the column rules
	var t := CSTown.new()
	var v := grid.nearest(Vector2(60.0, 0.0))
	ok(t.wild_add(v, CSTown.T_LAND) and not t.wild_add(v, CSTown.T_LAND), "land goes down once")
	ok(t.wild_add(v, CSTown.T_TREE) and t.wild_add(v, CSTown.T_TREE) and t.wild_add(v, CSTown.T_TREE) and not t.wild_add(v, CSTown.T_TREE), "trees: a tree, a grove, a forest, no more")
	ok(not t.wild_add(v, CSTown.T_ROAD), "a road does not go through trees")
	var u: int = grid.nbrs[v][0]
	ok(t.wild_add(u, CSTown.T_LAND) and t.wild_add(u, CSTown.T_ROAD) and not t.wild_add(u, CSTown.T_TREE), "trees do not grow in a road")
	var w2: int = grid.nbrs[v][1]
	for i in CSTown.MAX_HEIGHT:
		t.wild_add(w2, CSTown.T_MOUNTAIN if i % 2 == 0 else CSTown.T_ROCK)
	ok(t.wild_heights(w2) == "mrmrmr" and not t.wild_add(w2, CSTown.T_ROCK), "mountain and rock levels stack in the order built, up to %d" % CSTown.MAX_HEIGHT)
	var d := t.to_dict()
	var t2 := CSTown.new()
	t2.from_dict(d)
	ok(t2.wild_heights(w2) == "mrmrmr" and t2.wild_trees(v) == 3 and t2.wild_road(u), "the landscape survives a save round trip")
	ok(t.wild_remove(v) and t.wild_trees(v) == 2, "a right-click takes the top tree level first")
	t.wild_remove(v)
	t.wild_remove(v)
	t.wild_remove(v)
	ok(not t.has_wild(v), "then the land, then the column is gone")
	# a castle block pushes the landscape out of its column
	var a := CSTown.new()
	var c := grid.nearest(Vector2.ZERO)
	a.wild_add(c, CSTown.T_LAND)
	ok(a.top(c) < 0 and a.has_wild(c), "land stands where no block does")
	# the whole country
	var k := _country("kingdom")
	var kt: CSTown = k[0]
	var kb: CSBuild = k[1]
	var kw: CSWorld = k[2]
	var kr: CSRoads = k[3]
	var ks: CSScatter = k[4]
	ok(kw.ground.size() > 80, "the kingdom has ground (%d columns)" % kw.ground.size())
	var peak := 0.0
	var bad := 0
	for u2: int in kw.corner:
		var h: float = kw.corner[u2]
		if not is_finite(h) or h < -0.01 or h > 40.0:
			bad += 1
	for u3: int in kw.ground:
		peak = maxf(peak, kw.altitude(u3))
	ok(bad == 0, "every terrain corner is a sane height")
	ok(peak > 8.0, "the mountains rise above the tree line (%.1f m)" % peak)
	ok(kw.stats.tris > 500, "the terrain is a mesh (%d triangles)" % kw.stats.tris)
	# flush with the castle: a corner that touches castle land is at its floor height
	var flush := true
	for u4: int in kw.ground:
		for q in grid.rings[u4]:
			if q < 0:
				continue
			for i in 3:
				var cc := grid.tris[q * 3 + i]
				if kb.land.has(cc) and kw.corner.has(q) and absf(float(kw.corner[q])) > 0.001:
					flush = false
	ok(flush, "land is flat where it meets the castle")
	ok(absf(kw.height_at(Vector2(1000.0, 1000.0)) - CSWorld.G) < 1e-5, "height_at is the ground height away from the landscape")
	var sample := kw.ground.keys()[0] as int
	var hp := kw.height_at(grid.verts[sample])
	ok(is_finite(hp) and hp >= CSWorld.G - 0.5, "height_at answers on a ground column (%.2f)" % hp)
	# what grows where depends on what is round it
	var kinds := {}
	for u5: int in ks.species:
		kinds[ks.species[u5]] = int(kinds.get(ks.species[u5], 0)) + 1
	ok(kinds.has("pine") and kinds.has("oak") or kinds.has("forest"), "the kingdom grows more than one kind of tree (%s)" % str(kinds))
	var pine_low := 0
	var oak_high := 0
	for u6: int in ks.species:
		if ks.species[u6] == "pine" and kw.altitude(u6) < 1.0 and kw.ctx(u6).mount == 0 and kw.ctx(u6).rock == 0:
			pine_low += 1
		if ks.species[u6] == "oak" and kw.altitude(u6) > 4.5:
			oak_high += 1
	ok(oak_high == 0, "no oak on high ground")
	var above := 0
	for it: Array in ks.inst:
		var tf: Transform3D = it[1]
		if int(it[0]) <= CSScatter.M_ORCHARD and tf.origin.y - CSWorld.G > CSScatter.TREE_LINE + 0.8:
			above += 1
	ok(above == 0, "no tree stands above the tree line (%d)" % above)
	var clash := 0
	for it: Array in ks.inst:
		var tf2: Transform3D = it[1]
		if int(it[0]) <= CSScatter.M_ORCHARD and not kw.road_clear(Vector2(tf2.origin.x, tf2.origin.z), 1.0):
			clash += 1
	ok(clash == 0, "no tree stands in a road (%d)" % clash)
	ok(int(ks.counts.get("boulder", 0)) + int(ks.counts.get("crag", 0)) + int(ks.counts.get("block", 0)) > 5, "rocks lie on the rock columns and mountain slopes (%s)" % str(ks.counts))
	# roads: one piece per neighbour pattern
	var rt := CSTown.new()
	var rc := grid.nearest(Vector2(60.0, 0.0))
	var arms := [rc] + Array(grid.nbrs[rc])
	for x: int in arms:
		rt.wild_add(x, CSTown.T_LAND)
	for x: int in arms.slice(0, 4):
		rt.wild_add(x, CSTown.T_ROAD)
	var rb := CSBuild.new()
	rb.build(grid, rt)
	var rw := CSWorld.new()
	rw.build(grid, rt, rb.land)
	var rr := CSRoads.new()
	rr.build(rw)
	var classes := {}
	for x2: int in rr.info:
		classes[(rr.info[x2] as Dictionary).cls] = true
	ok(classes.has("junction") or classes.has("through") or classes.has("dead"), "roads classify by their neighbours (%s)" % str(classes.keys()))
	ok(not rr.info.is_empty() and rw.road_segs.size() > 0, "a road lays its ribbon and marks where it runs")
	# a road over water is a jetty, then a bridge
	var wt := CSTown.new()
	var wc := grid.nearest(Vector2(60.0, 0.0))
	wt.wild_add(wc, CSTown.T_LAND)
	var over := int(grid.nbrs[wc][0])
	var over2 := int(grid.nbrs[over][0])
	wt.wild_add(over, CSTown.T_ROAD)
	var wb := CSBuild.new()
	wb.build(grid, wt)
	var ww := CSWorld.new()
	ww.build(grid, wt, wb.land)
	var wr := CSRoads.new()
	wr.build(ww)
	ok(ww.deck.has(over) and str((wr.info[over] as Dictionary).cls) in ["jetty", "bridge"], "a road with no earth under it is a jetty or a bridge")
	# determinism
	var k2 := _country("kingdom")
	ok((k2[4] as CSScatter).inst.size() == ks.inst.size() and (k2[3] as CSRoads).counts == kr.counts, "the same castle and country give the same trees, rocks and roads")
	# a landscape build is quick
	var t0 := Time.get_ticks_msec()
	_country("kingdom")
	var ms := Time.get_ticks_msec() - t0
	ok(ms < 3500, "castle and country built in %d ms" % ms)


func _look() -> void:
	## every light and quality row is complete, the ids line up, and the numbers are sane
	var keys: Array = (CSLook.LOOKS["golden"] as Dictionary).keys()
	for id: String in CSLook.LOOK_IDS:
		ok(CSLook.LOOKS.has(id) and CSLook.LOOK_NAMES.has(id), "light %s has a name and a row" % id)
		var row: Dictionary = CSLook.LOOKS[id]
		var missing := []
		for k: String in keys:
			if not row.has(k):
				missing.append(k)
		ok(missing.is_empty(), "light %s has every key of golden hour (missing %s)" % [id, str(missing)])
		ok(float(row.sun_elev) > 2.0 and float(row.sun_elev) < 85.0 and float(row.sun_energy) > 0.0, "light %s: the sun is above the horizon" % id)
		ok(float(row.exposure) > 0.3 and float(row.exposure) < 2.5, "light %s: exposure in range" % id)
	var qkeys: Array = (CSLook.QUALITY["high"] as Dictionary).keys()
	for id: String in CSLook.QUALITY_IDS:
		ok(CSLook.QUALITY.has(id) and CSLook.QUALITY_NAMES.has(id), "quality %s has a name and a row" % id)
		var row: Dictionary = CSLook.QUALITY[id]
		var missing := []
		for k: String in qkeys:
			if not row.has(k):
				missing.append(k)
		ok(missing.is_empty(), "quality %s has every key (missing %s)" % [id, str(missing)])
		ok(CSLook.SHADOW_LEVELS.has(int(row.shadows)), "quality %s: a known shadow level" % id)
		ok(float(row.scale) >= 0.5 and float(row.scale) <= 1.0, "quality %s: render scale in range" % id)


func _rocks() -> void:
	var t := CSTown.new()
	CSStarter.make("castle", grid, t)
	var b := CSBuild.new()
	b.build(grid, t)
	var loops := CSRocks.shore_loops(grid, b.land)
	ok(loops.size() >= 1, "the castle's land has a shore loop (%d)" % loops.size())
	var closed := true
	for l: Dictionary in loops:
		if (l.pts as PackedVector2Array).size() < 3:
			closed = false
	ok(closed, "every shore loop has at least three points")
	var t0 := Time.get_ticks_msec()
	var m := CSRocks.skirt_mesh(loops)
	var ms := Time.get_ticks_msec() - t0
	ok(m.get_surface_count() == 1, "the rock skirt is one surface")
	var bb := m.get_aabb()
	ok(bb.size.x > 20.0 and bb.size.z > 20.0, "the skirt runs round the island (%s)" % str(bb.size))
	ok(bb.position.y > -6.0 and bb.end.y < 5.0, "the skirt stays between -6 and 5 m (%.1f .. %.1f)" % [bb.position.y, bb.end.y])
	ok(ms < 800, "the skirt is made in %d ms" % ms)
	var arr := m.surface_get_arrays(0)
	var nan := 0
	for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			nan += 1
	ok(nan == 0, "no vertex of the skirt is not-a-number (%d)" % nan)
	var sea := CSRocks.seabed_mesh()
	ok(sea.get_surface_count() == 1 and sea.get_aabb().size.x > 1500.0, "the sea floor is one wide disc")
	ok(sea.get_aabb().end.y < -0.8, "the sea floor stays under the water (%.1f)" % sea.get_aabb().end.y)


func _props_clean(b: CSBuild, pr: CSProps, label: String) -> void:
	## Every pair of kept props (and every prop against the doors, slits and windows) apart; 27 points through each
	## prop's boxes, none inside a block or the land.
	var boxes := []
	for ci in pr.kept.size():
		for bx in pr.kept[ci].boxes:
			boxes.append([bx, ci])
	for bx in pr.fixed:
		boxes.append([bx, -1])
	var clash := 0
	var first := ""
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if int(boxes[i][1]) == int(boxes[j][1]):
				continue
			if CSProps.overlap(boxes[i][0], boxes[j][0]):
				clash += 1
				if first == "":
					var ki: String = "opening" if int(boxes[i][1]) < 0 else CSProps.KINDS[pr.kept[int(boxes[i][1])].kind]
					var kj: String = "opening" if int(boxes[j][1]) < 0 else CSProps.KINDS[pr.kept[int(boxes[j][1])].kind]
					first = " (first: %s / %s at %s)" % [ki, kj, str(boxes[i][0].c)]
	ok(clash == 0, "%s: no two props overlap (%d props, %d boxes, %d clashes%s)" % [label, pr.kept.size(), boxes.size(), clash, first])
	var inside := 0
	var where := ""
	for c in pr.kept:
		for bx in c.boxes:
			var he: Vector3 = bx.he - Vector3(0.02, 0.02, 0.02)
			for sx in [-1.0, 0.0, 1.0]:
				for sy in [-1.0, 0.0, 1.0]:
					for sz in [-1.0, 0.0, 1.0]:
						var off: Vector2 = bx.ax * he.x * sx + bx.az * he.z * sz
						var p := Vector3(bx.c.x + off.x, bx.c.y + he.y * sy, bx.c.z + off.y)
						if _in_solid(b, p):
							inside += 1
							if where == "":
								where = " (first: %s at %s)" % [CSProps.KINDS[c.kind], str(p)]
	ok(inside == 0, "%s: no prop inside a block, an arch, a corbel, a pillar, stairs or the land (%d points inside%s)" % [label, inside, where])


func _props() -> void:
	var t := CSTown.new()
	CSStarter.make("castle", grid, t)
	var b := _built(t)
	var tris := b.mesh.tri_count()
	var pr := CSProps.new()
	pr.build(b)
	print("   castle: %s" % str(pr.counts))
	print("   %s, %d instances" % [str(pr.stats), pr.instance_count()])
	ok(b.mesh.tri_count() == tris and b.mesh.verts.size() == tris * 3, "the props leave the welded skin alone (%d tris)" % tris)
	var few := []
	for kn: String in CSProps.KINDS.slice(0, CSProps.CASTLE_KINDS):
		if int(pr.counts.get(kn, 0)) < PROPS_MIN:
			few.append("%s %d" % [kn, int(pr.counts.get(kn, 0))])
	ok(few.is_empty(), "the castle starter gets at least %d of every kind of prop (short: %s)" % [PROPS_MIN, str(few)])
	_props_clean(b, pr, "castle")
	var land := CFBirds.landings_from(b.mesh)
	var n0 := (land.pos as PackedVector3Array).size()
	CSProps.add_perches(land, pr.perches())
	ok((land.pos as PackedVector3Array).size() > n0, "birds may perch on the chimneys (%d more perches)" % ((land.pos as PackedVector3Array).size() - n0))
	# the same every time: a fresh build of the same blocks gives the same props, transform for transform
	var b2 := _built(t)
	var pr2 := CSProps.new()
	pr2.build(b2)
	ok(pr2.buffers() == pr.buffers() and pr.kept.size() > 0, "the props are the same every time (%d kept)" % pr.kept.size())
	for n in ["village", "harbour", "tower", "bridges"]:
		var tv := CSTown.new()
		CSStarter.make(n, grid, tv)
		var bv := _built(tv)
		var pv := CSProps.new()
		pv.build(bv)
		print("   %s: %s" % [n, str(pv.counts)])
		_props_clean(bv, pv, n)
	# random 70-block castles: clean, and the castle plus its props built in under 3 s
	var worst := 0.0
	var worst_props := 0.0
	var dirty := 0
	var total := 0
	for s in 16:
		var tr := CSTown.new()
		CSStarter.random_growth(grid, tr, s, 70)
		var t0 := Time.get_ticks_usec()
		var br := CSBuild.new()
		br.build(grid, tr)
		var t1 := Time.get_ticks_usec()
		var prr := CSProps.new()
		prr.build(br)
		var t2 := Time.get_ticks_usec()
		worst = maxf(worst, float(t2 - t0) / 1000.0)
		worst_props = maxf(worst_props, float(t2 - t1) / 1000.0)
		total += prr.kept.size()
		if s < 6:
			var f0 := fails
			_props_clean(br, prr, "random %d" % s)
			if fails > f0:
				dirty += 1
		if s == 0:
			var pr3 := CSProps.new()
			pr3.build(br)
			ok(pr3.buffers() == prr.buffers(), "random 0: the props are the same every time")
	print("   (random castles: %d props in all, slowest props %.0f ms)" % [total, worst_props])
	ok(worst < 3000.0, "a 70-block castle and its props build in %.0f ms (props alone at most %.0f ms)" % [worst, worst_props])
