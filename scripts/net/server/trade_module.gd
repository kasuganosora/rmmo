extends RefCounted
## Domain module: trade (open/put/take/gold/ready/confirm, escrow refund).

var ctrl
func _init(c):
	ctrl = c

func snapshot_trade() -> Dictionary:
	if ctrl._trade.is_empty():
		return {"active": false}
	return {
		"active": true,
		"session_id": str(ctrl._trade.get("session_id", "")),
		"partner_id": str(ctrl._trade.get("partner_id", "")),
		"partner_name": str(ctrl._trade.get("partner_name", "")),
		"my_items": (ctrl._trade.get("my_items", []) as Array).duplicate(true),
		"their_items": (ctrl._trade.get("their_items", []) as Array).duplicate(true),
		"my_gold": int(ctrl._trade.get("my_gold", 0)),
		"their_gold": int(ctrl._trade.get("their_gold", 0)),
		"my_ready": bool(ctrl._trade.get("my_ready", false)),
		"their_ready": bool(ctrl._trade.get("their_ready", false)),
	}



func in_trade() -> bool:
	return not ctrl._trade.is_empty()



func _trade_update_action() -> Dictionary:
	return {"type": "trade_update", "trade": snapshot_trade()}



func _trade_close_action() -> Dictionary:
	return {"type": "trade_close"}



func _trade_force_cancel_silent() -> void:
	# Return escrow without UI spam (map reload / logout shell).
	if ctrl._trade.is_empty():
		return
	_trade_refund_my_escrow()
	ctrl._trade.clear()



func _trade_refund_my_escrow() -> void:
	if ctrl.inventory == null:
		return
	var items_v: Variant = ctrl._trade.get("my_items", [])
	if typeof(items_v) == TYPE_ARRAY:
		for it in items_v:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid = str(it.get("item_id", "")).strip_edges()
			var q: int = maxi(int(it.get("qty", 0)), 0)
			if iid.is_empty() or q <= 0:
				continue
			ctrl.inventory.add_item(iid, q)
	var g: int = maxi(int(ctrl._trade.get("my_gold", 0)), 0)
	if g > 0:
		ctrl.inventory.add_gold(g)
	ctrl._trade["my_items"] = []
	ctrl._trade["my_gold"] = 0



func _trade_inventory_actions() -> Array:
	var actions: Array = []
	if ctrl.inventory == null:
		return actions
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	return actions



func _trade_find_my_item(item_id: String) -> int:
	item_id = item_id.strip_edges()
	var items: Array = ctrl._trade.get("my_items", [])
	for i in range(items.size()):
		var it: Variant = items[i]
		if typeof(it) == TYPE_DICTIONARY and str(it.get("item_id", "")) == item_id:
			return i
	return -1



func try_trade_open(partner_name: String = "") -> Dictionary:
	var actions: Array = []
	if in_trade():
		actions.append({"type": "system_message", "text": "已在交易中。"})
		actions.append(_trade_update_action())
		return {"ok": false, "reason": "already", "actions": actions}
	partner_name = str(partner_name).strip_edges()
	var partner_id = "stub_trader_%d" % ctrl._next_trade_seq
	# Resolve existing remote/fake player by id or display name when provided.
	if not partner_name.is_empty():
		var rid = ""
		if ctrl._remote_players.has(partner_name):
			rid = partner_name
		else:
			rid = ctrl.find_remote_by_name(partner_name)
		if rid != "":
			var rd: Dictionary = ctrl.get_remote_player(rid)
			partner_id = rid
			var rn = str(rd.get("name", "")).strip_edges()
			if not rn.is_empty():
				partner_name = rn
	if partner_name.is_empty():
		partner_name = "旅人乙"
	ctrl._trade = {
		"session_id": "trade_%d" % ctrl._next_trade_seq,
		"partner_id": partner_id,
		"partner_name": partner_name,
		"my_items": [],
		"their_items": [],
		"my_gold": 0,
		"their_gold": 0,
		"my_ready": false,
		"their_ready": false,
	}
	ctrl._next_trade_seq += 1
	actions.append(_trade_update_action())
	actions.append({"type": "system_message", "text": "与【%s】开始交易（调试占位）。" % partner_name})
	return {"ok": true, "actions": actions}



func try_trade_cancel() -> Dictionary:
	var actions: Array = []
	if not in_trade():
		actions.append(_trade_close_action())
		return {"ok": true, "actions": actions}
	_trade_refund_my_escrow()
	ctrl._trade.clear()
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_close_action())
	actions.append({"type": "system_message", "text": "交易已取消。"})
	return {"ok": true, "actions": actions}



