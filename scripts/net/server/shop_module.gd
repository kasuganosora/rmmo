extends RefCounted
## Domain module: shop/vendor (buy/sell/junk/buyback, reputation, auction buy).

var ctrl
func _init(c):
	ctrl = c

const BUYBACK_MAX := 8

func _try_open_shop_action(shop_id: String) -> Dictionary:
	shop_id = shop_id.strip_edges()
	var actions: Array = []
	if shop_id.is_empty() or ctrl.shop_catalog == null or not ctrl.shop_catalog.has_shop(shop_id):
		actions.append({"type": "system_message", "text": "商店不可用。"})
		return {"ok": false, "reason": "no_shop", "actions": actions}
	actions.append(_build_open_shop_payload(shop_id))
	return {"ok": true, "shop_id": shop_id, "actions": actions}



func get_vendor_rep(shop_id: String = "starter_goods") -> int:
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		shop_id = "starter_goods"
	if shop_id == "starter_goods":
		return clampi(ctrl.vendor_rep, 0, 1000)
	return clampi(int(ctrl._rep_by_vendor.get(shop_id, 0)), 0, 1000)



func set_vendor_rep(shop_id: String, value: int) -> void:
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		shop_id = "starter_goods"
	var v: int = clampi(value, 0, 1000)
	ctrl._rep_by_vendor[shop_id] = v
	if shop_id == "starter_goods":
		ctrl.vendor_rep = v



func force_vendor_rep(shop_id: String, value: int) -> void:
	set_vendor_rep(shop_id, value)



func _vendor_discount_pct(rep: int) -> int:
	if rep >= 600:
		return 15
	if rep >= 300:
		return 10
	if rep >= 100:
		return 5
	return 0



func _discounted_buy_price(base: int, discount_pct: int) -> int:
	base = maxi(base, 0)
	if discount_pct <= 0:
		return maxi(base, 0)
	# Floor gold at least 1 when base > 0.
	if base <= 0:
		return 0
	return maxi(1, (base * (100 - discount_pct)) / 100)



func snapshot_shop(shop_id: String = "starter_goods") -> Dictionary:
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		shop_id = "starter_goods"
	var rep: int = get_vendor_rep(shop_id)
	var pct: int = _vendor_discount_pct(rep)
	var listings: Array = []
	if ctrl.shop_catalog != null and ctrl.shop_catalog.has_shop(shop_id):
		for row_v in ctrl.shop_catalog.build_listings(shop_id):
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = (row_v as Dictionary).duplicate(true)
			var base: int = int(row.get("buy_price", 0))
			row["base_buy_price"] = base
			row["buy_price"] = _discounted_buy_price(base, pct)
			listings.append(row)
	return {
		"shop_id": shop_id,
		"title": ctrl.shop_catalog.shop_title(shop_id) if ctrl.shop_catalog != null else shop_id,
		"listings": listings,
		"gold": ctrl.inventory.get_gold() if ctrl.inventory != null else 0,
		"vendor_rep": rep,
		"discount_pct": pct,
		"buyback": snapshot_shop_buyback(),
	}



func _build_open_shop_payload(shop_id: String) -> Dictionary:
	ctrl._active_shop_id = shop_id.strip_edges()
	var snap: Dictionary = snapshot_shop(shop_id)
	return {
		"type": "open_shop",
		"shop_id": str(snap.get("shop_id", shop_id)),
		"title": str(snap.get("title", shop_id)),
		"listings": snap.get("listings", []) if typeof(snap.get("listings", [])) == TYPE_ARRAY else [],
		"gold": int(snap.get("gold", 0)),
		"vendor_rep": int(snap.get("vendor_rep", 0)),
		"discount_pct": int(snap.get("discount_pct", 0)),
		"buyback": snap.get("buyback", []) if typeof(snap.get("buyback", [])) == TYPE_ARRAY else [],
	}



func _add_vendor_rep(shop_id: String, delta: int) -> Array:
	var actions: Array = []
	if delta == 0:
		return actions
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		return actions
	var before: int = get_vendor_rep(shop_id)
	var after: int = clampi(before + delta, 0, 1000)
	set_vendor_rep(shop_id, after)
	for thr in [100, 300, 600]:
		if before < thr and after >= thr:
			actions.append({"type": "system_message", "text": "声望提升"})
	return actions



