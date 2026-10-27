extends "res://tools/test_isolated_map_retarget.gd"
## Isolated, CPU-only regression: exact decoded prefab content, unrelated text,
## selected sidecars, source immutability and persisted record closure.
const Builder=preload("res://tools/isolated_full_native_map_builder.gd")
const BoundsFixture=preload("res://tools/test_asset_bounds_manifest.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")

func run()->void:
	var base:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):base=arg.trim_prefix("--output=")
	if base.is_empty() or not Paths.allowed(base,"D:/code/rmmo_runtime/review_artifacts") or DirAccess.dir_exists_absolute(base):
		printerr("new external --output directory required");quit(2);return
	var original_root:=base.path_join("original");var target_root:=base.path_join("target")
	DirAccess.make_dir_recursive_absolute(original_root.path_join("assets"));DirAccess.make_dir_recursive_absolute(target_root)
	var texture:=original_root.path_join("assets/shared.png")
	var image:=Image.create(7,11,false,Image.FORMAT_RGBA8);image.fill(Color(.25,.5,.75));check(image.save_png(texture)==OK,"private source texture saved")
	put(texture+".flip.bc5.dds",bc5(7,11))
	var model_source:=original_root.path_join("assets/model.glb");var logical:=target_root.path_join("assets/model.glb")
	var helper:=BoundsFixture.new();helper.write(model_source,helper.data())
	var bounds:Dictionary=preload("res://scripts/world3d/asset_bounds_manifest.gd").read(model_source);var source_sha:=FileAccess.get_sha256(model_source);helper.free()
	var product_dir:=Compiled.directory(target_root);DirAccess.make_dir_recursive_absolute(product_dir)
	var payload:=PackedByteArray([1,2,3,4]);var payload_sha:=Store._sha(payload)
	var product:=product_dir.path_join(payload_sha+".scn");put(product,payload)
	var generator:=Compiled.generator();var index:={"version":Compiled.VERSION,"source_sha":source_sha,"payload_sha":payload_sha,"generator":generator,"bytes":payload.size()}
	put(Compiled.index_path(logical,target_root),JSON.stringify(index).to_utf8_buffer())
	var stats:=Footprint.empty_stats();stats.nodes=2;stats.native_uncompressed_bytes=4096
	var budget:=Footprint.estimate_stats(stats);var box:AABB=bounds.local_bounds
	var metadata:={"version":1,"local_bounds":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z],"json_sha256":bounds.json_sha256,"file_length":bounds.file_length,"json_bytes":bounds.json_bytes}
	var descriptor:={"version":Footprint.VERSION,"footprint_generator":Footprint.generator(),"source_path":logical,"source_sha":source_sha,"payload_sha":payload_sha,"generator":generator,"bytes":payload.size(),"source_bytes":bounds.file_length,"stats":stats,"estimated_bytes":budget.estimated_bytes,"resident_bytes":budget.resident_bytes,"model_metadata":metadata}
	check(Footprint._publish(descriptor,Footprint.descriptor_path(logical,target_root),target_root)==OK,"private full product and bounds descriptor staged")
	var record:=make_record(texture);var second:Dictionary=record.duplicate(true);second.uuid="fixture_wall_2";second.position=[8.,2.,0.]
	var model:={"uuid":"model_1","kind":"asset","asset_path":model_source,"surface_id":"block","collision":"block","position":[1,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var model2:Dictionary=model.duplicate(true);model2.uuid="model_2";model2.position=[9,0,0]
	var source_map:=original_root.path_join("map.gltf");var source_records:=[record,second,model,model2]
	check(write_map(source_map,original_root,source_records).get("ok",false),"private original map written")
	var source_doc:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_map))
	source_doc.nodes[0].extras.editor_bookmark={"precise":-57.999996185302734}
	put(source_map,JSON.stringify(source_doc,"",false,true).to_utf8_buffer())
	check(Builder._replace_member("{\"r\":[1],\"r\":[2]}","r",[1],[3]).is_empty(),"duplicate JSON members are refused")
	var original_sha:=FileAccess.get_sha256(source_map);var texture_sha:=FileAccess.get_sha256(texture)
	var source_roundtrip:=read_map(source_map,original_root)
	var audit_path:=base.path_join("audit.json")
	var model_audit:Dictionary={};model_audit[model_source]=source_sha
	put(audit_path,JSON.stringify({"map":source_map,"current_map_sha256":original_sha,"source_record_count":4,"fixture_native_model_identity":model_audit}).to_utf8_buffer())
	var result:Dictionary=Builder.build(source_map,original_root,target_root,audit_path)
	check(result.get("ok",false),"full-material map relocation succeeds")
	if result.get("ok",false):
		check(result.get("scope")=="full_native_model_materials" and result.get("relocation_semantics_verified",false) and result.record_count==4 and result.relocation_semantics_scope.map_metadata_except_reference_closure_equal,"manifest reports full scope and every reopened record")
		check(result.models.size()==1 and result.resource_count==2 and result.models[0].logical_source==logical and result.models[0].payload_sha256==payload_sha and not FileAccess.file_exists(logical),"shared prefab and absent-GLB native model each deduplicate")
		var copied:=target_root.path_join("assets/shared.png")
		check(FileAccess.get_sha256(copied)==texture_sha and FileAccess.get_sha256(copied+".flip.bc5.dds")==FileAccess.get_sha256(texture+".flip.bc5.dds"),"original texture and selected sidecar copied byte-for-byte")
		var reopened:=read_map(result.target_map,target_root)
		check(reopened.get("ok",false) and reopened.records.size()==4,"target map reopens persisted reference closure")
		if reopened.get("ok",false):
			var moved:Dictionary=reopened.records[0]
			check(moved.provenance_note==texture and moved.prefab_materials[0].texture_path==copied,"only schema texture path changes; equal provenance string remains")
			var left:=Builder._record_semantics(source_roundtrip.records[0],original_root);var right:=Builder._record_semantics(moved,target_root)
			check(left.ok and right.ok and left.value==right.value,"decoded prefab geometry and every material value compare after relocation")
			var altered:Dictionary=moved.duplicate(true);altered.prefab_materials[0].roughness=.3
			check(Builder._record_semantics(altered,target_root).value!=left.value,"semantic comparator rejects material parameter changes")
	check(FileAccess.get_sha256(source_map)==original_sha and FileAccess.get_sha256(texture)==texture_sha,"source map and texture unchanged")
	check(not Builder.build(source_map,original_root,target_root,audit_path).get("ok",false),"builder rejects overwriting an existing fixture")
	print("ISOLATED_FULL_NATIVE_MAP checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
