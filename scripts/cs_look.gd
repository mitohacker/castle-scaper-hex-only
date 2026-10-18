class_name CSLook
extends Node
## How the castle LOOKS and what that costs. Two independent choices, both kept in user://castle_scaper_realistic.cfg:
##
##   the light      Golden hour / Overcast / Bright noon: the sun's height and colour, the sky, the haze, the colour grade, the sea's
##                  water, how wet and mossy the stone is. Each is fitted to a mock-up of round 1 in castle-scaper-realistic-art
##                  (tripo image gen repaints of the game's own castle): the numbers below were tuned against those pictures.
##   the quality    Low / Medium / High / Ultra: render scale and upscaler, anti-aliasing, how far and how soft the sun's shadows are,
##                  screen-space ambient occlusion and indirect light, sun-lit fog (god rays), real-time global illumination (SDFGI),
##                  depth of field, the lens. Same world at every level; only how well it is drawn changes.
##
## Tools can override: `--cs-look=<id>`, `--cs-quality=<id>`, `--cs-look-set=key=value,...` (any key of a look).

const LOOK_IDS := ["golden", "overcast", "noon", "dusk"]
const LOOK_NAMES := {"golden": "Golden hour", "overcast": "Overcast", "noon": "Bright noon", "dusk": "Dusk"}
const QUALITY_IDS := ["low", "medium", "high", "ultra"]
const QUALITY_NAMES := {"low": "Low", "medium": "Medium", "high": "High", "ultra": "Ultra"}
const PEN_IDS := ["off", "light", "full"]
const PEN_NAMES := {"off": "Off", "light": "Light", "full": "Full"}
const INFILL_IDS := ["pencil", "watercolour", "marker", "crayon", "stipple", "scribble", "gouache", "inkwash", "none"]
const INFILL_NAMES := {"pencil": "Colour pencil", "watercolour": "Watercolour", "marker": "Marker", "crayon": "Crayon", "stipple": "Stipple", "scribble": "Scribble", "gouache": "Gouache", "inkwash": "Ink wash", "none": "No infill"}
const SETTINGS := "user://castle_scaper_hex.cfg"

