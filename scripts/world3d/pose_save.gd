extends RefCounted
## Reuse a previously validated export only when its resources and all non-pose
## authoring data still match. No scene objects, GPU resources or global caches
## are touched by the worker functions in this file.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Fixtures = preload("res://scripts/world3d/building_fixtures.gd")
const FORMAT_VERSION := 1
const MANIFEST := "rmmo_save_manifest"

static func generator_key() -> String:
	var paths:Array=[]
	_generator_files("res://scripts/world3d",paths)
	paths.append_array(["res://scripts/world_editor/asset_library.gd","res://scripts/world_editor/save_job.gd"])
	paths.sort()
	var hashes:Array=[Engine.get_version_info().hash,FORMAT_VERSION]
	for path:String in paths:
		var code:String=""
		if ResourceLoader.has_cached(path):
			var resource:=ResourceLoader.load(path)
			if resource is Script:code=resource.source_code
			elif resource is Shader:code=resource.code
		if code.is_empty():code=FileAccess.get_file_as_string(path)
		# A running editor can still execute the old loaded Script after files
		# change on disk. Bind the baseline to that implementation, not the new file.
		hashes.append([path,code.replace("\r\n","\n").trim_prefix("\ufeff").sha256_text()])
	return str(hashes).sha256_text()

static func _generator_files(directory: String, result: Array) -> void:
	# Include the transitive generator implementation conservatively. A code
	# update costs one full save, but cannot silently reuse obsolete geometry.
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["gd","gdshader"]:result.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):_generator_files(directory.path_join(child),result)

static func same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b)) <= maxf(1e-12,maxf(absf(float(a)),absf(float(b)))*1e-14)
	if typeof(a)!=typeof(b):return false
	if a is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	return a==b

static func _json(path: String) -> Dictionary:
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:return {}
	return parser.data

static func serialize(data: Dictionary) -> String:
	return serialize_bytes(data).get_string_from_utf8()

static func sha256_bytes(bytes: PackedByteArray) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()

static func _checksum_byte_offset(text: String, digest: String) -> int:
	var needle:String='"rmmo_saved_content_sha256":"'+digest+'"'
	var offset:=text.find(needle)
	if offset<0 or text.find(needle,offset+needle.length())>=0:return -1
	# UTF-8 byte positions differ from String character positions for authoring
	# labels. New exports put the checksum near the beginning to keep this small.
	return text.left(offset+needle.length()-65).to_utf8_buffer().size()

static func serialize_bytes(data: Dictionary) -> PackedByteArray:
	var manifest:Variant=data.get("extras",{}).get(MANIFEST)
	if not manifest is Dictionary:return JSON.stringify(data,"",false,true).to_utf8_buffer()
	# Hash exact JSON bytes with only our own checksum zeroed. This avoids
	# reserializing float64 values through Godot's JSON parser (one-ULP drift).
	var zero:="0".repeat(64)
	manifest.erase("rmmo_saved_content_sha256")
	var ordered_manifest:Dictionary={"rmmo_saved_content_sha256":zero}
	ordered_manifest.merge(manifest);data.extras[MANIFEST]=ordered_manifest
	var ordered:Dictionary={"extras":data.extras};ordered.merge(data)
	var text:=JSON.stringify(ordered,"",false,true)
	var offset:=_checksum_byte_offset(text,zero)
	if offset<0:
		data.extras.erase(MANIFEST)
		return JSON.stringify(data,"",false,true).to_utf8_buffer()
	var bytes:=text.to_utf8_buffer()
	var digest:=sha256_bytes(bytes)
	ordered_manifest.rmmo_saved_content_sha256=digest
	for index in 64:bytes[offset+index]=digest.unicode_at(index)
	return bytes

static func valid_content(text: String, manifest: Dictionary) -> bool:
	return valid_content_bytes(text.to_utf8_buffer(),text,manifest)

static func valid_content_bytes(bytes: PackedByteArray, text: String, manifest: Dictionary) -> bool:
	var digest:Variant=manifest.get("rmmo_saved_content_sha256")
	if not digest is String or digest.length()!=64:return false
	var offset:=_checksum_byte_offset(text,digest)
	if offset<0:return false
	for index in 64:bytes[offset+index]=48
	return sha256_bytes(bytes)==digest

