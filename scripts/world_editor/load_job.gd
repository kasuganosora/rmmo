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
const PreparationQueue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const NativeFootprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const NativePreparation=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const MemoryEstimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
const PrefabPixels=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
const ModelOwnership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
static var parallel_preparation_enabled:=true # HTTP roundtrip + fixed-town 1/2-worker ABBA validated.
static var preparation_worker_limit:=2 # One is a conservative comparison control.
static var native_model_footprints_enabled:=true # Legacy diagnostic; cannot disable native-only consumption.
static var preparation_lanes_enabled:=false # Controlled model/texture scheduling candidate; full-town ABBA before enabling.
static var prepared_model_residency_enabled:=false # Controlled private resident window; full-town comparison before enabling.
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
var _validation:RefCounted
var _asset_paths: Array[String]=[]
var _model_candidates:Dictionary={}
var _cached_asset_candidates:Dictionary={}
var _verified_asset_versions:Dictionary={}
var _preparation:Node
var _model_ownership:Node
var _texture_tasks:Dictionary={}
var _texture_requests:Dictionary={}
var _texture_retry:=0
var _metadata_ready:=false
var _viewport_ready:=false
var _query_ready:=false
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
var loading_batch_budget_us:=16000
var _batch_budget_token:=0
var _budget_batches:Node

func state() -> Dictionary:
	var timing:Dictionary=_timings.duplicate(true)
	if is_instance_valid(_preparation):timing.preparation=_preparation.snapshot()
	if is_instance_valid(_model_ownership):timing.published_models=_model_ownership.report()
	return {"active":active,"job_id":_serial,"phase":phase,"completed":completed,"total":total,"path":path,"elapsed_seconds":(Time.get_ticks_usec()-_started)/1000000. if active else _elapsed,"timings":timing,"result":result.duplicate(true),
		"capabilities":{"metadata_ready":_metadata_ready,"viewport_ready":_viewport_ready,"query_ready":_query_ready,"editable":not active and phase=="complete","policy":"full_document_gate","viewport_scope":"scene_and_batches_prepared_not_first_presented_frame"}}

func start(value: String, initial: bool = false) -> Dictionary:
	if active or editor.saving(): return {"ok":false,"error":"正在读取或保存地图，请等待完成"}
	if not Paths.allowed(value) or value.get_extension().to_lower()!="gltf" or not FileAccess.file_exists(value): return {"ok":false,"error":"地图路径无效或文件不存在"}
	preload("res://scripts/world3d/definition_cache_policy.gd").configure()
	editor._finish_edits()
	path=value; _initial=initial; _started=Time.get_ticks_usec(); _serial+=1
	active=true; result={}; _timings={};_metadata_ready=false;_viewport_ready=false;_query_ready=false
	_asset_failures.clear(); _terrain_surfaces.clear(); _terrain_masks.clear(); _terrain_texture_checked.clear(); report("read")
	_show_overlay()
	_run.call_deferred()
	return {"ok":true,"pending":true,"job_id":_serial,"path":path}

func report(value: String, done: int = 0, count: int = 0) -> void:
	phase=value; completed=done; total=count
	if is_instance_valid(_label) and Time.get_ticks_usec()-_last_paint>50000:
		_paint(); _last_paint=Time.get_ticks_usec()

static func _read(value: String) -> RefCounted:
	var started:=preload("res://scripts/world3d/load_trace.gd").begin("editor.source_read")
	var result:=SourceSnapshot.read_file(value)
	preload("res://scripts/world3d/load_trace.gd").elapsed("editor.source_read",started)
	return result

