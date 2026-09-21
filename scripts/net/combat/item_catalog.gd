extends "res://scripts/util/catalog_base.gd"
## Item definitions loaded from JSON (shared path with future GameServer).
## Template fields: id, name, type, rarity, stack_max, use_effect, sell_price (+ legacy consumable/effect).

const DATA_PATHS: Array[String] = [
	"combat/items.json",
]


func _data_paths() -> Array:
	return DATA_PATHS


func _list_key() -> String:
	return "items"


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
	# Rarity: common|uncommon|rare|epic (default common).
	var rar := str(out.get("rarity", "")).strip_edges().to_lower()
	if rar not in ["common", "uncommon", "rare", "epic"]:
		rar = "common"
	out["rarity"] = rar
	if not out.has("consumable"):
		out["consumable"] = str(out.get("type", "")) == "consumable" or ue in [
			"heal_hp", "heal_mp", "apply_status", "clear_status", "cleanse", "recall", "teleport_home", "repair_equip", "party_summon"
		]
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
	return get_def(item_id)


func has_item(item_id: String) -> bool:
	return has_id(item_id)


## Runtime inject for tests / pack overrides. Does not persist.
func register_item(def: Dictionary) -> String:
	return register_def(def)


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
		{
			"id": "scroll_town",
			"name": "回城卷轴",
			"desc": "使用后传送回城镇安全点，消耗一张。",
			"type": "consumable",
			"stack_max": 20,
			"consumable": true,
			"use_effect": "recall",
			"effect": "recall",
			"cooldown": 1.0,
			"sell_price": 15,
		},
		{
			"id": "bait_worm",
			"name": "蚯蚓饵",
			"desc": "普通鱼饵。钓鱼时消耗，略微提高闪光鱼概率。",
			"type": "material",
			"stack_max": 99,
			"consumable": true,
			"use_effect": "",
			"sell_price": 1,
		},
		{
			"id": "bait_shiny",
			"name": "闪光饵",
			"desc": "稀有鱼饵。钓鱼时消耗，明显提高闪光鱼概率。",
			"type": "material",
			"stack_max": 99,
			"consumable": true,
			"use_effect": "",
			"sell_price": 5,
		},
		{
			"id": "tool_pickaxe",
			"name": "矿工镐",
			"desc": "开采矿石用的镐。采集时需要持有；每次成功消耗 1 点耐久，耐久归零时损坏。",
			"type": "misc",
			"stack_max": 1,
			"consumable": false,
			"use_effect": "",
			"sell_price": 8,
			"durability_max": 40,
		},
		{
			"id": "iron_ore",
			"name": "铁矿石",
			"type": "material",
			"stack_max": 99,
			"consumable": false,
			"use_effect": "",
			"sell_price": 3,
		},
	]:
		_by_id[str(d["id"])] = _normalize_def(d)
