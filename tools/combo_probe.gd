extends SceneTree
## Counts what the rules make and dumps it for the viewer (viewer\index.html): random towns -> every block's visible outcome (shape, top, roof,
## support, stairs, openings, props) and the neighbourhood it came from; EVERY arrangement of the side neighbours round one point, built and read;
## how far one click ripples; the landscape columns; plan drawings of three towns.
## Run: tools\cs_run.ps1 -Script res://tools/combo_probe.gd -Seconds 900 -ScriptArgs "-- --json=C:/Dev/Prototypes/castle-scaper-realistic/viewer/data/combos.json"
##   --phases=castle,ripple,exh,land,plans   which parts (default all; the exhaustive part alone takes about three minutes)
##   --towns=N --clicks=N --country=N --ripple=N --exh_point=I   sizes (defaults 100 / 70 / 30 / 25 / 0)
## Townscaper's side of the comparison (its corner-key space, counted from the rules in townscaper-re/notes): tools/townscaper_keyspace.py

var grid: CSGrid
var out := {}                # everything the viewer needs
var full_sigs := {}          # full outcome -> blocks
var struct_sigs := {}        # structural outcome (shape, top, support, stairs, land) -> blocks
var piece_sigs := {}         # geometry without props (structural + roof + openings) -> blocks
var ctx_full := {}           # canonical neighbourhood -> {full outcome: blocks}
var ctx_struct := {}
var tallies := {}            # part -> {value: n}
var blocks_seen := 0
var curve: Array = []


func _tally(part: String, value: String) -> void:
	if not tallies.has(part):
		tallies[part] = {}
	var d: Dictionary = tallies[part]
	d[value] = int(d.get(value, 0)) + 1


func _p2(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]


func _context(b: CSBuild, v: int, k: int) -> String:
	## What the rules can see of the blocks round (v, k): per side the neighbour's blocks one level down / level / up, and its own column's
	## blocks below / above, up to turning and mirroring the cell. (Diagonal blocks, which only pinch a corner, are left out.)
	var nb: PackedInt32Array = grid.nbrs[v]
	var n := nb.size()
	var sides: Array = []
	for i in n:
		var bits := 0
		if b.filled(nb[i], k - 1):
			bits |= 1
		if b.filled(nb[i], k):
			bits |= 2
		if b.filled(nb[i], k + 1):
			bits |= 4
		sides.append(bits)
	var own := 0
	if b.town.has(v, k - 1):
		own |= 1
	if b.town.has(v, k + 1):
		own |= 2
	if k == 0:
		own |= 4
	var best := ""
	for mirror in 2:
		for r in n:
			var s := ""
			for j in n:
				var idx := (r + j) % n if mirror == 0 else ((r - j) % n + n) % n
				s += str(sides[idx])
			if best == "" or s < best:
				best = s
	return "%d|%d|%s" % [n, own, best]


func _maps(b: CSBuild, pr: CSProps) -> Dictionary:
	var caps_by_key := {}
	for rec: Dictionary in b.caps:
		var k := roundi((float(rec.y) - CSBuild.B) / CSBuild.H) - 1
		caps_by_key[CSTown.key(int(rec.owner) - 1, k)] = rec
	var ops := {}
	for o: Dictionary in b.openings:
		var key := CSTown.key(int(o.v), int(o.k))
		if not ops.has(key):
			ops[key] = {"door": 0, "slit": 0, "window": 0}
		ops[key][str(o.kind)] = int(ops[key][str(o.kind)]) + 1
	var stair_keys := {}
	for s: Dictionary in b.stairs:
		if int(s.k) >= 0:
			stair_keys[CSTown.key(int(s.cell), int(s.k))] = true
		stair_keys[CSTown.key(int(s.up), int(s.k) + 1)] = true
	var props := {}
	for c in (pr.kept if pr != null else []):
		if int(c.key) >= 0:
			if not props.has(int(c.key)):
				props[int(c.key)] = {}
			props[int(c.key)][str(CSProps.KINDS[int(c.kind)])] = true
	return {"caps": caps_by_key, "ops": ops, "stairs": stair_keys, "props": props}


func _sigs(b: CSBuild, m: Dictionary, v: int, k: int) -> Array:
	## [full outcome, structural outcome]
	var key := CSTown.key(v, k)
	var st := "R" if b.is_round(v, k) else "C"
	var top := str(b.kinds.get(key, ""))
	st += ".top=" + (top if top != "" else "-")
	st += ".sup=" + str(b.pieces.get(key, "-"))
	if b._corbel_faces.has(key):
		st += str((b._corbel_faces[key] as Array).size())
	st += ".st=" + ("1" if (m.stairs as Dictionary).has(key) else "0")
	if k == 0:
		st += ".land=" + str(b.land.get(v, "-"))
	if b.town.has(v, k) and b.town.style(v, k) != CSStyle.CASTLE:
		st += ".sty=" + str(CSStyle.KEYS[b.town.style(v, k)]) + ".hat=" + _hat_canon(b, key) + (".ground" if k == 0 else ".upper")
	var full := st
	if (m.caps as Dictionary).has(key):
		var cp: Dictionary = (m.caps as Dictionary)[key]
		full += ".roof=" + ("tile" if cp.zone == CFMesh.Z_TILE else "slate") + (".flag" if bool(cp.banner) else "")
	var ops: Dictionary = (m.ops as Dictionary).get(key, {})
	full += ".op=d%ds%dw%d" % [int(ops.get("door", 0)), int(ops.get("slit", 0)), int(ops.get("window", 0))]
	var pk: Array = ((m.props as Dictionary).get(key, {}) as Dictionary).keys()
	pk.sort()
	full += ".pr=" + ",".join(pk)
	return [full, st]


