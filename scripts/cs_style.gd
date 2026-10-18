class_name CSStyle
extends RefCounted
## The building styles. A block is one value: style * 16 + colour (CSTown.value); the colour (0-11) picks a scheme from the style's palette
## (walls, roof, trim), the style decides everything else: the walls' material, how tall a storey looks, what the top of a column becomes
## (CSStyleBuild), the doors and windows, the details (CSProps), and how it behaves next to the other styles.
##
## Mesh zones (CFMesh.zone, COLOR.r * 255) the shader reads:  wall 20 + style, roof 30 + style, trim 40 + style (fascia, soffit, beams,
## lacquered wood), paving 50 + style (a courtyard's floor). The castle keeps its own zones (0-14).

enum { CASTLE, HOUSE, APARTMENT, CHINESE, JAPANESE, FANTASY, VILLAGE }
const COUNT := 7
const NAMES := ["Castle", "House", "Apartment", "Chinese", "Japanese", "Fantasy", "Village"]
const KEYS := ["castle", "house", "apartment", "chinese", "japanese", "fantasy", "village"]
const WALL := 20
const ROOF := 30
const TRIM := 40
const PAVE := 50
const GABLE := 60               # the triangle of wall under a gable roof (not part of the walls' bays)
const MAX_TIERS := 4

## Per style: how many metres of a level's wall one window row spans (an apartment level shows two floors).
const ROWS := [1, 1, 2, 1, 1, 1, 1]

