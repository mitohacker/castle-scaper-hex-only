class_name CSTown
extends RefCounted
## What the player built: blocks on grid vertices, one colour each (Townscaper's whole model). Everything else is
## derived from this by CSBuild.

const MAX_LEVEL := 15
const COLOURS := 12

var blocks := {}            # v * 64 + k -> colour index
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


func size() -> int:
	return blocks.size()


func to_dict() -> Dictionary:
	var list := []
	var ks := blocks.keys()
	ks.sort()
	for kk: int in ks:
		list.append([kk / 64, kk % 64, int(blocks[kk])])
	return {"name": name, "grid_seed": grid_seed, "grid_radius": grid_radius, "blocks": list}


func from_dict(d: Dictionary) -> void:
	blocks.clear()
	name = str(d.get("name", "Untitled"))
	grid_seed = int(d.get("grid_seed", 1))
	grid_radius = int(d.get("grid_radius", 10))
	for b in d.get("blocks", []):
		blocks[int(b[0]) * 64 + int(b[1])] = int(b[2])


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
