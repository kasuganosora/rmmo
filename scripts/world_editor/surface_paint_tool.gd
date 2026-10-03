extends Control
## Shared face picking and paint transactions for UI and MCP.
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
var editor: Node3D
var library
var active := false
var action := "pick"
var stroke_active := false
var pointer_down := false
var selected := {}
var hovered := {}
var material_id := "builtin:checker"
var options := {"mapping": "planar", "scale": [1.0, 1.0], "rotation": 0.0, "offset": [0.0, 0.0]}
var _before: Array = []
var _was_dirty := false
var _visited := {}
var _last_pointer := Vector2(INF, INF)
var _last_camera := Transform3D()
signal target_changed

func setup(owner: Node3D) -> void:
	editor = owner
	library = preload("res://scripts/world_editor/surface_material_library.gd").new(editor._material_directory)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true

func _visual(id: String) -> Node3D:
	if editor._doc._find(id).is_empty(): return null
	return editor._view.get_node_or_null(NodePath(id)) as Node3D

func resolve(id: String, target: Dictionary) -> Dictionary:
	var root := _visual(id)
	if root == null: return Paint.fail("物件不存在")
	# Resolve by enumerating this object's own nodes; never accept an arbitrary NodePath.
	for node in Paint.meshes(root):
		if str(root.get_path_to(node)) != str(target.get("mesh", "")): continue
		var geo := Paint.geometry(node)
		if not geo.ok: return geo
		var slot := int(target.get("surface", -1))
		var face := int(target.get("face", -1))
		if slot < 0 or slot >= geo.surfaces.size(): return Paint.fail("材质槽不存在")
		var data: Dictionary = geo.surfaces[slot]
		if not data.faces.has(face) or target.get("geometry") != data.signature: return Paint.fail("表面已变化，请重新拾取")
		return {"ok": true, "node": node, "data": data, "face": data.faces[face]}
	return Paint.fail("模型节点不存在，请重新拾取")

func list_faces(id: String, offset: int = 0, limit: int = 50) -> Dictionary:
	var root := _visual(id)
	if root == null: return Paint.fail("物件不存在")
	var rows: Array = []
	var warnings: Array = []
	for node in Paint.meshes(root):
		var geo := Paint.geometry(node)
		if not geo.ok: warnings.append(str(geo.error)); continue
		for slot in geo.surfaces.size():
			var data: Dictionary = geo.surfaces[slot]
			for face in data.faces:
				var target := {"mesh": str(root.get_path_to(node)), "surface": slot, "face": face, "geometry": data.signature}
				var center: Vector3 = node.global_transform * data.faces[face].center
				var normal: Vector3 = (node.global_basis.inverse().transposed() * data.faces[face].normal).normalized()
				var applied: Array = editor._doc._find(id).get("surface_paint", []).filter(func(entry): return Paint.face_key(entry) == Paint.face_key(target))
				rows.append({"target": target, "center": [center.x, center.y, center.z], "normal": [normal.x, normal.y, normal.z], "triangle_count": data.faces[face].triangles.size(), "paint": applied[0] if not applied.is_empty() else {}})
	return {"ok": true, "id": id, "faces": rows.slice(offset, offset + limit), "total": rows.size(), "warnings": warnings}

