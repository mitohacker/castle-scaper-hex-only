class_name CSGrid
extends RefCounted
## Castle Scaper Hex: the DOUBLE HEX GRID, "12 sides". A building cell is a regular DODECAGON: 12 sides instead of a hexagon's 6, at the SAME SIZE as
## the regular hexagon it replaces (21.65 m2, 5.2 m across the flats, side 1.39 m). The cells are the truncated hexagonal tiling (3.12.12):
## dodecagons sit on a triangular lattice and touch their six lattice neighbours along a whole shared side; the gap between every three of
## them is an equilateral triangle of the same side (0.84 m2), which is too small to build on: it is kept in the grid (so every corner is still
## shared by exactly three cells) but is not buildable, a little pit between the blocks. Two hexagon grids, one turned 30 degrees, draw
## lines in 12 directions; the dodecagons' sides run along all of them (every direction a multiple of 30 degrees).
##
## A block stands on a grid POINT and fills that point's cell. The points are the dodecagons' centres (12 neighbours: 6 dodecagons and 6
## triangles, alternating) and the triangles' centres (3 neighbours: the dodecagons round it). The faces of the point graph are the
## triangles (D, D', T), one per cell corner, and `centers[q]` is that corner's real position, not the face's centroid. Every corner is shared
## by exactly three cells that are all neighbours of each other, so two blocks never touch at only a corner. The outermost ring of dodecagons
## is sea (not buildable); a hexagon-shaped island stands inside it (19 rings round the middle one: the same 1141 cells as the hexagon grid).
##
## (History: a random-flip hex grid, an organic jittered one, a regular hexagon grid, a dodecagon grid twice the size. The seed is kept for
## saved towns and does nothing.)

const SIDE := 1.3905934          # the side of every cell (m): the dodecagon has the area of the regular hexagon of side 5 / sqrt(3) (21.65 m2)
const TURN := 3.7320508075688772     # 2 + sqrt(3): the distance between two dodecagon centres in sides
const D_SPACING := SIDE * TURN       # 5.19 m
const RINGS := 20                    # dodecagon rings round the middle one: 1261 dodecagons, the outer ring is the sea (1141 buildable)
const GRID_ID := "dodeca-2"          # saved towns say which grid their column numbers belong to (this one: dodecagons of 21.65 m2)
const KIND_DODECA := "dodeca"        # dodecagons (and unbuildable triangles between them)
const KIND_HEX := "hex"              # the plain regular hexagon grid: 1141 hexagons of 2.887 m side, 21.65 m2 at the full size
const HEX_ID := "hex-2"
const KIND_LAYER := "layer"          # two hexagon lattices layered, one turned 30 degrees: a cell round every point of both (their Voronoi cells)
const LAYER2_ID := "layer-2"
const KIND_LAYER3 := "layer3"        # three lattices layered, turned 0, 20 and 40 degrees
const LAYER3_ID := "layer3-2"
const BASE_AREA := 12.5 * 1.7320508075688772   # 21.65 m2: the area of a cell at div 1 (the hexagon of side 5 / sqrt 3, the dodecagon of side SIDE)
const DEFAULT_DIV := 4               # the cell size a new town starts with: a quarter of the area of the first version's cells (5.4 m2, side 0.70 m)
const DIVS := [1, 2, 4, 6, 8]        # the cell sizes the game offers: 1 / div of the area (div 1: 21.65 m2, 2: 10.8, 4: 5.4, 6: 3.6, 8: 2.7 m2)
const MAX_DIV := 8                   # (the largest a save or --cs-cell may name; 1/6 and 1/8 are the experimental steps: see SPEC 0b)

