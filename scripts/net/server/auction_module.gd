extends RefCounted
## Domain module: auction (list/cancel, snapshot, inventory actions).

var ctrl
func _init(c):
	ctrl = c

const Auction = preload("res://scripts/net/combat/auction.gd")

func snapshot_auction() -> Dictionary:
	if ctrl.auction == null:
		return {"listings": [], "count": 0, "max_listings": 50}
	return ctrl.auction.snapshot_state()



func _auction_update_action() -> Dictionary:
	return {"type": "auction_update", "auction": snapshot_auction()}



func _auction_inventory_actions() -> Array:
	var actions: Array = []
	if ctrl.inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
	actions.append(_auction_update_action())
	return actions



func _auction_seed_npc_stubs() -> void:
	if ctrl.auction == null:
		ctrl.auction = Auction.new()
	# Prefer clear player state on enter_world; re-seed a few NPC stubs so browse works.
	var stubs: Array = [
		{"seller_id": "npc_ah_1", "seller_name": "行商·阿福", "item_id": "potion_hp_small", "qty": 3, "price_gold": 25},
		{"seller_id": "npc_ah_2", "seller_name": "旅商·小翠", "item_id": "potion_mp_small", "qty": 2, "price_gold": 30},
		{"seller_id": "npc_ah_3", "seller_name": "拍卖行代理人", "item_id": "slime_jelly", "qty": 5, "price_gold": 15},
		{"seller_id": "npc_ah_1", "seller_name": "行商·阿福", "item_id": "wild_herb", "qty": 10, "price_gold": 8},
		{"seller_id": "npc_ah_4", "seller_name": "黑市商人", "item_id": "wooden_sword", "qty": 1, "price_gold": 120},
	]
	for s in stubs:
		if ctrl.auction.is_full():
			break
		var iid = str(s.get("item_id", ""))
		var iname = ctrl.item_display_name(iid) if ctrl.has_method("item_display_name") else iid
		ctrl.auction.try_add(
			str(s.get("seller_id", "npc")),
			str(s.get("seller_name", "NPC")),
			iid,
			iname,
			int(s.get("qty", 1)),
			int(s.get("price_gold", 1)),
		)



func try_auction_list(item_id: String, qty: int = 1, price_gold: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	price_gold = int(price_gold)
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "上架请求无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if price_gold <= 0:
		actions.append({"type": "system_message", "text": "售价必须大于 0。"})
		return {"ok": false, "reason": "bad_price", "actions": actions}
	if ctrl.auction == null:
		ctrl.auction = Auction.new()
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	if ctrl.auction.is_full():
		actions.append({"type": "system_message", "text": "拍卖行已满（最多 %d 件）。" % ctrl.auction.max_listings()})
		return {"ok": false, "reason": "full", "actions": actions}
	if ctrl.inventory.has_method("is_locked") and ctrl.inventory.is_locked(item_id):
		actions.append({"type": "system_message", "text": "该物品已锁定，无法上架。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if not ctrl.inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if ctrl.inventory.has_method("can_transfer") and not ctrl.inventory.can_transfer(item_id, qty):
		actions.append({"type": "system_message", "text": "已绑定物品无法上架拍卖。"})
		return {"ok": false, "reason": "bound", "actions": actions}
	var auc_consumed = false
	if ctrl.inventory.has_method("consume_unbound"):
		auc_consumed = ctrl.inventory.consume_unbound(item_id, qty)
	else:
		auc_consumed = ctrl.inventory.consume(item_id, qty)
	if not auc_consumed:
		actions.append({"type": "system_message", "text": "扣除背包物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var iname = ctrl.item_display_name(item_id)
	var add_r: Dictionary = ctrl.auction.try_add(
		ctrl._party_self_id(),
		ctrl._party_self_name(),
		item_id,
		iname,
		qty,
		price_gold,
	)
	if not bool(add_r.get("ok", false)):
		ctrl.inventory.add_item(item_id, qty)
		var ar = str(add_r.get("reason", "full"))
		if ar == "full":
			actions.append({"type": "system_message", "text": "拍卖行已满（最多 %d 件）。" % ctrl.auction.max_listings()})
		else:
			actions.append({"type": "system_message", "text": "上架失败。"})
		actions.append_array(_auction_inventory_actions())
		return {"ok": false, "reason": ar, "actions": actions}
	actions.append_array(_auction_inventory_actions())
	actions.append({"type": "system_message", "text": "已上架【%s】×%d（售价 %d 金币）。" % [iname, qty, price_gold]})
	return {"ok": true, "actions": actions}



func try_auction_cancel(listing_id: String) -> Dictionary:
	var actions: Array = []
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的拍卖编号。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.auction == null:
		actions.append({"type": "system_message", "text": "拍卖行不可用。"})
		return {"ok": false, "reason": "no_ah", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	var listing: Dictionary = ctrl.auction.get_listing(listing_id)
	if listing.is_empty():
		actions.append({"type": "system_message", "text": "找不到该拍卖品。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var seller_id = str(listing.get("seller_id", "")).strip_edges()
	var self_id = ctrl._party_self_id()
	if seller_id != self_id and seller_id != "player":
		actions.append({"type": "system_message", "text": "只能下架自己的拍卖品。"})
		return {"ok": false, "reason": "not_owner", "actions": actions}
	var iid = str(listing.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(listing.get("qty", 0)), 0)
	var iname = str(listing.get("item_name", "")).strip_edges()
	if iname.is_empty():
		iname = ctrl.item_display_name(iid)
	if iid.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "拍卖数据无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory.has_method("can_accept") and not ctrl.inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满，无法取回拍卖品。"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var rem: Dictionary = ctrl.auction.try_remove(listing_id)
	if not bool(rem.get("ok", false)):
		actions.append({"type": "system_message", "text": "下架失败。"})
		return {"ok": false, "reason": str(rem.get("reason", "not_found")), "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		# Restore listing; reverse partial
		if added > 0:
			ctrl.inventory.consume(iid, added)
		ctrl.auction.try_add(
			seller_id,
			str(listing.get("seller_name", "")),
			iid,
			iname,
			qty,
			int(listing.get("price_gold", 1)),
		)
		actions.append({"type": "system_message", "text": "背包已满，无法取回拍卖品。"})
		actions.append_array(_auction_inventory_actions())
		return {"ok": false, "reason": "bag_full", "actions": actions}
	actions.append_array(_auction_inventory_actions())
	actions.append({"type": "system_message", "text": "已下架【%s】×%d，物品已返还背包。" % [iname, qty]})
	return {"ok": true, "actions": actions}