## One row per light. sun: elevation above the horizon and the compass turn (degrees), colour, energy. sky_*: CSSky uniforms.
## ambient: the sky's light on the shaded sides. fog_*: depth haze. grade: tone-map exposure, contrast, saturation, tint.
## water_*: CSSea uniforms. wetness / moss / grime: the stone shader's.
const LOOKS := {
	"golden": {
		"sun_elev": 20.0, "sun_az": -38.0, "sun_col": Color(1.0, 0.72, 0.44), "sun_energy": 3.5, "sun_angle": 0.7, "sun_spec": 1.0,
		"zenith": Color(0.13, 0.28, 0.58), "horizon": Color(0.93, 0.82, 0.68), "glow_col": Color(1.0, 0.55, 0.26), "glow_power": 1.0,
		"sky_ground": Color(0.25, 0.4, 0.45), "cloud_cover": 0.42, "cloud_dark": 0.05, "haze": 0.75, "sun_power": 5.0, "rays": 0.3, "cirrus": 0.6, "stars": 0.0, "night": 0.0, "tone_shadow": Color(-0.015, 0.012, 0.05), "tone_high": Color(0.05, 0.02, -0.035),
		"ambient": 0.85, "ambient_sky": 0.4, "ambient_col": Color(0.82, 0.8, 0.8),
		"fog_col": Color(0.74, 0.66, 0.58), "fog_density": 0.0011, "vol_fog": 0.00025, "vol_col": Color(1.0, 0.78, 0.55),
		"tonemap": 2, "exposure": 0.9, "white": 6.0, "contrast": 1.06, "saturation": 1.1, "brightness": 1.0, "glow": 0.5,
		"water_deep": Color(0.02, 0.2, 0.27), "water_shallow": Color(0.08, 0.42, 0.45), "water_clarity": 3.5, "water_chop": 0.55,
		"wetness": 0.0, "moss": 0.5, "grime": 0.8,
		"vignette": 0.26, "grain": 0.012, "sharpen": 0.25, "clarity": 0.3, "tint": Color(1.0, 0.92, 0.84),
	},
	"overcast": {
		"sun_elev": 40.0, "sun_az": -38.0, "sun_col": Color(0.86, 0.9, 1.0), "sun_energy": 0.55, "sun_angle": 2.5, "sun_spec": 0.25,
		"zenith": Color(0.4, 0.44, 0.5), "horizon": Color(0.62, 0.65, 0.68), "glow_col": Color(0.8, 0.84, 0.9), "glow_power": 0.1,
		"sky_ground": Color(0.28, 0.33, 0.38), "cloud_cover": 0.8, "cloud_dark": 0.75, "haze": 0.9, "sun_power": 0.0, "rays": 0.0, "cirrus": 0.0, "stars": 0.0, "night": 0.25, "tone_shadow": Color(0.0, 0.01, 0.03), "tone_high": Color(0.0, 0.0, 0.01),
		"ambient": 1.5, "ambient_sky": 0.7, "ambient_col": Color(0.85, 0.9, 1.0),
		"fog_col": Color(0.55, 0.6, 0.65), "fog_density": 0.0035, "vol_fog": 0.0012, "vol_col": Color(0.7, 0.75, 0.8),
		"tonemap": 4, "exposure": 1.0, "white": 6.0, "contrast": 1.1, "saturation": 0.88, "brightness": 1.0, "glow": 0.35,
		"water_deep": Color(0.02, 0.055, 0.075), "water_shallow": Color(0.05, 0.14, 0.17), "water_clarity": 2.0, "water_chop": 1.15,
		"wetness": 0.8, "moss": 0.8, "grime": 1.0,
		"vignette": 0.3, "grain": 0.014, "sharpen": 0.25, "clarity": 0.35, "tint": Color(0.86, 0.92, 1.0),
	},
	"noon": {
		"sun_elev": 56.0, "sun_az": 35.0, "sun_col": Color(1.0, 0.96, 0.88), "sun_energy": 3.4, "sun_angle": 0.5, "sun_spec": 1.0,
		"zenith": Color(0.1, 0.3, 0.72), "horizon": Color(0.66, 0.82, 0.95), "glow_col": Color(1.0, 0.9, 0.7), "glow_power": 0.25,
		"sky_ground": Color(0.3, 0.55, 0.65), "cloud_cover": 0.34, "cloud_dark": 0.0, "haze": 0.5, "sun_power": 4.0, "rays": 0.1, "cirrus": 0.5, "stars": 0.0, "night": 0.0, "tone_shadow": Color(0.0, 0.01, 0.03), "tone_high": Color(0.02, 0.015, 0.0),
		"ambient": 1.1, "ambient_sky": 0.55, "ambient_col": Color(0.86, 0.88, 0.92),
		"fog_col": Color(0.7, 0.84, 0.95), "fog_density": 0.0005, "vol_fog": 0.0001, "vol_col": Color(1.0, 0.97, 0.9),
		"tonemap": 2, "exposure": 0.9, "white": 6.0, "contrast": 1.1, "saturation": 1.2, "brightness": 1.0, "glow": 0.4,
		"water_deep": Color(0.02, 0.2, 0.34), "water_shallow": Color(0.1, 0.6, 0.58), "water_clarity": 10.0, "water_chop": 0.4,
		"wetness": 0.0, "moss": 0.35, "grime": 0.6,
		"vignette": 0.18, "grain": 0.01, "sharpen": 0.3, "clarity": 0.35, "tint": Color(1.0, 1.0, 1.0),
	},
	"dusk": {
		"sun_elev": 4.0, "sun_az": -38.0, "sun_col": Color(1.0, 0.46, 0.22), "sun_energy": 2.4, "sun_angle": 1.0, "sun_spec": 1.0,
		"zenith": Color(0.05, 0.09, 0.28), "horizon": Color(0.82, 0.42, 0.36), "glow_col": Color(1.0, 0.4, 0.18), "glow_power": 1.4,
		"sky_ground": Color(0.12, 0.17, 0.26), "cloud_cover": 0.5, "cloud_dark": 0.25, "haze": 0.85, "sun_power": 3.0, "rays": 0.25, "cirrus": 0.8, "stars": 0.9, "night": 0.9,
		"tone_shadow": Color(-0.02, 0.0, 0.06), "tone_high": Color(0.06, 0.015, -0.04),
		"ambient": 0.55, "ambient_sky": 0.7, "ambient_col": Color(0.55, 0.6, 0.85),
		"fog_col": Color(0.5, 0.36, 0.38), "fog_density": 0.0014, "vol_fog": 0.0004, "vol_col": Color(1.0, 0.5, 0.3),
		"tonemap": 2, "exposure": 1.05, "white": 6.0, "contrast": 1.1, "saturation": 1.0, "brightness": 1.0, "glow": 0.85,
		"water_deep": Color(0.01, 0.05, 0.1), "water_shallow": Color(0.04, 0.16, 0.22), "water_clarity": 2.5, "water_chop": 0.5,
		"wetness": 0.1, "moss": 0.5, "grime": 0.8,
		"vignette": 0.34, "grain": 0.016, "sharpen": 0.25, "clarity": 0.3, "tint": Color(0.95, 0.88, 1.0),
	},
}

