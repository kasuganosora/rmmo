extends VBoxContainer
## Player/target status strip: buffs (top) + debuffs (bottom), L2 plate + FF14 pie timer.

const SlotScript = preload("res://scripts/ui/status_icon_slot.gd")

@export var icon_size: float = 36.0
@export var max_icons_per_row: int = 12
## Player bar only: right-click beneficial buff/hot to request cancel.
@export var allow_cancel: bool = false

signal cancel_requested(status_id: String)

var _buff_row: HBoxContainer
var _debuff_row: HBoxContainer
var _statuses: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_rows()
	set_process(true)


func _ensure_rows() -> void:
	if _buff_row != null and is_instance_valid(_buff_row):
		return
	_buff_row = HBoxContainer.new()
	_buff_row.name = "BuffRow"
	_buff_row.add_theme_constant_override("separation", 3)
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buff_row)
	_debuff_row = HBoxContainer.new()
	_debuff_row.name = "DebuffRow"
	_debuff_row.add_theme_constant_override("separation", 3)
	_debuff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_debuff_row)


func apply_statuses(statuses: Array) -> void:
	_ensure_rows()
	_statuses = []
	for s in statuses:
		if typeof(s) == TYPE_DICTIONARY:
			_statuses.append((s as Dictionary).duplicate(true))
	_rebuild()


func tick(delta: float) -> void:
	if _buff_row == null:
		return
	for row in [_buff_row, _debuff_row]:
		if row == null:
			continue
		for c in row.get_children():
			if c.has_method("tick"):
				c.tick(delta)
			if c.has_method("remaining") and float(c.remaining()) <= 0.0:
				c.queue_free()


func _is_debuff_kind(kind: String) -> bool:
	kind = kind.strip_edges().to_lower()
	return kind == "debuff" or kind == "dot"


func _rebuild() -> void:
	_ensure_rows()
	for c in _buff_row.get_children():
		c.queue_free()
	for c in _debuff_row.get_children():
		c.queue_free()
	var buff_n := 0
	var debuff_n := 0
	for s in _statuses:
		var d: Dictionary = s
		var kind := str(d.get("kind", "buff"))
		var slot = SlotScript.new()
		slot.custom_minimum_size = Vector2(icon_size, icon_size)
		if _is_debuff_kind(kind):
			if debuff_n >= max_icons_per_row:
				continue
			_debuff_row.add_child(slot)
			debuff_n += 1
		else:
			if buff_n >= max_icons_per_row:
				continue
			_buff_row.add_child(slot)
			buff_n += 1
		if allow_cancel and not _is_debuff_kind(kind):
			slot.cancelable = true
			if not slot.cancel_requested.is_connected(_on_slot_cancel_requested):
				slot.cancel_requested.connect(_on_slot_cancel_requested)
		else:
			slot.cancelable = false
		slot.setup(d)
	_buff_row.visible = buff_n > 0
	_debuff_row.visible = debuff_n > 0


func _on_slot_cancel_requested(status_id: String) -> void:
	cancel_requested.emit(status_id)
