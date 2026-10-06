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

func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	_host = Control.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_host)
	resized.connect(_schedule)
	visibility_changed.connect(_schedule)
	get_v_scroll_bar().value_changed.connect(func(_value): _schedule())

func set_entries(items: Array, placeholder: Texture2D) -> void:
	entries = items
	_placeholder = placeholder
	_selected = -1
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
	button.focus_mode = Control.FOCUS_NONE
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
		select(index)
		item_selected.emit(index)
	)
	return button

func _sync() -> void:
	_scheduled = false
	if _host == null: return
	_columns = maxi(1, int((size.x - 16) / CELL_WIDTH))
	_host.custom_minimum_size.y = ceili(float(entries.size()) / _columns) * CELL_HEIGHT
	if not is_visible_in_tree():
		_release()
		visible_entries_changed.emit()
		return
	var first := maxi(0, int(scroll_vertical / CELL_HEIGHT) - 1) * _columns
	var end := mini(entries.size(), (ceili((scroll_vertical + size.y) / CELL_HEIGHT) + 1) * _columns)
	var required := maxi(0, end - first)
	# Reuse controls; shrink the pool as the visible area becomes smaller.
	while _pool.size() > required:
		var removed := _pool.pop_back() as Button
		removed.free()
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
	visible_entries_changed.emit()
