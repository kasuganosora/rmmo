extends SceneTree
## Headless: equipment enhance (+0..+5) via blacksmith try_enhance; stone+gold; persist.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_enhance: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.equipment == null or srv.item_catalog == null:
		print("test_enhance: FAIL combat layers missing")
		quit(1)
		return

	# Catalog + shop
	var def: Dictionary = srv.item_catalog.get_item("enhance_stone")
	failed += _expect(not def.is_empty(), "catalog enhance_stone")
	failed += _expect(str(def.get("name", "")) == "强化石", "Chinese name 强化石")
	failed += _expect(int(def.get("stack_max", 0)) == 99, "stack_max 99")
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "enhance_stone"), "shop sells enhance_stone")

	failed += _expect(srv.has_method("try_enhance"), "srv try_enhance")
	failed += _expect(srv.equipment.has_method("try_enhance"), "eq try_enhance")
	failed += _expect(int(srv.equipment.ENHANCE_MAX) == 5, "ENHANCE_MAX 5")

	# --- Weapon enhance: +1 p_atk per level ---
	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
	srv.inventory.clear()
	srv.equipment.clear()
	srv.inventory.add_gold(500)
	srv.inventory.add_item("wooden_sword", 1)
	srv.inventory.add_item("enhance_stone", 10)
	var eq: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(eq.get("ok", false)), "equip sword")
	failed += _expect(srv.equipment.get_enhance("weapon_main") == 0, "start +0")
	var bon0: Dictionary = srv.equipment.total_bonuses()
	failed += _expect(int(bon0.get("p_atk", 0)) == 3, "base p_atk 3")

	var gold0: int = srv.inventory.get_gold()
	var stone0: int = srv.inventory.get_qty("enhance_stone")
	var r1: Dictionary = srv.try_enhance("weapon_main")
	failed += _expect(bool(r1.get("ok", false)), "enhance +1 ok")
	failed += _expect(int(r1.get("enhance", 0)) == 1, "enhance=1")
	failed += _expect(srv.equipment.get_enhance("weapon_main") == 1, "slot +1")
	failed += _expect(int(r1.get("gold_spent", 0)) == 10, "cost 10 for +0→+1")
	failed += _expect(srv.inventory.get_gold() == gold0 - 10, "gold -10")
	failed += _expect(srv.inventory.get_qty("enhance_stone") == stone0 - 1, "stone -1")
	failed += _expect(str(r1.get("stat_key", "")) == "p_atk", "weapon stat p_atk")
	failed += _expect(_msg_has(r1, "强化成功"), "success msg")
	failed += _expect(_has(r1, "equipment_update"), "equipment_update")
	failed += _expect(_has(r1, "inventory_update"), "inventory_update")
	var bon1: Dictionary = srv.equipment.total_bonuses()
	failed += _expect(int(bon1.get("p_atk", 0)) == 4, "p_atk 3+1=4")

	# Cost scales: +1→+2 = 20
	var r2: Dictionary = srv.try_enhance("weapon_main")
	failed += _expect(bool(r2.get("ok", false)), "enhance +2 ok")
	failed += _expect(int(r2.get("gold_spent", 0)) == 20, "cost 20 for +1→+2")
	failed += _expect(srv.equipment.get_enhance("weapon_main") == 2, "slot +2")
	failed += _expect(int(srv.equipment.total_bonuses().get("p_atk", 0)) == 5, "p_atk 3+2=5")

	# Snapshot includes enhance
	var snap_ok := false
	for row in srv.equipment.snapshot():
		if typeof(row) == TYPE_DICTIONARY and str(row.get("slot", "")) == "weapon_main":
			snap_ok = int(row.get("enhance", 0)) == 2
	failed += _expect(snap_ok, "snapshot enhance 2")

	# Persist through unequip/equip
	var uq: Dictionary = srv.try_unequip_item("weapon_main")
	failed += _expect(bool(uq.get("ok", false)), "unequip ok")
	var bag_enh := 0
	for brow in srv.inventory.snapshot():
		if typeof(brow) == TYPE_DICTIONARY and str(brow.get("id", "")) == "wooden_sword":
			bag_enh = int(brow.get("enhance", 0))
	failed += _expect(bag_enh == 2, "bag keeps enhance 2")
	var eq2: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(eq2.get("ok", false)), "re-equip ok")
	failed += _expect(srv.equipment.get_enhance("weapon_main") == 2, "re-equip keeps +2")
	failed += _expect(int(srv.equipment.total_bonuses().get("p_atk", 0)) == 5, "bonuses after re-equip")

	# --- Armor enhance: +1 p_def ---
	srv.inventory.add_item("leather_vest", 1)
	var eqv: Dictionary = srv.try_equip_item("leather_vest", "chest")
	failed += _expect(bool(eqv.get("ok", false)), "equip vest")
	var rv: Dictionary = srv.try_enhance("chest")
	failed += _expect(bool(rv.get("ok", false)), "enhance vest ok")
	failed += _expect(str(rv.get("stat_key", "")) == "p_def", "armor stat p_def")
	failed += _expect(srv.equipment.get_enhance("chest") == 1, "vest +1")
	failed += _expect(int(srv.equipment.total_bonuses().get("p_def", 0)) == 3, "p_def 2+1=3")

	# --- Max +5 ---
	srv.equipment.set_enhance("weapon_main", 4)
	srv.inventory.add_item("enhance_stone", 5)
	srv.inventory.add_gold(200)
	var r4: Dictionary = srv.try_enhance("weapon_main")
	failed += _expect(bool(r4.get("ok", false)), "+4→+5 ok")
	failed += _expect(srv.equipment.get_enhance("weapon_main") == 5, "at +5")
	failed += _expect(int(r4.get("gold_spent", 0)) == 50, "cost 50 for +4→+5")
	var stone_max: int = srv.inventory.get_qty("enhance_stone")
	var rmax: Dictionary = srv.try_enhance("weapon_main")
	failed += _expect(not bool(rmax.get("ok", true)), "maxed fails")
	failed += _expect(str(rmax.get("reason", "")) == "maxed", "reason maxed")
	failed += _expect(srv.inventory.get_qty("enhance_stone") == stone_max, "stone unchanged at max")
	failed += _expect(_msg_has(rmax, "强化上限"), "max msg")

	# --- Fail: no stone ---
	srv.equipment.set_enhance("chest", 1)
	# drain stones
	while srv.inventory.get_qty("enhance_stone") > 0:
		srv.inventory.consume("enhance_stone", 1)
	var rns: Dictionary = srv.try_enhance("chest")
	failed += _expect(not bool(rns.get("ok", true)), "no stone fails")
	failed += _expect(str(rns.get("reason", "")) == "no_stone", "reason no_stone")
	failed += _expect(_msg_has(rns, "需要强化石"), "no stone msg")

	# --- Fail: no gold ---
	srv.inventory.add_item("enhance_stone", 2)
	srv.inventory.gold = 0
	var rng: Dictionary = srv.try_enhance("chest")
	failed += _expect(not bool(rng.get("ok", true)), "no gold fails")
	failed += _expect(str(rng.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(srv.inventory.get_qty("enhance_stone") == 2, "stone not consumed on no_gold")

	# --- Blacksmith dialogue options include enhance ---
	srv.inventory.add_gold(100)
	var meta := {"blacksmith": true, "name": "铁匠", "repair_cost_per_point": 1}
	# Ensure blacksmith NPC interact path
	if srv.combat_stats != null and srv.combat_stats.has_method("set_npc_meta"):
		pass
	# Directly inspect try_npc_interact if blacksmith spawn exists; else dialogue choice API
	failed += _expect(srv.has_method("try_dialogue_choice"), "try_dialogue_choice")
	srv.inventory.add_item("enhance_stone", 1)
	srv.equipment.set_enhance("chest", 1)
	var gold_d: int = srv.inventory.get_gold()
	var stone_d: int = srv.inventory.get_qty("enhance_stone")
	var rd: Dictionary = srv.try_dialogue_choice("enhance:chest")
	failed += _expect(bool(rd.get("ok", false)), "dialogue enhance:chest ok")
	failed += _expect(srv.equipment.get_enhance("chest") == 2, "dialogue bumped to +2")
	failed += _expect(srv.inventory.get_gold() == gold_d - 20, "dialogue cost 20")
	failed += _expect(srv.inventory.get_qty("enhance_stone") == stone_d - 1, "dialogue stone -1")

	# EquipCompare effective bonuses
	var EquipCompare = load("res://scripts/ui/equip_compare.gd")
	var ws: Dictionary = srv.item_catalog.get_item("wooden_sword")
	var eff = EquipCompare.effective_bonuses(ws, 2)
	failed += _expect(int(eff.get("p_atk", 0)) == 5, "compare effective p_atk 3+2")
	var vest: Dictionary = srv.item_catalog.get_item("leather_vest")
	var eff2 = EquipCompare.effective_bonuses(vest, 1)
	failed += _expect(int(eff2.get("p_def", 0)) == 3, "compare effective p_def 2+1")

	if failed == 0:
		print("test_enhance: PASS")
		quit(0)
	else:
		print("test_enhance: FAIL %d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	print("  FAIL  %s" % label)
	return 1


func _has(r: Dictionary, atype: String) -> bool:
	for a in r.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == atype:
			return true
	return false


func _msg_has(r: Dictionary, frag: String) -> bool:
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(frag) >= 0:
			return true
	return false
