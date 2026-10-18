class_name CSFacades
extends RefCounted
## Tells the shader where a facade begins and ends, so painted windows, pillars and timber frames fall in even bays that start and end at the
## corners. After the plan has made the walls, every vertical wall triangle of a styled block (and the gable triangles of its roof) is put in
## a group: the same column (owner), plane (direction within 0.6 degrees, offset within 2 cm), wall zone and colour. In each group the triangles'
## spans along the wall are merged into one facade (gaps up to GAP m are bridged: a door's recess); a facade is one side of one cell, wall and gable
## apart. Each vertex then gets UV2 = (its distance from the facade's left end as seen from outside, the facade's length); a facade with a door
## has its length negated (the door stands in the middle of the side). The wall's own UV (CFPlan) stays: u = the world coordinate along the wall
## (the direction (nz, -nx) of its outward normal), v = the world height. Faces flagged F_NOWIN (parapets, penthouses) are left alone (UV2 = 0).

const GAP := 1.7
const NOWIN := 128
const MIN_LEN := 0.9


static func is_zone(zone: int) -> bool:
	return (zone >= CSStyle.WALL + 1 and zone <= CSStyle.WALL + 6) or (zone >= CSStyle.GABLE + 1 and zone <= CSStyle.GABLE + 6)


static func _key(n2: Vector2, p: Vector3, zone: int, seed_g: float, owner: int) -> Vector4i:
	var ang := roundi(atan2(n2.y, n2.x) / 0.0105)
	var off := roundi((n2.x * p.x + n2.y * p.z) / 0.02)
	return Vector4i(ang, off, zone * 4096 + roundi(seed_g * 255.0), owner)


static func annotate(mesh: CFMesh, doors: Array = []) -> int:
	## doors: [{out: Vector2, p: Vector2, zone: int, seed: float, owner: int}] of the doors on facades. Returns the number of facades found.
	var verts := mesh.verts
	var cols := mesh.cols
	var norms := mesh.norms
	var cust1 := mesh.cust1
	var groups := {}                 # key -> {"n": Vector2, "tris": [], "s0": [], "s1": []}
	for t in range(0, verts.size(), 3):
		var zone := roundi(cols[t].r * 255.0)
		if not is_zone(zone):
			continue
		if (roundi(cols[t].b * 255.0) & NOWIN) != 0:
			continue
		var nn := norms[t]
		if absf(nn.y) > 0.35:
			continue
		var n2 := Vector2(nn.x, nn.z)
		if n2.length_squared() < 1e-6:
			continue
		n2 = n2.normalized()
		var tg := Vector2(n2.y, -n2.x)
		var key := _key(n2, verts[t], zone, cols[t].g, int(cust1[t * 4 + 3]))
		var g: Dictionary
		if groups.has(key):
			g = groups[key]
		else:
			g = {"n": n2, "tg": tg, "tris": [], "s0": [], "s1": []}
			groups[key] = g
		var s0 := INF
		var s1 := -INF
		for k in 3:
			var p := verts[t + k]
			var s := p.x * tg.x + p.z * tg.y
			s0 = minf(s0, s)
			s1 = maxf(s1, s)
		(g.tris as Array).append(t)
		(g.s0 as Array).append(s0)
		(g.s1 as Array).append(s1)
	var door_by_group := {}
	for d: Dictionary in doors:
		var o: Vector2 = d.out
		var tg2 := Vector2(o.y, -o.x).normalized()
		var pk := _key(o.normalized(), Vector3(d.p.x, 0.0, d.p.y), int(d.zone), float(d.seed), int(d.owner))
		if not door_by_group.has(pk):
			door_by_group[pk] = []
		(door_by_group[pk] as Array).append((d.p as Vector2).dot(tg2))
	var n_fac := 0
	for key: Vector4i in groups:
		var g: Dictionary = groups[key]
		var tris: Array = g.tris
		var order := range(tris.size())
		var s0a: Array = g.s0
		var s1a: Array = g.s1
		order.sort_custom(func(a: int, b: int) -> bool: return float(s0a[a]) < float(s0a[b]))
		var fac_of := {}                # triangle position -> facade index
		var facades: Array = []         # [s0, s1]
		for oi: int in order:
			var a0: float = s0a[oi]
			var a1: float = s1a[oi]
			if facades.is_empty() or a0 > float((facades[facades.size() - 1] as Array)[1]) + GAP:
				facades.append([a0, a1])
			else:
				(facades[facades.size() - 1] as Array)[1] = maxf(float((facades[facades.size() - 1] as Array)[1]), a1)
			fac_of[oi] = facades.size() - 1
		n_fac += facades.size()
		var has_door := []
		for _f in facades.size():
			has_door.append(false)
		for ds: float in door_by_group.get(key, []):
			for fi in facades.size():
				if ds >= float((facades[fi] as Array)[0]) - 0.2 and ds <= float((facades[fi] as Array)[1]) + 0.2:
					has_door[fi] = true
		var tg: Vector2 = g.tg
		for oi in tris.size():
			var t: int = tris[oi]
			var fi: int = fac_of[oi]
			var f0: float = (facades[fi] as Array)[0]
			var len := float((facades[fi] as Array)[1]) - f0
			for k in 3:
				var p := verts[t + k]
				var s := p.x * tg.x + p.z * tg.y
				mesh.uv2s[t + k] = Vector2(s - f0, -len if has_door[fi] else len)
	return n_fac
