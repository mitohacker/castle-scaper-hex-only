extends SceneTree
## The editor driven like a player (windowed, through the memory guard): real mouse and key events pushed into the
## window, the castle building on its worker thread. A click on the sea puts a block down, a click on its roof stacks
## another, a right-click takes it away, Ctrl+Z / Ctrl+Y undo and redo, a drag only moves the camera, a swatch only
## picks a colour, and ten quick clicks all land in the shown castle.
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
	# a left drag moves the camera and builds nothing
	var n2 := town.size()
	var goal0: Vector3 = main.cam_goal
	var a := Vector2(vs.x * 0.5, vs.y * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = a
	root.push_input(press)
	for j in 6:
		var mv := InputEventMouseMotion.new()
		mv.position = a + Vector2(12.0 * (j + 1), 0.0)
		mv.relative = Vector2(12.0, 0.0)
		root.push_input(mv)
		await process_frame
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = a + Vector2(72.0, 0.0)
	root.push_input(rel)
	await _settle()
	ok(town.size() == n2 and (main.cam_goal as Vector3).distance_to(goal0) > 0.5, "a drag moves the camera and builds nothing")
	# a swatch picks a colour and builds nothing under it
	var ui: CSUi = main.ui
	var sw: Button = ui.swatches[7]
	await _click(sw.get_global_rect().get_center())
	await _settle()
	ok(main.colour == 7 and town.size() == n2, "a swatch picks colour 8 and builds nothing (colour %d)" % main.colour)
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
