extends SceneTree
## The editor driven like a player (windowed, through the memory guard): real mouse and key events pushed into the
## window, the castle building on its worker thread. A click on the sea puts a block down, a click on its roof stacks
## another, a right-click takes it away, Ctrl+Z / Ctrl+Y undo and redo, a left drag previews a row of blocks and the release builds them (one undo step), a
## middle drag moves the camera, a right drag turns it, a swatch only picks a colour, and ten quick clicks all land in the shown castle.
## Run: Godot --path . --audio-driver Dummy --resolution 1600x900 --script res://tests/verify_cs_editor.gd -- --cs-fresh
## The spots it clicks are chosen for a window of at least 1600x900 (the castle fills a smaller one and the bars cover the free sea):
## in a smaller window it prints why and exits with code 4 without running a check.

const TIME_CAP_MS := 1500000        # the whole run: 25 minutes of wall-clock time. (A cap in frames does not do: a real GPU draws a frame in 7 ms while a
                                    # build on the worker takes about a second and a half at the default cell size, so the frames a step needs depend on the machine.)
const SETTLE_CAP_MS := 120000       # one wait for the castle on screen to catch up with the town

var fails := 0
var checks := 0
var main: Node3D
var frames := 0
var t_start := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print("  %s %s" % ["ok  " if cond else "FAIL", what])