func try_trade_put_item(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = maxi(qty, 1)
	if not in_trade():
		actions.append({"type": "system_message", "text": "未在交易中。"})
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if bool(ctrl._trade.get("my_ready", false)):
		actions.append({"type": "system_message", "text": "已锁定，无法改动报价。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if ctrl.inventory == null or not ctrl.inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "物品不足。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if ctrl.inventory.has_method("can_transfer") and not ctrl.inventory.can_transfer(item_id, qty):
		actions.append({"type": "system_message", "text": "已绑定物品无法交易。"})
		return {"ok": false, "reason": "bound", "actions": actions}
	var consumed_ok = false
	if ctrl.inventory.has_method("consume_unbound"):
		consumed_ok = ctrl.inventory.consume_unbound(item_id, qty)
	else:
		consumed_ok = ctrl.inventory.consume(item_id, qty)
	if not consumed_ok:
		actions.append({"type": "system_message", "text": "扣除物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var idx = _trade_find_my_item(item_id)
	var items: Array = ctrl._trade.get("my_items", [])
	if idx >= 0:
		var row: Dictionary = items[idx]
		row["qty"] = int(row.get("qty", 0)) + qty
		items[idx] = row
	else:
		items.append({
			"item_id": item_id,
			"qty": qty,
			"name": ctrl.item_display_name(item_id),
		})
	ctrl._trade["my_items"] = items
	ctrl._trade["their_ready"] = false
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_update_action())
	return {"ok": true, "actions": actions}



func try_trade_take_item(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = maxi(qty, 1)
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if bool(ctrl._trade.get("my_ready", false)):
		actions.append({"type": "system_message", "text": "已锁定，无法改动报价。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	var idx = _trade_find_my_item(item_id)
	if idx < 0:
		return {"ok": false, "reason": "not_in_offer", "actions": actions}
	var items: Array = ctrl._trade.get("my_items", [])
	var row: Dictionary = items[idx]
	var have: int = int(row.get("qty", 0))
	var take: int = mini(qty, have)
	if take <= 0:
		return {"ok": false, "reason": "empty", "actions": actions}
	if ctrl.inventory != null:
		ctrl.inventory.add_item(item_id, take)
	have -= take
	if have <= 0:
		items.remove_at(idx)
	else:
		row["qty"] = have
		items[idx] = row
	ctrl._trade["my_items"] = items
	ctrl._trade["their_ready"] = false
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_update_action())
	return {"ok": true, "actions": actions}



func try_trade_set_gold(amount: int) -> Dictionary:
	var actions: Array = []
	amount = maxi(amount, 0)
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if bool(ctrl._trade.get("my_ready", false)):
		actions.append({"type": "system_message", "text": "已锁定，无法改动报价。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if ctrl.inventory == null:
		return {"ok": false, "reason": "no_inv", "actions": actions}
	# Refund previous escrowed gold first, then re-escrow.
	var prev: int = maxi(int(ctrl._trade.get("my_gold", 0)), 0)
	if prev > 0:
		ctrl.inventory.add_gold(prev)
		ctrl._trade["my_gold"] = 0
	if amount > 0:
		if not ctrl.inventory.try_spend_gold(amount):
			actions.append({"type": "system_message", "text": "金币不足。"})
			actions.append_array(_trade_inventory_actions())
			actions.append(_trade_update_action())
			return {"ok": false, "reason": "no_gold", "actions": actions}
		ctrl._trade["my_gold"] = amount
	ctrl._trade["their_ready"] = false
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_update_action())
	return {"ok": true, "actions": actions}



func _trade_fill_stub_offer() -> void:
	## Canned counter-offer so the shell can complete a full swap.
	if int(ctrl._trade.get("their_gold", 0)) > 0 or not (ctrl._trade.get("their_items", []) as Array).is_empty():
		return
	ctrl._trade["their_gold"] = 15
	var oid = "potion_mp_small"
	ctrl._trade["their_items"] = [{
		"item_id": oid,
		"qty": 1,
		"name": ctrl.item_display_name(oid),
	}]



func try_trade_ready(ready: bool = true) -> Dictionary:
	var actions: Array = []
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	ctrl._trade["my_ready"] = ready
	if ready:
		ctrl._trade["their_ready"] = true
	else:
		ctrl._trade["their_ready"] = false
	actions.append(_trade_update_action())
	if ready:
		actions.append({"type": "system_message", "text": "你已锁定报价。对方已锁定（无报价）。"})
	else:
		actions.append({"type": "system_message", "text": "已取消锁定。"})
	return {"ok": true, "actions": actions}



func try_trade_confirm() -> Dictionary:
	var actions: Array = []
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if not bool(ctrl._trade.get("my_ready", false)) or not bool(ctrl._trade.get("their_ready", false)):
		actions.append({"type": "system_message", "text": "双方需先锁定报价。"})
		return {"ok": false, "reason": "not_ready", "actions": actions}
	if ctrl.inventory == null:
		return {"ok": false, "reason": "no_inv", "actions": actions}
	# Receive their offer (my escrow already removed from bag).
	var their_items: Array = ctrl._trade.get("their_items", [])
	for it in their_items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid = str(it.get("item_id", "")).strip_edges()
		var q: int = maxi(int(it.get("qty", 0)), 0)
		if iid.is_empty() or q <= 0:
			continue
		var add_r: Dictionary = ctrl.inventory.try_add_item(iid, q)
		var added: int = int(add_r.get("added", 0)) if typeof(add_r) == TYPE_DICTIONARY else 0
		if added < q:
			# Rollback: refund remaining theirs not applied is lost in shell — prefer refund my escrow and abort.
			# Best-effort: put back what we couldn't take is already partial; keep shell simple: warn + keep trade open.
			actions.append({"type": "system_message", "text": "背包空间不足，交易未完成。"})
			actions.append_array(_trade_inventory_actions())
			actions.append(_trade_update_action())
			return {"ok": false, "reason": "bag_full", "actions": actions}
	var their_gold: int = maxi(int(ctrl._trade.get("their_gold", 0)), 0)
	if their_gold > 0:
		ctrl.inventory.add_gold(their_gold)
	# My escrow stays with stub (consumed). Clear session.
	var pname = str(ctrl._trade.get("partner_name", "对方"))
	ctrl._trade.clear()
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_close_action())
	actions.append({"type": "system_message", "text": "与【%s】交易完成。" % pname})
	return {"ok": true, "actions": actions}