static func _paths(value: Variant, found: Dictionary, field: String="") -> void:
	if value is Dictionary:
		for key in value:
			# Warp destinations and derived editor thumbnails are not export inputs.
			if key in ["target_path","spawn","thumbnail_path"]:continue
			_paths(value[key],found,str(key))
	elif value is Array:
		for entry in value:_paths(entry,found,field)
	elif value is String and not value.is_empty() and ((field.ends_with("_path") and field!="target_path") or field=="path" or (value.is_absolute_path() and value.get_extension().to_lower() in ["glb","gltf","png","jpg","jpeg","webp","json"])):
		found[value.replace("\\","/").simplify_path()]=true

static func _hash_batch(paths: Array, content_root: String, discover: bool, io: Script) -> Dictionary:
	var files:Dictionary={};var children:Array=[]
	for path:String in paths:
		if not Paths.allowed(path,content_root) or not FileAccess.file_exists(path):return {"ok":false,"files":{}}
		var digest:=FileAccess.get_sha256(path)
		if digest.is_empty():return {"ok":false,"files":{}}
		files[path]=digest
		# Keep the existing hash-before-parse ordering within each independent
		# source. Never bind a later parent hash to an earlier dependency list.
		if discover:
			var dependencies_:=_source_dependencies(path,io)
			if not dependencies_.ok:return {"ok":false,"files":{}}
			children.append_array(dependencies_.paths)
	return {"ok":true,"files":files,"children":children}

static func hash_files(paths: Array, content_root: String, discover: bool=false, io: Script=null) -> Dictionary:
	var lengths:Dictionary={};var total:=0
	for path:String in paths:
		if not Paths.allowed(path,content_root):return {"ok":false,"files":{}}
		var input:=FileAccess.open(path,FileAccess.READ)
		if input==null:return {"ok":false,"files":{}}
		lengths[path]=input.get_length();total+=int(lengths[path])
	if paths.size()<2 or total<8*1024*1024:return _hash_batch(paths,content_root,discover,io)
	var count_:int=mini(4,paths.size());var groups:Array=[];var sizes:Array=[]
	for index in count_:groups.append([]);sizes.append(0)
	var ordered:=paths.duplicate()
	ordered.sort_custom(func(a,b):return lengths[a]>lengths[b])
	for path:String in ordered:
		var smallest:int=sizes.find(sizes.min())
		groups[smallest].append(path);sizes[smallest]+=int(lengths[path])
	var threads:Array=[];var ok:=true
	for group:Array in groups:
		var worker:=Thread.new()
		if worker.start(_hash_batch.bind(group,content_root,discover,io))!=OK:ok=false;break
		threads.append(worker)
	var files:Dictionary={};var children:Array=[]
	# Always join every started worker, including error paths; no worker can
	# outlive its caller or mutate shared dictionaries/scene resources.
	for worker:Thread in threads:
		var outcome:Dictionary=worker.wait_to_finish()
		ok=ok and outcome.ok
		files.merge(outcome.get("files",{}));children.append_array(outcome.get("children",[]))
	return {"ok":ok,"files":files if ok else {},"children":children}

static func _source_dependencies(path: String, io: Script) -> Dictionary:
	var paths:Array=[];var extension:=path.get_extension().to_lower()
	if extension not in ["glb","gltf"]:return {"ok":true,"paths":paths}
	var data:Dictionary={}
	if extension=="gltf":data=_json(path)
	else:
		var input:=FileAccess.open(path,FileAccess.READ)
		if input==null or input.get_length()<20 or input.get_32()!=0x46546C67 or input.get_32()!=2:return {"ok":false}
		input.get_32()
		var length:=input.get_32()
		if input.get_32()!=0x4E4F534A or length>input.get_length()-20:return {"ok":false}
		var parser:=JSON.new()
		if parser.parse(input.get_buffer(length).get_string_from_utf8())!=OK or not parser.data is Dictionary:return {"ok":false}
		data=parser.data
	if data.is_empty():return {"ok":false}
	for section in ["buffers","images"]:
		if not data.get(section,[]) is Array:return {"ok":false}
		for item in data.get(section,[]):
			if not item is Dictionary or not item.get("uri","") is String:return {"ok":false}
			var uri:String=item.get("uri","")
			if uri.is_empty() or uri.begins_with("data:"):continue
			var relative:String=io.decode_dependency_uri(uri)
			if relative.is_empty() or ".." in relative.split("/"):return {"ok":false}
			paths.append(path.get_base_dir().path_join(relative).simplify_path())
	return {"ok":true,"paths":paths}

