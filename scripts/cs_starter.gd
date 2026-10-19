class_name CSStarter
extends RefCounted
## Ready-made block layouts (the Castles menu, the tests and the screenshots). They are only blocks: every tower,
## roof, battlement, gate and courtyard in them comes out of CSBuild's rules, as when the player clicks them in.

const NAMES := ["castle", "village", "tower", "harbour", "bridges", "landscape", "kingdom", "houses", "apartments", "chinese", "japanese", "fantasy", "hamlet", "styles"]


static func make(name: String, grid: CSGrid, town: CSTown) -> void:
	town.clear()
	match name:
		"village":
			_village(grid, town, 5)
		"tower":
			_tower(grid, town)
		"harbour":
			_harbour(grid, town)
		"bridges":
			_bridges(grid, town)
		"landscape":
			_landscape(grid, town)
		"kingdom":
			_kingdom(grid, town)
		"houses":
			_district(grid, town, CSStyle.HOUSE, 11, _centre_pos(grid), 27.0, 0.52, 3, [0, 1, 2, 3, 4, 6, 7, 9])
		"apartments":
			_district(grid, town, CSStyle.APARTMENT, 12, _centre_pos(grid), 25.0, 0.58, 6, [0, 1, 2, 3, 4, 5, 6, 9])
		"chinese":
			_district(grid, town, CSStyle.CHINESE, 13, _centre_pos(grid), 27.0, 0.46, 3, [0, 1, 2, 3, 4, 5, 6, 7, 8])
		"japanese":
			_district(grid, town, CSStyle.JAPANESE, 14, _centre_pos(grid), 27.0, 0.42, 3, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
		"fantasy":
			_district(grid, town, CSStyle.FANTASY, 15, _centre_pos(grid), 27.0, 0.46, 5, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
		"hamlet":
			_district(grid, town, CSStyle.VILLAGE, 16, _centre_pos(grid), 29.0, 0.36, 2, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
		"styles":
			_styles(grid, town)
		_:
			if name.begins_with("random"):
				# random:SEED or random:SEED:CLICKS (the core suite's castles are random:0..15:70); a fourth number picks the style (-1: any)
				var parts := name.split(":")
				random_growth(grid, town, int(parts[1]) if parts.size() > 1 else 1, int(parts[2]) if parts.size() > 2 else 60, int(parts[3]) if parts.size() > 3 else 0)
			else:
				_castle(grid, town)


static func _centre(grid: CSGrid) -> int:
	return grid.nearest(Vector2.ZERO)


static func _band(grid: CSGrid, c: Vector2, r0: float, r1: float) -> Array:
	var out := []
	for v in grid.verts.size():
		if grid.buildable(v):
			var d := grid.verts[v].distance_to(c)
			if d >= r0 and d <= r1:
				out.append(v)
	return out


static func _nearest_angle(grid: CSGrid, cells: Array, c: Vector2, ang: float) -> int:
	var best := -1
	var bd := INF
	for v: int in cells:
		var a := (grid.verts[v] - c).angle()
		var d := absf(angle_difference(a, ang))
		if d < bd:
			bd = d
			best = v
	return best


static func _castle(grid: CSGrid, town: CSTown) -> void:
	var cv := _centre(grid)
	var c := grid.verts[cv]
	# the curtain: a band one cell thick and a bit more (a band of less can leave a gap the sea floods through), the same radius whatever the cells
	var ring := _band(grid, c, 17.5 - 0.58 * grid.spacing, 17.5 + 0.58 * grid.spacing)
	for v: int in ring:
		town.add(v, 0, 0)
		town.add(v, 1, 1 if CSBuild.h01(v, 1) < 0.5 else 0)
	# four towers, two levels taller than the curtain
	var tcol := [7, 3, 9, 6]
	for i in 4:
		var t := _nearest_angle(grid, ring, c, PI * 0.25 + PI * 0.5 * float(i))
		for k in range(2, 4 + i % 2):
			town.add(t, k, tcol[i])
	# a gate passage facing the camera (+z): the block on the ground taken out, the one above kept. The ring only meets
	# some of its cells corner to corner, so the wall is closed on the gate's far side too: the block above then bridges
	# between two walls and gets its arch.
	var gate := _nearest_angle(grid, ring, c, PI * 0.5)
	var gp := grid.verts[gate]
	for u0 in grid.nbrs[gate]:
		if not town.has(u0, 0):
			continue
		var d0 := (grid.verts[u0] - gp).normalized()
		var far := -1
		var best := -0.6
		for u1 in grid.nbrs[gate]:
			var dd := d0.dot((grid.verts[u1] - gp).normalized())
			if dd < best:
				best = dd
				far = u1
		if far >= 0 and not town.has(far, 0) and grid.buildable(far):
			town.add(far, 0, 0)
			town.add(far, 1, 1 if CSBuild.h01(far, 1) < 0.5 else 0)
		break
	town.remove(gate, 0)
	town.add(gate, 2, 1)
	# the keep: a block of cells three high with a round tower rising from its middle
	var keep := [cv]
	var knb: PackedInt32Array = grid.nbrs[cv]
	# two opposite building neighbours (east and west) make a bar of three cells; the keep must not fill the courtyard
	for ang in [0.0, PI]:
		var arm := -1
		var bd := INF
		for u in knb:
			if not grid.is_dodecagon(u):
				continue
			var d := absf(angle_difference((grid.verts[u] - c).angle(), ang))
			if d < bd:
				bd = d
				arm = u
		if arm >= 0:
			keep.append(arm)
	for v: int in keep:
		for k in 3:
			town.add(v, k, 10 if v != cv else 1)
	for k in range(3, 6):
		town.add(cv, k, 4)
	# cottages in the courtyard
	var court := _band(grid, c, 8.5, 12.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for v: int in court:
		if Array(grid.nbrs[v]).any(func(u: int) -> bool: return town.has(u, 0)):
			continue                     # six neighbours make touching likely; a cottage stands alone
		if rng.randf() < 0.85 / float(grid.div):
			town.add(v, 0, [2, 3, 5, 9, 7][rng.randi_range(0, 4)])


static func _village(grid: CSGrid, town: CSTown, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cells := _band(grid, _centre_pos(grid), 0.0, 26.0)
	for v: int in cells:
		var r := rng.randf()
		if r < 0.32:
			var c := rng.randi_range(0, 11)
			town.add(v, 0, c)
			if rng.randf() < 0.4:
				town.add(v, 1, c)
				if rng.randf() < 0.3:
					town.add(v, 2, rng.randi_range(0, 11))


static func _centre_pos(grid: CSGrid) -> Vector2:
	return grid.verts[_centre(grid)]


static func _tower(grid: CSGrid, town: CSTown) -> void:
	var cv := _centre(grid)
	for k in 5:
		town.add(cv, k, 0 if k < 4 else 4)


static func _harbour(grid: CSGrid, town: CSTown) -> void:
	## A quay along the sea with a tall lighthouse and a row of houses behind it.
	var c := _centre_pos(grid)
	for v in grid.verts.size():
		if not grid.buildable(v):
			continue
		var p := grid.verts[v] - c
		if p.y > -4.0 and p.y < 4.0 and absf(p.x) < 24.0:
			town.add(v, 0, 10)
		elif p.y >= 4.0 and p.y < 9.0 and absf(p.x) < 20.0:
			var col: int = [1, 2, 3, 5, 7, 8, 9][int(CSBuild.h01(v, 3) * 7.0)]
			town.add(v, 0, col)
			town.add(v, 1, col)
			if CSBuild.h01(v, 4) < 0.4:
				town.add(v, 2, col)
	var lh := grid.nearest(c + Vector2(-26.0, 0.0))
	for k in 7:
		town.add(lh, k, 0 if k % 2 == 0 else 4)


static func _toward(grid: CSGrid, v: int, dir: Vector2, avoid: Array) -> int:
	## v's neighbour most in direction dir, not one of avoid (nor next to any of them).
	var best := -1
	var bd := -INF
	for u in grid.nbrs[v]:
		if not grid.buildable(u) or u in avoid:
			continue
		var near := false
		for a: int in avoid:
			if a != v and grid.index_of(u, a) >= 0:
				near = true
		if near:
			continue
		var d := (grid.verts[u] - grid.verts[v]).normalized().dot(dir)
		if d > bd:
			bd = d
			best = u
	return best


static func _bridges(grid: CSGrid, town: CSTown) -> void:
	## The pieces that hold blocks up, and stairs: two towers joined high up by one block (an arch under it), a
	## block hung on a tower (corbels), one hung beyond it (a pillar), and a wall walk stepping down a level (stairs).
	## Still only blocks: the pieces come from the rules.
	var b := _centre(grid)
	var t1 := grid.neighbour_towards(b, Vector2(-1, 0))
	var t2 := -1
	var best := INF
	for u in grid.nbrs[b]:
		var d := (grid.verts[u] - grid.verts[b]).normalized().dot((grid.verts[t1] - grid.verts[b]).normalized())
		if d < best:
			best = d
			t2 = u
	for k in 5:
		town.add(t1, k, 7)
		town.add(t2, k, 3 if k < 4 else 9)
	town.add(b, 3, 1)
	# an oriel on the front of the left tower, and a balcony beyond it on a pillar
	var o1 := _toward(grid, t1, Vector2(-0.3, 1).normalized(), [b, t2])
	if o1 >= 0:
		town.add(o1, 3, 5)
		var p1 := _toward(grid, o1, Vector2(-0.3, 1).normalized(), [t1, b])
		if p1 >= 0:
			town.add(p1, 3, 2)
	# a wall walk running from the right tower towards the camera, a level lower after two cells
	var avoid := [b, t1]
	var cur := t2
	var cells := []
	for i in 5:
		var nx := _toward(grid, cur, Vector2(0.25, 1).normalized(), avoid + cells)
		if nx < 0:
			break
		cells.append(nx)
		cur = nx
	for i in cells.size():
		town.add(cells[i], 0, 0)
		if i < 2:
			town.add(cells[i], 1, 0)


static func random_growth(grid: CSGrid, town: CSTown, seed: int, clicks: int, style: int = 0) -> void:
	## Random "clicks": on the sea near the middle, on top of a block, or beside one (the test castles). style -1: a random style per click.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed
	var c := _centre_pos(grid)
	for _i in clicks:
		var cols := town.columns()
		var r := rng.randf()
		if cols.is_empty() or r < 0.15:
			var v := grid.nearest(c + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
			if v >= 0:
				town.add(v, 0, rng.randi_range(0, 11), _pick_style(rng, style))
			continue
		var v0: int = cols[rng.randi_range(0, cols.size() - 1)]
		if r < 0.5:
			town.add(v0, town.top(v0) + 1, rng.randi_range(0, 11), _pick_style(rng, style))
		else:
			var nb: PackedInt32Array = grid.nbrs[v0]
			var u := nb[rng.randi_range(0, nb.size() - 1)]
			if grid.buildable(u):
				var k := rng.randi_range(0, maxi(0, town.top(v0)))
				town.add(u, k, rng.randi_range(0, 11), _pick_style(rng, style))


static func _pick_style(rng: RandomNumberGenerator, style: int) -> int:
	return rng.randi_range(0, CSStyle.COUNT - 1) if style < 0 else style


static func _district(grid: CSGrid, town: CSTown, style: int, seed: int, c: Vector2, radius: float, dens: float, hmax: int, pool: Array) -> void:
	## A cluster of one style round c: dense and tall in the middle, thinning out towards the rim.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for v: int in _band(grid, c, 0.0, radius):
		var d := grid.verts[v].distance_to(c) / radius
		if rng.randf() < dens * (1.25 - 0.7 * d):
			var col: int = pool[rng.randi_range(0, pool.size() - 1)]
			var h := 1
			if rng.randf() < 0.62 - 0.45 * d:
				h += rng.randi_range(1, maxi(1, hmax - 1))
			for k in mini(h, hmax):
				town.add(v, k, col if rng.randf() < 0.85 else pool[rng.randi_range(0, pool.size() - 1)], style)


static func _styles(grid: CSGrid, town: CSTown) -> void:
	## All seven styles side by side: a sector of the band round the middle for each.
	var c := _centre_pos(grid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var heights := [3, 3, 6, 3, 3, 5, 2]
	for v: int in _band(grid, c, 5.0, 30.0):
		var p := grid.verts[v] - c
		var sec := int(floor(fposmod(p.angle(), TAU) / TAU * float(CSStyle.COUNT)))
		var d := p.length() / 30.0
		if rng.randf() < 0.62 - 0.3 * d:
			var col := rng.randi_range(0, 11)
			var h := 1
			if rng.randf() < 0.5 - 0.3 * d:
				h += rng.randi_range(1, maxi(1, int(heights[sec]) - 1))
			for k in mini(h, int(heights[sec])):
				town.add(v, k, col, sec)


static func _landscape(grid: CSGrid, town: CSTown) -> void:
	## Meadow with a mountain range on the left, rocks and a pine forest below it, an orchard of trees and a road across to a headland.
	var c := Vector2.ZERO
	for v: int in _band(grid, c, 0.0, 26.0):
		town.wild_add(v, CSTown.T_LAND)
	var mc := c + Vector2(-16.0, -4.0)
	for v: int in _band(grid, mc, 0.0, 14.0):
		var d := grid.verts[v].distance_to(mc)
		var n := clampi(int((14.0 - d) / 3.2) + 1, 1, 5)
		for i in n:
			town.wild_add(v, CSTown.T_MOUNTAIN)
	for v: int in _band(grid, c + Vector2(-8.0, 13.0), 0.0, 8.0):
		if town.wild_heights(v) == "":
			for i in 1 + int(CSBuild.h01(v, 3) * 2.0):
				town.wild_add(v, CSTown.T_ROCK)
	for v: int in _band(grid, c + Vector2(8.0, -12.0), 0.0, 11.0):
		for i in 1 + int(CSBuild.h01(v, 5) * 3.0):
			town.wild_add(v, CSTown.T_TREE)

	# a road from the mountains' foot across the meadow, out over the water on a bridge and on to a small headland
	var rc := Vector2(-6.0, 6.0)
	var road := []
	var cur := grid.nearest(rc)
	var goal := grid.nearest(Vector2(30.0, 6.0))
	var guard := 0
	while cur != goal and guard < 40:
		guard += 1
		road.append(cur)
		cur = _toward(grid, cur, grid.verts[goal] - grid.verts[cur], road)
		if cur < 0:
			break
	for v: int in road:
		town.wild_add(v, CSTown.T_ROAD)
	for v: int in _band(grid, Vector2(36.0, 6.0), 0.0, 7.0):
		if town.wild_heights(v) == "":
			town.wild_add(v, CSTown.T_LAND)


static func _kingdom(grid: CSGrid, town: CSTown) -> void:
	## The castle in its country: land all round it, mountains behind (with snow), rocks where the mountains meet the plain, a wood and an
	## orchard by the walls, a courtyard garden, and a road from the gate across the meadow to a bridge and a village across the water.
	_castle(grid, town)
	var c := Vector2.ZERO
	var ring_out := 40.0
	for v: int in _band(grid, c, 0.0, ring_out):
		if town.top(v) < 0:
			town.wild_add(v, CSTown.T_LAND)
	var mc := c + Vector2(-8.0, -34.0)
	for v: int in _band(grid, mc, 0.0, 22.0):
		if town.top(v) >= 0:
			continue
		var d := grid.verts[v].distance_to(mc)
		var n := clampi(int((22.0 - d) / 3.4) + 1, 1, 6)
		for i in n:
			town.wild_add(v, CSTown.T_MOUNTAIN if i < n - 1 or d < 8.0 else CSTown.T_ROCK)
	for v: int in _band(grid, c + Vector2(30.0, -20.0), 0.0, 9.0):
		if town.top(v) < 0 and town.wild_heights(v) == "":
			for i in 1 + int(CSBuild.h01(v, 11) * 2.0):
				town.wild_add(v, CSTown.T_ROCK)
	for v: int in _band(grid, c + Vector2(-30.0, 14.0), 0.0, 10.0):
		if town.top(v) < 0 and town.wild_heights(v) == "":
			for i in 2 + int(CSBuild.h01(v, 5) * 2.0):
				town.wild_add(v, CSTown.T_TREE)
	for v: int in _band(grid, c + Vector2(24.0, 14.0), 0.0, 7.0):
		if town.top(v) < 0 and town.wild_heights(v) == "":
			town.wild_add(v, CSTown.T_TREE)
	# the road: from the gate (south, +z) out across the meadow, then east over a gap of water to the village island
	var gate := grid.nearest(c + Vector2(0.0, 19.5))
	var path := []
	var cur := grid.nearest(c + Vector2(0.0, 24.0))
	var goal := grid.nearest(c + Vector2(40.0, 30.0))
	var guard := 0
	while cur != goal and guard < 60:
		guard += 1
		path.append(cur)
		cur = _toward(grid, cur, grid.verts[goal] - grid.verts[cur], path)
		if cur < 0:
			break
	for v: int in path:
		if town.top(v) < 0:
			town.wild_add(v, CSTown.T_ROAD)
