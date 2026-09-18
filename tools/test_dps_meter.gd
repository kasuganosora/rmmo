extends SceneTree
## Headless: personal DPS meter — hit accumulates, idle timeout ends fight, util math.


const DpsUtil = preload("res://scripts/ui/dps_meter_util.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_util_math()
	failed += _test_damage_and_timeout()
	failed += await _test_hud_apply()

	if failed == 0:
		print("test_dps_meter: PASS")
		quit(0)
	else:
		print("test_dps_meter: FAIL count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL: ", label)
	return 1


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _find_type(actions: Array, t: String) -> Dictionary:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return a
	return {}


func _test_util_math() -> int:
	var failed := 0
	failed += _expect(is_equal_approx(DpsUtil.calc_dps(100, 0.0), 100.0), "calc floor elapsed 1")
	failed += _expect(is_equal_approx(DpsUtil.calc_dps(100, 0.5), 100.0), "calc floor elapsed <1")
	failed += _expect(is_equal_approx(DpsUtil.calc_dps(100, 2.0), 50.0), "calc 100/2=50")
	failed += _expect(DpsUtil.format_label(123.4) == "DPS 123", "format round")
	failed += _expect(DpsUtil.format_label(123.6) == "DPS 124", "format round up")
	var n: Dictionary = DpsUtil.normalize({"dps": 10.5, "total": 42, "elapsed": 4.0, "active": true})
	failed += _expect(bool(n.get("active", false)) and int(n.get("total", 0)) == 42, "normalize")
	failed += _expect(DpsUtil.should_show(true, true, false), "show when active")
	failed += _expect(not DpsUtil.should_show(true, false, false), "hide when idle")
	failed += _expect(not DpsUtil.should_show(false, true, false), "hide when setting off")
	failed += _expect(is_equal_approx(DpsUtil.IDLE_TIMEOUT_SEC, 6.0), "idle timeout 6s")
	return failed


func _test_damage_and_timeout() -> int:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_dps_meter: FAIL no MockServer")
		return 1
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.combat_engine != null, "combat_engine ready")
	failed += _expect(srv.combat_engine.has_method("note_dps_hit"), "has note_dps_hit")
	failed += _expect(srv.combat_engine.has_method("tick_dps"), "has tick_dps")
	failed += _expect(srv.has_method("snapshot_dps"), "has snapshot_dps")

	var eng = srv.combat_engine
	eng.reset_dps_fight()
	eng._dps_clock = 0.0

	# Unit: direct note
	var a1: Dictionary = eng.note_dps_hit(50)
	failed += _expect(str(a1.get("type", "")) == "dps_update", "hit emits dps_update")
	failed += _expect(bool(a1.get("active", false)), "hit active true")
	failed += _expect(int(a1.get("total", 0)) == 50, "total 50")
	failed += _expect(float(a1.get("dps", 0.0)) >= 50.0 - 0.01, "dps >=50 (elapsed floor 1)")

	eng._dps_clock = 2.0
	var a2: Dictionary = eng.note_dps_hit(50)
	failed += _expect(int(a2.get("total", 0)) == 100, "total 100 after 2nd")
	failed += _expect(is_equal_approx(float(a2.get("elapsed", 0.0)), 2.0), "elapsed 2")
	failed += _expect(is_equal_approx(float(a2.get("dps", 0.0)), 50.0), "dps 50")

	# Via try_attack
	var stats = srv.combat_stats
	stats.reset_player(5)
	stats.ensure_npc("dps_mob", true, true)
	stats.set_npc_cell("dps_mob", 8, 8)
	stats.npcs["dps_mob"]["hp"] = 500
	stats.npcs["dps_mob"]["hp_max"] = 500
	stats.npcs["dps_mob"]["def"] = 0
	srv.set_player_cell(8, 8)
	eng.reset_dps_fight()
	eng._dps_clock = 10.0
	srv.combat_randf = func() -> float: return 0.01
	if stats.has_method("set_attack_cooldown"):
		stats.set_attack_cooldown(0.0)
	var atk: Dictionary = srv.try_attack("dps_mob", 8, 8)
	failed += _expect(bool(atk.get("ok", false)), "try_attack ok")
	var dps_act: Dictionary = _find_type(atk.get("actions", []), "dps_update")
	failed += _expect(not dps_act.is_empty(), "attack actions include dps_update")
	failed += _expect(bool(dps_act.get("active", false)), "attack dps active")
	failed += _expect(int(dps_act.get("total", 0)) > 0, "attack total > 0")
	var snap: Dictionary = srv.snapshot_dps()
	failed += _expect(bool(snap.get("active", false)), "snapshot active")
	failed += _expect(int(snap.get("total", 0)) > 0, "snapshot total > 0")

	# Timeout: force idle past 6s
	var last_total: int = int(snap.get("total", 0))
	eng._dps_fight["active"] = true
	eng._dps_fight["last_hit_time"] = eng._dps_clock - 6.1
	var end_acts: Array = eng.tick_dps(0.0)
	failed += _expect(not end_acts.is_empty(), "timeout emits dps_update")
	var end_act: Dictionary = end_acts[0] if not end_acts.is_empty() else {}
	failed += _expect(not bool(end_act.get("active", true)), "timeout active false")
	failed += _expect(int(end_act.get("total", -1)) == last_total, "timeout keeps total")
	failed += _expect(not bool(eng._dps_fight.get("active", true)), "fight inactive")
	var snap2: Dictionary = srv.snapshot_dps()
	failed += _expect(not bool(snap2.get("active", true)), "snapshot inactive after end")

	# MockServer _tick_dps_meter path
	eng.reset_dps_fight()
	eng._dps_clock = 0.0
	eng.note_dps_hit(30)
	srv._pending_tick_actions.clear()
	for _i in range(61):
		srv._tick_dps_meter(0.1)
	failed += _expect(_has_type(srv._pending_tick_actions, "dps_update"), "server tick emits end")
	var pend: Dictionary = _find_type(srv._pending_tick_actions, "dps_update")
	failed += _expect(not bool(pend.get("active", true)), "server end active false")
	return failed


