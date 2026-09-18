extends SceneTree
## Headless: follow/inspect/death/passives/party invite/keybinds/combat log.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	failed += _expect(srv != null, "MockServer")
	if srv == null:
		_finish(failed)
		return
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	srv.awaiting_respawn = false
	if srv.has_method("_party_clear"):
		srv._party_clear()
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()

	# Death waits for try_respawn
	srv.combat_stats.player["hp"] = 0
	srv.awaiting_respawn = true
	failed += _expect(srv.has_method("try_respawn"), "try_respawn exists")
	var rr: Dictionary = srv.try_respawn()
	failed += _expect(bool(rr.get("ok", false)), "respawn ok")
	failed += _expect(_has(rr, "respawn"), "respawn action")
	failed += _expect(not srv.awaiting_respawn, "cleared awaiting")
	failed += _expect(srv.combat_stats.player_alive(), "alive after respawn")

	# 就地 vs 回城（关掉碰撞，避免演示图把目标格重映射）
	var saved_col = srv.map_collision
	srv.map_collision = null
	srv.respawn_cell = Vector2i(10, 10)
	srv.death_cell = Vector2i(3, 4)
	srv.set_player_cell(3, 4)
	srv.combat_stats.player["hp"] = 0
	srv.awaiting_respawn = true
	var here_r: Dictionary = srv.try_respawn("here")
	failed += _expect(bool(here_r.get("ok", false)), "here respawn ok")
	failed += _expect(srv.player_cell == Vector2i(3, 4), "here dest death_cell")
	var hp_here: int = int(srv.combat_stats.player.get("hp", 0))
	var hp_max: int = int(srv.combat_stats.player.get("hp_max", 0))
	failed += _expect(hp_here == maxi(1, hp_max / 2), "here half hp")
	srv.combat_stats.player["hp"] = 0
	srv.awaiting_respawn = true
	srv.death_cell = Vector2i(3, 4)
	var town_r: Dictionary = srv.try_respawn("town")
	failed += _expect(bool(town_r.get("ok", false)), "town respawn ok")
	failed += _expect(srv.player_cell == Vector2i(10, 10), "town dest respawn_cell")
	failed += _expect(int(srv.combat_stats.player.get("hp", 0)) == hp_max, "town full hp")

	# Recall to town
	srv.set_player_cell(1, 1)
	srv.respawn_cell = Vector2i(10, 10)
	var rec: Dictionary = srv.try_recall()
	failed += _expect(bool(rec.get("ok", false)), "recall ok")
	failed += _expect(_has(rec, "recall"), "recall action")
	failed += _expect(srv.player_cell == Vector2i(10, 10), "recall teleported")
	srv.map_collision = saved_col

	# Sit / rest regen / stand on damage
	srv.combat_stats.player["hp"] = 20
	srv.combat_stats.player["mp"] = 10
	var sit_r: Dictionary = srv.try_sit(true)
	failed += _expect(bool(sit_r.get("ok", false)), "sit ok")
	failed += _expect(bool(srv.sitting), "sitting flag")
	failed += _expect(_has(sit_r, "sit"), "sit action")
	srv._tick_sit(3.0)
	failed += _expect(int(srv.combat_stats.player.get("hp", 0)) > 20, "sit regen hp")
	failed += _expect(int(srv.combat_stats.player.get("mp", 0)) > 10, "sit regen mp")
	var stand_acts: Array = []
	failed += _expect(srv._stand_if_sitting(stand_acts), "stand from sit")
	failed += _expect(not bool(srv.sitting), "standing after cancel")
	srv.try_sit(true)
	var dmg_r: Dictionary = srv._finalize_combat_result({
		"ok": true,
		"actions": [{"type": "damage", "target": "player", "amount": 1, "hp": 19}],
	})
	failed += _expect(not bool(srv.sitting), "hit cancels sit")
	failed += _expect(_has(dmg_r, "sit"), "hit emits sit off")

	# Party invite pending then accept
	srv.try_party_create()
	var inv: Dictionary = srv.try_party_invite("壳测试盟友")
	failed += _expect(bool(inv.get("ok", false)), "invite ok")
	failed += _expect(srv.snapshot_party().get("pending_invites", []).size() >= 1, "pending invite")
	var found := false
	for m in srv.snapshot_party().get("members", []):
		if typeof(m) == TYPE_DICTIONARY and str(m.get("name", "")) == "壳测试盟友":
			found = true
	failed += _expect(not found, "not in party until accept")
	if srv._party_invites.size() > 0:
		srv._party_invites[0]["ready_at"] = 0
	srv._tick_party_invites()
	for m2 in srv.snapshot_party().get("members", []):
		if typeof(m2) == TYPE_DICTIONARY and str(m2.get("name", "")) == "壳测试盟友":
			found = true
	failed += _expect(found, "accepted into party")

	# Incoming invite dialog path
	var inc: Dictionary = srv.try_party_incoming_invite("旅人甲")
	failed += _expect(bool(inc.get("ok", false)), "incoming invite")
	failed += _expect(_has(inc, "party_invite"), "incoming action")
	var iid := str(_first(inc, "party_invite").get("invite_id", ""))
	var dec: Dictionary = srv.try_party_invite_respond(iid, false)
	failed += _expect(bool(dec.get("ok", false)), "decline ok")

	# Trade no canned offer
	if srv.inventory:
		srv.inventory.add_item("potion_hp_small", 1)
	srv.try_trade_open("空报价")
	srv.try_trade_ready(true)
	var snap: Dictionary = srv.snapshot_trade()
	failed += _expect((snap.get("their_items", []) as Array).is_empty(), "trade empty their items")
	failed += _expect(int(snap.get("their_gold", -1)) == 0, "trade empty their gold")
	srv.try_trade_cancel()

	var packed: PackedScene = load("res://scenes/ui/game_hud.tscn")
	var hud: Control = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	failed += _expect(hud.has_method("show_death_dialog"), "death dialog api")
	hud.show_death_dialog()
	await process_frame
	failed += _expect(hud._death_panel != null and hud._death_panel.visible, "death visible")
	var death_txt := ""
	for b in hud._death_panel.find_children("*", "Button", true, false):
		death_txt += str((b as Button).text)
	failed += _expect(death_txt.find("就地") >= 0, "death here button")
	failed += _expect(death_txt.find("回城") >= 0, "death town button")
	hud.hide_death_dialog()
	failed += _expect(not hud._death_panel.visible, "death hidden")

	var RadarView = load("res://scripts/ui/radar_view.gd")
	var rv: Control = Control.new()
	rv.set_script(RadarView)
	rv.custom_minimum_size = Vector2(100, 100)
	rv.size = Vector2(100, 100)
	root.add_child(rv)
	await process_frame
	rv.size = Vector2(100, 100)
	rv.world_scale = 1.0
	rv._center_world = Vector2(480, 480)
	var mid: Vector2i = rv.local_to_cell(Vector2(50, 50))
	failed += _expect(mid == Vector2i(10, 10), "radar center cell")
	rv.set_pin_cell(Vector2i(4, 5))
	failed += _expect(rv._pin_cell == Vector2i(4, 5), "radar pin set")
	var MapOverview = load("res://scripts/ui/map_overview.gd")
	var ov: Control = Control.new()
	ov.set_script(MapOverview)
	ov.custom_minimum_size = Vector2(200, 200)
	ov.size = Vector2(200, 200)
	root.add_child(ov)
	await process_frame
	ov.size = Vector2(200, 200)
	ov._pan_cell = Vector2(50, 50)
	ov._cells_across = 100.0
	var oc: Vector2i = ov.local_to_cell(Vector2(100, 100))
	failed += _expect(oc == Vector2i(50, 50), "overview center cell")
	ov.set_pin_cell(Vector2i(8, 9))
	failed += _expect(ov._pin_cell == Vector2i(8, 9), "overview pin set")

	var gs_sit = load("res://scripts/game/game_settings.gd").get_i()
	if gs_sit != null:
		failed += _expect(int(gs_sit.key_for("sit")) == KEY_R, "default sit R")

	hud.append_combat("测试伤害 12")
	failed += _expect(hud._chat_history.size() >= 1, "combat log row")
	var last: Dictionary = hud._chat_history[hud._chat_history.size() - 1]
	failed += _expect(str(last.get("channel", "")) == "combat", "combat channel")

	# Known passive: HUD explains it is always on (not cast).
	if hud.has_method("_known_skills") or true:
		hud._known_skills["tough_skin"] = true
	hud._on_skill_slot_pressed("tough_skin")
	var saw_passive := false
	for row in hud._chat_history:
		var msg := str(row.get("msg", ""))
		if msg.find("被动已生效") >= 0 or msg.find("被动始终生效") >= 0:
			saw_passive = true
	failed += _expect(saw_passive, "passive always-on message")

	hud._show_inspect("p1", "测试玩家")
	await process_frame
	failed += _expect(hud._inspect_panel != null and hud._inspect_panel.visible, "inspect open")

	hud.apply_quest_snapshot([
		{"id": "q1", "title": "新手", "status": "in_progress", "objectives": [{"text": "假人", "cur": 1, "max": 3}]},
	])
	await process_frame
	failed += _expect(hud._quest_tracker != null and hud._quest_tracker.visible, "quest tracker")

	var gs = load("res://scripts/game/game_settings.gd").get_i()
	if gs != null:
		gs.persist_enabled = false
		var prev := int(gs.key_for("cycle_target"))
		failed += _expect(prev == KEY_TAB, "default tab cycle")
		var conflict := str(gs.set_keybind("pickup", KEY_C))
		failed += _expect(conflict == "character", "keybind conflict")
		failed += _expect(str(gs.set_keybind("pickup", KEY_F)) == "", "rebind same ok")
		gs.set_flag("auto_pickup", true)
		failed += _expect(bool(gs.auto_pickup), "auto_pickup flag")
		gs.set_flag("auto_pickup", false)

	hud._on_system_tab("keys")
	await process_frame
	var sys: PanelContainer = hud._windows.get("system")
	failed += _expect(sys.get_meta("system_tabs").get_child_count() == 5, "keys tab exists")

	# Inventory split / lock / sort
	if srv.inventory:
		srv.inventory.clear()
		srv.inventory.add_item("potion_hp_small", 8)
		failed += _expect(srv.inventory.slot_count() == 1, "one stack before split")
		var sp: Dictionary = srv.try_inventory_split("potion_hp_small", 3)
		failed += _expect(bool(sp.get("ok", false)), "split ok")
		failed += _expect(srv.inventory.slot_count() == 2, "two stacks after split")
		failed += _expect(srv.inventory.get_qty("potion_hp_small") == 8, "qty still 8")
		var lk: Dictionary = srv.try_inventory_lock("potion_hp_small", true)
		failed += _expect(bool(lk.get("ok", false)), "lock ok")
		failed += _expect(srv.inventory.is_locked("potion_hp_small"), "locked")
		var drop_l: Dictionary = srv.try_drop_item("potion_hp_small", 1)
		failed += _expect(not bool(drop_l.get("ok", true)), "locked cannot drop")
		srv.try_inventory_lock("potion_hp_small", false)
		srv.try_inventory_sort()
		failed += _expect(srv.inventory.slot_count() == 2, "sort keeps stacks")

	# Shop buyback
	if srv.inventory:
		srv.inventory.clear()
		srv.inventory.add_item("potion_hp_small", 2)
		srv.inventory.add_gold(50)
		var sell: Dictionary = srv.try_shop_sell("potion_hp_small", 2)
		failed += _expect(bool(sell.get("ok", false)), "sell ok")
		failed += _expect(srv.snapshot_shop_buyback().size() >= 1, "buyback listed")
		var gold_mid: int = srv.inventory.get_gold()
		var bb: Dictionary = srv.try_shop_buyback(0)
		failed += _expect(bool(bb.get("ok", false)), "buyback ok")
		failed += _expect(srv.inventory.get_qty("potion_hp_small") == 2, "bought back")
		failed += _expect(srv.inventory.get_gold() < gold_mid or srv.inventory.get_gold() <= gold_mid, "gold spent")

	# Chat: no stub echo
	srv.try_remote_debug_spawn("听者")
	var wh: Dictionary = srv.try_chat("whisper", "你好", "听者")
	failed += _expect(bool(wh.get("ok", false)), "whisper ok")
	var echo := 0
	for a in wh.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "chat_message":
			echo += 1
			failed += _expect(str(a.get("text", "")).find("占位") < 0, "no stub whisper")
	failed += _expect(echo == 1, "whisper only self line")
	var near: Dictionary = srv.try_chat("nearby", "附近测试")
	failed += _expect(bool(near.get("ok", false)), "nearby ok")
	for a2 in near.get("actions", []):
		if typeof(a2) == TYPE_DICTIONARY:
			failed += _expect(str(a2.get("text", "")).find("调试假玩家") < 0, "no debug hint nearby")

	# Inspect does not copy local Adena
	hud._server_gold = 99999
	hud._server_combat = {"atk": 99, "def": 99, "exp": 1, "exp_to_next": 2}
	hud._show_inspect("remote_x", "路人")
	await process_frame
	var inspect_txt := _collect_labels(hud._inspect_panel)
	failed += _expect(inspect_txt.find("Adena") < 0, "inspect no Adena")
	failed += _expect(inspect_txt.find("STR") < 0, "inspect no STR")
	failed += _expect(inspect_txt.find("路人") >= 0, "inspect shows name")

	# Party panel has no debug fill when empty
	hud._party_state = {"party_id": "", "members": []}
	hud._refresh_party_panel()
	await process_frame
	var party_btns := ""
	if hud._party_body:
		for c in hud._party_body.get_children():
			if c is Button:
				party_btns += str((c as Button).text)
	failed += _expect(party_btns.find("调试") < 0, "party no debug fill")
	failed += _expect(party_btns.find("假玩家") < 0, "party no fake player")

	_finish(failed)


func _collect_labels(n: Node) -> String:
	if n == null:
		return ""
	var acc := ""
	if n is Label:
		acc += str((n as Label).text)
	for c in n.get_children():
		acc += _collect_labels(c)
	return acc


func _has(result: Dictionary, t: String) -> bool:
	var acts: Variant = result.get("actions", [])
	if typeof(acts) != TYPE_ARRAY:
		return false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


func _first(result: Dictionary, t: String) -> Dictionary:
	var acts: Variant = result.get("actions", [])
	if typeof(acts) != TYPE_ARRAY:
		return {}
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return a
	return {}


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("test_shell_systems: ALL PASS")
		quit(0)
	else:
		print("test_shell_systems: FAIL count=", failed)
		quit(1)
