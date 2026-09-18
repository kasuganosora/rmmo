extends SceneTree
## Headless: thin EventRuntime move_route — cell change, blocked stop, wait/turn.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")
	var EventCommands = load("res://scripts/editor/event_commands.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")

	# --- Schema / editor helpers ---
	var def: Dictionary = EventCommands.default_command("move_route")
	failed += _expect(str(def.get("op", "")) == "move_route", "default op move_route")
	failed += _expect(typeof(def.get("route", null)) == TYPE_ARRAY, "default route array")
	failed += _expect(str(EventCommands.summarize(def)).find("移动路径") >= 0, "summarize 移动路径")
	var op_ids: Array = []
	for row in EventCommands.OPS:
		op_ids.append(str(row.get("id", "")))
	failed += _expect(op_ids.has("move_route"), "OPS has move_route")

	# --- Unit: free move (no collision) updates cell + emits npc_move ---
	var rt = EventRuntime.new()
	rt.set_map_id("test_map")
	rt.load_events_array([
		{
			"id": "walker",
			"cell": {"x": 5, "y": 5},
			"trigger": "action",
			"through": true,
			"pages": [{
				"when": {},
				"commands": [{
					"op": "move_route",
					"target": "self",
					"wait": true,
					"route": [
						{"code": "move_right", "repeat": 2},
						{"code": "turn_down"},
						{"code": "wait", "duration": 0.25},
						{"code": "move_down"},
						"turn_left",
					],
				}],
			}],
		},
	], "test_map")

	var acts: Array = rt.run_event("walker", {})
	var moves: Array = []
	var waits := 0
	var turn_down := false
	var turn_left := false
	for a in acts:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		if t == "npc_move":
			moves.append(a)
			if int(a.get("x", -1)) == 7 and int(a.get("y", -1)) == 5 and int(a.get("facing", 0)) == 2:
				turn_down = true
			if int(a.get("x", -1)) == 7 and int(a.get("y", -1)) == 6 and int(a.get("facing", 0)) == 4:
				turn_left = true
		elif t == "wait":
			waits += 1
			failed += _expect(abs(float(a.get("duration", 0)) - 0.25) < 0.001, "wait duration 0.25")
	failed += _expect(moves.size() >= 4, "emits npc_move steps")
	failed += _expect(waits >= 1, "emits wait")
	failed += _expect(turn_down, "turn_down keeps cell 7,5 facing 2")
	failed += _expect(turn_left, "turn_left after move_down at 7,6")
	var cell_after: Dictionary = rt.get_event("walker").get("cell", {})
	failed += _expect(int(cell_after.get("x", -1)) == 7 and int(cell_after.get("y", -1)) == 6, "walker cell → 7,6")
	failed += _expect(str(rt.events_by_cell.get("7,6", "")) == "walker", "events_by_cell updated")
	failed += _expect(not rt.events_by_cell.has("5,5") or str(rt.events_by_cell.get("5,5", "")) != "walker", "old cell cleared")

	# --- Blocked path: stop cleanly, no crash ---
	# Use real demo collision for a wall-ish reject via synthetic can_pass wrapper.
	var pack = TilemapPack.load_pack("res://demo_map")
	failed += _expect(pack != null and pack.collision != null, "demo collision")
	var rt2 = EventRuntime.new()
	rt2.set_map_id("demo_map")
	# Place next to a likely blocked direction using collision.is_blocked probe.
	var start := Vector2i(1, 1)
	var found := false
	if pack.collision.has_method("can_pass"):
		for y in range(0, 24):
			for x in range(0, 24):
				# Prefer open cell that cannot move right into block.
				if pack.collision.has_method("is_blocked") and pack.collision.is_blocked(x, y):
					continue
				if not pack.collision.can_pass(x, y, 6):
					start = Vector2i(x, y)
					found = true
					break
			if found:
				break
	failed += _expect(found, "found open cell with blocked right")
	rt2.load_events_array([
		{
			"id": "blocker",
			"cell": {"x": start.x, "y": start.y},
			"trigger": "action",
			"through": true,
			"pages": [{
				"when": {},
				"commands": [{
					"op": "move_route",
					"target": "self",
					"skippable": false,
					"route": [
						{"code": "move_right", "repeat": 3},
						{"code": "move_down"},
					],
				}],
			}],
		},
	], "demo_map")
	var ctx_block := {"collision": pack.collision, "player_cell": Vector2i(-9999, -9999)}
	var acts_b: Array = rt2.run_event("blocker", ctx_block)
	# Should not crash; cell either unchanged or only moved while open.
	var bc: Dictionary = rt2.get_event("blocker").get("cell", {})
	failed += _expect(typeof(bc) == TYPE_DICTIONARY, "blocker still has cell")
	# First step is blocked → zero successful moves expected when start cannot pass right.
	var move_count := 0
	for a in acts_b:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "npc_move":
			# Only count actual position changes (not pure turns).
			if int(a.get("x", start.x)) != start.x or int(a.get("y", start.y)) != start.y:
				move_count += 1
	failed += _expect(move_count == 0, "blocked first step → no cell change moves")
	failed += _expect(int(bc.get("x", -1)) == start.x and int(bc.get("y", -1)) == start.y, "cell stays on block")

	# skippable: skip blocked, continue later steps that are open (turn still works)
	rt2.update_event_cell("blocker", start.x, start.y)
	var page0: Dictionary = rt2.get_event("blocker")["pages"][0]
	page0["commands"] = [{
		"op": "move_route",
		"target": "self",
		"skippable": true,
		"route": [
			{"code": "move_right", "repeat": 2},
			{"code": "turn_up"},
		],
	}]
	var acts_s: Array = rt2.run_event("blocker", ctx_block)
	var faced_up := false
	for a in acts_s:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type")) == "npc_move":
			if int(a.get("facing", 0)) == 8:
				faced_up = true
	failed += _expect(faced_up, "skippable still handles turn_up")

	# --- Demo pack includes mover_demo ---
	var pack2 = TilemapPack.load_pack("res://demo_map")
	var has_mover := false
	for ev in pack2.events:
		if typeof(ev) == TYPE_DICTIONARY and str(ev.get("id")) == "mover_demo":
			has_mover = true
			break
	failed += _expect(has_mover, "demo_map has mover_demo")

	var rt3 = EventRuntime.new()
	rt3.load_from_pack(pack2)
	failed += _expect(rt3.has_event("mover_demo"), "runtime has mover_demo")
	var demo_cell0: Dictionary = rt3.get_event("mover_demo").get("cell", {})
	var dx0 := int(demo_cell0.get("x", 0))
	var dy0 := int(demo_cell0.get("y", 0))
	var ctx_demo := {
		"collision": pack2.collision,
		"player_cell": Vector2i(-9999, -9999),
	}
	# Clear event occupancy so self-block does not trap the first step.
	if pack2.collision.has_method("set_extra_blocked"):
		pack2.collision.set_extra_blocked(dx0, dy0, false)
	var acts_d: Array = rt3.run_event("mover_demo", ctx_demo)
	var demo_moves := 0
	var demo_wait := false
	var demo_dlg := false
	var demo_msg := false
	for a in acts_d:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		match str(a.get("type", "")):
			"npc_move":
				demo_moves += 1
			"wait":
				demo_wait = true
			"show_npc_dialogue":
				demo_dlg = true
			"system_message":
				demo_msg = true
	failed += _expect(demo_dlg, "mover_demo dialogue")
	failed += _expect(demo_moves >= 1, "mover_demo emitted npc_move")
	failed += _expect(demo_wait, "mover_demo wait in route")
	failed += _expect(demo_msg, "mover_demo finish message")
	var demo_cell1: Dictionary = rt3.get_event("mover_demo").get("cell", {})
	# Route is right×2 then left×2 → should return home if path open; else at least ran without crash.
	failed += _expect(typeof(demo_cell1) == TYPE_DICTIONARY, "mover cell dict after")

	# --- MockServer authority path ---
	var srv = root.get_node_or_null("MockServer")
	if srv == null:
		print("test_move_route: FAIL no MockServer")
		quit(1)
		return
	if srv.event_runtime == null and srv.has_method("_init_combat_layers"):
		srv._init_combat_layers()
	failed += _expect(srv.event_runtime != null, "server event_runtime")
	srv._load_pack("res://demo_map")
	srv.event_runtime.clear_session()
	if srv.combat_stats == null:
		srv._init_combat_layers()
	# Register mover at its pack cell.
	var me: Dictionary = srv.event_runtime.get_event("mover_demo")
	var mc: Dictionary = me.get("cell", {"x": 18, "y": 20})
	var mx := int(mc.get("x", 18))
	var my := int(mc.get("y", 20))
	srv.set_player_cell(mx, my + 1)
	srv.register_npc("mover_demo", mx, my, false, false, 2, 0, 0, {"id": "mover_demo", "name": "巡逻木桩"})
	# Ensure start cell not double-blocked oddly: register already set extra via try path.
	var ir: Dictionary = srv.try_interact("mover_demo", mx, my + 1)
	failed += _expect(bool(ir.get("ok", false)), "server interact mover ok")
	var ia: Array = ir.get("actions", [])
	var srv_moves := 0
	var last_xy := Vector2i(mx, my)
	for a in ia:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type")) == "npc_move" and str(a.get("npc_id")) == "mover_demo":
			srv_moves += 1
			last_xy = Vector2i(int(a.get("x", last_xy.x)), int(a.get("y", last_xy.y)))
	failed += _expect(srv_moves >= 1, "server emits npc_move for mover")
	var srv_cell: Vector2i = srv.combat_stats.get_npc_cell("mover_demo")
	failed += _expect(srv_cell.x == last_xy.x and srv_cell.y == last_xy.y, "combat_stats cell matches last move")
	var ev_cell: Dictionary = srv.event_runtime.get_event("mover_demo").get("cell", {})
	failed += _expect(int(ev_cell.get("x", -1)) == last_xy.x and int(ev_cell.get("y", -1)) == last_xy.y, "event cell matches last move")

	# Existing systems smoke: chest still works after move_route wiring.
	srv.event_runtime.clear_session()
	srv._load_pack("res://demo_map")
	if srv.combat_stats == null:
		srv._init_combat_layers()
	srv.set_player_cell(9, 21)
	srv.register_npc("chest_a", 9, 22, false, false, 2, 0, 0, {"id": "chest_a", "name": "宝箱"})
	var cr: Dictionary = srv.try_interact("chest_a", 9, 21)
	failed += _expect(bool(cr.get("ok", false)), "chest still ok after move_route")

	if failed == 0:
		print("test_move_route: PASS")
		quit(0)
	else:
		print("test_move_route: FAIL count=%d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("  OK  ", label)
		return 0
	print("  FAIL", " ", label)
	return 1
