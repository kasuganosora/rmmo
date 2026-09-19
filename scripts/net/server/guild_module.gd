extends RefCounted
## Domain module: guild (create/invite/respond/kick/leave/disband).

var ctrl
func _init(c):
	ctrl = c

const Guild = preload("res://scripts/net/combat/guild.gd")

func snapshot_guild() -> Dictionary:
	if ctrl.guild == null:
		return {"id": "", "name": "", "leader_id": "", "members": []}
	return ctrl.guild.snapshot()



func _guild_update_action() -> Dictionary:
	return {"type": "guild_update", "guild": snapshot_guild()}



func in_guild() -> bool:
	return ctrl.guild != null and ctrl.guild.in_guild()



func _guild_self_id() -> String:
	return ctrl._party_self_id()



func _guild_self_name() -> String:
	return ctrl._party_self_name()



func try_guild_create(guild_name: String) -> Dictionary:
	var actions: Array = []
	guild_name = str(guild_name).strip_edges()
	if ctrl.guild == null:
		ctrl.guild = Guild.new()
	if ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你已经加入公会了。"})
		actions.append(_guild_update_action())
		return {"ok": false, "reason": "already_in_guild", "actions": actions}
	if guild_name.is_empty():
		actions.append({"type": "system_message", "text": "请输入公会名称。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if guild_name.length() < 2 or guild_name.length() > 12:
		actions.append({"type": "system_message", "text": "公会名称需为 2～12 个字符。"})
		return {"ok": false, "reason": "bad_name", "actions": actions}
	var gid = "guild_%d" % ctrl._next_guild_seq
	ctrl._next_guild_seq += 1
	var r: Dictionary = ctrl.guild.try_create(gid, guild_name, _guild_self_id(), _guild_self_name())
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "failed"))
		actions.append({"type": "system_message", "text": "无法创建公会。"})
		return {"ok": false, "reason": reason, "actions": actions}
	ctrl._guild_invites.clear()
	actions.append(_guild_update_action())
	actions.append({"type": "system_message", "text": "已创建公会【%s】。" % guild_name})
	return {"ok": true, "actions": actions}



