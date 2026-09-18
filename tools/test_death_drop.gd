extends SceneTree
## Headless: softcore death drops — bag + inventory cut; empty safe; locked skipped; respawn ok.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	var failed := 0
	if srv == null:
		print("FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	# Deterministic: 0.0 → 5% gold, first preferred stacks, 1 item pick.
	srv.death_drop_randf = func() -> float: return 0.0

	failed += _test_death_with_items(srv)
	failed += _test_death_empty_bag(srv)
	failed += _test_locked_not_dropped(srv)
	failed += _test_respawn_still_works(srv)

	srv.death_drop_randf = Callable()

	if failed == 0:
		print("test_death_drop: PASS")
		quit(0)
	else:
		print("test_death_drop: FAIL count=", failed)
		quit(1)


func _reset(srv) -> void:
	srv.awaiting_respawn = false
	if srv.has_method("try_loot_close"):
		srv.try_loot_close()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
	if srv.combat_stats != null and srv.combat_stats.has_method("restore_after_death"):
		srv.combat_stats.restore_after_death(false)
	srv.set_player_cell(4, 6)


func _kill(srv) -> Dictionary:
	if srv.combat_stats != null:
		srv.combat_stats.player["hp"] = 0
	return srv._finalize_combat_result({
		"ok": true,
		"actions": [{"type": "player_died"}],
	})


func _has_msg(actions: Array, needle: String) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if needle in str(a.get("text", "")):
			return true
	return false


func _has_ground(actions: Array) -> bool:
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) in ["ground_spawn", "ground_update"]:
			return true
	return false


func _bag_coin_qty(bag: Dictionary) -> int:
	var n := 0
	var items_v: Variant = bag.get("items", [])
	if typeof(items_v) != TYPE_ARRAY:
		return 0
	for it in items_v:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("item_id", "")) == "rusty_coin":
			n += int(it.get("qty", 0))
	return n