func pick(screen: Vector2) -> Dictionary:
	if not Rect2(Vector2.ZERO, editor._canvas.size).has_point(screen): return Paint.fail("坐标超出 3D 画布")
	var origin: Vector3 = editor._camera.project_ray_origin(screen)
	var direction: Vector3 = editor._camera.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * editor._camera.far)
	query.hit_back_faces = false
	var hit: Dictionary = editor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return Paint.fail("没有命中可绘制表面")
	var id := str(hit.collider.get_meta("uuid", ""))
	var record: Dictionary = editor._doc._find(id)
	if not editor._record_editable(record) or record.get("kind") not in ["box", "asset", "seat"] or record.get("invisible", false): return Paint.fail("目标隐藏、锁定、不在当前楼层或不是可绘制物件")
	var node: MeshInstance3D = hit.collider.get_meta("visual")
	var geo := Paint.geometry(node)
	if not geo.ok: return geo
	var local_origin := node.global_transform.affine_inverse() * origin
	var local_direction := (node.global_basis.inverse() * direction).normalized()
	var closest := INF
	var target := {}
	for slot in geo.surfaces.size():
		var data: Dictionary = geo.surfaces[slot]
		var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
		for triangle in data.face_for_triangle.size():
			var at: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction, vertices[data.indices[triangle * 3]], vertices[data.indices[triangle * 3 + 1]], vertices[data.indices[triangle * 3 + 2]])
			if at == null: continue
			var distance := local_origin.distance_squared_to(at)
			if distance >= closest: continue
			closest = distance
			target = {"mesh": str(_visual(id).get_path_to(node)), "surface": slot, "face": int(data.face_for_triangle[triangle]), "geometry": data.signature}
	if target.is_empty(): return Paint.fail("没有命中可绘制三角面")
	return {"ok": true, "id": id, "target": target}

func paint(id: String, target: Dictionary, chosen: String, settings: Dictionary = {}) -> Dictionary:
	if editor._load_failed: return Paint.fail("地图只读")
	var record: Dictionary = editor._doc._find(id)
	if record.has("terrain_depth_blend") or record.has("terrain_slope_blend") or record.has("terrain_regions") or record.has("terrain_saturation"): return Paint.fail("此地形使用渐变、区域或底材调色；请先停用这些效果再手刷三角面，或使用地表区域工具")
	if not editor._record_editable(record) or record.get("kind") not in ["box", "asset", "seat"]: return Paint.fail("物件不存在、锁定、隐藏或不在当前楼层")
	var resolved := resolve(id, target)
	if not resolved.ok: return resolved
	var material: Dictionary = library.find(chosen)
	if material.is_empty(): return Paint.fail("材质不存在，请先导入或查询材质库")
	var entry := target.duplicate(true)
	entry.merge({"material": material, "mapping": settings.get("mapping", "planar"), "scale": settings.get("scale", [1, 1]), "rotation": settings.get("rotation", 0), "offset": settings.get("offset", [0, 0])})
	for previous in record.get("surface_paint", []):
		if previous == entry: return {"ok": true, "changed_ids": []}
	var next := record.duplicate(true)
	var entries: Array = next.get("surface_paint", []).filter(func(old): return Paint.face_key(old) != Paint.face_key(target))
	entries.append(entry)
	next.surface_paint = entries
	if not Paint.valid(next): return Paint.fail("材质参数无效或超过 128 个已绘制面")
	var mesh_entries := entries.filter(func(old): return old.mesh == target.mesh)
	var preview := Paint.painted_mesh(resolved.node, mesh_entries)
	if not preview.ok: return preview
	return _commit(id, next)

func clear_paint(id: String, target: Dictionary = {}) -> Dictionary:
	if editor._load_failed: return Paint.fail("地图只读")
	var record: Dictionary = editor._doc._find(id)
	if not editor._record_editable(record): return Paint.fail("物件不存在、锁定、隐藏或不在当前楼层")
	var next := record.duplicate(true)
	if target.is_empty(): next.erase("surface_paint")
	else:
		var resolved := resolve(id, target)
		if not resolved.ok: return resolved
		next.surface_paint = next.get("surface_paint", []).filter(func(entry): return Paint.face_key(entry) != Paint.face_key(target))
		if next.surface_paint.is_empty(): next.erase("surface_paint")
	return _commit(id, next)