func _run() -> void:
	var operation:=_serial
	await get_tree().process_frame
	if not _operation_current(operation):return
	_thread=Thread.new()
	var err:=_thread.start(_read.bind(path),Thread.PRIORITY_LOW)
	if err!=OK: _complete(false,"无法启动地图读取："+error_string(err)); return
	Drainer.for_tree(get_tree()).watch(_thread,null)
	while _thread.is_alive():
		await get_tree().process_frame
		if not _operation_current(operation):return
	var prepared: SourceSnapshot=_join_worker()
	report("validate"); await get_tree().process_frame
	if not _operation_current(operation):return
	var validation=preload("res://scripts/world3d/document_open_cursor.gd").new()
	_validation=validation
	var validate_started:=Time.get_ticks_usec()
	validation.begin_snapshot(prepared,true,report)
	while not validation.done:
		validation.advance(_validation_budget_us)
		if not validation.done:
			await get_tree().process_frame
			if not _operation_current(operation):return
	_timings.validation=validation.metrics
	_timings.validate_ms=(Time.get_ticks_usec()-validate_started)/1000.
	preload("res://scripts/world3d/load_trace.gd").elapsed("editor.validate",validate_started)
	var document=validation.document
	if document==null:_validation=null;_complete(false,validation.error);return
	# Only replace the old document after parsing and all validators succeed.
	editor._material_tool.clear_target()
	editor._doc=document; editor._path=path; editor._load_failed=false; editor._dirty=false
	_metadata_ready=true;_timings.metadata_ready_ms=(Time.get_ticks_usec()-_started)/1000.
	preload("res://scripts/net/net.gd").session().world3d_editor_path=path
	editor._selection_tools.ids.clear(); editor._inspector.selection=""
	var release_started:=Time.get_ticks_usec()
	prepared=null;validation=null;_validation=null
	_timings.prepared_release_ms=(Time.get_ticks_usec()-release_started)/1000.
	report("scope"); await get_tree().process_frame
	if not _operation_current(operation):return
	var scope_started:=Time.get_ticks_usec()
	editor._load_asset_scope()
	_begin_asset_lookahead(document.records)
	_timings.asset_scope_ms=(Time.get_ticks_usec()-scope_started)/1000.
	report("build",0,document.records.size()); await get_tree().process_frame
	if not _operation_current(operation):return
	var build_started:=Time.get_ticks_usec()
	_timings.build={"units":{},"yields":0,"max_slice_ms":0.,"max_slice_first_uuid":"","max_slice_last_uuid":""}
	var mark:=Time.get_ticks_usec()
	var begin_steps:Dictionary={}
	editor._begin_rebuild(begin_steps)
	_timings.build.begin_rebuild_steps=begin_steps
	_build_timing("begin_rebuild",mark)
	var context: Array=[document.load_paint_validation,document.load_texture_checks,document.load_box_meshes,document.load_model_signatures,document.load_material_pool,document.load_native_model_identities]
	document.load_paint_validation={}; document.load_texture_checks={}; document.load_box_meshes={}; document.load_model_signatures={}; document.load_material_pool={}; document.load_native_model_identities={}
	mark=Time.get_ticks_usec()
	document.terrain_neighbors=await _prepare_terrain(document.records)
	if not _operation_current(operation):return
	_build_timing("terrain_prepare_wait",mark)
	mark=Time.get_ticks_usec()
	editor._view=document.export_root(); editor.add_child(editor._view)
	_build_timing("export_root",mark)
	var slice:=Time.get_ticks_usec(); var count:=0; var slice_first_uuid:=""
	for record in document.records:
		var uuid:=str(record.get("uuid",""))
		var prepared_asset:Dictionary=await _prepare_asset(record)
		if not _operation_current(operation) or prepared_asset.get("cancelled",false):
			Drainer.dispose_result(prepared_asset);return
		var texture_payload:Dictionary=await _prepare_record_textures(record)
		if not _operation_current(operation) or texture_payload.get("cancelled",false):
			Drainer.dispose_result(prepared_asset);return
		if prepared_asset.get("yielded",false) or not texture_payload.is_empty():slice=Time.get_ticks_usec();slice_first_uuid=""
		if not await _publication_slot():Drainer.dispose_result(prepared_asset);return
		if slice_first_uuid.is_empty():slice_first_uuid=uuid
		var record_started:=Time.get_ticks_usec()
		var image_scope:Dictionary=TerrainTextures.install(texture_payload) if not texture_payload.is_empty() else {}
		var visual: Node3D=document._asset(record,prepared_asset) if record.get("kind")=="asset" else _prepared_mesh(document,record)
		if not texture_payload.is_empty():
			TerrainTextures.restore(image_scope,texture_payload.failed)
			if not texture_payload.failed.is_empty():visual.set_meta("paint_error","材质贴图缺失或损坏")
			var texture_key:String=texture_payload.get("queue_key","")
			if not texture_key.is_empty() and is_instance_valid(_preparation):_preparation.release(texture_key)
			else:texture_payload.clear()
		FrameBudget.charge("publication",record_started)
		_build_timing("asset" if record.get("kind")=="asset" else "mesh",record_started,uuid)
		mark=Time.get_ticks_usec();editor._view.add_child(visual)
		_build_timing("add_child",mark,uuid)
		mark=Time.get_ticks_usec();editor._authoring.decorate(record,visual)
		_build_timing("decorate",mark,uuid)
		mark=Time.get_ticks_usec()
		var picking:Dictionary=await _add_record_bodies(visual,uuid,slice,slice_first_uuid)
		if not _operation_current(operation):return
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
			if not _operation_current(operation):return
	mark=Time.get_ticks_usec()
	document.load_paint_validation=context[0]; document.load_texture_checks=context[1]; document.load_box_meshes=context[2]; document.load_model_signatures=context[3]; document.load_material_pool=context[4]; document.load_native_model_identities=context[5]
	_build_timing("context_restore",mark)
	report("batch"); await get_tree().process_frame
	if not _operation_current(operation):return
	mark=Time.get_ticks_usec()
	_budget_batches=editor._ground_batches
	_batch_budget_token=_budget_batches.begin_loading_budget(loading_batch_budget_us)
	_timings.build.batch_budget_us=_budget_batches.effective_work_budget_usec()
	editor._finish_rebuild()
	_build_timing("finish_rebuild",mark)
	var batch_wait_started:=Time.get_ticks_usec()
	while editor._ground_batches.stats().pending_groups>0:
		await get_tree().process_frame
		if not _operation_current(operation):return
	_viewport_ready=true;_query_ready=true
	_timings.viewport_ready_ms=(Time.get_ticks_usec()-_started)/1000.;_timings.query_ready_ms=_timings.viewport_ready_ms
	_timings.build.batch_wait_ms=(Time.get_ticks_usec()-batch_wait_started)/1000.
	preload("res://scripts/world3d/load_trace.gd").elapsed("editor.batch_wait",batch_wait_started)
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
	var operation:=_serial
	var pending:Array=[visual];var wait_us:=0
	var picking_plan:Dictionary=editor._picking_plan(visual)
	while not pending.is_empty():
		if first_uuid.is_empty():first_uuid=uuid
		var node:Node=pending.pop_back()
		# Reuse the synchronous traversal's exact subtree exclusion rule.
		if not editor._body_node_enabled(node):continue
		if node is MeshInstance3D and node.mesh!=null and picking_plan.has(node.get_instance_id()):
			_build_elapsed("picking_lod_skipped",0,uuid)
		elif node is MeshInstance3D and node.mesh!=null and editor._body_layers(node)!=0:
			var mark:=Time.get_ticks_usec()
			var snapshot:=PickingPreparation.snapshot(node.get_meta("paint_source",node.mesh))
			_build_timing("picking_capture",mark,uuid)
			if not snapshot.is_empty():
				_thread=Thread.new();var prepared:Dictionary
				if _thread.start(PickingPreparation.extract.bind(snapshot.surfaces),Thread.PRIORITY_LOW)==OK:
					Drainer.for_tree(get_tree()).watch(_thread,null)
					_remember_picking_slice(slice,first_uuid,uuid)
					report("picking",completed,total);mark=Time.get_ticks_usec()
					await get_tree().process_frame
					if not _operation_current(operation):return {"cancelled":true}
					while _thread.is_alive():
						await get_tree().process_frame
						if not _operation_current(operation):return {"cancelled":true}
					prepared=_join_worker()
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
					if not _operation_current(operation):return {"cancelled":true}
					wait_us+=Time.get_ticks_usec()-mark;slice=Time.get_ticks_usec();first_uuid=uuid
			mark=Time.get_ticks_usec();editor._add_bodies(node,false,picking_plan)
			_build_timing("picking_publish",mark,uuid)
		# Reverse insertion preserves the former recursive depth-first order.
		var children:=node.get_children()
		for index in range(children.size()-1,-1,-1):pending.append(children[index])
		if Time.get_ticks_usec()-slice>=8000:
			_remember_picking_slice(slice,first_uuid,uuid)
			_timings.build.yields+=1
			var mark:=Time.get_ticks_usec();await get_tree().process_frame
			if not _operation_current(operation):return {"cancelled":true}
			wait_us+=Time.get_ticks_usec()-mark;slice=Time.get_ticks_usec();first_uuid=""
	return {"wait_us":wait_us,"slice":slice,"first_uuid":first_uuid}

