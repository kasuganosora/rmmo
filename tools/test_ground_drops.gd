extends SceneTree
## Headless: ground bags — kill creates bag; drop_item creates bag; take_all empties/despawns; close keeps bag.

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
	srv.combat_stats.clear_npcs()
	srv.npc_spawn_templates.clear()
	_reset(srv)
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = func() -> float: return 0.0
	srv.npc_spawn_templates["street_slime"] = {
		"id": "street_slime",
		"charset": "retira_slime",
		"hostile": true,
		"home_cell": {"x": 8, "y": 8},
	}
	srv.set_player_cell(8, 8)

	failed += _test_kill_creates_bag(srv)
	failed += _test_drop_item_creates_bag(srv)
	failed += _test_merge_same_cell(srv)
	failed += _test_take_all_despawns(srv)
	failed += _test_close_keeps(srv)
	failed += _test_snapshot(srv)

	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = Callable()

	if failed == 0:
		print("test_ground_drops: PASS")
		quit(0)
	else:
		print("test_ground_drops: FAIL count=", failed)
		quit(1)


func _reset(srv) -> void:
	if srv.has_method("try_loot_close"):
		srv.try_loot_close()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
		srv.inventory.max_slots = 40


func _test_kill_creates_bag(srv) -> int:
	var failed := 0
	_reset(srv)
	# home_cell in template is 8,8; death cell differs so loot must NOT use home.
	srv.set_player_cell(1, 1)
	var death := {"x": 3, "y": 5}
	var acts: Array = srv._roll_and_grant_loot("street_slime", death)
	var spawn := false
	var loot_cell := {}
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t in ["ground_spawn", "ground_update"]:
			spawn = true
			var bag_v: Variant = a.get("bag", {})
			if typeof(bag_v) == TYPE_DICTIONARY:
				var cv: Variant = bag_v.get("cell", null)
				if typeof(cv) == TYPE_DICTIONARY:
					loot_cell = cv
	failed += _expect(spawn, "kill emits ground_spawn/update")
	failed += _expect(srv.ground_bag_count() == 1, "one bag after kill")
	var bid: String = srv.find_ground_bag_at(3, 5)
	failed += _expect(bid != "", "bag at death cell")
	failed += _expect(srv.find_ground_bag_at(8, 8) == "", "bag not at home_cell")
	failed += _expect(not loot_cell.is_empty(), "action bag has cell")
	if not loot_cell.is_empty():
		failed += _expect(int(loot_cell.get("x", -1)) == 3 and int(loot_cell.get("y", -1)) == 5, "loot cell equals death cell")
		failed += _expect(not (int(loot_cell.get("x", -1)) == 8 and int(loot_cell.get("y", -1)) == 8), "loot cell not home_cell")
	var snap: Dictionary = srv.get_ground_bag(bid) if bid != "" else {}
	failed += _expect(str(snap.get("source", "")) == "monster", "source monster")
	failed += _expect(not (snap.get("items", []) as Array).is_empty(), "bag has items")
	return failed


func _test_drop_item_creates_bag(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.set_player_cell(3, 4)
	srv.inventory.add_item("potion_hp_small", 2)
	var before: int = srv.inventory.get_qty("potion_hp_small")
	var r: Dictionary = srv.try_drop_item("potion_hp_small", 1)
	failed += _expect(bool(r.get("ok", false)), "drop ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == before - 1, "inv qty -1")
	failed += _expect(srv.ground_bag_count() == 1, "bag after drop")
	var bid: String = srv.find_ground_bag_at(3, 4)
	failed += _expect(bid != "", "bag at player cell")
	var got_inv := false
	var got_msg := false
	var got_spawn := false
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "inventory_update":
			got_inv = true
		if t == "system_message" and "扔下了" in str(a.get("text", "")):
			got_msg = true
		if t in ["ground_spawn", "ground_update"]:
			got_spawn = true
	failed += _expect(got_inv, "drop inventory_update")
	failed += _expect(got_msg, "扔下了 message")
	failed += _expect(got_spawn, "drop ground_spawn/update")
	var snap: Dictionary = srv.get_ground_bag(bid)
	failed += _expect(str(snap.get("source", "")) == "player", "source player")
	return failed


func _test_merge_same_cell(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.set_player_cell(2, 2)
	srv.inventory.add_item("potion_hp_small", 3)
	srv.try_drop_item("potion_hp_small", 1)
	srv.try_drop_item("potion_mp_small", 1)
	failed += _expect(srv.ground_bag_count() == 1, "same cell merges to one bag")
	var bid: String = srv.find_ground_bag_at(2, 2)
	var items: Array = srv.get_ground_bag(bid).get("items", [])
	failed += _expect(items.size() >= 2, "merged bag has both items")
	return failed


func _test_take_all_despawns(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.set_player_cell(8, 8)
	srv._roll_and_grant_loot("street_slime")
	var bid: String = srv.find_ground_bag_at(8, 8)
	var open_r: Dictionary = srv.try_open_ground_bag(bid)
	failed += _expect(bool(open_r.get("ok", false)), "open ok")
	var r: Dictionary = srv.try_loot_take_all()
	failed += _expect(bool(r.get("ok", false)), "take_all ok")
	failed += _expect(srv.ground_bag_count() == 0, "empty bag despawned")
	var despawn := false
	for a in r.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "ground_despawn":
			despawn = true
	failed += _expect(despawn, "ground_despawn action")
	failed += _expect(not srv.has_pending_loot(), "UI closed after empty")
	return failed


func _test_close_keeps(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.set_player_cell(8, 8)
	srv._roll_and_grant_loot("street_slime")
	var bid: String = srv.find_ground_bag_at(8, 8)
	srv.try_open_ground_bag(bid)
	srv.try_loot_close()
	failed += _expect(srv.ground_bag_count() == 1, "close keeps bag")
	failed += _expect(not srv.has_pending_loot(), "UI closed")
	# Re-open and take one
	srv.try_open_ground_bag(bid)
	failed += _expect(srv.has_pending_loot(), "re-open works")
	return failed


func _test_snapshot(srv) -> int:
	var failed := 0
	_reset(srv)
	srv.set_player_cell(1, 1)
	srv.inventory.add_item("rusty_coin", 1)
	srv.try_drop_item("rusty_coin", 1)
	var snap: Array = srv.snapshot_ground_bags()
	failed += _expect(snap.size() == 1, "snapshot size 1")
	if snap.size() > 0 and typeof(snap[0]) == TYPE_DICTIONARY:
		var b: Dictionary = snap[0]
		failed += _expect(str(b.get("id", "")) != "", "snapshot id")
		failed += _expect(typeof(b.get("cell", null)) == TYPE_DICTIONARY, "snapshot cell")
		failed += _expect(typeof(b.get("items", null)) == TYPE_ARRAY, "snapshot items")
	else:
		failed += _expect(false, "snapshot entry dict")
	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
