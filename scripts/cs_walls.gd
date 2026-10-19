class_name CSWalls
extends RefCounted
## Straight walls as data (CSTown.walls) and what is done with them before they are built: an old save's walls are put on the grid they were made
## for, and walls that lie side by side are merged into one thicker wall.
##
## A wall is a rectangle: an axis (a point, a heading, a length) and a width. Two walls MERGE when they are parallel (the same heading, or the opposite,
## within CSWalls.PARALLEL_DEG) and lie close enough, measured in CELL WIDTHS (W = the distance between the middles of two neighbouring cells, 5.19 m on the
## full-size cells, so every number scales with the cell setting):
##   side by side - the lines of two single walls are at most MERGE_LAT_K = 1.5 W apart (centre to centre; for a thick wall: the gap between the strips
##                  at most 1.5 W less one wall thickness), so a wall dragged one cell, or two cells, beside another joins it;
##   along the line - their spans overlap, or touch, or lie at most MERGE_AX_K = 1 W apart end to end; the nearer the strips (the smaller the side gap),
##                  the larger the gap along the line that still counts: it falls linearly from 1 W (strips touching) to nothing (strips 1.5 W apart), so
##                  two walls that only half overlap diagonally never make a huge empty slab;
## and the merged wall is not wider than MAX_W_K = 3 W. The merged wall is the bounding rectangle of the two in their common direction: its width is the
## union of their widths (two strips side by side make a wall about twice as thick, three three times), its length the union of their spans, its heading
## the first wall's (so it stays on one of the wall directions). Walls that meet or cross at an angle are not merged: they stay two walls with one joined
## outline (CSBuild._walls). The merge runs when a wall is added, in the drag preview (`with_new`) and when a save loads.

const NEAR := 0.1              # a corner this close to another wall's side (and not on it) is a near miss the build cannot weld
const NUDGE := 0.06            # ... the wall is built this much longer
const PARALLEL_DEG := 0.6
const THICK := 1.9              # a single wall's width on the full-size cells (m); smaller cells scale it with the cell
const MERGE_LAT_K := 1.5        # side by side: lines of two single walls at most this many cell widths apart
const MERGE_AX_K := 1.0         # end to end: spans at most this many cell widths apart (when the strips touch)
const MAX_W_K := 3.0            # the thickest merged wall, in cell widths (15.6 m on the full-size cells, 7.8 m on 1/4 cells)


static func cell_width(base: float) -> float:
	## The distance between two neighbouring cells' middles, from a single wall's thickness (both scale with the cell).
	return base * CSGrid.D_SPACING / THICK


static func thickness(grid: CSGrid) -> float:
	## The width of a single wall on this grid (1.9 m on the full-size cells, thinner on smaller ones).
	return THICK * grid.cell


static func dir_of(w: Dictionary) -> Vector2:
	return Vector2.from_angle(deg_to_rad(float(w.deg)))


static func normalize(town: CSTown, grid: CSGrid) -> void:
	## A wall of an older save began on a cell (`v`): it starts at that cell's middle, a single wall wide, on the grid the save names.
	var keep: Array = []
	for w: Dictionary in town.walls:
		if w.has("v"):
			var v := int(w.v)
			if not grid.is_dodecagon(v) or v >= grid.verts.size():
				continue
			var p := grid.verts[v]
			keep.append({"x": p.x, "z": p.y, "deg": fposmod(float(w.deg), 360.0), "len": float(w.len), "w": thickness(grid), "c": int(w.c)})
		else:
			keep.append(w)
	town.walls = keep


static func settle(town: CSTown, grid: CSGrid) -> int:
	## Normalize, then merge: what a save is put through when it loads and what a new wall is put through. The number of merges made.
	normalize(town, grid)
	return merge(town, thickness(grid))


static func merge(town: CSTown, base: float) -> int:
	## Merge every pair of walls that lie together, the closest pair first, until none does. The number of merges made.
	return merge_list(town.walls, base)


static func merge_list(walls: Array, base: float) -> int:
	var merges := 0
	var guard := 0
	while guard < 400:
		guard += 1
		var bi := -1
		var bj := -1
		var best := INF
		var res := {}
		var n := walls.size()
		for i in n:
			for j in range(i + 1, n):
				var r := try_merge(walls[i], walls[j], base)
				if not r.is_empty() and float(r.score) < best:
					best = float(r.score)
					bi = i
					bj = j
					res = r
		if bi < 0:
			break
		res.erase("score")
		walls[bi] = res
		walls.remove_at(bj)
		merges += 1
	return merges


