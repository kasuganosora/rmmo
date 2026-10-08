extends RefCounted
## CPU-only native reference document. Standard glTF consumers see placement
## cubes; native readers resolve immutable authored definitions separately.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Store = preload("res://scripts/world3d/map_resource_store.gd")
const Atomic = preload("res://scripts/world3d/atomic_file.gd")
const VERSION := 2
const STORAGE := "references_v1"

static func _json_safe(value: Variant, ancestors: Array, budget: Array) -> bool:
	budget[0]-=1
	if budget[0]<0 or ancestors.size()>64:return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_STRING:return true
		TYPE_INT:return value>=-9007199254740991 and value<=9007199254740991
		TYPE_FLOAT:return is_finite(value)
		TYPE_ARRAY,TYPE_DICTIONARY:
			for parent in ancestors:
				if is_same(parent,value):return false
			ancestors.append(value)
			if value is Dictionary:
				for key in value:
					if not (key is String or key is StringName) or not _json_safe(value[key],ancestors,budget):ancestors.pop_back();return false
			else:
				for item in value:
					if not _json_safe(item,ancestors,budget):ancestors.pop_back();return false
			ancestors.pop_back();return true
	return false

static func _result(error: int) -> Dictionary:
	return {"error":error,"signature":"","mode":"reference_map","resources_written":0,
		"resources_reused":0,"reused":0,"bytes_written":0,"images_written":0,
		"texture_export_passes":0,"phases":{}}

static func save(path: String, expected: Variant, records: Array, map_meta: Dictionary,
		content_root: String, io: Script, progress: Callable=Callable()) -> Dictionary:
	var result := _result(ERR_INVALID_PARAMETER)
	# Metadata is JSON, unlike immutable CPU definitions. Reject native values
	# that JSON.stringify would silently turn into lossy strings.
	if not _json_safe(map_meta,[],[2000000]):return result
	# Validate the original input before canonicalization: never turn a relative
	# path or an engine URI into an apparently permitted external path.
	if path.get_extension().to_lower()!="gltf" or not Paths.allowed(path,content_root):return result
	path=path.replace("\\","/").simplify_path()
	var staged:=path+".reference.%d.%d.tmp"%[OS.get_process_id(),Time.get_ticks_usec()]
	for candidate in [path+".previous",path+".save-lock",staged]:
		if not Paths.allowed(candidate,content_root):return result
	var error:=DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error!=OK:result.error=error;return result
	error=io._acquire_save_lock(path)
	if error!=OK:result.error=error;return result
	result=_save_locked(path,staged,expected,records,map_meta,content_root,io,progress)
	# Every normal error path has one cleanup owner. Published immutable objects
	# remain available to other maps/history, including after a failed map save.
	io._remove_file(staged)
	io._remove_tree(path+".save-lock")
	return result

static func _save_locked(path: String, staged: String, expected: Variant, records: Array,
		map_meta: Dictionary, content_root: String, io: Script, progress: Callable) -> Dictionary:
	var result:=_result(OK)
	var mark:=Time.get_ticks_usec()
	var existed:=FileAccess.file_exists(path)
	var baseline:=FileAccess.get_sha256(path) if existed else ""
	if (existed and baseline.is_empty()) or (expected!=null and baseline!=str(expected)):
		result.error=ERR_BUSY;return result
	result.phases.initial_verify_ms=(Time.get_ticks_usec()-mark)/1000.0
	mark=Time.get_ticks_usec()
	if progress.is_valid():progress.call("resources",0,records.size())
	var stored:=Store.write_records(records,path,content_root,progress)
	result.phases.resources_ms=(Time.get_ticks_usec()-mark)/1000.0
	if not stored.ok:result.error=stored.error;result.reason=stored.get("reason","");return result
	result.resources_written=stored.resources_written
	result.resources_reused=stored.get("resources_reused",stored.get("reused",0))
	result.reused=result.resources_reused
	result.bytes_written=stored.bytes_written
	for key in ["encoding_cache_hits","encoding_cache_misses","encoded_raw_bytes","encoding_ms","verified_bytes",
		"identity_cache_hits","serialized_raw_bytes","compression_count","identity_cache_entries"]:
		result[key]=stored.get(key,0)
	if io.save_fault.is_valid() and io.save_fault.call("resources_ready"):
		result.error=ERR_FILE_CANT_WRITE;return result
	mark=Time.get_ticks_usec()
	var data:=proxy_document(stored.records,map_meta,stored.dependencies)
	var bytes:=JSON.stringify(data,"",false,true).to_utf8_buffer()
	if progress.is_valid():progress.call("publish",0,0)
	var file:=FileAccess.open(staged,FileAccess.WRITE)
	if file==null:result.error=FileAccess.get_open_error();return result
	file.store_buffer(bytes);file.flush()
	result.error=file.get_error();file.close()
	result.map_bytes_written=bytes.size()
	result.phases.serialize_ms=(Time.get_ticks_usec()-mark)/1000.0
	if result.error!=OK:return result
	if io.save_fault.is_valid() and io.save_fault.call("before_publish"):
		result.error=ERR_FILE_CANT_WRITE;return result
	mark=Time.get_ticks_usec()
	# Resource filenames are not proof of immutable bytes. Recheck complete
	# published definitions after the map staging write and fault hook.
	if not Store.verify_dependencies(stored.dependencies,path,content_root):
		result.error=ERR_BUSY;return result
	var signature:=FileAccess.get_sha256(staged)
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes)
	if signature.is_empty() or signature!=context.finish().hex_encode():
		result.error=ERR_FILE_CORRUPT;return result
	# Even Save As / explicitly authorized overwrite gets an observation at the
	# start and immediately before publication. No await or callback follows it.
	if FileAccess.file_exists(path)!=existed or (existed and FileAccess.get_sha256(path)!=baseline):
		result.error=ERR_BUSY;return result
	result.phases.final_verify_ms=(Time.get_ticks_usec()-mark)/1000.0
	mark=Time.get_ticks_usec()
	result.error=Atomic.publish(staged,path)
	result.phases.atomic_publish_ms=(Time.get_ticks_usec()-mark)/1000.0
	if result.error==OK:result.signature=signature
	return result

