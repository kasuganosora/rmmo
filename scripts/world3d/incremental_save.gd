extends RefCounted
## Reconcile authored instance membership while retaining published resource indices.
## Planning is CPU-only. New source scenes are constructed separately on main.

static func structural_change(data: Dictionary, records: Array, pose: Script) -> bool:
	var root: int=pose._root(data)
	if root<0:return false
	var previous:Variant=data.nodes[root].get("extras",{}).get("rmmo_records",[])
	if not previous is Array or previous.size()!=records.size():return true
	for i in records.size():
		if previous[i].get("uuid")!=records[i].get("uuid"):return true
	return false

static func _template(record: Dictionary, pose: Script) -> Dictionary:
	var value:Dictionary=pose._without_pose(record)
	value.erase("uuid")
	# These editor-only fields live in rmmo_records, never in exported geometry
	# or runtime node extras. An independent copied group still shares resources.
	for key:String in ["editor_group","editor_group_name","editor_locked","editor_hidden"]:value.erase(key)
	return value

static func _canonical_numbers(value: Variant) -> Variant:
	# JSON parses every number as float; in-memory authoring also contains ints.
	# Canonicalize only the lookup key, then verify the full recipe with Pose.same.
	if value is int or value is float:return float(value)
	if value is Dictionary:
		var copy:Dictionary={}
		for key in value:copy[key]=_canonical_numbers(value[key])
		return copy
	if value is Array:
		var copy:Array=[]
		for item in value:copy.append(_canonical_numbers(item))
		return copy
	return value

static func plan(data: Dictionary, records: Array, meta: Dictionary, pose: Script) -> Dictionary:
	var graph=load("res://scripts/world3d/gltf_delta_graph.gd")
	var valid:Dictionary=graph.validate(data)
	if not valid.ok:return valid
	var root: int=pose._root(data)
	if root<0:return {"ok":false,"reason":"unsupported_root"}
	var previous:Variant=data.nodes[root].extras.get("rmmo_records")
	if not previous is Array:return {"ok":false,"reason":"record_nodes"}
	var children:Array=data.nodes[root].get("children",[])
	if children.size()!=previous.size():return {"ok":false,"reason":"record_nodes"}
	var nodes:Dictionary={};var before:Dictionary={};var after:Dictionary={}
	for index in children:
		var id:String=data.nodes[int(index)].get("name","")
		if id.is_empty() or nodes.has(id):return {"ok":false,"reason":"ambiguous_node"}
		nodes[id]=int(index)
	for record:Dictionary in previous:
		var id:String=record.get("uuid","")
		if before.has(id) or not nodes.has(id):return {"ok":false,"reason":"record_identity"}
		before[id]=record
	for record:Dictionary in records:
		var id:String=record.get("uuid","")
		if id.is_empty() or after.has(id):return {"ok":false,"reason":"record_identity"}
		after[id]=record
	var removed:Array=[];var added:Array=[];var aligned:Array=[]
	for record:Dictionary in previous:
		var id:String=record.uuid
		if not after.has(id):
			if not pose._safe_pose(record):return {"ok":false,"reason":"incremental_neighbor_geometry"}
			removed.append(nodes[id])
		aligned.append(after.get(id,record))
	for record:Dictionary in records:
		if not before.has(str(record.uuid)):
			if not pose._safe_pose(record):return {"ok":false,"reason":"incremental_neighbor_geometry"}
			added.append(record)
	# Reuse the existing exact pose, floor and building-registration validation.
	# Its scratch authoring array includes removed instances until graph reconciliation.
	var moved:Dictionary=pose.update(data,aligned,meta)
	if not moved.ok:return moved
	var export_records:Array=[];var cloned:=0
	var templates:Dictionary={}
	for id:String in before:
		var record:Dictionary=before[id]
		if not pose._safe_pose(record) or record.has("building"):continue
		var key:String=JSON.stringify(_canonical_numbers(_template(record,pose)),"",true,true)
		if not templates.has(key):templates[key]=id
	for record:Dictionary in added:
		var key:String=JSON.stringify(_canonical_numbers(_template(record,pose)),"",true,true)
		var source:String=templates.get(key,"")
		if not source.is_empty() and not record.has("building") and pose.same(_template(before[source],pose),_template(record,pose)):
			var duplicate:Dictionary=graph.clone_instance(data,int(nodes[source]),str(record.uuid))
			if not duplicate.ok:return duplicate
			nodes[str(record.uuid)]=int(duplicate.root)
			pose._set_pose(data.nodes[int(duplicate.root)],pose.pose(record))
			cloned+=1
		else:export_records.append(record)
	var erased:Dictionary=graph.remove_instances(data,removed)
	if not erased.ok:return erased
	for id:String in before:
		if not after.has(id):nodes.erase(id)
	var next_children:Array=[]
	for record:Dictionary in records:
		if nodes.has(str(record.uuid)):next_children.append(nodes[str(record.uuid)])
	if next_children.is_empty():data.nodes[root].erase("children")
	else:data.nodes[root].children=next_children
	data.nodes[root].extras=pose.extras(records,meta)
	return {"ok":true,"data":data,"root":root,"nodes":nodes,"records":records,
		"export_records":export_records,"added_instances":added.size(),"removed_instances":removed.size(),
		"cloned_instances":cloned,"updated_nodes":moved.updated}

