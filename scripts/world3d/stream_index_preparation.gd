extends RefCounted
## Private derived-index construction with no resident index writes. The final
## append still validates the current public index and all incoming schemas.
const Index=preload("res://scripts/world3d/stream_index.gd")
const Landscape=preload("res://scripts/world3d/stream_landscape.gd")
const DERIVED_FIELDS:Array=["render_building","render_bounds","render_supports","render_dependents"]
const EMPTY_RECORD:Dictionary={}
static var shared_signature_defaults_enabled:=true
# Private schema/signature snapshots, prepared in slices and verified by pure
# native readers before the main-thread geometry checks. Diagnostic fallback
# keeps the ordinary complete schema/signature path available for comparison.
static var native_snapshot_validation_enabled:=true
var source:Array=[]
var projection:Array=[]
var signatures:Array=[]
var result:Dictionary={}
var error:=""
var phase:=0
var cursor:=0
var subphase:=0
var part:=0
var group_ids:Array=[]
var land:Array=[]
var supports:Array=[]
var groups:Dictionary={}
var structures:Dictionary={}
var lamps:Dictionary={}
var by_id:Dictionary={}
var known:Dictionary={}
var spatial:Dictionary={}
var props:Dictionary={}
var collisions:Dictionary={}
var raw_bounds:Dictionary={}
var append_state:Dictionary={"namespaces":{},"prefixes":{},"namespace_sizes":{},"retirement_units":{},"fixtures":{},"group_bounds":{},"group_cells":{},"group_order":{},"ground_cells":{},"ground_order":{},"dependents":{}}
var cell:Dictionary={}
var low:=Vector2i(2147483647,2147483647)
var high:=-low
var binding:Dictionary={}
var attached:Array=[]
var profile:Dictionary={"slices":0,"elapsed_us":0,"max_slice_us":0}
var owns_projection:=false
var runtime_source:Array=[]
var runtime_owned:=false
var publication_packet:RefCounted
var fixtures:Array=[]
var owned_groups:Dictionary={}
var owned_bounds:Dictionary={}
var owned_supports:Dictionary={}
var validation_snapshot:Array=[]
var snapshot_by_id:Dictionary={}
var snapshot_bounds:Dictionary={}
func begin(values:Array)->void:source=values.duplicate()
## Only for unpublished runtime specs exclusively owned by the calling job.
## Authored records/extras remain borrowed and untouched. Landscape uses the
## ordinary copied projection because it has mutable reverse dependency links.
func begin_owned(values:Array)->void:
	owns_projection=true;begin(values)
## The deferred loader owns these unpublished specs and immutable geometry
## exclusively until transfer. No external callback runs during preparation.
## Fixture pose updates are the sole writer and restart preparation on change.
func begin_runtime_owned(values:Array)->void:
	begin_owned(values);runtime_source=values;runtime_owned=true
	publication_packet=preload("res://scripts/world3d/publication_metadata.gd").new();publication_packet.begin(values)
func valid_runtime_owned(values:Array)->bool:
	return runtime_owned and owns_projection and phase==7 and error.is_empty() and is_same(runtime_source,values) and source.size()==values.size() and publication_packet.ready(values)
func accept()->void:owns_projection=false
func _notification(what:int)->void:
	# RefCounted is already marked invalid in PREDELETE; member calls fail here.
	if what==NOTIFICATION_PREDELETE:
		preload("res://scripts/world3d/resource_retirement.gd").defer_private_array(validation_snapshot)
	if what==NOTIFICATION_PREDELETE and owns_projection:
		for spec:Dictionary in projection:
			for field:String in DERIVED_FIELDS:spec.erase(field)
func _clear_owned_fields()->void:
	if not owns_projection:return
	for spec:Dictionary in projection:
		for field:String in DERIVED_FIELDS:spec.erase(field)
	owns_projection=false
static func signature(spec:Dictionary)->Array:
	# Defaults are eagerly evaluated, including when both records already
	# exist. Reuse one immutable empty Dictionary; native Array equality keeps
	# its strict types and recursive/NaN semantics unchanged.
	var empty:Dictionary=EMPTY_RECORD if shared_signature_defaults_enabled else {}
	var extra:Dictionary=spec.get("extras",empty);var record:Dictionary=spec.get("ground_batch_record",empty)
	var ground:=Landscape.ground_record(record)
	var landscape:bool=ground or record.has("road_mesh") or record.has("channel_mesh") or record.has("bridge_mesh") or record.has("fortification") or extra.get("rmmo_landscape_kind","")=="channel"
	return [spec.uuid,spec.mesh,spec.transform,spec.chunk_min,spec.chunk_max,spec.mesh.get_aabb(),extra.get("building",empty).get("id",""),record.get("building",empty).get("id",""),extra.get("rmmo_streetlamp_instance",""),extra.get("rmmo_streetlamp_crystal",false),extra.get("rmmo_collision",""),extra.has("rmmo_wind"),landscape,ground,Index._fixture_key(spec)]
