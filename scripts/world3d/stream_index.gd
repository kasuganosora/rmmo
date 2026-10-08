extends RefCounted
## Worker-owned immutable spatial data. No SceneTree or renderer calls.
const Landscape=preload("res://scripts/world3d/stream_landscape.gd")
static func build(library:Array)->Dictionary:
	var result:Dictionary={}
	var index:Dictionary={};var by_id:Dictionary={};var known:Dictionary={};var lamp_roots:Dictionary={}
	var structures:Dictionary={}
	for spec:Dictionary in library:
		by_id[spec.uuid]=spec;known[spec.uuid]=true
		# Imported multi-mesh towers need whole-asset town visibility just as
		# native houses do. Derive this from geometry, never from a display name.
		# Foliage/cloth retain their own near residency and authored LOD policy.
		if str(spec.uuid).contains("__") and spec.get("mesh") is Mesh:
			var asset_id:=str(spec.uuid).get_slice("__",0)
			var bounds:AABB=spec.transform*spec.mesh.get_aabb()
			var extra:Dictionary=spec.get("extras",{})
			if not structures.has(asset_id):structures[asset_id]={"bounds":bounds,"wind":false,"solid":false}
			var row:Dictionary=structures[asset_id]
			row.bounds=row.bounds.merge(bounds)
			row.wind=row.wind or extra.has("rmmo_wind")
			row.solid=row.solid or extra.get("rmmo_collision","")!="none"
		# Previously saved flat glTF already tags the crystal but not its sibling parts.
		# Recover that explicit fixture's asset namespace without rewriting user maps.
		if spec.get("extras",{}).get("rmmo_streetlamp_crystal",false) and str(spec.uuid).contains("__"):
			lamp_roots[str(spec.uuid).get_slice("__",0)]=true
		for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
			for x in range(spec.chunk_min.x,spec.chunk_max.x+1):
				var key:=Vector2i(x,z)
				if not index.has(key):index[key]=[]
				index[key].append(spec.uuid)
	result.stream_index=index;result.stream_by_id=by_id;result.stream_known=known
	var groups:Dictionary={}
	var props:Dictionary={};var collisions:Dictionary={}
	for spec:Dictionary in library:
		var id:String=spec.get("ground_batch_record",{}).get("building",{}).get("id","")
		# Keep each whole streetlamp with its supporting landscape at town view distance.
		# Physics still uses the original near-field bounds and collision index.
		var lamp_id:String=spec.get("extras",{}).get("rmmo_streetlamp_instance","")
		var asset_id:=str(spec.uuid).get_slice("__",0)
		if lamp_id.is_empty() and lamp_roots.has(asset_id):lamp_id=asset_id
		if id.is_empty() and not lamp_id.is_empty():id="streetlamp:"+lamp_id
		if id.is_empty() and structures.has(asset_id):
			var structure:Dictionary=structures[asset_id]
			if structure.bounds.size.y>=12.0 and structure.solid and not structure.wind:id="structure:"+asset_id
		var solid:bool=spec.get("extras",{}).get("rmmo_collision","")!="none"
		if id.is_empty() or solid:
			for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
				for x in range(spec.chunk_min.x,spec.chunk_max.x+1):
					var key:=Vector2i(x,z)
					if id.is_empty() and not Landscape.landscape(spec):
						if not props.has(key):props[key]=[]
						props[key].append(spec)
					if solid:
						if not collisions.has(key):collisions[key]=[]
						collisions[key].append(spec)
		if id.is_empty():continue
		if not groups.has(id):groups[id]=[]
		groups[id].append(spec)
	for id:String in groups:
		var low:=Vector2i(2147483647,2147483647);var high:=-low
		for spec:Dictionary in groups[id]:low=low.min(spec.chunk_min);high=high.max(spec.chunk_max)
		for spec:Dictionary in groups[id]:
			spec.render_building=id;spec.render_bounds={"chunk":low,"chunk_min":low,"chunk_max":high}
	result.stream_landscape=Landscape.bind(library,groups)
	result.stream_building_groups=groups
	result.stream_prop_index=props;result.stream_collision_index=collisions
	result.stream_building_count=library.size()
	result.stream_append_state=_append_state(library,groups,result.stream_landscape)
	return result

# Append bookkeeping is derived once alongside the full index. It contains only
# spatial IDs and ordering, never a second scene/mesh representation.
static func _cells_add(buckets:Dictionary,bounds:Dictionary,value:Variant)->void:
	for z in range(bounds.chunk_min.y,bounds.chunk_max.y+1):
		for x in range(bounds.chunk_min.x,bounds.chunk_max.x+1):
			var key:=Vector2i(x,z)
			if not buckets.has(key):buckets[key]=[]
			buckets[key].append(value)

static func _fixture_key(spec:Dictionary)->String:
	var extra:Dictionary=spec.get("extras",{})
	if not extra.has("fixture"):return ""
	var owner:String=preload("res://scripts/world3d/building_fixtures.gd").owner_id(extra)
	return JSON.stringify([owner,str(extra.fixture.get("id",""))])

