extends ScrollContainer
## Virtual grid. Nodes and texture references exist only for the viewport + one row.
signal item_selected(index: int)
signal visible_entries_changed
const CELL_HEIGHT := 100.0
const CELL_WIDTH := 96.0
var entries: Array = []
var item_count: int:
	get: return entries.size()
var _host: Control
var _pool: Array[Button] = []
var _active := {}
var _placeholder: Texture2D
var _selected := -1
var _columns := 3
var _scheduled := false
var _focused_index := -1
var _syncing := false

func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	focus_mode = Control.FOCUS_ALL
	follow_focus = false # Logical indices, not pooled button instances, own focus.
	tooltip_text = "方向键浏览素材 · Enter 选取 · Home / End 首尾 · Page Up / Down 翻页"
	_host = Control.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_host)
	resized.connect(_schedule)
	visibility_changed.connect(_schedule)
	get_v_scroll_bar().value_changed.connect(func(_value): _schedule())
	focus_entered.connect(func():
		if not _syncing and not entries.is_empty():
			_focus_index(_focused_index if _focused_index >= 0 else maxi(0, _selected))
	)

func set_entries(items: Array, placeholder: Texture2D) -> void:
	entries = items
	_placeholder = placeholder
	_selected = -1
	_focused_index = -1
	scroll_vertical = 0
	_release()
	_schedule()

func select(index: int) -> void:
	_selected = index
	for button in _pool:
		button.set_pressed_no_signal(int(button.get_meta("index", -1)) == index)

func visible_entries() -> Array:
	var result: Array = []
	for index in _active: result.append(entries[index])
	return result

func apply_thumbnail(key: String, texture: Texture2D) -> void:
	for index in _active:
		if preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(entries[index]) == key:
			(_active[index].get_node("Contents/Icon") as TextureRect).texture = texture

func get_item_icon(index: int) -> Texture2D:
	return (_active[index].get_node("Contents/Icon") as TextureRect).texture if _active.has(index) else null

func _release() -> void:
	_active.clear()
	for button in _pool:
		button.hide()
		button.set_meta("index", -1)
		(button.get_node("Contents/Icon") as TextureRect).texture = null

func _schedule() -> void:
	if _scheduled: return
	_scheduled = true
	_sync.call_deferred()

func _make_button() -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.clip_contents = true
	# The grid is one Tab stop; arrows can focus every virtualized item.
	button.focus_mode = Control.FOCUS_CLICK
	button.gui_input.connect(_navigation_input)
	button.focus_entered.connect(func():
		if not _syncing: _focused_index = int(button.get_meta("index", -1))
	)
	button.set_drag_forwarding(func(_position):
		var index := int(button.get_meta("index", -1))
		if index < 0 or index >= entries.size(): return null
		var preview := Label.new()
		preview.text = str(entries[index].get("label", "物件"))
		button.set_drag_preview(preview)
		return {"type": "rmmo_palette", "entry": entries[index]}
	, Callable(), Callable())
	_host.add_child(button)
	var content := VBoxContainer.new()
	content.name = "Contents"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4
	content.offset_right = -4
	content.offset_top = 4
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size.y = 64
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(icon)
	var label := Label.new()
	label.name = "Caption"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)
	button.pressed.connect(func():
		var index := int(button.get_meta("index", -1))
		if index < 0: return
		_focused_index = index
		select(index)
		item_selected.emit(index)
	)
	return button

func _gui_input(event: InputEvent) -> void:
	_navigation_input(event)

func _navigation_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return
	var key: Key = event.keycode
	if key not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: return
	accept_event() # Never let grid navigation move a selected scene object.
	if entries.is_empty(): return
	var index := clampi(_focused_index if _focused_index >= 0 else maxi(0, _selected), 0, entries.size() - 1)
	var page := maxi(1, int(size.y / CELL_HEIGHT)) * _columns
	match key:
		KEY_LEFT: index -= 1
		KEY_RIGHT: index += 1
		KEY_UP: index -= _columns
		KEY_DOWN: index += _columns
		KEY_HOME: index = 0
		KEY_END: index = entries.size() - 1
		KEY_PAGEUP: index -= page
		KEY_PAGEDOWN: index += page
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				select(index)
				item_selected.emit(index)
			return
	_focus_index(clampi(index, 0, entries.size() - 1))

func _focus_index(index: int) -> void:
	if entries.is_empty() or not is_visible_in_tree(): return
	_focused_index = clampi(index, 0, entries.size() - 1)
	var top := floori(float(_focused_index) / _columns) * CELL_HEIGHT
	if top < scroll_vertical: scroll_vertical = int(top)
	elif top + CELL_HEIGHT > scroll_vertical + size.y:
		scroll_vertical = int(top + CELL_HEIGHT - size.y)
	_sync()
	if _active.has(_focused_index): _active[_focused_index].grab_focus()

func _sync() -> void:
	_scheduled = false
	if _host == null: return
	var previous_focus := get_viewport().gui_get_focus_owner()
	var restore_focus := previous_focus == self or (previous_focus != null and _host.is_ancestor_of(previous_focus))
	_syncing = true
	_columns = maxi(1, int((size.x - 16) / CELL_WIDTH))
	_host.custom_minimum_size.y = ceili(float(entries.size()) / _columns) * CELL_HEIGHT
	if not is_visible_in_tree():
		_release()
		_syncing = false
		visible_entries_changed.emit()
		return
	var first := maxi(0, int(scroll_vertical / CELL_HEIGHT) - 1) * _columns
	var end := mini(entries.size(), (ceili((scroll_vertical + size.y) / CELL_HEIGHT) + 1) * _columns)
	var required := maxi(0, end - first)
	# Reuse controls; shrink the pool as the visible area becomes smaller.
	while _pool.size() > required:
		var removed := _pool.pop_back() as Button
		_host.remove_child(removed)
		removed.queue_free() # Navigation may be executing this button's gui_input.
	while _pool.size() < required: _pool.append(_make_button())
	_active.clear()
	var width := maxf(1, (size.x - 16) / _columns)
	for slot in required:
		var index := first + slot
		var button := _pool[slot]
		if int(button.get_meta("index", -1)) != index:
			(button.get_node("Contents/Icon") as TextureRect).texture = _placeholder
		button.set_meta("index", index)
		button.position = Vector2((index % _columns) * width, (index / _columns) * CELL_HEIGHT)
		button.size = Vector2(width - 4, CELL_HEIGHT - 4)
		(button.get_node("Contents/Caption") as Label).text = str(entries[index].get("label", ""))
		button.tooltip_text = str(entries[index].get("label", "")) + " · " + str(entries[index].get("category", ""))
		button.set_pressed_no_signal(index == _selected)
		button.show()
		_active[index] = button
	if restore_focus:
		if _active.has(_focused_index): _active[_focused_index].grab_focus()
		else: grab_focus()
	_syncing = false
	visible_entries_changed.emit()
