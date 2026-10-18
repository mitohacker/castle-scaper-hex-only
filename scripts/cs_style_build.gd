class_name CSStyleBuild
extends RefCounted
## The tops of the building styles (everything but the castle). CSBuild hands over every styled block with nothing above it; this reads what stands
## round it and chooses the hat from the style's own list of roofs:
##   - each side of the block is OPEN (sea, land, a courtyard), a PARTY wall (a block of the same height beside it) or TALL (a taller block's wall rises
##     beside it); a side that touches a neighbour gets no eave, a gable stands where a gable can, a mono-pitch roof leans on the taller wall;
##   - the choice is a weighted pick from the style's list (the weights depend on the sides, the storey, the shape of the cell and the colour scheme,
##     the pick is seeded by the grid point), so the same arrangement always gives the same roof and a different arrangement a different one;
##   - the hat is built as closed solids (CSRoofs), kept in CSBuild.hats and appended to the skin after the plan has run.
## A hat record: {kind, style, v, k, parts: [{sh, inside}], seed, owner, anchor, top (absolute y), rec (the generator's record), poly}.

const OPEN := 0
const PARTY := 1
const TALL := 2
const F_NOWIN := 128           # mesh flag: a wall face above the storeys (parapets, penthouses): no windows are painted on it

const KINDS := ["gable", "hip", "shed", "flat", "penthouse", "pyramid", "mansard", "curved_hip", "yingshan", "pavilion", "wide_hip", "wide_gable",
	"thatch_hip", "thatch_gable", "lean_to", "spire", "onion", "mushroom", "witch", "crystal", "dome"]


class Ctx:
	extends RefCounted
	var b: CSBuild
	var v := 0
	var k := 0
	var s := 0
	var c := 0
	var n := 0
	var poly := PackedVector2Array()       # the outline, rotated so that edge j (poly[j] -> poly[j + 1]) is side j (towards neighbour j)
	var cls := PackedByteArray()
	var no := 0
	var np := 0
	var nt := 0
	var centre := Vector2.ZERO
	var axis := Vector2.RIGHT               # the long way of the cell
	var elong := 1.0
	var inr := 0.0                          # the nearest side from the centre
	var ys := 0.0
	var seed := 0.0
	var owner := 0
	var anchor := Vector3.ZERO

	func h(salt: int) -> float:
		return CSBuild.h01(v, k, 200 + salt)

	func rnd(salt: int, lo: float, hi: float) -> float:
		return lo + (hi - lo) * h(salt)

	func zones(side_zone: int = -1) -> Dictionary:
		return {"roof": CSStyle.roof_zone(s), "side": CSStyle.trim_zone(s) if side_zone < 0 else side_zone, "soffit": CSStyle.trim_zone(s),
			"gable": CSStyle.gable_zone(s)}


# --- entry -----------------------------------------------------------------------------------------

static func tops(b: CSBuild, list: Array) -> void:
	for kk: int in list:
		_top(b, kk / 64, kk % 64)


static func _top(b: CSBuild, v: int, k: int) -> void:
	var kk := CSTown.key(v, k)
	if b.top_of(v) > k:
		b.kinds[kk] = "flat"                # a block of its own column floats above it (a pillar comes down onto it): no hat
		return
	var ctx := _ctx(b, v, k)
	if ctx == null:
		b.kinds[kk] = "flat"
		return
	var list := _weights(ctx)
	var kind := _pick(list, ctx.h(1))
	if not _build(ctx, kind):
		# the chosen roof does not fit this cell: the plainest one that always does
		if not _build(ctx, "hip") and not _build(ctx, "flat"):
			b.kinds[kk] = "flat"


static func tiers(b: CSBuild, list: Array) -> void:
	for kk: int in list:
		_tier(b, kk / 64, kk % 64)


