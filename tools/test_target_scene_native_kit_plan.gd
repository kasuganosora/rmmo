extends "res://tools/test_native_kit_consumer_preparation.gd"
const Target=preload("res://scripts/world3d/target_scene_prefetch.gd")

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	var top:=fixture("target_kit_top",true);var edge:=fixture("target_kit_edge",true)
	delete_authoring_source(top);delete_authoring_source(edge)
	var document:=kit_document(top.path,edge.path)
	var map_path:=content_root.path_join("target_map.gltf");write(map_path,"{}")
	var plan:Dictionary=Target.plan(document.records,content_root,map_path,FileAccess.get_sha256(map_path),{})
	check(not plan.is_empty(),"kit target plan remains admissible")
	var expected:Array[String]=[]
	for model:Dictionary in [top,edge]:
		var candidate:=Assets.native_candidate(model.path,content_root)
		for path:String in [Compiled.index_path(model.path,content_root),Footprint.descriptor_path(model.path,content_root),candidate.product]:
			expected.append(path)
			check(plan.get("files",{}).has(path),"target records kit identity "+path.get_file())
	check(plan.get("estimated_bytes",0)==Target.LEASE_BYTES,"kit textures participate in existing strict native budget policy")
	var descriptor:=Footprint.descriptor_path(edge.path,content_root)
	var original:=FileAccess.get_file_as_string(descriptor);write(descriptor,original+" ")
	check(not Target.verify(plan.get("files",{}),content_root),"changed kit descriptor invalidates the parked target plan")
	write(descriptor,original)
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify({"checks":checks,"failures":failures,"plan":plan,"expected_native_files":expected,"scope":"CPU metadata and source invalidation; no renderer"},"\t"))
	print("TARGET_NATIVE_KIT_PLAN checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