func _build_timing(unit:String,started:int,uuid:String="")->void:
	var used:=Time.get_ticks_usec()-started
	_build_elapsed(unit,used,uuid)
	if preload("res://scripts/world3d/load_trace.gd").enabled:preload("res://scripts/world3d/load_trace.gd").elapsed("editor."+unit,started,{"uuid":uuid})

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

static func _parse_native_asset(value:String,content_root:String,candidate:Dictionary,product_generator:String="")->Dictionary:
	# This reader binds the exact product behind the admitted footprint and has
	# no raw fallback. Package identity replaces repeated source authentication.
	var started:=preload("res://scripts/world3d/load_trace.gd").begin("editor.model_parse")
	var parsed:=NativePreparation.read(value,candidate,content_root,Callable(),preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),false,product_generator,true)
	preload("res://scripts/world3d/load_trace.gd").elapsed("editor.model_parse",started,{"path":value,"stage":"compiled_read"})
	return parsed

static func _native_result_action(candidate:Dictionary,parsed:Dictionary)->String:
	# Reader control packets are trusted only in their precise ownership shape.
	# Resource-bearing errors other than the known source replacement stay errors.
	if not parsed.get("error") is int:return "reject"
	if parsed.has("fallback_required"):
		for key:Variant in parsed:
			if key not in ["error","fallback_required","cache_reason","elapsed_us"]:return "reject"
		if parsed.fallback_required is bool and parsed.fallback_required and parsed.error==OK and parsed.get("cache_reason") is String:return "retry"
		return "reject"
	if parsed.has("native_source_retry"):
		for key:Variant in parsed:
			if key not in ["error","packed","compiled","source_digest","compiled_payload_bytes","native_source_retry","cache_reason","elapsed_us","retained_resources"]:return "reject"
		if not parsed.get("retained_resources",[]) is Array:return "reject"
		if parsed.native_source_retry is bool and parsed.native_source_retry and parsed.error==ERR_BUSY and parsed.get("packed") is PackedScene and parsed.get("compiled") is bool and parsed.compiled and parsed.get("source_digest")==candidate.get("source_sha") and NativePreparation.Compiled._sha(candidate.get("source_sha")) and parsed.get("cache_reason")=="candidate_source_changed_after_read":return "retry"
		return "reject"
	if parsed.error!=OK:return "error"
	return "ready" if parsed.get("packed") is PackedScene and parsed.get("compiled") is bool and parsed.compiled and parsed.get("source_digest")==candidate.get("source_sha") and NativePreparation.Compiled._sha(candidate.get("source_sha")) else "reject"

