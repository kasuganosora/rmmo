extends SceneTree
## Playtest load path: nested pack collision matches painted walkable cell.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var MockServer = load("res://scripts/net/mock_server.gd")
	var root := "user://content/packs/plan_walk_pack"
	var pack = ContentPack.new()
	pack.new_blank("plan_walk_pack", "walk", 12, 12)
	var doc = pack.get_map("Map001")
	doc.set_tile(4, 5, 0, 2816, false)
	doc.set_tile(5, 5, 0, 2816, false)
	failed += _expect(pack.save_dir(root), "save walk pack")
	var tp = TilemapPack.load_pack(root, "Map001")
	failed += _expect(tp != null and tp.collision != null, "TilemapPack collision")
	failed += _expect(int(tp.width) == 12 and int(tp.height) == 12, "size 12x12")
	failed += _expect(int(tp.collision.tile_id(4, 5, 0)) == 2816, "collision has grass id")
	failed += _expect(bool(tp.collision.is_landable(4, 5)), "grass cell landable")
	failed += _expect(not bool(tp.collision.is_landable(1, 1)), "empty void not landable")
	var sv = MockServer.new()
	get_root().add_child(sv)
	failed += _expect(sv.has_method("load_world_pack"), "server load_world_pack")
	failed += _expect(bool(sv.load_world_pack(root, "Map001", Vector2i(4, 5))), "load_world_pack ok")
	failed += _expect(sv.map_collision != null, "server collision")
	# Player occupancy marks 4,5 extra-blocked; neighbor grass 5,5 must stay landable.
	failed += _expect(bool(sv.map_collision.is_landable(5, 5)), "server neighbor grass landable")
	failed += _expect(bool(sv.map_collision.can_pass(4, 5, 6)), "server can_pass onto grass")
	failed += _expect(not bool(sv.map_collision.is_landable(1, 1)), "server void not landable")
	sv.queue_free()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
