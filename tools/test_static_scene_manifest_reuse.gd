extends "res://tools/test_asset_bounds_manifest.gd"
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
func snapshot(scene:Node)->Array:
	var result:Array=[];var stack:Array=[scene]
	while not stack.is_empty():
		var node:Node=stack.pop_front();stack.append_array(node.get_children())
		var row:Array=[node.get_class()]
		if node is Node3D:row.append(node.transform)
		if node is MeshInstance3D:
			for slot:int in node.mesh.get_surface_count():row.append(var_to_bytes(node.mesh.surface_get_arrays(slot)))
		result.append(row)
	return result
func run()->void:
	var directory:=Paths.cache_directory("static_manifest_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("model.glb");write(path,data())
	var manifest:=Manifest.read(path);check(manifest.known,"temporary model has a package static observation")
	var api:=Preparation.new();var method:Dictionary={}
	for entry:Dictionary in api.get_method_list():
		if entry.name=="_parse_verified_fallback":method=entry
	var expected:Array=[];var trials:Array=[]
	for variant:int in [0,1,2,3]:
		Policy.verify_packages=variant==2
		var hints:Dictionary={}
		if variant!=0:hints[path]=manifest if variant!=3 else {"known":false}
		var args:Array=[path,Paths.external_root(),{},true]
		if method.args.size()==5:args.append(hints)
		Trace.minimum_event_us=0;Trace.start();var began:=Time.get_ticks_usec()
		var packet:Dictionary=api.callv("_parse_verified_fallback",args);var elapsed:=Time.get_ticks_usec()-began;var trace:=Trace.stop()
		check(packet.error==OK and packet.get("scene") is Node,"static scene route completes")
		if packet.error!=OK or not packet.get("scene") is Node:continue
		var actual:=snapshot(packet.scene)
		if expected.is_empty():expected=actual
		check(actual==expected,"same transforms and exact GPU surface arrays")
		var reads:=0
		for event:Dictionary in trace.events:
			if event.label=="model.bounds_manifest":reads+=1
		check(reads==(0 if variant==1 else 1),"only the current trusted static observation avoids a second manifest scan")
		trials.append({"variant":variant,"manifest_reads":reads,"us":elapsed,"reused":packet.get("static_manifest_reused",false)})
		packet.scene.free();packet.clear()
	Policy.verify_packages=false;DirAccess.remove_absolute(path);DirAccess.remove_absolute(directory)
	print("STATIC_SCENE_MANIFEST_REUSE ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
