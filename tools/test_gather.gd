extends SceneTree
## Headless: MockServer try_gather — success, deplete, fail while depleted, respawn (force).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_gather: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.gather_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_gather"), "has try_gather")
	failed += _expect(srv.gather_catalog != null, "gather_catalog loaded")
	failed += _expect(srv.gather_catalog.has_node("herb_a"), "catalog herb_a")
	failed += _expect(srv.gather_catalog.has_node("herb_b"), "catalog herb_b")
	failed += _expect(srv.gather_catalog.has_node("herb_c"), "catalog herb_c")

	# Load demo pack so map_id + gather nodes activate.
	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	failed += _expect(srv._gather_nodes.has("herb_a"), "map loaded herb_a")
	failed += _expect(srv._gather_nodes.has("herb_b"), "map loaded herb_b")
	failed += _expect(srv._gather_nodes.has("herb_c"), "map loaded herb_c")

	# Place player adjacent to herb_a (10,22).
	srv.set_player_cell(10, 21)
	# Register NPC so try_interact range also works.
	if srv.has_method("register_npc"):
		srv.register_npc("herb_a", 10, 22, false, false, 2, 0, 0, {
			"id": "herb_a",
			"name": "野生药草",
			"kind": "object",
			"interact_text": "一丛野生药草。",
		})

	srv.inventory.clear()
	srv.inventory.add_gold(10)
	var before: int = srv.inventory.get_qty("wild_herb")

	# --- success ---
	var ok1: Dictionary = srv.try_gather("herb_a")
	failed += _expect(bool(ok1.get("ok", false)), "gather success")
	failed += _expect(str(ok1.get("item_id", "")) != "", "yielded item_id")
	failed += _expect(int(ok1.get("qty", 0)) >= 1, "yielded qty>=1")
	var iid := str(ok1.get("item_id", ""))
	failed += _expect(srv.inventory.get_qty(iid) == before + int(ok1.get("qty", 0)), "bag gained yield")
	failed += _expect(_msg_has(ok1, "采集获得："), "msg 采集获得")
	failed += _expect(_has_type(ok1, "inventory_update"), "inventory_update")
	failed += _expect(_has_type(ok1, "gather_update"), "gather_update deplete")
	failed += _expect(srv.is_gather_depleted("herb_a"), "depleted after gather")

	# --- fail while depleted ---
	var fail_d: Dictionary = srv.try_gather("herb_a")
	failed += _expect(not bool(fail_d.get("ok", true)), "depleted fails")
	failed += _expect(str(fail_d.get("reason", "")) == "depleted", "reason depleted")
	failed += _expect(_msg_has(fail_d, "资源尚未恢复"), "msg 资源尚未恢复")

	# try_interact routes to gather
	var ir: Dictionary = srv.try_interact("herb_a", 10, 21)
	failed += _expect(not bool(ir.get("ok", true)), "interact while depleted fails")
	failed += _expect(_msg_has(ir, "资源尚未恢复"), "interact msg 资源尚未恢复")

	# --- force respawn ---
	failed += _expect(srv.has_method("force_gather_respawn"), "has force_gather_respawn")
	var ra: Array = srv.force_gather_respawn("herb_a")
	failed += _expect(not srv.is_gather_depleted("herb_a"), "respawned")
	failed += _expect(not ra.is_empty(), "respawn actions")
	var restored := false
	for a in ra:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "gather_update":
			if not bool(a.get("depleted", true)):
				restored = true
	failed += _expect(restored, "gather_update restored")

	# Gather again after respawn
	var ok2: Dictionary = srv.try_gather("herb_a")
	failed += _expect(bool(ok2.get("ok", false)), "gather after respawn")
	failed += _expect(srv.is_gather_depleted("herb_a"), "depleted again")

	# --- bag full ---
	srv.force_gather_respawn("herb_a")
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.max_slots = 1
	# Fill the only slot with a different stack-maxed item.
	srv.inventory.add_item("rusty_coin", 99)
	# Ensure wild_herb cannot merge (different id) and no free slot.
	var full: Dictionary = srv.try_gather("herb_a")
	failed += _expect(not bool(full.get("ok", true)), "bag full fails")
	failed += _expect(str(full.get("reason", "")) == "bag_full", "reason bag_full")
	failed += _expect(_msg_has(full, "背包已满"), "msg 背包已满")
	failed += _expect(not srv.is_gather_depleted("herb_a"), "not depleted on bag full")
	srv.inventory.max_slots = 40

	# --- tick respawn path (mock clock via ready_at in past) ---
	srv.force_gather_respawn("herb_b")
	srv.set_player_cell(8, 21)
	if srv.has_method("register_npc"):
		srv.register_npc("herb_b", 8, 22, false, false, 2, 0, 0, {"id": "herb_b", "name": "野生药草", "kind": "object"})
	srv.inventory.clear()
	var gb: Dictionary = srv.try_gather("herb_b")
	failed += _expect(bool(gb.get("ok", false)), "herb_b gather")
	failed += _expect(srv.is_gather_depleted("herb_b"), "herb_b depleted")
	# Force ready_at into the past then tick.
	if srv._gather_state.has("herb_b"):
		srv._gather_state["herb_b"] = {"depleted": true, "ready_at": 0.0}
	var tick_acts: Array = srv._tick_gather_respawns()
	failed += _expect(not srv.is_gather_depleted("herb_b"), "tick respawned herb_b")
	failed += _expect(not tick_acts.is_empty(), "tick emitted gather_update")

	# --- range fail ---
	srv.force_gather_respawn("herb_c")
	srv.set_player_cell(0, 0)
	var far: Dictionary = srv.try_gather("herb_c")
	failed += _expect(not bool(far.get("ok", true)), "out of range fails")
	failed += _expect(str(far.get("reason", "")) == "range", "reason range")

	if failed == 0:
		print("test_gather: PASS")
		quit(0)
	else:
		print("test_gather: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL ", label)
	return 1


func _msg_has(result: Dictionary, needle: String) -> bool:
	var acts: Array = result.get("actions", [])
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")).find(needle) >= 0:
			return true
	return false


func _has_type(result: Dictionary, type_name: String) -> bool:
	var acts: Array = result.get("actions", [])
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == type_name:
			return true
	return false