static func _terrain_context(records:Array)->Dictionary:
	var started:=preload("res://scripts/world3d/load_trace.gd").begin("editor.terrain_prepare")
	var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
	context.update(records,true)
	preload("res://scripts/world3d/load_trace.gd").elapsed("editor.terrain_neighbors",started)
	var neighbor_us:=Time.get_ticks_usec()-started
	var geometry:=preload("res://scripts/world_editor/terrain_load_preparation.gd").prepare(records,context)
	preload("res://scripts/world3d/load_trace.gd").elapsed("editor.terrain_prepare",started)
	return {"context":context,"elapsed_us":neighbor_us,"geometry":geometry}

func _prepare_terrain(records:Array)->RefCounted:
	# Busy input guards keep records read-only. Only this new private context is
	# written by the worker; publish it after join, like the runtime map loader.
	var operation:=_serial
	report("terrain");await get_tree().process_frame
	if not _operation_current(operation):return null
	_thread=Thread.new()
	if _thread.start(_terrain_context.bind(records),Thread.PRIORITY_LOW)!=OK:
		_thread=null
		var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
		context.update(records)
		report("build",0,records.size())
		return context
	Drainer.for_tree(get_tree()).watch(_thread,null)
	while _thread.is_alive():
		await get_tree().process_frame
		if not _operation_current(operation):return null
	var prepared:Dictionary=_join_worker()
	_build_elapsed("terrain_neighbors_worker",prepared.elapsed_us)
	_build_elapsed("terrain_arrays_worker",prepared.geometry.arrays_us)
	_build_elapsed("terrain_masks_worker",prepared.geometry.masks_us)
	_timings.build.terrain_geometry={"wall_ms":prepared.geometry.elapsed_us/1000.,"worker_elapsed_sum_ms":prepared.geometry.worker_elapsed_sum_us/1000.}
	_terrain_surfaces=prepared.geometry.surfaces;_terrain_masks=prepared.geometry.masks
	report("build",0,records.size())
	return prepared.context

