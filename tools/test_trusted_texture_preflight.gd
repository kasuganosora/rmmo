extends SceneTree
## Headless native CPU geometry fixture. No GPU readback or user-map edits.
const Document=preload("res://scripts/world3d/world_document.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var passed:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1

func fixture(path:String)->Dictionary:
	var material:={"name":"declared unused material","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":path}
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(0,1,1)])
	# A legal unused material slot retains package dependency metadata. The
	# actual render/collision surface uses slot zero and binds no texture.
	var data:={"materials":[{"null":true},{"paint":material,"cull":0}],"meshes":[{"bounds":AABB(Vector3(-1,0,-1),Vector3(2,1,2)),"box_size":Vector3.ZERO,"surfaces":[arrays],"materials":[0]}],"entries":[[[0],[0,0]]],"specs":[]}
	var bytes:=var_to_bytes(data)
	return {"uuid":"native_preflight","kind":"box","position":[0.,0.,0.],"rotation":[0.,0.,0.],"size":[2.,1.,2.],"surface_id":"block","collision":"none","building":{"id":"building","part":"shell","role":"shell","floor":0,"floor_y":0.},"prefab_locked":true,"prefab_materials":[material],"house_prefab":{"version":1,"sha256":Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}}

func run()->void:
	var folder:=Paths.cache_directory("trusted_texture_preflight_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("declared.png")
	var image:=Image.create(8,8,false,Image.FORMAT_RGB8);image.fill(Color(.2,.6,.4))
	check(image.save_png(path)==OK,"temporary real PNG saved outside project")
	var record:=fixture(path)
	Policy.verify_packages=true
	check(Prefab.valid(record),"unused native material slot and declared dependencies satisfy strict prefab contract")
	var prepared:=Prefab.geometry(record)
	check(not prepared.is_empty() and prepared.mesh is Cpu and prepared.mesh.materials==[null],"real prefab CPU geometry has no bound paint texture")
	if prepared.is_empty():quit(1);return
	var source_sha:=FileAccess.get_sha256(path)
	Paint.texture_profile_enabled=true;Pixels.profile_enabled=true
	for mode:Dictionary in [
		{"label":"trusted mounted live","strict":false,"immutable":true,"effects":true,"reads":0},
		{"label":"strict mounted live","strict":true,"immutable":true,"effects":true,"reads":1},
		{"label":"interactive mutable","strict":false,"immutable":false,"effects":true,"reads":1},
		{"label":"offline effects disabled","strict":false,"immutable":true,"effects":false,"reads":1}]:
		Policy.verify_packages=mode.strict;Paint.refresh_sources();Pixels.reset_profile()
		var cache_path:=Pixels.cache_path(path,false)
		if FileAccess.file_exists(cache_path):DirAccess.remove_absolute(cache_path)
		var doc:=Document.new();doc.load_immutable_records=mode.immutable;doc.load_texture_checks={}
		var node:MeshInstance3D=doc._mesh(record,mode.effects)
		var counters:Dictionary=Paint.profile_snapshot().counters
		var reads:int=counters.get("paint.texture.runtime_image_lookup",0)
		print("PREFLIGHT_CASE ",JSON.stringify({"mode":mode.label,"reads":reads,"counters":counters}))
		check(not node.has_meta("paint_error") and node.mesh!=null,mode.label+" preserves successful real geometry construction")
		check(reads==mode.reads,mode.label+" performs "+str(mode.reads)+" extra declared-texture runtime reads")
		var checked:bool=doc.load_texture_checks.has(["decoded_texture",path,false])
		check(checked==(mode.reads==1),mode.label+" preserves intended preflight boundary")
		node.free();doc=null
	check(FileAccess.get_sha256(path)==source_sha,"all modes preserve original resource bytes")
	Paint.refresh_sources();Prefab._meshes.clear();Prefab._render_meshes.clear();prepared.clear()
	Paint.texture_profile_enabled=false;Pixels.profile_enabled=false;Policy.verify_packages=false
	var cache:=Pixels.cache_path(path,false)
	if FileAccess.file_exists(cache):DirAccess.remove_absolute(cache)
	DirAccess.remove_absolute(path)
	print("TRUSTED_TEXTURE_PREFLIGHT passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
