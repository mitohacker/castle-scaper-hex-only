class_name CFBirds
extends Node3D
## (Castle Scaper: copied from Castle Forge; landings_from takes the built mesh.)
## Birds that perch on the castle, circle it in a flock and take off when you build next to them: Townscaper's
## BirdFlock re-made in code (rules and constants read from Townscaper's own code with REA + Ghidra, see
## townscaper-re/notes/mesh_life_props.md, B1-B8; distances scaled from Townscaper units to metres by U).
##
## - Landings are a by-product of the build (landings_from): merlon and parapet tops that nothing rises above,
##   and the tips of the roofs. A coarse height field of the castle stands in for Townscaper's density field.
## - How many: f = clamp(sqrt(landings) - 6, 0, 64); keep between round(0.9 f - 2) and round(1.1 f + 2).
## - Every bird decides on its own 0.3 s tick; between ticks it moves along a quadratic B-spline through the
##   segment midpoints (smooth flight from coarse decisions). Seven poses are static meshes made in code
##   (sit, half sit, stand, land, flap, fly, glide); a pose change cross-fades by scale (1 - t^3 / 1 - (1-t)^3).
## - Flying birds steer to one shared orbit point (a new one every 8-20 s) with boids; after 8 s they look for a
##   landing ahead (a 37 degree cone, next to other birds preferred), approach, touch down and perch, fidget
##   every ~3 s (turn, change pose, hop to a better spot). An edit near them uproots them; a perch that is
##   rebuilt away uproots its bird.

const U := 2.5                      # metres per Townscaper unit (a Townscaper house cell is about 2.5 m of castle)
const TICK := 0.3
const SIZE := 1.6                   # bird scale (a body about 1 m long: oversized like Townscaper's, to read at castle scale)
const MAX_BIRDS := 48
const DENSITY := 2.0                # Townscaper counts a perch every half unit of ridge and railing; merlons are sparser
enum { P_SIT, P_HALF, P_STAND, P_LAND, P_FLAP, P_FLY, P_GLIDE }
enum { S_FLY, S_APPROACH, S_TOUCH, S_PERCH, S_LEAVE }
const POSE_COUNT := 7

class Bird:
	var mid := Vector3.ZERO         # control point of the spline (the position at the tick)
	var vprev := Vector3.ZERO       # last tick's step
	var vnext := Vector3.ZERO       # this tick's step
	var rot0 := Quaternion.IDENTITY
	var rot1 := Quaternion.IDENTITY
	var t := 0.0                    # start of the current tick
	var pose0 := 0
	var pose1 := 0
	var state := 0
	var landing := -1
	var last_action := 0.0
	var chosen := 0.0               # when the landing was picked
	var scale := 1.0

var enabled := true
var rng := RandomNumberGenerator.new()
var now := 0.0
var birds: Array[Bird] = []

var l_pos := PackedVector3Array()   # where a bird sits
var l_out := PackedVector3Array()   # the way a perched bird faces (out of the castle, horizontal)
var l_flat := PackedByteArray()
var l_bird := PackedInt32Array()
var l_nb := PackedInt32Array()      # perched birds within 1.1 U
var l_hash := {}                    # Vector3i cell (2 U) -> [landing ids]

var heights := {}                   # Vector2i (2 m cells) -> top of the castle there
var box := AABB()                   # castle bounds (for the orbit)
var centre := Vector3.ZERO
var top := 10.0
var orbit_pos := Vector3(0, 20, 0)
var orbit_target := Vector3(0, 20, 0)
var next_orbit := 0.0
var lo_count := 0
var hi_count := 0
var ideal_count := 0

var _mm: Array[MultiMeshInstance3D] = []
var _shade: MultiMeshInstance3D


func _init() -> void:
	rng.seed = 1234


