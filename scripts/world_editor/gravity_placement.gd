extends RefCounted
## Editor-only deterministic placement, not runtime rigid-body simulation.
## Moving props use oriented authored bounds; scene obstacles use physical shapes.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const MASK = 1 << 20
const SKIN = 0.002
var editor: Node3D
var enabled := false
var falling := false
var _records: Array = []
var _before: Array = []
var _originals: Array = []
var _remaining := 0.0
var _velocity := 0.0
var _dirty_before := false
var _added_ids: Array = []
var _next_before := 0
var _selection_before: Array = []

func configure(value: bool) -> void:
	complete()
	enabled = value
	if editor._gravity_toggle != null: editor._gravity_toggle.set_pressed_no_signal(value)

func supported(records: Array) -> bool:
	return not records.is_empty() and records.size() <= 256 and records.all(func(r):
		return r.get("kind") in ["box", "asset"] and editor._record_editable(r) and not ["building", "fixture", "fortification", "terrain_mesh", "road_mesh", "channel_mesh", "rock_bank", "tile3d"].any(func(key): return r.has(key)))

func _excluded(records: Array) -> Array[RID]:
	var result: Array[RID] = []
	for record in records:
		for body in editor._bodies_by_uuid.get(str(record.uuid), []):
			if is_instance_valid(body): result.append(body.get_rid())
	return result

func _query(record: Dictionary, excluded: Array[RID]) -> PhysicsShapeQueryParameters3D:
	var extent := Geometry.vector(record, "size")
	var bounds := AABB(-extent * .5, extent)
	if record.kind == "asset": bounds = AABB(Geometry.vector(record, "bounds_position") * extent, Geometry.vector(record, "bounds_size") * extent)
	var shape := BoxShape3D.new()
	shape.size = (bounds.size - Vector3.ONE * (2 * SKIN)).max(Vector3.ONE * .0001)
	var basis := Basis.from_euler(Geometry.vector(record, "rotation") * PI / 180)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(basis, Geometry.vector(record, "position") + basis * bounds.get_center())
	query.collision_mask = MASK
	query.margin = 0
	query.exclude = excluded
	return query

func clear_pose(records: Array) -> bool:
	var excluded := _excluded(records)
	for record in records:
		if not editor.get_world_3d().direct_space_state.intersect_shape(_query(record, excluded), 1).is_empty(): return false
	return true

func _sweep(query: PhysicsShapeQueryParameters3D, motion: Vector3) -> float:
	# A long cast's safe fraction has coarse absolute precision. Refine only the
	# safe/unsafe interval; otherwise a 1000 m search leaves props visibly floating.
	var origin := query.transform.origin
	var low := 0.0
	var high := 1.0
	for iteration in 10:
		query.transform.origin = origin + motion * low
		query.motion = motion * (high - low)
		var hit := editor.get_world_3d().direct_space_state.cast_motion(query)
		if hit.size() != 2: return -1.0
		if hit[0] >= 1.0: return high
		var span := high - low
		high = low + span * hit[1]
		low += span * hit[0]
		if (high - low) * motion.length() < .0002: break
	return low

func _interpolate(previous: Array, proposed: Array, weight: float) -> Array:
	if weight <= 0: return previous.duplicate(true)
	if weight >= 1: return proposed.duplicate(true)
	var result: Array = previous.duplicate(true)
	var first_center := Vector3.ZERO
	var last_center := Vector3.ZERO
	for i in result.size():
		first_center += Geometry.vector(previous[i], "position")
		last_center += Geometry.vector(proposed[i], "position")
	first_center /= result.size(); last_center /= result.size()
	var first_rotation := Quaternion.from_euler(Geometry.vector(previous[0], "rotation") * PI / 180)
	var last_rotation := Quaternion.from_euler(Geometry.vector(proposed[0], "rotation") * PI / 180)
	var delta := Quaternion.IDENTITY.slerp(last_rotation * first_rotation.inverse(), weight)
	var scale_ := lerpf(1.0, Geometry.vector(proposed[0], "size").x / Geometry.vector(previous[0], "size").x, weight)
	for i in result.size():
		for field in ["position", "size"]:
			var value := Geometry.vector(previous[i], field).lerp(Geometry.vector(proposed[i], field), weight)
			if field == "position" and result.size() > 1:
				value = first_center.lerp(last_center, weight) + delta * ((Geometry.vector(previous[i], field) - first_center) * scale_)
			result[i][field] = [value.x, value.y, value.z]
		var a := Quaternion.from_euler(Geometry.vector(previous[i], "rotation") * PI / 180)
		var b := Quaternion.from_euler(Geometry.vector(proposed[i], "rotation") * PI / 180)
		var angle := a.slerp(b, weight).get_euler() * 180 / PI
		result[i].rotation = [angle.x, angle.y, angle.z]
	return result

