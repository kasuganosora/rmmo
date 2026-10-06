extends SceneTree
## Drives the real content editor through the migrated session use cases.
## Creates packs under user:// and deletes only the ones this run added.


var _failed := 0
var _keep_packs: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var Editor = load("res://scripts/editor/content_editor.gd")
	var ed = Editor.new()
	root.add_child(ed)
	for _i in range(8):
		await process_frame
	if ed.pack == null or ed.doc == null:
		_fail("编辑器启动后没有打开内容包")
		_finish(ed)
		return
	_keep_packs = _pack_names()
	print("BOOT pack=%s map=%s status=%s" % [ed.pack.pack_id, ed.current_map_id, ed._status.text])

	_case_new_pack(ed)
	if ed.pack == null or str(ed.pack.root) == "":
		_finish(ed)
		return
	_case_save_shortcut(ed)
	var original_root := str(ed.pack.root)
	var saveas_root := _case_save_as(ed)
	_case_open_pack(ed, original_root)
	_case_map_tree(ed)
	_case_unsaved_switch(ed)
	_case_map_settings(ed)
	_case_windows(ed)
	_case_reference(ed)
	_case_rmpack(ed)
	_case_playtest(ed)
	_case_demo_copy(ed)
	if saveas_root != "":
		pass
	_finish(ed)


func _case_new_pack(ed) -> void:
	var before := str(ed.pack.root)
	ed._on_menu(ContentEditor.MENU_FILE_NEW)
	_expect(ed.pack != null and str(ed.pack.root) != before, "新建内容包换了目录")
	_expect(str(ed._status.text).begins_with("已新建"), "新建状态栏：%s" % ed._status.text)
	_expect(ed.doc != null and ed.current_map_id != "", "新建后选中起始地图")
	_expect(FileAccess.file_exists(str(ed.pack.root).path_join("pack.json")), "新建已写入 pack.json")


func _case_save_shortcut(ed) -> void:
	var before := int(ed.doc.tile(1, 1, 0))
	ed.doc.set_tile(1, 1, 0, before + 3)
	_key(ed, KEY_S, true, false)
	_expect(str(ed._status.text).begins_with("已保存"), "Ctrl+S：%s" % ed._status.text)
	_expect(not ed.doc.dirty, "Ctrl+S 后地图不再是脏的")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var loaded = ContentPack.new()
	var ok: bool = loaded.load_dir(str(ed.pack.root))
	_expect(ok and int(loaded.get_map(ed.current_map_id).tile(1, 1, 0)) == before + 3, "Ctrl+S 把格子写进磁盘")


func _case_save_as(ed) -> String:
	var nid := "regress_saveas_%d" % Time.get_ticks_msec()
	ed._on_menu(ContentEditor.MENU_FILE_SAVE_AS)
	_expect(ed._saveas_dlg.visible, "另存为对话框打开")
	ed._saveas_edit.text = nid
	ed._saveas_dlg.confirmed.emit()
	_expect(str(ed.pack.pack_id) == nid, "另存为后的包 id：%s" % ed.pack.pack_id)
	_expect(str(ed._status.text).begins_with("已另存为"), "另存为状态栏：%s" % ed._status.text)
	_expect(FileAccess.file_exists(str(ed.pack.root).path_join("pack.json")), "另存为目录有 pack.json")
	return str(ed.pack.root)


func _case_open_pack(ed, root_path: String) -> void:
	ed._on_menu(ContentEditor.MENU_FILE_OPEN)
	_expect(ed._open_dlg.visible, "打开包对话框")
	var idx := -1
	for i in range(ed._open_list.item_count):
		if str(ed._open_list.get_item_metadata(i)) == root_path:
			idx = i
			break
	_expect(idx >= 0, "打开列表里有新建的包")
	if idx < 0:
		return
	ed._open_list.select(idx)
	ed._open_dlg.confirmed.emit()
	_expect(str(ed.pack.root) == root_path, "确认打开后回到该包")
	_expect(str(ed._status.text).begins_with("已打开"), "打开状态栏：%s" % ed._status.text)
	_expect(ed.doc != null, "打开后有地图文档")


