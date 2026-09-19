extends RefCounted
## Domain module: loot (ground bags, loot session, party loot-roll resolution).

var ctrl
func _init(c):
	ctrl = c

func snapshot_ground_bags() -> Array:
	var out: Array = []
	for bid in ctrl._ground_bags.keys():
		out.append(_bag_snapshot(str(bid)))
	return out



func ground_bag_count() -> int:
	return ctrl._ground_bags.size()



func get_ground_bag(bag_id: String) -> Dictionary:
	bag_id = bag_id.strip_edges()
	if bag_id.is_empty() or not ctrl._ground_bags.has(bag_id):
		return {}
	return _bag_snapshot(bag_id)



func has_pending_loot() -> bool:
	return not ctrl._open_loot_bag_id.is_empty() and not ctrl._open_bag_items().is_empty()



func pending_loot_snapshot() -> Dictionary:
	if ctrl._open_loot_bag_id.is_empty() or not ctrl._ground_bags.has(ctrl._open_loot_bag_id):
		return {}
	var bag: Dictionary = ctrl._ground_bags[ctrl._open_loot_bag_id]
	return {
		"session_id": ctrl._open_loot_bag_id,
		"bag_id": ctrl._open_loot_bag_id,
		"npc_id": str(bag.get("npc_id", "")),
		"cell": (bag.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true),
		"items": ctrl._open_bag_items_dup(),
	}



func _ground_bag_now() -> float:
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("now_sec"):
		return float(ctrl.combat_stats.now_sec())
	return float(Time.get_ticks_msec()) / 1000.0



func _bag_loot_owner_blocks(bag: Dictionary) -> bool:
	var oid = str(bag.get("owner_id", "")).strip_edges()
	if oid.is_empty():
		return false
	var created_at: float = float(bag.get("created_at", 0.0))
	# Free after 60s from created_at (same clock as spawn). Age can be large if created_at is old/negative.
	if (_ground_bag_now() - created_at) >= 60.0:
		return false
	var self_id = ctrl._party_self_id()
	if oid == self_id or oid == "player":
		return false
	return true



func _bag_loot_owner_fail_msg(bag: Dictionary) -> String:
	var oid = str(bag.get("owner_id", "")).strip_edges()
	var oname = ""
	var idx = ctrl._party_find_member_index(oid)
	if idx >= 0:
		oname = str((ctrl._party_members[idx] as Dictionary).get("name", "")).strip_edges()
	if oname != "":
		return "该掉落属于【%s】。" % oname
	return "该掉落属于队友。"



func can_loot_ground_bag(bag_id: String) -> bool:
	bag_id = bag_id.strip_edges()
	if bag_id.is_empty() or not ctrl._ground_bags.has(bag_id):
		return false
	return not _bag_loot_owner_blocks(ctrl._ground_bags[bag_id])



