extends RefCounted
## Domain module: inventory/items (split/sort/lock, use, drop, bag display).

var ctrl
func _init(c):
	ctrl = c

const Equipment = preload("res://scripts/net/combat/equipment.gd")

func try_use_item(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	# Pet whistle: summon companion (does not consume).
	if item_id == "pet_whistle":
		if ctrl.inventory == null or not ctrl.inventory.has_item("pet_whistle", 1):
			return {
				"ok": false,
				"reason": "missing",
				"actions": [{"type": "system_message", "text": "背包中没有宠物哨。"}],
			}
		return ctrl.try_pet_summon("default")
	# Equipment: hotbar / inventory "use" toggles equip (not consume).
	if ctrl.item_catalog != null and not item_id.is_empty():
		var def: Dictionary = ctrl.item_catalog.get_item(item_id)
		if str(def.get("type", "")).strip_edges() == "equipment":
			return ctrl.try_toggle_equip(item_id)
		# Recall / town scroll: fail before consume if dead / awaiting respawn / already safe.
		var ue = str(def.get("use_effect", def.get("effect", ""))).strip_edges()
		if ue == "party_summon" or item_id == "party_summon":
			return ctrl._try_party_summon_item(item_id, def)
		if ue == "recall" or ue == "teleport_home":
			var gate: Dictionary = ctrl._gate_recall_item_use()
			if not bool(gate.get("ok", false)):
				return gate
	if ctrl.combat_engine == null:
		return {"ok": false, "actions": []}
	var result: Dictionary = ctrl.combat_engine.try_use_item(item_id)
	ctrl._bind_recall_actions(result)
	ctrl._combat_stand_if_needed(result)
	ctrl._maybe_party_food_share(item_id, result)
	return ctrl._finalize_combat_result(result)



func try_inventory_split(item_id: String, qty: int) -> Dictionary:
	var actions: Array = []
	if ctrl.inventory == null or not ctrl.inventory.has_method("try_split"):
		return {"ok": false, "reason": "no_inv", "actions": actions}
	item_id = item_id.strip_edges()
	var r: Dictionary = ctrl.inventory.try_split(item_id, qty)
	if not bool(r.get("ok", false)):
		var why = str(r.get("reason", ""))
		var msg = "无法拆分。"
		if why == "bag_full":
			msg = "背包已满，无法拆分。"
		elif why == "too_small":
			msg = "数量不足，无法拆分。"
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": why, "actions": actions}
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}



func try_inventory_sort() -> Dictionary:
	var actions: Array = []
	if ctrl.inventory == null or not ctrl.inventory.has_method("sort_stacks"):
		return {"ok": false, "reason": "no_inv", "actions": actions}
	ctrl.inventory.sort_stacks()
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}



func try_inventory_lock(item_id: String, on: bool) -> Dictionary:
	var actions: Array = []
	if ctrl.inventory == null or not ctrl.inventory.has_method("set_locked"):
		return {"ok": false, "reason": "no_inv", "actions": actions}
	ctrl.inventory.set_locked(item_id, on)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}




func _item_binds_on_pickup(item_id: String) -> bool:
	if ctrl.item_catalog == null:
		return false
	var def: Dictionary = ctrl.item_catalog.get_item(item_id.strip_edges())
	return Equipment.is_bind_on_pickup(def)



func try_drop_item(item_id: String, qty: int = 1) -> Dictionary:
	item_id = item_id.strip_edges()
	var actions: Array = []
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inventory", "actions": actions}
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory.has_method("is_locked") and ctrl.inventory.is_locked(item_id):
		actions.append({"type": "system_message", "text": "该物品已锁定，无法丢弃。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if not ctrl.inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	if not ctrl.inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "丢弃失败。"})
		return {"ok": false, "reason": "consume_failed", "actions": actions}
	var cell = {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	var bag_actions: Array = ctrl._add_items_to_ground(cell, [{"item_id": item_id, "qty": qty}], "player", "")
	actions.append_array(bag_actions)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "扔下了 %s×%d" % [item_display_name(item_id), qty],
	})
	return {"ok": true, "item_id": item_id, "qty": qty, "actions": actions}



func try_drop_equipped(slot: String) -> Dictionary:
	slot = slot.strip_edges()
	var actions: Array = []
	if ctrl.equipment == null:
		actions.append({"type": "system_message", "text": "装备不可用。"})
		return {"ok": false, "reason": "no_equipment", "actions": actions}
	if slot.is_empty():
		actions.append({"type": "system_message", "text": "无效栏位。"})
		return {"ok": false, "reason": "invalid_slot", "actions": actions}
	var r: Dictionary = ctrl.equipment.try_unequip(slot)
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "fail"))
		var msg = "无法丢弃装备。"
		match reason:
			"empty":
				msg = "该栏位没有装备。"
			"invalid_slot":
				msg = "无效栏位。"
			_:
				msg = "无法丢弃装备（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var iid = str(r.get("item_id", "")).strip_edges()
	if iid.is_empty():
		actions.append({"type": "system_message", "text": "无效物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var cell = {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	actions.append_array(ctrl._add_items_to_ground(cell, [{"item_id": iid, "qty": 1}], "player", ""))
	actions.append(ctrl._equipment_update_action())
	actions.append({
		"type": "system_message",
		"text": "扔下了 %s×1" % item_display_name(iid),
	})
	return {"ok": true, "item_id": iid, "slot": slot, "qty": 1, "actions": actions}



func _open_bag_items() -> Array:
	if ctrl._open_loot_bag_id.is_empty() or not ctrl._ground_bags.has(ctrl._open_loot_bag_id):
		return []
	var items_v: Variant = ctrl._ground_bags[ctrl._open_loot_bag_id].get("items", [])
	return items_v if typeof(items_v) == TYPE_ARRAY else []




func _item_icon_fields(item_id: String) -> Dictionary:
	var out = {"icon_index": -1}
	if ctrl.item_catalog == null or item_id.strip_edges().is_empty():
		return out
	var def: Dictionary = ctrl.item_catalog.get_item(item_id)
	if def.is_empty():
		return out
	out["icon_index"] = int(def.get("icon_index", -1))
	var ic = str(def.get("icon", "")).strip_edges()
	if not ic.is_empty():
		out["icon"] = ic
	var iref = str(def.get("icon_ref", "")).strip_edges()
	if iref.is_empty() and not ic.is_empty():
		iref = "content://icon/%s" % ic
	if not iref.is_empty():
		out["icon_ref"] = iref
	return out



func _open_bag_items_dup() -> Array:
	var out: Array = []
	for d_v in _open_bag_items():
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = d_v
		var iid = str(d.get("item_id", "")).strip_edges()
		var q: int = int(d.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		var row = {"item_id": iid, "qty": q, "name": item_display_name(iid)}
		row.merge(_item_icon_fields(iid))
		out.append(row)
	return out



func _merge_item_into_list(items: Array, item_id: String, qty: int) -> void:
	for i in range(items.size()):
		var pe: Dictionary = items[i]
		if str(pe.get("item_id", "")) == item_id:
			pe["qty"] = int(pe.get("qty", 0)) + qty
			items[i] = pe
			return
	items.append({"item_id": item_id, "qty": qty})



func item_display_name(item_id: String) -> String:
	if ctrl.item_catalog == null:
		return item_id
	var def: Dictionary = ctrl.item_catalog.get_item(item_id)
	if def.is_empty():
		return item_id
	return str(def.get("name", item_id))