func try_shop_buy(shop_id: String, item_id: String, qty: int = 1) -> Dictionary:
	shop_id = shop_id.strip_edges()
	item_id = item_id.strip_edges()
	qty = maxi(qty, 1)
	var actions: Array = []
	if ctrl.shop_catalog == null or ctrl.inventory == null:
		return {"ok": false, "reason": "no_shop", "actions": [{"type": "system_message", "text": "商店不可用。"}]}
	if not ctrl.shop_catalog.has_shop(shop_id) or not ctrl.shop_catalog.sells_item(shop_id, item_id):
		actions.append({"type": "system_message", "text": "该商店不出售此物品。"})
		return {"ok": false, "reason": "not_sold", "actions": actions}
	var base_unit: int = ctrl.shop_catalog.buy_price_for(shop_id, item_id)
	if base_unit < 0:
		actions.append({"type": "system_message", "text": "价格无效。"})
		return {"ok": false, "reason": "bad_price", "actions": actions}
	var unit: int = _discounted_buy_price(base_unit, _vendor_discount_pct(get_vendor_rep(shop_id)))
	var total: int = unit * qty
	if not ctrl.inventory.try_spend_gold(total):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % total})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(item_id, qty)
	var added: int = int(add_r.get("added", 0))
	if added <= 0:
		# Refund — use real try_add reason (stack merge path already handled when room exists).
		ctrl.inventory.add_gold(total)
		var reason = str(add_r.get("reason", "bag_full"))
		var msg = "背包已满，无法购买。"
		if reason == "stack_full":
			msg = "该物品已达堆叠上限，无法购买。"
		elif reason == "invalid":
			msg = "无法购买该物品。"
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason if reason != "" else "bag_full", "actions": actions}
	if added < qty:
		# Partial: refund unused
		var refund: int = unit * (qty - added)
		ctrl.inventory.add_gold(refund)
		total = unit * added
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "购买了 %s×%d（-%d 金币）" % [ctrl.item_display_name(item_id), added, total],
	})
	# +1 rep per purchase (not per unit); threshold msgs before refresh.
	actions.append_array(_add_vendor_rep(shop_id, 1))
	# Refresh shop gold / discounted listings / rep for client.
	actions.append(_build_open_shop_payload(shop_id))
	return {"ok": true, "actions": actions, "unit_price": unit, "paid": total, "vendor_rep": get_vendor_rep(shop_id)}



func try_shop_sell(item_id: String, qty: int = 1) -> Dictionary:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 1)
	var actions: Array = []
	if ctrl.inventory == null or ctrl.item_catalog == null:
		return {"ok": false, "reason": "no_inv", "actions": [{"type": "system_message", "text": "无法出售。"}]}
	var def: Dictionary = ctrl.item_catalog.get_item(item_id)
	if def.is_empty():
		actions.append({"type": "system_message", "text": "未知物品。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	var sell_price: int = maxi(int(def.get("sell_price", 0)), 0)
	if sell_price <= 0:
		actions.append({"type": "system_message", "text": "该物品无法出售。"})
		return {"ok": false, "reason": "no_sell", "actions": actions}
	if ctrl.inventory.has_method("is_locked") and ctrl.inventory.is_locked(item_id):
		actions.append({"type": "system_message", "text": "该物品已锁定，无法出售。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	# BoP bound stacks cannot be vendor-sold (BoE bound still can).
	if ctrl._item_binds_on_pickup(item_id):
		var unbound: int = ctrl.inventory.unbound_qty(item_id) if ctrl.inventory.has_method("unbound_qty") else 0
		if unbound < qty:
			actions.append({"type": "system_message", "text": "已绑定，无法出售。"})
			return {"ok": false, "reason": "bound", "actions": actions}
	if not ctrl.inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "not_in_bag", "actions": actions}
	if not ctrl.inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "出售失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var gained: int = sell_price * qty
	ctrl.inventory.add_gold(gained)
	_push_shop_buyback(item_id, qty, sell_price)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "出售了 %s×%d（+%d 金币）" % [ctrl.item_display_name(item_id), qty, gained],
	})
	# Small sell rep: +1 when a vendor shop is active.
	if ctrl._active_shop_id != "":
		actions.append_array(_add_vendor_rep(ctrl._active_shop_id, 1))
	actions.append(_shop_buyback_action())
	return {"ok": true, "actions": actions}



func try_shop_sell_junk() -> Dictionary:
	var actions: Array = []
	if ctrl.inventory == null or ctrl.item_catalog == null:
		return {"ok": false, "reason": "no_inv", "actions": [{"type": "system_message", "text": "无法出售。"}]}
	var total_gained = 0
	var sold_any = false
	# Snapshot first — consume mutates bag stacks.
	var rows: Array = ctrl.inventory.snapshot()
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var iid = str(row.get("id", "")).strip_edges()
		var qty: int = int(row.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		if not _is_shop_junk_item(iid):
			continue
		if ctrl.inventory.has_method("is_locked") and ctrl.inventory.is_locked(iid):
			continue
		if bool(row.get("locked", false)):
			continue
		if bool(row.get("bound", false)) and ctrl._item_binds_on_pickup(iid):
			continue
		var unit: int = _shop_junk_unit_price(iid)
		if unit <= 0 or unit > 10:
			continue
		# Re-check live qty (snapshot may be stale vs earlier consumes of same id).
		var have: int = ctrl.inventory.get_qty(iid) if ctrl.inventory.has_method("get_qty") else qty
		if have <= 0:
			continue
		var take: int = have
		if not ctrl.inventory.consume(iid, take):
			continue
		var gained: int = unit * take
		total_gained += gained
		sold_any = true
		_push_shop_buyback(iid, take, unit)
	if not sold_any:
		actions.append({"type": "system_message", "text": "没有可出售的垃圾。"})
		return {"ok": false, "reason": "no_junk", "actions": actions, "gained": 0}
	ctrl.inventory.add_gold(total_gained)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "出售垃圾获得 %d 金。" % total_gained,
	})
	actions.append(_shop_buyback_action())
	return {"ok": true, "actions": actions, "gained": total_gained}



