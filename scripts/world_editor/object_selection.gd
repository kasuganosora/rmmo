extends Control
## Selection is editor state; grouping/visibility/locking live in undoable records.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
var editor: Node3D
var ids: Array[String] = []
var box_mode := false
var marquee := false
var start := Vector2.ZERO
var end := Vector2.ZERO
var additive := false
var component_edit := false
var whole := false
var last_error := ""
var motion = preload("res://scripts/world_editor/building_motion.gd").new()
var _pivot_valid := false
var _pivot := Vector3.ZERO


func setup(owner: Node3D) -> void:
	editor = owner
	motion.editor = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true


func records() -> Array:
	if ids.is_empty(): return []
	var wanted := {}
	for id in ids: wanted[id] = true
	var found := {}
	for record in editor._doc.records:
		if wanted.has(str(record.uuid)): found[str(record.uuid)] = record
		if found.size() == wanted.size(): break
	var result: Array = []
	for id in ids:
		var record: Dictionary = found.get(id, {})
		if editor._record_editable(record): result.append(record)
	return result


func set_component_edit(enabled: bool) -> void:
	editor._transform_drag.finish()
	var previous := component_edit
	component_edit = enabled
	if not enabled:
		var expanded: Dictionary = motion.expand(ids)
		if not expanded.ok:
			component_edit = previous
			refresh()
			return
	var primary: String = ids.back() if not ids.is_empty() else ""
	set_ids([primary] if enabled and not primary.is_empty() else ids.duplicate())


func set_ids(values: Array) -> void:
	if editor._placement_tools != null: editor._placement_tools.cancel()
	var requested := values.duplicate()
	if not requested.is_empty():
		var expanded: Dictionary = motion.expand(requested,false,true)
		if not expanded.ok: return
		requested = expanded.ids
	var available := {}
	for record in editor._doc.records:
		if editor._record_editable(record): available[str(record.uuid)] = true
	ids.clear()
	var seen := {}
	for value in requested:
		var id := str(value)
		if not seen.has(id) and available.has(id): ids.append(id); seen[id] = true
	refresh()


func refresh(refresh_scene: bool=true) -> void:
	invalidate_pivot()
	var available := {}
	for record in editor._doc.records:
		if editor._record_editable(record): available[str(record.uuid)] = true
	ids = ids.filter(func(id): return available.has(id))
	whole = false
	if not ids.is_empty():
		var expanded: Dictionary = motion.expand(ids,false,true)
		if not expanded.ok: ids.clear()
		else: ids.assign(expanded.ids)
		for record in editor._doc.records:
			if record.has("building") and (not component_edit or record.get("prefab_locked",false)) and ids.has(str(record.uuid)): whole = true; break
	if editor._inspector != null:
		editor._inspector.selection = ids.back() if not ids.is_empty() else ""
		editor._inspector.refresh(refresh_scene)
	if editor._object_list != null: editor._object_list.sync_selection()
	if editor._event_panel != null: editor._event_panel.refresh()
	if editor._space_button != null: editor._update_space_button()


func members(id: String) -> Array[String]:
	var result: Array[String] = []
	var record: Dictionary = editor._doc._find(id)
	if record.is_empty(): return []
	if record.has("building"):
		if component_edit and not record.get("prefab_locked",false): return [id] if editor._record_editable(record) else []
		var expanded: Dictionary = motion.expand([id])
		if expanded.ok: result.assign(expanded.ids)
		return result
	var group := str(record.get("editor_group", ""))
	if group.is_empty():
		if editor._record_editable(record): result.append(id)
		return result
	for member in editor._doc.records:
		if str(member.get("editor_group", "")) != group: continue
		# A locked/hidden part prevents accidental partial movement of a group.
		if not editor._record_editable(member): return []
		result.append(str(member.uuid))
	return result


func choose(id: String, add: bool = false) -> void:
	var picked := members(id)
	if not add:
		set_ids(picked)
		return
	var next := ids.duplicate()
	var remove := not picked.is_empty() and picked.all(func(value): return ids.has(value))
	for value in picked:
		if remove: next.erase(value)
		elif not next.has(value): next.append(value)
	set_ids(next)


func pivot(live_records: Variant = null) -> Vector3:
	if editor._transform_drag.active and editor._transform_drag.mode != 0: return editor._transform_drag.center
	if _pivot_valid: return _pivot
	var selected: Array = records() if live_records == null else live_records
	_pivot = Geometry.vector(selected[0], "position") if selected.size() == 1 else Geometry.bounds(selected).get_center()
	_pivot_valid = true
	return _pivot