func bird_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true      # the colours below are picked as sRGB (charcoal stays charcoal)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _ready() -> void:
	var mat := bird_material()
	for p in POSE_COUNT:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = make_pose_mesh(p)
		mm.instance_count = MAX_BIRDS * 2
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_mm.append(mmi)
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\n" + \
		"void fragment() { float r = length(UV * 2.0 - 1.0); ALBEDO = vec3(0.02, 0.02, 0.03); ALPHA = 0.38 * (1.0 - smoothstep(0.35, 1.0, r)); }\n"
	var smat := ShaderMaterial.new()
	smat.shader = sh
	var quad := PlaneMesh.new()
	quad.size = Vector2(1, 1)
	_shade = MultiMeshInstance3D.new()
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = quad
	smm.instance_count = MAX_BIRDS
	smm.visible_instance_count = 0
	_shade.multimesh = smm
	_shade.material_override = smat
	_shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shade)


# --- landings from the built castle ---------------------------------------------------------------

static func landings_from(m: CFMesh) -> Dictionary:
	## Where birds can sit, from the castle's own mesh (call it on the build thread): up-facing stone faces 3 m or more
	## above the ground that nothing rises above (merlon and parapet tops, tower tops), one per 0.5 m, and the highest
	## point of every roof. Also a 2 m height field of the whole castle (birds steer clear of it).
	var vs := m.verts
	var ns := m.norms
	var cs := m.cols
	var cust := m.cust1
	var hf := {}
	var tops := {}                  # Vector3i (0.5 m cells) -> [pos, normal]
	var roof_tip := {}              # owner -> highest roof / finial vertex
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in range(0, vs.size(), 3):
		var a := vs[i]
		var b := vs[i + 1]
		var cc := vs[i + 2]
		var ymax := maxf(a.y, maxf(b.y, cc.y))
		lo = Vector3(minf(lo.x, minf(a.x, minf(b.x, cc.x))), 0.0, minf(lo.z, minf(a.z, minf(b.z, cc.z))))
		hi = Vector3(maxf(hi.x, maxf(a.x, maxf(b.x, cc.x))), maxf(hi.y, ymax), maxf(hi.z, maxf(a.z, maxf(b.z, cc.z))))
		# the height field: every 2 m cell a triangle's box touches gets its top
		var x0 := floori(minf(a.x, minf(b.x, cc.x)) / 2.0)
		var x1 := floori(maxf(a.x, maxf(b.x, cc.x)) / 2.0)
		var z0 := floori(minf(a.z, minf(b.z, cc.z)) / 2.0)
		var z1 := floori(maxf(a.z, maxf(b.z, cc.z)) / 2.0)
		if (x1 - x0 + 1) * (z1 - z0 + 1) <= 400:
			for gx in range(x0, x1 + 1):
				for gz in range(z0, z1 + 1):
					var k := Vector2i(gx, gz)
					if ymax > float(hf.get(k, -1.0)):
						hf[k] = ymax
		var zone := int(cs[i].r * 255.0 + 0.5)
		var n := (ns[i] + ns[i + 1] + ns[i + 2]).normalized()
		if zone in [CFMesh.Z_SLATE, CFMesh.Z_TILE, CFMesh.Z_THATCH, CFMesh.Z_GOLD, CFMesh.Z_IRON] or (zone > CSStyle.ROOF and zone <= CSStyle.ROOF + 6):
			var own := int(cust[i * 4 + 3])
			for v in [a, b, cc]:
				if not roof_tip.has(own) or v.y > (roof_tip[own] as Vector3).y:
					roof_tip[own] = v
			continue
		if (zone != CFMesh.Z_STONE and zone != CFMesh.Z_FLAG) or n.y < 0.95:
			continue
		var cen := (a + b + cc) / 3.0
		if cen.y < 3.0 or (b - a).cross(cc - a).length() * 0.5 > 2.0:
			continue
		var key := Vector3i(floori(cen.x / 0.5), roundi(cen.y / 0.25), floori(cen.z / 0.5))
		if not tops.has(key):
			tops[key] = cen
	var pos := PackedVector3Array()
	var flat := PackedByteArray()
	for key in tops:
		var p: Vector3 = tops[key]
		var hk := Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))
		# nothing may rise above it nearby (that is a floor under something, or the foot of a taller wall)
		var free := true
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var hh := float(hf.get(Vector2i(hk.x + dx, hk.y + dz), -1.0))
				if hh > p.y + (0.5 if dx == 0 and dz == 0 else 3.0):
					free = false
		if free:
			pos.append(p)
			flat.append(1)
	for own in roof_tip:
		pos.append(roof_tip[own])
		flat.append(0)
	return {"pos": pos, "flat": flat, "heights": hf, "box": AABB(lo, hi - lo)}


