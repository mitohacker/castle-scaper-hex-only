extends Node3D
## Castle Scaper: build a castle the Townscaper way. One action: click to put a block on the grid (on the sea, on top
## of a block, or beside one), right-click to take one away, pick its colour below. Towers, roofs, wall walks with
## battlements, gate passages, courtyards, doors and windows all come out of CSBuild's rules.

const AUTOSAVE := "user://castle_scaper_realistic_autosave.json"
const CASTLES_DIR := "user://castles"
const HISTORY_MAX := 300
const DRAG_PX := 6.0

var grid := CSGrid.new()
var town := CSTown.new()
var build: CSBuild
var ui: CSUi
var cam: Camera3D
var env: Environment
var sky_mat: ShaderMaterial
var key_light: DirectionalLight3D
var mat_plaster: ShaderMaterial
var castle_mi: MeshInstance3D
var castle_shape: CollisionShape3D
var castle_body: StaticBody3D
var terrain_mi: MeshInstance3D
var terrain_shape: CollisionShape3D
var terrain_body: StaticBody3D
var mat_terrain: ShaderMaterial
var world: CSWorld
var scatter: CSScatter
var scatter_meshes: Array = []
var scatter_mi: Array = []
var mat_flora: ShaderMaterial
var mat_road: ShaderMaterial
var road_mi: MeshInstance3D
var road_meshes: Array = []
var road_prop_mi: Array = []
var road_body: StaticBody3D
var road_shape: CollisionShape3D
var roads: CSRoads
var build_type := 0                 # CSTown.T_*: what a click puts down
var sea_mi: MeshInstance3D
var seabed_mi: MeshInstance3D
var rocks_mi: MeshInstance3D
var look: CSLook
var reflect: CSReflect
var life: CSLife
var pen: CSPen
var grid_mi: MeshInstance3D
var grid_mat: ShaderMaterial
var ghost_mi: MeshInstance3D
var ghost_mat: StandardMaterial3D
var birds: CFBirds
var birds_on := true
var props: CSProps                  # the prop layer on screen (CSProps: built with the castle on the worker)
var props_on := true
var prop_meshes: Array = []
var prop_mat: ShaderMaterial
var leave_mat: ShaderMaterial
var prop_root: Node3D
var prop_mi: Array = []             # one MultiMeshInstance3D per CSProps mesh
var leave_mi: Array = []            # the same for the props of a block just taken away, shrinking
var leaving := false
var leave_t0 := -10.0
var unpop := {}                     # block keys taken away since the last build started

var colour := 1
var cam_yaw := 0.6
var cam_pitch := 0.6
var cam_dist := 80.0
var cam_target := Vector3.ZERO
var cam_goal := Vector3.ZERO
var spin := false
var hover := {}
var last_mouse := Vector2.ZERO
var press := {}                     # button -> {"pos": Vector2, "moved": bool}
var history := []
var future := []
var dirty := true
var async_build := true
var build_task := -1
var build_job := {}
var building := false
var build_pending := false
var pop_id := -1.0
var pop_t0 := -10.0
var pop_pending := false
var time_alive := 0.0
var autosave_timer := -1.0
var status_msg := ""
var status_t := 0.0
var args := {}
var fresh := false
var scare_at := -1.0
var shot_path := ""
var shot_wait := 2.5
var shot_frames := 0
var shot_views := []
var shot_next := 0.0