func _hat_canon(b: CSBuild, key: int) -> String:
	## The hat's kind and, round the cell, what each side is (open / party wall / taller wall, eave or gable), up to turning and mirroring the cell.
	var h: Dictionary = b.hats.get(key, {})
	if h.is_empty():
		return "-"
	var cls: PackedByteArray = h.cls
	var gab: PackedByteArray = h.gable
	var n := cls.size()
	var best := ""
	for mirror in 2:
		for r in n:
			var s := ""
			for j in n:
				var idx := (r + j) % n if mirror == 0 else ((r - j) % n + n) % n
				s += "%d%d" % [cls[idx], (gab[idx] if gab.size() > idx else 0)]
			if best == "" or s < best:
				best = s
	return "%s:%s" % [str(h.kind), best]


func _count_town(b: CSBuild, pr: CSProps) -> void:
	var m := _maps(b, pr)
	for v: int in b.town.columns():
		if not grid.buildable(v):
			continue
		for k in range(0, b.top_of(v) + 1):
			if not b.town.has(v, k):
				continue
			var key := CSTown.key(v, k)
			var s := _sigs(b, m, v, k)
			var full: String = s[0]
			var st: String = s[1]
			full_sigs[full] = int(full_sigs.get(full, 0)) + 1
			struct_sigs[st] = int(struct_sigs.get(st, 0)) + 1
			var piece := full.substr(0, full.find(".pr="))              # the block's own geometry: shape, top, support, roof, openings (no props)
			piece_sigs[piece] = int(piece_sigs.get(piece, 0)) + 1
			var cx := _context(b, v, k)
			if not ctx_full.has(cx):
				ctx_full[cx] = {}
				ctx_struct[cx] = {}
			(ctx_full[cx] as Dictionary)[full] = int((ctx_full[cx] as Dictionary).get(full, 0)) + 1
			(ctx_struct[cx] as Dictionary)[st] = int((ctx_struct[cx] as Dictionary).get(st, 0)) + 1
			blocks_seen += 1
			_tally("shape", "round" if b.is_round(v, k) else "cell")
			_tally("top", str(b.kinds.get(key, "(not a top)")))
			_tally("support", str(b.pieces.get(key, "(none)")))
			if (m.caps as Dictionary).has(key):
				var cp: Dictionary = (m.caps as Dictionary)[key]
				_tally("roof", "tile" if cp.zone == CFMesh.Z_TILE else "slate")
			for kind: String in ((m.props as Dictionary).get(key, {}) as Dictionary):
				_tally("prop", kind)
			var ops: Dictionary = (m.ops as Dictionary).get(key, {})
			for kind: String in ops:
				if int(ops[kind]) > 0:
					_tally("opening", kind)
	curve.append([blocks_seen, full_sigs.size(), struct_sigs.size(), ctx_full.size()])


func _fanout(label: String, ctx: Dictionary) -> Dictionary:
	## How far the neighbourhood decides the outcome: for each neighbourhood the commonest outcome; the share of blocks that show it.
	var total := 0
	var modal := 0
	var multi := 0
	var spread := 0
	var frequent := 0
	for cx: String in ctx:
		var d: Dictionary = ctx[cx]
		var n := 0
		var mx := 0
		for sg: String in d:
			n += int(d[sg])
			mx = maxi(mx, int(d[sg]))
		total += n
		modal += mx
		if d.size() > 1:
			multi += 1
		if n >= 5:
			frequent += 1
			spread += d.size()
	print("  %-10s %d neighbourhoods (%d seen 5+ times, those average %.2f outcomes each), %d show more than one outcome; commonest outcome of its neighbourhood covers %.1f%% of blocks" % [
		label, ctx.size(), frequent, float(spread) / maxf(1.0, float(frequent)), multi, 100.0 * float(modal) / maxf(1.0, float(total))])
	return {"contexts": ctx.size(), "frequent": frequent, "avg_outcomes": snappedf(float(spread) / maxf(1.0, float(frequent)), 0.01), "multi": multi,
		"modal_pct": snappedf(100.0 * float(modal) / maxf(1.0, float(total)), 0.1)}


