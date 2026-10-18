extends Node
const Trace=preload("res://scripts/world3d/load_trace.gd")
const CrossMapPrefetch=preload("res://scripts/world3d/cross_map_prefetch.gd")
const OwnershipProof=preload("res://scripts/world3d/dependency_index_proof.gd")
## Parse and prepare eligible private static graphs off-tree. Publish on main.
signal finished(scene: Node, path: String, error: String)
signal progress(stage: String, done: int, total: int)
static var initial_model_workers_override:=0 # Benchmark only; zero uses production policy.
static var entry_pipeline_enabled:=true # Benchmark control; production overlaps private preparation.
static var cold_index_rebuild_enabled:=true # Probe control; recover near-first on the same cold visit.
static var initial_cpu_capture_enabled:=true # Probe retains monolithic stream adoption.
static var initial_static_specs_enabled:=true # Probe keeps the legacy on-tree adoption.
static var startup_render_context_enabled:=true # Probe isolates late renderer initialization.
static var startup_render_context_frames:=2 # Zero is the continuous-draw diagnostic control.
var _startup_viewport:SubViewport
var _startup_draw_count:=0
var _record_meta := {}
var _asset_states := {}
var _model_preparation := preload("res://scripts/world3d/model_parse_preparation.gd").new()
var _source_hash_preparation := preload("res://scripts/world3d/model_source_hashes.gd").new()
var _building := false
var _prepared: Node
var _thread: Thread
var _cache_thread: Thread
var _mesh_cache_thread:Thread
var _mesh_read_thread:Thread
var _mesh_cache_data:Dictionary={}
var _mesh_cache_selection:=""
var _mesh_cache_allowed:=true
var _source_digest:=""
var _generator_key:=""
var _model_signatures:Dictionary={}
var _needed_textures:Dictionary={}
var _decoded_images:Dictionary={}
var _texture_thread:Thread
var _terrain_thread:Thread
var _terrain_context:RefCounted
var _surface_arrays:Dictionary={}
var _index_thread:Thread
var _document: GLTFDocument
var _state: GLTFState
var _error := OK
var _path := ""
var _content_root := ""
var _cancelled := false
var _profile: Dictionary = {}
var _prefab_worker_count:int=4
var _source_snapshot:RefCounted
var _reference_dependencies:Dictionary={}
var _full_reference_dependencies:Dictionary={} # Cold selection retains the fully verified publication closure.
var _failure_reason:=""
var near_first:=false
var background_preload:=false # Private GPU preload; no authority/global scene publication.
var _private_assets:Dictionary={}
var _asset_cursor:RefCounted
var source_prefetch:CrossMapPrefetch.Packet
var _entry_origin:=Vector3(0,.9,4)
var _entry_origin_explicit:=false
var _deferred_assets:Array=[]
var _deferred_ids:Dictionary={}
var _record_order:Dictionary={}
var _prepared_asset_paths:Dictionary={}
var _dependency_index:Dictionary={}
var _dependency_proof:OwnershipProof
var _author_reference_meta:Dictionary={}
var _selected_record_indices:Array=[]
var _build_dependency_index:=false
var _entry_plan:Dictionary={}
var _collision_core_deferred_ids:Array[String]=[] # Scheduling hint only; never collision authority.
var _early_models:=preload("res://scripts/world3d/initial_model_prefetch.gd").new()
var _early_deferred:Node
var _draining_deferred:Node


static func resolve_path(requested: String) -> String:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader.resolve_path") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not requested.is_empty():
		return requested
	var Paths = preload("res://scripts/world3d/map_paths.gd")
	var yard := Paths.cache_directory("p4_yard")
	var inn := Paths.cache_directory("p4_inn")
	if yard.is_empty() or inn.is_empty():
		return ""
	var path := yard.path_join("map.gltf")
	var inn_path := inn.path_join("map.gltf")
	var Document = preload("res://scripts/world3d/world_document.gd")
	if not FileAccess.file_exists(path) and Document.sample_yard(inn_path).save(path) != OK:
		return ""
	if not FileAccess.file_exists(inn_path) and Document.make_inn(path).save(inn_path) != OK:
		return ""
	return path


func start(path: String,origin:Variant=null) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader.start") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_model_preparation.prepare_static_scenes=true
	if background_preload:_prefab_worker_count=1
	preload("res://scripts/world3d/definition_cache_policy.gd").configure()
	_path = path
	_collision_core_deferred_ids.clear()
	var session:=get_node_or_null("/root/GameSession")
	_entry_origin_explicit=origin is Vector3
	if origin is Vector3:_entry_origin=origin
	elif session!=null:_entry_origin=session.world3d_spawn
	# Snapshot the configured root on the main thread; parsing must not read autoload nodes.
	_content_root = preload("res://scripts/world3d/map_paths.gd").external_root()
	_prepare_startup_render_context()
	_thread = Thread.new()
	_error = _thread.start(_parse)
	if _error != OK:
		_thread = null
		call_deferred("_finish_error", "无法启动地图读取")

func _prepare_startup_render_context()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._prepare_startup_render_context") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not startup_render_context_enabled or background_preload or DisplayServer.get_name()=="headless":return
	var viewport:=get_viewport()
	if viewport==null or (not viewport.disable_3d and viewport.get_camera_3d()!=null):return
	# Forward+ enables rendering feature groups on its first 3D scene. A late
	# camera makes that first setup process every imported material together.
	# Keep a private empty scene active while imports arrive, behind the normal
	# loading UI. Match rendering features; never attach the map or run gameplay.
	_startup_viewport=SubViewport.new();_startup_viewport.name="LoadingRenderContext"
	_startup_viewport.own_world_3d=true;_startup_viewport.size=Vector2i(16,16)
	_startup_viewport.use_taa=viewport.use_taa;_startup_viewport.msaa_3d=viewport.msaa_3d
	_startup_viewport.screen_space_aa=viewport.screen_space_aa
	_startup_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(_startup_viewport)
	var camera:=Camera3D.new();_startup_viewport.add_child(camera);camera.current=true
	RenderingServer.frame_post_draw.connect(_startup_context_drawn)
	_profile.startup_render_context=true

func _startup_context_drawn()->void:
	if not is_instance_valid(_startup_viewport):return
	_startup_draw_count+=1
	if startup_render_context_frames>0 and _startup_draw_count>=startup_render_context_frames:
		_startup_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		RenderingServer.frame_post_draw.disconnect(_startup_context_drawn)


func cancel() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader.cancel") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_cancelled = true
	_early_models.cancel()
	_source_hash_preparation.cancel()
	_model_preparation.cancel()


func _parse() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._parse") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var trace_started:=Trace.begin("game.parse")
	_parse_inner()
	# Hydration, validation and preflight can all exit before consuming the hint.
	# Keep any rejected GPU resources alive until the main thread can release them.
	_early_models.abandon()
	Trace.elapsed("game.parse",trace_started)

