extends RefCounted
## Item definitions loaded from JSON (shared path with future GameServer).
## Template fields: id, name, type, stack_max, use_effect, sell_price (+ legacy consumable/effect).

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/items.json",
	"res://data/combat/items.json",
]

var _by_id: Dictionary = {}


func load_catalog() -> void:
	_by_id.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get("items", [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var iid := str(d.get("id", "")).strip_edges()
		if iid.is_empty():
			continue
		_by_id[iid] = _normalize_def(d)
	if _by_id.is_empty():
		_load_builtin_fallback()


## Normalize legacy consumable/effect into type / use_effect / stack_max.
func _normalize_def(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var iid := str(out.get("id", ""))
	if not out.has("type") or str(out.get("type", "")).strip_edges() == "":
		if bool(out.get("consumable", false)):
			out["type"] = "consumable"
		else:
			out["type"] = "misc"
	if not out.has("stack_max"):
		var t := str(out.get("type", ""))
		if t == "consumable":
			out["stack_max"] = 20
		elif t == "equipment":
			out["stack_max"] = 1
		else:
			out["stack_max"] = 99
	else:
		out["stack_max"] = maxi(int(out.get("stack_max", 1)), 1)
	# Preserve equipment fields (equip_slot / bonuses).
	if str(out.get("type", "")) == "equipment":
		out["consumable"] = false
		if not out.has("equip_slot"):
			out["equip_slot"] = ""
		if not out.has("bonuses") or typeof(out.get("bonuses")) != TYPE_DICTIONARY:
			out["bonuses"] = {}
	# Prefer use_effect; fall back to legacy effect.
	var ue := str(out.get("use_effect", "")).strip_edges()
	if ue.is_empty():
		ue = str(out.get("effect", "")).strip_edges()
		if not ue.is_empty():
			out["use_effect"] = ue
	else:
		out["effect"] = ue  # keep both in sync for try_use_item
	if not out.has("name") or str(out.get("name", "")).strip_edges() == "":
		out["name"] = iid
	if not out.has("consumable"):
		out["consumable"] = str(out.get("type", "")) == "consumable" or ue in ["heal_hp", "heal_mp"]
	# Icons: MV atlas index (primary) + optional standalone file id.
	if not out.has("icon_index"):
		out["icon_index"] = -1
	else:
		out["icon_index"] = int(out.get("icon_index", -1))
	var icon_id := str(out.get("icon", "")).strip_edges()
	if icon_id.is_empty():
		out.erase("icon")
		out.erase("icon_ref")
	else:
		out["icon"] = icon_id
		out["icon_ref"] = "content://icon/%s" % icon_id
	return out


func get_item(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if _by_id.has(item_id):
		return (_by_id[item_id] as Dictionary).duplicate(true)
	return {}


func has_item(item_id: String) -> bool:
	return _by_id.has(item_id.strip_edges())


func all_ids() -> Array:
	return _by_id.keys()


## Ordered list of item defs for HUD (text labels).
func list_all() -> Array:
	var ids: Array = _by_id.keys()
	ids.sort()
	var out: Array = []
	for iid in ids:
		out.append(get_item(str(iid)))
	return out



func icon_index_of(item_id: String) -> int:
	var def := get_item(item_id)
	if def.is_empty():
		return -1
	return int(def.get("icon_index", -1))


func icon_id_of(item_id: String) -> String:
	var def := get_item(item_id)
	if def.is_empty():
		return ""
	return str(def.get("icon", "")).strip_edges()


func icon_ref_of(item_id: String) -> String:
	var def := get_item(item_id)
	if def.is_empty():
		return ""
	var r := str(def.get("icon_ref", "")).strip_edges()
	if not r.is_empty():
		return r
	var iid := str(def.get("icon", "")).strip_edges()
	if iid.is_empty():
		return ""
	return "content://icon/%s" % iid


func _load_builtin_fallback() -> void:
	_by_id = {}
	for d in [
		{
			"id": "potion_hp_small",
			"name": "小型生命药水",
			"type": "consumable",
			"stack_max": 20,
			"consumable": true,
			"use_effect": "heal_hp",
			"effect": "heal_hp",
			"amount": 40,
			"cooldown": 1.0,
			"sell_price": 5,
		},
		{
			"id": "potion_mp_small",
			"name": "小型魔法药水",
			"type": "consumable",
			"stack_max": 20,
			"consumable": true,
			"use_effect": "heal_mp",
			"effect": "heal_mp",
			"amount": 25,
			"cooldown": 1.0,
			"sell_price": 5,
		},
	]:
		_by_id[str(d["id"])] = _normalize_def(d)


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