func set_landings(d: Dictionary) -> void:
	## A new castle: perched birds whose spot still exists keep it, the others take off.
	var old_pos := l_pos
	var pos: PackedVector3Array = d.get("pos", PackedVector3Array())
	l_pos = pos
	l_flat = d.get("flat", PackedByteArray())
	heights = d.get("heights", {})
	box = d.get("box", AABB())
	centre = box.get_center()
	centre.y = 0.0
	top = maxf(box.end.y, 6.0)
	l_out.resize(pos.size())
	l_bird.resize(pos.size())
	l_bird.fill(-1)
	l_nb.resize(pos.size())
	l_nb.fill(0)
	l_hash.clear()
	for i in pos.size():
		var o := pos[i] - centre
		o.y = 0.0
		l_out[i] = o.normalized() if o.length() > 0.1 else Vector3.BACK
		var hk := _hkey(pos[i])
		if not l_hash.has(hk):
			l_hash[hk] = []
		(l_hash[hk] as Array).append(i)
	for bi in birds.size():
		var b := birds[bi]
		if b.landing < 0:
			continue
		var was := old_pos[b.landing] if b.landing < old_pos.size() else Vector3.INF
		b.landing = -1
		var best := _nearest_landing(was, 0.15)
		if best >= 0 and l_bird[best] < 0:
			b.landing = best
			l_bird[best] = bi
		elif b.state == S_PERCH or b.state == S_TOUCH:
			_uproot(b, Vector3.UP, 1.0)
	for bi in birds.size():
		if birds[bi].landing >= 0 and (birds[bi].state == S_PERCH or birds[bi].state == S_TOUCH):
			_neighbours_changed(birds[bi].landing)
	var f := clampf(sqrt(float(pos.size()) * DENSITY) - 6.0, 0.0, 64.0)
	ideal_count = mini(int(f), MAX_BIRDS)
	lo_count = mini(roundi(maxf(0.0, 0.9 * f - 2.0)), MAX_BIRDS)
	hi_count = mini(roundi(maxf(0.0, 1.1 * f + 2.0)), MAX_BIRDS)


func _hkey(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / (2.0 * U)), floori(p.y / (2.0 * U)), floori(p.z / (2.0 * U)))


func _landings_near(p: Vector3, r: float) -> Array:
	var out := []
	var k := _hkey(p)
	var reach := int(ceil(r / (2.0 * U)))
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				for i: int in l_hash.get(Vector3i(k.x + dx, k.y + dy, k.z + dz), []):
					if l_pos[i].distance_to(p) <= r:
						out.append(i)
	return out


func _nearest_landing(p: Vector3, r: float) -> int:
	var best := -1
	var bd := r
	for i: int in _landings_near(p, r):
		var d := l_pos[i].distance_to(p)
		if d <= bd:
			bd = d
			best = i
	return best


func _neighbours_changed(li: int) -> void:
	for j: int in _landings_near(l_pos[li], 1.2 * U):
		var c := 0
		for k: int in _landings_near(l_pos[j], 1.1 * U):
			if k != j and l_bird[k] >= 0 and birds[l_bird[k]].state == S_PERCH:
				c += 1
		l_nb[j] = c


# --- the flock ------------------------------------------------------------------------------------

func active_count() -> int:
	var n := 0
	for b in birds:
		if b.state != S_LEAVE:
			n += 1
	return n


func perched_count() -> int:
	var n := 0
	for b in birds:
		if b.state == S_PERCH or b.state == S_TOUCH:
			n += 1
	return n