func _case_map_tree(ed) -> void:
	_key(ed, KEY_S, true, false)
	var parent_id := str(ed.current_map_id)
	var count_before: int = ed.pack.maps.size()
	ed._on_menu(ContentEditor.MENU_MAP_ADD)
	if ed._unsaved_dlg.visible:
		ed._unsaved_dlg.confirmed.emit()
	_expect(ed.pack.maps.size() == count_before + 1, "新建子地图")
	var child_id := str(ed.current_map_id)
	_expect(child_id != parent_id and _parent_of(ed, child_id) == parent_id, "子地图挂在当前地图下：%s -> %s" % [child_id, _parent_of(ed, child_id)])

	ed._on_menu(34)
	_expect(ed._rename_dlg.visible, "重命名对话框")
	ed._rename_edit.text = "回归改名"
	ed._rename_dlg.confirmed.emit()
	_expect(str(ed.doc.display_name) == "回归改名", "重命名结果：%s" % ed.doc.display_name)

	var dup_before: int = ed.pack.maps.size()
	_key(ed, KEY_D, true, false)
	_expect(ed.pack.maps.size() == dup_before + 1, "Ctrl+D 复制地图")
	var copy_id := str(ed.current_map_id)
	_expect(copy_id != child_id, "复制后选中新地图 %s" % copy_id)

	ed._ctx_map_id = child_id
	ed._on_map_ctx(ContentEditor.CTX_START)
	_expect(str(ed.pack.start_map) == child_id, "设为起始地图")

	ed._select_map(parent_id)
	if ed._unsaved_dlg.visible:
		ed._unsaved_dlg.confirmed.emit()
	ed._ctx_map_id = copy_id
	ed._on_map_ctx(ContentEditor.CTX_REPARENT)
	_expect(_parent_of(ed, copy_id) == parent_id, "复制地图移到根地图下")
	_expect(str(ed._status.text).begins_with("已将"), "移动状态栏：%s" % ed._status.text)

	var del_target := copy_id
	ed._select_map(del_target)
	if ed._unsaved_dlg.visible:
		ed._unsaved_dlg.confirmed.emit()
	var size_before_del: int = ed.pack.maps.size()
	ed._on_menu(ContentEditor.MENU_MAP_DEL)
	_expect(ed._del_dlg.visible, "删除确认框")
	ed._del_dlg.confirmed.emit()
	_expect(not ed.pack.maps.has(del_target) and ed.pack.maps.size() == size_before_del - 1, "确认后地图已删除")
	_expect(ed.pack.maps.size() >= 1 and ed.doc != null, "删除后仍停在一张地图上")


func _case_unsaved_switch(ed) -> void:
	_key(ed, KEY_S, true, false)
	var here := str(ed.current_map_id)
	var other := ""
	for mid in ed.pack.maps.keys():
		if str(mid) != here:
			other = str(mid)
			break
	_expect(other != "", "切换测试有第二张地图")
	if other == "":
		return
	var before := int(ed.doc.tile(2, 2, 0))
	var marker := before + 11
	ed.doc.set_tile(2, 2, 0, marker)
	ed._select_map(other)
	_expect(ed._unsaved_dlg.visible and str(ed._pending_switch) == other, "脏地图切换弹出未保存提示")
	_expect(str(ed.current_map_id) == here, "取消前仍停在原地图")
	ed._unsaved_dlg.confirmed.emit()
	_expect(str(ed.current_map_id) == other, "保存并切换")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var disk = ContentPack.new()
	disk.load_dir(str(ed.pack.root))
	_expect(int(disk.get_map(here).tile(2, 2, 0)) == marker, "保存并切换写回了修改")

	ed._select_map(here)
	if ed._unsaved_dlg.visible:
		ed._unsaved_dlg.confirmed.emit()
	var kept := int(ed.doc.tile(2, 2, 0))
	ed.doc.set_tile(2, 2, 0, kept + 5)
	ed._select_map(other)
	_expect(ed._unsaved_dlg.visible, "再次切换仍提示未保存")
	ed._unsaved_dlg.custom_action.emit("discard")
	_expect(str(ed.current_map_id) == other, "放弃修改后切走")
	ed._select_map(here)
	if ed._unsaved_dlg.visible:
		ed._unsaved_dlg.confirmed.emit()
	_expect(int(ed.doc.tile(2, 2, 0)) == kept, "放弃修改后格子恢复为磁盘内容")