func _castle_phase(towns: int, clicks: int) -> void:
	var names: Array = []
	for n: String in CSStarter.NAMES:
		if n != "landscape":
			names.append(n)
	for s in towns:
		names.append("random:%d:%d" % [s, clicks])
	for n: String in names:
		var town := CSTown.new()
		CSStarter.make(n, grid, town)
		var b := CSBuild.new()
		b.build(grid, town)
		var pr := CSProps.new()
		pr.build(b)
		_count_town(b, pr)
	print("== castle blocks: %d towns (%d starters + %d random of %d clicks), %d blocks" % [names.size(), CSStarter.NAMES.size() - 1, towns, clicks, blocks_seen])
	for part: String in ["shape", "top", "support", "roof", "opening", "prop"]:
		var d: Dictionary = tallies.get(part, {})
		var keys := d.keys()
		keys.sort_custom(func(x: String, y: String) -> bool: return int(d[x]) > int(d[y]))
		var parts: Array = []
		for kk: String in keys:
			parts.append("%s %d" % [kk, int(d[kk])])
		print("  %-8s %2d kinds: %s" % [part, d.size(), ", ".join(parts)])
	print("  distinct full outcomes %d, structural outcomes %d, neighbourhoods %d" % [full_sigs.size(), struct_sigs.size(), ctx_full.size()])
	var fo_full := _fanout("full", ctx_full)
	var fo_struct := _fanout("structural", ctx_struct)
	var once := 0
	var twice := 0
	for sg: String in full_sigs:
		if int(full_sigs[sg]) == 1:
			once += 1
		elif int(full_sigs[sg]) == 2:
			twice += 1
	var chao := float(full_sigs.size()) + float(once * once) / (2.0 * maxf(1.0, float(twice)))
	var cover := 100.0 * (1.0 - float(once) / float(blocks_seen))
	print("  full outcomes seen exactly once: %d, twice: %d, of %d; sample coverage %.0f%%; Chao1 estimate of all full outcomes ~%d" % [
		once, twice, full_sigs.size(), cover, roundi(chao)])
	var p1 := 0
	var p2 := 0
	for sg: String in piece_sigs:
		if int(piece_sigs[sg]) == 1:
			p1 += 1
		elif int(piece_sigs[sg]) == 2:
			p2 += 1
	var piece_chao := float(piece_sigs.size()) + float(p1 * p1) / (2.0 * maxf(1.0, float(p2)))
	print("  geometry without props (structure + roof + openings): %d seen, %d once, %d twice, Chao1 estimate ~%d" % [piece_sigs.size(), p1, p2, roundi(piece_chao)])
	var slist: Array = []
	for sg: String in struct_sigs:
		slist.append([sg, int(struct_sigs[sg])])
	slist.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) > int(y[1]))
	out["castle"] = {"towns": names.size(), "starters": CSStarter.NAMES.size() - 1, "random_towns": towns, "clicks": clicks, "blocks": blocks_seen,
		"tallies": tallies.duplicate(true), "distinct": {"full": full_sigs.size(), "structural": struct_sigs.size(), "neighbourhoods": ctx_full.size()},
		"fanout_full": fo_full, "fanout_struct": fo_struct, "curve": curve, "once": once, "twice": twice, "coverage": snappedf(cover, 0.1),
		"chao1": roundi(chao), "structural": slist, "pieces": {"observed": piece_sigs.size(), "once": p1, "twice": p2, "chao1": roundi(piece_chao)}}


# --- one click's ripple ----------------------------------------------------------------------------

func _short(sig: String) -> String:
	## "C.top=walk.sup=corbel2.st=1" -> "wall walk on corbels, with stairs"
	var parts: PackedStringArray = sig.split(".")
	var t := ""
	var s := ""
	var st := ""
	var ld := ""
	for p in parts:
		if p.begins_with("top="):
			t = p.substr(4)
		elif p.begins_with("sup="):
			s = p.substr(4)
		elif p.begins_with("st="):
			st = p.substr(3)
		elif p.begins_with("land="):
			ld = p.substr(5)
	var names := {"walk": "wall walk", "tower": "tower, cone roof", "battle": "tower, battlements", "cottage": "cottage", "flat": "flat top", "-": "covered"}
	var w: String = ("round " if parts[0] == "R" else "") + str(names.get(t, t))
	if s.begins_with("corbel"):
		w += " on corbels"
	elif s == "arch":
		w += " on an arch"
	elif s == "pillar":
		w += " on a pillar"
	if st == "1":
		w += ", with stairs"
	if ld != "" and ld != "base" and ld != "-":
		w += " (" + ld + ")"
	return w