static func source_files(records: Array, content_root: String, io: Script) -> Dictionary:
	var paths:Dictionary={}
	_paths(records,paths)
	for record in records:
		var shape:String=record.get("building_shape","")
		if shape in ["timber_door","interior_door","interior_door_frame"]:
			var relative:String="timber_door/timber_door_mesh.json" if shape=="timber_door" else "interior_timber_door/interior_timber_door_mesh.json"
			paths[content_root.path_join("assets").path_join(relative)]=true
			paths[content_root.path_join("packs/default/assets/materials/wood/solid_timber/texture.png")]=true
	var pending:Array=paths.keys()
	var result:Dictionary={}
	while not pending.is_empty():
		var unique:Dictionary={}
		for path:String in pending:
			if not result.has(path):unique[path]=true
		if result.size()+unique.size()>10000:return {"ok":false,"files":{}}
		var batch:=hash_files(unique.keys(),content_root,true,io)
		if not batch.ok:return {"ok":false,"files":{}}
		result.merge(batch.files);pending=batch.children
	return {"ok":true,"files":result,"generator":generator_key()}

static func verify_source_files(sources: Dictionary, content_root: String) -> bool:
	if not sources.get("ok",false) or not sources.get("files") is Dictionary:return false
	# The initial discovery already includes every parent model and its complete
	# dependency closure. Rehash every file: an added/removed/redirected URI must
	# change its parent's SHA, so final verification need not parse it again.
	# This is only a recheck within one save with frozen authoring records.
	var current:=hash_files(sources.files.keys(),content_root)
	# Match source_files: sample the generator after the potentially long hash
	# pass, so a code change during it is not accepted using an earlier key.
	return current.ok and same(current.files,sources.files) and sources.get("generator")==generator_key()

static func dependencies(data: Dictionary, path: String, content_root: String, io: Script) -> Dictionary:
	var locations:Dictionary={};var unique:Dictionary={}
	for section in ["buffers","images"]:
		if not data.get(section,[]) is Array:return {"ok":false}
		for item in data.get(section,[]):
			if not item is Dictionary or not item.get("uri","") is String:return {"ok":false}
			var uri:String=item.get("uri","")
			if uri.is_empty() or uri.begins_with("data:"):continue
			var relative:String=io.decode_dependency_uri(uri)
			if relative.is_empty() or ".." in relative.split("/"):return {"ok":false}
			var dependency:=path.get_base_dir().path_join(relative).simplify_path()
			if not Paths.allowed(dependency,content_root) or not FileAccess.file_exists(dependency):return {"ok":false}
			locations[uri]=dependency;unique[dependency]=true
			if section=="buffers":
				var input:=FileAccess.open(dependency,FileAccess.READ)
				if input==null or input.get_length()<int(item.get("byteLength",0)):return {"ok":false}
	var hashed:=hash_files(unique.keys(),content_root)
	if not hashed.ok:return {"ok":false}
	var result:Dictionary={}
	for uri:String in locations:result[uri]=hashed.files[locations[uri]]
	return {"ok":true,"files":result}

static func extras(records: Array, meta: Dictionary) -> Dictionary:
	var result:Dictionary={"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_unit":"m"}
	result.merge(meta,true)
	result.rmmo_records=records
	return result

static func _root(data: Dictionary) -> int:
	var scenes:Variant=data.get("scenes");var nodes:Variant=data.get("nodes");var scene:=int(data.get("scene",0))
	if not scenes is Array or not nodes is Array or scene<0 or scene>=scenes.size():return -1
	var roots:Variant=scenes[scene].get("nodes")
	if not roots is Array or roots.size()!=1:return -1
	var index:=int(roots[0])
	if index<0 or index>=nodes.size():return -1
	for key in ["translation","rotation","scale","matrix"]:
		if nodes[index].has(key):return -1
	return index if nodes[index].get("extras",{}).get("rmmo_format")=="rmmo_gltf_map" else -1

static func _without_pose(record: Dictionary) -> Dictionary:
	var result:=record.duplicate()
	result.erase("position");result.erase("rotation")
	if record.has("building"):
		result.building=record.building.duplicate();result.building.erase("floor_y")
	return result