func _case_map_settings(ed) -> void:
	var MapExt = load("res://scripts/map/map_ext.gd")
	_import_bgm(ed)
	ed._on_menu(ContentEditor.MENU_MAP_SETTINGS)
	_expect(ed._set_dlg.visible, "地图设置对话框")
	_expect(ed._set_ts.item_count > 0, "图块套列表有条目")
	_expect(ed._set_light.item_count > 0, "光照列表有条目")
	_expect(ed._set_bgm.item_count >= 2, "环境音列表含导入的 BGM")
	var ts_id := str(ed.doc.tileset_id)
	var ts_pick := 0
	for i in range(ed._set_ts.item_count):
		if str(ed._set_ts.get_item_metadata(i)) != ts_id:
			ts_pick = i
			break
	ed._set_name.text = "设置后的地图"
	ed._set_w.value = 18
	ed._set_h.value = 12
	ed._set_ts.select(ts_pick)
	ed._set_start.button_pressed = true
	ed._set_far_sx.value = 0.5
	ed._set_far_sy.value = -0.25
	ed._set_water.button_pressed = true
	ed._set_env.select(1)
	var light_pick := 1 if ed._set_light.item_count > 1 else 0
	ed._set_light.select(light_pick)
	var light_id := int(ed._set_light.get_item_id(light_pick))
	var bgm_pick := 0
	for i in range(ed._set_bgm.item_count):
		if str(ed._set_bgm.get_item_metadata(i)) == "regress_bgm":
			bgm_pick = i
			break
	ed._set_bgm.select(bgm_pick)
	ed._set_fx_color.color = Color(0.2, 0.4, 0.6, 1)
	ed._set_dlg.confirmed.emit()
	_expect(str(ed.doc.display_name) == "设置后的地图", "设置写了显示名")
	_expect(int(ed.doc.width) == 18 and int(ed.doc.height) == 12, "设置改了尺寸 %dx%d" % [ed.doc.width, ed.doc.height])
	_expect(str(ed.doc.tileset_id) == str(ed._set_ts.get_item_metadata(ts_pick)), "设置写了图块套")
	_expect(str(ed.pack.start_map) == str(ed.current_map_id), "设置勾选了起始地图")
	_expect(is_equal_approx(float(ed.doc.far_scroll.x), 0.5) and is_equal_approx(float(ed.doc.far_scroll.y), -0.25), "远景滚动")
	_expect(bool(ed.doc.water_through), "水面可走")
	_expect(str(ed.doc.environment) == str(MapExt.ENV_INDOOR), "室内环境")
	_expect(int(ed.doc.light_preset) == light_id, "光照预设 %s" % light_id)
	_expect(str(ed.doc.bgm) == "regress_bgm", "环境音")
	_expect(ed.doc.light_fx_color.is_equal_approx(Color(0.2, 0.4, 0.6, 1)), "光效颜色")
	_key(ed, KEY_S, true, false)
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var disk = ContentPack.new()
	var mid := str(ed.current_map_id)
	_expect(disk.load_dir(str(ed.pack.root)), "设置保存后能重新打开包")
	var doc = disk.get_map(mid)
	_expect(doc != null and int(doc.width) == 18 and int(doc.height) == 12, "磁盘上的尺寸")
	_expect(doc != null and str(doc.bgm) == "regress_bgm" and bool(doc.water_through), "磁盘上的环境音和水面")
	_expect(str(disk.start_map) == mid, "磁盘上的起始地图")


func _case_windows(ed) -> void:
	ed._on_menu(ContentEditor.MENU_ASSET_LIB)
	_expect(ed._asset_win != null and ed._asset_win.visible, "素材库窗口")
	_expect(ed._asset_win.pack == ed.pack, "素材库绑了当前包")
	ed._asset_win.hide()
	ed._on_menu(ContentEditor.MENU_ASSET_TILESET)
	_expect(ed._tileset_win != null and ed._tileset_win.visible, "图块套窗口")
	ed._tileset_win.hide()
	ed._on_menu(ContentEditor.MENU_ENTITY)
	_expect(ed._entity_win != null and ed._entity_win.visible, "实体窗口")
	_expect(ed._inspector != null, "实体检查器已绑定")
	ed._entity_win.hide()


