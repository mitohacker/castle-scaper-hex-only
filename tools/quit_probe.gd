extends SceneTree
## Quitting while the castle is still building on the worker thread must be clean (it was an access violation on exit): starts a build and quits at once, with no
## shutdown call of its own (the scene's _exit_tree does it). Run windowed: Godot --path . --script res://tools/quit_probe.gd -- --cs-fresh ; the exit code is the result.
var main: Node3D
var n := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	n += 1
	if n == 30:
		var v: int = main.grid.nearest(Vector2(60.0, 10.0))
		main.add_block(v, 0)
	if n > 30 and main.building and main.build_task >= 0:
		print("quitting while building: task ", main.build_task)
		quit(0)
	if n > 3000:
		print("the build never started")
		quit(1)
	return false
