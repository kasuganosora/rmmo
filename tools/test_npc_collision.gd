extends SceneTree
func _init() -> void:
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	ProjectSettings.set_setting("rmmo/charset_root", _runtime_root() + "/characters")
	var pack = TilemapPack.load_pack("res://demo_map")
	var col = pack.collision
	# slime at 19,22 — should block entry from 19,23 (dir 8 = up)
	var blocked = not col.can_pass(19, 23, 8)
	var open = col.can_pass(18, 22, 6) == false  # into slime from left
	# actor_rest at 6,17 is solid (through=false) — should block
	var actor_blocks = col.is_extra_blocked(6, 17) == true
	print("block_slime=", blocked, " block_from_left=", open, " actor_rest_blocked=", actor_blocks)
	print("landable_slime=", col.is_landable(19, 22), " landable_near=", col.is_landable(18, 22))
	quit(0 if blocked and open and actor_blocks else 1)




func _runtime_root() -> String:
	for cand in ["/workspace/rmmo_runtime", "D:/code/rmmo_runtime"]:
		if DirAccess.dir_exists_absolute(cand):
			return cand
	return "/workspace/rmmo_runtime"