static func _tier(b: CSBuild, v: int, k: int) -> void:
	## The roof between a block and the smaller block of its column on top of it: a pent roof ringing the upper wall (a deck with a parapet on a set-back tower).
	var x := _ctx(b, v, k)
	if x == null:
		return
	var n := x.n
	var up := b.level_outline(v, k + 1)
	if up.size() != n:
		return
	var parts: Array = []
	var rec: Dictionary = {}
	if x.s == CSStyle.APARTMENT:
		rec = _flat(x, parts, false)
	else:
		# the wall above, ordered like the outline and pulled 1 cm into itself: the roof's top ring ends inside that wall, with no crack between them
		var inner := PackedVector2Array()
		for j in n:
			inner.append(up[(j + n - 1) % n])
		var c := CSRoofs.centroid(inner)
		var grow := PackedVector2Array()
		for q in inner:
			grow.append(c + (q - c) * 0.995)
		var sh := CSRoofs.Shell.new()
		var o := {"ovh": _ovh_for(x, 0.9), "H": 1.0, "profile": PROF_STRAIGHT, "lift": 0.0, "sub": 3, "tf": 0.2, "zones": x.zones(), "inner": grow}
		match x.s:
			CSStyle.CHINESE:
				o = {"ovh": _ovh_for(x, x.rnd(3, 0.85, 1.1)), "H": x.rnd(2, 0.9, 1.3), "profile": PROF_CHINESE, "lift": x.rnd(4, 0.25, 0.4), "lift_u": 0.6, "sub": 3,
					"tf": 0.24, "zones": x.zones(), "inner": grow}
			CSStyle.JAPANESE:
				o = {"ovh": _ovh_for(x, x.rnd(3, 0.8, 1.0)), "H": x.rnd(2, 0.7, 1.0), "profile": PROF_STRAIGHT, "lift": x.rnd(4, 0.05, 0.15), "lift_u": 0.6, "sub": 3,
					"tf": 0.2, "zones": x.zones(), "inner": grow}
			CSStyle.FANTASY:
				o = {"ovh": _ovh_for(x, x.rnd(3, 0.25, 0.5)), "H": x.rnd(2, 0.6, 1.0), "profile": PROF_WITCH, "lift": x.rnd(4, 0.1, 0.25), "lift_u": 0.6, "sub": 3,
					"tf": 0.16, "zones": x.zones(), "inner": grow}
		rec = CSRoofs.pyramid(sh, x.poly, x.ys, o)
		parts.append({"sh": sh, "inside": rec.centre})
	if rec.is_empty():
		return
	var kk := CSTown.key(v, k)
	b.kinds[kk] = "tier"
	b.hats[kk] = {"kind": "tier", "style": x.s, "v": v, "k": k, "parts": parts, "seed": x.seed, "owner": x.owner, "anchor": x.anchor,
		"top": float(rec.get("top", x.ys + 1.0)), "rec": rec, "poly": x.poly, "ys": x.ys, "cls": x.cls, "gable": PackedByteArray()}


static func _pick(list: Array, h: float) -> String:
	var total := 0.0
	for e: Array in list:
		total += maxf(float(e[1]), 0.0)
	var r := h * total
	for e: Array in list:
		r -= maxf(float(e[1]), 0.0)
		if r < 0.0:
			return str(e[0])
	return str((list[list.size() - 1] as Array)[0])


static func _ctx(b: CSBuild, v: int, k: int) -> Ctx:
	var ol := b.level_outline(v, k)
	var n := ol.size()
	if n < 3 or not CSBuild.convex(ol):
		return null
	var ctx := Ctx.new()
	ctx.b = b
	ctx.v = v
	ctx.k = k
	ctx.s = b.town.style(v, k)
	ctx.c = b.town.colour(v, k)
	ctx.n = n
	var nb: PackedInt32Array = b.grid.nbrs[v]
	for j in n:
		ctx.poly.append(ol[(j + n - 1) % n])
		var u := nb[j]
		if b.filled(u, k + 1):
			ctx.cls.append(TALL)
			ctx.nt += 1
		elif b.filled(u, k):
			ctx.cls.append(PARTY)
			ctx.np += 1
		else:
			ctx.cls.append(OPEN)
			ctx.no += 1
	ctx.centre = CSRoofs.centroid(ctx.poly)
	# the long axis: the principal axis of the corners, else the longest side
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	for q in ctx.poly:
		var d := q - ctx.centre
		sxx += d.x * d.x
		sxy += d.x * d.y
		syy += d.y * d.y
	var tr := sxx + syy
	var det := sxx * syy - sxy * sxy
	var disc := sqrt(maxf(tr * tr * 0.25 - det, 0.0))
	var l1 := tr * 0.5 + disc
	var l2 := maxf(tr * 0.5 - disc, 1e-6)
	ctx.elong = sqrt(l1 / l2)
	var best_len := -1.0
	for j in n:
		var e := ctx.poly[(j + 1) % n] - ctx.poly[j]
		if e.length() > best_len:
			best_len = e.length()
			ctx.axis = e.normalized()
	if ctx.elong > 1.06 and disc > 1e-6:
		var ang := 0.5 * atan2(2.0 * sxy, sxx - syy)
		ctx.axis = Vector2(cos(ang), sin(ang))
	var inr := INF
	for j in n:
		inr = minf(inr, Geometry2D.get_closest_point_to_segment(ctx.centre, ctx.poly[j], ctx.poly[(j + 1) % n]).distance_to(ctx.centre))
	ctx.inr = inr
	ctx.ys = b.level_y(k + 1)
	ctx.seed = CSBuild.colour_seed(ctx.c)
	ctx.owner = v + 1
	var p := b.grid.verts[v]
	ctx.anchor = Vector3(p.x, b.level_y(k), p.y)
	return ctx