func constrain(previous: Array, proposed: Array) -> Array:
	if not enabled: return proposed
	if not supported(previous) or not clear_pose(previous): return previous.duplicate(true)
	var excluded := _excluded(previous)
	var space := editor.get_world_3d().direct_space_state
	var rotate := false
	var angle := 0.0
	for i in previous.size():
		var a := Quaternion.from_euler(Geometry.vector(previous[i], "rotation") * PI / 180)
		var b := Quaternion.from_euler(Geometry.vector(proposed[i], "rotation") * PI / 180)
		angle = maxf(angle, a.angle_to(b))
		if not Geometry.vector(previous[i], "size").is_equal_approx(Geometry.vector(proposed[i], "size")): rotate = true
	rotate = rotate or angle > .00001
	if not rotate:
		var fraction := 1.0
		for i in previous.size():
			var query := _query(previous[i], excluded)
			query.motion = Geometry.vector(proposed[i], "position") - Geometry.vector(previous[i], "position")
			if query.motion.is_zero_approx(): continue
			var motion := query.motion
			var safe := _sweep(query, motion)
			if safe < 0: return previous.duplicate(true)
			if safe < 1: fraction = minf(fraction, maxf(0, safe - SKIN / motion.length()))
		return _interpolate(previous, proposed, fraction)
	# Check the swept convex envelope between small angular steps, including the
	# path of all corners. Endpoint-only overlap misses a thin wall during rotation.
	var steps := clampi(ceili(rad_to_deg(angle)), 1, 180)
	var accepted: Array = previous.duplicate(true)
	for step in steps:
		var next := _interpolate(previous, proposed, float(step + 1) / steps)
		for i in next.size():
			var first := _query(accepted[i], excluded)
			var last := _query(next[i], excluded)
			var points := PackedVector3Array()
			for query in [first, last]:
				var bounds := AABB(-query.shape.size * .5, query.shape.size)
				for corner in 8: points.append(query.transform * bounds.get_endpoint(corner))
			var hull := ConvexPolygonShape3D.new()
			hull.points = points
			first.shape = hull
			first.transform = Transform3D.IDENTITY
			var collisions := space.intersect_shape(first, 1)
			if not collisions.is_empty():
				return accepted
		accepted = next
	return accepted

func landing(records: Array, distance: float = 1000.0) -> Dictionary:
	if not supported(records): return {"ok":false, "error":"重力放置支持普通物件和完整物件组合；地形与生成建筑仍使用专用编辑工具"}
	if not clear_pose(records): return {"ok":false, "error":"物件已与障碍物重叠，请关闭重力放置并移出重叠后重试"}
	var excluded := _excluded(records)
	var amount := distance
	var found := false
	for record in records:
		var query := _query(record, excluded)
		query.motion = Vector3.DOWN * distance
		var fraction := _sweep(query, query.motion)
		if fraction < 0: return {"ok":false,"error":"无法完成落地碰撞检查"}
		if fraction < 1.0:
			found = true
			var basis := query.transform.basis
			var vertical_skin := SKIN * (absf(basis.x.y) + absf(basis.y.y) + absf(basis.z.y))
			amount = minf(amount, maxf(0, distance * fraction - vertical_skin))
	if not found: return {"ok":false, "error":"下方没有承托面，已保留原位置"}
	return {"ok":true, "distance":amount}