func invalidate_pivot() -> void:
	_pivot_valid = false


func begin_box(point: Vector2, add: bool) -> void:
	marquee = true
	start = point
	end = point
	additive = add
	queue_redraw()


func move_box(point: Vector2) -> void:
	end = point.clamp(Vector2.ZERO, size)
	queue_redraw()


func finish_box(cancel: bool = false) -> void:
	if not marquee: return
	marquee = false
	queue_redraw()
	if cancel: return
	if start.distance_to(end) < 4:
		choose(editor._pick_object(end), additive)
		return
	var rectangle := Rect2(start, end - start).abs()
	var next: Array = ids.duplicate() if additive else []
	for record in editor._doc.records:
		if not editor._record_editable(record): continue
		var projected := Rect2()
		var valid := true
		var first := true
		for point in Geometry.corners(record):
			if editor._camera.is_position_behind(point): valid = false; break
			var screen: Vector2 = editor._camera.unproject_position(point)
			if first: projected = Rect2(screen, Vector2.ZERO); first = false
			else: projected = projected.expand(screen)
		if valid and rectangle.encloses(projected):
			for id in members(str(record.uuid)):
				if not next.has(id): next.append(id)
	set_ids(next)


func group() -> void:
	if records().any(func(r):return r.get("prefab_locked",false)):motion.fail("固定建筑预制件不能拆改或重新分组");return
	if whole: motion.fail("生成建筑已按整栋管理；需要组合构件时先解除生成关联"); return
	if editor._load_failed or ids.size() < 2: return
	editor._transform_drag.finish()
	var selected := records()
	var existing := str(selected[0].get("editor_group", ""))
	if not existing.is_empty() and selected.all(func(r): return r.get("editor_group") == existing) and members(ids[0]).size() == ids.size(): return
	editor._doc.checkpoint()
	var group_id := Geometry.new_group_id()
	for record in selected:
		record.editor_group = group_id
		record.editor_group_name = "组合（%d 件）" % selected.size()
	changed()


func ungroup() -> void:
	if records().any(func(r):return r.get("prefab_locked",false)):motion.fail("固定建筑预制件不能拆改或解除分组");return
	if whole: motion.fail("生成建筑保持整栋关联；修改单个组件请开启构件编辑"); return
	if editor._load_failed: return
	var groups := {}
	for record in records():
		if record.has("editor_group"): groups[record.editor_group] = true
	if groups.is_empty(): return
	var affected: Array = editor._doc.records.filter(func(r): return groups.has(r.get("editor_group", "")))
	if not affected.all(editor._record_editable):
		editor._status.text = "请先显示并解锁组合的所有成员"
		return
	editor._doc.checkpoint()
	for record in affected:
		record.erase("editor_group")
		record.erase("editor_group_name")
	changed()


func changed(refresh_scene: bool=true) -> void:
	editor._dirty = true
	if editor._object_list != null: editor._object_list.refresh()
	refresh(refresh_scene)


func remove() -> void:
	if editor._load_failed or ids.is_empty(): return
	var structures:Array=records().filter(func(r):return r.get("prefab_locked",false) and r.has("fortification"))
	if not structures.is_empty():
		var owner:String=structures[0].fortification.id
		if structures.size()!=ids.size() or not structures.all(func(r):return r.fortification.id==owner):motion.fail("请单独选择一组固定城防进行整体删除");return
		var result:Dictionary=editor._fortifications.remove(owner,false)
		if not result.ok:motion.fail(result.error)
		else:set_ids([])
		return
	editor._transform_drag.finish()
	if whole: motion.remove(); return
	editor._doc.checkpoint()
	for id in ids: editor._doc.remove(id)
	preload("res://scripts/world3d/auto_tile_rules.gd").refresh_all(editor._doc.records)
	ids.clear()
	editor._dirty = true
	editor._rebuild()
	refresh()


func duplicate_selected() -> void:
	if editor._load_failed or ids.is_empty(): return
	if records().any(func(r):return r.get("prefab_locked",false) and r.has("fortification")):motion.fail("固定城防不支持复制现有路径身份；请在城防面板新建独立布局");return
	editor._transform_drag.finish()
	if whole: motion.duplicate_selected(); return
	editor._doc.checkpoint()
	var step: float = editor._snap if editor._snap > 0 else 0.25
	var added := Geometry.duplicate_records(editor._doc, records(), Vector3(step, 0, 0))
	editor._dirty = true
	editor._rebuild()
	set_ids(added)


