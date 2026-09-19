extends "res://scripts/util/catalog_base.gd"
## Skill definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/skills.json",
	"res://data/combat/skills.json",
]


func _data_paths() -> Array:
	return DATA_PATHS


func _list_key() -> String:
	return "skills"


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
	out["starter"] = bool(out.get("starter", false))
	out["learn_level"] = maxi(int(out.get("learn_level", 1)), 1)
	out["sp_cost"] = maxi(int(out.get("sp_cost", 0 if out["starter"] else 1)), 0)
	if str(out.get("id", "")).strip_edges() == "basic_attack":
		out["starter"] = true
		out["learn_level"] = 1
		out["sp_cost"] = 0
	return out


func get_skill(skill_id: String) -> Dictionary:
	return get_def(skill_id)


func has_skill(skill_id: String) -> bool:
	return has_id(skill_id)


## Runtime inject for tests / pack overrides. Does not persist.
func register_skill(def: Dictionary) -> String:
	return register_def(def)



func is_starter(skill_id: String) -> bool:
	var def := get_skill(skill_id)
	if def.is_empty():
		return skill_id.strip_edges() == "basic_attack"
	return bool(def.get("starter", false))


func starter_ids() -> Array:
	var out: Array = []
	for sid in all_ids():
		if is_starter(str(sid)):
			out.append(str(sid))
	if "basic_attack" not in out:
		out.append("basic_attack")
	out.sort()
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
			"starter": true,
			"learn_level": 1,
			"sp_cost": 0,
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
			"starter": true,
			"learn_level": 1,
			"sp_cost": 0,
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
			"requires_target": false,
			"target_mode": "ground",
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
		"mana_shield": {
			"id": "mana_shield",
			"name": "法力护盾",
			"category": "magic",
			"mp_cost": 12,
			"cooldown": 20.0,
			"range": 0,
			"effect": "apply_status",
			"requires_target": false,
			"status": {
				"id": "mana_shield",
				"name": "法力护盾",
				"kind": "buff",
				"duration": 30.0,
				"tick_interval": 0,
				"absorb_ratio": 0.5,
				"absorb_max": 0,
				"hp_per_mp": 2,
			},
		},
		"stealth": {
			"id": "stealth",
			"name": "潜行",
			"category": "physical",
			"mp_cost": 10,
			"cooldown": 15.0,
			"range": 0,
			"effect": "apply_status",
			"requires_target": false,
			"status": {
				"id": "stealth",
				"name": "潜行",
				"kind": "buff",
				"duration": 8.0,
				"tick_interval": 0,
			},
		},
		"taunt": {
			"id": "taunt",
			"name": "嘲讽",
			"category": "physical",
			"mp_cost": 6,
			"cooldown": 8.0,
			"range": 4,
			"effect": "taunt",
			"hate_amount": 1000,
			"requires_target": true,
		},
		"interrupt": {
			"id": "interrupt",
			"name": "打断",
			"category": "magic",
			"mp_cost": 8,
			"cooldown": 10.0,
			"range": 4,
			"effect": "interrupt",
			"power": 0.35,
			"requires_target": true,
			"status": {
				"id": "silence",
				"name": "沉默",
				"kind": "debuff",
				"duration": 3.0,
				"tick_interval": 0,
			},
		},
		"mark": {
			"id": "mark",
			"name": "标记",
			"category": "magic",
			"mp_cost": 8,
			"cooldown": 10.0,
			"range": 5,
			"effect": "mark",
			"requires_target": true,
			"status": {
				"id": "mark",
				"name": "标记",
				"kind": "debuff",
				"duration": 12.0,
				"tick_interval": 0,
				"stack_max": 1,
				"def_mul": 0.85,
			},
		},
		"revive": {
			"id": "revive",
			"name": "复活",
			"category": "magic",
			"mp_cost": 25,
			"cooldown": 30.0,
			"range": 4,
			"effect": "revive",
			"heal_pct": 0.3,
			"requires_target": true,
		},
		"charge": {
			"id": "charge",
			"name": "冲锋",
			"category": "physical",
			"mp_cost": 12,
			"cooldown": 12.0,
			"range": 6,
			"min_range": 2,
			"effect": "charge",
			"power": 1.2,
			"requires_target": true,
			"status": {
				"id": "root",
				"name": "定身",
				"kind": "debuff",
				"duration": 0.75,
				"tick_interval": 0,
				"move_speed_mul": 0.0,
			},
		},
		"battle_shout": {
			"id": "battle_shout",
			"name": "战吼",
			"category": "physical",
			"mp_cost": 10,
			"cooldown": 20.0,
			"range": 0,
			"effect": "apply_status",
			"requires_target": false,
			"party_share": true,
			"party_duration": 15.0,
			"status": {
				"id": "battle_shout",
				"name": "战吼",
				"kind": "buff",
				"duration": 15.0,
				"tick_interval": 0,
				"stack_max": 1,
				"atk_add": 3,
			},
			"learn_level": 3,
			"sp_cost": 1,
		},
		"execute": {
			"id": "execute",
			"name": "斩杀",
			"category": "physical",
			"mp_cost": 15,
			"cooldown": 15.0,
			"range": 2,
			"effect": "execute",
			"power": 2.0,
			"hp_threshold": 0.3,
			"requires_target": true,
			"learn_level": 1,
			"sp_cost": 1,
		},
		"mount": {
			"id": "mount",
			"name": "骑乘",
			"category": "physical",
			"mp_cost": 0,
			"cooldown": 2.0,
			"range": 0,
			"effect": "mount",
			"requires_target": false,
			"status": {
				"id": "mounted",
				"name": "骑乘",
				"kind": "buff",
				"duration": 999999.0,
				"tick_interval": 0,
				"move_speed_mul": 1.45,
			},
			"learn_level": 1,
			"sp_cost": 1,
		},
	}
	# Normalize icon fields on builtin defs.
	var keys: Array = _by_id.keys()
	for k in keys:
		_by_id[k] = _normalize_def(_by_id[k])
