extends SceneTree
## Headless: try_inn_rest gold cost, full HP/MP, clear harmful; NPC/event wire.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_inn: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.combat_stats == null:
		print("test_inn: FAIL combat layers missing")
		quit(1)
		return

	failed += _expect(srv.has_method("try_inn_rest"), "has try_inn_rest")

	srv.awaiting_respawn = false
	srv.sitting = false
	if srv.combat_stats.statuses != null:
		srv.combat_stats.statuses.clear_all("player")

	# --- already full ---
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	var p: Dictionary = srv.combat_stats.player
	var hp_max: int = int(p.get("hp_max", 100))
	var mp_max: int = int(p.get("mp_max", 50))
	p["hp"] = hp_max
	p["mp"] = mp_max
	srv.combat_stats.player = p
	var gold0: int = srv.inventory.get_gold()
	var r_full: Dictionary = srv.try_inn_rest(25)
	failed += _expect(not bool(r_full.get("ok", true)), "already_full fails")
	failed += _expect(str(r_full.get("reason", "")) == "already_full", "reason already_full")
	failed += _expect(_msg_has(r_full, "你已经状态全满。"), "msg 全满")
	failed += _expect(srv.inventory.get_gold() == gold0, "gold unchanged when full")

	# --- no gold ---
	p = srv.combat_stats.player
	p["hp"] = maxi(1, hp_max / 2)
	p["mp"] = maxi(0, mp_max / 2)
	srv.combat_stats.player = p
	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var r_poor: Dictionary = srv.try_inn_rest(25)
	failed += _expect(not bool(r_poor.get("ok", true)), "no_gold fails")
	failed += _expect(str(r_poor.get("reason", "")) == "no_gold", "reason no_gold")
	failed += _expect(_msg_has(r_poor, "金币不足。"), "msg 金币不足")
	failed += _expect(srv.inventory.get_gold() == 10, "gold unchanged when poor")
	failed += _expect(int(srv.combat_stats.player.get("hp", 0)) == maxi(1, hp_max / 2), "hp unchanged when poor")

	# --- success: spend + full restore ---
	srv.inventory.clear()
	srv.inventory.add_gold(100)
	p = srv.combat_stats.player
	p["hp"] = maxi(1, hp_max / 4)
	p["mp"] = 0
	srv.combat_stats.player = p
	if srv.combat_stats.statuses != null:
		srv.combat_stats.statuses.apply_status(
			"player",
			{"id": "bleed", "name": "流血", "kind": "dot", "duration": 6.0, "tick_hp": -2},
			6.0
		)
		srv.combat_stats.statuses.apply_status(
			"player",
			{"id": "atk_up", "name": "强击", "kind": "buff", "duration": 10.0},
			10.0
		)
	var r_ok: Dictionary = srv.try_inn_rest(25)
	failed += _expect(bool(r_ok.get("ok", false)), "rest ok")
	failed += _expect(srv.inventory.get_gold() == 75, "gold spent 25")
	failed += _expect(int(srv.combat_stats.player.get("hp", 0)) == hp_max, "hp full")
	failed += _expect(int(srv.combat_stats.player.get("mp", 0)) == mp_max, "mp full")
	failed += _expect(_msg_has(r_ok, "你休息得很好。"), "msg 休息得很好")
	failed += _expect(_has(r_ok, "set_stat"), "set_stat action")
	failed += _expect(_has(r_ok, "inventory_update"), "inventory_update action")
	if srv.combat_stats.statuses != null:
		failed += _expect(not srv.combat_stats.statuses.has_status("player", "bleed"), "bleed cleared")
		failed += _expect(srv.combat_stats.statuses.has_status("player", "atk_up"), "buff kept")
		failed += _expect(_has(r_ok, "status_update"), "status_update action")

	# --- default cost 25 ---
	srv.inventory.clear()
	srv.inventory.add_gold(30)
	p = srv.combat_stats.player
	p["hp"] = 1
	srv.combat_stats.player = p
	if srv.combat_stats.statuses != null:
		srv.combat_stats.statuses.clear_all("player")
	var r_def: Dictionary = srv.try_inn_rest()
	failed += _expect(bool(r_def.get("ok", false)), "default cost ok")
	failed += _expect(srv.inventory.get_gold() == 5, "default cost 25")

	# --- dialogue choice inn_rest:N ---
	srv.inventory.clear()
	srv.inventory.add_gold(50)
	p = srv.combat_stats.player
	p["hp"] = 1
	p["mp"] = 0
	srv.combat_stats.player = p
	var r_ch: Dictionary = srv.try_dialogue_choice("inn_rest:25")
	failed += _expect(bool(r_ch.get("ok", false)), "dialogue inn_rest ok")
	failed += _expect(srv.inventory.get_gold() == 25, "dialogue spent 25")
	failed += _expect(_msg_has(r_ch, "你休息得很好。"), "dialogue msg")

	# --- event command inn_rest via EventRuntime ---
	if srv.event_runtime != null:
		srv.inventory.clear()
		srv.inventory.add_gold(40)
		p = srv.combat_stats.player
		p["hp"] = 1
		p["mp"] = 0
		srv.combat_stats.player = p
		var ctx: Dictionary = srv._event_server_ctx("旅店")
		var acts: Array = srv.event_runtime._run_commands(
			"test_inn_ev",
			[{"op": "inn_rest", "cost": 25}],
			ctx
		)
		failed += _expect(_msg_has_arr(acts, "你休息得很好。"), "event op inn_rest msg")
		failed += _expect(srv.inventory.get_gold() == 15, "event spent 25")
		failed += _expect(int(srv.combat_stats.player.get("hp", 0)) == hp_max, "event hp full")
	else:
		failed += _expect(false, "event_runtime present")

	# --- NPC meta / pack flag (soft check via spawn meta) ---
	srv.npc_meta["innkeeper"] = {
		"name": "旅店老板",
		"interact_text": "欢迎。",
		"shop_id": "",
		"inn_rest": true,
		"inn_cost": 25,
	}
	if srv.combat_stats != null and srv.combat_stats.has_method("set_npc_cell"):
		srv.combat_stats.set_npc_cell("innkeeper", 12, 12)
	srv.set_player_cell(12, 13)
	p = srv.combat_stats.player
	p["hp"] = hp_max
	p["mp"] = mp_max
	srv.combat_stats.player = p
	if srv.combat_stats.statuses != null:
		srv.combat_stats.statuses.clear_all("player")
	var r_npc: Dictionary = srv.try_interact("innkeeper", 12, 13)
	failed += _expect(bool(r_npc.get("ok", false)), "interact innkeeper ok")
	failed += _expect(_has(r_npc, "show_npc_dialogue"), "show dialogue")
	var found_opt := false
	for a in r_npc.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "show_npc_dialogue":
			continue
		for o in a.get("options", []):
			if typeof(o) == TYPE_DICTIONARY and str(o.get("id", "")).begins_with("inn_rest"):
				found_opt = true
	failed += _expect(found_opt, "dialogue has inn_rest option")

	# Cleanup
	if srv.combat_stats.statuses != null:
		srv.combat_stats.statuses.clear_all("player")

	if failed == 0:
		print("test_inn: PASS")
		quit(0)
		return
	print("test_inn: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _msg_has(result: Dictionary, needle: String) -> bool:
	return _msg_has_arr(result.get("actions", []), needle)


func _msg_has_arr(actions: Array, needle: String) -> bool:
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