static func _validation_copy(value:Dictionary)->Dictionary:
	# Clone the mutable schema/signature fields, preserving borrowed identity
	# for unrelated author arrays. These snapshots are private and unpublished.
	var snapshot:Dictionary=value.duplicate()
	if value.has("extras"):
		var extra:Dictionary=value.extras.duplicate()
		for key:String in ["building","fixture","fortification"]:
			if not extra.has(key):continue
			var fields:Dictionary=extra[key].duplicate()
			# Building IDs are schema-checked strings. Fixture/fortification IDs
			# are stringified by the index and may themselves be nested values.
			var identity:Variant=fields.get("id")
			if identity is Array or identity is Dictionary:fields.id=identity.duplicate(true)
			extra[key]=fields
		snapshot.extras=extra
	if value.has("ground_batch_record"):
		var record:Dictionary=value.ground_batch_record.duplicate()
		if record.has("building"):record.building=record.building.duplicate()
		if record.get("kind")=="box" and record.get("surface_id")=="ground" and record.has("size"):record.size=record.size.duplicate()
		snapshot.ground_batch_record=record
	return snapshot
func valid_owned_snapshot(values:Array)->bool:
	if not native_snapshot_validation_enabled or not owns_projection or phase!=7 or not error.is_empty() or source.size()!=values.size() or validation_snapshot.size()!=values.size():return false
	# Native equality includes exact Variant types of every validated field.
	# Snapshots were copied immediately after full schema/signature validation,
	# before yielding. Any mismatch uses the ordinary validator, never a hash.
	if not preload("res://scripts/world3d/spec_snapshot_validation.gd").matches(values,validation_snapshot,source):return false
	for i:int in values.size():
		var spec:Dictionary=values[i]
		if not is_same(spec,source[i]) or spec.mesh.get_aabb()!=signatures[i][5]:return false
		if owned_groups.has(spec.uuid):
			var id:String=owned_groups[spec.uuid]
			if not is_same(spec.get("render_bounds"),owned_bounds[id]) or not is_same(spec.get("render_supports"),owned_supports[id]):return false
	# Native value equality cannot prove the shared derived owners' identities.
	for id:String in owned_bounds:
		if owned_bounds[id]!=raw_bounds[id] or not owned_supports[id].is_empty():return false
	return true
func valid_for(values:Array,schema_checked:bool=false)->bool:
	if runtime_owned:return false # Consumed private packets cannot fall through to public snapshots.
	if phase!=7 or not error.is_empty() or source.size()!=values.size():return false
	for i:int in values.size():
		if not is_same(values[i],source[i]) or (not schema_checked and not Index._valid_append_spec(values[i])) or signature(values[i])!=signatures[i]:return false
		var spec:Dictionary=values[i]
		if owns_projection and owned_groups.has(spec.uuid):
			var id:String=owned_groups[spec.uuid]
			if spec.get("render_building")!=id or not is_same(spec.get("render_bounds"),owned_bounds[id]):return false
			if not is_same(spec.get("render_supports"),owned_supports[id]) or spec.has("render_dependents"):return false
		else:
			for field:String in DERIVED_FIELDS:
				if spec.has(field):return false
	if owns_projection:
		for id:String in owned_bounds:
			if owned_bounds[id]!=raw_bounds[id] or not owned_supports[id].is_empty():return false
	return true
func _next_phase()->void:
	phase+=1;cursor=0;part=0;subphase=0
func _start_cells(bounds:Dictionary,operations:Array)->void:
	cell={"low":bounds.chunk_min,"high":bounds.chunk_max,"x":bounds.chunk_min.x,"z":bounds.chunk_min.y,"operations":operations}
func _cell_step()->void:
	var key:=Vector2i(cell.x,cell.z)
	for operation:Array in cell.operations:
		var buckets:Dictionary=operation[0]
		if not buckets.has(key):buckets[key]=[]
		buckets[key].append(operation[1])
	cell.x+=1
	if cell.x>cell.high.x:cell.x=cell.low.x;cell.z+=1
	if cell.z>cell.high.y:cell={}