func _test_death_with_items(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("potion_hp_small", 6)
	srv.inventory.add_item("potion_mp_small", 4)
	srv.inventory.add_item("wooden_sword", 1)
	var gold_before: int = srv.inventory.get_gold()
	var hp_before: int = srv.inventory.get_qty("potion_hp_small")
	var mp_before: int = srv.inventory.get_qty("potion_mp_small")
	var sword_before: int = srv.inventory.get_qty("wooden_sword")
	var bags_before: int = srv._ground_bags.size()
	var r: Dictionary = _kill(srv)
	var acts: Array = r.get("actions", [])
	failed += _expect(bool(r.get("ok", false)), "death ok")
	failed += _expect(srv.awaiting_respawn, "awaiting_respawn")
	failed += _expect(srv.death_cell == Vector2i(4, 6), "death_cell set")
	failed += _expect(_has_ground(acts), "ground_spawn/update emitted")
	failed += _expect(srv._ground_bags.size() > bags_before, "ground bag created")
	var bid: String = srv.find_ground_bag_at(4, 6)
	failed += _expect(bid != "", "bag at death cell")
	var bag: Dictionary = srv._ground_bags.get(bid, {}) if bid != "" else {}
	failed += _expect(str(bag.get("source", "")) == "death", "source=death")
	var bag_items: Array = bag.get("items", []) if typeof(bag.get("items", [])) == TYPE_ARRAY else []
	failed += _expect(not bag_items.is_empty(), "bag has items")
	var gold_after: int = srv.inventory.get_gold()
	var hp_after: int = srv.inventory.get_qty("potion_hp_small")
	var mp_after: int = srv.inventory.get_qty("potion_mp_small")
	var reduced := gold_after < gold_before or hp_after < hp_before or mp_after < mp_before
	failed += _expect(reduced, "inventory/gold reduced")
	failed += _expect(srv.inventory.get_qty("wooden_sword") == sword_before, "equipment not dropped")
	failed += _expect(srv.inventory.slot_count() >= 1, "bag not emptied")
	# randf=0 → 5% of 200 = 10
	failed += _expect(gold_after == gold_before - 10, "gold -5% (10)")
	failed += _expect(_bag_coin_qty(bag) == 10, "rusty_coin in bag == gold lost")
	failed += _expect(_has_msg(acts, "你损失了部分物品/金币"), "loss system_message")
	# Second finalize while already dead must NOT double-drop.
	var bags_mid: int = srv._ground_bags.size()
	var gold_mid: int = srv.inventory.get_gold()
	srv._finalize_combat_result({
		"ok": true,
		"actions": [{"type": "player_died"}],
	})
	failed += _expect(srv._ground_bags.size() == bags_mid, "no double bag")
	failed += _expect(srv.inventory.get_gold() == gold_mid, "no double gold loss")
	return failed


func _test_death_empty_bag(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.inventory.clear()
	failed += _expect(srv.inventory.get_gold() == 0, "empty gold")
	failed += _expect(srv.inventory.slot_count() == 0, "empty slots")
	var r: Dictionary = _kill(srv)
	failed += _expect(bool(r.get("ok", false)), "empty death ok")
	failed += _expect(srv.awaiting_respawn, "empty awaiting")
	failed += _expect(not _has_ground(r.get("actions", [])), "no ground bag when nothing to drop")
	failed += _expect(not _has_msg(r.get("actions", []), "你损失了部分物品/金币"), "no loss msg when nothing dropped")
	return failed


func _test_locked_not_dropped(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 5)
	srv.inventory.add_item("wooden_sword", 1)
	srv.inventory.set_locked("potion_hp_small", true)
	var r: Dictionary = _kill(srv)
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 5, "locked potion kept")
	failed += _expect(srv.inventory.get_qty("wooden_sword") == 1, "equipment kept")
	failed += _expect(not _has_ground(r.get("actions", [])), "no bag when only locked/equip")
	# With gold + locked consumable: only gold (rusty_coin) drops.
	_reset(srv)
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("potion_hp_small", 3)
	srv.inventory.set_locked("potion_hp_small", true)
	var r2: Dictionary = _kill(srv)
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 3, "locked still kept with gold")
	failed += _expect(srv.inventory.get_gold() == 95, "5% of 100 gold lost")
	var bid: String = srv.find_ground_bag_at(4, 6)
	failed += _expect(bid != "", "bag for gold-only drop")
	if bid != "":
		var bag: Dictionary = srv._ground_bags[bid]
		failed += _expect(_bag_coin_qty(bag) == 5, "bag is rusty_coin x5")
		var has_potion := false
		for it in bag.get("items", []):
			if typeof(it) == TYPE_DICTIONARY and str(it.get("item_id", "")) == "potion_hp_small":
				has_potion = true
		failed += _expect(not has_potion, "locked potion not in bag")
	return failed


func _test_respawn_still_works(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	srv.inventory.add_item("potion_hp_small", 2)
	_kill(srv)
	var bid: String = srv.find_ground_bag_at(4, 6)
	failed += _expect(bid != "", "bag before respawn")
	var saved_col = srv.map_collision
	srv.map_collision = null
	srv.respawn_cell = Vector2i(10, 10)
	var rr: Dictionary = srv.try_respawn("town")
	failed += _expect(bool(rr.get("ok", false)), "respawn ok")
	failed += _expect(not srv.awaiting_respawn, "cleared awaiting")
	failed += _expect(srv.player_cell == Vector2i(10, 10), "town cell")
	failed += _expect(srv._ground_bags.has(bid), "death bag persists after respawn")
	# Stand on/adjacent to death bag to loot (town respawn is far away).
	srv.set_player_cell(4, 6)
	var open_r: Dictionary = srv.try_open_ground_bag(bid)
	failed += _expect(bool(open_r.get("ok", false)), "open death bag")
	var take_r: Dictionary = srv.try_loot_take_all()
	failed += _expect(bool(take_r.get("ok", false)), "loot take_all from death bag")
	srv.map_collision = saved_col
	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