func _parse_inner() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._parse_inner") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var started:=Time.get_ticks_usec()
	# Native maps are reference documents. The glTF locator nodes are not their
	# runtime visuals. Resolve and verify definitions before any cache is used.
	if _path.get_extension().to_lower() == "gltf":
		if background_preload and (source_prefetch==null or source_prefetch.path!=_path or not source_prefetch.snapshot.matches_disk()):_error=ERR_SKIP;return
		if source_prefetch!=null and source_prefetch.path==_path and source_prefetch.snapshot.matches_disk():
			_source_snapshot=source_prefetch.snapshot;_profile.source_prefetch_hit=true
		else:_source_snapshot=preload("res://scripts/world3d/document_source_snapshot.gd").read_file(_path)
		_profile.source_read_us=Time.get_ticks_usec()-started
		Trace.elapsed("game.source_read",started)
		if not _source_snapshot.error.is_empty():
			_error=ERR_INVALID_DATA;_failure_reason=_source_snapshot.error;return
		var data:Variant=_source_snapshot._data
		_source_digest=_source_snapshot._signature
		var Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
		var native:int=Cursor.native_root(data)
		if native<0 and Cursor.claims_native(data):
			_error=ERR_INVALID_DATA;_failure_reason="旧版或不支持的地图格式，需要显式迁移后才能进入游戏";return
		if native<0:
			_document=GLTFDocument.new();_state=GLTFState.new()
			preload("res://scripts/world3d/runtime_probe_controls.gd").configure_gltf(_state)
			_error=_document.append_from_file(_path,_state,0,_path.get_base_dir());return
		# Metadata envelopes previously held hydrated records using map SHA only.
		# Bypass them until their format also proves definition resource integrity.
		_profile.metadata_cache_hit=false
		_profile.metadata_cache_bypassed="reference_integrity"
		_author_reference_meta=data.nodes[native].extras
		var requested_extra:Dictionary=_author_reference_meta
		if not _entry_origin_explicit and _entry_origin==Vector3(0,.9,4) and requested_extra.get("spawn") is Array and requested_extra.spawn.size()>=3:
			_entry_origin=Vector3(requested_extra.spawn[0],requested_extra.spawn[1],requested_extra.spawn[2])
		if near_first:
			var directory_started:=Time.get_ticks_usec()
			var directory:Dictionary=preload("res://scripts/world3d/map_dependency_index.gd").read_for_loading(_path,_content_root,_source_digest)
			_profile.reference_index_read_us=Time.get_ticks_usec()-directory_started
			_profile.reference_index_hit=directory.ok
			_profile.reference_index_reason=directory.get("reason","")
			if directory.ok:
				var candidate:Dictionary=directory.index
				_entry_plan=preload("res://scripts/world3d/entry_plan.gd").create(_entry_origin)
				var selection:Dictionary=preload("res://scripts/world3d/map_dependency_index.gd").select(candidate,[_entry_plan.core_clip])
				if selection.ok:
					selection=_collision_first_selection(candidate,selection)
					_dependency_index=candidate;requested_extra=selection.extras;_selected_record_indices=selection.record_indices
					_dependency_proof=directory.proof
					if entry_pipeline_enabled and not background_preload:
						var hints:Dictionary={}
						for index:int in selection.record_indices:
							var model_path:String=candidate.rows[index].asset_path
							if not model_path.is_empty():hints[model_path]=true
						_profile.initial_models_prefetched=_early_models.start(hints.keys(),_model_preparation,_initial_model_workers(),_content_root)
						_profile.initial_models_prefetch_started_us=_early_models.started_us
					_register_reference_pending(selection.deferred_entries)
					_profile.reference_selected_count=selection.selected_count;_profile.reference_deferred_count=selection.deferred_count
					_profile.reference_selected_groups=selection.selected_groups.size()
					_profile.entry_core_cell=[_entry_plan.cell.x,_entry_plan.cell.y]
					_profile.entry_conservative_global_records=candidate.rows.filter(func(row):return row.classification=="global").size()
				else:_entry_plan.clear()
			_build_dependency_index=_dependency_index.is_empty()
		for i in _author_reference_meta.rmmo_records.size():_record_order[_author_reference_meta.rmmo_records[i].uuid]=i
		var hydrate_started:=Time.get_ticks_usec()
		var restored:Dictionary={}
		if background_preload and (_dependency_index.is_empty() or source_prefetch.selected!=_selected_record_indices or source_prefetch.restored.get("dependencies",{})!=requested_extra.rmmo_resource_dependencies):_error=ERR_SKIP;return
		if source_prefetch!=null and source_prefetch.snapshot==_source_snapshot and source_prefetch.selected==_selected_record_indices and source_prefetch.restored.get("dependencies",{})==requested_extra.rmmo_resource_dependencies:
			if preload("res://scripts/world3d/map_resource_store.gd").verify_dependencies(source_prefetch.restored.dependencies,_path,_content_root,1 if background_preload else 4):
				restored=source_prefetch.restored;_profile.hydration_prefetch_hit=true
		if restored.is_empty():restored=Cursor.hydrate_references(requested_extra,_path,_content_root,1 if background_preload else 4)
		if background_preload:
			var gpu_plan:=preload("res://scripts/world3d/target_scene_prefetch.gd").plan(restored.get("extras",{}).get("rmmo_records",[]),_content_root,_path,_source_digest,restored.get("dependencies",{}))
			if gpu_plan.is_empty() or gpu_plan.files!=source_prefetch.scene_plan.files or not preload("res://scripts/world3d/target_scene_prefetch.gd").verify(gpu_plan.files,_content_root):_error=ERR_SKIP;return
		source_prefetch=null
		_profile.hydrate_us=Time.get_ticks_usec()-hydrate_started
		_profile.reference_read=restored.get("read_profile",{})
		Trace.elapsed("game.hydrate",hydrate_started)
		if not restored.get("ok",false):
			_error=ERR_INVALID_DATA;_failure_reason=str(restored.get("reason","引用资源无法读取"));return
		_reference_dependencies=restored.dependencies
		var extra:Dictionary=restored.extras
		# These identities are trusted only after read_records verified every
		# referenced byte and the complete closure. Instance state cannot override
		# surface_paint. Never derive validation shortcuts from an unchecked header.
		var compact:Array=requested_extra.rmmo_records
		var verified_paint_ids:Array=[]
		if compact.size()!=extra.rmmo_records.size():
			_error=ERR_INVALID_DATA;_failure_reason="引用物件顺序无效";return
		for i in compact.size():
			if compact[i].uuid!=extra.rmmo_records[i].uuid:
				_error=ERR_INVALID_DATA;_failure_reason="引用物件顺序无效";return
			verified_paint_ids.append(compact[i].rmmo_ref.sha256)
		_profile.paint_identity_count=verified_paint_ids.size()
		_profile.parse_us=Time.get_ticks_usec()-started
		var validate_started:=Time.get_ticks_usec()
		if not _valid_records(extra,verified_paint_ids):
			_error=ERR_INVALID_DATA;_failure_reason="引用地图的物件或元数据无效";return
		_profile.validate_us=Time.get_ticks_usec()-validate_started
		Trace.elapsed("game.validate",validate_started)
		var integrity_started:=Time.get_ticks_usec()
		if not _reference_integrity():
			_error=ERR_BUSY;_failure_reason="读取期间地图或引用资源已改变";return
		_profile.initial_integrity_us=Time.get_ticks_usec()-integrity_started
		_profile.reference_index_rebuilt_before_models=false
		if near_first and _dependency_index.is_empty() and cold_index_rebuild_enabled:
			if entry_pipeline_enabled and not background_preload:
				var cold_hints:Array=_cold_model_hints(extra.rmmo_records)
				if not cold_hints.is_empty():
					_profile.initial_models_prefetched=_early_models.start(cold_hints,_model_preparation,_initial_model_workers(),_content_root)
					if _profile.initial_models_prefetched:
						_early_models.allow_validated_raw()
						_profile.initial_models_prefetch_started_us=_early_models.started_us
						_profile.cold_models_overlap_index=true
			# A missing/changed derived directory must not force this visit to
			# prepare all models, textures and geometry just to help the next visit.
			# Full hydration, global ownership and source validation above remain
			# mandatory; only verified CPU data may create this new directory.
			var rebuilt:Dictionary=_rebuild_initial_reference_selection(extra,verified_paint_ids)
			_profile.reference_index_rebuild_reason=rebuilt.get("reason","")
			if _cancelled:_error=ERR_SKIP;return
			if rebuilt.ok:
				extra=rebuilt.extras;requested_extra=rebuilt.requested_extras
				_profile.reference_index_rebuilt_before_models=true
			# Directory I/O and the second, selected validation may race a writer.
			# Recheck even on ordinary directory failure before starting any image
			# or model preparation. Retain the full cold closure through publication.
			var rebuild_integrity_started:=Time.get_ticks_usec()
			var rebuild_integrity:bool=_reference_integrity()
			_profile.reference_index_rebuild_integrity_us=Time.get_ticks_usec()-rebuild_integrity_started
			if not rebuild_integrity:
				_error=ERR_BUSY;_failure_reason="重建区块目录期间地图或引用资源已改变";return
			if rebuilt.ok and entry_pipeline_enabled and not background_preload and not _profile.get("initial_models_prefetched",false):
				var hints:Dictionary={}
				for index:int in _selected_record_indices:
					var model_path:String=_dependency_index.rows[index].asset_path
					if not model_path.is_empty():hints[model_path]=true
				_profile.initial_models_prefetched=_early_models.start(hints.keys(),_model_preparation,_initial_model_workers(),_content_root)
				_profile.initial_models_prefetch_started_us=_early_models.started_us
		elif near_first and _dependency_index.is_empty():_profile.reference_index_rebuild_reason="disabled"
		_record_meta=extra
		# Validated, operation-local requests may decode beside terrain/model work.
		# This preserves all source hashes and does not trust old metadata hints.
		_start_texture_prefetch(_needed_textures.values())
		_generator_key=preload("res://scripts/world3d/runtime_mesh_cache.gd").generator_key()
		# A selected closure has a separate namespace and authenticated envelope;
		# it can never borrow the complete map's cooked UUID or terrain closure.
		if not _dependency_index.is_empty():
			_mesh_cache_selection=preload("res://scripts/world3d/runtime_mesh_cache.gd").selection_identity(_selected_record_indices,requested_extra.rmmo_records)
			_mesh_cache_allowed=not _mesh_cache_selection.is_empty()
			_profile.mesh_cache_scope="selected_reference_closure";_profile.mesh_cache_selection=_mesh_cache_selection
		else:_profile.mesh_cache_scope="complete_map"
		if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:
			# Diagnostic tangents/materials must never enter the normal cooked
			# namespace. Cache policy stays identical within each fresh-process arm.
			_mesh_cache_selection=(_mesh_cache_selection+"|diagnostic-no-map-textures-v1").sha256_text()
			_profile.mesh_cache_scope="diagnostic_without_map_textures"
		if preload("res://scripts/world3d/runtime_probe_controls.gd").white_materials:
			_mesh_cache_selection=(_mesh_cache_selection+"|diagnostic-white-materials-v1").sha256_text()
			_profile.mesh_cache_scope="diagnostic_white_materials"
		if _mesh_cache_allowed:
			_profile.mesh_cache_path=preload("res://scripts/world3d/runtime_mesh_cache.gd").cache_path(_path,_mesh_cache_selection)
			_mesh_read_thread=Thread.new()
			var read_cache:=preload("res://scripts/world3d/runtime_mesh_cache.gd").read.bind(_path,_source_digest,_generator_key,null,_mesh_cache_selection)
			if background_preload or _mesh_read_thread.start(read_cache)!=OK:
				_mesh_read_thread=null;_mesh_cache_data=read_cache.call()
		else:_profile.mesh_cache_bypassed="invalid_selected_identity"
		_prepare_record_assets()
		_profile.parser_total_us=Time.get_ticks_usec()-started
		return

	_document = GLTFDocument.new()
	_state = GLTFState.new()
	preload("res://scripts/world3d/runtime_probe_controls.gd").configure_gltf(_state)
	_error = _document.append_from_file(_path, _state, 0, _path.get_base_dir())

func _reference_integrity() -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._reference_integrity") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Hash resources first; the map snapshot observation is the last operation
	# before publication, so a writer during resource verification is detected.
	var began:=Time.get_ticks_usec()
	var dependencies:Dictionary=_full_reference_dependencies if not _full_reference_dependencies.is_empty() else _reference_dependencies
	var valid:bool=_source_snapshot!=null and load("res://scripts/world3d/map_resource_store.gd").verify_dependencies(dependencies,_path,_content_root,1 if background_preload else 4) and _source_snapshot.matches_disk()
	Trace.elapsed("game.reference_integrity",began)
	return valid

# Conservative hints only after full snapshot validation. The selected path
# set and source identities must still match before any prepared scene is used.
func _cold_model_hints(records:Array)->Array:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._cold_model_hints") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var plan:Dictionary=preload("res://scripts/world3d/entry_plan.gd").create(_entry_origin)
	if plan.is_empty():return []
	var manifests:Dictionary={};var paths:Dictionary={}
	var Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
	for record:Dictionary in records:
		if record.get("kind")!="asset" or record.has("house_prefab"):continue
		var path:String=record.get("asset_path","")
		if not preload("res://scripts/world3d/map_paths.gd").allowed(path,_content_root):return []
		if not manifests.has(path):manifests[path]=Manifest.read(path)
		var placed:Dictionary=Manifest.apply_record(manifests[path],record)
		if not placed.get("known",false):return []
		if plan.core_clip.intersects(placed.world_bounds):paths[path]=true
	return paths.keys()