# palettes: [name, wall, roof, trim, pattern]
const PAL := {
	HOUSE: [
		["Cream, terracotta", Color(0.93, 0.88, 0.74), Color(0.72, 0.33, 0.2), Color(0.97, 0.96, 0.92), 0],
		["White, slate", Color(0.94, 0.94, 0.92), Color(0.33, 0.38, 0.46), Color(0.3, 0.36, 0.44), 0],
		["Ochre, terracotta", Color(0.84, 0.66, 0.36), Color(0.7, 0.3, 0.18), Color(0.95, 0.93, 0.86), 0],
		["Salmon, terracotta", Color(0.9, 0.6, 0.5), Color(0.62, 0.3, 0.22), Color(0.97, 0.95, 0.9), 0],
		["Red brick, slate", Color(0.66, 0.3, 0.22), Color(0.32, 0.35, 0.4), Color(0.95, 0.94, 0.9), 1],
		["Grey stone, slate", Color(0.62, 0.6, 0.56), Color(0.36, 0.4, 0.44), Color(0.88, 0.86, 0.8), 3],
		["Sage, terracotta", Color(0.62, 0.72, 0.58), Color(0.68, 0.36, 0.24), Color(0.95, 0.94, 0.88), 0],
		["Powder blue, grey", Color(0.66, 0.78, 0.86), Color(0.42, 0.45, 0.5), Color(0.96, 0.96, 0.96), 0],
		["Teal clapboard", Color(0.34, 0.54, 0.56), Color(0.3, 0.3, 0.34), Color(0.95, 0.95, 0.93), 2],
		["Brown brick, tile", Color(0.5, 0.34, 0.26), Color(0.66, 0.34, 0.22), Color(0.9, 0.88, 0.8), 1],
		["Charcoal, zinc", Color(0.3, 0.31, 0.33), Color(0.55, 0.58, 0.6), Color(0.8, 0.45, 0.2), 0],
		["Lavender, slate", Color(0.78, 0.72, 0.88), Color(0.38, 0.36, 0.46), Color(0.96, 0.95, 0.97), 0]],
	APARTMENT: [
		["Light concrete", Color(0.8, 0.8, 0.78), Color(0.35, 0.36, 0.37), Color(0.2, 0.22, 0.25), 0],
		["Warm concrete", Color(0.76, 0.72, 0.66), Color(0.35, 0.36, 0.37), Color(0.22, 0.2, 0.2), 0],
		["Brown brick", Color(0.52, 0.34, 0.27), Color(0.32, 0.32, 0.33), Color(0.85, 0.82, 0.74), 1],
		["Red brick", Color(0.64, 0.3, 0.24), Color(0.32, 0.32, 0.33), Color(0.9, 0.9, 0.88), 1],
		["White stucco", Color(0.93, 0.93, 0.9), Color(0.4, 0.4, 0.42), Color(0.25, 0.3, 0.38), 3],
		["Sand stucco", Color(0.88, 0.78, 0.6), Color(0.4, 0.38, 0.36), Color(0.3, 0.26, 0.22), 3],
		["Blue glass", Color(0.4, 0.58, 0.74), Color(0.3, 0.32, 0.34), Color(0.85, 0.9, 0.95), 2],
		["Teal glass", Color(0.3, 0.6, 0.62), Color(0.3, 0.32, 0.34), Color(0.88, 0.94, 0.94), 2],
		["Dark glass", Color(0.18, 0.24, 0.32), Color(0.26, 0.27, 0.29), Color(0.7, 0.75, 0.8), 2],
		["Yellow ceramic", Color(0.9, 0.76, 0.38), Color(0.4, 0.38, 0.36), Color(0.3, 0.3, 0.32), 0],
		["Pink stucco", Color(0.9, 0.68, 0.66), Color(0.4, 0.38, 0.38), Color(0.95, 0.93, 0.92), 3],
		["Mint stucco", Color(0.7, 0.86, 0.76), Color(0.4, 0.42, 0.42), Color(0.95, 0.97, 0.95), 3]],
	CHINESE: [
		["White, grey tiles", Color(0.93, 0.91, 0.86), Color(0.32, 0.34, 0.36), Color(0.62, 0.12, 0.1), 0],
		["White, green glaze", Color(0.93, 0.91, 0.86), Color(0.2, 0.5, 0.34), Color(0.62, 0.12, 0.1), 0],
		["White, imperial yellow", Color(0.93, 0.91, 0.86), Color(0.92, 0.72, 0.16), Color(0.62, 0.12, 0.1), 0],
		["White, blue glaze", Color(0.93, 0.91, 0.86), Color(0.18, 0.36, 0.64), Color(0.62, 0.12, 0.1), 0],
		["Red, imperial yellow", Color(0.66, 0.12, 0.1), Color(0.92, 0.72, 0.16), Color(0.5, 0.08, 0.07), 1],
		["Red, green glaze", Color(0.66, 0.12, 0.1), Color(0.2, 0.5, 0.34), Color(0.5, 0.08, 0.07), 1],
		["Grey brick, grey tiles", Color(0.55, 0.55, 0.54), Color(0.3, 0.31, 0.33), Color(0.62, 0.12, 0.1), 2],
		["Ochre, orange tiles", Color(0.86, 0.7, 0.42), Color(0.82, 0.42, 0.14), Color(0.62, 0.12, 0.1), 0],
		["White, red tiles", Color(0.93, 0.91, 0.86), Color(0.7, 0.2, 0.14), Color(0.62, 0.12, 0.1), 0],
		["Grey brick, green glaze", Color(0.55, 0.55, 0.54), Color(0.2, 0.5, 0.34), Color(0.62, 0.12, 0.1), 2],
		["Yellow, blue glaze", Color(0.92, 0.8, 0.4), Color(0.18, 0.36, 0.64), Color(0.62, 0.12, 0.1), 0],
		["Dark red, black tiles", Color(0.45, 0.1, 0.09), Color(0.14, 0.14, 0.15), Color(0.7, 0.55, 0.2), 1]],
	JAPANESE: [
		["White, grey kawara", Color(0.93, 0.92, 0.88), Color(0.3, 0.32, 0.34), Color(0.24, 0.17, 0.12), 0],
		["White, black kawara", Color(0.93, 0.92, 0.88), Color(0.12, 0.12, 0.13), Color(0.2, 0.14, 0.1), 0],
		["White, hinoki", Color(0.93, 0.92, 0.88), Color(0.3, 0.32, 0.34), Color(0.6, 0.44, 0.28), 0],
		["Cream, grey", Color(0.9, 0.86, 0.74), Color(0.3, 0.32, 0.34), Color(0.3, 0.2, 0.14), 0],
		["Charred wood", Color(0.14, 0.13, 0.12), Color(0.3, 0.32, 0.34), Color(0.5, 0.36, 0.22), 1],
		["Mud wall", Color(0.66, 0.52, 0.38), Color(0.3, 0.32, 0.34), Color(0.24, 0.17, 0.12), 2],
		["White, copper green", Color(0.93, 0.92, 0.88), Color(0.34, 0.56, 0.5), Color(0.24, 0.17, 0.12), 0],
		["White, blue-grey", Color(0.93, 0.92, 0.88), Color(0.35, 0.42, 0.5), Color(0.24, 0.17, 0.12), 0],
		["Sakura plaster", Color(0.94, 0.84, 0.84), Color(0.3, 0.32, 0.34), Color(0.3, 0.2, 0.15), 0],
		["Dark wood", Color(0.3, 0.22, 0.16), Color(0.16, 0.16, 0.17), Color(0.62, 0.5, 0.34), 1],
		["White, thatch", Color(0.93, 0.92, 0.88), Color(0.62, 0.5, 0.28), Color(0.24, 0.17, 0.12), 0],
		["Grey stone", Color(0.6, 0.6, 0.58), Color(0.3, 0.32, 0.34), Color(0.24, 0.17, 0.12), 2]],
	FANTASY: [
		["Lilac, violet", Color(0.78, 0.66, 0.9), Color(0.52, 0.26, 0.7), Color(1.0, 0.82, 0.3), 0],
		["Pink, magenta", Color(0.96, 0.7, 0.8), Color(0.82, 0.2, 0.5), Color(1.0, 0.9, 0.4), 0],
		["Teal, purple", Color(0.5, 0.82, 0.78), Color(0.5, 0.24, 0.62), Color(1.0, 0.85, 0.4), 1],
		["Mint, orange", Color(0.7, 0.92, 0.78), Color(0.95, 0.5, 0.2), Color(0.4, 0.9, 1.0), 0],
		["Sky, red", Color(0.62, 0.78, 0.96), Color(0.86, 0.22, 0.3), Color(1.0, 0.9, 0.5), 1],
		["Butter, blue", Color(0.98, 0.9, 0.56), Color(0.26, 0.42, 0.82), Color(0.9, 0.5, 1.0), 2],
		["Coral, teal", Color(0.96, 0.6, 0.5), Color(0.2, 0.6, 0.62), Color(1.0, 0.9, 0.5), 0],
		["Lavender, green", Color(0.82, 0.76, 0.95), Color(0.3, 0.62, 0.4), Color(1.0, 0.8, 0.4), 2],
		["Pearl, gold", Color(0.96, 0.94, 0.98), Color(0.9, 0.7, 0.2), Color(0.6, 0.8, 1.0), 1],
		["Violet, pink", Color(0.46, 0.32, 0.66), Color(0.95, 0.4, 0.7), Color(1.0, 0.8, 0.4), 2],
		["Lime, purple", Color(0.76, 0.9, 0.46), Color(0.5, 0.24, 0.66), Color(1.0, 0.85, 0.4), 0],
		["Peach, turquoise", Color(0.98, 0.8, 0.64), Color(0.2, 0.72, 0.74), Color(1.0, 0.95, 0.5), 1]],
	VILLAGE: [
		["Cream, straw", Color(0.92, 0.86, 0.7), Color(0.74, 0.6, 0.32), Color(0.28, 0.19, 0.12), 0],
		["White, straw", Color(0.95, 0.93, 0.88), Color(0.74, 0.6, 0.32), Color(0.28, 0.19, 0.12), 0],
		["Ochre, dark thatch", Color(0.84, 0.68, 0.42), Color(0.5, 0.4, 0.24), Color(0.26, 0.18, 0.11), 0],
		["Pink, straw", Color(0.92, 0.78, 0.72), Color(0.74, 0.6, 0.32), Color(0.28, 0.19, 0.12), 1],
		["Cream, tile", Color(0.92, 0.86, 0.7), Color(0.7, 0.32, 0.2), Color(0.28, 0.19, 0.12), 0],
		["White, red tile", Color(0.95, 0.93, 0.88), Color(0.66, 0.24, 0.16), Color(0.28, 0.19, 0.12), 1],
		["Yellow, reed", Color(0.94, 0.84, 0.5), Color(0.6, 0.56, 0.44), Color(0.28, 0.19, 0.12), 0],
		["Green wash, straw", Color(0.72, 0.82, 0.64), Color(0.74, 0.6, 0.32), Color(0.28, 0.19, 0.12), 1],
		["Blue wash, straw", Color(0.7, 0.8, 0.86), Color(0.74, 0.6, 0.32), Color(0.28, 0.19, 0.12), 0],
		["White, slate", Color(0.95, 0.93, 0.88), Color(0.34, 0.38, 0.44), Color(0.28, 0.19, 0.12), 2],
		["Cream, mossy thatch", Color(0.92, 0.86, 0.7), Color(0.5, 0.56, 0.28), Color(0.28, 0.19, 0.12), 0],
		["Rose, terracotta", Color(0.9, 0.66, 0.62), Color(0.7, 0.32, 0.2), Color(0.28, 0.19, 0.12), 2]],
}