var kind := KIND_DODECA             # which cells: KIND_DODECA or KIND_HEX
var div := 1                        # the cell size: 1 / div of the area of the full-size cell (the island stays as big, it has more cells)
var cell := 1.0                     # ... as a length: 1 / sqrt(div)
var side := SIDE                    # the side of every cell (m)
var spacing := D_SPACING            # the distance between the middles of two neighbouring building cells (m)
var step := D_SPACING               # (the size of the hash cells of the lookup)
var radius := RINGS                 # rings of cells round the middle one
var seed := 1
var verts := PackedVector2Array()   # the points: dodecagon centres first (d_count), then triangle centres (m)
var d_count := 0                    # how many of the points are dodecagon centres
var border := PackedByteArray()     # 1 on the sea ring (not buildable)
var tris := PackedInt32Array()      # 3 point ids per face, counter-clockwise in (x, z): dodecagon, dodecagon, triangle
var centers := PackedVector2Array() # per face: the cell corner it stands for (shared by the three cells round it)
var nbrs: Array = []                # per point: PackedInt32Array of neighbours, counter-clockwise
var rings: Array = []               # per point: PackedInt32Array, face i lies between nbrs[i] and nbrs[i+1] (-1: outside)
var cells: Array = []               # per point: its cell polygon (the corners of its faces, counter-clockwise)
var _mid := {}                      # edge key -> midpoint
var _hash := {}                     # Vector2i (cells of _hs metres) -> [point ids]
var _hs := HASH                     # the size of a hash cell: 1.16 cell spacings (so a lookup tests as many points at 1/8 cells as at the full size)

const HASH := 6.0                    # (the hash cell of the full-size grid and of the layered ones)


func edge_key(a: int, b: int) -> int:
	return mini(a, b) * 1048576 + maxi(a, b)


func mid(a: int, b: int) -> Vector2:
	return _mid.get(edge_key(a, b), (verts[a] + verts[b]) * 0.5)


static func id_of(k: String, d: int = 1) -> String:
	## The tag a saved town carries for cells of kind k at 1 / d of the full area: "dodeca-2", "hex-2" (d = 1, the tags of the first versions), then
	## "dodeca-2/2", "dodeca-2/3", "hex-2/2" ...
	var base := GRID_ID
	match k:
		KIND_HEX:
			base = HEX_ID
		KIND_LAYER:
			base = LAYER2_ID
		KIND_LAYER3:
			base = LAYER3_ID
	return base if d <= 1 else "%s/%d" % [base, d]


static func kind_of(id: String) -> String:
	## The kind of cells a tag names, or "" for a tag of another grid.
	match id.get_slice("/", 0):
		HEX_ID:
			return KIND_HEX
		GRID_ID:
			return KIND_DODECA
		LAYER2_ID:
			return KIND_LAYER
		LAYER3_ID:
			return KIND_LAYER3
	return ""


static func div_of(id: String) -> int:
	## The cell size a tag names (1 for the tags without one).
	if "/" in id:
		return clampi(int(id.get_slice("/", 1)), 1, MAX_DIV)
	return 1


static func parse_div(text: String) -> int:
	## "2" or "1/2": the cell size as 1 / div of the area.
	var parts := text.split("/")
	return clampi(int(parts[parts.size() - 1]), 1, MAX_DIV)


static func variants() -> Array:
	## The grids the game offers, in the order the Cells button goes through them: [kind, div]. The first is the default (12-sided cells at a quarter of the
	## area), then the two smaller steps (1/6 and 1/8: they build, with a few defects on the stress towns), then the larger ones; the layered lattices
	## (KIND_LAYER, KIND_LAYER3) are experiments, reachable with --cs-grid=layer only: their cells are irregular.
	return [[KIND_DODECA, DEFAULT_DIV], [KIND_DODECA, 6], [KIND_DODECA, 8], [KIND_DODECA, 2], [KIND_DODECA, 1], [KIND_HEX, 4], [KIND_HEX, 2], [KIND_HEX, 1]]


static func variant_name(k: String, d: int) -> String:
	var shape := "12 sides"
	match k:
		KIND_HEX:
			shape = "6 sides"
		KIND_LAYER:
			shape = "2 layers"
		KIND_LAYER3:
			shape = "3 layers"
	return shape if d <= 1 else "%s, 1/%d area" % [shape, d]