func _ready() -> void:
	args = _parse_args()
	if args.has("uncap"):
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_make_environment()
	_make_camera()
	pen = CSPen.new()
	var comp := Compositor.new()
	comp.compositor_effects = [pen]
	cam.compositor = comp
	mat_plaster = ShaderMaterial.new()
	mat_plaster.shader = load("res://shaders/cs_castle.gdshader")
	mat_plaster.set_shader_parameter("land_y", CSBuild.B)
	_make_sea()
	castle_mi = MeshInstance3D.new()
	castle_mi.name = "Castle"
	add_child(castle_mi)
	var body := StaticBody3D.new()
	castle_shape = CollisionShape3D.new()
	body.add_child(castle_shape)
	add_child(body)
	castle_body = body
	mat_terrain = ShaderMaterial.new()
	mat_terrain.shader = load("res://shaders/cs_terrain.gdshader")
	mat_flora = ShaderMaterial.new()
	mat_flora.shader = load("res://shaders/cs_flora.gdshader")
	mat_road = ShaderMaterial.new()
	mat_road.shader = load("res://shaders/cs_road.gdshader")
	road_mi = MeshInstance3D.new()
	road_mi.name = "Roads"
	add_child(road_mi)
	road_body = StaticBody3D.new()
	road_shape = CollisionShape3D.new()
	road_body.add_child(road_shape)
	add_child(road_body)
	road_meshes = CSRoads.make_meshes()
	scatter_meshes = CSScatter.make_meshes()
	var sroot := Node3D.new()
	sroot.name = "Flora"
	add_child(sroot)
	for i in CSScatter.MESH_COUNT:
		var smi := MultiMeshInstance3D.new()
		smi.material_override = mat_flora
		sroot.add_child(smi)
		scatter_mi.append(smi)
	for i in CSRoads.MESH_COUNT:
		var rmi := MultiMeshInstance3D.new()
		rmi.material_override = mat_flora
		sroot.add_child(rmi)
		road_prop_mi.append(rmi)
	terrain_mi = MeshInstance3D.new()
	terrain_mi.name = "Terrain"
	add_child(terrain_mi)
	terrain_body = StaticBody3D.new()
	terrain_shape = CollisionShape3D.new()
	terrain_body.add_child(terrain_shape)
	add_child(terrain_body)
	ghost_mi = MeshInstance3D.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.albedo_color = Color(1, 1, 1, 0.38)
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_mi.material_override = ghost_mat
	ghost_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost_mi.visible = false
	ghost_mi.layers = 2
	add_child(ghost_mi)
	_make_props()
	life = CSLife.new()
	life.name = "Life"
	add_child(life)
	if not args.has("nobirds"):
		birds = CFBirds.new()
		birds.name = "Birds"
		add_child(birds)
	# the town: a file, a starter, the autosave, or the castle starter
	var loaded := false
	if args.has("load"):
		loaded = town.load_json(str(args.load))
	elif not fresh and not args.has("starter") and FileAccess.file_exists(AUTOSAVE):
		loaded = town.load_json(AUTOSAVE)
	grid.generate(town.grid_seed, town.grid_radius)
	if args.has("starter"):
		CSStarter.make(str(args.starter), grid, town)
	elif not loaded and not fresh:
		CSStarter.make("castle", grid, town)
	_make_grid_overlay()
	ui = CSUi.new()
	ui.main = self
	add_child(ui)
	if args.has("noui"):
		ui.visible = false
	if args.has("spin"):
		spin = true
	_rebuild_now()
	frame_town(true)
	if args.has("cam"):
		var c: PackedStringArray = str(args.cam).split(",")
		if c.size() >= 3:
			cam_yaw = float(c[0])
			cam_pitch = float(c[1])
			cam_dist = float(c[2])
	if args.has("target"):
		var tg: PackedStringArray = str(args.target).split(",")
		if tg.size() >= 3:
			cam_goal = Vector3(float(tg[0]), float(tg[1]), float(tg[2]))
			cam_target = cam_goal
	_update_camera(1.0)
	look.apply()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--cs-"):
			continue
		var kv := a.substr(5).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if out.has("shot"):
		async_build = false
		shot_path = str(out.shot)
		shot_wait = float(out.get("wait", "2.5"))
		if out.has("views"):
			for v in str(out.views).split(","):
				var q := v.split("/")
				if q.size() >= 7:
					shot_views.append([q[0], float(q[1]), float(q[2]), float(q[3]), Vector3(float(q[4]), float(q[5]), float(q[6]))])
	if out.has("scare"):
		scare_at = float(out.scare)
	fresh = out.has("fresh")
	return out


# --- scene ---------------------------------------------------------------------------------------

func _make_environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/cs_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	key_light = DirectionalLight3D.new()
	key_light.name = "Sun"
	add_child(key_light)
	look = CSLook.new()
	look.name = "Look"
	add_child(look)
	look.setup(self, env, key_light, sky_mat)


func _make_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.1
	cam.far = 3000.0
	add_child(cam)
	cam.make_current()


func _make_sea() -> void:
	sea_mi = MeshInstance3D.new()
	sea_mi.name = "Sea"
	sea_mi.mesh = CSRocks.sea_mesh()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/cs_sea.gdshader")
	sea_mi.material_override = sm
	sea_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	sea_mi.layers = 2
	add_child(sea_mi)
	seabed_mi = MeshInstance3D.new()
	seabed_mi.name = "Seabed"
	seabed_mi.mesh = CSRocks.seabed_mesh()
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/cs_seabed.gdshader")
	seabed_mi.material_override = bm
	seabed_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	seabed_mi.layers = 2
	add_child(seabed_mi)
	# far islands on the horizon (they stand in the haze; the water's shallow-edge foam rings them by itself)
	var ism := ShaderMaterial.new()
	ism.shader = load("res://shaders/cs_island.gdshader")
	for isl: Array in [[-1250.0, -900.0, 11, 260.0, 120.0], [1500.0, -1500.0, 23, 380.0, 170.0], [-300.0, 1700.0, 37, 210.0, 80.0], [1800.0, 700.0, 51, 150.0, 55.0]]:
		var imi := MeshInstance3D.new()
		imi.name = "FarIsland"
		imi.add_to_group("far_island")
		imi.mesh = CSRocks.island_mesh(int(isl[2]), float(isl[3]), float(isl[4]))
		imi.material_override = ism
		imi.position = Vector3(float(isl[0]), 0.0, float(isl[1]))
		imi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		imi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(imi)
	rocks_mi = MeshInstance3D.new()
	rocks_mi.name = "Rocks"
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/cs_rock.gdshader")
	rocks_mi.material_override = rm
	add_child(rocks_mi)
	reflect = CSReflect.new()
	reflect.name = "Reflection"
	add_child(reflect)
	reflect.setup(cam, sm, env)
	look.reflect = reflect
	look.set_sea(sm)