func _ripple(towns: int, trials: int) -> void:
	## One extra click on a random town: how many OTHER blocks change their outcome, and how far away.
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var cases: Array = []
	for s in towns:
		var base := CSTown.new()
		CSStarter.make("random:%d:70" % s, grid, base)
		var b0 := CSBuild.new()
		b0.build(grid, base)
		var p0 := CSProps.new()
		p0.build(b0)
		var m0 := _maps(b0, p0)
		var before := {}
		for v: int in base.columns():
			for k in range(0, b0.top_of(v) + 1):
				if base.has(v, k):
					before[CSTown.key(v, k)] = _sigs(b0, m0, v, k)
		for _t in trials:
			var t2 := base.duplicate_town()
			var cols := t2.columns()
			var v0: int = cols[rng.randi_range(0, cols.size() - 1)]
			var cv := v0
			var ck := t2.top(v0) + 1
			if rng.randf() < 0.5:
				var nb: PackedInt32Array = grid.nbrs[v0]
				cv = nb[rng.randi_range(0, nb.size() - 1)]
				ck = rng.randi_range(0, maxi(0, t2.top(v0)))
			var colour := rng.randi_range(0, 11)
			if not grid.buildable(cv) or not t2.add(cv, ck, colour):
				continue
			var b1 := CSBuild.new()
			b1.build(grid, t2)
			var p1 := CSProps.new()
			p1.build(b1)
			var m1 := _maps(b1, p1)
			var cs := 0
			var cf := 0
			var far := 0.0
			var chg: Array = []
			for key: int in before:
				var v: int = key >> 6
				var k: int = key & 63
				if not t2.has(v, k):
					continue
				var now := _sigs(b1, m1, v, k)
				var was: Array = before[key]
				if now[1] != was[1]:
					cs += 1
					chg.append([v, k, "struct", _short(was[1]), _short(now[1])])
				elif now[0] != was[0]:
					chg.append([v, k, "look", "", ""])
				if now[0] != was[0]:
					cf += 1
					far = maxf(far, grid.verts[v].distance_to(grid.verts[cv]))
			cases.append({"seed": s, "click": [cv, ck, colour], "cs": cs, "cf": cf, "reach": snappedf(far, 0.1), "changed": chg})
	var sum_s := 0
	var sum_f := 0
	var max_s := 0
	var max_f := 0
	var sum_r := 0.0
	var max_r := 0.0
	var zero_struct := 0
	var hist_s := [0, 0, 0, 0, 0, 0, 0, 0]
	var hist_f := [0, 0, 0, 0, 0, 0, 0, 0]
	for c: Dictionary in cases:
		sum_s += int(c.cs)
		sum_f += int(c.cf)
		max_s = maxi(max_s, int(c.cs))
		max_f = maxi(max_f, int(c.cf))
		sum_r += float(c.reach)
		max_r = maxf(max_r, float(c.reach))
		if int(c.cs) == 0:
			zero_struct += 1
		hist_s[mini(int(c.cs), 7)] += 1
		hist_f[mini(int(c.cf), 7)] += 1
	var runs := cases.size()
	print("== ripple of one click (%d clicks on %d random 70-click castles): other blocks that change" % [runs, towns])
	print("  structural outcome (shape, top, support, stairs): mean %.2f, max %d, %.0f%% of clicks change none" % [
		float(sum_s) / maxf(1.0, float(runs)), max_s, 100.0 * float(zero_struct) / maxf(1.0, float(runs))])
	print("  full outcome (adds roof colour, openings, props): mean %.2f, max %d; farthest changed block mean %.1f m, max %.1f m (a cell is about 4 m)" % [
		float(sum_f) / maxf(1.0, float(runs)), max_f, sum_r / maxf(1.0, float(runs)), max_r])
	# three cases to show: the most structural change (smallest reach), one with only looks changing, one with a single structural change
	var picks: Array = []
	var a_best = null
	var b_best = null
	var c_best = null
	for c: Dictionary in cases:
		if int(c.cs) >= 2 and (a_best == null or int(c.cs) > int(a_best.cs) or (int(c.cs) == int(a_best.cs) and float(c.reach) < float(a_best.reach))):
			a_best = c
		if int(c.cs) == 0 and int(c.cf) >= 2 and (b_best == null or int(c.cf) > int(b_best.cf)):
			b_best = c
		if int(c.cs) == 1 and (c_best == null or float(c.reach) < float(c_best.reach) and float(c.reach) > 3.0):
			c_best = c
	for c in [a_best, c_best, b_best]:
		if c != null:
			picks.append(c)
	out["ripple"] = {"clicks": runs, "towns": towns, "mean_struct": snappedf(float(sum_s) / maxf(1.0, float(runs)), 0.01), "max_struct": max_s,
		"zero_struct_pct": snappedf(100.0 * float(zero_struct) / maxf(1.0, float(runs)), 0.1), "mean_full": snappedf(float(sum_f) / maxf(1.0, float(runs)), 0.01),
		"max_full": max_f, "reach_mean": snappedf(sum_r / maxf(1.0, float(runs)), 0.1), "reach_max": snappedf(max_r, 0.1), "hist_struct": hist_s, "hist_full": hist_f,
		"cases": picks}


# --- every neighbourhood of one point ---------------------------------------------------------------

func _canon(p: int, n: int, per_side: int) -> int:
	## The smallest value of pattern p over turning and mirroring the cell (its own-column bits stay put).
	var mask := (1 << per_side) - 1
	var own := p >> (n * per_side)
	var best := -1
	for mirror in 2:
		for r in n:
			var q := 0
			for j in n:
				var idx := (r + j) % n if mirror == 0 else ((r - j) % n + n) % n
				q |= ((p >> (idx * per_side)) & mask) << (j * per_side)
			q |= own << (n * per_side)
			if best < 0 or q < best:
				best = q
	return best


