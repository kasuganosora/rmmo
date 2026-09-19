extends RefCounted
## Domain module: warehouse (open/deposit/withdraw items+gold).

var ctrl
func _init(c):
	ctrl = c

func snapshot_warehouse() -> Dictionary:
	if ctrl.warehouse == null:
		return {"items": [], "gold": 0, "max_slots": 60, "used_slots": 0}
	return ctrl.warehouse.snapshot_state()



func _warehouse_update_action() -> Dictionary:
	return {"type": "warehouse_update", "warehouse": snapshot_warehouse()}



func _warehouse_inventory_actions() -> Array:
	var actions: Array = []
	if ctrl.inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
	actions.append(_warehouse_update_action())
	return actions



func try_warehouse_open() -> Dictionary:
	var actions: Array = []
	actions.append(_warehouse_update_action())
	actions.append({"type": "system_message", "text": "仓库已打开。"})
	return {"ok": true, "actions": actions}



func try_warehouse_deposit(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效的存入数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory == null or ctrl.warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not ctrl.inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if not ctrl.inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "扣除背包物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var add_r: Dictionary = ctrl.warehouse.try_add_item(item_id, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			ctrl.warehouse.consume(item_id, added)
		ctrl.inventory.add_item(item_id, qty)
		var reason = str(add_r.get("reason", "bag_full"))
		var msg = "仓库已满，无法存入。"
		if reason == "stack_full":
			msg = "仓库堆叠已满，无法存入。"
		actions.append({"type": "system_message", "text": msg})
		actions.append_array(_warehouse_inventory_actions())
		return {"ok": false, "reason": "warehouse_full", "actions": actions}
	var iname = ctrl.item_display_name(item_id)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "存入【%s】×%d。" % [iname, qty]})
	return {"ok": true, "actions": actions}



func try_warehouse_withdraw(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效的取出数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory == null or ctrl.warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not ctrl.warehouse.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "仓库中没有足够的物品。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if not ctrl.warehouse.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "扣除仓库物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(item_id, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			ctrl.inventory.consume(item_id, added)
		ctrl.warehouse.add_item(item_id, qty)
		var reason = str(add_r.get("reason", "bag_full"))
		var msg = "背包已满，无法取出。"
		if reason == "stack_full":
			msg = "背包堆叠已满，无法取出。"
		actions.append({"type": "system_message", "text": msg})
		actions.append_array(_warehouse_inventory_actions())
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var iname = ctrl.item_display_name(item_id)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "取出【%s】×%d。" % [iname, qty]})
	return {"ok": true, "actions": actions}



func try_warehouse_deposit_gold(amount: int) -> Dictionary:
	var actions: Array = []
	amount = int(amount)
	if amount <= 0:
		actions.append({"type": "system_message", "text": "无效的金币数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory == null or ctrl.warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not ctrl.inventory.try_spend_gold(amount):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	ctrl.warehouse.add_gold(amount)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "存入金币 %d。" % amount})
	return {"ok": true, "actions": actions}



func try_warehouse_withdraw_gold(amount: int) -> Dictionary:
	var actions: Array = []
	amount = int(amount)
	if amount <= 0:
		actions.append({"type": "system_message", "text": "无效的金币数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory == null or ctrl.warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not ctrl.warehouse.try_spend_gold(amount):
		actions.append({"type": "system_message", "text": "仓库金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	ctrl.inventory.add_gold(amount)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "取出金币 %d。" % amount})
	return {"ok": true, "actions": actions}


