extends "res://tools/test_deferred_asset_scene.gd"
## Private GPU fixture for measuring an older published product without rebuild.
func run()->void:
	var folder:=Paths.external_root().path_join("review_artifacts/published_native_migration_fixture_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var manager:=root.get_node("AssetManager");var old_root:String=manager.content_root_override
	manager.content_root_override=folder
	var compiler:=preload("res://scripts/world3d/compiled_asset_cache.gd")
	var footprint:=preload("res://scripts/world3d/compiled_asset_footprint.gd")
	var source:=folder.path_join("model.glb");static_fixture(source,Color(.2,.6,.3,1))
	check(compiler.build(source).get("ok",false),"fixture creates a real native product through explicit conversion")
	var index:=compiler.index_path(source)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(index))
	# Synthetic historical producer identity: only the fixture index changes,
	# never an actual asset or a claimed producer/visual compatibility report.
	manifest.generator="1".repeat(64)
	var file:=FileAccess.open(index,FileAccess.WRITE);file.store_string(JSON.stringify(manifest));file.close()
	var product:=compiler.directory().path_join(str(manifest.payload_sha)+".scn")
	var index_sha:=FileAccess.get_sha256(index);var product_sha:=FileAccess.get_sha256(product)
	var source_sha:=FileAccess.get_sha256(source)
	var product_count:=Array(DirAccess.get_files_at(compiler.directory())).filter(func(name):return name.ends_with(".scn")).size()
	check(not footprint.build(source,folder).get("ok",false),"ordinary conversion accounting still requires its current producer")
	var measured:=footprint.build(source,folder,true)
	check(measured.get("ok",false) and measured.get("candidate",{}).get("generator")==manifest.generator,"explicit migration measures an older native product without changing its identity")
	check(FileAccess.get_sha256(index)==index_sha and FileAccess.get_sha256(product)==product_sha and FileAccess.get_sha256(source)==source_sha,"migration preserves original index, SCN and GLB bytes")
	check(Array(DirAccess.get_files_at(compiler.directory())).filter(func(name):return name.ends_with(".scn")).size()==product_count,"migration does not generate another SCN")
	var native:=preload("res://scripts/world3d/native_model_product.gd").read(source,folder)
	check(not native.is_empty() and native.get("native_payload_sha")==product_sha,"measured historical product has complete consumer bounds and budget")
	var building:=footprint.ensure_imported_building(source,folder)
	check(building.get("ok",false) and not building.get("present",true) and building.get("reused",false),"non-building component contract is persisted and reused")
	var policy:=preload("res://scripts/world3d/runtime_package_policy.gd")
	var old_policy:bool=policy.verify_packages;policy.verify_packages=true
	check(DirAccess.rename_absolute(source,source+".held")==OK,"move GLB outside its logical model key")
	var worker:=Thread.new()
	var started:=worker.start(Deferred.prepare_scene.bind(source,source_sha,null,native,true,folder,false,Deferred.CollisionGeometry.ALL,false,false,true))
	check(started==OK,"strict native-only deferred worker starts")
	if started==OK:
		while worker.is_alive():await process_frame
		var prepared:Dictionary=worker.wait_to_finish()
		check(prepared.get("error","missing").is_empty() and prepared.get("scene") is Node3D and prepared.get("source_digest")==source_sha,"strict deferred preparation uses published native geometry without reading GLB")
		Drainer.dispose_result(prepared)
	worker=Thread.new()
	started=worker.start(Deferred._prepare_fixed_scene.bind(source,source_sha,null,native,true,folder,native.get("native_candidate",{}),Deferred.CollisionGeometry.ALL,true))
	check(started==OK,"strict fixed-candidate worker starts with nonempty native metadata")
	if started==OK:
		while worker.is_alive():await process_frame
		var prepared:Dictionary=worker.wait_to_finish()
		check(prepared.get("error","missing").is_empty() and prepared.get("scene") is Node3D,"private instantiation callback does not recheck the missing GLB")
		Drainer.dispose_result(prepared)
	check(DirAccess.rename_absolute(source+".held",source)==OK,"restore test-only authoring source for explicit reimport rejection")
	policy.verify_packages=old_policy
	var native_descriptor_sha:=FileAccess.get_sha256(footprint.descriptor_path(source,folder))
	static_fixture(source,Color.RED)
	var changed:=footprint.build(source,folder,true)
	check(not changed.get("ok",true) and changed.get("reason")=="reimport_required","source changes require explicit reimport instead of relabelling the old native")
	check(FileAccess.get_sha256(index)==index_sha and FileAccess.get_sha256(footprint.descriptor_path(source,folder))==native_descriptor_sha,"failed preserve migration does not replace accepted metadata")
	manager.content_root_override=old_root
	print("PUBLISHED_NATIVE_MIGRATION failures=",failures," root=",folder)
	quit(1 if failures else 0)
