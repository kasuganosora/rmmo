extends RefCounted
## Domain module: quest journal (accept/abandon/turn-in, dialogue, progress notes).

var ctrl
func _init(c):
	ctrl = c

func try_dialogue_choice(option_id: String = "", option_index: int = -1) -> Dictionary:
	option_id = str(option_id).strip_edges()
	if option_id.begins_with("quest_accept:"):
		var qid = option_id.substr("quest_accept:".length()).strip_edges()
		return try_accept_quest(qid)
	if option_id.begins_with("quest_turn_in:"):
		var qid2 = option_id.substr("quest_turn_in:".length()).strip_edges()
		return try_turn_in_quest(qid2)
	if option_id.begins_with("shop_open:"):
		var sid = option_id.substr("shop_open:".length()).strip_edges()
		return ctrl._try_open_shop_action(sid)
	if option_id == "inn_rest" or option_id.begins_with("inn_rest:"):
		var inn_c = 25
		if option_id.begins_with("inn_rest:"):
			inn_c = int(option_id.substr("inn_rest:".length()).strip_edges())
		return ctrl.try_inn_rest(inn_c)
	# repair / repair:all / repair:all:1 / repair:weapon_main / repair:weapon_main:1
	if option_id == "repair" or option_id.begins_with("repair:"):
		var r_slot = "all"
		var r_cpp = 1
		if option_id.begins_with("repair:"):
			var rest = option_id.substr("repair:".length()).strip_edges()
			var parts: PackedStringArray = rest.split(":")
			if parts.size() >= 1 and str(parts[0]).strip_edges() != "":
				r_slot = str(parts[0]).strip_edges()
			if parts.size() >= 2:
				r_cpp = int(str(parts[1]).strip_edges())
		return ctrl.try_repair(r_slot, r_cpp)
	# enhance / enhance:weapon_main
	if option_id == "enhance" or option_id.begins_with("enhance:"):
		var e_slot = ""
		if option_id.begins_with("enhance:"):
			e_slot = option_id.substr("enhance:".length()).strip_edges()
		elif ctrl.equipment != null:
			# First eligible under max
			for sid2 in ctrl.equipment.SLOT_IDS:
				if not str(ctrl.equipment.get_item_in(sid2)).strip_edges().is_empty():
					if int(ctrl.equipment.get_enhance(sid2)) < int(ctrl.equipment.ENHANCE_MAX):
						e_slot = sid2
						break
		return ctrl.try_enhance(e_slot)
	if ctrl.event_runtime == null:
		return {"ok": false, "actions": []}
	var actions: Array = ctrl.event_runtime.try_event_choice(option_id, option_index)
	return {"ok": true, "actions": actions}



func get_quest_list() -> Array:
	if ctrl.quest_journal == null:
		return []
	return ctrl.quest_journal.get_quest_list()



func snapshot_quest_journal() -> Array:
	return get_quest_list()



func _grant_quest_reward(reward: Dictionary) -> Array:
	var actions: Array = []
	if typeof(reward) != TYPE_DICTIONARY:
		return actions
	var exp_amt: int = maxi(int(reward.get("exp", 0)), 0)
	var gold_amt: int = maxi(int(reward.get("gold", 0)), 0)
	var items_v: Variant = reward.get("items", [])
	if exp_amt > 0 and ctrl.combat_stats != null:
		var summary: Dictionary = ctrl.combat_stats.grant_exp(exp_amt)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", exp_amt)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "获得经验 %d" % exp_amt})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else ctrl.combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				var new_lv: int = int(lv_v)
				actions.append({"type": "level_up", "level": new_lv, "combat": combat_snap})
				actions.append({"type": "system_message", "text": "升级到 Lv.%d！" % new_lv})
			ctrl._append_level_up_sp(actions, summary.get("levels_gained", []))
			actions.append({
				"type": "set_stat",
				"target": "player",
				"hp": int(combat_snap.get("hp", 0)),
				"hp_max": int(combat_snap.get("hp_max", 0)),
				"mp": int(combat_snap.get("mp", 0)),
				"mp_max": int(combat_snap.get("mp_max", 0)),
				"level": int(combat_snap.get("level", 1)),
				"exp": int(combat_snap.get("exp", 0)),
				"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
				"atk": int(combat_snap.get("atk", 0)),
				"def": int(combat_snap.get("def", 0)),
				"attr_points": int(combat_snap.get("attr_points", 0)),
				"attrs": combat_snap.get("attrs", {}),
			})
	var inv_dirty = false
	if gold_amt > 0 and ctrl.inventory != null:
		ctrl.inventory.add_gold(gold_amt)
		inv_dirty = true
		actions.append({"type": "system_message", "text": "获得金币 %d" % gold_amt})
	if typeof(items_v) == TYPE_ARRAY and ctrl.inventory != null:
		for it in items_v:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid = str(it.get("id", it.get("item_id", ""))).strip_edges()
			var qty: int = maxi(int(it.get("qty", 1)), 1)
			if iid.is_empty():
				continue
			var add_r: Dictionary = ctrl._try_add_loot_item(iid, qty)
			var added: int = int(add_r.get("added", 0))
			if added > 0:
				inv_dirty = true
				actions.append({
					"type": "system_message",
					"text": "获得 %s×%d" % [ctrl.item_display_name(iid), added],
				})
	if inv_dirty and ctrl.inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
	return actions