static func _safe_pose(record: Dictionary) -> bool:
	for key in ["terrain_mesh","road_mesh","channel_mesh","rock_bank","fortification_art","tile3d","bridge_mesh"]:
		if record.has(key):return false
	if record.get("building_shape")=="roof_prism" and not record.get("roof_mesh",{}).has("uv_origin"):return false
	for key in ["position","rotation"]:
		var values:Variant=record.get(key)
		if not values is Array or values.size()!=3:return false
		for value in values:
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>100000:return false
	return record.get("kind") in ["box","asset","npc","gather","warp","seat"]

static func pose(record: Dictionary) -> Transform3D:
	var value:=Fixtures.transform(record)
	if record.get("kind")=="asset":value.basis=value.basis.scaled_local(Fixtures.vec(record.size))
	return value

static func _node_pose(node: Dictionary) -> Transform3D:
	if node.has("matrix"):
		var m:Array=node.matrix
		if m.size()!=16:return Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.INF)
		return Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[4],m[5],m[6]),Vector3(m[8],m[9],m[10])),Vector3(m[12],m[13],m[14]))
	var q:Array=node.get("rotation",[0,0,0,1])
	return Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3])).scaled_local(Fixtures.vec(node.get("scale",[1,1,1]))),Fixtures.vec(node.get("translation",[0,0,0])))

static func _set_pose(node: Dictionary, value: Transform3D) -> void:
	for key in ["translation","rotation","scale"]:node.erase(key)
	var b:=value.basis;var p:=value.origin
	node.matrix=[b.x.x,b.x.y,b.x.z,0,b.y.x,b.y.y,b.y.z,0,b.z.x,b.z.y,b.z.z,0,p.x,p.y,p.z,1]

static func _metadata_compatible(previous: Dictionary, current: Dictionary, changed: Dictionary) -> bool:
	var a:=previous.duplicate();var b:=current.duplicate()
	a.erase("rmmo_records");b.erase("rmmo_records")
	var old:Dictionary=a.get("building_instances",{});var fresh:Dictionary=b.get("building_instances",{})
	a.erase("building_instances");b.erase("building_instances")
	if not same(a,b) or old.size()!=fresh.size():return false
	for id in old:
		if not fresh.has(id):return false
		var left:Dictionary=old[id].duplicate();var right:Dictionary=fresh[id].duplicate()
		if same(left,right):continue
		if not changed.has(id):return false
		for field in ["position","yaw","signatures"]:left.erase(field);right.erase(field)
		if not same(left,right):return false
		var old_position:Variant=old[id].get("position");var new_position:Variant=fresh[id].get("position")
		if not old_position is Array or not new_position is Array or old_position.size()!=3 or new_position.size()!=3:return false
		for number in new_position+[fresh[id].get("yaw")]:
			if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number))>100000:return false
		var turn:=Basis(Vector3.UP,deg_to_rad(float(fresh[id].yaw)-float(old[id].yaw)))
		for pair:Array in changed[id].values():
			var expected:=Fixtures.vec(new_position)+turn*(Fixtures.vec(pair[0].position)-Fixtures.vec(old_position))
			if not expected.is_equal_approx(Fixtures.vec(pair[1].position)):return false
			var rotation:=turn*Basis.from_euler(Fixtures.vec(pair[0].rotation)*PI/180)
			if not rotation.is_equal_approx(Basis.from_euler(Fixtures.vec(pair[1].rotation)*PI/180)):return false
		# Every changed signature must describe that exact changed member; preserve
		# existing hand-edit conflicts rather than blessing unrelated signatures.
		var signatures:Dictionary=old[id].signatures;var next:Dictionary=fresh[id].signatures
		if signatures.size()!=next.size():return false
		for part in signatures:
			if not next.has(part):return false
			if signatures[part]==next[part]:continue
			if not changed[id].has(part):return false
			var pair:Array=changed[id][part]
			var blueprint=load("res://scripts/world3d/building_blueprint.gd")
			if signatures[part]!=blueprint.geometry_signature(pair[0]) or next[part]!=blueprint.geometry_signature(pair[1]):return false
	return true

