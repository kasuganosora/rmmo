extends Control
## Placement commands shared by UI and MCP. Plan all changes before one commit.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
var editor: Node3D
var active := false
var align_normal := true
var offset := 0.0
var _hit := {}

func setup(owner: Node3D) -> void:
	editor = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true

func failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func report(result: Dictionary) -> void:
	editor._status.text = "已完成 · %d 件物件" % result.get("changed_ids", []).size() if result.ok else str(result.error)

func _selection() -> Dictionary:
	if editor._selection_tools.whole: return failure("整栋建筑请使用 XYZ 移动或建筑位置参数；暂不支持贴面、落地和自动排列")
	if editor._load_failed: return failure("地图只读，无法修改")
	if editor._transform_drag.active or editor._auto_stroke.active or editor._stroke._open or editor._selection_tools.marquee: return failure("请先结束当前拖动或笔画")
	var selected: Array = editor._selection_tools.records()
	if selected.is_empty() or selected.size() != editor._selection_tools.ids.size(): return failure("请先选择可编辑的物件")
	if selected.size() > 256: return failure("一次最多操作 256 件物件")
	var groups := {}
	for record in selected:
		var group_id := str(record.get("editor_group", ""))
		if not group_id.is_empty(): groups[group_id] = true
	for record in editor._doc.records:
		if groups.has(str(record.get("editor_group", ""))) and not editor._selection_tools.ids.has(str(record.uuid)):
			return failure("摆放与排列需要选择完整组合；请显示、解锁并选中全部成员，或先解组")
	return {"ok": true, "records": selected}

func _units(selected: Array) -> Array:
	var units: Array = []
	var indices := {}
	for record in selected:
		var key := "group:" + str(record.editor_group) if record.has("editor_group") and not str(record.editor_group).is_empty() else "object:" + str(record.uuid)
		if not indices.has(key): indices[key] = units.size(); units.append({"records": [], "order": 0})
		var unit: Dictionary = units[indices[key]]
		unit.records.append(record)
		unit.order = selected.find(record)
	for unit in units: unit.bounds = Geometry.bounds(unit.records)
	# Last selected member defines the fixed reference group for alignment.
	units.sort_custom(func(a, b): return a.order < b.order)
	return units

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var excluded: Array[RID] = []
	for record in editor._doc.records:
		if editor._selection_tools.ids.has(str(record.uuid)) or record.get("kind") not in ["box", "asset"] or bool(record.get("editor_hidden", false)) or bool(record.get("invisible", false)):
			for body in editor._bodies_by_uuid.get(str(record.uuid), []): excluded.append(body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xffffffff, excluded)
	query.hit_back_faces = false
	return editor.get_world_3d().direct_space_state.intersect_ray(query)

func _screen_hit(screen: Vector2) -> Dictionary:
	if not Rect2(Vector2.ZERO, editor._canvas.size).has_point(screen): return {}
	var origin: Vector3 = editor._camera.project_ray_origin(screen)
	return _ray(origin, origin + editor._camera.project_ray_normal(screen) * 10000.0)

func _rotated(records: Array, center: Vector3, normal: Vector3, match_normal: bool) -> Array:
	var result: Array = records.duplicate(true)
	if not match_normal: return result
	var reference: Dictionary = records.back()
	var previous := Basis.from_euler(Geometry.vector(reference, "rotation") * PI / 180)
	var rotation := Basis(Quaternion(previous.y.normalized(), normal))
	if rotation.is_equal_approx(Basis.IDENTITY): return result
	for record in result:
		var position := center + rotation * (Geometry.vector(record, "position") - center)
		var angles := (rotation * Basis.from_euler(Geometry.vector(record, "rotation") * PI / 180)).get_euler() * 180 / PI
		record.position = [position.x, position.y, position.z]
		record.rotation = [angles.x, angles.y, angles.z]
	return result

func _translate(records: Array, delta: Vector3) -> void:
	for record in records:
		var position := Geometry.vector(record, "position") + delta
		record.position = [position.x, position.y, position.z]

func _distance(records: Array, point: Vector3, normal: Vector3) -> float:
	var minimum := INF
	for record in records:
		for corner in Geometry.corners(record): minimum = minf(minimum, (corner - point).dot(normal))
	return minimum

func drop_selection(match_normal: bool = false, distance: float = 100.0, clearance: float = 0.0) -> Dictionary:
	var selected := _selection()
	if not selected.ok: return selected
	if not is_finite(distance) or distance <= 0 or distance > 10000 or not is_finite(clearance) or clearance < 0 or clearance > 100: return failure("贴地距离或离面距离无效")
	var proposed: Array = []
	for unit in _units(selected.records):
		var bounds: AABB = unit.bounds
		var from := Vector3(bounds.get_center().x, bounds.position.y + 0.02, bounds.get_center().z)
		var hit := _ray(from, from - Vector3.UP * (distance + 0.02))
		if hit.is_empty() or hit.normal.y < 0.1: return failure("物件底部中心下方没有可用表面，未修改任何物件")
		var normal: Vector3 = hit.normal.normalized()
		var next := _rotated(unit.records, bounds.get_center(), normal, match_normal)
		var delta_y := (clearance - _distance(next, hit.position, normal)) / normal.y
		if absf(delta_y) > distance + 0.02: return failure("贴地移动超过距离限制，未修改任何物件")
		_translate(next, Vector3.UP * delta_y)
		proposed.append_array(next)
	return _commit(proposed)

