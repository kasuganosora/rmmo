extends Node3D
## Places boxes into a WorldDocument and saves that document, not the camera view.

const Document = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Modules = preload("res://scripts/world3d/world_modules.gd")
const Paint = preload("res://scripts/world3d/world_paint.gd")
const Net = preload("res://scripts/net/net.gd")
const AutoRules = preload("res://scripts/world3d/auto_tile_rules.gd")
const SelectionGeometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Prefabs = preload("res://scripts/world_editor/prefab_library.gd")

var _assets = preload("res://scripts/world_editor/asset_library.gd").new()
var _asset_pack_root := ""
var _shared_assets: Array = []
var _doc = null
var _query := ""
var _pick := 0
var _stroke = Paint.new()
var _auto_stroke = preload("res://scripts/world_editor/auto_tile_stroke.gd").new()
var _auto_cell_size := 4.0
var _auto_height := 0.0
var _auto_panel: VBoxContainer
var _auto_erase := false
var _auto_toolbar: Control
var _view: Node
var _bodies_by_uuid := {}
var _camera: Camera3D
var _status: Label
var _path := ""
var _load_failed := false
var _dirty := false:
	set(value):
		_dirty = value
		if _doc != null: _doc.editor_dirty = value
var _mode := 0
var _inspector: VBoxContainer
var _selection_box: MeshInstance3D
var _grid: MeshInstance3D
var _canvas: SubViewportContainer
var _preview: SubViewportContainer
var _palette_items: Array = []
var _search_timer: Timer
var _palette: ScrollContainer
var _snap := 0.25
var _rotation_snap := 15.0
var _orbit_center := Vector3.ZERO
var _transform_mode := 0
var _local_transform := false
var _scale_snap := 0.0
var _gizmo: Control
var _transform_buttons: Array[Button] = []
var _space_button: Button
var _transform_drag = preload("res://scripts/world_editor/transform_drag.gd").new()
var _pack_map_dialog: ConfirmationDialog
var _dock_tabs: TabContainer
var _mode_buttons: Array[Button] = []
var _thumbnails: Node
var _selection_tools: Control
var _object_list: VBoxContainer
var _box_button: Button
var _snap_controls := {}
var _mcp: Node
var _mcp_popup: PopupMenu
var _mcp_autostart := true
var _placement_tools: Control
var _safety: Node
var _draft_directory := "" # Tests may isolate the recovery store under the content root.
var _recovery_button: Button
var _material_tool: Control
var _material_panel: VBoxContainer
var _material_directory := "" # Isolated fixtures may supply an external test library.
var _gameplay = preload("res://scripts/world_editor/gameplay_tools.gd").new()
var _event_panel: VBoxContainer
var _environment_panel: VBoxContainer
var _sun: DirectionalLight3D
var _authoring = preload("res://scripts/world_editor/authoring_view.gd").new()
var _view_panel: VBoxContainer
var _playtest: Node
var _buildings = preload("res://scripts/world_editor/building_tools.gd").new()
var _building_panel: VBoxContainer


func _ready() -> void:
	var dir := Paths.cache_directory("editor_yard")
	_path = dir.path_join("map.gltf") if dir != "" else ""
	if Net.session().world3d_editor_path != "":
		_path = Net.session().world3d_editor_path
	var kept = Net.session().world3d_editor_doc
	if kept != null:
		_doc = kept
		_dirty = kept.editor_dirty
	elif _path != "" and FileAccess.file_exists(_path):
		_doc = Document.open_file(_path)
		_load_failed = _doc == null
		if _load_failed:
			_doc = Document.new()
	else:
		_doc = Document.new()
		_doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
		_dirty = true
		Net.session().world3d_editor_doc = _doc
	_load_asset_scope()
	_gameplay.editor = self
	_buildings.editor = self
	_authoring.editor = self
	_playtest = preload("res://scripts/world_editor/playtest_session.gd").new()
	add_child(_playtest); _playtest.editor = self
	_auto_stroke.editable = _record_editable
	_add_light()
	_camera = Camera3D.new()
	_camera.current = true
	_camera.position = Vector3(0, 8, 12)
	_camera.rotation_degrees = Vector3(-35, 0, 0)
	add_child(_camera)
	_rebuild()
	_hud()
	_apply_environment()
	_safety = preload("res://scripts/world_editor/document_safety.gd").new()
	add_child(_safety)
	_safety.setup(self)
	if _load_failed:
		_status.text = "地图读取失败或格式不支持；已禁止覆盖保存"
	if _mcp_autostart and (OS.get_environment("RMMO_EDITOR_MCP").strip_edges().to_lower() in ["1", "true", "yes", "on"] or "--mcp" in OS.get_cmdline_user_args()):
		start_mcp()


