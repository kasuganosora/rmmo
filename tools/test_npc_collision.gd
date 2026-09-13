extends SceneTree
func _init() -> void:
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	ProjectSettings.set_setting("rmmo/charset_root", "D:/code/rmmo_runtime/characters")
	var pack = TilemapPack.load_pack("res://demo_map")
	var col = pack.collision
	# slime at 17,12 — should block entry from 17,13 (dir 8 = up)
	var blocked = not col.can_pass(17, 13, 8)
	var open = col.can_pass(16, 12, 6) == false  # into slime from left
	# actor_rest at 15,10 is solid (through=false) — should block
	var actor_blocks = col.is_extra_blocked(15, 10) == true
	print("block_slime=", blocked, " block_from_left=", open, " actor_rest_blocked=", actor_blocks)
	print("landable_slime=", col.is_landable(17, 12), " landable_near=", col.is_landable(16, 12))
	quit(0 if blocked and open and actor_blocks else 1)
