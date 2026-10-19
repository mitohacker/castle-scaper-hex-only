class_name CSStyleProps
extends RefCounted
## The props of the building styles, placed after the castle's (CSProps.build calls build()): they come from the roofs and walls the rules made, not from a roll of dice
## alone. A chimney stands on the firewall side of a gable roof (where the neighbour's wall is) or at a corner of a hip, rooftop gear (air conditioners, a water tank, a
## mast, solar panels, planters) stands on a flat roof in the room the parapet and the penthouse leave, paper lanterns hang from the lifted corners of a curved roof and
## beside Chinese and Japanese doors, a torii stands in the sea in front of a Japanese house's water side, an awning shades a house door.
## Meshes: roof gear and lanterns are made once in make_mesh() (CSProps.make_meshes calls it for the indices from M_AC on).

const M_AC := 18
const M_TANK := 19
const M_MAST := 20
const M_SOLAR := 21
const M_PLANTER := 22
const M_PAPER := 23
const M_TORII := 24
const M_AWNING := 25
const MESH_END := 26

const CHIMNEY_COLS := [4, 11, 10, 3, 4, 4]


static func build(p: CSProps) -> void:
	_door_things(p)
	_chimneys(p)
	_roofgear(p)
	_eave_lanterns(p)
	_torii(p)


# --- doors -------------------------------------------------------------------------------------------

static func _door_things(p: CSProps) -> void:
	for op: Dictionary in p.b.openings:
		if str(op.kind) != "door":
			continue
		var sty := int(op.get("style", 0))
		if sty == CSStyle.CASTLE:
			continue
		var v: int = op.v
		var k: int = op.k
		var slot: int = v * 16 + int(op.i)
		var pt: Vector2 = op.p
		var o := Vector3(pt.x, float(op.y0), pt.y)
		var bas := CSProps.wall_basis(op.out)
		var kk := CSTown.key(v, k)
		if sty == CSStyle.CHINESE or sty == CSStyle.JAPANESE:
			# paper lanterns either side of the door (a pair of red ones; one white one now and then)
			var col := 0 if sty == CSStyle.CHINESE else 1
			var sides: Array = [-1.0, 1.0] if (sty == CSStyle.CHINESE or CSBuild.h01(slot, k, 301) < 0.35) else [1.0 if CSBuild.h01(slot, k, 302) < 0.5 else -1.0]
			for side: float in sides:
				var oo := o + bas.x * side * 0.72 + Vector3(0.0, 2.15, 0.0)
				var c := p._cand(CSProps.PAPER, 2.0, CSBuild.h01(slot, k, 303 + int(side > 0.0)), v, kk)
				c.boxes = [CSProps.box(oo, bas, Vector3(-0.2, -0.78, 0.0), Vector3(0.2, 0.05, 0.62))]
				c.inst = [[M_PAPER, Transform3D(bas, oo), 0, col]]
		else:
			# an iron lantern on a bracket beside the door (the castle's own), and now and then an awning over it
			var first := 1.0 if CSBuild.h01(slot, k, 81) < 0.5 else -1.0
			var m := p._mount(op, first * 0.6)
			var q: Vector2 = m[0]
			var oo := Vector3(q.x, float(op.y0) + 2.05, q.y)
			var bb := CSProps.wall_basis(m[1])
			var t := p._cand(CSProps.TORCH, 2.0, CSBuild.h01(slot, k, 83), v, kk)
			t.boxes = [CSProps.box(oo, bb, Vector3(-0.14, -0.36, 0.0), Vector3(0.14, 0.1, 0.4))]
			t.inst = [[CSProps.M_TORCH, Transform3D(bb, oo), 0, 0]]
			if sty != CSStyle.FANTASY and CSBuild.h01(slot, k, 304) < 0.5:
				var ao := o + Vector3(0.0, 2.72, 0.0)
				var cols := [4, 7, 8, 11, 2]
				var ca: int = cols[int(CSBuild.h01(slot, k, 305) * float(cols.size())) % cols.size()]
				var aw := p._cand(CSProps.AWNING, 2.5, CSBuild.h01(slot, k, 306), v, kk)
				aw.boxes = [CSProps.box(ao, bas, Vector3(-0.85, -0.34, 0.0), Vector3(0.85, 0.2, 0.95))]
				aw.inst = [[M_AWNING, Transform3D(bas, ao), ca, 1]]


