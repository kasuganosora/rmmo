extends RefCounted
## Domain module: mail (send/read/claim/delete, welcome inject).

var ctrl
func _init(c):
	ctrl = c

const Mailbox = preload("res://scripts/net/combat/mailbox.gd")

func snapshot_mail() -> Dictionary:
	if ctrl.mailbox == null:
		return {"mails": [], "count": 0, "max_mail": 30}
	return ctrl.mailbox.snapshot_state()



func _mail_update_action() -> Dictionary:
	return {"type": "mail_update", "mail": snapshot_mail()}



func _mail_inventory_actions() -> Array:
	var actions: Array = []
	if ctrl.inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
	actions.append(_mail_update_action())
	return actions



func _mail_inject_welcome() -> void:
	if ctrl._mail_welcome_sent:
		return
	if ctrl.mailbox == null:
		ctrl.mailbox = Mailbox.new()
	if ctrl.mailbox.count() > 0:
		ctrl._mail_welcome_sent = true
		return
	var to_name = ctrl._party_self_name()
	ctrl.mailbox.try_add(
		"系统",
		to_name,
		"欢迎来到世界",
		"冒险者你好！这是系统邮筒。可给自己或已知玩家寄信，并可附带金币与物品。",
		0,
		[]
	)
	ctrl._mail_welcome_sent = true



func _resolve_mail_recipient(to_name: String) -> Dictionary:
	## Returns {ok, id, name, is_self, reason}.
	to_name = str(to_name).strip_edges()
	if to_name.is_empty():
		return {"ok": false, "reason": "invalid", "id": "", "name": "", "is_self": false}
	var self_name = ctrl._party_self_name()
	var self_id = ctrl._party_self_id()
	var low = to_name.to_lower()
	if (
		to_name == self_name
		or to_name == self_id
		or low == self_name.to_lower()
		or to_name == "自己"
		or low == "self"
		or to_name == "你"
	):
		return {"ok": true, "id": self_id, "name": self_name, "is_self": true, "reason": ""}
	# Friends list by name/id
	if ctrl.friend_list != null:
		for e in ctrl.friend_list.snapshot():
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var fid = str(e.get("id", "")).strip_edges()
			var fname = str(e.get("name", "")).strip_edges()
			if fid == to_name or fname == to_name or fname.to_lower() == low:
				return {"ok": true, "id": fid, "name": fname if fname != "" else fid, "is_self": false, "reason": ""}
	var resolved: Dictionary = ctrl._resolve_friend_target(to_name)
	if bool(resolved.get("ok", false)):
		return {
			"ok": true,
			"id": str(resolved.get("id", "")),
			"name": str(resolved.get("name", to_name)),
			"is_self": false,
			"reason": "",
		}
	return {"ok": false, "reason": "not_found", "id": "", "name": "", "is_self": false}