func _popcount(x: int) -> int:
	var n := 0
	var y := x
	while y > 0:
		n += y & 1
		y >>= 1
	return n


func _cell(v: int) -> Dictionary:
	var nb: PackedInt32Array = grid.nbrs[v]
	var poly: Array = []
	for p in grid.dual(v):
		poly.append(_p2(p))
	var ns: Array = []
	var nps: Array = []
	for u in nb:
		ns.append(_p2(grid.verts[u]))
		var q: Array = []
		for p in grid.dual(u):
			q.append(_p2(p))
		nps.append(q)
	return {"v": v, "pt": _p2(grid.verts[v]), "poly": poly, "nbrs": ns, "nbr_polys": nps}


func _exhaustive(v: int, k: int, style: int = 0) -> Dictionary:
	## Every arrangement of blocks at the side neighbours (one level down / level / up) and in the point's own column, built and read.
	## With a style, every block is of that style and takes the colour scheme (class number mod 12) so the colour's part in the pick shows too.
	var nb: PackedInt32Array = grid.nbrs[v]
	var n := nb.size()
	var use_below := k >= 1
	var per_side := 3 if use_below else 2
	var nbits := n * per_side + (2 if use_below else 1)
	var mult := {}
	var rep := {}
	for p in (1 << nbits):
		var c := _canon(p, n, per_side)
		mult[c] = int(mult.get(c, 0)) + 1
		if not rep.has(c) or _popcount(p) < _popcount(int(rep[c])):
			rep[c] = p
	var by_sig := {}                  # structural outcome -> {classes, patterns, rep (the class with the fewest neighbours)}
	var cls_sig := {}
	var t0 := Time.get_ticks_msec()
	var sides_len := []
	var dl := grid.dual(v)
	for i in dl.size():
		sides_len.append(snappedf(dl[i].distance_to(dl[(i + 1) % dl.size()]), 0.1))
	for c: int in rep:
		var p: int = rep[c]
		var t := CSTown.new()
		var colr := 0 if style == 0 else c % 12
		t.add(v, k, colr, style)
		var own := p >> (n * per_side)
		if use_below:
			if own & 1:
				t.add(v, k - 1, colr, style)
			if own & 2:
				t.add(v, k + 1, colr, style)
		elif own & 1:
			t.add(v, k + 1, colr, style)
		for i in n:
			var g := (p >> (i * per_side)) & ((1 << per_side) - 1)
			if use_below:
				if g & 1:
					t.add(nb[i], k - 1, colr, style)
				if g & 2:
					t.add(nb[i], k, colr, style)
				if g & 4:
					t.add(nb[i], k + 1, colr, style)
			else:
				if g & 1:
					t.add(nb[i], k, colr, style)
				if g & 2:
					t.add(nb[i], k + 1, colr, style)
		var b := CSBuild.new()
		b.build(grid, t)
		var sg: String = _sigs(b, _maps(b, null), v, k)[1]
		cls_sig[c] = sg
		if not by_sig.has(sg):
			by_sig[sg] = {"classes": 0, "patterns": 0, "rep": p}
		var rec: Dictionary = by_sig[sg]
		rec.classes = int(rec.classes) + 1
		rec.patterns = int(rec.patterns) + int(mult[c])
		if _popcount(p) < _popcount(int(rec.rep)) or (_popcount(p) == _popcount(int(rec.rep)) and p < int(rec.rep)):
			rec.rep = p
	var keys := by_sig.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return int(by_sig[x].patterns) > int(by_sig[y].patterns))
	var outcomes: Array = []
	var idx_of := {}
	for i in keys.size():
		idx_of[keys[i]] = i
		var r: Dictionary = by_sig[keys[i]]
		outcomes.append({"sig": keys[i], "classes": r.classes, "patterns": r.patterns, "rep": r.rep})
	var canon: Array = []
	var oi: Array = []
	var ml: Array = []
	var cl: Array = rep.keys()
	cl.sort()
	for c: int in cl:
		canon.append(c)
		oi.append(idx_of[cls_sig[c]])
		ml.append(mult[c])
	print("== every neighbourhood of point %d (%d sides %s m), level %d: %d bits = %d raw patterns, %d classes up to turning and mirroring, built in %d ms" % [
		v, n, str(sides_len), k, nbits, 1 << nbits, rep.size(), Time.get_ticks_msec() - t0])
	print("  %d different structural outcomes" % by_sig.size())
	for i in mini(keys.size(), 30):
		print("   %-44s %5d classes, %6d patterns (%.1f%%) rep %d" % [keys[i], by_sig[keys[i]].classes, by_sig[keys[i]].patterns,
			100.0 * float(by_sig[keys[i]].patterns) / float(1 << nbits), by_sig[keys[i]].rep])
	return {"point": v, "level": k, "sides": sides_len, "bits": nbits, "per_side": per_side, "raw": 1 << nbits, "classes": rep.size(), "build_ms": Time.get_ticks_msec() - t0,
		"outcomes": outcomes, "canon": canon, "outcome": oi, "mult": ml}


