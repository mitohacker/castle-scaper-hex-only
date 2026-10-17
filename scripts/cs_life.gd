class_name CSLife
extends Node3D
## What moves round the castle besides the water: smoke rising from the chimneys, gulls soaring over the sea, a fishing boat sailing slowly
## round the island, and a puff of stone dust (or, on the water, a splash) when a block goes down or comes away. Cheap on purpose: CPU
## particles in small pools, six gulls and a boat as plain meshes moved by a few sines.

const GULLS := 6

var smoke_nodes: Array = []
var gulls: Array = []
var boat: Node3D
var t := 0.0
var soft: GradientTexture2D
var puff_pool: Array = []
var puff_next := 0


func _ready() -> void:
	soft = GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	_make_gulls()
	_make_boat()
	for i in 6:
		var p := _particles(26, 0.9, false)
		add_child(p)
		puff_pool.append(p)


func _mat(col: Color, unshaded := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft
	m.albedo_color = col
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	return m


func _particles(amount: int, life: float, loop: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = not loop
	p.emitting = false
	p.explosiveness = 0.0 if loop else 0.9
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _mat(Color(1, 1, 1, 1))
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Smoke from every chimney of the shown castle (positions = chimney tops).
func set_chimneys(tops: Array) -> void:
	for n in smoke_nodes:
		remove_child(n)
		n.free()
	smoke_nodes.clear()
	for v in tops:
		var p := _particles(14, 7.0, true)
		p.position = v
		p.direction = Vector3(0.25, 1.0, 0.1)
		p.spread = 12.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 0.9
		p.gravity = Vector3(0.35, 0.18, 0.1)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 0.8
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 3.2))
		p.scale_amount_curve = sc
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.62, 0.6, 0.58, 0.0))
		ramp.add_point(0.12, Color(0.6, 0.58, 0.56, 0.32))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.7, 0.7, 0.72, 0.0))
		p.color_ramp = ramp
		add_child(p)
		p.emitting = true
		smoke_nodes.append(p)


## A puff of dust where a block went down or came away, or a splash if it was on the water (y = the level's height).
func puff(pos: Vector3, splash: bool, count := 26) -> void:
	var p: CPUParticles3D = puff_pool[puff_next % puff_pool.size()]
	puff_next += 1
	p.emitting = false
	p.position = pos
	p.amount = count
	p.restart()
	var ramp := Gradient.new()
	if splash:
		p.direction = Vector3(0, 1, 0)
		p.spread = 35.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.5
		p.gravity = Vector3(0, -12.0, 0)
		p.lifetime = 0.9
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.5
		ramp.set_color(0, Color(0.95, 0.98, 1.0, 0.9))
		ramp.set_color(1, Color(0.95, 0.98, 1.0, 0.0))
	else:
		p.direction = Vector3(0, 0.6, 0)
		p.spread = 160.0
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.6
		p.gravity = Vector3(0, -0.6, 0)
		p.lifetime = 1.1
		p.scale_amount_min = 0.9
		p.scale_amount_max = 1.8
		ramp.set_color(0, Color(0.8, 0.74, 0.64, 0.55))
		ramp.set_color(1, Color(0.8, 0.74, 0.64, 0.0))
	p.color_ramp = ramp
	p.emitting = true


