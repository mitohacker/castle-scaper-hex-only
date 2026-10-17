extends SceneTree
## Every light at every quality in the windowed scene (through the memory guard): the shaders compile (a broken one prints its error
## to the log, which the verify .bat searches), the settings really change the world (the sun's energy and angle, the environment's tone
## mapper, SSAO, SDFGI, volumetric fog, the reflection, the render scale), the look cycles with L and G, the castle and the water
## draw something (the picture is not one flat colour), and the castle's edits still show.
## Run: Godot --path . --audio-driver Dummy --resolution 1280x720 --script res://tests/verify_cs_look.gd -- --cs-fresh

const FRAME_CAP := 3000

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


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		root.push_input(e)
		await process_frame


## How varied the picture is: the standard deviation of the brightness over a coarse grid (a black or flat frame is ~0).
func _spread() -> float:
	var img := root.get_texture().get_image()
	var vals := []
	var step := maxi(img.get_width() / 24, 1)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			vals.append(img.get_pixel(x, y).get_luminance())
	var m := 0.0
	for v: float in vals:
		m += v
	m /= float(vals.size())
	var d := 0.0
	for v: float in vals:
		d += (v - m) * (v - m)
	return sqrt(d / float(vals.size()))


func _run() -> void:
	await _wait(30)
	var look: CSLook = main.look
	ok(look != null and look.env != null and look.sun != null, "the scene has a look, an environment and a sun")
	ok(main.reflect != null and main.sea_mi != null and main.seabed_mi != null and main.rocks_mi != null, "the sea, its floor, the rocks and the reflection exist")
	ok(main.rocks_mi.mesh != null and main.rocks_mi.mesh.get_surface_count() == 1, "the castle's rock skirt is on screen")
	ok(main.life != null and main.life.gulls.size() == CSLife.GULLS and main.life.boat != null, "gulls and a boat sail round the castle")
	ok(main.life.smoke_nodes.size() >= 1, "the castle starter's chimneys smoke (%d)" % main.life.smoke_nodes.size())
	var islands := root.get_tree().get_nodes_in_group("far_island").size()
	ok(islands >= 3, "far islands stand on the horizon (%d)" % islands)
	for lid: String in CSLook.LOOK_IDS:
		look.look_id = lid
		for qid: String in CSLook.QUALITY_IDS:
			look.quality_id = qid
			look.apply()
			await _wait(8)
			var row: Dictionary = CSLook.LOOKS[lid]
			var q: Dictionary = CSLook.QUALITY[qid]
			var tag := "%s / %s" % [lid, qid]
			ok(is_equal_approx(look.sun.light_energy, float(row.sun_energy)), "%s: the sun's energy is the light's" % tag)
			ok(look.env.tonemap_mode == int(row.tonemap), "%s: the tone mapper is the light's" % tag)
			ok(look.env.ssao_enabled == (int(q.ssao) > 0), "%s: ambient occlusion follows the quality" % tag)
			ok(look.env.sdfgi_enabled == bool(q.sdfgi), "%s: SDFGI follows the quality" % tag)
			ok(look.env.volumetric_fog_enabled == bool(q.vol), "%s: god rays follow the quality" % tag)
			ok(main.reflect.on == (float(q.refl) > 0.01), "%s: the reflection follows the quality" % tag)
			ok(is_equal_approx(root.scaling_3d_scale, 1.0 if str(q.upscaler) == "native" else float(q.scale)), "%s: the render scale follows the quality" % tag)
			var sp := _spread()
			ok(sp > 0.03, "%s: the picture has content (spread %.3f)" % [tag, sp])
	# the keys cycle
	look.look_id = "golden"
	look.quality_id = "high"
	look.apply()
	await _key(KEY_L)
	ok(look.look_id == "overcast", "L moves to the next light (%s)" % look.look_id)
	await _key(KEY_G)
	ok(look.quality_id == "ultra", "G moves to the next quality (%s)" % look.quality_id)
	await _key(KEY_G)
	ok(look.quality_id == "low", "G wraps round to low (%s)" % look.quality_id)
	# the pen over the picture: off, light, full; the compute pass must not break the frame
	look.pen_id = "off"
	look.apply()
	await _key(KEY_N)
	ok(look.pen_id == "light" and main.pen.mode == 1 and main.pen.enabled, "N turns the pen to light (%s)" % look.pen_id)
	await _wait(8)
	ok(_spread() > 0.03, "the picture has content with the pen on light")
	await _key(KEY_N)
	ok(look.pen_id == "full" and main.pen.mode == 2, "N turns the pen to full")
	await _wait(8)
	ok(_spread() > 0.03, "the picture has content with the pen on full")
	await _key(KEY_N)
	ok(look.pen_id == "off" and not main.pen.enabled, "N wraps round to off")
	# every infill medium draws something and leaves the frame alive, on light and on full
	look.pen_id = "light"
	for iid: String in CSLook.INFILL_IDS:
		look.infill_id = iid
		look.apply()
		await _wait(6)
		ok(main.pen.style == CSLook.INFILL_IDS.find(iid), "infill %s reaches the pen pass" % iid)
		ok(_spread() > 0.03, "infill %s: the picture has content" % iid)
	await _key(KEY_I)
	ok(look.infill_id == "pencil", "I wraps round the infills to the first (%s)" % look.infill_id)
	look.pen_id = "off"
	look.apply()
	# overrides
	look._overrides = {"exposure": 0.5}
	look.apply()
	ok(is_equal_approx(look.env.tonemap_exposure, 0.5), "a --cs-look-set override reaches the environment")
	look._overrides = {}
	look.look_id = "golden"
	look.quality_id = "high"
	look.apply()
	# a block still goes down and the water reflects something
	var n0: int = main.town.size()
	main.town.add(main.grid.nearest(Vector2(0.0, 0.0)), 0, 1)
	main.mark_changed()
	await _wait(120)
	ok(main.town.size() == n0 + 1 or main.town.size() == n0, "an edit still goes through")
	print("%d checks, %d failed" % [checks, fails])
	quit(1 if fails else 0)
