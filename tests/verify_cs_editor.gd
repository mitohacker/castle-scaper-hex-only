extends SceneTree
## The editor driven like a player (windowed, through the memory guard): real mouse and key events pushed into the
## window, the castle building on its worker thread. A click on the sea puts a block down, a click on its roof stacks
## another, a right-click takes it away, Ctrl+Z / Ctrl+Y undo and redo, a left drag paints a row of blocks (one undo step), a
## middle drag moves the camera, a right drag turns it, a swatch only picks a colour, and ten quick clicks all land in the shown castle.
## Run: Godot --path . --audio-driver Dummy --resolution 1600x900 --script res://tests/verify_cs_editor.gd -- --cs-fresh

const FRAME_CAP := 4000

var fails := 0
var checks := 0
var main: Node3D
var frames := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print("  %s %s" % ["ok  " if cond else "FAIL", what])


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	frames += 1
	if OS.get_static_memory_usage() > 1.5e9 or Performance.get_monitor(Performance.OBJECT_NODE_COUNT) > 150000.0:
		push_error("runaway: static memory %d, nodes %d" % [OS.get_static_memory_usage(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		quit(3)
		return true
	if frames > FRAME_CAP:
		print("  FAIL the test ran out of frames")
		quit(2)
		return true
	return false


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _settle() -> void:
	## Until the castle on screen is the town's (the worker idle, nothing dirty), then two physics frames for the shape.
	for _i in 600:
		await process_frame
		if not main.building and not main.dirty and main.build_task < 0:
			break
	await physics_frame
	await physics_frame
	await process_frame


func _click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	root.push_input(mv)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await process_frame


func _path(pts: Array) -> Array:
	## The mouse path through the given points, a sample about every 12 px.
	var out := [pts[0]]
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var n := maxi(int(ceilf(a.distance_to(b) / 12.0)), 1)
		for j in range(1, n + 1):
			out.append(a.lerp(b, float(j) / float(n)))
	return out


func _drag(button: int, path: Array) -> void:
	## Press at the path's start, move along it (a frame between samples), release at its end.
	var first: Vector2 = path[0]
	var mv0 := InputEventMouseMotion.new()
	mv0.position = first
	mv0.global_position = first
	root.push_input(mv0)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = first
	press.global_position = first
	root.push_input(press)
	await process_frame
	for i in range(1, path.size()):
		var mv := InputEventMouseMotion.new()
		mv.position = path[i]
		mv.global_position = path[i]
		mv.relative = path[i] - path[i - 1]
		mv.button_mask = 1 << (button - 1)
		root.push_input(mv)
		await process_frame
	var last: Vector2 = path[path.size() - 1]
	var rel := InputEventMouseButton.new()
	rel.button_index = button
	rel.pressed = false
	rel.position = last
	rel.global_position = last
	root.push_input(rel)
	await process_frame


func _sea_pair(wild: bool) -> Array:
	## Two screen points over free sea cells in view, 150-300 px apart, each of which a click would build on (wild: a landscape column).
	var grid: CSGrid = main.grid
	var town: CSTown = main.town
	var cands := []
	for v in grid.verts.size():
		if not grid.buildable(v) or town.top(v) >= 0 or town.has_wild(v):
			continue
		var d := grid.verts[v].length()
		if d < 24.0 or d > 36.0:
			continue
		var w := Vector3(grid.verts[v].x, 0.0, grid.verts[v].y)
		if (main.cam as Camera3D).is_position_behind(w):
			continue
		var sc := _screen(w)
		if not _safe(sc):
			continue
		var pk: Dictionary = main.pick(sc)
		if (int(pk.wadd) if wild else (int(pk.add[0]) if not (pk.add as Array).is_empty() else -1)) != v:
			continue
		cands.append(sc)
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var dd: float = (cands[i] as Vector2).distance_to(cands[j])
			if dd > 150.0 and dd < 300.0:
				return [cands[i], cands[j]]
	return []


func _key(code: int, ctrl: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	root.push_input(e)
	await process_frame


func _hold(code: Key, frames: int) -> void:
	## A key held down for some frames, through Input (the state W / A / S / D polling reads).
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	for _i in frames:
		await process_frame
	var r := InputEventKey.new()
	r.keycode = code
	r.physical_keycode = code
	r.pressed = false
	Input.parse_input_event(r)
	await process_frame


func _screen(p: Vector3) -> Vector2:
	return (main.cam as Camera3D).unproject_position(p)


func _safe(s: Vector2) -> bool:
	var vs := root.get_visible_rect().size
	return s.x > 120 and s.x < vs.x - 120 and s.y > 110 and s.y < vs.y - 150


func _run() -> void:
	await _wait(5)
	main.load_starter("castle")
	await _settle()
	var town: CSTown = main.town
	var grid: CSGrid = main.grid
	ok(main.build != null and town.size() > 50, "the castle starter is built (%d blocks)" % town.size())
	var shown := 0
	for mi: MultiMeshInstance3D in main.prop_mi:
		if mi.multimesh != null:
			shown += mi.multimesh.instance_count
	ok(main.props != null and main.props.kept.size() > 40 and shown == main.props.instance_count(),
		"its props are shown (%d props, %d instances on screen)" % [main.props.kept.size() if main.props else 0, shown])
	# a free spot on the sea in view, clear of the castle
	var spot := -1
	var best := INF
	var vs := root.get_visible_rect().size
	for v in grid.verts.size():
		if not grid.buildable(v) or town.top(v) >= 0:
			continue
		var d := grid.verts[v].length()
		if d < 24.0 or d > 30.0:
			continue
		var crowded := false
		for u in grid.nbrs[v]:
			if town.top(u) >= 0:
				crowded = true
		var s := _screen(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y))
		if crowded or not _safe(s) or (main.cam as Camera3D).is_position_behind(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y)):
			continue
		var score := s.distance_to(Vector2(vs.x * 0.5, vs.y * 0.62))
		if score < best:
			best = score
			spot = v
	ok(spot >= 0, "found a free spot on the sea in view (%d)" % spot)
	if spot < 0:
		_end()
		return
	var p := grid.verts[spot]
	var n0 := town.size()
	await _click(_screen(Vector3(p.x, 0.0, p.y)))
	await _settle()
	ok(town.has(spot, 0) and town.size() == n0 + 1, "a click on the sea puts a block there")
	ok(main.build.kinds.get(CSTown.key(spot, 0), "") == "cottage", "alone, it is a cottage (%s)" % main.build.kinds.get(CSTown.key(spot, 0), "-"))
	# its roof: a click there stacks a second block
	var roof := Vector3(p.x, CSBuild.level_y_static(1) + 0.6, p.y)
	var hover: Dictionary = main.pick(_screen(roof))
	ok((hover.add as Array) == [spot, 1], "the roof offers the block above (%s)" % str(hover.add))
	await _click(_screen(roof))
	await _settle()
	ok(town.has(spot, 1), "a click on the roof stacks a block on it")
	# a click on a wall's side puts a block beside it
	var side_pick := {}
	var side_pos := Vector2.ZERO
	var cell := grid.dual(spot)
	for i in cell.size():
		var mid := (cell[i] + cell[(i + 1) % cell.size()]) * 0.5
		var q := mid + (mid - p).normalized() * 0.05
		var sp := _screen(Vector3(q.x, CSBuild.level_y_static(0) + 2.0, q.y))
		if not _safe(sp):
			continue
		var pk: Dictionary = main.pick(sp)
		if not (pk.add as Array).is_empty() and int(pk.add[0]) != spot and int(pk.add[1]) == 0:
			side_pick = pk
			side_pos = sp
			break
	ok(not side_pick.is_empty(), "a wall's side offers the cell beside it")
	if not side_pick.is_empty():
		var u: int = side_pick.add[0]
		await _click(side_pos)
		await _settle()
		ok(town.has(u, 0), "a click on the side builds beside it")
		ok(main.build.kinds.get(CSTown.key(u, 0), "") != "cottage", "two blocks side by side are no longer a lone cottage")
	# right-click the top block away, then undo and redo with the keys
	var top_pt := Vector3(p.x, CSBuild.level_y_static(2) + 0.6, p.y)
	var n1 := town.size()
	await _click(_screen(top_pt), MOUSE_BUTTON_RIGHT)
	await _settle()
	ok(not town.has(spot, 1) and town.size() == n1 - 1, "a right-click takes the top block away")
	await _key(KEY_Z, true)
	await _settle()
	ok(town.has(spot, 1), "Ctrl+Z puts it back")
	await _key(KEY_Y, true)
	await _settle()
	ok(not town.has(spot, 1), "Ctrl+Y takes it away again")
	# a left drag PAINTS: a block on every new cell the mouse passes over, none stacked on what the stroke just built,
	# one undo step for the whole stroke; a middle drag moves the camera, a right drag turns it, both build nothing
	var n2 := town.size()
	var pair := _sea_pair(false)
	ok(pair.size() == 2, "found two spots on the sea to drag between")
	if pair.size() == 2:
		var pa: Vector2 = pair[0]
		var pb: Vector2 = pair[1]
		var hist0: int = main.history.size()
		var goal_l: Vector3 = main.cam_goal
		await _drag(MOUSE_BUTTON_LEFT, _path([pa, pb]))
		await _settle()
		var painted := town.size() - n2
		ok(painted >= 2, "a left drag across the sea paints blocks on the cells it passes over (%d)" % painted)
		ok(main.history.size() == hist0 + 1, "the whole stroke is one undo step (%d new)" % (main.history.size() - hist0))
		ok((main.cam_goal as Vector3).distance_to(goal_l) < 0.01, "a left drag does not move the camera")
		ok(not main.stroke_active and main.stroke_seen.is_empty(), "the stroke ends when the button is released")
		await _key(KEY_Z, true)
		await _settle()
		ok(town.size() == n2, "one Ctrl+Z takes the whole stroke back (%d -> %d blocks)" % [n2 + painted, town.size()])
		await _key(KEY_Y, true)
		await _settle()
		ok(town.size() == n2 + painted, "Ctrl+Y paints it again")
		# back and forth over the same cells in one stroke builds nothing new on top of it
		await _key(KEY_Z, true)
		await _settle()
		var cols0 := town.columns()
		await _drag(MOUSE_BUTTON_LEFT, _path([pa, pb, pa, pb]))
		await _settle()
		var tall := 0
		var fresh := 0
		for v2: int in town.columns():
			if not cols0.has(v2):
				fresh += 1
				if town.top(v2) > 0:
					tall += 1
		ok(fresh >= 2 and tall == 0, "dragging back and forth over the cells the stroke built does not stack blocks on them (%d new columns, %d stacked)" % [fresh, tall])
		await _key(KEY_Z, true)
		await _settle()
		ok(town.size() == n2, "and that stroke was one undo step too (%d blocks)" % town.size())
		var h1: int = main.history.size()
		var n_before := town.size()
		await _drag(MOUSE_BUTTON_LEFT, [pa, pa + Vector2(2.0, 1.0)])
		await _settle()
		ok(town.size() == n_before + 1 and main.history.size() == h1 + 1 and not main.stroke_active, "a left button moved only a couple of pixels is still a click: one block, no stroke")
		await _key(KEY_Z, true)
		await _settle()
	var goal_m: Vector3 = main.cam_goal
	var nm := town.size()
	await _drag(MOUSE_BUTTON_MIDDLE, _path([Vector2(vs.x * 0.5, vs.y * 0.5), Vector2(vs.x * 0.5 + 72.0, vs.y * 0.5)]))
	await _settle()
	ok(town.size() == nm and (main.cam_goal as Vector3).distance_to(goal_m) > 0.5, "a middle drag moves the camera and builds nothing")
	var yaw0: float = main.cam_yaw
	await _drag(MOUSE_BUTTON_RIGHT, _path([Vector2(vs.x * 0.5, vs.y * 0.5), Vector2(vs.x * 0.5 + 96.0, vs.y * 0.5)]))
	await _settle()
	ok(town.size() == nm and absf(main.cam_yaw - yaw0) > 0.1, "a right drag turns the camera and takes nothing away")
	var n2b := town.size()
	# a swatch picks a colour and builds nothing under it
	var ui: CSUi = main.ui
	var sw: Button = ui.swatches[7]
	await _click(sw.get_global_rect().get_center())
	await _settle()
	ok(main.colour == 7 and town.size() == n2b, "a swatch picks colour 8 and builds nothing (colour %d)" % main.colour)
	# ten quick clicks on the sea while the worker builds: every block lands in the shown castle
	var ring := []
	for v in grid.verts.size():
		if ring.size() >= 10:
			break
		if not grid.buildable(v) or town.top(v) >= 0:
			continue
		var d := grid.verts[v].length()
		var s := _screen(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y))
		var apart := true
		for w: int in ring:
			if grid.verts[w].distance_to(grid.verts[v]) < 10.0:
				apart = false
		if d > 22.0 and d < 34.0 and apart and _safe(s):
			ring.append(v)
	var n3 := town.size()
	var t0 := Time.get_ticks_msec()
	for v: int in ring:
		await _click(_screen(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y)))
	await _settle()
	var placed := 0
	for v: int in ring:
		if town.top(v) >= 0:
			placed += 1
	ok(ring.size() >= 6 and town.size() == n3 + ring.size(),
		"%d quick clicks each put down one block (%d on their own spots, the rest on blocks standing in front)" % [ring.size(), placed])
	ok(int(main.build.stats.get("blocks", -1)) == town.size(), "the shown castle has every block (%d / %d), settled in %d ms" % [
		int(main.build.stats.get("blocks", -1)), town.size(), Time.get_ticks_msec() - t0])
	# the pieces that hold blocks up: a click on a pillar offers the empty cell it stands in, a right-click the block it
	# carries (the bridges starter has one)
	main.load_starter("bridges")
	await _settle()
	var pv := -1
	var pl := -1
	for kk: int in main.build.pieces:
		if main.build.pieces[kk] == "pillar":
			pv = kk / 64
			pl = kk % 64
	ok(pv >= 0, "the bridges starter has a block on a pillar")
	if pv >= 0:
		var q := grid.verts[pv]
		var aim := Vector3(q.x, CSBuild.level_y_static(pl) - 2.0, q.y)
		var want_add := [pv, pl - 1]
		var want_rm := [pv, pl]
		var seen := "no hit"
		var good := false
		for yi in 8:
			main.cam_goal = aim
			main.cam_target = aim
			main.cam_dist = 14.0
			main.cam_pitch = 0.15
			main.cam_yaw = TAU * float(yi) / 8.0
			await _wait(3)
			var hp: Dictionary = main.pick(_screen(aim))
			seen = "add %s, remove %s" % [str(hp.add), str(hp.remove)]
			if (hp.add as Array) == want_add and (hp.remove as Array) == want_rm:
				good = true
				break
		ok(good, "a pillar offers the empty cell it stands in and the block it carries (%s)" % seen)
	# the landscape: pick a build type, click land, trees, a road and a mountain onto the sea, right-click them away, undo
	main.load_starter("castle")
	await _settle()
	var ui2: CSUi = main.ui
	await _click((ui2.type_btns[CSTown.T_LAND] as Button).get_global_rect().get_center())
	ok(main.build_type == CSTown.T_LAND, "the Land button picks the land")
	var lv := -1
	var lbest := INF
	for v in grid.verts.size():
		if not grid.buildable(v) or town.top(v) >= 0 or town.has_wild(v):
			continue
		var d2 := grid.verts[v].length()
		if d2 < 26.0 or d2 > 34.0:
			continue
		var sc := _screen(Vector3(grid.verts[v].x, 0.6, grid.verts[v].y))
		if not _safe(sc) or (main.cam as Camera3D).is_position_behind(Vector3(grid.verts[v].x, 0.6, grid.verts[v].y)):
			continue
		if int(main.pick(_screen(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y))).wadd) != v:
			continue                      # a block of the castle stands in front of it
		var sco := sc.distance_to(Vector2(vs.x * 0.5, vs.y * 0.62))
		if sco < lbest:
			lbest = sco
			lv = v
	ok(lv >= 0, "found a free spot for land in view")
	if lv >= 0:
		var lp := grid.verts[lv]
		var lscreen := _screen(Vector3(lp.x, 0.0, lp.y))
		var blocks0 := town.size()
		await _click(lscreen)
		await _settle()
		ok(town.wild_is_ground(lv) and town.size() == blocks0, "a click with Land picked puts land there and no block")
		main.set_build_type(CSTown.T_TREE)
		var lscr2 := _screen(Vector3(lp.x, main.world.height_at(lp) + 0.1, lp.y))
		await _click(lscr2)
		await _settle()
		ok(town.wild_trees(lv) == 1, "Trees: a click plants a tree (%d)" % town.wild_trees(lv))
		await _click(lscr2)
		await _settle()
		ok(town.wild_trees(lv) == 2 and main.scatter.inst.size() > 0, "a second click grows a grove, and the trees stand on screen (%d instances)" % main.scatter.inst.size())
		main.set_build_type(CSTown.T_ROAD)
		await _click(lscr2)
		await _settle()
		ok(not town.wild_road(lv), "a road is refused where trees stand")
		await _click(lscr2, MOUSE_BUTTON_RIGHT)
		await _click(lscr2, MOUSE_BUTTON_RIGHT)
		await _settle()
		ok(town.wild_trees(lv) == 0 and town.wild_is_ground(lv), "right-clicks take the trees away and leave the land")
		await _click(lscr2)
		await _settle()
		ok(town.wild_road(lv), "then the road goes down")
		main.set_build_type(CSTown.T_MOUNTAIN)
		await _click(lscr2)
		await _settle()
		ok(town.wild_heights(lv) == "m" and main.world.altitude(lv) > 3.0, "a mountain click raises the column (%.1f m)" % main.world.altitude(lv))
		await _key(KEY_Z, true)
		await _settle()
		ok(town.wild_heights(lv) == "", "Ctrl+Z takes the mountain level back")
		main.set_build_type(CSTown.T_CASTLE)
		await _click(lscr2)
		await _settle()
		ok(town.top(lv) >= 0 and not town.has_wild(lv), "a castle block on a landscape column replaces what was there")
	# painting the landscape: a stroke of Land puts land on every column it passes over, one undo step
	main.load_starter("castle")
	await _settle()
	main.set_build_type(CSTown.T_LAND)
	var lpair := _sea_pair(true)
	ok(lpair.size() == 2, "found two spots on the sea to paint land between")
	if lpair.size() == 2:
		var w0 := 0
		for v3 in grid.verts.size():
			if town.wild_is_ground(v3):
				w0 += 1
		var hl0: int = main.history.size()
		await _drag(MOUSE_BUTTON_LEFT, _path([lpair[0], lpair[1]]))
		await _settle()
		var w1 := 0
		for v3 in grid.verts.size():
			if town.wild_is_ground(v3):
				w1 += 1
		ok(w1 - w0 >= 2 and main.history.size() == hl0 + 1, "a Land stroke paints land on the columns it passes over, as one undo step (%d new columns, %d history steps)" % [w1 - w0, main.history.size() - hl0])
		await _key(KEY_Z, true)
		await _settle()
		var w2 := 0
		for v3 in grid.verts.size():
			if town.wild_is_ground(v3):
				w2 += 1
		ok(w2 == w0, "one Ctrl+Z takes the whole stroke of land back (%d -> %d)" % [w1, w2])
	main.set_build_type(CSTown.T_CASTLE)
	# the building styles: each type button puts down a block of its own style, with a hat of its own and painted walls
	main.load_starter("castle")
	await _settle()
	var used := {}
	for sty in range(1, CSStyle.COUNT):
		await _click((ui2.type_btns[sty] as Button).get_global_rect().get_center())
		ok(main.build_type == sty, "the %s button picks the %s style" % [CSStyle.NAMES[sty], CSStyle.NAMES[sty]])
		var cand: Array = []
		for v in grid.verts.size():
			if not grid.buildable(v) or town.top(v) >= 0 or town.has_wild(v) or used.has(v):
				continue
			var d3 := grid.verts[v].length()
			if d3 < 26.0 or d3 > 36.0:
				continue
			var crowded2 := false
			for u in grid.nbrs[v]:
				if town.top(u) >= 0 or used.has(u):
					crowded2 = true
			var sc2 := _screen(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y))
			if crowded2 or not _safe(sc2) or (main.cam as Camera3D).is_position_behind(Vector3(grid.verts[v].x, 0.0, grid.verts[v].y)):
				continue
			cand.append([sc2.distance_to(Vector2(vs.x * 0.5, vs.y * 0.62)), v])
		cand.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		# the first spot whose click really lands on that cell of the sea (not on a block standing in front of it)
		var sv := -1
		for ci in cand.size():
			var vv: int = cand[ci][1]
			var pk2: Dictionary = main.pick(_screen(Vector3(grid.verts[vv].x, 0.0, grid.verts[vv].y)))
			if (pk2.add as Array) == [vv, 0]:
				sv = vv
				break
		ok(sv >= 0, "found a free spot for a %s block in view" % CSStyle.NAMES[sty])
		if sv < 0:
			continue
		used[sv] = true
		var sp2 := grid.verts[sv]
		await _click(_screen(Vector3(sp2.x, 0.0, sp2.y)))
		await _settle()
		ok(town.has(sv, 0) and town.style(sv, 0) == sty, "a click with %s picked puts a %s block there (style %d)" % [CSStyle.NAMES[sty], CSStyle.NAMES[sty], town.style(sv, 0)])
		var hk := CSTown.key(sv, 0)
		ok(main.build.hats.has(hk) or main.build.kinds.get(hk, "") == "flat", "the %s block has its own roof (%s)" % [CSStyle.NAMES[sty], str(main.build.kinds.get(hk, "-"))])
		ok(main.build.mesh.tri_count() > 0 and main.build.facades > 0, "the painted walls have their facades (%d)" % main.build.facades)
		# it stacks: a click on its roof puts the next block of the same style on top
		var top_y := CSBuild.level_y_static(1) + 0.4
		var hover2: Dictionary = main.pick(_screen(Vector3(sp2.x, top_y, sp2.y)))
		if (hover2.add as Array) == [sv, 1]:
			await _click(_screen(Vector3(sp2.x, top_y, sp2.y)))
			await _settle()
			ok(town.has(sv, 1) and town.style(sv, 1) == sty, "a click on the roof stacks a second %s block" % CSStyle.NAMES[sty])
	main.set_build_type(CSTown.T_CASTLE)
	# W / A / S / D move the view across the map (Input state set by parsed key events, as a keyboard would)
	main.cam_yaw = 0.0
	main.cam_goal = Vector3.ZERO
	main.cam_target = Vector3.ZERO
	var held := {}
	for kc: int in [KEY_W, KEY_S, KEY_A, KEY_D]:
		held[kc] = true
	await _hold(KEY_W, 14)
	var g1: Vector3 = main.cam_goal
	ok(g1.z < -1.0 and absf(g1.x) < 0.01, "W moves the view forward, away from the camera (%s)" % str(g1))
	await _hold(KEY_S, 14)
	var g2: Vector3 = main.cam_goal
	ok(g2.z > g1.z + 1.0, "S moves it back (%s)" % str(g2))
	var gx: float = g2.x
	await _hold(KEY_D, 14)
	ok((main.cam_goal as Vector3).x > gx + 1.0, "D moves it to the right (%s)" % str(main.cam_goal))
	var gx2: float = (main.cam_goal as Vector3).x
	await _hold(KEY_A, 14)
	ok((main.cam_goal as Vector3).x < gx2 - 1.0, "A moves it to the left (%s)" % str(main.cam_goal))
	main.cam_yaw = PI * 0.5
	var g3: Vector3 = main.cam_goal
	await _hold(KEY_W, 14)
	ok((main.cam_goal as Vector3).x < g3.x - 1.0, "W follows the view's turn: forward is now along -x (%s)" % str(main.cam_goal))
	var gy: float = main.cam_yaw
	await _hold(KEY_E, 10)
	ok(main.cam_yaw > gy + 0.1, "E turns the view")
	var g4: Vector3 = main.cam_goal
	var ctrl_e := InputEventKey.new()
	ctrl_e.physical_keycode = KEY_CTRL
	ctrl_e.keycode = KEY_CTRL
	ctrl_e.pressed = true
	Input.parse_input_event(ctrl_e)
	await _hold(KEY_W, 10)
	ctrl_e.pressed = false
	Input.parse_input_event(ctrl_e)
	ok((main.cam_goal as Vector3).distance_to(g4) < 0.01, "with Ctrl held (Ctrl+S saves) W does not move the view")
	_end()


func _end() -> void:
	print("%d checks, %d failed" % [checks, fails])
	await _wait(3)
	quit(1 if fails else 0)