func _step()->void:
	if not cell.is_empty():_cell_step();return
	match phase:
		0:
			if cursor>=source.size():_next_phase();return
			var value:Variant=source[cursor];cursor+=1
			if not Index._valid_append_spec(value):error="invalid spec";phase=7;return
			if by_id.has(value.uuid):error="duplicate UUID";phase=7;return
			for field:String in DERIVED_FIELDS:
				if value.has(field):error="existing_derived_fields";phase=7;return
			if owns_projection and Landscape.landscape(value):error="owned_projection_ineligible";phase=7;return
			var mesh_bounds:AABB=value.mesh.get_aabb() if runtime_owned else AABB()
			if runtime_owned:
				publication_packet.add(value,mesh_bounds)
				if not publication_packet.error.is_empty():error=publication_packet.error;phase=7;return
				if value.get("extras",EMPTY_RECORD).has("fixture"):fixtures.append(value)
			else:signatures.append(signature(value))
			if owns_projection and native_snapshot_validation_enabled and not runtime_owned:
				var snapshot:Dictionary=_validation_copy(value)
				validation_snapshot.append(snapshot);snapshot_by_id[value.uuid]=snapshot
			var spec:Dictionary=value if owns_projection else value.duplicate();projection.append(spec)
			by_id[spec.uuid]=spec;known[spec.uuid]=true
			var prefix:String=spec.uuid.get_slice("__",0);append_state.prefixes[prefix]=true
			append_state.namespace_sizes[prefix]=int(append_state.namespace_sizes.get(prefix,0))+1
			if spec.uuid.contains("__"):
				append_state.namespaces[prefix]=true
				var bounds:AABB=spec.transform*(mesh_bounds if runtime_owned else spec.mesh.get_aabb());var extra:Dictionary=spec.get("extras",{})
				if not structures.has(prefix):structures[prefix]={"bounds":bounds,"wind":false,"solid":false}
				var row:Dictionary=structures[prefix];row.bounds=row.bounds.merge(bounds)
				row.wind=row.wind or extra.has("rmmo_wind");row.solid=row.solid or extra.get("rmmo_collision","")!="none"
				if extra.get("rmmo_streetlamp_crystal",false):lamps[prefix]=true
			var fixture:=Index._fixture_key(spec)
			if not fixture.is_empty():append_state.fixtures[fixture]=true
			Index._retirement_member(append_state,spec,fixture)
			_start_cells(spec,[[spatial,spec.uuid]])
		1:
			if cursor>=projection.size():_next_phase();return
			var spec:Dictionary=projection[cursor];cursor+=1
			var extra:Dictionary=spec.get("extras",{});var record:Dictionary=spec.get("ground_batch_record",{})
			var id:String=extra.get("building",{}).get("id",record.get("building",{}).get("id",""))
			var lamp:String=extra.get("rmmo_streetlamp_instance","");var prefix:String=spec.uuid.get_slice("__",0)
			if lamp.is_empty() and lamps.has(prefix):lamp=prefix
			if id.is_empty() and not lamp.is_empty():id="streetlamp:"+lamp
			if id.is_empty() and structures.has(prefix):
				var structure:Dictionary=structures[prefix]
				if structure.bounds.size.y>=12. and structure.solid and not structure.wind:id="structure:"+prefix
			var operations:Array=[]
			if id.is_empty() and not Landscape.landscape(spec):operations.append([props,spec])
			if extra.get("rmmo_collision","")!="none":operations.append([collisions,spec])
			if not operations.is_empty():_start_cells(spec,operations)
			if not id.is_empty():
				if not groups.has(id):groups[id]=[];group_ids.append(id)
				groups[id].append(spec)
		2:
			if cursor>=group_ids.size():_next_phase();return
			var id:String=group_ids[cursor];var members:Array=groups[id]
			if part<members.size():
				var spec:Dictionary=members[part];part+=1
				low=low.min(spec.chunk_min);high=high.max(spec.chunk_max);spec.render_building=id
				Index._retirement_group(append_state,spec,id)
				if owns_projection:owned_groups[spec.uuid]=id
			else:
				var bounds:Dictionary={"chunk":low,"chunk_min":low,"chunk_max":high}
				raw_bounds[id]=bounds;members[0].render_bounds=bounds
				cursor+=1;part=0;low=Vector2i(2147483647,2147483647);high=-low
		3:
			if cursor>=projection.size():_next_phase();return
			var spec:Dictionary=projection[cursor];cursor+=1
			if not Landscape.landscape(spec):return
			spec.render_bounds={"chunk":spec.chunk_min,"chunk_min":spec.chunk_min,"chunk_max":spec.chunk_max}
			spec.render_dependents=[];land.append(spec)
			if Landscape.ground(spec):supports.append(spec)
		4:
			if cursor>=group_ids.size():_next_phase();return
			var members:Array=groups[group_ids[cursor]]
			if binding.is_empty():
				binding=members[0].render_bounds.duplicate()
				if owns_projection:owned_bounds[group_ids[cursor]]=binding;owned_supports[group_ids[cursor]]=attached
				if not validation_snapshot.is_empty():snapshot_bounds[group_ids[cursor]]=binding.duplicate()
			if subphase==0:
				if part>=supports.size():subphase=1;part=0;return
				var tile:Dictionary=supports[part];part+=1
				if tile.chunk_min.x<=binding.chunk_max.x and tile.chunk_max.x>=binding.chunk_min.x and tile.chunk_min.y<=binding.chunk_max.y and tile.chunk_max.y>=binding.chunk_min.y:attached.append(tile)
			elif subphase==1:
				if part>=attached.size():subphase=2;part=0;return
				var tile:Dictionary=attached[part];part+=1
				binding.chunk_min=binding.chunk_min.min(tile.chunk_min);binding.chunk_max=binding.chunk_max.max(tile.chunk_max)
			elif subphase==2:
				if part>=members.size():subphase=3;part=0;return
				if not validation_snapshot.is_empty():
					var snapshot:Dictionary=snapshot_by_id[members[part].uuid]
					snapshot.render_building=group_ids[cursor];snapshot.render_bounds=snapshot_bounds[group_ids[cursor]];snapshot.render_supports=[]
				members[part].render_bounds=binding;members[part].render_supports=attached
				if runtime_owned:publication_packet.group_member(members[part],group_ids[cursor])
				part+=1
			else:
				if part<attached.size():attached[part].render_dependents.append(binding);part+=1;return
				cursor+=1;part=0;subphase=0;binding={};attached=[]
		5:
			if cursor>=supports.size():_next_phase();return
			var spec:Dictionary=supports[cursor];cursor+=1
			append_state.ground_order[spec.uuid]=append_state.ground_order.size();append_state.dependents[spec.uuid]=[]
			_start_cells(spec,[[append_state.ground_cells,spec.uuid]])
		6:
			if cursor>=group_ids.size():
				result={"stream_index":spatial,"stream_by_id":by_id,"stream_known":known,"stream_landscape":land,"stream_building_groups":groups,"stream_prop_index":props,"stream_collision_index":collisions,"stream_collision_revision":1,"stream_collision_candidate_cache":{},"stream_building_count":projection.size(),"stream_append_state":append_state}
				phase=7;return
			var id:String=group_ids[cursor]
			if subphase==0:
				append_state.group_bounds[id]=raw_bounds[id];append_state.group_order[id]=append_state.group_order.size()
				_start_cells(raw_bounds[id],[[append_state.group_cells,id]]);subphase=1;return
			var rows:Array=groups[id][0].get("render_supports",[])
			if part<rows.size():append_state.dependents[rows[part].uuid].append(id);part+=1
			else:cursor+=1;part=0;subphase=0
func advance(budget_usec:int)->bool:
	var began:=Time.get_ticks_usec();var advanced:=false
	while phase<7 and (not advanced or budget_usec<=0 or Time.get_ticks_usec()-began<budget_usec):
		advanced=true;_step()
	var elapsed:=Time.get_ticks_usec()-began
	profile.slices+=1;profile.elapsed_us+=elapsed;profile.max_slice_us=maxi(int(profile.max_slice_us),elapsed)
	return phase==7
func dispose()->void:
	_clear_owned_fields();owned_groups={};owned_bounds={};owned_supports={}
	runtime_source=[];publication_packet=null;fixtures=[];runtime_owned=false
	preload("res://scripts/world3d/resource_retirement.gd").defer_private_array(validation_snapshot)
	validation_snapshot=[];snapshot_by_id={};snapshot_bounds={}
	source=[];projection=[];signatures=[];result={};groups={};structures={};lamps={};by_id={};known={};spatial={};props={};collisions={};raw_bounds={};append_state={};cell={};binding={};attached=[];land=[];supports=[];group_ids=[];phase=7
