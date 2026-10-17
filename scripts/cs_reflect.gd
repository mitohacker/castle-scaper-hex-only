class_name CSReflect
extends Node
## The castle's reflection in the sea. A second camera, the main camera mirrored in the water plane (y = 0), draws the castle, its rocks
## and props into a transparent half-resolution SubViewport (the sea and the sea floor sit on render layer 2 and are not drawn);
## cs_sea.gdshader lays that picture on the water by Fresnel, shaken by the wave normals. The sky's own reflection stays the engine's.
## Costs one more draw of a small scene at a quarter of the pixels (and its sun shadows), so only High and Ultra have it.

var vp: SubViewport
var cam: Camera3D
var env: Environment
var main_cam: Camera3D
var sea_mat: ShaderMaterial
var scale := 0.5
var on := true
var _tick := 0


func setup(p_main_cam: Camera3D, p_sea_mat: ShaderMaterial, p_world_env: Environment) -> void:
	main_cam = p_main_cam
	sea_mat = p_sea_mat
	vp = SubViewport.new()
	vp.name = "ReflectionViewport"
	vp.transparent_bg = true
	vp.size = Vector2i(960, 540)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.gui_disable_input = true
	vp.handle_input_locally = false
	add_child(vp)
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.sky = p_world_env.sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam = Camera3D.new()
	cam.name = "MirrorCamera"
	cam.cull_mask = 1            # layer 2 (the sea, the sea floor, the grid) stays out
	cam.environment = env
	cam.near = main_cam.near
	cam.far = main_cam.far
	vp.add_child(cam)
	cam.make_current()
	sea_mat.set_shader_parameter("refl_tex", vp.get_texture())


## Follows the look: the same ambient and exposure as the main picture; scale 0 turns the reflection off.
func configure(p_scale: float, p_env: Environment) -> void:
	on = p_scale > 0.01
	scale = clampf(p_scale, 0.25, 1.0)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	env.ambient_light_color = p_env.ambient_light_color
	env.ambient_light_sky_contribution = p_env.ambient_light_sky_contribution
	env.ambient_light_energy = p_env.ambient_light_energy
	env.tonemap_exposure = p_env.tonemap_exposure
	sea_mat.set_shader_parameter("refl_on", 1.0 if on else 0.0)


func _process(_delta: float) -> void:
	if not on or main_cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(int(vs.x * scale), 64), maxi(int(vs.y * scale), 64))
	if vp.size != want:
		vp.size = want
	cam.fov = main_cam.fov
	var t := main_cam.global_transform
	var f := -t.basis.z
	var p := t.origin
	var from := Vector3(p.x, -p.y, p.z)
	var dir := Vector3(f.x, -f.y, f.z)
	if absf(dir.y) > 0.999:
		dir = (dir + Vector3(0.001, 0.0, 0.0)).normalized()
	cam.look_at_from_position(from, from + dir, Vector3.UP)
	# every other frame is enough: the water moves the picture anyway
	_tick += 1
	if _tick % 2 == 0:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