static func wall_zone(s: int) -> int:
	return WALL + s if s != CASTLE else CFMesh.Z_STONE


static func roof_zone(s: int) -> int:
	return ROOF + s


static func trim_zone(s: int) -> int:
	return TRIM + s


static func pave_zone(s: int) -> int:
	return PAVE + s


static func gable_zone(s: int) -> int:
	return GABLE + s


## How the roof of colour scheme c is covered (the shader draws it): 0 clay tile, 1 slate, 2 thatch, 3 glazed tile, 4 zinc, 5 copper, 6 wood shingle, 7 fish scale.
const ROOF_CLAY := 0
const ROOF_SLATE := 1
const ROOF_THATCH := 2
const ROOF_GLAZE := 3
const ROOF_ZINC := 4
const ROOF_COPPER := 5
const ROOF_SHINGLE := 6
const ROOF_SCALE := 7


static func roof_pattern(s: int, c: int) -> int:
	var nm := str(palette(s, c)[0]).to_lower()
	if s == FANTASY:
		return ROOF_GLAZE if nm.contains("gold") or nm.contains("pearl") else ROOF_SCALE
	if nm.contains("thatch") or nm.contains("straw") or nm.contains("reed"):
		return ROOF_THATCH
	if nm.contains("glaze") or nm.contains("yellow"):
		return ROOF_GLAZE
	if nm.contains("slate"):
		return ROOF_SLATE
	if nm.contains("zinc") or s == APARTMENT:
		return ROOF_ZINC
	if nm.contains("copper"):
		return ROOF_COPPER
	if nm.contains("hinoki"):
		return ROOF_SHINGLE
	if s == JAPANESE and (nm.contains("kawara") or nm.contains("grey") or nm.contains("blue")):
		return ROOF_CLAY
	if nm.contains("black") and s == CHINESE:
		return ROOF_CLAY
	return ROOF_CLAY


