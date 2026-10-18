extends SceneTree
## Renders the pictures of the combinations viewer with the game itself: a turntable (sprite sheet of frames) for every outcome of the exhaustive
## neighbourhood dump, the click-and-pop animation of three ripple cases, turntables of landscape spots and of the castle starter.
## Windowed (a render is needed), muted, through the memory guard:
##   powershell -File tools\cs_run.ps1 -Windowed -Script res://tools/analysis_render.gd -Seconds 900 -ScriptArgs "-- --cs-fresh --cs-noui --cs-nobirds --cs-uncap --cs-quality=high
##     --cs-look=overcast --combos=C:/.../viewer/data/combos.json --out=C:/.../viewer/img [--only=patterns,ripple,spots,castle] [--from=0 --count=40] [--tag=_pen]"
## Needs --resolution WxH on the Godot command line (cs_run.ps1 uses 1600x900; the tiles are cut from a RENDER-sized window, see --render=WxH below).
## Output: <out>/<id><tag>.jpg sprite sheets and <out>/renders<tag>.json (each run updates the records of the jobs it did).

const FRAME_CAP := 400000
const SPOTS := ["orchard", "poplar", "willow", "pine_snow", "quarry", "bridge", "jetty", "junction", "garden", "gravel_climb", "flatten", "road_to_door"]