# --- the pick ----------------------------------------------------------------------------------------

static func _weights(x: Ctx) -> Array:
	var free := x.no == x.n
	var closed := x.np + x.nt
	var low := x.k <= 1
	match x.s:
		CSStyle.HOUSE:
			var modern := x.c == 10
			var w: Array = [["gable", 5.0 if not modern else 1.0], ["hip", 2.6 if free else 1.6]]
			w.append(["shed", 0.5 + (3.2 if (x.nt > 0 or x.np > 0) and x.no >= 2 else 0.0) + (2.0 if modern else 0.0)])
			w.append(["flat", 0.25 + (4.0 if modern else 0.0) + (1.0 if x.k >= 2 else 0.0) + (3.0 if closed >= x.n - 1 else 0.0)])
			if free and x.elong < 1.2 and x.n == 4:
				w.append(["pyramid", 0.9 if x.k >= 1 else 0.3])
			if x.c in [4, 9, 0]:
				w.append(["mansard", 0.9])
			return w
		CSStyle.APARTMENT:
			var w2: Array = [["flat", 6.0], ["penthouse", 2.2 + (1.5 if x.k >= 3 else 0.0)], ["shed", 0.8 + (2.0 if closed > 0 else 0.0)]]
			if x.c in [4, 5, 10, 11]:
				w2.append(["hip", 1.2])
			return w2
		CSStyle.CHINESE:
			var palace := x.c in [2, 4, 5]
			var w3: Array = [["curved_hip", 5.0 + (2.0 if palace else 0.0)], ["yingshan", 1.2 + (2.5 if closed >= 2 else 0.0)]]
			if free and x.n == 4 and x.elong < 1.25:
				w3.append(["pavilion", 2.6 + (1.5 if palace else 0.0)])
			return w3
		CSStyle.JAPANESE:
			var farm := x.c == 10
			var w4: Array = [["wide_hip", 3.2], ["wide_gable", 3.0 + (2.0 if closed >= 1 else 0.0)]]
			if farm:
				w4 = [["wide_gable", 3.0], ["thatch_gable", 5.0]]
			if x.c in [4, 9]:
				w4.append(["shed", 1.0])
			return w4
		CSStyle.FANTASY:
			var w5: Array = [["spire", 3.0 + (1.0 if x.k >= 1 else 0.0)], ["witch", 2.2], ["onion", 1.6 + (1.0 if x.c in [8, 4] else 0.0)], ["mushroom", 1.4 + (1.6 if x.c in [3, 10] else 0.0)],
				["crystal", 1.2 + (1.5 if x.c in [2, 7] else 0.0)], ["dome", 1.0 + (1.5 if x.c == 8 else 0.0)]]
			if closed >= 1:
				w5.append(["gable", 1.5])
			return w5
		CSStyle.VILLAGE:
			var w6: Array = [["thatch_hip", 3.0 if free else 1.2], ["thatch_gable", 3.5], ["lean_to", 0.4 + (3.0 if closed >= 1 else 0.0)]]
			if x.c in [4, 5, 9, 11]:
				w6 = [["gable", 4.0], ["hip", 1.6], ["lean_to", 0.4 + (2.5 if closed >= 1 else 0.0)]]
			if not low:
				w6.append(["flat", 0.5])
			return w6
	return [["hip", 1.0]]


