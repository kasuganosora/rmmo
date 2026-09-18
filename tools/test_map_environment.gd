extends SceneTree
## Map-level indoor/outdoor setting persists for weather.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var MapExt = load("res://scripts/map/map_ext.gd")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var Editor = load("res://scripts/editor/content_editor.gd")
	var EditorMcp = load("res://scripts/editor/adapters/editor_mcp.gd")
	var PaintTools = load("res://scripts/editor/domain/paint_tools.gd")

	failed += _expect(MapExt.normalize_environment("室内") == MapExt.ENV_INDOOR, "parse 室内")
	failed += _expect(MapExt.normalize_environment(true) == MapExt.ENV_INDOOR, "parse true")
	failed += _expect(MapExt.normalize_environment("outdoor") == MapExt.ENV_OUTDOOR, "parse outdoor")
	failed += _expect(MapExt.environment_label("indoor") == "室内", "label indoor")

	var pack = ContentPack.new()
	pack.new_blank("env_pack", "环境测试", 12, 12)
	failed += _expect(pack.save_dir(), "save blank")
	var doc = pack.get_map("Map001")
	failed += _expect(str(doc.environment) == MapExt.ENV_OUTDOOR, "default outdoor")
	doc.environment = MapExt.ENV_INDOOR
	failed += _expect(pack.save_dir(), "save indoor")
	failed += _expect(pack.reload_map("Map001"), "reload")
	doc = pack.get_map("Map001")
	failed += _expect(str(doc.environment) == MapExt.ENV_INDOOR, "survived save")

	var loaded = TilemapPack.load_pack(pack.root, "Map001")
	failed += _expect(loaded != null, "runtime pack")
	failed += _expect(str(loaded.environment) == MapExt.ENV_INDOOR, "runtime environment indoor")

	var ed = Editor.new()
	ed.pack = pack
	ed.doc = doc
	ed.current_map_id = "Map001"
	ed.paint = PaintTools.new()
	var mcp = EditorMcp.new()
	root.add_child(mcp)
	mcp.editor = ed
	var gs: Dictionary = mcp.call_tool("get_map_settings", {})
	failed += _expect(bool(gs.get("indoor", false)), "mcp indoor true")
	failed += _expect(str(gs.get("environment", "")) == MapExt.ENV_INDOOR, "mcp env indoor")
	var seto: Dictionary = mcp.call_tool("set_map_settings", {"environment": "outdoor"})
	failed += _expect(str(seto.get("environment", "")) == MapExt.ENV_OUTDOOR, "mcp set outdoor")
	failed += _expect(not bool(seto.get("indoor", true)), "mcp indoor false")
	mcp.call_tool("set_map_settings", {"indoor": true})
	failed += _expect(str(doc.environment) == MapExt.ENV_INDOOR, "mcp indoor bool")

	var dup: RefCounted = doc.clone("Map002", "复制")
	failed += _expect(str(dup.environment) == MapExt.ENV_INDOOR, "clone keeps env")

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