func try_mail_send(to: String, subject: String, body: String, gold: int = 0, item_id: String = "", qty: int = 1) -> Dictionary:
	var actions: Array = []
	to = str(to).strip_edges()
	subject = str(subject).strip_edges()
	body = str(body)
	gold = int(gold)
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	if to.is_empty():
		actions.append({"type": "system_message", "text": "请填写收件人。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if gold < 0 or (not item_id.is_empty() and qty <= 0):
		actions.append({"type": "system_message", "text": "附件无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.mailbox == null:
		ctrl.mailbox = Mailbox.new()
	var recip: Dictionary = _resolve_mail_recipient(to)
	if not bool(recip.get("ok", false)):
		var rr = str(recip.get("reason", "not_found"))
		if rr == "invalid":
			actions.append({"type": "system_message", "text": "请填写收件人。"})
		else:
			actions.append({"type": "system_message", "text": "找不到收件人【%s】。" % to})
		return {"ok": false, "reason": rr, "actions": actions}
	var is_self = bool(recip.get("is_self", false))
	var recip_name = str(recip.get("name", to))
	if is_self and ctrl.mailbox.is_full():
		actions.append({"type": "system_message", "text": "收件箱已满（最多 %d 封）。" % ctrl.mailbox.max_mail()})
		return {"ok": false, "reason": "full", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	if gold > 0 and ctrl.inventory.get_gold() < gold:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not item_id.is_empty():
		if qty <= 0:
			actions.append({"type": "system_message", "text": "附件数量无效。"})
			return {"ok": false, "reason": "invalid", "actions": actions}
		if not ctrl.inventory.has_item(item_id, qty):
			actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
			return {"ok": false, "reason": "no_item", "actions": actions}
		if ctrl.inventory.has_method("can_transfer") and not ctrl.inventory.can_transfer(item_id, qty):
			actions.append({"type": "system_message", "text": "已绑定物品无法邮寄。"})
			return {"ok": false, "reason": "bound", "actions": actions}
	# Deduct attachments
	if gold > 0 and not ctrl.inventory.try_spend_gold(gold):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not item_id.is_empty():
		var mail_ok = false
		if ctrl.inventory.has_method("consume_unbound"):
			mail_ok = ctrl.inventory.consume_unbound(item_id, qty)
		else:
			mail_ok = ctrl.inventory.consume(item_id, qty)
		if not mail_ok:
			if gold > 0:
				ctrl.inventory.add_gold(gold)
			actions.append({"type": "system_message", "text": "扣除背包物品失败。"})
			return {"ok": false, "reason": "consume_fail", "actions": actions}
	var attach: Array = []
	if not item_id.is_empty():
		attach.append({"id": item_id, "qty": qty})
	if is_self:
		var add_r: Dictionary = ctrl.mailbox.try_add(ctrl._party_self_name(), recip_name, subject, body, gold, attach)
		if not bool(add_r.get("ok", false)):
			# Refund
			if gold > 0:
				ctrl.inventory.add_gold(gold)
			if not item_id.is_empty():
				ctrl.inventory.add_item(item_id, qty)
			var ar = str(add_r.get("reason", "full"))
			if ar == "full":
				actions.append({"type": "system_message", "text": "收件箱已满（最多 %d 封）。" % ctrl.mailbox.max_mail()})
			else:
				actions.append({"type": "system_message", "text": "发送失败。"})
			actions.append_array(_mail_inventory_actions())
			return {"ok": false, "reason": ar, "actions": actions}
		actions.append_array(_mail_inventory_actions())
		actions.append({"type": "system_message", "text": "已发送邮件给自己。"})
		return {"ok": true, "actions": actions}
	# Delivered to remote/friend/stub (not visible in local inbox).
	actions.append_array(_mail_inventory_actions())
	actions.append({"type": "system_message", "text": "已发送邮件给【%s】。" % recip_name})
	return {"ok": true, "actions": actions}



func try_mail_read(mail_id: String) -> Dictionary:
	var actions: Array = []
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的邮件。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.mailbox == null:
		actions.append({"type": "system_message", "text": "邮箱不可用。"})
		return {"ok": false, "reason": "no_box", "actions": actions}
	var r: Dictionary = ctrl.mailbox.try_mark_read(mail_id)
	if not bool(r.get("ok", false)):
		actions.append({"type": "system_message", "text": "找不到该邮件。"})
		return {"ok": false, "reason": str(r.get("reason", "not_found")), "actions": actions}
	actions.append(_mail_update_action())
	return {"ok": true, "actions": actions}



func try_mail_claim(mail_id: String) -> Dictionary:
	var actions: Array = []
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的邮件。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.mailbox == null or ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "邮箱不可用。"})
		return {"ok": false, "reason": "no_box", "actions": actions}
	var mail: Dictionary = ctrl.mailbox.get_mail(mail_id)
	if mail.is_empty():
		actions.append({"type": "system_message", "text": "找不到该邮件。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	if bool(mail.get("claimed", false)):
		actions.append({"type": "system_message", "text": "附件已领取。"})
		actions.append(_mail_update_action())
		return {"ok": false, "reason": "already_claimed", "actions": actions}
	var gold: int = maxi(int(mail.get("gold", 0)), 0)
	var items_v: Variant = mail.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	# Pre-check bag capacity for all item attachments.
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid = str(it.get("id", it.get("item_id", ""))).strip_edges()
		var q: int = int(it.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		if not ctrl.inventory.can_accept(iid, q):
			actions.append({"type": "system_message", "text": "背包已满，无法收取附件。"})
			return {"ok": false, "reason": "bag_full", "actions": actions}
	# Grant
	if gold > 0:
		ctrl.inventory.add_gold(gold)
	for it2 in items:
		if typeof(it2) != TYPE_DICTIONARY:
			continue
		var iid2 = str(it2.get("id", it2.get("item_id", ""))).strip_edges()
		var q2: int = int(it2.get("qty", 0))
		if iid2.is_empty() or q2 <= 0:
			continue
		var add_r: Dictionary = ctrl.inventory.try_add_item(iid2, q2)
		var added: int = int(add_r.get("added", 0))
		if added < q2:
			# Rollback gold already granted; refund partial items
			if gold > 0:
				ctrl.inventory.try_spend_gold(gold)
			if added > 0:
				ctrl.inventory.consume(iid2, added)
			actions.append({"type": "system_message", "text": "背包已满，无法收取附件。"})
			actions.append_array(_mail_inventory_actions())
			return {"ok": false, "reason": "bag_full", "actions": actions}
	var mark: Dictionary = ctrl.mailbox.try_mark_claimed(mail_id)
	if not bool(mark.get("ok", false)):
		# Should not happen; refund
		if gold > 0:
			ctrl.inventory.try_spend_gold(gold)
		for it3 in items:
			if typeof(it3) != TYPE_DICTIONARY:
				continue
			var iid3 = str(it3.get("id", it3.get("item_id", ""))).strip_edges()
			var q3: int = int(it3.get("qty", 0))
			if not iid3.is_empty() and q3 > 0:
				ctrl.inventory.consume(iid3, q3)
		actions.append({"type": "system_message", "text": "领取失败。"})
		actions.append_array(_mail_inventory_actions())
		return {"ok": false, "reason": str(mark.get("reason", "failed")), "actions": actions}
	actions.append_array(_mail_inventory_actions())
	actions.append({"type": "system_message", "text": "已收取邮件附件。"})
	return {"ok": true, "actions": actions}



func try_mail_delete(mail_id: String) -> Dictionary:
	var actions: Array = []
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的邮件。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.mailbox == null:
		actions.append({"type": "system_message", "text": "邮箱不可用。"})
		return {"ok": false, "reason": "no_box", "actions": actions}
	var r: Dictionary = ctrl.mailbox.try_delete(mail_id)
	if not bool(r.get("ok", false)):
		actions.append({"type": "system_message", "text": "找不到该邮件。"})
		return {"ok": false, "reason": str(r.get("reason", "not_found")), "actions": actions}
	actions.append(_mail_update_action())
	actions.append({"type": "system_message", "text": "已删除邮件。"})
	return {"ok": true, "actions": actions}


