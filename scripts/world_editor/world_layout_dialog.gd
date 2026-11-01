extends Window
## Author-only layout drafting. All validation, history and disk writes use the MCP facade.
const Style = preload("res://scripts/world_editor/workspace_theme.gd")
const Canvas = preload("res://scripts/world_editor/world_layout_canvas.gd")
const Address = preload("res://scripts/world3d/world_address.gd")
const EDGES := ["x_min", "x_max", "z_min", "z_max"]
var editor: Node3D
var tools: RefCounted
var _document: Dictionary = {}
var _documents: Dictionary = {}
var _layout: Dictionary = {}
var _base_layout: Dictionary = {}
var _new_context: Dictionary = {}
var _candidate: Dictionary = {}
var _diagnostics: Array = []
var _space_id := ""
var _placement_id := ""
var _seam_id := ""
var _loading := false
var _placement_pending := false
var _seam_pending := false
var _world_form_pending := false
var _space_form_pending := false
var _listing_valid := false
var _pending_action: Callable
var _worlds: OptionButton
var _packs: OptionButton
var _world_key: LineEdit
var _spaces: OptionButton
var _space_name: LineEdit
var _placements: Tree
var _seams: Tree
var _maps: OptionButton
var _place_fields: Dictionary = {}
var _seam_fields: Dictionary = {}
var _canvas: Control
var _diagnostic_tree: Tree
var _diagnostic_details: Label
var _state_label: Label
var _status: Label
var _preview_button: Button
var _apply_button: Button
var _save_button: Button
var _undo_button: Button
var _redo_button: Button
var _reload_button: Button
var _replace_prompt: ConfirmationDialog
var _close_prompt: ConfirmationDialog
var _address: LineEdit
var _address_result: Label
var _locate_fields: Dictionary = {}


static func open(target: Node3D) -> Window:
	var dialog := target.get_node_or_null("WorldLayoutDialog") as Window
	if dialog == null:
		dialog = load("res://scripts/world_editor/world_layout_dialog.gd").new()
		dialog.name = "WorldLayoutDialog"
		dialog.editor = target
		dialog.tools = target._world_layout_tools
		target.add_child(dialog)
	dialog.refresh()
	dialog.popup_centered_clamped(Vector2i(1180, 880), 0.94)
	return dialog