func _native_model_candidate(asset_path:String,root_:String)->Dictionary:
	return AssetLibrary.native_candidate(asset_path,root_)

func _asset_load_estimate(asset_path:String,root_:String)->Dictionary:
	var native:=_native_model_candidate(asset_path,root_)
	if native.is_empty():return {"candidate":{},"estimate":{},"raw_computed":false}
	return {"candidate":native,"estimate":{"estimated_bytes":int(native.estimated_bytes),"exclusive":bool(native.exclusive)},"raw_computed":false}

func _begin_asset_lookahead(records:Array)->void:
	_clear_asset_lookahead()
	_preparation=PreparationQueue.new();_preparation.worker_limit=clampi(preparation_worker_limit,1,4) if parallel_preparation_enabled else 1
	_preparation.resident_enabled=prepared_model_residency_enabled and native_model_footprints_enabled
	_preparation.lanes_enabled=preparation_lanes_enabled or _preparation.resident_enabled
	if _preparation.resident_enabled:
		_preparation.resident_eligible=_can_reside_native
		_model_ownership=ModelOwnership.for_tree(get_tree())
		if not is_instance_valid(_model_ownership):
			_preparation.resident_enabled=false
			_preparation.lanes_enabled=preparation_lanes_enabled
	_preparation.diagnostics_enabled=preload("res://scripts/world3d/load_trace.gd").enabled
	_preparation.byte_limit=preload("res://scripts/world3d/definition_cache_policy.gd").work_budget(_preparation.byte_limit)
	# LoadJob is also used with lightweight test hosts without an editor ledger.
	# A real editor shares the budget with its concurrent import coordinator.
	if is_instance_valid(editor) and "_shared_preparation_ledger" in editor:
		_preparation.ledger=editor._shared_preparation_ledger
		_preparation.shared_ledger_enabled=true
		_preparation.ledger.worker_limit=_preparation.worker_limit
		_preparation.ledger.byte_limit=_preparation.byte_limit
	add_child(_preparation)
	var seen:Dictionary={};var queued_textures:Dictionary={};var root_:String=Paths.external_root()
	var native_bytes:=0;var legacy_bytes:=0;var legacy_skipped:=0
	var began:=Time.get_ticks_usec()
	for record:Dictionary in records:
		if record.get("kind")=="asset" and not record.has("house_prefab") and not record.has("bridge_mesh"):
			var value:=str(record.get("asset_path",""))
			if not seen.has(value) and Paths.asset_key_allowed(value,root_):
				seen[value]=true;_asset_paths.append(value)
				var plan:=_asset_load_estimate(value,root_)
				var native:Dictionary=plan.candidate
				legacy_skipped+=1
				if native.is_empty():
					_asset_failures[value]=true
					continue
				_model_candidates[value]=native.duplicate(true)
				if AssetLibrary._native_cached(value,native):
					var cached:PackedScene=AssetLibrary._scenes[value]
					_verified_asset_versions[value]={"owner":weakref(cached),"source_digest":native.source_sha}
					continue
				var native_estimate:={"estimated_bytes":int(native.estimated_bytes),"exclusive":bool(native.exclusive),"stage":"compiled_read"}
				native_bytes+=native_estimate.estimated_bytes
				_preparation.enqueue("model:"+value,_parse_native_asset.bind(value,root_,native,""),native_estimate,"model")
		if not record.has("terrain_mesh") and not record.has("house_prefab"):continue
		var requested:=TerrainTextures.requests(record,{})
		for key:String in requested.keys():
			if queued_textures.has(key):requested.erase(key)
			else:queued_textures[key]=true
		if requested.is_empty():continue
		var key:="textures:"+str(record.uuid)
		_texture_tasks[str(record.uuid)]=key;_texture_requests[key]=requested
		_enqueue_textures(key,requested,root_)
	_timings.asset_lookahead={"unique_paths":_asset_paths.size(),"started":0,"consumed":0,"start_failures":0,"ready_on_consume":0,"peak_unconsumed":0,"compiled_hits":0,"compiled_misses":0}
	_timings.asset_lookahead.merge({"native_footprints_enabled":true,"legacy_native_diagnostic":native_model_footprints_enabled,"native_candidates":_model_candidates.size(),"native_retries":0,"native_retry_reasons":{},"planned_model_reservation_bytes":native_bytes,"legacy_model_reservation_bytes":legacy_bytes if legacy_skipped==0 else null,"legacy_model_known_reservation_bytes":legacy_bytes,"legacy_estimate_skipped_paths":legacy_skipped})
	_timings.asset_lookahead.lanes_enabled=_preparation.lanes_enabled
	_timings.asset_lookahead.residency_enabled=_preparation.resident_enabled
	_timings.asset_lookahead.ownership_rejections={}
	_timings.preparation_plan_ms=(Time.get_ticks_usec()-began)/1000.
	_timings.preparation_policy="ordered first-use; published native only; completed packets charged until publication"
	if _preparation.lanes_enabled:
		_timings.preparation_policy=_timings.preparation_policy.replace("ordered first-use","document-order publication")+"; model/texture lane heads with borrowed speculative shares; actual demand first; same global worker/byte/retained window"
	if _preparation.resident_enabled:
		_timings.preparation_policy=_timings.preparation_policy.replace("same global worker/byte/retained window","%d workers; 4 inflight plus 8 private residents share full transient byte envelope; successful cache handoff separately tracks published native envelopes until resource retirement; not a total process memory cap; reader-completion source snapshot"%_preparation.worker_limit)
	_preparation.pump()