func start_mcp(port: int = 18766) -> Dictionary:
	if _mcp == null:
		_mcp = preload("res://scripts/world_editor/mcp_server.gd").new()
		_mcp.editor = self
		add_child(_mcp)
	if _mcp.running: return {"ok": true, "url": _mcp.url(), "port": _mcp.port}
	var result: Dictionary = _mcp.start(port)
	_mcp_popup.set_item_checked(0, result.ok)
	_mcp_popup.set_item_disabled(1, not result.ok)
	_status.text = "3D MCP 已启用 · " + str(result.url) if result.ok else "MCP 启动失败：" + str(result.error)
	return result


func _toggle_mcp() -> void:
	if _mcp != null and _mcp.running:
		_mcp.stop()
		_mcp_popup.set_item_checked(0, false)
		_mcp_popup.set_item_disabled(1, true)
		_status.text = "3D MCP 已关闭"
	else: start_mcp()


func _copy_mcp_url() -> void:
	if _mcp != null and _mcp.running:
		DisplayServer.clipboard_set(_mcp.url())
		_status.text = "已复制 3D MCP 地址 · " + _mcp.url()


func _show_placement_panel() -> void:
	_placement_tools.cancel()
	if get_node_or_null("PlacementDialog") != null: return
	preload("res://scripts/world_editor/placement_panel.gd").show_panel(self)