# --- building ----------------------------------------------------------------------------------------

static func _build(x: Ctx, kind: String) -> bool:
	var parts: Array = []
	var rec: Dictionary = {}
	match kind:
		"gable":
			rec = _ridge(x, parts, "gable", {"slope": x.rnd(2, 0.85, 1.3), "eave": x.rnd(3, 0.25, 0.65), "verge": x.rnd(4, 0.08, 0.3), "tf": 0.16})
		"hip":
			rec = _ridge(x, parts, "hip", {"slope": x.rnd(2, 0.7, 1.05), "eave": x.rnd(3, 0.3, 0.7), "verge": 0.0, "tf": 0.16})
		"shed":
			rec = _ridge(x, parts, "shed", {"slope": x.rnd(2, 0.28, 0.55), "eave": x.rnd(3, 0.25, 0.6), "verge": x.rnd(4, 0.05, 0.2), "tf": 0.16})
		"wide_hip":
			rec = _ridge(x, parts, "hip", {"slope": x.rnd(2, 0.55, 0.75), "eave": x.rnd(3, 0.85, 1.15), "verge": 0.0, "tf": 0.2})
		"wide_gable":
			rec = _ridge(x, parts, "gable", {"slope": x.rnd(2, 0.55, 0.8), "eave": x.rnd(3, 0.8, 1.1), "verge": x.rnd(4, 0.5, 0.8), "tf": 0.2})
		"yingshan":
			rec = _ridge(x, parts, "gable", {"slope": x.rnd(2, 0.6, 0.85), "eave": x.rnd(3, 0.8, 1.05), "verge": 0.08, "tf": 0.24})
		"thatch_gable":
			rec = _ridge(x, parts, "gable", {"slope": x.rnd(2, 1.25, 1.7), "eave": x.rnd(3, 0.5, 0.75), "verge": x.rnd(4, 0.3, 0.5), "tf": 0.34})
		"lean_to":
			rec = _ridge(x, parts, "shed", {"slope": x.rnd(2, 0.5, 0.8), "eave": x.rnd(3, 0.35, 0.6), "verge": x.rnd(4, 0.15, 0.3), "tf": 0.2})
		"flat":
			rec = _flat(x, parts, false)
		"penthouse":
			rec = _flat(x, parts, true)
		"mansard":
			rec = _mansard(x, parts)
		"pyramid":
			rec = _pyramid(x, parts, {"H": x.rnd(2, 2.2, 3.4), "ovh": x.rnd(3, 0.25, 0.5), "tf": 0.16, "profile": PROF_STRAIGHT, "lift": 0.0})
		"curved_hip":
			rec = _curved(x, parts, false)
		"pavilion":
			rec = _curved(x, parts, true)
		"thatch_hip":
			rec = _pyramid(x, parts, {"H": x.rnd(2, 2.0, 2.9), "ovh": x.rnd(3, 0.45, 0.7), "tf": 0.34, "profile": PROF_THATCH, "lift": 0.0, "ridge": x.elong > 1.12})
		"spire":
			rec = _pyramid(x, parts, {"H": x.rnd(2, 4.2, 6.2), "ovh": x.rnd(3, 0.2, 0.45), "tf": 0.16, "profile": PROF_SPIRE, "lift": 0.12, "bend": Vector2.from_angle(x.h(5) * TAU) * x.rnd(6, 0.0, 0.9)})
		"witch":
			rec = _pyramid(x, parts, {"H": x.rnd(2, 3.4, 5.0), "ovh": x.rnd(3, 0.65, 0.95), "tf": 0.2, "profile": PROF_WITCH, "lift": 0.22, "bend": Vector2.from_angle(x.h(5) * TAU) * x.rnd(6, 0.3, 1.2)})
		"crystal":
			rec = _pyramid(x, parts, {"H": x.rnd(2, 3.2, 5.4), "ovh": x.rnd(3, 0.1, 0.3), "tf": 0.1, "profile": PROF_STRAIGHT, "lift": 0.0, "sub": 1})
		"onion":
			rec = _dome(x, parts, "onion")
		"mushroom":
			rec = _dome(x, parts, "mushroom")
		"dome":
			rec = _dome(x, parts, "dome")
		_:
			return false
	if rec.is_empty():
		return false
	var kk := CSTown.key(x.v, x.k)
	x.b.kinds[kk] = kind
	x.b.hats[kk] = {"kind": kind, "style": x.s, "v": x.v, "k": x.k, "parts": parts, "seed": x.seed, "owner": x.owner, "anchor": x.anchor,
		"top": float(rec.get("top", x.ys + 1.0)), "rec": rec, "poly": x.poly, "ys": x.ys, "cls": x.cls, "gable": rec.get("gable", PackedByteArray())}
	return true


