extends RefCounted
## Domain module: party (create/invite/leave/kick/loot-rolls/summon/quest&kill share).

var ctrl
func _init(c):
	ctrl = c

const LOOT_ROLL_WINDOW_SEC: float = 15.0
const PARTY_SUMMON_WINDOW_SEC: float = 30.0

func _maybe_party_food_share(item_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	item_id = item_id.strip_edges()
	if item_id.is_empty() or ctrl.item_catalog == null:
		return
	var def: Dictionary = ctrl.item_catalog.get_item(item_id)
	if def.is_empty() or not bool(def.get("party_share", false)):
		return
	var st_v: Variant = def.get("status", {})
	if typeof(st_v) != TYPE_DICTIONARY or (st_v as Dictionary).is_empty():
		return
	var st: Dictionary = (st_v as Dictionary).duplicate(true)
	var sid = str(st.get("id", "")).strip_edges()
	if sid.is_empty():
		return
	if not in_party() or _party_online_same_map_count() <= 1:
		return
	var party_dur: float = float(def.get("party_duration", 90.0))
	if party_dur <= 0.0:
		party_dur = 90.0
	st["duration"] = party_dur
	var acts_v: Variant = result.get("actions", [])
	var actions: Array = acts_v if typeof(acts_v) == TYPE_ARRAY else []
	if ctrl.combat_stats != null and ctrl.combat_stats.statuses != null:
		ctrl.combat_stats.statuses.apply_status("player", st, party_dur, "player")
		actions.append(ctrl.combat_stats.statuses.status_update_action("player"))
	actions.append({
		"type": "party_buff",
		"item_id": item_id,
		"status_id": sid,
		"duration": party_dur,
	})
	var iname = str(def.get("name", item_id))
	if item_id == "food_party_ration" or iname == "队伍干粮":
		actions.append({"type": "system_message", "text": "队伍干粮：全员士气提升。"})
	else:
		actions.append({"type": "system_message", "text": "与队伍分享了宴席。"})
	result["actions"] = actions



func _maybe_party_skill_share(skill_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty() or ctrl.skill_catalog == null:
		return
	var def: Dictionary = ctrl.skill_catalog.get_skill(skill_id)
	if def.is_empty() or not bool(def.get("party_share", false)):
		return
	var st_v: Variant = def.get("status", {})
	if typeof(st_v) != TYPE_DICTIONARY or (st_v as Dictionary).is_empty():
		return
	var st: Dictionary = (st_v as Dictionary).duplicate(true)
	var sid = str(st.get("id", "")).strip_edges()
	if sid.is_empty():
		return
	if not in_party() or _party_online_same_map_count() <= 1:
		return
	var party_dur: float = float(def.get("party_duration", float(st.get("duration", 15.0))))
	if party_dur <= 0.0:
		party_dur = float(st.get("duration", 15.0))
	if party_dur <= 0.0:
		party_dur = 15.0
	st["duration"] = party_dur
	var acts_v: Variant = result.get("actions", [])
	var actions: Array = acts_v if typeof(acts_v) == TYPE_ARRAY else []
	if ctrl.combat_stats != null and ctrl.combat_stats.statuses != null:
		ctrl.combat_stats.statuses.apply_status("player", st, party_dur, "player")
		actions.append(ctrl.combat_stats.statuses.status_update_action("player"))
	actions.append({
		"type": "party_buff",
		"skill_id": skill_id,
		"status_id": sid,
		"duration": party_dur,
	})
	var sname = str(def.get("name", skill_id))
	if skill_id == "battle_shout" or sname == "战吼":
		actions.append({"type": "system_message", "text": "战吼：全队攻击提升！"})
	else:
		actions.append({"type": "system_message", "text": "与队伍分享了增益。"})
	result["actions"] = actions



func _party_quest_share_eligible() -> bool:
	return in_party() and _party_online_same_map_count() > 1



func _party_quest_share_result(changed: bool) -> Array:
	var actions: Array = []
	if not changed:
		return actions
	actions.append(ctrl._quest_update_action())
	actions.append({"type": "system_message", "text": "队伍协作：任务进度 +1"})
	return actions



func note_party_kill(npc_kind: String) -> Array:
	npc_kind = npc_kind.strip_edges()
	if npc_kind.is_empty() or ctrl.quest_journal == null or not _party_quest_share_eligible():
		return []
	return _party_quest_share_result(bool(ctrl.quest_journal.note_kill(npc_kind)))



func note_party_gather(gather_id: String, qty: int = 1) -> Array:
	gather_id = gather_id.strip_edges()
	qty = maxi(qty, 0)
	if gather_id.is_empty() or qty <= 0 or ctrl.quest_journal == null or not _party_quest_share_eligible():
		return []
	var changed = false
	if ctrl.quest_journal.has_method("note_gather"):
		changed = bool(ctrl.quest_journal.note_gather(gather_id, qty))
	else:
		changed = bool(ctrl.quest_journal.note_item_gain(gather_id, qty))
	return _party_quest_share_result(changed)



func note_party_fish(item_id: String = "", qty: int = 1) -> Array:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 0)
	if qty <= 0 or ctrl.quest_journal == null or not _party_quest_share_eligible():
		return []
	if not ctrl.quest_journal.has_method("note_fish"):
		return []
	return _party_quest_share_result(bool(ctrl.quest_journal.note_fish(item_id, qty)))



func snapshot_party() -> Dictionary:
	var pending: Array = []
	for inv in ctrl._party_invites:
		if typeof(inv) != TYPE_DICTIONARY:
			continue
		pending.append({
			"id": str(inv.get("id", "")),
			"name": str(inv.get("name", "")),
			"outgoing": bool(inv.get("outgoing", true)),
			"from": str(inv.get("from", "")),
		})
	return {
		"party_id": ctrl.party_id,
		"leader": ctrl.party_leader_id,
		"members": ctrl._party_members.duplicate(true),
		"shared_target_id": ctrl.party_shared_target_id,
		"shared_target_name": ctrl.party_shared_target_name,
		"loot_mode": ctrl.party_loot_mode if ctrl.party_loot_mode.strip_edges() != "" else "ffa",
		"pending_invites": pending,
	}



func in_party() -> bool:
	return ctrl.party_id.strip_edges() != "" and not ctrl._party_members.is_empty()



func _party_online_same_map_count() -> int:
	if not in_party():
		return 0
	var n = 0
	for m in ctrl._party_members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not bool(m.get("online", true)):
			continue
		var mid_map = str(m.get("map_id", "")).strip_edges()
		if mid_map != "" and mid_map != ctrl.map_pack_id:
			continue
		n += 1
	return n



func _party_kill_exp_with_bonus(base: int, online_n: int = -1) -> int:
	base = maxi(base, 0)
	if base <= 0:
		return 0
	var n: int = online_n
	if n < 0:
		n = _party_online_same_map_count() if in_party() else 1
	if n <= 1:
		return base
	var extras: int = mini(n - 1, 5)
	# Integer form of floor(base * (1 + 0.05*extras)) = (base * (100 + 5*extras)) // 100
	return maxi(1, int((base * (100 + 5 * extras)) / 100))



func _party_online_same_map_ids() -> Array:
	var out: Array = []
	if not in_party():
		return out
	for m in ctrl._party_members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not bool(m.get("online", true)):
			continue
		var mid_map = str(m.get("map_id", "")).strip_edges()
		if mid_map != "" and mid_map != ctrl.map_pack_id:
			continue
		var mid = str(m.get("id", "")).strip_edges()
		if mid.is_empty():
			continue
		out.append(mid)
	return out



func _party_assign_kill_loot_owner() -> String:
	if not in_party():
		return ""
	var mode = ctrl.party_loot_mode.strip_edges().to_lower()
	if mode == "" or mode == "ffa" or mode == "need_greed" or mode == "roll":
		return ""
	if mode == "leader":
		return ctrl.party_leader_id.strip_edges()
	if mode == "round_robin":
		var ids: Array = _party_online_same_map_ids()
		if ids.is_empty():
			return ""
		var n: int = ids.size()
		var idx: int = posmod(ctrl._party_loot_rr_index, n)
		var oid = str(ids[idx])
		ctrl._party_loot_rr_index += 1
		return oid
	return ""



func try_party_set_loot_mode(mode: String) -> Dictionary:
	var actions: Array = []
	mode = str(mode).strip_edges().to_lower()
	if mode == "roll":
		mode = "need_greed"
	if mode not in ["ffa", "leader", "round_robin", "need_greed"]:
		actions.append({"type": "system_message", "text": "无效的拾取模式。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if not in_party():
		actions.append({"type": "system_message", "text": "你不在队伍中。"})
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	if ctrl.party_leader_id != _party_self_id():
		actions.append({"type": "system_message", "text": "只有队长可以更改拾取模式。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	ctrl.party_loot_mode = mode
	if mode == "round_robin":
		ctrl._party_loot_rr_index = maxi(ctrl._party_loot_rr_index, 0)
	actions.append(_party_update_action())
	var label = "自由拾取"
	match mode:
		"leader":
			label = "队长分配"
		"round_robin":
			label = "轮流拾取"
		"need_greed":
			label = "需求/贪婪"
		_:
			label = "自由拾取"
	actions.append({"type": "system_message", "text": "队伍拾取模式：%s" % label})
	_mark_party_poll()
	return {"ok": true, "loot_mode": mode, "actions": actions}



func _party_member_display_name(member_id: String) -> String:
	member_id = member_id.strip_edges()
	if member_id.is_empty():
		return "?"
	var idx = _party_find_member_index(member_id)
	if idx >= 0:
		var nm = str((ctrl._party_members[idx] as Dictionary).get("name", "")).strip_edges()
		if nm != "":
			return nm
	if member_id == _party_self_id() or member_id == "player":
		return "你"
	return member_id



func _start_party_loot_rolls(cell: Dictionary, pending_items: Array, npc_id: String, source: String, eligible: Array) -> Array:
	var actions: Array = []
	for it_v in pending_items:
		if typeof(it_v) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_v
		var iid = str(it.get("item_id", "")).strip_edges()
		var qty: int = int(it.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		actions.append_array(_start_party_loot_roll(cell, iid, qty, npc_id, source, eligible))
	return actions



func _start_party_loot_roll(cell: Dictionary, item_id: String, qty: int, npc_id: String, source: String, eligible: Array) -> Array:
	var actions: Array = []
	var rid = "lr_%d" % ctrl._next_loot_roll_seq
	ctrl._next_loot_roll_seq += 1
	var elig: Array = []
	for e in eligible:
		var mid = str(e).strip_edges()
		if mid != "" and mid not in elig:
			elig.append(mid)
	var now = ctrl._loot_roll_now()
	ctrl._loot_rolls[rid] = {
		"id": rid,
		"item_id": item_id,
		"qty": qty,
		"cell": {"x": int(cell.get("x", ctrl.player_cell.x)), "y": int(cell.get("y", ctrl.player_cell.y))},
		"npc_id": str(npc_id),
		"source": str(source),
		"eligible": elig,
		"choices": {},
		"expires_at": now + LOOT_ROLL_WINDOW_SEC,
		"resolved": false,
		"created_at": now,
	}
	var iname = ctrl.item_display_name(item_id) if ctrl.has_method("item_display_name") else item_id
	actions.append({"type": "system_message", "text": "开始掷骰：%s" % iname})
	actions.append({
		"type": "loot_roll_start",
		"roll_id": rid,
		"item_id": item_id,
		"qty": qty,
		"name": iname,
		"expires_at": now + LOOT_ROLL_WINDOW_SEC,
		"eligible": elig.duplicate(),
	})
	return actions



func _party_update_action() -> Dictionary:
	ctrl._party_poll_pending = false
	return {"type": "party_update", "party": snapshot_party()}



func _mark_party_poll() -> void:
	ctrl._party_poll_pending = true



func _party_self_id() -> String:
	var aid = ctrl._session_character_id.strip_edges()
	if aid != "":
		return aid
	if ctrl.combat_stats != null:
		var pa = str(ctrl.combat_stats.player_actor_id).strip_edges()
		if pa != "":
			return pa
	return "player"



func _party_self_name() -> String:
	var sid = _party_self_id()
	if ctrl._session_user != "" and ctrl._accounts.has(ctrl._session_user):
		for c in ctrl._accounts[ctrl._session_user]["characters"]:
			if str(c.get("id", "")) == sid:
				var n = str(c.get("name", "")).strip_edges()
				if n != "":
					return n
	return "你"



func _party_self_hp() -> Dictionary:
	var hp = 100
	var hp_max = 100
	if ctrl.combat_stats != null and not ctrl.combat_stats.player.is_empty():
		hp = int(ctrl.combat_stats.player.get("hp", 100))
		hp_max = int(ctrl.combat_stats.player.get("hp_max", maxi(hp, 1)))
	return {"hp": hp, "hp_max": maxi(hp_max, 1)}



func _party_member_statuses(member_id: String) -> Array:
	## Self: live snapshot from combat_stats. Stubs: statuses stored on member dict.
	var mid = member_id.strip_edges()
	var self_id = _party_self_id()
	if mid == self_id or mid == "player":
		if ctrl.combat_stats != null and ctrl.combat_stats.statuses != null:
			return ctrl.combat_stats.statuses.snapshot_statuses("player")
		return []
	var idx = _party_find_member_index(mid)
	if idx >= 0:
		var m: Dictionary = ctrl._party_members[idx]
		var st_v: Variant = m.get("statuses", [])
		if typeof(st_v) == TYPE_ARRAY:
			return (st_v as Array).duplicate(true)
	return []



func _party_statuses_fingerprint(statuses: Array) -> String:
	var parts: PackedStringArray = []
	for s in statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = s
		parts.append("%s:%.1f:%s" % [str(d.get("id", "")), float(d.get("remaining_sec", 0.0)), str(d.get("kind", ""))])
	return "|".join(parts)



func _party_demo_stub_statuses(stub_key: String) -> Array:
	## Light demo buffs so party expand UI is testable without a full remote client.
	var h: int = abs(int(stub_key.hash()))
	var rem_buff: float = 12.0 + float(h % 8)
	var rem_hot: float = 8.0 + float(h % 5)
	return [
		{
			"id": "stub_atk_up",
			"name": "强击",
			"kind": "buff",
			"remaining_sec": rem_buff,
			"duration_max": rem_buff,
			"stacks": 1,
		},
		{
			"id": "stub_regen",
			"name": "再生",
			"kind": "hot",
			"remaining_sec": rem_hot,
			"duration_max": rem_hot,
			"stacks": 1,
			"tick_hp": 2,
		},
	]



func _party_make_self_member() -> Dictionary:
	var hpinfo = _party_self_hp()
	var sid = _party_self_id()
	return {
		"id": sid,
		"name": _party_self_name(),
		"hp": int(hpinfo.get("hp", 100)),
		"hp_max": int(hpinfo.get("hp_max", 100)),
		"online": true,
		"statuses": _party_member_statuses(sid),
	}



func _party_self_hp_fingerprint() -> String:
	var hpinfo = _party_self_hp()
	return "%d/%d" % [int(hpinfo.get("hp", 0)), int(hpinfo.get("hp_max", 0))]



func _party_refresh_self_member() -> bool:
	if not in_party():
		return false
	var self_id = _party_self_id()
	var idx = _party_find_member_index(self_id)
	var fresh = _party_make_self_member()
	var fp = "%d/%d" % [int(fresh.get("hp", 0)), int(fresh.get("hp_max", 0))]
	var st_v: Variant = fresh.get("statuses", [])
	var st_arr: Array = st_v if typeof(st_v) == TYPE_ARRAY else []
	var st_fp = _party_statuses_fingerprint(st_arr)
	if idx < 0:
		ctrl._party_members.insert(0, fresh)
		ctrl._party_last_self_hp_fp = fp
		ctrl._party_last_self_status_fp = st_fp
		return true
	var prev: Dictionary = ctrl._party_members[idx]
	var prev_st_v: Variant = prev.get("statuses", [])
	var prev_st: Array = prev_st_v if typeof(prev_st_v) == TYPE_ARRAY else []
	var changed = (
		int(prev.get("hp", -1)) != int(fresh.get("hp", -2))
		or int(prev.get("hp_max", -1)) != int(fresh.get("hp_max", -2))
		or str(prev.get("name", "")) != str(fresh.get("name", ""))
		or _party_statuses_fingerprint(prev_st) != st_fp
	)
	ctrl._party_members[idx] = fresh
	if changed or fp != ctrl._party_last_self_hp_fp or st_fp != ctrl._party_last_self_status_fp:
		ctrl._party_last_self_hp_fp = fp
		ctrl._party_last_self_status_fp = st_fp
		return true
	return false



func _party_find_member_index(member_id: String) -> int:
	member_id = member_id.strip_edges()
	if member_id.is_empty():
		return -1
	for i in range(ctrl._party_members.size()):
		var m: Variant = ctrl._party_members[i]
		if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) == member_id:
			return i
	return -1



func _party_find_member_by_name(member_name: String) -> int:
	member_name = member_name.strip_edges()
	if member_name.is_empty():
		return -1
	for i in range(ctrl._party_members.size()):
		var m: Variant = ctrl._party_members[i]
		if typeof(m) == TYPE_DICTIONARY and str(m.get("name", "")) == member_name:
			return i
	return -1



func _party_clear() -> void:
	ctrl.party_id = ""
	ctrl.party_leader_id = ""
	ctrl._party_members.clear()
	ctrl.party_shared_target_id = ""
	ctrl.party_shared_target_name = ""
	ctrl.party_loot_mode = "ffa"
	ctrl._party_loot_rr_index = 0
	ctrl._loot_rolls.clear()
	ctrl.loot_roll_rng_fn = Callable()
	ctrl._party_last_self_hp_fp = ""
	ctrl._party_last_self_status_fp = ""
	ctrl._party_invites.clear()
	ctrl._party_summon_pending.clear()
	ctrl.party_summon_auto_accept = false



func _party_make_stub(stub_key: String = "") -> Dictionary:
	if stub_key.strip_edges() == "":
		stub_key = "stub_ally_%d" % ctrl._stub_ally_seq
		ctrl._stub_ally_seq += 1
	var names: Array = ["盟友甲", "盟友乙", "盟友丙", "队友丁"]
	var h: int = int(stub_key.hash())
	if h < 0:
		h = -h
	var idx: int = (ctrl._stub_ally_seq + h) % names.size()
	var hp_max: int = 80 + (h % 5) * 20
	var hp: int = maxi(1, int(float(hp_max) * 0.6) + (h % 20))
	return {
		"id": stub_key,
		"name": names[idx],
		"hp": hp,
		"hp_max": hp_max,
		"online": true,
		"statuses": _party_demo_stub_statuses(stub_key),
	}



func try_party_create() -> Dictionary:
	var actions: Array = []
	if in_party():
		actions.append({"type": "system_message", "text": "你已在队伍中。"})
		actions.append(_party_update_action())
		return {"ok": false, "reason": "already_in_party", "actions": actions}
	ctrl.party_id = "party_%d" % ctrl._next_party_seq
	ctrl._next_party_seq += 1
	ctrl.party_leader_id = _party_self_id()
	ctrl.party_loot_mode = "ffa"
	ctrl._party_loot_rr_index = 0
	ctrl._party_members = [_party_make_self_member()]
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已创建队伍。"})
	actions.append_array(ctrl._note_achievement_counter("party", 1))
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func try_party_invite(target: String = "") -> Dictionary:
	var actions: Array = []
	target = str(target).strip_edges()
	if not in_party():
		# Auto-create so invite works as a shell shortcut.
		var created: Dictionary = try_party_create()
		var ca: Variant = created.get("actions", [])
		if typeof(ca) == TYPE_ARRAY:
			for a in ca:
				# Drop the create tip; invite tip below is clearer.
				if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
					continue
				actions.append(a)
		if not bool(created.get("ok", false)) and not in_party():
			actions.append({"type": "system_message", "text": "无法创建队伍。"})
			return {"ok": false, "reason": "no_party", "actions": actions}
	if ctrl.party_leader_id != _party_self_id():
		actions.append({"type": "system_message", "text": "只有队长可以邀请。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	# Resolve target: existing id/name match → noop; else spawn stub.
	# Prefer matching an existing remote/fake player by id or display name.
	var remote_id = ""
	var remote_name = ""
	if target != "":
		if ctrl._remote_players.has(target):
			remote_id = target
			var rd0: Variant = ctrl._remote_players[target]
			if typeof(rd0) == TYPE_DICTIONARY:
				remote_name = str(rd0.get("name", target))
		else:
			remote_id = ctrl.find_remote_by_name(target)
			if remote_id != "":
				var rd1: Dictionary = ctrl.get_remote_player(remote_id)
				remote_name = str(rd1.get("name", target))
				if remote_name.is_empty():
					remote_name = target
	var stub_id = ""
	if target != "":
		if _party_find_member_index(target) >= 0 or _party_find_member_by_name(target) >= 0:
			actions.append({"type": "system_message", "text": "对方已在队伍中。"})
			actions.append(_party_update_action())
			return {"ok": false, "reason": "already_member", "actions": actions}
		if remote_id != "" and (_party_find_member_index(remote_id) >= 0 or _party_find_member_by_name(remote_name) >= 0):
			actions.append({"type": "system_message", "text": "对方已在队伍中。"})
			actions.append(_party_update_action())
			return {"ok": false, "reason": "already_member", "actions": actions}
		if target.begins_with("stub_ally_"):
			stub_id = target
		elif remote_id != "":
			# Keep remote id as party member id so UI/kick can refer to the fake player.
			stub_id = remote_id
		else:
			# Treat free-form name/id as a new stub id slug.
			stub_id = "stub_ally_%s" % target.to_lower().replace(" ", "_")
	else:
		stub_id = "stub_ally_%d" % ctrl._stub_ally_seq
		ctrl._stub_ally_seq += 1
	if ctrl._party_members.size() >= 8:
		actions.append({"type": "system_message", "text": "队伍已满。"})
		return {"ok": false, "reason": "full", "actions": actions}
	var stub = _party_make_stub(stub_id)
	# Prefer remote display name, else human-readable invite name when provided.
	if remote_name != "":
		stub["name"] = remote_name
	elif target != "" and not target.begins_with("stub_ally_"):
		stub["name"] = target
	var now: float = _party_clock()
	var inv_id = "inv_%d" % ctrl._next_invite_seq
	ctrl._next_invite_seq += 1
	ctrl._party_invites.append({
		"id": inv_id,
		"name": str(stub.get("name", stub_id)),
		"outgoing": true,
		"ready_at": now + 0.35,
		"expires_at": now + 15.0,
		"member": stub,
		"from": _party_self_name(),
	})
	actions.append(_party_update_action())
	actions.append({
		"type": "party_invite",
		"direction": "out",
		"invite_id": inv_id,
		"name": str(stub.get("name", stub_id)),
		"status": "pending",
	})
	actions.append({"type": "system_message", "text": "已向【%s】发出组队邀请。" % str(stub.get("name", stub_id))})
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func _party_clock() -> float:
	return Time.get_ticks_msec() / 1000.0



func _tick_party_invites() -> Array:
	var actions: Array = []
	if ctrl._party_invites.is_empty():
		return actions
	var now: float = _party_clock()
	var keep: Array = []
	for inv_v in ctrl._party_invites:
		if typeof(inv_v) != TYPE_DICTIONARY:
			continue
		var inv: Dictionary = inv_v
		var name = str(inv.get("name", ""))
		if now >= float(inv.get("expires_at", 0.0)):
			actions.append({"type": "system_message", "text": "组队邀请已过期：【%s】" % name})
			actions.append({
				"type": "party_invite",
				"direction": "out" if bool(inv.get("outgoing", true)) else "in",
				"invite_id": str(inv.get("id", "")),
				"name": name,
				"status": "expired",
			})
			continue
		if bool(inv.get("outgoing", true)) and now >= float(inv.get("ready_at", 0.0)):
			var mem: Variant = inv.get("member", {})
			if typeof(mem) == TYPE_DICTIONARY:
				ctrl._party_members.append(mem)
			actions.append(_party_update_action())
			actions.append({
				"type": "party_invite",
				"direction": "out",
				"invite_id": str(inv.get("id", "")),
				"name": name,
				"status": "accepted",
			})
			actions.append({"type": "system_message", "text": "【%s】加入了队伍。" % name})
			continue
		keep.append(inv)
	ctrl._party_invites = keep
	if not actions.is_empty():
		_mark_party_poll()
	return actions



func try_party_invite_respond(invite_id: String, accept: bool) -> Dictionary:
	var actions: Array = []
	invite_id = invite_id.strip_edges()
	var idx = -1
	for i in range(ctrl._party_invites.size()):
		var inv: Variant = ctrl._party_invites[i]
		if typeof(inv) == TYPE_DICTIONARY and str(inv.get("id", "")) == invite_id:
			idx = i
			break
	if idx < 0:
		actions.append({"type": "system_message", "text": "没有这条邀请。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var row: Dictionary = ctrl._party_invites[idx]
	ctrl._party_invites.remove_at(idx)
	var name = str(row.get("name", ""))
	if not bool(row.get("outgoing", true)):
		if accept:
			if not in_party():
				var created: Dictionary = try_party_create()
				var ca: Variant = created.get("actions", [])
				if typeof(ca) == TYPE_ARRAY:
					for a in ca:
						if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
							continue
						actions.append(a)
			var from = str(row.get("from", name))
			var stub = _party_make_stub(str(row.get("id", "stub_leader")))
			stub["name"] = from
			ctrl._party_members.append(stub)
			ctrl.party_leader_id = str(stub.get("id", ""))
			actions.append(_party_update_action())
			actions.append({"type": "system_message", "text": "你加入了【%s】的队伍。" % from})
			actions.append_array(ctrl._note_achievement_counter("party", 1))
		else:
			actions.append({"type": "system_message", "text": "你拒绝了组队邀请。"})
		actions.append({
			"type": "party_invite",
			"direction": "in",
			"invite_id": invite_id,
			"name": name,
			"status": "accepted" if accept else "declined",
		})
		return {"ok": true, "actions": actions}
	if accept:
		var mem: Variant = row.get("member", {})
		if typeof(mem) == TYPE_DICTIONARY:
			ctrl._party_members.append(mem)
		actions.append(_party_update_action())
		actions.append({"type": "system_message", "text": "【%s】加入了队伍。" % name})
	else:
		actions.append({"type": "system_message", "text": "已取消对【%s】的邀请。" % name})
	return {"ok": true, "actions": actions}



func try_party_incoming_invite(from_name: String = "旅人甲") -> Dictionary:
	var actions: Array = []
	from_name = str(from_name).strip_edges()
	if from_name.is_empty():
		from_name = "旅人甲"
	var inv_id = "inv_%d" % ctrl._next_invite_seq
	ctrl._next_invite_seq += 1
	var now: float = _party_clock()
	ctrl._party_invites.append({
		"id": inv_id,
		"name": from_name,
		"outgoing": false,
		"ready_at": now + 9999.0,
		"expires_at": now + 15.0,
		"from": from_name,
	})
	actions.append({
		"type": "party_invite",
		"direction": "in",
		"invite_id": inv_id,
		"name": from_name,
		"status": "pending",
		"expires_in": 15.0,
	})
	actions.append({"type": "system_message", "text": "【%s】邀请你加入队伍。" % from_name})
	return {"ok": true, "actions": actions}



func try_party_leave() -> Dictionary:
	var actions: Array = []
	if not in_party():
		actions.append({"type": "system_message", "text": "你不在队伍中。"})
		actions.append(_party_update_action())
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	var self_id = _party_self_id()
	var was_leader = ctrl.party_leader_id == self_id
	var idx = _party_find_member_index(self_id)
	if idx >= 0:
		ctrl._party_members.remove_at(idx)
	# Shell: leaving dissolves the local party (stubs vanish with you).
	_party_clear()
	actions.append(_party_update_action())
	if was_leader:
		actions.append({"type": "system_message", "text": "你已离开队伍（队长离队，队伍解散）。"})
	else:
		actions.append({"type": "system_message", "text": "你已离开队伍。"})
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func try_party_kick(member_id: String = "") -> Dictionary:
	var actions: Array = []
	member_id = str(member_id).strip_edges()
	if not in_party():
		actions.append({"type": "system_message", "text": "你不在队伍中。"})
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	if ctrl.party_leader_id != _party_self_id():
		actions.append({"type": "system_message", "text": "只有队长可以踢人。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	if member_id.is_empty():
		actions.append({"type": "system_message", "text": "未指定队员。"})
		return {"ok": false, "reason": "no_target", "actions": actions}
	if member_id == _party_self_id():
		actions.append({"type": "system_message", "text": "不能踢出自己，请使用离开队伍。"})
		return {"ok": false, "reason": "self", "actions": actions}
	var idx = _party_find_member_index(member_id)
	if idx < 0:
		idx = _party_find_member_by_name(member_id)
	if idx < 0:
		actions.append({"type": "system_message", "text": "队伍中没有该队员。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var kicked: Dictionary = ctrl._party_members[idx]
	var kname = str(kicked.get("name", member_id))
	ctrl._party_members.remove_at(idx)
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已将【%s】移出队伍。" % kname})
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func try_party_debug_fill() -> Dictionary:
	var actions: Array = []
	if not in_party():
		var created: Dictionary = try_party_create()
		var ca: Variant = created.get("actions", [])
		if typeof(ca) == TYPE_ARRAY:
			for a in ca:
				if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
					continue
				actions.append(a)
		if not in_party():
			actions.append({"type": "system_message", "text": "调试组队失败。"})
			return {"ok": false, "reason": "create_failed", "actions": actions}
	# Count non-self members.
	var self_id = _party_self_id()
	var others = 0
	for m in ctrl._party_members:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) != self_id:
			others += 1
	var want = 2
	var added: Array = []
	while others < want and ctrl._party_members.size() < 8:
		var stub = _party_make_stub()
		# Avoid id collision.
		if _party_find_member_index(str(stub.get("id", ""))) >= 0:
			continue
		ctrl._party_members.append(stub)
		added.append(str(stub.get("name", stub.get("id", ""))))
		others += 1
	actions.append(_party_update_action())
	if added.is_empty():
		actions.append({"type": "system_message", "text": "调试队伍已就绪。"})
	else:
		actions.append({"type": "system_message", "text": "调试组队：加入 %s。" % "、".join(added)})
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func try_party_set_target(npc_id: String = "", display_name: String = "") -> Dictionary:
	var actions: Array = []
	npc_id = str(npc_id).strip_edges()
	display_name = str(display_name).strip_edges()
	if not in_party():
		actions.append({"type": "system_message", "text": "不在队伍中，无法共享目标。"})
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	if ctrl.party_leader_id != _party_self_id():
		# Non-leader: still allow assist mark in shell so click-to-share works for the local player.
		pass
	if npc_id.is_empty():
		return try_party_clear_target()
	var same = ctrl.party_shared_target_id == npc_id
	ctrl.party_shared_target_id = npc_id
	if display_name.is_empty():
		display_name = npc_id
	ctrl.party_shared_target_name = display_name
	_party_refresh_self_member()
	actions.append(_party_update_action())
	if not same:
		actions.append({"type": "system_message", "text": "队伍目标：%s" % ctrl.party_shared_target_name})
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func try_party_clear_target() -> Dictionary:
	var actions: Array = []
	if not in_party():
		ctrl.party_shared_target_id = ""
		ctrl.party_shared_target_name = ""
		return {"ok": true, "actions": actions}
	if ctrl.party_shared_target_id.is_empty() and ctrl.party_shared_target_name.is_empty():
		actions.append(_party_update_action())
		return {"ok": true, "actions": actions}
	ctrl.party_shared_target_id = ""
	ctrl.party_shared_target_name = ""
	_party_refresh_self_member()
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已清除队伍目标。"})
	_mark_party_poll()
	return {"ok": true, "actions": actions}



func snapshot_party_summon() -> Dictionary:
	if ctrl._party_summon_pending.is_empty():
		return {"active": false}
	return {
		"active": true,
		"id": str(ctrl._party_summon_pending.get("id", "")),
		"caster_id": str(ctrl._party_summon_pending.get("caster_id", "")),
		"caster_cell": (ctrl._party_summon_pending.get("caster_cell", {}) as Dictionary).duplicate(true) if typeof(ctrl._party_summon_pending.get("caster_cell", {})) == TYPE_DICTIONARY else {},
		"map_id": str(ctrl._party_summon_pending.get("map_id", "")),
		"invites": (ctrl._party_summon_pending.get("invites", {}) as Dictionary).duplicate(true) if typeof(ctrl._party_summon_pending.get("invites", {})) == TYPE_DICTIONARY else {},
		"expires_at": float(ctrl._party_summon_pending.get("expires_at", 0.0)),
	}



func _try_party_summon_item(item_id: String, def: Dictionary) -> Dictionary:
	var actions: Array = []
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		item_id = "party_summon"
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.inventory == null or not ctrl.inventory.has_item(item_id, 1):
		actions.append({"type": "system_message", "text": "背包中没有该物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	if ctrl.combat_stats != null and not ctrl.combat_stats.is_item_ready(item_id):
		actions.append({"type": "system_message", "text": "物品冷却中。"})
		return {"ok": false, "reason": "cooldown", "actions": actions}
	if not in_party() or _party_online_same_map_count() <= 1:
		actions.append({"type": "system_message", "text": "需要队伍。"})
		return {"ok": false, "reason": "need_party", "actions": actions}
	if ctrl.player_cell.x <= -9990:
		actions.append({"type": "system_message", "text": "没有空余位置。"})
		return {"ok": false, "reason": "no_cell", "actions": actions}
	var free: Array = _party_summon_list_free_cells(ctrl.player_cell.x, ctrl.player_cell.y, {})
	if free.is_empty():
		actions.append({"type": "system_message", "text": "没有空余位置。"})
		return {"ok": false, "reason": "no_space", "actions": actions}
	var self_id = _party_self_id()
	var targets: Array = []
	for m in ctrl._party_members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid = str(m.get("id", "")).strip_edges()
		if mid.is_empty() or mid == self_id:
			continue
		if not bool(m.get("online", true)):
			continue
		var mid_map = str(m.get("map_id", "")).strip_edges()
		if mid_map != "" and mid_map != ctrl.map_pack_id:
			continue
		targets.append(m)
	if targets.is_empty():
		actions.append({"type": "system_message", "text": "需要队伍。"})
		return {"ok": false, "reason": "need_party", "actions": actions}
	if not ctrl.inventory.consume(item_id, 1):
		actions.append({"type": "system_message", "text": "背包中没有该物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var cd: float = float(def.get("cooldown", 60.0))
	if ctrl.combat_stats != null:
		ctrl.combat_stats.set_item_cooldown(item_id, cd)
	var summon_id = "psum_%d" % ctrl._next_party_summon_seq
	ctrl._next_party_summon_seq += 1
	var invites: Dictionary = {}
	var invite_ids: Array = []
	for t in targets:
		var tid = str(t.get("id", "")).strip_edges()
		var tname = str(t.get("name", tid)).strip_edges()
		invites[tid] = {"name": tname, "accepted": false}
		invite_ids.append(tid)
	var expires_at: float = 0.0
	if ctrl.combat_stats != null:
		expires_at = float(ctrl.combat_stats.now_sec()) + PARTY_SUMMON_WINDOW_SEC
	ctrl._party_summon_pending = {
		"id": summon_id,
		"caster_id": self_id,
		"caster_cell": {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y},
		"map_id": ctrl.map_pack_id,
		"invites": invites,
		"expires_at": expires_at,
	}
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold() if ctrl.inventory.has_method("get_gold") else 0,
	})
	actions.append({"type": "system_message", "text": "发出了集结。"})
	actions.append({
		"type": "party_summon",
		"summon_id": summon_id,
		"members": invite_ids.duplicate(),
	})
	if ctrl.party_summon_auto_accept:
		for mid2 in invite_ids:
			var ar: Dictionary = try_party_summon_accept(str(mid2))
			var aa: Variant = ar.get("actions", [])
			if typeof(aa) == TYPE_ARRAY:
				for a in aa:
					actions.append(a)
	return {"ok": true, "summon_id": summon_id, "actions": actions}



func _party_summon_list_free_cells(cx: int, cy: int, reserved: Dictionary) -> Array:
	var out: Array = []
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var x: int = cx + ox
			var y: int = cy + oy
			var key = "%d,%d" % [x, y]
			if reserved.has(key):
				continue
			if not _party_summon_cell_free(x, y):
				continue
			out.append(Vector2i(x, y))
	return out



func _party_summon_cell_free(x: int, y: int) -> bool:
	if ctrl.player_cell.x > -9990 and x == ctrl.player_cell.x and y == ctrl.player_cell.y:
		return false
	if ctrl.map_collision != null:
		if ctrl.map_collision.has_method("is_landable") and not bool(ctrl.map_collision.is_landable(x, y)):
			return false
		if ctrl.map_collision.has_method("is_extra_blocked") and bool(ctrl.map_collision.is_extra_blocked(x, y)):
			return false
	# Occupied by remotes
	for rid in ctrl._remote_players.keys():
		var rd: Variant = ctrl._remote_players[rid]
		if typeof(rd) != TYPE_DICTIONARY:
			continue
		var cell_v: Variant = (rd as Dictionary).get("cell", {})
		if typeof(cell_v) == TYPE_DICTIONARY:
			if int(cell_v.get("x", -9999)) == x and int(cell_v.get("y", -9999)) == y:
				return false
	# Occupied by already-accepted summon landings / party member cells
	for m in ctrl._party_members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mc: Variant = (m as Dictionary).get("cell", {})
		if typeof(mc) == TYPE_DICTIONARY:
			if int(mc.get("x", -9999)) == x and int(mc.get("y", -9999)) == y:
				return false
	if not ctrl._party_summon_pending.is_empty():
		var inv_v: Variant = ctrl._party_summon_pending.get("invites", {})
		if typeof(inv_v) == TYPE_DICTIONARY:
			for _ik in (inv_v as Dictionary).keys():
				var inv: Variant = (inv_v as Dictionary)[_ik]
				if typeof(inv) != TYPE_DICTIONARY:
					continue
				if not bool((inv as Dictionary).get("accepted", false)):
					continue
				var ic: Variant = (inv as Dictionary).get("cell", {})
				if typeof(ic) == TYPE_DICTIONARY:
					if int(ic.get("x", -9999)) == x and int(ic.get("y", -9999)) == y:
						return false
	return true



func try_party_summon_accept(member_id: String = "") -> Dictionary:
	var actions: Array = []
	member_id = str(member_id).strip_edges()
	if ctrl._party_summon_pending.is_empty():
		actions.append({"type": "system_message", "text": "没有进行中的集结。"})
		return {"ok": false, "reason": "no_pending", "actions": actions}
	if ctrl.combat_stats != null:
		var now: float = float(ctrl.combat_stats.now_sec())
		if now > float(ctrl._party_summon_pending.get("expires_at", 0.0)) + 0.001:
			ctrl._party_summon_pending.clear()
			actions.append({"type": "system_message", "text": "集结已过期。"})
			return {"ok": false, "reason": "expired", "actions": actions}
	var invites_v: Variant = ctrl._party_summon_pending.get("invites", {})
	if typeof(invites_v) != TYPE_DICTIONARY:
		actions.append({"type": "system_message", "text": "没有进行中的集结。"})
		return {"ok": false, "reason": "no_pending", "actions": actions}
	var invites: Dictionary = invites_v
	if member_id.is_empty():
		# Pick first unaccepted invite (debug convenience).
		for k in invites.keys():
			var row0: Variant = invites[k]
			if typeof(row0) == TYPE_DICTIONARY and not bool((row0 as Dictionary).get("accepted", false)):
				member_id = str(k)
				break
	if member_id.is_empty() or not invites.has(member_id):
		actions.append({"type": "system_message", "text": "没有你的集结邀请。"})
		return {"ok": false, "reason": "not_invited", "actions": actions}
	var inv_row: Dictionary = invites[member_id]
	if bool(inv_row.get("accepted", false)):
		actions.append({"type": "system_message", "text": "已响应集结。"})
		return {"ok": false, "reason": "already", "actions": actions}
	var cc_v: Variant = ctrl._party_summon_pending.get("caster_cell", {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y})
	var cx: int = ctrl.player_cell.x
	var cy: int = ctrl.player_cell.y
	if typeof(cc_v) == TYPE_DICTIONARY:
		cx = int(cc_v.get("x", cx))
		cy = int(cc_v.get("y", cy))
	# Prefer live caster cell if still on same map.
	if ctrl.player_cell.x > -9990:
		cx = ctrl.player_cell.x
		cy = ctrl.player_cell.y
	var free: Array = _party_summon_list_free_cells(cx, cy, {})
	if free.is_empty():
		actions.append({"type": "system_message", "text": "没有空余位置。"})
		return {"ok": false, "reason": "no_space", "actions": actions}
	var dest: Vector2i = free[0]
	inv_row["accepted"] = true
	inv_row["cell"] = {"x": dest.x, "y": dest.y}
	invites[member_id] = inv_row
	ctrl._party_summon_pending["invites"] = invites
	_party_summon_apply_member_cell(member_id, dest, actions)
	var mname = str(inv_row.get("name", member_id)).strip_edges()
	if mname.is_empty():
		mname = member_id
	actions.append({"type": "system_message", "text": "%s 响应了集结。" % mname})
	actions.append({
		"type": "party_summon_arrive",
		"summon_id": str(ctrl._party_summon_pending.get("id", "")),
		"member_id": member_id,
		"x": dest.x,
		"y": dest.y,
	})
	_mark_party_poll()
	return {"ok": true, "x": dest.x, "y": dest.y, "actions": actions}



func try_party_summon_decline(member_id: String = "") -> Dictionary:
	var actions: Array = []
	member_id = str(member_id).strip_edges()
	if ctrl._party_summon_pending.is_empty():
		return {"ok": true, "actions": actions}
	var invites_v: Variant = ctrl._party_summon_pending.get("invites", {})
	if typeof(invites_v) != TYPE_DICTIONARY:
		return {"ok": true, "actions": actions}
	var invites: Dictionary = invites_v
	if member_id.is_empty():
		return {"ok": false, "reason": "need_member", "actions": actions}
	if not invites.has(member_id):
		return {"ok": false, "reason": "not_invited", "actions": actions}
	invites.erase(member_id)
	ctrl._party_summon_pending["invites"] = invites
	actions.append({"type": "system_message", "text": "已拒绝集结。"})
	if invites.is_empty():
		ctrl._party_summon_pending.clear()
	return {"ok": true, "actions": actions}



func try_party_summon_accept_all() -> Dictionary:
	var actions: Array = []
	if ctrl._party_summon_pending.is_empty():
		actions.append({"type": "system_message", "text": "没有进行中的集结。"})
		return {"ok": false, "reason": "no_pending", "actions": actions}
	var invites_v: Variant = ctrl._party_summon_pending.get("invites", {})
	if typeof(invites_v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "no_pending", "actions": actions}
	var any_ok = false
	for mid in (invites_v as Dictionary).keys():
		var row: Variant = (invites_v as Dictionary)[mid]
		if typeof(row) == TYPE_DICTIONARY and bool((row as Dictionary).get("accepted", false)):
			continue
		var r: Dictionary = try_party_summon_accept(str(mid))
		var aa: Variant = r.get("actions", [])
		if typeof(aa) == TYPE_ARRAY:
			for a in aa:
				actions.append(a)
		if bool(r.get("ok", false)):
			any_ok = true
	return {"ok": any_ok, "actions": actions}



func _party_summon_apply_member_cell(member_id: String, dest: Vector2i, actions: Array) -> void:
	member_id = member_id.strip_edges()
	var idx = _party_find_member_index(member_id)
	if idx >= 0:
		var m: Dictionary = ctrl._party_members[idx]
		m["cell"] = {"x": dest.x, "y": dest.y}
		ctrl._party_members[idx] = m
		actions.append(_party_update_action())
	if ctrl._remote_players.has(member_id):
		var rd: Dictionary = ctrl._remote_players[member_id]
		# Free old occupancy if we tracked it via extra_blocked — remotes usually not blocked.
		rd["cell"] = {"x": dest.x, "y": dest.y}
		ctrl._remote_players[member_id] = rd
		actions.append({
			"type": "remote_move",
			"player_id": member_id,
			"x": dest.x,
			"y": dest.y,
			"facing": int(rd.get("facing", 2)),
		})