func _build_quest_dialogue_options(npc_id: String) -> Array:
	var out: Array = []
	if ctrl.quest_journal == null:
		return out
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return out
	# Turn-in first (ready), then offers.
	if ctrl.quest_journal.has_method("can_turn_in_to"):
		for q in ctrl.quest_journal.can_turn_in_to(npc_id):
			if typeof(q) != TYPE_DICTIONARY:
				continue
			var qid = str(q.get("id", "")).strip_edges()
			var title = str(q.get("title", qid))
			if qid.is_empty():
				continue
			out.append({"id": "quest_turn_in:%s" % qid, "label": "交付：%s" % title})
	if ctrl.quest_journal.has_method("list_offers_for_npc"):
		for def in ctrl.quest_journal.list_offers_for_npc(npc_id):
			if typeof(def) != TYPE_DICTIONARY:
				continue
			var oid = str(def.get("id", "")).strip_edges()
			var otitle = str(def.get("title", oid))
			if oid.is_empty():
				continue
			out.append({"id": "quest_accept:%s" % oid, "label": "接受：%s" % otitle})
	return out



func _append_quest_offer_blurb(body: String, npc_id: String) -> String:
	if ctrl.quest_journal == null or not ctrl.quest_journal.has_method("list_offers_for_npc"):
		return body
	var offers: Array = ctrl.quest_journal.list_offers_for_npc(npc_id)
	if offers.is_empty():
		return body
	var lines: Array = []
	for def in offers:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var offer = str(def.get("offer_text", "")).strip_edges()
		var title = str(def.get("title", def.get("id", "")))
		if offer.is_empty():
			offer = "有任务可接：%s" % title
		lines.append(offer)
	if lines.is_empty():
		return body
	var blurb = ""
	for i in range(lines.size()):
		if i > 0:
			blurb += "\n"
		blurb += str(lines[i])
	return body + "\n\n" + blurb



func try_accept_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	var actions: Array = []
	if ctrl.quest_journal == null:
		actions.append({"type": "system_message", "text": "任务系统不可用。"})
		return {"ok": false, "reason": "no_journal", "actions": actions}
	var already = false
	var jr: Dictionary = {}
	if ctrl.quest_journal.has_method("try_accept_quest"):
		jr = ctrl.quest_journal.try_accept_quest(quest_id)
		if not bool(jr.get("ok", false)):
			var reason = str(jr.get("reason", "reject"))
			var msg = str(jr.get("message", "")).strip_edges()
			if msg.is_empty():
				msg = "无法接取该任务。"
				if reason == "daily_claimed":
					msg = "今日已领取该日常。"
			actions.append({"type": "system_message", "text": msg})
			return {"ok": false, "reason": reason, "actions": actions}
		already = bool(jr.get("already", false))
	else:
		if ctrl.quest_journal.has_method("is_accepted"):
			already = bool(ctrl.quest_journal.is_accepted(quest_id))
		elif ctrl.quest_journal.get_quest(quest_id):
			already = not ctrl.quest_journal.get_quest(quest_id).is_empty()
		var ok: bool = bool(ctrl.quest_journal.accept_quest(quest_id))
		if not ok:
			actions.append({"type": "system_message", "text": "无法接取该任务。"})
			return {"ok": false, "reason": "reject", "actions": actions}
	# If accepted from the talk-target NPC in the same dialogue, count talk progress.
	var talk_npc = ctrl._dialogue_npc_id
	if talk_npc != "":
		actions.append_array(_quest_note_talk_actions(talk_npc))
	actions.append(_quest_update_action())
	var title = quest_id
	var q: Dictionary = ctrl.quest_journal.get_quest(quest_id)
	if not q.is_empty():
		title = str(q.get("title", quest_id))
	elif ctrl.quest_journal.has_method("get_catalog_entry"):
		var def0: Dictionary = ctrl.quest_journal.get_catalog_entry(quest_id)
		if not def0.is_empty():
			title = str(def0.get("title", quest_id))
	if already:
		actions.append({"type": "system_message", "text": "任务已在日志中：%s" % title})
	else:
		actions.append({"type": "system_message", "text": "已接取任务：%s" % title})
		if ctrl.quest_journal.has_method("get_catalog_entry"):
			var def: Dictionary = ctrl.quest_journal.get_catalog_entry(quest_id)
			var at = str(def.get("accept_text", "")).strip_edges()
			if at != "":
				actions.append({"type": "system_message", "text": at})
	return {"ok": true, "quest_id": quest_id, "actions": actions}



