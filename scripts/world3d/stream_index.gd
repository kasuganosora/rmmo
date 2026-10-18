extends RefCounted
## Worker-owned immutable spatial data. No SceneTree or renderer calls.
const Landscape=preload("res://scripts/world3d/stream_landscape.gd")
const EMPTY_RECORD:Dictionary={}
const SPEC_FIELDS:Array=["uuid","mesh","transform","chunk_min","chunk_max"]
const DICTIONARY_EXTRAS_FIELDS:Array=["fixture","building","fortification"]
const SPATIAL_FIELDS:Array=["stream_index","stream_prop_index","stream_collision_index"]
static var legacy_owned_rebuild_enabled:=false
static func build(library:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_index.build") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
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
		# Authored membership survives render-merge exclusions (lights, LODs,
		# glass and wind). Batch eligibility must not change building residency.
		var id:String=spec.get("extras",{}).get("building",{}).get("id",spec.get("ground_batch_record",{}).get("building",{}).get("id",""))
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
	var group_bounds:Dictionary={}
	for id:String in groups:
		var low:=Vector2i(2147483647,2147483647);var high:=-low
		for spec:Dictionary in groups[id]:low=low.min(spec.chunk_min);high=high.max(spec.chunk_max)
		var bounds:={"chunk":low,"chunk_min":low,"chunk_max":high}
		group_bounds[id]=bounds;groups[id][0].render_bounds=bounds
		# Landscape.bind installs one final shared bound per group. Do not
		# allocate a disposable bound dictionary for every imported component.
		for spec:Dictionary in groups[id]:spec.render_building=id
	result.stream_landscape=Landscape.bind(library,groups)
	result.stream_building_groups=groups
	result.stream_prop_index=props;result.stream_collision_index=collisions
	# This revision describes index membership, not residency/source requests.
	# A full rebuild also replaces the index identity and clears cached owners.
	result.stream_collision_revision=1
	result.stream_collision_candidate_cache={}
	result.stream_building_count=library.size()
	result.stream_append_state=_append_state(library,groups,result.stream_landscape,group_bounds)
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

static func _append_state(library:Array,groups:Dictionary,land:Array,raw_bounds:Dictionary={})->Dictionary:
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
		var bounds:Dictionary=raw_bounds.get(id,{})
		if bounds.is_empty():
			var low:=Vector2i(2147483647,2147483647);var high:=-low
			for spec:Dictionary in groups[id]:low=low.min(spec.chunk_min);high=high.max(spec.chunk_max)
			bounds={"chunk":low,"chunk_min":low,"chunk_max":high}
		state.group_bounds[id]=bounds;state.group_order[id]=state.group_order.size()
		_cells_add(state.group_cells,bounds,id)
		for support:Dictionary in groups[id][0].get("render_supports",[]):state.dependents[support.uuid].append(id)
	return state

static func _append_failure(reason:String)->Dictionary:
	return {"ok":false,"error":reason}

static func _valid_append_spec(value:Variant)->bool:
	if not value is Dictionary or not value.has_all(SPEC_FIELDS):return false
	var spec:Dictionary=value
	if not spec.uuid is String or spec.uuid.is_empty():return false
	if not spec.mesh is Mesh or not spec.transform is Transform3D:return false
	if not spec.chunk_min is Vector2i or not spec.chunk_max is Vector2i:return false
	if spec.chunk_min.x>spec.chunk_max.x or spec.chunk_min.y>spec.chunk_max.y:return false
	# A default expression is evaluated even on a hit. Reuse this read-only
	# empty value rather than allocate several throwaway dictionaries per spec
	# during each complete retirement validation.
	var raw_extra:Variant=spec.get("extras",EMPTY_RECORD);var raw_record:Variant=spec.get("ground_batch_record",EMPTY_RECORD)
	if not raw_extra is Dictionary or not raw_record is Dictionary:return false
	var extra:Dictionary=raw_extra;var record:Dictionary=raw_record
	var record_building:Variant=record.get("building",EMPTY_RECORD)
	if not record_building is Dictionary or not record_building.get("id","") is String:return false
	if not extra.get("rmmo_streetlamp_instance","") is String:return false
	for field in DICTIONARY_EXTRAS_FIELDS:
		if extra.has(field) and not extra[field] is Dictionary:return false
	if not extra.get("building",EMPTY_RECORD).get("id","") is String:return false
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
		var values:Array=addition[key]
		if originals.is_empty() or values.is_empty() or not values[0] is Dictionary:
			target[key].append_array(values)
		else:
			for value:Dictionary in values:target[key].append(originals[value.uuid])

static func _retire_failure(reason:String)->Dictionary:
	return {"ok":false,"error":reason,"removed":0,"removed_ids":[],"removed_specs":[]}

static func _retire_dependency(spec:Dictionary)->String:
	if not _valid_append_spec(spec):return "invalid spec"
	if bool(spec.get("native_visual",false)):return "native visual"
	for field in ["render_building","render_bounds","render_supports","render_dependents"]:
		if spec.has(field):return field
	var extra:Dictionary=spec.get("extras",{});var record:Dictionary=spec.get("ground_batch_record",{})
	for field in ["building","fixture","fortification","house_prefab"]:
		if record.has(field) or extra.has(field):return field
	if Landscape.landscape(spec):return "landscape"
	# Runtime retirement currently supports ordinary asset records only. A bare
	# spec without an authored record remains usable by pure index consumers.
	if not record.is_empty() and record.get("kind","")!="asset":return "non-asset record"
	for field in ["surface_paint","prefab_materials","material","material_state","material_overrides","event","event_template"]:
		if record.has(field):return field
	if extra.has("rmmo_streetlamp_instance") or extra.has("rmmo_streetlamp_crystal"):return "streetlamp"
	if extra.get("kind","") in ["npc","gather","event","teleport","warp"] or extra.has("event") or bool(extra.get("hostile",false)) or bool(extra.get("ally",false)):return "gameplay owner"
	return ""

static func _retire_plan(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_index._retire_plan") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	for key in ["stream_by_id","stream_known","stream_index","stream_prop_index","stream_collision_index","stream_building_groups","stream_append_state"]:
		if not existing.get(key) is Dictionary:return _retire_failure("invalid existing index: "+key)
	var state:Dictionary=existing.stream_append_state
	for key in ["namespaces","prefixes","fixtures","group_bounds","group_cells","group_order","ground_cells","ground_order","dependents"]:
		if not state.get(key) is Dictionary:return _retire_failure("invalid append bookkeeping: "+key)
	if not existing.get("stream_landscape") is Array or not existing.get("stream_building_count") is int:return _retire_failure("invalid existing index")
	if library.size()!=existing.stream_building_count or library.size()!=existing.stream_by_id.size():return _retire_failure("library/index size mismatch")
	var selected:Dictionary={};var prefixes:Dictionary={};var cells:Dictionary={}
	for value:Variant in ids:
		if not value is String or value.is_empty():return _retire_failure("invalid retirement UUID")
		if selected.has(value):return _retire_failure("duplicate retirement UUID: "+value)
		if not existing.stream_by_id.has(value):return _retire_failure("unknown retirement UUID: "+value)
		var spec:Variant=existing.stream_by_id[value]
		if not spec is Dictionary:return _retire_failure("invalid resident spec: "+value)
		var dependency:=_retire_dependency(spec)
		if not dependency.is_empty():return _retire_failure("pinned dependency "+dependency+": "+value)
		selected[value]=true;prefixes[value.get_slice("__",0)]=true
		for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
			for x in range(spec.chunk_min.x,spec.chunk_max.x+1):cells[Vector2i(x,z)]=true
	# Validate the complete request before mutating any shared dictionary/array.
	# This is a metadata scan, not a rebuild or a second copy of resident specs.
	var seen:Dictionary={};var removed:Array=[];var ordered:Array=[]
	for value:Variant in library:
		if not value is Dictionary or not value.get("uuid") is String:return _retire_failure("invalid library spec")
		var id:String=value.uuid
		if seen.has(id) or not existing.stream_by_id.has(id) or not is_same(existing.stream_by_id[id],value) or not existing.stream_known.has(id):return _retire_failure("library/index identity mismatch: "+id)
		seen[id]=true
		var prefix:=id.get_slice("__",0)
		if prefixes.has(prefix) and not selected.has(id):return _retire_failure("split imported namespace: "+prefix)
		if selected.has(id):removed.append(value);ordered.append(id)
	for prefix:String in prefixes:
		if not state.prefixes.has(prefix):return _retire_failure("missing prefix bookkeeping: "+prefix)
	for id:String in selected:
		if id.contains("__") and not state.namespaces.has(id.get_slice("__",0)):return _retire_failure("missing namespace bookkeeping: "+id)
	# Derived groups remain pinned even if a caller has stripped a spec's tags.
	for members:Variant in existing.stream_building_groups.values():
		if not members is Array:return _retire_failure("invalid building group")
		for member:Variant in members:
			if member is Dictionary and selected.has(member.get("uuid")):return _retire_failure("pinned building group: "+str(member.uuid))
	for member:Variant in existing.stream_landscape:
		if member is Dictionary and selected.has(member.get("uuid")):return _retire_failure("pinned landscape: "+str(member.uuid))
	for key:Vector2i in cells:
		for field in ["stream_index","stream_prop_index","stream_collision_index"]:
			if not existing[field].get(key,[]) is Array:return _retire_failure("invalid spatial bucket: "+field)
	return {"ok":true,"selected":selected,"prefixes":prefixes,"cells":cells,"removed_ids":ordered,"removed_specs":removed}

## Read-only preflight for the caller's navigation/worker retirement handshake.
## Call retire synchronously after acquiring all owners' consent; do not await
## between consent and commit. Both calls use exactly the same validation.
static func validate_retire(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	var plan:=_retire_plan(existing,library,ids)
	if not plan.ok:return plan
	return {"ok":true,"error":"","removed":plan.removed_ids.size(),"removed_ids":plan.removed_ids}

## Complete static ownership units. The caller additionally protects live draw,
## collision, navigation, source pins and transient work before committing.
static func validate_owned_retire(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_index.validate_owned_retire") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	var selected:Dictionary={};var prefixes:Dictionary={}
	for key:String in ["stream_by_id","stream_known","stream_index","stream_prop_index","stream_collision_index","stream_building_groups","stream_append_state"]:
		if not existing.get(key) is Dictionary:return _retire_failure("invalid existing index: "+key)
	var state:Dictionary=existing.stream_append_state
	for key:String in ["namespaces","prefixes","fixtures","group_bounds","group_cells","group_order","ground_cells","ground_order","dependents"]:
		if not state.get(key) is Dictionary:return _retire_failure("invalid append bookkeeping: "+key)
	if not existing.get("stream_landscape") is Array:return _retire_failure("invalid landscape catalogue")
	if library.size()!=existing.get("stream_by_id",{}).size() or library.size()!=int(existing.get("stream_building_count",-1)):return _retire_failure("library/index size mismatch")
	var seen:Dictionary={};var namespace_sizes:Dictionary={};var by_id:Dictionary=existing.stream_by_id
	for spec:Dictionary in library:
		if seen.has(spec.get("uuid")) or not _valid_append_spec(spec) or not is_same(by_id.get(spec.uuid),spec):return _retire_failure("library/index identity mismatch")
		seen[spec.uuid]=true
		var prefix:String=str(spec.uuid).get_slice("__",0)
		namespace_sizes[prefix]=int(namespace_sizes.get(prefix,0))+1
	var checked_cells:Dictionary={};var checked_ground_cells:Dictionary={}
	for id:Variant in ids:
		if not id is String or selected.has(id) or not by_id.has(id):return _retire_failure("invalid complete retirement identity")
		var spec:Dictionary=by_id[id]
		# The complete identity/schema pass above covered every by_id object.
		# Do not validate all fields of each selected member a second time.
		if spec.get("native_visual",false):return _retire_failure("active native owner")
		for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
			for x in range(spec.chunk_min.x,spec.chunk_max.x+1):
				var key:=Vector2i(x,z)
				# This complete validation is synchronous and read-only. Thousands
				# of parts can share one cell; validate each same bucket just once.
				if not checked_cells.has(key):
					for field:String in SPATIAL_FIELDS:
						if not existing[field].get(key,[]) is Array:return _retire_failure("invalid spatial bucket: "+field)
					checked_cells[key]=true
				if state.ground_order.has(id) and not checked_ground_cells.has(key):
					if not state.ground_cells.get(key,[]) is Array:return _retire_failure("invalid ground bucket")
					checked_ground_cells[key]=true
		if spec.has("render_building") and not existing.stream_building_groups.has(spec.render_building):return _retire_failure("missing derived building")
		var extra:Dictionary=spec.get("extras",{});var record:Dictionary=spec.get("ground_batch_record",{})
		for field in ["event","event_template","hostile","ally","seat"]:
			if extra.has(field) or record.has(field):return _retire_failure("active gameplay owner")
		if extra.get("kind","") in ["npc","gather","event","teleport","warp"]:return _retire_failure("active gameplay owner")
		selected[id]=true
		var prefix:String=id.get_slice("__",0);prefixes[prefix]=int(prefixes.get(prefix,0))+1
	for prefix:String in prefixes:
		if prefixes[prefix]!=namespace_sizes[prefix]:return _retire_failure("split namespace")
	var checked_group_cells:Dictionary={}
	for group:String in existing.stream_building_groups:
		var members:Variant=existing.stream_building_groups[group]
		if not members is Array or members.is_empty():return _retire_failure("invalid building group")
		var selected_members:=0
		for member:Variant in members:
			if not member is Dictionary or not member.get("uuid") is String:return _retire_failure("invalid building group")
			if selected.has(member.uuid):selected_members+=1
		var touched:bool=selected_members>0
		if touched and selected_members!=members.size():return _retire_failure("split building group")
		if touched:
			var bounds:Variant=state.group_bounds.get(group)
			if not bounds is Dictionary or not bounds.get("chunk_min") is Vector2i or not bounds.get("chunk_max") is Vector2i:return _retire_failure("invalid building bounds")
			for z in range(bounds.chunk_min.y,bounds.chunk_max.y+1):
				for x in range(bounds.chunk_min.x,bounds.chunk_max.x+1):
					var key:=Vector2i(x,z)
					if not checked_group_cells.has(key):
						if not state.group_cells.get(key,[]) is Array:return _retire_failure("invalid group bucket")
						checked_group_cells[key]=true
			if not members[0].get("render_supports",[]) is Array:return _retire_failure("invalid building support")
			for support:Variant in members[0].get("render_supports",[]):
				if not support is Dictionary or not support.get("uuid") is String or not support.get("render_dependents") is Array or not state.dependents.get(support.uuid) is Array:return _retire_failure("invalid support dependencies")
		if not touched:
			for support:Dictionary in members[0].get("render_supports",[]):
				if selected.has(support.uuid):return _retire_failure("retained building needs landscape support")
	return {"ok":true,"error":"","removed":selected.size()}

static func retire_owned(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	var checked:=validate_owned_retire(existing,library,ids)
	if not checked.ok:return checked
	return _commit_owned_retire(existing,library,ids)

## Internal atomic commit: validation and owner consent must have completed in
## the same synchronous transaction, without publishing a plan or awaiting.
static func _commit_owned_retire(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	var _method_scope:RefCounted=preload("res://scripts/world3d/load_trace.gd").method_scope("method.stream_index._commit_owned_retire") if preload("res://scripts/world3d/load_trace.gd").methods_enabled else null
	if ids.is_empty():return {"ok":true,"error":"","removed":0,"removed_ids":[],"data":existing}
	if not legacy_owned_rebuild_enabled:return _commit_owned_delta(existing,library,ids)
	var selected:Dictionary={}
	for id:String in ids:selected[id]=true
	var survivors:Array=[]
	for spec:Dictionary in library:
		if selected.has(spec.uuid):continue
		# Rebind every surviving support/dependent link to live source identities.
		for field in ["render_building","render_bounds","render_supports","render_dependents"]:spec.erase(field)
		survivors.append(spec)
	var rebuilt:=build(survivors)
	library.clear();library.append_array(survivors)
	return {"ok":true,"error":"","removed":ids.size(),"removed_ids":ids.duplicate(),"data":rebuilt}

static func _commit_owned_delta(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	# validate_owned_retire already proved complete namespaces/groups and that
	# no surviving building depends on selected ground. Preserve every surviving
	# spec, bucket and dependency object instead of regenerating the entire map.
	var state:Dictionary=existing.stream_append_state
	var selected:Dictionary={};var prefixes:Dictionary={};var cells:Dictionary={};var removed:Array=[]
	var ground_cells:Dictionary={};var groups:Dictionary={};var group_cells:Dictionary={}
	var touched_supports:Dictionary={}
	for id:String in ids:
		var spec:Dictionary=existing.stream_by_id[id]
		selected[id]=true;prefixes[id.get_slice("__",0)]=true;removed.append(spec)
		for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
			for x in range(spec.chunk_min.x,spec.chunk_max.x+1):cells[Vector2i(x,z)]=true
		if spec.has("render_building"):groups[spec.render_building]=true
		if state.ground_order.has(id):
			for z in range(spec.chunk_min.y,spec.chunk_max.y+1):
				for x in range(spec.chunk_min.x,spec.chunk_max.x+1):ground_cells[Vector2i(x,z)]=true
			state.ground_order.erase(id);state.dependents.erase(id)
		var fixture:=_fixture_key(spec)
		if not fixture.is_empty():state.fixtures.erase(fixture)
	for id:String in groups:
		var members:Array=existing.stream_building_groups[id]
		var raw:Dictionary=state.group_bounds[id]
		for z in range(raw.chunk_min.y,raw.chunk_max.y+1):
			for x in range(raw.chunk_min.x,raw.chunk_max.x+1):group_cells[Vector2i(x,z)]=true
		for support:Dictionary in members[0].get("render_supports",[]):
			if selected.has(support.uuid):continue
			touched_supports[support.uuid]=support
		existing.stream_building_groups.erase(id)
		state.group_bounds.erase(id);state.group_order.erase(id)
	for support:Dictionary in touched_supports.values():
		var dependents:Array=state.dependents[support.uuid];var retained:=0
		for at:int in dependents.size():
			if groups.has(dependents[at]):continue
			dependents[retained]=dependents[at];retained+=1
		dependents.resize(retained)
		# Equal bounds from different buildings are distinct mutable owners.
		# Rebind exact surviving identities, not Array.erase(value equality).
		support.render_dependents.clear()
		for id:String in state.dependents[support.uuid]:support.render_dependents.append(existing.stream_building_groups[id][0].render_bounds)
	for key:Vector2i in group_cells:_retire_bucket(state.group_cells,key,groups,false)
	for key:Vector2i in ground_cells:_retire_bucket(state.ground_cells,key,selected,false)
	# Append uses dense ordering offsets. Compact scalar ranks only; leave all
	# surviving support arrays/bounds identities and their order unchanged.
	for ranks:Dictionary in [state.group_order,state.ground_order]:
		var rank:=0
		for id:String in ranks:ranks[id]=rank;rank+=1
	var landscape:Array=existing.stream_landscape;var write:=0
	for read:int in landscape.size():
		if selected.has(landscape[read].uuid):continue
		landscape[write]=landscape[read];write+=1
	landscape.resize(write)
	var result:=_commit_retire(existing,library,{"selected":selected,"prefixes":prefixes,"cells":cells,"removed_ids":ids.duplicate(),"removed_specs":removed})
	result.erase("removed_specs")
	return result

static func owned_dependency_pinned(existing:Dictionary,ids:Array)->bool:
	# Rejection-only shortcut. Missing/malformed metadata falls through to the
	# complete integrity validation; this never authorizes a retirement.
	var state:Variant=existing.get("stream_append_state")
	if not state is Dictionary or not state.get("dependents") is Dictionary:return false
	var selected:Dictionary={}
	for id:Variant in ids:
		if not id is String:return false
		selected[id]=true
	for id:String in selected:
		var dependents:Variant=state.dependents.get(id,[])
		if not dependents is Array:return false
		for group:Variant in dependents:
			var members:Variant=existing.get("stream_building_groups",{}).get(group)
			if not members is Array or members.is_empty():continue
			if members.any(func(spec):return spec is Dictionary and not selected.has(spec.get("uuid"))):return true
	return false

static func _retire_bucket(buckets:Dictionary,key:Vector2i,selected:Dictionary,by_spec:bool)->void:
	if not buckets.has(key):return
	var bucket:Array=buckets[key];var write:=0
	for read in bucket.size():
		var value:Variant=bucket[read]
		var id:Variant=value.get("uuid") if by_spec and value is Dictionary else value
		if selected.has(id):continue
		bucket[write]=value;write+=1
	bucket.resize(write)
	if bucket.is_empty():buckets.erase(key)

## Main-thread atomic index retirement for ordinary static props only. The
## caller must release SceneTree, candidate/plan, batcher and navigation owners.
## Complete imported namespaces are required; dependent/native groups stay pinned.
## removed_specs deliberately retains resources only until the caller finishes
## cleanup. Never store this result in a long-lived profile/history dictionary.
static func retire(existing:Dictionary,library:Array,ids:Array)->Dictionary:
	var plan:=_retire_plan(existing,library,ids)
	if not plan.ok:return plan
	return _commit_retire(existing,library,plan)

static func _commit_retire(existing:Dictionary,library:Array,plan:Dictionary)->Dictionary:
	var selected:Dictionary=plan.selected;var state:Dictionary=existing.stream_append_state
	for id:String in selected:
		existing.stream_by_id.erase(id);existing.stream_known.erase(id)
	for key:Vector2i in plan.cells:
		_retire_bucket(existing.stream_index,key,selected,false)
		_retire_bucket(existing.stream_prop_index,key,selected,true)
		_retire_bucket(existing.stream_collision_index,key,selected,true)
	for prefix:String in plan.prefixes:state.namespaces.erase(prefix);state.prefixes.erase(prefix)
	var write:=0
	for read in library.size():
		if selected.has(library[read].uuid):continue
		library[write]=library[read];write+=1
	library.resize(write)
	existing.stream_building_count=library.size()
	if not selected.is_empty():_collision_membership_changed(existing)
	return {"ok":true,"error":"","data":existing,"removed":plan.removed_ids.size(),"removed_ids":plan.removed_ids,"removed_specs":plan.removed_specs}

static func _collision_membership_changed(existing:Dictionary)->void:
	existing.stream_collision_revision=int(existing.get("stream_collision_revision",0))+1
	# Drop retired specs/meshes immediately, even when no later query occurs.
	if existing.get("stream_collision_candidate_cache") is Dictionary:existing.stream_collision_candidate_cache.clear()

## Atomic main-thread publication only: callers own the library append and
## residency dirty notification. Existing indexes must come from build/append.
## Every imported namespace, building and fixture must arrive as a whole batch.
static func append(existing:Dictionary,additions:Array,preparation:RefCounted=null)->Dictionary:
	var phase_began:=preload("res://scripts/world3d/load_trace.gd").begin("stream.append_validate")
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
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.append_validate",phase_began,{"specs":additions.size()})
	phase_began=preload("res://scripts/world3d/load_trace.gd").begin("stream.append_fragment")
	# A private small fragment validates derived grouping before any caller-owned
	# dictionary or new spec is touched. Mesh resources remain shared/read-only.
	# build/bind replace top-level derived fields, never mutate authored extras,
	# records or their nested arrays. A private shallow spec projection gives
	# the same atomic failure isolation without copying entire author graphs.
	var fragment:Dictionary
	if preparation!=null:
		# Only our private cursor can donate a fragment. Schema validation above
		# and these same-transaction identity/geometry/group checks remain fresh.
		if preparation.get_script()!=load("res://scripts/world3d/stream_index_preparation.gd") or not preparation.valid_for(additions,true):return _append_failure("stale_private_index")
		fragment=preparation.result
	else:
		var projection:Array=[]
		for spec:Dictionary in additions:projection.append(spec.duplicate())
		fragment=build(projection)
	var fresh:Dictionary=fragment.stream_append_state
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.append_fragment",phase_began,{"specs":additions.size(),"groups":fragment.stream_building_groups.size()})
	phase_began=preload("res://scripts/world3d/load_trace.gd").begin("stream.append_plan")
	for id:String in fragment.stream_building_groups:
		if existing.stream_building_groups.has(id):return _append_failure("split building group: "+id)
	var affected:Dictionary={}
	for uuid:String in fresh.ground_order:
		for id:String in _query_ids(state.group_cells,originals[uuid]):affected[id]=true
	for id:String in fragment.stream_building_groups:affected[id]=true
	var ground_offset:int=state.ground_order.size();var group_offset:int=state.group_order.size()
	var plans:Dictionary={};var touched:Dictionary={};var planned_dependents:Dictionary={}
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
			if not planned_dependents.has(uuid):planned_dependents[uuid]=[]
			planned_dependents[uuid].append(id)
			bounds.chunk_min=bounds.chunk_min.min(support.chunk_min);bounds.chunk_max=bounds.chunk_max.max(support.chunk_max)
		if old:
			for support:Dictionary in existing.stream_building_groups[id][0].render_supports:touched[support.uuid]=true
		plans[id]={"bounds":bounds,"supports":supports}
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.append_plan",phase_began,{"groups":plans.size(),"supports":touched.size()})
	phase_began=preload("res://scripts/world3d/load_trace.gd").begin("stream.append_index_commit")
	# Commit has no await or fallible I/O. Preserve existing maps, buckets and
	# spec objects; update only dependency groups intersected by new ground.
	for uuid:String in originals:
		var spec:Dictionary=originals[uuid];var prepared:Dictionary=fragment.stream_by_id[uuid]
		for field in ["render_building","render_bounds","render_supports","render_dependents"]:
			spec.erase(field)
			if prepared.has(field) and field not in ["render_supports","render_dependents"]:spec[field]=prepared[field]
		if Landscape.landscape(spec):spec.render_dependents=[]
	existing.stream_by_id.merge(originals,true)
	existing.stream_known.merge(fragment.stream_known,true)
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
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.append_index_commit",phase_began,{"specs":additions.size()})
	phase_began=preload("res://scripts/world3d/load_trace.gd").begin("stream.append_dependents")
	for uuid:String in touched:
		var dependents:Array=state.dependents[uuid]
		# Filter each old reverse edge once. Repeated erase + a scan of every
		# plan/support list made a large imported building quadratic in groups.
		var retained:=0
		for at:int in dependents.size():
			if affected.has(dependents[at]):continue
			dependents[retained]=dependents[at];retained+=1
		dependents.resize(retained)
		dependents.append_array(planned_dependents.get(uuid,[]))
		dependents.sort_custom(func(a,b):return state.group_order[a]<state.group_order[b])
		var support:Dictionary=existing.stream_by_id[uuid]
		support.render_dependents.clear()
		for id:String in dependents:support.render_dependents.append(existing.stream_building_groups[id][0].render_bounds)
	preload("res://scripts/world3d/load_trace.gd").elapsed("stream.append_dependents",phase_began,{"supports":touched.size()})
	# These old entries can change residency without a camera/chunk change.
	# Return their original references so the caller can replan just this delta.
	var changed_existing:Dictionary={}
	for id:String in plans:
		for member:Dictionary in existing.stream_building_groups[id]:
			if not originals.has(member.uuid):changed_existing[member.uuid]=member
	for uuid:String in touched:
		if not originals.has(uuid):changed_existing[uuid]=existing.stream_by_id[uuid]
	existing.stream_building_count+=additions.size()
	_collision_membership_changed(existing)
	return {"ok":true,"data":existing,"added":additions.size(),"affected_groups":affected.size(),"affected_existing_specs":changed_existing.values()}
