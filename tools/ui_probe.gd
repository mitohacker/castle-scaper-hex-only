extends SceneTree
## Where the UI panels sit in the window (the editor test must click clear of them).
## Run (windowed): Godot --path . --resolution 1600x900 --script res://tools/ui_probe.gd -- --cs-fresh

var main: Node3D
var frames := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 40:
		var ui: CSUi = main.ui
		print("window ", root.get_visible_rect().size, " ", DisplayServer.window_get_size())
		for n in ["top", "type_bar", "swatch_bar"]:
			print(n, " ", (ui.get(n) as Control).get_global_rect())
		print("straight button ", ui.b_straight.get_global_rect())
		for c in root.get_children():
			pass
		quit(0)
	return false