func _shop_junk_unit_price(item_id: String) -> int:
	var def: Dictionary = ctrl.item_catalog.get_item(item_id) if ctrl.item_catalog != null else {}
	if def.is_empty():
		return 0
	var sp: int = int(def.get("sell_price", -1))
	if sp < 0:
		sp = int(def.get("price", 0))
	return maxi(sp, 0)



func _is_shop_junk_item(item_id: String) -> bool:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return false
	if item_id in ["pet_whistle", "scroll_town"]:
		return false
	if item_id.begins_with("potion_") or item_id.begins_with("food_") or item_id.begins_with("fish_"):
		return false
	var def: Dictionary = ctrl.item_catalog.get_item(item_id) if ctrl.item_catalog != null else {}
	if def.is_empty():
		return false
	# Catalog field is `type`; accept `kind` if present.
	var kind = str(def.get("kind", "")).strip_edges().to_lower()
	if kind.is_empty():
		kind = str(def.get("type", "")).strip_edges().to_lower()
	if kind not in ["misc", "material"]:
		return false
	var unit: int = _shop_junk_unit_price(item_id)
	return unit > 0 and unit <= 10



func snapshot_shop_buyback() -> Array:
	return ctrl._shop_buyback.duplicate(true)



func _clear_shop_session_buyback() -> void:
	ctrl._shop_buyback.clear()
	ctrl._active_shop_id = ""



func try_shop_close() -> Dictionary:
	# Keep buyback until map transfer / ring overwrite — accidental close must not wipe it.
	return {"ok": true, "actions": [_shop_buyback_action()]}



func _push_shop_buyback(item_id: String, qty: int, unit_price: int, bound: bool = false) -> void:
	ctrl._shop_buyback.insert(0, {
		"item_id": item_id,
		"qty": qty,
		"unit_price": unit_price,
		"price": unit_price * qty,  # total buyback cost (= sell gold gained)
		"name": ctrl.item_display_name(item_id),
		"bound": bound,
	})
	while ctrl._shop_buyback.size() > BUYBACK_MAX:
		ctrl._shop_buyback.pop_back()



func _shop_buyback_action() -> Dictionary:
	return {"type": "shop_buyback", "buyback": snapshot_shop_buyback(), "gold": ctrl.inventory.get_gold() if ctrl.inventory else 0}



