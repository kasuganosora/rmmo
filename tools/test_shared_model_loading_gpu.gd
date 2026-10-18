extends "res://tools/test_deferred_asset_scene.gd"
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=60;Compiled.enabled=false
	var folder:=Paths.cache_directory("shared_model_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("source.glb");static_fixture(path,Color.WHITE)
	var published:=folder.path_join(FileAccess.get_sha256(path)+".glb");DirAccess.rename_absolute(path,published);path=published
	Trace.minimum_event_us=0;Trace.start()
	var first:Node3D=Library.instantiate(path);check(first!=null,"shared model imports")
	if first==null:quit(1);return
	var mesh:Mesh=first.find_child("Plain",true,false).mesh
	var independent:=true;var shared:=true
	for i in 100:
		var instance:Node3D=Library.instantiate(path)
		independent=independent and instance!=first
		shared=shared and instance.find_child("Plain",true,false).mesh==mesh
		instance.position.x=i+1
		Drainer.dispose_scene(instance)
	check(independent and first.position==Vector3.ZERO,"101 placements retain independent instances and poses")
	check(shared,"101 placements share the same immutable mesh resource")
	var trace:=Trace.stop()
	check(trace.events.filter(func(e):return e.label=="asset_library.raw_load").size()==1,"101 shared placements parse and generate their source exactly once")
	var cpu:=preload("res://scripts/world3d/ground_cpu_mesh.gd").new()
	cpu.surfaces=[mesh.surface_get_arrays(0)];cpu.materials.assign([null]);cpu.bounds=mesh.get_aabb()
	Trace.start();var gpu:Mesh=cpu.restore();var shared_gpu:=true
	for i in 100:shared_gpu=shared_gpu and cpu.restore()==gpu
	check(shared_gpu and Trace.stop().events.filter(func(e):return e.label=="mesh.gpu_restore").size()==1,"101 CPU-backed instances upload shared mesh buffers exactly once")
	gpu=null;cpu=null
	Drainer.dispose_scene(first);mesh=null
	Trace.start()
	var returned:Node3D=Library.instantiate(path);Drainer.dispose_scene(returned)
	check(Trace.stop().events.filter(func(e):return e.label=="asset_library.raw_load").is_empty(),"returning while a template is resident performs no new model parse")
	Library.evict_cached_scene(path)
	Trace.start();returned=Library.instantiate(path);Drainer.dispose_scene(returned)
	check(Trace.stop().events.filter(func(e):return e.label=="asset_library.raw_load").size()==1,"after explicit final-template eviction a return performs one new load")
	Library.evict_cached_scene(path);Drainer.synchronize_transfer()
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(folder)
	print("SHARED_MODEL_LOADING_GPU failures=",failures);quit(1 if failures else 0)