## Build/read are CPU-only and issue the same immutable ownership proof as the
## warm path. Adopt only after selected validation; otherwise retain full input.
func _rebuild_initial_reference_selection(full:Dictionary,paint_ids:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._rebuild_initial_reference_selection") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var Index=preload("res://scripts/world3d/map_dependency_index.gd")
	var plan:Dictionary=preload("res://scripts/world3d/entry_plan.gd").create(_entry_origin)
	if plan.is_empty():return {"ok":false,"reason":"invalid_entry_plan"}
	if _cancelled:return {"ok":false,"reason":"cancelled"}
	var build_started:=Time.get_ticks_usec()
	var built:Dictionary=Index.build(_path,_content_root,full.rmmo_records,_source_digest)
	_profile.reference_index_rebuild_build_us=Time.get_ticks_usec()-build_started
	if not built.ok:return {"ok":false,"reason":"build:"+str(built.get("reason","unknown"))}
	built.clear() # The disk reader below owns the only directory eligible for proof.
	if _cancelled:return {"ok":false,"reason":"cancelled"}
	var read_started:=Time.get_ticks_usec()
	var directory:Dictionary=Index.read_for_loading(_path,_content_root,_source_digest)
	_profile.reference_index_rebuild_read_us=Time.get_ticks_usec()-read_started
	if not directory.ok:return {"ok":false,"reason":"read:"+str(directory.get("reason","unknown"))}
	var candidate:Dictionary=directory.index
	var selection:Dictionary=Index.select(candidate,[plan.core_clip])
	if not selection.ok:return {"ok":false,"reason":"select:"+str(selection.get("reason","unknown"))}
	selection=_collision_first_selection(candidate,selection)
	var records:Array=[];var selected_paint_ids:Array=[]
	for index:int in selection.record_indices:
		if index<0 or index>=full.rmmo_records.size() or index>=paint_ids.size():return {"ok":false,"reason":"selected_index_out_of_range"}
		if full.rmmo_records[index].uuid!=candidate.rows[index].uuid:return {"ok":false,"reason":"selected_identity_mismatch"}
		records.append(full.rmmo_records[index]);selected_paint_ids.append(paint_ids[index])
	var selected_extra:Dictionary=selection.extras.duplicate()
	selected_extra.rmmo_records=records
	# _valid_records owns _needed_textures and its validation diagnostics. Its
	# second pass removes far-only image requests as well as checking exact
	# selected ownership; no full-author or sealed directory data is mutated.
	var full_textures:Dictionary=_needed_textures.duplicate()
	var full_validation:Dictionary={}
	for key:String in ["prefab_decode_us","ownership_us","validation_parts"]:full_validation[key]=_profile.get(key)
	_dependency_index=candidate;_dependency_proof=directory.proof
	var validate_started:=Time.get_ticks_usec()
	var selected_valid:bool=_valid_records(selected_extra,selected_paint_ids)
	_profile.reference_index_rebuild_select_validate_us=Time.get_ticks_usec()-validate_started
	if not selected_valid or _cancelled:
		_dependency_index={};_dependency_proof=null
		_needed_textures=full_textures
		for key:String in full_validation:_profile[key]=full_validation[key]
		return {"ok":false,"reason":"cancelled" if _cancelled else "selected_validation_failed"}
	_profile.reference_full_validation=full_validation
	_profile.reference_full_paint_identity_count=paint_ids.size()
	_profile.paint_identity_count=selected_paint_ids.size()
	_full_reference_dependencies=_reference_dependencies
	_reference_dependencies=selection.dependencies.duplicate()
	_profile.reference_publication_integrity_scope="complete_cold_reference_closure"
	_entry_plan=plan;_selected_record_indices=selection.record_indices
	_register_reference_pending(selection.deferred_entries)
	_profile.reference_selected_count=selection.selected_count;_profile.reference_deferred_count=selection.deferred_count
	_profile.reference_selected_groups=selection.selected_groups.size()
	_profile.entry_core_cell=[plan.cell.x,plan.cell.y]
	_profile.entry_conservative_global_records=candidate.rows.filter(func(row):return row.classification=="global").size()
	_build_dependency_index=false # Never rebuild a complete directory from this subset.
	return {"ok":true,"reason":"","extras":selected_extra,"requested_extras":selection.extras}

func _collision_first_selection(index:Dictionary,selection:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._collision_first_selection") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Worker-only hint selection. A directory is not a readiness proof: the
	# independent loader must validate all sources, otherwise ordinary Deferred
	# imports this exact record. Terrain and atomic building groups stay in core.
	_collision_core_deferred_ids.clear()
	_profile.collision_first_core_deferred=0
	_profile.collision_first_core_deferred_ids=[]
	if not preload("res://scripts/world3d/deferred_asset_loader.gd").collision_first_enabled:return selection
	var candidates:Dictionary={};var selected:Array=[];var records:Array=[];var dependencies:Dictionary={}
	var landing:=Rect2(_entry_origin.x-2,_entry_origin.z-2,4,4)
	var moved:=0
	for at:int in selection.record_indices:
		var row:Dictionary=index.rows[at];var compact:Dictionary=index.extras.rmmo_records[at]
		var eligible:bool=row.reason=="model_accessor_bounds" and row.bounds_known and row.group_id.is_empty() and row.owner_keys.is_empty() and not row.asset_path.is_empty()
		if eligible:
			var bounds:AABB=row.bounds
			# Unknown imported interiors/supports at the actual landing retain full
			# visuals as well as collision, even without authored building ownership.
			eligible=not landing.intersects(Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z),true)
		if eligible:
			if not candidates.has(row.asset_path):candidates[row.asset_path]=not preload("res://scripts/world3d/collision_asset_descriptor.gd").candidate(row.asset_path,_content_root).is_empty()
			eligible=candidates[row.asset_path]
		if eligible:
			selection.deferred_indices.append(at);selection.deferred_compact_records.append(compact)
			selection.deferred_entries.append({"record_index":at,"compact_record":compact,"bounds":row.bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":row.group_id,"memory_bytes":row.memory_bytes})
			_collision_core_deferred_ids.append(str(compact.uuid))
			moved+=1
		else:
			selected.append(at);records.append(compact);dependencies[compact.rmmo_ref.uri]=compact.rmmo_ref.sha256
	selection.record_indices=selected;selection.compact_records=records;selection.dependencies=dependencies
	selection.extras.rmmo_records=records;selection.extras.rmmo_resource_dependencies=dependencies
	selection.selected_count=selected.size();selection.deferred_count=selection.deferred_indices.size()
	_profile.collision_first_core_deferred=moved
	_profile.collision_first_core_deferred_ids=_collision_core_deferred_ids.slice(0,32)
	return selection

func _register_reference_pending(entries:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._register_reference_pending") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var estimates:Dictionary={}
	for entry:Dictionary in entries:
		var key:String=preload("res://scripts/world3d/deferred_asset_loader.gd").reference_path(entry)
		var memory:Dictionary={"estimated_bytes":int(entry.get("memory_bytes",65536)),"exclusive":false,"known":true}
		var manifest:Dictionary={}
		if not entry.asset_path.is_empty():
			if not estimates.has(entry.asset_path):estimates[entry.asset_path]=preload("res://scripts/world3d/asset_memory_estimate.gd").estimate(entry.asset_path)
			memory=estimates[entry.asset_path]
			manifest=_dependency_index.models.get(entry.asset_path,{})
		_deferred_assets.append({"record":entry.compact_record,"path":key,"bounds":entry.bounds,"digest":"","memory":memory,"manifest":manifest,"draw_order":int(entry.record_index)*65536,"reference_entry":entry,"reference_prepared":false,"native_reference":entry.asset_path.is_empty(),"group_id":entry.group_id})
		_deferred_ids[entry.compact_record.uuid]=true


func _prepare_record_assets()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._prepare_record_assets") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var trace_started:=Time.get_ticks_usec()
	_prepare_record_assets_inner()
	Trace.elapsed("game.asset_preparation",trace_started)

func _initial_model_workers()->int:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._initial_model_workers") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if background_preload:return 1
	return clampi(OS.get_processor_count()/2,1,4) if initial_model_workers_override<=0 else clampi(initial_model_workers_override,1,4)

func _prepare_record_assets_inner()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._prepare_record_assets_inner") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Each model worker returns geometry bound to its own final full-source SHA.
	# Do not hash every source in a separate barrier before those same reads.
	var source_scan_started:=Time.get_ticks_usec()
	var paths:Array=[];var first_ids:Dictionary={};var manifests:Dictionary={};var memory_estimates:Dictionary={}
	var signature_paths:Dictionary={}
	if not _entry_origin_explicit and _entry_origin==Vector3(0,.9,4) and _record_meta.get("spawn") is Array and _record_meta.spawn.size()>=3:
		_entry_origin=Vector3(_record_meta.spawn[0],_record_meta.spawn[1],_record_meta.spawn[2])
	var near_clip:AABB=_entry_plan.get("core_clip",AABB(Vector3(_entry_origin.x-96,-100000,_entry_origin.z-96),Vector3(192,200000,192)))
	if _record_order.is_empty():
		for i in _record_meta.rmmo_records.size():_record_order[_record_meta.rmmo_records[i].uuid]=i
	for record:Dictionary in _record_meta.rmmo_records:
		if record.has("fortification_art"):
			var path:String=record.fortification_art.asset_path
			signature_paths[path]=true
		if record.get("kind")!="asset" or record.has("house_prefab"):continue
		var path:String=str(record.get("asset_path",""))
		if near_first:
			var Manifest=preload("res://scripts/world3d/asset_bounds_manifest.gd")
			if not manifests.has(path):manifests[path]=Manifest.read(path)
			var footprint:Dictionary=Manifest.apply_record(manifests[path],record)
			if footprint.get("known",false) and not near_clip.intersects(footprint.world_bounds):
				if not memory_estimates.has(path):memory_estimates[path]=preload("res://scripts/world3d/asset_memory_estimate.gd").estimate(path)
				# Large distant files are hashed on their preparation worker. The
				# source JSON bounds snapshot is checked again before import; full
				# navigation caches stay disabled until every source hash is known.
				_deferred_assets.append({"record":record,"path":path,"bounds":footprint.world_bounds,"digest":"","memory":memory_estimates[path],"manifest":{"json_sha256":manifests[path].json_sha256,"file_length":manifests[path].file_length},"draw_order":int(_record_order[record.uuid])*65536})
				_deferred_ids[record.uuid]=true
				continue
		signature_paths[path]=true
		if not first_ids.has(path):paths.append(path);first_ids[path]=record.uuid
	_profile.deferred_asset_instances=_deferred_assets.size();_profile.initial_asset_paths=paths.size()
	_profile.source_scan_us=Time.get_ticks_usec()-source_scan_started
	Trace.elapsed("game.source_scan",source_scan_started,{"required_models":signature_paths.size()})
	if _cancelled:_error=ERR_SKIP;return
	# Cheap complete-input preflight still rejects missing/out-of-root sources
	# before starting speculative work; it grants no content identity.
	for path:String in signature_paths:
		if not preload("res://scripts/world3d/map_paths.gd").allowed(path,_content_root):
			_error=ERR_INVALID_PARAMETER;_failure_reason="模型来源超出资源根目录："+path;return
		if not FileAccess.file_exists(path):
			_error=ERR_FILE_NOT_FOUND;_failure_reason="模型来源不存在："+path;return
	# Joining the cache reader here blocks only this parser worker, never UI.
	# The candidate is speculative until every prepared model's identity matches.
	# Nothing from it is published before the model transaction completes below.
	var cache_started:=Time.get_ticks_usec()
	if _mesh_read_thread!=null:
		_mesh_cache_data=_mesh_read_thread.wait_to_finish();_mesh_read_thread=null
	_profile.mesh_cache_read_wait_us=Time.get_ticks_usec()-cache_started
	Trace.elapsed("game.mesh_cache_wait",cache_started)
	_profile.mesh_cache_candidate=not _mesh_cache_data.is_empty()
	var terrain_snapshot:Variant=_mesh_cache_data.get("terrain_context")
	_terrain_thread=Thread.new()
	var prepare_terrain:=func(build_geometry:bool,snapshot:Variant):
		var began:=Trace.begin("game.terrain_prepare")
		var cached=preload("res://scripts/world3d/terrain_context_cache.gd").restore(snapshot,_record_meta.rmmo_records)
		if cached!=null:return {"context":cached,"surfaces":{},"elapsed":Time.get_ticks_usec()-began,"cache_hit":true}
		var mask_buckets:Array=[[],[],[],[]];var mask_workers:Array[Thread]=[];var masks:Dictionary={};var mask_at:=0
		for record:Dictionary in _record_meta.rmmo_records:
			if record.has("terrain_regions"):mask_buckets[mask_at%4].append(record);mask_at+=1
		for bucket:Array in mask_buckets:
			var worker:=Thread.new()
			var task:=func():
				var result:Dictionary={}
				for record:Dictionary in bucket:result[record.uuid]=preload("res://scripts/world3d/terrain_regions.gd").mask(record)
				return result
			if not background_preload and not bucket.is_empty() and worker.start(task)==OK:mask_workers.append(worker)
			else:masks.merge(task.call())
		var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
		var neighbor_started:=Time.get_ticks_usec()
		context.update(_record_meta.rmmo_records,not background_preload)
		Trace.elapsed("game.terrain_neighbors",neighbor_started)
		# Coverage masks are CPU images; build them off the scene thread too.
		var buckets:Array=[[],[],[],[]];var at:=0;var workers:Array[Thread]=[]
		for record:Dictionary in _record_meta.rmmo_records:
			if build_geometry and (record.has("terrain_volume") or record.has("terrain_mesh") or record.has("road_mesh") or record.has("rock_bank")):
				buckets[at%4].append({"record":record,"image":null,"surfaces":[]});at+=1
		for bucket:Array in buckets:
			if bucket.is_empty():continue
			var worker:=Thread.new()
			var task:=func():
				var worker_started:=Time.get_ticks_usec()
				for entry:Dictionary in bucket:
					var record:Dictionary=entry.record
					if build_geometry:
						if record.has("terrain_volume"):entry.surfaces=preload("res://scripts/world3d/terrain_volume.gd").arrays(record)
						elif record.has("terrain_mesh"):entry.surfaces=preload("res://scripts/world3d/terrain_surface.gd").arrays(record,context.data.get(record.uuid,{}))
						elif record.has("road_mesh"):entry.surfaces=preload("res://scripts/world3d/road_surface.gd").arrays(record)
						elif record.has("rock_bank"):entry.surfaces=preload("res://scripts/world3d/rock_bank_mesh.gd").arrays(record)
				Trace.elapsed("game.terrain_geometry_worker",worker_started,{"records":bucket.size()})
			if not background_preload and worker.start(task)==OK:workers.append(worker)
			else:task.call()
		for worker:Thread in workers:worker.wait_to_finish()
		for worker:Thread in mask_workers:masks.merge(worker.wait_to_finish())
		var surfaces:Dictionary={}
		for bucket:Array in buckets:
			for entry:Dictionary in bucket:
				if not entry.surfaces.is_empty():surfaces[entry.record.uuid]=entry.surfaces
		for id:String in masks:
			if not context.data.has(id):context.data[id]={}
			context.data[id].region_mask=masks[id]
		Trace.elapsed("game.terrain_prepare",began)
		return {"context":context,"surfaces":surfaces,"elapsed":Time.get_ticks_usec()-began,"cache_hit":false}
	var initial_terrain:=prepare_terrain.bind(_mesh_cache_data.is_empty(),terrain_snapshot)
	if background_preload or _terrain_thread.start(initial_terrain)!=OK:
		_terrain_thread=null
		var terrain:Dictionary=initial_terrain.call()
		_terrain_context=terrain.context;_surface_arrays=terrain.surfaces;_profile.terrain_context_worker_us=terrain.elapsed
		_profile.terrain_context_cache_hit=terrain.cache_hit
	_profile.asset_parses=[];_profile.asset_parse_us=0
	# A verified compiled candidate checks source SHA after native read; a raw
	# fallback checks before/after parsing. Both return that geometry's identity.
	# Keep headroom for reference/texture preparation and the main thread. The
	# unchanged byte/exclusive admission still limits simultaneous large models.
	var hint:Dictionary=_early_models.take(paths)
	_profile.initial_models_prefetch_accepted=hint.accepted
	if not hint.accepted and _model_preparation.is_cancelled() and not _cancelled:
		# A hint mismatch is a cache miss, not a malformed map. Its resources have
		# already been released on main before starting another admission ledger.
		var previous:RefCounted=_model_preparation
		_model_preparation=preload("res://scripts/world3d/model_parse_preparation.gd").new()
		_model_preparation.inflight_byte_limit=previous.inflight_byte_limit
		_model_preparation.memory_estimator=previous.memory_estimator
		_model_preparation.cache_reader=previous.cache_reader
		_model_preparation.eligibility_checker=previous.eligibility_checker
		_model_preparation.prepare_static_scenes=previous.prepare_static_scenes
	if _cancelled:_model_preparation.cancel()
	var prepared:Dictionary=hint.result if hint.accepted else _model_preparation.run(paths,Callable(),_initial_model_workers(),Callable(),_content_root)
	_profile.asset_parse_wall_us=prepared.elapsed_us
	_profile.asset_admission_details=prepared.get("admission_profile",{})
	_profile.asset_admission={}
	for key:String in ["worker_limit","native_cache_hits","native_cache_misses","inflight_budget_bytes","peak_inflight_estimate_bytes","peak_inflight_jobs","initial_required_resident_estimate_bytes","result_resident_estimate_bytes","peak_live_estimate_bytes","retired_native_estimate_bytes","inflight_reserved_at_return","inflight_jobs_at_return"]:
		_profile.asset_admission[key]=prepared.get(key,0)
	for key:String in ["parallel_eligible_count","parallel_batches","eligibility_us","fallback_count"]:
		_profile["asset_"+key]=prepared.get(key,0)
	for entry:Dictionary in prepared.entries:
		_profile.asset_parse_us+=entry.elapsed_us
		_profile.asset_parses.append({"path":entry.path,"uuid":first_ids[entry.path],"elapsed_us":entry.elapsed_us,"error":entry.error,"compiled":entry.get("compiled",false)})
		# Even a failed transaction can contain successful sibling resources.
		# Retain them until the loader's main-thread cleanup, never drop on parser.
		_asset_states[entry.path]=entry
	_error=prepared.error
	if _error!=OK:return # The coordinator has joined every worker before returning.
	if _profile.get("cold_models_overlap_index",false):
		# Early preparation may have finished while the cold directory was still
		# rebuilding. Re-observe on this parser worker before accepting its output;
		# all sibling resources above already have a main-thread cleanup owner.
		var recheck_started:=Time.get_ticks_usec()
		for entry:Dictionary in prepared.entries:
			if not preload("res://scripts/world3d/map_paths.gd").allowed(entry.path,_content_root) or FileAccess.get_sha256(entry.path)!=entry.get("source_digest","") or not preload("res://scripts/world3d/map_paths.gd").allowed(entry.path,_content_root):
				_error=ERR_BUSY;_failure_reason="模型来源在目录重建期间已改变："+str(entry.path);return
		_profile.cold_model_identity_recheck_us=Time.get_ticks_usec()-recheck_started
	_model_signatures={}
	for entry:Dictionary in prepared.entries:
		if not first_ids.has(entry.path) or _model_signatures.has(entry.path) or not preload("res://scripts/world3d/compiled_asset_cache.gd")._sha(entry.get("source_digest")):
			_error=ERR_INVALID_DATA;_failure_reason="模型准备缺少有效来源身份："+str(entry.path);return
		_model_signatures[entry.path]=entry.source_digest;signature_paths.erase(entry.path)
	if _model_signatures.size()!=paths.size():
		_error=ERR_INVALID_DATA;_failure_reason="模型准备结果不完整";return
	# Non-model dependencies (e.g. fortification art) have no model transaction.
	# They retain their complete source verification before cache acceptance.
	var source_hash_started:=Time.get_ticks_usec()
	var hashes:Dictionary=_source_hash_preparation.run(signature_paths.keys(),_content_root,1 if background_preload else 4)
	_profile.source_hash_us=hashes.elapsed_us;_profile.source_hash_profile=hashes
	_profile.model_source_identity_mode="verified_prepared_result"
	_profile.model_source_hash_barrier_avoided=paths.size()
	Trace.elapsed("game.source_hash",source_hash_started,{"models":signature_paths.size(),"peak_active":hashes.get("peak_active",0)})
	if hashes.error!=OK:
		_model_signatures.clear();_error=hashes.error;_failure_reason="模型来源校验失败："+str(hashes.get("reason",""))+" "+str(hashes.get("error_path",""));return
	_model_signatures.merge(hashes.signatures)
	if _cancelled:_error=ERR_SKIP;return
	if not _mesh_cache_data.is_empty() and not preload("res://scripts/world3d/runtime_mesh_cache.gd").models_match(_mesh_cache_data,_model_signatures):
		_mesh_cache_data.clear();_profile.mesh_cache_candidate=false
		# A changed model invalidates the speculative cooked selection. Join its
		# terrain task before discarding output and rebuilding; never race captured
		# flags or fall back to main-thread geometry generation.
		if _terrain_thread!=null:_terrain_thread.wait_to_finish()
		_terrain_context=null;_surface_arrays.clear();_profile.terrain_identity_restarts=1
		_terrain_thread=Thread.new()
		var fresh_terrain:=prepare_terrain.bind(true,null)
		if background_preload or _terrain_thread.start(fresh_terrain)!=OK:
			_terrain_thread=null
			var terrain:Dictionary=fresh_terrain.call()
			_terrain_context=terrain.context;_surface_arrays=terrain.surfaces;_profile.terrain_context_worker_us=terrain.elapsed
			_profile.terrain_context_cache_hit=terrain.cache_hit
	for entry:Dictionary in prepared.entries:_asset_states[entry.path]=entry
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return
	var texture_wait_started:=Time.get_ticks_usec()
	var decoded:Dictionary=_texture_thread.wait_to_finish() if _texture_thread!=null else _decode_textures(_needed_textures)
	Trace.elapsed("game.texture_join_wait",texture_wait_started)
	_texture_thread=null
	_decoded_images=decoded.images
	_profile.texture_decode_us=decoded.elapsed
	# The dependency hint is optional. Full validated records remain authoritative.
	for key:String in _needed_textures:
		if not _decoded_images.has(key):
			var source:Array=_needed_textures[key]
			var image:Image=preload("res://scripts/world3d/runtime_texture_cache.gd").image(source[0],source[1])
			if image==null:_error=ERR_FILE_CORRUPT;return
			_decoded_images[key]=image


func _finish_terrain()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._finish_terrain") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if _terrain_thread==null:return
	var wait_started:=Time.get_ticks_usec()
	while _terrain_thread.is_alive():await get_tree().process_frame
	var terrain:Dictionary=_terrain_thread.wait_to_finish();_terrain_thread=null
	_profile.terrain_join_wait_us=int(_profile.get("terrain_join_wait_us",0))+Time.get_ticks_usec()-wait_started
	Trace.elapsed("game.terrain_join_wait",wait_started)
	_terrain_context=terrain.context;_surface_arrays=terrain.surfaces;_profile.terrain_context_worker_us=terrain.elapsed
	_profile.terrain_context_cache_hit=terrain.cache_hit



func _start_texture_prefetch(dependencies:Variant)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._start_texture_prefetch") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return
	if background_preload:return
	if not dependencies is Array or dependencies.is_empty():return
	var requested:Dictionary={}
	for item in dependencies:
		if not item is Array or item.size()!=2 or not item[0] is String or not item[1] is bool:return
		if item[0].get_extension().to_lower() not in ["png","jpg","jpeg","webp"] or not preload("res://scripts/world3d/map_paths.gd").allowed(item[0],_content_root) or not FileAccess.file_exists(item[0]):return
		requested[item[0]+("|flip_y" if item[1] else "")]=item
	_texture_thread=Thread.new()
	if _texture_thread.start(_decode_textures.bind(requested))!=OK:_texture_thread=null

func _decode_textures(requested:Dictionary)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._decode_textures") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var began:=Trace.begin("game.texture_decode")
	var buckets:Array=[[],[],[]];var at:=0
	for key:String in requested:
		buckets[at%3].append({"key":key,"source":requested[key],"image":null});at+=1
	var workers:Array=[]
	for bucket:Array in buckets:
		var worker:=Thread.new()
		var task:=func():
			for entry:Dictionary in bucket:entry.image=preload("res://scripts/world3d/runtime_texture_cache.gd").image(entry.source[0],entry.source[1])
		if not background_preload and worker.start(task)==OK:workers.append(worker)
		else:task.call()
	for worker:Thread in workers:worker.wait_to_finish()
	var images:Dictionary={}
	for bucket:Array in buckets:
		for entry:Dictionary in bucket:
			if entry.image!=null:images[entry.key]=entry.image
	Trace.elapsed("game.texture_decode",began,{"requests":requested.size()})
	return {"images":images,"elapsed":Time.get_ticks_usec()-began}


func _process(_delta: float) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._process") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	preload("res://scripts/world3d/scene_preparation_pump.gd").pump(1000 if background_preload else preload("res://scripts/world3d/scene_preparation_pump.gd").loading_budget_usec)
	_early_models.drain_discarded()
	if not _cancelled and is_instance_valid(_early_deferred):_early_deferred.pump_entry_prefetch()
	if _building or (_thread==null and _mesh_read_thread==null) or (_thread!=null and _thread.is_alive()):
		return
	if _thread!=null:
		_thread.wait_to_finish();_thread=null
		_release_retired_models()
	if _mesh_read_thread!=null:
		if _mesh_read_thread.is_alive():return
		_mesh_cache_data=_mesh_read_thread.wait_to_finish();_mesh_read_thread=null
	if _mesh_cache_data.get("models",{})!=_model_signatures:_mesh_cache_data.clear()
	if _cancelled:
		_building=true
		_retire()
		return
	if _error != OK:
		_finish_error(_failure_reason if not _failure_reason.is_empty() else "地图读取失败：%s" % error_string(_error))
		return
	if not _record_meta.is_empty():
		_building = true
		_start_entry_prefetch()
		_build_records()
		return
	if _can_stream_static():
		_building = true
		_build_static()
		return
	var scene := preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(_document, _state)
	finished.emit(scene, _path, "" if scene != null else "地图场景生成失败")
	queue_free()


func _release_retired_models()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._release_retired_models") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Called on main after the parser/coordinator has joined every worker. These
	# Rejected native versions retire here; a consumable private scene remains
	# owned by its entry until cache_scene packs and safely disposes it on main.
	var has_retired:=false
	for entry:Dictionary in _asset_states.values():
		if not entry.get("retained_resources",[]).is_empty():has_retired=true;break
	if not has_retired:return
	var Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
	Drainer.synchronize_transfer()
	for entry:Dictionary in _asset_states.values():
		if entry.get("retained_resources",[]).is_empty():continue
		var retired:Dictionary={"retained_resources":entry.get("retained_resources",[])}
		Drainer.dispose_result(retired)
		entry.erase("retained_resources")
	Drainer.synchronize_transfer()


func _retire()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._retire") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	await _drain_entry_prefetch()
	while (_cache_thread!=null and _cache_thread.is_alive()) or (_mesh_cache_thread!=null and _mesh_cache_thread.is_alive()) or (_terrain_thread!=null and _terrain_thread.is_alive()) or (_texture_thread!=null and _texture_thread.is_alive()):
		await get_tree().process_frame
	queue_free()


func _finish_error(message: String) -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._finish_error") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_building=true
	# Failure can immediately resume the old world's queue. All private safety
	# workers must relinquish their reservations before that rollback signal.
	await _drain_entry_prefetch()
	if not _cancelled:
		finished.emit(null, _path, message)
	_retire()


func _exit_tree() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._exit_tree") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if RenderingServer.frame_post_draw.is_connected(_startup_context_drawn):RenderingServer.frame_post_draw.disconnect(_startup_context_drawn)
	_cancelled=true
	_early_models.cancel()
	_model_preparation.cancel()
	if is_instance_valid(_early_deferred):
		_early_deferred.shutdown();_early_deferred.free();_early_deferred=null
	if is_instance_valid(_draining_deferred):
		_draining_deferred.shutdown();_draining_deferred.free();_draining_deferred=null
	if is_instance_valid(_prepared): _prepared.free()
	if _asset_cursor!=null:_asset_cursor.dispose();_asset_cursor=null
	if _thread != null:
		preload("res://scripts/world3d/asset_worker_drainer.gd").drain_shutdown(_thread)
	_early_models.drain_discarded()
	if _cache_thread != null:
		_cache_thread.wait_to_finish()
	if _mesh_cache_thread!=null:_mesh_cache_thread.wait_to_finish()
	if _mesh_read_thread!=null:_mesh_read_thread.wait_to_finish()
	if _texture_thread!=null:_texture_thread.wait_to_finish()
	if _terrain_thread!=null:_terrain_thread.wait_to_finish()
	if _index_thread!=null:_index_thread.wait_to_finish()
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	for entry:Dictionary in _asset_states.values():preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(entry)
	_asset_states.clear()
	# Drop only this loader's unconsumed handoff images (e.g. height maps or
	# materials already resident); never pin them for the rest of the session.
	var images:Dictionary=preload("res://scripts/world3d/surface_materials.gd").prepared_images
	for key in _decoded_images:
		if images.get(key)==_decoded_images[key]:images.erase(key)
	_decoded_images.clear()

func _new_deferred()->Node:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._new_deferred") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var deferred:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	deferred._prepared_paths=_prepared_asset_paths.duplicate()
	deferred.source_signatures=_model_signatures.duplicate()
	if not _dependency_index.is_empty():deferred.configure_references(_dependency_index,_path,_content_root,_dependency_proof)
	deferred.pending=_deferred_assets
	return deferred

func _start_entry_prefetch()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._start_entry_prefetch") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if background_preload or not entry_pipeline_enabled or _entry_plan.is_empty() or _deferred_assets.is_empty():return
	_early_deferred=_new_deferred()
	# Initial model workers have all joined. Their retained output is still
	# charged separately: it is transferred into Assets during main construction.
	_early_deferred.profile.initial_retained_estimate_bytes=_profile.get("asset_admission",{}).get("result_resident_estimate_bytes",0)
	if not _early_deferred.begin_entry_prefetch(get_tree(),_entry_plan.safety_clip,_model_signatures):
		_early_deferred.free();_early_deferred=null;return
	# Reuse the eventual map-owned collision queue. Only CPU descriptors/faces
	# prepare here; the map's Store is created after actual scene-tree adoption.
	# Keep the actual core deferrals ahead of the existing safety-ring queue.
	# Deferred intersects this hint with its unchanged supported safety entries;
	# neither candidate presence nor this ordering grants a readiness proof.
	_early_deferred.begin_collision_prefetch(self,_entry_plan.safety_clip,_collision_core_deferred_ids)
	_profile.entry_prefetch_started_us=Time.get_ticks_usec()
	_early_deferred.pump_entry_prefetch()

func _drain_entry_prefetch()->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._drain_entry_prefetch") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not is_instance_valid(_early_deferred):return
	var deferred:Node=_early_deferred
	# Stop process-frame pumping before awaiting the outstanding workers.
	_early_deferred=null
	_draining_deferred=deferred
	await deferred.quiesce()
	if is_instance_valid(deferred):deferred.free()
	_draining_deferred=null


func _valid_records(extra: Dictionary, immutable_paint_ids:Array=[]) -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._valid_records") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	_needed_textures.clear()
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(extra): return false
	var Format=preload("res://scripts/world3d/world_location.gd")
	if extra.get("rmmo_format", "") != Format.FORMAT or extra.get("rmmo_version") != Format.FORMAT_VERSION or extra.get("rmmo_storage") != Format.STORAGE: return false
	if not preload("res://scripts/world3d/environment_settings.gd").valid(extra): return false
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(extra): return false
	var records: Variant = extra.get("rmmo_records")
	if not records is Array: return false
	if not immutable_paint_ids.is_empty() and immutable_paint_ids.size()!=records.size():return false
	var ids:Dictionary={};var buckets:Array=[[],[],[],[]];var workers:Array[Thread]=[];var results:Array=[]
	for i in records.size():
		var record:Variant=records[i]
		if not record is Dictionary or str(record.get("uuid", "")).is_empty() or ids.has(record.uuid):return false
		ids[record.uuid]=true
		buckets[i%4].append({"record":record,"paint_id":null if immutable_paint_ids.is_empty() else immutable_paint_ids[i]})
	# Each validator owns its caches and dependency map. It reads the same
	# immutable snapshot as prefab decoding, without waiting for decompression.
	for bucket:Array in buckets:
		var worker:=Thread.new()
		if not background_preload and worker.start(_validate_record_batch.bind(bucket))==OK:workers.append(worker)
		else:results.append(_validate_record_batch(bucket))
	var prefab_started:=Time.get_ticks_usec()
	_decode_prefabs(records,_prefab_worker_count)
	_profile.prefab_decode_us=Time.get_ticks_usec()-prefab_started
	var ownership_started:=Time.get_ticks_usec()
	var ownership_ok:bool
	if _dependency_index.is_empty():ownership_ok=preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(extra,records)
	else:ownership_ok=preload("res://scripts/world3d/map_dependency_index.gd").validate_selected(_dependency_index,records,_content_root,_dependency_proof).ok
	_profile.ownership_us=Time.get_ticks_usec()-ownership_started
	for worker:Thread in workers:results.append(worker.wait_to_finish())
	var totals:Dictionary={"terrain":0,"paint":0,"dependencies":0,"other":0};var valid_:bool=ownership_ok
	for result:Dictionary in results:
		valid_=valid_ and result.ok
		if not result.ok:continue
		_needed_textures.merge(result.textures,true)
		for key:String in totals:totals[key]+=result.timings[key]
	_profile.validation_parts=totals
	return valid_


func _validate_record_batch(entries:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._validate_record_batch") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var validation_parts:Dictionary={"terrain":0,"paint":0,"dependencies":0,"other":0}
	var textures:Dictionary={}
	var material_validation: Dictionary={}; var checked_paths: Dictionary={};var checked_definitions:Dictionary={}
	var checked_paints:Dictionary={}
	for entry:Dictionary in entries:
		var part_started:=Time.get_ticks_usec()
		var record:Dictionary=entry.record
		if not preload("res://scripts/world3d/wind_response.gd").valid(record): return {"ok":false}
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return {"ok":false}
		if not preload("res://scripts/world3d/river_material_data.gd").valid(record): return {"ok":false}
		validation_parts.terrain+=Time.get_ticks_usec()-part_started;part_started=Time.get_ticks_usec()
		var paint_id:Variant=entry.paint_id
		if not preload("res://scripts/world3d/surface_materials.gd").valid(record,false,_content_root,material_validation,paint_id): return {"ok":false}
		validation_parts.paint+=Time.get_ticks_usec()-part_started;part_started=Time.get_ticks_usec()
		var include_paint:bool=paint_id==null or not checked_paints.has(paint_id)
		if paint_id!=null:checked_paints[paint_id]=true
		for definition in preload("res://scripts/world3d/surface_materials.gd").definitions(record,include_paint):
			if checked_definitions.has(definition):continue
			checked_definitions[definition]=true
			if not preload("res://scripts/world3d/surface_materials.gd").material_valid(definition,false,_content_root,material_validation): return {"ok":false}
			for field in preload("res://scripts/world3d/surface_materials.gd").MAP_FIELDS:
				var path: String=definition.get(field, "")
				if not path.is_empty():
					var flip:bool=field=="normal_path" and definition.get("normal_format", "opengl")=="directx"
					textures[path+("|flip_y" if flip else "")]=[path,flip]
				if not path.is_empty() and not checked_paths.has(path):
					if not preload("res://scripts/world3d/map_paths.gd").allowed(path,_content_root) or not FileAccess.file_exists(path): return {"ok":false}
					checked_paths[path]=true
		validation_parts.dependencies+=Time.get_ticks_usec()-part_started;part_started=Time.get_ticks_usec()
		if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record, false, _content_root): return {"ok":false}
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record, _content_root): return {"ok":false}
		for field in ["position", "rotation", "size"]:
			var values: Variant = record.get(field)
			if not values is Array or values.size() != 3: return {"ok":false}
			for value in values:
				if not (value is int or value is float) or not is_finite(float(value)): return {"ok":false}
		validation_parts.other+=Time.get_ticks_usec()-part_started
	return {"ok":true,"textures":textures,"timings":validation_parts}


func _decode_prefabs(records:Array,worker_count:int=4)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._decode_prefabs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Only immutable plain data is decompressed here. GPU/material creation still
	# runs on the scene thread; authoritative validation below is never skipped.
	var unique:Dictionary={};var buckets:Array=[];var workers:Array[Thread]=[]
	for i in clampi(worker_count,1,16):buckets.append({"values":[],"bytes":0})
	for r in records:
		if not r is Dictionary or not r.get("house_prefab") is Dictionary:continue
		var value:Dictionary=r.house_prefab
		if not value.get("sha256") is String or unique.has(value.sha256):continue
		unique[value.sha256]=true
		var smallest:int=0
		for i in buckets.size():
			if buckets[i].bytes<buckets[smallest].bytes:smallest=i
		buckets[smallest].values.append(value);buckets[smallest].bytes+=int(value.get("length",0))
	for bucket in buckets:
		if bucket.values.is_empty():continue
		var worker:=Thread.new()
		var job:=func():
			for value:Dictionary in bucket.values:preload("res://scripts/world3d/house_prefab.gd").warm(value)
		if not background_preload and worker.start(job)==OK:workers.append(worker)
		else:job.call()
	for worker in workers:worker.wait_to_finish()


func _prepare_static_asset_specs(root:Node3D,instance:Node,parts:Array,library:Array)->bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._prepare_static_asset_specs") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	# Match ordinary adoption exactly, while the graph is still private: avoid
	# attaching thousands of disposable render instances to a live scenario.
	if root.transform!=Transform3D.IDENTITY:return true
	preload("res://scripts/world3d/scene_integrity.gd").prepare(instance)
	if instance.has_meta("native_graph_preserved") or parts.any(func(node):return node.has_meta("native_visual")):return true
	var Stream=preload("res://scripts/world3d/world_stream.gd")
	var slice_started:=Time.get_ticks_usec();var elapsed:=0;var slices:=0
	var budget:=2000 if background_preload else 16000
	var compiled_holders:Dictionary={}
	for i:int in parts.size():
		var node:MeshInstance3D=parts[i]
		var pose:=Transform3D.IDENTITY
		var chain:Array[Node3D]=[]
		var parent:Node=node
		while parent!=root:
			if parent.has_meta("_compiled_resource_owner"):compiled_holders[parent.get_instance_id()]=weakref(parent)
			if parent is Node3D:chain.append(parent)
			parent=parent.get_parent()
		for at:int in range(chain.size()-1,-1,-1):pose=pose*chain[at].transform
		var spec:Dictionary=Stream._spec(node)
		spec.transform=pose;spec.position=pose.origin
		var bounds:AABB=pose*node.get_aabb()
		spec.chunk=Stream.chunk_key(pose.origin);spec.chunk_min=Stream.chunk_key(bounds.position);spec.chunk_max=Stream.chunk_key(bounds.end)
		preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
		spec.uuid=str(spec.extras.get("uuid",str(root.get_path_to(node)).replace("/","__")))
		library.append(spec)
		if Time.get_ticks_usec()-slice_started>=budget:
			elapsed+=Time.get_ticks_usec()-slice_started;slices+=1
			progress.emit("准备模型流式索引",i+1,parts.size())
			await get_tree().process_frame
			if _cancelled:return false
			slice_started=Time.get_ticks_usec()
	# Children precede mesh parents, just as in WorldStream._adopt. Preserve
	# empty transform holders and their authored metadata/whole-asset identity.
	for i:int in range(parts.size()-1,-1,-1):
		var node:Node=parts[i]
		node.get_parent().remove_child(node);node.free()
		if Time.get_ticks_usec()-slice_started>=budget:
			elapsed+=Time.get_ticks_usec()-slice_started;slices+=1
			await get_tree().process_frame
			if _cancelled:return false
			slice_started=Time.get_ticks_usec()
	# Match on-tree adoption's ownership transfer too: empty transform holders
	# must not pin the complete compiled PackedScene after specs own its meshes.
	# Genuine native/behavioural graphs are excluded above and by this predicate.
	for reference:WeakRef in compiled_holders.values():
		var holder:Node=reference.get_ref()
		if is_instance_valid(holder) and Stream._empty_compiled_holder(holder):holder.remove_meta("_compiled_resource_owner")
	elapsed+=Time.get_ticks_usec()-slice_started;slices+=1
	_profile.asset_static_specs=int(_profile.get("asset_static_specs",0))+parts.size()
	_profile.asset_static_specs_us=int(_profile.get("asset_static_specs_us",0))+elapsed
	_profile.asset_static_spec_slices=int(_profile.get("asset_static_spec_slices",0))+slices
	return true

func _prepare_asset_instance(doc:RefCounted,record:Dictionary,prepared:Dictionary)->Node3D:
	# Namespace and component semantics are shared with the synchronous editor
	# operation. The loader owns this off-tree graph across every yield/exit.
	_asset_cursor=preload("res://scripts/world3d/asset_instance_preparation.gd").new()
	var budget_usec:=2000 if background_preload else 8000
	var began:=Time.get_ticks_usec()
	_asset_cursor.begin_from_source(doc,record,prepared)
	Trace.elapsed("game.asset_instance_begin",began,{"uuid":record.uuid})
	var need_yield:=Time.get_ticks_usec()-began>=budget_usec
	while true:
		if need_yield:
			progress.emit("准备模型命名与组件",0,1)
			await get_tree().process_frame
			if _cancelled:
				_asset_cursor.dispose();_asset_cursor=null;return null
		var step_started:=Time.get_ticks_usec()
		var done:bool=_asset_cursor.advance(budget_usec)
		Trace.elapsed("game.asset_instance_step",step_started,{"uuid":record.uuid,"done":done})
		if done:break
		need_yield=true
	_profile.asset_instance_slices=int(_profile.get("asset_instance_slices",0))+int(_asset_cursor.profile.slices)
	_profile.asset_instance_cpu_us=int(_profile.get("asset_instance_cpu_us",0))+int(_asset_cursor.profile.elapsed_us)
	_profile.asset_instance_max_slice_us=maxi(int(_profile.get("asset_instance_max_slice_us",0)),int(_asset_cursor.profile.max_slice_us))
	var result:Node3D=_asset_cursor.take_holder();_asset_cursor=null;return result

func _build_records() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._build_records") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var build_started:=Time.get_ticks_usec()
	var root := Node3D.new()
	_prepared = root
	root.name = "rmmo_world"
	root.set_meta("extras", _record_meta)
	# Complete author reference metadata is distinct from prepared runtime records.
	if not _author_reference_meta.is_empty():root.set_meta("author_reference_extras",_author_reference_meta)
	root.set_meta("runtime_record_subset",not _dependency_index.is_empty())
	var library: Array = []
	var asset_specs:Array=[] # Imported rows keep their independent source/cache identity.
	# Restore buildings while the independent ground workers are still busy.
	# Keep a deterministic partition so per-record cache identities stay exact.
	var records:Array=[];var landscape:Array=[]
	for record:Dictionary in _record_meta.rmmo_records:
		if _deferred_ids.has(record.uuid):continue
		if record.has("terrain_volume") or record.has("terrain_mesh") or record.has("road_mesh") or record.has("rock_bank"):landscape.append(record)
		else:records.append(record)
	var terrain_pending:bool=entry_pipeline_enabled and _terrain_thread!=null and _terrain_thread.is_alive()
	_profile.terrain_ready_prefix_records=records.size() if terrain_pending else 0
	if near_first:
		# CPU directory construction also visits the current district first. The
		# stream retains independent records and the original authoring order.
		var distance_order:=func(a,b):return Vector2(a.position[0]-_entry_origin.x,a.position[2]-_entry_origin.z).length_squared()<Vector2(b.position[0]-_entry_origin.x,b.position[2]-_entry_origin.z).length_squared()
		if terrain_pending:
			# Sorting the combined list used to undo this readiness partition: a
			# nearby ground record stalled all already-ready buildings behind it.
			# Retain distance order within each ready class and authored identities.
			records.sort_custom(distance_order);landscape.sort_custom(distance_order)
			records.append_array(landscape)
		else:
			records.append_array(landscape);records.sort_custom(distance_order)
	else:records.append_array(landscape)
	var doc = preload("res://scripts/world3d/world_document.gd").new()
	doc.records=records
	doc.load_immutable_records=true
	doc.load_paint_validation={}
	doc.load_material_pool={}
	doc.load_texture_checks={}
	doc.load_model_signatures=_model_signatures
	doc.load_surface_arrays=_surface_arrays
	if _terrain_context!=null:doc.terrain_neighbors=_terrain_context
	var Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
	preload("res://scripts/world3d/surface_materials.gd").prepare_images(_decoded_images)
	var restore_started:=Time.get_ticks_usec()
	_profile.cooked_restore_parts={}
	doc.load_box_meshes=Cook.restore(_mesh_cache_data,doc.load_paint_validation,doc.load_material_pool,_profile.cooked_restore_parts)
	var cooked_specs:Array=Cook.restore_specs(_mesh_cache_data,records)
	_profile.cooked_specs=cooked_specs.filter(func(spec):return not spec.is_empty()).size()
	_profile.cooked_meshes=doc.load_box_meshes.size()
	_profile.cooked_restore_us=Time.get_ticks_usec()-restore_started
	Trace.elapsed("game.cooked_restore",restore_started)

	var Stream = preload("res://scripts/world3d/world_stream.gd")
	var cursor := 0
	_profile.mesh_us=0;_profile.spec_us=0;_profile.frames=0;_profile.hit_us=0;_profile.miss_us=0;_profile.mesh_categories={}
	_profile.asset_generate_us=0;_profile.asset_instantiate_us=0
	while cursor < records.size():
		var start := Time.get_ticks_usec()
		while cursor < records.size() and Time.get_ticks_usec() - start < (2000 if background_preload else 24000):
			if _terrain_thread!=null and (records[cursor].has("terrain_volume") or records[cursor].has("terrain_mesh") or records[cursor].has("road_mesh") or records[cursor].has("rock_bank")):
				progress.emit("准备地形数据（后台）",cursor,records.size())
				await _finish_terrain()
				if _cancelled:root.free();_prepared=null;await _retire();return
				if _terrain_context!=null:doc.terrain_neighbors=_terrain_context
				else:doc.terrain_neighbors.update(records)
				doc.load_surface_arrays=_surface_arrays
				start=Time.get_ticks_usec()
			if records[cursor].get("kind") == "asset" and not records[cursor].has("house_prefab"):
				if not FileAccess.file_exists(str(records[cursor].get("asset_path", ""))):
					root.free()
					_prepared = null
					_finish_error("地图素材缺失：" + str(records[cursor].get("asset_path", "")))
					return
				var asset_path: String = records[cursor].asset_path
				if _asset_states.has(asset_path):
					var asset_started:=Time.get_ticks_usec()
					var prepared_asset:Dictionary=_asset_states[asset_path]
					var asset_library=preload("res://scripts/world_editor/asset_library.gd")
					var cached:=false
					if background_preload:
						if prepared_asset.has("packed"):_private_assets[asset_path]=prepared_asset.packed
						else:
							var imported:Node=prepared_asset.get("scene")
							if imported==null:imported=preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(prepared_asset.document,prepared_asset.state)
							if imported!=null:
								var packed:=PackedScene.new()
								if packed.pack(imported)==OK:_private_assets[asset_path]=packed
								preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(imported)
								prepared_asset.erase("scene")
						cached=_private_assets.has(asset_path)
					elif prepared_asset.has("packed"):
						cached=asset_library.cache_packed(asset_path,prepared_asset.packed,str(_model_signatures.get(asset_path,"")))
					else:
						var imported:Node=prepared_asset.get("scene")
						if imported==null:imported=preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(prepared_asset.document,prepared_asset.state)
						cached=imported!=null and asset_library.cache_scene(asset_path,imported,str(_model_signatures.get(asset_path,"")))
						if not is_instance_valid(imported):prepared_asset.erase("scene")
					if not cached:
						root.free()
						_prepared = null
						_finish_error("地图素材无法实例化：" + asset_path)
						return
					_asset_states.erase(asset_path)
					if not background_preload:preload("res://scripts/world3d/runtime_asset_cache_scope.gd").claim(root,asset_path)
					_prepared_asset_paths[asset_path]=true
					_profile.asset_generate_us+=Time.get_ticks_usec()-asset_started
					Trace.elapsed("game.asset_generate",asset_started,{"path":asset_path})
				var instance_started:=Time.get_ticks_usec()
				# Do not stack a completed large template pack and instance creation
				# in the same covered loading frame.
				if Time.get_ticks_usec()-start>=(2000 if background_preload else 24000):
					await get_tree().process_frame
					if _cancelled:root.free();_prepared=null;await _retire();return
					start=Time.get_ticks_usec()
				var instance:Node=await _prepare_asset_instance(doc,records[cursor],{"template":_private_assets[asset_path]} if background_preload else {})
				if _cancelled:root.free();_prepared=null;await _retire();return
				_profile.asset_instantiate_us+=Time.get_ticks_usec()-instance_started
				Trace.elapsed("game.asset_instantiate",instance_started,{"uuid":records[cursor].uuid,"path":asset_path})
				if not background_preload:preload("res://scripts/world3d/runtime_asset_cache_scope.gd").claim(root,asset_path)
				# The prepared root owns the instance across yields/cancellation. GPU
				# buffer getters stay on main, where they avoid synchronous worker
				# round trips; bounded slices keep them out of first stream adoption.
				root.add_child(instance)
				if initial_cpu_capture_enabled:
					var capture_started:=Time.get_ticks_usec()
					var preparation=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
					var capture:Dictionary=preparation.begin(instance,true)
					while not preparation.advance(capture,2000 if background_preload else 16000):
						progress.emit("准备模型 CPU 几何",int(capture.profile.captured_meshes),0)
						await get_tree().process_frame
						if _cancelled:root.free();_prepared=null;await _retire();return
					if not capture.profile.error.is_empty():
						root.free();_prepared=null;_finish_error(str(capture.profile.error));return
					_profile.asset_capture_wall_us=int(_profile.get("asset_capture_wall_us",0))+Time.get_ticks_usec()-capture_started
					for field:String in ["elapsed_us","slices","captured_meshes","face_bytes"]:_profile["asset_capture_"+field]=int(_profile.get("asset_capture_"+field,0))+int(capture.profile[field])
					_profile.asset_capture_max_slice_us=maxi(int(_profile.get("asset_capture_max_slice_us",0)),int(capture.profile.max_slice_us))
				var parts:Array=preload("res://scripts/world3d/surface_materials.gd").meshes(instance)
				for i in parts.size():parts[i].set_meta("map_draw_order",int(_record_order[records[cursor].uuid])*65536+i)
				if initial_static_specs_enabled and not await _prepare_static_asset_specs(root,instance,parts,asset_specs):
					root.free();_prepared=null;await _retire();return
				cursor += 1
				continue
			var spec:Dictionary
			if not cooked_specs.is_empty() and not cooked_specs[cursor].is_empty():spec=cooked_specs[cursor]
			else:
				var hits_before:int=doc.load_box_hits
				var mesh_started:=Time.get_ticks_usec()
				var mesh_parts:Variant={} if Trace.enabled else null
				var visual: MeshInstance3D = doc._mesh(records[cursor],true,mesh_parts)
				var mesh_elapsed:=Time.get_ticks_usec()-mesh_started
				if Trace.enabled:Trace.elapsed("game.mesh",mesh_started,{"uuid":records[cursor].uuid,"prefab":records[cursor].has("house_prefab"),"terrain":records[cursor].has("terrain_mesh"),"parts_ms":mesh_parts})
				var category:String="prefab" if records[cursor].has("house_prefab") else ("terrain" if records[cursor].has("terrain_mesh") else ("road" if records[cursor].has("road_mesh") else "other"))
				_profile.mesh_categories[category]=int(_profile.mesh_categories.get(category,0))+mesh_elapsed
				_profile.mesh_us+=mesh_elapsed
				_profile["hit_us" if doc.load_box_hits>hits_before else "miss_us"]+=mesh_elapsed
				if visual.has_meta("tile_error") or visual.has_meta("paint_error"):
					visual.free(); root.free(); _prepared = null
					_finish_error("自动拼接套件模型缺失或无效")
					return
				var spec_started:=Time.get_ticks_usec()
				spec = Stream._spec(visual)
				_profile.spec_us+=Time.get_ticks_usec()-spec_started
				if Trace.enabled:Trace.elapsed("game.spec",spec_started,{"uuid":records[cursor].uuid})
				visual.free()
			var id: String = spec.uuid
			spec.map_draw_order=int(_record_order.get(id,0))*65536
			library.append(spec)
			cursor += 1
		progress.emit("准备地图几何与材质", cursor, records.size())
		_profile.frames+=1
		await get_tree().process_frame
		if _cancelled:
			root.free()
			_prepared = null
			await _retire()
			return
	await _finish_terrain()
	if not background_preload and _mesh_cache_allowed and (_mesh_cache_data.is_empty() or not _profile.get("terrain_context_cache_hit",false)) and not _source_digest.is_empty():
		var pack_started:=Time.get_ticks_usec()
		var snapshot:Dictionary=Cook.pack(doc.load_box_meshes,_source_digest,_generator_key,library)
		if _terrain_context!=null:snapshot.terrain_context=preload("res://scripts/world3d/terrain_context_cache.gd").pack(_terrain_context)
		snapshot.models=_model_signatures
		if not _mesh_cache_selection.is_empty():snapshot.selection=_mesh_cache_selection
		_profile.cache_pack_us=Time.get_ticks_usec()-pack_started
		Trace.elapsed("game.cache_pack",pack_started)
		_mesh_cache_thread=Thread.new()
		if _mesh_cache_thread.start(Cook.write.bind(_path,snapshot,_mesh_cache_selection))!=OK:_mesh_cache_thread=null
	# Cook.restore_specs expects exactly the authored non-asset rows. Imported
	# geometry joins only the runtime directory, after that cache snapshot.
	library.append_array(asset_specs)
	var index_started:=Time.get_ticks_usec()
	var index_job:=preload("res://scripts/world3d/stream_index.gd").build.bind(library)
	_index_thread=Thread.new()
	var index_data:Dictionary
	if _index_thread.start(index_job)==OK:
		progress.emit("构建空间索引（后台）",0,library.size())
		while _index_thread.is_alive():await get_tree().process_frame
		index_data=_index_thread.wait_to_finish();_index_thread=null
	else:
		_index_thread=null;index_data=index_job.call()
	_profile.index_worker_us=Time.get_ticks_usec()-index_started
	Trace.elapsed("game.index_wait",index_started)
	if _cancelled:
		root.free();_prepared=null;await _retire();return
	var integrity_started:=Time.get_ticks_usec()
	if not _reference_integrity():
		root.free();_prepared=null;_finish_error("构建期间地图或引用资源已改变");return
	_profile.final_integrity_us=Time.get_ticks_usec()-integrity_started
	_profile.build_total_us=Time.get_ticks_usec()-build_started
	if not _entry_plan.is_empty():
		_entry_plan.core_resources_ready_us=Time.get_ticks_usec()
		_profile.core_resources_ready_us=_entry_plan.core_resources_ready_us
		root.set_meta("entry_plan",_entry_plan.duplicate(true))
	Trace.elapsed("game.build",build_started)
	root.set_meta("stream_library",library)
	for key:String in index_data:root.set_meta(key,index_data[key])
	root.set_meta("stream_children", -1 if root.get_child_count() > 0 else 0)
	root.set_meta("record_stream_load", true)
	root.set_meta("load_box_cache_hits",doc.load_box_hits)
	_profile.startup_render_context_draws=_startup_draw_count
	_profile.definition_cache=preload("res://scripts/world3d/definition_cache_policy.gd").snapshot()
	root.set_meta("load_profile",_profile)
	root.set_meta("runtime_geometry_key",_source_digest+_generator_key+str(_model_signatures))
	root.set_meta("source_map_sha256",_source_digest)
	root.set_meta("collision_first_loading",preload("res://scripts/world3d/deferred_asset_loader.gd").collision_first_enabled and not _dependency_index.is_empty())
	if _build_dependency_index and not background_preload:
		# Optional CPU cache construction continues after the ready scene is emitted.
		# The author snapshot is immutable; runtime fixture poses live on specs.
		_cache_thread=Thread.new()
		var build_directory:=preload("res://scripts/world3d/map_dependency_index.gd").build.bind(_path,_content_root,_record_meta.rmmo_records,_source_digest)
		if _cache_thread.start(build_directory)!=OK:_cache_thread=null
	if not _deferred_assets.is_empty() or not _dependency_index.is_empty():
		var deferred:Node=_early_deferred if is_instance_valid(_early_deferred) else _new_deferred()
		if deferred==_early_deferred:
			deferred.finish_entry_prefetch()
			_early_deferred=null
		# Far instances share the same immutable scene already prepared for a
		# near instance. Do not import that model a second time in the queue.
		deferred._prepared_paths=_prepared_asset_paths.duplicate()
		deferred.source_signatures=_model_signatures.duplicate()
		deferred.pending=_deferred_assets;root.add_child(deferred)
		deferred.handoff_collision_prefetch(root)
		root.set_meta("deferred_geometry",true)
		root.set_meta("stream_children",-1) # First adoption skips the marked service.
	var server=get_node_or_null("/root/MockServer")
	if not background_preload and server!=null and server.has_method("register_loaded_world3d_environment"):
		server.register_loaded_world3d_environment(_path,_record_meta)
	_prepared = null
	finished.emit(root, _path, "")
	await _retire()


func _can_stream_static() -> bool:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._can_stream_static") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not _state.animations.is_empty() or not _state.skins.is_empty() or not _state.cameras.is_empty() or not _state.lights.is_empty(): return false
	for extension in _state.json.get("extensionsUsed", []):
		if str(extension) != "GODOT_single_root": return false
	for node in _state.nodes:
		if node.skin >= 0 or node.skeleton >= 0 or not node.visible: return false
	for imported in _state.meshes:
		if not imported.blend_weights.is_empty(): return false
	return true


func _build_static() -> void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.map_loader._build_static") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var root := Node3D.new()
	_prepared = root
	root.name = "rmmo_world"
	var raw_nodes: Array = _state.json.get("nodes", [])
	if _state.root_nodes.size() == 1:
		root.set_meta("extras", raw_nodes[_state.root_nodes[0]].get("extras", {}))
	var stack: Array = []
	for id in _state.root_nodes: stack.append({"id": id, "parent": Transform3D.IDENTITY})
	var library: Array = []
	var by_id := {}
	var index := {}
	var known := {}
	var meshes := {}
	var visited := {}
	var Stream = preload("res://scripts/world3d/world_stream.gd")
	while not stack.is_empty():
		var start := Time.get_ticks_usec()
		while not stack.is_empty() and Time.get_ticks_usec() - start < 3000:
			var entry: Dictionary = stack.pop_back()
			var id: int = entry.id
			if visited.has(id): continue
			visited[id] = true
			var node: GLTFNode = _state.nodes[id]
			var transform: Transform3D = entry.parent * node.xform
			for child in node.children: stack.append({"id": child, "parent": transform})
			if node.mesh < 0: continue
			if not meshes.has(node.mesh):
				var imported: GLTFMesh = _state.meshes[node.mesh]
				var resource: ArrayMesh = imported.mesh.get_mesh()
				if not imported.instance_materials.is_empty():
					resource = resource.duplicate()
					for surface in mini(resource.get_surface_count(), imported.instance_materials.size()):
						if imported.instance_materials[surface] != null: resource.surface_set_material(surface, imported.instance_materials[surface])
				meshes[node.mesh] = resource
			var visual := MeshInstance3D.new()
			visual.name = "gltf_node_%d" % id
			visual.mesh = meshes[node.mesh]
			visual.transform = transform
			visual.set_meta("extras", raw_nodes[id].get("extras", {}))
			var spec: Dictionary = Stream._spec(visual)
			visual.free()
			var uuid := str(spec.extras.get("uuid", spec.uuid))
			if known.has(uuid):
				_finish_error("地图物件 ID 重复：" + uuid)
				return
			spec.uuid = uuid
			known[uuid] = true
			by_id[uuid] = spec
			library.append(spec)
			for z in range(spec.chunk_min.y, spec.chunk_max.y + 1):
				for x in range(spec.chunk_min.x, spec.chunk_max.x + 1):
					var key := Vector2i(x, z)
					if not index.has(key): index[key] = []
					index[key].append(uuid)
		progress.emit("准备静态地图", visited.size(), _state.nodes.size())
		await get_tree().process_frame
		if _cancelled:
			queue_free()
			return
	root.set_meta("stream_library", library)
	root.set_meta("stream_by_id", by_id)
	root.set_meta("stream_known", known)
	root.set_meta("stream_index", index)
	root.set_meta("stream_children", -1 if root.get_child_count() > 0 else 0)
	root.set_meta("static_stream_load", true)
	_prepared = null
	finished.emit(root, _path, "")
	queue_free()
