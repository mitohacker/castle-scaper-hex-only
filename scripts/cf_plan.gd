class_name CFPlan
extends RefCounted
## The castle's masonry as stacked footprints, welded into one skin.
##
## Every part (tower, wall, gatehouse, parapet, notch, slit...) is a "layer": a flat convex outline
## (x, z) standing between two heights. Layers belong to stacks (same material and owner) and stacks to
## groups; a CUT layer only takes away from ADD layers of its own group, a CAP layer marks where a roof
## starts. The solid at a point is: some ADD layer holds it and no CUT of that layer's group does.
##
## Building the mesh:
##  1. all outlines are snapped to a 1 mm lattice and every edge is split wherever another outline
##     crosses it or has a corner on it, so all outlines share their vertices;
##  2. each piece of edge asks "what is solid on my left and right at every height?": where the answer
##     differs there is a wall (a vertical face), and where the solid begins or ends at a height there
##     is a ledge (a horizontal face, triangulated with holes by CFTri);
##  3. walls are cut at the heights used by their corner columns, ledges use the very same vertices:
##     the result is one conforming surface, no overlaps, no buried faces, no T-junctions.
##
## Rebuilding after an edit (run(mesh, prev)): every layer has a content id (cid: its outline, heights and its
## stack's info) and a neighbour signature (the cids of the layers it shares a 1 m cell with). A layer whose
## cid and signature both match a layer of the previous plan is "stable": everything that depends only on its
## neighbourhood (its split outline, the classification of the sub-edges it created, the wall mesh of those
## sub-edges) is taken from the previous plan instead of being computed again. Only the rest is computed, by the
## very same code, so the result is the mesh a full rebuild makes (tests/verify_cf_core.gd checks that).
## The previous plan is only read, never changed (the editor keeps showing it while the worker builds).

const Q := 0.001            # lattice of the plan (m)
const SNAP := 0.02          # vertices closer than this are one vertex (features smaller than this do not exist)
const DELTA := 0.003        # how far from an edge the "which side is solid" probes sit
const YE := 0.0006          # heights closer than this are one height
const HC := 1.0             # cell of the layer hash (m): small, so a point query meets few layers
const GROUND := 0.0
const OP_ADD := 0
const OP_CUT := 1
const OP_CAP := 2
const TURN_REAL := 0.5      # radians (~29 deg): a sharper turn along a wall is a real corner
const ONE_LINE := 0.004     # two edges whose shorter one lies this close to the longer one's line are on one line (m)

# --- input ----------------------------------------------------------------------------------
var stacks: Array = []                       # info dictionaries
var lay_stack := PackedInt32Array()
var lay_op := PackedInt32Array()
var lay_group := PackedInt32Array()
var lay_prio := PackedInt32Array()
var lay_zone := PackedInt32Array()
var lay_y0 := PackedFloat64Array()
var lay_y1 := PackedFloat64Array()
var lay_alive := PackedByteArray()
var lay_poly: Array = []                     # PackedVector2Array (snapped, counter-clockwise; after the split: with every split vertex)
var lay_rect: Array = []                     # Rect2
var lay_vids: Array = []                     # PackedInt32Array, the loop with every split vertex
var lay_cvids: Array = []                    # PackedInt32Array, the outline's own corners (before the splits)
var lay_cid := PackedInt64Array()            # content id: outline, heights and the stack's info
var lay_attr := PackedInt32Array()           # what the classification looks at of a layer: op, priority, zone override, heights (not where it is)
var attr_table := {}                         # [op, priority, zone, y0, y1] -> number; passed on from plan to plan so the numbers stay the same
var attr_shared := false                     # this plan uses the previous plan's table, so its memo keys mean the same
var lay_nxor := PackedInt64Array()           # neighbour signature: xor of the cids of the layers sharing a cell
var lay_ncnt := PackedInt32Array()           # ... and how many they are
var lay_reg: Array = []                      # PackedVector2Array: the outline right after the vertices were merged
var lay_rx0 := PackedFloat64Array()          # the rect as numbers (the point-in-layer prefilter)
var lay_rz0 := PackedFloat64Array()
var lay_rx1 := PackedFloat64Array()
var lay_rz1 := PackedFloat64Array()

# --- vertices, edges ------------------------------------------------------------------------
var vpos := PackedVector2Array()
var vcell := {}
var vexact := {}                             # lattice point -> vertex id (a point that is already a vertex needs no search)
var e_a := PackedInt32Array()
var e_b := PackedInt32Array()
var e_l := PackedInt32Array()
var e_box := PackedFloat32Array()            # x0, z0, x1, z1 per edge
var e_splits: Array = []                     # per edge: null or Array of [t, vid]
var lay_first := PackedInt32Array()          # first edge of each layer, and how many it has
var lay_edge_n := PackedInt32Array()
var lay_cells := {}                          # Vector2i -> Array of layer ids
var pair_a := PackedInt32Array()             # layers that share a cell, in the order they were found
var pair_b := PackedInt32Array()
var pair_events := {}                        # a * layers + b -> PackedVector2Array: the crossings that pair asked for, in order
var cur_events: PackedVector2Array = PackedVector2Array()
var cur_has_events := false

# --- sub-edges ------------------------------------------------------------------------------
# A sub-edge is a piece of outline between two vertices, shared by every layer that has it. It is directed the way
# the first layer that has it (its creator) runs, so that layer is always on the left of it.
var se_a := PackedInt32Array()
var se_b := PackedInt32Array()
var se_src: Array = []                       # per sub-edge: Array [layer, sign, layer, sign...] (sign +1: that layer has it a -> b)
var se_creator := PackedInt32Array()         # the first layer with it ...
var se_creator_k := PackedInt32Array()       # ... and which edge of that layer's loop it is
var se_index := {}
var lay_se_start := PackedInt32Array()       # per layer: where its loop's sub-edges start in lay_se_flat (-1: a loop edge of no length)
var lay_se_flat := PackedInt32Array()

# --- results of the classification -----------------------------------------------------------
# Per sub-edge, independent of the vertex ids so that the next plan can take them over as they are:
#   se_walls[i]: null or a flat Array, six entries per wall piece: [1 if it runs a -> b else 0, y0, y1, slot of the layer
#     whose solid it is, slot of the layer it is built from (-1: none), zone override (-1: none)]; a slot is a place in se_cids[i]
#   se_ledges[i]: null or a flat Array, three entries per ledge: [y, +1 up / -1 down, 1 if the region is left of a -> b]
var se_walls: Array = []
var se_ledges: Array = []
var se_cids: Array = []                      # per sub-edge: PackedInt64Array, the cids of the layers its key lists (what the slots in se_walls mean)
var ledges := {}                             # Vector2i(round(y/Q), +1 up / -1 down) -> Array of from, to pairs
var lay_wall: Array = []                     # per layer: CFMesh with the wall pieces of the sub-edges it created, or null
var stats := {}
var debug := false
var open_loops := 0
var reusable := false                        # may the next plan take things over from this one?
var cid_index := {}                          # cid -> layer (-2: more than one layer has it)
var stable := PackedByteArray()              # per layer: 1 when it was taken over from the previous plan
var old_of := PackedInt32Array()             # per layer: the layer of the previous plan it matches, or -1
var uid_idx := {}                            # cid -> layer, for the wall pieces
static var use_threads := true               # kept for the callers; the plan runs on one thread (script calls do not scale)
static var cross_one_line := false           # debug: let edges on one line cross each other as before (tools/slant_probe.gd compares)
var threaded := true
var ol_a := PackedInt32Array()               # overlapping edge pairs on one line (_edge_pair), which pass their vertices on (_pass_on)
var ol_b := PackedInt32Array()
var passed_on := 0                           # splits made by passing vertices on along lines (stats)


# --- building the input --------------------------------------------------------------------------

func new_stack(op: int, group: int, info: Dictionary) -> int:
	## info: zone, top_zone, seed, flags, owner, prio, anchor (Vector3), round (bool), center (Vector2), radius, uvoff, label
	var d := info.duplicate()
	d["op"] = op
	d["group"] = group
	if not d.has("zone"):
		d["zone"] = CFMesh.Z_STONE
	if not d.has("top_zone"):
		d["top_zone"] = CFMesh.Z_FLAG
	d["seed"] = float(d.get("seed", 0.0))
	d["flags"] = int(d.get("flags", 0))
	d["owner"] = int(d.get("owner", 0))
	d["prio"] = int(d.get("prio", 0))
	d["anchor"] = d.get("anchor", Vector3.ZERO)
	d["round"] = bool(d.get("round", false))
	d["center"] = d.get("center", Vector2.ZERO)
	d["radius"] = float(d.get("radius", 1.0))
	d["uvoff"] = float(d.get("uvoff", 0.0))
	d["label"] = str(d.get("label", ""))
	stacks.append(d)
	return stacks.size() - 1


