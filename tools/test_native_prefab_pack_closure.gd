extends "res://tools/test_editor_native_asset_requests.gd"
## Metadata/packaging contract only. Synthetic native geometry is serialized by
## the shared fixture; this test never starts pixel workers or renders a model.

func run()->void:
	content_root=Binding.Paths.external_root()
	if not content_root.replace("\\","/").contains("/review_artifacts/"):quit(2);return
	var model:=fixture("prefab_pack_closure",false)
	check(not FileAccess.file_exists(model.path),"native prefab fixture has no authoring GLB")
	check(Assets.native_available(model.path),"original native registration is available")
	var library=Assets.new(content_root.path_join("packs/destination/assets"))
	var document=Doc.new()
	document.add_asset({"asset_path":model.path,"bounds_size":[1,1,1]},Vector3.ZERO)
	var before:Array=document.records.duplicate(true)
	var saved:=Prefabs.capture(document.records,library,"Native pack closure")
	check(saved.get("ok",false) and document.records==before,"capture succeeds without GLB and preserves source records")
	if not saved.get("ok",false):printerr(saved);quit(2);return
	var loaded:=Prefabs.read(saved.entry)
	check(loaded.get("ok",false),"captured prefab initially reads with the source registration")
	if not loaded.get("ok",false):printerr(loaded);quit(2);return
	var captured_path:String=loaded.records[0].asset_path
	check(captured_path.begins_with(library.directory+"/"),"captured native dependency belongs to the destination pack")
	var index:=Compiled.index_path(model.path,content_root)
	var parked:=index+".held-by-pack-closure-test"
	assert(index.begins_with(content_root+"/") and parked.begins_with(content_root+"/"))
	check(DirAccess.rename_absolute(index,parked)==OK,"remove only this fixture's original logical registration")
	check(not Assets.native_available(model.path),"original logical registration is now absent")
	var independent:=Prefabs.read(saved.entry)
	check(independent.get("ok",false),"captured pack remains usable without the original logical registration")
	check(DirAccess.rename_absolute(parked,index)==OK,"restore original registration for the control case")
	check(Prefabs.read(saved.entry).get("ok",false),"restoring the original registration restores captured prefab access")
	var captured_candidate:=Assets.native_candidate(captured_path,content_root)
	var original_candidate:=Assets.native_candidate(model.path,content_root)
	check(captured_candidate.product==original_candidate.product and captured_candidate.payload_sha==original_candidate.payload_sha and captured_candidate.source_sha==original_candidate.source_sha,"pack registration shares exact native payload and source identity")
	check(not FileAccess.file_exists(captured_path),"packaged logical model needs no copied authoring GLB")
	var alias_index:=Compiled.index_path(captured_path,content_root)
	var alias_before:=FileAccess.get_file_as_bytes(alias_index)
	var shared:Dictionary={}
	var dependency=preload("res://scripts/world_editor/native_prefab_dependencies.gd")
	check(dependency.capture(model.path,library.directory,shared).path==captured_path and dependency.capture(model.path,library.directory,shared).path==captured_path and shared.size()==1,"one capture context processes a repeated model only once")
	var descriptor_path:=Footprint.descriptor_path(model.path,content_root)
	var original_descriptor:=FileAccess.get_file_as_bytes(descriptor_path)
	var outer:Dictionary=JSON.parse_string(original_descriptor.get_string_from_utf8());var body:Dictionary=JSON.parse_string(outer.body)
	body.estimated_bytes+=1024;body.resident_bytes=body.estimated_bytes
	outer.body=JSON.stringify(body);outer.sha256=str(outer.body).sha256_text();write(descriptor_path,JSON.stringify(outer))
	var revised:Dictionary=dependency.capture(model.path,library.directory,{})
	check(revised.ok and revised.path!=captured_path,"changed footprint budget gets a separate immutable registration")
	check(FileAccess.get_file_as_bytes(alias_index)==alias_before,"new snapshot never overwrites old registration")
	var restore:=FileAccess.open(descriptor_path,FileAccess.WRITE);restore.store_buffer(original_descriptor);restore.close()
	var building_path:=Footprint.building_descriptor_path(model.path,content_root)
	var building:={"version":1,"source_sha":original_candidate.source_sha,"payload_sha":original_candidate.payload_sha,"present":false}
	write(building_path,dependency._envelope(building))
	var with_building:Dictionary=dependency.capture(model.path,library.directory,{})
	check(with_building.ok and with_building.path!=captured_path,"published building-contract presence participates in immutable snapshot identity")
	var copied_building:=Footprint._building_metadata(with_building.path,content_root,Assets.native_candidate(with_building.path,content_root))
	check(copied_building==JSON.parse_string(JSON.stringify(building)),"pack registration preserves the exact valid building contract")
	DirAccess.remove_absolute(building_path)
	check(not Footprint._building_metadata(with_building.path,content_root,Assets.native_candidate(with_building.path,content_root)).is_empty(),"pack building contract is independent of original descriptor")
	var moved:=content_root.path_join("packs/moved/assets")
	DirAccess.make_dir_recursive_absolute(moved.get_base_dir())
	check(DirAccess.rename_absolute(library.directory,moved)==OK,"move the complete resource library within the same content root")
	var moved_library=Assets.new(moved);var moved_entry:Dictionary=moved_library.entries[0]
	var relocated:=Prefabs.read(moved_entry)
	check(relocated.ok and str(relocated.records[0].asset_path).begins_with(moved+"/"),"moved prefab resolves its own relative native registration")
	check(DirAccess.rename_absolute(index,parked)==OK,"remove original registration again after pack move")
	check(Prefabs.read(moved_entry).ok,"moved pack remains independent of original logical registration")
	var moved_path:String=relocated.records[0].asset_path
	check(Assets.native_candidate(moved_path,content_root).product==original_candidate.product,"move does not copy or change root-shared native payload")
	var missing:=Compiled.index_path(moved_path,content_root);var held:=missing+".held"
	check(DirAccess.rename_absolute(missing,held)==OK,"withhold actual packaged native dependency")
	var destination=Doc.new();var before_history:int=destination._undo.size()
	check(not Prefabs.place(destination,moved_entry,Vector3.ZERO).ok and destination.records.is_empty() and destination._undo.size()==before_history,"missing native dependency fails before document or undo mutation")
	check(DirAccess.rename_absolute(held,missing)==OK and DirAccess.rename_absolute(parked,index)==OK,"restore only this test's withheld registrations")
	check(document.records==before,"registration probes do not change authored records")
	var report:={"checks":checks,"failures":failures,"source_path":model.path,"captured_path":captured_path,"destination":library.directory,"independent_read":independent,"scope":"native metadata and prefab pack dependency, no GPU or performance claim"}
	write(content_root.get_base_dir().path_join("observations.json"),JSON.stringify(report,"\t"))
	print("NATIVE_PREFAB_PACK_CLOSURE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
