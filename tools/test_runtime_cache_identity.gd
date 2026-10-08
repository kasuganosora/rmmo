extends SceneTree
## Headless CPU regression: disposable envelope and complete cooked-spec UUID set.
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
var failed:=0
var directory:String
var path:String
func _init()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if not value:failed+=1
func triangle()->Mesh:
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	mesh.surfaces=[arrays];mesh.materials.append(null);mesh.bounds=AABB(Vector3(0,0,-1),Vector3(1,0,1))
	return mesh
func spec(mesh:Mesh)->Dictionary:
	return {"uuid":"cached","extras":{"uuid":"cached"},"native_visual":false,"cast_shadow":1,"transform":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"material_override":null,"surface_overrides":[],"mesh":mesh,"collision_mesh":mesh}
func external_model()->String:
	var bytes:=PackedByteArray();bytes.resize(36)
	var points:=[Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]
	for index in points.size():
		for axis in 3:bytes.encode_float(index*12+axis*4,points[index][axis])
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,"+Marshalls.raw_to_base64(bytes)}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,-1],"max":[1,0,0]}]}
	var model_path:=directory.path_join("external_triangle.gltf")
	var file:=FileAccess.open(model_path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	check(document.append_from_file(model_path,state)==OK and state.meshes.size()==1,"external record points to a genuine parsed glTF model fixture")
	return model_path
func put(bytes:PackedByteArray)->void:
	var file:=FileAccess.open(Cook.cache_path(path),FileAccess.WRITE);file.store_buffer(bytes);file.close()
func envelope(payload:PackedByteArray,source:String,generator:String,checksum:PackedByteArray=PackedByteArray())->PackedByteArray:
	var result:=Cook.MAGIC.to_ascii_buffer();result.resize(17);result.encode_u64(9,payload.size())
	var source_key:=Cook._identity(source);var generator_key_:=Cook._identity(generator)
	result.append_array(source_key);result.append_array(generator_key_)
	result.append_array(Cook._checksum(source_key,generator_key_,payload) if checksum.is_empty() else checksum)
	result.append_array(payload);return result
func run()->void:
	directory=Paths.cache_directory("runtime_identity_%d"%Time.get_ticks_usec());path=directory.path_join("map.gltf")
	DirAccess.make_dir_recursive_absolute(directory)
	var mesh:=triangle();var model_path:=external_model();var model_sha:=FileAccess.get_sha256(model_path)
	var imported:={"uuid":"external","kind":"asset","asset_path":model_path,"position":[3.,0.,0.],"rotation":[0.,90.,0.],"size":[1.,1.,1.]}
	var regular:={"uuid":"cached","kind":"box"}
	var records:Array=[imported,regular]
	var data:=Cook.pack({["triangle"]:{"mesh":mesh,"source":mesh}},"source","generator",[spec(mesh)])
	check(Cook.valid_data(data) and data.specs.size()==1,"mixed source stores only the loader-owned cooked spec")
	Cook.write(path,data)
	var original:=FileAccess.get_file_as_bytes(Cook.cache_path(path));var metrics:Dictionary={}
	var restored:=Cook.read(path,"source","generator",metrics)
	check(not restored.is_empty() and metrics.reason=="hit" and metrics.payload_bytes_read==original.size()-Cook.HEADER_SIZE,"matching fixed identity still reads and verifies the complete payload")
	Cook.restore(restored)
	var specs:=Cook.restore_specs(restored,records)
	check(specs.size()==2 and specs[0].is_empty() and not specs[1].is_empty(),"ordinary external asset placeholder preserves neighboring cooked spec")
	check(specs.size()==2 and specs[1].transform==Transform3D.IDENTITY and specs[1].extras.uuid=="cached" and var_to_bytes(specs[1].mesh.surfaces)==var_to_bytes(mesh.surfaces) and specs[1].collision_mesh==specs[1].mesh,"cached transform extras render geometry and collision source remain exact")
	var reordered:=Cook.restore_specs(restored,[regular,imported])
	check(reordered.size()==2 and not reordered[0].is_empty() and reordered[1].is_empty(),"mixed record order is aligned by UUID")
	check(Cook.restore_specs(restored,[regular,regular]).is_empty(),"duplicate author UUIDs reject even if cache rows are unique")
	check(Cook.restore_specs(restored,[imported,{"uuid":"missing","kind":"box"}]).is_empty(),"missing ordinary cooked record rejects")
	check(Cook.restore_specs(restored,[imported]).is_empty(),"unexpected cached UUID rejects")
	var invalid:=restored.duplicate();invalid.specs=restored.specs.duplicate(true);invalid.specs.append(invalid.specs[0])
	check(Cook.restore_specs(invalid,records).is_empty(),"duplicate cached UUID rejects")
	invalid=restored.duplicate();invalid.specs=restored.specs.duplicate(true);invalid.specs.append({"fallback":true,"uuid":"external"})
	check(Cook.restore_specs(invalid,records).is_empty(),"unexpected cache entry for separately imported asset rejects")
	var prefab:={"uuid":"frozen","kind":"asset","house_prefab":{}}
	check(Cook.restore_specs(restored,[regular,prefab]).is_empty(),"asset with house_prefab still requires an explicit cache row")
	invalid=restored.duplicate();invalid.specs=restored.specs.duplicate(true);invalid.specs.append({"fallback":true,"uuid":"frozen"})
	var fallback:=Cook.restore_specs(invalid,[imported,regular,prefab])
	check(fallback.size()==3 and fallback[0].is_empty() and not fallback[1].is_empty() and fallback[2].is_empty(),"explicit frozen-prefab fallback coexists with imported placeholder and valid neighbor")
	invalid.specs[1].uuid="wrong"
	check(Cook.restore_specs(invalid,[imported,regular,prefab]).is_empty(),"fallback UUID mismatch rejects")
	metrics={};check(Cook.read(path,"changed","generator",metrics).is_empty() and metrics.reason=="identity_mismatch" and metrics.payload_bytes_read==0,"source mismatch rejects before reading payload")
	metrics={};check(Cook.read(path,"source","changed",metrics).is_empty() and metrics.payload_bytes_read==0,"generator mismatch rejects before reading payload")
	var corrupt:=original.duplicate();corrupt[corrupt.size()-1]^=1;put(corrupt)
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.reason=="checksum" and metrics.payload_bytes_read>0,"matching identities never bypass payload corruption")
	corrupt=original.duplicate();corrupt[17]^=1;put(corrupt)
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.payload_bytes_read==0,"corrupt identity header is a safe early miss")
	var wrong_body:=data.duplicate();wrong_body.digest="different-source"
	put(envelope(var_to_bytes(wrong_body),"source","generator"))
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.reason=="payload_identity","valid envelope checksum still requires payload source identity match")
	wrong_body=data.duplicate();wrong_body.generator="different-generator"
	put(envelope(var_to_bytes(wrong_body),"source","generator"))
	check(Cook.read(path,"source","generator").is_empty(),"valid envelope checksum still requires payload generator match")
	wrong_body=data.duplicate(true);wrong_body.meshes[0].materials=[999]
	put(envelope(var_to_bytes(wrong_body),"source","generator"))
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.reason=="invalid_data","matching identities and checksum retain complete geometry validation")
	var payload:=var_to_bytes(data)
	put(envelope(payload,"source","generator",Cook._checksum(Cook._identity("other"),Cook._identity("generator"),payload)))
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.reason=="checksum","checksum binds fixed identity bytes as well as payload")
	var old:="RMMOMESH1".to_ascii_buffer();old.resize(17);old.encode_u64(9,payload.size());old.append_array(Cook.Envelope.checksum(payload));old.append_array(payload);put(old)
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.payload_bytes_read==0,"old disposable envelope misses without decoding or migration")
	var large:=PackedByteArray();large.resize(8*1024*1024);put(envelope(large,"stale","generator"))
	metrics={};var started:=Time.get_ticks_usec()
	check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.payload_bytes_read==0,"large malformed stale payload is rejected without deserialization")
	print("STALE_HEADER_REJECT_MS=",(Time.get_ticks_usec()-started)/1000.)
	corrupt=original.duplicate();corrupt.encode_u64(9,268435457);put(corrupt)
	metrics={};check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.payload_bytes_read==0,"oversized declared payload rejected before allocation")
	put(original.slice(0,50));metrics={}
	check(Cook.read(path,"source","generator",metrics).is_empty() and metrics.payload_bytes_read==0,"truncated fixed header rejects")
	DirAccess.remove_absolute(Cook.cache_path(path));metrics={}
	check(Cook.read(path,"source","generator",metrics).is_empty(),"missing cache remains a normal miss")
	check(FileAccess.get_sha256(model_path)==model_sha,"source external model remains byte-for-byte unchanged")
	if failed==0:Io._remove_tree(directory)
	else:print("RUNTIME_CACHE_IDENTITY_FIXTURE ",directory)
	print("RUNTIME_CACHE_IDENTITY_FAILED=",failed);quit(0 if failed==0 else 1)