func _make_props() -> void:
	## The prop layer: one MultiMeshInstance3D per prop mesh, and a second set for the props of a block just taken away
	## (they shrink out). The instances are made on the build thread (CSProps.multimeshes).
	prop_meshes = CSProps.make_meshes()
	var sh: Shader = load("res://shaders/cs_props.gdshader")
	prop_mat = ShaderMaterial.new()
	prop_mat.shader = sh
	leave_mat = ShaderMaterial.new()
	leave_mat.shader = sh
	leave_mat.set_shader_parameter("leave_t", 1.0)
	prop_root = Node3D.new()
	prop_root.name = "Props"
	add_child(prop_root)
	for i in CSProps.MESH_COUNT:
		for set_i in 2:
			var mi := MultiMeshInstance3D.new()
			mi.material_override = prop_mat if set_i == 0 else leave_mat
			mi.visible = set_i == 0
			prop_root.add_child(mi)
			(prop_mi if set_i == 0 else leave_mi).append(mi)
	if args.has("noprops"):
		props_on = false
		prop_root.visible = false


func toggle_props() -> void:
	props_on = not props_on
	prop_root.visible = props_on
	flash("Details" + (" on" if props_on else " off"))
	if ui:
		ui.refresh()


func _make_grid_overlay() -> void:
	## The grid on the water, shown round the cursor (Townscaper draws one quad per face with UV corners at +-1).
	if grid_mi == null:
		grid_mi = MeshInstance3D.new()
		grid_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;\n" + \
			"uniform vec3 center = vec3(0.0); uniform float radius = 14.0;\nvarying vec3 w;\n" + \
			"void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\n" + \
			"void fragment() { vec2 fw = max(fwidth(UV), vec2(1e-4)); vec2 g = (1.0 - abs(UV)) / fw; float line = 1.0 - min(min(g.x, g.y), 1.0);\n" + \
			"float fade = 1.0 - smoothstep(radius * 0.3, radius, length(w.xz - center.xz)); ALBEDO = vec3(1.0); ALPHA = line * fade * 0.55; }\n"
		grid_mat.shader = sh
		grid_mi.material_override = grid_mat
		grid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grid_mi.layers = 2
		add_child(grid_mi)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cuv := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for q in grid.quads.size() / 4:
		for k: int in [0, 1, 2, 0, 2, 3]:
			var p := grid.verts[grid.quads[q * 4 + k]]
			verts.append(Vector3(p.x, 0.06, p.y))
			uvs.append(cuv[k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	grid_mi.mesh = m


# --- building ------------------------------------------------------------------------------------

func mark_changed() -> void:
	dirty = true
	autosave_timer = 1.0


func push_history() -> void:
	history.append(town.to_dict())
	if history.size() > HISTORY_MAX:
		history.pop_front()
	future.clear()


func undo() -> void:
	if history.is_empty():
		flash("Nothing to undo")
		return
	future.append(town.to_dict())
	town.from_dict(history.pop_back())
	mark_changed()


func redo() -> void:
	if future.is_empty():
		flash("Nothing to redo")
		return
	history.append(town.to_dict())
	town.from_dict(future.pop_back())
	mark_changed()


func add_block(v: int, k: int) -> bool:
	if v < 0 or not grid.buildable(v) or k < 0 or k > CSTown.MAX_LEVEL or town.has(v, k):
		return false
	push_history()
	town.wild_clear(v)
	town.add(v, k, colour)
	pop_id = float(v + 1)
	pop_t0 = time_alive
	pop_pending = async_build
	_puff(v, k)
	_scare(v, k)
	mark_changed()
	return true


func remove_block(v: int, k: int) -> bool:
	if not town.has(v, k):
		return false
	push_history()
	town.remove(v, k)
	unpop[CSTown.key(v, k)] = true
	_puff(v, k)
	_scare(v, k)
	mark_changed()
	return true


func _puff(v: int, k: int) -> void:
	if life == null or shot_path != "":
		return
	var p := grid.verts[v]
	var on_water := k == 0
	life.puff(Vector3(p.x, 0.2 if on_water else CSBuild.level_y_static(k) + 1.0, p.y), on_water)


func _chimney_tops() -> Array:
	var out := []
	if props == null:
		return out
	for c: CSProps.Cand in props.kept:
		if c.kind != CSProps.CHIMNEY:
			continue
		for it: Array in c.inst:
			if int(it[0]) == CSProps.M_CHIMNEY:
				var tf: Transform3D = it[1]
				out.append(tf.origin + tf.basis.y * 1.05)
	return out


func _scare(v: int, k: int) -> void:
	if birds:
		var p := grid.verts[v]
		birds.uproot_near(Vector3(p.x, CSBuild.level_y_static(k) + CSBuild.H, p.y), 9.0, 1.0)


func new_town() -> void:
	push_history()
	town.clear()
	mark_changed()
	flash("An empty sea: click to put down the first block")


func load_starter(name: String) -> void:
	push_history()
	CSStarter.make(name, grid, town)
	mark_changed()
	frame_town(false)


func save_town() -> String:
	DirAccess.make_dir_recursive_absolute(CASTLES_DIR)
	var n := 1
	while n < 1000 and FileAccess.file_exists("%s/castle_%03d.json" % [CASTLES_DIR, n]):
		n += 1
	var path := "%s/castle_%03d.json" % [CASTLES_DIR, n]
	town.name = "Castle %d" % n
	town.save_json(path)
	flash("Saved as castle_%03d" % n)
	return path


func saved_towns() -> Array:
	var out := []
	var d := DirAccess.open(CASTLES_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f)
	out.sort()
	return out


func load_saved(file: String) -> void:
	push_history()
	town.load_json("%s/%s" % [CASTLES_DIR, file])
	mark_changed()
	frame_town(false)


func set_colour(c: int) -> void:
	colour = clampi(c, 0, CSTown.COLOURS - 1)
	if ui:
		ui.refresh()


func toggle_birds() -> void:
	birds_on = not birds_on
	if birds:
		birds.visible = birds_on
	flash("Birds" + (" back" if birds_on else " away"))
	if ui:
		ui.refresh()


func _rebuild() -> void:
	dirty = false
	if not async_build:
		_rebuild_now()
		return
	if build_task >= 0:
		build_pending = true
		return
	_start_build()


func _rebuild_now() -> void:
	var gone := unpop
	unpop = {}
	var b := CSBuild.new()
	b.build(grid, town, build)
	_apply(b, _finish(b), gone)


func _finish(b: CSBuild) -> Dictionary:
	## Everything the shown castle needs, made off the main thread when the build runs on the worker.
	var m := ArrayMesh.new()
	b.mesh.commit(m, mat_plaster)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(b.mesh.verts)
	var pr := CSProps.new()
	pr.build(b)
	var landings := CFBirds.landings_from(b.mesh) if birds else {}
	CSProps.add_perches(landings, pr.perches())
	var w := CSWorld.new()
	w.build(grid, b.town, b.land)
	var tm := ArrayMesh.new()
	w.commit(tm, mat_terrain)
	var rd := CSRoads.new()
	rd.build(w)
	var rm := ArrayMesh.new()
	rd.commit(rm, mat_road)
	var rshape := ConcavePolygonShape3D.new()
	rshape.backface_collision = true
	rshape.set_faces(rd.faces())
	var sc := CSScatter.new()
	sc.build(w)
	var tshape := ConcavePolygonShape3D.new()
	tshape.backface_collision = true
	tshape.set_faces(w.faces)
	var skip := {}
	for u: int in w.ground:
		skip[u] = true
	for u: int in w.deck:
		skip[u] = true
	return {"mesh": m, "shape": shape, "rocks": CSRocks.skirt_mesh(CSRocks.shore_loops(grid, b.land, skip)), "landings": landings, "props": pr, "prop_mm": pr.multimeshes(prop_meshes),
		"world": w, "terrain": tm, "terrain_shape": tshape, "scatter": sc, "scatter_mm": sc.multimeshes(scatter_meshes), "roads": rd, "road_mesh": rm, "road_shape": rshape, "road_mm": rd.multimeshes(road_meshes)}


func _start_build() -> void:
	var t := town.duplicate_town()
	var prev := build
	var job := {"b": null, "res": {}, "gone": unpop}
	unpop = {}
	build_job = job
	building = true
	build_pending = false
	build_task = WorkerThreadPool.add_task(func() -> void:
		var b := CSBuild.new()
		b.build(grid, t, prev)
		job["res"] = _finish(b)
		job["b"] = b
		if prev:
			prev.plan = null, true, "castle build")
	if ui:
		ui.refresh()


func _poll_build() -> void:
	if build_task < 0 or not WorkerThreadPool.is_task_completed(build_task):
		return
	WorkerThreadPool.wait_for_task_completion(build_task)
	build_task = -1
	building = false
	var job := build_job
	build_job = {}
	_apply(job.b, job.res, job.gone)
	if build_pending or dirty:
		dirty = false
		build_pending = false
		_start_build()


func _apply(b: CSBuild, res: Dictionary, gone: Dictionary = {}) -> void:
	build = b
	castle_mi.mesh = res.mesh
	castle_shape.shape = res.shape
	world = res.world
	scatter = res.scatter
	roads = res.roads
	road_mi.mesh = res.road_mesh
	road_shape.shape = res.road_shape
	var rmm: Array = res.road_mm
	for i in road_prop_mi.size():
		(road_prop_mi[i] as MultiMeshInstance3D).multimesh = rmm[i]
	var sm: Array = res.scatter_mm
	for i in scatter_mi.size():
		(scatter_mi[i] as MultiMeshInstance3D).multimesh = sm[i]
	terrain_mi.mesh = res.terrain
	terrain_shape.shape = res.terrain_shape
	rocks_mi.mesh = res.rocks
	if not gone.is_empty() and props != null:
		# the props that hung on the blocks just taken away shrink out from where they were
		var mm: Array = props.multimeshes(prop_meshes, gone)
		for i in leave_mi.size():
			(leave_mi[i] as MultiMeshInstance3D).multimesh = mm[i]
			(leave_mi[i] as MultiMeshInstance3D).visible = mm[i] != null
		leaving = true
		leave_t0 = time_alive
	props = res.props
	if life != null:
		life.set_chimneys(_chimney_tops())
	var pm: Array = res.prop_mm
	for i in prop_mi.size():
		(prop_mi[i] as MultiMeshInstance3D).multimesh = pm[i]
	if birds:
		birds.set_landings(res.landings)
	if pop_pending:
		pop_pending = false
		pop_t0 = time_alive
	if ui:
		ui.refresh()


# --- picking -------------------------------------------------------------------------------------

func pick(mouse: Vector2) -> Dictionary:
	## {"add": [v, k] or [], "remove": [v, k] or [], "point": Vector3}: where a click would put a block, what a
	## right-click would take away.
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var out := {"add": [], "remove": [], "point": Vector3.ZERO}
	var hit := {}
	if (castle_shape.shape != null or terrain_shape.shape != null) and is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2500.0)
		hit = get_world_3d().direct_space_state.intersect_ray(q)
	out["wadd"] = -1
	out["wremove"] = -1
	if not hit.is_empty() and (hit.collider == terrain_body or hit.collider == road_body):
		# the landscape: the column under the cursor (a castle click here is a click on the water at that spot)
		var tp: Vector3 = hit.position
		out.point = tp
		var tv := grid.nearest(Vector2(tp.x, tp.z))
		if tv >= 0:
			out.wadd = tv if town.top(tv) < 0 else -1
			out.wremove = _wild_near(Vector2(tp.x, tp.z), tv)
			out.add = [tv, 0] if not town.has(tv, 0) else [tv, town.top(tv) + 1]
		return out
	if hit.is_empty() or build == null:
		if dir.y >= -1e-4:
			return out
		var p := from + dir * (-from.y / dir.y)
		out.point = p
		var v := grid.nearest(Vector2(p.x, p.z))
		if v >= 0:
			out.add = [v, 0] if not town.has(v, 0) else [v, town.top(v) + 1]
			out.wadd = v if town.top(v) < 0 else -1
			out.wremove = _wild_near(Vector2(p.x, p.z), v)
		return out
	var p: Vector3 = hit.position
	out.point = p
	var hn: Vector3 = hit.normal
	var wv := grid.nearest(Vector2(p.x + hn.x * 1.6, p.z + hn.z * 1.6))
	out.wadd = wv if wv >= 0 and town.top(wv) < 0 else -1
	var tri: int = hit.get("face_index", -1)
	var m := build.mesh
	if tri < 0 or tri * 3 + 2 >= m.verts.size():
		return out
	var v := int(m.cust1[tri * 12 + 3]) - 1
	if v < 0 or not grid.buildable(v):
		var vs := grid.nearest(Vector2(p.x, p.z))
		if vs >= 0:
			out.add = [vs, 0] if not town.has(vs, 0) else []
		return out
	var n := (m.norms[tri * 3] + m.norms[tri * 3 + 1] + m.norms[tri * 3 + 2]).normalized()
	var top := town.top(v)
	if top < 0:
		out.add = [v, 0]                    # a courtyard or a passage: build on the ground there
		return out
	var lvl := (p.y - CSBuild.B) / CSBuild.H
	if n.y > 0.45:
		var kb := clampi(floori(lvl + 0.02) - 1, -1, top)
		if p.y > CSBuild.level_y_static(top + 1) - 0.05:
			kb = top
		if kb >= 0 and not town.has(v, kb):
			# the top of what holds a block up (a corbel inside an arch, a pillar's base): the empty cell above it
			out.add = [v, kb + 1] if not town.has(v, kb + 1) else []
			out.remove = _held_above(v, kb + 1)
			return out
		out.add = [v, kb + 1] if not town.has(v, kb + 1) else []
		out.remove = [v, kb] if kb >= 0 else []
	elif n.y < -0.5:
		var kt := roundi(lvl)
		out.add = [v, kt - 1] if kt - 1 >= 0 and not town.has(v, kt - 1) else []
		out.remove = [v, kt] if town.has(v, kt) else _held_above(v, kt)
	else:
		var kh := clampi(floori(lvl), 0, CSTown.MAX_LEVEL)
		if kh > top:
			out.add = [v, top + 1]
			out.remove = [v, top]
		elif not town.has(v, kh) and _inside_cell(v, Vector2(p.x, p.z), 0.08):
			# a face inside the cell of what holds a block up (an arch's passage, a pillar, a corbel's front): the empty
			# cell it stands in, and the block it holds
			out.add = [v, kh]
			out.remove = _held_above(v, kh)
		else:
			var u := grid.neighbour_towards(v, Vector2(n.x, n.z))
			if u >= 0 and grid.buildable(u) and not town.has(u, kh):
				out.add = [u, kh]
			out.remove = [v, kh] if town.has(v, kh) else _held_above(v, kh)
	return out


func _wild_near(pt: Vector2, v: int) -> int:
	## The landscape column nearest to pt among v and its neighbours, or -1.
	var best := -1
	var bd := INF
	for u: int in [v] + Array(grid.nbrs[v]):
		if not town.has_wild(u):
			continue
		var d := grid.verts[u].distance_squared_to(pt)
		if d < bd:
			bd = d
			best = u
	return best


func add_wild(v: int) -> bool:
	if v < 0 or not grid.buildable(v) or town.top(v) >= 0:
		return false
	var land := str(build.land.get(v, "")) if build != null else ""
	if land == "base" or land == "passage":
		flash("The castle stands there")
		return false
	if land == "court" and build_type != CSTown.T_LAND and build_type != CSTown.T_TREE and build_type != CSTown.T_ROAD:
		flash("Only land, trees and roads grow in a courtyard")
		return false
	var snap := town.to_dict()
	if not town.wild_add(v, build_type):
		flash(_wild_refusal(v))
		return false
	history.append(snap)
	if history.size() > HISTORY_MAX:
		history.pop_front()
	future.clear()
	_puff_wild(v, false)
	mark_changed()
	return true


func remove_wild(v: int) -> bool:
	if v < 0 or not town.has_wild(v):
		return false
	push_history()
	town.wild_remove(v)
	_puff_wild(v, true)
	mark_changed()
	return true


func _wild_refusal(v: int) -> String:
	match build_type:
		CSTown.T_LAND:
			return "That is land already"
		CSTown.T_ROAD:
			return "A road does not go through trees" if town.wild_trees(v) > 0 else "A road runs there already"
		CSTown.T_TREE:
			return "Trees do not grow in the road" if town.wild_road(v) else "That is a forest already"
		_:
			return "As high as it goes"


func _puff_wild(v: int, gone: bool) -> void:
	if life == null or shot_path != "":
		return
	var p := grid.verts[v]
	var y := world.height_at(p) if world != null else 0.6
	life.puff(Vector3(p.x, maxf(y, 0.2) + 0.5, p.y), world != null and not world.is_land(v) and not gone)


func set_build_type(t: int) -> void:
	build_type = posmod(t, CSTown.TYPE_NAMES.size())
	ghost_mi.set_meta("key", "")
	if ui:
		ui.refresh()
	flash("Build: " + str(CSTown.TYPE_NAMES[build_type]))


func _held_above(v: int, k: int) -> Array:
	## The lowest block of v's column at level k or above (what an arch, a pillar or corbels at level k hold up).
	for kk in range(maxi(k, 0), CSTown.MAX_LEVEL + 1):
		if town.has(v, kk):
			return [v, kk]
	return []


func _inside_cell(v: int, pt: Vector2, margin: float) -> bool:
	var d := grid.dual(v)
	if not Geometry2D.is_point_in_polygon(pt, d):
		return false
	for i in d.size():
		if Geometry2D.get_closest_point_to_segment(pt, d[i], d[(i + 1) % d.size()]).distance_to(pt) < margin:
			return false
	return true


func _update_ghost() -> void:
	if build_type != CSTown.T_CASTLE and not press.has(MOUSE_BUTTON_RIGHT):
		_update_wild_ghost()
		return
	var target: Array = hover.get("remove", []) if press.has(MOUSE_BUTTON_RIGHT) else hover.get("add", [])
	if target.is_empty() or (press.has(MOUSE_BUTTON_LEFT) and press[MOUSE_BUTTON_LEFT].moved) or ui.mouse_over_ui():
		ghost_mi.visible = false
		return
	var v: int = target[0]
	var k: int = target[1]
	ghost_mat.albedo_color = Color(1.0, 0.45, 0.4, 0.45) if press.has(MOUSE_BUTTON_RIGHT) else Color(1, 1, 1, 0.38)
	var key := "%d:%d:%d" % [v, k, int(press.has(MOUSE_BUTTON_RIGHT))]
	if ghost_mi.get_meta("key", "") != key:
		ghost_mi.set_meta("key", key)
		ghost_mi.mesh = _prism(grid.dual(v), CSBuild.level_y_static(k) + 0.02, CSBuild.level_y_static(k + 1) - 0.02, 0.15)
	ghost_mi.visible = true


func _update_wild_ghost() -> void:
	var v := int(hover.get("wadd", -1))
	if v < 0 or (press.has(MOUSE_BUTTON_LEFT) and press[MOUSE_BUTTON_LEFT].moved) or ui.mouse_over_ui():
		ghost_mi.visible = false
		return
	var key := "w%d:%d:%d" % [v, build_type, town.wild_heights(v).length() * 10 + town.wild_trees(v)]
	if ghost_mi.get_meta("key", "") != key:
		ghost_mi.set_meta("key", key)
		var ground_y := 0.6 + (world.altitude(v) if world != null else 0.0)
		var top := ground_y
		match build_type:
			CSTown.T_LAND, CSTown.T_ROAD:
				top = ground_y + 0.25
			CSTown.T_TREE:
				top = ground_y + 0.5 + 1.6 * float(town.wild_trees(v) + 1)
			CSTown.T_ROCK:
				top = ground_y + CSWorld.RK_LEVEL
			CSTown.T_MOUNTAIN:
				top = ground_y + CSWorld.MT_LEVEL
		ghost_mi.mesh = _prism(grid.dual(v), ground_y - 0.05, top, 0.2)
	ghost_mat.albedo_color = Color(1, 1, 1, 0.38)
	ghost_mi.visible = true


func _prism(poly: PackedVector2Array, y0: float, y1: float, shrink: float) -> ArrayMesh:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(p + (c - p).normalized() * shrink)
	var verts := PackedVector3Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		for q: Vector3 in [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]:
			verts.append(q)
		for q: Vector3 in [Vector3(c.x, y1, c.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y)]:
			verts.append(q)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- camera --------------------------------------------------------------------------------------

func frame_town(snap: bool) -> void:
	var cols := town.columns()
	for v: int in town.wild_columns():
		if not cols.has(v):
			cols.append(v)
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for v: int in cols:
		var p := grid.verts[v]
		lo = Vector3(minf(lo.x, p.x), 0.0, minf(lo.z, p.y))
		var top_y := CSBuild.level_y_static(town.top(v) + 1)
		if town.has_wild(v):
			top_y = maxf(top_y, 0.6 + float(town.wild_heights(v).length()) * 3.0 + 3.0)
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, top_y), maxf(hi.z, p.y))
	if cols.is_empty():
		cam_goal = Vector3.ZERO
		cam_dist = 70.0
	else:
		cam_goal = Vector3((lo.x + hi.x) * 0.5, hi.y * 0.25, (lo.z + hi.z) * 0.5)
		cam_dist = clampf(maxf(hi.x - lo.x, hi.z - lo.z) * 1.6 + hi.y * 1.2 + 25.0, 40.0, 400.0)
	if snap:
		cam_target = cam_goal


