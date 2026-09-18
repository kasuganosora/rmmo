extends SceneTree
## Headless: MockServer warehouse deposit/withdraw + full/reject.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_warehouse: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.warehouse == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	# Fresh bags
	srv.warehouse.clear()
	srv.inventory.clear()
	srv.inventory.add_gold(200)
	srv.inventory.add_item("potion_hp_small", 5)

	failed += _expect(srv.has_method("try_warehouse_deposit"), "has deposit")
	failed += _expect(srv.has_method("try_warehouse_withdraw"), "has withdraw")
	failed += _expect(srv.has_method("try_warehouse_deposit_gold"), "has deposit gold")
	failed += _expect(srv.has_method("try_warehouse_withdraw_gold"), "has withdraw gold")
	failed += _expect(srv.has_method("snapshot_warehouse"), "has snapshot")

	var snap0: Dictionary = srv.snapshot_warehouse()
	failed += _expect(int(snap0.get("used_slots", -1)) == 0, "empty used_slots")
	failed += _expect(int(snap0.get("gold", -1)) == 0, "empty gold")
	failed += _expect(int(snap0.get("max_slots", 0)) >= 40, "capacity set")

	var dep: Dictionary = srv.try_warehouse_deposit("potion_hp_small", 2)
	failed += _expect(bool(dep.get("ok", false)), "deposit ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 3, "bag left 3")
	failed += _expect(srv.warehouse.get_qty("potion_hp_small") == 2, "wh has 2")
	failed += _expect(_has(dep, "warehouse_update"), "deposit warehouse_update")
	failed += _expect(_has(dep, "inventory_update"), "deposit inventory_update")

	var bad_qty: Dictionary = srv.try_warehouse_deposit("potion_hp_small", 0)
	failed += _expect(not bool(bad_qty.get("ok", true)), "reject qty 0")
	failed += _expect(str(bad_qty.get("reason", "")) == "invalid", "reason invalid")

	var bad_item: Dictionary = srv.try_warehouse_deposit("potion_hp_small", 99)
	failed += _expect(not bool(bad_item.get("ok", true)), "reject missing qty")

	var wd: Dictionary = srv.try_warehouse_withdraw("potion_hp_small", 1)
	failed += _expect(bool(wd.get("ok", false)), "withdraw ok")
	failed += _expect(srv.inventory.get_qty("potion_hp_small") == 4, "bag back to 4")
	failed += _expect(srv.warehouse.get_qty("potion_hp_small") == 1, "wh left 1")

	var g0: int = srv.inventory.get_gold()
	var gd: Dictionary = srv.try_warehouse_deposit_gold(50)
	failed += _expect(bool(gd.get("ok", false)), "deposit gold ok")
	failed += _expect(srv.inventory.get_gold() == g0 - 50, "bag gold -50")
	failed += _expect(srv.warehouse.get_gold() == 50, "wh gold 50")
	var gw: Dictionary = srv.try_warehouse_withdraw_gold(20)
	failed += _expect(bool(gw.get("ok", false)), "withdraw gold ok")
	failed += _expect(srv.warehouse.get_gold() == 30, "wh gold 30")
	failed += _expect(srv.inventory.get_gold() == g0 - 30, "bag gold after withdraw")

	# Warehouse full: shrink capacity to 1 occupied slot, then reject new id.
	srv.warehouse.clear()
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 1)
	srv.inventory.add_item("potion_mp_small", 1)
	srv.warehouse.max_slots = 1
	var d1: Dictionary = srv.try_warehouse_deposit("potion_hp_small", 1)
	failed += _expect(bool(d1.get("ok", false)), "fill single slot")
	var full: Dictionary = srv.try_warehouse_deposit("potion_mp_small", 1)
	failed += _expect(not bool(full.get("ok", true)), "reject when warehouse full")
	failed += _expect(str(full.get("reason", "")) == "warehouse_full", "reason warehouse_full")
	failed += _expect(srv.inventory.get_qty("potion_mp_small") == 1, "item stays in bag on reject")
	srv.warehouse.max_slots = 60

	# Bag full reject on withdraw
	srv.warehouse.clear()
	srv.inventory.clear()
	srv.warehouse.add_item("potion_mp_small", 1)
	srv.inventory.max_slots = 1
	srv.inventory.add_item("potion_hp_small", 1)
	var bag_full: Dictionary = srv.try_warehouse_withdraw("potion_mp_small", 1)
	failed += _expect(not bool(bag_full.get("ok", true)), "reject withdraw into full bag")
	failed += _expect(str(bag_full.get("reason", "")) == "bag_full", "reason bag_full")
	failed += _expect(srv.warehouse.get_qty("potion_mp_small") == 1, "item stays in warehouse")
	srv.inventory.max_slots = 40

	# In-memory survives map transfer (not cleared except enter_world).
	srv.warehouse.clear()
	srv.inventory.clear()
	srv.inventory.add_item("potion_hp_small", 2)
	srv.try_warehouse_deposit("potion_hp_small", 2)
	failed += _expect(srv.warehouse.get_qty("potion_hp_small") == 2, "pre-transfer qty")
	failed += _expect(srv.warehouse.get_qty("potion_hp_small") == 2, "survives session transfer")

	# Spawn snapshot includes warehouse
	var snap: Dictionary = srv.snapshot_warehouse()
	failed += _expect(typeof(snap.get("items", null)) == TYPE_ARRAY, "snap items array")
	failed += _expect(int(snap.get("used_slots", 0)) == 1, "snap used 1")

	if failed == 0:
		print("test_warehouse: PASS")
		quit(0)
		return
	print("test_warehouse: FAIL count=%d" % failed)
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