static func merge_fragment(plan_: Dictionary, fragment: Dictionary, pose: Script) -> Dictionary:
	var root: int=pose._root(fragment)
	if root<0:return {"ok":false,"reason":"incremental_fragment_root"}
	var roots:Array=fragment.nodes[root].get("children",[]).duplicate()
	# Leave an inert wrapper rather than another native-map authoring root.
	fragment.nodes[root].erase("children")
	fragment.nodes[root].erase("extras")
	fragment.nodes[root].name="delta_export_root"
	var merged:Dictionary=load("res://scripts/world3d/gltf_delta_graph.gd").append_fragment(plan_.data,fragment,roots)
	if not merged.ok:return merged
	for index in merged.roots:
		var id:String=plan_.data.nodes[int(index)].get("name","")
		if plan_.nodes.has(id):return {"ok":false,"reason":"incremental_fragment_identity"}
		plan_.nodes[id]=int(index)
	var children:Array=[]
	for record:Dictionary in plan_.records:
		if not plan_.nodes.has(str(record.uuid)):return {"ok":false,"reason":"incremental_fragment_missing"}
		children.append(plan_.nodes[str(record.uuid)])
	if children.is_empty():plan_.data.nodes[int(plan_.root)].erase("children")
	else:plan_.data.nodes[int(plan_.root)].children=children
	return load("res://scripts/world3d/gltf_delta_graph.gd").validate(plan_.data)

static func prepare_materials(records: Array) -> void:
	# A newly introduced source might already be cached by an unrelated preview.
	# Invalidate only source paths/recipes used by the exported subset. Existing
	# live instances keep their immutable resources; no town view is rebuilt.
	var materials=load("res://scripts/world3d/surface_materials.gd")
	var definitions:Array=[];var texture_keys:Dictionary={};var door_modules:Dictionary={}
	for record:Dictionary in records:
		for definition:Dictionary in materials.definitions(record):
			if not definition in definitions:definitions.append(definition)
		var shape:String=record.get("building_shape","")
		if shape=="timber_door":door_modules["timber_door_mesh"]=true
		elif shape in ["interior_door","interior_door_frame"]:door_modules["interior_door_mesh"]=true
	if not door_modules.is_empty():
		# These authoring generators load implicit JSON and wood inputs, absent
		# from SurfaceMaterials.definitions(record) but included in source_files.
		var art=load("res://scripts/asset/art_paths.gd")
		definitions.append({"texture_path":art.external_root().path_join("packs/default/assets/materials/wood/solid_timber/texture.png")})
		for name_:String in door_modules:
			var module=load("res://scripts/world3d/"+name_+".gd")
			module._data.clear();module._meshes.clear()
	for definition:Dictionary in definitions:
		for field:String in materials.MAP_FIELDS:
			var path:String=definition.get(field,"")
			if not path.is_empty():texture_keys[path]=true;texture_keys[path+"|flip_y"]=true
	for key in materials._materials.keys():
		var definition:Dictionary=materials._materials[key].get_meta("runtime_paint_definition",{})
		var affected:bool=definition in definitions
		for field:String in materials.MAP_FIELDS:
			if texture_keys.has(str(definition.get(field,""))):affected=true
		if affected:materials._materials.erase(key)
	for key:String in texture_keys:
		materials._textures.erase(key);materials.prepared_images.erase(key)
	# Frozen prefab geometry caches retain material objects too. Remove only
	# entries referring to the affected paths; immutable encoded geometry stays.
	load("res://scripts/world3d/house_prefab.gd").invalidate_texture_materials(texture_keys)

