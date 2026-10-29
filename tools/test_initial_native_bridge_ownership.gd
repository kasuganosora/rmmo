extends "res://tools/test_initial_native_cpu_preparation.gd"
## Actual procedural bridge record through MapLoader._build_records. Stop only
## after its real bridge mesh, instance cursor and CPU capture have completed.
const Bridge=preload("res://scripts/world3d/bridge_mesh.gd")
class BridgeLoader extends "res://scripts/world3d/map_loader.gd":
	var observed_bridge:=false
	func _prepare_static_asset_specs(_root:Node3D,instance:Node,parts:Array,_library:Array)->bool:
		observed_bridge=parts.size()==1 and parts[0].name=="StoneBridge" and parts[0].mesh.get_surface_count()==3 and not instance.has_meta("paint_error")
		return false # Exercise normal retirement after the actual asset branch.

func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-root="):directory=arg.trim_prefix("--test-root=").replace("\\","/").simplify_path()
	if directory.is_empty() or not Paths.allowed(directory,"D:/code/rmmo_runtime/review_artifacts") or directory=="D:/code/rmmo_runtime/review_artifacts":quit(2);return
	DirAccess.make_dir_recursive_absolute(directory)
	ProjectSettings.set_setting("rmmo/content_root",directory)
	Drainer.for_tree(self)
	check(not Preparation.initial_native_cpu_preparation_enabled,"native CPU experiment is disabled by default")
	Preparation.initial_native_cpu_preparation_enabled=true
	var fixture:=product("bridge")
	if fixture.metadata.is_empty():quit(1);return
	var result:=await execute(fixture,Preparation.new())
	check(result.get("error",FAILED)==OK,"real bridge kit native product prepares successfully")
	var entry:Dictionary=result.entries[0]
	var scene:Node=entry.get("private_preparation",{}).get("scene")
	check(scene!=null and scene.get_parent()==null,"bridge candidate owns the speculative detached scene")
	if scene==null:drain(result);quit(1);return
	var scene_ref:WeakRef=weakref(scene);var packed_ref:WeakRef=weakref(entry.packed)
	var materials:Dictionary={}
	for role:String in ["deck","masonry","trim"]:materials[role]={"name":"fixture_"+role,"color":[.8,.8,.8,1.],"roughness":.8,"texture_path":"","tile_size":[2,2]}
	var record:={"kind":"asset","uuid":"procedural_bridge","asset_path":fixture.path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"walk","bridge_mesh":{"version":1,"prefab_id":"native_fixture","length":8.,"width":4.,"depth":1.5,"camber":0.,"arches":1,"recipe":{"style":"segmental","max_span":10.,"rail_height":1.05,"pier_width":1.3}},"bridge_materials":materials}
	check(preload("res://scripts/world3d/bridge_data.gd").valid(record),"actual procedural bridge recipe is valid")
	var loader:=BridgeLoader.new();root.add_child(loader)
	loader.near_first=false;loader._building=true
	loader._model_preparation.require_native_products=true
	loader._record_meta={"rmmo_records":[record]};loader._record_order={record.uuid:0}
	loader._model_signatures={fixture.path:entry.source_digest};loader._asset_states={fixture.path:entry}
	await loader._build_records()
	check(loader.observed_bridge,"real bridge branch built its three-surface mesh and completed normal instance preparation")
	check(scene_ref.get_ref()==null,"MapLoader disposes the private scene ignored by the procedural bridge branch")
	# Keep a failed red run clean without letting this harness hide the assertion.
	if is_instance_valid(scene):Drainer.dispose_scene(scene)
	await process_frame
	check(not is_instance_valid(loader),"normal loader retirement completed")
	drain(result);entry.clear();scene=null
	Assets._scenes.erase(fixture.path);Bridge.kits.erase(fixture.path);Bridge.meshes.clear()
	Drainer.synchronize_transfer()
	check(packed_ref.get_ref()==null,"bridge kit and speculative scene release the native owner after cache retirement")
	write_json(directory.path_join("result.json"),{"checks":checks,"failed":failed})
	print("INITIAL_NATIVE_BRIDGE_FINISHED checks=",checks," failures=",failed)
	quit(1 if failed else 0)