func try_shop_buyback(index: int, qty: int = -1) -> Dictionary:
	var actions: Array = []
	if ctrl.inventory == null:
		return {"ok": false, "reason": "no_inv", "actions": [{"type": "system_message", "text": "无法回购。"}]}
	if ctrl._shop_buyback.is_empty() or index < 0 or index >= ctrl._shop_buyback.size():
		actions.append({"type": "system_message", "text": "没有可回购的物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var row: Dictionary = ctrl._shop_buyback[index]
	var iid = str(row.get("item_id", "")).strip_edges()
	var have: int = maxi(int(row.get("qty", 0)), 0)
	var unit: int = maxi(int(row.get("unit_price", 0)), 0)
	var take: int = have if qty < 0 else clampi(qty, 1, have)
	if iid.is_empty() or take <= 0:
		actions.append({"type": "system_message", "text": "没有可回购的物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var total: int = unit * take
	if not ctrl.inventory.try_spend_gold(total):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	# Respect bind: BoP always returns bound; otherwise restore sold bound flag.
	var restore_bound = bool(row.get("bound", false))
	if ctrl._item_binds_on_pickup(iid):
		restore_bound = true
	var add_r: Dictionary = ctrl.inventory.try_add_item(iid, take, restore_bound)
	var added: int = int(add_r.get("added", 0))
	if added <= 0:
		ctrl.inventory.add_gold(total)
		actions.append({"type": "system_message", "text": "背包已满，无法回购。"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	if added < take:
		ctrl.inventory.add_gold(unit * (take - added))
		take = added
		total = unit * take
	var left: int = have - take
	if left <= 0:
		ctrl._shop_buyback.remove_at(index)
	else:
		row["qty"] = left
		row["price"] = unit * left
		ctrl._shop_buyback[index] = row
	var nm = ctrl.item_display_name(iid)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append(_shop_buyback_action())
	actions.append({"type": "system_message", "text": "已回购：%s" % nm})
	return {"ok": true, "actions": actions, "item_id": iid, "qty": take, "paid": total}



func try_auction_buy(listing_id: String) -> Dictionary:
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
	if seller_id == self_id or seller_id == "player":
		actions.append({"type": "system_message", "text": "不能购买自己的拍卖品，请使用下架。"})
		return {"ok": false, "reason": "own_listing", "actions": actions}
	var iid = str(listing.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(listing.get("qty", 0)), 0)
	var price: int = maxi(int(listing.get("price_gold", 0)), 0)
	var iname = str(listing.get("item_name", "")).strip_edges()
	if iname.is_empty():
		iname = ctrl.item_display_name(iid)
	if iid.is_empty() or qty <= 0 or price <= 0:
		actions.append({"type": "system_message", "text": "拍卖数据无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory.get_gold() < price:
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % price})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if ctrl.inventory.has_method("can_accept") and not ctrl.inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满，无法购买。"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	if not ctrl.inventory.try_spend_gold(price):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % price})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var rem: Dictionary = ctrl.auction.try_remove(listing_id)
	if not bool(rem.get("ok", false)):
		ctrl.inventory.add_gold(price)
		actions.append({"type": "system_message", "text": "购买失败，拍卖品已不存在。"})
		actions.append_array(ctrl._auction_inventory_actions())
		return {"ok": false, "reason": "not_found", "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		# Rollback: restore listing + refund gold; reverse partial add.
		if added > 0:
			ctrl.inventory.consume(iid, added)
		ctrl.inventory.add_gold(price)
		ctrl.auction.try_add(
			seller_id,
			str(listing.get("seller_name", "")),
			iid,
			iname,
			qty,
			price,
		)
		var reason = str(add_r.get("reason", "bag_full"))
		var msg = "背包已满，无法购买。"
		if reason == "stack_full":
			msg = "该物品已达堆叠上限，无法购买。"
		actions.append({"type": "system_message", "text": msg})
		actions.append_array(ctrl._auction_inventory_actions())
		return {"ok": false, "reason": reason if reason != "" else "bag_full", "actions": actions}
	# Player sellers: credit gold (shell single-player rarely hits this path).
	if not seller_id.begins_with("npc_") and seller_id != self_id:
		pass  # remote stub seller — gold retained by house
	actions.append_array(ctrl._auction_inventory_actions())
	actions.append({"type": "system_message", "text": "已购买【%s】×%d（-%d 金币）。" % [iname, qty, price]})
	return {"ok": true, "actions": actions}


