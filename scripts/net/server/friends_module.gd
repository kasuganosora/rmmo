extends RefCounted
## Domain module: friends (add/remove/resolve target).

var ctrl
func _init(c):
	ctrl = c

const FriendList = preload("res://scripts/net/combat/friend_list.gd")
const SHELL_REMOTE_NAMES := ["旅人甲", "旅人乙", "旅人丙"]

func snapshot_friends() -> Dictionary:
	var online_ids: Dictionary = {}
	var online_names: Dictionary = {}
	for rid in ctrl._remote_players.keys():
		online_ids[str(rid)] = true
		var d: Variant = ctrl._remote_players[rid]
		if typeof(d) == TYPE_DICTIONARY:
			var nm = str(d.get("name", "")).strip_edges()
			if nm != "":
				online_names[nm] = true
	if ctrl.friend_list == null:
		return {"friends": [], "count": 0, "max_friends": 50}
	return ctrl.friend_list.snapshot_state(online_ids, online_names)



func _friends_update_action() -> Dictionary:
	return {"type": "friends_update", "friends": snapshot_friends()}



func _resolve_friend_target(name_or_id: String) -> Dictionary:
	name_or_id = str(name_or_id).strip_edges()
	if name_or_id.is_empty():
		return {"ok": false, "reason": "invalid", "id": "", "name": ""}
	# Direct remote id
	if ctrl._remote_players.has(name_or_id):
		var rd: Dictionary = ctrl._remote_players[name_or_id]
		var rn = str(rd.get("name", name_or_id)).strip_edges()
		return {"ok": true, "id": name_or_id, "name": rn if rn != "" else name_or_id, "reason": ""}
	# Remote by display name
	var rid = ctrl.find_remote_by_name(name_or_id)
	if rid != "":
		var rd2: Dictionary = ctrl.get_remote_player(rid)
		var rn2 = str(rd2.get("name", name_or_id)).strip_edges()
		return {"ok": true, "id": rid, "name": rn2 if rn2 != "" else name_or_id, "reason": ""}
	# Party member by id or name
	for m in ctrl._party_members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid = str(m.get("id", "")).strip_edges()
		var mname = str(m.get("name", "")).strip_edges()
		if mid == name_or_id or mname == name_or_id or mname.to_lower() == name_or_id.to_lower():
			if mid.is_empty():
				mid = "party_%s" % mname
			return {"ok": true, "id": mid, "name": mname if mname != "" else mid, "reason": ""}
	# Known shell remote display names (may be offline / not currently spawned)
	for kn in SHELL_REMOTE_NAMES:
		var kns = str(kn).strip_edges()
		if kns == name_or_id or kns.to_lower() == name_or_id.to_lower():
			return {"ok": true, "id": "known:%s" % kns, "name": kns, "reason": ""}
	return {"ok": false, "reason": "not_found", "id": "", "name": ""}



func try_friend_add(name_or_id: String) -> Dictionary:
	var actions: Array = []
	name_or_id = str(name_or_id).strip_edges()
	if name_or_id.is_empty():
		actions.append({"type": "system_message", "text": "请输入要添加的玩家名字。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.friend_list == null:
		ctrl.friend_list = FriendList.new()
	var resolved: Dictionary = _resolve_friend_target(name_or_id)
	if not bool(resolved.get("ok", false)):
		var reason = str(resolved.get("reason", "not_found"))
		if reason == "invalid":
			actions.append({"type": "system_message", "text": "请输入要添加的玩家名字。"})
		else:
			actions.append({"type": "system_message", "text": "找不到玩家【%s】。" % name_or_id})
		return {"ok": false, "reason": reason, "actions": actions}
	var fid = str(resolved.get("id", ""))
	var fname = str(resolved.get("name", ""))
	var add_r: Dictionary = ctrl.friend_list.try_add(fid, fname)
	if not bool(add_r.get("ok", false)):
		var r2 = str(add_r.get("reason", ""))
		if r2 == "duplicate":
			actions.append({"type": "system_message", "text": "【%s】已经是你好友了。" % fname})
			actions.append(_friends_update_action())
			return {"ok": false, "reason": "duplicate", "actions": actions}
		if r2 == "full":
			actions.append({"type": "system_message", "text": "好友列表已满（最多 %d 人）。" % ctrl.friend_list.max_friends()})
			return {"ok": false, "reason": "full", "actions": actions}
		actions.append({"type": "system_message", "text": "无法添加好友。"})
		return {"ok": false, "reason": r2 if r2 != "" else "failed", "actions": actions}
	actions.append(_friends_update_action())
	actions.append({"type": "system_message", "text": "已添加好友【%s】。" % fname})
	return {"ok": true, "actions": actions}



func try_friend_remove(friend_id: String) -> Dictionary:
	var actions: Array = []
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的好友。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.friend_list == null:
		actions.append({"type": "system_message", "text": "好友列表不可用。"})
		return {"ok": false, "reason": "no_list", "actions": actions}
	var fname = friend_id
	var idx: int = ctrl.friend_list.find_index_by_id(friend_id)
	if idx >= 0 and idx < ctrl.friend_list._friends.size():
		var e: Variant = ctrl.friend_list._friends[idx]
		if typeof(e) == TYPE_DICTIONARY:
			fname = str(e.get("name", friend_id))
	var rem: Dictionary = ctrl.friend_list.try_remove(friend_id)
	if not bool(rem.get("ok", false)):
		actions.append({"type": "system_message", "text": "好友列表中没有该玩家。"})
		return {"ok": false, "reason": str(rem.get("reason", "not_found")), "actions": actions}
	actions.append(_friends_update_action())
	actions.append({"type": "system_message", "text": "已删除好友【%s】。" % fname})
	return {"ok": true, "actions": actions}