func _style_census(style: int, towns: int, clicks: int) -> Dictionary:
	## Random click-built towns of one style (-1: every style and the castle together): the structural / geometric / full outcomes of their styled blocks.
	var structs := {}
	var pieces := {}
	var fulls := {}
	var tops := {}
	var blocks := 0
	for s in towns:
		var town := CSTown.new()
		CSStarter.random_growth(grid, town, s, clicks, style)
		var b := CSBuild.new()
		b.build(grid, town)
		var pr := CSProps.new()
		pr.build(b)
		var m := _maps(b, pr)
		for v: int in town.columns():
			if not grid.buildable(v):
				continue
			for k in range(0, b.top_of(v) + 1):
				if not town.has(v, k) or town.style(v, k) == CSStyle.CASTLE:
					continue
				var key := CSTown.key(v, k)
				var sg := _sigs(b, m, v, k)
				var piece: String = str(sg[0]).substr(0, str(sg[0]).find(".pr="))
				var sty := town.style(v, k)
				var mat := ".mat=%d/%d" % [int(CSStyle.palette(sty, town.colour(v, k))[4]), CSStyle.roof_pattern(sty, town.colour(v, k))]
				var tier := ".tier" if b.tier_scale(v, k) < 1.0 else ""
				structs[sg[1] + tier] = int(structs.get(sg[1] + tier, 0)) + 1
				pieces[piece + tier + mat] = int(pieces.get(piece + tier + mat, 0)) + 1
				fulls[str(sg[0]) + tier + mat] = int(fulls.get(str(sg[0]) + tier + mat, 0)) + 1
				var tk := str(b.kinds.get(key, "(not a top)"))
				tops[tk] = int(tops.get(tk, 0)) + 1
				blocks += 1
	return {"blocks": blocks, "towns": towns, "tops": tops, "struct": structs.size(), "piece": pieces.size(), "full": fulls.size(),
		"piece_chao": _chao(pieces), "full_chao": _chao(fulls), "struct_chao": _chao(structs)}


func _chao(d: Dictionary) -> int:
	var once := 0
	var twice := 0
	for sg: String in d:
		if int(d[sg]) == 1:
			once += 1
		elif int(d[sg]) == 2:
			twice += 1
	return roundi(float(d.size()) + float(once * once) / (2.0 * maxf(1.0, float(twice))))


func _styles_phase(towns: int, clicks: int, points: int) -> void:
	var census := {}
	for s in range(1, CSStyle.COUNT):
		census[CSStyle.KEYS[s]] = _style_census(s, towns, clicks)
		var c: Dictionary = census[CSStyle.KEYS[s]]
		print("  %-10s %4d blocks: %d structural outcomes, %d geometries (Chao1 ~%d), %d full looks (~%d); tops %s" % [CSStyle.KEYS[s], c.blocks, c.struct, c.piece, c.piece_chao, c.full, c.full_chao, str(c.tops)])
	census["mixed"] = _style_census(-1, towns, clicks)
	var cm: Dictionary = census["mixed"]
	print("  %-10s %4d styled blocks: %d structural outcomes, %d geometries (Chao1 ~%d), %d full looks" % ["mixed", cm.blocks, cm.struct, cm.piece, cm.piece_chao, cm.full])
	var pts := _four_valent()
	var exh := {}
	for s in range(1, CSStyle.COUNT):
		var union := {}
		var rec := {}
		for pi in mini(points, pts.size()):
			var pt := int(pts[pi])
			for k in [0, 1]:
				if pi > 0 and k == 0:
					continue
				var e := _exhaustive(pt, k, s)
				for o: Dictionary in e.outcomes:
					union[str(o.sig)] = true
				rec["p%d_k%d" % [pi, k]] = {"point": pt, "level": k, "raw": e.raw, "classes": e.classes, "outcomes": (e.outcomes as Array).size(), "build_ms": e.build_ms}
		rec["union"] = union.size()
		exh[CSStyle.KEYS[s]] = rec
		print("  == %s: %d structural outcomes over all neighbourhoods at %d points (and the colour schemes)" % [CSStyle.KEYS[s], union.size(), mini(points, pts.size())])
	out["styles"] = {"census": census, "exh": exh, "towns": towns, "clicks": clicks, "points": points}


func _four_valent() -> Array:
	## Points with four neighbours that all have four neighbours (the regular part of the grid), nearest the middle first.
	var res := []
	for v in grid.verts.size():
		if not grid.buildable(v) or (grid.nbrs[v] as PackedInt32Array).size() != 4:
			continue
		var ok := true
		for u in grid.nbrs[v]:
			if not grid.buildable(u) or (grid.nbrs[u] as PackedInt32Array).size() != 4:
				ok = false
		if ok and CSBuild.convex(grid.dual(v)):
			res.append(v)
	res.sort_custom(func(a: int, b: int) -> bool: return grid.verts[a].length() < grid.verts[b].length())
	return res


# --- plans of three towns ----------------------------------------------------------------------------

