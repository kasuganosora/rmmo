extends SceneTree
const Writer=preload("res://scripts/world3d/reference_map_save.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
var checks:=0
var directory:=""

func _initialize()->void:
	_run.call_deferred()

func _check(value:bool,label:String)->bool:
	checks+=1
	if value:print("PASS ",label)
	else:failures+=1;push_error("FAIL "+label)
	return value

func _write(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes);file.flush();file.close()

func _read(path:String)->Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _clean(path:String)->bool:
	if DirAccess.dir_exists_absolute(path+".save-lock"):return false
	for file in DirAccess.get_files_at(path.get_base_dir()):
		if file.begins_with(path.get_file()+".reference.") and file.ends_with(".tmp"):return false
	return true

func _record(id:String)->Dictionary:
	return {"uuid":id,"kind":"box","position":[1,2,3],"rotation":[0,30,0],"size":[2,3,4],
		"surface_id":"block","collision":"walk","editor_locked":true,
		"fixture":{"kind":"door","open":false},"building":{"id":"b1","part":"door","floor":0,"role":"door","floor_y":0}}

func _run()->void:
	var root:=Paths.external_root()
	directory=Paths.cache_directory("reference_writer_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var records:Array=[_record("one"),_record("two")]
	records[1].position=[7,2,3]
	var original:=JSON.stringify(records)
	var metadata:={"name":"引用场景","rmmo_format":"evil","rmmo_version":999,"rmmo_records":[],
		"rmmo_storage":"evil","rmmo_resource_dependencies":{"evil":"bad"},"rmmo_save_manifest":{"generator":"forged"}}
	var saved:=Writer.save(path,null,records,metadata,root,Io)
	if not _check(saved.error==OK,"first reference save"):_finish();return
	_check(saved.mode=="reference_map" and saved.images_written==0 and saved.texture_export_passes==0,"no real geometry texture export")
	_check(saved.resources_written==1 and saved.resources_reused==0,"identical definitions shared across UUID and pose")
	_check(JSON.stringify(records)==original,"writer does not mutate authored records")
	var data:=_read(path)
	var extras:Dictionary=data.nodes[0].extras
	_check(extras.rmmo_format=="rmmo_gltf_map" and extras.rmmo_version==2 and extras.rmmo_storage=="references_v1","metadata cannot override reserved format")
	_check(extras.name=="引用场景" and not extras.has("rmmo_save_manifest") and extras.rmmo_records.size()==2 and extras.rmmo_resource_dependencies.size()==1,"metadata and verified record dependency closure")
	_check(data.nodes.size()==3 and data.nodes[1].name=="one" and data.nodes[2].name=="two" and data.nodes[1].mesh==data.nodes[2].mesh,"one proxy per independent UUID")
	_check(data.nodes[1].translation==[1.,2.,3.] and data.nodes[1].scale==[2.,3.,4.],"proxy pose and size")
	_check(data.meshes.size()==1 and data.materials.size()==1 and data.buffers.size()==1 and str(data.buffers[0].uri).begins_with("data:"),"tiny embedded shared cube")
	var hydrated:=Store.read_records(extras.rmmo_records,path,root)
	_check(hydrated.ok and preload("res://scripts/world3d/pose_save.gd").same(hydrated.records,records),"floor fixture collision lock and definitions roundtrip")
	var importer:=GLTFDocument.new();var state:=GLTFState.new()
	_check(importer.append_from_file(path,state)==OK and state.meshes.size()==1 and state.nodes.size()==3,"standard glTF importer reads proxy document")
	var first_bytes:=FileAccess.get_file_as_bytes(path)
	var first_signature:String=saved.signature
	records[0].position=[9,8,7];records[0].rotation=[10,20,30];records[0].size=[4,5,6]
	saved=Writer.save(path,saved.signature,records,metadata,root,Io)
	_check(saved.error==OK and saved.resources_written==0 and saved.reused==1,"move and resize reuse immutable resource")
	_check(FileAccess.get_file_as_bytes(path+".previous")==first_bytes,"atomic replacement keeps previous reference document")
	data=_read(path)
	var q:=Quaternion.from_euler(Vector3(10,20,30)*PI/180.)
	var rotation:Array=data.nodes[1].rotation
	_check(Vector3(data.nodes[1].translation[0],data.nodes[1].translation[1],data.nodes[1].translation[2])==Vector3(9,8,7) and Quaternion(rotation[0],rotation[1],rotation[2],rotation[3]).is_equal_approx(q),"TRS rotation and moved position")
	var added:Dictionary=records[0].duplicate(true);added.uuid="three";records.append(added)
	saved=Writer.save(path,saved.signature,records,metadata,root,Io)
	_check(saved.error==OK and saved.resources_written==0 and _read(path).nodes.size()==4,"add copied instance changes only lightweight map")
	records.remove_at(1)
	saved=Writer.save(path,saved.signature,records,metadata,root,Io)
	_check(saved.error==OK and saved.resources_written==0 and _read(path).nodes.size()==3,"remove instance retains shared definition")
	var baseline:=FileAccess.get_file_as_bytes(path)
	var signature:String=saved.signature
	var stale:=Writer.save(path,first_signature,records,metadata,root,Io)
	_check(stale.error==ERR_BUSY and FileAccess.get_file_as_bytes(path)==baseline and _clean(path),"initial stale signature rejected without changing map")
	for phase:String in ["resources_ready","before_publish"]:
		Io.save_fault=func(point:String)->bool:return point==phase
		var interrupted:=Writer.save(path,signature,records,metadata,root,Io)
		Io.save_fault=Callable()
		_check(interrupted.error==ERR_FILE_CANT_WRITE and FileAccess.get_file_as_bytes(path)==baseline and _clean(path),phase+" fault keeps map and cleans lock/temp")
	data=_read(path)
	var dependencies:Dictionary=data.nodes[0].extras.rmmo_resource_dependencies
	var resource_path:=directory.path_join(str(dependencies.keys()[0]))
	var resource_bytes:=FileAccess.get_file_as_bytes(resource_path)
	Io.save_fault=func(point:String)->bool:
		if point=="before_publish":
			var bad:=resource_bytes.duplicate();bad[bad.size()-1]^=1;_write(resource_path,bad)
		return false
	var tampered:=Writer.save(path,signature,records,metadata,root,Io)
	Io.save_fault=Callable();_write(resource_path,resource_bytes)
	_check(tampered.error==ERR_BUSY and FileAccess.get_file_as_bytes(path)==baseline and _clean(path),"resource mutation after staging rejected by final complete check")
	var changed:=baseline.duplicate();changed.append(32)
	Io.save_fault=func(point:String)->bool:
		if point=="before_publish":_write(path,changed)
		return false
	var conflict:=Writer.save(path,signature,records,metadata,root,Io)
	Io.save_fault=Callable()
	_check(conflict.error==ERR_BUSY and FileAccess.get_file_as_bytes(path)==changed and _clean(path),"external map writer before publish is preserved")
	_write(path,baseline)
	var new_path:=directory.path_join("appeared.gltf")
	Io.save_fault=func(point:String)->bool:
		if point=="before_publish":_write(new_path,baseline)
		return false
	var appeared:=Writer.save(new_path,null,records,metadata,root,Io)
	Io.save_fault=Callable()
	_check(appeared.error==ERR_BUSY and FileAccess.get_file_as_bytes(new_path)==baseline and _clean(new_path),"new map does not overwrite concurrently appeared destination")
	var duplicates:Array=[records[0],records[0]]
	var invalid:=Writer.save(path,signature,duplicates,metadata,root,Io)
	_check(invalid.error!=OK and FileAccess.get_file_as_bytes(path)==baseline and _clean(path),"duplicate UUID input fails without map side effects")
	var outside:=Writer.save("D:/reference_map_outside_test.gltf",null,records,metadata,root,Io)
	_check(outside.error==ERR_INVALID_PARAMETER,"resource root restriction enforced before writes")
	for invalid_meta in [{"value":Vector3.ONE},{"value":9007199254740992},{"value":NAN}]:
		var rejected:=Writer.save(path,signature,records,invalid_meta,root,Io)
		_check(rejected.error==ERR_INVALID_PARAMETER and FileAccess.get_file_as_bytes(path)==baseline and _clean(path),"non-JSON or lossy map metadata rejected before publication")
	var migration:=directory.path_join("old_inline.gltf")
	var old_bytes:=JSON.stringify({"asset":{"version":"2.0"},"scenes":[{"nodes":[0]}],"nodes":[{"extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_records":records}}]}).to_utf8_buffer()
	_write(migration,old_bytes)
	var migrated:=Writer.save(migration,FileAccess.get_sha256(migration),records,metadata,root,Io)
	_check(migrated.error==OK and _read(migration).nodes[0].extras.rmmo_version==2 and FileAccess.get_file_as_bytes(migration+".previous")==old_bytes,"old inline file migrates using original conflict signature")
	var empty:=Writer.save(path,signature,[],metadata,root,Io)
	_check(empty.error==OK and _read(path).nodes.size()==1 and not _read(path).nodes[0].has("children"),"empty reference map remains valid")
	_check(_clean(path),"successful map save cleans lock and temporary file")
	_finish()

func _finish()->void:
	Io.save_fault=Callable()
	print("REFERENCE MAP WRITER: ",checks-failures,"/",checks," PASS; failures=",failures)
	print("Temporary fixture: ",directory)
	quit(0 if failures==0 else 1)