func _case_reference(ed) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var path := ProjectSettings.globalize_path("user://regress_ref.png")
	_expect(img.save_png(path) == OK, "写出参考图")
	ed._on_menu(37)
	_expect(ed._file_mode == "reference" and ed._file_dlg.visible, "参考图文件框")
	ed._file_dlg.file_selected.emit(path)
	var sprite = ed.map_field.get_node_or_null("RefOverlay")
	_expect(sprite != null and sprite.visible and sprite.texture != null, "参考图盖在地图上")
	ed._on_menu(38)
	_expect(sprite != null and not sprite.visible, "清除参考图")
	_expect(str(ed._status.text).find("清除") >= 0, "清除参考图状态栏")
	DirAccess.remove_absolute(path)


func _case_rmpack(ed) -> void:
	var zip_path := ProjectSettings.globalize_path("user://regress_pack.rmpack")
	if FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)
	ed._on_menu(ContentEditor.MENU_FILE_EXPORT)
	_expect(ed._file_mode == "export" and ed._file_dlg.visible, "导出文件框")
	_expect(ed._file_dlg.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "导出是保存模式")
	ed._file_dlg.file_selected.emit(zip_path)
	_expect(FileAccess.file_exists(zip_path), "导出了 .rmpack")
	_expect(str(ed._status.text).begins_with("已导出"), "导出状态栏：%s" % ed._status.text)
	var exported_id := str(ed.pack.pack_id)
	ed._on_menu(ContentEditor.MENU_FILE_IMPORT)
	_expect(ed._file_mode == "import" and ed._file_dlg.visible, "导入文件框")
	ed._file_dlg.file_selected.emit(zip_path)
	_expect(str(ed._status.text).begins_with("已导入"), "导入状态栏：%s" % ed._status.text)
	_expect(str(ed.pack.pack_id) == exported_id, "导入后包 id 仍是 %s（实际 %s）" % [exported_id, ed.pack.pack_id])
	_expect(ed.doc != null and str(ed.current_map_id) == str(ed.pack.start_map), "导入后打开起始地图")
	_expect(str(ed.pack.root).find("/imp_") >= 0, "导入写到新的 imp_ 目录")
	DirAccess.remove_absolute(zip_path)


func _case_playtest(ed) -> void:
	var sess = ed.get_node_or_null("/root/GameSession")
	_expect(sess != null, "有 GameSession")
	if sess == null:
		return
	sess._loading_transition_active = true
	ed._cursor = Vector2i(3, 4)
	_key(ed, KEY_F5, false, true)
	var spawn: Dictionary = sess.spawn_data
	var cell: Dictionary = spawn.get("cell", {})
	_expect(bool(sess.editor_return), "Shift+F5 标记编辑器返回")
	_expect(str(sess.editor_pack_root) == str(ed.pack.root), "Shift+F5 记录包目录")
	_expect(str(sess.editor_map_id) == str(ed.current_map_id), "Shift+F5 记录地图")
	_expect(int(cell.get("x", -1)) == 3 and int(cell.get("y", -1)) == 4, "Shift+F5 出生在光标格")
	_expect(str(sess.loading_mode) == "transfer", "试玩走加载场景")
	sess._loading_transition_active = true
	_key(ed, KEY_F5, false, false)
	var cell2: Dictionary = (sess.spawn_data as Dictionary).get("cell", {})
	var start: Vector2i = ed.doc.start_cell
	_expect(int(cell2.get("x", -1)) == start.x and int(cell2.get("y", -1)) == start.y, "F5 出生在地图起点")
	sess._loading_transition_active = false


