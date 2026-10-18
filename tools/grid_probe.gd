extends SceneTree
## What the cells look like: how many sides, which way round, how long the sides are, how elongated (the building styles size roofs from this).
## Run: Godot --headless --path . --script res://tools/grid_probe.gd

func _initialize() -> void:
	# --jitter=0.2, --circ=0.5, --seed=1
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.jitter = float(opt.get("jitter", CSGrid.default_jitter))
	g.circ_blend = float(opt.get("circ", 0.0))
	g.generate(int(opt.get("seed", 1)), 10, 10.0)
	var b := CSBuild.new()
	b.grid = g
	var by_n := {}
	var cw := 0
	var ccw := 0
	var lens := []
	var elong := []
	var areas := []
	var concave := 0
	var worst := 0.0                     # the sharpest turn the wrong way (deg) over all cells
	for v in g.verts.size():
		if not g.buildable(v):
			continue
		var ol := b.outline(v)
		var n := ol.size()
		by_n[n] = int(by_n.get(n, 0)) + 1
		var a2 := CSRoofs.area2(ol)
		if a2 > 0.0:
			ccw += 1
		else:
			cw += 1
		areas.append(absf(a2) * 0.5)
		if not CSBuild.convex(ol):
			concave += 1
		for i in n:
			var e0 := ol[(i + 1) % n] - ol[i]
			var e1 := ol[(i + 2) % n] - ol[(i + 1) % n]
			if e0.cross(e1) < 0.0:
				worst = maxf(worst, rad_to_deg(absf(e0.angle_to(e1))))
		for i in n:
			lens.append(ol[i].distance_to(ol[(i + 1) % n]))
		# elongation by the principal axis of the corners
		var c := CSRoofs.centroid(ol)
		var sxx := 0.0
		var sxy := 0.0
		var syy := 0.0
		for q in ol:
			var d := q - c
			sxx += d.x * d.x
			sxy += d.x * d.y
			syy += d.y * d.y
		var tr := sxx + syy
		var det := sxx * syy - sxy * sxy
		var disc := sqrt(maxf(tr * tr * 0.25 - det, 0.0))
		var l1 := tr * 0.5 + disc
		var l2 := maxf(tr * 0.5 - disc, 1e-6)
		elong.append(sqrt(l1 / l2))
	lens.sort()
	elong.sort()
	areas.sort()
	print("%s cells %d  sides {%s}  ccw %d cw %d  concave %d  worst reflex %.1f deg" % [str(opt), ccw + cw, str(by_n), ccw, cw, concave, worst])
	print("side length min %.2f p10 %.2f median %.2f p90 %.2f max %.2f" % [lens[0], lens[lens.size() / 10], lens[lens.size() / 2], lens[lens.size() * 9 / 10], lens[lens.size() - 1]])
	print("elongation min %.2f median %.2f p90 %.2f max %.2f" % [elong[0], elong[elong.size() / 2], elong[elong.size() * 9 / 10], elong[elong.size() - 1]])
	print("area min %.1f median %.1f max %.1f" % [areas[0], areas[areas.size() / 2], areas[areas.size() - 1]])
	quit(0)