func add_layer(sid: int, poly: PackedVector2Array, y0: float, y1: float, zone: int = -1) -> int:
	## Adds an outline (any winding) between y0 and y1 to stack sid; returns the layer id or -1 when it is degenerate.
	var st: Dictionary = stacks[sid]
	var pts := PackedVector2Array()
	for p in poly:
		var q := Vector2(roundf(p.x / Q) * Q, roundf(p.y / Q) * Q)
		if pts.is_empty() or q != pts[pts.size() - 1]:
			pts.append(q)
	while pts.size() > 1 and pts[0] == pts[pts.size() - 1]:
		pts.remove_at(pts.size() - 1)
	if pts.size() < 3 or absf(CFTri.area(pts)) < 1e-5:
		return -1
	if CFTri.area(pts) < 0.0:
		pts = CFTri.reversed(pts)
	y0 = roundf(y0 / Q) * Q
	y1 = roundf(y1 / Q) * Q
	if int(st.op) == OP_CAP:
		y1 = y0
	elif y1 <= y0 + YE:
		return -1
	lay_stack.append(sid)
	lay_op.append(int(st.op))
	lay_group.append(int(st.group))
	lay_prio.append(int(st.prio))
	lay_zone.append(zone)
	lay_y0.append(y0)
	lay_y1.append(y1)
	lay_alive.append(1)
	lay_poly.append(pts)
	lay_rect.append(Rect2())
	lay_vids.append(PackedInt32Array())
	lay_cvids.append(PackedInt32Array())
	return lay_stack.size() - 1


func prism(op: int, group: int, poly: PackedVector2Array, y0: float, y1: float, info: Dictionary) -> int:
	## One stack with one layer.
	return add_layer(new_stack(op, group, info), poly, y0, y1)


func layer_count() -> int:
	return lay_stack.size()


# --- the run -------------------------------------------------------------------------------------

func run(mesh: CFMesh, prev: CFPlan = null) -> void:
	## Builds the skin into mesh. prev: the plan of the build before this one (only read); everything that did not
	## change is taken over from it.
	var t0 := Time.get_ticks_usec()
	_content_ids(prev)
	var t1 := Time.get_ticks_usec()
	_register()
	var t2 := Time.get_ticks_usec()
	_pairs()
	_match(prev)
	var t3 := Time.get_ticks_usec()
	_split(prev)
	var t4 := Time.get_ticks_usec()
	_sub_edges()
	var t5 := Time.get_ticks_usec()
	_classify(prev)
	var t6 := Time.get_ticks_usec()
	var tris0 := mesh.tri_count()
	_emit_walls(mesh, prev)
	var t7 := Time.get_ticks_usec()
	_emit_ledges(mesh, prev)
	var t8 := Time.get_ticks_usec()
	_finish()
	var t9 := Time.get_ticks_usec()
	var stable_n := 0
	for li in lay_stack.size():
		stable_n += stable[li]
	stats = {"layers": layer_count(), "verts": vpos.size(), "edges": e_a.size(), "sub_edges": se_a.size(), "tris": mesh.tri_count() - tris0,
		"open_loops": open_loops, "one_line": ol_a.size(), "passed_on": passed_on, "stable_layers": stable_n, "changed_layers": changed_layers, "reused_sub_edges": reused_sub_edges, "classified": classified_sub_edges, "memo_keys": cmemo.size(),
		"wall_layers_built": wall_layers_built, "ledge_hits": ledge_hits, "ledge_misses": ledge_misses,
		"ms_ids": (t1 - t0) / 1000.0, "ms_register": (t2 - t1) / 1000.0, "ms_pairs": (t3 - t2) / 1000.0, "ms_split": (t4 - t3) / 1000.0, "ms_sub": (t5 - t4) / 1000.0,
		"ms_classify": (t6 - t5) / 1000.0, "ms_walls": (t7 - t6) / 1000.0, "ms_ledges": (t8 - t7) / 1000.0, "ms_finish": (t9 - t8) / 1000.0, "inner": inner}


func layer_loop(li: int) -> PackedVector2Array:
	## The outline of layer li with every vertex split points added (valid after run()).
	var out := PackedVector2Array()
	for v in lay_vids[li]:
		out.append(vpos[v])
	return out


func layer_corner_idx(li: int) -> PackedInt32Array:
	## Where the outline's own corners sit in layer_loop(li) (the rest of the loop is split points).
	var out := PackedInt32Array()
	var loop: PackedInt32Array = lay_vids[li]
	var cv: PackedInt32Array = lay_cvids[li]
	var k := 0
	for i in loop.size():
		if k < cv.size() and loop[i] == cv[k]:
			out.append(i)
			k += 1
	return out


# --- 0. content ids ----------------------------------------------------------------------------------

func _content_ids(prev: CFPlan) -> void:
	## cid of a layer: its stack's info (zone, group, priority, owner, seed...), zone override, heights and outline.
	var n := lay_stack.size()
	if prev != null and prev.reusable and prev.attr_table.size() < 100000:
		attr_table = prev.attr_table
		attr_shared = true
	lay_attr.resize(n)
	for li in n:
		var ak := [lay_op[li], lay_prio[li], lay_zone[li], lay_y0[li], lay_y1[li]]
		var an: int = attr_table.get(ak, -1)
		if an < 0:
			an = attr_table.size()
			attr_table[ak] = an
		lay_attr[li] = an
	var sh := PackedInt64Array()
	sh.resize(stacks.size())
	for s in stacks.size():
		sh[s] = hash(stacks[s])
	lay_cid.resize(n)
	for li in n:
		var h1: int = hash([sh[lay_stack[li]], lay_zone[li], lay_y0[li], lay_y1[li]])
		var h2: int = hash(lay_poly[li])
		lay_cid[li] = ((h1 << 32) | h2) & 0x3fffffffffffffff


# --- 1. snap, register ----------------------------------------------------------------------------