var main: Node3D
var frames := 0
var opts := {}
var out_dir := ""
var tag := ""
var tile := Vector2i(480, 360)
var records := {}
var world_name := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and not a.begins_with("--cs-"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out_dir = str(opts.get("out", "user://render"))
	tag = str(opts.get("tag", ""))
	if opts.has("tile"):
		var t := str(opts.tile).split("x")
		tile = Vector2i(int(t[0]), int(t[1]))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	frames += 1
	if frames > FRAME_CAP:
		print("FAIL the renderer ran out of frames")
		quit(2)
		return true
	return false


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != tile:
		img.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
	return img


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _aim(target: Vector3, dist: float, pitch: float, yaw: float) -> void:
	main.cam_goal = target
	main.cam_target = target
	main.cam_dist = dist
	main.cam_pitch = pitch
	main.cam_yaw = yaw


func _sheet(imgs: Array, cols: int) -> Image:
	var rows := int(ceil(float(imgs.size()) / float(cols)))
	var sheet := Image.create(cols * tile.x, rows * tile.y, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(Vector2i.ZERO, tile), Vector2i((i % cols) * tile.x, (i / cols) * tile.y))
	return sheet


func _save(id: String, imgs: Array, cols: int, extra: Dictionary = {}) -> void:
	var sheet := _sheet(imgs, cols)
	var file := "%s%s.jpg" % [id, tag]
	sheet.save_jpg("%s/%s" % [out_dir, file], float(opts.get("quality", 0.82)))
	var rec := {"file": file, "cols": cols, "rows": int(ceil(float(imgs.size()) / float(cols))), "tw": tile.x, "th": tile.y, "frames": imgs.size()}
	for k: String in extra:
		rec[k] = extra[k]
	records[id] = rec
	print("saved ", file, " (", imgs.size(), " frames)")


func _turntable(id: String, n: int, cols: int, yaw0: float, extra: Dictionary = {}, swing: float = 0.0) -> void:
	## A full turn from yaw0, or (swing > 0) a sweep of `swing` radians centred on yaw0 that the page plays back and forth.
	var imgs: Array = []
	for i in n:
		if swing > 0.0:
			main.cam_yaw = yaw0 - swing * 0.5 + swing * float(i) / float(n - 1)
		else:
			main.cam_yaw = yaw0 + TAU * float(i) / float(n)
		await _wait(14 if i == 0 else 3)
		imgs.append(await _grab())
	if swing > 0.0:
		extra["swing"] = true
	_save(id, imgs, cols, extra)


func _set_pattern(point: int, level: int, rep: int, per_side: int, c_ctx: int, c_sub: int) -> void:
	## The town of one neighbourhood class: the subject block (and its own column) in c_sub, the neighbours in c_ctx.
	var t: CSTown = main.town
	t.clear()
	var nb: PackedInt32Array = main.grid.nbrs[point]
	var n := nb.size()
	var use_below := level >= 1
	t.add(point, level, c_sub)
	var own := rep >> (n * per_side)
	if use_below:
		if own & 1:
			t.add(point, level - 1, c_sub)
		if own & 2:
			t.add(point, level + 1, c_sub)
	elif own & 1:
		t.add(point, level + 1, c_sub)
	for i in n:
		var g := (rep >> (i * per_side)) & ((1 << per_side) - 1)
		if use_below:
			if g & 1:
				t.add(nb[i], level - 1, c_ctx)
			if g & 2:
				t.add(nb[i], level, c_ctx)
			if g & 4:
				t.add(nb[i], level + 1, c_ctx)
		else:
			if g & 1:
				t.add(nb[i], level, c_ctx)
			if g & 2:
				t.add(nb[i], level + 1, c_ctx)
	main.mark_changed()


func _job_pattern(j: Dictionary) -> void:
	var point := int(j.point)
	var level := int(j.level)
	_set_pattern(point, level, int(j.rep), int(j.per_side), int(opts.get("ctx_colour", 10)), int(opts.get("sub_colour", 2)))
	await _wait(8)
	var top := 0
	for v: int in main.town.columns():
		top = maxi(top, main.town.top(v))
	var p: Vector2 = main.grid.verts[point]
	var hgt := float(top + 1) * CSBuild.H + 5.0               # the column plus room for a cone roof
	var dist := float(opts.get("dist", 11.5 + 0.9 * hgt))
	var ty := CSBuild.B + hgt * 0.5
	_aim(Vector3(p.x, ty, p.y), dist, float(opts.get("pitch", 0.45)), 0.55)
	await _turntable(str(j.id), 24, 6, 0.55, {"kind": "pattern", "level": level, "rep": int(j.rep)})


func _project(world: Vector3, ratio: Vector2) -> Array:
	var sp: Vector2 = main.cam.unproject_position(world)
	return [snappedf(sp.x * ratio.x, 0.1), snappedf(sp.y * ratio.y, 0.1)]


func _job_ripple(j: Dictionary) -> void:
	var c: Dictionary = j.case
	var seed := int(c.seed)
	CSStarter.make("random:%d:70" % seed, main.grid, main.town)
	main.mark_changed()
	await _wait(10)
	var click: Array = c.click
	var cv := int(click[0])
	var ck := int(click[1])
	var p: Vector2 = main.grid.verts[cv]
	var target := Vector3(p.x, CSBuild.level_y_static(ck) + 2.0, p.y)
	_aim(target, float(opts.get("rdist", 30.0)), 0.5, atan2(p.x, p.y))
	await _wait(16)
	var imgs: Array = []
	imgs.append(await _grab())                                   # 0: before
	main.set_colour(int(click[2]))
	main.add_block(cv, ck)
	await _wait(4)
	var pops := 14
	for i in pops:
		main.pop_t0 = main.time_alive - 0.6 * float(i) / float(pops - 1)
		await _wait(2)
		imgs.append(await _grab())                               # 1..14: the pop
	main.pop_t0 = main.time_alive - 2.0
	await _wait(8)
	imgs.append(await _grab())                                   # 15: after
	var ratio := Vector2(float(tile.x) / float(root.size.x), float(tile.y) / float(root.size.y))
	var marks: Array = [["click"] + _project(Vector3(p.x, CSBuild.level_y_static(ck) + 2.0, p.y), ratio)]
	for ch: Array in c.changed:
		var q: Vector2 = main.grid.verts[int(ch[0])]
		marks.append([str(ch[2]), str(ch[3]), str(ch[4])] + _project(Vector3(q.x, CSBuild.level_y_static(int(ch[1])) + 2.0, q.y), ratio))
	await _save(str(j.id), imgs, 4, {"kind": "ripple", "marks": marks, "pops": pops})


func _find_spot(name: String) -> int:
	## A column that shows one landscape rule, or -1.
	var w: CSWorld = main.world
	var species: Dictionary = main.scatter.species
	var roads: Dictionary = main.roads.info
	var best := -1
	var best_score := -1e9
	for v: int in w.ground:
		var cx := w.ctx(v)
		var alt := w.altitude(v)
		var s := -1e9
		match name:
			"orchard":
				if species.get(v, "") == "orchard":
					s = 10.0 + float(cx.castle) - 0.01 * float(v)
			"poplar":
				if species.get(v, "") == "poplar":
					s = 10.0 + float(cx.road) - 0.01 * float(v)
			"willow":
				if species.get(v, "") == "willow":
					s = 10.0 + float(cx.water) - 0.01 * float(v)
			"pine_snow":
				if species.get(v, "") == "pine" and alt > 4.0:
					s = alt - 0.01 * float(v)
			"quarry":
				if main.town.wild_heights(v).contains("r"):
					s = 5.0 * float(cx.castle) + float(cx.rock) - 0.01 * float(v)
			"flatten":
				if int(cx.castle) >= 1 and (int(cx.mount) >= 1 or int(cx.rock) >= 1 or alt > 1.0):
					s = 5.0 * float(cx.castle) + alt - 0.01 * float(v)
			"gravel_climb":
				if roads.has(v) and int((roads[v] as Dictionary).surface) == CSRoads.SURF_GRAVEL:
					s = alt - 0.01 * float(v)
			"junction":
				if roads.has(v) and str((roads[v] as Dictionary).cls) == "junction":
					s = float(((roads[v] as Dictionary).conns as Array).size()) - 0.01 * float(v)
			"road_to_door":
				if roads.has(v) and not ((roads[v] as Dictionary).castle as Array).is_empty():
					s = 1.0 - 0.01 * float(v)
		if s > best_score:
			best_score = s
			best = v
	if best >= 0:
		return best
	# decks (bridges, jetties) and gardens are not "ground"
	if name == "bridge" or name == "jetty":
		for v: int in w.deck:
			var inf: Dictionary = roads.get(v, {})
			if not inf.is_empty() and str(inf.cls) == name:
				var sc2 := 1.0 if int(inf.surface) == CSRoads.SURF_STONE else 0.0
				if sc2 + 0.001 * float(v) > best_score:
					best_score = sc2 + 0.001 * float(v)
					best = v
	if name == "garden":
		var gk: Array = w.garden.keys()
		gk.sort()
		if not gk.is_empty():
			best = gk[0]
	return best


func _fill_country(seed: int) -> void:
	## The probe's random country (a random castle with land, roads, trees, rocks and mountains round it).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + seed
	var town: CSTown = main.town
	CSStarter.random_growth(main.grid, town, seed, 40)
	var types := [CSTown.T_LAND, CSTown.T_ROAD, CSTown.T_TREE, CSTown.T_ROCK, CSTown.T_MOUNTAIN]
	var c := CSStarter._centre_pos(main.grid)
	for i in 220:
		var v := -1
		var cols := town.wild_columns() + town.columns()
		if cols.is_empty() or rng.randf() < 0.12:
			v = main.grid.nearest(c + Vector2(rng.randf_range(-24, 24), rng.randf_range(-24, 24)))
		else:
			var v0: int = cols[rng.randi_range(0, cols.size() - 1)]
			var nb: PackedInt32Array = main.grid.nbrs[v0]
			v = nb[rng.randi_range(0, nb.size() - 1)]
		if v < 0 or not main.grid.buildable(v) or town.top(v) >= 0:
			continue
		town.wild_add(v, types[rng.randi_range(0, types.size() - 1)])


func _load_world(name: String) -> void:
	if world_name == name:
		return
	if name.begins_with("country:"):
		main.town.clear()
		_fill_country(int(name.get_slice(":", 1)))
	else:
		CSStarter.make(name, main.grid, main.town)
	main.mark_changed()
	await _wait(12)
	world_name = name


func _job_spot(j: Dictionary) -> void:
	var v := -1
	for wn: String in ["kingdom", "landscape", "country:2", "country:4", "country:6", "country:8", "country:10", "country:12", "country:14", "country:16"]:
		await _load_world(wn)
		v = _find_spot(str(j.find))
		if v >= 0:
			break
	if v < 0:
		print("no spot for ", j.find)
		return
	var p: Vector2 = main.grid.verts[v]
	var gy: float = main.world.height_at(p)
	var target := Vector3(p.x, gy + 1.3, p.y)
	await _wait(6)                                  # the physics world takes the new shapes
	var cam_plan := _plan_camera(target, float(opts.get("sdist", 21.0)), atan2(p.x, p.y))
	print("   camera: pitch %.2f dist %.1f %s" % [cam_plan.pitch, cam_plan.dist, "full turn" if cam_plan.full else "sweep %.0f deg" % rad_to_deg(cam_plan.span)])
	_aim(target, cam_plan.dist, cam_plan.pitch, cam_plan.yaw0)
	await _wait(14)
	var extra := {"kind": "spot", "find": str(j.find), "v": v, "world": world_name}
	if cam_plan.full:
		await _turntable(str(j.id), 24, 6, cam_plan.yaw0, extra)
	else:
		await _turntable(str(j.id), 24, 6, cam_plan.yaw0, extra, cam_plan.span)


func _clearance(target: Vector3, yaw: float, pitch: float, want: float) -> float:
	## How far a camera can sit from `target` in that direction before a wall, a rock or the ground is in the way.
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(target, target + dir * want)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return want
	return (hit.position as Vector3).distance_to(target)


func _plan_camera(target: Vector3, want: float, yaw_out: float) -> Dictionary:
	## The pitch and the arc round `target` with the most room for a camera `want` m away: a full turn when nothing is in the way, else the widest
	## free sweep (the camera never ends up inside geometry).
	var n := 48
	var best := {"score": -1.0}
	for pitch: float in [0.5, 0.8, 1.05, 1.25]:
		var clr: Array = []
		for i in n:
			clr.append(_clearance(target, yaw_out + TAU * float(i) / float(n), pitch, want))
		var all_clear := true
		for c: float in clr:
			if c < want * 0.98:
				all_clear = false
		if all_clear:
			return {"pitch": pitch, "dist": want, "yaw0": yaw_out, "full": true, "span": TAU, "score": 99.0}
		for thr: float in [want * 0.98, want * 0.8, want * 0.62]:
			var best_len := 0
			var best_start := 0
			var run := 0
			for k in range(0, 2 * n):
				if float(clr[k % n]) >= thr:
					run += 1
					if run > best_len and run < n:
						best_len = run
						best_start = k - run + 1
				else:
					run = 0
			if best_len >= 5:
				var lo := 1e9
				for k in range(best_start, best_start + best_len):
					lo = minf(lo, float(clr[k % n]))
				var span := minf(TAU * float(best_len - 1) / float(n), 2.2)
				var mid := yaw_out + TAU * (float(best_start) + float(best_len - 1) * 0.5) / float(n)
				var score := span * (thr / want) - 0.05 * pitch
				if score > float(best.score):
					best = {"pitch": pitch, "dist": clampf(lo - 0.8, 9.0, want), "yaw0": mid, "full": false, "span": span, "score": score}
				break
	if float(best.score) < 0.0:
		best = {"pitch": 1.2, "dist": 12.0, "yaw0": yaw_out, "full": false, "span": 1.2, "score": 0.0}
	return best


func _job_castle(j: Dictionary) -> void:
	CSStarter.make(str(j.starter), main.grid, main.town)
	main.mark_changed()
	await _wait(10)
	main.frame_town(true)
	var dist: float = main.cam_dist * 0.85
	_aim(main.cam_goal, dist, 0.5, 0.6)
	await _wait(16)
	await _turntable(str(j.id), 24, 6, 0.6, {"kind": "castle"})


func _make_jobs(cb: Dictionary) -> Array:
	var jobs: Array = []
	var only := str(opts.get("only", "patterns,ripple,spots,castle"))
	if only.contains("patterns") and cb.has("exh"):
		for lvl in ["k1", "k0"]:
			var e: Dictionary = cb.exh[lvl]
			var outs: Array = e.outcomes
			for i in outs.size():
				jobs.append({"kind": "pattern", "id": "%s_%02d" % [lvl, i], "point": int(e.point), "level": int(e.level), "rep": int(outs[i].rep), "per_side": int(e.per_side)})
	if only.contains("ripple") and cb.has("ripple"):
		var cs: Array = cb.ripple.cases
		for i in cs.size():
			jobs.append({"kind": "ripple", "id": "rip_%d" % i, "case": cs[i]})
	if only.contains("spots"):
		var want := str(opts.get("spots", ",".join(SPOTS)))
		for s: String in SPOTS:
			if want.split(",").has(s):
				jobs.append({"kind": "spot", "id": "spot_" + s, "find": s})
	if only.contains("castle"):
		jobs.append({"kind": "castle", "id": "castle_castle", "starter": "castle"})
	return jobs


func _run() -> void:
	await _wait(8)
	main.async_build = false
	if main.life != null:
		main.life.visible = false
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cb := _read_json(str(opts.get("combos", "")))
	var jobs := _make_jobs(cb)
	var from := int(opts.get("from", 0))
	var count := int(opts.get("count", 100000))
	var prefix := str(opts.get("ids", ""))
	var rpath := "%s/renders%s.json" % [out_dir, tag]
	records = _read_json(rpath)
	var done := 0
	for idx in jobs.size():
		var j: Dictionary = jobs[idx]
		if idx < from or done >= count or (prefix != "" and not str(j.id).begins_with(prefix)):
			continue
		if str(j.kind) != "spot":
			world_name = ""                 # the town is about to change: a spot job must load its world again
		print("job %d/%d %s" % [idx + 1, jobs.size(), j.id])
		match str(j.kind):
			"pattern":
				await _job_pattern(j)
			"ripple":
				await _job_ripple(j)
			"spot":
				await _job_spot(j)
			"castle":
				await _job_castle(j)
		done += 1
	var f := FileAccess.open(rpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(records))
	f.close()
	print("wrote ", rpath)
	quit(0)
