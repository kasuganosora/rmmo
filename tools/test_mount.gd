extends SceneTree
## Headless: mount「骑乘」toggle — move_speed_mul buff; block in combat; dismount on damage.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_mount: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.skill_catalog == null or srv.combat_engine == null or srv.combat_stats == null:
		print("test_mount: FAIL combat layers missing")
		quit(1)
		return

	var skills = srv.skill_catalog
	var stats = srv.combat_stats
	var engine = srv.combat_engine

	# --- Catalog ---
	failed += _expect(skills.has_skill("mount"), "catalog has mount")
	var def: Dictionary = skills.get_skill("mount")
	failed += _expect(str(def.get("name", "")) == "骑乘", "Chinese name 骑乘")
	failed += _expect(str(def.get("effect", "")) == "mount", "effect mount")
	failed += _expect(int(def.get("mp_cost", -1)) == 0, "mp_cost 0")
	failed += _expect(float(def.get("cooldown", 0.0)) > 0.0, "cooldown > 0")
	failed += _expect(int(def.get("range", -1)) == 0, "range 0 self")
	failed += _expect(not bool(def.get("requires_target", true)), "no target required")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", 0)) >= 1, "sp_cost learnable")
	var st: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st.get("id", "")) == "mounted", "status id mounted")
	failed += _expect(str(st.get("kind", "")) == "buff", "status kind buff")
	failed += _expect(abs(float(st.get("move_speed_mul", 0.0)) - 1.45) < 0.001, "catalog move_speed_mul 1.45")

	failed += _expect(srv.has_method("player_is_mounted"), "MockServer.player_is_mounted")
	failed += _expect(srv.has_method("player_move_speed_mul"), "MockServer.player_move_speed_mul")
	failed += _expect(engine.has_method("player_is_mounted"), "engine.player_is_mounted")
	failed += _expect(engine.has_method("break_mount"), "engine.break_mount")
	failed += _expect(engine.has_method("player_in_combat"), "engine.player_in_combat")

	srv.awaiting_respawn = false
	srv.sitting = false
	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)

	# --- Learn ---
	failed += _expect(not stats.skill_book.is_known("mount"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("mount", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("mount"), "known after learn")

	# --- Mount out of combat: buff + speed ---
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.player["hp"] = 100
	stats.player["hp_max"] = 100
	if engine.has_method("reset_dps_fight"):
		engine.reset_dps_fight()
	failed += _expect(not srv.player_is_mounted(), "baseline not mounted")
	failed += _expect(is_equal_approx(float(srv.player_move_speed_mul()), 1.0), "baseline mul 1.0")
	failed += _expect(not engine.player_in_combat(), "baseline not in combat")

	var r_on: Dictionary = srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(bool(r_on.get("ok", false)), "mount cast ok")
	failed += _expect(stats.statuses.has_status("player", "mounted"), "mounted status applied")
	failed += _expect(srv.player_is_mounted(), "player_is_mounted true")
	failed += _expect(engine.player_is_mounted(), "engine mounted")
	failed += _expect(abs(float(srv.player_move_speed_mul()) - 1.45) < 0.001, "move_speed_mul 1.45")
	failed += _expect(_has_msg(r_on, "已骑乘。"), "msg 已骑乘。")
	failed += _expect(_has_type(r_on.get("actions", []), "status_update"), "status_update on mount")
	var inst: Dictionary = _find_status(stats, "mounted")
	failed += _expect(abs(float(inst.get("move_speed_mul", 0.0)) - 1.45) < 0.001, "inst move_speed_mul 1.45")

	# try_mount alias
	stats.skill_ready_at.clear()
	var r_off: Dictionary = srv.try_mount() if srv.has_method("try_mount") else srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(bool(r_off.get("ok", false)), "dismount toggle ok")
	failed += _expect(not srv.player_is_mounted(), "dismounted")
	failed += _expect(is_equal_approx(float(srv.player_move_speed_mul()), 1.0), "mul back to 1.0")
	failed += _expect(_has_msg(r_off, "已下马。"), "msg 已下马。")

	# Remount for combat / damage tests
	stats.skill_ready_at.clear()
	var r_on2: Dictionary = srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(bool(r_on2.get("ok", false)) and srv.player_is_mounted(), "remounted")

	# --- Block mount in combat ---
	stats.skill_ready_at.clear()
	# Force DPS fight active as combat gate
	engine._dps_fight["active"] = true
	engine._dps_fight["fight_start"] = 0.0
	engine._dps_fight["last_hit_time"] = 0.0
	# Dismount first so we attempt mount while "in combat"
	engine.break_mount([])
	failed += _expect(not srv.player_is_mounted(), "cleared for combat-block test")
	failed += _expect(engine.player_in_combat(), "in combat via dps")
	var r_block: Dictionary = srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(not bool(r_block.get("ok", false)), "mount blocked in combat")
	failed += _expect(_has_msg(r_block, "战斗中无法骑乘。"), "msg 战斗中无法骑乘。")
	failed += _expect(not srv.player_is_mounted(), "still not mounted")
	engine.reset_dps_fight()

	# --- Dismount on damage ---
	stats.skill_ready_at.clear()
	stats.player["hp"] = 100
	stats.player["mp"] = 50
	var r_on3: Dictionary = srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(bool(r_on3.get("ok", false)) and srv.player_is_mounted(), "mounted before damage")
	var dmg_acts: Array = []
	# roll_accuracy=false so hit always lands
	engine._damage_player(5, dmg_acts, "dummy", false)
	failed += _expect(not srv.player_is_mounted(), "damage cleared mount")
	failed += _expect(_has_msg({"actions": dmg_acts}, "已下马。"), "damage msg 已下马。")
	failed += _expect(is_equal_approx(float(srv.player_move_speed_mul()), 1.0), "mul 1.0 after damage")

	# --- Dismount on auto-attack ---
	stats.skill_ready_at.clear()
	stats.player["hp"] = 100
	stats.attack_ready_at = 0.0
	var r_on4: Dictionary = srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(srv.player_is_mounted(), "mounted before attack")
	stats.ensure_npc("dummy_m", true, true)
	stats.ensure_npc_ai("dummy_m", 2, true, Vector2i(1, 0), 0)
	stats.set_npc_cell("dummy_m", 1, 0)
	stats.attack_ready_at = 0.0
	var atk: Dictionary = engine.try_attack("dummy_m", 0, 0)
	failed += _expect(bool(atk.get("ok", false)), "attack ok")
	failed += _expect(not srv.player_is_mounted(), "attack cleared mount")
	failed += _expect(_has_msg(atk, "已下马。"), "attack msg 已下马。")

	# --- Dead cannot mount ---
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()
	stats.player["hp"] = 0
	var r_dead: Dictionary = srv.try_use_skill("mount", "", 0, 0)
	failed += _expect(not bool(r_dead.get("ok", false)), "dead cannot mount")
	failed += _expect(not srv.player_is_mounted(), "dead not mounted")
	failed += _expect(_has_msg(r_dead, "你已经倒下了。"), "dead mount msg 你已经倒下了。")
	stats.player["hp"] = 100

	if failed == 0:
		print("test_mount: PASS")
		quit(0)
	else:
		print("test_mount: FAIL count=%d" % failed)
		quit(1)


func _find_status(stats, sid: String) -> Dictionary:
	if stats == null or stats.statuses == null:
		return {}
	if stats.statuses.has_method("get_status"):
		var g: Dictionary = stats.statuses.get_status("player", sid)
		if not g.is_empty():
			return g
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == sid:
			return s
	return {}


func _has_msg(result: Dictionary, text: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "system_message" and str(a.get("text", "")) == text:
			return true
	return false


func _has_type(actions: Array, typ: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