static func with_new(walls: Array, nw: Dictionary, base: float) -> Dictionary:
	## What a wall about to be laid becomes beside the walls there are: {"wall": the wall it ends up as (the new wall itself when nothing merges),
	## "absorbed": how many of the existing walls it joins}. The walls given are not touched; the drag preview draws "wall" and building it makes the same.
	var list: Array = []
	for w: Dictionary in walls:
		list.append(w.duplicate())
	var n := nw.duplicate()
	n["_new"] = true
	list.append(n)
	var before := list.size()
	merge_list(list, base)
	var out := nw.duplicate()
	for w: Dictionary in list:
		if w.has("_new"):
			out = w.duplicate()
			out.erase("_new")
	return {"wall": out, "absorbed": before - list.size()}


static func try_merge(a: Dictionary, b: Dictionary, base: float) -> Dictionary:
	## The wall a and b make when they merge ({} when they do not), with a "score" (the two gaps added: the closest pair merges first).
	var ua := dir_of(a)
	var ub := dir_of(b)
	if absf(ua.cross(ub)) > sin(deg_to_rad(PARALLEL_DEG)):
		return {}
	var na := Vector2(-ua.y, ua.x)
	var pa := Vector2(float(a.x), float(a.z))
	var pb := Vector2(float(b.x), float(b.z))
	var la := float(a.len)
	var lb_len := float(b.len)
	var lat := na.dot(pb - pa)                         # b's axis, across a's
	var sb0 := ua.dot(pb - pa)
	var sb1 := sb0 + ua.dot(ub) * lb_len
	var smin_b := minf(sb0, sb1)
	var smax_b := maxf(sb0, sb1)
	var ha := float(a.w) * 0.5
	var hb := float(b.w) * 0.5
	var width := cell_width(base)
	var lat_gap := absf(lat) - (ha + hb)
	var ax_gap := maxf(smin_b - la, -smax_b)
	var lat_max := MERGE_LAT_K * width - base + 1e-6
	if lat_gap > lat_max:
		return {}
	var ax_max := MERGE_AX_K * width * (1.0 - clampf(maxf(lat_gap, 0.0) / lat_max, 0.0, 1.0))
	if ax_gap > ax_max + 1e-6:
		return {}
	var lo := minf(-ha, lat - hb)
	var hi := maxf(ha, lat + hb)
	if hi - lo > MAX_W_K * width + 1e-6:
		return {}
	var smin := minf(0.0, smin_b)
	var smax := maxf(la, smax_b)
	var p0 := pa + ua * smin + na * ((lo + hi) * 0.5)
	var r := {"x": p0.x, "z": p0.y, "deg": float(a.deg), "len": smax - smin, "w": hi - lo, "c": int(a.c) if la >= lb_len else int(b.c), "score": maxf(lat_gap, 0.0) + maxf(ax_gap, 0.0)}
	if a.has("_new") or b.has("_new"):
		r["_new"] = true
	return r


static func robust(walls: Array) -> Array:
	## The walls as they are built: a wall whose corner lies a hair's breadth (under NEAR) off the side of another wall, but not on it, is made a little
	## longer at that end until it clears (or it is plainly across it), so no two outlines meet in a sliver of an edge the plan cannot weld (it welds
	## exact joints and clear gaps, not that). The saved wall is not touched.
	var out: Array = []
	for w: Dictionary in walls:
		out.append(w.duplicate())
	for _pass in 12:
		var moved := false
		for i in out.size():
			var pa := _rect(out[i])
			for j in out.size():
				if j == i:
					continue
				var pb := _rect(out[j])
				for ci in 4:
					var q := pa[ci]
					for k in 4:
						var d := Geometry2D.get_closest_point_to_segment(q, pb[k], pb[(k + 1) % 4]).distance_to(q)
						if d > 1e-4 and d < NEAR:
							var w: Dictionary = out[i]
							var u := Vector2.from_angle(deg_to_rad(float(w.deg)))
							if ci == 0 or ci == 3:             # a corner at the start: the wall grows backwards
								w.x = float(w.x) - u.x * NUDGE
								w.z = float(w.z) - u.y * NUDGE
							w.len = float(w.len) + NUDGE
							moved = true
							pa = _rect(w)
							break
		if not moved:
			break
	return out


static func _rect(w: Dictionary) -> PackedVector2Array:
	var u := Vector2.from_angle(deg_to_rad(float(w.deg)))
	var n := Vector2(-u.y, u.x) * (float(w.w) * 0.5)
	var a := Vector2(float(w.x), float(w.z))
	var b := a + u * float(w.len)
	return PackedVector2Array([a - n, b - n, b + n, a + n])


static func add_from_cell(town: CSTown, grid: CSGrid, v: int, deg: float, length: float, c: int) -> bool:
	## A wall of a single width from the middle of cell v (what the tools and the tests lay).
	var p := grid.verts[v]
	return town.wall_add(p.x, p.y, deg, length, thickness(grid), c)
