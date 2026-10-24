extends Node
## Ordinary static model residency. Authored compact references remain; retired
## geometry goes through the same verified worker queue when demanded again.
## Buildings, terrain, interactions and painted resources stay pinned for now.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const EMPTY_RECORD:Dictionary={}
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
static var retirement_batching_enabled:=true
static var frame_retry_enabled:=true # Diagnostic control retains quarter-second dispatch.
var _retry_candidates:Array=[] # Bounded mature UUIDs; never retain source resources.
var _retry_individually:=false
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
	var packet:RefCounted=_deferred.get("publication_metadata") if is_instance_valid(_deferred) else null
	if packet!=null and packet.ready(specs) and _observe_publication(packet):return
	for spec:Dictionary in specs:
		var root_id:String=str(spec.uuid).get_slice("__",0)
		var source_record:Dictionary=spec.get("ground_batch_record",EMPTY_RECORD)
		var uuid:String=str(source_record.get("uuid",root_id))
		# Imported component UUIDs are model-local. The declared map instance
		# owns their model lease; different models may reuse every component ID.
		# This also keeps one namespace table per instance, not per mesh part.
		if _record_paths.has(root_id):uuid=root_id
		# Dictionary.get evaluates its fallback even on a hit. Most model parts
		# already have a directory path; avoid rebuilding their whole fallback
		# chain and temporary record dictionaries on every component.
		var path:String
		if _record_paths.has(uuid):path=_record_paths[uuid]
		elif _record_paths.has(root_id):path=_record_paths[root_id]
		else:path=source_record.get("asset_path",spec.get("extras",EMPTY_RECORD).get("asset_path",""))
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
		elif path.is_empty() and not _procedural_assets.has(uuid) and not _procedural_assets.has(root_id) and source_record.get("kind","")=="asset":_unknown_asset_specs[spec.uuid]=true
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
		if _resident[uuid].pinned.is_empty():
			var dependency:String=preload("res://scripts/world3d/stream_index.gd")._retire_dependency(spec)
			if not dependency.is_empty():_resident[uuid].pinned=dependency
	profile.resident_instances=_resident.size()
	_profile_usage()

func _observe_publication(packet:RefCounted)->bool:
	# The published packet is a complete, already indexed map instance. A
	# partial/duplicate observation retains the ordinary incremental path.
	for uuid:String in packet.namespaces:
		if str(_record_paths.get(uuid,"")).is_empty() or _namespace_specs.has(uuid) or _resident.has(uuid):return false
	for uuid:String in packet.namespaces:
		var members:Dictionary=packet.namespaces[uuid];var path:String=_record_paths[uuid]
		_namespace_specs[uuid]=members.ids.duplicate()
		if not _model_namespaces.has(path):_model_namespaces[path]={}
		_model_namespaces[path][uuid]=true
		if _native_namespaces.has(uuid) or not _catalog.has(uuid):continue
		if not _record_pins.has(uuid):
			var record:Dictionary=_deferred.runtime_record(uuid)
			if not record.is_empty():_remember_traits(record)
		var pin:String=_record_pins.get(uuid,"missing_authored_record")
		if pin.is_empty():pin=members.ordinary_pin
		_resident[uuid]={"ids":members.order.duplicate(),"known_ids":members.ids.duplicate(),"outside_since":-1,"pinned":pin}
		if _retired.erase(uuid):profile.revisits+=1
	_spec_namespaces.merge(packet.spec_namespaces,true)
	if not _unknown_asset_specs.is_empty():
		for id:String in packet.ids:_unknown_asset_specs.erase(id)
	profile.resident_instances=_resident.size();_profile_usage()
	profile.prepared_observations=int(profile.get("prepared_observations",0))+1
	return true

func handoff_native(uuid:String)->void:
	_native_namespaces[uuid]=true;_resident.erase(uuid)
	profile.resident_instances=_resident.size()

func forget_specs(ids:Array)->void:
	# Called by the shared Stream transaction, including native-unit retirement.
	# Store IDs only so this catalogue can never keep meshes/materials alive.
	var touched:Dictionary={}
	var previous_owner:Variant=null;var members:Dictionary={}
	for id:String in ids:
		_unknown_asset_specs.erase(id)
		var owner:Variant=_spec_namespaces.get(id)
		if owner==null:continue
		var uuid:String=owner;_spec_namespaces.erase(id)
		if owner!=previous_owner:
			if not touched.has(uuid):touched[uuid]=_namespace_specs[uuid]
			members=touched[uuid];previous_owner=owner
		members.erase(id)
	# Thousands of model parts share one namespace. Check and retire that
	# namespace once after all selected identities are removed, without changing
	# the per-part ownership or releasing a model that still has another user.
	for uuid:String in touched:
		if not touched[uuid].is_empty():continue
		_namespace_specs.erase(uuid)
		var path:String=_record_paths[uuid]
		_model_namespaces[path].erase(uuid)
		if _model_namespaces[path].is_empty():_model_namespaces.erase(path)
	profile.retirement_namespace_checks=int(profile.get("retirement_namespace_checks",0))+touched.size()
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
	if not is_instance_valid(_host) or not _host.get("_ready_for_play") or _host.get("_transfer_pending"):return
	if not is_instance_valid(_deferred) or not _deferred._active:return
	if _clock>=.25:
		_clock=0.;poll(Time.get_ticks_msec())
	elif frame_retry_enabled and not _retry_candidates.is_empty():_drain_candidates(Time.get_ticks_msec(),true)

