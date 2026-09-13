extends SceneTree
## Headless: ground-bag loot — kill spawns bag (no auto-open); open → take; close keeps bag.

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
	_reset_loot(srv)
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = func() -> float: return 0.0
	srv.npc_spawn_templates["street_slime"] = {
		"id": "street_slime",
		"charset": "retira_slime",
		"hostile": true,
		"home_cell": {"x": 5, "y": 5},
	}
	srv.set_player_cell(5, 5)

	failed += _test_no_auto_grant(srv)
	failed += _test_take_all(srv)
	failed += _test_close_keeps_bag(srv)
	failed += _test_bag_full_leaves_items(srv)

	if srv.loot_catalog != null:
		srv.loot_catalog.rng_roll = Callable()

	if failed == 0:
		print("test_loot_confirm: PASS")
		quit(0)
	else:
		print("test_loot_confirm: FAIL count=", failed)
		quit(1)


func _reset_loot(srv) -> void:
	if srv.has_method("try_loot_close"):
		srv.try_loot_close()
	srv._ground_bags.clear()
	srv._open_loot_bag_id = ""


func _open_only_bag(srv) -> String:
	var ids: Array = srv._ground_bags.keys()
	if ids.is_empty():
		return ""
	var bid := str(ids[0])
	var r: Dictionary = srv.try_open_ground_bag(bid)
	return bid if bool(r.get("ok", false)) else ""


func _test_no_auto_grant(srv) -> int:
	var failed := 0
	_reset_loot(srv)
	srv.inventory.clear()
	srv.inventory.grant_starter()
	var before: int = srv.inventory.get_qty("slime_jelly")
	var acts: Array = srv._roll_and_grant_loot("street_slime")
	var got_spawn := false
	var got_open := false
	var got_msg := false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "ground_spawn" or t == "ground_update":
			got_spawn = true
		if t == "loot_open":
			got_open = true
		if t == "system_message" and "地上出现了掉落物" in str(a.get("text", "")):
			got_msg = true
	failed += _expect(got_spawn, "ground_spawn/update on kill")
	failed += _expect(not got_open, "kill does not auto loot_open")
	failed += _expect(got_msg, "地上出现了掉落物 message")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == before, "kill does not auto-grant")
	failed += _expect(srv.ground_bag_count() > 0, "ground bag created")
	failed += _expect(not srv.has_pending_loot(), "no open UI after roll")
	return failed


func _test_take_all(srv) -> int:
	var failed := 0
	_reset_loot(srv)
	srv.inventory.clear()
	srv.inventory.grant_starter()
	var before: int = srv.inventory.get_qty("slime_jelly")
	srv._roll_and_grant_loot("street_slime")
	var bid: String = _open_only_bag(srv)
	failed += _expect(bid != "", "open bag ok")
	failed += _expect(srv.has_pending_loot(), "pending after open")
	var r: Dictionary = srv.try_loot_take_all()
	failed += _expect(bool(r.get("ok", false)), "take_all ok")
	var got_inv := false
	var got_gain := false
	var got_close := false
	var got_despawn := false
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "inventory_update":
			got_inv = true
		if t == "system_message" and str(a.get("text", "")).begins_with("获得"):
			got_gain = true
		if t == "loot_close":
			got_close = true
		if t == "ground_despawn":
			got_despawn = true
	failed += _expect(got_inv, "take_all inventory_update")
	failed += _expect(got_gain, "take_all 获得 message")
	failed += _expect(got_close, "take_all loot_close")
	failed += _expect(got_despawn, "take_all ground_despawn")
	failed += _expect(srv.inventory.get_qty("slime_jelly") > before, "jelly in bag after take_all")
	failed += _expect(not srv.has_pending_loot(), "no pending after take_all")
	failed += _expect(srv.ground_bag_count() == 0, "bag removed when empty")
	return failed


func _test_close_keeps_bag(srv) -> int:
	var failed := 0
	_reset_loot(srv)
	srv.inventory.clear()
	srv.inventory.grant_starter()
	var before: int = srv.inventory.get_qty("slime_jelly")
	srv._roll_and_grant_loot("street_slime")
	failed += _expect(srv.ground_bag_count() > 0, "bag before close")
	_open_only_bag(srv)
	failed += _expect(srv.has_pending_loot(), "pending before close")
	var r: Dictionary = srv.try_loot_close()
	failed += _expect(bool(r.get("ok", false)), "close ok")
	failed += _expect(not srv.has_pending_loot(), "UI cleared on close")
	failed += _expect(srv.ground_bag_count() > 0, "bag remains after close")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == before, "close does not grant")
	var closed := false
	var kept_msg := false
	for a in r.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "loot_close":
			closed = true
		if str(a.get("type", "")) == "system_message" and "仍在地上" in str(a.get("text", "")):
			kept_msg = true
	failed += _expect(closed, "loot_close action")
	failed += _expect(kept_msg, "close keeps-on-ground message")
	return failed


func _test_bag_full_leaves_items(srv) -> int:
	var failed := 0
	_reset_loot(srv)
	srv.inventory.clear()
	# Fill distinct slots so a new item_id cannot enter.
	srv.inventory.max_slots = 3
	srv.inventory.add_item("potion_hp_small", 1)
	srv.inventory.add_item("potion_mp_small", 1)
	srv.inventory.add_item("rusty_coin", 1)
	failed += _expect(not srv.inventory.can_accept("slime_jelly"), "bag full for jelly")
	srv._roll_and_grant_loot("street_slime")
	failed += _expect(srv.ground_bag_count() > 0, "ground bag despite full inv")
	_open_only_bag(srv)
	failed += _expect(srv.has_pending_loot(), "open loot despite full bag")
	var before: int = srv.inventory.get_qty("slime_jelly")
	var r: Dictionary = srv.try_loot_take("slime_jelly", -1)
	failed += _expect(not bool(r.get("ok", true)), "take fails when bag full")
	failed += _expect(srv.inventory.get_qty("slime_jelly") == before, "no grant when full")
	failed += _expect(srv.has_pending_loot(), "item remains in open bag")
	failed += _expect(srv.ground_bag_count() > 0, "ground bag remains")
	# Restore capacity for other tests / session
	srv.inventory.max_slots = 40
	_reset_loot(srv)
	return failed


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