func _update_camera(delta: float) -> void:
	cam_target = cam_target.lerp(cam_goal, 1.0 - exp(-8.0 * delta))
	cam_pitch = clampf(cam_pitch, 0.08, 1.45)
	var off := Vector3(cos(cam_pitch) * sin(cam_yaw), sin(cam_pitch), cos(cam_pitch) * cos(cam_yaw)) * cam_dist
	cam.position = cam_target + off
	cam.look_at(cam_target, Vector3.UP)
	if look:
		look.follow_camera(cam_dist)


# --- frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	time_alive += delta
	if pen != null:
		pen.time = time_alive
	_poll_build()
	if dirty:
		_rebuild()
	if spin:
		cam_yaw += delta * 0.15
	_update_camera(delta)
	var pt := clampf((time_alive - pop_t0) / 0.6, 0.0, 1.0)
	mat_plaster.set_shader_parameter("pop_t", pt)
	mat_plaster.set_shader_parameter("pop_id", pop_id)
	prop_mat.set_shader_parameter("pop_t", pt)
	prop_mat.set_shader_parameter("pop_id", pop_id)
	if leaving:
		var lt := clampf((time_alive - leave_t0) / 0.3, 0.0, 1.0)
		leave_mat.set_shader_parameter("leave_t", lt)
		if lt >= 1.0:
			leaving = false
			for mi: MultiMeshInstance3D in leave_mi:
				mi.visible = false
				mi.multimesh = null
	if not press.has(MOUSE_BUTTON_MIDDLE) and not (press.has(MOUSE_BUTTON_RIGHT) and press[MOUSE_BUTTON_RIGHT].moved):
		hover = pick(last_mouse)
	var hv: Array = hover.get("remove", [])
	mat_plaster.set_shader_parameter("hover_id", float(hv[0] + 1) if not hv.is_empty() else -1.0)
	grid_mat.set_shader_parameter("center", hover.get("point", Vector3.ZERO))
	grid_mi.visible = shot_path == "" and not spin
	_update_ghost()
	if birds:
		birds.visible = birds_on
	if scare_at > 0.0 and time_alive >= scare_at and birds:
		scare_at = -1.0
		birds.uproot_near(Vector3.ZERO, 1e6, 1.0)
	if status_t > 0.0:
		status_t -= delta
	if autosave_timer > 0.0:
		autosave_timer -= delta
		if autosave_timer <= 0.0 and not fresh:
			town.save_json(AUTOSAVE)
	if ui:
		ui.tick(delta)
	if shot_path != "":
		ghost_mi.visible = false
		_shot_step()


