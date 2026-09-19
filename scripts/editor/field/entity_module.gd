extends RefCounted
## Domain module: entity inspector (entity window, change, jump, chest event, replace prompt).

var ctrl
func _init(c):
	ctrl = c

const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")
const TileLabels = preload("res://scripts/editor/domain/tile_labels.gd")

func _open_entity_win() -> void:
	if ctrl._inspector:
		if ctrl._inspector.has_method("bind_pack"):
			ctrl._inspector.bind_pack(ctrl.pack)
		ctrl._inspector.load_cell(ctrl.doc, ctrl._cursor)
	if ctrl.map_field:
		ctrl.map_field.edit_cursor_cell = ctrl._cursor
	ctrl._popup_win(ctrl._entity_win)



func _on_entity_changed() -> void:
	if ctrl.pack:
		ctrl.pack.dirty = true
	if ctrl.map_field:
		ctrl.map_field.edit_cursor_cell = ctrl._cursor
	ctrl._status.text = "已更新实体"



func _on_entity_jump(c: Vector2i) -> void:
	ctrl._cursor = c
	if ctrl.map_field:
		ctrl.map_field.edit_cursor_cell = c
		ctrl.map_field.edit_hover_cell = c
	if ctrl._cam and ctrl.doc:
		ctrl._cam.position = Vector2((float(c.x) + 0.5) * float(ctrl.doc.tile_size), (float(c.y) + 0.5) * float(ctrl.doc.tile_size))
		ctrl._clamp_camera()
		ctrl._sync_scrollbars()
		ctrl._update_edit_observer()
	ctrl._status.text = "实体格 %d,%d" % [c.x, c.y]



func _add_chest_event() -> void:
	if ctrl.doc == null:
		return
	if ctrl.doc.has_method("remove_entity_at"):
		ctrl.doc.remove_entity_at(ctrl._cursor)
	var ev: Dictionary = EventCommands.make_chest(ctrl._cursor)
	ctrl.doc.events.append(ev)
	ctrl.doc.dirty = true
	if ctrl.pack:
		ctrl.pack.dirty = true
	if ctrl.map_field:
		ctrl.map_field.edit_cursor_cell = ctrl._cursor
	if ctrl._inspector:
		ctrl._inspector.load_cell(ctrl.doc, ctrl._cursor)
	_open_entity_win()
	ctrl._status.text = "已在 %d,%d 放宝箱 %s" % [ctrl._cursor.x, ctrl._cursor.y, str(ev.get("id", ""))]



func _replace_prompt() -> void:
	if ctrl.doc == null or ctrl.paint == null:
		return
	var old_id = int(ctrl.paint.tile_id)
	var dlg = ConfirmationDialog.new()
	dlg.title = "替换图块"
	dlg.dialog_text = "把当前层中与图块 %d（%s）同类的格子换成新 id。\n在调色板选好目标图块后确定。" % [old_id, TileLabels.label_of(old_id)]
	dlg.confirmed.connect(func():
		var dirty: Array[Vector2i] = ctrl.paint.replace_id(ctrl.doc, old_id, int(ctrl.paint.tile_id), true)
		ctrl._refresh_dirty(dirty)
		ctrl._status.text = "已替换 %d 格" % dirty.size()
		dlg.queue_free()
	)
	ctrl.add_child(dlg)
	dlg.popup_centered()


