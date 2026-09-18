extends SceneTree
## Headless: food_party_ration「队伍干粮」— solo well_fed 45s; party same-map N>1 → 90s + party_buff + morale msg.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_party_food: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.item_catalog == null or srv.inventory == null or srv.combat_engine == null or srv.combat_stats == null:
		print("test_party_food: FAIL combat layers missing")
		quit(1)
		return

	# Catalog
	failed += _expect(srv.item_catalog.has_item("food_party_ration"), "catalog has food_party_ration")
	var def: Dictionary = srv.item_catalog.get_item("food_party_ration")
	failed += _expect(str(def.get("name", "")) == "队伍干粮", "Chinese name 队伍干粮")
	failed += _expect(str(def.get("use_effect", def.get("effect", ""))) == "heal_hp", "use_effect heal_hp")
	failed += _expect(int(def.get("amount", 0)) == 20, "heal amount 20")
	failed += _expect(bool(def.get("party_share", false)), "party_share flag")
	failed += _expect(abs(float(def.get("party_duration", 0.0)) - 90.0) < 0.01, "party_duration 90")
	var st: Dictionary = def.get("status", {}) if typeof(def.get("status", {})) == TYPE_DICTIONARY else {}
	failed += _expect(str(st.get("id", "")) == "well_fed", "status well_fed")
	failed += _expect(abs(float(st.get("duration", 0.0)) - 45.0) < 0.01, "solo duration 45")
	failed += _expect(abs(float(st.get("atk_add", 0.0)) - 2.0) < 0.001, "well_fed atk_add 2")

	# Shop stock (optional but expected)
	if srv.shop_catalog != null and srv.shop_catalog.has_method("sells_item"):
		failed += _expect(srv.shop_catalog.sells_item("starter_goods", "food_party_ration"), "shop sells food_party_ration")

	var stats = srv.combat_stats
	srv.awaiting_respawn = false
	srv.sitting = false

	# Fresh party shell
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if stats.has_method("set_player_actor_id"):
		stats.set_player_actor_id("1")

	# --- Solo: heal + well_fed ~45s, no party_buff / morale ---
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	stats.player["hp_max"] = 200
	srv.inventory.clear()
	srv.inventory.add_item("food_party_ration", 3)
	failed += _expect(not srv.in_party(), "solo not in party")
	var r_solo: Dictionary = srv.try_use_item("food_party_ration")
	failed += _expect(bool(r_solo.get("ok", false)), "solo use ok")
	failed += _expect(int(stats.player.get("hp", 0)) == 30, "solo heal 20 (10->30)")
	failed += _expect(stats.statuses.has_status("player", "well_fed"), "solo well_fed applied")
	var rem_solo := _status_remaining(stats, "well_fed")
	failed += _expect(rem_solo > 40.0 and rem_solo <= 45.01, "solo remaining ~45 (got %.2f)" % rem_solo)
	failed += _expect(not _has_type(r_solo.get("actions", []), "party_buff"), "solo no party_buff")
	failed += _expect(not _has_msg(r_solo, "队伍干粮：全员士气提升。"), "solo no morale msg")
	failed += _expect(_has_msg(r_solo, "使用了【队伍干粮】。"), "solo use msg")
	failed += _expect(srv.inventory.get_qty("food_party_ration") == 2, "solo consumed 1")

	# Party alone (N=1): still no share
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	var cr: Dictionary = srv.try_party_create()
	failed += _expect(bool(cr.get("ok", false)), "party create ok")
	failed += _expect(int(srv._party_online_same_map_count()) == 1, "party alone N=1")
	var r_n1: Dictionary = srv.try_use_item("food_party_ration")
	failed += _expect(bool(r_n1.get("ok", false)), "N=1 use ok")
	var rem_n1 := _status_remaining(stats, "well_fed")
	failed += _expect(rem_n1 > 40.0 and rem_n1 <= 45.01, "N=1 remaining ~45 (got %.2f)" % rem_n1)
	failed += _expect(not _has_type(r_n1.get("actions", []), "party_buff"), "N=1 no party_buff")
	failed += _expect(not _has_msg(r_n1, "队伍干粮：全员士气提升。"), "N=1 no morale msg")

	# Party with stub (N=2): duration 90 + party_buff + morale
	stats.statuses.clear_everything()
	stats.item_ready_at.clear()
	stats.player["hp"] = 10
	var stub: Dictionary = srv._party_make_stub("stub_ally_food")
	srv._party_members.append(stub)
	failed += _expect(int(srv._party_online_same_map_count()) == 2, "online same-map N=2")
	var r_party: Dictionary = srv.try_use_item("food_party_ration")
	failed += _expect(bool(r_party.get("ok", false)), "party use ok")
	failed += _expect(int(stats.player.get("hp", 0)) == 30, "party heal 20")
	failed += _expect(stats.statuses.has_status("player", "well_fed"), "party well_fed applied")
	var rem_p := _status_remaining(stats, "well_fed")
	failed += _expect(rem_p > 85.0 and rem_p <= 90.01, "party remaining ~90 (got %.2f)" % rem_p)
	failed += _expect(_count_status(stats, "well_fed") == 1, "one well_fed instance")
	failed += _expect(_has_type(r_party.get("actions", []), "party_buff"), "party emits party_buff")
	var pb := _first_action(r_party.get("actions", []), "party_buff")
	failed += _expect(str(pb.get("item_id", "")) == "food_party_ration", "party_buff item_id")
	failed += _expect(str(pb.get("status_id", "")) == "well_fed", "party_buff status_id")
	failed += _expect(abs(float(pb.get("duration", 0.0)) - 90.0) < 0.01, "party_buff duration 90")
	failed += _expect(_has_msg(r_party, "队伍干粮：全员士气提升。"), "party morale msg")
	failed += _expect(srv.inventory.get_qty("food_party_ration") == 0, "all 3 consumed")

	# Cleanup
	if srv.has_method("_party_clear"):
		srv._party_clear()

	if failed == 0:
		print("test_party_food: PASS")
		quit(0)
		return
	print("test_party_food: FAIL count=%d" % failed)
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
