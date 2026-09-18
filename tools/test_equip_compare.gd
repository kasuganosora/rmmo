extends SceneTree
## Headless unit tests for equipment compare-on-hover tip helper.

const EquipCompare = preload("res://scripts/ui/equip_compare.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_slot_resolution()
	failed += _test_delta_vs_equipped()
	failed += _test_empty_slot()
	failed += _test_non_equipment()
	failed += _test_catalog_real_items()
	if failed == 0:
		print("test_equip_compare: PASS")
		quit(0)
	else:
		print("test_equip_compare: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _test_slot_resolution() -> int:
	var failed := 0
	var sword := {
		"id": "wooden_sword",
		"name": "木剑",
		"type": "equipment",
		"equip_slot": "weapon_main",
		"bonuses": {"p_atk": 3},
	}
	failed += _expect(EquipCompare.equip_slot_for_item(sword) == "weapon_main", "equip_slot weapon_main")
	failed += _expect(EquipCompare.is_equipment(sword), "is_equipment sword")
	var ring := {
		"id": "copper_ring",
		"type": "equipment",
		"equip_slot": "ring",
		"bonuses": {"p_atk": 1},
	}
	var slots := EquipCompare.paperdoll_slots_for("ring")
	failed += _expect(slots.size() == 2 and slots[0] == "ring_l", "ring family slots")
	var snap := [
		{"slot": "ring_l", "item_id": ""},
		{"slot": "ring_r", "item_id": "copper_ring"},
	]
	failed += _expect(EquipCompare.find_equipped_id("ring", snap) == "copper_ring", "find ring_r when l empty")
	return failed


func _test_delta_vs_equipped() -> int:
	var failed := 0
	var weak := {
		"id": "wooden_sword",
		"name": "木剑",
		"type": "equipment",
		"equip_slot": "weapon_main",
		"bonuses": {"p_atk": 3, "p_def": 2},
	}
	var strong := {
		"id": "iron_sword_fake",
		"name": "铁剑",
		"type": "equipment",
		"equip_slot": "weapon_main",
		"bonuses": {"p_atk": 8, "p_def": 1},
	}
	var tip := EquipCompare.format_compare_tip(strong, weak, "铁剑\niron_sword_fake")
	print("  tip-delta:\n", tip)
	failed += _expect(tip.contains("物攻 3 → 8 (+5)"), "atk delta +5")
	failed += _expect(tip.contains("物防 2 → 1 (-1)"), "def delta -1")
	failed += _expect(tip.contains("当前：木剑"), "shows current name")
	failed += _expect(tip.contains("+") and tip.contains("-"), "has + and - signs")
	return failed


func _test_empty_slot() -> int:
	var failed := 0
	var sword := {
		"id": "wooden_sword",
		"name": "木剑",
		"type": "equipment",
		"equip_slot": "weapon_main",
		"bonuses": {"p_atk": 3},
	}
	var tip := EquipCompare.format_compare_tip(sword, {}, "木剑\nwooden_sword")
	print("  tip-empty:\n", tip)
	failed += _expect(tip.contains("当前：空"), "mentions 空")
	failed += _expect(tip.contains("物攻 3"), "absolute atk")
	failed += _expect(not tip.contains("→"), "no arrow when empty")
	return failed


func _test_non_equipment() -> int:
	var failed := 0
	var pot := {
		"id": "potion_hp_small",
		"name": "小型生命药水",
		"type": "consumable",
		"bonuses": {"p_atk": 99},
	}
	var base := "小型生命药水\npotion_hp_small\nCtrl+点击拆分 · 右键锁定"
	var tip := EquipCompare.format_compare_tip(pot, {}, base)
	failed += _expect(tip == base, "non-equip unchanged")
	failed += _expect(not tip.contains("当前："), "no compare block")
	failed += _expect(EquipCompare.equip_slot_for_item(pot) == "", "no slot for potion")
	return failed


func _test_catalog_real_items() -> int:
	var failed := 0
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var sword: Dictionary = cat.get_item("wooden_sword")
	var vest: Dictionary = cat.get_item("leather_vest")
	var pot: Dictionary = cat.get_item("potion_hp_small")
	failed += _expect(not sword.is_empty(), "catalog wooden_sword")
	failed += _expect(EquipCompare.equip_slot_for_item(sword) == "weapon_main", "catalog slot")
	# Stronger fake vs wooden_sword from catalog
	var better := sword.duplicate(true)
	better["id"] = "better_sword"
	better["name"] = "精铁木剑"
	var bon: Dictionary = better.get("bonuses", {}).duplicate(true)
	var old_atk := int(bon.get("p_atk", 0))
	bon["p_atk"] = old_atk + 4
	better["bonuses"] = bon
	var tip := EquipCompare.format_compare_tip(better, sword, "精铁木剑\nbetter_sword")
	print("  tip-catalog:\n", tip)
	failed += _expect(tip.contains("(+4)"), "catalog-based +4 atk")
	failed += _expect(tip.contains("物攻 %d → %d" % [old_atk, old_atk + 4]), "catalog atk numbers")
	# Vest absolute when empty
	var tip2 := EquipCompare.format_compare_tip(vest, {}, "皮背心\nleather_vest")
	failed += _expect(tip2.contains("当前：空"), "vest empty slot")
	failed += _expect(tip2.contains("物防"), "vest shows p_def label")
	# Potion from catalog
	var base_p := "药\npotion_hp_small"
	failed += _expect(EquipCompare.format_compare_tip(pot, {}, base_p) == base_p, "catalog potion unchanged")
	return failed
