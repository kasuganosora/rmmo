extends SceneTree
## Headless: repair_kit consumable → repair_equip (+30% max ceil all damaged); fail if full.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_repair_kit: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.equipment == null or srv.combat_engine == null or srv.item_catalog == null:
		print("test_repair_kit: FAIL combat layers missing")
		quit(1)
		return

	# Catalog
	var def: Dictionary = srv.item_catalog.get_item("repair_kit")
	failed += _expect(not def.is_empty(), "catalog has repair_kit")
	failed += _expect(str(def.get("name", "")) == "修理工具包", "Chinese name")
	failed += _expect(str(def.get("use_effect", def.get("effect", ""))) == "repair_equip", "use_effect repair_equip")
	failed += _expect(int(def.get("stack_max", 0)) == 20, "stack_max 20")
	failed += _expect(int(def.get("sell_price", 0)) == 8, "sell_price 8")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 2.0) < 0.01, "cooldown 2s")

	# Shop stock
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "repair_kit"), "shop sells repair_kit")

	# Equip + wear durability
	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = maxi(int(srv.combat_stats.player.get("hp_max", 100)), 1)
	srv.inventory.clear()
	srv.inventory.add_item("wooden_sword", 1)
	srv.inventory.add_item("leather_vest", 1)
	srv.inventory.add_item("repair_kit", 2)
	srv.equipment.clear()
	var r_eq: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(r_eq.get("ok", false)), "equip sword")
	var r_vest: Dictionary = srv.try_equip_item("leather_vest", "chest")
	failed += _expect(bool(r_vest.get("ok", false)), "equip vest")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "sword full 100")
	failed += _expect(srv.equipment.get_durability("chest") == 100, "vest full 100")

	# Direct set damaged (prefer over death wear for exact numbers)
	srv.equipment._durability["weapon_main"] = 50
	srv.equipment._durability["chest"] = 70
	var gold_before: int = srv.inventory.get_gold()
	var qty_before: int = srv.inventory.get_qty("repair_kit")
	failed += _expect(qty_before == 2, "kit qty 2")

	var r: Dictionary = srv.try_use_item("repair_kit")
	failed += _expect(bool(r.get("ok", false)), "use kit ok")
	# +30% of 100 = 30 → 50→80, 70→100
	failed += _expect(srv.equipment.get_durability("weapon_main") == 80, "sword 50+30=80")
	failed += _expect(srv.equipment.get_durability("chest") == 100, "vest 70+30 capped 100")
	failed += _expect(srv.inventory.get_qty("repair_kit") == qty_before - 1, "kit qty -1")
	failed += _expect(srv.inventory.get_gold() == gold_before, "no gold spent")
	failed += _expect(_has(r, "equipment_update"), "equipment_update")
	failed += _expect(_has(r, "inventory_update"), "inventory_update")
	failed += _expect(_msg_has(r, "使用修理工具包，修复了装备。"), "success msg")

	# Full durability → fail, qty unchanged
	srv.equipment._durability["weapon_main"] = 100
	srv.equipment._durability["chest"] = 100
	var qty_full: int = srv.inventory.get_qty("repair_kit")
	# Clear cooldown if any
	if srv.combat_stats != null and srv.combat_stats.has_method("set_item_cooldown"):
		srv.combat_stats.set_item_cooldown("repair_kit", 0.0)
	var r2: Dictionary = srv.try_use_item("repair_kit")
	failed += _expect(not bool(r2.get("ok", true)), "full fails")
	failed += _expect(str(r2.get("reason", "")) == "nothing_to_repair", "reason nothing_to_repair")
	failed += _expect(_msg_has(r2, "没有需要修理的装备。"), "fail msg")
	failed += _expect(srv.inventory.get_qty("repair_kit") == qty_full, "qty unchanged when full")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "sword still full")

	# Smoke: equipment apply_kit_repair / needs_repair APIs
	failed += _expect(srv.equipment.has_method("apply_kit_repair"), "has apply_kit_repair")
	failed += _expect(srv.equipment.has_method("needs_repair"), "has needs_repair")
	failed += _expect(not srv.equipment.needs_repair(), "needs_repair false when full")
	srv.equipment._durability["weapon_main"] = 10
	failed += _expect(srv.equipment.needs_repair(), "needs_repair true when damaged")
	var rr: Dictionary = srv.equipment.apply_kit_repair(0.3)
	failed += _expect(bool(rr.get("ok", false)), "apply_kit_repair ok")
	failed += _expect(srv.equipment.get_durability("weapon_main") == 40, "10+30=40 via API")

	# Smoke existing durability/repair path still present
	if srv.has_method("try_repair"):
		srv.equipment._durability["weapon_main"] = 90
		srv.inventory.add_gold(50)
		var r_gold: Dictionary = srv.try_repair("weapon_main", 1)
		failed += _expect(bool(r_gold.get("ok", false)), "blacksmith try_repair still ok")
		failed += _expect(srv.equipment.get_durability("weapon_main") == 100, "gold repair full")

	# Combat engine recognizes effect
	failed += _expect(srv.combat_engine._is_item_effect("repair_equip"), "_is_item_effect repair_equip")

	if failed == 0:
		print("test_repair_kit: PASS")
		quit(0)
		return
	print("test_repair_kit: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _msg_has(result: Dictionary, needle: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if needle in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
