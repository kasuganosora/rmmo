extends SceneTree
## Headless: auto HP/MP potion on MockServer tick; settings gate + cooldown + empty bag.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_auto_potion: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.has_method("try_set_auto_potion"), "try_set_auto_potion")
	failed += _expect(srv.has_method("_tick_auto_potion"), "_tick_auto_potion")
	failed += _expect(srv.has_method("_best_auto_potion"), "_best_auto_potion")

	var stats = srv.combat_stats
	failed += _expect(stats != null, "combat_stats")
	if stats == null:
		_finish(failed)
		return
	srv.awaiting_respawn = false
	stats.item_ready_at.clear()

	# --- Enable auto HP; damage below threshold with potions → tick uses potion ---
	srv.try_set_auto_potion(true, 40, false, 30)
	failed += _expect(bool(srv.auto_potion_hp), "auto_potion_hp on")
	failed += _expect(int(srv.auto_potion_hp_pct) == 40, "hp pct 40")
	stats.player["hp_max"] = 100
	stats.player["hp"] = 30  # 30% <= 40
	stats.player["mp_max"] = 50
	stats.player["mp"] = 50
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 3)
	stats.item_ready_at.clear()
	srv._auto_potion_acc = 0.0
	var hp0: int = int(stats.player.get("hp", 0))
	var qty0: int = srv.inventory.get_qty("potion_hp_small")
	srv._tick_auto_potion(0.5)
	var hp1: int = int(stats.player.get("hp", 0))
	var qty1: int = srv.inventory.get_qty("potion_hp_small")
	failed += _expect(hp1 > hp0, "auto HP heal rose")
	failed += _expect(qty1 == qty0 - 1, "auto HP consumed 1")
	failed += _expect(qty1 == 2, "qty 2 left")

	# --- Cooldown: second tick soon after does not double-consume ---
	var hp_cd0: int = int(stats.player.get("hp", 0))
	# Keep below threshold so it would try again if ready.
	stats.player["hp"] = 20
	srv._auto_potion_acc = 0.0
	srv._tick_auto_potion(0.5)
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 2, "CD no second consume")
	failed += _expect(int(stats.player.get("hp", 0)) == 20, "CD hp unchanged")

	# --- Disabled → no auto use ---
	stats.item_ready_at.clear()
	srv.try_set_auto_potion(false, 40, false, 30)
	stats.player["hp"] = 25
	var qty_d0: int = srv.inventory.get_qty("potion_hp_small")
	srv._auto_potion_acc = 0.0
	srv._tick_auto_potion(0.5)
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == qty_d0, "disabled no consume")
	failed += _expect(int(stats.player.get("hp", 0)) == 25, "disabled hp unchanged")

	# --- No potions → no crash, qty 0 ---
	srv.try_set_auto_potion(true, 40, false, 30)
	srv.inventory.clear()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	srv._auto_potion_acc = 0.0
	srv._auto_potion_msg_at_ms = -999999
	srv._pending_tick_actions.clear()
	srv._tick_auto_potion(0.5)
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 0, "empty qty 0")
	failed += _expect(int(stats.player.get("hp", 0)) == 10, "empty no heal")
	# Optional throttle message once (not every tick)
	var msgs := 0
	for a in srv._pending_tick_actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
			msgs += 1
	failed += _expect(msgs <= 1, "empty msg at most 1")
	srv._pending_tick_actions.clear()
	srv._tick_auto_potion(0.5)
	var msgs2 := 0
	for a2 in srv._pending_tick_actions:
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "system_message":
			msgs2 += 1
	failed += _expect(msgs2 == 0, "empty msg throttled")

	# --- Auto MP path ---
	srv.try_set_auto_potion(false, 40, true, 30)
	stats.player["hp"] = 100
	stats.player["mp_max"] = 100
	stats.player["mp"] = 20  # 20% <= 30
	srv.inventory.clear()
	srv.inventory.add_item("potion_mp_small", 2)
	stats.item_ready_at.clear()
	srv._auto_potion_acc = 0.0
	var mp0: int = int(stats.player.get("mp", 0))
	srv._tick_auto_potion(0.5)
	failed += _expect(int(stats.player.get("mp", 0)) > mp0, "auto MP restored")
	failed += _expect(srv.inventory.get_qty("potion_mp_small") == 1, "auto MP consumed")

	# --- try_set clamps pct ---
	srv.try_set_auto_potion(true, 0, true, 99)
	failed += _expect(int(srv.auto_potion_hp_pct) == 1, "hp pct clamp low")
	failed += _expect(int(srv.auto_potion_mp_pct) == 90, "mp pct clamp high")

	# --- GameSettings defaults present ---
	var gs = root.get_node_or_null("GameSettings")
	if gs != null:
		failed += _expect(bool(gs.get("auto_potion_hp")) == false, "gs auto_hp default false")
		failed += _expect(int(gs.get("auto_potion_hp_pct")) == 40, "gs hp pct default 40")
		failed += _expect(bool(gs.get("auto_potion_mp")) == false, "gs auto_mp default false")
		failed += _expect(int(gs.get("auto_potion_mp_pct")) == 30, "gs mp pct default 30")
	else:
		failed += _expect(false, "GameSettings autoload")

	_finish(failed)


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_auto_potion: PASS")
		quit(0)
		return
	print("test_auto_potion: FAIL count=%d" % failed)
	quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	print("  FAIL  %s" % label)
	return 1