static func _append_state(library:Array,groups:Dictionary,land:Array)->Dictionary:
	var state:={"namespaces":{},"prefixes":{},"fixtures":{},"group_bounds":{},"group_cells":{},"group_order":{},"ground_cells":{},"ground_order":{},"dependents":{}}
	for spec:Dictionary in library:
		state.prefixes[str(spec.uuid).get_slice("__",0)]=true
		if str(spec.uuid).contains("__"):state.namespaces[str(spec.uuid).get_slice("__",0)]=true
		var fixture:=_fixture_key(spec)
		if not fixture.is_empty():state.fixtures[fixture]=true
	for spec:Dictionary in land:
		if not Landscape.ground(spec):continue
		state.ground_order[spec.uuid]=state.ground_order.size();state.dependents[spec.uuid]=[]
		_cells_add(state.ground_cells,spec,spec.uuid)
	for id:String in groups:
		var low:=Vector2i(2147483647,2147483647);var high:=-low
		for spec:Dictionary in groups[id]:low=low.min(spec.chunk_min);high=high.max(spec.chunk_max)
		var bounds:={"chunk":low,"chunk_min":low,"chunk_max":high}
		state.group_bounds[id]=bounds;state.group_order[id]=state.group_order.size()
		_cells_add(state.group_cells,bounds,id)
		for support:Dictionary in groups[id][0].get("render_supports",[]):state.dependents[support.uuid].append(id)
	return state

static func _append_failure(reason:String)->Dictionary:
	return {"ok":false,"error":reason}

static func _valid_append_spec(value:Variant)->bool:
	if not value is Dictionary or not value.get("uuid") is String or value.uuid.is_empty():return false
	if not value.get("mesh") is Mesh or not value.get("transform") is Transform3D:return false
	if not value.get("chunk_min") is Vector2i or not value.get("chunk_max") is Vector2i:return false
	if value.chunk_min.x>value.chunk_max.x or value.chunk_min.y>value.chunk_max.y:return false
	if not value.get("extras",{}) is Dictionary or not value.get("ground_batch_record",{}) is Dictionary:return false
	var extra:Dictionary=value.get("extras",{});var record:Dictionary=value.get("ground_batch_record",{})
	if not record.get("building",{}) is Dictionary or not record.get("building",{}).get("id","") is String:return false
	if not extra.get("rmmo_streetlamp_instance","") is String:return false
	for field in ["fixture","building","fortification"]:
		if extra.has(field) and not extra[field] is Dictionary:return false
	if record.get("kind")=="box" and record.get("surface_id")=="ground":
		var size:Variant=record.get("size",[1,3,1])
		if not size is Array or size.size()<2 or not (size[1] is int or size[1] is float):return false
	return true

static func _query_ids(buckets:Dictionary,bounds:Dictionary)->Dictionary:
	var found:Dictionary={}
	for z in range(bounds.chunk_min.y,bounds.chunk_max.y+1):
		for x in range(bounds.chunk_min.x,bounds.chunk_max.x+1):
			for id:Variant in buckets.get(Vector2i(x,z),[]):found[id]=true
	return found

static func _merge_buckets(target:Dictionary,addition:Dictionary,originals:Dictionary={})->void:
	for key:Variant in addition:
		if not target.has(key):target[key]=[]
		for value:Variant in addition[key]:target[key].append(originals[value.uuid] if value is Dictionary else value)

