extends SceneTree
## Headless: NPC double-click engage helpers (beside check + request path).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var WorldScr = load("res://scripts/game/world.gd")
	var NpcScr = load("res://scripts/game/npc_actor.gd")
	failed += _expect(WorldScr != null and NpcScr != null, "world + npc_actor load")
	if WorldScr == null or NpcScr == null:
		_finish(failed)
		return

	var world: Node2D = WorldScr.new()
	var npc: Node2D = NpcScr.new()
	npc.npc_id = "actor_rest"
	npc.cell = Vector2i(15, 10)
	failed += _expect(world.has_method("_request_npc_engage"), "world has _request_npc_engage")
	failed += _expect(world.has_method("_player_beside_npc"), "world has _player_beside_npc")
	failed += _expect(world.has_method("_approach_cell"), "approach helper")
	failed += _expect(world._approach_cell(Vector2i(0, 0), Vector2i(5, 0), 3) == Vector2i(2, 0), "approach range 3 axis")
	failed += _expect(world._approach_cell(Vector2i(0, 0), Vector2i(5, 5), 3) == Vector2i(2, 2), "approach range 3 diag")
	failed += _expect(world._approach_cell(Vector2i(4, 4), Vector2i(5, 5), 3) == Vector2i(4, 4), "already in range stays")
	failed += _expect(world._approach_cell(Vector2i(0, 0), Vector2i(2, 0), 1) == Vector2i(1, 0), "melee approach")
	failed += _expect(world._approach_cell(Vector2i(15, 18), Vector2i(16, 12), 1) == Vector2i(16, 13), "uneven axes melee")
	var heal := {"effect": "heal", "range": 0, "requires_target": false}
	failed += _expect(world._skill_chase_range(heal) < 0, "heal does not chase")
	var flame := {"effect": "aoe_damage", "range": 3, "target_mode": "ground", "requires_target": false}
	failed += _expect(world._skill_chase_range(flame) == 3, "flame chase 3")
	var strike := {"effect": "damage", "range": 1, "requires_target": true}
	failed += _expect(world._skill_chase_range(strike) == 1, "strike chase 1")
	var cry := {"effect": "apply_status", "range": 0, "requires_target": false}
	failed += _expect(world._skill_chase_range(cry) < 0, "self buff no chase")
	failed += _expect(world._player_beside_npc(npc, Vector2i(15, 11)), "adjacent south")
	failed += _expect(world._player_beside_npc(npc, Vector2i(14, 10)), "adjacent west")
	failed += _expect(world._player_beside_npc(npc, Vector2i(15, 10)), "same cell counts as beside")
	failed += _expect(not world._player_beside_npc(npc, Vector2i(15, 12)), "two cells away is not beside")
	failed += _expect(not world._player_beside_npc(null, Vector2i(15, 11)), "null npc is not beside")

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.double_click = true
	failed += _expect(mb.double_click == true, "mouse event carries double_click")

	world.free()
	npc.free()
	_finish(failed)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1


func _finish(failed: int) -> void:
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)