## One row per quality. scale / upscaler (native, fsr), aa (off fxaa msaa2 msaa4), shadows 0..4, ssao 0..3, ssil, sdfgi, vol (god rays and mist),
## dof, lens (0 off 1 lite 2 full), refl (the castle's reflection in the water: render scale of the mirror picture, 0 off).
const QUALITY := {
	"low": {"scale": 0.7, "upscaler": "fsr", "aa": "fxaa", "shadows": 1, "ssao": 0, "ssil": false, "sdfgi": false, "vol": false, "dof": false, "lens": 1, "refl": 0.0},
	"medium": {"scale": 0.85, "upscaler": "fsr", "aa": "fxaa", "shadows": 2, "ssao": 1, "ssil": false, "sdfgi": false, "vol": false, "dof": false, "lens": 2, "refl": 0.0},
	"high": {"scale": 1.0, "upscaler": "native", "aa": "msaa4", "shadows": 3, "ssao": 2, "ssil": true, "sdfgi": false, "vol": true, "dof": false, "lens": 2, "refl": 0.5},
	"ultra": {"scale": 1.0, "upscaler": "native", "aa": "msaa4", "shadows": 4, "ssao": 3, "ssil": true, "sdfgi": true, "vol": true, "dof": true, "lens": 2, "refl": 0.5},
}
## Shadow level -> {distance of the sun's shadows in metres, splits, soft filter quality 0..5, blur}
const SHADOW_LEVELS := {
	1: {"distance": 160.0, "splits": 2, "filter": 1, "blur": 1.0},
	2: {"distance": 260.0, "splits": 2, "filter": 2, "blur": 1.2},
	3: {"distance": 420.0, "splits": 4, "filter": 3, "blur": 1.4},
	4: {"distance": 700.0, "splits": 4, "filter": 4, "blur": 1.6},
}

signal changed

var main: Node
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var sea_mat: ShaderMaterial
var layer: CanvasLayer
var lens: ColorRect
var lens_mat: ShaderMaterial
var attrs: CameraAttributesPractical
var reflect: CSReflect
var look_id := "golden"
var pen_id := "off"
var infill_id := "pencil"
var quality_id := "high"
var cur := {}
var q := {}
var _args := {}
var _overrides := {}