func try_open_ground_bag(bag_id: String) -> Dictionary:
	bag_id = bag_id.strip_edges()
	var actions: Array = []
	if ctrl.awaiting_respawn or (ctrl.combat_stats != null and not ctrl.combat_stats.player_alive()):
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if bag_id.is_empty() or not ctrl._ground_bags.has(bag_id):
		actions.append({"type": "system_message", "text": "地上没有该掉落物。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var bag: Dictionary = ctrl._ground_bags[bag_id]
	if _bag_loot_owner_blocks(bag):
		actions.append({"type": "system_message", "text": _bag_loot_owner_fail_msg(bag)})
		return {"ok": false, "reason": "not_owner", "actions": actions}
	var items_v: Variant = bag.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		_remove_ground_bag(bag_id, actions)
		actions.append({"type": "system_message", "text": "掉落物已空。"})
		return {"ok": false, "reason": "empty", "actions": actions}
	var cell: Dictionary = bag.get("cell", {"x": 0, "y": 0})
	var bx: int = int(cell.get("x", 0))
	var by: int = int(cell.get("y", 0))
	if not ctrl._player_adjacent_or_on(bx, by):
		actions.append({"type": "system_message", "text": "离掉落物太远。"})
		return {"ok": false, "reason": "too_far", "actions": actions}
	# Switch open session without destroying previous bag.
	if not ctrl._open_loot_bag_id.is_empty() and ctrl._open_loot_bag_id != bag_id:
		actions.append({"type": "loot_close", "session_id": ctrl._open_loot_bag_id, "bag_id": ctrl._open_loot_bag_id})
	ctrl._open_loot_bag_id = bag_id
	actions.append(_loot_open_action())
	return {"ok": true, "bag_id": bag_id, "actions": actions}



func find_ground_bag_at(x: int, y: int) -> String:
	for bid in ctrl._ground_bags.keys():
		var bag: Dictionary = ctrl._ground_bags[bid]
		var cell: Dictionary = bag.get("cell", {})
		if int(cell.get("x", -99999)) == x and int(cell.get("y", -99999)) == y:
			return str(bid)
	return ""




func _try_add_loot_item(item_id: String, qty: int) -> Dictionary:
	if ctrl.inventory == null:
		return {"ok": false, "added": 0, "reason": "no_inventory"}
	var bound = ctrl._item_binds_on_pickup(item_id)
	return ctrl.inventory.try_add_item(item_id, qty, bound)



func try_loot_take(item_id: String, qty: int = -1) -> Dictionary:
	item_id = item_id.strip_edges()
	var actions: Array = []
	if ctrl.awaiting_respawn or (ctrl.combat_stats != null and not ctrl.combat_stats.player_alive()):
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl._open_loot_bag_id.is_empty() or not ctrl._ground_bags.has(ctrl._open_loot_bag_id):
		actions.append({"type": "system_message", "text": "没有可拾取的掉落。"})
		return {"ok": false, "reason": "no_loot", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inventory", "actions": actions}
	if item_id.is_empty():
		actions.append({"type": "system_message", "text": "无效物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var bag: Dictionary = ctrl._ground_bags[ctrl._open_loot_bag_id]
	if _bag_loot_owner_blocks(bag):
		actions.append({"type": "system_message", "text": _bag_loot_owner_fail_msg(bag)})
		return {"ok": false, "reason": "not_owner", "actions": actions}
	var items: Array = ctrl._open_bag_items()
	var idx: int = -1
	var have: int = 0
	for i in range(items.size()):
		var d: Dictionary = items[i]
		if str(d.get("item_id", "")) == item_id:
			idx = i
			have = int(d.get("qty", 0))
			break
	if idx < 0 or have <= 0:
		actions.append({"type": "system_message", "text": "掉落中没有该物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var want: int = have if qty <= 0 else mini(qty, have)
	var add_r: Dictionary = _try_add_loot_item(item_id, want)
	var added: int = int(add_r.get("added", 0))
	if added <= 0:
		var reason = str(add_r.get("reason", "bag_full"))
		var msg = "背包已满，无法拾取 %s。" % ctrl.item_display_name(item_id)
		if reason == "stack_full":
			msg = "该物品已达堆叠上限，无法拾取 %s。" % ctrl.item_display_name(item_id)
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason if reason != "" else "bag_full", "actions": actions}
	var left: int = have - added
	if left > 0:
		items[idx] = {"item_id": item_id, "qty": left}
	else:
		items.remove_at(idx)
	bag["items"] = items
	ctrl._ground_bags[ctrl._open_loot_bag_id] = bag
	actions.append({
		"type": "system_message",
		"text": "获得 %s×%d" % [ctrl.item_display_name(item_id), added],
	})
	actions.append_array(ctrl._quest_note_item_actions(item_id, added))
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	if items.is_empty():
		var sid = ctrl._open_loot_bag_id
		_remove_ground_bag(sid, actions)
		ctrl._open_loot_bag_id = ""
		actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})
	else:
		actions.append(ctrl._ground_update_action(ctrl._open_loot_bag_id))
		actions.append(_loot_update_action())
	return {"ok": true, "added": added, "item_id": item_id, "actions": actions}



func try_loot_take_all() -> Dictionary:
	var actions: Array = []
	if ctrl.awaiting_respawn or (ctrl.combat_stats != null and not ctrl.combat_stats.player_alive()):
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl._open_loot_bag_id.is_empty() or not ctrl._ground_bags.has(ctrl._open_loot_bag_id):
		actions.append({"type": "system_message", "text": "没有可拾取的掉落。"})
		return {"ok": false, "reason": "no_loot", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inventory", "actions": actions}
	var open_bag_chk: Dictionary = ctrl._ground_bags[ctrl._open_loot_bag_id]
	if _bag_loot_owner_blocks(open_bag_chk):
		actions.append({"type": "system_message", "text": _bag_loot_owner_fail_msg(open_bag_chk)})
		return {"ok": false, "reason": "not_owner", "actions": actions}
	var sid = ctrl._open_loot_bag_id
	var any_ok = false
	var bag_blocked = false
	var pending_ids: Array = []
	for d_v in ctrl._open_bag_items():
		if typeof(d_v) == TYPE_DICTIONARY:
			pending_ids.append(str(d_v.get("item_id", "")))
	for iid in pending_ids:
		if ctrl._open_loot_bag_id.is_empty() or not ctrl._ground_bags.has(ctrl._open_loot_bag_id):
			break
		iid = str(iid).strip_edges()
		if iid.is_empty():
			continue
		var r: Dictionary = try_loot_take(iid, -1)
		var sub: Array = r.get("actions", [])
		for a in sub:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var t = str(a.get("type", ""))
			# Nested take emits update/close/despawn; we emit a single final set.
			if t in ["loot_update", "loot_close", "ground_update", "ground_despawn"]:
				continue
			actions.append(a)
		if bool(r.get("ok", false)):
			any_ok = true
		else:
			var reason = str(r.get("reason", ""))
			if reason in ["bag_full", "stack_full"]:
				bag_blocked = true
	if not ctrl._ground_bags.has(sid) or ctrl._open_bag_items().is_empty():
		if ctrl._ground_bags.has(sid):
			_remove_ground_bag(sid, actions)
		else:
			actions.append({"type": "ground_despawn", "bag_id": sid})
		ctrl._open_loot_bag_id = ""
		actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})
		return {"ok": any_ok, "reason": ("" if any_ok else "empty"), "actions": actions}
	actions.append(ctrl._ground_update_action(sid))
	actions.append(_loot_update_action())
	if not any_ok and bag_blocked:
		return {"ok": false, "reason": "bag_full", "actions": actions}
	return {"ok": any_ok, "actions": actions}



func try_loot_close() -> Dictionary:
	var actions: Array = []
	var sid = ctrl._open_loot_bag_id
	var had = not sid.is_empty() and ctrl._ground_bags.has(sid) and not ctrl._open_bag_items().is_empty()
	ctrl._open_loot_bag_id = ""
	actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})
	if had:
		actions.append({"type": "system_message", "text": "已关闭掉落窗口（物品仍在地上）。"})
	return {"ok": true, "actions": actions}



func _bag_items_dup(bag_id: String) -> Array:
	var out: Array = []
	if not ctrl._ground_bags.has(bag_id):
		return out
	var items_v: Variant = ctrl._ground_bags[bag_id].get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	for d_v in items:
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = d_v
		var iid = str(d.get("item_id", "")).strip_edges()
		var q: int = int(d.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		var row = {"item_id": iid, "qty": q, "name": ctrl.item_display_name(iid)}
		row.merge(ctrl._item_icon_fields(iid))
		out.append(row)
	return out



func _bag_snapshot(bag_id: String) -> Dictionary:
	if not ctrl._ground_bags.has(bag_id):
		return {}
	var bag: Dictionary = ctrl._ground_bags[bag_id]
	return {
		"id": bag_id,
		"cell": (bag.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true),
		"items": _bag_items_dup(bag_id),
		"source": str(bag.get("source", "")),
		"owner_id": str(bag.get("owner_id", "")),
		"npc_id": str(bag.get("npc_id", "")),
		"created_at": float(bag.get("created_at", 0.0)),
	}



func _loot_update_action() -> Dictionary:
	var npc = ""
	if ctrl._ground_bags.has(ctrl._open_loot_bag_id):
		npc = str(ctrl._ground_bags[ctrl._open_loot_bag_id].get("npc_id", ""))
	return {
		"type": "loot_update",
		"session_id": ctrl._open_loot_bag_id,
		"bag_id": ctrl._open_loot_bag_id,
		"npc_id": npc,
		"items": ctrl._open_bag_items_dup(),
	}



func _loot_open_action() -> Dictionary:
	var bag: Dictionary = ctrl._ground_bags.get(ctrl._open_loot_bag_id, {})
	return {
		"type": "loot_open",
		"session_id": ctrl._open_loot_bag_id,
		"bag_id": ctrl._open_loot_bag_id,
		"npc_id": str(bag.get("npc_id", "")),
		"cell": (bag.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true),
		"items": ctrl._open_bag_items_dup(),
	}



func _ground_spawn_action(bag_id: String) -> Dictionary:
	return {"type": "ground_spawn", "bag": _bag_snapshot(bag_id)}



func _remove_ground_bag(bag_id: String, actions: Array) -> void:
	if bag_id.is_empty():
		return
	if ctrl._ground_bags.has(bag_id):
		ctrl._ground_bags.erase(bag_id)
	actions.append({"type": "ground_despawn", "bag_id": bag_id})
	if ctrl._open_loot_bag_id == bag_id:
		ctrl._open_loot_bag_id = ""



func _clear_pending_loot_on_death(actions: Array) -> void:
	if ctrl._open_loot_bag_id.is_empty():
		return
	var sid = ctrl._open_loot_bag_id
	ctrl._open_loot_bag_id = ""
	actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})