func _commit(id: String, next: Dictionary) -> Dictionary:
	var record: Dictionary = editor._doc._find(id)
	if record == next: return {"ok": true, "changed_ids": []}
	# A brush stroke already owns one complete before-image. Copying the whole
	# town for each painted component makes large architectural sets quadratic.
	var before: Array = [] if stroke_active else editor._doc.records.duplicate(true)
	var detached := Rules.attached(next)
	Rules.detach(next)
	record.clear(); record.merge(next)
	var changed: Array[String] = []
	if detached: changed.assign(Rules.refresh_all(editor._doc.records))
	if not changed.has(id): changed.append(id)
	editor._refresh_records(changed)
	if not stroke_active: editor._doc.commit_change(before)
	editor._dirty = true
	editor._selection_tools.refresh()
	return {"ok": true, "changed_ids": changed, "detached_auto_tile": detached}

func begin(mode: String) -> void:
	editor._finish_edits()
	if editor._load_failed: report(Paint.fail("地图只读")); return
	action = mode
	active = true
	_last_pointer = Vector2(INF, INF)
	editor._dock_tabs.current_tab = 3
	editor._status.text = "点选或拖动刷材质 · Esc 取消 · 右键转视角；自动瓦片绘制后冻结造型" if mode == "paint" else ("点选表面恢复原材质 · Esc 退出" if mode == "restore" else "点选一个表面 · Esc 退出")

func start_stroke() -> void:
	pointer_down = true
	stroke_active = action != "pick"
	_before = editor._doc.records.duplicate(true)
	_was_dirty = editor._dirty
	_visited.clear()

func dab(screen: Vector2) -> void:
	var hit := pick(screen)
	if not hit.ok: report(hit); return
	selected = hit
	target_changed.emit()
	if action == "pick": return
	var key := str(hit.id) + ":" + Paint.face_key(hit.target)
	if _visited.has(key): return
	var result := paint(hit.id, hit.target, material_id, options) if action == "paint" else clear_paint(hit.id, hit.target)
	if result.ok: _visited[key] = true
	report(result)

func finish(cancelled: bool = false) -> void:
	pointer_down = false
	if not stroke_active: return
	stroke_active = false
	if editor._doc.records != _before:
		if cancelled:
			editor._doc.records = _before
			editor._dirty = _was_dirty
			editor._rebuild()
		else: editor._doc.commit_change(_before)
	_before = []
	_visited.clear()

func cancel() -> void:
	finish()
	active = false
	hovered.clear()
	queue_redraw()

func clear_target() -> void:
	selected.clear(); hovered.clear()
	target_changed.emit()

func report(result: Dictionary) -> void:
	editor._status.text = ("表面材质已更新" + (" · 自动瓦片已冻结为独立物件" if result.get("detached_auto_tile", false) else "")) if result.ok else str(result.error)

func _process(_dt: float) -> void:
	if not active: return
	var pointer := get_local_mouse_position()
	if pointer == _last_pointer and _last_camera == editor._camera.global_transform: return
	_last_pointer = pointer; _last_camera = editor._camera.global_transform
	hovered = pick(pointer)
	queue_redraw()

func _draw() -> void:
	if not active: return
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color("eabb6d"), false, 2)
	var hit := hovered if hovered.get("ok", false) else selected
	if not hit.get("ok", false): return
	var resolved := resolve(hit.id, hit.target)
	if not resolved.ok: return
	var node: MeshInstance3D = resolved.node
	var data: Dictionary = resolved.data
	var vertices: PackedVector3Array = data.arrays[Mesh.ARRAY_VERTEX]
	for triangle in resolved.face.triangles.slice(0, 512):
		var points := PackedVector2Array()
		var behind := false
		for corner in 3:
			var position := node.global_transform * vertices[data.indices[triangle * 3 + corner]]
			behind = behind or editor._camera.is_position_behind(position)
			points.append(editor._camera.unproject_position(position))
		if behind: continue
		draw_colored_polygon(points, Color(1, 0.74, 0.3, 0.18))
		points.append(points[0]); draw_polyline(points, Color("ffd38c"), 1.5)