## Atomic main-thread publication only: callers own the library append and
## residency dirty notification. Existing indexes must come from build/append.
## Every imported namespace, building and fixture must arrive as a whole batch.
static func append(existing:Dictionary,additions:Array)->Dictionary:
	if not existing.get("stream_append_state") is Dictionary:return _append_failure("index lacks append bookkeeping")
	var originals:Dictionary={};var state:Dictionary=existing.stream_append_state
	for key in ["stream_by_id","stream_known","stream_index","stream_prop_index","stream_collision_index","stream_building_groups"]:
		if not existing.get(key) is Dictionary:return _append_failure("invalid existing index")
	for key in ["namespaces","prefixes","fixtures","group_bounds","group_cells","group_order","ground_cells","ground_order","dependents"]:
		if not state.get(key) is Dictionary:return _append_failure("invalid append bookkeeping")
	if not existing.get("stream_landscape") is Array or not existing.get("stream_building_count") is int:return _append_failure("invalid existing index")
	if additions.is_empty():return {"ok":true,"data":existing,"added":0,"affected_groups":0,"affected_existing_specs":[]}
	for value:Variant in additions:
		if not _valid_append_spec(value):return _append_failure("invalid spec")
		var id:String=value.uuid
		if originals.has(id) or existing.stream_by_id.has(id):return _append_failure("duplicate UUID: "+id)
		var prefix:=id.get_slice("__",0)
		if state.namespaces.has(prefix) or (id.contains("__") and state.prefixes.has(prefix)):return _append_failure("split imported namespace: "+id)
		var fixture:=_fixture_key(value)
		if not fixture.is_empty() and state.fixtures.has(fixture):return _append_failure("split fixture: "+fixture)
		originals[id]=value
	# A private small fragment validates derived grouping before any caller-owned
	# dictionary or new spec is touched. Mesh resources remain shared/read-only.
	var fragment:=build(additions.duplicate(true));var fresh:Dictionary=fragment.stream_append_state
	for id:String in fragment.stream_building_groups:
		if existing.stream_building_groups.has(id):return _append_failure("split building group: "+id)
	var affected:Dictionary={}
	for uuid:String in fresh.ground_order:
		for id:String in _query_ids(state.group_cells,originals[uuid]):affected[id]=true
	for id:String in fragment.stream_building_groups:affected[id]=true
	var ground_offset:int=state.ground_order.size();var group_offset:int=state.group_order.size()
	var plans:Dictionary={};var touched:Dictionary={}
	for id:String in affected:
		var old:bool=existing.stream_building_groups.has(id)
		var base:Dictionary=state.group_bounds[id] if old else fresh.group_bounds[id]
		var candidates:=_query_ids(state.ground_cells,base)
		candidates.merge(_query_ids(fresh.ground_cells,base),true)
		var ordered:Array=candidates.keys()
		ordered.sort_custom(func(a,b):return int(state.ground_order.get(a,ground_offset+int(fresh.ground_order.get(a,0))))<int(state.ground_order.get(b,ground_offset+int(fresh.ground_order.get(b,0)))))
		var supports:Array=[];var bounds:Dictionary=base.duplicate()
		for uuid:String in ordered:
			var support:Dictionary=existing.stream_by_id[uuid] if existing.stream_by_id.has(uuid) else originals[uuid]
			supports.append(support);touched[uuid]=true
			bounds.chunk_min=bounds.chunk_min.min(support.chunk_min);bounds.chunk_max=bounds.chunk_max.max(support.chunk_max)
		if old:
			for support:Dictionary in existing.stream_building_groups[id][0].render_supports:touched[support.uuid]=true
		plans[id]={"bounds":bounds,"supports":supports}
	# Commit has no await or fallible I/O. Preserve existing maps, buckets and
	# spec objects; update only dependency groups intersected by new ground.
	for uuid:String in originals:
		var spec:Dictionary=originals[uuid];var prepared:Dictionary=fragment.stream_by_id[uuid]
		for field in ["render_building","render_bounds","render_supports","render_dependents"]:
			spec.erase(field)
			if prepared.has(field) and field not in ["render_supports","render_dependents"]:spec[field]=prepared[field]
		if Landscape.landscape(spec):spec.render_dependents=[]
		existing.stream_by_id[uuid]=spec;existing.stream_known[uuid]=true
	for key in ["stream_index","stream_prop_index","stream_collision_index","stream_building_groups"]:
		_merge_buckets(existing[key],fragment[key],originals)
	for spec:Dictionary in fragment.stream_landscape:existing.stream_landscape.append(originals[spec.uuid])
	for key in ["namespaces","prefixes","fixtures","group_bounds"]:state[key].merge(fresh[key],true)
	for key in ["group_cells","ground_cells"]:_merge_buckets(state[key],fresh[key])
	for id:String in fresh.group_order:state.group_order[id]=group_offset+int(fresh.group_order[id])
	for uuid:String in fresh.ground_order:state.ground_order[uuid]=ground_offset+int(fresh.ground_order[uuid])
	for uuid:String in fresh.ground_order:state.dependents[uuid]=[]
	for id:String in plans:
		var members:Array=existing.stream_building_groups[id]
		var bounds:Dictionary=members[0].render_bounds
		bounds.clear();bounds.merge(plans[id].bounds,true)
		for member:Dictionary in members:member.render_bounds=bounds;member.render_supports=plans[id].supports
	for uuid:String in touched:
		var dependents:Array=state.dependents[uuid]
		for id:String in affected:dependents.erase(id)
		for id:String in plans:
			if plans[id].supports.any(func(spec):return spec.uuid==uuid):dependents.append(id)
		dependents.sort_custom(func(a,b):return state.group_order[a]<state.group_order[b])
		var support:Dictionary=existing.stream_by_id[uuid]
		support.render_dependents.clear()
		for id:String in dependents:support.render_dependents.append(existing.stream_building_groups[id][0].render_bounds)
	# These old entries can change residency without a camera/chunk change.
	# Return their original references so the caller can replan just this delta.
	var changed_existing:Dictionary={}
	for id:String in plans:
		for member:Dictionary in existing.stream_building_groups[id]:
			if not originals.has(member.uuid):changed_existing[member.uuid]=member
	for uuid:String in touched:
		if not originals.has(uuid):changed_existing[uuid]=existing.stream_by_id[uuid]
	existing.stream_building_count+=additions.size()
	return {"ok":true,"data":existing,"added":additions.size(),"affected_groups":affected.size(),"affected_existing_specs":changed_existing.values()}
