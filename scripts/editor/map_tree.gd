extends Tree
## Map tree with drag-to-reparent.

signal reparent_requested(map_id: String, new_parent: String)


func _get_drag_data(at_position: Vector2) -> Variant:
	var it := get_item_at_position(at_position)
	if it == null or not it.has_meta("map_id"):
		return null
	var preview := Label.new()
	preview.text = it.get_text(0)
	set_drag_preview(preview)
	return {"map_id": str(it.get_meta("map_id"))}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("map_id"):
		return false
	var it := get_item_at_position(at_position)
	return it != null and it.has_meta("map_id")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var src := str(data.get("map_id", ""))
	var it := get_item_at_position(at_position)
	if it == null or not it.has_meta("map_id") or src == "":
		return
	var parent := str(it.get_meta("map_id"))
	if parent == src:
		return
	reparent_requested.emit(src, parent)
