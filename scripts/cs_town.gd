class_name CSTown
extends RefCounted
## What the player built: blocks on grid vertices, one colour each (Townscaper's whole model). Everything else is
## derived from this by CSBuild.

const MAX_LEVEL := 15
const COLOURS := 12
const MAX_HEIGHT := 6           # mountain / rock levels in one column
const MAX_TREES := 3            # tree levels in one column: a tree, a grove, a forest
## The build types the player picks from (the castle is the only one that uses the 12 colours).
enum { T_CASTLE, T_LAND, T_ROAD, T_TREE, T_ROCK, T_MOUNTAIN }
const TYPE_NAMES := ["Castle", "Land", "Road", "Trees", "Rocks", "Mountains"]

var blocks := {}            # v * 64 + k -> colour index
## The landscape: grid point -> {"l": 1 when it is plain land, "h": "mrm.." the height levels from the ground up (m mountain, r rock),
## "t": tree levels 0..3, "d": 1 when a road runs through it}. A column of the landscape and a castle block never share a grid point,
## except that a courtyard (castle land with no block) can take land, trees and a road.
var wild := {}
var grid_seed := 1
var grid_radius := 10
var name := "Untitled"


static func key(v: int, k: int) -> int:
	return v * 64 + k


func has(v: int, k: int) -> bool:
	return k >= 0 and blocks.has(v * 64 + k)


func colour(v: int, k: int) -> int:
	return int(blocks.get(v * 64 + k, 0))


func add(v: int, k: int, c: int) -> bool:
	if k < 0 or k > MAX_LEVEL or has(v, k):
		return false
	blocks[v * 64 + k] = clampi(c, 0, COLOURS - 1)
	return true


func remove(v: int, k: int) -> bool:
	return blocks.erase(v * 64 + k)


func top(v: int) -> int:
	## The highest block on v, or -1.
	for k in range(MAX_LEVEL, -1, -1):
		if blocks.has(v * 64 + k):
			return k
	return -1


func columns() -> Array:
	## Vertices that hold at least one block, sorted.
	var seen := {}
	for kk: int in blocks:
		seen[kk / 64] = true
	var out := seen.keys()
	out.sort()
	return out


func clear() -> void:
	blocks.clear()
	wild.clear()


func size() -> int:
	return blocks.size()


# --- the landscape ---------------------------------------------------------------------------------

func has_wild(v: int) -> bool:
	return wild.has(v)


func wild_rec(v: int) -> Dictionary:
	return wild.get(v, {})


func wild_heights(v: int) -> String:
	return str(wild.get(v, {}).get("h", ""))


func wild_trees(v: int) -> int:
	return int(wild.get(v, {}).get("t", 0))


func wild_road(v: int) -> bool:
	return int(wild.get(v, {}).get("d", 0)) == 1


func wild_is_ground(v: int) -> bool:
	## True when the column has earth under it (land, a height or trees); a road alone over water is a bridge or a jetty.
	var r: Dictionary = wild.get(v, {})
	return not r.is_empty() and (int(r.get("l", 0)) == 1 or str(r.get("h", "")) != "" or int(r.get("t", 0)) > 0)


func wild_count() -> int:
	var n := 0
	for v: int in wild:
		var r: Dictionary = wild[v]
		n += int(r.get("l", 0)) + str(r.get("h", "")).length() + int(r.get("t", 0)) + int(r.get("d", 0))
	return n


func wild_columns() -> Array:
	var out := wild.keys()
	out.sort()
	return out


func wild_add(v: int, type: int) -> bool:
	## One click of a landscape type on column v. Land: plain meadow. Road: only where there are no trees. Trees: only where there is no road;
	## each click adds a level (a tree, a grove, a forest). Rocks / mountains: one more height level (up to MAX_HEIGHT).
	var r: Dictionary = wild.get(v, {})
	match type:
		T_LAND:
			if int(r.get("l", 0)) == 1 or wild_is_ground(v):
				return false
			r["l"] = 1
		T_ROAD:
			if int(r.get("d", 0)) == 1 or int(r.get("t", 0)) > 0:
				return false
			r["d"] = 1
		T_TREE:
			if int(r.get("d", 0)) == 1 or int(r.get("t", 0)) >= MAX_TREES:
				return false
			r["t"] = int(r.get("t", 0)) + 1
		T_ROCK, T_MOUNTAIN:
			var h := str(r.get("h", ""))
			if h.length() >= MAX_HEIGHT:
				return false
			r["h"] = h + ("r" if type == T_ROCK else "m")
		_:
			return false
	wild[v] = r
	return true


func wild_remove(v: int) -> bool:
	## One right-click: the trees come off first, then the road, then the top height level, then the plain land; an empty column goes.
	if not wild.has(v):
		return false
	var r: Dictionary = wild[v]
	if int(r.get("t", 0)) > 0:
		r["t"] = int(r["t"]) - 1
	elif int(r.get("d", 0)) == 1:
		r["d"] = 0
	elif str(r.get("h", "")) != "":
		r["h"] = str(r["h"]).substr(0, str(r["h"]).length() - 1)
	elif int(r.get("l", 0)) == 1:
		r["l"] = 0
	_tidy(v)
	return true


func wild_clear(v: int) -> void:
	wild.erase(v)


func _tidy(v: int) -> void:
	var r: Dictionary = wild.get(v, {})
	if int(r.get("l", 0)) == 0 and str(r.get("h", "")) == "" and int(r.get("t", 0)) == 0 and int(r.get("d", 0)) == 0:
		wild.erase(v)


func to_dict() -> Dictionary:
	var list := []
	var ks := blocks.keys()
	ks.sort()
	for kk: int in ks:
		list.append([kk / 64, kk % 64, int(blocks[kk])])
	var wl := []
	for v: int in wild_columns():
		var r: Dictionary = wild[v]
		wl.append([v, int(r.get("l", 0)), str(r.get("h", "")), int(r.get("t", 0)), int(r.get("d", 0))])
	return {"name": name, "grid_seed": grid_seed, "grid_radius": grid_radius, "blocks": list, "wild": wl}


func from_dict(d: Dictionary) -> void:
	blocks.clear()
	name = str(d.get("name", "Untitled"))
	grid_seed = int(d.get("grid_seed", 1))
	grid_radius = int(d.get("grid_radius", 10))
	wild.clear()
	for b in d.get("blocks", []):
		blocks[int(b[0]) * 64 + int(b[1])] = int(b[2])
	for w in d.get("wild", []):
		wild[int(w[0])] = {"l": int(w[1]), "h": str(w[2]), "t": int(w[3]), "d": int(w[4])}


func duplicate_town() -> CSTown:
	var t := CSTown.new()
	t.from_dict(to_dict())
	return t


func save_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


func load_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	from_dict(data)
	return true