func _can_reside_native(key:String,packet:Dictionary)->bool:
	if not key.begins_with("model:"):return false
	if not is_instance_valid(_preparation) or not _preparation.has(key) or _preparation.rows[key].estimate.get("stage")!="compiled_read" or packet.get("cancelled",false):return false
	var candidate:Dictionary=_model_candidates.get(key.trim_prefix("model:"),{})
	return not candidate.is_empty() and _native_result_action(candidate,packet)=="ready"

func _enqueue_textures(key:String,requested:Dictionary,root_:String)->void:
	var plan:=PrefabPixels.estimate(requested,root_,true)
	var bounded:bool=plan.rows.size()==requested.size()
	var estimate:Dictionary={"estimated_bytes":maxi(1,int(plan.estimated_bytes)),"exclusive":false} if bounded else MemoryEstimate._unknown("editor_texture_format")
	estimate.cpu_only=true
	_preparation.enqueue(key,_decode_textures.bind(requested,root_,plan if bounded else {}),estimate,"texture")

static func _decode_textures(requested:Dictionary,root_:String,plan:Dictionary)->Dictionary:
	if plan.is_empty():return TerrainTextures.decode(requested,root_)
	# Editor files may change in place. Reuse the admitted snapshot decoder with
	# content identity, without flipping the process-wide game package policy.
	var packet:=PrefabPixels.prepare(requested,plan,root_,null,true,{},false,true)
	if not packet.error.is_empty():return {"images":{},"failed":requested.keys(),"error":packet.error}
	return {"images":packet.images,"failed":[],"source_proof":packet.sources}

func _clear_asset_lookahead()->void:
	if is_instance_valid(_preparation):
		_timings.preparation=_preparation.snapshot()
		_preparation.cancel();_preparation.queue_free()
	_preparation=null;_asset_paths.clear();_model_candidates.clear();_cached_asset_candidates.clear();_verified_asset_versions.clear();_texture_tasks.clear();_texture_requests.clear();_texture_retry=0
	if is_instance_valid(_model_ownership):_timings.published_models=_model_ownership.report()

func _operation_current(operation:int)->bool:return is_inside_tree() and operation==_serial

func _queue_current(queue:Variant,operation:int)->bool:
	return _operation_current(operation) and is_instance_valid(queue) and queue==_preparation and not queue.cancelled

func _publication_slot()->bool:
	var operation:=_serial
	while _operation_current(operation) and FrameBudget.allowance("publication",8000,true)<=0:
		await get_tree().process_frame
	return _operation_current(operation)

