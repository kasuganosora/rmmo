extends SceneTree
## Headless: MockServer guild create/invite/kick/leave/disband + invite respond + clear.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_guild: FAIL no MockServer")
		quit(1)
		return
	if srv.guild == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.guild == null:
		print("test_guild: FAIL no guild after init")
		quit(1)
		return

	srv.guild.clear()
	srv._guild_invites.clear()
	if srv.has_method("try_remote_despawn"):
		srv.try_remote_despawn("")
	srv._session_character_id = "1"
	if srv.combat_stats == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_guild_create"), "has try_guild_create")
	failed += _expect(srv.has_method("try_guild_invite"), "has try_guild_invite")
	failed += _expect(srv.has_method("try_guild_kick"), "has try_guild_kick")
	failed += _expect(srv.has_method("try_guild_leave"), "has try_guild_leave")
	failed += _expect(srv.has_method("try_guild_disband"), "has try_guild_disband")
	failed += _expect(srv.has_method("snapshot_guild"), "has snapshot_guild")
	failed += _expect(srv.has_method("try_guild_invite_respond"), "has try_guild_invite_respond")
	failed += _expect(srv.has_method("try_guild_incoming_invite"), "has try_guild_incoming_invite")

	var snap0: Dictionary = srv.snapshot_guild()
	failed += _expect(str(snap0.get("id", "")) == "", "empty id")
	failed += _expect(typeof(snap0.get("members", null)) == TYPE_ARRAY, "members array")
	failed += _expect((snap0.get("members", []) as Array).is_empty(), "empty members")

	# Create
	var bad: Dictionary = srv.try_guild_create("")
	failed += _expect(not bool(bad.get("ok", true)), "empty name rejected")
	failed += _expect(_has(bad, "system_message"), "empty name msg")

	var bad2: Dictionary = srv.try_guild_create("A")
	failed += _expect(not bool(bad2.get("ok", true)), "short name rejected")

	var cr: Dictionary = srv.try_guild_create("龙之盟")
	failed += _expect(bool(cr.get("ok", false)), "create ok")
	failed += _expect(_has(cr, "guild_update"), "create guild_update")
	failed += _expect(_has(cr, "system_message"), "create system_message")
	var snap1: Dictionary = srv.snapshot_guild()
	failed += _expect(str(snap1.get("name", "")) == "龙之盟", "guild name")
	failed += _expect(str(snap1.get("id", "")) != "", "guild id set")
	failed += _expect(str(snap1.get("leader_id", "")) == "1", "leader is self")
	var mem1: Array = snap1.get("members", [])
	failed += _expect(mem1.size() == 1, "one member after create")

	var dup: Dictionary = srv.try_guild_create("再创一个")
	failed += _expect(not bool(dup.get("ok", true)), "already in guild")
	failed += _expect(str(dup.get("reason", "")) == "already_in_guild", "reason already_in_guild")

	# Spawn remote and invite
	var sp: Dictionary = srv.try_remote_debug_spawn("旅人甲")
	failed += _expect(bool(sp.get("ok", false)), "spawn 旅人甲")
	var rid := ""
	for r in srv.snapshot_remote_players():
		if typeof(r) == TYPE_DICTIONARY and str(r.get("name", "")) == "旅人甲":
			rid = str(r.get("id", ""))
			break
	failed += _expect(rid != "", "remote id")

	var inv: Dictionary = srv.try_guild_invite("旅人甲")
	failed += _expect(bool(inv.get("ok", false)), "invite remote ok")
	failed += _expect(_has(inv, "guild_update"), "invite guild_update")
	var snap2: Dictionary = srv.snapshot_guild()
	failed += _expect((snap2.get("members", []) as Array).size() == 2, "two members after invite")

	var inv_dup: Dictionary = srv.try_guild_invite("旅人甲")
	failed += _expect(not bool(inv_dup.get("ok", true)), "dup invite rejected")

	# Invite by free-form stub name
	var inv2: Dictionary = srv.try_guild_invite("盟友丁")
	failed += _expect(bool(inv2.get("ok", false)), "invite stub ok")
	failed += _expect((srv.snapshot_guild().get("members", []) as Array).size() == 3, "three members")

	# Invite known shell / friend-style name
	if srv.friend_list != null:
		srv.friend_list.clear()
		srv.try_friend_add("旅人乙")
	var inv3: Dictionary = srv.try_guild_invite("旅人乙")
	failed += _expect(bool(inv3.get("ok", false)), "invite friend/known ok")

	# Kick
	var kick_id := ""
	for e in srv.snapshot_guild().get("members", []):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("name", "")) == "盟友丁":
			kick_id = str(e.get("id", ""))
			break
	failed += _expect(kick_id != "", "stub id for kick")
	var kick: Dictionary = srv.try_guild_kick(kick_id)
	failed += _expect(bool(kick.get("ok", false)), "kick ok")
	var still := false
	for e2 in srv.snapshot_guild().get("members", []):
		if typeof(e2) == TYPE_DICTIONARY and str(e2.get("id", "")) == kick_id:
			still = true
	failed += _expect(not still, "kicked gone")

	var kick_self: Dictionary = srv.try_guild_kick("1")
	failed += _expect(not bool(kick_self.get("ok", true)), "cannot kick leader")

	# Cap
	var before_cap: int = (srv.snapshot_guild().get("members", []) as Array).size()
	var cap: int = int(srv.guild.max_members())
	failed += _expect(cap == 20, "cap 20")
	var fill_fail := false
	for i in range(cap - before_cap + 2):
		var fr: Dictionary = srv.try_guild_invite("填充成员%d" % i)
		if not bool(fr.get("ok", false)):
			if str(fr.get("reason", "")) == "full":
				fill_fail = true
				failed += _expect(_has(fr, "system_message"), "full message")
				break
	failed += _expect(fill_fail, "hit member cap")
	failed += _expect((srv.snapshot_guild().get("members", []) as Array).size() <= cap, "at/under cap")

	# Leave dissolves local shell guild (stubs vanish with you).
	var leave: Dictionary = srv.try_guild_leave()
	failed += _expect(bool(leave.get("ok", false)), "leader leave ok")
	var snap_leave: Dictionary = srv.snapshot_guild()
	failed += _expect(str(snap_leave.get("id", "")) == "", "guild cleared after leave")
	failed += _expect((snap_leave.get("members", []) as Array).is_empty(), "no members after leave")

	# Recreate and disband
	srv.guild.clear()
	srv._guild_invites.clear()
	var cr2: Dictionary = srv.try_guild_create("测试盟")
	failed += _expect(bool(cr2.get("ok", false)), "recreate ok")
	srv.try_guild_invite("旅人甲")
	var dis: Dictionary = srv.try_guild_disband()
	failed += _expect(bool(dis.get("ok", false)), "disband ok")
	failed += _expect(str(srv.snapshot_guild().get("id", "")) == "", "cleared after disband")
	failed += _expect((srv.snapshot_guild().get("members", []) as Array).is_empty(), "no members after disband")

	# Incoming invite accept / decline
	var inc: Dictionary = srv.try_guild_incoming_invite("旅人丙", "远征队")
	failed += _expect(bool(inc.get("ok", false)), "incoming invite ok")
	failed += _expect(_has(inc, "guild_invite"), "guild_invite action")
	var invite_id := ""
	for a in inc.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "guild_invite":
			invite_id = str(a.get("invite_id", ""))
	failed += _expect(invite_id != "", "invite_id")

	var dec: Dictionary = srv.try_guild_invite_respond(invite_id, false)
	failed += _expect(bool(dec.get("ok", false)), "decline ok")
	failed += _expect(str(srv.snapshot_guild().get("id", "")) == "", "still no guild after decline")

	var inc2: Dictionary = srv.try_guild_incoming_invite("旅人丙", "远征队")
	invite_id = ""
	for a2 in inc2.get("actions", []):
		if typeof(a2) == TYPE_DICTIONARY and str(a2.get("type", "")) == "guild_invite":
			invite_id = str(a2.get("invite_id", ""))
	var acc: Dictionary = srv.try_guild_invite_respond(invite_id, true)
	failed += _expect(bool(acc.get("ok", false)), "accept ok")
	failed += _expect(str(srv.snapshot_guild().get("name", "")) == "远征队", "joined 远征队")
	failed += _expect(_has(acc, "guild_update"), "accept guild_update")

	# enter_world style clear
	srv.guild.clear()
	srv._guild_invites.clear()
	failed += _expect(str(srv.snapshot_guild().get("id", "")) == "", "cleared for new session")

	# PCM INVITE_GUILD
	var PCM = load("res://scripts/ui/player_context_menu.gd")
	failed += _expect(PCM != null, "load PCM")
	if PCM != null:
		failed += _expect(PCM.Action.INVITE_GUILD == 8, "INVITE_GUILD id=8")
		failed += _expect(PCM.label_for(PCM.Action.INVITE_GUILD) == "邀请入会", "INVITE_GUILD label")
		failed += _expect(PCM.Action.ADD_FRIEND == 6, "ADD_FRIEND unchanged")
		failed += _expect(PCM.Action.INVITE == 2, "INVITE unchanged")

	if failed == 0:
		print("test_guild: PASS")
		quit(0)
		return
	print("test_guild: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
