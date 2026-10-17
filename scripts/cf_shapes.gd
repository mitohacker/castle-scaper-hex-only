class_name CFShapes
extends RefCounted
## Small 2D outline makers for the plan (x, z) plane. All outlines run counter-clockwise.


static func circle(c: Vector2, r: float, n: int, rot: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := rot + TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func rect(c: Vector2, ax: Vector2, hl: float, hw: float) -> PackedVector2Array:
	## Centre c, long axis ax (unit), half length hl along it, half width hw across it.
	var nx := Vector2(-ax.y, ax.x)
	return PackedVector2Array([c + ax * hl + nx * hw, c - ax * hl + nx * hw, c - ax * hl - nx * hw, c + ax * hl - nx * hw])


static func rect_ab(a: Vector2, b: Vector2, hw: float, ext_a: float = 0.0, ext_b: float = 0.0) -> PackedVector2Array:
	## A strip from a to b (extended ext_a behind a and ext_b beyond b), 2 * hw wide.
	var d := b - a
	var l := d.length()
	if l < 1e-6:
		return PackedVector2Array()
	var ax := d / l
	var mid := (a + b) * 0.5 + ax * ((ext_b - ext_a) * 0.5)
	return rect(mid, ax, l * 0.5 + (ext_a + ext_b) * 0.5, hw)


static func offset(poly: PackedVector2Array, delta: float) -> PackedVector2Array:
	## A convex counter-clockwise outline pushed out by delta (mitred corners); the same corners in the same order.
	var n := poly.size()
	var out := PackedVector2Array()
	for i in n:
		var p := poly[i]
		var a := (p - poly[(i - 1 + n) % n]).normalized()
		var b := (poly[(i + 1) % n] - p).normalized()
		var na := Vector2(a.y, -a.x)
		var nb := Vector2(b.y, -b.x)
		var k := 1.0 + na.dot(nb)
		out.append(p + (na + nb) * (delta / maxf(k, 0.2)))
	return out


static func scaled(poly: PackedVector2Array, c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(c + (p - c) * s)
	return out


static func moved(poly: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + d)
	return out
