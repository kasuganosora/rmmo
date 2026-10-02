extends "res://scripts/ui/hud_draggable.gd"
## Shared game window component. Body builders supply content and callbacks only.
## A single outer frame, an unboxed title, and common spacing are mandatory.
## The content editor does not use this component.
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func cancel_confirmation(panel: Control) -> void:
	var prompt = panel.get_meta("confirmation") if panel.has_meta("confirmation") else null
	if is_instance_valid(prompt):
		prompt.get_parent().remove_child(prompt)
		prompt.queue_free()
	panel.set_meta("confirmation", null)

static func confirm_action(panel: Control, message: String, action_label: String, action: Callable) -> void:
	cancel_confirmation(panel)
	var title: Control = panel.find_child("TitleBar", true, false)
	if title == null: return
	var host := title.get_parent()
	var prompt := VBoxContainer.new()
	prompt.name = "InlineConfirmation"
	prompt.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", L2Style.COL_TITLE)
	prompt.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	prompt.add_child(row)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): cancel_confirmation(panel))
	row.add_child(cancel)
	var confirm := Button.new()
	confirm.name = "ConfirmAction"
	confirm.text = action_label
	L2Style.style_primary_button(confirm)
	confirm.pressed.connect(func(): cancel_confirmation(panel); action.call())
	row.add_child(confirm)
	prompt.add_child(L2Style.hairline())
	host.add_child(prompt)
	host.move_child(prompt, title.get_index() + 1)
	panel.set_meta("confirmation", prompt)
	if not panel.has_meta("confirmation_visibility_hook"):
		panel.set_meta("confirmation_visibility_hook", true)
		panel.visibility_changed.connect(func():
			if not panel.visible: cancel_confirmation(panel)
		)
	cancel.grab_focus()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	super._ready()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if visible: call_deferred("_clamp_on_screen")


func _apply_resize(canvas_mouse: Vector2) -> void:
	# Pointer positions are screen pixels; the window's size is in local units.
	var factor := get_global_transform().get_scale()
	var delta := (canvas_mouse - _grab) / factor
	var extent := _start_rect.size
	var origin := _start_rect.position
	var minimum := min_size.max(get_combined_minimum_size())
	if _resize_edge & EDGE_L:
		extent.x = maxf(minimum.x, _start_rect.size.x - delta.x)
		origin.x += (_start_rect.size.x - extent.x) * factor.x
	if _resize_edge & EDGE_R:
		extent.x = maxf(minimum.x, _start_rect.size.x + delta.x)
	if _resize_edge & EDGE_T:
		extent.y = maxf(minimum.y, _start_rect.size.y - delta.y)
		origin.y += (_start_rect.size.y - extent.y) * factor.y
	if _resize_edge & EDGE_B:
		extent.y = maxf(minimum.y, _start_rect.size.y + delta.y)
	global_position = _snap_px(origin)
	size = _snap_px(extent)
	_clamp_on_screen()


static func apply_chrome(panel: PanelContainer) -> void:
	L2Style.apply_panel(panel)
	if panel.has_method("_clamp_on_screen"):
		panel.drag_anywhere = false
		panel.drag_strip_height = 36
	var marg := panel.get_child(0) as MarginContainer
	if marg != null:
		marg.add_theme_constant_override("margin_left", 7)
		marg.add_theme_constant_override("margin_top", 0)
		marg.add_theme_constant_override("margin_right", 7)
		marg.add_theme_constant_override("margin_bottom", 7)
	var vbox: VBoxContainer = null
	if marg != null and marg.get_child_count() > 0:
		vbox = marg.get_child(0) as VBoxContainer
	if vbox == null:
		return
	vbox.add_theme_constant_override("separation", 4)
	var title_bar := vbox.get_node_or_null("TitleBar") as PanelContainer
	var head: HBoxContainer = null
	if title_bar != null:
		title_bar.add_theme_stylebox_override("panel", L2Style.title_box())
		title_bar.custom_minimum_size.y = L2Style.TITLE_HEIGHT
		head = title_bar.get_child(0) as HBoxContainer if title_bar.get_child_count() > 0 else null
	else:
		for c in vbox.get_children():
			if c is HBoxContainer:
				head = c
				break
		if head != null:
			title_bar = PanelContainer.new()
			title_bar.name = "TitleBar"
			title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title_bar.custom_minimum_size = Vector2(0, L2Style.TITLE_HEIGHT)
			title_bar.add_theme_stylebox_override("panel", L2Style.title_box())
			var idx := head.get_index()
			vbox.remove_child(head)
			title_bar.add_child(head)
			vbox.add_child(title_bar)
			vbox.move_child(title_bar, idx)
	if head != null:
		head.add_theme_constant_override("separation", 4)
		if head.get_child_count() > 0:
			var title := head.get_child(0) as Label
			L2Style.style_title(title)
			if title != null:
				title.clip_text = true
				title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				title.tooltip_text = title.text
		if head.get_child_count() > 1:
			L2Style.style_close(head.get_child(head.get_child_count() - 1) as Button)
		for c in head.get_children():
			if c is Label and str(c.name).find("Gold") >= 0:
				L2Style.style_gold_amount(c)



static func place_dialog(panel: Control, vertical_fraction: float = 0.5) -> void:
	# Center anchors can retain stale offsets and stretch a newly built popup.
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.reset_size()
	var extent := panel.size * panel.get_global_transform().get_scale()
	var viewport := panel.get_viewport_rect().size
	panel.global_position = Vector2(maxf(4, (viewport.x - extent.x) * 0.5), maxf(4, (viewport.y - extent.y) * vertical_fraction))


static func build_body(panel: PanelContainer, title_text: String, close: Callable, title_name: String = "WindowTitle") -> VBoxContainer:
	var margin := MarginContainer.new()
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(body)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(head)
	var title := Label.new()
	title.name = title_name
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close_button := Button.new()
	close_button.pressed.connect(close)
	head.add_child(close_button)
	apply_chrome(panel)
	return body


static func add_tabs(parent: Container, labels: Array, changed: Callable) -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	parent.add_child(tabs)
	for i in labels.size():
		var button := Button.new()
		button.text = labels[i]
		button.custom_minimum_size = Vector2(72, 28)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(changed.bind(i))
		tabs.add_child(button)
	return tabs


static func highlight_tabs(tabs: HBoxContainer, selected: int) -> void:
	for i in tabs.get_child_count(): L2Style.style_tab_button(tabs.get_child(i), i == selected)


static func field(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 30
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 64
	label.add_theme_color_override("font_color", L2Style.COL_MUTED)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if control is SpinBox else Control.SIZE_EXPAND_FILL
	if control is SpinBox: control.custom_minimum_size.x = 120
	row.add_child(control)
	parent.add_child(row)
