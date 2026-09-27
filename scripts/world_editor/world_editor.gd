extends Node3D
## Places boxes into a WorldDocument and saves that document, not the camera view.

const Document = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Modules = preload("res://scripts/world3d/world_modules.gd")
const Paint = preload("res://scripts/world3d/world_paint.gd")
const Net = preload("res://scripts/net/net.gd")

var _assets = preload("res://scripts/world_editor/asset_library.gd").new()
var _doc = null
var _query := ""
var _pick := 0
var _stroke = Paint.new()
var _view: Node
var _camera: Camera3D
var _status: Label
var _path := ""
var _load_failed := false
var _dirty := false
var _mode := 0
var _inspector: VBoxContainer
var _selection_box: MeshInstance3D
var _grid: MeshInstance3D
var _canvas: SubViewportContainer
var _preview: SubViewportContainer
var _palette: ItemList
var _snap := 0.25
var _rotation_snap := 15.0
var _orbit_center := Vector3.ZERO
var _drag_anchor := Vector3.ZERO
var _drag_origin := Vector3.ZERO
var _drag_active := false
var _drag_changed := false


func _ready() -> void:
	var dir := Paths.cache_directory("editor_yard")
	_path = dir.path_join("map.gltf") if dir != "" else ""
	if Net.session().world3d_editor_path != "":
		_path = Net.session().world3d_editor_path
	var kept = Net.session().world3d_editor_doc
	if kept != null:
		_doc = kept
	elif _path != "" and FileAccess.file_exists(_path):
		_doc = Document.open_file(_path)
		_load_failed = _doc == null
		if _load_failed:
			_doc = Document.new()
	else:
		_doc = Document.new()
		_doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
		Net.session().world3d_editor_doc = _doc
	_add_light()
	_camera = Camera3D.new()
	_camera.current = true
	_camera.position = Vector3(0, 8, 12)
	_camera.rotation_degrees = Vector3(-35, 0, 0)
	add_child(_camera)
	_rebuild()
	_hud()
	if _load_failed:
		_status.text = "地图读取失败或格式不支持；已禁止覆盖保存"


