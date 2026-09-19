extends RefCounted
## Domain module: npc editing (copy/paste, npc kind, combat sync).

var ctrl
func _init(c):
	ctrl = c

func copy_current() -> bool:
	if ctrl.doc == null or not ctrl.doc.has_method("copy_entity_at"):
		return false
	var hit: Dictionary = ctrl.doc.copy_entity_at(ctrl.cell)
	if hit.is_empty():
		if ctrl._info:
			ctrl._info.text = "此格没有实体可复制"
		return false
	ctrl.clip = hit
	if ctrl._info:
		ctrl._info.text = "已复制 %s" % str(hit.get("kind", ""))
	return true



func paste_current() -> bool:
	if ctrl.doc == null or ctrl.clip.is_empty() or not ctrl.doc.has_method("paste_entity_at"):
		return false
	if not ctrl.doc.paste_entity_at(ctrl.clip, ctrl.cell):
		return false
	ctrl.changed.emit()
	ctrl.load_cell(ctrl.doc, ctrl.cell)
	if ctrl._info:
		ctrl._info.text = "已粘贴到 %d,%d" % [ctrl.cell.x, ctrl.cell.y]
	return true



func _npc_kind_id() -> String:
	if ctrl._npc_kind == null or ctrl._npc_kind.selected < 0:
		return "normal"
	return str(ctrl._npc_kind.get_item_metadata(ctrl._npc_kind.selected))



func _select_npc_kind(kind: String) -> void:
	if ctrl._npc_kind == null:
		return
	var key = kind.strip_edges().to_lower()
	if key == "":
		key = "monster" if (ctrl._hostile != null and ctrl._hostile.button_pressed) else "normal"
	for i in range(ctrl._npc_kind.item_count):
		if str(ctrl._npc_kind.get_item_metadata(i)) == key:
			ctrl._npc_kind.select(i)
			_sync_npc_combat()
			return
	ctrl._npc_kind.select(0)
	_sync_npc_combat()



func _on_npc_kind() -> void:
	var id = _npc_kind_id()
	if ctrl._hostile and id == "monster":
		ctrl._hostile.button_pressed = true
	elif ctrl._hostile and id == "normal":
		ctrl._hostile.button_pressed = false
	_sync_npc_combat()



func _sync_npc_combat() -> void:
	if ctrl._aggressive:
		ctrl._aggressive.disabled = ctrl._hostile == null or not ctrl._hostile.button_pressed
		if ctrl._aggressive.disabled:
			ctrl._aggressive.set_pressed_no_signal(false)
	if ctrl._hostile != null and ctrl._hostile.button_pressed and ctrl._npc_kind != null and _npc_kind_id() == "normal":
		_select_npc_kind("monster")