func _test_hud_apply() -> int:
	var failed := 0
	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	failed += _expect(packed != null, "game_hud.tscn loads")
	if packed == null:
		# Fallback: script-only
		var HudScript = load("res://scripts/ui/game_hud.gd")
		failed += _expect(HudScript != null, "game_hud script loads")
		if HudScript == null:
			return failed
		var hud_fb = HudScript.new()
		root.add_child(hud_fb)
		await process_frame
		failed += _expect(hud_fb.has_method("apply_dps_update"), "apply_dps_update API")
		hud_fb.apply_dps_update({"dps": 77.2, "total": 200, "elapsed": 2.5, "active": true})
		failed += _expect(hud_fb._dps_meter_active, "hud active flag")
		hud_fb.queue_free()
		await process_frame
		return failed

	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	failed += _expect(hud.has_method("apply_dps_update"), "apply_dps_update API")
	failed += _expect(hud.has_method("_build_dps_meter"), "_build_dps_meter API")
	hud.apply_dps_update({"dps": 77.2, "total": 200, "elapsed": 2.5, "active": true})
	await process_frame
	failed += _expect(bool(hud.get("_dps_meter_active")), "hud active flag")
	var lab: Label = hud.get("_dps_meter_label") as Label
	failed += _expect(lab != null, "label created")
	if lab != null:
		failed += _expect(str(lab.text).begins_with("DPS"), "label DPS prefix")
		failed += _expect(str(lab.text).find("77") >= 0 or str(lab.text).find("78") >= 0, "label shows dps")
	var panel = hud.get("_dps_meter_panel")
	failed += _expect(panel != null and bool(panel.visible), "panel visible when active")
	hud.apply_dps_update({"dps": 77.2, "total": 200, "elapsed": 2.5, "active": false})
	await process_frame
	failed += _expect(not bool(hud.get("_dps_meter_active")), "hud inactive")
	failed += _expect(panel == null or not bool(panel.visible), "hidden when idle")
	var gs = load("res://scripts/game/game_settings.gd").get_i()
	failed += _expect(gs != null and bool(gs.show_dps_meter), "show_dps_meter default ON")
	hud.queue_free()
	await process_frame
	return failed