func setup(p_main: Node, p_env: Environment, p_sun: DirectionalLight3D, p_sky: ShaderMaterial) -> void:
	main = p_main
	env = p_env
	sun = p_sun
	sky_mat = p_sky
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cs-"):
			var kv := a.substr(5).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK and not _args.has("fresh"):
		look_id = str(cf.get_value("look", "light", look_id))
		quality_id = str(cf.get_value("look", "quality", quality_id))
		pen_id = str(cf.get_value("look", "pen", pen_id))
		infill_id = str(cf.get_value("look", "infill", infill_id))
	if _args.has("look") and LOOKS.has(str(_args.look)):
		look_id = str(_args.look)
	if _args.has("pen") and str(_args.pen) in PEN_IDS:
		pen_id = str(_args.pen)
	if not pen_id in PEN_IDS:
		pen_id = "off"
	if _args.has("infill") and str(_args.infill) in INFILL_IDS:
		infill_id = str(_args.infill)
	if not infill_id in INFILL_IDS:
		infill_id = "pencil"
	if _args.has("quality") and QUALITY.has(str(_args.quality)):
		quality_id = str(_args.quality)
	if not LOOKS.has(look_id):
		look_id = "golden"
	if not QUALITY.has(quality_id):
		quality_id = "high"
	for kv: String in str(_args.get("look-set", "")).split(",", false):
		var p := kv.split("=", true, 1)
		if p.size() == 2:
			_overrides[p[0]] = float(p[1])
	attrs = CameraAttributesPractical.new()
	_build_lens()
	apply()


func set_sea(m: ShaderMaterial) -> void:
	sea_mat = m
	apply()


func cycle_look() -> void:
	look_id = LOOK_IDS[(LOOK_IDS.find(look_id) + 1) % LOOK_IDS.size()]
	_save()
	apply()


func cycle_pen() -> void:
	pen_id = PEN_IDS[(PEN_IDS.find(pen_id) + 1) % PEN_IDS.size()]
	_save()
	apply()


func cycle_infill() -> void:
	infill_id = INFILL_IDS[(INFILL_IDS.find(infill_id) + 1) % INFILL_IDS.size()]
	_save()
	apply()


func infill_name() -> String:
	return str(INFILL_NAMES[infill_id])


func pen_name() -> String:
	return str(PEN_NAMES[pen_id])


func cycle_quality() -> void:
	quality_id = QUALITY_IDS[(QUALITY_IDS.find(quality_id) + 1) % QUALITY_IDS.size()]
	_save()
	apply()


func _save() -> void:
	if _args.has("fresh"):
		return
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("look", "light", look_id)
	cf.set_value("look", "quality", quality_id)
	cf.set_value("look", "pen", pen_id)
	cf.set_value("look", "infill", infill_id)
	cf.save(SETTINGS)


func apply() -> void:
	cur = (LOOKS[look_id] as Dictionary).duplicate()
	for k: String in _overrides:
		if cur.has(k):
			cur[k] = _overrides[k]
	q = (QUALITY[quality_id] as Dictionary).duplicate()
	_apply_look()
	_apply_quality()
	if reflect:
		reflect.configure(float(q.refl), env)
	if main.pen != null:
		main.pen.style = INFILL_IDS.find(infill_id)
		main.pen.set_mode(PEN_IDS.find(pen_id))
	changed.emit()