func step(dt: float) -> void:
	## Advances the flock by dt seconds (the editor calls it every frame; tests call it with a fixed step).
	now += dt
	if l_pos.is_empty():
		for b in birds:
			if b.state != S_LEAVE:
				b.state = S_LEAVE
	else:
		_population()
		_orbit(dt)
	for bi in birds.size():
		var b := birds[bi]
		var guard := 0
		while now >= b.t + TICK and guard < 4:
			guard += 1
			b.t += TICK
			_tick(bi, b)
	# birds that left are gone once they are far away
	var keep: Array[Bird] = []
	var remap := {}
	for bi in birds.size():
		var b := birds[bi]
		if b.state == S_LEAVE and Vector2(b.mid.x - centre.x, b.mid.z - centre.z).length() > box.size.length() + 60.0:
			if b.landing >= 0:
				l_bird[b.landing] = -1
			continue
		remap[bi] = keep.size()
		keep.append(b)
	if keep.size() != birds.size():
		birds = keep
		for i in l_bird.size():
			if l_bird[i] >= 0:
				l_bird[i] = remap.get(l_bird[i], -1)


func _population() -> void:
	var act := active_count()
	if act < lo_count:
		var leaving := false
		for b in birds:
			if b.state == S_LEAVE and act < ideal_count:
				b.state = S_FLY        # called back
				act += 1
				leaving = true
		if not leaving and birds.size() < MAX_BIRDS:
			_spawn_cluster()
	elif act > hi_count:
		for b in birds:
			if b.state == S_FLY:
				b.state = S_LEAVE
				break


func _spawn_cluster() -> void:
	## Birds appear already perched, a few together (Townscaper: a random landing and the free ones within 0.2-0.6 U).
	var r := rng.randf_range(0.2, 0.6) * U
	var start := -1
	for _try in 100:
		var i := rng.randi_range(0, l_pos.size() - 1)
		if l_bird[i] < 0:
			start = i
			break
	if start < 0:
		return
	for li: int in _landings_near(l_pos[start], r):
		if l_bird[li] >= 0 or active_count() >= hi_count or birds.size() >= MAX_BIRDS:
			continue
		var b := Bird.new()
		b.scale = rng.randf_range(0.8, 1.2)
		b.t = now - fmod(float(birds.size()) / PI, TICK)      # an irrational stagger of the 0.3 s phases
		b.state = S_TOUCH
		b.landing = li
		b.mid = l_pos[li]
		b.last_action = now + rng.randf_range(3.0, 25.0) - 3.0
		var pose := P_LAND if rng.randf() < 0.1 else (P_SIT if rng.randf() < 0.5 else P_HALF)
		b.pose0 = pose
		b.pose1 = pose
		b.rot0 = _perch_rot(li, rng.randf_range(-20.0, 20.0))
		b.rot1 = b.rot0
		l_bird[li] = birds.size()
		birds.append(b)
		_neighbours_changed(li)


func _orbit(dt: float) -> void:
	if now >= next_orbit:
		next_orbit = now + float(rng.randi_range(8, 20))
		if rng.randf() < 0.5 and not l_pos.is_empty():
			var li := rng.randi_range(0, l_pos.size() - 1)
			orbit_target = l_pos[li] + l_out[li] * 0.3 * U
		else:
			orbit_target = Vector3(rng.randf_range(box.position.x - 8.0 * U, box.end.x + 8.0 * U), rng.randf_range(0.0, top + 6.0),
				rng.randf_range(box.position.z - 8.0 * U, box.end.z + 8.0 * U))
		var s := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0)
		orbit_target += s * rng.randf_range(0.0, 7.0) * U
		orbit_target.y = maxf(orbit_target.y, maxf(0.4 * U, _height_at(orbit_target) + 3.0))
	orbit_pos = orbit_pos.move_toward(orbit_target, 10.0 * U * dt)


func _height_at(p: Vector3) -> float:
	return float(heights.get(Vector2i(floori(p.x / 2.0), floori(p.z / 2.0)), 0.0))


func _perch_rot(li: int, yaw_deg: float) -> Quaternion:
	var f := l_out[li].rotated(Vector3.UP, deg_to_rad(yaw_deg))
	return Basis.looking_at(f, Vector3.UP).get_rotation_quaternion()