func _tick(label: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	inner[label] = float(inner.get(label, 0.0)) + float(t - t0) / 1000.0
	return t


func _vid(p: Vector2) -> int:
	var ek := Vector2i(roundi(p.x / Q), roundi(p.y / Q))
	var hit: int = vexact.get(ek, -1)
	if hit >= 0 and vpos[hit] == p:
		return hit    # a point that is a vertex already: no other vertex can be within SNAP of it
	var cs := SNAP * 2.0
	var cx := floori(p.x / cs)
	var cz := floori(p.y / cs)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr = vcell.get(Vector2i(cx + dx, cz + dz))
			if arr != null:
				for id: int in arr:
					if vpos[id].distance_squared_to(p) <= SNAP * SNAP:
						return id
	var id2 := vpos.size()
	vpos.append(p)
	vexact[ek] = id2
	var key := Vector2i(cx, cz)
	if not vcell.has(key):
		vcell[key] = []
	vcell[key].append(id2)
	return id2


func _cells_of(r: Rect2) -> Array:
	var out := []
	var x0 := floori(r.position.x / HC)
	var x1 := floori(r.end.x / HC)
	var z0 := floori(r.position.y / HC)
	var z1 := floori(r.end.y / HC)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			out.append(Vector2i(x, z))
	return out


func _register() -> void:
	var n := lay_stack.size()
	lay_first.resize(n)
	lay_edge_n.resize(n)
	lay_reg.resize(n)
	lay_rx0.resize(n)
	lay_rz0.resize(n)
	lay_rx1.resize(n)
	lay_rz1.resize(n)
	for li in n:
		var pts: PackedVector2Array = lay_poly[li]
		var ids := PackedInt32Array()
		for p in pts:
			var v := _vid(p)
			if ids.is_empty() or ids[ids.size() - 1] != v:
				ids.append(v)
		while ids.size() > 1 and ids[0] == ids[ids.size() - 1]:
			ids.remove_at(ids.size() - 1)
		if ids.size() < 3:
			lay_alive[li] = 0
			lay_vids[li] = PackedInt32Array()
			continue
		var snapped := PackedVector2Array()
		for v in ids:
			snapped.append(vpos[v])
		lay_poly[li] = snapped
		lay_reg[li] = snapped
		lay_vids[li] = ids
		lay_cvids[li] = ids
		var lo := snapped[0]
		var hi := snapped[0]
		for p in snapped:
			lo = lo.min(p)
			hi = hi.max(p)
		var rc := Rect2(lo, hi - lo).grow(SNAP)
		lay_rect[li] = rc
		lay_rx0[li] = rc.position.x
		lay_rz0[li] = rc.position.y
		lay_rx1[li] = rc.end.x
		lay_rz1[li] = rc.end.y
		for c in _cells_of(rc):
			if not lay_cells.has(c):
				lay_cells[c] = []
			lay_cells[c].append(li)
		# the layer's edges
		lay_first[li] = e_a.size()
		lay_edge_n[li] = ids.size()
		for i in ids.size():
			var a := ids[i]
			var b := ids[(i + 1) % ids.size()]
			e_a.append(a)
			e_b.append(b)
			e_l.append(li)
			var pa := vpos[a]
			var pb := vpos[b]
			e_box.append(minf(pa.x, pb.x) - SNAP)
			e_box.append(minf(pa.y, pb.y) - SNAP)
			e_box.append(maxf(pa.x, pb.x) + SNAP)
			e_box.append(maxf(pa.y, pb.y) + SNAP)
			e_splits.append(null)


# --- 2. neighbours, what can be taken over ---------------------------------------------------------------

func _pairs() -> void:
	## The layers that share a cell, each pair once, in the order they are met; and every layer's neighbour signature.
	var n := lay_stack.size()
	lay_nxor.resize(n)
	lay_ncnt.resize(n)
	var seen := {}
	for c in lay_cells:
		var arr: Array = lay_cells[c]
		var m := arr.size()
		for i in m:
			var a: int = arr[i]
			for j in range(i + 1, m):
				var b: int = arr[j]
				var lo := mini(a, b)
				var hi := maxi(a, b)
				var key := lo * n + hi
				if seen.has(key):
					continue
				seen[key] = true
				pair_a.append(lo)
				pair_b.append(hi)
				lay_nxor[lo] = lay_nxor[lo] ^ lay_cid[hi]
				lay_nxor[hi] = lay_nxor[hi] ^ lay_cid[lo]
				lay_ncnt[lo] += 1
				lay_ncnt[hi] += 1
	if debug:
		_warn_stack_overlaps()


func _match(prev: CFPlan) -> void:
	## Which layers are stable: same cid and same neighbourhood as in the previous plan.
	var n := lay_stack.size()
	stable.resize(n)
	old_of.resize(n)
	old_of.fill(-1)
	if prev == null or not prev.reusable:
		return
	var last_old := -1
	var pidx := prev.cid_index
	for li in n:
		if lay_alive[li] == 0:
			continue
		var o: int = pidx.get(lay_cid[li], -1)
		if o < 0:
			changed_layers += 1
			continue
		if o <= last_old:
			stable.fill(0)      # unchanged layers changed their order: nothing can be taken over
			old_of.fill(-1)
			return
		last_old = o
		if prev.lay_nxor[o] != lay_nxor[li] or prev.lay_ncnt[o] != lay_ncnt[li] or prev.lay_alive[o] == 0:
			continue
		if prev.lay_reg[o] != lay_reg[li]:
			continue        # the merged vertices came out differently
		stable[li] = 1
		old_of[li] = o


# --- 3. split edges where outlines meet -------------------------------------------------------------

func _split(prev: CFPlan) -> void:
	# layer pairs that can meet: same cell, different stacks, boxes meeting. Heights do not matter: collinear
	# edges of layers at other heights must share their split vertices too, or one line would carry two
	# different chains of sub-edges and their faces would overlap.
	# Vertices closer than SNAP are one vertex, whichever was made first: so the order in which vertices are made decides
	# where near-coincident ones end up. Two stable layers have nothing new to find, but the vertices their crossings make
	# are made again, in their turn, from the list of crossings the previous plan kept for the pair.
	var n := lay_stack.size()
	var ts0 := Time.get_ticks_usec()
	var prev_events := {}
	var pn := 0
	if prev != null and prev.reusable:
		prev_events = prev.pair_events
		pn = prev.lay_stack.size()
	for p in pair_a.size():
		var a := pair_a[p]
		var b := pair_b[p]
		if stable[a] == 1 and stable[b] == 1:
			# the previous plan knows whether the pair found anything (it did not when the layers share a stack or do not meet)
			var ev = prev_events.get(old_of[a] * pn + old_of[b])
			if ev != null:
				for x: Vector2 in ev:
					_vid(x)
				pair_events[a * n + b] = ev
			continue
		if lay_stack[a] == lay_stack[b] or lay_alive[a] == 0 or lay_alive[b] == 0:
			continue
		if not (lay_rect[a] as Rect2).intersects(lay_rect[b]):
			continue
		var rb: Rect2 = lay_rect[b]
		var fa := lay_first[a]
		var fb := lay_first[b]
		var na := lay_edge_n[a]
		var nb := lay_edge_n[b]
		cur_has_events = false
		for ea in range(fa, fa + na):
			var bx0 := e_box[ea * 4]
			var bz0 := e_box[ea * 4 + 1]
			var bx1 := e_box[ea * 4 + 2]
			var bz1 := e_box[ea * 4 + 3]
			if bx1 < rb.position.x or bx0 > rb.end.x or bz1 < rb.position.y or bz0 > rb.end.y:
				continue
			var p0 := vpos[e_a[ea]]
			var d1 := vpos[e_b[ea]] - p0
			var lim := (SNAP + 0.0001) * d1.length()
			for eb in range(fb, fb + nb):
				if e_box[eb * 4 + 2] < bx0 or e_box[eb * 4] > bx1 or e_box[eb * 4 + 3] < bz0 or e_box[eb * 4 + 1] > bz1:
					continue
				# the other edge lies wholly on one side of this edge's line, farther than SNAP: it can neither cross it nor touch it
				var s0 := d1.cross(vpos[e_a[eb]] - p0)
				var s1 := d1.cross(vpos[e_b[eb]] - p0)
				if (s0 > lim and s1 > lim) or (s0 < -lim and s1 < -lim):
					continue
				_edge_pair(ea, eb)
		if cur_has_events:
			pair_events[a * n + b] = cur_events
			cur_events = PackedVector2Array()
			cur_has_events = false
	var ts1 := _tick("split.pair_loops", ts0)
	# the split outline of a stable layer is the previous one
	for li in n:
		if stable[li] == 0:
			continue
		var chain: PackedVector2Array = prev.lay_poly[old_of[li]]
		var ids := PackedInt32Array()
		for q in chain:
			ids.append(_vid(q))
		lay_vids[li] = ids
		lay_poly[li] = chain
	ts1 = _tick("split.stable_chains", ts1)
	_pass_on()
	var ts2 := _tick("split.pass_on", ts1)
	# rebuild every loop with its split vertices
	for li in lay_stack.size():
		if lay_alive[li] == 0 or stable[li] == 1:
			continue
		var loop := PackedInt32Array()
		var first := lay_first[li]
		for e in range(first, first + lay_edge_n[li]):
			loop.append(e_a[e])
			var sp = e_splits[e]
			if sp != null:
				# one entry per vertex, ordered by where it projects on the edge (not by the t it was found with)
				var pa := vpos[e_a[e]]
				var ab := vpos[e_b[e]] - pa
				var l2 := maxf(ab.length_squared(), 1e-12)
				var seen := {}
				var ord: Array = []
				for sv: Array in sp:
					var vv: int = sv[1]
					if seen.has(vv) or vv == e_a[e] or vv == e_b[e]:
						continue
					seen[vv] = true
					ord.append([(vpos[vv] - pa).dot(ab) / l2, vv])
				ord.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
				for s2: Array in ord:
					loop.append(s2[1])
		lay_vids[li] = loop
		# the outline the side tests use is the very chain of sub-edges (kinks of up to SNAP included)
		var chain := PackedVector2Array()
		for v in loop:
			chain.append(vpos[v])
		lay_poly[li] = chain
	_tick("split.rebuild_chains", ts2)


func _warn_stack_overlaps() -> void:
	## Layers of one stack are never split against each other: they must not overlap in plan and height.
	var warned := 0
	for p in pair_a.size():
		var a := pair_a[p]
		var b := pair_b[p]
		if lay_stack[a] != lay_stack[b] or lay_alive[a] == 0 or lay_alive[b] == 0:
			continue
		if lay_y0[a] >= lay_y1[b] - YE or lay_y0[b] >= lay_y1[a] - YE:
			continue
		var hit := Geometry2D.intersect_polygons(lay_poly[a], lay_poly[b])
		if not hit.is_empty() and warned < 8:
			warned += 1
			print("  WARNING: layers %d and %d of stack %d (%s) overlap" % [a, b, lay_stack[a], stacks[lay_stack[a]].label])


func _add_split(e: int, t: float, v: int) -> void:
	if v == e_a[e] or v == e_b[e]:
		return
	if e_splits[e] == null:
		e_splits[e] = []
	e_splits[e].append([t, v])


func _edge_pair(ea: int, eb: int) -> void:
	var p0 := vpos[e_a[ea]]
	var p1 := vpos[e_b[ea]]
	var q0 := vpos[e_a[eb]]
	var q1 := vpos[e_b[eb]]
	var d1 := p1 - p0
	var d2 := q1 - q0
	var l1 := d1.length()
	var l2 := d2.length()
	if l1 < 1e-6 or l2 < 1e-6:
		return
	var den := d1.cross(d2)
	# two edges on one line do not cross: they share the vertices inside them (_pass_on), and their corners through _touch
	if not cross_one_line and absf(den) <= 2.0 * ONE_LINE * maxf(l1, l2) and _one_line(p0, d1, l1, q0, d2, l2):
		var tq0 := d1.dot(q0 - p0) / (l1 * l1)
		var tq1 := d1.dot(q1 - p0) / (l1 * l1)
		if maxf(tq0, tq1) > 0.0 and minf(tq0, tq1) < 1.0:
			ol_a.append(ea)
			ol_b.append(eb)
	elif absf(den) > 1e-9 * l1 * l2:
		var w := q0 - p0
		var t := w.cross(d2) / den
		var u := w.cross(d1) / den
		# a crossing strictly inside both edges; one a hair beyond an end is caught below as a corner on an edge
		if t > 0.0 and t < 1.0 and u > 0.0 and u < 1.0:
			var x := p0 + d1 * t
			x = Vector2(roundf(x.x / Q) * Q, roundf(x.y / Q) * Q)
			cur_events.append(x)
			cur_has_events = true
			var v := _vid(x)
			_add_split(ea, t, v)
			_add_split(eb, u, v)
	# a corner of one lying on the other (T-joints and collinear overlaps)
	_touch(ea, p0, p1, l1, e_a[eb], q0)
	_touch(ea, p0, p1, l1, e_b[eb], q1)
	_touch(eb, q0, q1, l2, e_a[ea], p0)
	_touch(eb, q0, q1, l2, e_b[ea], p1)


func _one_line(p0: Vector2, d1: Vector2, l1: float, q0: Vector2, d2: Vector2, l2: float) -> bool:
	## Do two edges lie on one line (the shorter one's ends within ONE_LINE of the longer one's line)? The 1 mm lattice
	## leaves the points of a slanted line up to 0.7 mm off it (the worst case, a short edge reaching past a long one's end,
	## is ~2.8 mm), so two of its edges are not quite parallel and would "cross" at some point along it: a vertex only that
	## pair would get, while the other edges of the line run past it (overlapping sub-edges, doubled walls).
	if l1 >= l2:
		return absf(d1.cross(q0 - p0)) <= ONE_LINE * l1 and absf(d1.cross(q0 + d2 - p0)) <= ONE_LINE * l1
	return absf(d2.cross(p0 - q0)) <= ONE_LINE * l2 and absf(d2.cross(p0 + d1 - q0)) <= ONE_LINE * l2


func _pass_on() -> void:
	## A vertex made on a line by one pair (a crossing, a corner on an edge) belongs to every edge of that line that runs
	## past it, also to those whose own test missed it (an edge whose corner was merged onto the crossing edge's corner meets
	## that edge only there). The overlapping edge pairs on one line (ol_a / ol_b, found by _edge_pair) give each other the
	## vertices they have inside them until nothing changes. Only vertices that exist are used, none is made, so the vertex
	## table and the replay of the crossings (pair_events) are untouched. A stable layer gives the vertices of its loop (the
	## previous plan's, which had them all) and takes none.
	var m := ol_a.size()
	if m == 0:
		return
	var inside := {}                         # edge -> Dictionary of the vertices inside it (made when first needed)
	var dirty := {}                          # edges that took vertices in the round before: after the first round only their pairs can change
	for r in 8:                              # a vertex moves on by at least one edge per round; a line has few edges
		var took := {}
		for k in m:
			var ea := ol_a[k]
			var eb := ol_b[k]
			if r > 0 and not dirty.has(ea) and not dirty.has(eb):
				continue
			var la := e_l[ea]
			var lb := e_l[eb]
			# most edges on a line have nothing inside them (asked again each round: what was passed on goes on)
			var ha: bool = (lay_vids[la].size() > lay_cvids[la].size()) if stable[la] == 1 else e_splits[ea] != null
			var hb: bool = (lay_vids[lb].size() > lay_cvids[lb].size()) if stable[lb] == 1 else e_splits[eb] != null
			if not ha and not hb:
				continue
			if hb and _give(eb, ea, inside):
				took[ea] = true
			if ha and _give(ea, eb, inside):
				took[eb] = true
		if took.is_empty():
			break
		dirty = took


func _inside(e: int, inside: Dictionary) -> Dictionary:
	var d = inside.get(e)
	if d == null:
		d = _inside_of(e)
		inside[e] = d
	return d


func _inside_of(e: int) -> Dictionary:
	## The vertices inside edge e: its splits, or for a stable layer those of its loop between the edge's corners.
	var d := {}
	var li := e_l[e]
	if stable[li] == 1:
		var loop: PackedInt32Array = lay_vids[li]
		var cv: PackedInt32Array = lay_cvids[li]
		var k := e - lay_first[li]
		var b := cv[(k + 1) % cv.size()]
		var i := loop.find(cv[k])
		if i >= 0:
			for j in range(1, loop.size()):
				var v := loop[(i + j) % loop.size()]
				if v == b:
					break
				d[v] = true
		return d
	var sp = e_splits[e]
	if sp != null:
		for sv: Array in sp:
			d[sv[1]] = true
	return d


func _give(src: int, dst: int, inside: Dictionary) -> bool:
	## Splits edge dst at the vertices inside src that lie on it (within SNAP, strictly between its ends); true when any did.
	if stable[e_l[dst]] == 1:
		return false
	var din := _inside(dst, inside)
	var va := e_a[dst]
	var vb := e_b[dst]
	var a := vpos[va]
	var ab := vpos[vb] - a
	var l2 := ab.length_squared()
	var got := false
	for v: int in _inside(src, inside):
		if v == va or v == vb or din.has(v):
			continue
		var p := vpos[v]
		var t := (p - a).dot(ab) / l2
		if t <= 0.0 or t >= 1.0 or (a + ab * t).distance_squared_to(p) > SNAP * SNAP:
			continue
		din[v] = true
		_add_split(dst, t, v)
		passed_on += 1
		got = true
	return got


func _touch(e: int, a: Vector2, b: Vector2, l: float, v: int, p: Vector2) -> void:
	if v == e_a[e] or v == e_b[e]:
		return
	var ab := b - a
	var t := (p - a).dot(ab) / (l * l)
	if t <= 0.0 or t >= 1.0:
		return
	var foot := a + ab * t
	if foot.distance_squared_to(p) <= SNAP * SNAP:
		_add_split(e, t, v)


# --- 4. sub-edges -----------------------------------------------------------------------------------

func _sub_edges() -> void:
	var n := lay_stack.size()
	var big := vpos.size() + 1
	lay_se_start.resize(n)
	var flat := PackedInt32Array()
	for li in n:
		lay_se_start[li] = flat.size()
		if lay_alive[li] == 0:
			continue
		var loop: PackedInt32Array = lay_vids[li]
		var m := loop.size()
		for k in m:
			var u := loop[k]
			var v := loop[(k + 1) % m]
			if u == v:
				flat.append(-1)
				continue
			var lo := mini(u, v)
			var hi := maxi(u, v)
			var key := lo * big + hi
			var idx: int = se_index.get(key, -1)
			var sign := 1
			if idx < 0:
				idx = se_a.size()
				se_a.append(u)
				se_b.append(v)
				se_creator.append(li)
				se_creator_k.append(k)
				se_src.append([])
				se_index[key] = idx
			elif se_a[idx] != u:
				sign = -1
			se_src[idx].append(li)
			se_src[idx].append(sign)
			flat.append(idx)
	lay_se_flat = flat


# --- 5. what is solid on each side, at every height --------------------------------------------------

func _contain(p: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cand = lay_cells.get(Vector2i(floori(p.x / HC), floori(p.y / HC)))
	if cand == null:
		return out
	for li: int in cand:
		if (lay_rect[li] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, lay_poly[li]):
			out.append(li)
	return out


func _surface(list: PackedInt32Array, ym: float) -> int:
	## The ADD layer that is the solid at height ym (highest priority), or -1 when there is none.
	var best := -1
	var best_p := -1
	for a in list:
		if lay_op[a] != OP_ADD or ym <= lay_y0[a] or ym >= lay_y1[a]:
			continue
		var g := lay_group[a]
		var cut := false
		for c in list:
			if lay_op[c] == OP_CUT and lay_group[c] == g and ym > lay_y0[c] and ym < lay_y1[c]:
				cut = true
				break
		if cut:
			continue
		var pr := lay_prio[a] * 65536 + a
		if pr > best_p:
			best = a
			best_p = pr
	return best


func _cut_zone(list: PackedInt32Array, ym: float, group: int) -> int:
	## Zone override of a cut of `group` that is open at ym (the inside of a slit), or -1.
	for c in list:
		if lay_op[c] == OP_CUT and lay_group[c] == group and ym > lay_y0[c] and ym < lay_y1[c] and lay_zone[c] >= 0:
			return lay_zone[c]
	return -1


func inside_point(p: Vector3) -> bool:
	## Is the 3D point inside the masonry? (valid after run(); used by checks)
	var lst := _contain(Vector2(p.x, p.z))
	return _surface(lst, p.y) >= 0


var kl_layers := PackedInt32Array()          # scratch of the last _side_key: the layers of the key


func _side_key(mid: Vector2, src: Array) -> PackedInt32Array:
	## Everything the classification of a sub-edge depends on: the layers that own it and those that hold all of it (the
	## middle decides), in the order of their numbers, each as what the classification looks at (its attributes, which of the
	## layers share a group, what it is to the sub-edge). The key does not say where the sub-edge is or which layers they
	## are, so sub-edges with the same key share one result, also from one plan to the next. kl_layers gets the layers themselves.
	var extras := PackedInt32Array()
	var ns := src.size()
	var cand = lay_cells.get(Vector2i(floori(mid.x / HC), floori(mid.y / HC)))
	if cand != null:
		var px := mid.x
		var py := mid.y
		var rx0 := lay_rx0
		var rz0 := lay_rz0
		var rx1 := lay_rx1
		var rz1 := lay_rz1
		var s0: int = src[0]
		for li: int in cand:
			if px < rx0[li] or py < rz0[li] or px >= rx1[li] or py >= rz1[li]:
				continue
			if li == s0:
				continue
			var own := false
			for k in range(2, ns, 2):
				if src[k] == li:
					own = true
					break
			if own:
				continue
			if Geometry2D.is_point_in_polygon(mid, lay_poly[li]):
				extras.append(li)
	var key := PackedInt32Array()
	var layers := PackedInt32Array()
	var groups := PackedInt32Array()
	var si := 0
	var ei := 0
	var ne := extras.size()
	while si < ns or ei < ne:
		var li2: int
		var role: int
		if si < ns and (ei >= ne or int(src[si]) < extras[ei]):
			li2 = src[si]
			role = 1 if int(src[si + 1]) == 1 else 2
			si += 2
		else:
			li2 = extras[ei]
			role = 0
			ei += 1
		var g := lay_group[li2]
		var gc := groups.find(g)
		if gc < 0:
			gc = groups.size()
			groups.append(g)
		key.append((lay_attr[li2] << 12) | (gc << 2) | role)
		layers.append(li2)
	kl_layers = layers
	return key


func _sides(layers: PackedInt32Array, key: PackedInt32Array, src_ids: PackedInt32Array, cl: PackedInt32Array, cr: PackedInt32Array) -> void:
	## The layers that hold the left and the right side of a sub-edge. A layer that owns the sub-edge says so itself (its
	## outline runs counter-clockwise: its inside is on the left of its own direction); every other layer either holds the
	## whole sub-edge or none of it. The owners come first, then the others.
	for i in layers.size():
		var r := key[i] & 3
		if r == 0:
			continue
		src_ids.append(layers[i])
		if r == 1:
			cl.append(layers[i])
		else:
			cr.append(layers[i])
	for i in layers.size():
		if key[i] & 3 == 0:
			cl.append(layers[i])
			cr.append(layers[i])


func _pick_src(src: PackedInt32Array, tag: int, ym: float) -> int:
	var first := -1
	for li in src:
		if li == tag:
			return li
		if first < 0 and ym > lay_y0[li] and ym < lay_y1[li]:
			first = li
	if first >= 0:
		return first
	return src[0] if src.size() > 0 else -1


var changed_layers := 0
var inner := {}                              # milliseconds spent in the parts of the stages (for the profile)
var reused_sub_edges := 0
var cmemo := {}                              # side key (cids) -> [walls, ledges]; the next plan looks keys up here first
var classified_sub_edges := 0


func _classify(prev: CFPlan) -> void:
	var n := se_a.size()
	se_walls.resize(n)
	se_ledges.resize(n)
	var pmemo := {}
	if prev != null and prev.reusable and attr_shared:
		pmemo = prev.cmemo
	cmemo = {}
	var pflat := PackedInt32Array()
	var pstart := PackedInt32Array()
	var pwalls: Array = []
	var pledges: Array = []
	var pcids: Array = []
	se_cids.resize(n)
	if prev != null:
		pflat = prev.lay_se_flat
		pstart = prev.lay_se_start
		pwalls = prev.se_walls
		pledges = prev.se_ledges
		pcids = prev.se_cids
	reused_sub_edges = 0
	classified_sub_edges = 0
	var tc0 := Time.get_ticks_usec()
	var t_keys := 0
	var t_side := 0
	var with_ledges := PackedInt32Array()
	for i in n:
		var c := se_creator[i]
		if stable[c] == 1:
			var j := pflat[pstart[old_of[c]] + se_creator_k[i]]
			se_walls[i] = pwalls[j]
			se_cids[i] = pcids[j]
			var lgr = pledges[j]
			se_ledges[i] = lgr
			if lgr != null:
				with_ledges.append(i)
			reused_sub_edges += 1
			continue
		var pa := vpos[se_a[i]]
		var pb := vpos[se_b[i]]
		if (pb - pa).length() < 1e-5:
			continue
		classified_sub_edges += 1
		var tk0 := Time.get_ticks_usec()
		var key := _side_key((pa + pb) * 0.5, se_src[i])
		var tk1 := Time.get_ticks_usec()
		t_side += tk1 - tk0
		var res = cmemo.get(key)
		if res == null:
			res = pmemo.get(key)
			if res == null:
				res = _classify_key(kl_layers, key)
				t_keys += Time.get_ticks_usec() - tk1
			cmemo[key] = res
		se_walls[i] = res[0]
		se_ledges[i] = res[1]
		if res[0] != null:
			# the slots of its wall pieces mean these layers
			var cids := PackedInt64Array()
			for li3 in kl_layers:
				cids.append(lay_cid[li3])
			se_cids[i] = cids
		if res[1] != null:
			with_ledges.append(i)
	inner["classify.side_keys"] = float(inner.get("classify.side_keys", 0.0)) + t_side / 1000.0
	inner["classify.new_keys"] = float(inner.get("classify.new_keys", 0.0)) + t_keys / 1000.0
	var tc1 := _tick("classify.loop", tc0)
	# the ledge edges of every level, in sub-edge order
	for i in with_ledges:
		var lg: Array = se_ledges[i]
		var ea := se_a[i]
		var eb := se_b[i]
		for k in range(0, lg.size(), 3):
			var lkey := Vector2i(int(roundf(float(lg[k]) / Q)), int(lg[k + 1]))
			var arr = ledges.get(lkey)
			if arr == null:
				arr = []
				ledges[lkey] = arr
			if int(lg[k + 2]) == 1:     # the region is on the left of a -> b: the edge runs that way
				arr.append(ea)
				arr.append(eb)
			else:
				arr.append(eb)
				arr.append(ea)
	_tick("classify.ledge_edges", tc1)


func _surfaces(list: PackedInt32Array, lv: PackedFloat64Array) -> PackedInt32Array:
	## _surface of the list at the middle of every interval between the levels lv: the layer that is solid there, or -1.
	var m1 := lv.size() - 1
	var out := PackedInt32Array()
	out.resize(m1)
	out.fill(-1)
	var add_id := PackedInt32Array()
	var add_pr := PackedInt32Array()
	var add_y0 := PackedFloat64Array()
	var add_y1 := PackedFloat64Array()
	var add_g := PackedInt32Array()
	var cut_g := PackedInt32Array()
	var cut_y0 := PackedFloat64Array()
	var cut_y1 := PackedFloat64Array()
	for a in list:
		var op := lay_op[a]
		if op == OP_ADD:
			add_id.append(a)
			add_pr.append(lay_prio[a] * 65536 + a)
			add_y0.append(lay_y0[a])
			add_y1.append(lay_y1[a])
			add_g.append(lay_group[a])
		elif op == OP_CUT:
			cut_g.append(lay_group[a])
			cut_y0.append(lay_y0[a])
			cut_y1.append(lay_y1[a])
	var na := add_id.size()
	var nc := cut_g.size()
	if na == 0:
		return out
	if na > 4095:
		return _surfaces_plain(list, lv)
	# the layers in order of priority (the highest last): the first one that stands at a height and is not cut is the solid there
	var order := PackedInt64Array()
	for x in na:
		order.append((add_pr[x] << 12) | (4095 - x))
	order.sort()
	for k in m1:
		var ym := (lv[k] + lv[k + 1]) * 0.5
		for t in range(na - 1, -1, -1):
			var x := 4095 - int(order[t] & 4095)
			if ym <= add_y0[x] or ym >= add_y1[x]:
				continue
			var cut := false
			var g := add_g[x]
			for c in nc:
				if cut_g[c] == g and ym > cut_y0[c] and ym < cut_y1[c]:
					cut = true
					break
			if cut:
				continue
			out[k] = add_id[x]
			break
	return out


func _surfaces_plain(list: PackedInt32Array, lv: PackedFloat64Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in range(lv.size() - 1):
		out.append(_surface(list, (lv[k] + lv[k + 1]) * 0.5))
	return out


func _cap_heights(list: PackedInt32Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for c in list:
		if lay_op[c] == OP_CAP:
			out.append(lay_y0[c])
	return out


func _capped(caps: PackedFloat64Array, y: float) -> bool:
	for cy in caps:
		if absf(cy - y) < YE:
			return true
	return false


func _classify_key(layers: PackedInt32Array, key: PackedInt32Array) -> Array:
	## [walls, ledges] of a sub-edge whose key lists these layers (see se_walls / se_ledges), or [null, null].
	var cl := PackedInt32Array()
	var cr := PackedInt32Array()
	var src := PackedInt32Array()
	_sides(layers, key, src, cl, cr)
	var ys := PackedFloat64Array()
	for li in cl:
		ys.append(lay_y0[li])
		ys.append(lay_y1[li])
	for li in cr:
		ys.append(lay_y0[li])
		ys.append(lay_y1[li])
	ys.sort()
	var lv := PackedFloat64Array()
	for y in ys:
		if lv.is_empty() or y - lv[lv.size() - 1] > YE:
			lv.append(y)
	var m := lv.size()
	if m < 2:
		return [null, null]
	var sl := _surfaces(cl, lv)
	var sr := _surfaces(cr, lv)
	var caps_l := _cap_heights(cl)
	var caps_r := _cap_heights(cr)
	var walls := []
	# walls: runs of intervals with the same face
	var run_start := -1
	var run_tag := -1
	var run_src := -1
	var run_zo := -1
	var run_fwd := true
	for k in range(m):
		var tag := -1
		var srcl := -1
		var zo := -1
		var fwd := true
		if k < m - 1:
			var inl := sl[k] >= 0
			var inr := sr[k] >= 0
			if inl != inr:
				fwd = inl
				tag = sl[k] if inl else sr[k]
				var ym2 := (lv[k] + lv[k + 1]) * 0.5
				zo = _cut_zone(cr if inl else cl, ym2, lay_group[tag])
				srcl = _pick_src(src, tag, ym2)
		if run_start >= 0 and tag == run_tag and srcl == run_src and zo == run_zo and fwd == run_fwd:
			continue
		if run_start >= 0 and run_tag >= 0:
			walls.append_array([1 if run_fwd else 0, lv[run_start], lv[k], layers.find(run_tag), layers.find(run_src) if run_src >= 0 else -1, run_zo])
		run_start = k
		run_tag = tag
		run_src = srcl
		run_zo = zo
		run_fwd = fwd
	# ledges: at every height, where the solid starts or ends
	var ledge_list := []
	for k in range(m):
		var y := lv[k]
		var bl := k > 0 and sl[k - 1] >= 0
		var br := k > 0 and sr[k - 1] >= 0
		var al := k < m - 1 and sl[k] >= 0
		var ar := k < m - 1 and sr[k] >= 0
		var upl := bl and not al and not _capped(caps_l, y)
		var upr := br and not ar and not _capped(caps_r, y)
		if upl != upr:
			ledge_list.append_array([y, 1, 1 if upl else 0])
		if absf(y - GROUND) > YE:
			var dnl := (not bl) and al
			var dnr := (not br) and ar
			if dnl != dnr:
				ledge_list.append_array([y, -1, 1 if dnl else 0])
	return [walls if not walls.is_empty() else null, ledge_list if not ledge_list.is_empty() else null]


func _ledge(y: float, kind: int, a: int, b: int, region_on_left: bool) -> void:
	var key := Vector2i(int(roundf(y / Q)), kind)
	if not ledges.has(key):
		ledges[key] = []
	var arr: Array = ledges[key]
	if region_on_left:
		arr.append(a)
		arr.append(b)
	else:
		arr.append(b)
		arr.append(a)


func piece_list() -> Array:
	## Debug: the wall pieces as [u, v, y0, y1, tag layer, source layer, zone override], in mesh order.
	var out := []
	var idx := _uid_index()
	for li in lay_stack.size():
		if lay_alive[li] == 0:
			continue
		var start := lay_se_start[li]
		for k in lay_vids[li].size():
			var i := lay_se_flat[start + k]
			if i < 0 or se_creator[i] != li or se_creator_k[i] != k or se_walls[i] == null:
				continue
			var w: Array = se_walls[i]
			var cids: PackedInt64Array = se_cids[i]
			for r in range(0, w.size(), 6):
				var tag: int = idx.get(cids[int(w[r + 3])], -1)
				var srcl: int = idx.get(cids[int(w[r + 4])], -1) if int(w[r + 4]) >= 0 else -1
				if int(w[r]) == 1:
					out.append([se_a[i], se_b[i], w[r + 1], w[r + 2], tag, srcl, int(w[r + 5])])
				else:
					out.append([se_b[i], se_a[i], w[r + 1], w[r + 2], tag, srcl, int(w[r + 5])])
	return out


func _uid_index() -> Dictionary:
	var d := {}
	for li in lay_stack.size():
		if lay_alive[li] == 1 and not d.has(lay_cid[li]):
			d[lay_cid[li]] = li
	return d


# --- 6. the walls ---------------------------------------------------------------------------------

var wall_layers_built := 0


func _emit_walls(mesh: CFMesh, prev: CFPlan) -> void:
	## The wall pieces of the sub-edges each layer created are one bucket of mesh, kept for the next plan. Buckets of stable
	## layers are the previous ones; the others are made here. Appending them in layer order is the order a full build has.
	var n := lay_stack.size()
	var tw0 := Time.get_ticks_usec()
	lay_wall = []
	lay_wall.resize(n)
	uid_idx = _uid_index()
	var need := PackedByteArray()
	need.resize(vpos.size())
	var todo: Array = []
	for li in n:
		if lay_alive[li] == 0:
			continue
		if stable[li] == 1:
			lay_wall[li] = prev.lay_wall[old_of[li]]
			continue
		var start := lay_se_start[li]
		var any := false
		for k in lay_vids[li].size():
			var i := lay_se_flat[start + k]
			if i < 0 or se_creator[i] != li or se_creator_k[i] != k or se_walls[i] == null:
				continue
			need[se_a[i]] = 1
			need[se_b[i]] = 1
			any = true
		if any:
			todo.append(li)
	wall_layers_built = todo.size()
	var tw1 := _tick("walls.mark", tw0)
	if not todo.is_empty():
		# the pieces round the vertices the new pieces touch: their heights and their directions
		var adj := {}
		for i in se_a.size():
			if se_walls[i] == null:
				continue
			var a := se_a[i]
			var b := se_b[i]
			if need[a] == 1:
				if not adj.has(a):
					adj[a] = []
				adj[a].append(i)
			if need[b] == 1:
				if not adj.has(b):
					adj[b] = []
				adj[b].append(i)
		var levels := {}
		var ends := {}
		tw1 = _tick("walls.adjacency", tw1)
		for li in todo:
			var m := CFMesh.new()
			var start := lay_se_start[li]
			for k in lay_vids[li].size():
				var i := lay_se_flat[start + k]
				if i < 0 or se_creator[i] != li or se_creator_k[i] != k or se_walls[i] == null:
					continue
				var w: Array = se_walls[i]
				for r in range(0, w.size(), 6):
					_emit_wall(m, i, r, adj, levels, ends)
			lay_wall[li] = m
		tw1 = _tick("walls.build", tw1)
	for li in n:
		var wm = lay_wall[li]
		if wm != null:
			mesh.append_mesh(wm)
	_tick("walls.append", tw1)


func _levels_at(vid: int, adj: Dictionary, levels: Dictionary) -> Array:
	## Every height at which a wall piece starts or ends at this vertex (merged within YE), sorted.
	var got = levels.get(vid)
	if got != null:
		return got
	var arr: Array = []
	for i: int in adj.get(vid, []):
		var w: Array = se_walls[i]
		for r in range(0, w.size(), 6):
			arr.append(w[r + 1])
			arr.append(w[r + 2])
	arr.sort()
	var clean := []
	for y: float in arr:
		if clean.is_empty() or y - float(clean[clean.size() - 1]) > YE:
			clean.append(y)
	levels[vid] = clean
	return clean


func _chain(lst: Array, ya: float, yb: float) -> Array:
	var out := [ya]
	for y: float in lst:
		if y > ya + YE and y < yb - YE:
			out.append(y)
	out.append(yb)
	return out


func _pieces_at(vid: int, adj: Dictionary, ends: Dictionary) -> Array:
	## [pieces starting here, pieces ending here], each [sub-edge, record, from, to, y0, y1].
	var got = ends.get(vid)
	if got != null:
		return got
	var outs: Array = []
	var ins: Array = []
	for i: int in adj.get(vid, []):
		var w: Array = se_walls[i]
		for r in range(0, w.size(), 6):
			var fwd := int(w[r]) == 1
			var u: int = se_a[i] if fwd else se_b[i]
			var v: int = se_b[i] if fwd else se_a[i]
			var pc := [i, r, u, v, w[r + 1], w[r + 2]]
			if u == vid:
				outs.append(pc)
			if v == vid:
				ins.append(pc)
	var res := [outs, ins]
	ends[vid] = res
	return res


func _turn_real(u: int, v: int, ou: int, ov: int) -> bool:
	## Is the corner between the piece u -> v and the piece ou -> ov (which continues it) sharper than TURN_REAL?
	var pu := vpos[u]
	var pv := vpos[v]
	var d1 := (pv - pu).normalized()
	var d2 := (vpos[ov] - vpos[ou]).normalized()
	return absf(atan2(d1.cross(d2), d1.dot(d2))) > TURN_REAL


func _end_real(i: int, r: int, u: int, v: int, ya: float, yb: float, at_v: bool, adj: Dictionary, ends: Dictionary) -> bool:
	var vid := v if at_v else u
	var pcs: Array = _pieces_at(vid, adj, ends)
	var cands: Array = pcs[0] if at_v else pcs[1]
	var smooth := false
	for o: Array in cands:
		if int(o[0]) == i and int(o[1]) == r:
			continue
		if float(o[4]) >= yb - YE or float(o[5]) <= ya + YE:
			continue   # no height in common
		if not _turn_real(u, v, int(o[2]), int(o[3])):
			smooth = true
		else:
			return true
	return not smooth


func _emit_wall(mesh: CFMesh, si: int, r: int, adj: Dictionary, levels: Dictionary, ends: Dictionary) -> void:
	var w: Array = se_walls[si]
	var fwd := int(w[r]) == 1
	var u: int = se_a[si] if fwd else se_b[si]
	var v: int = se_b[si] if fwd else se_a[si]
	var ya: float = w[r + 1]
	var yb: float = w[r + 2]
	var cids: PackedInt64Array = se_cids[si]
	var tag: int = uid_idx.get(cids[int(w[r + 3])], -1)
	var srcl: int = uid_idx.get(cids[int(w[r + 4])], -1) if int(w[r + 4]) >= 0 else -1
	var zo: int = int(w[r + 5])
	var pu := vpos[u]
	var pv := vpos[v]
	var dir := pv - pu
	var l := dir.length()
	if l < 1e-6:
		return
	var d := dir / l
	var n2 := Vector2(d.y, -d.x)                  # interior on the left, outside on the right
	var nf := Vector3(n2.x, 0.0, n2.y)
	var tan3 := Vector3(nf.z, 0.0, -nf.x)         # up x normal: the direction u grows in
	var st: Dictionary = stacks[lay_stack[tag]]
	var sst: Dictionary = stacks[lay_stack[srcl]] if srcl >= 0 else st
	var curved: bool = bool(sst.round)
	var zone: int = zo if zo >= 0 else (lay_zone[tag] if lay_zone[tag] >= 0 else int(st.zone))
	mesh.begin(zone, float(st.seed), int(st.flags) | (CFMesh.F_ROUND if curved else 0), int(st.owner), st.anchor, str(st.label))
	var tp0 := Time.get_ticks_usec()
	var real_u := _end_real(si, r, u, v, ya, yb, false, adj, ends)
	var real_v := _end_real(si, r, u, v, ya, yb, true, adj, ends)
	var tp1 := _tick("walls.piece.end_real", tp0)
	var cu: Array = _chain(_levels_at(u, adj, levels), ya, yb)
	var cv: Array = _chain(_levels_at(v, adj, levels), ya, yb)
	var tp2 := _tick("walls.piece.levels", tp1)
	var cen: Vector2 = sst.center
	var radius: float = sst.radius
	var phase := float(sst.uvoff)
	# u coordinate at each end
	var uu: float
	var uv_: float
	var nu := nf
	var nv := nf
	if curved:
		var ru := pu - cen
		var rv := pv - cen
		var au := atan2(ru.y, ru.x)
		var av := atan2(rv.y, rv.x)
		var dphi := fposmod(av - au + PI, TAU) - PI
		uu = -au * radius + phase
		uv_ = uu - dphi * radius
		nu = Vector3(ru.x, 0.0, ru.y).normalized()
		nv = Vector3(rv.x, 0.0, rv.y).normalized()
		if nu.dot(nf) < 0.0:
			nu = -nu
			nv = -nv
	else:
		uu = pu.x * tan3.x + pu.y * tan3.z + phase
		uv_ = pv.x * tan3.x + pv.y * tan3.z + phase
	var tp3 := _tick("walls.piece.curve", tp2)
	var tangent_u := tan3
	# the distances to the piece's two ends along it (0 and l), or none when that end is smooth: the same for every triangle
	var e_u0 := 0.0 if real_u else CFMesh.NO_EDGE
	var e_v0 := l if real_v else CFMesh.NO_EDGE
	var e_u1 := l if real_u else CFMesh.NO_EDGE
	var e_v1 := 0.0 if real_v else CFMesh.NO_EDGE
	var i := 0
	var j := 0
	var flags_f: int = mesh.flags
	while i < cu.size() - 1 or j < cv.size() - 1:
		var take_u := false
		if j >= cv.size() - 1:
			take_u = true
		elif i >= cu.size() - 1:
			take_u = false
		else:
			take_u = float(cu[i + 1]) <= float(cv[j + 1]) + 1e-9
		var ui: float = cu[i]
		var vj: float = cv[j]
		if take_u:
			var uj: float = cu[i + 1]
			mesh.push_tri3(Vector3(pu.x, ui, pu.y), Vector3(pu.x, uj, pu.y), Vector3(pv.x, vj, pv.y), nu, nu, nv,
				Vector2(uu, ui), Vector2(uu, uj), Vector2(uv_, vj), tangent_u, 1.0,
				Vector4(e_u0, e_v0, ui - ya, yb - ui), Vector4(e_u0, e_v0, uj - ya, yb - uj), Vector4(e_u1, e_v1, vj - ya, yb - vj), flags_f, nf)
			i += 1
		else:
			var vk: float = cv[j + 1]
			mesh.push_tri3(Vector3(pu.x, ui, pu.y), Vector3(pv.x, vk, pv.y), Vector3(pv.x, vj, pv.y), nu, nv, nv,
				Vector2(uu, ui), Vector2(uv_, vk), Vector2(uv_, vj), tangent_u, 1.0,
				Vector4(e_u0, e_v0, ui - ya, yb - ui), Vector4(e_u1, e_v1, vk - ya, yb - vk), Vector4(e_u1, e_v1, vj - ya, yb - vj), flags_f, nf)
			j += 1
	_tick("walls.piece.tris", tp3)


# --- 7. the ledges ---------------------------------------------------------------------------------

var ledge_keys: Array = []


var ledge_cache := {}                        # [y, up, outer, holes] -> [signature, CFMesh, triangulation failures]
var ledge_hits := 0
var ledge_t := 0
var ledge_misses := 0
var stamp := PackedInt32Array()
var stamp_token := 0


func _emit_ledges(mesh: CFMesh, prev: CFPlan) -> void:
	ledge_keys = ledges.keys()
	ledge_t = Time.get_ticks_usec()
	ledge_hits = 0
	ledge_misses = 0
	stamp.resize(lay_stack.size())
	var pcache := {}
	if prev != null and prev.reusable:
		pcache = prev.ledge_cache
	for key: Vector2i in ledge_keys:
		_emit_ledge_level(mesh, float(key.x) * Q, key.y > 0, ledges[key], pcache)


var imbalance_shown := 0


func _emit_ledge_level(mesh: CFMesh, y: float, up: bool, arr: Array, pcache: Dictionary) -> void:
	# directed edges from -> to with the region on the left
	var open0 := open_loops
	var m := arr.size() / 2
	# the edges that leave each vertex, as a chain through link[] in ascending order (first[vertex] is the first)
	var first := {}
	var link := PackedInt32Array()
	link.resize(m)
	for k in range(m - 1, -1, -1):
		var f: int = arr[k * 2]
		link[k] = first.get(f, -1)
		first[f] = k
	if debug:
		var out_edges := {}
		for k in m:
			var f2: int = arr[k * 2]
			if not out_edges.has(f2):
				out_edges[f2] = []
			out_edges[f2].append(k)
		var indeg := {}
		for k in m:
			var t: int = arr[k * 2 + 1]
			indeg[t] = int(indeg.get(t, 0)) + 1
		var shown := 0
		for v in out_edges:
			var o: int = (out_edges[v] as Array).size()
			if o != int(indeg.get(v, 0)) and shown < 3 and imbalance_shown < 12:
				shown += 1
				imbalance_shown += 1
				print("  IMBALANCE y=%.3f up=%s vertex %s in=%d out=%d" % [y, up, vpos[v], int(indeg.get(v, 0)), o])
		for v in indeg:
			if not out_edges.has(v) and shown < 3 and imbalance_shown < 12:
				shown += 1
				imbalance_shown += 1
				print("  IMBALANCE y=%.3f up=%s vertex %s in=%d out=0" % [y, up, vpos[v], int(indeg[v])])
	var used := PackedByteArray()
	used.resize(m)
	var loops: Array = []
	for k0 in m:
		if used[k0] == 1:
			continue
		var loop := PackedInt32Array()
		var cur := k0
		var guard := 0
		while guard < m + 2:
			guard += 1
			used[cur] = 1
			loop.append(arr[cur * 2])
			var to: int = arr[cur * 2 + 1]
			var best := -1
			var best_cw := 99.0
			var pf := vpos[arr[cur * 2]]
			var pt := vpos[to]
			var back := (pf - pt)
			var ang_back := atan2(back.y, back.x)
			var c: int = first.get(to, -1)
			while c >= 0:
				if used[c] == 0 or c == k0:
					var w := vpos[arr[c * 2 + 1]] - pt
					var cw := fposmod(ang_back - atan2(w.y, w.x), TAU)
					if cw < 1e-9:
						cw = TAU
					if cw < best_cw:
						best_cw = cw
						best = c
				c = link[c]
			if best < 0:
				open_loops += 1
				if debug and open_loops <= 12:
					var n_out := 0
					var c2: int = first.get(to, -1)
					while c2 >= 0:
						n_out += 1
						c2 = link[c2]
					print("  open loop y=%.3f up=%s stuck at %s after %d edges (out edges there: %d)" % [y, up, pt, loop.size(), n_out])
				loop = PackedInt32Array()
				break
			if best == k0:
				break
			cur = best
		if loop.size() >= 3:
			loops.append(loop)
	ledge_t = _tick("ledges.trace", ledge_t)
	# outers and holes
	var outers: Array = []
	var holes: Array = []
	for loop: PackedInt32Array in loops:
		var poly := PackedVector2Array()
		for v in loop:
			poly.append(vpos[v])
		var ar := CFTri.area(poly)
		if absf(ar) < 1e-7:
			continue
		if ar > 0.0:
			outers.append(poly)
		else:
			holes.append(poly)
	var assigned: Array = []
	for _o in outers.size():
		assigned.append([])
	for h: PackedVector2Array in holes:
		var best_o := -1
		var best_a := INF
		var probe := h[0]
		for oi in outers.size():
			var op: PackedVector2Array = outers[oi]
			var aa := CFTri.area(op)
			if aa < best_a and Geometry2D.is_point_in_polygon(probe, op):
				best_a = aa
				best_o = oi
		if best_o < 0:
			# the probe sits on the outer's boundary: try the polygon's middle
			var mid := Vector2.ZERO
			for p in h:
				mid += p
			mid /= float(h.size())
			for oi in outers.size():
				var op2: PackedVector2Array = outers[oi]
				var aa2 := CFTri.area(op2)
				if aa2 < best_a and Geometry2D.is_point_in_polygon(mid, op2):
					best_a = aa2
					best_o = oi
		if best_o >= 0:
			assigned[best_o].append(h)
	ledge_t = _tick("ledges.holes", ledge_t)
	var cacheable := open_loops == open0       # a level that lost edges is not cached (its edges still mark real boundaries)
	var ym := y - 0.002 if up else y + 0.002
	var nrm := Vector3.UP if up else Vector3.DOWN
	var real := {}
	var real_made := false
	for oi in outers.size():
		var outer: PackedVector2Array = outers[oi]
		var hs: Array = assigned[oi]
		var bb := Rect2(outer[0], Vector2.ZERO)
		for q in outer:
			bb = bb.expand(q)
		# what the tags of its triangles depend on: the layers standing at this height near the polygon
		var cands := _ledge_cands(bb, ym)
		var sig := cands.size()
		for li in cands:
			sig = sig ^ lay_cid[li] ^ lay_nxor[li]
		var ckey := [y, up, outer, hs]
		var hit = pcache.get(ckey) if cacheable else null
		ledge_t = _tick("ledges.cands_key", ledge_t)
		if hit != null and hit[0] == sig:
			mesh.append_mesh(hit[1])
			CFTri.fails += int(hit[2])
			ledge_hits += 1
			ledge_cache[ckey] = hit
			ledge_t = _tick("ledges.hit_append", ledge_t)
			continue
		ledge_misses += 1
		if not real_made:
			# which pairs of points are real boundary edges (for the edge wear)
			for k in m:
				real[_pair_key(vpos[arr[k * 2]], vpos[arr[k * 2 + 1]])] = true
			real_made = true
		ledge_t = _tick("ledges.real", ledge_t)
		var f0 := CFTri.fails
		var tris := CFTri.triangulate(outer, hs)
		ledge_t = _tick("ledges.triangulate", ledge_t)
		if CFTri.fails != f0 and debug:
			print("  ledge fail y=%.3f up=%s outer=%d verts holes=%d area=%.3f first=%s" % [y, up, outer.size(), hs.size(), CFTri.area(outer), outer[0]])
			var f := FileAccess.open("user://tri_fail_%d.txt" % CFTri.fails, FileAccess.WRITE)
			f.store_string(var_to_str([outer, hs]))
			f.close()
		var pm := CFMesh.new()
		for t in range(0, tris.size(), 3):
			_emit_ledge_tri(pm, y, up, nrm, tris[t], tris[t + 1], tris[t + 2], real, cands, ym)
		mesh.append_mesh(pm)
		if cacheable:
			ledge_cache[ckey] = [sig, pm, CFTri.fails - f0]
		ledge_t = _tick("ledges.tris", ledge_t)


func _ledge_cands(bb: Rect2, ym: float) -> PackedInt32Array:
	## The ADD and CUT layers that stand at height ym and whose rect meets bb.
	var out := PackedInt32Array()
	stamp_token += 1
	var tok := stamp_token
	var x0 := floori((bb.position.x - SNAP) / HC)
	var x1 := floori((bb.end.x + SNAP) / HC)
	var z0 := floori((bb.position.y - SNAP) / HC)
	var z1 := floori((bb.end.y + SNAP) / HC)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var cand = lay_cells.get(Vector2i(cx, cz))
			if cand == null:
				continue
			for li: int in cand:
				if stamp[li] == tok:
					continue
				stamp[li] = tok
				if lay_op[li] == OP_CAP or ym <= lay_y0[li] or ym >= lay_y1[li]:
					continue
				if lay_rx1[li] < bb.position.x or lay_rx0[li] > bb.end.x or lay_rz1[li] < bb.position.y or lay_rz0[li] > bb.end.y:
					continue
				out.append(li)
	return out


static func _pair_key(a: Vector2, b: Vector2) -> Vector4i:
	var ka := Vector2i(roundi(a.x / Q), roundi(a.y / Q))
	var kb := Vector2i(roundi(b.x / Q), roundi(b.y / Q))
	if ka.x < kb.x or (ka.x == kb.x and ka.y <= kb.y):
		return Vector4i(ka.x, ka.y, kb.x, kb.y)
	return Vector4i(kb.x, kb.y, ka.x, ka.y)


func _emit_ledge_tri(mesh: CFMesh, y: float, up: bool, nrm: Vector3, a: Vector2, b: Vector2, c: Vector2, real: Dictionary, cands: PackedInt32Array, ym: float) -> void:
	var cen := (a + b + c) / 3.0
	var tag := _ledge_tag(cen, cands, ym)
	var st: Dictionary = stacks[lay_stack[tag]] if tag >= 0 else {"zone": CFMesh.Z_FLAG, "top_zone": CFMesh.Z_FLAG, "seed": 0.0, "flags": 0, "owner": 0, "anchor": Vector3.ZERO, "label": ""}
	var zone: int = int(st.top_zone) if up else (int(st.zone) if int(st.zone) != CFMesh.Z_FLAG else CFMesh.Z_RUBBLE)
	if tag >= 0 and lay_zone[tag] >= 0 and not up:
		zone = lay_zone[tag]
	mesh.begin(zone, float(st.seed), int(st.flags), int(st.owner), st.anchor, str(st.label))
	var pa := Vector3(a.x, y, a.y)
	var pb := Vector3(b.x, y, b.y)
	var pc := Vector3(c.x, y, c.y)
	var tan3 := Vector3.RIGHT
	var bin := nrm.cross(tan3)
	var area2 := (pb - pa).cross(pc - pa).length()
	if area2 < 1e-9:
		return
	var ha := area2 / maxf((pc - pb).length(), 1e-6)
	var hb := area2 / maxf((pc - pa).length(), 1e-6)
	var hc := area2 / maxf((pb - pa).length(), 1e-6)
	var r_bc := real.has(_pair_key(b, c))
	var r_ca := real.has(_pair_key(c, a))
	var r_ab := real.has(_pair_key(a, b))
	var no := CFMesh.NO_EDGE
	var c_a := Vector4(ha if r_bc else no, 0.0 if r_ca else no, 0.0 if r_ab else no, no)
	var c_b := Vector4(0.0 if r_bc else no, hb if r_ca else no, 0.0 if r_ab else no, no)
	var c_c := Vector4(0.0 if r_bc else no, 0.0 if r_ca else no, hc if r_ab else no, no)
	mesh.push_tri3(pa, pb, pc, nrm, nrm, nrm, Vector2(pa.dot(tan3), pa.dot(bin)), Vector2(pb.dot(tan3), pb.dot(bin)), Vector2(pc.dot(tan3), pc.dot(bin)),
		tan3, 1.0, c_a, c_b, c_c, mesh.flags, nrm)


func _ledge_tag(p: Vector2, cands: PackedInt32Array, ym: float) -> int:
	## The ADD layer whose top (up) or bottom (down) surface is here (cands: the layers that stand at ym near the polygon).
	var here := PackedInt32Array()
	for li in cands:
		if p.x < lay_rx0[li] or p.y < lay_rz0[li] or p.x >= lay_rx1[li] or p.y >= lay_rz1[li]:
			continue
		if Geometry2D.is_point_in_polygon(p, lay_poly[li]):
			here.append(li)
	return _surface(here, ym)


# --- 8. what the next plan may take over -------------------------------------------------------------

func _finish() -> void:
	cid_index.clear()
	for li in lay_stack.size():
		if lay_alive[li] == 0:
			continue
		var cid := lay_cid[li]
		cid_index[cid] = -2 if cid_index.has(cid) else li
	reusable = true
	# the lookup tables of the run are not needed any more
	se_index.clear()
	e_splits.clear()
	e_splits.resize(0)
	vcell.clear()
	vexact.clear()
	uid_idx.clear()


func explain_vertex(p: Vector2, only_y: float = -1000.0) -> void:
	## Debug: every sub-edge at the vertex nearest p, what each side holds, and the states at each height.
	var best := -1
	var bd := INF
	for v in vpos.size():
		var d := vpos[v].distance_to(p)
		if d < bd:
			bd = d
			best = v
	print("vertex ", best, " at ", vpos[best])
	for i in se_a.size():
		if se_a[i] != best and se_b[i] != best:
			continue
		var pa := vpos[se_a[i]]
		var pb := vpos[se_b[i]]
		var l := (pb - pa).length()
		var mid := (pa + pb) * 0.5
		var cl := PackedInt32Array()
		var cr := PackedInt32Array()
		var src := PackedInt32Array()
		var kk := _side_key(mid, se_src[i])
		_sides(kl_layers, kk, src, cl, cr)
		print(" se ", i, " ", pa, " -> ", pb, " len ", l, " left layers ", cl, " right layers ", cr, " src ", se_src[i])
		var ys := PackedFloat64Array()
		for li in cl:
			ys.append(lay_y0[li])
			ys.append(lay_y1[li])
		for li in cr:
			ys.append(lay_y0[li])
			ys.append(lay_y1[li])
		ys.sort()
		var lv := PackedFloat64Array()
		for y in ys:
			if lv.is_empty() or y - lv[lv.size() - 1] > YE:
				lv.append(y)
		for k in range(lv.size() - 1):
			var ym := (lv[k] + lv[k + 1]) * 0.5
			if only_y > -999.0 and absf(ym - only_y) > 0.5:
				continue
			print("    y ", lv[k], "-", lv[k + 1], " left tag ", _surface(cl, ym), " right tag ", _surface(cr, ym))
