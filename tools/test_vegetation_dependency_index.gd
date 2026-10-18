extends "res://tools/test_asset_bounds_manifest.gd"
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
func run()->void:
	var directory:=Paths.cache_directory("vegetation_index_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("plant.glb");write(path,data())
	var record:Dictionary={"uuid":"plant","kind":"asset","asset_path":path,"surface_id":"model","collision":"none","position":[100,0,0],"rotation":[0,20,0],"size":[1,1,1]}
	var original:Dictionary=Index._classify(record,Paths.external_root(),{})
	check(original.bounds_known and original.classification=="spatial","verified ordinary static source has spatial accessor bounds")
	record.vegetation_batch=true
	var batched:Dictionary=Index._classify(record,Paths.external_root(),{})
	check(batched.bounds_known and batched.classification=="spatial" and batched.bounds==original.bounds,"render batching flag preserves exact model bounds instead of forcing global residency")
	record.vegetation_batch=false
	check(Index._classify(record,Paths.external_root(),{}).bounds==original.bounds,"disabled batching preserves ordinary geometry bounds")
	for invalid:Variant in [1,"yes",{},[]]:
		record.vegetation_batch=invalid
		check(not Index._classify(record,Paths.external_root(),{}).bounds_known,"malformed batching flag remains conservative: "+type_string(typeof(invalid)))
	record.vegetation_batch=true;record.future_geometry={"sweep":400}
	check(not Index._classify(record,Paths.external_root(),{}).bounds_known,"unknown geometry is not admitted by the render-only flag")
	record.erase("future_geometry");record.model_component_states={"door":.7}
	check(not Index._classify(record,Paths.external_root(),{}).bounds_known,"unproven legacy hinge-state bounds retain conservative fallback")
	record.erase("model_component_states")
	var animated:=data();animated.animations=[{}];write(path,animated)
	check(not Index._classify(record,Paths.external_root(),{}).bounds_known,"animated model source is not made spatial by vegetation batching")
	print("VEGETATION_DEPENDENCY_INDEX checks=",passed+failures," failures=",failures);quit(1 if failures else 0)