static func update(data: Dictionary, records: Array, meta: Dictionary) -> Dictionary:
	var root_index:=_root(data)
	if root_index<0:return {"ok":false,"reason":"unsupported_root"}
	var root:Dictionary=data.nodes[root_index];var previous:Dictionary=root.extras
	var old:Variant=previous.get("rmmo_records")
	if not old is Array or old.size()!=records.size():return {"ok":false,"reason":"record_count"}
	var children:Variant=root.get("children",[])
	if not children is Array or children.size()!=records.size():return {"ok":false,"reason":"record_nodes"}
	var nodes:Dictionary={}
	for index in children:
		if int(index)<0 or int(index)>=data.nodes.size():return {"ok":false,"reason":"record_nodes"}
		var child:Dictionary=data.nodes[int(index)];var id:String=child.get("name","")
		if nodes.has(id):return {"ok":false,"reason":"ambiguous_node"}
		nodes[id]=child
	var changed:Dictionary={};var updated:=0
	for i in records.size():
		var before:Dictionary=old[i];var after:Dictionary=records[i];var id:String=after.get("uuid","")
		if before.get("uuid")!=id or not nodes.has(id):return {"ok":false,"reason":"record_identity"}
		if same(before,after):continue
		if not _safe_pose(after) or not same(_without_pose(before),_without_pose(after)):return {"ok":false,"reason":"geometry_or_material_change"}
		var current:Dictionary=nodes[id]
		if not _node_pose(current).is_equal_approx(pose(before)):return {"ok":false,"reason":"node_pose_mismatch"}
		if after.has("building"):
			var owner:String=after.building.id;var delta_y:float=float(after.position[1])-float(before.position[1])
			# Node positions travel through Godot's float32 Vector3, whereas the
			# floor label remains JSON float64. Match the transform's precision.
			if not is_equal_approx(float(before.building.floor_y)+delta_y,float(after.building.floor_y)):return {"ok":false,"reason":"floor_elevation"}
			if not changed.has(owner):changed[owner]={}
			changed[owner][after.building.part]=[before,after]
			if not current.get("extras",{}).has("building"):return {"ok":false,"reason":"building_extras"}
			current.extras.building=after.building.duplicate(true)
		_set_pose(current,pose(after));updated+=1
	var fresh:=extras(records,meta)
	if not _metadata_compatible(previous,fresh,changed):return {"ok":false,"reason":"metadata_change"}
	root.extras=fresh
	return {"ok":true,"updated":updated}

static func attempt(path: String, expected: Variant, records: Array, meta: Dictionary, content_root: String, io: Script, progress: Callable=Callable()) -> Dictionary:
	var started:=Time.get_ticks_usec()
	if progress.is_valid():progress.call("reuse",0,0)
	var sources:=source_files(records,content_root,io)
	if not sources.ok:return {"handled":true,"error":ERR_INVALID_DATA}
	var source_ms:float=(Time.get_ticks_usec()-started)/1000.0
	var fallback:Dictionary={"handled":false,"sources":sources,"reason":"no_baseline","refresh_sources":true,"source_probe_ms":source_ms}
	if expected==null or path.get_extension().to_lower()!="gltf" or not FileAccess.file_exists(path):return fallback
	var err:Error=io._acquire_save_lock(path)
	if err!=OK:return {"handled":true,"error":err}
	var result:=_attempt_locked(path,str(expected),records,meta,content_root,io,progress,sources)
	io._remove_tree(path+".save-lock")
	result["reuse_check_ms"]=(Time.get_ticks_usec()-started)/1000.0
	result["source_probe_ms"]=source_ms
	return result

