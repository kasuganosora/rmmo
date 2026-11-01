extends Window
## Map-directory editing and read-only address inspection share the MCP facade.
const Style = preload("res://scripts/world_editor/workspace_theme.gd")
var editor: Node3D
var tools: RefCounted
## Allows UI regression to exercise copy without replacing the user's clipboard.
var clipboard_writer: Callable = Callable()
var _maps: Array = []
var _documents: Dictionary = {}
var _selected_entry := ""
var _selected_document_id := ""
var _pack: OptionButton
var _tree: Tree
var _number: LineEdit
var _register: Button
var _save: Button
var _undo: Button
var _redo: Button
var _discard: Button
var _document_status: Label
var _status: Label
var _address: LineEdit
var _canonical: LineEdit
var _address_details: Label
var _copy: Button
var _close_prompt: ConfirmationDialog
var _discard_prompt: ConfirmationDialog
var _pending_documents: Array = []
var _pending_discard: Dictionary = {}
var _refreshing := false
var _listing_valid := false


static func open(target: Node3D) -> Window:
	var dialog := target.get_node_or_null("WorldAddressDialog") as Window
	if dialog == null:
		dialog = load("res://scripts/world_editor/world_address_dialog.gd").new()
		dialog.name = "WorldAddressDialog"
		dialog.editor = target
		dialog.tools = target._world_address_tools
		target.add_child(dialog)
	dialog.refresh()
	dialog.popup_centered_clamped(Vector2i(940, 730), 0.9)
	return dialog


