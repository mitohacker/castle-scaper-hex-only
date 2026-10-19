extends SceneTree
## A courtyard cell ringed by its six dodecagon neighbours, three of them a level higher: which stairs the rules find.
func _initialize() -> void:
	var grid := CSGrid.new()
	grid.generate()
	var c := grid.nearest(Vector2.ZERO)
	var t := CSTown.new()
	var j := 0
	for u in grid.nbrs[c]:
		if grid.is_dodecagon(u):
			t.add(u, 0, 1)
			if j <= 2:
				t.add(u, 1, 1)
			j += 1
	var b := CSBuild.new()
	b.build(grid, t)
	print("land ", b.land.get(c, ""), " stairs ", b.stairs.size(), " ", b.stairs.map(func(s): return [s.k, s.cell, s.up]))
	quit(0)
