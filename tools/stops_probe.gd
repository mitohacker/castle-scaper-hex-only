extends SceneTree
## Where a straight wall may end along each of the 12 headings from the middle of the map.
func _initialize() -> void:
	var g := CSGrid.new()
	g.generate()
	var c := g.nearest(Vector2.ZERO)
	for deg in range(0, 360, 30):
		var st := g.line_stops(g.verts[c], Vector2.from_angle(deg_to_rad(float(deg))), 40.0)
		print(deg, " ", Array(st).slice(0, 8).map(func(x): return snappedf(x, 0.01)))
	quit(0)
