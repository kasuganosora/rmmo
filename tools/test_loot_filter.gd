extends SceneTree
## Headless: auto_pickup_filter settings + filtered auto-loot vs manual take-all.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var failed := 0
	var Settings = load("res://scripts/game/game_settings.gd")
	failed += _expect(Settings != null, "game_settings loads")
	if Settings == null:
		_finish(failed)
		return

	failed += _test_match_helper(Settings)
	failed += _test_persist(Settings)
	failed += _test_auto_vs_manual(Settings)

	_finish(failed)


func _test_match_helper(Settings) -> int:
	var failed := 0
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	var catalog = srv.item_catalog if srv != null else null
	failed += _expect(Settings.matches_auto_pickup_filter("all", "wooden_sword", catalog), "all allows equip")
	failed += _expect(Settings.matches_auto_pickup_filter("all", "potion_hp_small", catalog), "all allows potion")
	failed += _expect(not Settings.matches_auto_pickup_filter("no_equip", "wooden_sword", catalog), "no_equip skips sword")
	failed += _expect(Settings.matches_auto_pickup_filter("no_equip", "potion_hp_small", catalog), "no_equip allows potion")
	failed += _expect(Settings.matches_auto_pickup_filter("no_equip", "rusty_coin", catalog), "no_equip allows coin")
	failed += _expect(Settings.matches_auto_pickup_filter("no_equip", "slime_jelly", catalog), "no_equip allows material")
	failed += _expect(not Settings.matches_auto_pickup_filter("consumable_gold", "wooden_sword", catalog), "cg skips equip")
	failed += _expect(not Settings.matches_auto_pickup_filter("consumable_gold", "slime_jelly", catalog), "cg skips material")
	failed += _expect(Settings.matches_auto_pickup_filter("consumable_gold", "potion_hp_small", catalog), "cg allows potion")
	failed += _expect(Settings.matches_auto_pickup_filter("consumable_gold", "rusty_coin", catalog), "cg allows gold coin")
	return failed


func _test_persist(Settings) -> int:
	var failed := 0
	var gs: Node = Settings.new()
	gs.name = "LootFilterSettings"
	gs.persist_path = "user://_test_loot_filter.cfg"
	gs.persist_enabled = false
	root.add_child(gs)
	gs.persist_enabled = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.reset_defaults()
	failed += _expect(str(gs.auto_pickup_filter) == "all", "default filter all")
	gs.set_auto_pickup_filter("no_equip")
	failed += _expect(str(gs.auto_pickup_filter) == "no_equip", "set no_equip")
	gs.set_auto_pickup_filter("bogus")
	failed += _expect(str(gs.auto_pickup_filter) == "all", "bogus clamps to all")
	gs.set_auto_pickup_filter("consumable_gold")
	gs.save_to_disk()
	var gs2: Node = Settings.new()
	gs2.name = "LootFilterSettings2"
	gs2.persist_path = gs.persist_path
	gs2.persist_enabled = false
	root.add_child(gs2)
	gs2.load_from_disk()
	failed += _expect(str(gs2.auto_pickup_filter) == "consumable_gold", "reload consumable_gold")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.persist_path))
	gs.queue_free()
	gs2.queue_free()
	return failed


func _simulate_filtered_auto_take(srv, Settings, filter: String) -> void:
	var catalog = srv.item_catalog
	var snap: Dictionary = srv.pending_loot_snapshot()
	var ids: Array = []
	for d_v in snap.get("items", []):
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var iid := str(d_v.get("item_id", "")).strip_edges()
		if iid.is_empty():
			continue
		if Settings.matches_auto_pickup_filter(filter, iid, catalog):
			ids.append(iid)
	for iid in ids:
		if not srv.has_pending_loot():
			break
		srv.try_loot_take(str(iid), -1)
	if srv.has_pending_loot():
		srv.try_loot_close()


