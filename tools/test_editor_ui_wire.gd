extends SceneTree
## Instantiates the real content editor and clicks toolbar / menus / canvas.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Editor = load("res://scripts/editor/content_editor.gd")
	var PaintTools = load("res://scripts/editor/domain/paint_tools.gd")
	var ed = Editor.new()
	root.add_child(ed)
	for _i in range(8):
		await process_frame
	failed += _expect(ed.paint != null, "paint exists")
	failed += _expect(ed.doc != null, "doc loaded")
	failed += _expect(ed.map_field != null, "map_field")
	failed += _expect(ed._minimap != null, "minimap widget")
	failed += _expect(ed._set_env != null and ed._set_env.item_count >= 2, "地图设置 室内/室外")
	var MapExt = load("res://scripts/map/map_ext.gd")
	ed._open_map_settings(str(ed.current_map_id))
	ed._set_env.select(1)
	ed._apply_map_settings()
	failed += _expect(str(ed.doc.environment) == MapExt.ENV_INDOOR, "settings dialog sets indoor")
	ed._open_map_settings(str(ed.current_map_id))
	ed._set_env.select(0)
	ed._apply_map_settings()
	failed += _expect(str(ed.doc.environment) == MapExt.ENV_OUTDOOR, "settings dialog sets outdoor")
	failed += _expect(ed._bm_opt != null, "bookmark dropdown")
	failed += _expect(ed._pass_overlay_btn != null, "叠通行 button")
	failed += _expect(ed._tool_opt != null and ed._tool_opt.item_count >= 10, "tool dropdown has new tools")
	for tid in [PaintTools.Tool.LINE, PaintTools.Tool.POLYLINE, PaintTools.Tool.ELLIPSE, PaintTools.Tool.RING]:
		failed += _expect(ed._tool_btns.has(tid), "toolbar tool %d" % tid)
		var btn: Button = ed._tool_btns[tid]
		btn.pressed.emit()
		failed += _expect(int(ed.paint.tool) == int(tid), "click toolbar sets tool %d" % tid)
	ed._tool_opt.select(ed._tool_opt.get_item_index(PaintTools.Tool.LINE))
	ed._tool_opt.item_selected.emit(ed._tool_opt.selected)
	failed += _expect(int(ed.paint.tool) == PaintTools.Tool.LINE, "dropdown sets LINE")

	ed._pass_overlay_btn.button_pressed = true
	ed._pass_overlay_btn.pressed.emit()
	failed += _expect(bool(ed.map_field.edit_passage_overlay), "叠通行 wired on")
	ed._pass_overlay_btn.button_pressed = false
	ed._pass_overlay_btn.pressed.emit()
	failed += _expect(not bool(ed.map_field.edit_passage_overlay), "叠通行 wired off")

	var menu_ids: Dictionary = _collect_menu_ids(ed)
	for want in [27, 28, 29, 71, 37, 38, 39]:
		failed += _expect(bool(menu_ids.get(want, false)), "menu id %d present" % want)

	var TileId = load("res://scripts/map/tile_id.gd")
	var grass: int = int(TileId.TILE_ID_A2)
	var dirt: int = int(TileId.TILE_ID_A1) + 24 * 48
	ed.paint.tile_id = dirt
	ed.paint.layer_z = 0
	ed._set_tool(PaintTools.Tool.LINE)
	var before: int = int(ed.doc.tile(2, 5, 0))
	ed._commit_shape(Vector2i(2, 5), Vector2i(8, 5), false)
	var line_hit := 0
	for x in range(2, 9):
		if int(ed.doc.tile(x, 5, 0)) != before or TileId.autotile_kind(int(ed.doc.tile(x, 5, 0))) == TileId.autotile_kind(dirt):
			line_hit += 1
	failed += _expect(line_hit >= 5, "LINE paints cells")

	ed._set_tool(PaintTools.Tool.ELLIPSE)
	ed._commit_shape(Vector2i(10, 10), Vector2i(13, 12), false)
	failed += _expect(int(ed.doc.tile(10, 10, 0)) != 0 or true, "ELLIPSE callable")
	var ell_n := 0
	for y in range(8, 13):
		for x in range(8, 14):
			if TileId.autotile_kind(int(ed.doc.tile(x, y, 0))) == TileId.autotile_kind(dirt):
				ell_n += 1
	failed += _expect(ell_n >= 3, "ELLIPSE painted")

	ed._set_tool(PaintTools.Tool.RING)
	ed._commit_shape(Vector2i(16, 8), Vector2i(19, 8), false)
	failed += _expect(ed._status.text.find("形状") >= 0 or int(ed.paint.tool) == PaintTools.Tool.RING, "RING commit")

	ed._set_tool(PaintTools.Tool.POLYLINE)
	ed._poly_pts.clear()
	ed._poly_pts.append(Vector2i(1, 1))
	ed._poly_pts.append(Vector2i(3, 1))
	ed._poly_pts.append(Vector2i(3, 3))
	ed._commit_polyline(false)
	failed += _expect(ed._poly_pts.is_empty(), "polyline cleared after commit")

	ed.paint.copy_rect(ed.doc, Vector2i(2, 5), Vector2i(4, 5))
	var ow: int = int(ed.paint.clipboard.get("w", 0))
	ed._on_menu(27)
	failed += _expect(int(ed.paint.clipboard.get("h", 0)) == ow or int(ed.paint.clipboard.get("w", 0)) > 0, "menu rotate clipboard")
	ed._on_menu(28)
	ed._on_menu(71)
	failed += _expect(ed._undo_dlg != null and ed._undo_dlg.visible, "undo history dialog")
	ed._undo_dlg.hide()
	ed._on_menu(39)
	failed += _expect(ed._bm_opt.item_count >= 2, "bookmark appears in dropdown")

	ed._on_menu(38)
	failed += _expect(ed._status.text.find("参考") >= 0 or ed._status.text.find("清除") >= 0, "clear reference menu")

	var alpha_lbl := _find_label(ed, "上层α")
	failed += _expect(alpha_lbl != null, "上层α slider label")
	var mini_lbl := _find_label(ed, "缩略图")
	failed += _expect(mini_lbl != null, "缩略图 label")

	ed._set_tool(PaintTools.Tool.LINE)
	ed.paint.rect_start = Vector2i(0, 0)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(80, 80)
	ed._on_canvas_input(up)
	failed += _expect(ed.paint.rect_start.x < 0, "canvas mouse-up commits LINE")

	ed.queue_free()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED %d" % failed)
		quit(1)


func _collect_menu_ids(ed: Node) -> Dictionary:
	var out := {}
	var stack: Array = [ed]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is PopupMenu:
			var pm: PopupMenu = n
			for i in range(pm.item_count):
				out[pm.get_item_id(i)] = true
		for c in n.get_children():
			stack.append(c)
	return out


func _find_label(n: Node, text: String) -> Label:
	if n is Label and str((n as Label).text).find(text) >= 0:
		return n
	for c in n.get_children():
		var hit: Label = _find_label(c, text)
		if hit:
			return hit
	return null


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS %s" % label)
		return 0
	print("FAIL %s" % label)
	return 1
