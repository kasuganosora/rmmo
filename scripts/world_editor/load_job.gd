extends Node
## File bytes/JSON are private to a worker. Validation and scene resources stay
## on main, with counted scene construction between frames.
signal finished(result: Dictionary)
const Doc = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const AssetLibrary = preload("res://scripts/world_editor/asset_library.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const TerrainTextures=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
const PickingPreparation=preload("res://scripts/world_editor/picking_load_preparation.gd")
const SourceSnapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
var editor: Node3D
var active := false
var result := {}
var phase := "idle"
var completed := 0
var total := 0
var path := ""
var _started := 0
var _elapsed := 0.
var _serial := 0
var _thread: Thread
var _layer: CanvasLayer
var _label: Label
var _bar: ProgressBar
var _gui_modes := {}
var _viewport_modes := {}
var _last_paint := 0
var _initial := false
var _timings:Dictionary={}
var _validation_budget_us:=8000
var _asset_failures:Dictionary={}
var _terrain_surfaces:Dictionary={}
var _terrain_masks:Dictionary={}
var _terrain_texture_checked:Dictionary={}

func state() -> Dictionary:
	return {"active":active,"job_id":_serial,"phase":phase,"completed":completed,"total":total,"path":path,"elapsed_seconds":(Time.get_ticks_usec()-_started)/1000000. if active else _elapsed,"timings":_timings.duplicate(true),"result":result.duplicate(true)}

func start(value: String, initial: bool = false) -> Dictionary:
	if active or editor.saving(): return {"ok":false,"error":"正在读取或保存地图，请等待完成"}
	if not Paths.allowed(value) or value.get_extension().to_lower()!="gltf" or not FileAccess.file_exists(value): return {"ok":false,"error":"地图路径无效或文件不存在"}
	editor._finish_edits()
	path=value; _initial=initial; _started=Time.get_ticks_usec(); _serial+=1
	active=true; result={}; _timings={}; _asset_failures.clear(); _terrain_surfaces.clear(); _terrain_masks.clear(); _terrain_texture_checked.clear(); report("read")
	_show_overlay()
	_run.call_deferred()
	return {"ok":true,"pending":true,"job_id":_serial,"path":path}

func report(value: String, done: int = 0, count: int = 0) -> void:
	phase=value; completed=done; total=count
	if is_instance_valid(_label) and Time.get_ticks_usec()-_last_paint>50000:
		_paint(); _last_paint=Time.get_ticks_usec()

static func _read(value: String) -> RefCounted:
	return SourceSnapshot.read_file(value)

func _run() -> void:
	await get_tree().process_frame
	_thread=Thread.new()
	var err:=_thread.start(_read.bind(path),Thread.PRIORITY_LOW)
	if err!=OK: _complete(false,"无法启动地图读取："+error_string(err)); return
	while _thread.is_alive(): await get_tree().process_frame
	var prepared: SourceSnapshot=_thread.wait_to_finish(); _thread=null
	report("validate"); await get_tree().process_frame
	var validation=preload("res://scripts/world3d/document_open_cursor.gd").new()
	var validate_started:=Time.get_ticks_usec()
	validation.begin_snapshot(prepared,true,report)
	while not validation.done:
		validation.advance(_validation_budget_us)
		if not validation.done:await get_tree().process_frame
	_timings.validation=validation.metrics
	_timings.validate_ms=(Time.get_ticks_usec()-validate_started)/1000.
	var document=validation.document
	if document==null: _complete(false,validation.error); return
	# Only replace the old document after parsing and all validators succeed.
	editor._material_tool.clear_target()
	editor._doc=document; editor._path=path; editor._load_failed=false; editor._dirty=false
	preload("res://scripts/net/net.gd").session().world3d_editor_path=path
	editor._selection_tools.ids.clear(); editor._inspector.selection=""
	var release_started:=Time.get_ticks_usec()
	prepared=null;validation=null
	_timings.prepared_release_ms=(Time.get_ticks_usec()-release_started)/1000.
	report("scope"); await get_tree().process_frame
	var scope_started:=Time.get_ticks_usec()
	editor._load_asset_scope()
	_timings.asset_scope_ms=(Time.get_ticks_usec()-scope_started)/1000.
	report("build",0,document.records.size()); await get_tree().process_frame
	var build_started:=Time.get_ticks_usec()
	_timings.build={"units":{},"yields":0,"max_slice_ms":0.,"max_slice_first_uuid":"","max_slice_last_uuid":""}
	var mark:=Time.get_ticks_usec()
	var begin_steps:Dictionary={}
	editor._begin_rebuild(begin_steps)
	_timings.build.begin_rebuild_steps=begin_steps
	_build_timing("begin_rebuild",mark)
	var context: Array=[document.load_paint_validation,document.load_texture_checks,document.load_box_meshes,document.load_model_signatures,document.load_material_pool]
	document.load_paint_validation={}; document.load_texture_checks={}; document.load_box_meshes={}; document.load_model_signatures={}; document.load_material_pool={}
	mark=Time.get_ticks_usec()
	document.terrain_neighbors=await _prepare_terrain(document.records)
	_build_timing("terrain_prepare_wait",mark)
	mark=Time.get_ticks_usec()
	editor._view=document.export_root(); editor.add_child(editor._view)
	_build_timing("export_root",mark)
	var slice:=Time.get_ticks_usec(); var count:=0; var slice_first_uuid:=""
	for record in document.records:
		var uuid:=str(record.get("uuid",""))
		var texture_payload:Dictionary=await _prepare_record_textures(record)
		var prepared_asset:Dictionary=await _prepare_asset(record)
		if prepared_asset.get("yielded",false) or not texture_payload.is_empty():slice=Time.get_ticks_usec();slice_first_uuid=""
		if slice_first_uuid.is_empty():slice_first_uuid=uuid
		var record_started:=Time.get_ticks_usec()
		var image_scope:Dictionary=TerrainTextures.install(texture_payload) if not texture_payload.is_empty() else {}
		var visual: Node3D=document._asset(record,prepared_asset) if record.get("kind")=="asset" else _prepared_mesh(document,record)
		if not texture_payload.is_empty():
			TerrainTextures.restore(image_scope,texture_payload.failed)
			if not texture_payload.failed.is_empty():visual.set_meta("paint_error","材质贴图缺失或损坏")
			texture_payload.clear()
		_build_timing("asset" if record.get("kind")=="asset" else "mesh",record_started,uuid)
		mark=Time.get_ticks_usec();editor._view.add_child(visual)
		_build_timing("add_child",mark,uuid)
		mark=Time.get_ticks_usec();editor._authoring.decorate(record,visual)
		_build_timing("decorate",mark,uuid)
		mark=Time.get_ticks_usec()
		var picking:Dictionary=await _add_record_bodies(visual,uuid,slice,slice_first_uuid)
		_build_elapsed("add_bodies",Time.get_ticks_usec()-mark-picking.wait_us,uuid)
		_build_elapsed("record",Time.get_ticks_usec()-record_started-picking.wait_us,uuid)
		slice=picking.slice;slice_first_uuid=picking.first_uuid
		count+=1; completed=count
		var slice_us:=Time.get_ticks_usec()-slice
		if slice_us/1000.>_timings.build.max_slice_ms:
			_timings.build.max_slice_ms=slice_us/1000.;_timings.build.max_slice_first_uuid=slice_first_uuid;_timings.build.max_slice_last_uuid=uuid
		if slice_us>=8000:
			_timings.build.yields+=1
			await get_tree().process_frame; slice=Time.get_ticks_usec();slice_first_uuid=""
	mark=Time.get_ticks_usec()
	document.load_paint_validation=context[0]; document.load_texture_checks=context[1]; document.load_box_meshes=context[2]; document.load_model_signatures=context[3]; document.load_material_pool=context[4]
	_build_timing("context_restore",mark)
	report("batch"); await get_tree().process_frame
	mark=Time.get_ticks_usec()
	editor._finish_rebuild()
	_build_timing("finish_rebuild",mark)
	var batch_wait_started:=Time.get_ticks_usec()
	while editor._ground_batches.stats().pending_groups>0: await get_tree().process_frame
	_timings.build.batch_wait_ms=(Time.get_ticks_usec()-batch_wait_started)/1000.
	mark=Time.get_ticks_usec()
	editor._refresh_palette()
	_build_timing("refresh_palette",mark)
	mark=Time.get_ticks_usec()
	var missing:bool=not document.missing_assets().is_empty()
	_build_timing("missing_assets",mark)
	_timings.build.elapsed_ms=(Time.get_ticks_usec()-build_started)/1000.
	_complete(true,"已打开："+path.get_file()+(" · 素材缺失，请重新关联" if missing else ""))

func _remember_picking_slice(started:int,first_uuid:String,uuid:String)->void:
	var elapsed_ms:=(Time.get_ticks_usec()-started)/1000.
	if elapsed_ms>_timings.build.max_slice_ms:
		_timings.build.max_slice_ms=elapsed_ms;_timings.build.max_slice_first_uuid=first_uuid;_timings.build.max_slice_last_uuid=uuid

func _add_record_bodies(visual:Node,uuid:String,slice:int,first_uuid:String)->Dictionary:
	var pending:Array=[visual];var wait_us:=0
	while not pending.is_empty():
		if first_uuid.is_empty():first_uuid=uuid
		var node:Node=pending.pop_back()
		# Reuse the synchronous traversal's exact subtree exclusion rule.
		if not editor._picking_node_enabled(node):continue
		if node is MeshInstance3D and node.mesh!=null:
			var mark:=Time.get_ticks_usec()
			var snapshot:=PickingPreparation.snapshot(node.get_meta("paint_source",node.mesh))
			_build_timing("picking_capture",mark,uuid)
			if not snapshot.is_empty():
				_thread=Thread.new();var prepared:Dictionary
				if _thread.start(PickingPreparation.extract.bind(snapshot.surfaces),Thread.PRIORITY_LOW)==OK:
					_remember_picking_slice(slice,first_uuid,uuid)
					report("picking",completed,total);mark=Time.get_ticks_usec()
					await get_tree().process_frame
					while _thread.is_alive():await get_tree().process_frame
					prepared=_thread.wait_to_finish();_thread=null
					var waited:=Time.get_ticks_usec()-mark;wait_us+=waited
					_build_elapsed("picking_faces_wait",waited,uuid)
					slice=Time.get_ticks_usec();first_uuid=uuid
				else:
					_thread=null;prepared=PickingPreparation.extract(snapshot.surfaces)
				_build_elapsed("picking_faces_prepare",prepared.elapsed_us,uuid)
				PickingPreparation.publish(snapshot,prepared.faces)
				prepared.clear();snapshot.clear();report("build",completed,total)
			var source:Mesh=node.get_meta("paint_source",node.mesh)
			if not source is BoxMesh:
				# Cooking the native shape and attaching it to a physics body are
				# separate expensive calls. Keep the original shared full shape,
				# but give the UI a frame between them when the budget is spent.
				mark=Time.get_ticks_usec();editor._picking_shapes.shape_for(source)
				_build_timing("picking_shape",mark,uuid)
				if Time.get_ticks_usec()-slice>=8000:
					_remember_picking_slice(slice,first_uuid,uuid);_timings.build.yields+=1
					mark=Time.get_ticks_usec();await get_tree().process_frame
					wait_us+=Time.get_ticks_usec()-mark;slice=Time.get_ticks_usec();first_uuid=uuid
			mark=Time.get_ticks_usec();editor._add_bodies(node,false)
			_build_timing("picking_publish",mark,uuid)
		# Reverse insertion preserves the former recursive depth-first order.
		var children:=node.get_children()
		for index in range(children.size()-1,-1,-1):pending.append(children[index])
		if Time.get_ticks_usec()-slice>=8000:
			_remember_picking_slice(slice,first_uuid,uuid)
			_timings.build.yields+=1
			var mark:=Time.get_ticks_usec();await get_tree().process_frame
			wait_us+=Time.get_ticks_usec()-mark;slice=Time.get_ticks_usec();first_uuid=""
	return {"wait_us":wait_us,"slice":slice,"first_uuid":first_uuid}

func _build_timing(unit:String,started:int,uuid:String="")->void:
	var used:=Time.get_ticks_usec()-started
	_build_elapsed(unit,used,uuid)

func _build_elapsed(unit:String,used:int,uuid:String="")->void:
	var units:Dictionary=_timings.build.units
	if not units.has(unit):units[unit]={"count":0,"total_ms":0.,"max_ms":0.,"max_uuid":""}
	var row:Dictionary=units[unit]
	row.count+=1;row.total_ms+=used/1000.
	if used/1000.>row.max_ms:row.max_ms=used/1000.;row.max_uuid=uuid

func _prepared_mesh(document:RefCounted,record:Dictionary)->MeshInstance3D:
	var uuid:=str(record.uuid)
	if not _terrain_surfaces.has(uuid) and not _terrain_masks.has(uuid):return document._mesh(record,true)
	# UUID-keyed preparation belongs only to this immutable load. Install it for
	# this call and restore everything before any input/undo can see the document.
	var previous_arrays:Dictionary=document.load_surface_arrays
	if _terrain_surfaces.has(uuid):document.load_surface_arrays={uuid:_terrain_surfaces[uuid]}
	var contexts:Dictionary=document.terrain_neighbors.data
	var had_context:=contexts.has(uuid);var context:Dictionary=contexts.get(uuid,{})
	var had_mask:=context.has("region_mask");var previous_mask:Variant=context.get("region_mask")
	if _terrain_masks.has(uuid):context.region_mask=_terrain_masks[uuid];contexts[uuid]=context
	var visual:MeshInstance3D=document._mesh(record,true)
	document.load_surface_arrays=previous_arrays
	if had_mask:context.region_mask=previous_mask
	else:context.erase("region_mask")
	if not had_context:contexts.erase(uuid)
	_terrain_surfaces.erase(uuid);_terrain_masks.erase(uuid)
	return visual

static func _parse_asset(value:String)->Dictionary:
	# Same private GLTF state preparation as the game loader. Scene nodes and
	# the shared PackedScene cache are created only after joining on main.
	var started:=Time.get_ticks_usec()
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	var error:=document.append_from_file(value,state,0,value.get_base_dir())
	if error!=OK:
		error=document.append_from_buffer(FileAccess.get_file_as_bytes(value),value.get_base_dir(),state)
	return {"document":document,"state":state,"error":error,"elapsed_us":Time.get_ticks_usec()-started}

static func _terrain_context(records:Array)->Dictionary:
	var started:=Time.get_ticks_usec()
	var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
	context.update(records,true)
	var neighbor_us:=Time.get_ticks_usec()-started
	var geometry:=preload("res://scripts/world_editor/terrain_load_preparation.gd").prepare(records,context)
	return {"context":context,"elapsed_us":neighbor_us,"geometry":geometry}

func _prepare_terrain(records:Array)->RefCounted:
	# Busy input guards keep records read-only. Only this new private context is
	# written by the worker; publish it after join, like the runtime map loader.
	report("terrain");await get_tree().process_frame
	_thread=Thread.new()
	if _thread.start(_terrain_context.bind(records),Thread.PRIORITY_LOW)!=OK:
		_thread=null
		var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
		context.update(records)
		report("build",0,records.size())
		return context
	while _thread.is_alive():await get_tree().process_frame
	var prepared:Dictionary=_thread.wait_to_finish();_thread=null
	_build_elapsed("terrain_neighbors_worker",prepared.elapsed_us)
	_build_elapsed("terrain_arrays_worker",prepared.geometry.arrays_us)
	_build_elapsed("terrain_masks_worker",prepared.geometry.masks_us)
	_timings.build.terrain_geometry={"wall_ms":prepared.geometry.elapsed_us/1000.,"worker_elapsed_sum_ms":prepared.geometry.worker_elapsed_sum_us/1000.}
	_terrain_surfaces=prepared.geometry.surfaces;_terrain_masks=prepared.geometry.masks
	report("build",0,records.size())
	return prepared.context

func _prepare_asset(record:Dictionary)->Dictionary:
	if record.get("kind")!="asset" or record.has("house_prefab") or record.has("bridge_mesh"):return {}
	var asset_path:=str(record.get("asset_path",""))
	if _asset_failures.has(asset_path):return {"scene":null}
	if AssetLibrary._scenes.has(asset_path):return {}
	if not FileAccess.file_exists(asset_path):return {"scene":null}
	_thread=Thread.new()
	if _thread.start(_parse_asset.bind(asset_path),Thread.PRIORITY_LOW)!=OK:
		_thread=null
		return {} # Preserve the synchronous fallback if no worker can start.
	var done:=completed;var count:=total;var uuid:=str(record.get("uuid",""))
	report("asset",done,count)
	var wait_started:=Time.get_ticks_usec()
	while _thread.is_alive():await get_tree().process_frame
	var parsed:Dictionary=_thread.wait_to_finish();_thread=null
	_build_timing("asset_wait",wait_started,uuid)
	_build_elapsed("asset_parse_worker",parsed.elapsed_us,uuid)
	var mark:=Time.get_ticks_usec();var scene:Node3D
	if parsed.error==OK:
		var imported:Node=Io.generate_scene(parsed.document,parsed.state)
		if imported!=null and AssetLibrary.cache_scene(asset_path,imported):scene=AssetLibrary.instantiate(asset_path)
	if scene==null:_asset_failures[asset_path]=true
	_build_timing("asset_prepare_main",mark,uuid)
	mark=Time.get_ticks_usec();parsed.clear()
	_build_timing("asset_prepare_release",mark,uuid)
	report("build",done,count)
	return {"scene":scene,"yielded":true}

func _prepare_record_textures(record:Dictionary)->Dictionary:
	if not record.has("terrain_mesh") and not record.has("house_prefab"):return {}
	var requested:=TerrainTextures.requests(record,_terrain_texture_checked)
	if requested.is_empty():return {}
	_thread=Thread.new()
	var done:=completed;var count:=total;var uuid:=str(record.uuid)
	report("textures",done,count);var wait_started:=Time.get_ticks_usec()
	var prepared:Dictionary
	if _thread.start(TerrainTextures.decode.bind(requested,Paths.external_root()),Thread.PRIORITY_LOW)!=OK:
		# Resource freshness must not depend on OS thread availability. The rare
		# synchronous fallback publishes through exactly the same cache scope.
		_thread=null;prepared=TerrainTextures.decode(requested,Paths.external_root())
	else:
		while _thread.is_alive():await get_tree().process_frame
		prepared=_thread.wait_to_finish();_thread=null
	var timing_prefix:="prefab_texture" if record.has("house_prefab") else "terrain_texture"
	_build_timing(timing_prefix+"_wait",wait_started,uuid)
	_build_elapsed(timing_prefix+"_worker",prepared.elapsed_us,uuid)
	for key in requested:_terrain_texture_checked[key]=true
	report("build",done,count)
	return prepared

func _show_overlay() -> void:
	var viewports: Array=[editor.get_viewport()]
	viewports.append_array(editor.find_children("*","Window",true,false))
	for viewport in viewports:
		_gui_modes[viewport]=viewport.gui_disable_input; viewport.gui_disable_input=true
	for container in [editor._canvas,editor._preview]:
		if container==null: continue
		for child in container.get_children():
			if child is SubViewport:
				_viewport_modes[child]=child.render_target_update_mode; child.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_layer=CanvasLayer.new(); _layer.layer=100; add_child(_layer)
	var shade:=ColorRect.new(); shade.color=Color(0.025,.035,.05,.93); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _layer.add_child(shade)
	var center:=CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.add_child(center)
	var box:=VBoxContainer.new(); box.custom_minimum_size=Vector2(500,0); box.add_theme_constant_override("separation",18); center.add_child(box)
	var title:=Label.new(); title.text="正在打开地图"; title.add_theme_font_size_override("font_size",24); box.add_child(title)
	_label=Label.new(); box.add_child(_label)
	_bar=ProgressBar.new(); _bar.custom_minimum_size.y=12; _bar.show_percentage=false; box.add_child(_bar)
	_paint()

func _paint() -> void:
	if not is_instance_valid(_label): return
	var labels:={"read":"读取地图文件","validate":"检查地图和素材","scope":"准备地图素材库","terrain":"准备地形","textures":"准备材质贴图","picking":"准备拾取碰撞","asset":"解析模型素材","build":"构建物件与碰撞","batch":"准备静态渲染批次"}
	var count:=" · %d / %d"%[completed,total] if total>0 else ""
	_label.text="%s\n%s%s · 已用 %.1f 秒"%[path.get_file(),labels.get(phase,phase),count,state().elapsed_seconds]
	_bar.indeterminate=total<=0
	if total>0: _bar.max_value=total; _bar.value=completed

func _process(_dt: float) -> void:
	if active: _paint()

func _restore() -> void:
	for viewport in _gui_modes:
		if is_instance_valid(viewport): viewport.gui_disable_input=_gui_modes[viewport]
	for viewport in _viewport_modes:
		if is_instance_valid(viewport): viewport.render_target_update_mode=_viewport_modes[viewport]
	_gui_modes.clear(); _viewport_modes.clear()
	if is_instance_valid(_layer): _layer.queue_free()

func _complete(ok: bool, message: String) -> void:
	_asset_failures.clear()
	_terrain_texture_checked.clear()
	_terrain_surfaces.clear();_terrain_masks.clear()
	_elapsed=(Time.get_ticks_usec()-_started)/1000000.; active=false; phase="complete" if ok else "failed"
	result={"ok":ok,"pending":false,"job_id":_serial,"path":path,"timings":_timings.duplicate(true)}
	if not ok:
		result.error=message
		if _initial: editor._load_failed=true
	_restore(); editor._status.text=message
	finished.emit(result.duplicate(true))

func _exit_tree() -> void:
	if _thread!=null and _thread.is_started(): _thread.wait_to_finish()
	_restore()
