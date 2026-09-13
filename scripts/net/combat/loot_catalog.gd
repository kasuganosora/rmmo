extends RefCounted
## Loot table definitions: by_npc_id / by_charset / default.
## Entries: {item_id, chance, min, max}. MockServer rolls on kill_npc.

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/loot_tables.json",
	"res://data/combat/loot_tables.json",
]

var _by_npc_id: Dictionary = {}
var _by_charset: Dictionary = {}
var _default: Array = []
## Optional RNG override for tests (Callable returning float in [0,1)).
var rng_roll: Callable = Callable()


func load_catalog() -> void:
	_by_npc_id.clear()
	_by_charset.clear()
	_default.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var root: Dictionary = raw
	var bn: Variant = root.get("by_npc_id", {})
	if typeof(bn) == TYPE_DICTIONARY:
		_by_npc_id = (bn as Dictionary).duplicate(true)
	var bc: Variant = root.get("by_charset", {})
	if typeof(bc) == TYPE_DICTIONARY:
		_by_charset = (bc as Dictionary).duplicate(true)
	var def_v: Variant = root.get("default", [])
	if typeof(def_v) == TYPE_ARRAY:
		_default = (def_v as Array).duplicate(true)
	if _by_npc_id.is_empty() and _by_charset.is_empty() and _default.is_empty():
		_load_builtin_fallback()


func _load_builtin_fallback() -> void:
	_default = [
		{"item_id": "rusty_coin", "chance": 0.5, "min": 1, "max": 2},
	]
	_by_charset = {
		"retira_slime": [
			{"item_id": "slime_jelly", "chance": 0.8, "min": 1, "max": 2},
			{"item_id": "potion_hp_small", "chance": 0.3, "min": 1, "max": 1},
		],
	}


## Resolve table: npc_id → charset → default.
func get_entries(npc_id: String, charset: String = "") -> Array:
	npc_id = npc_id.strip_edges()
	charset = charset.strip_edges()
	if npc_id != "" and _by_npc_id.has(npc_id):
		var v: Variant = _by_npc_id[npc_id]
		if typeof(v) == TYPE_ARRAY:
			return (v as Array).duplicate(true)
	if charset != "" and _by_charset.has(charset):
		var v2: Variant = _by_charset[charset]
		if typeof(v2) == TYPE_ARRAY:
			return (v2 as Array).duplicate(true)
	return _default.duplicate(true)


func _rand() -> float:
	if rng_roll.is_valid():
		return float(rng_roll.call())
	return randf()


## Roll loot entries → [{item_id, qty}, ...].
func roll(npc_id: String, charset: String = "") -> Array:
	var out: Array = []
	for entry_v in get_entries(npc_id, charset):
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry_v
		var iid := str(e.get("item_id", "")).strip_edges()
		if iid.is_empty():
			continue
		var chance: float = float(e.get("chance", 0.0))
		if _rand() > chance:
			continue
		var mn: int = maxi(int(e.get("min", 1)), 1)
		var mx: int = maxi(int(e.get("max", mn)), mn)
		var qty: int = mn if mx <= mn else (mn + int(_rand() * float(mx - mn + 1)))
		if qty > 0:
			out.append({"item_id": iid, "qty": qty})
	return out


## Deterministic roll for tests: force every chance ≥ threshold to succeed with max qty.
func roll_forced(npc_id: String, charset: String = "", force_chance_at: float = 0.0) -> Array:
	var prev: Callable = rng_roll
	rng_roll = func() -> float: return force_chance_at
	var out: Array = roll(npc_id, charset)
	rng_roll = prev
	return out


static func _load_json_first(paths: Array) -> Variant:
	for p in paths:
		var path := str(p)
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return null