func _tick(bi: int, b: Bird) -> void:
	# advance the spline: the old next step becomes the previous one
	b.mid += b.vnext
	b.vprev = b.vnext
	b.rot0 = b.rot1
	b.pose0 = b.pose1
	match b.state:
		S_FLY, S_LEAVE:
			_fly(bi, b)
		S_APPROACH:
			_approach(bi, b)
		S_TOUCH:
			b.vnext = Vector3.ZERO
			if b.landing >= 0:
				b.vnext = l_pos[b.landing] - b.mid
				b.rot1 = _perch_rot(b.landing, rng.randf_range(-20.0, 20.0))
			b.pose1 = P_HALF if b.pose0 == P_LAND else b.pose0
			b.state = S_PERCH
			if b.landing >= 0:
				_neighbours_changed(b.landing)
		S_PERCH:
			_perch(bi, b)


func _fly(bi: int, b: Bird) -> void:
	var v := b.vnext
	v.y *= 0.7
	var desired: Vector3
	if b.state == S_LEAVE:
		desired = Vector3(b.vprev.x, 0.0, b.vprev.z)
		if desired.length() < 0.01:
			desired = (b.mid - centre) * Vector3(1, 0, 1)
	else:
		desired = orbit_pos - b.mid
	if desired.length() > 0.001:
		v = v.lerp(desired.normalized() * U, 0.2)
	v = v.normalized() * U if v.length() > 0.001 else Vector3(U, 0, 0)
	v += _boids(bi, b, v)
	# steer clear of the castle: probe along twice the step
	for k in range(1, 4):
		var q := b.mid + v * 2.0 * float(k) / 3.0
		var h := _height_at(q) + 1.5
		if q.y < h:
			var c := clampf((h - q.y) / (2.0 * U), 0.0, 1.0)
			var gx := _height_at(q + Vector3(-2, 0, 0)) - _height_at(q + Vector3(2, 0, 0))
			var gz := _height_at(q + Vector3(0, 0, -2)) - _height_at(q + Vector3(0, 0, 2))
			v += Vector3(gx * 0.25, 2.0, gz * 0.25).normalized() * 2.0 * c * U
			break
	if b.mid.y + v.y < 1.0:
		v.y = maxf(v.y, 1.0 - b.mid.y)
	# look for a landing after 8 s of flight
	if b.state == S_FLY:
		if b.landing < 0 and now - b.last_action > 8.0:
			var li := _get_landing(b, v)
			if li >= 0:
				b.landing = li
				l_bird[li] = bi
				b.chosen = now
		if b.landing >= 0:
			var target := l_pos[b.landing] + l_out[b.landing] * 0.3 * U + Vector3(0, 0.3 * U, 0)
			var t := clampf(inverse_lerp(6.0, 9.0, now - b.chosen), 0.0, 1.0)
			v = v.lerp((target - b.mid).normalized() * 2.0 * U, lerpf(0.1, 0.8, t))
			if b.mid.distance_to(target) < 1.5 * U:
				b.state = S_APPROACH
			elif now - b.chosen > 9.0:
				l_bird[b.landing] = -1
				b.landing = -1
				b.last_action = now
	b.vnext = v
	_flight_pose(b)


func _approach(bi: int, b: Bird) -> void:
	if b.landing < 0:
		b.state = S_FLY
		_fly(bi, b)
		return
	var lp := l_pos[b.landing]
	var target := lp + l_out[b.landing] * 0.3 * U + Vector3(0, 0.3 * U, 0)
	var d := lp.distance_to(b.mid)
	var perch := _perch_rot(b.landing, 0.0)
	if d < 0.3 * U:
		b.vnext = lp - b.mid
		b.rot1 = b.rot0.slerp(perch, 0.3)
		b.state = S_TOUCH
		b.pose1 = P_LAND
		return
	var aim := lp.lerp(target, clampf(d / U + 0.1, 0.0, 1.0))
	b.vnext = b.vnext.move_toward((aim - b.mid).limit_length(0.7 * U), 0.8 * U)
	var look := b.vnext if b.vnext.length() > 0.01 else l_out[b.landing]
	var up := (b.vnext - b.vprev) + Vector3(0, 0.5 * U, 0)
	b.rot1 = _look(look, up, b.rot0).slerp(perch, 0.1)
	b.pose1 = P_LAND