# --- chimneys ----------------------------------------------------------------------------------------

static func _chimneys(p: CSProps) -> void:
	for kk: int in p.b.hats:
		var h: Dictionary = p.b.hats[kk]
		var rec: Dictionary = h.rec
		if str(rec.get("kind", "")) != "ridge":
			continue
		var s: int = h.style
		var chance := 0.0
		match s:
			CSStyle.HOUSE:
				chance = 0.6
			CSStyle.VILLAGE:
				chance = 0.7
			CSStyle.FANTASY:
				chance = 0.25
			CSStyle.JAPANESE:
				chance = 0.12
		var v: int = h.v
		var k: int = h.k
		if CSBuild.h01(v, k, 310) > chance:
			continue
		var poly: PackedVector2Array = h.poly
		var n := poly.size()
		var c := CSRoofs.centroid(poly)
		var cls := _classes(p.b, v, k)
		# the firewall side first (a chimney is built into the wall it shares with the neighbour), else a corner of the roof
		var spots: Array = []
		for j in n:
			if cls[j] != CSStyleBuild.OPEN:
				spots.append([(poly[j] + poly[(j + 1) % n]) * 0.5, 0.64, 0.0])
		for j in n:
			spots.append([poly[j], 0.5, 1.0])
		var col: int = CHIMNEY_COLS[int(CSBuild.h01(v, k, 311) * float(CHIMNEY_COLS.size())) % CHIMNEY_COLS.size()]
		var gi := 0
		for sp: Array in spots:
			var q: Vector2 = c + ((sp[0] as Vector2) - c) * float(sp[1])
			var out := ((sp[0] as Vector2) - c).normalized()
			var bas := CSProps.wall_basis(out)
			var lo := INF
			var hi := -INF
			for sx: float in [-0.3, 0.3]:
				for sz: float in [-0.3, 0.3]:
					var pt := q + Vector2(bas.x.x, bas.x.z) * sx + out * sz
					var y := CSRoofs.ridge_height(rec, pt)
					lo = minf(lo, y)
					hi = maxf(hi, y)
			if hi - lo > 1.6:
				continue
			var top := hi + 0.7
			var ch := p._cand(CSProps.CHIMNEY, 1.5 + 0.2 * float(gi), CSBuild.h01(v * 16 + gi, k, 312), v, kk)
			gi += 1
			ch.group = "chimney %d" % kk
			ch.own_roof = kk
			ch.boxes = [CSProps.box(Vector3(q.x, 0.0, q.y), bas, Vector3(-0.3, lo, -0.3), Vector3(0.3, top + 0.13, 0.3))]
			var foot := lo - 0.3
			ch.inst = [[CSProps.M_CHIMNEY, Transform3D(Basis(bas.x, bas.y * (top - foot), bas.z), Vector3(q.x, foot, q.y)), col, 0],
				[CSProps.M_CHIMNEY_CAP, Transform3D(bas, Vector3(q.x, top, q.y)), col, 0]]
			ch.perch = Vector3(q.x, top + 0.13, q.y)


static func _classes(b: CSBuild, v: int, k: int) -> PackedByteArray:
	## OPEN / PARTY / TALL for each side of block (v, k), as CSStyleBuild reads them.
	var out := PackedByteArray()
	for u in b.grid.nbrs[v]:
		if b.filled(u, k + 1):
			out.append(CSStyleBuild.TALL)
		elif b.filled(u, k):
			out.append(CSStyleBuild.PARTY)
		else:
			out.append(CSStyleBuild.OPEN)
	return out


# --- rooftop gear ------------------------------------------------------------------------------------