func is_dodecagon(v: int) -> bool:
	## A building cell (a dodecagon, or any cell of the plain hexagon grid), not one of the little triangles.
	return v < d_count


func generate(p_seed: int = 1, p_radius: int = 0, p_kind: String = KIND_DODECA, p_div: int = 1) -> void:
	## p_radius 0: as many rings as keep the island as big as the full-size one (RINGS rings of full-size cells).
	seed = p_seed
	kind = p_kind
	div = maxi(p_div, 1)
	cell = 1.0 / sqrt(float(div))
	radius = clampi(p_radius if p_radius > 0 else roundi(float(RINGS) / cell), 2, 60)
	var n := radius
	if kind == KIND_HEX:
		_generate_hex(n)
		return
	if kind == KIND_LAYER or kind == KIND_LAYER3:
		_generate_layered([0.0, 30.0] if kind == KIND_LAYER else [0.0, 20.0, 40.0], BASE_AREA / float(div))
		return
	side = SIDE * cell
	spacing = D_SPACING * cell
	step = spacing
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var inside := func(a: int, b: int) -> bool:
		return absi(a) <= n and absi(b) <= n and absi(a + b) <= n
	# the dodecagons: a triangular lattice cut to a hexagon
	var did := {}
	verts.resize(0)
	border.resize(0)
	for a in range(-n, n + 1):
		for b in range(-n, n + 1):
			if inside.call(a, b):
				did[Vector2i(a, b)] = verts.size()
				verts.append((e1 * float(a) + e2 * float(b)) * spacing)
				border.append(1 if (absi(a) == n or absi(b) == n or absi(a + b) == n) else 0)
	d_count = verts.size()
	# a triangle in every gap between three dodecagons (the lattice triangles pointing up and down), and three faces round it
	var qs := PackedInt32Array()
	var lattice_tris: Array = []
	for a in range(-n, n + 1):
		for b in range(-n, n + 1):
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1):
				lattice_tris.append([did[Vector2i(a, b)], did[Vector2i(a + 1, b)], did[Vector2i(a, b + 1)]])
			if inside.call(a + 1, b) and inside.call(a + 1, b + 1) and inside.call(a, b + 1):
				lattice_tris.append([did[Vector2i(a + 1, b)], did[Vector2i(a + 1, b + 1)], did[Vector2i(a, b + 1)]])
	for lt: Array in lattice_tris:
		var t := verts.size()
		verts.append((verts[lt[0]] + verts[lt[1]] + verts[lt[2]]) / 3.0)
		border.append(0)
		for k in 3:
			qs.append_array([lt[k], lt[(k + 1) % 3], t])
	tris = qs
	_build_topology()


func _generate_hex(n: int) -> void:
	## The regular hexagon grid: a triangle lattice of 5 m cut to a hexagon of n rings, a cell round every point (the centroids of the six
	## triangles round it): regular hexagons of 2.887 m side, pointy-top.
	side = 5.0 / sqrt(3.0) * cell
	spacing = 5.0 * cell
	step = spacing
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var inside := func(a: int, b: int) -> bool:
		return absi(a) <= n and absi(b) <= n and absi(a + b) <= n
	var vid := {}
	verts.resize(0)
	border.resize(0)
	for a in range(-n, n + 1):
		for b in range(-n, n + 1):
			if inside.call(a, b):
				vid[Vector2i(a, b)] = verts.size()
				verts.append((e1 * float(a) + e2 * float(b)) * spacing)
				border.append(1 if (absi(a) == n or absi(b) == n or absi(a + b) == n) else 0)
	d_count = verts.size()
	var qs := PackedInt32Array()
	for a in range(-n, n + 1):
		for b in range(-n, n + 1):
			if inside.call(a, b) and inside.call(a + 1, b) and inside.call(a, b + 1):
				qs.append_array([vid[Vector2i(a, b)], vid[Vector2i(a + 1, b)], vid[Vector2i(a, b + 1)]])
			if inside.call(a + 1, b) and inside.call(a + 1, b + 1) and inside.call(a, b + 1):
				qs.append_array([vid[Vector2i(a + 1, b)], vid[Vector2i(a + 1, b + 1)], vid[Vector2i(a, b + 1)]])
	tris = qs
	_build_topology()


