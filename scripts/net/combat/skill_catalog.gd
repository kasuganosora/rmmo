extends RefCounted
## Skill definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/skills.json",
	"res://data/combat/skills.json",
]

## id -> def Dictionary
var _by_id: Dictionary = {}


func load_catalog() -> void:
	_by_id.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get("skills", [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var sid := str(d.get("id", "")).strip_edges()
		if sid.is_empty():
			continue
		_by_id[sid] = _normalize_def(d)
	if _by_id.is_empty():
		_load_builtin_fallback()



func _normalize_def(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
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


func icon_index_of(skill_id: String) -> int:
	var def := get_skill(skill_id)
	if def.is_empty():
		return -1
	return int(def.get("icon_index", -1))


func icon_id_of(skill_id: String) -> String:
	var def := get_skill(skill_id)
	if def.is_empty():
		return ""
	return str(def.get("icon", "")).strip_edges()


func icon_ref_of(skill_id: String) -> String:
	var def := get_skill(skill_id)
	if def.is_empty():
		return ""
	var r := str(def.get("icon_ref", "")).strip_edges()
	if not r.is_empty():
		return r
	var iid := str(def.get("icon", "")).strip_edges()
	if iid.is_empty():
		return ""
	return "content://icon/%s" % iid


func get_skill(skill_id: String) -> Dictionary:
	skill_id = skill_id.strip_edges()
	if _by_id.has(skill_id):
		return (_by_id[skill_id] as Dictionary).duplicate(true)
	return {}


func has_skill(skill_id: String) -> bool:
	return _by_id.has(skill_id.strip_edges())


func all_ids() -> Array:
	return _by_id.keys()


## Ordered list of skill defs for HUD (text labels).
func list_all() -> Array:
	var ids: Array = _by_id.keys()
	ids.sort()
	var out: Array = []
	for sid in ids:
		out.append(get_skill(str(sid)))
	return out


func _load_builtin_fallback() -> void:
	_by_id = {
		"basic_attack": {
			"id": "basic_attack",
			"name": "普通攻击",
			"category": "physical",
			"mp_cost": 0,
			"cooldown": 0.8,
			"range": 1,
			"effect": "damage",
			"power": 1.0,
			"requires_target": true,
		},
		"power_strike": {
			"id": "power_strike",
			"name": "强力打击",
			"category": "physical",
			"mp_cost": 8,
			"cooldown": 3.0,
			"range": 1,
			"effect": "damage",
			"power": 1.8,
			"requires_target": true,
		},
		"heal_light": {
			"id": "heal_light",
			"name": "轻度治疗",
			"category": "magic",
			"mp_cost": 12,
			"cooldown": 4.0,
			"range": 0,
			"effect": "heal",
			"heal_amount": 35,
			"requires_target": false,
			"cast_time": 1.2,
			"interrupt_on_move": true,
		},
		"tough_skin": {
			"id": "tough_skin",
			"name": "坚韧皮肤",
			"category": "passive",
			"mp_cost": 0,
			"cooldown": 0,
			"range": 0,
			"effect": "passive_def",
			"def_bonus": 5,
			"requires_target": false,
		},
		"keen_eye": {
			"id": "keen_eye",
			"name": "锐利目光",
			"category": "passive",
			"mp_cost": 0,
			"cooldown": 0,
			"range": 0,
			"effect": "passive_atk",
			"atk_bonus": 2,
			"requires_target": false,
		},
		"flame_burst": {
			"id": "flame_burst",
			"name": "火焰爆发",
			"category": "magic",
			"mp_cost": 18,
			"cooldown": 5.0,
			"range": 3,
			"effect": "aoe_damage",
			"power": 1.2,
			"aoe_radius": 2,
			"aoe_shape": "circle",
			"max_targets": 8,
			"requires_target": true,
			"cast_time": 1.5,
			"interrupt_on_move": true,
		},
		"poison_dart": {
			"id": "poison_dart",
			"name": "毒刺",
			"category": "physical",
			"mp_cost": 10,
			"cooldown": 4.0,
			"range": 3,
			"effect": "damage_and_status",
			"power": 0.7,
			"requires_target": true,
			"cast_time": 0.6,
			"interrupt_on_move": true,
			"status": {
				"id": "poison",
				"name": "中毒",
				"kind": "dot",
				"duration": 6.0,
				"tick_interval": 1.0,
				"tick_hp": -4,
				"def_mul": 0.9,
			},
		},
		"battle_cry": {
			"id": "battle_cry",
			"name": "战斗怒吼",
			"category": "physical",
			"mp_cost": 8,
			"cooldown": 12.0,
			"range": 0,
			"effect": "apply_status",
			"requires_target": false,
			"status": {
				"id": "battle_cry",
				"name": "战斗怒吼",
				"kind": "buff",
				"duration": 10.0,
				"tick_interval": 0,
				"atk_mul": 1.35,
			},
		},
		"regen_mist": {
			"id": "regen_mist",
			"name": "再生之雾",
			"category": "magic",
			"mp_cost": 14,
			"cooldown": 10.0,
			"range": 0,
			"aoe_radius": 0,
			"effect": "apply_status",
			"requires_target": false,
			"cast_time": 1.0,
			"interrupt_on_move": true,
			"status": {
				"id": "regen",
				"name": "再生",
				"kind": "hot",
				"duration": 8.0,
				"tick_interval": 1.0,
				"tick_hp": 5,
			},
		},
		"arcane_bolt": {
			"id": "arcane_bolt",
			"name": "奥术飞弹",
			"category": "magic",
			"mp_cost": 16,
			"cooldown": 4.0,
			"range": 4,
			"effect": "damage",
			"power": 2.2,
			"requires_target": true,
			"cast_time": 1.8,
			"interrupt_on_move": true,
		},
		"channel_beam": {
			"id": "channel_beam",
			"name": "导能射线",
			"category": "magic",
			"mp_cost": 20,
			"cooldown": 8.0,
			"range": 4,
			"effect": "damage",
			"power": 2.0,
			"requires_target": true,
			"channel_time": 2.0,
			"interrupt_on_move": true,
		},
	}
	# Normalize icon fields on builtin defs.
	var keys: Array = _by_id.keys()
	for k in keys:
		_by_id[k] = _normalize_def(_by_id[k])


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
