extends RefCounted
## 编辑器用例编排（应用层）：开包/新建/保存/选择/切换/删除/重命名/复制/试玩/导入导出。
## 所有方法为静态，接收组合根 ctrl: ContentEditor；状态字段经 ctrl.pack/doc/current_map_id/paint
## （委托到本实例的 pack/doc/current_map_id/paint）读写，UI/画布类辅助方法经 ctrl._method() 回调组合根。

const ContentPack = preload("res://scripts/editor/domain/content_pack.gd")
const Rtp = preload("res://scripts/editor/infrastructure/rtp.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const PackZip = preload("res://scripts/editor/infrastructure/pack_zip.gd")

## 会话状态袋。ContentEditor 通过委托属性（ctrl.pack/doc/current_map_id/paint）读写本实例字段。
var pack: RefCounted = null
var doc: RefCounted = null
var current_map_id: String = ""
var paint: RefCounted = null


static func open_or_create_default(ctrl: ContentEditor) -> void:
	var path := ContentPack.pack_dir_for(Rtp.DEFAULT_PACK_ID)
	ctrl.pack = ContentPack.new()
	if ctrl.pack.load_dir(path):
		if ctrl.pack.dirty:
			ctrl.pack.save_dir()
		select_map(ctrl, ctrl.pack.start_map)
		ctrl._status.text = "已打开默认包 · %s" % ctrl.pack.root
		return
	ctrl.pack.new_blank(Rtp.DEFAULT_PACK_ID, "默认内容包", 25, 20)
	ctrl.pack.save_dir()
	select_map(ctrl, ctrl.pack.start_map)
	ctrl._status.text = "已创建默认包（MV 室外图块）· %s" % ctrl.pack.root


static func new_pack(ctrl: ContentEditor) -> void:
	ctrl.current_map_id = ""
	ctrl.pack = ContentPack.new()
	var pid := "pack_%d" % int(Time.get_unix_time_from_system())
	ctrl.pack.new_blank(pid, "新内容包", 25, 20)
	ctrl.pack.save_dir()
	select_map(ctrl, ctrl.pack.start_map)
	ctrl._status.text = "已新建 %s" % ctrl.pack.root


static func save(ctrl: ContentEditor) -> void:
	if ctrl.pack == null:
		return
	if ctrl.pack.save_dir():
		ctrl._status.text = "已保存 %s" % ctrl.pack.root
	else:
		ctrl._status.text = "保存失败"


static func leave(ctrl: ContentEditor) -> void:
	ctrl._restore_window_scale()
	var sess = ctrl.get_node_or_null("/root/GameSession")
	if sess and sess.get("editor_return"):
		sess.editor_return = false
		sess.go_world()
	elif sess:
		sess.go_character_select()
	else:
		ctrl.get_tree().change_scene_to_file("res://scenes/login.tscn")


static func playtest(ctrl: ContentEditor, from_cursor: bool = false) -> void:
	if ctrl.pack == null:
		return
	ctrl.pack.save_dir()
	var sess = ctrl.get_node_or_null("/root/GameSession")
	if sess == null:
		ctrl._status.text = "无会话"
		return
	sess.editor_return = true
	sess.editor_pack_root = ctrl.pack.root
	sess.editor_map_id = ctrl.current_map_id
	var ch: Dictionary = sess.active_character() if sess.has_method("active_character") else {}
	if ch.is_empty():
		ch = {"name": "编辑器", "look_id": "1", "gender": "female", "level": 1, "class_id": "adventurer"}
	var sc: Vector2i = ctrl.doc.start_cell if ctrl.doc else Vector2i(2, 2)
	if from_cursor:
		sc = ctrl._cursor
		if ctrl.doc:
			sc = Vector2i(clampi(sc.x, 0, ctrl.doc.width - 1), clampi(sc.y, 0, ctrl.doc.height - 1))
	sess.spawn_data = {
		"pack_path": ctrl.pack.root,
		"map_id": ctrl.current_map_id,
		"cell": {"x": sc.x, "y": sc.y},
		"character": ch,
		"content_id": ctrl.pack.pack_id,
	}
	sess.loading_mode = "transfer"
	sess.go_loading()


static func select_map(ctrl: ContentEditor, id: String) -> void:
	if id == ctrl.current_map_id:
		return
	if ctrl.current_map_id != "" and ctrl.pack != null and ctrl.pack.has_method("map_is_dirty") and ctrl.pack.map_is_dirty(ctrl.current_map_id):
		ctrl._pending_switch = id
		ctrl._unsaved_dlg.popup_centered()
		return
	do_select_map(ctrl, id)


static func do_select_map(ctrl: ContentEditor, id: String) -> void:
	if id != ctrl.current_map_id:
		ctrl._cam_ready = false
	ctrl.current_map_id = id
	ctrl.doc = ctrl.pack.get_map(id)
	fix_autotiles(ctrl)
	ctrl._refresh_tree()
	ctrl._sync_palette()
	reload_assets(ctrl)
	ctrl._reload_field()
	ctrl._sync_light_controls()
	ctrl._apply_editor_light()
	ctrl._sync_fx_color_controls()
	ctrl._apply_editor_fx_color()
	if ctrl._inspector:
		if ctrl._inspector.has_method("bind_pack"):
			ctrl._inspector.bind_pack(ctrl.pack)
		ctrl._inspector.load_cell(ctrl.doc, ctrl._cursor)


static func confirm_switch_save(ctrl: ContentEditor) -> void:
	save(ctrl)
	var nid := ctrl._pending_switch
	ctrl._pending_switch = ""
	if nid != "":
		do_select_map(ctrl, nid)


static func unsaved_action(ctrl: ContentEditor, action: String) -> void:
	if action != "discard":
		return
	ctrl._unsaved_dlg.hide()
	var nid := ctrl._pending_switch
	ctrl._pending_switch = ""
	if ctrl.pack and ctrl.current_map_id != "" and ctrl.pack.has_method("reload_map"):
		if not ctrl.pack.reload_map(ctrl.current_map_id):
			if ctrl.doc:
				ctrl.doc.dirty = false
	elif ctrl.doc:
		ctrl.doc.dirty = false
	if nid != "":
		do_select_map(ctrl, nid)


static func open_pack_dialog(ctrl: ContentEditor) -> void:
	ctrl._open_list.clear()
	var packs: Array = ContentPack.list_user_packs()
	for p in packs:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		ctrl._open_list.add_item("%s  (%s)" % [str(p.get("name", "")), str(p.get("id", ""))])
		ctrl._open_list.set_item_metadata(ctrl._open_list.item_count - 1, str(p.get("root", "")))
	ctrl._open_dlg.popup_centered()


static func confirm_open_pack(ctrl: ContentEditor) -> void:
	var idx := ctrl._open_list.get_selected_items()
	if idx.is_empty():
		return
	var root_path := str(ctrl._open_list.get_item_metadata(idx[0]))
	ctrl.current_map_id = ""
	ctrl.pack = ContentPack.new()
	if ctrl.pack.load_dir(root_path):
		do_select_map(ctrl, ctrl.pack.start_map)
		ctrl._status.text = "已打开 %s" % ctrl.pack.pack_id
	else:
		ctrl._status.text = "无法打开 %s" % root_path


static func confirm_save_as(ctrl: ContentEditor) -> void:
	if ctrl.pack == null:
		return
	var nid := ctrl._saveas_edit.text.strip_edges()
	if nid == "":
		return
	if ctrl.pack.save_as(nid):
		ctrl._status.text = "已另存为 %s" % ctrl.pack.pack_id
	else:
		ctrl._status.text = "另存为失败"


static func open_demo_copy(ctrl: ContentEditor) -> void:
	ctrl.current_map_id = ""
	ctrl.pack = ContentPack.new()
	if not ctrl.pack.load_dir("res://demo_map"):
		ctrl._status.text = "无法读取 res://demo_map"
		return
	var nid := "demo_copy_%d" % int(Time.get_unix_time_from_system())
	if ctrl.pack.adopt_as_user_pack(nid, "demo_map 副本"):
		do_select_map(ctrl, ctrl.pack.start_map)
		ctrl._status.text = "已复制 demo_map → %s" % ctrl.pack.root
	else:
		ctrl._status.text = "无法保存 user 副本"


static func on_reparent(ctrl: ContentEditor, src: String, parent: String) -> void:
	if ctrl.pack == null:
		return
	if ctrl.pack.set_parent(src, parent):
		ctrl._refresh_tree()
		ctrl._status.text = "已将 %s 移到 %s 下" % [src, parent]
	else:
		ctrl._status.text = "无法移动（环路？）"


static func set_start_map(ctrl: ContentEditor, mid: String) -> void:
	if ctrl.pack == null or not ctrl.pack.maps.has(mid):
		return
	ctrl.pack.start_map = mid
	ctrl.pack.dirty = true
	ctrl._refresh_tree()
	ctrl._status.text = "起始地图 → %s" % mid


static func add_child_map(ctrl: ContentEditor) -> void:
	if ctrl.pack == null:
		return
	var nid: String = ctrl.pack.next_map_id() if ctrl.pack.has_method("next_map_id") else ("Map%03d" % (ctrl.pack.maps.size() + 1))
	var ts := ""
	if ctrl.doc:
		ts = str(ctrl.doc.tileset_id)
	ctrl.pack.add_map(nid, "新地图", ctrl.current_map_id, 20, 15, ts)
	select_map(ctrl, nid)


static func del_map(ctrl: ContentEditor) -> void:
	ask_del_map(ctrl, ctrl.current_map_id)


static func ask_del_map(ctrl: ContentEditor, mid: String) -> void:
	if ctrl.pack == null or mid == "":
		return
	if ctrl.pack.maps.size() <= 1:
		ctrl._status.text = "至少留一张地图"
		return
	ctrl._ctx_map_id = mid
	var d = ctrl.pack.get_map(mid)
	var label := str(d.display_name) if d else mid
	ctrl._del_dlg.dialog_text = "确定删除地图「%s」？子地图会提升到上一级。" % label
	ctrl._del_dlg.popup_centered()


static func confirm_del_map(ctrl: ContentEditor) -> void:
	var mid := ctrl._ctx_map_id if ctrl._ctx_map_id != "" else ctrl.current_map_id
	if ctrl.pack == null or not ctrl.pack.maps.has(mid):
		return
	if ctrl.pack.maps.size() <= 1:
		ctrl._status.text = "至少留一张地图"
		return
	ctrl.pack.remove_map(mid)
	select_map(ctrl, ctrl.pack.start_map)
	ctrl._status.text = "已删除 %s" % mid


static func open_map_settings(ctrl: ContentEditor, mid: String) -> void:
	if ctrl.pack == null or mid == "":
		return
	if mid != ctrl.current_map_id:
		select_map(ctrl, mid)
	if ctrl.doc == null:
		return
	ctrl._ctx_map_id = mid
	ctrl._set_name.text = str(ctrl.doc.display_name)
	ctrl._set_w.value = ctrl.doc.width
	ctrl._set_h.value = ctrl.doc.height
	ctrl._set_start.button_pressed = ctrl.pack.start_map == mid
	if ctrl._set_far_sx:
		ctrl._set_far_sx.value = ctrl.doc.far_scroll.x
	if ctrl._set_far_sy:
		ctrl._set_far_sy.value = ctrl.doc.far_scroll.y
	if ctrl._set_water:
		ctrl._set_water.button_pressed = ctrl.doc.water_through
	if ctrl._set_env:
		var env := MapExt.ENV_OUTDOOR
		if "environment" in ctrl.doc:
			env = MapExt.normalize_environment(ctrl.doc.environment)
		ctrl._set_env.select(1 if env == MapExt.ENV_INDOOR else 0)
	ctrl._fill_bgm_opt(str(ctrl.doc.bgm) if "bgm" in ctrl.doc else "")
	ctrl._fill_preset_opt(ctrl._set_light, "map/light_presets.json", ["日间", "黄昏", "夜晚"])
	ctrl._select_opt_id(ctrl._set_light, int(ctrl.doc.light_preset) if "light_preset" in ctrl.doc else 0)
	if ctrl._set_fx_color:
		ctrl._set_fx_color.color = ctrl.doc.light_fx_color if "light_fx_color" in ctrl.doc else Color(1, 1, 1, 1)
	ctrl._set_ts.clear()
	var keys: Array = ctrl.pack.tilesets.keys()
	keys.sort()
	var i := 0
	for k in keys:
		var sid := str(k)
		var label: String = ctrl.pack.tileset_label(sid) if ctrl.pack.has_method("tileset_label") else Rtp.display_name(sid)
		ctrl._set_ts.add_item(label, i)
		ctrl._set_ts.set_item_metadata(i, sid)
		if sid == str(ctrl.doc.tileset_id):
			ctrl._set_ts.select(i)
		i += 1
	ctrl._set_dlg.popup_centered()


static func apply_map_settings(ctrl: ContentEditor) -> void:
	if ctrl.pack == null or ctrl.doc == null:
		return
	var mid := ctrl.current_map_id
	var new_name := ctrl._set_name.text.strip_edges()
	if new_name == "":
		new_name = mid
	ctrl.pack.rename_map(mid, new_name)
	var ts_id := str(ctrl._set_ts.get_item_metadata(ctrl._set_ts.selected)) if ctrl._set_ts.item_count > 0 else ""
	if ts_id != "":
		ctrl.pack.set_map_tileset(mid, ts_id)
	var nw := int(ctrl._set_w.value)
	var nh := int(ctrl._set_h.value)
	if ctrl._set_far_sx and ctrl._set_far_sy:
		ctrl.doc.far_scroll = Vector2(ctrl._set_far_sx.value, ctrl._set_far_sy.value)
		ctrl.doc.dirty = true
	if ctrl._set_water:
		ctrl.doc.water_through = ctrl._set_water.button_pressed
		ctrl.doc.dirty = true
	if ctrl._set_env:
		var env_id := MapExt.ENV_OUTDOOR
		if ctrl._set_env.selected >= 0:
			env_id = MapExt.normalize_environment(ctrl._set_env.get_item_metadata(ctrl._set_env.selected))
		ctrl.doc.environment = env_id
		ctrl.doc.dirty = true
	if ctrl._set_bgm and "bgm" in ctrl.doc:
		var bgm_id := ""
		if ctrl._set_bgm.selected >= 0:
			bgm_id = str(ctrl._set_bgm.get_item_metadata(ctrl._set_bgm.selected))
		ctrl.doc.bgm = bgm_id
		ctrl.doc.dirty = true
	if ctrl._set_light and "light_preset" in ctrl.doc:
		ctrl.doc.light_preset = int(ctrl._set_light.get_item_id(ctrl._set_light.selected)) if ctrl._set_light.item_count > 0 else 0
		ctrl.doc.dirty = true
		ctrl._sync_light_controls()
		ctrl._apply_editor_light()
	if ctrl._set_fx_color and "light_fx_color" in ctrl.doc:
		ctrl.doc.light_fx_color = ctrl._set_fx_color.color
		ctrl.doc.dirty = true
		ctrl._sync_fx_color_controls()
		ctrl._apply_editor_fx_color()
	if nw != int(ctrl.doc.width) or nh != int(ctrl.doc.height):
		ctrl.doc.resize(nw, nh)
		var sc: Vector2i = ctrl.doc.start_cell
		ctrl.doc.start_cell = Vector2i(clampi(sc.x, 0, ctrl.doc.width - 1), clampi(sc.y, 0, ctrl.doc.height - 1))
	if ctrl._set_start.button_pressed:
		ctrl.pack.start_map = mid
		ctrl.pack.dirty = true
	ctrl.pack.dirty = true
	ctrl._refresh_tree()
	ctrl._sync_palette()
	ctrl._reload_field()
	ctrl._status.text = "已更新地图设置 · %s %dx%d（未写入磁盘，Ctrl+S 保存）" % [new_name, ctrl.doc.width, ctrl.doc.height]


static func dup_map(ctrl: ContentEditor, mid: String) -> void:
	if ctrl.pack == null or not ctrl.pack.has_method("duplicate_map"):
		return
	var nid: String = ctrl.pack.duplicate_map(mid)
	if nid == "":
		ctrl._status.text = "复制失败"
		return
	select_map(ctrl, nid)
	ctrl._status.text = "已复制为 %s" % nid


static func open_rename(ctrl: ContentEditor, mid: String) -> void:
	if ctrl.pack == null or mid == "":
		return
	ctrl._ctx_map_id = mid
	var d = ctrl.pack.get_map(mid)
	ctrl._rename_edit.text = str(d.display_name) if d else mid
	ctrl._rename_dlg.popup_centered()
	ctrl._rename_edit.grab_focus()
	ctrl._rename_edit.select_all()


static func apply_rename(ctrl: ContentEditor) -> void:
	var mid := ctrl._ctx_map_id if ctrl._ctx_map_id != "" else ctrl.current_map_id
	var nm := ctrl._rename_edit.text.strip_edges()
	if nm == "" or ctrl.pack == null:
		return
	ctrl.pack.rename_map(mid, nm)
	ctrl._refresh_tree()
	ctrl._status.text = "已重命名为 %s" % nm


static func on_file(ctrl: ContentEditor, path: String) -> void:
	match ctrl._file_mode:
		"export":
			if PackZip.export_zip(ctrl.pack.root, path):
				ctrl._status.text = "已导出 %s" % path
			else:
				ctrl._status.text = "导出失败"
		"import":
			var dest := "%s/imp_%d" % [ContentPack.USER_PACKS, int(Time.get_unix_time_from_system())]
			var res: Dictionary = PackZip.import_zip(path, dest)
			if bool(res.get("ok", false)):
				ctrl.current_map_id = ""
				ctrl.pack = ContentPack.new()
				if ctrl.pack.load_dir(str(res.get("root", dest))):
					select_map(ctrl, ctrl.pack.start_map)
					ctrl._status.text = "已导入 %s" % ctrl.pack.pack_id
				else:
					ctrl._status.text = "导入后无法加载"
			else:
				ctrl._status.text = str(res.get("error", "导入失败"))
		"tilesheet", "charset", "audio":
			import_asset(ctrl, path, ctrl._file_mode)
		"reference":
			if ctrl.map_field and ctrl.map_field.has_method("set_reference_image"):
				ctrl.map_field.set_reference_image(path, 0.35)
			ctrl._status.text = "参考图 %s" % path.get_file()


static func import_asset(ctrl: ContentEditor, src: String, kind: String) -> void:
	if ctrl.pack == null:
		return
	if ctrl.pack.root.is_empty():
		ctrl.pack.save_dir()
	var id := ""
	if ctrl.pack.has_method("import_asset_file"):
		id = ctrl.pack.import_asset_file(src, kind)
	if id == "":
		ctrl._status.text = "导入失败"
		return
	ctrl._status.text = "已导入 %s → %s" % [kind, id]
	reload_assets(ctrl)
	if kind != "tilesheet":
		return
	var ts_id := str(ctrl.doc.tileset_id) if ctrl.doc else ""
	if ts_id == "" or not ctrl.pack.tilesets.has(ts_id):
		ts_id = "outside" if ctrl.pack.tilesets.has("outside") else (str(ctrl.pack.tilesets.keys()[0]) if not ctrl.pack.tilesets.is_empty() else "")
	if ts_id == "":
		return
	var ts: Dictionary = ctrl.pack.tilesets[ts_id]
	var names: Variant = ts.get("tilesetNames", [])
	if typeof(names) != TYPE_ARRAY:
		return
	var arr: Array = names
	while arr.size() < 9:
		arr.append("")
	var slot := 4
	for s in range(9):
		if str(arr[s]).strip_edges() == "":
			slot = s
			break
	arr[slot] = id
	ts["tilesetNames"] = arr
	ctrl.pack.tilesets[ts_id] = ts
	ctrl.pack.dirty = true
	finish_sheet_assign(ctrl, slot, id)


static func finish_sheet_assign(ctrl: ContentEditor, slot: int, sheet: String) -> void:
	var ts_id := str(ctrl.doc.tileset_id) if ctrl.doc else ""
	if ts_id != "" and ctrl.pack.has_method("init_slot_passage"):
		ctrl.pack.init_slot_passage(ts_id, slot)
	ctrl._sync_palette()
	ctrl._reload_field()
	if ctrl._palette and ctrl._palette.has_method("select_slot"):
		ctrl._palette.select_slot(slot)
	ctrl._set_mode(2)
	var names: PackedStringArray = ["A1", "A2", "A3", "A4", "A5", "B", "C", "D", "E"]
	var lbl: String = names[slot] if slot >= 0 and slot < names.size() else str(slot)
	var hint := "× 阻挡" if slot == 2 or slot == 3 else "○ 可走"
	ctrl._status.text = "已编入 %s ← %s（默认%s）。点图块改 ○/×/★" % [lbl, sheet, hint]


static func fix_autotiles(ctrl: ContentEditor) -> void:
	if ctrl.paint == null or ctrl.doc == null or not ctrl.paint.has_method("refresh_all_floor_autotiles"):
		return
	var n: int = int(ctrl.paint.refresh_all_floor_autotiles(ctrl.doc))
	if n > 0:
		ctrl.doc.dirty = true


static func reload_assets(ctrl: ContentEditor) -> void:
	if ctrl._asset_win and ctrl._asset_win.has_method("bind_pack") and ctrl._asset_win.visible:
		ctrl._asset_win.bind_pack(ctrl.pack)
