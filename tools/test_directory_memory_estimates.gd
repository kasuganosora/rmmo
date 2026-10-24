extends "res://tools/test_map_dependency_index.gd"
const Memory=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
func run()->void:
	content_root=Paths.external_root();folder=Paths.cache_directory("directory_memory_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var model_fixture:=ModelFixture.new();var model_path:=folder.path_join("model.glb")
	model_fixture.write(model_path,model_fixture.data());created.append(model_path)
	var records:Array=[]
	for i:int in 120:
		var asset:=box("model_%d"%i,100.+i*12.);asset.kind="asset";asset.asset_path=model_path;asset.size=[1,1,1];records.append(asset)
	var source:=fixture("map",records);var built:=Index.build(source.path,content_root,records)
	check(built.ok and built.models.size()==1,"shared model instances retain one directory observation")
	var expected:=Memory.estimate(model_path);var reopened:=Index.read(source.path,content_root)
	check(built.models[model_path].get("memory")==expected,"directory persists one unchanged full estimate per model")
	check(reopened.ok and reopened.models==built.models,"source-bound scheduling estimates survive directory save/reopen")
	var api:=Memory.new();var trials:Array=[]
	for cached:bool in [false,true]:
		var began:=Time.get_ticks_usec();var actual:Dictionary;var identical:=true
		for i:int in 100:
			actual=api.call("from_manifest",model_path,reopened.models[model_path]) if cached and api.has_method("from_manifest") else Memory.estimate(model_path)
			identical=identical and actual==expected
		trials.append({"cached":cached,"us":Time.get_ticks_usec()-began})
		check(identical,"same conservative memory accounting for every repeated instance")
	if api.has_method("from_manifest"):
		var missing:=folder.path_join("not_read.glb")
		check(api.call("from_manifest",missing,reopened.models[model_path])==expected,"trusted directory budget does not reopen GLB")
		Policy.verify_packages=true
		check(api.call("from_manifest",missing,reopened.models[model_path]).reason=="missing","diagnostic mode still observes current source bytes")
		Policy.verify_packages=false
		check(api.call("from_manifest",model_path,{})==expected,"missing budget uses original bounded estimator")
		check(api.call("from_manifest",model_path,{"memory":{"estimated_bytes":0}})==expected,"malformed estimate cannot undercharge work")
	model_fixture.free()
	for path:String in created:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(folder)
	print("DIRECTORY_MEMORY_ESTIMATES ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
