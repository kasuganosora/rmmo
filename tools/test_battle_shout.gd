extends SceneTree
## Headless: battle_shout「战吼」— self atk_add +3 / 15s; party same-map N>1 → party_buff + share msg.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_battle_shout: FAIL no MockServer")
		quit(1)
		return
	if srv.combat_engine == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.skill_catalog == null or srv.combat_engine == null or srv.combat_stats == null:
		print("test_battle_shout: FAIL combat layers missing")
		quit(1)
		return

	var skills = srv.skill_catalog
	var stats = srv.combat_stats
	var engine = srv.combat_engine

	# --- Catalog ---
	failed += _expect(skills.has_skill("battle_shout"), "catalog has battle_shout")
	var def: Dictionary = skills.get_skill("battle_shout")
	failed += _expect(str(def.get("name", "")) == "战吼", "Chinese name 战吼")
	failed += _expect(str(def.get("category", "")) == "physical", "category physical")
	failed += _expect(str(def.get("effect", "")) == "apply_status", "effect apply_status")
	failed += _expect(int(def.get("mp_cost", 0)) == 10, "mp_cost 10")
	failed += _expect(abs(float(def.get("cooldown", 0.0)) - 20.0) < 0.01, "cooldown 20")
	failed += _expect(int(def.get("range", -1)) == 0, "range 0 self")
	failed += _expect(not bool(def.get("requires_target", true)), "no target required")
	failed += _expect(bool(def.get("party_share", false)), "party_share flag")
	failed += _expect(abs(float(def.get("party_duration", 0.0)) - 15.0) < 0.01, "party_duration 15")
	failed += _expect(not bool(def.get("starter", true)), "learnable not starter")
	failed += _expect(int(def.get("sp_cost", def.get("sp_cost", 0))) >= 1, "sp_cost learnable")
	var st: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st.get("id", "")) == "battle_shout", "status id battle_shout")
	failed += _expect(str(st.get("kind", "")) == "buff", "status kind buff")
	failed += _expect(abs(float(st.get("duration", 0.0)) - 15.0) < 0.01, "status duration 15")
	failed += _expect(abs(float(st.get("atk_add", 0.0)) - 3.0) < 0.001, "status atk_add 3")

	# Fresh party shell
	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("1")

	stats.ensure_skill_book()
	if stats.skill_book.list_known().is_empty():
		stats.skill_book.grant_starters(skills)
	stats.skill_book.grant_skill_points(99)

	# --- Learn ---
	failed += _expect(not stats.skill_book.is_known("battle_shout"), "not known before learn")
	var learn: Dictionary = stats.skill_book.try_learn("battle_shout", skills, 99)
	failed += _expect(bool(learn.get("ok", false)), "learn ok")
	failed += _expect(stats.skill_book.is_known("battle_shout"), "known after learn")

	# --- Solo: buff + msg, no party_buff ---
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	stats.player["mp_max"] = 50
	stats.player["atk"] = 10
	var atk0: int = engine._effective_atk_player()
	failed += _expect(not srv.in_party(), "solo not in party")
	var r_solo: Dictionary = srv.try_use_skill("battle_shout", "", 0, 0)
	failed += _expect(bool(r_solo.get("ok", false)), "solo cast ok")
	failed += _expect(stats.statuses.has_status("player", "battle_shout"), "solo status applied")
	var rem_solo := _status_remaining(stats, "battle_shout")
	failed += _expect(rem_solo > 14.0 and rem_solo <= 15.01, "solo remaining ~15 (got %.2f)" % rem_solo)
	failed += _expect(abs(_status_atk_add(stats, "battle_shout") - 3.0) < 0.001, "solo atk_add 3")
	failed += _expect(engine._effective_atk_player() == atk0 + 3, "solo effective atk +3")
	failed += _expect(int(stats.player.get("mp", 0)) == 40, "solo spent MP 10")
	failed += _expect(_has_msg(r_solo, "战吼响起！"), "solo shout msg")
	failed += _expect(not _has_msg(r_solo, "使用了【战吼】。"), "solo no generic use msg")
	failed += _expect(not _has_type(r_solo.get("actions", []), "party_buff"), "solo no party_buff")
	failed += _expect(not _has_msg(r_solo, "战吼：全队攻击提升！"), "solo no share msg")

	# --- CD gate ---
	var r_cd: Dictionary = srv.try_use_skill("battle_shout", "", 0, 0)
	failed += _expect(not bool(r_cd.get("ok", false)), "cd blocks recast")

	# --- Party alone (N=1): still no share ---
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "party create ok")
	failed += _expect(int(srv._party_online_same_map_count()) == 1, "party alone N=1")
	var r_n1: Dictionary = srv.try_use_skill("battle_shout", "", 0, 0)
	failed += _expect(bool(r_n1.get("ok", false)), "N=1 cast ok")
	failed += _expect(stats.statuses.has_status("player", "battle_shout"), "N=1 status")
	failed += _expect(not _has_type(r_n1.get("actions", []), "party_buff"), "N=1 no party_buff")
	failed += _expect(not _has_msg(r_n1, "战吼：全队攻击提升！"), "N=1 no share msg")
	failed += _expect(_has_msg(r_n1, "战吼响起！"), "N=1 shout msg")

	# --- Party with stub (N=2): party_buff + share ---
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()
	stats.player["mp"] = 50
	var stub: Dictionary = srv._party_make_stub("stub_ally_shout")
	srv._party_members.append(stub)
	failed += _expect(int(srv._party_online_same_map_count()) == 2, "online same-map N=2")
	var r_party: Dictionary = srv.try_use_skill("battle_shout", "", 0, 0)
	failed += _expect(bool(r_party.get("ok", false)), "party cast ok")
	failed += _expect(stats.statuses.has_status("player", "battle_shout"), "party status applied")
	var rem_p := _status_remaining(stats, "battle_shout")
	failed += _expect(rem_p > 14.0 and rem_p <= 15.01, "party remaining ~15 (got %.2f)" % rem_p)
	failed += _expect(_has_type(r_party.get("actions", []), "party_buff"), "party emits party_buff")
	var pb := _first_action(r_party.get("actions", []), "party_buff")
	failed += _expect(str(pb.get("skill_id", "")) == "battle_shout", "party_buff skill_id")
	failed += _expect(str(pb.get("status_id", "")) == "battle_shout", "party_buff status_id")
	failed += _expect(abs(float(pb.get("duration", 0.0)) - 15.0) < 0.01, "party_buff duration 15")
	failed += _expect(_has_msg(r_party, "战吼响起！"), "party shout msg")
	failed += _expect(_has_msg(r_party, "战吼：全队攻击提升！"), "party share msg")
	failed += _expect(engine._effective_atk_player() == atk0 + 3, "party effective atk +3")

	# Cleanup
	if srv.has_method("_party_clear"):
		srv._party_clear()
	stats.statuses.clear_everything()
	stats.skill_ready_at.clear()

	if failed == 0:
		print("test_battle_shout: PASS")
		quit(0)
		return
	print("test_battle_shout: FAIL count=%d" % failed)
	quit(1)


func _status_remaining(stats, status_id: String) -> float:
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			return float(s.get("remaining_sec", 0.0))
	return 0.0


func _status_atk_add(stats, status_id: String) -> float:
	for s in stats.statuses.snapshot_statuses("player"):
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == status_id:
			return float(s.get("atk_add", 0.0))
	return 0.0


func _has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _first_action(actions: Array, t: String) -> Dictionary:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return a
	return {}


func _has_msg(result: Dictionary, text: String) -> bool:
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return false
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")) == text or text in str(a.get("text", "")):
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
