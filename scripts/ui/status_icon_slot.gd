extends Control
## One L2/FF14-style status icon: letter face, kind border, CD pie + seconds.

const CdChromeScript = preload("res://scripts/ui/cd_chrome.gd")

const SLOT := 36.0

signal cancel_requested(status_id: String)

## When true, right-click cancels beneficial buff/hot (player bar only).
var cancelable: bool = false

var status_id: String = ""
var _kind: String = "buff"
var _name: String = ""
var _remaining: float = 0.0
var _duration_max: float = 0.0
var _stacks: int = 1

var _face: Label
var _stack_lab: Label
var _chrome: Control
var _border: Panel


func _ready() -> void:
	custom_minimum_size = Vector2(SLOT, SLOT)
	size = Vector2(SLOT, SLOT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_nodes()
	_refresh_visual()


func _ensure_nodes() -> void:
	if _border != null and is_instance_valid(_border):
		return
	_border = Panel.new()
	_border.name = "Border"
	_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border)

	_face = Label.new()
	_face.name = "Face"
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face.add_theme_font_size_override("font_size", 16)
	_face.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_face.add_theme_constant_override("outline_size", 2)
	_face.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)

	_chrome = CdChromeScript.new()
	_chrome.name = "CdChrome"
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_chrome)

	_stack_lab = Label.new()
	_stack_lab.name = "Stacks"
	_stack_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stack_lab.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_stack_lab.add_theme_font_size_override("font_size", 10)
	_stack_lab.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
	_stack_lab.add_theme_constant_override("outline_size", 2)
	_stack_lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_stack_lab.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_stack_lab.offset_left = 2
	_stack_lab.offset_top = 0
	_stack_lab.offset_right = 18
	_stack_lab.offset_bottom = 14
	_stack_lab.visible = false
	add_child(_stack_lab)


func setup(data: Dictionary) -> void:
	_ensure_nodes()
	status_id = str(data.get("id", "")).strip_edges()
	_name = str(data.get("name", status_id)).strip_edges()
	_kind = str(data.get("kind", "buff")).strip_edges().to_lower()
	_remaining = maxf(float(data.get("remaining_sec", 0.0)), 0.0)
	_duration_max = maxf(float(data.get("duration_max", data.get("duration", _remaining))), _remaining)
	if _duration_max <= 0.0:
		_duration_max = maxf(_remaining, 1.0)
	_stacks = maxi(int(data.get("stacks", 1)), 1)
	_refresh_visual()


func tick(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(_remaining - delta, 0.0)
	if _chrome != null and _chrome.has_method("tick_cooldown"):
		_chrome.tick_cooldown(delta)
	else:
		_refresh_chrome()
	_refresh_tooltip()


func remaining() -> float:
	return _remaining


func _kind_color() -> Color:
	match _kind:
		"buff":
			return Color(0.28, 0.82, 0.42, 1.0)
		"hot":
			return Color(0.3, 0.78, 0.95, 1.0)
		"debuff":
			return Color(0.72, 0.38, 0.92, 1.0)
		"dot":
			return Color(0.95, 0.32, 0.28, 1.0)
		_:
			return Color(0.7, 0.72, 0.78, 1.0)


func _refresh_visual() -> void:
	_ensure_nodes()
	var col := _kind_color()
	var sb := StyleBoxFlat.new()
	# L2-ish dark plate + bright rim; FF14-ish saturated kind color.
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	sb.set_border_width_all(2)
	sb.border_color = col
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(1, 1)
	_border.add_theme_stylebox_override("panel", sb)

	var ch := _name
	if ch.is_empty():
		ch = "?"
	_face.text = ch.substr(0, 1)

	_stack_lab.visible = _stacks > 1
	_stack_lab.text = str(_stacks)

	_refresh_chrome()
	_refresh_tooltip()


func _refresh_chrome() -> void:
	if _chrome != null and _chrome.has_method("set_cooldown"):
		_chrome.set_cooldown(_remaining, _duration_max)


func _refresh_tooltip() -> void:
	var kind_cn := _kind
	match _kind:
		"buff":
			kind_cn = "增益"
		"debuff":
			kind_cn = "减益"
		"dot":
			kind_cn = "持续伤害"
		"hot":
			kind_cn = "持续回复"
	tooltip_text = "%s（%s）\n剩余 %.1f / %.1f 秒" % [_name, kind_cn, _remaining, _duration_max]
	if cancelable and (_kind == "buff" or _kind == "hot"):
		tooltip_text += "\n右键取消"


func _gui_input(event: InputEvent) -> void:
	if not cancelable:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if _kind == "buff" or _kind == "hot":
				if status_id.strip_edges() != "":
					cancel_requested.emit(status_id)
				accept_event()
