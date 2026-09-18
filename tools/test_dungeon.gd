extends SceneTree
## Headless: dungeon instance stub — enter street, kill 2 guards, reward, exit demo.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame
	var failed := 0
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	if srv == null:
		print("test_dungeon: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.has_method("_dungeon_force_clear_silent"):
		srv._dungeon_force_clear_silent()
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(3)
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()

	failed += _expect(srv.has_method("try_dungeon_enter"), "has try_dungeon_enter")
	failed += _expect(srv.has_method("try_dungeon_exit"), "has try_dungeon_exit")
	failed += _expect(srv.has_method("snapshot_dungeon"), "has snapshot_dungeon")
	failed += _expect(not srv.in_dungeon(), "idle before enter")

	# Ensure start on demo_map
	if str(srv.map_pack_id) != "demo_map":
		srv.load_world_pack("res://demo_map", "demo_map", Vector2i(15, 12))
	srv.set_player_cell(15, 12)

	var gold0: int = int(srv.inventory.get_gold()) if srv.inventory != null else 0
	var exp0: int = int(srv.combat_stats.player.get("exp", 0))
	var stone0: int = int(srv.inventory.count_item("enhance_stone")) if srv.inventory != null and srv.inventory.has_method("count_item") else _count_item(srv, "enhance_stone")

	# --- Enter → street + active ---
	var ent: Dictionary = srv.try_dungeon_enter()
	failed += _expect(bool(ent.get("ok", false)), "enter ok")
	failed += _expect(srv.in_dungeon(), "enter → active")
	var pack_id := str(srv.map_pack_id)
	var pack_path := str(srv.map_pack_path)
	failed += _expect(
		pack_id.find("street") >= 0 or pack_path.find("street_map") >= 0,
		"on street_map after enter (id=%s path=%s)" % [pack_id, pack_path]
	)
	var snap: Dictionary = srv.snapshot_dungeon()
	failed += _expect(bool(snap.get("active", false)), "snap active")
	failed += _expect(int(snap.get("kills_needed", 0)) == 2, "kills_needed 2")
	failed += _expect(int(snap.get("kills", -1)) == 0, "kills 0")
	failed += _expect(_has(ent, "dungeon_update") or _has(ent, "map_transfer"), "enter actions")
	failed += _expect(srv.combat_stats.npcs.has("dungeon_guard_0"), "guard 0 spawned")
	failed += _expect(srv.combat_stats.npcs.has("dungeon_guard_1"), "guard 1 spawned")

	# --- Kill 2 dungeon mobs → complete + reward ---
	var k1: Dictionary = srv._finalize_combat_result({
		"ok": true,
		"actions": [
			{"type": "kill_npc", "npc_id": "dungeon_guard_0", "cell": {"x": 42, "y": 23}},
			{"type": "system_message", "text": "击败了敌人。"},
		],
	})
	failed += _expect(srv.in_dungeon(), "still active after 1 kill")
	failed += _expect(int(srv.snapshot_dungeon().get("kills", 0)) == 1, "kills 1")
	failed += _expect(_has(k1, "dungeon_update"), "kill1 dungeon_update")

	var k2: Dictionary = srv._finalize_combat_result({
		"ok": true,
		"actions": [
			{"type": "kill_npc", "npc_id": "dungeon_guard_1", "cell": {"x": 40, "y": 23}},
			{"type": "system_message", "text": "击败了敌人。"},
		],
	})
	failed += _expect(not srv.in_dungeon(), "complete clears active")
	failed += _expect(bool(srv.snapshot_dungeon().get("completed", false)), "snap completed")
	failed += _expect(_has_text(k2, "试炼完成"), "complete system message")
	var gold1: int = int(srv.inventory.get_gold()) if srv.inventory != null else 0
	var exp1: int = int(srv.combat_stats.player.get("exp", 0))
	var stone1: int = _count_item(srv, "enhance_stone")
	failed += _expect(gold1 > gold0, "reward gold")
	failed += _expect(exp1 > exp0, "reward exp")
	failed += _expect(stone1 > stone0, "reward enhance_stone")

	# --- Exit back to demo ---
	var ex: Dictionary = srv.try_dungeon_exit()
	failed += _expect(bool(ex.get("ok", false)), "exit ok")
	failed += _expect(not srv.in_dungeon(), "exit idle")
	failed += _expect(not bool(srv.snapshot_dungeon().get("completed", true)), "session cleared")
	var back_id := str(srv.map_pack_id)
	var back_path := str(srv.map_pack_path)
	failed += _expect(
		back_id.find("demo") >= 0 or back_path.find("demo_map") >= 0,
		"back on demo_map (id=%s path=%s)" % [back_id, back_path]
	)

	if failed == 0:
		print("test_dungeon: PASS")
		quit(0)
	else:
		print("test_dungeon: FAIL %d" % failed)
		quit(1)


func _count_item(srv, item_id: String) -> int:
	if srv.inventory == null:
		return 0
	if srv.inventory.has_method("count_item"):
		return int(srv.inventory.count_item(item_id))
	var n := 0
	for row in srv.inventory.snapshot():
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == item_id:
			n += int(row.get("qty", 0))
	return n


func _has(result: Dictionary, action_type: String) -> bool:
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return false
	for a in acts_v:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == action_type:
			return true
	return false


func _has_text(result: Dictionary, needle: String) -> bool:
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return false
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "system_message" and str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
