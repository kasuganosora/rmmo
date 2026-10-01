extends VBoxContainer
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
var editor: Node3D
var tree: Tree
var search: LineEdit
var _updating := false
var _items := {}
var _group_items := {}


func setup(owner: Node3D) -> void:
	editor = owner
	name = "物件"
	search = LineEdit.new()
	search.placeholder_text = "搜索场景物件 / 组合"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_value): refresh())
	add_child(search)
	var actions := HFlowContainer.new()
	add_child(actions)
	_button(actions, "成组", editor._selection_tools.group).tooltip_text = "Ctrl+G · 将所选物件组成一组"
	_button(actions, "解组", editor._selection_tools.ungroup).tooltip_text = "Ctrl+Shift+G"
	_button(actions, "存为预制件", editor._save_prefab_dialog)
	var hint := Label.new()
	hint.text = "Shift / Ctrl 多选 · 双击聚焦 · 子项可单独编辑"
	hint.add_theme_font_size_override("font_size", 12)
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(hint)
	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = 3
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.allow_reselect = true
	tree.column_titles_visible = true
	tree.set_column_title(0, "物件 / 组合")
	tree.set_column_title(1, "显示")
	tree.set_column_title(2, "锁定")
	for column in [1, 2]:
		tree.set_column_expand(column, false)
		tree.set_column_custom_minimum_width(column, 42)
	tree.multi_selected.connect(_selected)
	tree.item_edited.connect(_edited)
	tree.item_activated.connect(editor._focus_selected)
	add_child(tree)
	refresh()


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func refresh() -> void:
	if tree == null: return
	_updating = true
	var collapsed := {}
	for group in _group_items: collapsed[group] = _group_items[group].collapsed
	tree.clear()
	_items.clear()
	_group_items.clear()
	var root := tree.create_item()
	var groups := {}
	for record in editor._doc.records:
		var group := str(record.get("editor_group", ""))
		if group.is_empty(): continue
		if not groups.has(group): groups[group] = []
		groups[group].append(record)
	var needle := search.text.strip_edges().to_lower()
	for record in editor._doc.records:
		var group := str(record.get("editor_group", ""))
		if not group.is_empty():
			if _group_items.has(group): continue
			var members: Array = groups[group]
			var label := str(record.get("editor_group_name", "组合"))
			if not needle.is_empty() and not label.to_lower().contains(needle) and not members.any(func(r): return _matches(r, needle)): continue
			var parent := tree.create_item(root)
			_row(parent, members, label, group)
			_group_items[group] = parent
			parent.collapsed = bool(collapsed.get(group, false))
			for member in members:
				var item := tree.create_item(parent)
				_row(item, [member], Geometry.label(member))
				_items[str(member.uuid)] = item
		elif _matches(record, needle):
			var item := tree.create_item(root)
			_row(item, [record], Geometry.label(record))
			_items[str(record.uuid)] = item
	_updating = false
	sync_selection()


func _matches(record: Dictionary, needle: String) -> bool:
	return needle.is_empty() or (Geometry.label(record) + " " + str(record.uuid) + " " + str(record.get("kind", ""))).to_lower().contains(needle)


func _row(item: TreeItem, records: Array, label: String, group: String = "") -> void:
	var ids: Array[String] = []
	for record in records: ids.append(str(record.uuid))
	item.set_metadata(0, {"ids": ids, "group": group})
	item.set_text(0, label)
	item.set_tooltip_text(0, "%s\n%s" % [label, ", ".join(ids)])
	if not records.all(func(r): return editor._authoring.includes(r)):
		item.set_tooltip_text(0,item.get_tooltip_text(0)+"\n包含当前楼层之外的物件，请切换楼层后编辑")
	item.set_editable(0, true)
	for column in [1, 2]:
		item.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
		item.set_editable(column, true)
		item.set_selectable(column, false)
		var key := "editor_hidden" if column == 1 else "editor_locked"
		var count := records.filter(func(r): return bool(r.get(key, false))).size()
		item.set_checked(column, count == 0 if column == 1 else count == records.size())
		item.set_indeterminate(column, count > 0 and count < records.size())
		item.set_tooltip_text(column, "仅编辑时隐藏，游戏中仍显示" if column == 1 else "锁定后不能选择、变换或删除")
	if not records.all(editor._record_editable): item.set_custom_color(0, Color("84909b"))


func sync_selection() -> void:
	if tree == null or _updating: return
	_updating = true
	tree.deselect_all()
	for id in editor._selection_tools.ids:
		if _items.has(id): _items[id].select(0)
	for group in _group_items:
		var item: TreeItem = _group_items[group]
		# Selecting both a parent and its children makes a native child click emit
		# overlapping deselections. Highlight the group without selecting its row.
		if item.get_metadata(0).ids.all(func(id): return editor._selection_tools.ids.has(id)):
			item.set_custom_bg_color(0, Color("334953"))
		else: item.clear_custom_bg_color(0)
	_updating = false


func _selected(item: TreeItem, column: int, selected: bool) -> void:
	if _updating or column != 0: return
	editor._transform_drag.finish()
	var data: Dictionary = item.get_metadata(0)
	if not str(data.group).is_empty() and not data.ids.all(func(id): return editor._record_editable(editor._doc._find(id))): sync_selection.call_deferred(); return
	var next: Array = editor._selection_tools.ids.duplicate()
	# Tree owns Ctrl/Shift and single-selection gestures. Read its completed state
	# deferred, once all native deselection signals have been emitted.
	if selected:
		for id in data.ids:
			if not next.has(id): next.append(id)
	else:
		for id in data.ids: next.erase(id)
	editor._selection_tools.ids.assign(next)
	_sync_from_tree.call_deferred()


func _sync_from_tree() -> void:
	# Keep the Objects tab open when selecting its rows.
	editor._mode = 1
	for index in editor._mode_buttons.size(): editor._mode_buttons[index].set_pressed_no_signal(index == 1)
	editor._update_auto_controls()
	editor._selection_tools.refresh()


func _edited() -> void:
	if _updating or editor._load_failed: return
	var item := tree.get_edited()
	var column := tree.get_edited_column()
	var data: Dictionary = item.get_metadata(0)
	var records: Array = []
	for id in data.ids:
		var record: Dictionary = editor._doc._find(id)
		if not record.is_empty(): records.append(record)
	if records.is_empty(): return
	if column == 0 and not records.all(editor._record_editable): refresh.call_deferred(); return
	editor._transform_drag.finish()
	var properties := {}
	match column:
		0:
			var label := item.get_text(0).strip_edges()
			if label.is_empty(): refresh.call_deferred(); return
			properties["editor_name" if str(data.group).is_empty() else "editor_group_name"] = label
		1: properties.editor_hidden = not item.is_checked(1)
		2: properties.editor_locked = item.is_checked(2)
	# Tree forbids rebuilding its items during a mouse selection event.
	editor._selection_tools.set_properties.call_deferred(data.ids, properties)