func flash(msg: String) -> void:
	status_msg = msg
	status_t = 3.0


func _shot_step() -> void:
	shot_frames += 1
	if time_alive < shot_wait or shot_frames < 10 or time_alive < shot_next:
		return
	if shot_next <= 0.0:
		var n := 0
		for mi: MultiMeshInstance3D in prop_mi:
			if mi.multimesh != null:
				n += mi.multimesh.instance_count
		print("props on screen: %d instances of %d props, %d fps" % [n, props.kept.size() if props else 0, Engine.get_frames_per_second()])
	if shot_views.is_empty():
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("saved ", shot_path)
		shot_path = ""
		get_tree().quit(0)
		return
	if shot_next > 0.0:
		var done: Array = shot_views.pop_front()
		var p := shot_path.get_basename() + "_" + str(done[0]) + ".png"
		get_viewport().get_texture().get_image().save_png(p)
		print("saved ", p)
	if shot_views.is_empty():
		shot_path = ""
		get_tree().quit(0)
		return
	var v: Array = shot_views[0]
	cam_yaw = v[1]
	cam_pitch = v[2]
	cam_dist = v[3]
	cam_goal = v[4]
	cam_target = cam_goal
	shot_next = time_alive + 0.7


# --- input ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		last_mouse = e.position
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			cam_dist = maxf(cam_dist * 0.9, 12.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			cam_dist = minf(cam_dist * 1.1, 600.0)
		elif e.pressed:
			press[e.button_index] = {"pos": e.position, "moved": false}
		else:
			var info: Dictionary = press.get(e.button_index, {})
			press.erase(e.button_index)
			if info.is_empty() or info.moved:
				return
			if e.button_index == MOUSE_BUTTON_LEFT:
				var pk := pick(e.position)
				if build_type == CSTown.T_CASTLE:
					var a: Array = pk.get("add", [])
					if not a.is_empty():
						add_block(a[0], a[1])
				else:
					add_wild(int(pk.get("wadd", -1)))
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				var pr := pick(e.position)
				var r: Array = pr.get("remove", [])
				if not r.is_empty():
					remove_block(r[0], r[1])
				else:
					remove_wild(int(pr.get("wremove", -1)))
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		last_mouse = m.position
		for b: int in press:
			if (press[b].pos as Vector2).distance_to(m.position) > DRAG_PX:
				press[b].moved = true
		if press.has(MOUSE_BUTTON_RIGHT) and press[MOUSE_BUTTON_RIGHT].moved:
			cam_yaw -= m.relative.x * 0.006
			cam_pitch += m.relative.y * 0.005
		elif press.has(MOUSE_BUTTON_MIDDLE) or (press.has(MOUSE_BUTTON_LEFT) and press[MOUSE_BUTTON_LEFT].moved):
			var right := cam.global_transform.basis.x
			var fwd := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
			var k := cam_dist * 0.0016
			cam_goal += (-right * m.relative.x + fwd * m.relative.y) * k
			cam_target = cam_goal
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event as InputEventKey)