func _perch(bi: int, b: Bird) -> void:
	b.vnext = Vector3.ZERO
	if b.landing < 0:
		_uproot(b, Vector3.UP, 1.0)
		return
	if now - b.last_action <= 3.0:
		return
	b.last_action = now
	var flat := l_flat[b.landing] == 1
	var r := rng.randf()
	if r < 0.1:
		# hop to a better spot close by (next to more birds)
		var best := -1
		var best_s := 0.3 * float(l_nb[b.landing]) + 0.2 * rng.randf()
		for li: int in _landings_near(l_pos[b.landing], 0.8 * U):
			if l_bird[li] >= 0:
				continue
			var d := l_pos[li].distance_to(l_pos[b.landing]) / U
			var s := 0.3 * float(l_nb[li]) - d * d + 0.2 * rng.randf()
			if s > best_s:
				best_s = s
				best = li
		if best >= 0:
			var old := b.landing
			l_bird[old] = -1
			l_bird[best] = bi
			b.landing = best
			b.vnext = l_pos[best] - b.mid
			b.pose1 = P_LAND
			b.state = S_TOUCH
			_neighbours_changed(old)
			return
	if r < 0.4:
		b.pose1 = (P_SIT if rng.randf() < 0.5 else P_STAND) if flat else (P_SIT if rng.randf() < 0.5 else P_HALF)
	else:
		b.rot1 = _perch_rot(b.landing, rng.randf_range(-40.0, 40.0) if flat else rng.randf_range(-20.0, 20.0))


func _flight_pose(b: Bird) -> void:
	var x := ((b.vnext - b.vprev) + Vector3(0, 0.5 * U, 0)).length() / U - b.vnext.length() / U + 0.2
	b.pose1 = P_FLY if x <= 0.6 else P_FLAP
	var look := b.vnext
	look.y *= clampf(inverse_lerp(1.0, 0.7, x), 0.0, 1.0)
	b.rot1 = _look(look, (b.vnext - b.vprev) + Vector3(0, 0.5 * U, 0), b.rot1)


func _look(dir: Vector3, up: Vector3, keep: Quaternion) -> Quaternion:
	## A rotation facing dir with up as near to `up` as it can be (banking); `keep` when dir is too short or vertical.
	if dir.length() < 0.01:
		return keep
	var d := dir.normalized()
	if absf(d.y) > 0.97:
		return keep
	var u := up.normalized() if up.length() > 0.01 else Vector3.UP
	if absf(d.dot(u)) > 0.97:
		u = Vector3.UP
	return Basis.looking_at(d, u).get_rotation_quaternion()


func _boids(bi: int, b: Bird, v: Vector3) -> Vector3:
	var acc := Vector3.ZERO
	var wsum := 0.0
	var n := 0
	for oj in birds.size():
		if oj == bi:
			continue
		var o := birds[oj]
		if o.state != S_FLY and o.state != S_LEAVE:
			continue
		var d := o.mid.distance_to(b.mid)
		if d >= 2.0 * U or d < 0.001:
			continue
		var k := 1.0 - d / (4.0 * U)
		var dir := (o.mid - b.mid) / d
		acc += -dir * (k - 0.6) * k * k * k * U
		acc += (o.vnext - v) * k * k * k
		wsum += k * k
		n += 1
		if n >= 7:
			break
	return acc / wsum if wsum > 0.0 else Vector3.ZERO


func _get_landing(b: Bird, v: Vector3) -> int:
	var best := -1
	var best_s := -INF
	var ahead := b.mid + v
	var vd := v.normalized()
	for li: int in _landings_near(ahead, 1.0 * U * 2.0):
		if l_bird[li] >= 0:
			continue
		var to := (l_pos[li] - b.mid)
		if to.length() < 0.001:
			continue
		var dt := vd.dot(to.normalized())
		if dt < 0.8:
			continue
		var s := dt + 0.1 * float(l_nb[li])
		if s > best_s:
			best_s = s
			best = li
	return best


