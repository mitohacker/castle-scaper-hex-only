extends SceneTree
## Frames of the props popping: the castle starter's top block with the most props is taken away (its props shrink out
## on the leaving set), then put back (they spring out after the block pops up). Saves tmp/pop_out_*.png and
## tmp/pop_in_*.png. Windowed, through the memory guard:
##   Godot --path . --audio-driver Dummy --resolution 1280x720 --script res://tools/pop_probe.gd -- --cs-fresh

const FRAME_CAP := 3000

var main: Node3D
var frames := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	frames += 1
	if frames > FRAME_CAP:
		print("FAIL the probe ran out of frames")
		quit(2)
		return true
	return false


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved %s at t=%.2f (pop_t %.2f)" % [path, main.time_alive, clampf((main.time_alive - main.pop_t0) / 0.6, 0.0, 1.0)])


func _run() -> void:
	await _wait(5)
	main.async_build = false
	main.load_starter("castle")
	await _wait(10)
	var town: CSTown = main.town
	var per_key := {}
	for c in main.props.kept:
		var kk: int = c.key
		if town.top(kk / 64) == kk % 64:
			per_key[kk] = int(per_key.get(kk, 0)) + (c.inst as Array).size()
	var best := -1
	for kk: int in per_key:
		if best < 0 or int(per_key[kk]) > int(per_key[best]):
			best = kk
	if best < 0:
		print("FAIL no top block with props")
		quit(1)
		return
	var v := best / 64
	var k := best % 64
	var p: Vector2 = main.grid.verts[v]
	print("block (%d, %d): %d prop instances" % [v, k, int(per_key[best])])
	main.cam_goal = Vector3(p.x, CSBuild.level_y_static(k) + 2.0, p.y)
	main.cam_target = main.cam_goal
	main.cam_dist = 26.0
	main.cam_pitch = 0.3
	main.cam_yaw = atan2(p.x, p.y)          # from outside the castle, looking in at the block
	await _wait(20)
	await _shot("tmp/pop_0_before.png")
	var c0: int = town.colour(v, k)
	main.remove_block(v, k)
	await _wait(2)
	await _shot("tmp/pop_out_1.png")
	await _wait(6)
	await _shot("tmp/pop_out_2.png")
	await _wait(40)
	main.set_colour(c0)
	main.add_block(v, k)
	for j in 6:
		await _wait(5)
		await _shot("tmp/pop_in_%d.png" % j)
	await _wait(60)
	await _shot("tmp/pop_9_after.png")
	quit(0)
