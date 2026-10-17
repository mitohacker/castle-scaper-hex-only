class_name CSUi
extends CanvasLayer
## Castle Scaper's few controls (Townscaper keeps its interface almost empty): a slim top bar, the colour swatches at
## the bottom, a line that always says what the mouse does, a status line.

const PALETTE := [Color(0.84, 0.77, 0.62), Color(0.88, 0.82, 0.69), Color(0.82, 0.62, 0.37), Color(0.84, 0.59, 0.42),
	Color(0.62, 0.35, 0.28), Color(0.84, 0.62, 0.6), Color(0.54, 0.5, 0.6), Color(0.6, 0.68, 0.74),
	Color(0.48, 0.58, 0.54), Color(0.64, 0.7, 0.54), Color(0.56, 0.57, 0.59), Color(0.6, 0.34, 0.25)]
const INK := Color(0.2, 0.24, 0.3)

var main: Node
var root: Control
var top: PanelContainer
var swatches: Array = []
var swatch_bar: PanelContainer
var b_undo: Button
var b_redo: Button
var b_birds: Button
var b_props: Button
var b_spin: Button
var b_light: Button
var b_quality: Button
var castles_menu: MenuButton
var status: Label
var stats: Label
var help: Label


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var th := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.72)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	th.set_stylebox("panel", "PanelContainer", sb)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(1, 1, 1, 0.0)
	bn.set_corner_radius_all(8)
	bn.content_margin_left = 8
	bn.content_margin_right = 8
	bn.content_margin_top = 3
	bn.content_margin_bottom = 3
	var bh := bn.duplicate()
	bh.bg_color = Color(0.2, 0.3, 0.4, 0.1)
	var bp := bn.duplicate()
	bp.bg_color = Color(0.2, 0.3, 0.4, 0.18)
	for t in ["Button", "MenuButton"]:
		th.set_stylebox("normal", t, bn)
		th.set_stylebox("hover", t, bh)
		th.set_stylebox("pressed", t, bp)
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_color("font_color", t, INK)
		th.set_color("font_hover_color", t, INK)
		th.set_color("font_pressed_color", t, INK)
	th.set_color("font_color", "Label", INK)
	root.theme = th
	top = PanelContainer.new()
	top.position = Vector2(14, 12)
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	top.add_child(hb)
	var title := Label.new()
	title.text = "Castle Scaper  "
	title.add_theme_font_size_override("font_size", 17)
	hb.add_child(title)
	hb.add_child(_btn("New", "An empty sea (Ctrl+N)", func(): main.new_town()))
	castles_menu = MenuButton.new()
	castles_menu.text = "Castles"
	castles_menu.tooltip_text = "Start from a ready-made castle, or one you saved"
	castles_menu.focus_mode = Control.FOCUS_NONE
	castles_menu.about_to_popup.connect(_fill_castles)
	castles_menu.get_popup().id_pressed.connect(_on_castle)
	hb.add_child(castles_menu)
	hb.add_child(_btn("Save", "Save this castle (Ctrl+S)", func(): main.save_town()))
	b_undo = _btn("Undo", "Ctrl+Z", func(): main.undo())
	b_redo = _btn("Redo", "Ctrl+Y", func(): main.redo())
	hb.add_child(b_undo)
	hb.add_child(b_redo)
	b_birds = _btn("Birds", "Birds perch on the battlements and roofs and take off when you build next to them (B)", func(): main.toggle_birds())
	hb.add_child(b_birds)
	b_props = _btn("Details", "Window frames, shutters, flower boxes, shields, banners, lanterns, chimneys, hoardings, crates and bunting (P)", func(): main.toggle_props())
	hb.add_child(b_props)
	b_spin = _btn("Turn", "Slowly turn round the castle (Space)", func():
		main.spin = not main.spin
		refresh())
	hb.add_child(b_spin)
	b_light = _btn("Light", "Golden hour, overcast or bright noon (L)", func():
		main.look.cycle_look()
		refresh())
	hb.add_child(b_light)
	b_quality = _btn("Quality", "Low, medium, high or ultra: shadows, ambient occlusion, light bounce, fog, resolution (G)", func():
		main.look.cycle_quality()
		refresh())
	hb.add_child(b_quality)
	# the colours
	swatch_bar = PanelContainer.new()
	root.add_child(swatch_bar)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	swatch_bar.add_child(sh)
	for i in PALETTE.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Colour %d (%s)" % [i + 1, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="][i]]
		for st in ["normal", "hover", "pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = PALETTE[i] if st != "hover" else PALETTE[i].lightened(0.1)
			s.set_corner_radius_all(15)
			b.add_theme_stylebox_override(st, s)
		var idx := i
		b.pressed.connect(func(): main.set_colour(idx))
		sh.add_child(b)
		swatches.append(b)
	help = Label.new()
	help.text = "Click: put a block  ·  Right-click: take one away  ·  Right-drag: turn  ·  Left- or middle-drag: move  ·  Wheel: zoom  ·  1-0 - =: colour  ·  Ctrl+Z: undo"
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	help.add_theme_constant_override("shadow_offset_x", 1)
	help.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(help)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color(1, 1, 1))
	status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	status.add_theme_constant_override("shadow_offset_x", 1)
	status.add_theme_constant_override("shadow_offset_y", 1)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(stats)
	refresh()


