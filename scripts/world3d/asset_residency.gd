extends Node
## Ordinary static model residency. Authored compact references remain; retired
## geometry goes through the same verified worker queue when demanded again.
## Buildings, terrain, interactions and painted resources stay pinned for now.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
var grace_msec:=10000
var exit_margin:=64.0
var profile:Dictionary={"retired_instances":0,"retired_specs":0,"evicted_models":0,"revisits":0}
var _host:Node
var _map:Node
var _deferred:Node
var _catalog:Dictionary={}
var _resident:Dictionary={}
var _retired:Dictionary={}
var _record_pins:Dictionary={}
var _record_paths:Dictionary={}
var _spec_namespaces:Dictionary={}
var _namespace_specs:Dictionary={}
var _model_namespaces:Dictionary={}
var _unknown_asset_specs:Dictionary={}
var _procedural_assets:Dictionary={}
var _native_namespaces:Dictionary={}
static var legacy_retirement_source_scan_enabled:=false
var _clock:=0.0
var _cursor:=0

func configure(host:Node,map_root:Node,deferred:Node)->void:
	name="AssetResidency";set_meta("stream_instance",true)
	_host=host;_map=map_root;_deferred=deferred
	var index:Dictionary=deferred._reference_index
	for row:Dictionary in index.get("rows",[]):
		_record_paths[row.uuid]=row.asset_path # Includes pinned/native owners of shared models.
		if row.classification!="spatial" or not row.group_id.is_empty() or row.asset_path.is_empty():continue
		var compact:Dictionary=index.extras.rmmo_records[row.order]
		_catalog[row.uuid]={"record_index":row.order,"compact_record":compact,"bounds":row.bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":"","memory_bytes":row.memory_bytes}
	for record:Dictionary in map_root.get_meta("extras",{}).get("rmmo_records",[]):_remember_traits(record)
	observe(map_root.get_meta("stream_library",[]))
	deferred.published.connect(observe)

func observe(specs:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_residency.observe") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for spec:Dictionary in specs:
		var uuid:String=str(spec.get("ground_batch_record",{}).get("uuid",str(spec.uuid).get_slice("__",0)))
		var path:String=_record_paths.get(uuid,_record_paths.get(str(spec.uuid).get_slice("__",0),spec.get("ground_batch_record",{}).get("asset_path",spec.get("extras",{}).get("asset_path",""))))
		var root_id:String=str(spec.uuid).get_slice("__",0)
		# Some conservative directory rows have no model-path classification.
		# Publication hands off the hydrated record before emitting this signal.
		if path.is_empty() and is_instance_valid(_deferred):
			for source_id:String in [uuid,root_id]:
				var record:Dictionary=_deferred.runtime_record(source_id)
				if not record.is_empty():
					_remember_traits(record)
					path=str(record.get("asset_path",""))
					if not path.is_empty():break
		if not path.is_empty() and not _spec_namespaces.has(spec.uuid):
			_unknown_asset_specs.erase(spec.uuid)
			_record_paths[uuid]=path;_spec_namespaces[spec.uuid]=uuid
			if not _namespace_specs.has(uuid):_namespace_specs[uuid]={}
			_namespace_specs[uuid][spec.uuid]=true
			if not _model_namespaces.has(path):_model_namespaces[path]={}
			_model_namespaces[path][uuid]=true
		elif path.is_empty() and not _procedural_assets.has(uuid) and not _procedural_assets.has(root_id) and spec.get("ground_batch_record",{}).get("kind","")=="asset":_unknown_asset_specs[spec.uuid]=true
		if not _catalog.has(uuid):uuid=root_id
		if _native_namespaces.has(uuid) or not _catalog.has(uuid):continue
		if not _resident.has(uuid):
			if not _record_pins.has(uuid):
				var published:Dictionary=_deferred.runtime_record(uuid) if _deferred.has_method("runtime_record") else {}
				if not published.is_empty():_remember_traits(published)
				else:
					for record:Dictionary in _map.get_meta("extras",{}).get("rmmo_records",[]):
						if record.uuid==uuid:_remember_traits(record);break
			_resident[uuid]={"ids":[],"known_ids":{},"outside_since":-1,"pinned":_record_pins.get(uuid,"missing_authored_record")}
			if _retired.erase(uuid):profile.revisits+=1
		if not _resident[uuid].has("known_ids"):
			_resident[uuid].known_ids={}
			for id:String in _resident[uuid].ids:_resident[uuid].known_ids[id]=true
		if not _resident[uuid].known_ids.has(spec.uuid):_resident[uuid].ids.append(spec.uuid);_resident[uuid].known_ids[spec.uuid]=true
		var dependency:String=preload("res://scripts/world3d/stream_index.gd")._retire_dependency(spec)
		if not dependency.is_empty():_resident[uuid].pinned=dependency
	profile.resident_instances=_resident.size()
	_profile_usage()

func handoff_native(uuid:String)->void:
	_native_namespaces[uuid]=true;_resident.erase(uuid)
	profile.resident_instances=_resident.size()

func forget_specs(ids:Array)->void:
	# Called by the shared Stream transaction, including native-unit retirement.
	# Store IDs only so this catalogue can never keep meshes/materials alive.
	for id:String in ids:
		_unknown_asset_specs.erase(id)
		if not _spec_namespaces.has(id):continue
		var uuid:String=_spec_namespaces[id];_spec_namespaces.erase(id)
		_namespace_specs[uuid].erase(id)
		if not _namespace_specs[uuid].is_empty():continue
		_namespace_specs.erase(uuid)
		var path:String=_record_paths[uuid]
		_model_namespaces[path].erase(uuid)
		if _model_namespaces[path].is_empty():_model_namespaces.erase(path)
	_profile_usage()

func _profile_usage()->void:
	profile.model_namespaces=_model_namespaces.size();profile.unknown_model_specs=_unknown_asset_specs.size()
	profile.unknown_model_spec_sample=_unknown_asset_specs.keys().slice(0,8)

func model_in_use(path:String)->bool:
	return not _unknown_asset_specs.is_empty() or not _model_namespaces.get(path,{}).is_empty()

func _remember_traits(record:Dictionary)->void:
	_record_paths[record.uuid]=str(record.get("asset_path",""))
	if record.has("bridge_mesh") and str(record.get("asset_path","")).is_empty():_procedural_assets[record.uuid]=true
	var pin:="" if record.get("kind","")=="asset" else "non_asset"
	for field in ["building","fixture","fortification","house_prefab","bridge_mesh","surface_paint","prefab_materials","material","material_state","material_overrides","event","event_template","parametric_tree","tree","streetlamp"]:
		if record.has(field):pin=field;break
	_record_pins[record.uuid]=pin

func _process(delta:float)->void:
	_clock+=delta
	if _clock<0.25:return
	_clock=0
	if not is_instance_valid(_host) or not _host.get("_ready_for_play") or _host.get("_transfer_pending"):return
	if not is_instance_valid(_deferred) or not _deferred._active:return
	poll(Time.get_ticks_msec())

func _needed(entry:Dictionary)->bool:
	for demand:Dictionary in _deferred._demands.values():
		if demand.get("kind","all") in ["building","road","structure"]:continue
		if _deferred._intersects(entry.bounds,demand.clip.grow(exit_margin)):return true
	var navigation:Node=_host.get("_navigation")
	if is_instance_valid(navigation) and _deferred._intersects(entry.bounds,navigation._local_clip.grow(exit_margin)):return true
	return false

func poll(now_msec:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_residency.poll") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var keys:Array=_resident.keys()
	if keys.is_empty():return
	var navigation:Node=_host.get("_navigation")
	if not is_instance_valid(navigation) or not navigation.streaming_geometry:return
	# At most one namespace retires per tick; all preflights are nonblocking.
	for scanned in mini(32,keys.size()):
		_cursor%=keys.size()
		var uuid:String=keys[_cursor];_cursor+=1
		var entry:Dictionary=_catalog[uuid];var resident:Dictionary=_resident[uuid]
		if not resident.pinned.is_empty():continue
		if _needed(entry) or _deferred._jobs.has(entry.asset_path):resident.outside_since=-1;continue
		if int(resident.outside_since)<0:resident.outside_since=now_msec;continue
		if now_msec-int(resident.outside_since)<grace_msec:continue
		var ids:Array=resident.ids
		var result:=Stream.retire_specs(_map,ids,false,navigation)
		if not result.ok:
			profile.last_wait=result.error;continue
		_deferred.requeue_reference(entry)
		_resident.erase(uuid);_retired[uuid]=true
		profile.retired_instances+=1;profile.retired_specs+=result.removed;profile.last_wait=""
		profile.resident_instances=_resident.size()
		var used:=model_in_use(entry.asset_path)
		if legacy_retirement_source_scan_enabled:
			used=false
			for spec:Dictionary in _map.get_meta("stream_library",[]):
				var source_id:String=str(spec.uuid).get_slice("__",0)
				if _record_paths.get(source_id,"")==entry.asset_path or spec.get("ground_batch_record",{}).get("asset_path","")==entry.asset_path or spec.get("extras",{}).get("asset_path","")==entry.asset_path:used=true;break
			if not used:
				for id:String in _resident:
					if _catalog[id].asset_path==entry.asset_path:used=true;break
		# Other maps/nodes retain their own resources. The queue checks template
		# availability before publication, so a miss always returns to a worker.
		if not used:
			var scope:RefCounted=_map.get_meta("runtime_asset_cache_scope") if _map.has_meta("runtime_asset_cache_scope") else null
			var evicted:bool=scope.release(entry.asset_path) if scope!=null else Assets.evict_cached_scene(entry.asset_path)
			if evicted:_deferred._prepared_paths.erase(entry.asset_path);profile.evicted_models+=1
		return
