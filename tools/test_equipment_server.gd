extends SceneTree
## MockServer try_equip_item / try_unequip_item wiring.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await process_frame
	var Net = load("res://scripts/net/net.gd")
	var srv = Net.server()
	var failed := 0
	if srv == null:
		print("FAIL no server")
		quit(1)
		return
	# Ensure starter after enter_world-like reset
	if srv.inventory != null:
		srv.inventory.clear()
		srv.inventory.grant_starter()
	if srv.equipment != null:
		srv.equipment.clear()
	failed += _expect(srv.inventory.get_qty("wooden_sword") >= 1, "starter sword")
	var r: Dictionary = srv.try_equip_item("wooden_sword", "weapon_main")
	failed += _expect(bool(r.get("ok", false)), "try_equip ok")
	var actions: Array = r.get("actions", [])
	var has_inv := false
	var has_eq := false
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "inventory_update":
			has_inv = true
		if t == "equipment_update":
			has_eq = true
			failed += _expect((a.get("equipment") as Array).size() == 12, "eq snapshot 12")
			failed += _expect(int((a.get("bonuses") as Dictionary).get("p_atk", 0)) == 3, "bonus p_atk")
	failed += _expect(has_inv and has_eq, "emits inv+eq updates")
	failed += _expect(srv.equipment.get_item_in("weapon_main") == "wooden_sword", "server slot set")
	# Incompatible
	r = srv.try_equip_item("leather_vest", "head")
	failed += _expect(not bool(r.get("ok", false)), "vest reject head")
	# Unequip
	r = srv.try_unequip_item("weapon_main")
	failed += _expect(bool(r.get("ok", false)), "unequip ok")
	failed += _expect(srv.inventory.get_qty("wooden_sword") >= 1, "sword returned")
	# Toggle via try_use_item / try_toggle_equip
	r = srv.try_toggle_equip("wooden_sword")
	failed += _expect(bool(r.get("ok", false)), "toggle equip ok")
	failed += _expect(srv.equipment.get_item_in("weapon_main") == "wooden_sword", "toggle equipped")
	r = srv.try_use_item("wooden_sword")
	failed += _expect(bool(r.get("ok", false)), "use_item toggles unequip")
	failed += _expect(srv.equipment.is_empty("weapon_main"), "toggled off")
	failed += _expect(srv.inventory.get_qty("wooden_sword") >= 1, "sword back after toggle")
	if failed == 0:
		print("test_equipment_server: PASS")
		quit(0)
	else:
		print("test_equipment_server: FAIL count=", failed)
		quit(1)

func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK ", label)
		return 0
	print("  FAIL ", label)
	return 1
