extends SceneTree
## What the cells of the double hex grid look like: how many sides (12 for the dodecagons, 3 for the triangles between them), which way
## round, how long the sides are, how elongated, which directions the sides run in (6 orientations = 12 headings, multiples of 30 degrees), and how many
## cells there are of each kind (the building styles size roofs from this).
## Expected: 169 dodecagons + 384 triangles buildable, every side 2.887 m, corners 150 / 60 degrees, no concave cell.
## Run: Godot --headless --path . --script res://tools/grid_probe.gd [-- --svg=shots/hex_grid_plan.svg]   (--svg writes a plan of every cell)

func _initialize() -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			opt[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1) if "=" in a else "1"
	var g := CSGrid.new()
	g.generate(int(opt.get("seed", 1)))
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
	var dirs := {}                       # side direction (deg, mod 180) -> sides
	var corners := {}                    # interior angle (deg) -> corners
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
			var dd := int(roundf(fposmod(rad_to_deg((ol[(i + 1) % n] - ol[i]).angle()), 180.0)))
			dirs[dd % 180] = int(dirs.get(dd % 180, 0)) + 1
			var turn := rad_to_deg((ol[(i + 1) % n] - ol[i]).angle_to(ol[(i + 2) % n] - ol[(i + 1) % n]))
			var ia := int(roundf(180.0 - turn))
			corners[ia] = int(corners.get(ia, 0)) + 1
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
	var dk := dirs.keys()
	dk.sort()
	print("%d line orientations (%d headings, every 30 deg): %s" % [dk.size(), dk.size() * 2, str(dk)])
	print("corner angles (deg: count): %s   grid %s: %d dodecagons, %d triangles in all" % [str(corners), CSGrid.GRID_ID, g.d_count, g.verts.size() - g.d_count])
	print("side length min %.2f p10 %.2f median %.2f p90 %.2f max %.2f" % [lens[0], lens[lens.size() / 10], lens[lens.size() / 2], lens[lens.size() * 9 / 10], lens[lens.size() - 1]])
	print("elongation min %.2f median %.2f p90 %.2f max %.2f" % [elong[0], elong[elong.size() / 2], elong[elong.size() * 9 / 10], elong[elong.size() - 1]])
	print("area min %.1f median %.1f max %.1f" % [areas[0], areas[areas.size() / 2], areas[areas.size() - 1]])
	if opt.has("svg"):
		_write_svg(g, str(opt.svg))
	quit(0)


func _write_svg(g: CSGrid, path: String) -> void:
	## A plan of the cells: dodecagons dark blue, triangles light blue, the sea ring grey; 9 px to the metre.
	var sc := 9.0
	var ext := 0.0
	for v in g.verts.size():
		ext = maxf(ext, g.verts[v].length())
	ext += 8.0
	var size := int(ext * 2.0 * sc)
	var out := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n<rect width="100%%" height="100%%" fill="#10202b"/>\n' % [size, size, size, size]
	for v in g.verts.size():
		var poly := g.dual(v)
		if poly.size() < 3:
			continue
		var pts := []
		for q in poly:
			pts.append("%.1f,%.1f" % [(q.x + ext) * sc, (q.y + ext) * sc])
		var fill := "#3a4a54"
		if g.buildable(v):
			fill = "#2c5b72" if g.is_dodecagon(v) else "#5aa0bb"
		out += '<polygon points="%s" fill="%s" stroke="#cfe6ef" stroke-width="1"/>\n' % [" ".join(pts), fill]
	out += "</svg>\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("wrote ", path)