func _prepare_asset(record:Dictionary)->Dictionary:
	if record.get("kind")!="asset" or record.has("house_prefab") or record.has("bridge_mesh"):return {}
	var asset_path:=str(record.get("asset_path",""))
	if _asset_failures.has(asset_path):return {"scene":null}
	var key:="model:"+asset_path
	if not is_instance_valid(_preparation) or not _preparation.has(key) or _preparation.rows[key].state=="done":
		var verified:Dictionary=_verified_asset_versions.get(asset_path,{})
		var owner:PackedScene=verified.owner.get_ref() if not verified.is_empty() else null
		return {"template":owner} if owner!=null and AssetLibrary._scenes.get(asset_path)==owner and AssetLibrary.has_cached_scene(asset_path,verified.source_digest) else {"scene":null}
	var queue:Node=_preparation;var operation:=_serial
	var done:=completed;var count:=total;var uuid:=str(record.get("uuid",""))
	report("asset",done,count)
	var wait_started:=Time.get_ticks_usec();var yielded:=false
	if queue.is_ready(key):_timings.asset_lookahead.ready_on_consume+=1
	queue.demand(key)
	while not queue.is_ready(key):
		yielded=true;await get_tree().process_frame
		if not _queue_current(queue,operation):return {"cancelled":true,"scene":null}
	var parsed:Dictionary=queue.acquire(key)
	var worker_us:int=int(parsed.get("elapsed_us",0))
	var candidate:Dictionary=_model_candidates.get(asset_path,{})
	if _native_result_action(candidate,parsed)!="ready":parsed.error=ERR_INVALID_DATA
	_timings.asset_lookahead.consumed+=1
	_timings.asset_lookahead.started+=1
	if parsed.get("start_failed",false):_timings.asset_lookahead.start_failures+=1
	_timings.asset_lookahead.peak_unconsumed=_preparation.metrics.peak_unconsumed
	_timings.asset_lookahead["compiled_hits" if parsed.get("error",FAILED)==OK else "compiled_misses"]+=1
	_build_timing("asset_wait",wait_started,uuid)
	_build_elapsed("asset_parse_worker",worker_us,uuid)
	if not await _publication_slot() or not _queue_current(queue,operation):return {"cancelled":true,"scene":null}
	var mark:=Time.get_ticks_usec();var scene:Node3D
	var source_digest:String=str(parsed.get("source_digest",""))
	var already_cached:bool=parsed.get("error",FAILED)==OK and AssetLibrary._native_cached(asset_path,candidate)
	var cached_template:PackedScene=AssetLibrary._scenes.get(asset_path) if already_cached else null
	if already_cached:_verified_asset_versions[asset_path]={"source_digest":source_digest,"owner":weakref(cached_template)}
	if not already_cached:
		if parsed.get("error",FAILED)==OK:
			if queue.resident_enabled:
				scene=_publish_owned_native(asset_path,parsed,int(queue.rows[key].estimate.estimated_bytes))
			elif AssetLibrary.cache_packed(asset_path,parsed.packed,source_digest,candidate):scene=AssetLibrary._instantiate(parsed.packed)
		if scene==null:_asset_failures[asset_path]=true
		else:_verified_asset_versions[asset_path]={"source_digest":source_digest,"owner":weakref(AssetLibrary._scenes[asset_path])}
	_build_timing("asset_prepare_main",mark,uuid)
	FrameBudget.charge("publication",mark)
	mark=Time.get_ticks_usec();queue.release(key)
	_build_timing("asset_prepare_release",mark,uuid)
	report("build",done,count)
	# Texture preparation/publication can yield again in _run. Pin the validated
	# allocation through that gap instead of resolving the mutable global cache.
	return {"template":cached_template,"yielded":yielded} if already_cached else {"scene":scene,"yielded":yielded}

func _publish_owned_native(asset_path:String,packet:Dictionary,envelope_bytes:int)->Node3D:
	# No await between receipt, cache assignment and adoption. The queue retains
	# its complete private lease throughout; release occurs only in the caller.
	var receipt:Dictionary=_model_ownership.preflight(_model_candidates.get(asset_path,{}),packet,envelope_bytes)
	if not receipt.get("ok",false):
		_timings.asset_lookahead.ownership_rejections[asset_path]=receipt.get("reason","preflight_failed")
		return null
	if not AssetLibrary.cache_packed(asset_path,packet.packed,str(packet.get("source_digest","")),_model_candidates.get(asset_path,{})):return null
	var adopted:Dictionary=_model_ownership.adopt(receipt.ticket)
	if not adopted.get("ok",false):
		# Roll back only this allocation, never a replacement owned by another
		# operation. No instance exists yet; packet disposal still owns the lease.
		if AssetLibrary._scenes.get(asset_path)==packet.packed:AssetLibrary._scenes.erase(asset_path)
		_timings.asset_lookahead.ownership_rejections[asset_path]=adopted.get("reason","adoption_failed")
		return null
	return AssetLibrary._instantiate(packet.packed)