func try_guild_invite(target: String) -> Dictionary:
	var actions: Array = []
	target = str(target).strip_edges()
	if ctrl.guild == null or not ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你还没有公会。"})
		return {"ok": false, "reason": "no_guild", "actions": actions}
	if not ctrl.guild.is_leader(_guild_self_id()):
		actions.append({"type": "system_message", "text": "只有会长可以邀请。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	if target.is_empty():
		actions.append({"type": "system_message", "text": "请输入要邀请的玩家名字。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.guild.member_count() >= ctrl.guild.max_members():
		actions.append({"type": "system_message", "text": "公会人数已满（最多 %d 人）。" % ctrl.guild.max_members()})
		return {"ok": false, "reason": "full", "actions": actions}
	# Resolve: remotes / friends / known shell names / free-form stub
	var mid = ""
	var mname = ""
	var resolved: Dictionary = ctrl._resolve_friend_target(target)
	if bool(resolved.get("ok", false)):
		mid = str(resolved.get("id", ""))
		mname = str(resolved.get("name", target))
	else:
		# Free-form stub member (leader adds stub)
		mid = "stub_guild_%s" % target.to_lower().replace(" ", "_")
		mname = target
	if mid == _guild_self_id():
		actions.append({"type": "system_message", "text": "不能邀请自己。"})
		return {"ok": false, "reason": "self", "actions": actions}
	if ctrl.guild.has_member(mid) or ctrl.guild.has_member_name(mname):
		actions.append({"type": "system_message", "text": "【%s】已在公会中。" % mname})
		actions.append(_guild_update_action())
		return {"ok": false, "reason": "already_member", "actions": actions}
	var add_r: Dictionary = ctrl.guild.try_add_member(mid, mname, Guild.RANK_MEMBER)
	if not bool(add_r.get("ok", false)):
		var r2 = str(add_r.get("reason", ""))
		if r2 == "full":
			actions.append({"type": "system_message", "text": "公会人数已满（最多 %d 人）。" % ctrl.guild.max_members()})
			return {"ok": false, "reason": "full", "actions": actions}
		actions.append({"type": "system_message", "text": "无法邀请【%s】。" % mname})
		return {"ok": false, "reason": r2 if r2 != "" else "failed", "actions": actions}
	actions.append(_guild_update_action())
	actions.append({"type": "system_message", "text": "已邀请【%s】加入公会（已入会）。" % mname})
	return {"ok": true, "actions": actions}



func try_guild_incoming_invite(from_name: String = "旅人甲", guild_name: String = "测试公会") -> Dictionary:
	var actions: Array = []
	from_name = str(from_name).strip_edges()
	guild_name = str(guild_name).strip_edges()
	if from_name.is_empty():
		from_name = "旅人甲"
	if guild_name.is_empty():
		guild_name = "测试公会"
	if ctrl.guild != null and ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你已经加入公会了。"})
		return {"ok": false, "reason": "already_in_guild", "actions": actions}
	var inv_id = "ginv_%d" % ctrl._next_guild_invite_seq
	ctrl._next_guild_invite_seq += 1
	var gid = "guild_pending_%d" % ctrl._next_guild_seq
	ctrl._guild_invites.append({
		"id": inv_id,
		"guild_id": gid,
		"guild_name": guild_name,
		"from_id": "remote:%s" % from_name,
		"from_name": from_name,
	})
	actions.append({
		"type": "guild_invite",
		"invite_id": inv_id,
		"guild_name": guild_name,
		"from": from_name,
		"status": "pending",
	})
	actions.append({"type": "system_message", "text": "【%s】邀请你加入公会【%s】。" % [from_name, guild_name]})
	return {"ok": true, "actions": actions}



func try_guild_invite_respond(invite_id: String, accept: bool) -> Dictionary:
	var actions: Array = []
	invite_id = str(invite_id).strip_edges()
	var idx = -1
	for i in range(ctrl._guild_invites.size()):
		var inv: Variant = ctrl._guild_invites[i]
		if typeof(inv) == TYPE_DICTIONARY and str(inv.get("id", "")) == invite_id:
			idx = i
			break
	if idx < 0:
		actions.append({"type": "system_message", "text": "没有这条公会邀请。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var row: Dictionary = ctrl._guild_invites[idx]
	ctrl._guild_invites.remove_at(idx)
	var gname = str(row.get("guild_name", "公会"))
	var from_name = str(row.get("from_name", ""))
	if not accept:
		actions.append({
			"type": "guild_invite",
			"invite_id": invite_id,
			"guild_name": gname,
			"from": from_name,
			"status": "declined",
		})
		actions.append({"type": "system_message", "text": "你拒绝了公会邀请。"})
		return {"ok": true, "actions": actions}
	if ctrl.guild != null and ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你已经加入公会了。"})
		return {"ok": false, "reason": "already_in_guild", "actions": actions}
	if ctrl.guild == null:
		ctrl.guild = Guild.new()
	var gid = str(row.get("guild_id", ""))
	if gid.is_empty():
		gid = "guild_%d" % ctrl._next_guild_seq
		ctrl._next_guild_seq += 1
	var leader_id = str(row.get("from_id", "remote_leader"))
	var leader_name = from_name if from_name != "" else "会长"
	var cr: Dictionary = ctrl.guild.try_create(gid, gname, leader_id, leader_name)
	if not bool(cr.get("ok", false)):
		actions.append({"type": "system_message", "text": "无法加入公会。"})
		return {"ok": false, "reason": str(cr.get("reason", "failed")), "actions": actions}
	var ar: Dictionary = ctrl.guild.try_add_member(_guild_self_id(), _guild_self_name(), Guild.RANK_MEMBER)
	if not bool(ar.get("ok", false)):
		ctrl.guild.clear()
		actions.append({"type": "system_message", "text": "无法加入公会。"})
		return {"ok": false, "reason": str(ar.get("reason", "failed")), "actions": actions}
	actions.append(_guild_update_action())
	actions.append({
		"type": "guild_invite",
		"invite_id": invite_id,
		"guild_name": gname,
		"from": from_name,
		"status": "accepted",
	})
	actions.append({"type": "system_message", "text": "你加入了公会【%s】。" % gname})
	return {"ok": true, "actions": actions}



func try_guild_kick(member_id: String) -> Dictionary:
	var actions: Array = []
	member_id = str(member_id).strip_edges()
	if ctrl.guild == null or not ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你还没有公会。"})
		return {"ok": false, "reason": "no_guild", "actions": actions}
	if not ctrl.guild.is_leader(_guild_self_id()):
		actions.append({"type": "system_message", "text": "只有会长可以踢人。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	if member_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的成员。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if member_id == _guild_self_id() or member_id == ctrl.guild.leader_id:
		actions.append({"type": "system_message", "text": "不能踢出会长。"})
		return {"ok": false, "reason": "is_leader", "actions": actions}
	var idx: int = ctrl.guild.find_index_by_id(member_id)
	var mname = member_id
	if idx >= 0:
		var e: Variant = ctrl.guild.members[idx]
		if typeof(e) == TYPE_DICTIONARY:
			mname = str(e.get("name", member_id))
	var rem: Dictionary = ctrl.guild.try_remove_member(member_id)
	if not bool(rem.get("ok", false)):
		actions.append({"type": "system_message", "text": "公会中没有该成员。"})
		return {"ok": false, "reason": str(rem.get("reason", "not_found")), "actions": actions}
	actions.append(_guild_update_action())
	actions.append({"type": "system_message", "text": "已将【%s】移出公会。" % mname})
	return {"ok": true, "actions": actions}



func try_guild_leave() -> Dictionary:
	var actions: Array = []
	if ctrl.guild == null or not ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你不在公会中。"})
		actions.append(_guild_update_action())
		return {"ok": false, "reason": "no_guild", "actions": actions}
	var self_id = _guild_self_id()
	var gname: String = str(ctrl.guild.guild_name)
	var was_leader: bool = bool(ctrl.guild.is_leader(self_id))
	# Shell: leaving dissolves the local guild (stub members vanish with you).
	ctrl.guild.clear()
	ctrl._guild_invites.clear()
	actions.append(_guild_update_action())
	if was_leader:
		actions.append({"type": "system_message", "text": "你离开了公会【%s】（会长离会，公会解散）。" % gname})
	else:
		actions.append({"type": "system_message", "text": "你离开了公会【%s】。" % gname})
	return {"ok": true, "actions": actions}



func try_guild_disband() -> Dictionary:
	var actions: Array = []
	if ctrl.guild == null or not ctrl.guild.in_guild():
		actions.append({"type": "system_message", "text": "你还没有公会。"})
		actions.append(_guild_update_action())
		return {"ok": false, "reason": "no_guild", "actions": actions}
	if not ctrl.guild.is_leader(_guild_self_id()):
		actions.append({"type": "system_message", "text": "只有会长可以解散公会。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	var gname: String = str(ctrl.guild.guild_name)
	ctrl.guild.clear()
	ctrl._guild_invites.clear()
	actions.append(_guild_update_action())
	actions.append({"type": "system_message", "text": "公会【%s】已解散。" % gname})
	return {"ok": true, "actions": actions}