func _apply_look() -> void:
	if env == null:
		return
	var g := cur
	# the sun
	sun.rotation = Vector3(deg_to_rad(-float(g.sun_elev)), deg_to_rad(float(g.sun_az)), 0.0)
	sun.light_color = g.sun_col
	sun.light_energy = float(g.sun_energy)
	sun.light_angular_distance = float(g.sun_angle)
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.2
	sun.light_specular = float(g.sun_spec)
	# the sky
	sky_mat.set_shader_parameter("sun_dir", sun.basis.z)
	sky_mat.set_shader_parameter("sun_col", g.sun_col)
	sky_mat.set_shader_parameter("sun_power", float(g.sun_power))
	sky_mat.set_shader_parameter("zenith", g.zenith)
	sky_mat.set_shader_parameter("horizon", g.horizon)
	sky_mat.set_shader_parameter("glow_col", g.glow_col)
	sky_mat.set_shader_parameter("glow_power", float(g.glow_power))
	sky_mat.set_shader_parameter("ground_col", g.sky_ground)
	sky_mat.set_shader_parameter("cloud_cover", float(g.cloud_cover))
	sky_mat.set_shader_parameter("cloud_dark", float(g.cloud_dark))
	sky_mat.set_shader_parameter("haze", float(g.haze))
	sky_mat.set_shader_parameter("stars", float(g.stars))
	sky_mat.set_shader_parameter("rays", float(g.rays))
	sky_mat.set_shader_parameter("cirrus", float(g.cirrus))
	# the air: ambient light from the sky, depth haze
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = g.ambient_col
	env.ambient_light_sky_contribution = float(g.ambient_sky)
	env.ambient_light_energy = float(g.ambient)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = g.fog_col
	env.fog_density = float(g.fog_density)
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35
	env.fog_sun_scatter = 0.25
	# the grade
	env.tonemap_mode = int(g.tonemap) as Environment.ToneMapper
	env.tonemap_exposure = float(g.exposure)
	env.tonemap_white = float(g.white)
	env.adjustment_enabled = true
	env.adjustment_brightness = float(g.brightness)
	env.adjustment_contrast = float(g.contrast)
	env.adjustment_saturation = float(g.saturation)
	env.adjustment_color_correction = lut_for(g.tone_shadow, g.tone_high)
	env.glow_enabled = float(g.glow) > 0.0
	env.glow_intensity = float(g.glow)
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# volumetric light (lit in _apply_quality)
	env.volumetric_fog_density = float(g.vol_fog)
	env.volumetric_fog_albedo = g.vol_col
	env.volumetric_fog_emission = Color(0, 0, 0)
	env.volumetric_fog_anisotropy = 0.72
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_ambient_inject = 0.2
	# the water and the stone
	if sea_mat:
		sea_mat.set_shader_parameter("deep_col", g.water_deep)
		sea_mat.set_shader_parameter("shallow_col", g.water_shallow)
		sea_mat.set_shader_parameter("clarity", float(g.water_clarity))
		sea_mat.set_shader_parameter("chop", float(g.water_chop))
		sea_mat.set_shader_parameter("sun_col", g.sun_col)
		sea_mat.set_shader_parameter("debug_mode", int(_overrides.get("water_debug", 0)))
		if main.seabed_mi:
			(main.seabed_mi.material_override as ShaderMaterial).set_shader_parameter("clarity", float(g.water_clarity))
	if main.mat_plaster:
		main.mat_plaster.set_shader_parameter("wetness", float(g.wetness))
		main.mat_plaster.set_shader_parameter("moss", float(g.moss))
		main.mat_plaster.set_shader_parameter("grime", float(g.grime))
		main.mat_plaster.set_shader_parameter("night", float(g.night))
	if main.prop_mat:
		main.prop_mat.set_shader_parameter("night", float(g.night))
		main.leave_mat.set_shader_parameter("night", float(g.night))
		main.prop_mat.set_shader_parameter("wetness", float(g.wetness))
		main.leave_mat.set_shader_parameter("wetness", float(g.wetness))
	# the lens
	lens_mat.set_shader_parameter("vignette", float(g.vignette))
	lens_mat.set_shader_parameter("grain", float(g.grain))
	lens_mat.set_shader_parameter("sharpen", float(g.sharpen))
	lens_mat.set_shader_parameter("clarity", float(g.clarity))
	lens_mat.set_shader_parameter("tint", g.tint)