func _roll_and_grant_loot(npc_id: String, death_cell: Variant = null) -> Array:
	var actions: Array = []
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.loot_catalog == null:
		return actions
	var charset = ""
	var cell = {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	if typeof(death_cell) == TYPE_DICTIONARY:
		var dcd: Dictionary = death_cell
		cell = {"x": int(dcd.get("x", ctrl.player_cell.x)), "y": int(dcd.get("y", ctrl.player_cell.y))}
	elif typeof(death_cell) == TYPE_VECTOR2I:
		var dcv: Vector2i = death_cell
		if dcv.x > -9990:
			cell = {"x": dcv.x, "y": dcv.y}
	# Charset from spawn template only — NEVER use home_cell for loot placement.
	if ctrl.npc_spawn_templates.has(npc_id):
		var tmpl: Dictionary = ctrl.npc_spawn_templates[npc_id]
		charset = str(tmpl.get("charset", "")).strip_edges()
	var drops: Array = ctrl.loot_catalog.roll(npc_id, charset)
	if drops.is_empty():
		return actions
	var pending_items: Array = []
	for d_v in drops:
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = d_v
		var iid = str(d.get("item_id", "")).strip_edges()
		var qty: int = int(d.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		actions.append({
			"type": "loot_drop",
			"npc_id": npc_id,
			"item_id": iid,
			"qty": qty,
		})
		ctrl._merge_item_into_list(pending_items, iid, qty)
	if pending_items.is_empty():
		return actions
	# need_greed / roll: party N>1 → short roll window instead of immediate owner bag.
	var loot_mode = ctrl.party_loot_mode.strip_edges().to_lower()
	if loot_mode in ["need_greed", "roll"] and ctrl.in_party():
		var eligible: Array = ctrl._party_online_same_map_ids()
		if eligible.size() > 1:
			actions.append_array(ctrl._start_party_loot_rolls(cell, pending_items, npc_id, "monster", eligible))
			return actions
	var loot_owner = ctrl._party_assign_kill_loot_owner()
	actions.append_array(ctrl._add_items_to_ground(cell, pending_items, "monster", npc_id, loot_owner))
	actions.append({"type": "system_message", "text": "地上出现了掉落物。"})
	return actions



func snapshot_loot_rolls() -> Array:
	var out: Array = []
	for rid in ctrl._loot_rolls.keys():
		var r: Dictionary = ctrl._loot_rolls[rid]
		out.append({
			"id": str(r.get("id", "")),
			"item_id": str(r.get("item_id", "")),
			"qty": int(r.get("qty", 1)),
			"expires_at": float(r.get("expires_at", 0.0)),
			"eligible": (r.get("eligible", []) as Array).duplicate(),
			"choices": (r.get("choices", {}) as Dictionary).duplicate(true),
			"resolved": bool(r.get("resolved", false)),
		})
	return out



func loot_roll_count() -> int:
	return ctrl._loot_rolls.size()



func _loot_roll_now() -> float:
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("now_sec"):
		return float(ctrl.combat_stats.now_sec())
	return Time.get_ticks_msec() / 1000.0



func _next_loot_die() -> int:
	if ctrl.loot_roll_rng_fn.is_valid():
		return clampi(int(ctrl.loot_roll_rng_fn.call()), 1, 100)
	return ctrl._loot_roll_rng.randi_range(1, 100)



func debug_start_loot_roll(item_id: String, qty: int = 1, eligible: Array = []) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = maxi(int(qty), 1)
	if item_id.is_empty():
		return {"ok": false, "reason": "empty", "actions": actions}
	if eligible.is_empty():
		eligible = ctrl._party_online_same_map_ids()
	if eligible.size() <= 1:
		# Solo: spawn free for killer/local like skip-roll path.
		var cell = {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
		actions.append_array(ctrl._add_items_to_ground(cell, [{"item_id": item_id, "qty": qty}], "monster", "", ""))
		actions.append({"type": "system_message", "text": "地上出现了掉落物。"})
		return {"ok": true, "skipped": true, "actions": actions}
	var cell2 = {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	actions.append_array(ctrl._start_party_loot_roll(cell2, item_id, qty, "", "monster", eligible))
	var rid = ""
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "loot_roll_start":
			rid = str(a.get("roll_id", ""))
	return {"ok": true, "roll_id": rid, "actions": actions}



func try_loot_roll(choice: String, roll_id: String = "") -> Dictionary:
	return try_loot_roll_for(ctrl._party_self_id(), choice, roll_id)



func try_loot_roll_for(member_id: String, choice: String, roll_id: String = "") -> Dictionary:
	var actions: Array = []
	member_id = str(member_id).strip_edges()
	choice = str(choice).strip_edges().to_lower()
	roll_id = str(roll_id).strip_edges()
	if choice not in ["need", "greed", "pass"]:
		actions.append({"type": "system_message", "text": "无效的掷骰选项。"})
		return {"ok": false, "reason": "invalid_choice", "actions": actions}
	if member_id.is_empty():
		return {"ok": false, "reason": "no_member", "actions": actions}
	if roll_id.is_empty():
		roll_id = _first_open_loot_roll_for(member_id)
	if roll_id.is_empty() or not ctrl._loot_rolls.has(roll_id):
		actions.append({"type": "system_message", "text": "没有进行中的掷骰。"})
		return {"ok": false, "reason": "no_roll", "actions": actions}
	var roll: Dictionary = ctrl._loot_rolls[roll_id]
	if bool(roll.get("resolved", false)):
		return {"ok": false, "reason": "resolved", "actions": actions}
	var eligible_v: Variant = roll.get("eligible", [])
	var eligible: Array = eligible_v if typeof(eligible_v) == TYPE_ARRAY else []
	if member_id not in eligible:
		actions.append({"type": "system_message", "text": "你不能参与此次掷骰。"})
		return {"ok": false, "reason": "not_eligible", "actions": actions}
	var choices: Dictionary = roll.get("choices", {})
	if typeof(choices) != TYPE_DICTIONARY:
		choices = {}
	if choices.has(member_id):
		actions.append({"type": "system_message", "text": "你已经掷过骰了。"})
		return {"ok": false, "reason": "already", "actions": actions}
	var die = 0
	if choice != "pass":
		die = _next_loot_die()
	choices[member_id] = {
		"choice": choice,
		"roll": die,
		"at": _loot_roll_now(),
	}
	roll["choices"] = choices
	ctrl._loot_rolls[roll_id] = roll
	var mname = ctrl._party_member_display_name(member_id)
	if choice == "need":
		actions.append({"type": "system_message", "text": "%s 需求 %d" % [mname, die]})
	elif choice == "greed":
		actions.append({"type": "system_message", "text": "%s 贪婪 %d" % [mname, die]})
	# pass: silent thin
	actions.append({
		"type": "loot_roll_choice",
		"roll_id": roll_id,
		"member_id": member_id,
		"choice": choice,
		"roll": die,
	})
	# Early resolve when everyone has voted.
	if _loot_roll_all_voted(roll):
		actions.append_array(_resolve_loot_roll(roll_id))
	return {"ok": true, "roll_id": roll_id, "choice": choice, "roll": die, "actions": actions}



func _first_open_loot_roll_for(member_id: String) -> String:
	var best = ""
	var best_seq = 1 << 30
	for rid in ctrl._loot_rolls.keys():
		var r: Dictionary = ctrl._loot_rolls[rid]
		if bool(r.get("resolved", false)):
			continue
		var elig_v: Variant = r.get("eligible", [])
		if typeof(elig_v) != TYPE_ARRAY or member_id not in (elig_v as Array):
			continue
		var choices: Dictionary = r.get("choices", {})
		if typeof(choices) == TYPE_DICTIONARY and choices.has(member_id):
			continue
		# Prefer earliest id seq (lr_N)
		var seq = int(str(rid).get_slice("_", 1)) if str(rid).contains("_") else 0
		if best.is_empty() or seq < best_seq:
			best = str(rid)
			best_seq = seq
	return best



func _loot_roll_all_voted(roll: Dictionary) -> bool:
	var elig_v: Variant = roll.get("eligible", [])
	if typeof(elig_v) != TYPE_ARRAY:
		return false
	var choices: Dictionary = roll.get("choices", {})
	if typeof(choices) != TYPE_DICTIONARY:
		return false
	for mid in elig_v:
		if not choices.has(str(mid)):
			return false
	return true



func _tick_loot_rolls() -> Array:
	var actions: Array = []
	if ctrl._loot_rolls.is_empty():
		return actions
	var now = _loot_roll_now()
	var to_resolve: Array = []
	for rid in ctrl._loot_rolls.keys():
		var r: Dictionary = ctrl._loot_rolls[rid]
		if bool(r.get("resolved", false)):
			continue
		if now >= float(r.get("expires_at", 0.0)):
			to_resolve.append(str(rid))
	for rid2 in to_resolve:
		actions.append_array(_resolve_loot_roll(str(rid2)))
	return actions



func debug_force_loot_roll_timeout(roll_id: String = "") -> Dictionary:
	var actions: Array = []
	roll_id = str(roll_id).strip_edges()
	if roll_id != "":
		if not ctrl._loot_rolls.has(roll_id):
			return {"ok": false, "reason": "missing", "actions": actions}
		var r: Dictionary = ctrl._loot_rolls[roll_id]
		r["expires_at"] = _loot_roll_now() - 0.01
		ctrl._loot_rolls[roll_id] = r
		actions.append_array(_resolve_loot_roll(roll_id))
		return {"ok": true, "actions": actions}
	var ids: Array = ctrl._loot_rolls.keys()
	for rid in ids:
		var rr: Dictionary = ctrl._loot_rolls[rid]
		if bool(rr.get("resolved", false)):
			continue
		rr["expires_at"] = _loot_roll_now() - 0.01
		ctrl._loot_rolls[rid] = rr
		actions.append_array(_resolve_loot_roll(str(rid)))
	return {"ok": true, "actions": actions}



func _resolve_loot_roll(roll_id: String) -> Array:
	var actions: Array = []
	roll_id = str(roll_id).strip_edges()
	if roll_id.is_empty() or not ctrl._loot_rolls.has(roll_id):
		return actions
	var roll: Dictionary = ctrl._loot_rolls[roll_id]
	if bool(roll.get("resolved", false)):
		return actions
	# Auto-pass anyone who has not voted.
	var elig_v: Variant = roll.get("eligible", [])
	var eligible: Array = elig_v if typeof(elig_v) == TYPE_ARRAY else []
	var choices: Dictionary = roll.get("choices", {})
	if typeof(choices) != TYPE_DICTIONARY:
		choices = {}
	var now = _loot_roll_now()
	for mid_v in eligible:
		var mid = str(mid_v)
		if not choices.has(mid):
			choices[mid] = {"choice": "pass", "roll": 0, "at": now}
	roll["choices"] = choices
	ctrl._loot_tie_note = ""
	var winner_id = _pick_loot_roll_winner(choices)
	# Tie-break reroll once among tied top group if needed (handled inside pick).
	roll["resolved"] = true
	roll["winner_id"] = winner_id
	ctrl._loot_rolls[roll_id] = roll
	var item_id = str(roll.get("item_id", ""))
	var qty: int = int(roll.get("qty", 1))
	var cell_v: Variant = roll.get("cell", {})
	var cell: Dictionary = cell_v if typeof(cell_v) == TYPE_DICTIONARY else {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	var npc_id = str(roll.get("npc_id", ""))
	var source = str(roll.get("source", "monster"))
	var iname = ctrl.item_display_name(item_id) if ctrl.has_method("item_display_name") else item_id
	var owner_id = winner_id
	actions.append_array(ctrl._add_items_to_ground(cell, [{"item_id": item_id, "qty": qty}], source, npc_id, owner_id))
	if winner_id != "":
		var wname = ctrl._party_member_display_name(winner_id)
		actions.append({"type": "system_message", "text": "%s 获得了 %s" % [wname, iname]})
	if ctrl._loot_tie_note != "":
		actions.append({"type": "system_message", "text": ctrl._loot_tie_note})
		ctrl._loot_tie_note = ""
	else:
		actions.append({"type": "system_message", "text": "%s 无人认领，自由拾取。" % iname})
	actions.append({
		"type": "loot_roll_resolve",
		"roll_id": roll_id,
		"item_id": item_id,
		"qty": qty,
		"winner_id": winner_id,
	})
	ctrl._loot_rolls.erase(roll_id)
	return actions



func _pick_loot_roll_winner(choices: Dictionary) -> String:
	var need_pool: Array = []
	var greed_pool: Array = []
	for mid in choices.keys():
		var row_v: Variant = choices[mid]
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var ch = str(row.get("choice", "")).to_lower()
		if ch == "need":
			need_pool.append({"id": str(mid), "roll": int(row.get("roll", 0)), "at": float(row.get("at", 0.0))})
		elif ch == "greed":
			greed_pool.append({"id": str(mid), "roll": int(row.get("roll", 0)), "at": float(row.get("at", 0.0))})
	var pool: Array = need_pool if not need_pool.is_empty() else greed_pool
	if pool.is_empty():
		return ""
	return ctrl._pick_highest_roll_with_tiebreak(pool)