func _plan(name: String) -> Dictionary:
	var town := CSTown.new()
	CSStarter.make(name, grid, town)
	var b := CSBuild.new()
	b.build(grid, town)
	var cols: Array = []
	var tops := {}
	for v: int in town.columns():
		if not grid.buildable(v):
			continue
		var poly: Array = []
		for p in grid.dual(v):
			poly.append(_p2(p))
		var lv: Array = []
		for k in range(0, b.top_of(v) + 1):
			var key := CSTown.key(v, k)
			lv.append([k, 1 if town.has(v, k) else (2 if b.fills.has(key) else 0), str(b.kinds.get(key, "")), str(b.pieces.get(key, ""))])
			if b.kinds.has(key):
				tops[str(b.kinds[key])] = int(tops.get(str(b.kinds[key]), 0)) + 1
		cols.append({"v": v, "poly": poly, "top": b.top_of(v), "round": b.col_round(v), "land": str(b.land.get(v, "")), "levels": lv, "c": town.colour(v, 0)})
	var courts: Array = []
	for v: int in b.land:
		if str(b.land[v]) == "court" and not town.has(v, 0) and b.top_of(v) < 0:
			var poly2: Array = []
			for p in grid.dual(v):
				poly2.append(_p2(p))
			courts.append({"v": v, "poly": poly2})
	return {"name": name, "blocks": town.size(), "columns": cols, "courts": courts, "tops": tops}


# --- the landscape ---------------------------------------------------------------------------------

func _country(seed: int, castle_clicks: int, wild_clicks: int) -> CSTown:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + seed
	var town := CSTown.new()
	if castle_clicks > 0:
		CSStarter.random_growth(grid, town, seed, castle_clicks)
	var types := [CSTown.T_LAND, CSTown.T_ROAD, CSTown.T_TREE, CSTown.T_ROCK, CSTown.T_MOUNTAIN]
	var c := CSStarter._centre_pos(grid)
	for i in wild_clicks:
		var v := -1
		var cols := town.wild_columns() + town.columns()
		if cols.is_empty() or rng.randf() < 0.12:
			v = grid.nearest(c + Vector2(rng.randf_range(-24, 24), rng.randf_range(-24, 24)))
		else:
			var v0: int = cols[rng.randi_range(0, cols.size() - 1)]
			var nb: PackedInt32Array = grid.nbrs[v0]
			v = nb[rng.randi_range(0, nb.size() - 1)]
		if v < 0 or not grid.buildable(v) or town.top(v) >= 0:
			continue
		town.wild_add(v, types[rng.randi_range(0, types.size() - 1)])
	return town


func _land_phase(n: int, castle_clicks: int, wild_clicks: int) -> void:
	var out_sigs := {}
	var ctx_out := {}
	var cols_seen := 0
	var states := {}
	for s in n:
		var town := _country(s, castle_clicks if s % 2 == 0 else 0, wild_clicks)
		var b := CSBuild.new()
		b.build(grid, town)
		var w := CSWorld.new()
		w.build(grid, town, b.land)
		var rd := CSRoads.new()
		rd.build(w)
		var sc := CSScatter.new()
		sc.build(w)
		var scratch := CSScatter.new()           # per-column rock outcomes: run the rock rule on one column at a time
		scratch.world = w
		scratch.grid = grid
		scratch.town = town
		for v: int in w.ground:
			var before: Dictionary = scratch.counts.duplicate()
			scratch._rocks(v)
			var rocks: Array = []
			for kk: String in scratch.counts:
				if int(scratch.counts[kk]) != int(before.get(kk, 0)):
					rocks.append(kk)
			rocks.sort()
			var rec := town.wild_rec(v)
			var cx := w.ctx(v)
			var alt := w.altitude(v)
			var own := "l%d.h=%s.t%d.d%d" % [int(rec.get("l", 0)), str(rec.get("h", "")), int(rec.get("t", 0)), int(rec.get("d", 0))]
			states[own] = true
			var ctx_key := "w%d r%d m%d d%d c%d t%d l%d k%d|alt%d" % [int(cx.water), int(cx.rock), int(cx.mount), int(cx.road), int(cx.castle), int(cx.tree), int(cx.land), int(cx.deck), clampi(roundi(alt / 3.0), 0, 5)]
			var tr := str(sc.species.get(v, "-"))
			var rd_info: Dictionary = rd.info.get(v, {})
			var road := "-"
			if not rd_info.is_empty():
				road = "%s/%d/s%d" % [str(rd_info.cls), (rd_info.conns as Array).size(), int(rd_info.surface)]
			var hs := str(rec.get("h", ""))
			var kind_h := ("M" if hs.count("m") > 0 else "") + ("R" if hs.count("r") > 0 else "")
			var sig := "tree=%s%d.rocks=%s.road=%s.garden=%d" % [tr, int(rec.get("t", 0)), ",".join(rocks), road, 1 if w.garden.has(v) else 0]
			out_sigs[sig] = int(out_sigs.get(sig, 0)) + 1
			if not ctx_out.has(ctx_key):
				ctx_out[ctx_key] = {}
			(ctx_out[ctx_key] as Dictionary)[sig] = int((ctx_out[ctx_key] as Dictionary).get(sig, 0)) + 1
			cols_seen += 1
			if tr != "-":
				_tally("species", tr)
			for rk: String in rocks:
				_tally("rockkind", rk)
			if road != "-":
				_tally("road", str(rd_info.cls) + "/" + ["cobble", "gravel", "dirt", "plank", "stone"][int(rd_info.surface)])
			_tally("terrain", kind_h if kind_h != "" else ("garden" if w.garden.has(v) else "plain"))
		for v: int in w.deck:
			var rd_info2: Dictionary = rd.info.get(v, {})
			if not rd_info2.is_empty():
				var road2 := "%s/%d/s%d" % [str(rd_info2.cls), (rd_info2.conns as Array).size(), int(rd_info2.surface)]
				_tally("road", str(rd_info2.cls) + "/" + ["cobble", "gravel", "dirt", "plank", "stone"][int(rd_info2.surface)])
				out_sigs["deck." + road2] = int(out_sigs.get("deck." + road2, 0)) + 1
	print("== landscape columns: %d countries (half with a castle), %d earth columns, %d own states seen" % [n, cols_seen, states.size()])
	for part: String in ["terrain", "species", "rockkind", "road"]:
		var d: Dictionary = tallies.get(part, {})
		var keys := d.keys()
		keys.sort_custom(func(x: String, y: String) -> bool: return int(d[x]) > int(d[y]))
		var ps: Array = []
		for kk: String in keys:
			ps.append("%s %d" % [kk, int(d[kk])])
		print("  %-9s %2d kinds: %s" % [part, d.size(), ", ".join(ps)])
	print("  distinct column outcomes (tree species+level, rocks, road class/links/surface, garden) %d, neighbourhoods (counts of water/rock/mount/road/castle/tree/land/deck + altitude band) %d" % [out_sigs.size(), ctx_out.size()])
	var fo := _fanout("landscape", ctx_out)
	var heights := 0
	for l in range(0, CSTown.MAX_HEIGHT + 1):
		heights += 1 << l
	out["landscape"] = {"countries": n, "columns": cols_seen, "states_seen": states.size(), "states_possible": heights * 5, "outcomes": out_sigs.size(),
		"contexts": ctx_out.size(), "fanout": fo, "tallies": tallies.duplicate(true)}