func _input(event: InputEvent) -> void:
	if _playtest != null and _playtest.active() and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE: _playtest.stop()
		get_viewport().set_input_as_handled(); return
	if _building_panel!=null and _building_panel.street!=null and _building_panel.street.input(event):
		get_viewport().set_input_as_handled(); return
	if _authoring.input(event): get_viewport().set_input_as_handled(); return
	if _material_tool != null and _material_tool.active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_material_tool.finish(true)
			_material_tool.cancel()
			_status.text = "已退出材质笔刷"
			get_viewport().set_input_as_handled(); return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _canvas.get_global_rect().has_point(event.position):
				_material_panel._sync()
				_material_tool.start_stroke()
				_material_tool.dab(event.position - _canvas.global_position)
				get_viewport().set_input_as_handled(); return
			if not event.pressed and _material_tool.pointer_down:
				_material_tool.finish()
				get_viewport().set_input_as_handled(); return
		if event is InputEventMouseMotion and _material_tool.pointer_down:
			if _material_tool.stroke_active and _canvas.get_global_rect().has_point(event.position): _material_tool.dab(event.position - _canvas.global_position)
			get_viewport().set_input_as_handled(); return
	if _placement_tools != null and _placement_tools.active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_placement_tools.cancel()
			_status.text = "已取消表面放置"
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _canvas.get_global_rect().has_point(event.position):
			var result: Dictionary = _placement_tools.snap_to_surface(event.position - _canvas.global_position, _placement_tools.align_normal, _placement_tools.offset)
			if result.ok: _placement_tools.cancel()
			_placement_tools.report(result)
			get_viewport().set_input_as_handled()
			return
	if _selection_tools != null and _selection_tools.marquee:
		if event is InputEventMouseMotion:
			_selection_tools.move_box(event.position - _canvas.global_position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_selection_tools.move_box(event.position - _canvas.global_position)
			_selection_tools.finish_box()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_selection_tools.finish_box(true)
		get_viewport().set_input_as_handled()
		return
	# A release over a dock is consumed by GUI before unhandled_input.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stroke.end()
		_transform_drag.finish()
		_finish_auto_stroke()
	if _auto_stroke.active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_finish_auto_stroke(true)
		elif event is InputEventMouseMotion:
			if _canvas.get_global_rect().has_point(event.position): _place(event.position - _canvas.global_position, false)
		if event is InputEventKey or event is InputEventMouseMotion or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
	if _transform_drag.active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_transform_drag.finish(true)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			_transform_drag.update(event.position - _canvas.global_position, event.alt_pressed)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _building_panel!=null and _building_panel.street!=null:
			_building_panel.street.drawing=false; _building_panel.street.refresh()
		if _material_tool != null: _material_tool.cancel()
		if _placement_tools != null: _placement_tools.cancel()
		_transform_drag.finish()
		_finish_auto_stroke()
		if _selection_tools != null: _selection_tools.finish_box(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit: return
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_9:
			_pick = key - KEY_1
			_refresh_palette()
		elif key == KEY_Z and event.ctrl_pressed:
			if event.shift_pressed: _redo()
			else: _undo()
		elif key == KEY_Y and event.ctrl_pressed:
			_redo()
		elif key == KEY_DELETE and not _inspector.selection.is_empty():
			_selection_tools.remove()
		elif key == KEY_G and event.ctrl_pressed:
			if event.shift_pressed: _selection_tools.ungroup()
			else: _selection_tools.group()
		elif key == KEY_A and event.ctrl_pressed:
			_selection_tools.set_ids(_doc.records.map(func(r): return str(r.uuid)))
			_set_mode(1)
		elif key == KEY_B:
			_toggle_box_select()
		elif key == KEY_S and event.ctrl_pressed:
			_save()
			return
		elif key == KEY_F5:
			_play()
		elif key == KEY_D and event.ctrl_pressed:
			_duplicate_selected()
		elif key == KEY_F:
			_focus_selected()
		elif key == KEY_END:
			_placement_tools.report(_placement_tools.drop_selection(event.shift_pressed))
			get_viewport().set_input_as_handled()
			return
		elif key == KEY_V and not event.ctrl_pressed and not event.alt_pressed:
			_placement_tools.begin_surface(not event.shift_pressed)
			get_viewport().set_input_as_handled()
			return
		elif key in [KEY_W, KEY_R, KEY_T]:
			_set_transform_mode({KEY_W: 0, KEY_R: 1, KEY_T: 2}[key])
		elif key == KEY_L:
			_toggle_transform_space()
		elif key == KEY_Q or key == KEY_E:
			_rotate_selected(-1 if key == KEY_Q else 1)
		elif key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]:
			var direction: Vector3 = {KEY_LEFT: Vector3.LEFT, KEY_RIGHT: Vector3.RIGHT, KEY_UP: Vector3.FORWARD, KEY_DOWN: Vector3.BACK, KEY_PAGEUP: Vector3.UP, KEY_PAGEDOWN: Vector3.DOWN}[key]
			_nudge_selected(direction)
		elif key == KEY_ESCAPE:
			if not _inspector.selection.is_empty(): _inspector.select("")
			else: _request_exit()
		_status.text = _hint()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			_stroke.end()
		if not _canvas.get_global_rect().has_point(button.position):
			return
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.85 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18
			_camera.position = _orbit_center + (_camera.position - _orbit_center).normalized() * clampf(_camera.position.distance_to(_orbit_center) * factor, 2, 100)
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_place(button.position - _canvas.global_position, true, button.shift_pressed)
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
	var found: Array = _palette_items
	if found.is_empty():
		return {}
	return found[clampi(_pick, 0, found.size() - 1)]


func _can_drop_palette(_position: Vector2, data: Variant) -> bool:
	return not _load_failed and data is Dictionary and data.get("type") == "rmmo_palette" and _palette_items.has(data.get("entry"))


func _drop_palette(position: Vector2, data: Variant) -> void:
	if not _can_drop_palette(position, data): return
	_pick = _palette_items.find(data.entry)
	_palette.select(_pick)
	_set_mode(0)
	_place(position, true)
	_stroke.end()
	_finish_auto_stroke()
	_status.text = _hint()


func _place(screen: Vector2, fresh: bool, erase_override: bool = false) -> void:
	if _load_failed:
		return
	var spec := _selected()
	if (_mode == 0 and spec.is_empty()) or _camera == null:
		return
	var origin := _camera.project_ray_origin(screen)
	if _mode == 0 and spec.has("auto_family"):
		var point: Variant = Plane(Vector3.UP, _auto_height).intersects_ray(origin, _camera.project_ray_normal(screen))
		if point == null: return
		if fresh:
			_finish_auto_stroke()
			var options: Dictionary = _auto_panel.options(str(spec.auto_family))
			if options.has("error"):
				_status.text = options.error
				return
			_auto_stroke.begin(_doc, str(spec.auto_family), _auto_cell_size, _auto_height, _auto_erase or erase_override, options)
		var changed: Array[String] = _auto_stroke.paint(point)
		_refresh_records(changed)
		if not _auto_stroke.error.is_empty(): _status.text = _auto_stroke.error
		return
	if _mode == 1 and not fresh:
		_transform_drag.update(screen)
		return
	if _mode == 1 and fresh:
		if _selection_tools.box_mode:
			_selection_tools.begin_box(screen, erase_override)
			return
		if erase_override:
			_selection_tools.choose(_pick_object(screen), true)
			return
		var handle: int = _gizmo.hit_test(screen)
		if handle >= 0:
			_transform_drag.begin(self, screen, handle)
			return
	var end := origin + _camera.project_ray_normal(screen) * 80.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		if _mode == 1:
			_inspector.select("")
			return
		var point = Plane(Vector3.UP, _authoring.settings.base_height if _authoring.settings.isolation else 0.0).intersects_ray(origin, _camera.project_ray_normal(screen))
		if point == null or _mode == 1:
			return
		hit = {"position": point}
	if _mode == 1:
		if fresh:
			var id := str(hit.collider.get_meta("uuid", ""))
			if not _selection_tools.ids.has(id): _selection_tools.choose(id)
			if _transform_mode == 0:
				_transform_drag.begin(self, screen, 3)
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
	if spec.has("prefab_path"):
		if not fresh: return
		_place_prefab(spec, hit.position)
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
	if _building_panel != null:
		_building_panel.clear_preview()
		_building_panel.refresh_list()
	_authoring.refresh()
	_bodies_by_uuid.clear()
	var doomed: Array = []
	for child in get_children():
		if child == _view or child is StaticBody3D:
			doomed.append(child)
	for child in doomed:
		remove_child(child)
		child.free()
	_view = null
	_view = _doc.build()
	add_child(_view)
	for record in _doc.records:
		var visual := _view.get_node_or_null(NodePath(str(record.uuid))) as Node3D
		if visual != null: _authoring.decorate(record,visual)
	_add_bodies(_view)
	if _selection_tools != null: _selection_tools.refresh()
	if _object_list != null: _object_list.refresh()
	_refresh_selection()
	_apply_environment()
	if not _load_failed:
		Net.session().world3d_editor_doc = _doc


func _add_bodies(node: Node) -> void:
	if node.get_meta("editor_floor_excluded",false): return
	if node is Node3D and not node.visible: return
	if node is MeshInstance3D and node.mesh != null:
		var visual := node as MeshInstance3D
		var body := StaticBody3D.new()
		body.name = "%s_body" % str(visual.name)
		var asset: Node = visual
		while asset != null and not asset.has_meta("asset_uuid"): asset = asset.get_parent()
		body.set_meta("uuid", str(asset.get_meta("asset_uuid")) if asset != null else str(visual.name))
		body.set_meta("visual", visual)
		var uuid := str(body.get_meta("uuid"))
		if not _bodies_by_uuid.has(uuid): _bodies_by_uuid[uuid] = []
		_bodies_by_uuid[uuid].append(body)
		var shape := CollisionShape3D.new()
		if visual.mesh is BoxMesh:
			var box := BoxShape3D.new()
			box.size = visual.get_aabb().size
			shape.shape = box
			shape.position = visual.get_aabb().get_center()
		else:
			shape.shape = visual.mesh.create_trimesh_shape()
		body.transform = visual.global_transform
		body.add_child(shape)
		add_child(body)
		body.force_update_transform()
	for child in node.get_children():
		_add_bodies(child)


func _sync_selected_transform() -> void:
	if _authoring.settings.isolation and not _transform_drag.active:
		_rebuild()
		return
	for record in _selection_tools.records(): _sync_record_transform(record)
	_refresh_selection()


func _sync_record_transform(record: Dictionary) -> void:
	if record.has("surface_paint") and record.get("kind") != "asset":
		_refresh_records([str(record.uuid)])
		return
	var visual := _view.get_node_or_null(NodePath(str(record.uuid))) as Node3D
	if visual == null: return
	var helper = preload("res://scripts/world_editor/transform_gizmo.gd")
	visual.position = helper.vector(record, "position")
	visual.rotation_degrees = helper.vector(record, "rotation")
	if record.get("kind") == "asset" or record.has("tile3d"): visual.scale = helper.vector(record, "size")
	elif visual is MeshInstance3D and visual.mesh is BoxMesh: visual.mesh.size = helper.vector(record, "size")
	visual.force_update_transform()
	for body: StaticBody3D in _bodies_by_uuid.get(str(record.uuid), []):
		var mesh: MeshInstance3D = body.get_meta("visual")
		body.transform = mesh.global_transform
		var shape: CollisionShape3D = body.get_child(0)
		if shape.shape is BoxShape3D:
			shape.shape.size = mesh.get_aabb().size
			shape.position = mesh.get_aabb().get_center()
		body.force_update_transform()


func _refresh_records(ids: Array[String]) -> void:
	# Rebuild only cells whose rule variant changed, including erased cells.
	for uuid in ids:
		for body in _bodies_by_uuid.get(uuid, []): body.free()
		_bodies_by_uuid.erase(uuid)
		var previous := _view.get_node_or_null(NodePath(uuid))
		if previous != null: previous.free()
		var record: Dictionary = _doc._find(uuid)
		if record.is_empty(): continue
		var visual: Node3D = _doc._asset(record) if record.get("kind") == "asset" else _doc._mesh(record)
		_authoring.decorate(record,visual)
		_view.add_child(visual)
		_add_bodies(visual)
	if _inspector != null and ids.has(_inspector.selection): _inspector.refresh()


func _finish_auto_stroke(cancel: bool = false) -> void:
	if not _auto_stroke.active: return
	var had_changes: bool = _auto_stroke.changed
	if _auto_stroke.finish(cancel): _dirty = true
	if cancel and had_changes:
		_rebuild()
		_inspector.refresh()
	if _object_list != null and had_changes: _object_list.refresh()
	if _status != null: _status.text = "已取消自动铺设" if cancel else _hint()


func _detach_selected_tile() -> void:
	var changed := false
	for record in _selection_tools.records():
		if AutoRules.attached(record):
			AutoRules.detach(record)
			changed = true
	if changed: _refresh_records(AutoRules.refresh_all(_doc.records))
	_inspector.refresh()


func _update_auto_controls() -> void:
	if _auto_toolbar != null: _auto_toolbar.visible = _mode == 0 and _selected().has("auto_family")
	if _auto_panel != null: _auto_panel.refresh()


func _finish_edits() -> void:
	_authoring.picking = false
	if _material_tool != null: _material_tool.cancel()
	_transform_drag.finish()
	_finish_auto_stroke()
	_stroke.end()
	_selection_tools.finish_box(true)
	_placement_tools.cancel()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null:
		if focus is LineEdit and focus.get_parent() is SpinBox: focus.get_parent().apply()
		focus.release_focus()


func _save() -> bool:
	return _save_to(_path)


func _save_to(path: String, overwrite: bool = false) -> bool:
	_finish_edits()
	if _load_failed:
		_status.text = "读取失败的地图不能覆盖保存；请先恢复草稿或打开有效地图"
		return false
	if not Paths.allowed(path) or path.get_extension().to_lower() != "gltf":
		_status.text = "地图必须保存为工程外内容目录内的 glTF 文件"
		return false
	path = path.replace("\\", "/").simplify_path()
	var previous_path := _path
	if path != _path and FileAccess.file_exists(path) and not overwrite:
		_status.text = "另存为目标已存在，请选择新路径"
		return false
	Net.session().world3d_editor_doc = _doc
	var err: Error = _doc.save(path)
	if err == OK:
		_path = path
		_dirty = false
		Net.session().world3d_editor_path = _path
		if _safety != null: _safety.saved(previous_path)
		if previous_path != _path:
			_load_asset_scope()
			_refresh_palette()
	_status.text = "已保存" if err == OK else ("地图已被其他窗口修改或正在保存，请重新打开或另存为" if err == ERR_BUSY else "保存失败：" + error_string(err))
	return err == OK


func _play() -> void:
	_finish_edits()
	var result: Dictionary = _playtest.start()
	_status.text = "正在准备临时试玩…" if result.ok else str(result.error)

func _record_editable(record: Dictionary) -> bool:
	return SelectionGeometry.editable(record) and _authoring.includes(record)


func _hud() -> void:
	preload("res://scripts/world_editor/workspace.gd").build(self)


func _file_dialog(save_as: bool) -> void:
	if not save_as:
		_open_pack_maps()
		return
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
			_save_to(path, true)
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
	if _material_tool != null: _material_tool.cancel(); _material_tool.clear_target()
	if _placement_tools != null: _placement_tools.cancel()
	var document = Document.open_file(path)
	if document == null:
		_status.text = "无法读取地图，当前文档保持不变"
		return false
	_transform_drag.finish()
	_finish_auto_stroke()
	_doc = document
	_path = path
	Net.session().world3d_editor_path = path
	_load_asset_scope()
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
	if _mode == 1:
		var action: String = ["箭头沿轴移动 / 中心沿地面移动", "拖动三轴圆环旋转", "方块沿轴缩放 / 中心等比缩放"][_transform_mode]
		return "Shift+点选增减 · B 框选 · Ctrl+G 成组 · W/R/T 变换 · %s · Alt 不吸附" % action
	var spec := _selected()
	if spec.has("auto_family") and _mode == 0:
		return "自动%s · 左键连续铺设 · Shift+左键擦除当前类型 · Esc 取消整笔 · 固定高度 %.2f m · Ctrl+Z/Y 撤销/重做" % [AutoRules.LABELS[str(spec.auto_family)], _auto_height]
	var label := str(spec.get("label", "无"))
	var mode := "涂地" if bool(spec.get("paint", false)) else "摆放"
	return "模块库 %d 个 · %s「%s」· 1-9 选择 · Ctrl+Z 撤销整笔 · F5 临时副本试玩" % [_palette_items.size(), mode, label]


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

func _apply_environment() -> void:
	if _camera != null:
		preload("res://scripts/world3d/environment_settings.gd").apply(preload("res://scripts/world3d/environment_settings.gd").resolve(_doc.map_meta), _sun, _camera.environment)
	if _environment_panel != null: _environment_panel.refresh()

func snap_position(point: Vector3) -> Vector3:
	# Snap the horizontal plane without changing support height.
	return Vector3(snappedf(point.x, _snap), point.y, snappedf(point.z, _snap)) if _snap > 0 else point


func _refresh_palette() -> void:
	_palette_items = _library_items()
	_pick = clampi(_pick, 0, maxi(0, _palette_items.size() - 1))
	_palette.set_entries(_palette_items, _thumbnails.placeholder)
	_thumbnails.set_visible_entries([])
	if not _palette_items.is_empty(): _palette.select(_pick)
	# Filtering never imports a 3D model.
	if _preview: _preview.show_asset("")
	_update_auto_controls()


func _on_palette_selected(index: int) -> void:
	_pick = index
	if _selected().has("prefab_path"): _preview.show_prefab(_selected())
	else: _preview.show_asset(str(_selected().get("asset_path", "")))
	_set_mode(0)
	_status.text = _hint()


func _update_visible_thumbnails() -> void:
	var entries: Array = _palette.visible_entries() if _palette.is_visible_in_tree() else []
	_thumbnails.set_visible_entries(entries)
	for entry in entries:
		_palette.apply_thumbnail(preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(entry), _thumbnails.lookup(entry))


func _apply_thumbnail(key: String, texture: Texture2D) -> void:
	_palette.apply_thumbnail(key, texture)


func _set_mode(mode: int) -> void:
	if _material_tool != null: _material_tool.cancel()
	if _placement_tools != null: _placement_tools.cancel()
	_transform_drag.finish()
	_finish_auto_stroke()
	_selection_tools.finish_box(true)
	_mode = mode
	_stroke.end()
	for index in _mode_buttons.size():
		_mode_buttons[index].set_pressed_no_signal(index == mode)
	if mode == 0: _dock_tabs.current_tab = 0
	elif mode == 1: _dock_tabs.current_tab = 1
	if _gizmo != null: _gizmo.visible = mode == 1 and not _inspector.selection.is_empty()
	if _status != null: _status.text = _hint()
	_update_auto_controls()


func _set_transform_mode(mode: int) -> void:
	_transform_drag.finish()
	_transform_mode = mode
	_selection_tools.box_mode = false
	_box_button.set_pressed_no_signal(false)
	_set_mode(1)
	for index in _transform_buttons.size(): _transform_buttons[index].set_pressed_no_signal(index == mode)
	_update_space_button()


func _toggle_transform_space() -> void:
	if _transform_mode == 2 or _selection_tools.ids.size() > 1: return
	_transform_drag.finish()
	_local_transform = not _local_transform
	_update_space_button()


func _update_space_button() -> void:
	var multi: bool = _selection_tools.ids.size() > 1
	_space_button.text = "组合中心" if multi else ("局部轴" if _local_transform or _transform_mode == 2 else "世界轴")
	_space_button.disabled = multi or _transform_mode == 2
	_space_button.tooltip_text = "多选绕共同中心旋转，使用中心方块等比缩放" if multi else ("缩放沿物件局部轴" if _transform_mode == 2 else "L · 切换世界 / 局部坐标轴")


func _undo() -> void:
	if _material_tool != null: _material_tool.cancel()
	if _placement_tools != null: _placement_tools.cancel()
	_transform_drag.finish()
	_finish_auto_stroke()
	if _doc.undo():
		_dirty = true
		_rebuild()
		_selection_tools.refresh()


func _redo() -> void:
	if _material_tool != null: _material_tool.cancel()
	if _placement_tools != null: _placement_tools.cancel()
	_transform_drag.finish()
	_finish_auto_stroke()
	if _doc.redo():
		_dirty = true
		_rebuild()
		_selection_tools.refresh()


func _request_exit() -> void:
	_safety.request_exit(false)


func _exit_editor() -> void:
	Net.session().editor_return = false
	Net.session().go_login()


func _open_pack_maps() -> void:
	if _pack_map_dialog == null:
		_pack_map_dialog = preload("res://scripts/world_editor/pack_map_dialog.gd").new()
		add_child(_pack_map_dialog)
		_pack_map_dialog.map_chosen.connect(func(path: String):
			if path != _path: _request_open(path)
		)
	_pack_map_dialog.show_maps(_path)


func _duplicate_selected() -> void:
	_transform_drag.finish()
	_finish_auto_stroke()
	_selection_tools.duplicate_selected()


func _nudge_selected(direction: Vector3) -> void:
	if _load_failed: return
	if _selection_tools.ids.is_empty(): return
	_doc.checkpoint()
	var step := _snap if _snap > 0 else 0.01
	for record in _selection_tools.records():
		for axis in 3: record.position[axis] += direction[axis] * step
	_detach_selected_tile()
	_dirty = true
	_sync_selected_transform()
	_inspector.refresh()


func _rotate_selected(direction: int) -> void:
	if _load_failed: return
	if _selection_tools.ids.size() > 1:
		_selection_tools.transform_numeric("rotation", 1, direction * (_rotation_snap if _rotation_snap > 0 else 1.0))
		return
	var record: Dictionary = _doc._find(_inspector.selection)
	if record.is_empty(): return
	_doc.checkpoint()
	var step := _rotation_snap if _rotation_snap > 0 else 1.0
	record.rotation[1] = snappedf(float(record.rotation[1]) + direction * step, step)
	_detach_selected_tile()
	_dirty = true
	_sync_selected_transform()
	_inspector.refresh()


func _focus_selected() -> void:
	if _selection_tools.ids.is_empty(): return
	var bounds := SelectionGeometry.bounds(_selection_tools.records())
	_orbit_center = bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
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
	if _selection_tools == null or _selection_tools.records().is_empty(): return
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for record in _selection_tools.records():
		var corners := SelectionGeometry.corners(record)
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
	if _space_button != null: _update_space_button()


func _pick_object(screen: Vector2) -> String:
	var origin := _camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(screen) * 1000)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return "" if hit.is_empty() else str(hit.collider.get_meta("uuid", ""))


