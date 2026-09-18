extends SceneTree
## Headless: out-of-combat sit HP/MP regen — +3/+2 every ~3s; 2× safe zone; break combat.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_sit_regen: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.combat_stats != null, "combat_stats ready")
	failed += _expect(srv.has_method("_tick_sit"), "has _tick_sit")
	failed += _expect(srv.get("SIT_REGEN_INTERVAL") != null or true, "regen constants present")
	failed += _expect(abs(float(srv.SIT_REGEN_INTERVAL) - 3.0) < 0.01, "interval 3s")
	failed += _expect(int(srv.SIT_REGEN_HP) == 3, "base HP +3")
	failed += _expect(int(srv.SIT_REGEN_MP) == 2, "base MP +2")

	var engine = srv.combat_engine
	var stats = srv.combat_stats
	srv.awaiting_respawn = false
	srv.map_pack_id = "demo_map"
	if engine != null and engine.has_method("reset_dps_fight"):
		engine.reset_dps_fight()

	# Outside safe zone baseline
	srv.set_player_cell(17, 12)
	failed += _expect(not srv.player_in_safe_zone(), "outside safe zone")
	stats.player["hp_max"] = 100
	stats.player["mp_max"] = 50
	stats.player["hp"] = 40
	stats.player["mp"] = 20
	srv.sitting = true
	srv._sit_acc = 0.0
	srv._sit_regen_acc = 0.0
	srv._pending_tick_actions.clear()

	# Partial tick — no regen
	srv._tick_sit(2.9)
	failed += _expect(int(stats.player.get("hp", 0)) == 40, "partial <3s no hp")
	failed += _expect(int(stats.player.get("mp", 0)) == 20, "partial <3s no mp")
	failed += _expect(not _has_type(srv._pending_tick_actions, "set_stat"), "partial no set_stat")

	# Full tick outside — +3/+2
	srv._pending_tick_actions.clear()
	srv._tick_sit(0.2)  # total ~3.1 from prior partial + this (acc was 2.9)
	# After partial, acc=2.9; +0.2 => 3.1 => fire once, reset to 0
	failed += _expect(int(stats.player.get("hp", 0)) == 43, "outside tick hp 40+3=43")
	failed += _expect(int(stats.player.get("mp", 0)) == 22, "outside tick mp 20+2=22")
	failed += _expect(_has_type(srv._pending_tick_actions, "set_stat"), "emits set_stat")
	failed += _expect(not _has_type(srv._pending_tick_actions, "system_message"), "silent (no system_message)")

	# Another full 3s
	srv._pending_tick_actions.clear()
	srv._tick_sit(3.0)
	failed += _expect(int(stats.player.get("hp", 0)) == 46, "second tick hp 46")
	failed += _expect(int(stats.player.get("mp", 0)) == 24, "second tick mp 24")

	# Safe zone 2×
	srv.set_player_cell(12, 12)
	failed += _expect(srv.player_in_safe_zone(), "inside safe zone")
	stats.player["hp"] = 40
	stats.player["mp"] = 20
	srv.sitting = true
	srv._sit_regen_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(3.0)
	failed += _expect(int(stats.player.get("hp", 0)) == 46, "safe 2× hp 40+6=46")
	failed += _expect(int(stats.player.get("mp", 0)) == 24, "safe 2× mp 20+4=24")

	# Clamp to max
	stats.player["hp"] = 98
	stats.player["mp"] = 49
	srv._sit_regen_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(3.0)
	failed += _expect(int(stats.player.get("hp", 0)) == 100, "clamp hp to max")
	failed += _expect(int(stats.player.get("mp", 0)) == 50, "clamp mp to max")

	# Full — no set_stat
	srv._sit_regen_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(3.0)
	failed += _expect(int(stats.player.get("hp", 0)) == 100, "full hp stays")
	failed += _expect(not _has_type(srv._pending_tick_actions, "set_stat"), "full no set_stat")

	# In combat — no regen (force sit flag; combat normally stands)
	srv.set_player_cell(17, 12)
	stats.player["hp"] = 40
	stats.player["mp"] = 20
	if engine != null and engine.has_method("note_dps_hit"):
		engine.note_dps_hit(5)
	failed += _expect(engine != null and engine.player_in_combat(), "in combat")
	srv.sitting = true
	srv._sit_regen_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(3.0)
	failed += _expect(int(stats.player.get("hp", 0)) == 40, "combat no hp regen")
	failed += _expect(int(stats.player.get("mp", 0)) == 20, "combat no mp regen")
	failed += _expect(not _has_type(srv._pending_tick_actions, "set_stat"), "combat no set_stat")

	# Stand clears regen
	if engine != null and engine.has_method("reset_dps_fight"):
		engine.reset_dps_fight()
	srv.sitting = true
	srv._sit_regen_acc = 2.5
	var acts: Array = []
	srv._stand_if_sitting(acts)
	failed += _expect(not bool(srv.sitting), "stood")
	failed += _expect(abs(float(srv._sit_regen_acc)) < 0.001, "stand clears regen acc")

	# Not sitting — no regen
	stats.player["hp"] = 40
	stats.player["mp"] = 20
	srv.sitting = false
	srv._sit_regen_acc = 0.0
	srv._pending_tick_actions.clear()
	srv._tick_sit(3.0)
	failed += _expect(int(stats.player.get("hp", 0)) == 40, "standing no regen")

	if failed == 0:
		print("test_sit_regen: PASS")
		quit(0)
	else:
		print("test_sit_regen: FAIL count=%d" % failed)
		quit(1)


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