func _ready() -> void:
	title = "世界布局与接缝诊断"
	min_size = Vector2i(780, 560)
	transient = true
	exclusive = true
	close_requested.connect(request_close)
	var panel := PanelContainer.new()
	panel.theme = Style.build()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	_label(root, "世界布局 · 不同尺寸地图 · 平移放置", false)
	_label(root, "表单 → 草稿 → 预览 → 应用（单笔撤销）→ 保存布局。布局与地图、编号目录各自保存；此窗口不加载邻图。", true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_build_world_controls(body)
	_build_space_controls(body)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	var tabs := TabContainer.new()
	tabs.name = "WorldLayoutFormTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.x = 430
	split.add_child(tabs)
	_build_placement_controls(tabs)
	_build_seam_controls(tabs)
	var overview := VBoxContainer.new()
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(overview)
	_canvas = Canvas.new()
	_canvas.name = "WorldLayoutCanvas"
	_canvas.placement_selected.connect(_select_canvas_placement)
	overview.add_child(_canvas)
	_label(overview, "XZ 归属范围为左闭右开。预览检查布局结构；接缝检查另读取已保存原生高度场。运行通行尚未验证。", true)
	_diagnostic_tree = _tree(overview, "WorldLayoutDiagnostics", ["级别", "位置 / 问题"], 120)
	_diagnostic_tree.set_column_expand(0, false)
	_diagnostic_tree.set_column_custom_minimum_width(0, 55)
	_diagnostic_tree.item_selected.connect(_select_diagnostic)
	_diagnostic_details = _label(overview, "预览会列出重叠、边界、接缝和角点诊断。选择一条可高亮并查看两侧坐标。", true)
	_diagnostic_details.name = "WorldLayoutDiagnosticDetails"
	_build_address_controls(body)
	# Transaction controls remain visible while the forms and results scroll.
	_state_label = _label(root, "", true)
	_state_label.name = "WorldLayoutDocumentStatus"
	var actions := HFlowContainer.new()
	root.add_child(actions)
	_preview_button = _button(actions, "预览草稿", "WorldLayoutPreviewButton", _preview)
	_apply_button = _button(actions, "应用候选", "WorldLayoutApplyButton", _apply)
	_save_button = _button(actions, "保存所选布局", "WorldLayoutSaveButton", _save)
	_undo_button = _button(actions, "布局撤销", "WorldLayoutUndoButton", _request_history.bind("undo_layout"))
	_redo_button = _button(actions, "布局重做", "WorldLayoutRedoButton", _request_history.bind("redo_layout"))
	_reload_button = _button(actions, "重新读取 / 放弃文档编辑…", "WorldLayoutReloadButton", _request_reload)
	_button(actions, "放弃未应用草稿…", "WorldLayoutDiscardDraftButton", _request_discard_draft)
	_button(actions, "检查已应用接缝", "WorldLayoutValidateSeamsButton", _validate_seams)
	_status = _label(root, "选择已有世界后载入，或选择所属包并输入世界标识，新建布局草稿。", true)
	_status.name = "WorldLayoutStatus"
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	bottom.add_spacer(false)
	_button(bottom, "关闭", "WorldLayoutCloseButton", request_close)
	_replace_prompt = ConfirmationDialog.new()
	_replace_prompt.name = "WorldLayoutReplaceConfirmation"
	_replace_prompt.theme = panel.theme
	_replace_prompt.title = "确认替换编辑"
	_replace_prompt.ok_button_text = "确认"
	_replace_prompt.cancel_button_text = "继续编辑"
	_replace_prompt.dialog_autowrap = true
	_replace_prompt.confirmed.connect(func():
		_replace_prompt.hide()
		var action := _pending_action
		_pending_action = Callable()
		if action.is_valid(): action.call())
	add_child(_replace_prompt)
	_close_prompt = ConfirmationDialog.new()
	_close_prompt.name = "WorldLayoutCloseConfirmation"
	_close_prompt.theme = panel.theme
	_close_prompt.title = "世界布局尚未保存"
	_close_prompt.dialog_autowrap = true
	_close_prompt.dialog_hide_on_ok = false
	_close_prompt.ok_button_text = "保存并关闭"
	_close_prompt.cancel_button_text = "继续编辑"
	_close_prompt.add_button("保留编辑并关闭", false, "keep")
	_close_prompt.add_button("放弃未保存编辑并关闭", false, "discard")
	_close_prompt.confirmed.connect(_save_before_close)
	_close_prompt.custom_action.connect(_close_action)
	add_child(_close_prompt)
	_update_state()


func _build_world_controls(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, "已有世界", false)
	_worlds = _option(row, "WorldLayoutWorldPicker")
	_button(row, "载入", "WorldLayoutLoadButton", _request_load)
	_button(row, "刷新列表", "WorldLayoutRefreshButton", refresh)
	var creation := HBoxContainer.new()
	parent.add_child(creation)
	_label(creation, "所属包", false)
	_packs = _option(creation, "WorldLayoutPackPicker")
	_world_key = _line(creation, "WorldLayoutWorldKeyInput", "世界标识，例如 overworld")
	_world_key.max_length = 128
	_world_key.text_changed.connect(func(_text):
		if _loading: return
		if _document.is_empty() and not _layout.is_empty():
			_layout.world_key = _world_key.text
			_changed()
		else:
			_world_form_pending = _world_key.text != str(_layout.get("world_key", ""))
			_invalidate_candidate()
			_update_state())
	_world_key.tooltip_text = "新建世界的稳定标识。已有世界不能在普通布局编辑中改名；输入原标识可取消新建输入。"
	_button(creation, "新建草稿", "WorldLayoutNewButton", _request_new)


func _build_space_controls(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_label(row, "连续空间", false)
	_spaces = _option(row, "WorldLayoutSpacePicker")
	_spaces.item_selected.connect(_space_selected)
	_space_name = _line(row, "WorldLayoutSpaceIdInput", "新空间标识")
	_space_name.max_length = 128
	_space_name.text_changed.connect(func(_text):
		if not _loading:
			_space_form_pending = not _space_name.text.is_empty()
			_invalidate_candidate()
			_update_state())
	_button(row, "添加空间", "WorldLayoutAddSpaceButton", _add_space)
	_button(row, "删除所选空间…", "WorldLayoutRemoveSpaceButton", _remove_space)


func _build_placement_controls(parent: Node) -> void:
	var page := VBoxContainer.new()
	page.name = "地图放置"
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)
	_placements = _tree(page, "WorldLayoutPlacementTree", ["放置 ID", "地图", "尺寸 X × Z"], 115)
	_placements.item_selected.connect(_placement_selected)
	_maps = _option(page, "WorldLayoutMapPicker")
	_maps.item_selected.connect(_map_selected)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	for spec in [["id", "放置 ID", "PlacementId"], ["pack_id", "地图所属包", "PlacementPackId"], ["map_number", "地图数字编号", "PlacementMapNumber"], ["pack_version", "包版本（可空）", "PlacementPackVersion"], ["origin_x", "原点 X", "OriginX"], ["origin_y", "原点 Y", "OriginY"], ["origin_z", "原点 Z", "OriginZ"], ["min_x", "本地 X 最小", "MinX"], ["min_z", "本地 Z 最小", "MinZ"], ["max_x", "本地 X 最大", "MaxX"], ["max_z", "本地 Z 最大", "MaxZ"]]:
		_label(grid, spec[1], false)
		var field := _line(grid, "WorldLayout" + spec[2] + "Input", "")
		field.max_length = 19 if spec[0] == "map_number" else 128 if spec[0] in ["id", "pack_id", "pack_version"] else 96
		field.custom_minimum_size.x = 100
		_place_fields[spec[0]] = field
		field.text_changed.connect(func(_text):
			if not _loading:
				_placement_pending = true
				_invalidate_candidate()
				_update_state())
	_label(page, "范围为地图本地米制矩形；各图尺寸可以不同。原点仅做平移，不旋转或缩放。", true)
	var actions := HFlowContainer.new()
	page.add_child(actions)
	_button(actions, "添加 / 更新放置", "WorldLayoutUpsertPlacementButton", _upsert_placement)
	_button(actions, "删除所选放置", "WorldLayoutRemovePlacementButton", _remove_placement)
	_button(actions, "重置表单", "WorldLayoutResetPlacementButton", _reset_placement_form)


func _build_seam_controls(parent: Node) -> void:
	var page := VBoxContainer.new()
	page.name = "接缝"
	page.add_theme_constant_override("separation", 6)
	parent.add_child(page)
	_seams = _tree(page, "WorldLayoutSeamTree", ["接缝 ID", "A 侧", "B 侧"], 115)
	_seams.item_selected.connect(_seam_selected)
	_seam_fields.id = _line(page, "WorldLayoutSeamIdInput", "接缝标识")
	_seam_fields.id.max_length = 128
	_seam_fields.id.text_changed.connect(_seam_input_changed)
	for side in ["a", "b"]:
		var grid := GridContainer.new()
		grid.columns = 2
		page.add_child(grid)
		_label(grid, side.to_upper() + " 侧放置", false)
		var placement := _option(grid, "WorldLayoutSeam" + side.to_upper() + "PlacementPicker")
		placement.item_selected.connect(func(_index): _seam_input_changed(""))
		_seam_fields[side + "_placement"] = placement
		_label(grid, "边界", false)
		var edge := _option(grid, "WorldLayoutSeam" + side.to_upper() + "EdgePicker")
		for value in EDGES:
			edge.add_item(value)
			edge.set_item_metadata(edge.item_count - 1, value)
		edge.select(1 if side == "a" else 0)
		edge.item_selected.connect(func(_index): _seam_input_changed(""))
		_seam_fields[side + "_edge"] = edge
		for endpoint in ["start", "end"]:
			_label(grid, "本地区间" + ("起点" if endpoint == "start" else "终点"), false)
			var field := _line(grid, "WorldLayoutSeam" + side.to_upper() + endpoint.capitalize() + "Input", "米")
			field.max_length = 96
			field.text_changed.connect(_seam_input_changed)
			_seam_fields[side + "_" + endpoint] = field
	_label(page, "x_min / x_max 的区间沿本地 Z；z_min / z_max 沿本地 X。两侧边相向，可只连接一段。", true)
	var actions := HFlowContainer.new()
	page.add_child(actions)
	_button(actions, "添加 / 更新接缝", "WorldLayoutUpsertSeamButton", _upsert_seam)
	_button(actions, "删除所选接缝", "WorldLayoutRemoveSeamButton", _remove_seam)
	_button(actions, "重置表单", "WorldLayoutResetSeamButton", _reset_seam_form)


func _build_address_controls(parent: Node) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	_address = _line(row, "WorldLayoutAddressInput", "资源包:地图编号:x,y,z")
	_button(row, "解析到已应用世界", "WorldLayoutResolveAddressButton", _resolve_address)
	var inverse := HBoxContainer.new()
	parent.add_child(inverse)
	_label(inverse, "空间坐标", false)
	for axis in ["x", "y", "z"]:
		_locate_fields[axis] = _line(inverse, "WorldLayoutSpace" + axis.to_upper() + "Input", axis.to_upper() + "（米）")
	_button(inverse, "查询所属地图", "WorldLayoutLocatePositionButton", _locate_position)
	_address_result = _label(parent, "地址解析使用已应用文档及所选空间；不会传送或移动编辑器镜头。", true)
	_address_result.name = "WorldLayoutAddressResult"


func _label(parent: Node, text: String, wrap: bool) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _line(parent: Node, control_name: String, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.name = control_name
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.max_length = 512
	parent.add_child(field)
	return field


func _option(parent: Node, control_name: String) -> OptionButton:
	var option := OptionButton.new()
	option.name = control_name
	option.fit_to_longest_item = false
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(option)
	return option


func _button(parent: Node, text: String, control_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = control_name
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _tree(parent: Node, control_name: String, titles: Array, height: int) -> Tree:
	var tree := Tree.new()
	tree.name = control_name
	tree.columns = titles.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.custom_minimum_size.y = height
	for index in titles.size(): tree.set_column_title(index, titles[index])
	parent.add_child(tree)
	return tree


func _metadata(option: OptionButton) -> Variant:
	return option.get_item_metadata(option.selected) if option.selected >= 0 else null


func _select_metadata(option: OptionButton, value: Variant) -> void:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func refresh() -> void:
	if tools == null:
		_show({"ok": false, "message": "世界布局服务尚未就绪。"})
		return
	var previous_world: Variant = _metadata(_worlds)
	var listed: Dictionary = tools.list_worlds({})
	_listing_valid = listed.get("ok", false)
	_documents.clear()
	var state: Dictionary = tools.state()
	for document: Dictionary in state.get("documents", []): _documents[str(document.get("document_id", ""))] = document
	_worlds.clear()
	var represented: Dictionary = {}
	if listed.get("ok", false):
		for document: Dictionary in listed.get("documents", []): _documents[str(document.get("document_id", ""))] = document
		for world: Dictionary in listed.get("worlds", []):
			var document_id := str(world.get("document_id", ""))
			_worlds.add_item("%s · %s" % [world.get("pack_id", ""), world.get("world_key", world.get("name", ""))])
			_worlds.set_item_metadata(_worlds.item_count - 1, document_id)
			_worlds.set_item_tooltip(_worlds.item_count - 1, str(world.get("path", "")))
			represented[document_id] = true
	for document: Dictionary in _documents.values():
		if represented.has(document.get("document_id", "")): continue
		_worlds.add_item("%s · %s%s" % [document.get("pack_id", ""), document.get("world_key", "未保存世界"), "（未保存）" if document.get("dirty", false) else "（缓存文档）"])
		_worlds.set_item_metadata(_worlds.item_count - 1, document.get("document_id", ""))
	_select_metadata(_worlds, _document.get("document_id", previous_world))
	if _documents.has(_document.get("document_id", "")):
		var latest: Dictionary = _documents[_document.document_id]
		# Keep the loaded editing baseline. Refresh must not bless a stale local draft.
		for key in ["read_only", "reason_code", "message", "disk_conflict"]:
			if latest.has(key): _document[key] = latest[key]
	_refresh_maps()
	_update_state()
	if not listed.get("ok", false): _show(listed)


func _refresh_maps() -> void:
	if editor._world_address_tools == null: return
	var listed: Dictionary = editor._world_address_tools.list_maps({})
	if not listed.get("ok", false):
		_show(listed)
		return
	var previous_pack: Variant = _metadata(_packs)
	_loading = true
	_packs.clear()
	for pack: Dictionary in listed.get("packs", []):
		_packs.add_item("%s (%s) %s" % [pack.get("name", ""), pack.get("id", ""), pack.get("version", "")])
		_packs.set_item_metadata(_packs.item_count - 1, pack.duplicate(true))
		if previous_pack is Dictionary and pack.get("root", "") == previous_pack.get("root", ""):
			_packs.select(_packs.item_count - 1)
	_maps.clear()
	_maps.add_item("从已登记地图填入身份（可手动填写）")
	_maps.set_item_metadata(0, {})
	for map: Dictionary in listed.get("maps", []):
		if str(map.get("map_number", "")).is_empty(): continue
		var entry := map.duplicate(true)
		for pack: Dictionary in listed.get("packs", []):
			if pack.get("root", "") == map.get("pack_root", ""): entry.pack_version = pack.get("version", "")
		_maps.add_item("%s:%s · %s%s" % [map.get("pack_id", ""), map.get("map_number", ""), map.get("name", ""), "（目录未保存）" if not map.get("persisted", false) else ""])
		_maps.set_item_metadata(_maps.item_count - 1, entry)
		_maps.set_item_tooltip(_maps.item_count - 1, str(map.get("path", "")))
	_loading = false


func _request_load() -> void:
	var document_id: Variant = _metadata(_worlds)
	if not document_id is String or document_id.is_empty():
		_show({"ok": false, "message": "请先选择世界布局。"})
		return
	_request_replace(_load_document.bind(document_id), "载入另一个布局会放弃本窗口尚未应用的草稿及表单输入。已应用的文档编辑仍保留。")


func _load_document(document_id: String) -> void:
	var result: Dictionary = tools.get_layout({"document_id": document_id})
	if result.get("ok", false): _accept_document(result)
	_show(result, "已载入布局；未修改地图。")


func _request_new() -> void:
	# The world-key input is consumed by this action, not discarded.
	if _layout != _base_layout or _forms_pending() or _space_form_pending:
		_ask(_new_draft, "新建草稿会放弃本窗口尚未应用的草稿及表单输入。已应用文档仍保留，可从列表重新载入。")
	else: _new_draft()


func _new_draft() -> void:
	var pack: Variant = _metadata(_packs)
	if not pack is Dictionary or _world_key.text.strip_edges().is_empty():
		_show({"ok": false, "message": "请选择所属资源包并填写世界标识。"})
		return
	_new_context = {"pack_id": pack.get("id", ""), "pack_root": pack.get("root", "")}
	_document = {}
	_layout = {"schema_version": 1, "world_key": _world_key.text.strip_edges(), "units": "meters", "up_axis": "Y", "spaces": [{"id": "main", "placements": [], "seams": []}]}
	_base_layout = {}
	_space_id = "main"
	_placement_id = ""
	_seam_id = ""
	_placement_pending = false
	_seam_pending = false
	_world_form_pending = false
	_space_form_pending = false
	_space_name.clear()
	_changed()
	_rebuild()
	_status.text = "新世界草稿已建立。添加地图放置后先预览，再应用及保存。"


func _accept_document(result: Dictionary) -> void:
	_document = result.get("document", {}).duplicate(true)
	_layout = result.get("layout", {}).duplicate(true)
	_base_layout = _layout.duplicate(true)
	_new_context = {}
	_placement_pending = false
	_seam_pending = false
	_world_form_pending = false
	_space_form_pending = false
	_space_name.clear()
	_candidate = {}
	_diagnostics = result.get("diagnostics", []).duplicate(true)
	if not _document.is_empty(): _documents[str(_document.get("document_id", ""))] = _document.duplicate(true)
	_rebuild()
	refresh()


func _space() -> Dictionary:
	for space: Dictionary in _layout.get("spaces", []):
		if space.get("id", "") == _space_id: return space
	return {}


func _rebuild() -> void:
	_loading = true
	if not _world_form_pending: _world_key.text = str(_layout.get("world_key", _world_key.text))
	_world_key.editable = true
	_spaces.clear()
	for space: Dictionary in _layout.get("spaces", []):
		_spaces.add_item(str(space.get("id", "")))
		_spaces.set_item_metadata(_spaces.item_count - 1, space.get("id", ""))
	_select_metadata(_spaces, _space_id)
	_space_id = str(_metadata(_spaces)) if _metadata(_spaces) != null else ""
	_loading = false
	_rebuild_space()
	_fill_diagnostics()
	_update_state()


func _rebuild_space() -> void:
	_loading = true
	_placements.clear()
	var root_item := _placements.create_item()
	for placement: Dictionary in _space().get("placements", []):
		var item := _placements.create_item(root_item)
		item.set_text(0, str(placement.get("id", "")))
		item.set_text(1, "%s:%s" % [placement.get("pack_id", ""), placement.get("map_number", "")])
		var bounds: Array = placement.get("ownership_xz_m", [])
		if bounds.size() == 4: item.set_text(2, "%s × %s" % [_precise(float(bounds[2]) - float(bounds[0])), _precise(float(bounds[3]) - float(bounds[1]))])
		item.set_metadata(0, placement)
		if placement.get("id", "") == _placement_id: item.select(0)
	_seams.clear()
	root_item = _seams.create_item()
	for seam: Dictionary in _space().get("seams", []):
		var item := _seams.create_item(root_item)
		item.set_text(0, str(seam.get("id", "")))
		for index in 2:
			var side: Dictionary = seam.get("a" if index == 0 else "b", {})
			item.set_text(index + 1, "%s · %s" % [side.get("placement_id", ""), side.get("edge", "")])
		item.set_metadata(0, seam)
		if seam.get("id", "") == _seam_id: item.select(0)
	for side in ["a", "b"]:
		var picker: OptionButton = _seam_fields[side + "_placement"]
		picker.clear()
		for placement: Dictionary in _space().get("placements", []):
			picker.add_item(str(placement.get("id", "")))
			picker.set_item_metadata(picker.item_count - 1, placement.get("id", ""))
	_loading = false
	_reset_placement_form()
	_reset_seam_form()
	_canvas.set_view(_space(), _placement_id, _seam_id)


func _space_selected(index: int) -> void:
	if _loading: return
	var next_id := str(_spaces.get_item_metadata(index))
	if _forms_pending():
		_select_metadata(_spaces, _space_id)
		_ask(_switch_space.bind(next_id), "切换空间会放弃尚未添加 / 更新的表单输入；已写入草稿的内容保留。")
	else:
		_switch_space(next_id)


func _switch_space(value: String) -> void:
	_space_id = value
	_select_metadata(_spaces, value)
	_placement_id = ""
	_seam_id = ""
	_rebuild_space()
	_update_state()


func _add_space() -> void:
	if _layout.is_empty():
		_show({"ok": false, "message": "请先新建或载入世界。"})
		return
	var id := _space_name.text.strip_edges()
	if id.is_empty():
		_show({"ok": false, "message": "请填写新空间标识。"})
		return
	for space: Dictionary in _layout.spaces:
		if space.get("id", "") == id:
			_show({"ok": false, "message": "该空间标识已存在。"})
			return
	if _forms_pending():
		_show({"ok": false, "message": "请先添加 / 更新或重置当前表单，再添加空间。"})
		return
	_layout.spaces.append({"id": id, "placements": [], "seams": []})
	_space_id = id
	_space_name.clear()
	_space_form_pending = false
	_changed()
	_rebuild()


func _remove_space() -> void:
	if _space().is_empty(): return
	var id := _space_id
	_ask(func():
		for index in _layout.spaces.size():
			if _layout.spaces[index].id == id:
				_layout.spaces.remove_at(index)
				break
		_space_id = ""
		_placement_pending = false
		_seam_pending = false
		_changed()
		_rebuild(), "从草稿删除空间 %s 及其全部放置和接缝。应用前不会修改文档或地图。" % id)


func _tree_record(tree: Tree) -> Dictionary:
	if tree.get_selected() == null: return {}
	var value: Variant = tree.get_selected().get_metadata(0)
	return value if value is Dictionary else {}


func _placement_selected() -> void:
	if _loading: return
	var next_id := str(_tree_record(_placements).get("id", ""))
	if _placement_pending:
		_ask(_choose_placement.bind(next_id), "切换放置会放弃此放置表单中尚未添加 / 更新的输入。")
		_select_tree_id(_placements, _placement_id)
	else: _choose_placement(next_id)


func _choose_placement(id: String) -> void:
	_placement_id = id
	_select_tree_id(_placements, id)
	_reset_placement_form()
	_canvas.set_view(_space(), _placement_id, _seam_id)


func _select_tree_id(tree: Tree, id: String) -> void:
	if tree.get_root() == null: return
	var previous := _loading
	_loading = true
	tree.deselect_all()
	for item in tree.get_root().get_children():
		var data: Dictionary = item.get_metadata(0)
		if data.get("id", "") == id: item.select(0)
	_loading = previous


func _select_canvas_placement(id: String) -> void:
	if _placement_pending: _ask(_choose_placement.bind(id), "选择另一放置会放弃尚未添加 / 更新的放置表单输入。")
	else: _choose_placement(id)


func _reset_placement_form() -> void:
	_loading = true
	var record: Dictionary = {}
	for placement: Dictionary in _space().get("placements", []):
		if placement.get("id", "") == _placement_id: record = placement
	for key in ["id", "pack_id", "map_number", "pack_version"]: _place_fields[key].text = str(record.get(key, ""))
	var origin: Array = record.get("origin_m", [0, 0, 0])
	var bounds: Array = record.get("ownership_xz_m", [0, 0, 100, 100])
	for index in 3: _place_fields[["origin_x", "origin_y", "origin_z"][index]].text = _precise(origin[index])
	for index in 4: _place_fields[["min_x", "min_z", "max_x", "max_z"][index]].text = _precise(bounds[index])
	_placement_pending = false
	_loading = false
	_update_state()


func _map_selected(index: int) -> void:
	if _loading: return
	var map: Dictionary = _maps.get_item_metadata(index)
	if map.is_empty(): return
	for key in ["pack_id", "map_number", "pack_version"]: _place_fields[key].text = str(map.get(key, ""))
	_placement_pending = true
	_invalidate_candidate()
	_update_state()


func _number_values(fields: Dictionary, keys: Array) -> Dictionary:
	var values: Array = []
	for key in keys:
		var value: String = fields[key].text.strip_edges()
		var parsed := Address.parse("d:0:" + value + ",0,0")
		if not parsed.get("ok", false):
			return {"ok": false, "reason_code": parsed.get("reason_code", "invalid_coordinate"), "message": "%s：%s" % [key, parsed.get("message", "请输入范围内的有限数值。")]}
		values.append(parsed.position_m[0])
	return {"ok": true, "values": values}


func _precise(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _upsert_placement() -> void:
	var space := _space()
	if space.is_empty():
		_show({"ok": false, "message": "请先创建并选择连续空间。"})
		return
	var origin := _number_values(_place_fields, ["origin_x", "origin_y", "origin_z"])
	var bounds := _number_values(_place_fields, ["min_x", "min_z", "max_x", "max_z"])
	if not origin.ok or not bounds.ok:
		_show(origin if not origin.ok else bounds)
		return
	var id: String = _place_fields.id.text.strip_edges()
	if id.is_empty():
		_show({"ok": false, "message": "请填写放置 ID。"})
		return
	var record := {"id": id, "pack_id": _place_fields.pack_id.text.strip_edges(), "map_number": _place_fields.map_number.text.strip_edges(), "origin_m": origin.values, "ownership_xz_m": bounds.values}
	if not _place_fields.pack_version.text.strip_edges().is_empty(): record.pack_version = _place_fields.pack_version.text.strip_edges()
	_upsert_record(space.placements, record)
	_placement_id = id
	_placement_pending = false
	_changed()
	# Preserve unrelated pending seam inputs; placement selector options refresh after they are committed/reset.
	if _seam_pending:
		_rebuild_placement_tree_only()
	else:
		_rebuild_space()
	_status.text = "放置已写入本地草稿。预览会统一检查身份、范围及重叠。"


func _upsert_record(records: Array, record: Dictionary) -> void:
	for index in records.size():
		if records[index].get("id", "") == record.id:
			records[index] = record
			return
	records.append(record)


func _rebuild_placement_tree_only() -> void:
	# Both forms can be edited independently; do not discard the other tab's pending text.
	var saved := _capture_seam_form()
	var pending := _seam_pending
	_rebuild_space()
	_restore_seam_form(saved)
	_seam_pending = pending
	_update_state()


func _remove_placement() -> void:
	if _placement_id.is_empty(): return
	for seam: Dictionary in _space().get("seams", []):
		if seam.get("a", {}).get("placement_id", "") == _placement_id or seam.get("b", {}).get("placement_id", "") == _placement_id:
			_show({"ok": false, "message": "请先删除关联接缝 %s，再删除放置。" % seam.get("id", "")})
			return
	_remove_record(_space().get("placements", []), _placement_id)
	_placement_id = ""
	_placement_pending = false
	_changed()
	_rebuild_placement_tree_only()


func _remove_record(records: Array, id: String) -> void:
	for index in records.size():
		if records[index].get("id", "") == id:
			records.remove_at(index)
			return


func _seam_input_changed(_text: String) -> void:
	if _loading: return
	_seam_pending = true
	_invalidate_candidate()
	_update_state()


func _seam_selected() -> void:
	if _loading: return
	var id := str(_tree_record(_seams).get("id", ""))
	if _seam_pending:
		_ask(_choose_seam.bind(id), "切换接缝会放弃此接缝表单中尚未添加 / 更新的输入。")
		_select_tree_id(_seams, _seam_id)
	else: _choose_seam(id)


func _choose_seam(id: String) -> void:
	_seam_id = id
	_select_tree_id(_seams, id)
	_reset_seam_form()
	_canvas.set_view(_space(), _placement_id, _seam_id)


func _reset_seam_form() -> void:
	_loading = true
	var record: Dictionary = {}
	for seam: Dictionary in _space().get("seams", []):
		if seam.get("id", "") == _seam_id: record = seam
	_seam_fields.id.text = str(record.get("id", ""))
	for side in ["a", "b"]:
		var value: Dictionary = record.get(side, {})
		_select_placement_option(_seam_fields[side + "_placement"], str(value.get("placement_id", "")))
		_select_metadata(_seam_fields[side + "_edge"], value.get("edge", "x_max" if side == "a" else "x_min"))
		var interval: Array = value.get("interval_m", [0, 100])
		_seam_fields[side + "_start"].text = _precise(interval[0])
		_seam_fields[side + "_end"].text = _precise(interval[1])
	_seam_pending = false
	_loading = false
	_update_state()


func _capture_seam_form() -> Dictionary:
	var saved := {"id": _seam_fields.id.text}
	for side in ["a", "b"]:
		for key in ["placement", "edge"]: saved[side + "_" + key] = _metadata(_seam_fields[side + "_" + key])
		for key in ["start", "end"]: saved[side + "_" + key] = _seam_fields[side + "_" + key].text
	return saved


func _restore_seam_form(saved: Dictionary) -> void:
	_loading = true
	_seam_fields.id.text = saved.id
	for side in ["a", "b"]:
		_select_placement_option(_seam_fields[side + "_placement"], str(saved[side + "_placement"]) if saved[side + "_placement"] != null else "")
		_select_metadata(_seam_fields[side + "_edge"], saved[side + "_edge"])
		for key in ["start", "end"]: _seam_fields[side + "_" + key].text = saved[side + "_" + key]
	_loading = false


func _select_placement_option(picker: OptionButton, id: String) -> void:
	if id.is_empty(): return
	for index in picker.item_count:
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			return
	# A pending side must not silently retarget when its referenced placement is removed.
	picker.add_item(id + "（引用缺失）")
	picker.set_item_metadata(picker.item_count - 1, id)
	picker.select(picker.item_count - 1)


func _upsert_seam() -> void:
	if _space().is_empty(): return
	var id: String = _seam_fields.id.text.strip_edges()
	if id.is_empty():
		_show({"ok": false, "message": "请填写接缝 ID。"})
		return
	var record := {"id": id, "mode": "continuous"}
	for side in ["a", "b"]:
		var interval := _number_values(_seam_fields, [side + "_start", side + "_end"])
		if not interval.ok:
			_show(interval)
			return
		var placement: Variant = _metadata(_seam_fields[side + "_placement"])
		if placement == null:
			_show({"ok": false, "message": "接缝两侧都需要选择地图放置。"})
			return
		record[side] = {"placement_id": placement, "edge": _metadata(_seam_fields[side + "_edge"]), "interval_m": interval.values}
	_upsert_record(_space().seams, record)
	_seam_id = id
	_seam_pending = false
	_changed()
	_rebuild_seams_preserving_placement()
	_status.text = "接缝已写入本地草稿。请预览检查两侧区间和空间位置。"


func _rebuild_seams_preserving_placement() -> void:
	var saved: Dictionary = {}
	for key in _place_fields: saved[key] = _place_fields[key].text
	var pending := _placement_pending
	_rebuild_space()
	if pending:
		_loading = true
		for key in saved: _place_fields[key].text = saved[key]
		_loading = false
		_placement_pending = true
	_update_state()


func _remove_seam() -> void:
	if _seam_id.is_empty(): return
	_remove_record(_space().get("seams", []), _seam_id)
	_seam_id = ""
	_seam_pending = false
	_changed()
	_rebuild_seams_preserving_placement()


func _changed() -> void:
	_invalidate_candidate()
	_diagnostics = []
	_fill_diagnostics()
	_update_state()
	if _canvas != null: _canvas.set_view(_space(), _placement_id, _seam_id)


func _invalidate_candidate() -> void:
	_candidate = {}
	if _apply_button != null: _apply_button.disabled = true


func _forms_pending() -> bool:
	return _placement_pending or _seam_pending


func _uncommitted_inputs() -> bool:
	return _forms_pending() or _world_form_pending or _space_form_pending


func has_local_changes() -> bool:
	return _uncommitted_inputs() or _layout != _base_layout


func _update_state() -> void:
	if _state_label == null: return
	var local := has_local_changes()
	_state_label.text = "未载入布局" if _layout.is_empty() else "%s / %s · %s · %s" % [_document.get("pack_id", _new_context.get("pack_id", "")), _layout.get("world_key", ""), "有未应用草稿" if local else "草稿与文档一致", "文档未保存" if _document.get("dirty", false) else "文档已保存" if not _document.is_empty() else "尚未应用为文档"]
	if _uncommitted_inputs(): _state_label.text += " · 表单输入尚未添加 / 更新到草稿"
	if not _document.is_empty(): _state_label.text += " · 编辑修订 %s" % _document.get("edit_revision", 0)
	if _document.get("read_only", false): _state_label.text += " · 只读：" + str(_document.get("message", _document.get("reason_code", "")))
	if _document.get("disk_conflict", false): _state_label.text += " · 磁盘有变化，请重新读取或解决冲突"
	_state_label.tooltip_text = str(_document.get("path", ""))
	_preview_button.disabled = _layout.is_empty()
	_apply_button.disabled = _candidate.is_empty() or _uncommitted_inputs()
	_save_button.disabled = _document.is_empty() or not _document.get("dirty", false) or _document.get("read_only", false)
	_undo_button.disabled = _document.is_empty() or int(_document.get("undo_count", 0)) == 0 or _document.get("read_only", false)
	_redo_button.disabled = _document.is_empty() or int(_document.get("redo_count", 0)) == 0 or _document.get("read_only", false)
	_reload_button.disabled = _document.is_empty()


func _revision_args(document: Dictionary) -> Dictionary:
	return {"document_id": document.get("document_id", ""), "expected_edit_revision": document.get("edit_revision", 0)}


func _preview() -> bool:
	if _layout.is_empty(): return false
	if _uncommitted_inputs():
		_show({"ok": false, "message": "请先完成新建世界 / 添加空间或对应表单的“添加 / 更新”，也可清空新建输入或重置表单，再预览草稿。"})
		return false
	var args := {"mode": "create" if _document.is_empty() else "update", "layout": _layout.duplicate(true), "expected_edit_revision": _document.get("edit_revision", 0)}
	if _document.is_empty():
		args.merge(_new_context)
		args.world_key = _layout.get("world_key", "")
	else: args.document_id = _document.document_id
	var result: Dictionary = tools.preview_layout(args)
	_candidate = result.duplicate(true) if result.get("ok", false) else {}
	_diagnostics = result.get("diagnostics", []).duplicate(true)
	_fill_diagnostics()
	_update_state()
	_show(result, "布局预览通过，可以应用为一笔文档编辑。该结论仅覆盖布局结构。")
	return result.get("ok", false)


func _apply() -> bool:
	if _candidate.is_empty() or _uncommitted_inputs(): return false
	var result: Dictionary = tools.apply_layout({"candidate_id": _candidate.get("candidate_id", ""), "expected_edit_revision": _candidate.get("base_edit_revision", _document.get("edit_revision", 0))})
	if result.get("ok", false): _accept_document(result)
	else:
		_candidate = {}
		_update_state()
	_show(result, "布局已应用为一笔独立撤销；保存后写入世界配置。")
	return result.get("ok", false)


func _save_document(document: Dictionary) -> Dictionary:
	var args := _revision_args(document)
	args.expected_disk_sha = document.get("disk_sha", "")
	return tools.save_layout(args)


func _save() -> bool:
	if _document.is_empty(): return false
	var result := _save_document(_document)
	if result.get("ok", false):
		# Saving applied data never consumes unapplied local form or draft changes.
		_document = result.get("document", _document).duplicate(true)
		refresh()
	_show(result, "已保存所选世界布局；地图和编号目录未修改。" + (" 本地草稿仍未应用。" if has_local_changes() else ""))
	return result.get("ok", false)


func _request_history(method: String) -> void:
	if _document.is_empty(): return
	_request_replace(_history.bind(method), "执行布局历史会放弃本窗口尚未应用的草稿及表单输入；只改变此布局文档。")


func _history(method: String) -> void:
	var result: Dictionary = tools.call(method, _revision_args(_document))
	if result.get("ok", false): _accept_document(result)
	_show(result, "布局历史已更新；未改变当前地图历史。")


func _request_reload() -> void:
	if _document.is_empty(): return
	_ask(_reload_document, "重新校验并读取所选世界的磁盘配置，放弃此文档已应用但未保存的修改，以及本窗口未应用草稿。地图和编号目录不会修改。")


func _reload_document() -> void:
	var result: Dictionary = tools.discard_layout(_revision_args(_document))
	if result.get("ok", false):
		if result.get("abandoned", false) or not result.has("layout"):
			_clear_local()
			refresh()
		else: _accept_document(result)
	_show(result, "已重新读取布局；未修改地图。")


func _request_discard_draft() -> void:
	if not has_local_changes(): return
	_ask(_discard_draft, "放弃本窗口尚未应用的草稿及表单输入。已应用的文档编辑和磁盘文件保持原状。")


func _discard_draft() -> void:
	if _document.is_empty(): _clear_local()
	else:
		_layout = _base_layout.duplicate(true)
		_placement_pending = false
		_seam_pending = false
		_world_form_pending = false
		_space_form_pending = false
		_space_name.clear()
		_changed()
		_rebuild()


func _clear_local() -> void:
	_document = {}
	_layout = {}
	_base_layout = {}
	_new_context = {}
	_candidate = {}
	_diagnostics = []
	_space_id = ""
	_placement_id = ""
	_seam_id = ""
	_placement_pending = false
	_seam_pending = false
	_world_form_pending = false
	_space_form_pending = false
	_world_key.clear()
	_space_name.clear()
	_rebuild()


func _request_replace(action: Callable, message: String) -> void:
	if has_local_changes(): _ask(action, message)
	else: action.call()


func _ask(action: Callable, message: String) -> void:
	_pending_action = action
	_replace_prompt.dialog_text = message
	_replace_prompt.popup_centered_clamped(Vector2i(620, 180), 0.85)


func _validate_seams() -> void:
	if _document.is_empty():
		_show({"ok": false, "message": "尚未应用为文档，请先预览草稿。"})
		return
	var args := {"document_id": _document.document_id}
	if not _space_id.is_empty(): args.space_id = _space_id
	var result: Dictionary = tools.validate_seams(args)
	_diagnostics = result.get("diagnostics", []).duplicate(true)
	_fill_diagnostics()
	_show(result, "已检查应用文档的接缝。高度场结果见诊断；物理和运行通行尚未验证。")


func _fill_diagnostics() -> void:
	if _diagnostic_tree == null: return
	_diagnostic_tree.clear()
	var root_item := _diagnostic_tree.create_item()
	for diagnostic: Dictionary in _diagnostics:
		var item := _diagnostic_tree.create_item(root_item)
		item.set_text(0, "错误" if diagnostic.get("severity", "error") == "error" else "信息")
		item.set_text(1, "%s · %s" % [diagnostic.get("seam_id", diagnostic.get("space_id", "")), diagnostic.get("message", diagnostic.get("code", ""))])
		item.set_metadata(0, diagnostic)
		item.set_tooltip_text(1, str(diagnostic.get("path", "")))
	_diagnostic_details.text = "共 %s 条诊断。选择一条查看对应范围及两侧坐标；结构通过不表示可通行。" % _diagnostics.size()


func _select_diagnostic() -> void:
	var diagnostic := _tree_record(_diagnostic_tree)
	if diagnostic.is_empty(): return
	var wanted_space := str(diagnostic.get("space_id", _space_id))
	if wanted_space != _space_id and not wanted_space.is_empty():
		if _forms_pending():
			_ask(_show_diagnostic.bind(diagnostic), "定位另一空间会放弃尚未添加 / 更新的表单输入；草稿内容保留。")
			return
	_show_diagnostic(diagnostic)


func _show_diagnostic(diagnostic: Dictionary) -> void:
	var wanted_space := str(diagnostic.get("space_id", _space_id))
	if wanted_space != _space_id and not wanted_space.is_empty(): _switch_space(wanted_space)
	var lines: PackedStringArray = [str(diagnostic.get("message", diagnostic.get("code", "")))]
	for pair in [["local_a_m", "A 侧地图本地"], ["local_b_m", "B 侧地图本地"], ["space_a_m", "A 侧空间位置"], ["space_b_m", "B 侧空间位置"], ["space_position_m", "空间定位"], ["local_segment_a_m", "A 侧本地边段"], ["local_segment_b_m", "B 侧本地边段"], ["delta_m", "位置差"], ["horizontal_error_m", "水平差（米）"]]:
		if diagnostic.has(pair[0]): lines.append(pair[1] + "：" + _precise(diagnostic[pair[0]]))
	if diagnostic.has("placement_ids"): lines.append("两侧放置：" + str(diagnostic.placement_ids))
	_diagnostic_details.text = "\n".join(lines)
	_canvas.set_view(_space(), _placement_id, str(diagnostic.get("seam_id", "")), diagnostic)


func _resolve_address() -> void:
	if _document.is_empty():
		_show({"ok": false, "message": "请先应用布局，再解析到该世界。"})
		return
	var args := {"document_id": _document.document_id, "address": _address.text}
	if not _space_id.is_empty(): args.space_id = _space_id
	var result: Dictionary = tools.resolve_address(args)
	_present_address(result)


func _locate_position() -> void:
	if _document.is_empty() or _space_id.is_empty():
		_show({"ok": false, "message": "请先应用布局，并选择连续空间。"})
		return
	var coordinates := _number_values(_locate_fields, ["x", "y", "z"])
	if not coordinates.ok:
		_show(coordinates)
		return
	var result: Dictionary = tools.locate_position({"document_id": _document.document_id, "space_id": _space_id, "space_position_m": coordinates.values})
	_present_address(result)


func _present_address(result: Dictionary) -> void:
	if result.get("ok", false):
		_address_result.text = "%s\n地图本地：%s\n空间 %s / 放置 %s：%s\n只读解析，未验证表面或通行。" % [result.get("canonical", result.get("address", "")), _precise(result.get("local_position_m", result.get("position_m", []))), result.get("space_id", ""), result.get("placement_id", ""), _precise(result.get("space_position_m", []))]
		var issue := {"space_position_m": result.get("space_position_m", []), "placement_ids": [result.get("placement_id", "")]}
		_canvas.set_view(_space(), str(result.get("placement_id", "")), "", issue)
	else: _address_result.text = str(result.get("message", result.get("reason_code", "解析失败")))
	_show(result, "地址已解析到已应用布局。未移动角色或镜头。")


func _show(result: Dictionary, success: String = "") -> void:
	if _status == null: return
	_status.text = success if result.get("ok", false) else "%s%s" % [result.get("message", result.get("error", "操作失败")), (" [" + str(result.reason_code) + "]") if result.has("reason_code") else ""]


func _dirty_documents() -> Array:
	var state: Dictionary = tools.state() if tools != null else {}
	var dirty: Array = []
	for document: Dictionary in state.get("documents", []):
		if document.get("dirty", false): dirty.append(document)
	return dirty


func request_close() -> void:
	var dirty := _dirty_documents()
	if not has_local_changes() and dirty.is_empty():
		hide()
		return
	_close_prompt.dialog_text = "会话有 %s 个未保存布局文档%s。保存或放弃仅针对当前草稿和所选文档；其他文档保留。保存会先预览 / 应用草稿，表单输入需先添加 / 更新。保留编辑只关闭窗口，退出编辑器时仍会提示。" % [dirty.size(), "，以及尚未应用的本地编辑" if has_local_changes() else ""]
	_close_prompt.popup_centered_clamped(Vector2i(690, 220), 0.88)


func _save_before_close() -> void:
	if has_local_changes():
		if not _preview() or not _apply():
			_close_prompt.hide()
			return
	if not _document.is_empty() and _document.get("dirty", false):
		var result := _save_document(_document)
		if not result.get("ok", false):
			_show(result)
			_close_prompt.hide()
			refresh()
			return
	if not _document.is_empty(): _load_document(_document.document_id)
	_close_prompt.hide()
	hide()


func _close_action(action: StringName) -> void:
	if action == "keep":
		_close_prompt.hide()
		hide()
		return
	if action != "discard": return
	if not _document.is_empty() and _document.get("dirty", false):
		var result: Dictionary = tools.discard_layout(_revision_args(_document))
		if not result.get("ok", false):
			_show(result)
			_close_prompt.hide()
			refresh()
			return
	_clear_local()
	refresh()
	_close_prompt.hide()
	hide()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not _replace_prompt.visible and not _close_prompt.visible: request_close()
		get_viewport().set_input_as_handled()
