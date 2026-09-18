extends SceneTree
## Headless: MockServer pet summon / follow step / dismiss / double-summon fail.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_pet: FAIL no MockServer")
		quit(1)
		return
	if srv.get("combat_stats") == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_pet_summon"), "has try_pet_summon")
	failed += _expect(srv.has_method("try_pet_dismiss"), "has try_pet_dismiss")
	failed += _expect(srv.has_method("snapshot_pet"), "has snapshot_pet")
	failed += _expect(srv.has_method("_tick_pet_follow"), "has _tick_pet_follow")

	# Clean slate
	if srv.has_method("_pet_reset"):
		srv._pet_reset()
	srv.player_cell = Vector2i(10, 10)

	var snap0: Dictionary = srv.snapshot_pet()
	failed += _expect(not bool(snap0.get("active", true)), "starts inactive")

	# Summon
	var r1: Dictionary = srv.try_pet_summon("default")
	failed += _expect(bool(r1.get("ok", false)), "summon ok")
	failed += _expect(_has(r1, "pet_spawn"), "summon pet_spawn")
	failed += _expect(_msg_has(r1, "召唤"), "summon msg")
	var snap1: Dictionary = srv.snapshot_pet()
	failed += _expect(bool(snap1.get("active", false)), "active after summon")
	failed += _expect(str(snap1.get("id", "")) == "default", "id default")
	failed += _expect(str(snap1.get("name", "")).strip_edges() != "", "name set")
	var cell0: Dictionary = snap1.get("cell", {})
	failed += _expect(typeof(cell0) == TYPE_DICTIONARY, "cell dict")
	var p0 := Vector2i(int(cell0.get("x", 0)), int(cell0.get("y", 0)))
	var dist0: int = maxi(absi(p0.x - 10), absi(p0.y - 10))
	failed += _expect(dist0 >= 1 and dist0 <= 2, "spawn lag 1–2 (got %d)" % dist0)

	# Double summon fails
	var r2: Dictionary = srv.try_pet_summon("default")
	failed += _expect(not bool(r2.get("ok", true)), "double summon fails")
	failed += _expect(str(r2.get("reason", "")) == "already_active", "reason already_active")
	failed += _expect(_msg_has(r2, "已有宠物"), "msg 已有宠物")

	# Follow step: move player far, tick until pet_move
	srv.player_cell = Vector2i(20, 20)
	var moved := false
	var last_cell := p0
	for _i in range(40):
		var acts: Array = srv._tick_pet_follow(1.0)
		for a in acts:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if str(a.get("type", "")) != "pet_move":
				continue
			moved = true
			last_cell = Vector2i(int(a.get("x", 0)), int(a.get("y", 0)))
		if moved:
			break
	failed += _expect(moved, "follow emitted pet_move")
	var dist1: int = maxi(absi(last_cell.x - 20), absi(last_cell.y - 20))
	var dist_before: int = maxi(absi(p0.x - 20), absi(p0.y - 20))
	failed += _expect(dist1 < dist_before, "closer after follow (%d < %d)" % [dist1, dist_before])

	# Dismiss
	var r3: Dictionary = srv.try_pet_dismiss()
	failed += _expect(bool(r3.get("ok", false)), "dismiss ok")
	failed += _expect(_has(r3, "pet_despawn"), "dismiss pet_despawn")
	failed += _expect(_msg_has(r3, "收回"), "dismiss msg")
	var snap2: Dictionary = srv.snapshot_pet()
	failed += _expect(not bool(snap2.get("active", true)), "inactive after dismiss")

	# Dismiss when none
	var r4: Dictionary = srv.try_pet_dismiss()
	failed += _expect(not bool(r4.get("ok", true)), "dismiss empty fails")

	# Item whistle path (grant + use)
	if srv.inventory != null and srv.item_catalog != null:
		if not srv.inventory.has_item("pet_whistle", 1):
			srv.inventory.add_item("pet_whistle", 1)
		failed += _expect(srv.inventory.has_item("pet_whistle", 1), "has pet_whistle")
		var r5: Dictionary = srv.try_use_item("pet_whistle")
		failed += _expect(bool(r5.get("ok", false)), "whistle summon ok")
		failed += _expect(_has(r5, "pet_spawn"), "whistle pet_spawn")
		failed += _expect(bool(srv.snapshot_pet().get("active", false)), "active via whistle")
		# Whistle does not consume
		failed += _expect(srv.inventory.has_item("pet_whistle", 1), "whistle not consumed")
		srv.try_pet_dismiss()
	else:
		print("  SKIP whistle (no inventory/catalog)")

	if failed == 0:
		print("test_pet: PASS")
		quit(0)
		return
	print("test_pet: FAIL count=%d" % failed)
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
