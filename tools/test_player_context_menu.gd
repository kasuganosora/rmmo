extends SceneTree
## Headless: remote player context-menu actions (invite/trade by display name) + menu ids.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_player_context_menu: FAIL no MockServer")
		quit(1)
		return

	# Fresh remotes / party / trade
	if srv.has_method("try_remote_despawn"):
		srv.try_remote_despawn("")
	if srv.has_method("_party_clear"):
		srv._party_clear()
	srv._party_poll_pending = false
	srv._stub_ally_seq = 1
	srv._session_character_id = "1"
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.combat_stats != null:
		srv.combat_stats.reset_player(3)
		if srv.combat_stats.has_method("set_player_actor_id"):
			srv.combat_stats.set_player_actor_id("1")
	srv.set_player_cell(10, 10)

	# Menu helper labels / ids
	var PCM = load("res://scripts/ui/player_context_menu.gd")
	failed += _expect(PCM != null, "load player_context_menu")
	if PCM != null:
		failed += _expect(PCM.Action.INVITE == 2, "invite id=2")
		failed += _expect(PCM.Action.TRADE == 3, "trade id=3")
		failed += _expect(PCM.Action.WHISPER == 4, "whisper id=4")
		failed += _expect(PCM.label_for(PCM.Action.INVITE) == "邀请组队", "invite label")
		failed += _expect(PCM.label_for(PCM.Action.TRADE) == "交易", "trade label")
		failed += _expect(PCM.label_for(PCM.Action.WHISPER) == "密语", "whisper label")
		failed += _expect(PCM.Action.ADD_FRIEND == 6, "add_friend id=6")
		failed += _expect(PCM.label_for(PCM.Action.ADD_FRIEND) == "加为好友", "add_friend label")
		failed += _expect(PCM.Action.DUEL == 7, "duel id=7")
		failed += _expect(PCM.label_for(PCM.Action.DUEL) == "决斗", "duel label")
		var defs: Array = PCM.item_defs()
		failed += _expect(defs.size() >= 4, "menu has >=4 items")
		var texts := {}
		for d in defs:
			texts[str(d.get("text", ""))] = true
		failed += _expect(texts.has("邀请组队") and texts.has("交易"), "menu has invite+trade")

	# Spawn remote「旅人甲」
	var sp: Dictionary = srv.try_remote_debug_spawn("旅人甲")
	failed += _expect(bool(sp.get("ok", false)), "spawn 旅人甲 ok")
	failed += _expect(srv.snapshot_remote_players().size() >= 1, "has remote")
	var remote: Dictionary = srv.snapshot_remote_players()[0]
	var rid := str(remote.get("id", ""))
	var rname := str(remote.get("name", ""))
	failed += _expect(rname == "旅人甲", "remote name 旅人甲")
	failed += _expect(not rid.is_empty(), "remote id set")

	# Invite by display name → pending then stub/remote accepts on tick
	var inv: Dictionary = srv.try_party_invite("旅人甲")
	failed += _expect(bool(inv.get("ok", false)), "invite by name ok")
	failed += _expect(_has(inv, "party_update"), "invite party_update")
	# Force pending invite ready (shell auto-accept).
	if srv._party_invites.size() > 0:
		srv._party_invites[0]["ready_at"] = 0
	var resolved: Array = srv._tick_party_invites()
	failed += _expect(resolved.size() >= 1, "invite resolved")
	var mems: Array = srv.snapshot_party().get("members", [])
	var found := false
	var found_id := ""
	for m in mems:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("name", "")) == "旅人甲":
			found = true
			found_id = str(m.get("id", ""))
	failed += _expect(found, "party member name 旅人甲")
	failed += _expect(found_id == rid, "party member id is remote id")

	# Leave then invite by remote id also works
	srv.try_party_leave()
	var inv2: Dictionary = srv.try_party_invite(rid)
	failed += _expect(bool(inv2.get("ok", false)), "invite by id ok")
	if srv._party_invites.size() > 0:
		srv._party_invites[0]["ready_at"] = 0
	srv._tick_party_invites()
	var mems2: Array = srv.snapshot_party().get("members", [])
	var found2 := false
	for m2 in mems2:
		if typeof(m2) == TYPE_DICTIONARY and str(m2.get("name", "")) == "旅人甲":
			found2 = true
	failed += _expect(found2, "invite by id keeps display name")

	# Trade by display name → partner_name + partner_id
	if srv.in_trade():
		srv.try_trade_cancel()
	var tr: Dictionary = srv.try_trade_open("旅人甲")
	failed += _expect(bool(tr.get("ok", false)), "trade open ok")
	failed += _expect(srv.in_trade(), "in trade")
	var snap: Dictionary = srv.snapshot_trade()
	failed += _expect(str(snap.get("partner_name", "")) == "旅人甲", "trade partner_name")
	failed += _expect(str(snap.get("partner_id", "")) == rid, "trade partner_id is remote")

	# Empty trade still defaults to 旅人乙 (cancel first)
	srv.try_trade_cancel()
	var tr0: Dictionary = srv.try_trade_open("")
	failed += _expect(bool(tr0.get("ok", false)), "empty trade ok")
	failed += _expect(str(srv.snapshot_trade().get("partner_name", "")) == "旅人乙", "empty defaults 旅人乙")

	# World helper exists (script parse / method presence via load)
	var world_script = load("res://scripts/game/world.gd")
	failed += _expect(world_script != null, "load world.gd")
	if world_script != null:
		# Source-level presence is enough in headless without full scene.
		var src := FileAccess.get_file_as_string("res://scripts/game/world.gd")
		failed += _expect(src.contains("_find_remote_at"), "world has _find_remote_at")
		failed += _expect(src.contains("_on_world_right_click"), "world has right-click handler")
		failed += _expect(src.contains("open_player_context_menu"), "world opens context menu")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/game_hud.gd")
	failed += _expect(hud_src.contains("open_player_context_menu"), "hud open_player_context_menu")
	failed += _expect(hud_src.contains("右键玩家，或输入名字"), "party placeholder updated")
	failed += _expect(hud_src.contains("prefill_whisper"), "hud prefill_whisper")

	if failed == 0:
		print("test_player_context_menu: PASS")
		quit(0)
		return
	print("test_player_context_menu: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _first(result: Dictionary, typ: String) -> Dictionary:
	## Prefer the last matching action (invite may emit create then update).
	var last := {}
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			last = a
	return last


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
