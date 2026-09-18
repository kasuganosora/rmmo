extends SceneTree
## Headless: fishing bait optional — no bait / worm / prefer shiny / no consume on fail.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_fish_bait: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.fish_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_fish"), "has try_fish")
	failed += _expect(srv.has_method("_best_fish_bait"), "has _best_fish_bait")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("bait_worm"), "item bait_worm")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("bait_shiny"), "item bait_shiny")
	failed += _expect(int(srv.item_catalog.get_item("bait_worm").get("sell_price", -1)) == 1, "worm sell 1")
	failed += _expect(int(srv.item_catalog.get_item("bait_shiny").get("sell_price", -1)) == 5, "shiny sell 5")

	# Shop sells worm (and shiny).
	if srv.shop_catalog != null:
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "bait_worm"), "shop sells bait_worm")
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "bait_shiny"), "shop sells bait_shiny")

	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	failed += _expect(srv._fish_spots.has("fish_pond_a"), "map fish_pond_a")

	srv.set_player_cell(16, 10)
	if srv.has_method("register_npc"):
		srv.register_npc("fish_pond_a", 16, 11, false, false, 2, 0, 0, {
			"id": "fish_pond_a",
			"name": "小水塘",
			"kind": "object",
			"interact_text": "一处可以垂钓的浅水。",
		})

	# --- without bait: fish works; bait qty stays 0 ---
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	srv._fish_busy_until = 0.0
	if srv.has_method("force_fish_respawn"):
		srv.force_fish_respawn("fish_pond_a")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 0, "no worm before")
	failed += _expect(srv.inventory.get_qty("bait_shiny") == 0, "no shiny before")
	var no_bait: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(no_bait.get("ok", false)), "fish without bait ok")
	failed += _expect(str(no_bait.get("item_id", "")) in ["fish_small", "fish_shiny"], "got fish no bait")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 0, "bait still 0 after")
	failed += _expect(str(no_bait.get("bait_id", "")) == "", "bait_id empty")
	failed += _expect(not _msg_has(no_bait, "使用了"), "no bait msg without bait")

	# --- with worm: decrements on success ---
	srv.force_fish_respawn("fish_pond_a")
	srv._fish_busy_until = 0.0
	srv.inventory.clear()
	srv.inventory.add_item("bait_worm", 3)
	var before_w: int = srv.inventory.get_qty("bait_worm")
	var with_worm: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(with_worm.get("ok", false)), "fish with worm ok")
	failed += _expect(str(with_worm.get("item_id", "")) in ["fish_small", "fish_shiny"], "got fish with worm")
	failed += _expect(srv.inventory.get_qty("bait_worm") == before_w - 1, "worm decremented")
	failed += _expect(str(with_worm.get("bait_id", "")) == "bait_worm", "bait_id worm")
	failed += _expect(_msg_has(with_worm, "使用了蚯蚓饵"), "msg 使用了蚯蚓饵")
	var fish_qty: int = srv.inventory.get_qty("fish_small") + srv.inventory.get_qty("fish_shiny")
	failed += _expect(fish_qty >= 1, "bag has fish after worm")

	# --- prefer shiny bait over worm ---
	srv.force_fish_respawn("fish_pond_a")
	srv._fish_busy_until = 0.0
	srv.inventory.clear()
	srv.inventory.add_item("bait_worm", 5)
	srv.inventory.add_item("bait_shiny", 2)
	var pref: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(pref.get("ok", false)), "fish prefer shiny ok")
	failed += _expect(str(pref.get("bait_id", "")) == "bait_shiny", "used shiny over worm")
	failed += _expect(srv.inventory.get_qty("bait_shiny") == 1, "shiny decremented")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 5, "worm untouched")
	failed += _expect(_msg_has(pref, "使用了闪光饵"), "msg 使用了闪光饵")

	# --- busy: no bait consume ---
	srv.force_fish_respawn("fish_pond_a")
	srv.inventory.clear()
	srv.inventory.add_item("bait_worm", 4)
	srv._fish_busy_until = srv._fish_now() + 5.0
	var busy: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(busy.get("ok", true)), "busy fails")
	failed += _expect(str(busy.get("reason", "")) == "busy", "reason busy")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 4, "busy no consume")

	# --- depleted: no bait consume ---
	srv._fish_busy_until = 0.0
	# First success depletes.
	var ok_pre: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(ok_pre.get("ok", false)), "pre-deplete with bait")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 3, "consumed on success")
	srv._fish_busy_until = 0.0
	var dep: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(dep.get("ok", true)), "depleted fails")
	failed += _expect(str(dep.get("reason", "")) == "depleted", "reason depleted")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 3, "depleted no consume")

	# --- bag full: no bait consume ---
	srv.force_fish_respawn("fish_pond_a")
	srv._fish_busy_until = 0.0
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.max_slots = 1
	srv.inventory.add_item("bait_worm", 2)  # occupies only slot; fish cannot enter
	# If bait stacks in 1 slot and fish needs new slot — bag full.
	var full: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(full.get("ok", true)), "bag full fails")
	failed += _expect(str(full.get("reason", "")) == "bag_full", "reason bag_full")
	failed += _expect(srv.inventory.get_qty("bait_worm") == 2, "bag_full no consume")
	failed += _expect(not srv.is_fish_depleted("fish_pond_a"), "not depleted on bag full")
	srv.inventory.max_slots = 40

	# Starter grant includes ×10 worm (when grant_starter used).
	srv.inventory.grant_starter()
	failed += _expect(srv.inventory.get_qty("bait_worm") == 10, "starter ×10 worm")

	if failed == 0:
		print("test_fish_bait: PASS")
		quit(0)
	else:
		print("test_fish_bait: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _msg_has(result: Dictionary, needle: String) -> bool:
	var acts: Array = result.get("actions", [])
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false