func _key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed
	match e.keycode:
		KEY_Z:
			if ctrl:
				if e.shift_pressed:
					redo()
				else:
					undo()
		KEY_Y:
			if ctrl:
				redo()
		KEY_S:
			if ctrl:
				save_town()
		KEY_N:
			if ctrl:
				new_town()
			else:
				look.cycle_pen()
				flash("Pen: " + look.pen_name())
				if ui:
					ui.refresh()
		KEY_I:
			look.cycle_infill()
			flash("Infill: " + look.infill_name())
			if ui:
				ui.refresh()
		KEY_B:
			toggle_birds()
		KEY_P:
			toggle_props()
		KEY_TAB:
			set_build_type(build_type + (-1 if e.shift_pressed else 1))
		KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6:
			set_build_type(e.keycode - KEY_F1)
		KEY_L:
			look.cycle_look()
			flash("Light: " + look.look_name())
			if ui:
				ui.refresh()
		KEY_G:
			look.cycle_quality()
			flash("Quality: " + look.quality_name())
			if ui:
				ui.refresh()
		KEY_F:
			frame_town(false)
		KEY_SPACE:
			spin = not spin
			if ui:
				ui.refresh()
		KEY_MINUS:
			set_colour(10)
		KEY_EQUAL:
			set_colour(11)
		_:
			if e.keycode >= KEY_0 and e.keycode <= KEY_9:
				set_colour(9 if e.keycode == KEY_0 else e.keycode - KEY_1)