func _toggle_box_select() -> void:
	_set_mode(1)
	_selection_tools.box_mode = not _selection_tools.box_mode
	_box_button.set_pressed_no_signal(_selection_tools.box_mode)
	_status.text = "拖动框选完整落入框内的物件 · Shift 追加 · Esc 取消" if _selection_tools.box_mode else _hint()


func _place_prefab(entry: Dictionary, point: Vector3) -> bool:
	var result := Prefabs.place(_doc, entry, point)
	if not result.ok:
		_status.text = result.error
		return false
	_dirty = true
	_rebuild()
	_selection_tools.set_ids(result.ids)
	return true


func _save_prefab_dialog() -> void:
	_transform_drag.finish()
	_finish_auto_stroke()
	if _selection_tools.ids.is_empty():
		_status.text = "请先选择要保存为预制件的物件"
		return
	var packs: Array[Dictionary] = preload("res://scripts/world_editor/resource_pack_catalog.gd").new().packs()
	if packs.is_empty():
		_status.text = "请先建立带 metadata.json 的资源包"
		return
	var records: Array = _selection_tools.records().duplicate(true)
	var dialog := ConfirmationDialog.new()
	dialog.title = "保存可编辑预制件 · %d 件" % records.size()
	var fields := VBoxContainer.new()
	dialog.add_child(fields)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "名称，例如：木屋 / 门廊 / 桌椅组合"
	name_edit.text = str(records[0].get("editor_group_name", SelectionGeometry.label(records[0])))
	fields.add_child(name_edit)
	var packs_control := OptionButton.new()
	for pack in packs: packs_control.add_item(str(pack.name) + (" · 全局共享" if pack.shared else ""))
	for index in packs.size():
		if str(packs[index].root) == _asset_pack_root: packs_control.select(index)
	fields.add_child(packs_control)
	var hint := Label.new()
	hint.text = "保存后可在素材库搜索、预览、拖入地图。\n每次放置都是可独立修改的组合。"
	fields.add_child(hint)
	dialog.confirmed.connect(func():
		var root_path := str(packs[packs_control.selected].root)
		var library = preload("res://scripts/world_editor/asset_library.gd").new(root_path.path_join("assets"))
		var result := Prefabs.capture(records, library, name_edit.text)
		if result.ok:
			if root_path == _asset_pack_root: _assets = library
			else:
				_shared_assets = _shared_assets.filter(func(existing): return existing.directory != library.directory)
				_shared_assets.append(library)
			_query = ""
			_refresh_palette()
			_pick = _palette_items.find(result.entry)
			_palette.select(_pick)
			_thumbnails.queue_import(result.entry)
			_dock_tabs.current_tab = 0
			_status.text = "已保存预制件：" + str(result.entry.label)
		else: _status.text = result.error
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(390, 190))
	name_edit.grab_focus()


