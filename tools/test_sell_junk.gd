extends SceneTree
## Headless: try_shop_sell_junk bulk sell rules (misc/material, price<=10, excludes).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_sell_junk: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.item_catalog == null:
		print("test_sell_junk: FAIL combat layers missing")
		quit(1)
		return

	failed += _expect(srv.has_method("try_shop_sell_junk"), "has try_shop_sell_junk")

	# --- empty / no junk ---
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	var r_empty: Dictionary = srv.try_shop_sell_junk()
	failed += _expect(not bool(r_empty.get("ok", true)), "empty fails")
	failed += _expect(str(r_empty.get("reason", "")) == "no_junk", "reason no_junk")
	failed += _expect(_msg_has(r_empty, "没有可出售的垃圾。"), "msg 没有可出售的垃圾")
	failed += _expect(srv.inventory.get_gold() == 0, "gold unchanged empty")

	# --- only excluded / non-junk ---
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	srv.inventory.add_item("pet_whistle", 1)  # misc, sell 10 — excluded by id
	srv.inventory.add_item("scroll_town", 1)  # excluded
	srv.inventory.add_item("potion_hp_small", 3)  # potion_* + consumable
	srv.inventory.add_item("fish_small", 2)  # fish_* material would match without prefix exclude
	srv.inventory.add_item("food_grilled_fish", 1)  # food_*
	srv.inventory.add_item("wooden_sword", 1)  # equipment
	var r_ex: Dictionary = srv.try_shop_sell_junk()
	failed += _expect(not bool(r_ex.get("ok", true)), "excludes-only fails")
	failed += _expect(_msg_has(r_ex, "没有可出售的垃圾。"), "msg excludes")
	failed += _expect(srv.inventory.get_qty("pet_whistle") == 1, "pet_whistle kept")
	failed += _expect(srv.inventory.get_qty("fish_small") == 2, "fish_small kept")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 3, "potion kept")
	failed += _expect(srv.inventory.get_gold() == 10, "gold unchanged excludes")

	# --- locked junk skipped ---
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.add_item("slime_jelly", 5)
	srv.inventory.add_item("torn_cloth", 2)
	if srv.inventory.has_method("set_locked"):
		srv.inventory.set_locked("slime_jelly", true)
	var r_lock: Dictionary = srv.try_shop_sell_junk()
	failed += _expect(bool(r_lock.get("ok", false)), "locked skip still sells other")
	# torn_cloth sell 1 * 2 = 2; slime locked kept
	failed += _expect(srv.inventory.get_qty("slime_jelly") == 5, "locked jelly kept")
	failed += _expect(srv.inventory.get_qty("torn_cloth") == 0, "cloth sold")
	failed += _expect(srv.inventory.get_gold() == 2, "gold +2 from cloth")
	failed += _expect(_msg_has(r_lock, "出售垃圾获得 2 金。"), "msg 2金")
	failed += _expect(_has(r_lock, "inventory_update"), "inventory_update locked case")
	if srv.inventory.has_method("set_locked"):
		srv.inventory.set_locked("slime_jelly", false)

	# --- bulk success: mix junk + keep expensive material / excludes ---
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("slime_jelly", 3)  # 2 each = 6
	srv.inventory.add_item("wild_herb", 4)  # 1 each = 4
	srv.inventory.add_item("monster_fang", 2)  # 3 each = 6
	srv.inventory.add_item("torn_cloth", 1)  # 1
	srv.inventory.add_item("rusty_coin", 5)  # 1 each = 5
	srv.inventory.add_item("fish_shiny", 1)  # material sell 12 > 10 — keep
	srv.inventory.add_item("pet_whistle", 1)
	srv.inventory.add_item("fish_small", 3)
	srv.inventory.add_item("potion_mp_small", 2)
	var expect_gain := 6 + 4 + 6 + 1 + 5  # 22
	var r_ok: Dictionary = srv.try_shop_sell_junk()
	failed += _expect(bool(r_ok.get("ok", false)), "bulk ok")
	failed += _expect(int(r_ok.get("gained", -1)) == expect_gain, "gained %d" % expect_gain)
	failed += _expect(srv.inventory.get_gold() == 100 + expect_gain, "gold +%d" % expect_gain)
	failed += _expect(_msg_has(r_ok, "出售垃圾获得 %d 金。" % expect_gain), "msg bulk")
	failed += _expect(_has(r_ok, "inventory_update"), "inventory_update bulk")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == 0, "jelly sold")
	failed += _expect(srv.inventory.get_qty("wild_herb") == 0, "herb sold")
	failed += _expect(srv.inventory.get_qty("monster_fang") == 0, "fang sold")
	failed += _expect(srv.inventory.get_qty("torn_cloth") == 0, "cloth sold bulk")
	failed += _expect(srv.inventory.get_qty("rusty_coin") == 0, "coin sold")
	failed += _expect(srv.inventory.get_qty("fish_shiny") == 1, "fish_shiny kept (price>10)")
	failed += _expect(srv.inventory.get_qty("pet_whistle") == 1, "whistle kept bulk")
	failed += _expect(srv.inventory.get_qty("fish_small") == 3, "fish_small kept bulk")
	failed += _expect(srv.inventory.get_qty("potion_mp_small") == 2, "potion kept bulk")

	# --- HUD wires SellJunk button (source check; game_hud has unrelated parse noise under load()) ---
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	failed += _expect(not hud_src.is_empty(), "hud source readable")
	failed += _expect("SellJunkBtn" in hud_src, "SellJunkBtn in hud")
	failed += _expect("出售垃圾" in hud_src, "label 出售垃圾 in hud")
	failed += _expect("func _on_shop_sell_junk" in hud_src, "handler _on_shop_sell_junk")
	failed += _expect("request_shop_sell_junk" in hud_src, "calls request_shop_sell_junk")
	var world_src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
	failed += _expect("func request_shop_sell_junk" in world_src, "world request_shop_sell_junk")

	if failed == 0:
		print("test_sell_junk: PASS")
		quit(0)
		return
	print("test_sell_junk: FAIL count=%d" % failed)
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