func _test_auto_vs_manual(Settings) -> int:
	var failed := 0
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	if srv == null:
		return _expect(false, "MockServer present")
	if srv.combat_stats == null and srv.has_method("_ensure_combat_layers"):
		srv._ensure_combat_layers()
	_reset_loot(srv)
	if srv.inventory != null:
		srv.inventory.clear()
	srv.set_player_cell(8, 8)

	var seed_items: Array = [
		{"item_id": "wooden_sword", "qty": 1},
		{"item_id": "potion_hp_small", "qty": 2},
		{"item_id": "rusty_coin", "qty": 5},
		{"item_id": "slime_jelly", "qty": 3},
	]
	srv._add_items_to_ground({"x": 8, "y": 8}, seed_items, "monster", "test_npc")
	failed += _expect(srv.ground_bag_count() >= 1, "seeded bag")
	var bag_id: String = srv.find_ground_bag_at(8, 8)
	failed += _expect(not bag_id.is_empty(), "bag at cell")
	var open_r: Dictionary = srv.try_open_ground_bag(bag_id)
	failed += _expect(bool(open_r.get("ok", false)), "open bag")

	_simulate_filtered_auto_take(srv, Settings, "consumable_gold")

	failed += _expect(srv.inventory.get_qty("potion_hp_small") >= 2, "auto took potion")
	failed += _expect(srv.inventory.get_qty("rusty_coin") >= 5, "auto took gold")
	failed += _expect(srv.inventory.get_qty("wooden_sword") == 0, "auto skipped equip")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == 0, "auto skipped material")
	failed += _expect(srv.ground_bag_count() >= 1, "leftovers stay on ground")
	failed += _expect(not srv.has_pending_loot(), "loot UI closed after filter")

	# Manual take-all still takes anything remaining
	bag_id = str(srv.find_ground_bag_at(8, 8))
	open_r = srv.try_open_ground_bag(bag_id)
	failed += _expect(bool(open_r.get("ok", false)), "reopen for manual")
	var take_all: Dictionary = srv.try_loot_take_all()
	failed += _expect(bool(take_all.get("ok", false)), "manual take_all ok")
	failed += _expect(srv.inventory.get_qty("wooden_sword") >= 1, "manual took equip")
	failed += _expect(srv.inventory.get_qty("slime_jelly") >= 3, "manual took material")

	# no_equip: leave only equipment
	_reset_loot(srv)
	srv.inventory.clear()
	srv.set_player_cell(9, 9)
	srv._add_items_to_ground({"x": 9, "y": 9}, [
		{"item_id": "wooden_sword", "qty": 1},
		{"item_id": "potion_hp_small", "qty": 1},
		{"item_id": "slime_jelly", "qty": 1},
	], "monster", "test_npc2")
	bag_id = str(srv.find_ground_bag_at(9, 9))
	srv.try_open_ground_bag(bag_id)
	_simulate_filtered_auto_take(srv, Settings, "no_equip")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") >= 1, "no_equip took potion")
	failed += _expect(srv.inventory.get_qty("slime_jelly") >= 1, "no_equip took material")
	failed += _expect(srv.inventory.get_qty("wooden_sword") == 0, "no_equip left sword")
	failed += _expect(srv.ground_bag_count() >= 1, "equip remains in bag")

	# UI labels
	failed += _expect(Settings.AUTO_PICKUP_FILTERS.size() == 3, "3 filter labels")
	failed += _expect(str(Settings.AUTO_PICKUP_FILTERS[0][0]) == "全部", "label 全部")
	failed += _expect(str(Settings.AUTO_PICKUP_FILTERS[1][0]) == "不拾取装备", "label 不拾取装备")
	failed += _expect(str(Settings.AUTO_PICKUP_FILTERS[2][0]) == "金币与消耗品", "label 金币与消耗品")

	return failed


func _reset_loot(srv) -> void:
	if srv.has_method("try_loot_close"):
		srv.try_loot_close()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""


func _expect(cond: bool, msg: String) -> int:
	if cond:
		print("  OK ", msg)
		return 0
	print("  FAIL ", msg)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_loot_filter: PASS")
		quit(0)
	else:
		print("test_loot_filter: FAIL count=", failed)
		quit(1)
