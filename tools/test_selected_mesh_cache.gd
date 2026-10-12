extends SceneTree
## Default is CPU-only cache identity/geometry coverage. --gpu exercises actual
## cold/hot MapLoader entry; use tools/run_godot_background.py for that mode.
const Cook=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Fixtures=preload("res://tools/test_map_dependency_index.gd")
var passed:=0
var failures:=0
var folder:=""
var created:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func put(path:String,bytes:PackedByteArray)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
func compact(uuid:String)->Dictionary:
	return {"uuid":uuid,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"rmmo_state":{},"rmmo_ref":{"version":1,"uri":"map.gltf.resources/"+"a".repeat(64)+".rmres","sha256":"a".repeat(64),"length":128}}
func triangle()->Mesh:
	var mesh:=Cpu.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD]);arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	mesh.surfaces=[arrays];mesh.materials.append(null);mesh.bounds=AABB(Vector3(0,0,-1),Vector3(1,0,1))
	return mesh
func spec(mesh:Mesh)->Dictionary:
	return {"uuid":"near","extras":{"uuid":"near","surface_id":"ground","rmmo_collision":"walk"},"native_visual":false,"cast_shadow":1,"transform":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"material_override":null,"surface_overrides":[],"mesh":mesh,"collision_mesh":mesh}
func envelope(data:Dictionary,selection:String)->PackedByteArray:
	var bytes:=var_to_bytes(data);var result:=Cook.MAGIC.to_ascii_buffer();result.resize(17);result.encode_u64(9,bytes.size())
	var source_key:=Cook._source_identity(data.digest,selection);var generator_key:=Cook._identity(data.generator)
	result.append_array(source_key);result.append_array(generator_key);result.append_array(Cook._checksum(source_key,generator_key,bytes));result.append_array(bytes)
	return result