func _prepare_record_textures(record:Dictionary)->Dictionary:
	if not record.has("terrain_mesh") and not record.has("house_prefab"):return {}
	var requested:=TerrainTextures.requests(record,_terrain_texture_checked)
	if requested.is_empty():return {}
	var complete_requested:Dictionary=requested.duplicate()
	var queue:Node=_preparation;var operation:=_serial
	if not _queue_current(queue,operation):return {"cancelled":true}
	var done:=completed;var count:=total;var uuid:=str(record.uuid)
	report("textures",done,count);var wait_started:=Time.get_ticks_usec()
	var key:String=_texture_tasks.get(uuid,"")
	var prepared:Dictionary={}
	if not key.is_empty() and is_instance_valid(_preparation) and _preparation.has(key):
		_preparation.demand(key)
		while not _preparation.is_ready(key):
			await get_tree().process_frame
			if not _queue_current(queue,operation):return {"cancelled":true}
		prepared=_preparation.acquire(key)
		# A prior record can have evicted a shared texture from the real LRU. Do
		# not silently accept incomplete pixels because they were planned earlier.
		for cached:String in _texture_requests[key]:requested.erase(cached)
		if not requested.is_empty():
			# Re-admit the complete request. Dropping this joined packet first
			# prevents an exclusive repair waiting on its own retained pixels.
			_preparation.release(key);prepared={}
			requested=TerrainTextures.requests(record,_terrain_texture_checked)
	if prepared.is_empty():
		_texture_retry+=1;key="textures:repair:%d"%_texture_retry
		_enqueue_textures(key,requested,Paths.external_root());_preparation.demand(key)
		while not _preparation.is_ready(key):
			await get_tree().process_frame
			if not _queue_current(queue,operation):return {"cancelled":true}
		prepared=_preparation.acquire(key)
	if not prepared.has("images"):prepared.images={};prepared.failed=complete_requested.keys()
	if not prepared.has("failed"):prepared.failed=[]
	prepared.queue_key=key
	var timing_prefix:="prefab_texture" if record.has("house_prefab") else "terrain_texture"
	_build_timing(timing_prefix+"_wait",wait_started,uuid)
	_build_elapsed(timing_prefix+"_worker",prepared.elapsed_us,uuid)
	for image_key:String in prepared.images:_terrain_texture_checked[image_key]=true
	for image_key:String in prepared.failed:_terrain_texture_checked[image_key]=true
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
	_restore_batch_budget()
	_clear_asset_lookahead()
	_asset_failures.clear()
	_terrain_texture_checked.clear()
	_terrain_surfaces.clear();_terrain_masks.clear()
	_elapsed=(Time.get_ticks_usec()-_started)/1000000.; active=false; phase="complete" if ok else "failed"
	_timings.definition_cache=preload("res://scripts/world3d/definition_cache_policy.gd").snapshot()
	result={"ok":ok,"pending":false,"job_id":_serial,"path":path,"timings":_timings.duplicate(true)}
	if not ok:
		result.error=message
		if _initial: editor._load_failed=true
	_restore(); editor._report_result(result,message,"打开地图")
	finished.emit(result.duplicate(true))

func _exit_tree() -> void:
	_serial+=1;active=false
	_restore_batch_budget()
	_clear_asset_lookahead()
	_abandon_worker(_thread);_thread=null
	# The generic cursor's destructor joins its reader for synchronous callers.
	# This asynchronous editor operation explicitly transfers that private reader
	# before dropping the cursor, so closing during reference hydration is safe.
	if _validation!=null and _validation._reference_thread!=null:
		_abandon_worker(_validation._reference_thread);_validation._reference_thread=null
	_validation=null
	_restore()

func _abandon_worker(worker:Thread)->void:
	if worker!=null and worker.is_started():
		var owner:Node=get_tree().root.get_node_or_null(Drainer.NODE_NAME)
		if is_instance_valid(owner) and owner.is_inside_tree():
			# Also accepts a fixture-injected private worker not started here.
			var watched:=false
			for job:Dictionary in owner.jobs:
				if job.worker==worker:watched=true;break
			if not watched:owner.watch(worker,null)
			owner.abandon(worker)
		else:Drainer.drain_shutdown(worker)

func _join_worker()->Variant:
	var worker:Thread=_thread
	var prepared:Variant=worker.wait_to_finish()
	Drainer.for_tree(get_tree()).forget(worker);_thread=null
	return prepared

func _restore_batch_budget()->void:
	if is_instance_valid(_budget_batches) and _batch_budget_token!=0:_budget_batches.end_loading_budget(_batch_budget_token)
	_batch_budget_token=0;_budget_batches=null
