extends RefCounted
## Domain module: equipment (equip/unequip/toggle, update action).

var ctrl
func _init(c):
	ctrl = c

const Equipment = preload("res://scripts/net/combat/equipment.gd")

func try_equip_item(item_id: String, slot: String = "") -> Dictionary:
	item_id = item_id.strip_edges()
	slot = slot.strip_edges()
	if ctrl.equipment == null or ctrl.inventory == null:
		return {"ok": false, "reason": "no_equipment", "actions": []}
	var r: Dictionary = ctrl.equipment.try_equip_from_bag(ctrl.inventory, item_id, slot)
	var actions: Array = []
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "fail"))
		var msg = str(r.get("message", "")).strip_edges()
		if msg.is_empty():
			msg = "无法装备。"
			match reason:
				"incompatible_slot":
					msg = "该物品不能装备到此栏位。"
				"not_in_bag":
					msg = "背包中没有该物品。"
				"not_equipment":
					msg = "该物品无法装备。"
				"bag_full":
					msg = "背包已满，无法替换装备。"
				"unknown_item":
					msg = "未知物品。"
				"two_hand_blocks_off":
					msg = "双手武器占用副手。"
				_:
					msg = "无法装备（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append(_equipment_update_action())
	var iname = ctrl.item_display_name(item_id)
	var slot_used = str(r.get("slot", slot))
	actions.append({"type": "system_message", "text": "装备了【%s】。" % iname})
	if bool(r.get("newly_bound", false)):
		actions.append({"type": "system_message", "text": "已绑定：%s" % iname})
	return {
		"ok": true,
		"reason": "",
		"slot": slot_used,
		"unequipped_item_id": str(r.get("unequipped_item_id", "")),
		"newly_bound": bool(r.get("newly_bound", false)),
		"bound": bool(r.get("bound", false)),
		"actions": actions,
	}



func try_unequip_item(slot: String) -> Dictionary:
	slot = slot.strip_edges()
	if ctrl.equipment == null or ctrl.inventory == null:
		return {"ok": false, "reason": "no_equipment", "actions": []}
	var r: Dictionary = ctrl.equipment.try_unequip_to_bag(ctrl.inventory, slot)
	var actions: Array = []
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "fail"))
		var msg = "无法卸下。"
		match reason:
			"empty":
				msg = "该栏位没有装备。"
			"bag_full":
				msg = "背包已满，无法卸下。"
			"invalid_slot":
				msg = "无效栏位。"
			_:
				msg = "无法卸下（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var iid = str(r.get("item_id", ""))
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append(_equipment_update_action())
	actions.append({"type": "system_message", "text": "卸下了【%s】。" % ctrl.item_display_name(iid)})
	return {"ok": true, "reason": "", "item_id": iid, "slot": slot, "actions": actions}




func try_toggle_equip(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if ctrl.equipment == null or ctrl.inventory == null:
		return {"ok": false, "reason": "no_equipment", "actions": []}
	if item_id.is_empty():
		return {"ok": false, "reason": "invalid", "actions": [{"type": "system_message", "text": "未知物品。"}]}
	var slot = ""
	if ctrl.equipment.has_method("find_slot_of"):
		slot = str(ctrl.equipment.find_slot_of(item_id)).strip_edges()
	else:
		for sid in Equipment.SLOT_IDS:
			if str(ctrl.equipment.get_item_in(sid)).strip_edges() == item_id:
				slot = sid
				break
	if not slot.is_empty():
		return try_unequip_item(slot)
	# Not equipped — try equip from bag (auto slot).
	return try_equip_item(item_id, "")



func _equipment_update_action() -> Dictionary:
	return {
		"type": "equipment_update",
		"equipment": ctrl.equipment.snapshot() if ctrl.equipment != null else [],
		"bonuses": ctrl.equipment.total_bonuses() if ctrl.equipment != null else {},
	}