func start(records: Array, before: Array, originals: Array = []) -> Dictionary:
	if falling: return {"ok":false,"error":"请等待当前物件落地"}
	var result := landing(records)
	if not result.ok: return result
	_records = records.duplicate()
	_originals = records.duplicate(true) if originals.is_empty() else originals.duplicate(true)
	_before = before
	_remaining = result.distance
	_velocity = 0
	_dirty_before = editor._dirty
	falling = true
	if editor._walk_mode != null: editor._walk_mode.reset_input()
	if editor._camera_navigation != null: editor._camera_navigation.reset()
	editor._status.text = "重力放置中 · Esc 取消"
	return {"ok":true}

func settle_selection() -> Dictionary:
	var selection: Dictionary = editor._placement_tools._selection()
	if not selection.ok: return selection
	return start(selection.records, editor._doc.records.duplicate(true))

func place(entry: Dictionary, point: Vector3) -> Dictionary:
	# Stage and validate outside the live document: failure cannot consume IDs,
	# clear redo, create nodes or add a half-placed object to the undo history.
	var staged = preload("res://scripts/world3d/world_document.gd").new()
	if entry.has("prefab_path"):
		var loaded := preload("res://scripts/world_editor/prefab_library.gd").read(entry)
		if not loaded.ok: return loaded
		if not loaded.building_instances.is_empty(): return {"ok":false,"error":"建筑预制件请关闭重力放置后使用建筑摆放"}
		Geometry.duplicate_records(staged, loaded.records, point, str(entry.get("label", "组合")))
	elif entry.has("asset_path"):
		staged.add_asset(entry, point - Vector3(0, float(entry.get("bounds_position", [0,0,0])[1]), 0))
	else:
		var size_: Vector3 = entry.get("size", Vector3.ONE)
		staged.add_box(str(entry.get("surface_id", "block")), point + Vector3.UP * size_.y * .5, size_, entry.get("rotation", Vector3.ZERO))
	for i in staged.records.size(): staged.records[i].uuid = "gravity_candidate_%d" % i
	var valid := landing(staged.records)
	if not valid.ok: return valid
	var before: Array = editor._doc.records.duplicate(true)
	var next: int = editor._doc._next
	var previous_selection: Array = editor._selection_tools.ids.duplicate()
	var ids := Geometry.duplicate_records(editor._doc, staged.records, Vector3.ZERO)
	editor._commit_records(ids)
	editor._selection_tools.set_ids(ids)
	var result := start(editor._selection_tools.records(), before)
	if not result.ok:
		for id in ids: editor._doc.remove(id)
		editor._doc._next = next
		editor._commit_records(ids)
		editor._selection_tools.set_ids(previous_selection)
		return result
	_added_ids = ids
	_next_before = next
	_selection_before = previous_selection
	return {"ok":true,"ids":ids}

func _move(distance: float) -> void:
	for record in _records: record.position[1] -= distance
	editor._sync_selected_transform(_records)
	editor._inspector.refresh_transform()

func tick(delta: float) -> void:
	if not falling: return
	_velocity += 9.8 * minf(delta, .05)
	var distance := minf(_remaining, _velocity * minf(delta, .05))
	_move(distance)
	_remaining -= distance
	if _remaining <= .00001: complete()

func complete(cancel: bool = false) -> void:
	if not falling: return
	if cancel:
		if not _added_ids.is_empty():
			for id in _added_ids: editor._doc.remove(id)
			editor._doc._next = _next_before
			editor._commit_records(_added_ids)
			_records = []
		else:
			for i in _records.size():
				for field in ["position", "rotation", "size"]: _records[i][field] = _originals[i][field].duplicate()
	else:
		_move(_remaining)
		if _before != editor._doc.records:
			editor._doc.commit_owned_snapshot(_before)
			editor._dirty = true
	falling = false
	_remaining = 0
	if cancel and not _added_ids.is_empty(): editor._selection_tools.set_ids(_selection_before)
	if cancel: editor._dirty = _dirty_before
	editor._sync_selected_transform(_records)
	editor._inspector.refresh(false)
	_records = []; _originals = []; _before = []; _added_ids = []; _selection_before = []
	editor._status.text = "已取消重力放置" if cancel else "已落地 · 可撤销"
