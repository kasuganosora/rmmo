extends RefCounted
## One private MapLoader operation, consumed before Deferred activation. Only
## scalar membership and the compact records needed for requeue survive this
## preparation: never retain the library, spec dictionaries or geometry owners.
const Index=preload("res://scripts/world3d/stream_index.gd")
const Ordinary=preload("res://scripts/world3d/asset_residency.gd")
const CHUNK_M=preload("res://scripts/world3d/world_stream.gd").CHUNK_M
const EMPTY:Dictionary={}
static var enabled:=true # Component legacy control; no change to live publication.
var token:=RefCounted.new()
var consumed:=false
var profile:Dictionary={"directory_rows":0,"record_rows":0,"index_spec_rows":0,"building_registrations":0}
var ordinary:Dictionary={"catalog":{},"resident":{},"record_pins":{},"record_paths":{},"spec_namespaces":{},"namespace_specs":{},"model_namespaces":{},"unknown_asset_specs":{},"procedural_assets":{},"native_namespaces":{}}
var native:Dictionary={"units":{},"owners":{},"group_units":{},"model_entries":{},"resident":{},"changed":{},"observed_bounds":0}
var _directory:Dictionary={}
var _record_count:=0
var _spec_count:=0
var _revision:=0
var _complete:=false
var _unsafe:Dictionary={}
var _group_data:Dictionary={}

static func begin(directory:Dictionary,records:Array)->RefCounted:
	var result:=new()
	result._directory=directory;result._record_count=records.size()
	# Replace the two configure-time directory walks with one worker walk.
	for row:Dictionary in directory.get("rows",[]):
		result.profile.directory_rows+=1
		result.ordinary.record_paths[row.uuid]=row.asset_path
		var compact:Dictionary=directory.extras.rmmo_records[row.order]
		if row.classification=="spatial" and row.group_id.is_empty() and not row.asset_path.is_empty():
			result.ordinary.catalog[row.uuid]=_entry(row,compact,row.bounds,"")
		if not row.bounds_known:continue
		if row.group_id.is_empty() and not row.asset_path.is_empty():
			result.native.model_entries[row.uuid]=_entry(row,compact,row.bounds,"");continue
		if row.group_id.is_empty() and row.reason not in ["native_box","terrain_context_global","native_road","native_bridge","native_fortification","prefab_ownership_global"]:continue
		var unit:String=row.group_id if not row.group_id.is_empty() else "record:"+str(row.uuid)
		var bounds:AABB=directory.groups[row.group_id].bounds if not row.group_id.is_empty() else row.bounds
		if not result.native.units.has(unit):result.native.units[unit]={"entries":[],"bounds":bounds,"kind":"building" if unit.begins_with("building:") else "all"}
		result.native.units[unit].entries.append(_entry(row,compact,bounds,row.group_id))
		result.native.owners[row.uuid]=unit
	for record:Dictionary in records:
		result.profile.record_rows+=1
		result.ordinary.record_paths[record.uuid]=str(record.get("asset_path",""))
		if record.has("bridge_mesh") and str(record.get("asset_path","")).is_empty():result.ordinary.procedural_assets[record.uuid]=true
		result.ordinary.record_pins[record.uuid]=Ordinary.pin_for_record(record)
	return result