# --- ridge roofs -------------------------------------------------------------------------------------

static func _edge_dir(x: Ctx, j: int) -> Vector2:
	return (x.poly[(j + 1) % x.n] - x.poly[j]).normalized()


static func _out_normal(x: Ctx, j: int) -> Vector2:
	var d := _edge_dir(x, j)
	return Vector2(d.y, -d.x)


static func _mid(x: Ctx, j: int) -> Vector2:
	return (x.poly[j] + x.poly[(j + 1) % x.n]) * 0.5


static func _eave_score(x: Ctx, j: int) -> float:
	match x.cls[j]:
		OPEN:
			return 2.0
		PARTY:
			return -0.5
	return -2.0


static func _gable_eaves(x: Ctx) -> PackedInt32Array:
	## The two sides that get eaves: opposite each other, open if possible, running the long way of the cell.
	var best := -INF
	var out := PackedInt32Array()
	for i in x.n:
		for j in range(i + 1, x.n):
			if _out_normal(x, i).dot(_out_normal(x, j)) > -0.5:
				continue
			var score := _eave_score(x, i) + _eave_score(x, j)
			score += (absf(_edge_dir(x, i).dot(x.axis)) + absf(_edge_dir(x, j).dot(x.axis))) * (0.6 + 2.0 * (x.elong - 1.0))
			score += 0.5 * CSBuild.h01(x.v, x.k, 230 + i * 7 + j)
			if score > best:
				best = score
				out = PackedInt32Array([i, j])
	return out


static func _shed_eave(x: Ctx) -> int:
	## The low side of a mono-pitch roof: an open side, opposite a wall to lean on if there is one.
	var best := -INF
	var out := 0
	for j in x.n:
		var score := _eave_score(x, j) + 0.5 * CSBuild.h01(x.v, x.k, 250 + j)
		for m in x.n:
			if m != j and _out_normal(x, j).dot(_out_normal(x, m)) < -0.5 and x.cls[m] != OPEN:
				score += 1.5
		if score > best:
			best = score
			out = j
	return out


static func _ridge(x: Ctx, parts: Array, mode: String, p: Dictionary) -> Dictionary:
	var n := x.n
	var gable := PackedByteArray()
	gable.resize(n)
	var ovh := PackedFloat32Array()
	ovh.resize(n)
	var eaves: Array = []
	match mode:
		"gable":
			var e := _gable_eaves(x)
			if e.size() < 2:
				return {}
			eaves = [e[0], e[1]]
		"shed":
			eaves = [_shed_eave(x)]
		_:
			for j in n:
				eaves.append(j)
	for j in n:
		var is_eave := eaves.has(j)
		gable[j] = 0 if is_eave else 1
		ovh[j] = (float(p.eave) if is_eave else float(p.verge)) if x.cls[j] == OPEN else 0.0
	var sh := CSRoofs.Shell.new()
	var rec := CSRoofs.ridge(sh, x.poly, x.ys, {"slope": p.slope, "gable": gable, "ovh": ovh, "tf": p.tf, "zones": x.zones()})
	if rec.is_empty():
		return {}
	parts.append({"sh": sh, "inside": rec.centre})
	return rec


# --- flat roofs --------------------------------------------------------------------------------------

