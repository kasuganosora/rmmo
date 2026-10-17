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
var _resident:Dictionary={}
var _retired:Dictionary={}
var _clock:=0.
var _cursor:=0
func configure(host:Node,map_root:Node,queue:Node)->void:
	name="NativeResidency";set_meta("stream_instance",true);_host=host;_map=map_root;_queue=queue
	var index:Dictionary=queue._reference_index
	for row:Dictionary in index.get("rows",[]):
		if not row.bounds_known:continue
		if row.group_id.is_empty() and not row.asset_path.is_empty():continue # Existing prop service owns these.
		if row.group_id.is_empty() and row.reason not in ["native_box","terrain_context_global","native_road","native_bridge","native_fortification","prefab_ownership_global"]:continue
		var unit:String=row.group_id if not row.group_id.is_empty() else "record:"+str(row.uuid)
		var bounds:AABB=index.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds
		if not _units.has(unit):_units[unit]={"entries":[],"bounds":bounds,"kind":"building" if unit.begins_with("building:") else "all"}
		var entry:={"record_index":row.order,"compact_record":index.extras.rmmo_records[row.order],"bounds":bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":row.group_id,"memory_bytes":row.memory_bytes}
		_units[unit].entries.append(entry);_owners[row.uuid]=unit
	observe(map_root.get_meta("stream_library",[]));queue.published.connect(observe)
func observe(specs:Array)->void:
	for spec:Dictionary in specs:
		var uuid:String=spec.get("ground_batch_record",{}).get("uuid",str(spec.uuid).get_slice("__",0))
		if not _owners.has(uuid):continue
		var unit:String=_owners[uuid]
		if not _resident.has(unit):
			_resident[unit]={"ids":[],"outside_since":-1}
			if _retired.erase(unit):profile.revisits+=1
		if not spec.uuid in _resident[unit].ids:_resident[unit].ids.append(spec.uuid)
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
	if not is_instance_valid(_queue) or not _queue._active:return
	var nav:Node=_host._navigation
	if not is_instance_valid(nav) or not nav.streaming_geometry:return
	var keys:Array=_resident.keys()
	for scan in mini(16,keys.size()):
		_cursor%=keys.size();var id:String=keys[_cursor];_cursor+=1
		var state:Dictionary=_resident[id];var unit:Dictionary=_units[id]
		if _needed(unit):state.outside_since=-1;continue
		if int(state.outside_since)<0:state.outside_since=now;continue
		if now-int(state.outside_since)<grace_msec:continue
		var waiting:=false
		for entry:Dictionary in unit.entries:
			if _queue.pending.any(func(item):return item.record.uuid==entry.compact_record.uuid):waiting=true
		if waiting:continue
		var ids:Array=state.ids;var check:=Stream.can_retire_specs(_map,ids,true)
		if not check.ok:profile.last_wait=check.error;continue
		# Moving hinge state is captured only after an animation has finished.
		var tweens:Dictionary=_map.get_meta("fixture_tweens",{})
		if tweens.values().any(func(tween):return is_instance_valid(tween) and tween.is_running()):profile.last_wait="fixture_animation";continue
		var fixtures:Dictionary={};var digests:Dictionary={};var model_paths:Dictionary={}
		for uuid:String in ids:
			var spec:Dictionary=_map.get_meta("stream_by_id")[uuid];var record:Dictionary=spec.get("ground_batch_record",{})
			if spec.extras.has("fixture"):fixtures[record.get("uuid",uuid.get_slice("__",0))]=float(spec.extras.fixture.open)
			if record.has("house_prefab"):digests[record.house_prefab.sha256]=true
			if record.has("asset_path"):model_paths[record.asset_path]=true
		var released:Dictionary=nav.try_retire_specs(ids)
		if not released.ok:profile.last_wait=released.reason;continue
		var result:=Stream.retire_specs(_map,ids,true)
		if not result.ok:
			var survivors:Array=[]
			for uuid:String in ids:
				if _map.get_meta("stream_by_id",{}).has(uuid):survivors.append(_map.get_meta("stream_by_id")[uuid])
			nav.append_specs(survivors);profile.last_wait=result.error;continue
		_queue.runtime_fixture_states.merge(fixtures,true)
		for entry:Dictionary in unit.entries:_queue.requeue_reference(entry)
		_queue._doc.load_box_meshes.clear();_queue._doc.load_material_pool.clear();_queue._doc.load_surface_arrays.clear()
		_queue._doc.terrain_neighbors=preload("res://scripts/world3d/terrain_neighbors.gd").new()
		Prefab.evict_geometry(digests)
		for path:String in model_paths:
			if not _map.get_meta("stream_library",[]).any(func(spec):return spec.get("ground_batch_record",{}).get("asset_path","")==path):
				preload("res://scripts/world_editor/asset_library.gd").evict_cached_scene(path);_queue._prepared_paths.erase(path)
		# Drop hot-cache ownership; active maps retain resources and weak catalogues
		# continue reusing them. This never changes a live material or texture.
		Paint._materials.clear();Paint._textures.clear()
		_resident.erase(id);_retired[id]=true;profile.retired_units+=1;profile.retired_specs+=result.removed;profile.last_wait=""
		return
