extends SceneTree
## Headless: pet combat assist damage + pet_assist gate.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_pet_assist: FAIL no MockServer")
		quit(1)
		return
	if srv.get("combat_stats") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("_tick_pet_combat"), "has _tick_pet_combat")
	failed += _expect(srv.has_method("try_set_pet_assist"), "has try_set_pet_assist")
	failed += _expect(srv.has_method("try_set_combat_target"), "has try_set_combat_target")
	failed += _expect(srv.has_method("_pet_atk"), "has _pet_atk")

	var stats = srv.combat_stats
	failed += _expect(stats != null, "combat_stats")
	if stats == null:
		_finish(failed)
		return

	if srv.has_method("_pet_reset"):
		srv._pet_reset()
	srv.awaiting_respawn = false
	srv.try_set_pet_assist(true)
	failed += _expect(bool(srv.pet_assist), "pet_assist default/on")

	srv.player_cell = Vector2i(10, 10)
	if stats.has_method("reset_player"):
		stats.reset_player(5)
	else:
		stats.player["level"] = 5
	var atk_expect: int = 3 + 5
	failed += _expect(int(srv._pet_atk()) == atk_expect, "pet_atk 3+level (%d)" % atk_expect)

	var r1: Dictionary = srv.try_pet_summon("default")
	failed += _expect(bool(r1.get("ok", false)), "summon ok")
	var snap: Dictionary = srv.snapshot_pet()
	failed += _expect(bool(snap.get("active", false)), "pet active")
	failed += _expect(int(snap.get("atk", 0)) == atk_expect, "snapshot atk")
	failed += _expect(bool(snap.get("assist", false)), "snapshot assist on")

	# Place pet adjacent to hostile target.
	var pet_cell: Dictionary = snap.get("cell", {})
	var px: int = int(pet_cell.get("x", 10))
	var py: int = int(pet_cell.get("y", 10))
	srv._pet["cell"] = {"x": px, "y": py}

	stats.ensure_npc("pet_tgt", true, true)
	stats.set_npc_cell("pet_tgt", px + 1, py)
	stats.npcs["pet_tgt"]["hp"] = 100
	stats.npcs["pet_tgt"]["hp_max"] = 100
	stats.npcs["pet_tgt"]["def"] = 0
	stats.npcs["pet_tgt"]["hostile"] = true
	if stats.has_method("ensure_npc_ai"):
		stats.ensure_npc_ai("pet_tgt", 2, true, Vector2i(px + 1, py), 0)

	srv.try_set_combat_target("pet_tgt")
	failed += _expect(str(srv._player_combat_target_id) == "pet_tgt", "combat target set")

	srv._pet["combat_acc"] = 0.0
	var hp0: int = int(stats.npcs["pet_tgt"].get("hp", 0))
	var dealt := false
	var acts: Array = []
	for _i in range(8):
		acts = srv._tick_pet_combat(1.0)
		if _has_type(acts, "damage"):
			dealt = true
			break
	failed += _expect(dealt, "pet combat emitted damage")
	var hp1: int = int(stats.npcs["pet_tgt"].get("hp", 0)) if stats.npcs.has("pet_tgt") else 0
	failed += _expect(hp1 < hp0, "HP dropped (%d < %d)" % [hp1, hp0])
	failed += _expect(_msg_has(acts, "宠物攻击了"), "combat log 宠物攻击了")

	# Hate attributed to player
	if stats.has_method("get_hate_list"):
		var hate: Array = stats.get_hate_list("pet_tgt", false)
		var has_player := false
		var you := str(stats.player_actor_id).strip_edges() if "player_actor_id" in stats else "player"
		if you.is_empty():
			you = "player"
		for e in hate:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == you:
				has_player = true
				break
		failed += _expect(has_player, "hate on player")

	# pet_assist off → no damage
	srv.try_set_pet_assist(false)
	failed += _expect(not bool(srv.snapshot_pet().get("assist", true)), "snapshot assist off")
	if stats.npcs.has("pet_tgt"):
		stats.npcs["pet_tgt"]["hp"] = 80
		stats.npcs["pet_tgt"]["hp_max"] = 100
	srv.try_set_combat_target("pet_tgt")
	srv._pet["combat_acc"] = 0.0
	var hp_off0: int = int(stats.npcs["pet_tgt"].get("hp", 0))
	var acts_off: Array = srv._tick_pet_combat(2.0)
	var hp_off1: int = int(stats.npcs["pet_tgt"].get("hp", 0))
	failed += _expect(not _has_type(acts_off, "damage"), "assist off no damage act")
	failed += _expect(hp_off1 == hp_off0, "assist off HP unchanged")

	# Re-enable still works
	srv.try_set_pet_assist(true)
	srv._pet["combat_acc"] = 0.0
	var acts2: Array = srv._tick_pet_combat(2.0)
	failed += _expect(_has_type(acts2, "damage"), "assist on again damages")

	srv.try_pet_dismiss()
	_finish(failed)


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_pet_assist: PASS")
		quit(0)
		return
	print("test_pet_assist: FAIL count=%d" % failed)
	quit(1)


func _has_type(actions: Array, typ: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _msg_has(actions: Array, needle: String) -> bool:
	for a in actions:
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