func _btn(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _fill_castles() -> void:
	var pm := castles_menu.get_popup()
	pm.clear()
	var labels := {"castle": "Castle with keep and gate", "village": "Village", "tower": "One tower", "harbour": "Harbour and lighthouse",
		"bridges": "Arches, corbels, pillars and stairs"}
	for i in CSStarter.NAMES.size():
		pm.add_item(labels.get(CSStarter.NAMES[i], CSStarter.NAMES[i]), i)
	var saved: Array = main.saved_towns()
	if not saved.is_empty():
		pm.add_separator()
		for j in saved.size():
			pm.add_item(str(saved[j]).get_basename(), 100 + j)


func _on_castle(id: int) -> void:
	if id < 100:
		main.load_starter(CSStarter.NAMES[id])
	else:
		var saved: Array = main.saved_towns()
		if id - 100 < saved.size():
			main.load_saved(saved[id - 100])


func mouse_over_ui() -> bool:
	var m := root.get_viewport().get_mouse_position()
	return top.get_global_rect().has_point(m) or swatch_bar.get_global_rect().has_point(m)


func refresh() -> void:
	if main == null or b_undo == null:
		return
	b_undo.disabled = main.history.is_empty()
	b_redo.disabled = main.future.is_empty()
	b_birds.text = "Birds: On" if main.birds_on else "Birds: Off"
	b_props.text = "Details: On" if main.props_on else "Details: Off"
	b_spin.text = "Turn: On" if main.spin else "Turn"
	if main.look:
		b_light.text = "Light: " + main.look.look_name()
		b_quality.text = "Quality: " + main.look.quality_name()
	for i in swatches.size():
		var b: Button = swatches[i]
		var s: StyleBoxFlat = b.get_theme_stylebox("normal")
		s.border_color = Color(0.15, 0.2, 0.28) if i == main.colour else Color(1, 1, 1, 0.9)
		s.set_border_width_all(4 if i == main.colour else 2)


func tick(_delta: float) -> void:
	var vs := root.get_viewport_rect().size
	swatch_bar.position = Vector2((vs.x - swatch_bar.size.x) * 0.5, vs.y - swatch_bar.size.y - 34)
	help.position = Vector2(16, vs.y - 26)
	status.size = Vector2(vs.x, 24)
	status.position = Vector2(0, 64)
	status.text = main.status_msg if main.status_t > 0.0 else ""
	stats.size = Vector2(420, 20)
	stats.position = Vector2(vs.x - 436, vs.y - 26)
	var b: CSBuild = main.build
	if b:
		stats.text = "%d blocks · %d tris · built in %.0f ms%s" % [main.town.size(), int(b.stats.get("tris", 0)), float(b.stats.get("ms", 0.0)),
			" (building...)" if main.building else ""]