func _generate_layered(angles: Array, area: float) -> void:
	## Hexagon lattices layered: the points of every lattice (each turned by its own angle about the middle of the island), those that fall within
	## 0.4 of a lattice step of one already there dropped (so no cell is a sliver), and a cell round every point: its Voronoi cell, the polygon of the
	## circumcentres of the Delaunay triangles round it. Every cell is convex, every corner is shared by exactly three cells that all touch.
	var m := angles.size()
	var step_len := sqrt(2.0 * area * float(m) * 0.9 / sqrt(3.0))          # the lattice step that makes the cells average about `area`
	var rad := float(RINGS) * D_SPACING                                  # the island is as big as the full-size one
	var reach := rad + 2.5 * step_len
	var min_d := 0.4 * step_len
	side = 0.55 * sqrt(area)
	spacing = step_len
	step = step_len
	var e1 := Vector2(1.0, 0.0)
	var e2 := Vector2(0.5, sqrt(3.0) * 0.5)
	var hexd := func(p: Vector2) -> float:
		# the "hex distance" of p: the circumradius of the regular hexagon (vertices on the lattice axes) through it
		return maxf(maxf(absf(p.dot(Vector2.from_angle(deg_to_rad(30.0)))), absf(p.dot(Vector2.from_angle(deg_to_rad(90.0))))), absf(p.dot(Vector2.from_angle(deg_to_rad(150.0))))) * 2.0 / sqrt(3.0)
	var pts: Array[Vector2] = []
	var grid_cells := {}
	var n := int(reach / step_len) + 3
	for li in m:
		var rot := deg_to_rad(float(angles[li]))
		var cand: Array = []
		for a in range(-n, n + 1):
			for b in range(-n, n + 1):
				var p := ((e1 * float(a) + e2 * float(b)) * step_len).rotated(rot)
				if float(hexd.call(p)) <= reach:
					cand.append(p)
		cand.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.length_squared() < y.length_squared())
		for p: Vector2 in cand:
			var key := Vector2i(floori(p.x / min_d), floori(p.y / min_d))
			var near := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for q: Vector2 in grid_cells.get(Vector2i(key.x + dx, key.y + dz), []):
						if q.distance_squared_to(p) < min_d * min_d:
							near = true
			if near:
				continue
			if not grid_cells.has(key):
				grid_cells[key] = []
			(grid_cells[key] as Array).append(p)
			pts.append(p)
	# triangulate, drop a point whose cell has a side shorter than `min_edge` (a sliver; the cell beside it takes its place) and triangulate again
	var min_edge := 0.07 * step_len
	var alive: Array[Vector2] = pts
	var qs := PackedInt32Array()
	for pass_no in 40:
		verts.resize(0)
		border.resize(0)
		for p: Vector2 in alive:
			verts.append(p)
			border.append(1 if float(hexd.call(p)) > rad else 0)
		var tri := Geometry2D.triangulate_delaunay(verts)
		qs = PackedInt32Array()
		for i in range(0, tri.size(), 3):
			var a := tri[i]
			var b := tri[i + 1]
			var c := tri[i + 2]
			var cr := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			if absf(cr) < 1e-9:
				continue
			if cr < 0.0:
				var t := b
				b = c
				c = t
			qs.append_array([a, b, c])
		# the Voronoi side between two points is the distance between the circumcentres of the two triangles that share their edge
		var edge_q := {}
		var drop := {}
		for q in qs.size() / 3:
			var cc := _circumcentre(verts[qs[q * 3]], verts[qs[q * 3 + 1]], verts[qs[q * 3 + 2]])
			for k in 3:
				var u := qs[q * 3 + k]
				var w := qs[q * 3 + (k + 1) % 3]
				var key := mini(u, w) * 1048576 + maxi(u, w)
				if edge_q.has(key):
					var other: Vector2 = edge_q[key]
					if other.distance_to(cc) < min_edge and (float(hexd.call(verts[u])) < reach - step_len and float(hexd.call(verts[w])) < reach - step_len):
						# drop the one farther from the middle (the lattice drawn first keeps its points)
						drop[u if verts[u].length_squared() > verts[w].length_squared() else w] = true
				else:
					edge_q[key] = cc
		if drop.is_empty():
			break
		var next: Array[Vector2] = []
		for i in alive.size():
			if not drop.has(i):
				next.append(alive[i])
		alive = next
	d_count = verts.size()
	tris = qs
	_build_topology()