func _input(event: InputEvent) -> void:
	# A release over a dock is consumed by GUI before unhandled_input.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stroke.end()
		_drag_active = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9:
			_pick = key - KEY_1
			_refresh_palette()
		elif key == KEY_Z and event.ctrl_pressed:
			if _doc.undo():
				_dirty = true
				_rebuild()
				_inspector.select(_inspector.selection)
		elif key == KEY_DELETE and not _inspector.selection.is_empty():
			_doc.checkpoint()
			_doc.remove(_inspector.selection)
			_dirty = true
			_rebuild()
			_inspector.select("")
		elif key == KEY_S and event.ctrl_pressed:
			_save()
		elif key == KEY_F5:
			_play()
		elif key == KEY_D and event.ctrl_pressed:
			_duplicate_selected()
		elif key == KEY_F:
			_focus_selected()
		elif key == KEY_Q or key == KEY_E:
			_rotate_selected(-1 if key == KEY_Q else 1)
		elif key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]:
			var direction: Vector3 = {KEY_LEFT: Vector3.LEFT, KEY_RIGHT: Vector3.RIGHT, KEY_UP: Vector3.FORWARD, KEY_DOWN: Vector3.BACK, KEY_PAGEUP: Vector3.UP, KEY_PAGEDOWN: Vector3.DOWN}[key]
			_nudge_selected(direction)
		elif key == KEY_ESCAPE:
			Net.session().editor_return = false
			Net.session().go_login()
		_status.text = _hint()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_stroke.end()
			_drag_active = false
		if not _canvas.get_global_rect().has_point(button.position):
			return
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.85 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18
			_camera.position = _orbit_center + (_camera.position - _orbit_center).normalized() * clampf(_camera.position.distance_to(_orbit_center) * factor, 2, 100)
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_place(button.position - _canvas.global_position, true)
			else:
				_stroke.end()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not _canvas.get_global_rect().has_point(motion.position):
			return
		if (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			var pan := (-_camera.global_basis.x * motion.relative.x + _camera.global_basis.y * motion.relative.y) * _camera.position.distance_to(_orbit_center) * 0.0015
			_camera.position += pan
			_orbit_center += pan
		elif (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			var distance := _camera.position.distance_to(_orbit_center)
			_camera.rotation.x = clampf(_camera.rotation.x - motion.relative.y * 0.005, -1.55, -0.05)
			_camera.rotation.y -= motion.relative.x * 0.005
			_camera.position = _orbit_center + _camera.basis.z * distance
		elif (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_place(motion.position - _canvas.global_position, false)


func _selected() -> Dictionary:
	var found: Array = _library_items()
	if found.is_empty():
		return {}
	return found[clampi(_pick, 0, found.size() - 1)]


func _place(screen: Vector2, fresh: bool) -> void:
	if _load_failed:
		return
	var spec := _selected()
	if (_mode == 0 and spec.is_empty()) or _camera == null:
		return
	var origin := _camera.project_ray_origin(screen)
	if _mode == 1 and not fresh:
		if not _drag_active: return
		var point = Plane(Vector3.UP, _drag_origin.y).intersects_ray(origin, _camera.project_ray_normal(screen))
		if point == null: return
		var position := snap_position(_drag_origin + point - _drag_anchor)
		var record: Dictionary = _doc._find(_inspector.selection)
		if record.is_empty(): return
		var current := Vector3(record.position[0], record.position[1], record.position[2])
		if position.is_equal_approx(current): return
		if not _drag_changed:
			_doc.checkpoint()
			_drag_changed = true
		_doc.move(_inspector.selection, position)
		_dirty = true
		_rebuild()
		_inspector.select(_inspector.selection)
		return
	var end := origin + _camera.project_ray_normal(screen) * 80.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		var point = Plane(Vector3.UP, 0).intersects_ray(origin, _camera.project_ray_normal(screen))
		if point == null or _mode == 1:
			return
		hit = {"position": point}
	if _mode == 1:
		if fresh:
			_inspector.select(str(hit.collider.get_meta("uuid", "")))
			var record: Dictionary = _doc._find(_inspector.selection)
			if not record.is_empty():
				_drag_origin = Vector3(record.position[0], record.position[1], record.position[2])
				var point = Plane(Vector3.UP, _drag_origin.y).intersects_ray(origin, _camera.project_ray_normal(screen))
				_drag_active = point != null
				_drag_changed = false
				if point != null: _drag_anchor = point
		return
	hit.position = snap_position(hit.position)
	if _mode >= 2:
		if not fresh:
			return
		_doc.checkpoint()
		var id := ""
		match _mode:
			2: id = _doc.add_npc(hit.position + Vector3(0, 0.8, 0), "npc", "你好")
			3: id = _doc.add_gather(hit.position + Vector3(0, 0.2, 0), "gather")
			4: id = _doc.add_warp(hit.position + Vector3(0, 0.1, 0), "", Vector3(0, 0.9, 4))
		_dirty = true
		_rebuild()
		_inspector.select(id)
		return
	if spec.has("asset_path"):
		if not fresh: return
		var base: Array = spec.get("bounds_position", [0, 0, 0])
		var id: String = _doc.add_asset(spec, hit.position - Vector3(0, float(base[1]), 0))
		_dirty = true
		_rebuild()
		_inspector.select(id)
		return
	var size: Vector3 = spec.get("size", Vector3.ONE)
	if bool(spec.get("paint", false)):
		_stroke.add(_doc, hit.position + Vector3(0, size.y, 0), spec)
	elif fresh:
		var rotation: Vector3 = spec.get("rotation", Vector3.ZERO)
		_doc.add_box(str(spec.get("surface_id", "ground")), hit.position + Vector3(0, size.y * 0.5, 0), size, rotation)
	else:
		return
	_dirty = true
	_rebuild()


func _rebuild() -> void:
	var doomed: Array = []
	for child in get_children():
		if child == _view or str(child.name).ends_with("_body"):
			doomed.append(child)
	for child in doomed:
		remove_child(child)
		child.free()
	_view = null
	_view = _doc.build()
	add_child(_view)
	_add_bodies(_view)
	_refresh_selection()
	if not _load_failed:
		Net.session().world3d_editor_doc = _doc


func _add_bodies(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var visual := node as MeshInstance3D
		var body := StaticBody3D.new()
		body.name = "%s_body" % str(visual.name)
		var asset: Node = visual
		while asset != null and not asset.has_meta("asset_uuid"): asset = asset.get_parent()
		body.set_meta("uuid", str(asset.get_meta("asset_uuid")) if asset != null else str(visual.name))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = visual.get_aabb().size
		shape.shape = box
		shape.position = visual.get_aabb().get_center()
		body.transform = visual.global_transform
		body.add_child(shape)
		add_child(body)
		body.force_update_transform()
	for child in node.get_children():
		_add_bodies(child)


func _save() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	if _load_failed:
		return false
	if _path == "":
		_status.text = "没有工程外的内容目录"
		return false
	Net.session().world3d_editor_doc = _doc
	var err: Error = _doc.save(_path)
	if err == OK:
		_dirty = false
		Net.session().world3d_editor_path = _path
	_status.text = "已保存" if err == OK else ("地图已被其他窗口修改或正在保存，请重新打开或另存为" if err == ERR_BUSY else "保存失败：" + error_string(err))
	return err == OK


func _play() -> void:
	if not _save():
		return
	Net.session().world3d_map_path = _path
	Net.session().world3d_spawn = Vector3(0, 0.9, 4)
	Net.session().editor_return = true
	Net.session().go_world_3d()


func _hud() -> void:
	preload("res://scripts/world_editor/workspace.gd").build(self)


func _file_dialog(save_as: bool) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save_as else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.gltf ; 三维地图"])
	dialog.current_dir = _path.get_base_dir()
	dialog.file_selected.connect(func(path: String):
		if save_as:
			if Paths._confine(Paths.external_root(), path) == "":
				_status.text = "地图必须保存在工程外内容目录"
				return
			_path = path
			_save()
		else:
			_request_open(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(900, 600))


func _request_open(path: String) -> void:
	if not _dirty:
		open_document(path)
		return
	var prompt := ConfirmationDialog.new()
	prompt.dialog_text = "当前地图有未保存修改。"
	prompt.ok_button_text = "保存并打开"
	prompt.add_button("放弃修改并打开", true, "discard")
	prompt.confirmed.connect(func():
		if _save(): open_document(path)
		prompt.queue_free()
	)
	prompt.custom_action.connect(func(_action: String): open_document(path); prompt.queue_free())
	prompt.canceled.connect(prompt.queue_free)
	add_child(prompt)
	prompt.popup_centered()


func open_document(path: String) -> bool:
	var document = Document.open_file(path)
	if document == null:
		_status.text = "无法读取地图，当前文档保持不变"
		return false
	_doc = document
	_path = path
	Net.session().world3d_editor_path = path
	_load_failed = false
	_dirty = false
	_rebuild()
	_inspector.select("")
	_refresh_palette()
	_status.text = "已打开：" + path.get_file() + (" · 素材缺失，请重新关联" if not _doc.missing_assets().is_empty() else "")
	return true


func _on_search(text: String) -> void:
	_query = text
	_pick = 0
	_refresh_palette()
	_status.text = _hint()


func _hint() -> String:
	var spec := _selected()
	var label := str(spec.get("label", "无"))
	var mode := "涂地" if bool(spec.get("paint", false)) else "摆放"
	return "模块库 %d 个 · %s「%s」· 1-9 选择 · Ctrl+Z 撤销整笔 · 保存后再试玩" % [_library_items().size(), mode, label]


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

func snap_position(point: Vector3) -> Vector3:
	# Snap the horizontal plane without changing support height.
	return Vector3(snappedf(point.x, _snap), point.y, snappedf(point.z, _snap)) if _snap > 0 else point


func _refresh_palette() -> void:
	_palette.clear()
	for item in _library_items():
		_palette.add_item(str(item["label"]) + "   ·   " + str(item["category"]))
	if _palette.item_count > 0:
		_pick = clampi(_pick, 0, _palette.item_count - 1)
		_palette.select(_pick)
	if _preview != null: _preview.show_asset(str(_selected().get("asset_path", "")))


func _duplicate_selected() -> void:
	var record: Dictionary = _doc._find(_inspector.selection)
	if record.is_empty(): return
	_doc.checkpoint()
	var copy: Dictionary = record.duplicate(true)
	var id: String = _doc._push(str(copy.kind), str(copy.surface_id), Vector3.ZERO, Vector3.ONE)
	copy.uuid = id
	copy.position[0] += _snap if _snap > 0 else 0.25
	_doc.records[-1] = copy
	_dirty = true
	_rebuild()
	_inspector.select(id)


func _nudge_selected(direction: Vector3) -> void:
	var record: Dictionary = _doc._find(_inspector.selection)
	if record.is_empty(): return
	_doc.checkpoint()
	var step := _snap if _snap > 0 else 0.01
	for axis in 3: record.position[axis] += direction[axis] * step
	_dirty = true
	_rebuild()
	_inspector.select(_inspector.selection)


func _rotate_selected(direction: int) -> void:
	var record: Dictionary = _doc._find(_inspector.selection)
	if record.is_empty(): return
	_doc.checkpoint()
	var step := _rotation_snap if _rotation_snap > 0 else 1.0
	record.rotation[1] = snappedf(float(record.rotation[1]) + direction * step, step)
	_dirty = true
	_rebuild()
	_inspector.select(_inspector.selection)


func _focus_selected() -> void:
	var record: Dictionary = _doc._find(_inspector.selection)
	if record.is_empty(): return
	_orbit_center = Vector3(record.position[0], record.position[1], record.position[2])
	var size := Vector3(record.size[0], record.size[1], record.size[2])
	if record.get("kind") == "asset":
		var dims: Array = record.get("bounds_size", [1, 1, 1])
		var origin: Array = record.get("bounds_position", [0, 0, 0])
		var bounds_size := Vector3(dims[0], dims[1], dims[2])
		var center := (Vector3(origin[0], origin[1], origin[2]) + bounds_size * 0.5) * size
		var basis := Basis.from_euler(Vector3(record.rotation[0], record.rotation[1], record.rotation[2]) * PI / 180)
		_orbit_center += basis * center
		size *= bounds_size
	var extent := maxf(size.x, maxf(size.y, size.z))
	_camera.position = _orbit_center + _camera.basis.z * clampf(extent * 2.5, 3, 80)


func _top_view() -> void:
	var distance := _camera.position.distance_to(_orbit_center)
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	_camera.position = _orbit_center + Vector3.UP * distance


func _add_grid() -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-40, 41):
		lines.surface_add_vertex(Vector3(i, 0.012, -40))
		lines.surface_add_vertex(Vector3(i, 0.012, 40))
		lines.surface_add_vertex(Vector3(-40, 0.012, i))
		lines.surface_add_vertex(Vector3(40, 0.012, i))
	lines.surface_end()
	_grid = MeshInstance3D.new()
	_grid.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3, 0.38, 0.44, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid.material_override = material
	add_child(_grid)


func _refresh_selection() -> void:
	if is_instance_valid(_selection_box):
		_selection_box.free()
	if _inspector == null: return
	var record: Dictionary = _doc._find(_inspector.selection)
	if record.is_empty(): return
	var dimension := Vector3(record.size[0], record.size[1], record.size[2])
	var center := Vector3.ZERO
	if record.get("kind") == "asset":
		var bounds_size: Array = record.get("bounds_size", [1, 1, 1])
		var bounds_position: Array = record.get("bounds_position", [0, 0, 0])
		var extent := Vector3(bounds_size[0], bounds_size[1], bounds_size[2])
		center = (Vector3(bounds_position[0], bounds_position[1], bounds_position[2]) + extent * 0.5) * dimension
		dimension *= extent
	var half := dimension * 0.5 + Vector3.ONE * 0.015
	var corners: Array[Vector3] = []
	for i in 8: corners.append(center + Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 8:
		for bit in [1, 2, 4]:
			if not i & bit:
				lines.surface_add_vertex(corners[i])
				lines.surface_add_vertex(corners[i | bit])
	lines.surface_end()
	_selection_box = MeshInstance3D.new()
	_selection_box.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffd36b")
	material.no_depth_test = true
	_selection_box.material_override = material
	add_child(_selection_box)
	_selection_box.position = Vector3(record.position[0], record.position[1], record.position[2])
	_selection_box.rotation_degrees = Vector3(record.rotation[0], record.rotation[1], record.rotation[2])


func _library_items() -> Array:
	return Modules.search(_query) + _assets.search(_query)

func _import_asset(relink: bool = false) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.glb,*.gltf ; 3D 模型"])
	dialog.file_selected.connect(func(path: String):
		var result: Dictionary = _assets.import_file(path)
		if not result.ok:
			_status.text = result.error
		else:
			if relink:
				var record: Dictionary = _doc._find(_inspector.selection)
				if record.get("kind") == "asset":
					_doc.checkpoint()
					record.merge(result.entry, true)
					_dirty = true
					_rebuild()
			_query = ""
			_refresh_palette()
			var all := _library_items()
			for i in all.size():
				if all[i].get("asset_path") == result.entry.asset_path: _pick = i
			_refresh_palette()
			_status.text = "模型已导入，可摆放：" + str(result.entry.label)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _manage_asset() -> void:
	var entry := _selected()
	if not entry.has("asset_path"):
		_status.text = "请先在素材库选择导入模型"
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "素材名称与分类"
	var fields := VBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = str(entry.label)
	name_edit.placeholder_text = "素材名称"
	fields.add_child(name_edit)
	var category := LineEdit.new()
	category.text = str(entry.category)
	category.placeholder_text = "分类"
	fields.add_child(category)
	dialog.add_child(fields)
	dialog.add_button("从库列表移除", true, "remove")
	dialog.confirmed.connect(func():
		var old := entry.duplicate(true)
		entry.label = name_edit.text.strip_edges()
		entry.category = category.text.strip_edges()
		if entry.label.is_empty(): entry.label = old.label
		if _assets.save() != OK: entry.merge(old, true); _status.text = "素材库保存失败"
		_refresh_palette()
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(_action: String):
		var index: int = _assets.entries.find(entry)
		_assets.entries.erase(entry)
		if _assets.save() != OK: _assets.entries.insert(index, entry); _status.text = "素材库保存失败"
		_refresh_palette()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(360, 180))


func _restore_previous() -> void:
	if not FileAccess.file_exists(_path + ".previous"):
		_status.text = "当前地图没有上次保存的恢复版本"
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "恢复上次保存的地图？当前未保存的修改将被替换，当前磁盘版本会成为新的恢复版本。"
	dialog.confirmed.connect(func():
		var err: Error = preload("res://scripts/world3d/gltf_map_io.gd").restore_previous(_path)
		if err == OK: open_document(_path)
		else: _status.text = "恢复失败：" + error_string(err)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