func _make_gulls() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode cull_disabled, shadows_disabled;\ninstance uniform float phase = 0.0;\nvarying float tip;\n" + \
		"void vertex() { tip = abs(VERTEX.x); VERTEX.y += tip * sin(TIME * 6.0 + phase) * 0.55 + sin(TIME * 6.0 + phase) * 0.05; }\n" + \
		"void fragment() { ALBEDO = mix(vec3(0.92, 0.93, 0.95), vec3(0.12, 0.13, 0.15), smoothstep(0.55, 0.85, tip)); ROUGHNESS = 0.8; }\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# body, a long narrow arrowhead, and two swept wings
	var pts := [[Vector3(0, 0, 0.45), Vector3(-0.08, 0, -0.35), Vector3(0.08, 0, -0.35)],
		[Vector3(0, 0, 0.1), Vector3(-1.0, 0.0, -0.2), Vector3(0, 0, -0.25)],
		[Vector3(0, 0, 0.1), Vector3(0, 0, -0.25), Vector3(1.0, 0.0, -0.2)]]
	for tri: Array in pts:
		for p: Vector3 in tri:
			st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in GULLS:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.set_instance_shader_parameter("phase", rng.randf() * TAU)
		mi.scale = Vector3.ONE * rng.randf_range(0.8, 1.2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		gulls.append({"node": mi, "r": rng.randf_range(28.0, 90.0), "h": rng.randf_range(10.0, 42.0), "w": rng.randf_range(0.1, 0.22) * (1.0 if i % 2 == 0 else -1.0),
			"a": rng.randf() * TAU, "cx": rng.randf_range(-20.0, 20.0), "cz": rng.randf_range(-20.0, 20.0), "ph": rng.randf() * TAU})


func _make_boat() -> void:
	boat = Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.2, 0.12)
	wood.roughness = 0.8
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.7, 0.62, 0.5)
	trim.roughness = 0.85
	var sail := StandardMaterial3D.new()
	sail.albedo_color = Color(0.9, 0.85, 0.74)
	sail.roughness = 0.95
	sail.cull_mode = BaseMaterial3D.CULL_DISABLED
	# the hull: stations from stern to bow, each a V of keel and two gunwale points
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stn := [[-2.3, 0.62, 0.35, 0.15], [-1.4, 0.55, 0.62, -0.1], [0.0, 0.5, 0.75, -0.28], [1.4, 0.55, 0.6, -0.12], [2.9, 0.95, 0.0, 0.2]]   # x, deck y, half beam, keel y
	var left := []
	var right := []
	var keel := []
	for s: Array in stn:
		left.append(Vector3(s[0], s[1], -s[2]))
		right.append(Vector3(s[0], s[1], s[2]))
		keel.append(Vector3(s[0], s[3], 0.0))
	for i in stn.size() - 1:
		for side in [left, right]:
			var a: Vector3 = side[i]
			var b: Vector3 = side[i + 1]
			var ka: Vector3 = keel[i]
			var kb: Vector3 = keel[i + 1]
			st.add_vertex(a)
			st.add_vertex(ka)
			st.add_vertex(kb)
			st.add_vertex(a)
			st.add_vertex(kb)
			st.add_vertex(b)
	st.generate_normals()
	var hull := MeshInstance3D.new()
	hull.mesh = st.commit()
	hull.material_override = wood
	var rig := Node3D.new()   # the hull is modelled along +x; the rig turns the bow to -z, where look_at points
	rig.rotation.y = PI / 2.0
	boat.add_child(rig)
	rig.add_child(hull)
	var deck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.4, 0.06, 1.3)
	deck.mesh = bm
	deck.material_override = trim
	deck.position = Vector3(0.2, 0.55, 0.0)
	rig.add_child(deck)
	var mast := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 6.0
	mast.mesh = cm
	mast.material_override = wood
	mast.position = Vector3(0.3, 3.5, 0.0)
	rig.add_child(mast)
	var sm := ArrayMesh.new()
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [Vector3(0.35, 0.9, 0.0), Vector3(0.35, 6.2, 0.0), Vector3(-2.0, 1.1, 0.0), Vector3(0.35, 0.9, 0.0), Vector3(0.35, 5.2, 0.05), Vector3(2.4, 1.0, 0.1)]:
		sst.add_vertex(p)
	sst.generate_normals()
	var sl := MeshInstance3D.new()
	sl.mesh = sst.commit()
	sl.material_override = sail
	rig.add_child(sl)
	boat.scale = Vector3.ONE * 1.1
	add_child(boat)


func _process(delta: float) -> void:
	t += delta
	for g: Dictionary in gulls:
		var a: float = float(g.a) + t * float(g.w)
		var n: Node3D = g.node
		var r: float = g.r
		var pos := Vector3(float(g.cx) + cos(a) * r, float(g.h) + sin(t * 0.7 + float(g.ph)) * 2.0, float(g.cz) + sin(a) * r)
		var vel := Vector3(-sin(a) * signf(float(g.w)), 0.0, cos(a) * signf(float(g.w)))
		n.position = pos
		n.look_at(pos + vel, Vector3.UP)
		n.rotate_object_local(Vector3.FORWARD, -signf(float(g.w)) * 0.35)
	# the boat sails round the island, a long way out, bobbing and rolling a little
	var ba := t * 0.035
	var br := 58.0
	var bp := Vector3(cos(ba) * br, 0.0, sin(ba) * br)
	var tangent := Vector3(-sin(ba), 0.0, cos(ba))
	boat.position = bp + Vector3(0.0, 0.05 + 0.12 * sin(t * 1.1), 0.0)
	boat.look_at(boat.position + tangent, Vector3.UP)
	boat.rotate_object_local(Vector3.RIGHT, 0.0)
	boat.rotate_object_local(Vector3.FORWARD, 0.07 * sin(t * 0.9) + 0.1)
	boat.rotate_object_local(Vector3.RIGHT, 0.05 * sin(t * 1.3 + 1.0))
