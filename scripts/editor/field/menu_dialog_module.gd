extends RefCounted
## Domain module: menus/dialogs (popup, menu, pack dialog, file, undo/redo, undo list, bookmark).

var ctrl
func _init(c):
	ctrl = c

const EditorMinimapBridge = preload("res://scripts/editor/interface/editor_minimap_bridge.gd")
const EditorSession = preload("res://scripts/editor/application/editor_session.gd")

func _add_popup(bar: MenuBar, title: String, items: Array) -> void:
	var pm = PopupMenu.new()
	pm.name = title
	for it in items:
		if typeof(it) != TYPE_ARRAY or (it as Array).is_empty():
			pm.add_separator()
			continue
		var row: Array = it
		pm.add_item(str(row[0]), int(row[1]))
	pm.id_pressed.connect(_on_menu)
	bar.add_child(pm)



func _on_menu(id: int) -> void:
	match id:
		ctrl.MENU_FILE_NEW:
			ctrl._new_pack()
		ctrl.MENU_FILE_OPEN:
			_open_pack_dialog()
		ctrl.MENU_FILE_SAVE:
			ctrl._save()
		ctrl.MENU_FILE_SAVE_AS:
			ctrl._saveas_edit.text = ctrl.pack.pack_id if ctrl.pack else "pack"
			ctrl._saveas_dlg.popup_centered()
		ctrl.MENU_FILE_OPEN_DEMO:
			ctrl._open_demo_copy()
		ctrl.MENU_FILE_IMPORT:
			ctrl._file_mode = "import"
			ctrl._pick_file(false)
		ctrl.MENU_FILE_EXPORT:
			ctrl._file_mode = "export"
			ctrl._pick_file(true)
		ctrl.MENU_FILE_LEAVE:
			ctrl._leave()
		ctrl.MENU_EDIT_UNDO:
			if ctrl.doc:
				ctrl.doc.undo()
				ctrl._reload_field()
		ctrl.MENU_EDIT_REDO:
			if ctrl.doc:
				ctrl.doc.redo()
				ctrl._reload_field()
		ctrl.MENU_EDIT_COPY:
			ctrl._copy_tiles()
		ctrl.MENU_EDIT_CUT:
			ctrl._cut_tiles()
		ctrl.MENU_EDIT_PASTE:
			ctrl._paste_tiles()
		25:
			ctrl._copy_entity()
		26:
			ctrl._paste_entity()
		27:
			ctrl._rotate_clip(true)
		28:
			ctrl._flip_clip(true)
		29:
			ctrl._replace_prompt()
		71:
			_show_undo_list()
		37:
			ctrl._pick_reference()
		38:
			ctrl._clear_reference()
		39:
			_add_bookmark_here()
		ctrl.MENU_MAP_SETTINGS:
			ctrl._open_map_settings(ctrl.current_map_id)
		34:
			ctrl._open_rename(ctrl.current_map_id)
		ctrl.MENU_MAP_ADD:
			ctrl._add_child_map()
		35:
			ctrl._dup_map(ctrl.current_map_id)
		ctrl.MENU_MAP_DEL:
			ctrl._ask_del_map(ctrl.current_map_id)
		ctrl.MENU_MAP_CHEST:
			ctrl._add_chest_event()
		ctrl.MENU_ENTITY:
			ctrl._open_entity_win()
		ctrl.MENU_ASSET_LIB:
			ctrl._open_asset_win()
		ctrl.MENU_ASSET_TILESET:
			ctrl._open_tileset_win()
		ctrl.MENU_ASSET_TILE:
			ctrl._file_mode = "tilesheet"
			ctrl._pick_file(false)
		ctrl.MENU_ASSET_CHAR:
			ctrl._file_mode = "charset"
			ctrl._pick_file(false)
		ctrl.MENU_ASSET_AUDIO:
			ctrl._file_mode = "audio"
			ctrl._pick_file(false)
		ctrl.MENU_GAME_PLAY:
			ctrl._playtest()
		ctrl.MENU_GAME_PLAY_CURSOR:
			ctrl._playtest(true)
		ctrl.MENU_MCP_TOGGLE:
			ctrl._toggle_mcp()



func _open_pack_dialog() -> void:
	EditorSession.open_pack_dialog(ctrl)



func _confirm_open_pack() -> void:
	EditorSession.confirm_open_pack(ctrl)



func _popup_win(win: Window) -> void:
	if win == null:
		return
	win.popup_centered()



func _on_file(path: String) -> void:
	EditorSession.on_file(ctrl, path)



func _undo_edit() -> void:
	if ctrl.doc == null or not ctrl.doc.has_method("undo_cells"):
		return
	var cells: Array[Vector2i] = ctrl.doc.undo_cells()
	if ctrl.paint and ctrl.paint.has_method("refresh_autotiles"):
		ctrl.paint.refresh_autotiles(ctrl.doc, cells, cells)
	if cells.is_empty():
		cells.append(ctrl._cursor)
	ctrl._refresh_dirty(cells)



func _redo_edit() -> void:
	if ctrl.doc == null or not ctrl.doc.has_method("redo_cells"):
		return
	var cells: Array[Vector2i] = ctrl.doc.redo_cells()
	if ctrl.paint and ctrl.paint.has_method("refresh_autotiles"):
		ctrl.paint.refresh_autotiles(ctrl.doc, cells, cells)
	if cells.is_empty():
		cells.append(ctrl._cursor)
	ctrl._refresh_dirty(cells)



func _show_undo_list() -> void:
	if ctrl._undo_dlg == null:
		ctrl._undo_dlg = AcceptDialog.new()
		ctrl._undo_dlg.title = "撤销历史"
		ctrl._undo_list = ItemList.new()
		ctrl._undo_list.custom_minimum_size = Vector2(320, 240)
		ctrl._undo_dlg.add_child(ctrl._undo_list)
		ctrl.add_child(ctrl._undo_dlg)
	ctrl._undo_list.clear()
	if ctrl.doc == null:
		ctrl._undo_dlg.popup_centered()
		return
	var stack: Array = ctrl.doc.get("_undo") if "_undo" in ctrl.doc else []
	ctrl._undo_list.add_item("共 %d 步（最近在上）" % stack.size())
	for i in range(stack.size() - 1, maxi(stack.size() - 16, -1), -1):
		if i < 0:
			break
		var cmd: Dictionary = stack[i] if typeof(stack[i]) == TYPE_DICTIONARY else {}
		var n: int = ctrl.doc._cmd_cells(cmd).size() if ctrl.doc.has_method("_cmd_cells") else 0
		ctrl._undo_list.add_item("%s · %d 格" % [str(cmd.get("t", "?")), n])
	ctrl._undo_dlg.popup_centered()



func _add_bookmark_here() -> void:
	EditorMinimapBridge.add_bookmark_here(ctrl)