static func _attempt_locked(path: String, expected: String, records: Array, meta: Dictionary, content_root: String, io: Script, progress: Callable, sources: Dictionary) -> Dictionary:
	var phase:=Time.get_ticks_usec();var timings:Dictionary={}
	var bytes:=FileAccess.get_file_as_bytes(path)
	if sha256_bytes(bytes)!=expected:return {"handled":true,"error":ERR_BUSY}
	var text:=bytes.get_string_from_utf8();var parser:=JSON.new()
	var data:Dictionary={}
	if parser.parse(text)==OK and parser.data is Dictionary:data=parser.data
	var manifest_value:Variant=data.get("extras",{}).get(MANIFEST,{}) if data.get("extras",{}) is Dictionary else {}
	var manifest:Dictionary=manifest_value if manifest_value is Dictionary else {}
	var source_match:bool=sources.ok and manifest.get("version")==FORMAT_VERSION and manifest.get("generator")==sources.get("generator") and same(manifest.get("sources"),sources.files)
	var result:Dictionary={"handled":false,"sources":sources,"reason":"source_changed_or_missing_baseline","refresh_sources":not source_match}
	if not source_match:return result
	if not valid_content_bytes(bytes,text,manifest):result.reason="baseline_content_changed";return result
	bytes=PackedByteArray();text="";parser=null
	timings.read_verify_ms=(Time.get_ticks_usec()-phase)/1000.0;phase=Time.get_ticks_usec()
	var resources:=dependencies(data,path,content_root,io)
	if not resources.ok or not same(resources.get("files"),manifest.get("dependencies")):
		result.reason="published_dependency_changed";return result
	timings.dependencies_ms=(Time.get_ticks_usec()-phase)/1000.0;phase=Time.get_ticks_usec()
	var ready:=update(data,records,meta)
	if not ready.ok:result.reason=ready.reason;return result
	timings.pose_compare_ms=(Time.get_ticks_usec()-phase)/1000.0;phase=Time.get_ticks_usec()
	var staged:=path+".pose.%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	if progress.is_valid():progress.call("publish",0,0)
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:return {"handled":true,"error":FileAccess.get_open_error()}
	file.store_buffer(serialize_bytes(data));file.flush()
	var err:=file.get_error();file.close()
	timings.serialize_ms=(Time.get_ticks_usec()-phase)/1000.0;phase=Time.get_ticks_usec()
	if err==OK and io.save_fault.is_valid() and io.save_fault.call("resources_ready"):err=ERR_FILE_CANT_WRITE
	if err==OK and io.save_fault.is_valid() and io.save_fault.call("before_publish"):err=ERR_FILE_CANT_WRITE
	# Do not replace an external writer or trust a resource that changed while
	# the new JSON was being prepared. The published dependency versions stay immutable.
	if err==OK and FileAccess.get_sha256(path)!=expected:err=ERR_BUSY
	if err==OK:
		var sources_valid:=verify_source_files(sources,content_root)
		var current_resources:=dependencies(data,path,content_root,io)
		if not sources_valid or not current_resources.ok or not same(current_resources.get("files"),resources.files):err=ERR_BUSY
	var signature:=FileAccess.get_sha256(staged) if err==OK else ""
	if err==OK and FileAccess.get_sha256(path)!=expected:err=ERR_BUSY
	timings.final_verify_ms=(Time.get_ticks_usec()-phase)/1000.0;phase=Time.get_ticks_usec()
	if err==OK:err=preload("res://scripts/world3d/atomic_file.gd").publish(staged,path)
	io._remove_file(staged)
	timings.atomic_publish_ms=(Time.get_ticks_usec()-phase)/1000.0
	return {"handled":true,"error":err,"signature":signature,"mode":"pose_reuse","updated_nodes":ready.updated,"reused_images":data.get("images",[]).size(),"reused_buffers":data.get("buffers",[]).size(),"texture_export_passes":0,"images_written":0,"phases":timings}

static func install_manifest(data: Dictionary, path: String, sources: Dictionary, content_root: String, io: Script) -> void:
	if not verify_source_files(sources,content_root):return
	var resources:=dependencies(data,path,content_root,io)
	if not resources.ok:return
	if not data.get("extras") is Dictionary:data.extras={}
	data.extras[MANIFEST]={"version":FORMAT_VERSION,"generator":sources.generator,"sources":sources.files,"dependencies":resources.files}

static func refresh_export_sources(document: RefCounted) -> void:
	# Main thread only. Existing live instances retain their resources; future
	# export builds must not associate new disk hashes with old cached pixels.
	document._save_meshes=load("res://scripts/world3d/save_mesh_cache.gd").new()
	var paint=load("res://scripts/world3d/surface_materials.gd")
	paint._materials.clear();paint._textures.clear();paint.prepared_images.clear()
	load("res://scripts/world_editor/asset_library.gd")._scenes.clear()
	var prefab=load("res://scripts/world3d/house_prefab.gd")
	prefab._meshes.clear();prefab._render_meshes.clear()
	for name_ in ["timber_door_mesh","interior_door_mesh"]:
		var module=load("res://scripts/world3d/"+name_+".gd")
		module._data.clear();module._meshes.clear()
	var fort=load("res://scripts/world3d/fortification_art.gd")
	fort.kits.clear();fort.cache.clear();fort.cache_sizes.clear();fort.cache_bytes=0
	var bridge=load("res://scripts/world3d/bridge_mesh.gd")
	bridge.kits.clear();bridge.meshes.clear()
	load("res://scripts/world3d/auto_tile_kit.gd")._meshes.clear()
	load("res://scripts/world3d/streetlamp_banner.gd")._meshes.clear()
	load("res://scripts/world3d/parametric_tree.gd").cache.clear()