func _case_demo_copy(ed) -> void:
	print("DEMO copy start")
	ed._on_menu(ContentEditor.MENU_FILE_OPEN_DEMO)
	print("DEMO status=%s" % ed._status.text)
	var text := str(ed._status.text)
	var opened := text.begins_with("已复制 demo_map")
	var refused := text.find("无法") >= 0
	_expect(opened or refused, "打开 demo 副本有明确结果：%s" % text)
	if opened:
		_expect(ed.doc != null and str(ed.pack.root).find("demo_copy_") >= 0, "demo 副本在 user 目录并可编辑")


func _import_bgm(ed) -> void:
	var wav := _write_wav(ProjectSettings.globalize_path("user://regress_bgm.wav"))
	ed._on_menu(ContentEditor.MENU_ASSET_LIB)
	var win = ed._asset_win
	var item := _find_tree_meta(win._cat.get_root(), "audio/bgm")
	_expect(item != null, "素材库有 BGM 分类")
	if item == null:
		DirAccess.remove_absolute(wav)
		return
	item.select(0)
	win._on_cat()
	win._file_dlg.file_selected.emit(wav)
	_expect(str(win._info.text).begins_with("已导入"), "素材库导入 BGM：%s" % win._info.text)
	var listed := false
	for it in ed.pack.list_assets("audio/bgm"):
		if str(it.get("id", "")) == "regress_bgm":
			listed = true
	_expect(listed, "BGM 出现在 audio/bgm")
	win.hide()
	DirAccess.remove_absolute(wav)


func _find_tree_meta(item: TreeItem, kind: String) -> TreeItem:
	var cursor := item
	while cursor != null:
		var meta: Variant = cursor.get_metadata(0)
		if str(meta) == kind:
			return cursor
		var child := cursor.get_first_child()
		if child != null:
			var found := _find_tree_meta(child, kind)
			if found != null:
				return found
		cursor = cursor.get_next()
	return null


func _parent_of(ed, id: String) -> String:
	for item in ed.pack.map_tree:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("id", "")) == id:
			return str(item.get("parent", ""))
	return ""


func _key(ed, code: Key, ctrl: bool, shift: bool) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = false
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	ed._unhandled_input(event)


func _write_wav(path: String) -> String:
	var data := PackedByteArray()
	data.resize(44)
	data[0] = 0x52
	data[1] = 0x49
	data[2] = 0x46
	data[3] = 0x46
	data[8] = 0x57
	data[9] = 0x41
	data[10] = 0x56
	data[11] = 0x45
	data[12] = 0x66
	data[13] = 0x6d
	data[14] = 0x74
	data[15] = 0x20
	data[16] = 16
	data[20] = 1
	data[22] = 1
	data[24] = 0x44
	data[25] = 0xac
	data[34] = 16
	data[36] = 0x64
	data[37] = 0x61
	data[38] = 0x74
	data[39] = 0x61
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)
	return path


func _pack_names() -> Dictionary:
	var out := {}
	var abs_root := ProjectSettings.globalize_path("user://content/packs")
	var da := DirAccess.open(abs_root)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if da.current_is_dir() and not name.begins_with("."):
			out[name] = true
		name = da.get_next()
	da.list_dir_end()
	return out


func _finish(ed) -> void:
	if ed != null and is_instance_valid(ed):
		ed.queue_free()
	var abs_root := ProjectSettings.globalize_path("user://content/packs")
	var now := _pack_names()
	for name in now.keys():
		if _keep_packs.has(name):
			continue
		_wipe(abs_root.path_join(str(name)))
		print("CLEAN %s" % name)
	if _failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED %d" % _failed)
		quit(1)


func _wipe(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.remove_absolute(abs_path)
		return
	var da := DirAccess.open(abs_path)
	if da == null:
		return
	var dirs: Array[String] = []
	var files: Array[String] = []
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			if da.current_is_dir():
				dirs.append(name)
			else:
				files.append(name)
		name = da.get_next()
	da.list_dir_end()
	for file_name in files:
		DirAccess.remove_absolute(abs_path.path_join(file_name))
	for dir_name in dirs:
		_wipe(abs_path.path_join(dir_name))
	DirAccess.remove_absolute(abs_path)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("PASS %s" % label)
		return
	_failed += 1
	print("FAIL %s" % label)


func _fail(label: String) -> void:
	_expect(false, label)
