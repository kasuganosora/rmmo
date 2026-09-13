extends Control
## Skill-cell owned cooldown chrome: FF14-style radial wipe + bottom-right seconds.
## Text hides when remaining < 1.0s. Cast progress uses the same pie (no seconds).

var _cd_remaining: float = 0.0
var _cd_total: float = 0.0
var _cast_frac: float = -1.0
var _cd_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_label()
	queue_redraw()


func _ensure_label() -> void:
	if _cd_label != null and is_instance_valid(_cd_label):
		return
	_cd_label = Label.new()
	_cd_label.name = "CdSeconds"
	_cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_cd_label.add_theme_font_size_override("font_size", 10)
	_cd_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_cd_label.add_theme_constant_override("outline_size", 3)
	_cd_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cd_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cd_label.anchor_left = 1.0
	_cd_label.anchor_top = 1.0
	_cd_label.anchor_right = 1.0
	_cd_label.anchor_bottom = 1.0
	_cd_label.offset_left = -30
	_cd_label.offset_top = -14
	_cd_label.offset_right = -2
	_cd_label.offset_bottom = -1
	_cd_label.visible = false
	add_child(_cd_label)


func set_cooldown(remaining: float, total: float) -> void:
	_cd_remaining = maxf(remaining, 0.0)
	_cd_total = maxf(total, 0.0)
	if _cd_total <= 0.0:
		_cd_remaining = 0.0
	_refresh_label()
	queue_redraw()


func clear_cooldown() -> void:
	_cd_remaining = 0.0
	_cd_total = 0.0
	_refresh_label()
	queue_redraw()


func set_cast_progress(frac: float) -> void:
	if frac < 0.0:
		_cast_frac = -1.0
	else:
		_cast_frac = clampf(frac, 0.0, 1.0)
	_refresh_label()
	queue_redraw()


func tick_cooldown(delta: float) -> void:
	if _cd_remaining <= 0.0:
		return
	_cd_remaining = maxf(_cd_remaining - delta, 0.0)
	if _cd_remaining <= 0.0:
		_cd_total = 0.0
	_refresh_label()
	queue_redraw()


func _refresh_label() -> void:
	_ensure_label()
	# Cast mode: no CD seconds (icon pie only). CD text only when remaining >= 1s.
	if _cast_frac >= 0.0:
		_cd_label.visible = false
		_cd_label.text = ""
		return
	if _cd_remaining >= 1.0:
		var shown: float = _cd_remaining
		if shown >= 10.0:
			_cd_label.text = str(int(ceil(shown)))
		else:
			_cd_label.text = "%.1f" % shown
		_cd_label.visible = true
	else:
		_cd_label.text = ""
		_cd_label.visible = false


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	if radius <= 1.0:
		return
	if _cast_frac >= 0.0:
		_draw_pie(center, radius, 1.0 - _cast_frac, Color(0.05, 0.08, 0.14, 0.72))
		return
	if _cd_total > 0.0 and _cd_remaining > 0.0:
		var frac: float = clampf(_cd_remaining / _cd_total, 0.0, 1.0)
		_draw_pie(center, radius, frac, Color(0.02, 0.04, 0.08, 0.78))


func _draw_pie(center: Vector2, radius: float, frac: float, color: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.001:
		return
	if frac >= 0.999:
		draw_circle(center, radius, color)
		return
	var start: float = -PI * 0.5
	var sweep: float = TAU * frac
	var steps: int = maxi(8, int(ceil(36.0 * frac)))
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(center)
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var ang: float = start + sweep * t
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	draw_colored_polygon(pts, color)