func _library_items() -> Array:
	var result := Modules.search(_query) + _assets.search(_query)
	for library in _shared_assets: result.append_array(library.search(_query))
	return result

func _load_asset_scope() -> void:
	var catalog = preload("res://scripts/world_editor/resource_pack_catalog.gd").new()
	var packs: Array[Dictionary] = catalog.packs()
	var owner: int = catalog.owner_of(_path, packs)
	_asset_pack_root = str(packs[owner].root) if owner >= 0 else ""
	if owner >= 0:
		_assets = preload("res://scripts/world_editor/asset_library.gd").new(_asset_pack_root.path_join("assets"))
	else:
		_assets.entries = []
	_shared_assets.clear()
	for pack in packs:
		if pack.shared and pack.root != _asset_pack_root:
			_shared_assets.append(preload("res://scripts/world_editor/asset_library.gd").new(str(pack.root).path_join("assets")))


func _import_asset(relink: bool = false) -> void:
	if relink and (_selection_tools.ids.size() != 1 or _load_failed):
		_status.text = "请单独选择一个未锁定的模型再重新关联"
		return
	if not _asset_pack_root.is_empty():
		_import_asset_into_pack(_asset_pack_root, relink)
		return
	var packs: Array[Dictionary] = preload("res://scripts/world_editor/resource_pack_catalog.gd").new().packs()
	if packs.is_empty():
		_status.text = "请先建立带 metadata.json 的资源包，再导入模型。"
		return
	var choose := ConfirmationDialog.new()
	choose.title = "导入到资源包"
	choose.ok_button_text = "选择模型…"
	var options := OptionButton.new()
	for pack in packs: options.add_item(str(pack.name) + (" · 全局" if pack.shared else ""))
	choose.add_child(options)
	choose.confirmed.connect(func():
		var path := str(packs[options.selected].root)
		choose.hide()
		choose.queue_free()
		_import_asset_into_pack(path, relink)
	)
	choose.canceled.connect(choose.queue_free)
	add_child(choose)
	choose.popup_centered(Vector2i(360, 120))


func _import_asset_into_pack(pack_root: String, relink: bool) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.glb,*.gltf ; 3D 模型"])
	dialog.file_selected.connect(func(path: String):
		if _asset_pack_root != pack_root:
			_asset_pack_root = pack_root
			_assets = preload("res://scripts/world_editor/asset_library.gd").new(pack_root.path_join("assets"))
			_shared_assets = _shared_assets.filter(func(library): return library.directory != _assets.directory)
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
			_thumbnails.queue_import(result.entry)
			_status.text = "模型已导入，正在生成资源包缩略图…"
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _manage_asset() -> void:
	var entry := _selected()
	if not entry.has("asset_path") and not entry.has("prefab_path"):
		_status.text = "请先在素材库选择导入模型或预制件"
		return
	var owner = _assets
	for library in _shared_assets:
		if library.entries.has(entry): owner = library
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
		if owner.save() != OK: entry.merge(old, true); _status.text = "素材库保存失败"
		_refresh_palette()
		dialog.queue_free()
	)
	dialog.custom_action.connect(func(_action: String):
		var index: int = owner.entries.find(entry)
		owner.entries.erase(entry)
		if owner.save() != OK: owner.entries.insert(index, entry); _status.text = "素材库保存失败"
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