func _init() -> void:
	var towns := 100
	var clicks := 70
	var country := 30
	var ripple := 25
	var exh_point := 0
	var json := ""
	var phases := "castle,ripple,exh,land,plans"
	var style_towns := 40
	var style_points := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--towns="):
			towns = int(a.get_slice("=", 1))
		elif a.begins_with("--clicks="):
			clicks = int(a.get_slice("=", 1))
		elif a.begins_with("--country="):
			country = int(a.get_slice("=", 1))
		elif a.begins_with("--ripple="):
			ripple = int(a.get_slice("=", 1))
		elif a.begins_with("--exh_point="):
			exh_point = int(a.get_slice("=", 1))
		elif a.begins_with("--json="):
			json = a.substr(7)
		elif a.begins_with("--phases="):
			phases = a.get_slice("=", 1)
		elif a.begins_with("--style_towns="):
			style_towns = int(a.get_slice("=", 1))
		elif a.begins_with("--style_points="):
			style_points = int(a.get_slice("=", 1))
		elif a == "--merge" and FileAccess.file_exists(json):
			var f0 := FileAccess.open(json, FileAccess.READ)
			var d0 = JSON.parse_string(f0.get_as_text())
			f0.close()
			if d0 is Dictionary:
				out = d0
	grid = CSGrid.new()
	grid.generate()
	var t0 := Time.get_ticks_msec()
	if phases.contains("castle"):
		_castle_phase(towns, clicks)
		print("  (%d ms)" % (Time.get_ticks_msec() - t0))
	tallies.clear()
	if phases.contains("ripple") and ripple > 0:
		_ripple(ripple, 4)
		print("  (%d ms)" % (Time.get_ticks_msec() - t0))
	if phases.contains("exh"):
		var pts := _four_valent()
		var pt := int(pts[mini(exh_point, pts.size() - 1)])
		out["exh"] = {"cell": _cell(pt), "k0": _exhaustive(pt, 0), "k1": _exhaustive(pt, 1)}
		print("  (%d ms)" % (Time.get_ticks_msec() - t0))
	if phases.contains("styles"):
		_styles_phase(style_towns, clicks, style_points)
		print("  (%d ms)" % (Time.get_ticks_msec() - t0))
	if phases.contains("plans"):
		out["plans"] = [_plan("castle"), _plan("random:3:70"), _plan("village")]
	tallies.clear()
	if phases.contains("land") and country > 0:
		_land_phase(country, 40, 220)
		print("  (%d ms)" % (Time.get_ticks_msec() - t0))
	if json != "":
		DirAccess.make_dir_recursive_absolute(json.get_base_dir())
		var f := FileAccess.open(json, FileAccess.WRITE)
		if f == null:
			print("FAIL cannot write ", json)
			quit(1)
			return
		f.store_string(JSON.stringify(out))
		f.close()
		print("wrote ", json)
	quit(0)
