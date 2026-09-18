extends PanelContainer
## Drag (title strip or anywhere); resize from edges/corners; snap on release.
signal layout_changed

@export var snap_distance: float = 24.0
@export var screen_margin: float = 4.0
@export var drag_strip_height: float = 22.0
@export var drag_anywhere: bool = true
@export var resize_margin: float = 6.0
@export var resizable: bool = true
@export var min_size: Vector2 = Vector2(140, 72)
@export var default_size: Vector2 = Vector2.ZERO
## none | top_left | top_right | top_center | bottom_left | bottom_center | bottom_right
@export var initial_dock: String = "none"

var _dragging: bool = false
var _resizing: bool = false
var _grab: Vector2 = Vector2.ZERO
var _resize_edge: int = 0
var _start_rect: Rect2 = Rect2()
var _anchored_once: bool = false

const EDGE_NONE := 0
const EDGE_L := 1
const EDGE_R := 2
const EDGE_T := 4
const EDGE_B := 8

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	set_process_input(false)
	_make_display_children_pass_mouse(self)
	call_deferred("_convert_to_free_position")

func _is_scripted_slot(c: Control) -> bool:
	## InvSlot / EquipSlot / SkillSlot / HotbarSlot must keep STOP for clicks/drags.
	var scr = c.get_script()
	if scr == null:
		return false
	var path := str(scr.resource_path)
	return (
		path.ends_with("inv_slot.gd")
		or path.ends_with("equip_slot.gd")
		or path.ends_with("skill_slot.gd")
		or path.ends_with("hotbar_slot.gd")
	)


func _make_display_children_pass_mouse(node: Node) -> void:
	for c in node.get_children():
		if not (c is Control):
			_make_display_children_pass_mouse(c)
			continue
		var ctrl := c as Control
		if c is Button or c is LineEdit or c is TextEdit or c is ItemList or c is OptionButton:
			ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		elif _is_scripted_slot(ctrl):
			ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		elif c is Label or c is ProgressBar or c is ColorRect:
			ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		elif c is MarginContainer or c is VBoxContainer or c is HBoxContainer or c is PanelContainer:
			ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_make_display_children_pass_mouse(c)

func _convert_to_free_position() -> void:
	if _anchored_once:
		return
	_anchored_once = true
	var r := get_global_rect()
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	global_position = _snap_px(r.position)
	if default_size != Vector2.ZERO:
		size = default_size
	else:
		size = r.size
	var vp0 := get_viewport_rect().size
	if size.y > vp0.y * 0.85:
		size.y = minf(default_size.y if default_size != Vector2.ZERO else 340.0, vp0.y * 0.7)
	if size.x > vp0.x * 0.85:
		size.x = minf(default_size.x if default_size != Vector2.ZERO else 360.0, vp0.x * 0.7)
	_apply_dock()
	_clamp_on_screen()

func _apply_dock() -> void:
	if initial_dock == "none" or initial_dock.is_empty():
		return
	var vp := get_viewport_rect().size
	var m := screen_margin
	var s := size
	match initial_dock:
		"top_left":
			global_position = _snap_px(Vector2(m, m))
		"top_right":
			global_position = _snap_px(Vector2(vp.x - s.x - m, m))
		"top_center":
			global_position = _snap_px(Vector2((vp.x - s.x) * 0.5, m))
		"bottom_left":
			global_position = _snap_px(Vector2(m, vp.y - s.y - m))
		"bottom_center":
			global_position = _snap_px(Vector2((vp.x - s.x) * 0.5, vp.y - s.y - m))
		"bottom_right":
			global_position = _snap_px(Vector2(vp.x - s.x - m, vp.y - s.y - m))

func _edge_at(local_pos: Vector2) -> int:
	if not resizable:
		return EDGE_NONE
	var e := EDGE_NONE
	var s := size
	var rm := resize_margin
	if local_pos.x <= rm:
		e |= EDGE_L
	elif local_pos.x >= s.x - rm:
		e |= EDGE_R
	if local_pos.y <= rm:
		e |= EDGE_T
	elif local_pos.y >= s.y - rm:
		e |= EDGE_B
	return e

func _cursor_for_edge(edge: int) -> Control.CursorShape:
	match edge:
		EDGE_L, EDGE_R:
			return Control.CURSOR_HSIZE
		EDGE_T, EDGE_B:
			return Control.CURSOR_VSIZE
		EDGE_L | EDGE_T, EDGE_R | EDGE_B:
			return Control.CURSOR_FDIAGSIZE
		EDGE_R | EDGE_T, EDGE_L | EDGE_B:
			return Control.CURSOR_BDIAGSIZE
		_:
			return Control.CURSOR_ARROW