static func _inside(poly: PackedVector2Array, pt: Vector2, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(pt, poly):
		return false
	var n := poly.size()
	for i in n:
		if Geometry2D.get_closest_point_to_segment(pt, poly[i], poly[(i + 1) % n]).distance_to(pt) < margin:
			return false
	return true


static func _roofgear(p: CSProps) -> void:
	for kk: int in p.b.hats:
		var h: Dictionary = p.b.hats[kk]
		var rec: Dictionary = h.rec
		if str(rec.get("kind", "")) != "slab":
			continue
		var s: int = h.style
		var v: int = h.v
		var k: int = h.k
		var inner: PackedVector2Array = rec.inner
		var area := absf(CSRoofs.area2(inner)) * 0.5
		var deck: float = rec.deck
		var pent: PackedVector2Array = rec.get("penthouse", PackedVector2Array())
		var count := clampi(int(area / 6.0 * (0.6 + CSBuild.h01(v, k, 320))), 0, 5)
		var kinds: Array = []
		match s:
			CSStyle.APARTMENT:
				kinds = [M_AC, M_AC, M_AC, M_TANK, M_MAST, M_SOLAR, M_SOLAR]
			CSStyle.HOUSE:
				kinds = [M_PLANTER, M_PLANTER, M_AC, M_SOLAR]
			_:
				kinds = [M_PLANTER]
		var c := CSRoofs.centroid(inner)
		for gi in count:
			var mesh: int = kinds[int(CSBuild.h01(v * 8 + gi, k, 321) * float(kinds.size())) % kinds.size()]
			# a spot in the room that is left: tried in a seeded order, the first that fits
			var placed := false
			for tr in 8:
				var a := CSBuild.h01(v * 64 + gi * 8 + tr, k, 322)
				var bq := CSBuild.h01(v * 64 + gi * 8 + tr, k, 323)
				var ring := inner[int(a * float(inner.size())) % inner.size()]
				var pt := c + (ring - c) * (0.15 + 0.7 * bq)
				if not _inside(inner, pt, 0.9):
					continue
				if pent.size() >= 3 and (Geometry2D.is_point_in_polygon(pt, pent) or _inside(pent, pt, -0.9)):
					continue
				var yaw := CSBuild.h01(v * 64 + gi, k, 324) * TAU
				var bas := Basis(Vector3.UP, yaw)
				var half := Vector3(0.5, 0.0, 0.4)
				var height := 0.75
				match mesh:
					M_TANK:
						half = Vector3(0.7, 0.0, 0.7)
						height = 1.9
					M_MAST:
						half = Vector3(0.35, 0.0, 0.35)
						height = 3.3
					M_SOLAR:
						half = Vector3(0.65, 0.0, 0.5)
						height = 0.6
					M_PLANTER:
						half = Vector3(0.65, 0.0, 0.3)
						height = 0.9
				var o := Vector3(pt.x, deck, pt.y)
				var cand := p._cand(CSProps.ROOFGEAR, 3.0, CSBuild.h01(v * 8 + gi, k, 325), v, kk)
				cand.own_roof = kk
				cand.boxes = [CSProps.box(o, bas, Vector3(-half.x, 0.0, -half.z), Vector3(half.x, height, half.z))]
				cand.inst = [[mesh, Transform3D(bas, o), 4 if mesh == M_PLANTER else 10, 0]]
				placed = true
				break
			if not placed:
				continue


# --- eaves -------------------------------------------------------------------------------------------

static func _eave_lanterns(p: CSProps) -> void:
	for kk: int in p.b.hats:
		var h: Dictionary = p.b.hats[kk]
		var rec: Dictionary = h.rec
		if h.style != CSStyle.CHINESE or str(rec.get("kind", "")) != "pyramid" or not rec.has("tips"):
			continue
		var v: int = h.v
		var k: int = h.k
		var ctr: Vector2 = rec.centre2
		var i := 0
		for tip: Vector3 in rec.tips:
			i += 1
			if CSBuild.h01(v * 8 + i, k, 330) > 0.6:
				continue
			# hung from a bracket at the corner, reaching out along the corner's diagonal
			var out := (Vector2(tip.x, tip.z) - ctr).normalized()
			var bas := CSProps.wall_basis(out)
			var o := tip - Vector3(out.x, 0.0, out.y) * 0.12
			var c := p._cand(CSProps.PAPER, 4.0, CSBuild.h01(v * 8 + i, k, 331), v, kk)
			c.own_roof = kk
			c.boxes = [CSProps.box(o, bas, Vector3(-0.2, -0.82, -0.1), Vector3(0.2, 0.05, 0.62))]
			c.inst = [[M_PAPER, Transform3D(bas, o), 0, 0]]


# --- the torii -----------------------------------------------------------------------------------------

static func _torii(p: CSProps) -> void:
	for v: int in p.town.columns():
		if not p.grid.buildable(v) or not p.town.has(v, 0) or p.town.style(v, 0) != CSStyle.JAPANESE:
			continue
		if CSBuild.h01(v, 340) > 0.22:
			continue
		var door := int(p.b.doors.get(v, -1))
		var nb: PackedInt32Array = p.grid.nbrs[v]
		for sd: Array in p._sides(v, 0):
			var i: int = sd[0]
			if i == door or p.b.land.has(nb[i]) or float(sd[3]) < 1.3:
				continue
			var mid: Vector2 = sd[1]
			var out: Vector2 = sd[2]
			var q := mid + out * 2.4
			var bas := CSProps.wall_basis(out)
			var o := Vector3(q.x, 0.0, q.y)
			var c := p._cand(CSProps.TORII, 5.0, CSBuild.h01(v, i, 341), v, CSTown.key(v, 0))
			c.group = "torii %d" % v
			c.boxes = [CSProps.box(o, bas, Vector3(-1.75, -1.2, -0.3), Vector3(-1.05, 3.7, 0.3)), CSProps.box(o, bas, Vector3(1.05, -1.2, -0.3), Vector3(1.75, 3.7, 0.3)),
				CSProps.box(o, bas, Vector3(-2.1, 2.7, -0.3), Vector3(2.1, 3.7, 0.3))]
			c.inst = [[M_TORII, Transform3D(bas, o), 0, 0]]
			break


# --- the meshes ----------------------------------------------------------------------------------------

static func make_mesh(m: int, mb: CSProps.MB) -> void:
	match m:
		M_AC:
			mb.box(Vector3(-0.45, 0.0, -0.3), Vector3(0.45, 0.7, 0.3), CSProps.P_METAL)
			mb.box(Vector3(-0.36, 0.08, 0.3), Vector3(0.36, 0.62, 0.31), CSProps.P_DARK)
			mb.disc(0.705, 0.24, 12, true, CSProps.P_DARK)
			mb.box(Vector3(-0.5, 0.0, -0.05), Vector3(-0.45, 0.35, 0.05), CSProps.P_IRON)
		M_TANK:
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					mb.beam(Vector3(0.42 * sx, 0.0, 0.42 * sz), Vector3(0.42 * sx, 0.62, 0.42 * sz), 0.1, CSProps.P_IRON)
			mb.lathe([Vector2(0.0, 0.55), Vector2(0.6, 0.55), Vector2(0.66, 0.62), Vector2(0.66, 1.62), Vector2(0.6, 1.7), Vector2(0.3, 1.78), Vector2(0.0, 1.8)], 14, CSProps.P_METAL)
			mb.beam(Vector3(0.0, 1.78, 0.0), Vector3(0.0, 1.95, 0.0), 0.08, CSProps.P_IRON)
		M_MAST:
			mb.box(Vector3(-0.2, 0.0, -0.2), Vector3(0.2, 0.18, 0.2), CSProps.P_METAL)
			mb.beam(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 3.2, 0.0), 0.06, CSProps.P_METAL)
			for yy: float in [2.35, 2.75, 3.1]:
				mb.box(Vector3(-0.5 + (yy - 2.35) * 0.3, yy - 0.015, -0.015), Vector3(0.5 - (yy - 2.35) * 0.3, yy + 0.015, 0.015), CSProps.P_METAL)
			mb.beam(Vector3(0.0, 1.2, 0.0), Vector3(0.22, 1.25, 0.0), 0.04, CSProps.P_METAL)
		M_SOLAR:
			mb.extrude_x([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 0.18), Vector2(-0.5, 0.5)], -0.62, 0.62, CSProps.P_DARK)
			mb.extrude_x([Vector2(-0.5, 0.0), Vector2(-0.46, 0.0), Vector2(-0.46, 0.48), Vector2(-0.5, 0.5)], -0.64, 0.64, CSProps.P_METAL)
		M_PLANTER:
			mb.box(Vector3(-0.6, 0.0, -0.26), Vector3(0.6, 0.42, 0.26), CSProps.P_WOOD)
			mb.box(Vector3(-0.56, 0.42, -0.22), Vector3(0.56, 0.45, 0.22), CSProps.P_EARTH)
			for j in 8:
				var x := -0.48 + float(j) * 0.137
				mb.box(Vector3(x - 0.07, 0.44, -0.18 + 0.05 * float(j % 3)), Vector3(x + 0.07, 0.66 + 0.1 * float(j % 2), 0.14), CSProps.P_LEAF)
			for j in 6:
				var x2 := -0.4 + float(j) * 0.16
				mb.box(Vector3(x2 - 0.05, 0.66 + 0.08 * float(j % 2), -0.05 + 0.08 * float((j + 1) % 2)), Vector3(x2 + 0.05, 0.78 + 0.08 * float(j % 2), 0.05 + 0.08 * float((j + 1) % 2)), CSProps.P_BLOOM)
		M_PAPER:
			# a wall bracket reaching out, then a paper lantern hung from its tip (hung from a roof corner, the bracket is hidden in the roof's edge)
			mb.box(Vector3(-0.02, -0.03, -CSProps.EMBED), Vector3(0.02, 0.03, 0.34), CSProps.P_DARKWOOD)
			mb.box(Vector3(-0.006, -0.17, 0.33), Vector3(0.006, -0.02, 0.35), CSProps.P_IRON)
			var hang := Vector3(0.0, 0.0, 0.34)
			mb.lathe([Vector2(0.0, -0.17), Vector2(0.07, -0.17), Vector2(0.09, -0.19), Vector2(0.0, -0.19)], 10, CSProps.P_GOLD, hang)
			mb.lathe([Vector2(0.0, -0.19), Vector2(0.09, -0.2), Vector2(0.2, -0.3), Vector2(0.26, -0.43), Vector2(0.2, -0.56), Vector2(0.09, -0.65), Vector2(0.0, -0.66)], 12, CSProps.P_PAPER, hang)
			mb.lathe([Vector2(0.0, -0.66), Vector2(0.06, -0.66), Vector2(0.06, -0.69), Vector2(0.0, -0.69)], 8, CSProps.P_GOLD, hang)
			mb.beam(Vector3(0.0, -0.69, 0.34), Vector3(0.0, -0.8, 0.34), 0.014, CSProps.P_PAPER)
		M_TORII:
			for sx: float in [-1.0, 1.0]:
				mb.lathe([Vector2(0.0, -1.2), Vector2(0.19, -1.2), Vector2(0.19, 0.2), Vector2(0.16, 3.2), Vector2(0.0, 3.2)], 10, CSProps.P_LACQUER, Vector3(1.4 * sx, 0.0, 0.0))
			mb.box(Vector3(-1.45, 2.5, -0.09), Vector3(1.45, 2.72, 0.09), CSProps.P_LACQUER)
			mb.box(Vector3(-0.09, 2.72, -0.07), Vector3(0.09, 3.28, 0.07), CSProps.P_LACQUER)
			mb.box(Vector3(-2.05, 3.28, -0.2), Vector3(2.05, 3.5, 0.2), CSProps.P_DARK)
			mb.box(Vector3(-1.85, 3.2, -0.17), Vector3(1.85, 3.28, 0.17), CSProps.P_LACQUER)
			mb.box(Vector3(-2.15, 3.46, -0.2), Vector3(-1.95, 3.58, 0.2), CSProps.P_DARK)
			mb.box(Vector3(1.95, 3.46, -0.2), Vector3(2.15, 3.58, 0.2), CSProps.P_DARK)
		M_AWNING:
			# a striped canopy sloping down and out from the wall, alternate strips in the two colours
			for i in 8:
				var x0 := -0.8 + float(i) * 0.2
				mb.extrude_x([Vector2(-CSProps.EMBED, 0.2), Vector2(0.95, -0.25), Vector2(0.95, -0.33), Vector2(0.7, -0.33), Vector2(-CSProps.EMBED, 0.1)], x0, x0 + 0.2, CSProps.P_CLOTH if i % 2 == 0 else CSProps.P_CLOTH2)
