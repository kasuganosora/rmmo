extends SceneTree
## Headless: MockServer.try_npc_move wall reject, player mutual block, extra_blocked update.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting("rmmo/charset_root", _runtime_root() + "/characters")
	var srv = root.get_node("MockServer")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var pack = TilemapPack.load_pack("res://demo_map")
	srv.map_collision = pack.collision
	srv.map_tile_size = pack.tile_size
	srv.map_collision.clear_extra_blocked()
	srv.map_collision.apply_npc_blocks(pack.npcs)

	# Player stands south of actor_rest (6,17) -> (6,18)
	srv.set_player_cell(6, 18)
	var col = srv.map_collision

	# Illegal: NPC walks into player
	var into_player = srv.try_npc_move("actor_rest", 6, 17, 2)
	var reject_player = not bool(into_player.get("ok", true))

	# Illegal: synthetic block to the right
	col.set_extra_blocked(7, 17, true)
	var into_block = srv.try_npc_move("actor_rest", 6, 17, 6)
	var reject_block = not bool(into_block.get("ok", true))
	col.set_extra_blocked(7, 17, false)

	# Move player away; ensure actor cell still blocked
	srv.set_player_cell(20, 20)
	if not col.is_extra_blocked(6, 17):
		col.set_extra_blocked(6, 17, true)

	# Try each cardinal until one succeeds (map-dependent)
	var moved: Dictionary = {"ok": false}
	var ok_move := false
	for d in [4, 6, 2, 8]:
		moved = srv.try_npc_move("actor_rest", 6, 17, int(d))
		if bool(moved.get("ok", false)):
			ok_move = true
			break
		# restore block if rejected (can_pass didn't move occupancy)
		if not col.is_extra_blocked(6, 17):
			col.set_extra_blocked(6, 17, true)

	var nx: int = int(moved.get("x", 6))
	var ny: int = int(moved.get("y", 17))
	var at_new = col.is_extra_blocked(nx, ny) if ok_move else false
	var old_clear = (not col.is_extra_blocked(6, 17)) if ok_move else false
	print("reject_player=", reject_player, " reject_block=", reject_block)
	print("ok_move=", ok_move, " at_new=", at_new, " old_clear=", old_clear, " result=", moved)
	var pass_all = reject_player and reject_block and ok_move and at_new and old_clear
	quit(0 if pass_all else 1)




func _runtime_root() -> String:
	for cand in ["/workspace/rmmo_runtime", "D:/code/rmmo_runtime"]:
		if DirAccess.dir_exists_absolute(cand):
			return cand
	return "/workspace/rmmo_runtime"
