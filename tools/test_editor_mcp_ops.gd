extends SceneTree
## Paint shapes, inspect, map admin, tileset preview, entities.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var TileId = load("res://scripts/map/tile_id.gd")
	var MapExt = load("res://scripts/map/map_ext.gd")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var EditorMcp = load("res://scripts/editor/adapters/editor_mcp.gd")
	var Editor = load("res://scripts/editor/content_editor.gd")
	var PaintTools = load("res://scripts/editor/domain/paint_tools.gd")

	var pack = ContentPack.new()
	pack.new_blank("ed_ops_pack", "Ops测试", 24, 24)
	var doc = pack.get_map("Map001")
	var ed = Editor.new()
	ed.pack = pack
	ed.doc = doc
	ed.current_map_id = "Map001"
	ed.paint = PaintTools.new()
	ed._cursor = Vector2i(2, 2)
	var mcp = EditorMcp.new()
	root.add_child(mcp)
	mcp.editor = ed

	var listed: Variant = mcp.handle_rpc({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})
	var tools: Array = (listed as Dictionary).get("result", {}).get("tools", []) if typeof(listed) == TYPE_DICTIONARY else []
	var names := PackedStringArray()
	for t in tools:
		if typeof(t) == TYPE_DICTIONARY:
			names.append(str(t.get("name", "")))
	for need in [
		"get_tile", "get_tiles_rect", "list_entities", "list_layers", "list_tilesets",
		"get_map_settings", "set_map_settings", "create_map", "resize_map", "duplicate_map",
		"set_layer", "paint_rect", "paint_fill", "paint_cells", "paint_polyline",
		"paint_ellipse", "paint_ring", "copy_tiles", "paste_tiles", "undo", "redo",
		"preview_tileset", "preview_charset", "set_passage", "update_entity", "place_chest",
		"import_asset", "refresh_autotiles", "set_stamp", "paint_stamp",
	]:
		failed += _expect(names.find(need) >= 0, "tool %s" % need)
	failed += _expect(names.size() >= 45, "tool count >= 45")

	var grass: int = TileId.TILE_ID_A2
	var dirt: int = TileId.make_autotile_id(24, 0)
	var rect_r: Dictionary = mcp.call_tool("paint_rect", {
		"x": 2, "y": 2, "w": 5, "h": 5, "tile_id": grass, "z": 0,
	})
	failed += _expect(bool(rect_r.get("ok", false)), "paint_rect ok")
	failed += _expect(int(rect_r.get("painted", 0)) == 25, "paint_rect 25 cells")
	var center: int = int(doc.tile(4, 4, 0))
	failed += _expect(TileId.is_tile_a2(center), "rect grass A2")
	failed += _expect(TileId.autotile_kind(center) == TileId.autotile_kind(grass), "rect kind grass")
	failed += _expect(TileId.autotile_shape(center) == 0, "3x3 interior shape 0")

	var gt: Dictionary = mcp.call_tool("get_tile", {"x": 4, "y": 4})
	failed += _expect(bool(gt.get("ok", false)), "get_tile ok")
	failed += _expect(int((gt.get("z", []) as Array)[0]) == center, "get_tile z0")

	var fill_r: Dictionary = mcp.call_tool("paint_fill", {"x": 4, "y": 4, "tile_id": dirt, "z": 0})
	failed += _expect(bool(fill_r.get("ok", false)), "paint_fill ok")
	failed += _expect(int(fill_r.get("painted", 0)) >= 25, "fill at least 25")
	failed += _expect(TileId.autotile_kind(int(doc.tile(4, 4, 0))) == 24, "filled dirt kind")

	var poly: Dictionary = mcp.call_tool("paint_polyline", {
		"points": [{"x": 0, "y": 10}, {"x": 8, "y": 10}],
		"tile_id": grass, "width": 1, "z": 0,
	})
	failed += _expect(bool(poly.get("ok", false)), "polyline ok")
	failed += _expect(int(poly.get("painted", 0)) >= 9, "polyline length")

	var ell: Dictionary = mcp.call_tool("paint_ellipse", {
		"x": 16, "y": 16, "rx": 3, "ry": 3, "tile_id": grass, "z": 0, "fill": true,
	})
	failed += _expect(bool(ell.get("ok", false)), "ellipse ok")
	failed += _expect(int(ell.get("painted", 0)) >= 9, "ellipse cells")

	var ring: Dictionary = mcp.call_tool("paint_ring", {
		"x": 16, "y": 8, "r": 3, "thickness": 1, "tile_id": grass, "z": 0,
	})
	failed += _expect(bool(ring.get("ok", false)), "ring ok")
	failed += _expect(int(ring.get("painted", 0)) >= 8, "ring outline")
	var ring2: Dictionary = mcp.call_tool("paint_ring", {
		"x": 12, "y": 12, "r": 8, "thickness": 2, "tile_id": dirt, "z": 0,
	})
	failed += _expect(bool(ring2.get("ok", false)), "ring r8 ok")
	failed += _expect(int(ring2.get("painted", 0)) >= 40, "ring r8 cells")

	var cells_r: Dictionary = mcp.call_tool("paint_cells", {
		"cells": [{"x": 1, "y": 1, "tile_id": grass}, {"x": 1, "y": 2, "tile_id": grass}],
		"z": 0,
	})
	failed += _expect(bool(cells_r.get("ok", false)), "paint_cells ok")
	failed += _expect(int(cells_r.get("painted", 0)) >= 2, "paint_cells 2")

	var slice: Dictionary = mcp.call_tool("get_tiles_rect", {"x": 1, "y": 1, "w": 3, "h": 2, "z": 0})
	failed += _expect(bool(slice.get("ok", false)), "get_tiles_rect ok")
	var rows: Array = slice.get("tiles", [])
	failed += _expect(rows.size() == 2, "tiles_rect rows")
	failed += _expect((rows[0] as Array).size() == 3, "tiles_rect cols")

	var und: Dictionary = mcp.call_tool("undo", {})
	failed += _expect(bool(und.get("ok", false)), "undo ok")
	var red: Dictionary = mcp.call_tool("redo", {})
	failed += _expect(bool(red.get("ok", false)), "redo ok")

	mcp.call_tool("copy_tiles", {"x": 1, "y": 1, "w": 2, "h": 2, "z": 0})
	var pst: Dictionary = mcp.call_tool("paste_tiles", {"x": 20, "y": 20})
	failed += _expect(bool(pst.get("ok", false)), "paste_tiles ok")

	mcp.call_tool("set_stamp", {"w": 2, "h": 1, "tiles": [grass, grass]})
	var st: Dictionary = mcp.call_tool("paint_stamp", {"x": 18, "y": 1, "z": 0})
	failed += _expect(bool(st.get("ok", false)), "paint_stamp ok")

	var meta_b: Dictionary = mcp.call_tool("set_meta", {"x": 0, "y": 0, "w": 3, "h": 1, "bit": MapExt.META_FORCE_BLOCK})
	failed += _expect(bool(meta_b.get("ok", false)), "set_meta rect")
	failed += _expect((int(doc.ext_tile("meta", 2, 0)) & MapExt.META_FORCE_BLOCK) != 0, "meta batch block")

	mcp.call_tool("set_layer", {"ext": "roof"})
	var lyr: Dictionary = mcp.call_tool("list_layers", {})
	failed += _expect(str(lyr.get("ext", "")) == "roof", "set_layer roof")
	mcp.call_tool("set_layer", {"z": 0})

	var huge: Dictionary = mcp.call_tool("create_map", {"name": "大陆", "w": 10000, "h": 10000})
	failed += _expect(bool(huge.get("ok", false)), "create 10000x10000 chunked map")
	failed += _expect(int(huge.get("width", 0)) == 10000, "chunked width 10000")
	mcp.call_tool("select_map", {"map_id": "Map001"})
	var created: Dictionary = mcp.call_tool("create_map", {"name": "内城", "w": 12, "h": 10})
	failed += _expect(bool(created.get("ok", false)), "create_map")
	failed += _expect(str(ed.current_map_id) != "Map001", "switched to new map")
	var resized: Dictionary = mcp.call_tool("resize_map", {"w": 14, "h": 11})
	failed += _expect(bool(resized.get("ok", false)), "resize_map")
	failed += _expect(int(ed.doc.width) == 14, "resized width")
	var sets: Dictionary = mcp.call_tool("set_map_settings", {"name": "城内", "bgm": "Town1", "start_x": 3, "start_y": 4, "light_preset": 1})
	failed += _expect(bool(sets.get("ok", false)), "set_map_settings")
	failed += _expect(str(ed.doc.display_name) == "城内", "renamed")
	failed += _expect(str(ed.doc.bgm) == "Town1", "bgm")
	failed += _expect(int(ed.doc.start_cell.x) == 3, "start x")
	var tsets: Dictionary = mcp.call_tool("list_tilesets", {})
	failed += _expect(bool(tsets.get("ok", false)), "list_tilesets")
	failed += _expect((tsets.get("tilesets", []) as Array).size() >= 1, "has tileset")

	mcp.call_tool("select_map", {"map_id": "Map001"})
	var chest: Dictionary = mcp.call_tool("place_chest", {"x": 5, "y": 5, "gold": 20})
	failed += _expect(bool(chest.get("ok", false)), "place_chest")
	var ents: Dictionary = mcp.call_tool("list_entities", {})
	failed += _expect(int(ents.get("count", 0)) >= 1, "list_entities")
	var upd: Dictionary = mcp.call_tool("update_entity", {"x": 5, "y": 5, "name": "金箱"})
	failed += _expect(bool(upd.get("ok", false)), "update_entity")
	failed += _expect(str(doc.entity_at(Vector2i(5, 5)).get("data", {}).get("name", "")) == "金箱", "chest renamed")

	var prev_ts: Dictionary = mcp.call_tool("preview_tileset", {"tab": "A", "max_px": 256})
	failed += _expect(bool(prev_ts.get("ok", false)), "preview_tileset ok")
	failed += _expect(int(prev_ts.get("count", 0)) >= 32, "tileset catalog")
	failed += _expect(str(prev_ts.get("png_base64", "")).length() > 80, "tileset png")

	var stt: Dictionary = mcp.call_tool("editor_state", {})
	failed += _expect(stt.has("tileset_id"), "state tileset_id")
	failed += _expect(stt.has("layer_z"), "state layer_z")

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