func transform_numeric(field: String, axis: int, value: float) -> void:
	if editor._load_failed or ids.is_empty(): return
	var origin := pivot()
	var translation := Vector3.ZERO
	var rotation := Basis.IDENTITY
	var factor := 1.0
	match field:
		"position": translation[axis] = value - origin[axis]
		"rotation": rotation = Basis([Vector3.RIGHT, Vector3.UP, Vector3.BACK][axis], deg_to_rad(value))
		"size": factor = clampf(value, 0.001, 1000.0)
	apply_transform(translation, rotation, factor)


func apply_transform(translation: Vector3, rotation: Basis, factor: float) -> Dictionary:
	if editor._load_failed or ids.is_empty(): return {"ok":false,"error":"请先选择可编辑物件"}
	if records().any(func(r):return r.get("prefab_locked",false) and r.has("fortification")):return {"ok":false,"error":"固定城防结构不可拆改；请使用城防面板的整体删除或城门开合"}
	if not is_equal_approx(factor,1.0) and records().any(func(r):return r.get("prefab_locked",false)):return {"ok":false,"error":"固定预制件不可缩放内部结构"}
	var origin := pivot()
	if whole: return motion.move(translation,rotation,factor,origin)
	if translation.is_zero_approx() and rotation.is_equal_approx(Basis.IDENTITY) and is_equal_approx(factor, 1.0): return {"ok":true,"changed":false}
	editor._doc.checkpoint()
	for record in records():
		var position := origin + rotation * ((Geometry.vector(record, "position") - origin) * factor) + translation
		var angles := (rotation * Basis.from_euler(Geometry.vector(record, "rotation") * PI / 180)).get_euler() * 180 / PI
		var size_ := Geometry.vector(record, "size") * factor
		record.position = [position.x, position.y, position.z]
		record.rotation = [angles.x, angles.y, angles.z] if not rotation.is_equal_approx(Basis.IDENTITY) else record.rotation
		record.size = [size_.x, size_.y, size_.z]
	editor._detach_selected_tile(false)
	editor._sync_selected_transform()
	changed(false)
	return {"ok":true,"changed":true}


func set_properties(targets: Array, properties: Dictionary) -> bool:
	# Shared by list checkboxes/name editing and the MCP adapter.
	if editor._load_failed: return false
	var selected: Array = []
	for id in targets:
		var record: Dictionary = editor._doc._find(str(id))
		if record.is_empty(): return false
		if (properties.has("editor_name") or properties.has("editor_group_name")) and not editor._record_editable(record): return false
		selected.append(record)
	var before: Array = editor._doc.records.duplicate(true)
	for record in selected:
		for property in properties: record[property] = properties[property]
	if before == editor._doc.records: return true
	editor._doc.commit_change(before)
	editor._dirty = true
	editor._rebuild()
	return true


func set_object_transform(id: String, properties: Dictionary) -> bool:
	last_error = "物件不存在、已隐藏、锁定或不在当前楼层"
	var record: Dictionary = editor._doc._find(id)
	if editor._load_failed or not editor._record_editable(record): return false
	if record.get("prefab_locked",false) and (record.has("fortification") or properties.has("size")):
		last_error="固定预制件不可修改结构或单个城防构件";return false
	if record.has("building") and (not component_edit or record.get("prefab_locked",false)):
		last_error = "生成建筑默认按整栋操作；请用 transform_selection，编辑单个组件需先开启 component_edit"
		if record.get("prefab_locked",false):last_error="固定预制件不能修改内部组件；请用 transform_selection 整栋移动或旋转"
		editor._status.text = last_error
		return false
	var changed_ := false
	for field in properties:
		if record[field] != properties[field]: changed_ = true
	if not changed_: return true
	editor._doc.checkpoint()
	for field in properties: record[field] = properties[field].duplicate()
	if ids != [id]: set_ids([id])
	elif editor._placement_tools != null: editor._placement_tools.cancel()
	editor._detach_selected_tile(false)
	editor._dirty = true
	editor._sync_selected_transform()
	refresh(false)
	return true


func _draw() -> void:
	if not marquee: return
	var rectangle := Rect2(start, end - start).abs()
	draw_rect(rectangle, Color(0.3, 0.75, 0.9, 0.12))
	draw_rect(rectangle, Color("79d6e8"), false, 1.5)