static func _flat(x: Ctx, parts: Array, penthouse: bool) -> Dictionary:
	var ovh := PackedFloat32Array()
	ovh.resize(x.n)
	var apartment := x.s == CSStyle.APARTMENT
	for j in x.n:
		ovh[j] = (x.rnd(10 + j, 0.0, 0.18) if apartment else x.rnd(10 + j, 0.1, 0.3)) if x.cls[j] == OPEN else 0.0
	var sh := CSRoofs.Shell.new()
	var zr := x.zones(CSStyle.wall_zone(x.s))
	zr["roof"] = CSStyle.pave_zone(x.s)
	zr["cap"] = CSStyle.trim_zone(x.s)
	var rec := CSRoofs.slab(sh, x.poly, x.ys, {"ovh": ovh, "rim": x.rnd(2, 0.55, 0.95), "wall": 0.22, "deck": 0.1, "zones": zr, "side_flags": F_NOWIN})
	parts.append({"sh": sh, "inside": rec.centre})
	if penthouse:
		# a box of stairs and machine rooms standing back from the parapet, with a little roof of its own
		var inset := PackedVector2Array()
		var rot := x.rnd(7, -0.35, 0.35)
		var sc := x.rnd(8, 0.38, 0.55)
		for q in x.poly:
			inset.append(x.centre + (q - x.centre).rotated(rot) * sc)
		var ph := x.rnd(9, 1.8, 2.8)
		var sh2 := CSRoofs.Shell.new()
		var pr := CSRoofs.prism(sh2, inset, float(rec.deck) - 0.02, float(rec.deck) + ph, CSStyle.wall_zone(x.s), CSStyle.trim_zone(x.s), F_NOWIN)
		parts.append({"sh": sh2, "inside": pr.centre})
		rec["top"] = float(rec.deck) + ph
		rec["penthouse"] = inset
	return rec


static func _mansard(x: Ctx, parts: Array) -> Dictionary:
	## A steep skirt of slate round a flat top: a truncated pyramid with an inset ring, closed by a low hip.
	var inner := PackedVector2Array()
	for q in x.poly:
		inner.append(x.centre + (q - x.centre) * 0.62)
	var ovh := PackedFloat32Array()
	ovh.resize(x.n)
	for j in x.n:
		ovh[j] = x.rnd(3, 0.15, 0.35) if x.cls[j] == OPEN else 0.0
	var sh := CSRoofs.Shell.new()
	var H := x.rnd(2, 1.5, 2.1)
	var rec := CSRoofs.pyramid(sh, x.poly, x.ys, {"ovh": ovh, "H": H, "profile": PROF_STRAIGHT, "sub": 1, "tf": 0.16, "inner": inner, "zones": x.zones()})
	parts.append({"sh": sh, "inside": rec.centre})
	return rec


# --- radial roofs ------------------------------------------------------------------------------------

const PROF_STRAIGHT := [Vector2(0, 0), Vector2(1, 1)]
const PROF_THATCH := [Vector2(0, 0), Vector2(0.12, 0.2), Vector2(0.3, 0.46), Vector2(0.55, 0.74), Vector2(0.8, 0.93), Vector2(1, 1)]
const PROF_SPIRE := [Vector2(0, 0), Vector2(0.1, 0.05), Vector2(0.3, 0.2), Vector2(0.55, 0.5), Vector2(0.8, 0.84), Vector2(1, 1)]
const PROF_WITCH := [Vector2(0, 0), Vector2(0.08, 0.02), Vector2(0.22, 0.08), Vector2(0.45, 0.3), Vector2(0.72, 0.68), Vector2(1, 1)]
const PROF_CHINESE := [Vector2(0, 0), Vector2(0.12, 0.03), Vector2(0.3, 0.13), Vector2(0.52, 0.36), Vector2(0.78, 0.72), Vector2(1, 1)]


static func _ovh_for(x: Ctx, v: float) -> PackedFloat32Array:
	var ovh := PackedFloat32Array()
	ovh.resize(x.n)
	for j in x.n:
		ovh[j] = v if x.cls[j] == OPEN else 0.0
	return ovh


static func _pyramid(x: Ctx, parts: Array, p: Dictionary) -> Dictionary:
	var o := {"ovh": _ovh_for(x, float(p.ovh)), "H": float(p.H), "profile": p.profile, "lift": float(p.get("lift", 0.0)), "sub": int(p.get("sub", 4)),
		"tf": float(p.tf), "zones": x.zones(), "bend": p.get("bend", Vector2.ZERO)}
	if bool(p.get("ridge", false)):
		o["ridge"] = {"axis": x.axis, "along": 0.5, "across": 0.06}
	var sh := CSRoofs.Shell.new()
	var rec := CSRoofs.pyramid(sh, x.poly, x.ys, o)
	parts.append({"sh": sh, "inside": rec.centre})
	return rec


