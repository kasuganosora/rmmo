extends SceneTree
## Headless: bind-on-equip — first equip binds; trade/auction/mail blocked when bound;
## unbound BoE still tradable; non-bind gear unaffected; shop sell allowed.


func _init() -> void:
	call_deferred("_run")


const EquipmentScript = preload("res://scripts/net/combat/equipment.gd")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_bind_equip: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.equipment == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.inventory == null or srv.equipment == null or srv.item_catalog == null:
		print("test_bind_equip: FAIL combat layers missing")
		quit(1)
		return

	failed += _expect(srv.item_catalog.has_item("wooden_sword"), "catalog wooden_sword")
	failed += _expect(srv.item_catalog.has_item("leather_vest"), "catalog leather_vest")
	failed += _expect(srv.item_catalog.has_item("leather_gloves"), "catalog leather_gloves")
	var ws: Dictionary = srv.item_catalog.get_item("wooden_sword")
	var lv: Dictionary = srv.item_catalog.get_item("leather_vest")
	var lg: Dictionary = srv.item_catalog.get_item("leather_gloves")
	failed += _expect(EquipmentScript.is_bind_on_equip(ws), "wooden_sword is BoE")
	failed += _expect(EquipmentScript.is_bind_on_equip(lv), "leather_vest is BoE")
	failed += _expect(not EquipmentScript.is_bind_on_equip(lg), "leather_gloves not BoE")

	# --- Equip binds ---
	srv.inventory.clear()
	srv.equipment.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("wooden_sword", 1)
	failed += _expect(not srv.inventory.is_bound("wooden_sword"), "sword starts unbound")
	var eq: Dictionary = srv.try_equip_item("wooden_sword")
	failed += _expect(bool(eq.get("ok", false)), "equip sword ok")
	failed += _expect(bool(eq.get("newly_bound", false)), "newly_bound true")
	failed += _expect(bool(eq.get("bound", false)), "equipped bound")
	failed += _expect(_has_sys(eq, "已绑定"), "bind system_message once")
	var slot := str(eq.get("slot", ""))
	failed += _expect(not slot.is_empty(), "equip slot set")
	failed += _expect(srv.equipment.is_slot_bound(slot), "slot marked bound")

	# Unequip keeps bound in bag
	var uq: Dictionary = srv.try_unequip_item(slot)
	failed += _expect(bool(uq.get("ok", false)), "unequip ok")
	failed += _expect(srv.inventory.is_bound("wooden_sword"), "bag keeps bound")
	failed += _expect(srv.inventory.has_item("wooden_sword", 1), "sword back in bag")
	var found_bound := false
	for row in srv.inventory.snapshot():
		if typeof(row) == TYPE_DICTIONARY and str(row.get("id", "")) == "wooden_sword":
			if bool(row.get("bound", false)):
				found_bound = true
	failed += _expect(found_bound, "snapshot has bound")

	# Re-equip bound piece: no second bind message
	var eq2: Dictionary = srv.try_equip_item("wooden_sword")
	failed += _expect(bool(eq2.get("ok", false)), "re-equip ok")
	failed += _expect(not bool(eq2.get("newly_bound", false)), "no second newly_bound")
	failed += _expect(not _has_sys(eq2, "已绑定"), "no repeat bind msg")
	srv.try_unequip_item(str(eq2.get("slot", slot)))

	# --- Bound: trade / auction / mail blocked ---
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()
	elif srv.in_trade():
		srv.try_trade_cancel()
	var op: Dictionary = srv.try_trade_open("绑定测试商人")
	failed += _expect(bool(op.get("ok", false)), "trade open")
	var putb: Dictionary = srv.try_trade_put_item("wooden_sword", 1)
	failed += _expect(not bool(putb.get("ok", false)), "trade rejects bound")
	failed += _expect(str(putb.get("reason", "")) == "bound", "trade reason bound")
	failed += _expect(srv.inventory.has_item("wooden_sword", 1), "trade did not consume")
	if srv.in_trade():
		srv.try_trade_cancel()

	if srv.auction != null and srv.auction.has_method("clear"):
		srv.auction.clear()
	var auc: Dictionary = srv.try_auction_list("wooden_sword", 1, 50)
	failed += _expect(not bool(auc.get("ok", false)), "auction rejects bound")
	failed += _expect(str(auc.get("reason", "")) == "bound", "auction reason bound")
	failed += _expect(srv.inventory.has_item("wooden_sword", 1), "auction did not consume")

	var self_name := "你"
	if srv.has_method("_party_self_name"):
		self_name = str(srv._party_self_name())
	var mail: Dictionary = srv.try_mail_send(self_name, "绑测", "body", 0, "wooden_sword", 1)
	failed += _expect(not bool(mail.get("ok", false)), "mail rejects bound")
	failed += _expect(str(mail.get("reason", "")) == "bound", "mail reason bound")
	failed += _expect(srv.inventory.has_item("wooden_sword", 1), "mail did not consume")

	# Shop sell still OK for bound
	var gold0: int = srv.inventory.get_gold()
	var sell: Dictionary = srv.try_shop_sell("wooden_sword", 1)
	failed += _expect(bool(sell.get("ok", false)), "shop sell bound ok")
	failed += _expect(srv.inventory.get_gold() > gold0, "sell gained gold")
	failed += _expect(not srv.inventory.has_item("wooden_sword", 1), "sold sword gone")

	# --- Unbound BoE still tradable ---
	srv.inventory.clear()
	srv.equipment.clear()
	srv.inventory.add_gold(100)
	srv.inventory.add_item("leather_vest", 1)
	failed += _expect(not srv.inventory.is_bound("leather_vest"), "vest unbound")
	failed += _expect(srv.inventory.can_transfer("leather_vest", 1), "vest transferable")
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()
	var op2: Dictionary = srv.try_trade_open("未绑定商人")
	failed += _expect(bool(op2.get("ok", false)), "trade open unbound")
	var putu: Dictionary = srv.try_trade_put_item("leather_vest", 1)
	failed += _expect(bool(putu.get("ok", false)), "trade accepts unbound BoE")
	failed += _expect(not srv.inventory.has_item("leather_vest", 1), "vest escrowed")
	if srv.in_trade():
		srv.try_trade_cancel()
	failed += _expect(srv.inventory.has_item("leather_vest", 1), "cancel refunds vest")
	failed += _expect(not srv.inventory.is_bound("leather_vest"), "refund still unbound")

	# --- Non-bind gear unaffected ---
	srv.inventory.clear()
	srv.equipment.clear()
	srv.inventory.add_item("leather_gloves", 1)
	var eqg: Dictionary = srv.try_equip_item("leather_gloves")
	failed += _expect(bool(eqg.get("ok", false)), "equip gloves ok")
	failed += _expect(not bool(eqg.get("newly_bound", false)), "gloves not newly_bound")
	failed += _expect(not _has_sys(eqg, "已绑定"), "gloves no bind msg")
	var gslot := str(eqg.get("slot", ""))
	failed += _expect(gslot.is_empty() or not srv.equipment.is_slot_bound(gslot), "gloves slot unbound")
	if not gslot.is_empty():
		srv.try_unequip_item(gslot)
	failed += _expect(not srv.inventory.is_bound("leather_gloves"), "gloves bag unbound")
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()
	srv.try_trade_open("手套商人")
	var putg: Dictionary = srv.try_trade_put_item("leather_gloves", 1)
	failed += _expect(bool(putg.get("ok", false)), "gloves tradable after equip")
	if srv.in_trade():
		srv.try_trade_cancel()

	# Snapshot tip flags
	srv.inventory.clear()
	srv.inventory.add_item("wooden_sword", 1)
	failed += _expect(not bool(srv.inventory.snapshot()[0].get("bound", false)), "tip unbound flag")
	srv.inventory.add_item("wooden_sword", 1, true)
	var any_bound_row := false
	for r in srv.inventory.snapshot():
		if typeof(r) == TYPE_DICTIONARY and str(r.get("id", "")) == "wooden_sword" and bool(r.get("bound", false)):
			any_bound_row = true
	failed += _expect(any_bound_row, "tip bound flag in snapshot")

	if failed == 0:
		print("test_bind_equip: PASS")
		quit(0)
		return
	print("test_bind_equip: FAIL count=%d" % failed)
	quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _has_sys(result: Dictionary, needle: String) -> bool:
	var actions: Array = result.get("actions", [])
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		var txt := str(a.get("text", ""))
		if txt.find(needle) >= 0:
			return true
	return false
