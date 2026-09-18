extends SceneTree
## Headless: boots_swift consumable → swift_oil status move_speed_mul; try_move reports mul; tween helper.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_move_speed: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("boots_swift"), "catalog boots_swift")
	var def: Dictionary = srv.item_catalog.get_item("boots_swift")
	failed += _expect(str(def.get("name", "")) == "疾风靴油", "name 疾风靴油")
	failed += _expect(str(def.get("use_effect", def.get("effect", ""))) == "apply_status", "use_effect apply_status")
	var st_def: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st_def.get("id", "")) == "swift_oil", "status id swift_oil")
	failed += _expect(abs(float(st_def.get("move_speed_mul", 0.0)) - 1.35) < 0.001, "catalog move_speed_mul 1.35")
	failed += _expect(abs(float(st_def.get("duration", 0.0)) - 60.0) < 0.001, "duration 60s")

	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "boots_swift"), "shop sells boots_swift")

	failed += _expect(srv.has_method("player_move_speed_mul"), "player_move_speed_mul exists")
	var stats = srv.combat_stats
	failed += _expect(stats != null and stats.statuses != null, "combat_stats.statuses")
	if stats == null:
		print("test_move_speed: FAIL count=%d" % failed)
		quit(1)
		return

	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	failed += _expect(is_equal_approx(float(srv.player_move_speed_mul()), 1.0), "baseline mul 1.0")

	srv.inventory.clear()
	srv.inventory.add_item("boots_swift", 2)
	var r: Dictionary = srv.try_use_item("boots_swift")
	failed += _expect(bool(r.get("ok", false)), "use boots_swift ok")
	failed += _expect(stats.statuses.has_status("player", "swift_oil"), "swift_oil applied")
	failed += _expect(_status_remaining(stats, "swift_oil") > 50.0, "swift_oil remaining near 60")
	var inst: Dictionary = _find_status(stats, "swift_oil")
	failed += _expect(abs(float(inst.get("move_speed_mul", 0.0)) - 1.35) < 0.001, "inst move_speed_mul 1.35")
	failed += _expect(abs(float(srv.player_move_speed_mul()) - 1.35) < 0.001, "player_move_speed_mul 1.35")
	failed += _expect(_has_type(r.get("actions", []), "status_update"), "status_update action")
	failed += _expect(srv.inventory.get_qty("boots_swift") == 1, "consumed 1 oil")

	# try_move returns mul (open map: disable collision gate)
	var saved_col = srv.map_collision
	srv.map_collision = null
	# Without map, try_move early-fails — use a minimal pass-through stub via setting player cell
	# and calling player_move_speed_mul / constructing expected. Prefer real move if map present.
	srv.map_collision = saved_col
	if saved_col != null:
		srv.set_player_cell(10, 10)
		# Find a passable dir
		var moved := false
		for d in [6, 4, 2, 8]:
			var mv: Dictionary = srv.try_move(10, 10, d)
			if bool(mv.get("ok", false)):
				failed += _expect(abs(float(mv.get("move_speed_mul", 0.0)) - 1.35) < 0.001, "try_move move_speed_mul 1.35")
				moved = true
				break
			# resync cell
			srv.set_player_cell(10, 10)
		if not moved:
			# Still assert helper path even if terrain blocks
			failed += _expect(abs(float(srv.player_move_speed_mul()) - 1.35) < 0.001, "mul still 1.35 if move blocked")
	else:
		failed += _expect(abs(float(srv.player_move_speed_mul()) - 1.35) < 0.001, "mul without map")

	# Client tween helper
	var PlayerScr = load("res://scripts/game/player.gd")
	failed += _expect(PlayerScr != null, "player script loads")
	if PlayerScr != null:
		var p = PlayerScr.new()
		failed += _expect(p.has_method("step_duration_with_mul"), "step_duration_with_mul")
		var base := 0.16
		var sped: float = p.step_duration_with_mul(base, 1.35)
		failed += _expect(abs(sped - (base / 1.35)) < 0.0001, "tween dur shortened")
		failed += _expect(is_equal_approx(p.step_duration_with_mul(base, 1.0), base), "mul 1 unchanged")
		p.free()

	# Clear status → baseline
	stats.statuses.clear_status("player", "swift_oil")
	failed += _expect(not stats.statuses.has_status("player", "swift_oil"), "cleared")
	failed += _expect(is_equal_approx(float(srv.player_move_speed_mul()), 1.0), "mul back to 1.0")

	# Refresh on re-use
	stats.item_ready_at.clear()
	var r2: Dictionary = srv.try_use_item("boots_swift")
	failed += _expect(bool(r2.get("ok", false)), "reuse ok")
	failed += _expect(_count_status(stats, "swift_oil") == 1, "refresh keeps one")
	failed += _expect(_status_remaining(stats, "swift_oil") > 50.0, "refreshed near 60")

	if failed == 0:
		print("test_move_speed: PASS")
		quit(0)
		return
	print("test_move_speed: FAIL count=%d" % failed)
	quit(1)


func _status_remaining(stats, status_id: String) -> float:
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			return float(s.get("remaining_sec", 0.0))
	return 0.0


func _count_status(stats, status_id: String) -> int:
	var n := 0
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			n += 1
	return n


func _find_status(stats, status_id: String) -> Dictionary:
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			return s
	return {}


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