static func build_record(document: RefCounted, record: Dictionary, io: Script) -> Node3D:
	# A removed UUID can be reintroduced after its source changes. The disposable
	# save mesh key contains record data, not external bytes, so invalidate just it.
	document._save_meshes.remove(str(record.uuid))
	if record.has("house_prefab"):return document._mesh(record,false)
	if record.get("kind")=="asset" and not record.has("bridge_mesh") and not record.has("house_prefab"):
		# Fresh imported mesh IDs also bypass parametric_tree / streetlamp_banner
		# recipe caches, whose keys contain the source mesh instance ID.
		return document._asset(record,{"scene":io.load_scene(str(record.get("asset_path","")))})
	return document._asset(record) if record.get("kind")=="asset" else document._mesh(record,false)

static func export_and_publish(plan_: Dictionary, view: Node3D, path: String, expected: String,
		content_root: String, io: Script, pose: Script, progress: Callable=Callable()) -> Dictionary:
	var lock:Error=io._acquire_save_lock(path)
	if lock!=OK:return {"handled":true,"error":lock}
	var result:Dictionary=_export_locked(plan_,view,path,expected,content_root,io,pose,progress)
	io._remove_tree(path+".save-lock")
	return result

static func _export_locked(plan_: Dictionary, view: Node3D, path: String, expected: String,
		content_root: String, io: Script, pose: Script, progress: Callable) -> Dictionary:
	if FileAccess.get_sha256(path)!=expected:return {"handled":true,"error":ERR_BUSY}
	if plan_.export_records.is_empty():
		var valid:Dictionary=load("res://scripts/world3d/gltf_delta_graph.gd").validate(plan_.data)
		if not valid.ok:return {"handled":true,"error":ERR_INVALID_DATA,"incremental_error":valid.get("reason","")}
		plan_.data.extras[pose.MANIFEST].sources=plan_.sources.files
		return pose.publish_reuse(plan_.data,path,expected,content_root,io,progress,plan_.sources,plan_.resources,plan_.get("timings",{}),metrics(plan_))
	var relative:String=path.get_file()+".versions/delta_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var directory:String=path.get_base_dir().path_join(relative)
	var file:String=directory.path_join(path.get_file())
	var err:Error=DirAccess.make_dir_recursive_absolute(directory)
	if err!=OK:return {"handled":true,"error":err}
	err=io.save_scene(view,file,progress)
	if err!=OK:return {"handled":true,"error":err}
	var exported:Dictionary=io.last_export_metrics.duplicate(true)
	var fragment:Dictionary=pose._json(file)
	for section:String in ["images","buffers"]:
		for item:Dictionary in fragment.get(section,[]):
			var uri:String=item.get("uri","")
			if uri.is_empty() or uri.begins_with("data:"):continue
			var decoded:String=io.decode_dependency_uri(uri)
			if decoded.is_empty() or ".." in decoded.split("/") or not FileAccess.file_exists(directory.path_join(decoded)):
				return {"handled":true,"error":ERR_INVALID_DATA}
			item.uri=(relative+"/"+decoded).uri_encode()
	var merged:Dictionary=merge_fragment(plan_,fragment,pose)
	if not merged.ok:return {"handled":true,"error":ERR_INVALID_DATA,"incremental_error":merged.get("reason","")}
	var resources:Dictionary=pose.dependencies(plan_.data,path,content_root,io)
	if not resources.ok:return {"handled":true,"error":ERR_INVALID_DATA}
	# Pre-existing published bytes must still match the verified baseline.
	for uri:String in plan_.resources.files:
		if resources.files.get(uri)!=plan_.resources.files[uri]:return {"handled":true,"error":ERR_BUSY}
	plan_.data.extras[pose.MANIFEST].sources=plan_.sources.files
	plan_.data.extras[pose.MANIFEST].dependencies=resources.files
	var result_metrics:Dictionary=metrics(plan_)
	result_metrics.images_written=exported.get("images_written",0)
	result_metrics.texture_export_passes=exported.get("texture_export_passes",0)
	result_metrics.exported_instances=plan_.export_records.size()
	result_metrics.partial_export=exported
	return pose.publish_reuse(plan_.data,path,expected,content_root,io,progress,plan_.sources,resources,plan_.get("timings",{}),result_metrics)

static func metrics(plan_: Dictionary) -> Dictionary:
	return {"mode":"incremental_reuse","updated_nodes":plan_.updated_nodes,
		"added_instances":plan_.added_instances,"removed_instances":plan_.removed_instances,
		"cloned_instances":plan_.cloned_instances,"exported_instances":0,
		"texture_export_passes":0,"images_written":0}