static func _entry(row:Dictionary,compact:Dictionary,bounds:AABB,group:String)->Dictionary:
	return {"record_index":row.order,"compact_record":compact,"bounds":bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":group,"memory_bytes":row.memory_bytes}

func mark_unsafe(namespace_:String)->void:
	_unsafe[namespace_]=true

func note_grouped_namespace(namespace_:String)->void:
	# Called in Index.build's existing group pass, after its full unsafe pass.
	if native.owners.has(namespace_) or not native.model_entries.has(namespace_) or _unsafe.has(namespace_):return
	var unit:="asset:"+namespace_;var entry:Dictionary=native.model_entries[namespace_]
	native.units[unit]={"entries":[entry],"bounds":entry.bounds,"kind":"building","source_uuid":namespace_,"support_ids":{}}
	native.owners[namespace_]=unit;ordinary.native_namespaces[namespace_]=true

func add_spec(spec:Dictionary,prefix:String)->void:
	# This runs inside the existing _append_state pass, after Landscape.bind.
	# Both service tables are final mutable owners, not a packet to rescan later.
	profile.index_spec_rows+=1
	var source_record:Dictionary=spec.get("ground_batch_record",EMPTY)
	var uuid:String=str(source_record.get("uuid",prefix))
	if ordinary.record_paths.has(prefix):uuid=prefix
	var path:String
	if ordinary.record_paths.has(uuid):path=ordinary.record_paths[uuid]
	elif ordinary.record_paths.has(prefix):path=ordinary.record_paths[prefix]
	else:path=source_record.get("asset_path",spec.get("extras",EMPTY).get("asset_path",""))
	if not path.is_empty() and not ordinary.spec_namespaces.has(spec.uuid):
		ordinary.unknown_asset_specs.erase(spec.uuid)
		ordinary.record_paths[uuid]=path;ordinary.spec_namespaces[spec.uuid]=uuid
		if not ordinary.namespace_specs.has(uuid):ordinary.namespace_specs[uuid]={}
		ordinary.namespace_specs[uuid][spec.uuid]=true
		if not ordinary.model_namespaces.has(path):ordinary.model_namespaces[path]={}
		ordinary.model_namespaces[path][uuid]=true
	elif path.is_empty() and not ordinary.procedural_assets.has(uuid) and not ordinary.procedural_assets.has(prefix) and source_record.get("kind","")=="asset":ordinary.unknown_asset_specs[spec.uuid]=true
	if not ordinary.catalog.has(uuid):uuid=prefix
	if not ordinary.native_namespaces.has(uuid) and ordinary.catalog.has(uuid):
		if not ordinary.resident.has(uuid):ordinary.resident[uuid]={"ids":[],"known_ids":{},"outside_since":-1,"pinned":ordinary.record_pins.get(uuid,"missing_authored_record")}
		var member:Dictionary=ordinary.resident[uuid]
		if not member.known_ids.has(spec.uuid):member.ids.append(spec.uuid);member.known_ids[spec.uuid]=true
		# The loader owns already validated runtime specs; do not authenticate
		# their complete schema a second time just to classify a retirement pin.
		if member.pinned.is_empty():member.pinned=Index._retire_dependency(spec,true)
	var native_uuid:String=source_record.get("uuid",prefix)
	if not native.owners.has(native_uuid):native_uuid=prefix
	if not native.owners.has(native_uuid):return
	var unit:String=native.owners[native_uuid]
	if not native.resident.has(unit):native.resident[unit]={"ids":[],"known_ids":{},"outside_since":-1}
	var resident:Dictionary=native.resident[unit]
	if not resident.known_ids.has(spec.uuid):resident.ids.append(spec.uuid);resident.known_ids[spec.uuid]=true
	var definition:Dictionary=native.units[unit]
	if definition.kind!="building":return
	if not definition.has("support_ids"):definition.support_ids={}
	var group:String=spec.get("render_building","")
	if not group.is_empty() and native.group_units.get(group,EMPTY).has(unit):return
	var bounds:AABB
	var supports:Dictionary={}
	if not group.is_empty() and _group_data.has(group):
		bounds=_group_data[group].bounds;supports=_group_data[group].supports
	else:
		var render:Dictionary=spec.get("render_bounds",spec)
		var low:Vector2i=render.chunk_min;var high:Vector2i=render.chunk_max
		bounds=AABB(Vector3(low.x*CHUNK_M,-100000,low.y*CHUNK_M),Vector3((high.x-low.x+1)*CHUNK_M,200000,(high.y-low.y+1)*CHUNK_M))
		if not group.is_empty():
			for support:Dictionary in spec.get("render_supports",[]):
				var id:String=support.get("ground_batch_record",EMPTY).get("uuid",str(support.uuid).get_slice("__",0))
				supports[id]=true
			_group_data[group]={"bounds":bounds,"supports":supports}
	definition.bounds=definition.bounds.merge(bounds);definition.support_ids.merge(supports,true)
	if not group.is_empty():
		if not native.group_units.has(group):native.group_units[group]={}
		native.group_units[group][unit]=true
	native.changed[unit]=true;native.observed_bounds+=1

func finish(index:Dictionary)->void:
	_spec_count=int(index.stream_building_count);_revision=int(index.stream_collision_revision)
	_complete=true;_unsafe={};_group_data={}

func claim(map_root:Node,queue:Node)->bool:
	# Private operation identity, not content authentication. Direct mutation of
	# source arrays/records without an index transaction is forbidden until this
	# one-shot handoff; we deliberately do not hash or retain those geometry owners.
	if not enabled or consumed or not _complete or queue._active:return false
	if not is_same(queue._reference_index,_directory):return false
	var state:Dictionary=map_root.get_meta("stream_append_state",EMPTY)
	if state.get("initial_residency_token")!=token:return false
	if int(map_root.get_meta("stream_collision_revision",-1))!=_revision:return false
	if int(map_root.get_meta("stream_building_count",-1))!=_spec_count or map_root.get_meta("stream_library",[]).size()!=_spec_count:return false
	if map_root.get_meta("extras",EMPTY).get("rmmo_records",[]).size()!=_record_count:return false
	consumed=true;_directory={};return true

func take_ordinary()->Dictionary:
	var result:=ordinary;ordinary={};return result

func take_native()->Dictionary:
	var result:=native;native={};return result