func _canvas_mouse() -> Vector2:
	## CanvasItem space (project viewport), not window pixels — event.global_position
	## mismatches under canvas_items stretch and makes the panel jitter.
	return get_global_mouse_position()


func _snap_px(v: Vector2) -> Vector2:
	return Vector2(round(v.x), round(v.y))


func _begin_pointer_capture() -> void:
	set_process_input(true)
	move_to_front()


func _end_pointer_capture() -> void:
	if not _dragging and not _resizing:
		return
	_dragging = false
	_resizing = false
	_resize_edge = EDGE_NONE
	_clamp_on_screen()
	_snap_to_edges()
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	set_process_input(false)
	layout_changed.emit()


func _is_hud_locked() -> bool:
	var ml := Engine.get_main_loop()
	if ml == null:
		return false
	var r: Window = ml.root
	if r == null:
		return false
	var gs := r.get_node_or_null("GameSettings")
	return gs != null and bool(gs.get("hud_locked"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_end_pointer_capture()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_pointer_capture()


func _gui_input(event: InputEvent) -> void:
	if _is_hud_locked():
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging or _resizing:
			# Follow is handled in _input so we keep tracking after the cursor
			# leaves this panel (fast drag). Only update the hover cursor here.
			accept_event()
			return
		if resizable:
			mouse_default_cursor_shape = _cursor_for_edge(_edge_at(motion.position))
		else:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var edge := _edge_at(mb.position) if resizable else EDGE_NONE
			if edge != EDGE_NONE:
				_resizing = true
				_resize_edge = edge
				_start_rect = Rect2(global_position, size)
				_grab = _canvas_mouse()
				_begin_pointer_capture()
				accept_event()
				return
			if drag_anywhere or mb.position.y <= drag_strip_height:
				_dragging = true
				_grab = _canvas_mouse() - global_position
				_begin_pointer_capture()
				accept_event()
		else:
			if _dragging or _resizing:
				_end_pointer_capture()
				accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging and not _resizing:
		return
	if event is InputEventMouseMotion:
		if _dragging:
			global_position = _snap_px(_canvas_mouse() - _grab)
			_clamp_on_screen()
		elif _resizing and resizable:
			_apply_resize(_canvas_mouse())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_pointer_capture()
		get_viewport().set_input_as_handled()


func _apply_resize(canvas_mouse: Vector2) -> void:
	var delta := canvas_mouse - _grab
	var r := _start_rect
	var mn := min_size
	if _resize_edge & EDGE_L:
		var nx := r.position.x + delta.x
		var nw := r.size.x - delta.x
		if nw < mn.x:
			nx = r.position.x + r.size.x - mn.x
			nw = mn.x
		r.position.x = nx
		r.size.x = nw
	if _resize_edge & EDGE_R:
		r.size.x = maxf(mn.x, r.size.x + delta.x)
	if _resize_edge & EDGE_T:
		var ny := r.position.y + delta.y
		var nh := r.size.y - delta.y
		if nh < mn.y:
			ny = r.position.y + r.size.y - mn.y
			nh = mn.y
		r.position.y = ny
		r.size.y = nh
	if _resize_edge & EDGE_B:
		r.size.y = maxf(mn.y, r.size.y + delta.y)
	global_position = _snap_px(r.position)
	size = _snap_px(r.size)
	_clamp_on_screen()

func _clamp_on_screen() -> void:
	var vp := get_viewport_rect().size
	var s := size
	global_position = _snap_px(Vector2(
		clampf(global_position.x, screen_margin, maxf(screen_margin, vp.x - s.x - screen_margin)),
		clampf(global_position.y, screen_margin, maxf(screen_margin, vp.y - s.y - screen_margin))
	))

func _snap_to_edges() -> void:
	var vp := get_viewport_rect().size
	var p := global_position
	var s := size
	var m := screen_margin
	var d := snap_distance
	if p.x - m <= d:
		p.x = m
	elif (vp.x - m) - (p.x + s.x) <= d:
		p.x = vp.x - s.x - m
	if p.y - m <= d:
		p.y = m
	elif (vp.y - m) - (p.y + s.y) <= d:
		p.y = vp.y - s.y - m
	global_position = _snap_px(p)