func _ready() -> void:
	title = "世界地址与地图编号"
	min_size = Vector2i(660, 440)
	transient = true
	exclusive = true
	close_requested.connect(request_close)
	var panel := PanelContainer.new()
	panel.theme = Style.build()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_label(root, "地图编号与坐标地址", false)
	_label(root, "目录有独立的撤销记录。保存目录不会保存场景；解析地址不会移动角色。", true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var filters := HBoxContainer.new()
	body.add_child(filters)
	_label(filters, "资源包 / 版本", false)
	_pack = OptionButton.new()
	_pack.name = "WorldAddressPackPicker"
	_pack.fit_to_longest_item = false
	_pack.clip_text = true
	_pack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pack.item_selected.connect(func(_index): _fill_maps(); _invalidate_address())
	filters.add_child(_pack)
	_button(filters, "刷新目录", "RefreshWorldMapListButton", refresh)
	_tree = Tree.new()
	_tree.name = "WorldMapTree"
	_tree.columns = 4
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.custom_minimum_size.y = 170
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in 4:
		_tree.set_column_title(index, ["地图", "所属资源包", "编号", "登记状态"][index])
	_tree.set_column_expand(2, false)
	_tree.set_column_custom_minimum_width(2, 120)
	_tree.item_selected.connect(_select_map)
	body.add_child(_tree)
	var registration := HBoxContainer.new()
	body.add_child(registration)
	_label(registration, "数字编号", false)
	_number = LineEdit.new()
	_number.name = "MapNumberInput"
	_number.placeholder_text = "例如 123；确认登记后保持稳定"
	_number.max_length = 19
	_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_number.text_changed.connect(func(_text): _update_actions())
	registration.add_child(_number)
	_register = _button(registration, "登记所选地图", "RegisterWorldMapButton", _register_selected)
	_document_status = _label(body, "", true)
	_document_status.name = "WorldCatalogDocumentStatus"
	var directory_actions := HFlowContainer.new()
	body.add_child(directory_actions)
	_save = _button(directory_actions, "保存所选目录", "SaveWorldCatalogButton", _save_selected)
	_undo = _button(directory_actions, "目录撤销", "UndoWorldCatalogButton", _undo_selected)
	_redo = _button(directory_actions, "目录重做", "RedoWorldCatalogButton", _redo_selected)
	_discard = _button(directory_actions, "放弃所选目录编辑…", "DiscardWorldCatalogButton", _confirm_discard)
	body.add_child(HSeparator.new())
	_label(body, "世界地址（资源包:地图编号:x,y,z）", false)
	var address_row := HBoxContainer.new()
	body.add_child(address_row)
	_address = LineEdit.new()
	_address.name = "WorldAddressInput"
	_address.placeholder_text = "default:123:30,5,100"
	_address.max_length = 512
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_changed.connect(func(_text): _invalidate_address())
	_address.text_submitted.connect(func(_text): _resolve())
	address_row.add_child(_address)
	_button(address_row, "解析地址", "ResolveWorldAddressButton", _resolve)
	var current_actions := HFlowContainer.new()
	body.add_child(current_actions)
	_button(current_actions, "复制选中物件地址", "CopyObjectWorldAddressButton", _current.bind("object_origin"))
	_button(current_actions, "复制行走脚点地址", "CopyFeetWorldAddressButton", _current.bind("feet"))
	var result_row := HBoxContainer.new()
	body.add_child(result_row)
	_canonical = LineEdit.new()
	_canonical.name = "WorldAddressResult"
	_canonical.editable = false
	_canonical.placeholder_text = "解析后的规范地址"
	_canonical.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_row.add_child(_canonical)
	_copy = _button(result_row, "复制地址", "CopyWorldAddressButton", _copy_result)
	_copy.disabled = true
	_address_details = _label(body, "选择所需资源包版本可消除同名包歧义。坐标单位为米，Y 为高度。", true)
	_address_details.name = "WorldAddressDetails"
	_status = _label(body, "", true)
	_status.name = "WorldAddressStatus"
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	bottom.add_spacer(false)
	_button(bottom, "关闭", "CloseWorldAddressButton", request_close)
	_close_prompt = ConfirmationDialog.new()
	_close_prompt.theme = panel.theme
	_close_prompt.name = "WorldCatalogCloseConfirmation"
	_close_prompt.title = "地图目录尚未保存"
	_close_prompt.ok_button_text = "保存目录并关闭"
	_close_prompt.cancel_button_text = "继续编辑"
	_close_prompt.dialog_hide_on_ok = false
	_close_prompt.dialog_autowrap = true
	_close_prompt.add_button("放弃未保存编辑", false, "discard")
	_close_prompt.add_button("保留编辑并关闭", false, "keep")
	_close_prompt.confirmed.connect(_save_before_close)
	_close_prompt.custom_action.connect(_close_action)
	add_child(_close_prompt)
	_discard_prompt = ConfirmationDialog.new()
	_discard_prompt.theme = panel.theme
	_discard_prompt.name = "WorldCatalogDiscardConfirmation"
	_discard_prompt.title = "放弃目录编辑"
	_discard_prompt.ok_button_text = "重新读取磁盘目录"
	_discard_prompt.cancel_button_text = "取消"
	_discard_prompt.dialog_autowrap = true
	_discard_prompt.confirmed.connect(_discard_selected)
	add_child(_discard_prompt)
	_update_actions()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not _close_prompt.visible and not _discard_prompt.visible:
			request_close()
		get_viewport().set_input_as_handled()


func _label(parent: Node, value: String, wrap: bool) -> Label:
	var label := Label.new()
	label.text = value
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, control_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = control_name
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func refresh() -> void:
	if tools == null:
		_listing_valid = false
		_update_actions()
		_show_result({"ok": false, "message": "世界地址服务尚未就绪。"})
		return
	var listed: Dictionary = tools.list_maps({})
	if not listed.get("ok", false):
		_listing_valid = false
		# A missing pack/root must not strand an editor-owned directory draft.
		# Keep it selectable for an explicit reload/abandon, never for new writes.
		if tools.has_method("state"):
			var cached: Dictionary = tools.state()
			_documents.clear()
			for document: Dictionary in cached.get("documents", []):
				var view := document.duplicate(true)
				view.read_only = true
				view.reason_code = listed.get("reason_code", "catalog_unavailable")
				view.message = listed.get("message", "目录发现失败，可重新读取或放弃本会话编辑。")
				_documents[str(view.get("document_id", ""))] = view
		_fill_maps()
		_update_actions()
		_show_result(listed)
		return
	_listing_valid = true
	var previous_pack := _pack_root()
	_refreshing = true
	_maps = listed.get("maps", []).duplicate()
	_documents.clear()
	for document: Dictionary in listed.get("documents", []):
		_documents[str(document.get("document_id", ""))] = document
	_pack.clear()
	_pack.add_item("全部资源包")
	_pack.set_item_metadata(0, "")
	for pack: Dictionary in listed.get("packs", []):
		var pack_path := str(pack.get("root", pack.get("pack_root", "")))
		var pack_id := str(pack.get("id", pack.get("pack_id", "")))
		var label := "%s (%s)" % [pack.get("name", pack_id), pack_id]
		if not str(pack.get("version", "")).is_empty():
			label += " · " + str(pack.version)
		var index := _pack.item_count
		_pack.add_item(label)
		_pack.set_item_metadata(index, pack_path)
		_pack.set_item_tooltip(index, pack_path)
		if pack_path == previous_pack:
			_pack.select(index)
	_refreshing = false
	_fill_maps()


func _pack_root() -> String:
	if _pack == null or _pack.selected < 0:
		return ""
	return str(_pack.get_item_metadata(_pack.selected))


func _fill_maps() -> void:
	if _tree == null or _refreshing:
		return
	_refreshing = true
	_tree.clear()
	var root_item := _tree.create_item()
	var preferred: TreeItem
	var same_document: TreeItem
	var current: TreeItem
	for row: Dictionary in _rows_with_documents():
		if not _pack_root().is_empty() and row.get("pack_root", "") != _pack_root():
			continue
		var item := _tree.create_item(root_item)
		item.set_text(0, str(row.get("name", row.get("path", ""))))
		item.set_text(1, str(row.get("pack_id", "")))
		item.set_text(2, str(row.get("map_number", "")))
		var state := str(row.get("status", "unregistered"))
		item.set_text(3, {"registered": "已登记", "unregistered": "未登记", "missing": "文件缺失", "invalid": "不可登记", "conflict": "登记冲突", "tombstone": "编号已保留", "catalog_invalid": "目录只读", "catalog_document": "目录文档"}.get(state, state))
		item.set_metadata(0, row)
		item.set_tooltip_text(0, str(row.get("path", "")))
		item.set_tooltip_text(3, str(row.get("message", row.get("reason_code", ""))))
		if not _selected_entry.is_empty() and row.get("entry_id", "") == _selected_entry:
			preferred = item
		if row.get("document_id", "") == _selected_document_id:
			same_document = item
		if str(row.get("path", "")).replace("\\", "/").to_lower() == str(editor._path).replace("\\", "/").to_lower():
			current = item
	if preferred != null:
		preferred.select(0)
	elif same_document != null:
		same_document.select(0)
	elif current != null:
		current.select(0)
	_refreshing = false
	_select_map()


func _rows_with_documents() -> Array:
	var rows: Array = []
	var represented: Dictionary = {}
	for row: Dictionary in _maps:
		var document_id := str(row.get("document_id", ""))
		if not _documents.has(document_id):
			continue
		rows.append(row)
		represented[document_id] = true
	for document: Dictionary in _documents.values():
		var document_id := str(document.get("document_id", ""))
		if represented.has(document_id):
			continue
		rows.append({
			"entry_id": "", "document_id": document_id,
			"name": ("未保存目录 · " if document.get("dirty", false) else "地图目录 · ") + str(document.get("pack_id", "")),
			"path": document.get("path", ""), "pack_id": document.get("pack_id", ""), "pack_root": document.get("pack_root", ""),
			"map_number": "", "suggested_number": "", "map_ref": "",
			"status": "catalog_invalid" if document.get("read_only", false) else "catalog_document",
			"reason_code": document.get("reason_code", ""), "message": document.get("message", "")
		})
	return rows


func _selected_map() -> Dictionary:
	if _tree == null or _tree.get_selected() == null:
		return {}
	var value: Variant = _tree.get_selected().get_metadata(0)
	return value if value is Dictionary else {}


func _selected_document() -> Dictionary:
	return _documents.get(str(_selected_map().get("document_id", "")), {})


func _select_map() -> void:
	if _refreshing:
		return
	var row := _selected_map()
	_selected_entry = str(row.get("entry_id", ""))
	_selected_document_id = str(row.get("document_id", ""))
	_number.text = str(row.get("map_number", ""))
	if _number.text.is_empty():
		_number.text = str(row.get("suggested_number", ""))
	_update_actions()


func _update_actions() -> void:
	if _register == null:
		return
	var row := _selected_map()
	var document := _selected_document()
	var writable: bool = _listing_valid and not document.is_empty() and not document.get("read_only", false)
	var discovered_map: bool = not str(row.get("entry_id", "")).is_empty()
	_number.editable = writable and discovered_map and str(row.get("map_number", "")).is_empty()
	_register.disabled = not writable or not discovered_map or not str(row.get("map_number", "")).is_empty() or _number.text.is_empty()
	_save.disabled = not writable or not document.get("dirty", false)
	_undo.disabled = not writable or int(document.get("undo_count", 0)) == 0
	_redo.disabled = not writable or int(document.get("redo_count", 0)) == 0
	var needs_reload: bool = not _listing_valid or document.get("read_only", false) or document.get("disk_conflict", false)
	_discard.disabled = document.is_empty() or not (document.get("dirty", false) or needs_reload)
	_discard.text = "放弃所选目录编辑…" if document.get("dirty", false) else "重新载入所选目录…"
	if document.is_empty():
		_document_status.text = "选择地图后可查看其所属目录；地图编号不会根据目录名称或日期自动分配。"
		return
	_document_status.text = "%s · %s · 目录编辑修订 %s" % [document.get("pack_id", ""), "未保存" if document.get("dirty", false) else "已保存", document.get("edit_revision", 0)]
	if document.get("read_only", false):
		_document_status.text += " · 只读：" + str(document.get("message", document.get("reason_code", "目录不可编辑")))
	if document.get("disk_conflict", false):
		_document_status.text += " · 磁盘目录已变化，保存时将检查冲突"
	_document_status.tooltip_text = str(document.get("path", ""))


func _revision_args(document: Dictionary) -> Dictionary:
	return {"document_id": document.get("document_id", ""), "expected_edit_revision": document.get("edit_revision", -1)}


func _register_selected() -> void:
	var row := _selected_map()
	var document := _selected_document()
	if row.is_empty() or document.is_empty():
		return
	var result: Dictionary = tools.register_map({"entry_id": row.entry_id, "map_number": _number.text, "expected_edit_revision": document.edit_revision})
	refresh()
	_show_result(result, "地图编号已登记到当前目录编辑，保存目录后生效于后续会话。")


func _save_document(document: Dictionary) -> Dictionary:
	var args := _revision_args(document)
	args.expected_disk_sha = document.get("disk_sha", "")
	return tools.save_catalog(args)


func _save_selected() -> void:
	var document := _selected_document()
	if document.is_empty():
		return
	var result := _save_document(document)
	refresh()
	_show_result(result, "地图目录已保存；场景文件未修改。")


func _undo_selected() -> void:
	var document := _selected_document()
	if document.is_empty():
		return
	var result: Dictionary = tools.undo_catalog(_revision_args(document))
	refresh()
	_show_result(result, "已撤销一笔目录修改；已使用的编号继续保留。")


func _redo_selected() -> void:
	var document := _selected_document()
	if document.is_empty():
		return
	var result: Dictionary = tools.redo_catalog(_revision_args(document))
	refresh()
	_show_result(result, "已重做一笔目录修改。")


func _confirm_discard() -> void:
	_pending_discard = _selected_document().duplicate(true)
	if _pending_discard.is_empty():
		return
	if _pending_discard.get("reason_code", "") == "pack_unavailable":
		_discard_prompt.dialog_text = "资源包 %s 已不可用。放弃仅清理本会话中的目录编辑，不会重建资源包或修改地图。" % _pending_discard.get("pack_id", "")
	elif _pending_discard.get("dirty", false):
		_discard_prompt.dialog_text = "重新读取 %s 的磁盘目录，并放弃未保存的登记编辑。\n本会话已使用的编号仍可能保留，避免旧地址指向其他地图。" % _pending_discard.get("pack_id", "")
	else:
		_discard_prompt.dialog_text = "重新校验并读取 %s 的磁盘目录，更新当前目录状态。原地图文件不会修改。" % _pending_discard.get("pack_id", "")
	_discard_prompt.popup_centered_clamped(Vector2i(560, 180), 0.85)


func _discard_selected() -> void:
	var result: Dictionary = tools.discard_catalog(_revision_args(_pending_discard))
	_pending_discard.clear()
	refresh()
	_show_result(result, "已重新读取目录。请检查是否仍有待保存的编号保留记录。")


func _invalidate_address() -> void:
	if _canonical == null:
		return
	_canonical.clear()
	_copy.disabled = true
	_address_details.text = "地址尚未解析。解析只检查地址和地图身份，不验证落脚面或执行传送。"


func _resolve() -> void:
	var args: Dictionary = {"address": _address.text}
	if not _pack_root().is_empty():
		args.pack_root = _pack_root()
	var result: Dictionary = tools.resolve_address(args)
	_display_address(result)


func _current(anchor: String) -> void:
	var args: Dictionary = {"anchor_kind": anchor}
	if not _pack_root().is_empty():
		args.pack_root = _pack_root()
	var result: Dictionary = tools.current_address(args)
	if result.get("ok", false):
		_address.text = str(result.get("address", ""))
	_display_address(result)
	if result.get("ok", false):
		_copy_result()


func _display_address(result: Dictionary) -> void:
	_invalidate_address()
	if not result.get("ok", false):
		_show_result(result)
		return
	_canonical.text = str(result.get("address", ""))
	_copy.disabled = _canonical.text.is_empty()
	var anchor := str(result.get("anchor_kind", "point"))
	var anchor_label: String = {"point": "点坐标", "feet": "角色脚点", "object_origin": "物件原点"}.get(anchor, anchor)
	_address_details.text = "资源包 %s · 地图 %s · %s\n原地图身份：%s\n解析结果不代表落脚面、碰撞或传送就绪。" % [result.get("pack_id", ""), result.get("map_number", ""), anchor_label, result.get("map_ref", "")]
	if result.has("persisted") and not result.persisted:
		_address_details.text += "\n此编号登记尚未保存；后续会话使用前请保存目录。"
	_show_result(result, "地址已解析。")


func _copy_result() -> void:
	if _copy.disabled or _canonical.text.is_empty():
		return
	if clipboard_writer.is_valid():
		clipboard_writer.call(_canonical.text)
	else:
		DisplayServer.clipboard_set(_canonical.text)
	_status.text = "已复制规范地址。"


func _show_result(result: Dictionary, success: String = "") -> void:
	if _status == null:
		return
	if result.get("ok", false):
		_status.text = str(result.get("message", success))
		if _status.text.is_empty():
			_status.text = success
	else:
		_status.text = str(result.get("message", result.get("error", "操作失败")))
		if not str(result.get("reason_code", "")).is_empty():
			_status.text += "\n" + str(result.reason_code)
	_status.tooltip_text = _status.text


func _dirty_documents() -> Array:
	var result: Array = []
	for document: Dictionary in _documents.values():
		if document.get("dirty", false):
			result.append(document.duplicate(true))
	return result


func has_dirty_catalogs() -> bool:
	refresh()
	return not _dirty_documents().is_empty()


func request_close() -> void:
	refresh()
	_pending_documents = _dirty_documents()
	if _pending_documents.is_empty():
		hide()
		return
	_close_prompt.dialog_text = "%d 个资源包地图目录有未保存修改。\n保存只处理地图编号目录，不保存场景。保留编辑仅持续到当前编辑会话结束。" % _pending_documents.size()
	_close_prompt.popup_centered_clamped(Vector2i(670, 200), 0.95)


func _save_before_close() -> void:
	for document: Dictionary in _pending_documents:
		var result := _save_document(document)
		if not result.get("ok", false):
			_close_prompt.hide()
			refresh()
			_show_result(result)
			return
	_close_prompt.hide()
	refresh()
	if _dirty_documents().is_empty():
		hide()
	else:
		_show_result({"ok": false, "message": "目录仍有未保存修改，请检查后再关闭。"})


func _close_action(action: StringName) -> void:
	if action == &"keep":
		_close_prompt.hide()
		hide()
	elif action == &"discard":
		for document: Dictionary in _pending_documents:
			var result: Dictionary = tools.discard_catalog(_revision_args(document))
			if not result.get("ok", false):
				_close_prompt.hide()
				refresh()
				_show_result(result)
				return
		_close_prompt.hide()
		refresh()
		if _dirty_documents().is_empty():
			hide()
		else:
			_show_result({"ok": false, "message": "登记编辑已放弃，但本会话的编号保留记录尚未保存。可以保存目录，或选择“保留编辑并关闭”。"})
