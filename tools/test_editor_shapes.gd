extends SceneTree
## Shapes, stamps, replace, find_tiles, overview, ring gaps.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var MapShapes = load("res://scripts/editor/domain/map_shapes.gd")
	var TileLabels = load("res://scripts/editor/domain/tile_labels.gd")
	var TileId = load("res://scripts/map/tile_id.gd")
	var PaintTools = load("res://scripts/editor/domain/paint_tools.gd")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var Editor = load("res://scripts/editor/content_editor.gd")
	var EditorMcp = load("res://scripts/editor/adapters/editor_mcp.gd")

	var line: Array = MapShapes.line_cells(Vector2i(0, 0), Vector2i(4, 0))
	failed += _expect(line.size() == 5, "line 5 cells")
	var ring: Array = MapShapes.ring_cells(10, 10, 6, 6, 1, [])
	failed += _expect(ring.size() >= 20, "ring cells")
	var gapped: Array = MapShapes.ring_cells(10, 10, 6, 6, 1, [{"deg": 90, "width_deg": 40}])
	failed += _expect(gapped.size() < ring.size(), "gap removes cells")
	var sc: Array = MapShapes.scatter_along(line, 2)
	failed += _expect(sc.size() >= 2 and sc.size() <= line.size(), "scatter spacing")
	failed += _expect(TileLabels.label_of(TileId.TILE_ID_A2).find("草") >= 0, "grass label")
	failed += _expect(not TileLabels.search("水").is_empty(), "find water")

	var paint = PaintTools.new()
	paint.clipboard = {"w": 2, "h": 1, "tiles": PackedInt32Array([1, 2])}
	paint.rotate_clipboard(true)
	failed += _expect(int(paint.clipboard.get("w", 0)) == 1, "rotate w")
	failed += _expect(int(paint.clipboard.get("h", 0)) == 2, "rotate h")
	paint.flip_clipboard(true)

	var pack = ContentPack.new()
	pack.new_blank("shape_pack", "形状", 20, 20)
	pack.save_dir()
	var doc = pack.get_map("Map001")
	var ed = Editor.new()
	ed.pack = pack
	ed.doc = doc
	ed.current_map_id = "Map001"
	ed.paint = paint
	var mcp = EditorMcp.new()
	root.add_child(mcp)
	mcp.editor = ed
	paint.layer_z = 0
	paint.tile_id = TileId.TILE_ID_A2
	var grass: int = int(TileId.TILE_ID_A2)
	var dirt: int = int(TileId.TILE_ID_A1) + 24 * 48
	mcp.call_tool("paint_rect", {"x": 0, "y": 0, "w": 8, "h": 8, "tile_id": grass, "z": 0})
	var rep: Dictionary = mcp.call_tool("replace_tiles", {"old_id": grass, "new_id": dirt, "z": 0})
	failed += _expect(bool(rep.get("ok", false)), "replace ok")
	failed += _expect(int(rep.get("replaced", 0)) >= 8, "replaced cells")
	var arc: Dictionary = mcp.call_tool("paint_arc", {
		"x": 10, "y": 10, "rx": 5, "from_deg": 0, "to_deg": 90, "tile_id": grass, "z": 0,
	})
	failed += _expect(bool(arc.get("ok", false)), "arc ok")
	failed += _expect(int(arc.get("painted", 0)) >= 3, "arc cells")
	var rg: Dictionary = mcp.call_tool("paint_ring", {
		"x": 10, "y": 10, "r": 6, "thickness": 1, "tile_id": dirt, "z": 0,
		"gap_deg": 90, "gap_width_deg": 50,
	})
	failed += _expect(bool(rg.get("ok", false)), "gapped ring")
	var pk: Dictionary = mcp.call_tool("pick_tileset", {"tab": "A", "col": 0, "row": 2})
	failed += _expect(int(pk.get("tile_id", 0)) == TileId.TILE_ID_A2, "pick A2")
	var ft: Dictionary = mcp.call_tool("find_tiles", {"query": "草"})
	failed += _expect((ft.get("matches", []) as Array).size() >= 1, "find grass")
	mcp.call_tool("stamp_from_tileset", {"tab": "B", "col": 0, "row": 0, "w": 2, "h": 2})
	mcp.call_tool("save_stamp", {"name": "树块"})
	var ls: Dictionary = mcp.call_tool("list_stamps", {})
	failed += _expect((ls.get("stamps", []) as Array).has("树块") or str(ls.get("stamps", "")).find("树") >= 0, "named stamp")
	mcp.call_tool("add_bookmark", {"name": "南门", "x": 3, "y": 4})
	failed += _expect(int(mcp.call_tool("list_bookmarks", {}).get("bookmarks", []).size()) >= 1, "bookmark")
	mcp.call_tool("add_region", {"name": "广场", "x": 2, "y": 2, "w": 4, "h": 4})
	failed += _expect(int(mcp.call_tool("list_regions", {}).get("regions", []).size()) >= 1, "region")
	var ov: Dictionary = mcp.call_tool("preview_map", {"overview": true, "max_px": 128, "grid": false})
	failed += _expect(bool(ov.get("ok", false)), "overview ok")
	failed += _expect(int(ov.get("w", 0)) == 20, "overview whole width")
	var sca: Dictionary = mcp.call_tool("scatter", {
		"along": "polyline",
		"points": [{"x": 0, "y": 15}, {"x": 8, "y": 15}],
		"spacing": 2, "tile_id": grass, "z": 0,
	})
	failed += _expect(bool(sca.get("ok", false)), "scatter ok")
	failed += _expect(int(sca.get("scattered", 0)) >= 2, "scatter spots")
	mcp.queue_free()
	ed.free()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED %d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS %s" % label)
		return 0
	print("FAIL %s" % label)
	return 1