static func proxy_document(records: Array, map_meta: Dictionary, dependencies: Dictionary) -> Dictionary:
	var extras:=map_meta.duplicate(true)
	# Caller metadata cannot impersonate the writer's format or replace the
	# authoritative records/dependency closure with unverified alternatives.
	for key in extras.keys():
		if str(key).begins_with("rmmo_"):extras.erase(key)
	extras.merge({"rmmo_format":"rmmo_gltf_map","rmmo_version":VERSION,"rmmo_unit":"m",
		"rmmo_storage":STORAGE,"rmmo_records":records.duplicate(true),
		"rmmo_resource_dependencies":dependencies.duplicate(true)},true)
	var nodes:Array=[{"name":"rmmo_world","extras":extras}]
	var children:Array=[]
	for record:Dictionary in records:
		var angles:Array=record.rotation
		var rotation:=Quaternion.from_euler(Vector3(float(angles[0]),float(angles[1]),float(angles[2]))*PI/180.0)
		children.append(nodes.size())
		nodes.append({"name":record.uuid,"mesh":0,"translation":record.position.duplicate(),
			"rotation":[rotation.x,rotation.y,rotation.z,rotation.w],"scale":record.size.duplicate(),
			"extras":{"rmmo_proxy":true,"uuid":record.uuid}})
	if not children.is_empty():nodes[0].children=children
	# Unit cube, outward-wound faces and explicit normals. All instances share
	# this tiny embedded geometry/material; no editor rendering resources exist.
	var positions:=PackedFloat32Array();var normals:=PackedFloat32Array();var indices:=PackedByteArray()
	var faces:Array=[
		[Vector3.RIGHT,Vector3(.5,-.5,-.5),Vector3(.5,.5,-.5),Vector3(.5,.5,.5),Vector3(.5,-.5,.5)],
		[Vector3.LEFT,Vector3(-.5,-.5,.5),Vector3(-.5,.5,.5),Vector3(-.5,.5,-.5),Vector3(-.5,-.5,-.5)],
		[Vector3.UP,Vector3(-.5,.5,-.5),Vector3(-.5,.5,.5),Vector3(.5,.5,.5),Vector3(.5,.5,-.5)],
		[Vector3.DOWN,Vector3(-.5,-.5,.5),Vector3(-.5,-.5,-.5),Vector3(.5,-.5,-.5),Vector3(.5,-.5,.5)],
		[Vector3.BACK,Vector3(-.5,-.5,.5),Vector3(.5,-.5,.5),Vector3(.5,.5,.5),Vector3(-.5,.5,.5)],
		[Vector3.FORWARD,Vector3(.5,-.5,-.5),Vector3(-.5,-.5,-.5),Vector3(-.5,.5,-.5),Vector3(.5,.5,-.5)]]
	for face_index in faces.size():
		var face:Array=faces[face_index]
		for vertex:Vector3 in face.slice(1):
			positions.append_array([vertex.x,vertex.y,vertex.z])
			var normal:Vector3=face[0];normals.append_array([normal.x,normal.y,normal.z])
		for index in [0,1,2,0,2,3]:
			var offset:=indices.size();indices.resize(offset+2);indices.encode_u16(offset,face_index*4+index)
	var buffer:=positions.to_byte_array();buffer.append_array(normals.to_byte_array());buffer.append_array(indices)
	return {"asset":{"version":"2.0","generator":"RMMO reference map"},"scene":0,
		"scenes":[{"nodes":[0]}],"nodes":nodes,
		"meshes":[{"name":"Placement proxy","primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0}]}],
		"materials":[{"name":"Placement proxy","pbrMetallicRoughness":{"baseColorFactor":[.55,.65,.75,1],"metallicFactor":0,"roughnessFactor":1}}],
		"buffers":[{"byteLength":buffer.size(),"uri":"data:application/octet-stream;base64,"+Marshalls.raw_to_base64(buffer)}],
		"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":288,"target":34962},
			{"buffer":0,"byteOffset":288,"byteLength":288,"target":34962},{"buffer":0,"byteOffset":576,"byteLength":72,"target":34963}],
		"accessors":[{"bufferView":0,"componentType":5126,"count":24,"type":"VEC3","min":[-.5,-.5,-.5],"max":[.5,.5,.5]},
			{"bufferView":1,"componentType":5126,"count":24,"type":"VEC3"},{"bufferView":2,"componentType":5123,"count":36,"type":"SCALAR"}]}