static func _curved(x: Ctx, parts: Array, pavilion: bool) -> Dictionary:
	## A Chinese hip roof: the eaves curve up at the corners and the slope is hollowed (steeper under the ridge).
	var o := {"ovh": _ovh_for(x, x.rnd(3, 0.85, 1.2)), "H": x.rnd(2, 1.7, 2.5) + (0.9 if pavilion else 0.0), "profile": PROF_CHINESE,
		"lift": x.rnd(4, 0.35, 0.6), "lift_u": 0.55, "sub": 4, "tf": 0.26, "zones": x.zones()}
	if not pavilion:
		o["ridge"] = {"axis": x.axis, "along": 0.55, "across": 0.05}
	var sh := CSRoofs.Shell.new()
	var rec := CSRoofs.pyramid(sh, x.poly, x.ys, o)
	parts.append({"sh": sh, "inside": rec.centre})
	# a gold ball on the apex of a pavilion
	if pavilion:
		var sh2 := CSRoofs.Shell.new()
		var g := sh2.group(CFMesh.Z_GOLD)
		var ap: Vector3 = rec.apex
		CSRoofs.lathe(sh2, ap - Vector3(0, 0.05, 0), [Vector2(0.0, 0.0), Vector2(0.16, 0.02), Vector2(0.22, 0.2), Vector2(0.13, 0.42), Vector2(0.04, 0.62), Vector2(0.0, 0.78)], 10, g)
		parts.append({"sh": sh2, "inside": ap + Vector3(0, 0.3, 0)})
		rec["top"] = ap.y + 0.75
	return rec


static func _dome(x: Ctx, parts: Array, shape: String) -> Dictionary:
	## A drum on the cell with a dome, an onion or a mushroom cap on it (a surface of revolution).
	var r := x.inr * 0.93
	var drum_h := x.rnd(2, 0.25, 0.5)
	var drum := PackedVector2Array()
	for q in x.poly:
		drum.append(x.centre + (q - x.centre) * 0.97)
	var sh := CSRoofs.Shell.new()
	var pr := CSRoofs.prism(sh, drum, x.ys - 0.02, x.ys + drum_h, CSStyle.wall_zone(x.s), CSStyle.trim_zone(x.s), F_NOWIN)
	parts.append({"sh": sh, "inside": pr.centre})
	var sh2 := CSRoofs.Shell.new()
	var g := sh2.group(CSStyle.roof_zone(x.s))
	var base := Vector3(x.centre.x, x.ys + drum_h - 0.02, x.centre.y)
	var prof: Array = []
	var top := 0.0
	match shape:
		"onion":
			var H := x.rnd(3, 2.6, 3.8)
			prof = [Vector2(0.0, 0.0), Vector2(r * 0.9, 0.0), Vector2(r * 1.12, H * 0.12), Vector2(r * 1.18, H * 0.28), Vector2(r * 1.02, H * 0.46), Vector2(r * 0.66, H * 0.64),
				Vector2(r * 0.34, H * 0.8), Vector2(r * 0.14, H * 0.93), Vector2(0.0, H)]
			top = H
		"mushroom":
			var H2 := x.rnd(3, 1.7, 2.5)
			prof = [Vector2(0.0, 0.0), Vector2(r * 1.2, 0.0), Vector2(r * 1.26, H2 * 0.1), Vector2(r * 1.2, H2 * 0.3), Vector2(r * 0.98, H2 * 0.58), Vector2(r * 0.66, H2 * 0.82),
				Vector2(r * 0.3, H2 * 0.96), Vector2(0.0, H2)]
			top = H2
		_:
			var H3 := x.rnd(3, 1.9, 2.6)
			prof = [Vector2(0.0, 0.0), Vector2(r, 0.0), Vector2(r * 0.97, H3 * 0.3), Vector2(r * 0.85, H3 * 0.58), Vector2(r * 0.6, H3 * 0.82), Vector2(r * 0.28, H3 * 0.96), Vector2(0.0, H3)]
			top = H3
	CSRoofs.lathe(sh2, base, prof, 20, g, x.h(9) * TAU)
	parts.append({"sh": sh2, "inside": base + Vector3(0, top * 0.4, 0)})
	return {"kind": "dome", "top": base.y + top, "centre": base + Vector3(0, top * 0.4, 0), "ys": x.ys, "dome_r": r}