static func palette(s: int, c: int) -> Array:
	## [name, wall, roof, trim, pattern] of colour scheme c of style s (the castle's twelve plasters are CSUi.PALETTE).
	if not PAL.has(s):
		return ["", Color(0.9, 0.88, 0.84), Color(0.5, 0.3, 0.2), Color(0.3, 0.3, 0.3), 0]
	return PAL[s][clampi(c, 0, 11)]


static func swatch(s: int, c: int) -> Color:
	return palette(s, c)[1]


## The palettes as arrays the shaders read (index style * 16 + colour): walls (alpha = pattern / 8), roofs, trims.
static func shader_tables() -> Dictionary:
	var wall := PackedColorArray()
	var roof := PackedColorArray()
	var trim := PackedColorArray()
	for s in COUNT:
		for c in 16:
			var e := palette(s, mini(c, 11))
			var w: Color = e[1]
			var rc: Color = e[2]
			wall.append(Color(w.r, w.g, w.b, float(int(e[4])) / 8.0))
			roof.append(Color(rc.r, rc.g, rc.b, float(roof_pattern(s, mini(c, 11))) / 8.0))
			trim.append(e[3])
	return {"wall": wall, "roof": roof, "trim": trim}


static func apply_palettes(mat: ShaderMaterial) -> void:
	var t := shader_tables()
	mat.set_shader_parameter("style_wall", t.wall)
	mat.set_shader_parameter("style_roof", t.roof)
	mat.set_shader_parameter("style_trim", t.trim)