func _uproot(b: Bird, nrm: Vector3, strength: float) -> void:
	## Off it goes: along the perch's normal plus a random push (Townscaper: (normal + insideUnitSphere * 0.5) * strength).
	var cur := _pos_of(b)
	var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0)
	var v := (nrm + rnd * 0.5).normalized() * U * maxf(strength, 0.3)
	v.y = absf(v.y) + 0.3 * U
	if b.landing >= 0:
		var old := b.landing
		l_bird[old] = -1
		b.landing = -1
		_neighbours_changed(old)
	# keep the curve going from where the bird is drawn now
	b.vprev = Vector3.ZERO
	b.vnext = v
	b.mid = cur
	b.t = now
	b.rot0 = _rot_of(b)
	b.state = S_FLY
	b.pose1 = P_FLAP
	b.last_action = now


func uproot_near(p: Vector3, radius: float, strength: float = 1.0) -> int:
	## Birds perched within radius of p take off (an edit or a click there). Returns how many.
	var n := 0
	for b in birds:
		if (b.state == S_PERCH or b.state == S_TOUCH) and _pos_of(b).distance_to(p) <= radius:
			var nrm := l_out[b.landing] + Vector3.UP if b.landing >= 0 else Vector3.UP
			_uproot(b, nrm.normalized(), strength)
			n += 1
	return n


func clear() -> void:
	birds.clear()
	l_bird.fill(-1)
	l_nb.fill(0)


# --- drawing --------------------------------------------------------------------------------------

func _phase(b: Bird) -> float:
	return clampf((now - b.t) / TICK, 0.0, 1.0)


func _pos_of(b: Bird) -> Vector3:
	var t := _phase(b)
	var p0 := b.mid - b.vprev * 0.5
	var p2 := b.mid + b.vnext * 0.5
	return p0 * (1.0 - t) * (1.0 - t) + b.mid * 2.0 * t * (1.0 - t) + p2 * t * t


func _rot_of(b: Bird) -> Quaternion:
	return b.rot0.slerp(b.rot1, _phase(b))


func _process(delta: float) -> void:
	if not enabled or not visible:
		return
	step(minf(delta, 0.1))
	draw()


func draw() -> void:
	var counts := PackedInt32Array()
	counts.resize(POSE_COUNT)
	counts.fill(0)
	var nshade := 0
	for b in birds:
		var t := _phase(b)
		var p := _pos_of(b)
		var basis := Basis(_rot_of(b)).scaled(Vector3.ONE * b.scale * SIZE)
		if b.pose0 == b.pose1:
			_put(b.pose1, Transform3D(basis, p), counts)
		else:
			_put(b.pose0, Transform3D(basis * (1.0 - t * t * t), p), counts)
			_put(b.pose1, Transform3D(basis * (1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)), p), counts)
		if (b.state == S_PERCH or b.state == S_TOUCH) and nshade < MAX_BIRDS:
			var s := 0.55 * b.scale * SIZE * (0.7 if b.pose1 == P_STAND else 1.0)
			_shade.multimesh.set_instance_transform(nshade, Transform3D(Basis().scaled(Vector3(s, 1, s)), p + Vector3(0, 0.03, 0)))
			nshade += 1
	for k in POSE_COUNT:
		_mm[k].multimesh.visible_instance_count = counts[k]
	_shade.multimesh.visible_instance_count = nshade


func _put(pose: int, xf: Transform3D, counts: PackedInt32Array) -> void:
	if counts[pose] >= MAX_BIRDS * 2:
		return
	_mm[pose].multimesh.set_instance_transform(counts[pose], xf)
	counts[pose] += 1


# --- the bird, made in code ----------------------------------------------------------------------

