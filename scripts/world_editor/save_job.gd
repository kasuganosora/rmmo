extends Node
## One exclusive save. Scene creation/readback stays on main; an off-tree export
## and its private resources belong to one worker until that worker has joined.
signal finished(result: Dictionary)
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const CpuTexture = preload("res://scripts/world3d/export_cpu_texture.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")
var editor: Node3D
var active := false
var result: Dictionary = {}
var thread: Thread
var _mutex := Mutex.new()
var _progress := {"phase":"idle", "completed":0, "total":0}
var _started := 0
var _ended := 0
var _serial := 0
var _path := ""
var _materials := {}
var _textures := {}
var _mesh_copies := {}
var _view: Node3D
var _viewport_modes := {}
var _gui_input_modes := {}
var _snapshot_error := false

func state() -> Dictionary:
	_mutex.lock()
	var value := _progress.duplicate()
	_mutex.unlock()
	value.merge({"active":active,"job_id":_serial,"path":_path,"elapsed_seconds":((Time.get_ticks_usec() if active else _ended)-_started)/1000000.0,"result":result.duplicate(true)})
	return value

func report(phase: String, completed: int = 0, total: int = 0) -> void:
	_mutex.lock()
	_progress = {"phase":phase,"completed":completed,"total":total}
	_mutex.unlock()

func start(path: String, overwrite: bool = false) -> Dictionary:
	if active: return {"ok":false,"error":"正在保存，请等待当前保存完成"}
	if not editor._prepare_save(path, overwrite): return {"ok":false,"error":editor._status.text}
	_path = path.replace("\\", "/").simplify_path()
	_started = Time.get_ticks_usec(); _serial += 1; result = {}; active = true; _snapshot_error = false
	report("validate")
	# Embedded dialogs have their own Viewport input routing. Lock their GUI as
	# well as the editor shortcuts, so a material/inspector dialog cannot mutate
	# records while the export scene is being prepared.
	var input_viewports: Array = [editor.get_viewport()]
	input_viewports.append_array(editor.find_children("*", "Window", true, false))
	for viewport in input_viewports:
		_gui_input_modes[viewport] = viewport.gui_disable_input
		viewport.gui_disable_input = true
	# Editing is locked; retain the last 3D frame while the status bar animates.
	# Avoid spending GPU/CPU time re-rendering an unchanged large town every frame.
	for container in [editor._canvas, editor._preview]:
		if container == null: continue
		for child in container.get_children():
			if child is SubViewport:
				_viewport_modes[child] = child.render_target_update_mode
				child.render_target_update_mode = SubViewport.UPDATE_DISABLED
	editor._save_progress.visible = true
	_run.call_deferred()
	return {"ok":true,"saved":false,"pending":true,"job_id":_serial,"path":_path}

func wait_result() -> Dictionary:
	if active: return await finished
	return result.duplicate(true)

func _run() -> void:
	# Let the first status frame paint before any work is started.
	await get_tree().process_frame
	var document = editor._doc
	var previous_path: String = editor._path
	document.last_save_metrics = {}
	var phase := Time.get_ticks_usec()
	# Resource-root validation can consult the active AssetManager. Keep it on
	# main and yield between records, using exactly the synchronous validators.
	var err: Error = document.validate_save_meta()
	if err != OK: _complete(err, previous_path); return
	var slice := Time.get_ticks_usec()
	var count := 0
	var material_validation:Dictionary={}
	for record in document.records:
		err = document.validate_save_record(record,material_validation)
		if err != OK: _complete(err, previous_path); return
		count += 1
		report("validate", count, document.records.size())
		if Time.get_ticks_usec()-slice >= 8000:
			await get_tree().process_frame
			slice = Time.get_ticks_usec()
	document.last_save_metrics.validate_ms = (Time.get_ticks_usec()-phase)/1000.0
	if err != OK: _complete(err, previous_path); return
	report("build", 0, document.records.size())
	await get_tree().process_frame
	phase = Time.get_ticks_usec()
	_view = document.export_root()
	document.terrain_neighbors.update(document.records)
	document._save_meshes.begin(document.records)
	# The editor already owns the authoritative painted building arrays. Reuse
	# them for the first export too; don't rebuild/upload every face a second time.
	var reused:=0
	if is_instance_valid(editor._view):
		for record in document.records:
			if not record.has("building"):continue
			var visual:MeshInstance3D=editor._view.get_node_or_null(NodePath(str(record.uuid))) as MeshInstance3D
			if visual==null or visual.mesh==null or visual.material_override!=null or visual.has_meta("paint_error"):continue
			var clean:=true
			for slot in visual.mesh.get_surface_count():
				if visual.get_surface_override_material(slot)!=null:clean=false;break
			if not clean:continue
			document._save_meshes.put_mesh(str(record.uuid),document._save_meshes.key(record,{}),visual.mesh);reused+=1
	document.last_save_metrics.live_building_meshes_reused=reused
	slice = Time.get_ticks_usec()
	count = 0
	for record in document.records:
		var child: Node3D = document._asset(record) if record.get("kind") == "asset" else document._mesh(record, false)
		_view.add_child(child)
		if child.has_meta("paint_error") or child.has_meta("tile_error"):
			_complete(ERR_INVALID_DATA, previous_path); return
		_snapshot_materials(child)
		if _snapshot_error: _complete(ERR_INVALID_DATA, previous_path); return
		count += 1
		report("build", count, document.records.size())
		if Time.get_ticks_usec()-slice >= 8000:
			await get_tree().process_frame
			slice = Time.get_ticks_usec()
	document.last_save_metrics.build_ms = (Time.get_ticks_usec()-phase)/1000.0
	document.last_save_metrics.geometry_cache_hits = document._save_meshes.hits
	document.last_save_metrics.geometry_cache_misses = document._save_meshes.misses
	document.last_save_metrics.geometry_cache_bytes = document._save_meshes.bytes
	phase = Time.get_ticks_usec()
	thread = Thread.new()
	err = thread.start(Io.save_scene_atomic.bind(_view, _path, document.save_signature(_path), report))
	if err == OK:
		while thread.is_alive(): await get_tree().process_frame
		err = thread.wait_to_finish()
	thread = null
	document.last_save_metrics.publish_ms = (Time.get_ticks_usec()-phase)/1000.0
	if err == OK:
		document.last_save_metrics.export = Io.last_export_metrics.duplicate(true)
		document.accept_save(_path, str(_view.get_meta("published_signature", "")))
	_complete(err, previous_path)