func run()->void:
	folder=Paths.cache_directory("selected_mesh_cache_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("cache_fixture.gltf");var near:=compact("near");var far:=compact("far")
	var a:=Cook.selection_identity([0],[near]);var b:=Cook.selection_identity([1],[far])
	check(not a.is_empty() and a!=b and Cook.selection_identity([0],[near.duplicate(true)])==a,"exact original ordered compact selection has a stable distinct identity")
	check(Cook.selection_identity([1,0],[near,far]).is_empty() and Cook.selection_identity([0,1],[near,near]).is_empty(),"unordered and duplicate selections are rejected")
	var changed:=near.duplicate(true);changed.position[0]=1
	check(Cook.selection_identity([0],[changed])!=a,"pose change cannot borrow a selected geometry identity")
	changed=near.duplicate(true);changed.rmmo_ref.sha256="b".repeat(64)
	check(Cook.selection_identity([0],[changed])!=a,"definition hash change cannot borrow a selected identity")
	var a_path:=Cook.cache_path(path,a);var b_path:=Cook.cache_path(path,b);var full_path:=Cook.cache_path(path)
	created.append_array([a_path,b_path,full_path])
	check(a_path!=b_path and a_path!=full_path and Cook.cache_path(path,"../escape").is_empty(),"selected entries and full-map cache use separate controlled paths")
	var mesh:=triangle();var cold_spec:=spec(mesh);var data:=Cook.pack({["triangle"]:{"mesh":mesh,"source":mesh}},"source","generator",[cold_spec])
	data.selection=a;data.models={"model":"a".repeat(64)}
	Cook.write(path,data,a);var original:=FileAccess.get_file_as_bytes(a_path);var diagnostics:Dictionary={}
	var hot:=Cook.read(path,"source","generator",diagnostics,a)
	check(not hot.is_empty() and diagnostics.reason=="hit" and Cook.models_match(hot,data.models),"matching selected closure verifies and restores its own cooked payload")
	Cook.restore(hot);var restored:=Cook.restore_specs(hot,[{"uuid":"near","kind":"box"}])
	check(restored.size()==1 and restored[0].transform==cold_spec.transform and restored[0].extras==cold_spec.extras and restored[0].mesh.surfaces==mesh.surfaces and restored[0].collision_mesh.surfaces==mesh.surfaces,"cold and hot geometry preserve transforms, render arrays, collision arrays and gameplay metadata")
	check(Cook.restore_specs(hot,[{"uuid":"far","kind":"box"}]).is_empty(),"selected cooked UUID closure cannot restore a different district")
	check(not Cook.models_match(hot,{"model":"b".repeat(64)}) and not Cook.models_match(hot,{}),"changed or removed model signatures reject geometry reuse")
	check(Cook.read(path,"source","generator",null,b).is_empty() and Cook.read(path,"source","generator").is_empty(),"selected cache is never searched through another closure or whole-map namespace")
	put(b_path,original);diagnostics={}
	check(Cook.read(path,"source","generator",diagnostics,b).is_empty() and diagnostics.payload_bytes_read==0,"copying a valid payload into another closure rejects before payload allocation")
	put(full_path,original);diagnostics={}
	check(Cook.read(path,"source","generator",diagnostics).is_empty() and diagnostics.payload_bytes_read==0,"selected cache copied over the full-map path still cannot cross its envelope identity")
	var full:=data.duplicate();full.erase("selection");Cook.write(path,full)
	put(a_path,FileAccess.get_file_as_bytes(full_path));diagnostics={}
	check(Cook.read(path,"source","generator",diagnostics,a).is_empty() and diagnostics.payload_bytes_read==0,"whole-map cache cannot masquerade as the selected closure")
	put(a_path,original);diagnostics={}
	check(Cook.read(path,"new-source","generator",diagnostics,a).is_empty() and diagnostics.payload_bytes_read==0,"changed complete author source invalidates selected geometry before reading arrays")
	diagnostics={}
	check(Cook.read(path,"source","new-generator",diagnostics,a).is_empty() and diagnostics.payload_bytes_read==0,"changed geometry generator invalidates selected geometry")
	var wrong:=data.duplicate();wrong.selection=b;put(a_path,envelope(wrong,a))
	check(Cook.read(path,"source","generator",null,a).is_empty(),"valid envelope checksum still requires exact selection identity in payload")
	var corrupt:=original.duplicate();corrupt[-1]^=1;put(a_path,corrupt)
	check(Cook.read(path,"source","generator",null,a).is_empty(),"selected payload corruption is a disposable miss")
	put(a_path,original)
	if "--gpu" in OS.get_cmdline_user_args():await loader_cases()
	for file:String in created:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	for file:String in created:
		if file.get_extension()=="gltf":DirAccess.remove_absolute(file+".resources")
	DirAccess.remove_absolute(folder)
	print("SELECTED_MESH_CACHE passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
func load_case(path:String,origin:Vector3)->Dictionary:
	var loader:=Loader.new();loader.near_first=true;root.add_child(loader);var result:={"done":false}
	loader.finished.connect(func(scene:Node,_path:String,error:String):result.scene=scene;result.error=error;result.done=true)
	loader.start(path,origin);var deadline:=Time.get_ticks_msec()+60000
	while is_instance_valid(loader) and Time.get_ticks_msec()<deadline:await process_frame
	check(result.done and result.get("scene")!=null and result.get("error","").is_empty(),"actual selected MapLoader entry succeeds")
	if not result.get("scene") is Node:return {}
	var scene:Node=result.scene;var profile:Dictionary=scene.get_meta("load_profile",{}).duplicate(true);var geometry:Dictionary={}
	for value:Dictionary in scene.get_meta("stream_library",[]):
		var render:Mesh=Cpu.capture(value.mesh);var solid:Mesh=Cpu.capture(value.get("collision_mesh",value.mesh));var materials:Array=[]
		for material:Material in render.materials:materials.append(Cook.material_data(material))
		geometry[value.uuid]=[value.transform,value.extras,var_to_bytes(render.surfaces),var_to_bytes(solid.surfaces),materials]
	var cache_path:String=profile.get("mesh_cache_path","")
	if not cache_path.is_empty():created.append(cache_path)
	scene.free();return {"profile":profile,"geometry":geometry}
func loader_cases()->void:
	var helper:=Fixtures.new();helper.folder=folder;helper.content_root=Paths.external_root()
	var terrain:Dictionary=helper.box("terrain",0);terrain.position=[0,0,0];terrain.size=[32,1,32];terrain.surface_id="ground";terrain.collision="walk"
	terrain.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-2,"heights":[0,1,2,0,1,2,0,1,2],"holes":[false,false,false,false]}
	var records:Array=[helper.box("near",0),helper.box("far",600),terrain]
	var f:Dictionary=helper.fixture("actual_loader",records);created.append_array(helper.created);helper.free()
	check(Index.build(f.path,Paths.external_root(),records).ok,"temporary map builds its dependency directory")
	var source_sha:=FileAccess.get_sha256(f.path)
	var cold:Dictionary=await load_case(f.path,Vector3(0,.9,0));var hot:Dictionary=await load_case(f.path,Vector3(0,.9,0))
	if cold.is_empty() or hot.is_empty():return
	check(not cold.profile.mesh_cache_candidate and hot.profile.mesh_cache_candidate and hot.profile.terrain_context_cache_hit,"same selected entry reuses cooked geometry and exact terrain context on the hot load")
	check(cold.geometry==hot.geometry and hot.profile.cooked_specs>0,"actual cold and hot selected entries have identical render, collision, materials and metadata")
	var elsewhere:Dictionary=await load_case(f.path,Vector3(600,.9,0))
	check(not elsewhere.is_empty() and not elsewhere.profile.mesh_cache_candidate and elsewhere.profile.mesh_cache_selection!=hot.profile.mesh_cache_selection and elsewhere.geometry.has("far") and not elsewhere.geometry.has("near"),"a different entry uses a different selected namespace and its own local geometry")
	check(FileAccess.get_sha256(f.path)==source_sha,"selected cold and hot loads never modify the authored map")