static func _circumcentre(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-12:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d, (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


func _build_topology() -> void:
	_hs = HASH if (kind == KIND_LAYER or kind == KIND_LAYER3) else spacing * 1.16
	_hash.clear()
	var nv := verts.size()
	var nq := tris.size() / 3
	centers.resize(nq)
	_mid.clear()
	var around: Array = []                    # per point: [face, prev neighbour, next neighbour]
	around.resize(nv)
	for i in nv:
		around[i] = []
	for q in nq:
		# the cell corner of face (dodecagon, dodecagon, triangle): on the shared side of the two dodecagons, half a side from its
		# middle towards the triangle (the other end of that side is the corner of the face on the triangle's other flank)
		if kind == KIND_LAYER or kind == KIND_LAYER3:
			centers[q] = _circumcentre(verts[tris[q * 3]], verts[tris[q * 3 + 1]], verts[tris[q * 3 + 2]])
		elif kind == KIND_HEX:
			centers[q] = (verts[tris[q * 3]] + verts[tris[q * 3 + 1]] + verts[tris[q * 3 + 2]]) / 3.0
		else:
			var da := verts[tris[q * 3]]
			var db := verts[tris[q * 3 + 1]]
			var mid_ab := (da + db) * 0.5
			centers[q] = mid_ab + (verts[tris[q * 3 + 2]] - mid_ab).normalized() * (side * 0.5)
		for k in 3:
			var v := tris[q * 3 + k]
			var nx := tris[q * 3 + (k + 1) % 3]
			var pv := tris[q * 3 + (k + 2) % 3]
			(around[v] as Array).append([q, nx, pv])
			var ek := edge_key(v, nx)
			if not _mid.has(ek):
				_mid[ek] = (verts[v] + verts[nx]) * 0.5
	nbrs.resize(nv)
	rings.resize(nv)
	cells.resize(nv)
	_hash.clear()
	for v in nv:
		var items: Array = around[v]
		# order the triangles round v counter-clockwise: triangle (v, nx, pv) spans nx -> pv going counter-clockwise
		items.sort_custom(func(x: Array, y: Array) -> bool:
			return (centers[x[0]] - verts[v]).angle() < (centers[y[0]] - verts[v]).angle())
		var nb := PackedInt32Array()
		var rg := PackedInt32Array()
		for it: Array in items:
			if nb.is_empty() or nb[nb.size() - 1] != int(it[1]):
				if not nb.is_empty():
					rg.append(-1)            # a gap (the map's edge)
				nb.append(int(it[1]))
			rg.append(int(it[0]))
			nb.append(int(it[2]))
		# a closed ring repeats its first neighbour at the end
		if nb.size() > 1 and nb[nb.size() - 1] == nb[0] and rg.size() == nb.size() - 1:
			nb.remove_at(nb.size() - 1)
		else:
			rg.append(-1)
		nbrs[v] = nb
		rings[v] = rg
		var poly := PackedVector2Array()
		for q in rg:
			if q >= 0:
				poly.append(centers[q])
		cells[v] = poly
		var hk := Vector2i(floori(verts[v].x / _hs), floori(verts[v].y / _hs))
		if not _hash.has(hk):
			_hash[hk] = []
		(_hash[hk] as Array).append(v)


# --- queries ---------------------------------------------------------------------------------------

func buildable(v: int) -> bool:
	## A dodecagon with a full ring of faces, not on the sea ring. The triangles between them are too small to build on.
	if v < 0 or v >= d_count or border[v]:
		return false
	for q in rings[v]:
		if q < 0:
			return false
	return true


func nearest(p: Vector2, only_buildable: bool = true) -> int:
	## The point whose cell contains p (a dodecagon is far wider than a triangle, so the nearest centre is not the cell p is in). A p over a
	## cell that is not buildable (the sea ring) gives the nearest buildable point instead; one outside every cell, the nearest point.
	var hk := Vector2i(floori(p.x / _hs), floori(p.y / _hs))
	var best := -1
	var bd := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for v: int in _hash.get(Vector2i(hk.x + dx, hk.y + dz), []):
				if _in_cell(v, p) and (not only_buildable or buildable(v)):
					return v
				if only_buildable and not buildable(v):
					continue
				var d := verts[v].distance_squared_to(p)
				if d < bd:
					bd = d
					best = v
	return best


func points_in_rect(lo: Vector2, hi: Vector2) -> PackedInt32Array:
	## The points (cells' middles) inside the rectangle lo..hi, in the order of their ids.
	var out := PackedInt32Array()
	for cx in range(floori(lo.x / _hs), floori(hi.x / _hs) + 1):
		for cz in range(floori(lo.y / _hs), floori(hi.y / _hs) + 1):
			for v: int in _hash.get(Vector2i(cx, cz), []):
				var p := verts[v]
				if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
					out.append(v)
	out.sort()
	return out


func _in_cell(v: int, p: Vector2) -> bool:
	## p inside v's convex cell (counter-clockwise polygon)?
	var poly: PackedVector2Array = cells[v]
	var n := poly.size()
	if n < 3:
		return false
	for i in n:
		if (poly[(i + 1) % n] - poly[i]).cross(p - poly[i]) < -1e-9:
			return false
	return true


const DIR_COUNTS := [12, 16, 24]     # the directions a straight wall may take: 12 (every 30 degrees: the lines of the grid), 16 (22.5), 24 (15)


static func snap_direction(d: Vector2, count: int = 12) -> Vector2:
	## d turned to the nearest of `count` evenly spaced directions, counting from 0 degrees (12: multiples of 30 degrees, the lines of both
	## hexagon grids; 16: multiples of 22.5; 24: multiples of 15).
	var step_angle := TAU / float(maxi(count, 4))
	return Vector2.from_angle(roundf(d.angle() / step_angle) * step_angle)


static func on_lattice(dir: Vector2) -> bool:
	## Does dir run along one of the grid's 12 lines (a multiple of 30 degrees)?
	var a := rad_to_deg(dir.angle()) / 30.0
	return absf(a - roundf(a)) < 0.002


func wall_stops(a: Vector2, dir: Vector2, max_len: float) -> PackedFloat32Array:
	## Where a straight wall from the middle of a cell may end along dir: along a line of the grid (line_stops) where the middle of a cell lies
	## on the line, along any other direction (the 16 and 24 direction walls) every half cell spacing, as far as the last whole cell the wall
	## passes. (Such a wall crosses cells anywhere; it keeps clear of a block's corners through the audit of the build, not by where it ends.)
	if on_lattice(dir):
		return line_stops(a, dir, max_len)
	var out := PackedFloat32Array()
	var unit := spacing * 0.5
	var d := dir.normalized()
	var s := unit
	while s <= max_len + 1e-4:
		out.append(s)
		s += unit
	return out


func cells_along(a: Vector2, b: Vector2, only_buildable: bool = true) -> PackedInt32Array:
	## The points whose cells the segment a-b passes through or runs along (a cell it only grazes within 2 cm counts), in the order it meets
	## them. Along the line through the middles of a row of dodecagons that is the row; along one of the 30 degree lines it goes through
	## dodecagon, triangle, then runs along the shared side of two dodecagons (both count) and on through the next triangle.
	var lo := a.min(b) - Vector2(_hs, _hs)
	var hi := a.max(b) + Vector2(_hs, _hs)
	var found: Array = []
	for cx in range(floori(lo.x / _hs), floori(hi.x / _hs) + 1):
		for cz in range(floori(lo.y / _hs), floori(hi.y / _hs) + 1):
			for v: int in _hash.get(Vector2i(cx, cz), []):
				if only_buildable and not buildable(v):
					continue
				var t := _enter(v, a, b)
				if t >= 0.0:
					found.append([t, v])
	found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt32Array()
	for f: Array in found:
		out.append(int(f[1]))
	return out


func is_whole(v: int) -> bool:
	## A point whose cell is a whole polygon, off the sea ring (a dodecagon or a triangle).
	if v < 0 or v >= verts.size() or border[v]:
		return false
	for q in rings[v]:
		if q < 0:
			return false
	return true


func line_stops(a: Vector2, dir: Vector2, max_len: float) -> PackedFloat32Array:
	## Where along the line from a (the middle of a cell) a straight wall may end: the distances, nearest first, at which the middle of a whole cell
	## (a dodecagon or a triangle) lies exactly on the line. A wall ending at the middle of a cell keeps its end face clear of the cell's
	## sides and corners. Along the lines through a row of dodecagons that is every D_SPACING; along the 30 degree lines (they run along the
	## sides between two rows) the triangles' middles and the second neighbours' come in between.
	var out := PackedFloat32Array()
	var d := dir.normalized()
	for v in cells_along(a, a + d * max_len, false):
		if not is_whole(v):
			continue
		var r := verts[v] - a
		var s := r.dot(d)
		if s > 0.5 and absf(r.cross(d)) < 0.02:
			out.append(s)
	var arr := Array(out)
	arr.sort()
	return PackedFloat32Array(arr)


func _enter(v: int, a: Vector2, b: Vector2) -> float:
	## Where along a-b (0..1) the segment enters v's convex cell (widened by 2 cm); -1 when it misses the cell.
	var poly: PackedVector2Array = cells[v]
	var n := poly.size()
	if n < 3:
		return -1.0
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in n:
		var p := poly[i]
		var e := poly[(i + 1) % n] - p
		var nrm := Vector2(-e.y, e.x).normalized()          # into the cell (counter-clockwise polygon)
		var dist := (a - p).dot(nrm) + 0.02                 # >= 0: inside this side's half plane
		var slope := d.dot(nrm)
		if absf(slope) < 1e-9:
			if dist < 0.0:
				return -1.0
			continue
		var t := -dist / slope
		if slope > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return -1.0
	return t0


func dual(v: int) -> PackedVector2Array:
	## The cell a block on v fills: the centres of the triangles round v, counter-clockwise (Townscaper's dual grid). Two
	## neighbouring cells share the straight side between the two triangle centres on their common edge.
	var out := PackedVector2Array()
	var rg: PackedInt32Array = rings[v]
	for i in rg.size():
		if rg[i] >= 0:
			out.append(centers[rg[i]])
	return out


func face(v: int, i: int) -> PackedVector2Array:
	## The side of v's cell facing neighbour i: from the centre of the triangle before it to the centre of the triangle after.
	var rg: PackedInt32Array = rings[v]
	var n := rg.size()
	return PackedVector2Array([centers[rg[(i + n - 1) % n]], centers[rg[i]]])


func wedge(v: int, i: int) -> PackedVector2Array:
	## The triangle of v's cell towards neighbour i: v and that side's two ends (a fan, for cells that are not convex).
	var f := face(v, i)
	return PackedVector2Array([verts[v], f[0], f[1]])


func neighbour_towards(v: int, dir: Vector2) -> int:
	var best := -1
	var bd := -INF
	for u in nbrs[v]:
		var d := (verts[u] - verts[v]).normalized().dot(dir.normalized())
		if d > bd:
			bd = d
			best = u
	return best


func index_of(v: int, u: int) -> int:
	var nb: PackedInt32Array = nbrs[v]
	for i in nb.size():
		if nb[i] == u:
			return i
	return -1