static func make_pose_mesh(pose: int) -> ArrayMesh:
	## A small jackdaw (grey nape, charcoal body) facing -Z, feet at y = 0, about 0.6 m long before SIZE.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift: float = {P_SIT: 0.035, P_HALF: 0.06, P_STAND: 0.13, P_LAND: 0.11, P_FLAP: 0.0, P_FLY: 0.0, P_GLIDE: 0.0}[pose]
	var dark := Color(0.13, 0.13, 0.15)
	var grey := Color(0.42, 0.42, 0.46)
	var beak := Color(0.05, 0.05, 0.05)
	# body: diamond sections lofted from beak to tail
	var secs := [
		[-0.30, 0.0, 0.050, 0.040, beak], [-0.24, 0.035, 0.090, 0.010, beak], [-0.20, 0.050, 0.110, 0.0, grey],
		[-0.13, 0.058, 0.090, -0.030, grey], [-0.05, 0.080, 0.090, -0.070, dark], [0.07, 0.070, 0.085, -0.050, dark],
		[0.15, 0.040, 0.055, -0.010, dark], [0.31, 0.065, 0.040, 0.025, dark]]
	var rings := []
	for s: Array in secs:
		var z: float = s[0]
		var w: float = s[1]
		var t: float = s[2]
		var bo: float = s[3]
		var mid := (t + bo) * 0.5
		rings.append([Vector3(0, t + lift, z), Vector3(w, mid + lift, z), Vector3(0, bo + lift, z), Vector3(-w, mid + lift, z), s[4]])
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in 4:
			_quad(st, a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k], b[4])
	var tail: Array = rings[rings.size() - 1]
	_tri(st, tail[0], tail[1], tail[2], dark)
	_tri(st, tail[0], tail[2], tail[3], dark)
	# eyes: two light dots on the grey head
	for sd in [-1.0, 1.0]:
		var e := Vector3(0.047 * sd, 0.082 + lift, -0.205)
		_tri(st, e + Vector3(0, 0.012, 0), e + Vector3(0, -0.008, -0.012), e + Vector3(0, -0.008, 0.012), Color(0.85, 0.85, 0.8))
	# wings
	var wings: Array = {
		P_SIT: [Vector3(0.07, 0.07, -0.06), Vector3(0.078, 0.075, 0.06), Vector3(0.05, 0.06, 0.25), Vector3(0.03, 0.08, 0.10)],
		P_HALF: [Vector3(0.07, 0.07, -0.06), Vector3(0.08, 0.075, 0.06), Vector3(0.055, 0.06, 0.25), Vector3(0.03, 0.08, 0.10)],
		P_STAND: [Vector3(0.07, 0.07, -0.06), Vector3(0.08, 0.075, 0.06), Vector3(0.055, 0.06, 0.25), Vector3(0.03, 0.08, 0.10)],
		P_LAND: [Vector3(0.07, 0.08, -0.06), Vector3(0.24, 0.20, -0.14), Vector3(0.34, 0.36, -0.06), Vector3(0.12, 0.12, 0.08)],
		P_FLAP: [Vector3(0.07, 0.08, -0.06), Vector3(0.24, 0.22, -0.03), Vector3(0.36, 0.42, 0.06), Vector3(0.14, 0.14, 0.10)],
		P_FLY: [Vector3(0.07, 0.07, -0.06), Vector3(0.28, 0.08, -0.03), Vector3(0.50, 0.06, 0.06), Vector3(0.20, 0.07, 0.13)],
		P_GLIDE: [Vector3(0.07, 0.07, -0.06), Vector3(0.28, 0.04, -0.02), Vector3(0.50, -0.01, 0.07), Vector3(0.20, 0.03, 0.13)]}[pose]
	for sd in [-1.0, 1.0]:
		var m := Vector3(sd, 1, 1)
		var q: Array = []
		for p: Vector3 in wings:
			q.append(p * m + Vector3(0, lift, 0))
		var root_back := Vector3(0.05 * sd, 0.075 + lift, 0.09)
		_tri(st, q[0], q[1], q[3], dark)
		_tri(st, q[1], q[2], q[3], dark.lightened(0.08))
		_tri(st, q[0], q[3], root_back, dark)
	# legs (standing and landing birds show them)
	if pose in [P_STAND, P_LAND, P_HALF]:
		for sd in [-1.0, 1.0]:
			var top := Vector3(0.025 * sd, lift - 0.03, 0.0)
			var foot := Vector3(0.03 * sd, 0.0 if pose != P_LAND else 0.02, -0.03 if pose != P_LAND else -0.07)
			_quad(st, top, top + Vector3(0.008, 0, 0), foot + Vector3(0.008, 0, 0), foot, beak)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for p in [a, c, b]:              # clockwise from outside: Godot's front faces
		st.set_color(col)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)