func _initialize() -> void:
	t_start = Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	frames += 1
	if OS.get_static_memory_usage() > 1.5e9 or Performance.get_monitor(Performance.OBJECT_NODE_COUNT) > 150000.0:
		push_error("runaway: static memory %d, nodes %d" % [OS.get_static_memory_usage(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		_quit(3)
		return true
	if Time.get_ticks_msec() - t_start > TIME_CAP_MS:
		print("  FAIL the test ran out of time (%d s, %d frames)" % [(Time.get_ticks_msec() - t_start) / 1000, frames])
		_quit(2)
		return true
	return false


func _quit(code: int) -> void:
	## Leave cleanly: the castle's worker thread must not still be running when the scene is freed (that was an access violation on exit).
	if main != null and is_instance_valid(main):
		main.shutdown_build()
	quit(code)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _settle() -> void:
	## Until the castle on screen is the town's (the worker idle, nothing dirty), then two physics frames for the shape.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < SETTLE_CAP_MS:
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


func _button(button: int, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	root.push_input(e)
	await process_frame


func _move_along(button: int, path: Array) -> void:
	## The mouse moving along the path (a frame between samples) with the button held.
	for i in range(1, path.size()):
		var mv := InputEventMouseMotion.new()
		mv.position = path[i]
		mv.global_position = path[i]
		mv.relative = path[i] - path[i - 1]
		mv.button_mask = 1 << (button - 1)
		root.push_input(mv)
		await process_frame


func _drag(button: int, path: Array) -> void:
	## Press at the path's start, move along it, release at its end.
	var first: Vector2 = path[0]
	var mv0 := InputEventMouseMotion.new()
	mv0.position = first
	mv0.global_position = first
	root.push_input(mv0)
	await _button(button, true, first)
	await _move_along(button, path)
	await _button(button, false, path[path.size() - 1])


func _sea_pair(wild: bool) -> Array:
	## Two screen points over free sea cells in view, 150-300 px apart, each of which a click would build on (wild: a landscape column).
	var grid: CSGrid = main.grid
	var town: CSTown = main.town
	var cands := []
	for v in grid.verts.size():
		if not grid.buildable(v) or town.top(v) >= 0 or town.has_wild(v):
			continue
		var d := grid.verts[v].length()
		if d < 24.0 or d > 60.0:
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


func _straight_plan() -> Dictionary:
	## A free cell on the sea in view and a grid heading (a multiple of 30 degrees) along which a wall of three stops (the middles of cells it may
	## end at) lies over free sea in view: {v0, deg, len (the wall's length), p0 (screen, the cell's middle), p1 (screen, the end, nudged a few
	## degrees off the line)}. Empty if none.
	var grid: CSGrid = main.grid
	var town: CSTown = main.town
	for v in grid.d_count:
		if not grid.buildable(v) or town.top(v) >= 0 or town.has_wild(v):
			continue
		var d := grid.verts[v].length()
		if d < 22.0 or d > 60.0:
			continue
		var a := grid.verts[v]
		var wa := Vector3(a.x, 0.0, a.y)
		if (main.cam as Camera3D).is_position_behind(wa):
			continue
		var pa := _screen(wa)
		if not _safe(pa):
			continue
		var pk: Dictionary = main.pick(pa)
		if (pk.add as Array).size() != 2 or int((pk.add as Array)[0]) != v or int((pk.add as Array)[1]) != 0:
			continue
		for deg in range(0, 360, 30):
			var dir := Vector2.from_angle(deg_to_rad(float(deg)))
			var stops := grid.line_stops(a, dir, 40.0)
			if stops.size() < 3:
				continue
			var len := float(stops[2])
			var end := a + dir * len
			var off := a + (dir * len).rotated(deg_to_rad(5.0))
			var pb := _screen(Vector3(off.x, 0.0, off.y))
			if not _safe(pb) or (main.cam as Camera3D).is_position_behind(Vector3(off.x, 0.0, off.y)) or pa.distance_to(pb) < 100.0:
				continue
			var hit: Dictionary = main.pick(pb)
			var hp: Vector3 = hit.point
			var dd := Vector2(hp.x, hp.z) - a
			if hit.point == Vector3.ZERO or CSGrid.snap_direction(dd).angle_to(dir) > 0.01:
				continue
			# the nearest place a wall may end to where the pointer's shadow falls on the line must be the third stop
			var along := dd.dot(dir)
			var nearest := 0.0
			for s: float in stops:
				if absf(s - along) < absf(nearest - along):
					nearest = s
			if absf(nearest - len) > 0.01:
				continue
			var free := true
			for c: int in grid.cells_along(a, end, false):
				if not grid.is_whole(c) or town.top(c) >= 0 or town.has_wild(c) or (grid.is_dodecagon(c) and not grid.buildable(c)):
					free = false
			if free:
				return {"v0": v, "deg": deg, "len": len, "p0": pa, "p1": pb}
	return {}


func _key(code: int, ctrl: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	root.push_input(e)
	await process_frame


func _key_shift(code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.shift_pressed = true
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
	var win := root.get_visible_rect().size
	if win.x < 1599.0 or win.y < 899.0:
		print("NOT RUN: this suite needs a window of at least 1600x900 (this one is %dx%d); start it with --resolution 1600x900" % [int(win.x), int(win.y)])
		_quit(4)
		return
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
		if d < 24.0 or d > 60.0:
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
	# a left drag PREVIEWS: a translucent ghost of every block the stroke would place, following the pointer (moving back takes
	# cells off it), nothing built while the button is down; the release builds them as ONE undo step; a plain click builds one
	# block; Esc or the right button cancels; middle drag moves the camera, right drag turns it
	var n2 := town.size()
	var pair := _sea_pair(false)
	ok(pair.size() == 2, "found two spots on the sea to drag between")
	if pair.size() == 2:
		var pa: Vector2 = pair[0]
		var pb: Vector2 = pair[1]
		var hist0: int = main.history.size()
		var goal_l: Vector3 = main.cam_goal
		var mv0 := InputEventMouseMotion.new()
		mv0.position = pa
		mv0.global_position = pa
		root.push_input(mv0)
		await _button(MOUSE_BUTTON_LEFT, true, pa)
		await _move_along(MOUSE_BUTTON_LEFT, _path([pa, pb]))
		var shown_out: int = main.stroke_cols.size()
		ok(main.stroke_active and shown_out >= 2 and (main.stroke_mi as MeshInstance3D).visible and (main.stroke_mi.mesh as ArrayMesh).get_surface_count() == shown_out,
			"holding the button and dragging shows a ghost of every cell on the way (%d previewed)" % shown_out)
		ok(town.size() == n2 and main.history.size() == hist0, "nothing is built while the button is down")
		ok(not (main.ghost_mi as MeshInstance3D).visible, "the single hover ghost steps aside for the preview")
		ok((main.cam_goal as Vector3).distance_to(goal_l) < 0.01, "a left drag does not move the camera")
		await _move_along(MOUSE_BUTTON_LEFT, _path([pb, pa]))
		var shown_back: int = main.stroke_cols.size()
		ok(shown_back >= 1 and shown_back < shown_out and town.size() == n2, "moving back over the cells takes them off the preview (%d -> %d)" % [shown_out, shown_back])
		await _move_along(MOUSE_BUTTON_LEFT, _path([pa, pb]))
		ok(main.stroke_cols.size() == shown_out, "moving on again puts them back (%d)" % main.stroke_cols.size())
		var planned: Array = main.stroke_cols.duplicate()
		await _button(MOUSE_BUTTON_LEFT, false, pb)
		await _settle()
		var painted := town.size() - n2
		ok(not main.stroke_active and not (main.stroke_mi as MeshInstance3D).visible, "the release ends the stroke and hides the preview")
		ok(painted == planned.size(), "the release builds exactly the previewed blocks (%d of %d)" % [painted, planned.size()])
		var all_there := true
		for col: int in planned:
			if town.top(col) < 0:
				all_there = false
		ok(all_there, "each previewed cell has its block")
		ok(main.history.size() == hist0 + 1, "the whole stroke is one undo step (%d new)" % (main.history.size() - hist0))
		await _key(KEY_Z, true)
		await _settle()
		ok(town.size() == n2, "one Ctrl+Z takes the whole stroke back (%d -> %d blocks)" % [n2 + painted, town.size()])
		await _key(KEY_Y, true)
		await _settle()
		ok(town.size() == n2 + painted, "Ctrl+Y builds it again")
		await _key(KEY_Z, true)
		await _settle()
		# Esc cancels: no build, no preview, and the rest of the drag does nothing
		var h1: int = main.history.size()
		await _button(MOUSE_BUTTON_LEFT, true, pa)
		await _move_along(MOUSE_BUTTON_LEFT, _path([pa, pb]))
		var was_previewing: bool = main.stroke_active and main.stroke_cols.size() >= 2
		await _key(KEY_ESCAPE, false)
		ok(was_previewing and not main.stroke_active and not (main.stroke_mi as MeshInstance3D).visible, "Esc during a drag cancels it and hides the preview")
		await _move_along(MOUSE_BUTTON_LEFT, _path([pb, pa]))
		await _button(MOUSE_BUTTON_LEFT, false, pa)
		await _settle()
		ok(town.size() == n2 and main.history.size() == h1 and not main.stroke_active, "a cancelled drag builds nothing, not even on release or when the pointer moves on")
		# the right button cancels too
		await _button(MOUSE_BUTTON_LEFT, true, pa)
		await _move_along(MOUSE_BUTTON_LEFT, _path([pa, pb]))
		await _button(MOUSE_BUTTON_RIGHT, true, pb)
		ok(not main.stroke_active and not (main.stroke_mi as MeshInstance3D).visible, "pressing the right button during a drag cancels it")
		await _button(MOUSE_BUTTON_RIGHT, false, pb)
		await _button(MOUSE_BUTTON_LEFT, false, pb)
		await _settle()
		ok(town.size() == n2 and main.history.size() == h1, "and nothing is built (%d blocks)" % town.size())
		# a left button moved only a couple of pixels is a click: one block
		await _drag(MOUSE_BUTTON_LEFT, [pa, pa + Vector2(2.0, 1.0)])
		await _settle()
		ok(town.size() == n2 + 1 and main.history.size() == h1 + 1 and not main.stroke_active, "a left button moved only a couple of pixels is still a click: one block, no stroke")
		await _key(KEY_Z, true)
		await _settle()
		ok(town.size() == n2, "and Ctrl+Z takes it back")
	# STRAIGHT WALLS: the button next to the build types (and the T key) turn it on; a drag then previews ONE straight wall from the middle of the
	# cell pressed on, along the grid direction (a multiple of 30 degrees) nearest to the pointer, ending at the middle of a cell, so it always lies
	# on a grid line; it follows the pointer, builds only at the release as ONE undo step (the wall's every point on four parallel lines), Esc or
	# the right button cancels, a right-click takes the wall away, and a click still builds one block
	var sb: Button = main.ui.b_straight
	ok(sb != null and sb.is_visible_in_tree() and not main.straight_mode and not sb.button_pressed, "a Straight wall button sits with the build types, off to begin with")
	await _click(sb.get_global_rect().get_center())
	ok(main.straight_mode and sb.button_pressed and sb.text.contains("On"), "clicking the button turns straight walls on and shows it on the button (%s)" % sb.text)
	await _key(KEY_T, false)
	ok(not main.straight_mode and not sb.button_pressed, "the T key turns it off again")
	await _key(KEY_T, false)
	ok(main.straight_mode and sb.button_pressed, "and on")
	var swp := _straight_plan()
	ok(not swp.is_empty(), "found a free stretch of sea along a grid direction to drag a wall over")
	if not swp.is_empty():
		var v0: int = swp.v0
		var p0: Vector2 = swp.p0
		var p1: Vector2 = swp.p1
		var a0: Vector2 = grid.verts[v0]
		var dir0 := Vector2.from_angle(deg_to_rad(float(swp.deg)))
		var n3 := town.size()
		var hist3: int = main.history.size()
		var mvs := InputEventMouseMotion.new()
		mvs.position = p0
		mvs.global_position = p0
		root.push_input(mvs)
		await _button(MOUSE_BUTTON_LEFT, true, p0)
		await _move_along(MOUSE_BUTTON_LEFT, _path([p0, p1]))
		var wl: Dictionary = main.stroke_wall
		ok(main.stroke_active and wl.has("len") and absf(float(wl.x) - a0.x) < 0.01 and int(wl.deg) == int(swp.deg) and absf(float(wl.len) - float(swp.len)) < 0.01,
			"a straight drag previews one wall from the cell pressed on, snapped to %d degrees although the pointer is a few degrees off it, %.2f m long (%s)" % [int(swp.deg), float(swp.len), str(wl)])
		ok(posmod(main.stroke_deg, 360) == int(swp.deg) and (main.stroke_mi as MeshInstance3D).visible and (main.stroke_mi.mesh as ArrayMesh).get_surface_count() == 1,
			"the ghost is one prism, not a row of cells")
		var gv: PackedVector3Array = (main.stroke_mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var ghost_off := 0.0
		for q: Vector3 in gv:
			ghost_off = maxf(ghost_off, absf((Vector2(q.x, q.z) - a0).cross(dir0)))
		ok(ghost_off < CSBuild.WALL_THICK * 0.5 + 0.01, "every point of the ghost lies within the wall's width of its grid line (%.3f m off)" % ghost_off)
		ok(town.walls.is_empty() and town.size() == n3 and main.history.size() == hist3, "nothing is built while the button is down")
		ok(main.status_msg.begins_with("Straight wall at "), "the in-game cue says what the straight drag will do (%s)" % main.status_msg)
		# the pointer coming back shortens it; going round swings it to another grid direction
		await _move_along(MOUSE_BUTTON_LEFT, _path([p1, p0.lerp(p1, 0.5)]))
		var shorter: Dictionary = main.stroke_wall
		ok(shorter.has("len") and float(shorter.len) < float(swp.len) - 0.5 and int(shorter.deg) == int(swp.deg), "moving the pointer back shortens the wall (%.2f -> %.2f m)" % [float(swp.len), float(shorter.get("len", 0.0))])
		var side := Vector2(-dir0.y, dir0.x)
		var other := _screen(Vector3(a0.x + side.x * 12.0, 0.0, a0.y + side.y * 12.0))
		await _move_along(MOUSE_BUTTON_LEFT, _path([p0.lerp(p1, 0.5), other]))
		var turned: Dictionary = main.stroke_wall
		ok(turned.has("len") and absi(posmod(int(turned.deg) - int(swp.deg), 360) - 90) <= 30 and posmod(int(turned.deg), 30) == 0,
			"turning the pointer to another side swings the wall to the grid direction there (%s)" % str(turned))
		await _move_along(MOUSE_BUTTON_LEFT, _path([other, p1]))
		ok(int(main.stroke_wall.get("deg", -1)) == int(swp.deg) and absf(float(main.stroke_wall.get("len", 0.0)) - float(swp.len)) < 0.01 and town.walls.is_empty(),
			"back on the first direction it is the same wall again, still unbuilt")
		await _button(MOUSE_BUTTON_LEFT, false, p1)
		await _settle()
		ok(not main.stroke_active and not (main.stroke_mi as MeshInstance3D).visible, "the release ends the stroke and hides the preview")
		ok(town.walls.size() == 1 and absf(float(town.walls[0].x) - a0.x) < 0.01 and absf(float(town.walls[0].z) - a0.y) < 0.01 and int(town.walls[0].deg) == int(swp.deg) and absf(float(town.walls[0].len) - float(swp.len)) < 0.01 and town.size() == n3,
			"the release builds exactly the previewed wall, and no block")
		ok(main.history.size() == hist3 + 1, "the whole wall is one undo step (%d new)" % (main.history.size() - hist3))
		# straight: every point of the wall's mesh lies on one of four parallel lines (its two faces and the parapet's two inner faces), from its start to its end
		var wm: CFMesh = main.build.mesh
		var owner := CSBuild.WALL_OWNER + 1
		var lines_ok := true
		var along_lo := INF
		var along_hi := -INF
		var perp_lo := INF
		var perp_hi := -INF
		var wall_verts := 0
		var half := CSBuild.WALL_THICK * 0.5
		var offs := [-half, -(half - CSBuild.PT), half - CSBuild.PT, half]
		var tower_r := float((CSWallJoints.compute(town.walls, CSWalls.thickness(grid)).towers[0] as Dictionary).r)
		for tri in wm.verts.size() / 3:
			if int(wm.cust1[tri * 12 + 3]) != owner:
				continue
			for k in 3:
				var q := wm.verts[tri * 3 + k]
				var r := Vector2(q.x, q.z) - a0
				var perp := r.cross(dir0)
				var al := r.dot(dir0)
				along_lo = minf(along_lo, al)
				along_hi = maxf(along_hi, al)
				if al < tower_r + 0.02 or al > float(swp.len) - tower_r - 0.02:
					continue                        # (the round towers on the two ends)
				wall_verts += 1
				perp_lo = minf(perp_lo, perp)
				perp_hi = maxf(perp_hi, perp)
				var near_line := false
				for o: float in offs:
					if absf(perp - o) < 0.012:
						near_line = true
				# a vertex on an end face (the parapet's corners, the notches' ends) is across the wall: its along value is the end's
				# (the end parapets are across the wall: their crenel's corners are at their inner face, 0.3 m from the end)
				if not near_line and not ((al < CSBuild.PT + 0.012 or al > float(swp.len) - CSBuild.PT - 0.012) and absf(perp) < half + 0.012):
					lines_ok = false
		ok(wall_verts > 100 and lines_ok, "straight: every point of the built wall lies on one of its four parallel lines, within 1.2 cm (%d vertices)" % wall_verts)
		ok(absf(perp_lo + half) < 0.012 and absf(perp_hi - half) < 0.012 and along_lo > -tower_r - 0.02 and along_lo < -half and along_hi < float(swp.len) + tower_r + 0.02 and along_hi > float(swp.len) + half,
			"and it is %.2f m thick, %.2f m long between its two end towers (%.3f .. %.3f across, %.3f .. %.3f along with the towers)" % [CSBuild.WALL_THICK, float(swp.len), perp_lo, perp_hi, along_lo, along_hi])
		# a right-click on the wall takes it away (one undo step), and Ctrl+Z puts it back
		var wp := Vector3(a0.x + dir0.x * float(swp.len) * 0.5, CSBuild.level_y_static(0) + 2.0, a0.y + dir0.y * float(swp.len) * 0.5)
		var pick_w: Dictionary = main.pick(_screen(wp))
		ok(int(pick_w.get("wall", -1)) == 0, "a click on the wall picks it (wall %d)" % int(pick_w.get("wall", -1)))
		await _click(_screen(wp), MOUSE_BUTTON_RIGHT)
		await _settle()
		ok(town.walls.is_empty() and main.history.size() == hist3 + 2, "a right-click takes the wall away, as one undo step")
		await _key(KEY_Z, true)
		await _settle()
		ok(town.walls.size() == 1, "Ctrl+Z puts it back")
		await _key(KEY_Z, true)
		await _settle()
		ok(town.walls.is_empty() and town.size() == n3 and main.history.size() == hist3, "one more Ctrl+Z takes the whole wall back")
		await _key(KEY_Y, true)
		await _settle()
		ok(town.walls.size() == 1, "Ctrl+Y builds it again")
		await _key(KEY_Z, true)
		await _settle()
		# Esc and the right button cancel
		await _button(MOUSE_BUTTON_LEFT, true, p0)
		await _move_along(MOUSE_BUTTON_LEFT, _path([p0, p1]))
		var was: bool = main.stroke_active and main.stroke_wall.has("len")
		await _key(KEY_ESCAPE, false)
		ok(was and not main.stroke_active and not (main.stroke_mi as MeshInstance3D).visible, "Esc cancels a straight drag and hides the preview")
		await _button(MOUSE_BUTTON_LEFT, false, p1)
		await _settle()
		ok(town.walls.is_empty() and town.size() == n3 and main.history.size() == hist3, "and the release after it builds nothing")
		await _button(MOUSE_BUTTON_LEFT, true, p0)
		await _move_along(MOUSE_BUTTON_LEFT, _path([p0, p1]))
		await _button(MOUSE_BUTTON_RIGHT, true, p1)
		ok(not main.stroke_active and not (main.stroke_mi as MeshInstance3D).visible, "pressing the right button cancels it too")
		await _button(MOUSE_BUTTON_RIGHT, false, p1)
		await _button(MOUSE_BUTTON_LEFT, false, p1)
		await _settle()
		ok(town.walls.is_empty() and town.size() == n3 and main.history.size() == hist3, "with nothing built")
		# a plain click still builds one block
		await _click(p0)
		await _settle()
		ok(town.size() == n3 + 1 and town.walls.is_empty() and main.history.size() == hist3 + 1 and town.top(v0) >= 0 and not main.stroke_active, "a plain click with straight walls on builds one block")
		await _key(KEY_Z, true)
		await _settle()
		ok(town.size() == n3, "and Ctrl+Z takes it back")
	# DIRECTIONS: the Directions button and R go 12 -> 16 -> 24 -> 12; the count is saved with the castle; the preview snaps to it (a 22.5 degree wall with 16)
	var db: Button = main.ui.b_dirs
	ok(db != null and db.is_visible_in_tree() and town.wall_dirs == 12 and db.text.contains("12"), "a Directions button shows the 12 directions of a wall, the default (%s)" % db.text)
	await _key(KEY_R, false)
	ok(town.wall_dirs == 16 and db.text.contains("16") and main.status_msg.contains("16"), "R turns it to 16 directions, on the button and in the cue (%s / %s)" % [db.text, main.status_msg])
	if not swp.is_empty():
		var a1: Vector2 = grid.verts[swp.v0]
		var deg16 := -1.0
		var d16 := Vector2.ZERO
		var e16 := Vector2.ZERO
		var q16 := Vector2.ZERO
		for k in 16:
			var cand := 22.5 * float(k)
			if absf(fposmod(cand, 30.0)) < 0.01 or absf(fposmod(cand, 30.0) - 30.0) < 0.01:
				continue                         # only the headings that are not on a grid line
			var dd := Vector2.from_angle(deg_to_rad(cand))
			var ee := a1 + dd * 11.0
			var qq := _screen(Vector3(ee.x, 0.0, ee.y))
			if not _safe(qq) or (main.cam as Camera3D).is_position_behind(Vector3(ee.x, 0.0, ee.y)) or (swp.p0 as Vector2).distance_to(qq) < 60.0:
				continue
			var free16 := true
			for c: int in grid.cells_along(a1, ee, false):
				if not grid.is_whole(c) or town.top(c) >= 0 or town.has_wild(c) or (grid.is_dodecagon(c) and not grid.buildable(c)):
					free16 = false
			if free16:
				deg16 = cand
				d16 = dd
				e16 = ee
				q16 = qq
				break
		if deg16 >= 0.0:
			await _button(MOUSE_BUTTON_LEFT, true, swp.p0)
			await _move_along(MOUSE_BUTTON_LEFT, _path([swp.p0, q16]))
			var w16: Dictionary = main.stroke_wall
			ok(w16.has("len") and absf(float(w16.deg) - deg16) < 0.01 and main.status_msg.contains(main.deg_text(deg16)) and main.status_msg.contains("16 directions"),
				"with 16 directions the drag snaps to %.1f degrees, off the grid's lines (%s)" % [deg16, main.status_msg])
			var units := float(w16.get("len", 0.0)) / (grid.spacing * 0.5)
			ok(absf(units - roundf(units)) < 0.01, "and ends a whole number of half cell spacings along it (%.2f m)" % float(w16.get("len", 0.0)))
			await _button(MOUSE_BUTTON_LEFT, false, q16)
			await _settle()
			ok(town.walls.size() == 1 and absf(float(town.walls[0].deg) - deg16) < 0.01, "and the release builds that wall")
			var bad_wall := CFAudit.check(main.build.mesh, [CFMesh.Z_CLOTH_A, CFMesh.Z_CLOTH_B])
			ok(int(bad_wall.open_other) + int(bad_wall.non_manifold) + int(bad_wall.flipped) + int(bad_wall.t_junctions) == 0, "a wall off the grid's lines builds closed")
			await _key(KEY_Z, true)
			await _settle()
			ok(town.walls.is_empty() and town.wall_dirs == 16, "undo takes the wall back and leaves the direction count alone")
		else:
			print("  (no 22.5 degree stretch in view: the 16 direction drag is left to the core suite)")
	await _key(KEY_R, false)
	ok(town.wall_dirs == 24 and db.text.contains("24"), "R again: 24 directions (%s)" % db.text)
	var saved_dirs := CSTown.new()
	saved_dirs.from_dict(town.to_dict())
	ok(saved_dirs.wall_dirs == 24, "the count is saved with the castle")
	await _click(db.get_global_rect().get_center())
	ok(town.wall_dirs == 12 and db.text.contains("12"), "the button goes on round to 12 again (%s)" % db.text)
	# MERGING: a wall laid over another along the same line, and one right beside it, become one (thicker) wall; Ctrl+Z splits them again
	var base_w := CSWalls.thickness(grid)
	var m0 := Vector2(-18.0, -30.0)
	ok(main.add_wall({"x": m0.x, "z": m0.y, "deg": 0.0, "len": 8.0, "w": base_w, "c": 1}) and town.walls.size() == 1, "a wall laid")
	ok(main.add_wall({"x": m0.x + 3.0, "z": m0.y + base_w * 0.5, "deg": 0.0, "len": 9.0, "w": base_w, "c": 1}) and town.walls.size() == 1,
		"a second laid half a thickness beside and overlapping it merges with it (%d wall)" % town.walls.size())
	ok(absf(float(town.walls[0].w) - 1.5 * base_w) < 1e-3 and absf(float(town.walls[0].len) - 12.0) < 1e-3, "one wall %.2f m thick and %.1f m long (the union)" % [float(town.walls[0].w), float(town.walls[0].len)])
	await _key(KEY_Z, true)
	await _settle()
	ok(town.walls.size() == 1 and absf(float(town.walls[0].w) - base_w) < 1e-3 and absf(float(town.walls[0].len) - 8.0) < 1e-3, "Ctrl+Z takes the second wall back: the first is as it was")
	await _key(KEY_Z, true)
	await _settle()
	ok(town.walls.is_empty(), "and the first")
	# off again: the hex-style drag follows the pointer cell by cell as before
	await _click(sb.get_global_rect().get_center())
	ok(not main.straight_mode and not sb.button_pressed, "the button turns straight walls off again")
	if not swp.is_empty():
		var n4 := town.size()
		await _button(MOUSE_BUTTON_LEFT, true, swp.p0)
		await _move_along(MOUSE_BUTTON_LEFT, _path([swp.p0, swp.p1]))
		ok(main.stroke_active and main.stroke_cols.size() >= 2 and main.status_msg.begins_with("Drag preview") and main.stroke_wall.is_empty(), "with it off a drag is the ordinary paint preview again")
		await _key(KEY_ESCAPE, false)
		await _button(MOUSE_BUTTON_LEFT, false, swp.p1)
		await _settle()
		ok(town.size() == n4 and town.walls.is_empty(), "(cancelled)")
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
			# only spots a click reaches itself: not behind a wall or a tower in front (a click there lands on that block, and when
			# the worker has not yet built the earlier clicks two such clicks name the same face, so the second adds nothing)
			var pk0: Dictionary = main.pick(s)
			if (pk0.add as Array).size() == 2 and int(pk0.add[0]) == v and int(pk0.add[1]) == 0:
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
	# the landscape: a stroke of Land previews land on every column it passes over and builds them at the release, one undo step
	main.load_starter("castle")
	await _settle()
	main.set_build_type(CSTown.T_LAND)
	var lpair := _sea_pair(true)
	ok(lpair.size() == 2, "found two spots on the sea to drag land between")
	if lpair.size() == 2:
		var w0 := 0
		for v3 in grid.verts.size():
			if town.wild_is_ground(v3):
				w0 += 1
		var hl0: int = main.history.size()
		await _button(MOUSE_BUTTON_LEFT, true, lpair[0])
		await _move_along(MOUSE_BUTTON_LEFT, _path([lpair[0], lpair[1]]))
		var lprev: int = main.stroke_cols.size()
		var w_mid := 0
		for v3 in grid.verts.size():
			if town.wild_is_ground(v3):
				w_mid += 1
		ok(lprev >= 2 and w_mid == w0 and (main.stroke_mi as MeshInstance3D).visible, "a Land drag previews the columns and builds none while the button is down (%d previewed)" % lprev)
		await _button(MOUSE_BUTTON_LEFT, false, lpair[1])
		await _settle()
		var w1 := 0
		for v3 in grid.verts.size():
			if town.wild_is_ground(v3):
				w1 += 1
		ok(w1 - w0 == lprev and main.history.size() == hl0 + 1, "the release puts the land on those columns as one undo step (%d new columns, %d history steps)" % [w1 - w0, main.history.size() - hl0])
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
	# the Cells switch: H (or the Cells button) asks, a second press within five seconds goes to the next grid of CSGrid.variants() (a new empty sea):
	# the game starts on 12-sided cells at 1/2 of the area, then 1/3, the full size, hexagons at 1/2 ...; Shift+H goes back
	await _settle()
	var cb: Button = main.ui.b_cells
	ok(cb != null and cb.is_visible_in_tree() and main.grid.kind == CSGrid.KIND_DODECA and main.grid.div == CSGrid.DEFAULT_DIV and cb.text.contains("12") and cb.text.contains("1/2"),
		"a Cells button shows the 12-sided cells at half the area, the default (%s)" % cb.text)
	ok(absf(main.grid.side - 0.98) < 0.01 and absf(CSWalls.thickness(main.grid) - CSBuild.WALL_THICK) < 1e-6, "the smaller cells: side %.2f m, a wall %.2f m thick" % [main.grid.side, CSBuild.WALL_THICK])
	var blocks_before := town.size()
	await _key(KEY_H, false)
	ok(main.grid.kind == CSGrid.KIND_DODECA and main.grid.div == CSGrid.DEFAULT_DIV and town.size() == blocks_before, "the first press of H only asks")
	await _key(KEY_H, false)
	await _settle()
	ok(main.grid.kind == CSGrid.KIND_DODECA and main.grid.div == 3 and main.town.grid_div == 3 and main.town.size() == 0 and cb.text.contains("1/3"), "the second press goes to the 12-sided cells at 1/3 of the area, an empty sea (%s)" % cb.text)
	var dv: int = main.grid.nearest(Vector2.ZERO)
	await _click(_screen(Vector3(main.grid.verts[dv].x, 0.0, main.grid.verts[dv].y)))
	await _settle()
	ok(main.town.has(dv, 0) and (main.grid.nbrs[dv] as PackedInt32Array).size() == 12, "a click builds a block on a 12-sided cell of the smaller size")
	for _i in 2:                       # on to the full size, then the hexagons at 1/2
		await _key(KEY_H, false)
		await _key(KEY_H, false)
		await _settle()
	ok(main.grid.kind == CSGrid.KIND_HEX and main.town.grid_kind == CSGrid.KIND_HEX and main.grid.div == 2 and main.town.size() == 0 and cb.text.contains("6"), "two more switches reach the hexagon grid at 1/2 of the area (%s)" % cb.text)
	var hv: int = main.grid.nearest(Vector2.ZERO)
	await _click(_screen(Vector3(main.grid.verts[hv].x, 0.0, main.grid.verts[hv].y)))
	await _settle()
	ok(main.town.has(hv, 0) and (main.grid.nbrs[hv] as PackedInt32Array).size() == 6, "a click builds a block on a hexagon")
	for _i in 3:                       # Shift+H back: the full size, 1/3, then the default
		await _key_shift(KEY_H)
		await _key_shift(KEY_H)
		await _settle()
	ok(main.grid.kind == CSGrid.KIND_DODECA and main.town.grid_kind == CSGrid.KIND_DODECA and main.grid.div == CSGrid.DEFAULT_DIV and main.town.size() == 0, "Shift+H goes back to the 12-sided cells at 1/2 of the area")
	_end()


func _end() -> void:
	print("%d checks, %d failed" % [checks, fails])
	await _wait(3)
	_quit(1 if fails else 0)
