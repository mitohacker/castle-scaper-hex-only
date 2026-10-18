class_name CFAudit
extends RefCounted
## Measures how well the castle's skin holds together: every vertex welded by position, every edge
## shared by exactly two triangles (except on the ground), no vertex sitting on another edge (a
## T-junction crack), consistent winding, and how many separate pieces the skin falls into.

const W := 0.001


static func check(mesh: CFMesh, skip_zones: Array = []) -> Dictionary:
	var verts := mesh.verts
	var ids := {}
	var wpos := PackedVector3Array()
	var vid := PackedInt32Array()
	vid.resize(verts.size())
	for i in verts.size():
		var p := verts[i]
		var k := Vector3i(roundi(p.x / W), roundi(p.y / W), roundi(p.z / W))
		var id: int = ids.get(k, -1)
		if id < 0:
			id = wpos.size()
			ids[k] = id
			wpos.append(Vector3(k) * W)
		vid[i] = id
	var nv := wpos.size()
	var big := nv + 1
	var undirected := {}
	var edge_tri := {}
	var directed := {}
	var directed_tri := {}
	var tri_keys := {}
	var degenerate := 0
	var bad_normal := 0
	var dup_tris := 0
	var parent := PackedInt32Array()
	parent.resize(nv)
	for i in nv:
		parent[i] = i
	var tris := 0
	for t in range(0, verts.size(), 3):
		var zone := roundi(mesh.cols[t].r * 255.0)
		if zone in skip_zones:
			continue
		var a := vid[t]
		var b := vid[t + 1]
		var c := vid[t + 2]
		if a == b or b == c or a == c:
			degenerate += 1
			continue
		tris += 1
		var gn := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t])
		# front faces are clockwise: the geometric normal must oppose the stored one
		if gn.dot(mesh.norms[t] + mesh.norms[t + 1] + mesh.norms[t + 2]) > 0.0:
			bad_normal += 1
		var sorted := [a, b, c]
		sorted.sort()
		var tk := Vector3i(sorted[0], sorted[1], sorted[2])
		if tri_keys.has(tk):
			dup_tris += 1
		tri_keys[tk] = true
		for e in [[a, b], [b, c], [c, a]]:
			var u: int = e[0]
			var v: int = e[1]
			var key := mini(u, v) * big + maxi(u, v)
			undirected[key] = int(undirected.get(key, 0)) + 1
			if not edge_tri.has(key):
				edge_tri[key] = t
			var dk := u * big + v
			directed[dk] = int(directed.get(dk, 0)) + 1
			directed_tri[dk] = t
		_union(parent, a, b)
		_union(parent, b, c)
	var open_ground := 0
	var open_other := []
	var open_info := []
	var nm_info := []
	var non_manifold := 0
	for key: int in undirected:
		var n: int = undirected[key]
		if n == 1:
			var u := key / big
			var v := key % big
			if absf(wpos[u].y) < 0.002 and absf(wpos[v].y) < 0.002:
				open_ground += 1
			else:
				open_other.append([u, v])
				var tt: int = edge_tri[key]
				open_info.append("%s -> %s zone %d %s" % [wpos[u], wpos[v], roundi(mesh.cols[tt].r * 255.0), "owner %d" % int(mesh.cust1[tt * 4 + 3])])
		elif n > 2:
			non_manifold += 1
			var tt2: int = edge_tri[key]
			nm_info.append("%s -> %s x%d zone %d %s" % [wpos[key / big], wpos[key % big], n, roundi(mesh.cols[tt2].r * 255.0), "owner %d" % int(mesh.cust1[tt2 * 4 + 3])])
	var flipped := 0
	var flip_info := []
	for dk: int in directed:
		if int(directed[dk]) > 1:
			flipped += 1
			if flip_info.size() < 6:
				var ft: int = directed_tri[dk]
				flip_info.append("%s -> %s x%d zone %d tri %s %s %s normal %s" % [wpos[dk / big], wpos[dk % big], int(directed[dk]), roundi(mesh.cols[ft].r * 255.0), verts[ft], verts[ft + 1], verts[ft + 2], mesh.norms[ft]])
	# T-junctions: a welded vertex strictly inside an open edge
	var grid := {}
	for i in nv:
		var cell := Vector3i(floori(wpos[i].x / 2.0), floori(wpos[i].y / 2.0), floori(wpos[i].z / 2.0))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(i)
	var tj := 0
	var tj_examples := []
	for e: Array in open_other:
		var pa := wpos[e[0]]
		var pb := wpos[e[1]]
		var ab := pb - pa
		var l2 := ab.length_squared()
		var lo := pa.min(pb)
		var hi := pa.max(pb)
		var found := false
		for cx in range(floori(lo.x / 2.0), floori(hi.x / 2.0) + 1):
			for cy in range(floori(lo.y / 2.0), floori(hi.y / 2.0) + 1):
				for cz in range(floori(lo.z / 2.0), floori(hi.z / 2.0) + 1):
					for i: int in grid.get(Vector3i(cx, cy, cz), []):
						if i == e[0] or i == e[1]:
							continue
						var t := (wpos[i] - pa).dot(ab) / maxf(l2, 1e-12)
						if t > 0.0 and t < 1.0 and (pa + ab * t).distance_to(wpos[i]) < 0.0025:
							found = true
		if found:
			tj += 1
			if tj_examples.size() < 4:
				tj_examples.append("%s -> %s" % [pa, pb])
	var roots := {}
	var comp_tris := {}
	var comp_at := {}
	for t in range(0, verts.size(), 3):
		if roundi(mesh.cols[t].r * 255.0) in skip_zones:
			continue
		if vid[t] != vid[t + 1] and vid[t] != vid[t + 2]:
			var rt := _find(parent, vid[t])
			roots[rt] = true
			comp_tris[rt] = int(comp_tris.get(rt, 0)) + 1
			if not comp_at.has(rt):
				comp_at[rt] = "%s zone %d %s" % [verts[t], roundi(mesh.cols[t].r * 255.0), "owner %d" % int(mesh.cust1[t * 4 + 3])]
	var small := []
	for rt in comp_tris:
		small.append([comp_tris[rt], comp_at[rt]])
	small.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return {"tris": tris, "welded_verts": nv, "degenerate": degenerate, "bad_normal": bad_normal, "dup_tris": dup_tris,
		"open_ground": open_ground, "open_other": open_other.size(), "non_manifold": non_manifold, "flipped": flipped,
		"t_junctions": tj, "pieces": roots.size(), "examples": tj_examples, "open_info": open_info, "nm_info": nm_info, "flip_info": flip_info, "components": small}


static func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb
