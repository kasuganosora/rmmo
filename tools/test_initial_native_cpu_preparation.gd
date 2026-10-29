extends SceneTree
## Real native read -> initial coordinator -> existing asset instance cursor.
## All generated products stay in the explicitly supplied external test root.
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Native=preload("res://scripts/world3d/native_model_product.gd")
const CpuPreparation=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Pump=preload("res://scripts/world3d/scene_preparation_pump.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failed:=0
var directory:=""
var measurements:Array=[]
class CancelAfterNative extends "res://scripts/world3d/model_parse_preparation.gd":
	func _candidate_stage(path:String,candidate:Dictionary,content_root:String)->Dictionary:
		var result:=super._candidate_stage(path,candidate,content_root)
		cancel();return result
class FailAfterNative extends "res://scripts/world3d/model_parse_preparation.gd":
	func _candidate_stage(path:String,candidate:Dictionary,content_root:String)->Dictionary:
		var result:=super._candidate_stage(path,candidate,content_root)
		result.error=ERR_INVALID_DATA;return result
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks+=1;print("PASS: " if ok else "FAIL: ",label_)
	if not ok:failed+=1
func write_json(path:String,value:Dictionary)->bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(value));file.close();return true
func product(kind:String)->Dictionary:
	var scene:=Node3D.new();scene.name="NativeFixture"
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.2,.6,.8)
	var roles:=["arch","pier","abutment","deck","parapet","post"]
	for i in (6 if kind=="bridge" else 64):
		var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
		if kind=="bridge":
			arrays=BoxMesh.new().get_mesh_arrays()
			material=StandardMaterial3D.new();material.resource_name="deck" if i==3 else ("trim" if i>=4 else "masonry")
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(0,material)
		if kind=="local":mesh.resource_local_to_scene=true
		for duplicate in (1 if kind=="bridge" else 2):
			var node:=MeshInstance3D.new();node.name=roles[i] if kind=="bridge" else "Mesh_%d_%d"%[i,duplicate];node.mesh=mesh
			if kind=="grass":node.set_meta("extras",{"rmmo_grass":true})
			scene.add_child(node);node.owner=scene
	var packed:=PackedScene.new();packed.pack(scene)
	packed.set_meta("compiled_asset_validated",true)
	var reuse:Dictionary={};var stats:=Footprint.measure(packed,reuse)
	if kind=="script":
		var behavior:=GDScript.new();behavior.source_code="extends Node3D\n";behavior.reload()
		scene.set_script(behavior);packed=PackedScene.new();packed.pack(scene);packed.set_meta("compiled_asset_validated",true)
		var forbidden:Dictionary={};var unsupported:=Footprint.measure(packed,forbidden)
		check(unsupported.is_empty() and not forbidden.get("safe",false),"offline classifier rejects scripted native fast reuse")
		reuse={"safe":false}
	var bounds:AABB=Assets.bounds_of(scene)
	Drainer.dispose_scene(scene)
	var folder:=Compiled.directory(directory);DirAccess.make_dir_recursive_absolute(folder)
	var staging:=folder.path_join(kind+"_staged.scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"save real "+kind+" native product")
	packed=null
	var sha:=FileAccess.get_sha256(staging);var target:=folder.path_join(sha+".scn")
	check(DirAccess.rename_absolute(staging,target)==OK,"publish isolated "+kind+" immutable product")
	stats.native_uncompressed_bytes=Footprint.native_uncompressed_bytes(target)
	var estimate:=Footprint.estimate_stats(stats)
	var source:=directory.path_join(kind+".glb") # Logical identity only; no raw source exists.
	var source_sha:=kind.sha256_text()
	var index:={"version":Compiled.VERSION,"source_sha":source_sha,"payload_sha":sha,"generator":Compiled.generator(),"bytes":FileAccess.get_file_as_bytes(target).size()}
	check(write_json(Compiled.index_path(source,directory),index),"publish "+kind+" native index")
	var descriptor:=index.duplicate();descriptor.version=Footprint.VERSION
	descriptor.merge({"source_path":source,"source_bytes":64,"footprint_generator":Footprint.generator(),"stats":stats,"estimated_bytes":estimate.estimated_bytes,"resident_bytes":estimate.resident_bytes,"model_metadata":{"version":1,"local_bounds":[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z],"file_length":64,"json_bytes":4,"json_sha256":source_sha},"direct_template_reuse":{"version":Footprint.DIRECT_TEMPLATE_REUSE_VERSION,"safe":reuse.get("safe",false)}})
	var body:=JSON.stringify(descriptor)
	check(write_json(Footprint.descriptor_path(source,directory),{"version":Footprint.VERSION,"body":body,"sha256":body.sha256_text()}),"publish "+kind+" native footprint")
	var metadata:=Native.read(source,directory)
	check(metadata.get("known",false) and not FileAccess.file_exists(source),"native "+kind+" metadata loads without a GLB source")
	check(metadata.get("native_candidate",{}).get("direct_template_reuse_safe",false)==(kind in ["safe","bridge"]),kind+" published classification selects only immutable shared resources")
	return {"path":source,"metadata":metadata,"budget":estimate.estimated_bytes}
func execute(row:Dictionary,job:RefCounted)->Dictionary:
	job.require_native_products=true;job.prepare_static_scenes=true
	job.static_scene_paths={row.path:row.metadata}
	var thread:=Thread.new();var began:=Time.get_ticks_usec()
	check(thread.start(job.run.bind([row.path,row.path],Callable(),2,Callable(),directory))==OK,"initial native coordinator starts")
	while thread.is_alive():
		# Same main-thread services as entry loading; never join a live GPU worker.
		preload("res://scripts/world3d/mesh_readback_batch.gd").pump(8000)
		Pump.pump(1000)
		await process_frame
	var result:Dictionary=thread.wait_to_finish();Drainer.synchronize_transfer()
	if not result.has("admission_profile"):
		check(false,"native fixture reached admitted work: "+JSON.stringify(result));return result
	measurements.append({"wall_us":Time.get_ticks_usec()-began,"error":result.error,"cancelled":result.cancelled,"entry":result.entries[0].get("private_preparation",{}).get("capture",{}),"admission":result.admission_profile})
	check(result.threads_started==1 and result.threads_joined==1 and result.unique_count==1,"one model ID reads and prepares once despite duplicate consumers")
	check(result.inflight_jobs_at_return==0 and result.inflight_reserved_at_return==0 and result.result_resident_estimate_bytes==row.budget,"private CPU and faces retain the existing full native reservation")
	return result
func meshes(scene:Node)->Array:return preload("res://scripts/world3d/surface_materials.gd").meshes(scene)
func drain(result:Dictionary)->void:
	# The coordinator owns an array of packets; Drainer deliberately recurses
	# only packet ownership fields, never arbitrary author/index arrays.
	for entry:Dictionary in result.get("entries",[]):Drainer.dispose_result(entry)
	Drainer.dispose_result(result)
func consume(row:Dictionary,result:Dictionary)->void:
	var entry:Dictionary=result.entries[0];var private:Dictionary=entry.get("private_preparation",{})
	var scene:Node=private.get("scene");var packed:PackedScene=entry.packed
	check(scene!=null and private.get("capture",{}).get("captured_meshes",0)==64,"initial native worker captures each unique mesh before main publication")
	if scene==null:drain(result);return
	check(scene.get_parent()==null and not scene.is_inside_tree() and scene.get_meta("_compiled_resource_owner")==packed,"one detached scene keeps the exact admitted native owner")
	var original:Mesh=meshes(scene)[0].mesh
	var owner:Mesh=original.get_meta("ground_cpu_cache")
	check(owner!=null and owner._collision_faces.size()==3,"private geometry includes exact prepared collision faces")
	check(int(private.get("thread_id",0))!=OS.get_main_thread_id() and int(private.get("thread_id",0))>0,"actual native CPU preparation runs on a worker")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader)
	var handed:Node=loader.call("_initial_native_scene",entry) if loader.has_method("_initial_native_scene") else null
	check(handed==scene and packed.get_meta("compiled_grass_rebound",false),"entry publication accepts this private scene and performs its one material handoff")
	var doc:=preload("res://scripts/world3d/world_document.gd").new();doc.load_immutable_records=true
	var record:={"kind":"asset","uuid":"first","asset_path":row.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"walk"}
	var first:Node3D=await loader._prepare_asset_instance(doc,record,{"scene":scene})
	private.erase("scene")
	check(first.get_child(0)==scene and meshes(first)[0].mesh==original,"first actual entry cursor consumes the prepared scene without instantiating again")
	var main_capture:=CpuPreparation.capture(first,true)
	check(main_capture.renderer_surfaces==0 and meshes(first)[0].mesh.get_meta("ground_cpu_cache")==owner,"main capture fallback reuses the worker arrays instead of reading the renderer")
	check(Assets.cache_packed(row.path,packed,entry.source_digest),"publish the same immutable PackedScene")
	record=record.duplicate(true);record.uuid="second"
	var second:Node3D=await loader._prepare_asset_instance(doc,record,{"template":packed})
	var second_capture:=CpuPreparation.capture(second,true)
	check(meshes(second)[0].mesh==original and meshes(second)[0].mesh.get_meta("ground_cpu_cache")==owner and second_capture.renderer_surfaces==0,"later instances preserve the same native and CPU owners")
	var scene_ref:WeakRef=weakref(scene);var packed_ref:WeakRef=weakref(packed);var cpu_ref:WeakRef=weakref(owner)
	Assets._scenes.erase(row.path)
	Drainer.dispose_scene(first);Drainer.dispose_scene(second)
	scene=null;first=null;second=null;original=null;owner=null;packed=null
	drain(result);entry.clear();private.clear();loader.free()
	check(scene_ref.get_ref()==null and packed_ref.get_ref()==null and cpu_ref.get_ref()==null,"consumed scene and native/CPU owners retire with the last consumer")
func rejected(row:Dictionary,job:RefCounted,label_:String)->void:
	var result:=await execute(row,job)
	var entry:Dictionary=result.entries[0];var private:Dictionary=entry.get("private_preparation",{})
	var scene:Node=private.get("scene");var packed_ref:WeakRef=weakref(entry.packed)
	check(result.error!=OK and scene!=null,label_+" keeps allocated private geometry until main drain")
	drain(result)
	check(not is_instance_valid(scene) and packed_ref.get_ref()==null and result.is_empty(),label_+" releases private graph and packet without leaked reservations")
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-root="):directory=arg.trim_prefix("--test-root=").replace("\\","/").simplify_path()
	if directory.is_empty() or not Paths.allowed(directory,"D:/code/rmmo_runtime/review_artifacts") or directory=="D:/code/rmmo_runtime/review_artifacts":quit(2);return
	DirAccess.make_dir_recursive_absolute(directory)
	if DisplayServer.get_name()=="headless":check(false,"test requires actual GPU resources and private desktop");quit(1);return
	Drainer.for_tree(self)
	Preparation.initial_native_cpu_preparation_enabled=true
	var safe:=product("safe")
	if safe.metadata.is_empty():quit(1);return
	var result:=await execute(safe,Preparation.new())
	check(result.error==OK,"real initial native read completes")
	await consume(safe,result)
	for kind:String in ["local","grass","script"]:
		var row:=product(kind);var excluded:=await execute(row,Preparation.new())
		check(excluded.error==OK and not excluded.entries[0].has("private_preparation"),kind+" stays on the established native route without speculative scene work")
		drain(excluded)
	await rejected(safe,CancelAfterNative.new(),"cancel after preparation")
	await rejected(safe,FailAfterNative.new(),"failure after preparation")
	check(not Pump.active() and preload("res://scripts/world3d/mesh_readback_batch.gd").snapshot().pending==0,"completed, cancelled and failed workers leave no pump or readback requests")
	write_json(directory.path_join("result.json"),{"checks":checks,"failed":failed,"measurements":measurements})
	print("INITIAL_NATIVE_CPU_PREPARATION_FINISHED checks=",checks," failures=",failed)
	quit(1 if failed else 0)
