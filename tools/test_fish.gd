extends SceneTree
## Headless: MockServer try_fish — success, deplete, busy, bag full, respawn, interact.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_fish: FAIL no MockServer")
		quit(1)
		return
	if srv.inventory == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	if srv.fish_catalog == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()

	failed += _expect(srv.has_method("try_fish"), "has try_fish")
	failed += _expect(srv.fish_catalog != null, "fish_catalog loaded")
	failed += _expect(srv.fish_catalog.has_spot("fish_pond_a"), "catalog fish_pond_a")
	failed += _expect(srv.fish_catalog.has_spot("fish_pond_b"), "catalog fish_pond_b")

	# Catalog items exist (name-only).
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("fish_small"), "item fish_small")
	failed += _expect(srv.item_catalog != null and srv.item_catalog.has_item("fish_shiny"), "item fish_shiny")

	if srv.has_method("_load_pack"):
		srv._load_pack("res://demo_map")
	failed += _expect(srv._fish_spots.has("fish_pond_a"), "map loaded fish_pond_a")
	failed += _expect(srv._fish_spots.has("fish_pond_b"), "map loaded fish_pond_b")

	# Place player adjacent to fish_pond_a (16,11).
	srv.set_player_cell(16, 10)
	if srv.has_method("register_npc"):
		srv.register_npc("fish_pond_a", 16, 11, false, false, 2, 0, 0, {
			"id": "fish_pond_a",
			"name": "小水塘",
			"kind": "object",
			"interact_text": "一处可以垂钓的浅水。",
		})

	srv.inventory.clear()
	srv.inventory.add_gold(10)
	srv._fish_busy_until = 0.0
	var before_small: int = srv.inventory.get_qty("fish_small")
	var before_shiny: int = srv.inventory.get_qty("fish_shiny")

	# --- success ---
	var ok1: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(ok1.get("ok", false)), "fish success")
	failed += _expect(str(ok1.get("item_id", "")) in ["fish_small", "fish_shiny"], "yielded fish item")
	failed += _expect(int(ok1.get("qty", 0)) >= 1, "yielded qty>=1")
	var iid := str(ok1.get("item_id", ""))
	var gained: int = int(ok1.get("qty", 0))
	var after: int = srv.inventory.get_qty(iid)
	var expect_after: int = (before_small if iid == "fish_small" else before_shiny) + gained
	failed += _expect(after == expect_after, "bag gained yield")
	failed += _expect(_msg_has(ok1, "钓到了："), "msg 钓到了")
	failed += _expect(_has_type(ok1, "inventory_update"), "inventory_update")
	failed += _expect(_has_type(ok1, "fish_update"), "fish_update deplete")
	failed += _expect(srv.is_fish_depleted("fish_pond_a"), "depleted after fish")

	# --- busy lock (cast_sec on pond_a is 0.8) ---
	# Force spot ready but keep busy lock from previous cast.
	if srv.has_method("force_fish_respawn"):
		# force_fish_respawn clears busy — re-set busy after.
		srv.force_fish_respawn("fish_pond_a")
	srv._fish_busy_until = srv._fish_now() + 5.0
	var busy: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(busy.get("ok", true)), "busy fails")
	failed += _expect(str(busy.get("reason", "")) == "busy", "reason busy")
	failed += _expect(_msg_has(busy, "还在甩杆"), "msg 还在甩杆")
	srv._fish_busy_until = 0.0

	# --- fail while depleted ---
	# Re-fish then deplete again.
	var ok_pre: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(ok_pre.get("ok", false)), "pre-deplete fish")
	srv._fish_busy_until = 0.0
	var fail_d: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(fail_d.get("ok", true)), "depleted fails")
	failed += _expect(str(fail_d.get("reason", "")) == "depleted", "reason depleted")
	failed += _expect(_msg_has(fail_d, "这里没有鱼"), "msg 这里没有鱼")

	# try_interact routes to fish
	var ir: Dictionary = srv.try_interact("fish_pond_a", 16, 10)
	failed += _expect(not bool(ir.get("ok", true)), "interact while depleted fails")
	failed += _expect(_msg_has(ir, "这里没有鱼"), "interact msg 这里没有鱼")

	# --- force respawn ---
	failed += _expect(srv.has_method("force_fish_respawn"), "has force_fish_respawn")
	var ra: Array = srv.force_fish_respawn("fish_pond_a")
	failed += _expect(not srv.is_fish_depleted("fish_pond_a"), "respawned")
	failed += _expect(not ra.is_empty(), "respawn actions")
	var restored := false
	for a in ra:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "fish_update":
			if not bool(a.get("depleted", true)):
				restored = true
	failed += _expect(restored, "fish_update restored")

	# Fish again after respawn
	var ok2: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(bool(ok2.get("ok", false)), "fish after respawn")
	failed += _expect(srv.is_fish_depleted("fish_pond_a"), "depleted again")
	srv._fish_busy_until = 0.0

	# --- bag full ---
	srv.force_fish_respawn("fish_pond_a")
	srv.inventory.clear()
	srv.inventory.add_gold(0)
	srv.inventory.max_slots = 1
	srv.inventory.add_item("rusty_coin", 99)
	var full: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(full.get("ok", true)), "bag full fails")
	failed += _expect(str(full.get("reason", "")) == "bag_full", "reason bag_full")
	failed += _expect(_msg_has(full, "背包已满"), "msg 背包已满")
	failed += _expect(not srv.is_fish_depleted("fish_pond_a"), "not depleted on bag full")
	srv.inventory.max_slots = 40

	# --- tick respawn path ---
	srv.force_fish_respawn("fish_pond_b")
	srv.set_player_cell(18, 10)
	if srv.has_method("register_npc"):
		srv.register_npc("fish_pond_b", 18, 11, false, false, 2, 0, 0, {
			"id": "fish_pond_b", "name": "浅水洼", "kind": "object"
		})
	srv.inventory.clear()
	srv._fish_busy_until = 0.0
	# fish_pond_b requires gather_level 2
	if "gather_level" in srv:
		srv.gather_level = maxi(int(srv.gather_level), 2)
	var gb: Dictionary = srv.try_fish("fish_pond_b")
	failed += _expect(bool(gb.get("ok", false)), "fish_pond_b fish")
	failed += _expect(srv.is_fish_depleted("fish_pond_b"), "fish_pond_b depleted")
	if srv._fish_state.has("fish_pond_b"):
		srv._fish_state["fish_pond_b"] = {"depleted": true, "ready_at": 0.0}
	var tick_acts: Array = srv._tick_fish_respawns()
	failed += _expect(not srv.is_fish_depleted("fish_pond_b"), "tick respawned fish_pond_b")
	failed += _expect(not tick_acts.is_empty(), "tick emitted fish_update")

	# --- range fail ---
	srv.force_fish_respawn("fish_pond_a")
	srv.set_player_cell(0, 0)
	srv._fish_busy_until = 0.0
	var far: Dictionary = srv.try_fish("fish_pond_a")
	failed += _expect(not bool(far.get("ok", true)), "out of range fails")
	failed += _expect(str(far.get("reason", "")) == "range", "reason range")

	# --- unknown ---
	var unk: Dictionary = srv.try_fish("no_such_spot")
	failed += _expect(not bool(unk.get("ok", true)), "unknown fails")
	failed += _expect(_msg_has(unk, "这里没有鱼"), "unknown msg 这里没有鱼")

	# gather still intact
	failed += _expect(srv.has_method("try_gather"), "gather still present")
	failed += _expect(srv.gather_catalog != null, "gather_catalog intact")

	if failed == 0:
		print("test_fish: PASS")
		quit(0)
	else:
		print("test_fish: FAIL count=%d" % failed)
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
