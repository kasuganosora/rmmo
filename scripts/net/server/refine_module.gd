extends RefCounted
## Domain module: item refine (repair, enhance).

var ctrl
func _init(c):
	ctrl = c

func try_repair(slot: String = "", cost_per_point: int = 1) -> Dictionary:
	var actions: Array = []
	slot = str(slot).strip_edges()
	cost_per_point = maxi(int(cost_per_point), 0)
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var do_tools = slot.is_empty() or slot == "all" or slot == "tools"
	var do_equip = slot != "tools"
	if do_equip and ctrl.equipment == null:
		actions.append({"type": "system_message", "text": "无法修理。"})
		return {"ok": false, "reason": "no_equipment", "actions": actions}
	# Preview costs so equip+tools can be paid atomically.
	var eq_points = 0
	var eq_targets: Array = []
	if do_equip and ctrl.equipment != null:
		if slot.is_empty() or slot == "all":
			for sid in ctrl.equipment.SLOT_IDS:
				if not ctrl.equipment.is_empty(sid) and ctrl.equipment.get_durability(sid) < ctrl.equipment.get_durability_max(sid):
					eq_targets.append(sid)
					eq_points += ctrl.equipment.get_durability_max(sid) - ctrl.equipment.get_durability(sid)
		elif ctrl.equipment.SLOT_IDS.has(slot):
			if ctrl.equipment.is_empty(slot):
				actions.append({"type": "system_message", "text": "该部位没有装备。"})
				return {"ok": false, "reason": "empty", "actions": actions}
			if ctrl.equipment.get_durability(slot) >= ctrl.equipment.get_durability_max(slot):
				# May still repair tools if slot was tools-only path — not here.
				pass
			else:
				eq_targets.append(slot)
				eq_points += ctrl.equipment.get_durability_max(slot) - ctrl.equipment.get_durability(slot)
		else:
			actions.append({"type": "system_message", "text": "该部位没有装备。"})
			return {"ok": false, "reason": "invalid_slot", "actions": actions}
	var tool_prev: Dictionary = {}
	var tool_points = 0
	if do_tools and ctrl.inventory.has_method("preview_tool_repair_full"):
		tool_prev = ctrl.inventory.preview_tool_repair_full()
		if bool(tool_prev.get("ok", false)):
			tool_points = int(tool_prev.get("points", 0))
	var total_points = eq_points + tool_points
	if total_points <= 0:
		if slot == "tools":
			actions.append({"type": "system_message", "text": "工具无需修理。"})
		else:
			actions.append({"type": "system_message", "text": "装备无需修理。"})
		return {"ok": false, "reason": "nothing_to_repair", "actions": actions, "cost": 0}
	var cost: int = total_points * cost_per_point
	if cost > 0 and not ctrl.inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions, "cost": cost}
	var repaired: Array = []
	if eq_points > 0 and ctrl.equipment != null:
		for sid_v in eq_targets:
			var sid: String = str(sid_v)
			var before: int = int(ctrl.equipment.get_durability(sid))
			var dmax: int = int(ctrl.equipment.get_durability_max(sid))
			ctrl.equipment._durability[sid] = dmax
			repaired.append({
				"slot": sid,
				"item_id": ctrl.equipment.get_item_in(sid),
				"before": before,
				"after": dmax,
				"max": dmax,
			})
	if tool_points > 0 and ctrl.inventory.has_method("apply_tool_repair_full"):
		var tr: Dictionary = ctrl.inventory.apply_tool_repair_full()
		for row in tr.get("repaired", []):
			repaired.append(row)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	if eq_points > 0:
		actions.append(ctrl._equipment_update_action())
	var spent: int = cost
	var pts: int = total_points
	if slot == "tools":
		actions.append({"type": "system_message", "text": "工具已修理（%d 点，花费 %dG）。" % [pts, spent]})
	elif tool_points > 0 and eq_points > 0:
		actions.append({"type": "system_message", "text": "装备与工具已修理（%d 点，花费 %dG）。" % [pts, spent]})
	elif tool_points > 0:
		actions.append({"type": "system_message", "text": "工具已修理（%d 点，花费 %dG）。" % [pts, spent]})
	elif slot.is_empty() or slot == "all":
		actions.append({"type": "system_message", "text": "装备已全部修理（%d 点，花费 %dG）。" % [pts, spent]})
	else:
		actions.append({"type": "system_message", "text": "装备已修理（%d 点，花费 %dG）。" % [pts, spent]})
	return {
		"ok": true,
		"reason": "",
		"actions": actions,
		"gold_spent": spent,
		"points": pts,
		"repaired": repaired,
	}



func try_enhance(slot: String = "") -> Dictionary:
	var actions: Array = []
	slot = str(slot).strip_edges()
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.equipment == null:
		actions.append({"type": "system_message", "text": "无法强化。"})
		return {"ok": false, "reason": "no_equipment", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if slot.is_empty():
		actions.append({"type": "system_message", "text": "该部位没有装备。"})
		return {"ok": false, "reason": "empty", "actions": actions}
	var r: Dictionary = ctrl.equipment.try_enhance(ctrl.inventory, slot)
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", ""))
		match reason:
			"maxed":
				actions.append({"type": "system_message", "text": "已达强化上限 +%d。" % int(ctrl.equipment.ENHANCE_MAX)})
			"no_stone":
				actions.append({"type": "system_message", "text": "需要强化石。"})
			"no_gold":
				actions.append({"type": "system_message", "text": "金币不足。"})
			"empty", "invalid_slot":
				actions.append({"type": "system_message", "text": "该部位没有装备。"})
			_:
				actions.append({"type": "system_message", "text": "无法强化。"})
		return {
			"ok": false,
			"reason": reason,
			"actions": actions,
			"cost": int(r.get("cost", 0)),
			"enhance": int(r.get("enhance", 0)),
		}
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append(ctrl._equipment_update_action())
	var enh_n: int = int(r.get("enhance", 0))
	var spent: int = int(r.get("gold_spent", 0))
	var iid = str(r.get("item_id", ""))
	var nm = ctrl.item_display_name(iid) if ctrl.has_method("item_display_name") else iid
	actions.append({
		"type": "system_message",
		"text": "强化成功：%s +%d（花费 %dG）。" % [nm, enh_n, spent],
	})
	return {
		"ok": true,
		"reason": "",
		"actions": actions,
		"slot": slot,
		"item_id": iid,
		"enhance": enh_n,
		"enhance_before": int(r.get("enhance_before", 0)),
		"gold_spent": spent,
		"stat_key": str(r.get("stat_key", "")),
	}



