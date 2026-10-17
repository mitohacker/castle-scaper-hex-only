extends SceneTree
## Compiles every script under scripts/, tests/ and tools/ and quits with 1 when one fails
## (a failed --script would otherwise leave Godot idling forever).

func _init() -> void:
	var bad := 0
	for dir in ["res://scripts", "res://tests", "res://tools"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = dir + "/" + f
			var s = load(path)
			if s == null or not (s is GDScript) or not s.can_instantiate():
				print("FAIL ", path)
				bad += 1
	print("scripts checked, failures: ", bad)
	quit(1 if bad else 0)
