extends Control
## Full-screen drop target (enabled only while dragging). Drop item/equipped onto world ground.

signal ground_drop_item(item_id: String)
signal ground_drop_equipped(slot_id: String)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = -20


func set_active(active: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if active:
		var p := get_parent()
		if p != null:
			p.move_child(self, 0)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	var kind := str(d.get("kind", ""))
	if kind == "item":
		return not str(d.get("item_id", "")).strip_edges().is_empty()
	if kind == "equipped":
		return not str(d.get("slot_id", "")).strip_edges().is_empty()
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var kind := str(d.get("kind", ""))
	if kind == "item":
		var iid := str(d.get("item_id", "")).strip_edges()
		if not iid.is_empty():
			ground_drop_item.emit(iid)
	elif kind == "equipped":
		var sid := str(d.get("slot_id", "")).strip_edges()
		if not sid.is_empty():
			ground_drop_equipped.emit(sid)
