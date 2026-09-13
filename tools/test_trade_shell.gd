extends SceneTree
## Headless: MockServer player trade shell (stub partner + escrow).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_trade_shell: FAIL no MockServer")
		quit(1)
		return
	if srv.has_method("_trade_force_cancel_silent"):
		srv._trade_force_cancel_silent()
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	# Seed bag + gold
	srv.inventory.add_item("potion_hp_small", 3)
	srv.inventory.add_gold(50)
	var gold0: int = srv.inventory.get_gold()
	var hp0: int = srv.inventory.get_qty("potion_hp_small")

	failed += _expect(srv.has_method("try_trade_open"), "has open")
	failed += _expect(srv.has_method("try_trade_confirm"), "has confirm")
	failed += _expect(not srv.in_trade(), "not in trade")

	var op: Dictionary = srv.try_trade_open("测试商人")
	failed += _expect(bool(op.get("ok", false)), "open ok")
	failed += _expect(srv.in_trade(), "in trade")
	failed += _expect(_has(op, "trade_update"), "open trade_update")
	var snap: Dictionary = srv.snapshot_trade()
	failed += _expect(bool(snap.get("active", false)), "snap active")
	failed += _expect(str(snap.get("partner_name", "")) == "测试商人", "partner name")

	var put: Dictionary = srv.try_trade_put_item("potion_hp_small", 2)
	failed += _expect(bool(put.get("ok", false)), "put ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == hp0 - 2, "escrow removed from bag")
	failed += _expect(_has(put, "inventory_update"), "put inv update")
	var my_items: Array = srv.snapshot_trade().get("my_items", [])
	failed += _expect(my_items.size() == 1, "one offer stack")
	failed += _expect(int(my_items[0].get("qty", 0)) == 2, "offer qty 2")

	var gold: Dictionary = srv.try_trade_set_gold(10)
	failed += _expect(bool(gold.get("ok", false)), "set gold ok")
	failed += _expect(srv.inventory.get_gold() == gold0 - 10, "gold escrowed")
	failed += _expect(int(srv.snapshot_trade().get("my_gold", 0)) == 10, "my_gold 10")

	var ready: Dictionary = srv.try_trade_ready(true)
	failed += _expect(bool(ready.get("ok", false)), "ready ok")
	var snap2: Dictionary = srv.snapshot_trade()
	failed += _expect(bool(snap2.get("my_ready", false)), "my ready")
	failed += _expect(bool(snap2.get("their_ready", false)), "their ready")
	failed += _expect(int(snap2.get("their_gold", 0)) == 15, "stub gold")
	var their: Array = snap2.get("their_items", [])
	failed += _expect(their.size() >= 1, "stub item")

	var conf: Dictionary = srv.try_trade_confirm()
	failed += _expect(bool(conf.get("ok", false)), "confirm ok")
	failed += _expect(not srv.in_trade(), "closed after confirm")
	failed += _expect(_has(conf, "trade_close"), "trade_close")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == hp0 - 2, "gave away 2 hp pots")
	failed += _expect(srv.inventory.get_qty("potion_mp_small") >= 1, "got mp pot")
	failed += _expect(srv.inventory.get_gold() == gold0 - 10 + 15, "gold net +5")

	# cancel refunds
	srv.try_trade_open("")
	srv.try_trade_put_item("potion_hp_small", 1)
	var q_before: int = srv.inventory.get_qty("potion_hp_small")
	var cancel: Dictionary = srv.try_trade_cancel()
	failed += _expect(bool(cancel.get("ok", false)), "cancel ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == q_before + 1, "cancel refunds item")

	if failed == 0:
		print("test_trade_shell: PASS")
		quit(0)
		return
	print("test_trade_shell: FAIL count=%d" % failed)
	quit(1)


func _has(result: Dictionary, typ: String) -> bool:
	for a in result.get("actions", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == typ:
			return true
	return false


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1