func snap_to_surface(screen: Vector2, match_normal: bool = true, clearance: float = 0.0) -> Dictionary:
	var selected := _selection()
	if not selected.ok: return selected
	if not screen.is_finite() or not is_finite(clearance) or clearance < 0 or clearance > 100: return failure("表面位置或离面距离无效")
	var hit := _screen_hit(screen)
	if hit.is_empty(): return failure("没有命中可见表面，请点击地面、墙面或模型")
	var normal: Vector3 = hit.normal.normalized()
	var center := Geometry.bounds(selected.records).get_center()
	var proposed := _rotated(selected.records, center, normal, match_normal)
	_translate(proposed, hit.position - center)
	_translate(proposed, normal * (clearance - _distance(proposed, hit.position, normal)))
	return _commit(proposed)

func align_selection(axis: int, anchor: String = "center") -> Dictionary:
	var selected := _selection()
	if not selected.ok: return selected
	if axis not in [0, 1, 2] or anchor not in ["min", "center", "max"]: return failure("对齐轴或边界无效")
	var units := _units(selected.records)
	if units.size() < 2: return failure("对齐至少需要两个独立物件或完整组合")
	var amount: float = {"min": 0.0, "center": 0.5, "max": 1.0}[anchor]
	var reference: AABB = units.back().bounds
	var target := reference.position[axis] + reference.size[axis] * amount
	var proposed: Array = []
	for unit in units:
		var next: Array = unit.records.duplicate(true)
		var delta := Vector3.ZERO
		delta[axis] = target - (unit.bounds.position[axis] + unit.bounds.size[axis] * amount)
		_translate(next, delta)
		proposed.append_array(next)
	return _commit(proposed)

func distribute_selection(axis: int, spacing: String = "gaps") -> Dictionary:
	var selected := _selection()
	if not selected.ok: return selected
	if axis not in [0, 1, 2] or spacing not in ["centers", "gaps"]: return failure("分布轴或间距类型无效")
	var units := _units(selected.records)
	if units.size() < 3: return failure("分布至少需要三个独立物件或完整组合")
	units.sort_custom(func(a, b):
		var ac: float = a.bounds.get_center()[axis]
		var bc: float = b.bounds.get_center()[axis]
		return a.order < b.order if ac == bc else ac < bc
	)
	var first: AABB = units.front().bounds
	var last: AABB = units.back().bounds
	var step := (last.get_center()[axis] - first.get_center()[axis]) / (units.size() - 1)
	var cursor := first.get_center()[axis]
	if spacing == "gaps":
		var total := 0.0
		for unit in units: total += unit.bounds.size[axis]
		step = (last.end[axis] - first.position[axis] - total) / (units.size() - 1)
		if step < -0.00001: return failure("两端之间空间不足，无法等间隙分布")
		cursor = first.position[axis]
	var proposed: Array = []
	for index in units.size():
		var unit: Dictionary = units[index]
		var next: Array = unit.records.duplicate(true)
		var delta := Vector3.ZERO
		if index > 0 and index < units.size() - 1:
			delta[axis] = cursor - (unit.bounds.position[axis] if spacing == "gaps" else unit.bounds.get_center()[axis])
		_translate(next, delta)
		proposed.append_array(next)
		cursor += step + (unit.bounds.size[axis] if spacing == "gaps" else 0.0)
	return _commit(proposed)

func _commit(proposed: Array) -> Dictionary:
	var changed: Array[String] = []
	for next in proposed:
		var original: Dictionary = editor._doc._find(str(next.uuid))
		if not editor._record_editable(original): return failure("选择已变更，未修改任何物件")
		var position := Geometry.vector(next, "position")
		if not position.is_finite() or position.abs()[position.abs().max_axis_index()] > 1000000: return failure("结果超过地图坐标范围")
		if not position.is_equal_approx(Geometry.vector(original, "position")) or not Geometry.vector(next, "rotation").is_equal_approx(Geometry.vector(original, "rotation")): changed.append(str(next.uuid))
	if changed.is_empty(): return {"ok": true, "changed_ids": changed}
	var before: Array = editor._doc.records.duplicate(true)
	for next in proposed:
		if not changed.has(str(next.uuid)): continue
		var original: Dictionary = editor._doc._find(str(next.uuid))
		original.position = next.position.duplicate()
		original.rotation = next.rotation.duplicate()
		Rules.detach(original)
	editor._refresh_records(Rules.refresh_all(editor._doc.records))
	editor._doc.commit_change(before)
	editor._sync_selected_transform()
	editor._selection_tools.changed()
	return {"ok": true, "changed_ids": changed}

func begin_surface(match_normal: bool = true, clearance: float = 0.0) -> void:
	var selected := _selection()
	if not selected.ok: report(selected); return
	editor._set_mode(1)
	align_normal = match_normal
	offset = clearance
	active = true
	_hit.clear()
	editor._status.text = "点选目标表面 · 排除当前选择 · Esc 取消"

func cancel() -> void:
	active = false
	_hit.clear()
	queue_redraw()

func _process(_dt: float) -> void:
	if not active: return
	_hit = _screen_hit(get_local_mouse_position())
	queue_redraw()

func _draw() -> void:
	if not active: return
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color("79d6e8"), false, 2)
	if _hit.is_empty(): return
	var point: Vector2 = editor._camera.unproject_position(_hit.position)
	draw_circle(point, 7, Color("79d6e8"), false, 2)
	draw_line(point - Vector2(12, 0), point + Vector2(12, 0), Color.WHITE, 1)
	draw_line(point - Vector2(0, 12), point + Vector2(0, 12), Color.WHITE, 1)
	var tip: Vector2 = editor._camera.unproject_position(_hit.position + _hit.normal)
	draw_line(point, tip, Color("8cde82"), 2)
