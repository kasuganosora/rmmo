extends Node
## Whole native/static ownership units, with render/collision/navigation consent.
## The immutable compact directory is the reconstruction source, never a hidden
## second copy of decoded meshes. Gameplay data and fixture values stay scalar.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var grace_msec:=10000
var profile:Dictionary={"retired_units":0,"retired_specs":0,"revisits":0,"last_wait":""}
var _map:Node
var _host:Node
var _queue:Node
var _units:Dictionary={}
var _owners:Dictionary={}
var _model_entries:Dictionary={}
var _resident:Dictionary={}
var _retired:Dictionary={}
var _clock:=0.
var _cursor:=0
static var retirement_batching_enabled:=true
func configure(host:Node,map_root:Node,queue:Node)->void:
	name="NativeResidency";set_meta("stream_instance",true);_host=host;_map=map_root;_queue=queue
	var index:Dictionary=queue._reference_index
	for row:Dictionary in index.get("rows",[]):
		if not row.bounds_known:continue
		if row.group_id.is_empty() and not row.asset_path.is_empty():
			# Ordinary props stay with AssetResidency. Actual imported component
			# metadata can later prove this namespace is one static building unit.
			_model_entries[row.uuid]={"record_index":row.order,"compact_record":index.extras.rmmo_records[row.order],"bounds":row.bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":"","memory_bytes":row.memory_bytes}
			continue
		if row.group_id.is_empty() and row.reason not in ["native_box","terrain_context_global","native_road","native_bridge","native_fortification","prefab_ownership_global"]:continue
		var unit:String=row.group_id if not row.group_id.is_empty() else "record:"+str(row.uuid)
		var bounds:AABB=index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds
		if not _units.has(unit):_units[unit]={"entries":[],"bounds":bounds,"kind":"building" if unit.begins_with("building:") else "all"}
		var entry:={"record_index":row.order,"compact_record":index.extras.rmmo_records[row.order],"bounds":bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":row.group_id,"memory_bytes":row.memory_bytes}
		_units[unit].entries.append(entry);_owners[row.uuid]=unit
	observe(map_root.get_meta("stream_library",[]));queue.published.connect(observe)
func observe(specs:Array)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.native_residency.observe") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var unsafe_namespaces:Dictionary={}
	for spec:Dictionary in specs:
		if spec.get("native_visual",false):unsafe_namespaces[str(spec.uuid).get_slice("__",0)]=true
	for spec:Dictionary in specs:
		var root_id:String=str(spec.uuid).get_slice("__",0)
		if not _owners.has(root_id) and _model_entries.has(root_id) and not unsafe_namespaces.has(root_id) and spec.has("render_building"):
			var unit_id:="asset:"+root_id;var entry:Dictionary=_model_entries[root_id]
			_units[unit_id]={"entries":[entry],"bounds":entry.bounds,"kind":"building","source_uuid":root_id,"support_ids":{}};_owners[root_id]=unit_id
			var ordinary:Node=_map.get_node_or_null("AssetResidency")
			if ordinary!=null:ordinary.handoff_native(root_id)
	# Resolve ownership before collecting any part, including light anchors that
	# precede the first building member in the original imported node order.
	var changed:Dictionary={};var support_groups:Dictionary={}
	for spec:Dictionary in specs:
		var uuid:String=spec.get("ground_batch_record",{}).get("uuid",str(spec.uuid).get_slice("__",0))
		if not _owners.has(uuid):uuid=str(spec.uuid).get_slice("__",0)
		if not _owners.has(uuid):continue
		var unit:String=_owners[uuid]
		if _units[unit].kind=="building":
			# Runtime adapters index a hinge's full sweep. Preserve this wider
			# scalar envelope for reload demand without changing the immutable
			# reference/proof bounds handed back to the geometry worker.
			var render:Dictionary=spec.get("render_bounds",spec)
			var low:Vector2i=render.chunk_min;var high:Vector2i=render.chunk_max
			var bounds:=AABB(Vector3(low.x*Stream.CHUNK_M,-100000,low.y*Stream.CHUNK_M),Vector3((high.x-low.x+1)*Stream.CHUNK_M,200000,(high.y-low.y+1)*Stream.CHUNK_M))
			_units[unit].bounds=_units[unit].bounds.merge(bounds)
			if not _units[unit].has("support_ids"):_units[unit].support_ids={}
			changed[unit]=true
			var group:String=spec.get("render_building","")
			if not group.is_empty() and not support_groups.has(group):
				support_groups[group]=true
				for support:Dictionary in spec.get("render_supports",[]):
					var id:String=support.get("ground_batch_record",{}).get("uuid",str(support.uuid).get_slice("__",0))
					_units[unit].support_ids[id]=true
		if not _resident.has(unit):
			_resident[unit]={"ids":[],"known_ids":{},"outside_since":-1}
			if _retired.erase(unit):profile.revisits+=1
		if not _resident[unit].has("known_ids"):
			_resident[unit].known_ids={}
			for id:String in _resident[unit].ids:_resident[unit].known_ids[id]=true
		if not _resident[unit].known_ids.has(spec.uuid):_resident[unit].ids.append(spec.uuid);_resident[unit].known_ids[spec.uuid]=true
	for unit:String in changed:
		for entry:Dictionary in _units[unit].entries:_queue.register_runtime_building(entry.compact_record.uuid,_units[unit].bounds,_units[unit].support_ids)
	profile.resident_units=_resident.size();profile.known_units=_units.size()
func _process(delta:float)->void:
	_clock+=delta
	if _clock<.25:return
	_clock=0.
	if is_instance_valid(_host) and _host._ready_for_play and not _host._transfer_pending:poll(Time.get_ticks_msec())
func _needed(unit:Dictionary)->bool:
	for demand:Dictionary in _queue._demands.values():
		var kind:String=demand.get("kind","all")
		if kind=="building" and unit.kind!="building":continue
		if kind in ["road","structure"]:
			var reason:String=unit.entries[0].reason
			if kind=="road" and reason!="native_road":continue
			if kind=="structure" and reason not in ["native_fortification","native_bridge"]:continue
		if _queue._intersects(unit.bounds,demand.clip.grow(64.)):return true
	var navigation:Node=_host._navigation
	return is_instance_valid(navigation) and _queue._intersects(unit.bounds,navigation._local_clip.grow(64.))
func poll(now:int)->void:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.native_residency.poll") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if not is_instance_valid(_queue) or not _queue._active:return
	var nav:Node=_host._navigation
	if not is_instance_valid(nav) or not nav.streaming_geometry:return
	# Finish the bounded observation slice even when its first unit can retire.
	# Otherwise each successful small retirement delays the next units' first
	# outside timestamp, keeping a large cold building alive for minutes.
	var candidates:=_retirement_candidates(now)
	candidates.sort_custom(func(a:String,b:String):return _resident[a].ids.size()>_resident[b].ids.size())
	var attempts:Array=[]
	for id:String in candidates:attempts.append([id])
	# Validate small cold units together. A large namespace still commits alone;
	# all selected units retain the same authoritative owner/pin transaction.
	if retirement_batching_enabled and not candidates.is_empty() and _resident[candidates[0]].ids.size()<=128:
		var bundle:Array=[];var count:=0
		for id:String in candidates:
			var size_:int=_resident[id].ids.size()
			if bundle.size()>=8 or count+size_>128:break
			bundle.append(id);count+=size_
		if bundle.size()>1:attempts.push_front(bundle)
	var started:=Time.get_ticks_usec()
	for units:Array in attempts:
		var ids:Array=[];var entries:Array=[]
		for id:String in units:ids.append_array(_resident[id].ids);entries.append_array(_units[id].entries)
		# Moving hinge state is captured only after an animation has finished.
		var tweens:Dictionary=_map.get_meta("fixture_tweens",{})
		if tweens.values().any(func(tween):return is_instance_valid(tween) and tween.is_running()):profile.last_wait="fixture_animation";continue
		var fixtures:Dictionary={};var digests:Dictionary={};var model_paths:Dictionary={}
		for entry:Dictionary in entries:
			if not entry.asset_path.is_empty():model_paths[entry.asset_path]=true
		for uuid:String in ids:
			var spec:Dictionary=_map.get_meta("stream_by_id")[uuid];var record:Dictionary=spec.get("ground_batch_record",{})
			if spec.extras.has("fixture"):fixtures[record.get("uuid",uuid.get_slice("__",0))]=float(spec.extras.fixture.open)
			if record.has("house_prefab"):digests[record.house_prefab.sha256]=true
			if record.has("asset_path"):model_paths[record.asset_path]=true
		var result:=Stream.retire_specs(_map,ids,true,nav)
		profile.retirement_attempts=int(profile.get("retirement_attempts",0))+1
		if not result.ok:
			profile.last_wait=result.error;profile.last_wait_unit=",".join(units)
			if not profile.has("wait_reasons"):profile.wait_reasons={}
			profile.wait_reasons[result.error]=int(profile.wait_reasons.get(result.error,0))+1
			# A complete validation is an indivisible transaction. Do not stack
			# several expensive refusals in the same interactive frame.
			if Time.get_ticks_usec()-started>=2000:return
			continue
		_queue.runtime_fixture_states.merge(fixtures,true)
		var requeue_began:=preload("res://scripts/world3d/load_trace.gd").begin("native.requeue")
		_queue.requeue_references(entries)
		_release_preparation_cache(entries)
		preload("res://scripts/world3d/load_trace.gd").elapsed("native.requeue",requeue_began,{"units":units.size(),"records":entries.size()})
		var release_began:=preload("res://scripts/world3d/load_trace.gd").begin("native.cache_release")
		Prefab.evict_geometry(digests)
		for path:String in model_paths:
			var usage:Node=_map.get_node_or_null("AssetResidency")
			var used:bool=usage.model_in_use(path) if usage!=null else _map.get_meta("stream_library",[]).any(func(spec):return spec.get("ground_batch_record",{}).get("asset_path","")==path)
			if not used:
				var scope:RefCounted=_map.get_meta("runtime_asset_cache_scope") if _map.has_meta("runtime_asset_cache_scope") else null
				var evicted:bool=scope.release(path) if scope!=null else preload("res://scripts/world_editor/asset_library.gd").evict_cached_scene(path)
				if evicted:_queue._prepared_paths.erase(path)
		# Drop hot-cache ownership; active maps retain resources and weak catalogues
		# continue reusing them. This never changes a live material or texture.
		Paint._materials.clear();Paint._textures.clear()
		preload("res://scripts/world3d/load_trace.gd").elapsed("native.cache_release",release_began,{"units":units.size(),"models":model_paths.size()})
		for id:String in units:_resident.erase(id);_retired[id]=true
		profile.retired_units+=units.size();profile.retired_specs+=result.removed;profile.last_wait=""
		profile.retirement_transactions=int(profile.get("retirement_transactions",0))+1
		profile.max_units_per_transaction=maxi(int(profile.get("max_units_per_transaction",0)),units.size())
		profile.resident_units=_resident.size()
		return

func _release_preparation_cache(entries:Array)->void:
	var document:RefCounted=_queue._doc
	document.load_box_meshes.clear()
	# These tables borrow admitted worker outputs, not a disposable global LRU.
	# Clearing them during another unit's retirement loses prepared road arrays
	# and terrain halos before that job publishes, forcing main-thread rebuilds.
	for entry:Dictionary in entries:
		var uuid:String=entry.compact_record.uuid
		document.load_surface_arrays.erase(uuid);document.terrain_neighbors.data.erase(uuid)
	# Material publication advances across frames. Keep its complete entries
	# until their owning jobs consume/discard them; release other hot owners.
	var protected:Dictionary={}
	for job:Dictionary in _queue._jobs.values():
		for prepared:Dictionary in job.get("result",{}).get("prefab_cpu",{}).values():
			for material:Dictionary in prepared.get("data",{}).get("materials",[]):protected[[material]]=true
	for key:Variant in document.load_material_pool.keys():
		if key is Array and not protected.has(key):document.load_material_pool.erase(key)

func _retirement_candidates(now:int)->Array:
	var keys:Array=_resident.keys();var candidates:Array=[];var pending_ids:Dictionary={}
	for item:Dictionary in _queue.pending:pending_ids[item.record.uuid]=true
	for scan:int in mini(16,keys.size()):
		_cursor%=keys.size();var id:String=keys[_cursor];_cursor+=1
		var state:Dictionary=_resident[id];var unit:Dictionary=_units[id]
		if _needed(unit):state.outside_since=-1;continue
		if int(state.outside_since)<0:state.outside_since=now;continue
		if now-int(state.outside_since)<grace_msec:continue
		var waiting:=false
		for entry:Dictionary in unit.entries:
			if pending_ids.has(entry.compact_record.uuid):waiting=true;break
		if not waiting:candidates.append(id)
	profile.scanned_units=int(profile.get("scanned_units",0))+mini(16,keys.size())
	return candidates