func _needed(entry:Dictionary)->bool:
	for demand:Dictionary in _deferred._demands.values():
		if demand.get("kind","all") in ["building","road","structure","terrain"]:continue
		if _deferred._intersects(entry.bounds,demand.clip.grow(exit_margin)):return true
	var navigation:Node=_host.get("_navigation")
	if is_instance_valid(navigation) and _deferred._intersects(entry.bounds,navigation._local_clip.grow(exit_margin)):return true
	return false

func _eligible(uuid:String,now_msec:int)->bool:
	var entry:Dictionary=_catalog[uuid];var resident:Dictionary=_resident[uuid]
	if not resident.pinned.is_empty():return false
	if _needed(entry) or _deferred._jobs.has(entry.asset_path):resident.outside_since=-1;return false
	if int(resident.outside_since)<0:resident.outside_since=now_msec;return false
	return now_msec-int(resident.outside_since)>=grace_msec

func poll(now_msec:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.asset_residency.poll") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var keys:Array=_resident.keys()
	if keys.is_empty():return
	var navigation:Node=_host.get("_navigation")
	if not is_instance_valid(navigation) or not navigation.streaming_geometry:return
	# Observe the bounded directory slice once, even if its first namespace
	# retires. Mature IDs can consume later frame budgets without rescanning.
	_retry_candidates=[]
	for scan:int in mini(32,keys.size()):
		_cursor%=keys.size();var uuid:String=keys[_cursor];_cursor+=1
		if _eligible(uuid,now_msec):_retry_candidates.append(uuid)
	_drain_candidates(now_msec,false)

func _drain_candidates(now_msec:int,recheck:bool)->void:
	var navigation:Node=_host.get("_navigation")
	if not is_instance_valid(navigation) or not navigation.streaming_geometry:return
	if recheck:
		var ready:Array=[]
		for uuid:String in _retry_candidates:
			if _resident.has(uuid) and _catalog.has(uuid) and _eligible(uuid,now_msec):ready.append(uuid)
		_retry_candidates=ready
	if _retry_candidates.is_empty():return
	if Stream._retirement_budget(_map).request(Engine.get_process_frames(),"ordinary_retirement",2000)<=0:
		profile.last_wait="retirement_budget";return
	var barrier:=Stream.retirement_barrier(_map,false,true)
	if not barrier.is_empty():
		profile.last_wait=barrier;profile.retirement_attempts=int(profile.get("retirement_attempts",0))+1
		return
	# One atomic success per callback, still admitted by the shared 2 ms frame
	# ledger. Non-global refusals fall back to singles without starving peers.
	while not _retry_candidates.is_empty():
		var uuid:String=_retry_candidates[0]
		var uuids:Array=[uuid];var count:int=_resident[uuid].ids.size()
		if retirement_batching_enabled and not _retry_individually and count<=128:
			for next:String in _retry_candidates.slice(1):
				if uuids.size()>=8:break
				var size_:int=_resident[next].ids.size()
				if count+size_>128:continue
				uuids.append(next);count+=size_
		var selection:=_retirement_selection(uuids)
		var ids:Array=selection.ids;var entries:Array=selection.entries
		var result:=Stream.retire_specs(_map,ids,false,navigation,"ordinary_retirement")
		profile.retirement_attempts=int(profile.get("retirement_attempts",0))+1
		if not result.ok:
			profile.last_wait=result.error
			# These map/frame barriers cannot change inside this synchronous poll.
			# Rechecking other owners only repeats the same refusal; it also must
			# not demote the next ready transaction to an individual retry.
			if result.error in ["retirement_budget","stream_busy","batch_leased","proxy_leased"]:return
			if uuids.size()>1:
				_retry_individually=true;return
			_retry_candidates.erase(uuid)
			continue
		var cleanup_started:=Time.get_ticks_usec()
		if entries.size()==1:_deferred.requeue_reference(entries[0])
		else:_deferred.requeue_references(entries)
		var paths:Dictionary={}
		for id:String in uuids:
			paths[_catalog[id].asset_path]=true
			_resident.erase(id);_retired[id]=true;_retry_candidates.erase(id)
		_retry_individually=false
		profile.retired_instances+=uuids.size();profile.retired_specs+=result.removed;profile.last_wait=""
		profile.retirement_transactions=int(profile.get("retirement_transactions",0))+1
		profile.max_instances_per_transaction=maxi(int(profile.get("max_instances_per_transaction",0)),uuids.size())
		profile.resident_instances=_resident.size()
		for path:String in paths:_evict_unused_model(path)
		Stream.charge_retirement_work(_map,"ordinary_retirement",cleanup_started)
		return

func _retirement_selection(uuids:Array)->Dictionary:
	var ids:Array=[];var entries:Array=[]
	for uuid:String in uuids:ids.append_array(_resident[uuid].ids);entries.append(_catalog[uuid])
	return {"ids":ids,"entries":entries}

func _evict_unused_model(path:String)->void:
	var used:=model_in_use(path)
	if legacy_retirement_source_scan_enabled:
		used=false
		for spec:Dictionary in _map.get_meta("stream_library",[]):
			var source_id:String=str(spec.uuid).get_slice("__",0)
			if _record_paths.get(source_id,"")==path or spec.get("ground_batch_record",{}).get("asset_path","")==path or spec.get("extras",{}).get("asset_path","")==path:used=true;break
		if not used:
			for id:String in _resident:
				if _catalog[id].asset_path==path:used=true;break
	# Other maps/nodes retain their resources. Evict shared paths only after
	# every selected namespace has released ownership in the same transaction.
	if not used:
		var scope:RefCounted=_map.get_meta("runtime_asset_cache_scope") if _map.has_meta("runtime_asset_cache_scope") else null
		var evicted:bool=scope.release(path) if scope!=null else Assets.evict_cached_scene(path)
		if evicted:_deferred._prepared_paths.erase(path);profile.evicted_models+=1
