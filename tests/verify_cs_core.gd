extends SceneTree
## Headless checks: Townscaper's grid, the block model, the rules (what a block becomes from its neighbours), every
## starter and random click-built castles audited as one welded skin, what holds a block with nothing under it up (an
## arch, corbels, a pillar) and stairs, the birds' perches, the prop layer (no two props overlap, none sits inside a
## block, an arch, a corbel, a pillar or stairs, the same every time, every kind on the castle starter, quick enough).
## Run: Godot --headless --path . --script res://tests/verify_cs_core.gd   (exit code = failures)

const SKIP := [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B]
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
	print("== castles audited")
	_audits()
	print("== birds")
	_birds()
	print("== props")
	_props()
	print("== look")
	_look()
	print("== rocks and sea floor")
	_rocks()
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails else 0)


func _grid() -> void:
	var t0 := Time.get_ticks_msec()
	grid.generate()
	var ms := Time.get_ticks_msec() - t0
	var nq := grid.quads.size() / 4
	ok(nq > 800 and grid.verts.size() > 800, "the hexagon map has a real grid (%d quads, %d vertices)" % [nq, grid.verts.size()])
	ok(ms < 3000, "made in %d ms" % ms)
	var folded := 0
	for q in nq:
		var a := grid.verts[grid.quads[q * 4]]
		var b := grid.verts[grid.quads[q * 4 + 1]]
		var c := grid.verts[grid.quads[q * 4 + 2]]
		var d := grid.verts[grid.quads[q * 4 + 3]]
		if (b - a).cross(d - a) <= 0.0 or (d - c).cross(b - c) <= 0.0:
			folded += 1
	ok(folded == 0, "no folded quad after relaxing (%d)" % folded)
	var val := {}
	var asym := 0
	var bad_cell := 0
	var buildable := 0
	var lost := 0
	for v in grid.verts.size():
		for u in grid.nbrs[v]:
			if grid.index_of(u, v) < 0:
				asym += 1
		if not grid.buildable(v):
			continue
		buildable += 1
		var n: int = (grid.nbrs[v] as PackedInt32Array).size()
		val[n] = int(val.get(n, 0)) + 1
		var d := grid.dual(v)
		if d.size() != n or CFTri.area(d) <= 0.5:
			bad_cell += 1
		if grid.nearest(grid.verts[v]) != v:
			lost += 1
	ok(asym == 0, "neighbours are mutual (%d one-way)" % asym)
	ok(buildable > 600, "%d buildable grid points" % buildable)
	ok(int(val.get(3, 0)) > 50 and int(val.get(5, 0)) > 20 and int(val.get(6, 0)) > 5, "irregular like Townscaper: vertices with 3, 5 and 6 quads (%s)" % str(val))
	ok(bad_cell == 0, "every cell is a closed counter-clockwise polygon (%d bad)" % bad_cell)
	ok(lost == 0, "the nearest grid point to a point is itself (%d)" % lost)
	var g2 := CSGrid.new()
	g2.generate()
	ok(g2.verts == grid.verts, "the grid is the same every time (seeded)")


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
	## Blocks round c's cell (its neighbours and the far corners of the quads round it) at level 0: a wall walk round a
	## one-cell courtyard; with raise, two of them one level higher.
	var t := CSTown.new()
	var nb: PackedInt32Array = grid.nbrs[c]
	var rg: PackedInt32Array = grid.rings[c]
	for i in nb.size():
		t.add(nb[i], 0, 1)
		var q := rg[i]
		for kq in 4:
			var x := grid.quads[q * 4 + kq]
			if x != c and x != nb[i] and x != nb[(i + 1) % nb.size()] and grid.buildable(x):
				t.add(x, 0, 2)
				if raise and i == 0:
					t.add(x, 1, 2)
					t.add(nb[i], 1, 1)
	return t


func _stairs() -> void:
	# a wall walk round a courtyard, part of it a level higher: stairs up from the courtyard and between the two walks
	var found := -1
	var b: CSBuild = null
	var near := []
	for v in grid.verts.size():
		if grid.buildable(v) and grid.verts[v].length() < 24.0 and (grid.nbrs[v] as PackedInt32Array).size() == 4:
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
		if ground and walk and bb.land.get(c, "") == "court":
			found = c
			b = bb
			break
	ok(found >= 0, "a courtyard gets stairs up to its wall walk, and the walk stairs up to the higher one (round %d)" % found)
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


func _audit(t: CSTown, label: String, strict: bool) -> Dictionary:
	var b := _built(t)
	var au := CFAudit.check(b.mesh, SKIP)
	var nan := false
	for p in b.mesh.verts:
		if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
			nan = true
			break
	ok(not nan and b.mesh.tri_count() > 0, "%s: a finite mesh (%d tris)" % [label, b.mesh.tri_count()])
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
	ok(int(seen.get("arch", 0)) > 0 and int(seen.get("corbel", 0)) > 0 and int(seen.get("pillar", 0)) > 0 and int(seen.get("stairs", 0)) > 0,
		"click-built castles grow arches, corbels, pillars and stairs (%s)" % str(seen))


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
			for kk in 4:
				cells[grid.quads[qd * 4 + kk]] = true
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
		ok(float(row.sun_elev) > 5.0 and float(row.sun_elev) < 85.0 and float(row.sun_energy) > 0.0, "light %s: the sun is above the horizon" % id)
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
	for kn: String in CSProps.KINDS:
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