func try_abandon_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	var actions: Array = []
	if ctrl.quest_journal == null:
		actions.append({"type": "system_message", "text": "任务系统不可用。"})
		return {"ok": false, "reason": "no_journal", "actions": actions}
	var title = quest_id
	var before: Dictionary = ctrl.quest_journal.get_quest(quest_id)
	if not before.is_empty():
		title = str(before.get("title", quest_id))
	var r: Dictionary = ctrl.quest_journal.try_abandon_quest(quest_id)
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "fail"))
		var msg = "无法放弃任务。"
		match reason:
			"completed":
				msg = "已完成的任务无法放弃。"
			"not_accepted":
				msg = "未接取该任务。"
			_:
				msg = "无法放弃任务（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	actions.append(_quest_update_action())
	actions.append({"type": "system_message", "text": "已放弃任务：%s" % title})
	return {"ok": true, "quest_id": quest_id, "actions": actions}



func try_turn_in_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if ctrl.quest_journal == null:
		return {"ok": false, "reason": "no_journal", "actions": [{"type": "system_message", "text": "任务系统不可用。"}]}
	var title = quest_id
	var q_before: Dictionary = ctrl.quest_journal.get_quest(quest_id)
	if not q_before.is_empty():
		title = str(q_before.get("title", quest_id))
	elif ctrl.quest_journal.has_method("get_catalog_entry"):
		var def_ti: Dictionary = ctrl.quest_journal.get_catalog_entry(quest_id)
		if not def_ti.is_empty():
			title = str(def_ti.get("title", quest_id))
	var r: Dictionary = ctrl.quest_journal.try_turn_in(quest_id)
	var actions: Array = []
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "fail"))
		var msg = "无法交付任务。"
		match reason:
			"not_ready":
				msg = "任务目标尚未完成。"
			"already_completed":
				msg = "该任务已完成。"
			"not_accepted":
				msg = "未接取该任务。"
			_:
				msg = "无法交付任务（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var reward: Dictionary = r.get("reward", {}) if typeof(r.get("reward", {})) == TYPE_DICTIONARY else {}
	actions.append_array(_grant_quest_reward(reward))
	actions.append(_quest_update_action())
	actions.append({"type": "system_message", "text": "任务完成：%s" % title})
	return {"ok": true, "quest_id": quest_id, "actions": actions}



func _quest_update_action() -> Dictionary:
	var a = {
		"type": "quest_update",
		"quests": ctrl.quest_journal.snapshot() if ctrl.quest_journal != null else [],
	}
	if ctrl.quest_journal != null and ctrl.quest_journal.has_method("snapshot_daily"):
		var d: Dictionary = ctrl.quest_journal.snapshot_daily()
		a["daily_date"] = str(d.get("daily_date", ""))
		a["daily"] = d.get("daily", []) if typeof(d.get("daily", [])) == TYPE_ARRAY else []
	return a



func _quest_note_kill_actions(npc_id: String) -> Array:
	var actions: Array = []
	if ctrl.quest_journal == null:
		return actions
	if ctrl.quest_journal.note_kill(npc_id):
		actions.append(_quest_update_action())
	return actions



func _quest_note_talk_actions(npc_id: String) -> Array:
	var actions: Array = []
	if ctrl.quest_journal == null:
		return actions
	if ctrl.quest_journal.note_talk(npc_id):
		actions.append(_quest_update_action())
	return actions



func _quest_note_item_actions(item_id: String, qty: int) -> Array:
	var actions: Array = []
	if ctrl.quest_journal == null:
		return actions
	if ctrl.quest_journal.note_item_gain(item_id, qty):
		actions.append(_quest_update_action())
	return actions




func _quest_note_fish_actions(item_id: String = "", qty: int = 1) -> Array:
	var actions: Array = []
	if ctrl.quest_journal == null:
		return actions
	if ctrl.quest_journal.has_method("note_fish") and ctrl.quest_journal.note_fish(item_id, qty):
		actions.append(_quest_update_action())
	return actions



func _quest_note_reach_actions(map_id: String, content_id: String = "", pack_path: String = "") -> Array:
	var actions: Array = []
	if ctrl.quest_journal == null:
		return actions
	if ctrl.quest_journal.note_reach(map_id, content_id, pack_path):
		actions.append(_quest_update_action())
	return actions


