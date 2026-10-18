extends SceneTree
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func run()->void:
	var files:=preload("res://tools/test_map_dependency_index.gd").new()
	files.content_root=Paths.external_root();files.folder=Paths.cache_directory("build_handoff_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var fixture=preload("res://tools/structure_dependency_fixture.gd")
	var records:Array=fixture.records(files.content_root)
	var source:Dictionary=files.fixture("map",records,fixture.metadata(records))
	var original:=var_to_bytes(records)
	var direct:=Index.build_for_loading(source.path,files.content_root,records)
	check(direct.ok and direct.proof is Proof,"build factory issues a typed proof")
	if direct.ok:
		var persisted:=Index.read_for_loading(source.path,files.content_root)
		check(persisted.ok and direct.index==persisted.index,"direct and persisted directories have identical rows, bounds, groups and metadata")
		check(Index.validate_index_ownership(direct.index,files.content_root,direct.proof,source.path),"direct proof authenticates its exact private directory")
		check(not Index.validate_index_ownership(direct.index.duplicate(),files.content_root,direct.proof,source.path),"copied directory cannot borrow proof")
		check(var_to_bytes(records)==original and not records.is_read_only() and not records[0].is_read_only(),"build neither mutates nor freezes caller records")
		records[2].fixture.open=.5;records[2].position[0]+=10
		check(direct.index.extras.rmmo_records[2].rmmo_state.fixture.open==0 and direct.index.extras.rmmo_records[2].position[0]!=records[2].position[0],"nested caller edits cannot alter sealed source snapshot")
		records=bytes_to_var(original)
		for clip:AABB in [AABB(Vector3(-2,-10,-2),Vector3(8,30,8)),AABB(Vector3(515,-10,-2),Vector3(20,30,8))]:
			check(Index.select(direct.index,[clip])==Index.select(persisted.index,[clip]),"same complete near/far namespace selection")
	var changed:Array=records.duplicate(true);changed[0].position[0]+=1
	check(not Index.build_for_loading(source.path,files.content_root,changed).ok,"changed pose rejected before proof")
	changed=records.duplicate(true);changed[0].collision="none"
	check(not Index.build_for_loading(source.path,files.content_root,changed).ok,"changed definition rejected before proof")
	check(not Index.build_for_loading(source.path,files.content_root,records,"0".repeat(64)).ok,"wrong source digest rejected")
	var ref:Dictionary=source.extras.rmmo_records[0].rmmo_ref
	var path:String=files.folder.path_join(ref.uri);var bytes:=FileAccess.get_file_as_bytes(path)
	files.write_bytes(path,"corrupt".to_utf8_buffer())
	check(not Index.build_for_loading(source.path,files.content_root,records).ok,"fresh complete dependency verification catches changed resource bytes")
	files.write_bytes(path,bytes)
	var mutable:=Index.build(source.path,files.content_root,records)
	check(mutable.ok and not mutable.is_read_only() and not mutable.rows.is_read_only(),"ordinary build remains mutable")
	var model_fixture:=preload("res://tools/test_asset_bounds_manifest.gd").new()
	var model_path:String=files.folder.path_join("source.glb")
	model_fixture.write(model_path,model_fixture.data());model_fixture.free();files.created.append(model_path)
	var model:Dictionary={"uuid":"near","kind":"asset","asset_path":model_path,"position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1]}
	var far:=model.duplicate(true);far.uuid="far";far.position[0]=500
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();loader._content_root=files.content_root;loader._entry_origin=Vector3.ZERO
	Index.classification_path_batching=false;var old_hints:Array=loader._cold_model_hints([model,far])
	Index.classification_path_batching=true
	check(old_hints==[model_path] and loader._cold_model_hints([model,far])==old_hints,"batched prefetch hints retain exact near model set across repeated instances")
	check(Index._classify(model,files.content_root,{}).classification=="spatial" and Index._classify(model,"C:/untrusted",{}).reason=="invalid_model_path","separate ordinary classifications cannot share default path observations across roots")
	far.asset_path=files.folder.path_join("missing.glb")
	check(loader._cold_model_hints([model,far]).is_empty(),"missing far manifest remains conservative")
	far.asset_path="C:/untrusted/model.glb"
	check(loader._cold_model_hints([model,far]).is_empty(),"out-of-root path cannot borrow another model's cached observation")
	loader.free()
	for created:String in files.created:
		if Paths.allowed(created,files.content_root) and FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(files.folder);files.free()
	print("DEPENDENCY_BUILD_HANDOFF passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
