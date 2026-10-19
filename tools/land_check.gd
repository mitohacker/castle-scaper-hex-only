extends SceneTree
## CSBuild._find_land floods only a box round the town; this compares it with the flood over the whole island on starters and random towns at a cell size.
## Run: Godot --headless --path . --script res://tools/land_check.gd -- --cell=8
func _reference(g: CSGrid, t: CSTown, b: CSBuild) -> Dictionary:
	var nv := g.verts.size()
	var sea := PackedByteArray()
	sea.resize(nv)
	var stack: Array[int] = []
	for v in nv:
		if not g.buildable(v) and g.is_dodecagon(v):
			sea[v] = 1
			stack.append(v)
	while not stack.is_empty():
		var v: int = stack.pop_back()
		for u in g.nbrs[v]:
			if sea[u] or t.has(u, 0) or b.top_of(u) >= 1:
				continue
			sea[u] = 1
			stack.append(u)
	var land := {}
	for v in nv:
		if not g.buildable(v):
			continue
		if t.has(v, 0):
			land[v] = "base"
		elif b.top_of(v) >= 1:
			land[v] = "passage"
		elif not sea[v]:
			land[v] = "court"
	return land


func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(1, 0, CSGrid.KIND_DODECA, CSGrid.parse_div(str(opt.get("cell", str(CSGrid.DEFAULT_DIV)))))
	var bad := 0
	var towns: Array = []
	for n: String in ["castle", "village", "harbour", "kingdom", "tower"]:
		var t := CSTown.new()
		CSStarter.make(n, g, t)
		towns.append([n, t])
	for s in 4:
		var t := CSTown.new()
		CSStarter.random_growth(g, t, s, 50, 0)
		towns.append(["random %d" % s, t])
	for e: Array in towns:
		var t: CSTown = e[1]
		var b := CSBuild.new()
		b.grid = g
		b.town = t
		b._find_land()
		var ref := _reference(g, t, b)
		var courts := 0
		var same := ref.size() == b.land.size()
		for v: int in ref:
			if b.land.get(v, "") != ref[v]:
				same = false
		for v: int in b.land:
			if b.land[v] == "court":
				courts += 1
		print("  %-9s %4d land cells, %3d courtyard cells: %s" % [e[0], b.land.size(), courts, "same as the whole-island flood" if same else "DIFFERENT"])
		bad += 0 if same else 1
	print("%d towns differ" % bad)
	quit(0)