func _snapshot_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		# Snapshot active materials before clearing the instance-wide override.
		var materials: Array[Material] = []
		for slot in node.mesh.get_surface_count(): materials.append(_material(node.get_active_material(slot)))
		node.material_override = null
		var cpu_compatible: bool = node.mesh.get_script() == CpuMesh or node.mesh is PrimitiveMesh
		if node.mesh is ArrayMesh:
			cpu_compatible = node.mesh.get_blend_shape_count() == 0
			for slot in node.mesh.get_surface_count():
				cpu_compatible = cpu_compatible and node.mesh.surface_get_primitive_type(slot) == Mesh.PRIMITIVE_TRIANGLES
		cpu_compatible = cpu_compatible and node.skin == null
		if cpu_compatible:
			# CPU meshes have no RenderingServer surface slots. Do not install GPU
			# overrides (or change cached materials shared with later saves).
			# Capture fresh geometry on main too: worker readbacks otherwise wait
			# for a render-frame roundtrip per mesh on the first save.
			var original: Mesh = node.mesh
			var copy: Mesh
			for entry in _mesh_copies.get(original, []):
				if entry.materials == materials: copy = entry.mesh; break
			if copy == null:
				var captured: Mesh = CpuMesh.capture(original)
				copy = CpuMesh.new()
				copy.surfaces = captured.surfaces
				copy.bounds = captured.bounds
				copy.box_size = captured.box_size
				copy.resource_name = original.resource_name
				if original.has_meta("extras"): copy.set_meta("extras", original.get_meta("extras").duplicate(true))
				copy.materials = materials
				if not _mesh_copies.has(original): _mesh_copies[original] = []
				_mesh_copies[original].append({"mesh":copy,"materials":materials})
			# Clear source GPU overrides before switching to a CPU-only mesh.
			if node.mesh.get_script() != CpuMesh:
				for slot in node.get_surface_override_material_count(): node.set_surface_override_material(slot, null)
			node.mesh = copy
		else:
			for slot in materials.size(): node.set_surface_override_material(slot, materials[slot])
	for child in node.get_children(): _snapshot_materials(child)

func _material(source: Material) -> Material:
	if source == null: return null
	if _materials.has(source): return _materials[source]
	var copy: Material = source.duplicate()
	_materials[source] = copy
	if source is BaseMaterial3D:
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var texture: Texture2D = source.get_texture(slot)
			if texture == null: continue
			if not _textures.has(texture):
				var cpu := CpuTexture.new()
				cpu.pixels = texture.get_image()
				cpu.resource_name = texture.resource_name
				if cpu.pixels == null or cpu.pixels.is_empty():
					_snapshot_error = true
					return null
				_textures[texture] = cpu
			copy.set_texture(slot, _textures[texture])
	return copy

func _complete(err: Error, previous_path: String) -> void:
	if is_instance_valid(_view): _view.free()
	_view = null; _materials.clear(); _textures.clear(); _mesh_copies.clear()
	_ended = Time.get_ticks_usec()
	editor._doc.last_save_metrics.total_ms = (_ended-_started)/1000.0
	editor._finish_save(err, _path, previous_path)
	result = {"ok":err==OK,"saved":err==OK,"pending":false,"job_id":_serial,"path":_path,"timings":editor._doc.last_save_metrics.duplicate(true)}
	if err != OK: result.error = editor._status.text
	report("complete" if err == OK else "failed", 1, 1)
	active = false
	_restore_viewports()
	editor._save_progress.hide()
	finished.emit(result.duplicate(true))

func _restore_viewports() -> void:
	for viewport in _viewport_modes:
		if is_instance_valid(viewport): viewport.render_target_update_mode = _viewport_modes[viewport]
	_viewport_modes.clear()
	for viewport in _gui_input_modes:
		if is_instance_valid(viewport): viewport.gui_disable_input = _gui_input_modes[viewport]
	_gui_input_modes.clear()

func _process(_delta: float) -> void:
	if not active: return
	var value := state()
	var labels := {"validate":"检查地图与素材", "build":"准备地图网格", "scene":"整理场景", "textures":"导出材质与贴图", "geometry":"写入网格数据", "publish":"完成原子保存"}
	editor._save_progress.indeterminate = int(value.total) <= 0
	if int(value.total) > 0:
		editor._save_progress.max_value = value.total
		editor._save_progress.value = value.completed
	var count := " · %d/%d" % [value.completed,value.total] if int(value.total)>0 else ""
	editor._status.text = "保存中 · %s%s · 已用 %.1f 秒" % [labels.get(value.phase,value.phase), count, value.elapsed_seconds]

func _exit_tree() -> void:
	# Normal close is rejected/deferred while active. Handle forced owner teardown
	# without freeing resources still owned by a worker.
	if thread != null and thread.is_started(): thread.wait_to_finish()
	if is_instance_valid(_view): _view.free()
	_restore_viewports()