func _apply_quality() -> void:
	var vp := main.get_viewport()
	# shadows
	var s: Dictionary = SHADOW_LEVELS[clampi(int(q.shadows), 1, 4)]
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(s.splits) == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = float(s.distance)
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.9
	sun.shadow_blur = float(s.blur)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(s.filter) as RenderingServer.ShadowQuality)
	# ambient occlusion
	var ao := int(q.ssao)
	env.ssao_enabled = ao > 0
	if ao > 0:
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.8
		env.ssao_power = 1.5
		env.ssao_detail = 0.6
		env.ssao_horizon = 0.06
		env.ssao_sharpness = 0.9
		env.ssao_light_affect = 0.2
		env.ssao_ao_channel_affect = 0.4
		RenderingServer.environment_set_ssao_quality([0, 0, 1, 2][ao] as RenderingServer.EnvironmentSSAOQuality, ao < 3, 0.5, 2, 50.0, 300.0)
	# indirect light
	env.ssil_enabled = bool(q.ssil)
	if env.ssil_enabled:
		env.ssil_radius = 5.0
		env.ssil_intensity = 1.0
		env.ssil_sharpness = 0.9
		env.ssil_normal_rejection = 1.0
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	env.sdfgi_enabled = bool(q.sdfgi)
	if env.sdfgi_enabled:
		env.sdfgi_use_occlusion = true
		env.sdfgi_bounce_feedback = 0.5
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.35
		env.sdfgi_energy = 1.0
		env.sdfgi_read_sky_light = true
	# god rays and mist
	env.volumetric_fog_enabled = bool(q.vol)
	# depth of field
	if bool(q.dof):
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = 160.0
		attrs.dof_blur_far_transition = 260.0
		attrs.dof_blur_amount = 0.04
		main.get_node("WorldEnvironment").camera_attributes = attrs
	else:
		main.get_node("WorldEnvironment").camera_attributes = null
	# resolution, upscaler, anti-aliasing
	var sc := clampf(float(q.scale), 0.5, 1.0)
	if str(q.upscaler) == "native" or sc >= 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.texture_mipmap_bias = 0.0
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = sc
		vp.texture_mipmap_bias = clampf(log(sc) / log(2.0), -1.5, 0.0)
		vp.fsr_sharpness = 0.4
	var aa := str(q.aa)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X if aa == "msaa4" else (Viewport.MSAA_2X if aa == "msaa2" else Viewport.MSAA_DISABLED)
	vp.use_taa = false
	lens.visible = int(q.lens) > 0
	lens_mat.set_shader_parameter("aberration", 0.0008 if int(q.lens) >= 2 else 0.0)


func _build_lens() -> void:
	layer = CanvasLayer.new()
	layer.name = "Lens"
	layer.layer = -1   # over the 3D picture, under the interface
	main.add_child(layer)
	lens = ColorRect.new()
	lens.name = "LensRect"
	lens.set_anchors_preset(Control.PRESET_FULL_RECT)
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens_mat = ShaderMaterial.new()
	lens_mat.shader = preload("res://shaders/cs_lens.gdshader")
	lens.material = lens_mat
	layer.add_child(lens)


## The depth of field follows how far the camera is from what it looks at.
func follow_camera(dist: float) -> void:
	if bool(q.get("dof", false)):
		attrs.dof_blur_far_distance = dist * 1.6
		attrs.dof_blur_far_transition = dist * 2.2


func look_name() -> String:
	return str(LOOK_NAMES[look_id])


func quality_name() -> String:
	return str(QUALITY_NAMES[quality_id])


static var _luts := {}


## A 16-cube colour table: a split tone, the shadows pushed toward `shadow` and the lights toward `high` (offsets on 0..1).
static func lut_for(shadow: Color, high: Color) -> ImageTexture3D:
	var key := "%s%s" % [shadow, high]
	if _luts.has(key):
		return _luts[key]
	var n := 16
	var imgs: Array[Image] = []
	for z in n:
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
		for y in n:
			for x in n:
				var c := Vector3(x, y, z) / float(n - 1)
				var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
				var sh := pow(1.0 - l, 2.0)
				var hi := l * l
				c += Vector3(shadow.r, shadow.g, shadow.b) * sh + Vector3(high.r, high.g, high.b) * hi
				img.set_pixel(x, y, Color(clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0)))
		imgs.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, imgs)
	_luts[key] = tex
	return tex
