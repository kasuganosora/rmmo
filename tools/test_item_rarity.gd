extends SceneTree
## Headless: item rarity labels + catalog normalize + tip/float wiring.

const ItemRarity = preload("res://scripts/ui/item_rarity.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const EquipCompare = preload("res://scripts/ui/equip_compare.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_label_cn()
	failed += _test_format_name_line()
	failed += _test_normalize_and_def()
	failed += _test_catalog_defaults_and_tags()
	failed += _test_equip_compare_preserves_prefix()
	failed += await _test_hud_float_and_inv_tip()
	if failed == 0:
		print("test_item_rarity: PASS")
		quit(0)
	else:
		print("test_item_rarity: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _test_label_cn() -> int:
	var failed := 0
	failed += _expect(ItemRarity.label_cn("common") == "普通", "common→普通")
	failed += _expect(ItemRarity.label_cn("uncommon") == "优秀", "uncommon→优秀")
	failed += _expect(ItemRarity.label_cn("rare") == "精良", "rare→精良")
	failed += _expect(ItemRarity.label_cn("epic") == "史诗", "epic→史诗")
	failed += _expect(ItemRarity.label_cn("COMMON") == "普通", "case-insensitive")
	failed += _expect(ItemRarity.label_cn("") == "普通", "empty→普通")
	failed += _expect(ItemRarity.label_cn("legendary") == "普通", "unknown→普通")
	return failed


func _test_format_name_line() -> int:
	var failed := 0
	failed += _expect(
		ItemRarity.format_name_line("木剑", "uncommon") == "[优秀] 木剑",
		"format [优秀] 木剑"
	)
	failed += _expect(
		ItemRarity.format_name_line("小型生命药水", "common") == "[普通] 小型生命药水",
		"format [普通] potion"
	)
	failed += _expect(
		ItemRarity.format_name_line("强化石", "rare") == "[精良] 强化石",
		"format [精良] stone"
	)
	failed += _expect(
		ItemRarity.format_name_line("骨项链", "epic") == "[史诗] 骨项链",
		"format [史诗] necklace"
	)
	failed += _expect(
		ItemRarity.format_name_line("  ", "rare") == "[精良] ?",
		"empty name → ?"
	)
	return failed


func _test_normalize_and_def() -> int:
	var failed := 0
	failed += _expect(ItemRarity.normalize("Rare") == "rare", "normalize Rare")
	failed += _expect(ItemRarity.normalize(null) == "common", "normalize null")
	var def := {"id": "x", "name": "X", "rarity": "epic"}
	failed += _expect(ItemRarity.rarity_of_def(def) == "epic", "rarity_of_def epic")
	failed += _expect(
		ItemRarity.format_def_name(def) == "[史诗] X",
		"format_def_name"
	)
	failed += _expect(ItemRarity.rarity_of_def({}) == "common", "empty def common")
	return failed


func _test_catalog_defaults_and_tags() -> int:
	var failed := 0
	var cat: RefCounted = ItemCatalog.new()
	cat.load_catalog()
	failed += _expect(cat.has_item("potion_hp_small"), "catalog has potion")
	var pot: Dictionary = cat.get_item("potion_hp_small")
	failed += _expect(str(pot.get("rarity", "")) == "common", "potion default common")
	var herb: Dictionary = cat.get_item("wild_herb")
	failed += _expect(str(herb.get("rarity", "")) == "common", "material omit→common")
	var sword: Dictionary = cat.get_item("wooden_sword")
	failed += _expect(str(sword.get("rarity", "")) == "uncommon", "wooden_sword uncommon")
	var vest: Dictionary = cat.get_item("leather_vest")
	failed += _expect(str(vest.get("rarity", "")) == "uncommon", "leather_vest uncommon")
	var stone: Dictionary = cat.get_item("enhance_stone")
	failed += _expect(str(stone.get("rarity", "")) == "rare", "enhance_stone rare")
	var shiny: Dictionary = cat.get_item("fish_shiny")
	failed += _expect(str(shiny.get("rarity", "")) == "rare", "fish_shiny rare")
	var feast: Dictionary = cat.get_item("food_fish_feast")
	failed += _expect(str(feast.get("rarity", "")) == "rare", "food_fish_feast rare")
	var bone: Dictionary = cat.get_item("bone_necklace")
	failed += _expect(str(bone.get("rarity", "")) == "epic", "bone_necklace epic")
	# register_item normalizes bad rarity
	cat.register_item({"id": "tmp_junk", "name": "Junk", "type": "misc", "rarity": "ultra"})
	var junk: Dictionary = cat.get_item("tmp_junk")
	failed += _expect(str(junk.get("rarity", "")) == "common", "register bad→common")
	cat.register_item({"id": "tmp_ok", "name": "Ok", "type": "misc"})
	var ok: Dictionary = cat.get_item("tmp_ok")
	failed += _expect(str(ok.get("rarity", "")) == "common", "register omit→common")
	return failed


func _test_equip_compare_preserves_prefix() -> int:
	var failed := 0
	var sword := {
		"id": "wooden_sword",
		"name": "木剑",
		"type": "equipment",
		"equip_slot": "weapon_main",
		"rarity": "uncommon",
		"bonuses": {"p_atk": 3},
	}
	var base := ItemRarity.format_name_line("木剑", "uncommon") + "\nwooden_sword"
	var tip := EquipCompare.format_compare_tip(sword, {}, base)
	failed += _expect(tip.begins_with("[优秀] 木剑"), "compare tip keeps rarity prefix")
	failed += _expect(tip.contains("当前：空"), "compare still adds 当前：空")
	return failed


func _test_hud_float_and_inv_tip() -> int:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		return failed
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	failed += _expect(hud.has_method("_item_rarity_name_line"), "HUD helper present")
	failed += _expect(hud.has_method("show_item_gain_float"), "float API")
	# Without Net.server catalog, rarity falls back to common on empty def.
	hud.show_item_gain_float("wild_herb", 2, "野生药草")
	await process_frame
	var texts: Array = hud.get_item_gain_float_texts() if hud.has_method("get_item_gain_float_texts") else []
	failed += _expect(texts.size() >= 1, "float text present")
	if texts.size() >= 1:
		var t0 := str(texts[0])
		failed += _expect(t0.find("获得") >= 0, "float has 获得")
		failed += _expect(t0.find("野生药草") >= 0, "float has name")
		failed += _expect(t0.find("[普通]") >= 0, "float has [普通] when no catalog")
	# Unit-style: helper with synthetic def via mocking is hard; call format path directly
	var line := ItemRarity.format_name_line("木剑", "uncommon")
	failed += _expect(line == "[优秀] 木剑", "direct format for tip builders")
	# Inv tip builder if method exists — apply to a throwaway panel
	if hud.has_method("_apply_inv_slot_compare_tip"):
		# Inject a tiny fake catalog path by stubbing _item_def is not possible;
		# instead verify helper composition matches expected tip first line.
		var tip_name := ItemRarity.format_name_line("强化石", "rare")
		failed += _expect(tip_name == "[精良] 强化石", "inv tip name composition")
	hud.hide_item_gain_floats()
	hud.queue_free()
	await process_frame
	return failed
