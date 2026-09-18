extends SceneTree
## Create the first-party `default` content pack under user:// then print its path.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var TileId = load("res://scripts/map/tile_id.gd")
	var pack = ContentPack.new()
	pack.new_blank("default", "默认", 24, 24)
	pack.pack_id = "default"
	pack.pack_name = "默认"
	pack.start_map = "Map001"
	var ts := {
		"id": 1,
		"name": "default",
		"mode": 1,
		"note": "Washed first-party tileset. No RTP sheets.",
		"tilesetNames": ["", "", "", "", "Ground", "", "", "", ""],
		"flags": [],
	}
	pack.tilesets = {"default": ts}
	pack.init_slot_passage("default", 4, 0)
	var doc = pack.get_map("Map001")
	if doc != null:
		doc.tileset_id = "default"
		doc.display_name = "原点"
		doc.environment = "outdoor"
		var a5: int = 1536
		if TileId != null and TileId.has_method("slot_range"):
			var r: Vector2i = TileId.slot_range(4)
			if r.x > 0:
				a5 = r.x
		for y in range(int(doc.height)):
			for x in range(int(doc.width)):
				doc.set_tile(x, y, 0, a5, false)
		doc.start_cell = Vector2i(12, 12)
	var am: Node = root.get_node_or_null("AssetManager")
	var content := "D:/code/rmmo_runtime"
	if am != null and am.has_method("content_root"):
		content = str(am.content_root())
	var dest := "%s/packs/map_pack/default/0.1.0" % content.rstrip("/").rstrip("\\")
	if not pack.save_dir(dest):
		push_error("init_default_pack: save_dir failed")
		quit(1)
		return
	print("DEFAULT_PACK_SAVED=", dest)
	quit(0)
