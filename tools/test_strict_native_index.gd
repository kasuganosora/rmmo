extends "res://tools/test_collision_instance_preparation.gd"
## Isolated real native product; only setup touches GLB. Strict index consumers
## must preserve spatial classification and full admission after it is removed.
const NativeFixture=preload("res://tools/collision_native_fixture.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Cross=preload("res://scripts/world3d/cross_map_prefetch.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")

## This test-only publisher creates a real PackedScene with changed scene metadata,
## then measures its actual footprint against the same restored authoring bytes.
func republish_same_source(path:String,source:PackedByteArray,publication:Dictionary)->bool:
	if not NativeFixture.write_bytes(path,source):return false
	var candidate:Dictionary=publication.model.native_candidate
	var packed:=ResourceLoader.load(candidate.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed==null:return false
	var scene:=packed.instantiate()
	if scene==null:return false
	scene.set_meta("strict_index_test_revision",2)
	var changed:=PackedScene.new();var error:=changed.pack(scene);scene.free()
	if error!=OK:return false
	var temp:=folder.path_join("replacement.scn")
	if ResourceSaver.save(changed,temp)!=OK:return false
	var sha:=FileAccess.get_sha256(temp)
	if sha==publication.payload_sha:return false
	var file:=FileAccess.open(temp,FileAccess.READ)
	if file==null:return false
	var size:=file.get_length();file.close()
	if DirAccess.rename_absolute(temp,Compiled.directory(folder).path_join(sha+".scn"))!=OK:return false
	var index_path:=Compiled.index_path(path,folder)
	var index:Variant=JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not index is Dictionary:return false
	index.payload_sha=sha;index.bytes=size
	if not NativeFixture.write_bytes(index_path,JSON.stringify(index).to_utf8_buffer()):return false
	var measured:=Footprint.build(path,folder,true)
	return measured.get("ok",false) and DirAccess.remove_absolute(path)==OK
func run()->void:
	var errors:=Errors.new();OS.add_logger(errors)
	var manager:=root.get_node("AssetManager");var previous_root:String=manager.content_root_override
	var previous_policy:=Policy.verify_packages;Policy.verify_packages=true
	folder=Paths.external_root().path_join("review_artifacts/strict_native_index_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder);manager.content_root_override=folder
	var model:=folder.path_join("asset.glb");fixture(model)
	var regions:Array=[{"id":"inside","floor":0,"min":[0,0,0],"max":[10,10,10]}]
	var floor_part:Dictionary={"floor":0,"floor_y":0.0,"role":"floor","part":"floor"}
	var body_part:Dictionary={"floor":0,"floor_y":0.0,"role":"body","part":"body"}
	rewrite_nodes(model,func(data:Dictionary)->void:
		data.nodes[0].extras={"rmmo_model_components":{"version":1},"rmmo_building":{"version":1,"regions":regions}}
		data.nodes[1].extras.merge({"uuid":"floor_mesh","rmmo_part":floor_part})
		data.nodes[3].extras.merge({"uuid":"body_mesh","rmmo_part":body_part}))
	var source_bytes:=FileAccess.get_file_as_bytes(model)
	var publication:=NativeFixture.publish(model,folder)
	check(publication.get("ok",false),"real authoring import publishes native product")
	if not publication.get("ok",false):
		print("NATIVE_PUBLICATION_FAILURE ",publication);manager.content_root_override=previous_root;Policy.verify_packages=previous_policy;finish(errors);return
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[placed("one",model,[0,2,0],[0,0,0],[1,1,1],"none")]
	var building:Dictionary=preload("res://scripts/world3d/imported_building.gd").read_source_descriptor(model,publication.source_sha,folder)
	check(not building.is_empty(),"real native model publishes its building membership descriptor")
	records[0].model_building=building;records[0].model_building_states={}
	var map:=helper.fixture("map",records)
	var raw:=Index.build(map.path,folder,records)
	check(raw.get("ok",false) and raw.rows[0].get("bounds_known",false),"explicit offline raw index still accepts an existing authoring source")
	check(DirAccess.remove_absolute(model)==OK and not FileAccess.file_exists(model),"authoring GLB removed before runtime index")
	var opened:Variant=preload("res://scripts/world3d/world_document.gd").open_file(map.path)
	check(opened!=null and opened.records.size()==1 and opened.records[0].get("asset_path")==model,"strict editor document opens a native building without the authoring GLB")
	var draft_issue:String=preload("res://scripts/world_editor/draft_store.gd").validate_record(records[0],{"next":2},{})
	check(draft_issue.is_empty(),"draft validation accepts an in-root source-less native logical key")
	var escaped:Dictionary=records[0].duplicate(true);escaped.asset_path=folder.get_base_dir().path_join("outside.glb")
	check(not preload("res://scripts/world_editor/draft_store.gd").validate_record(escaped,{"next":2},{}).is_empty(),"draft validation rejects an outside logical model key")
	var fort:Dictionary={"kind":"box","fortification_art":{"version":1,"module":"wall","asset_path":model}}
	check(preload("res://scripts/world3d/fortification_data.gd").valid_record(fort),"fortification validates its source-less in-root logical native key")
	fort.fortification_art.asset_path=escaped.asset_path
	check(not preload("res://scripts/world3d/fortification_data.gd").valid_record(fort),"fortification rejects an outside logical native key")
	var built:=Index.build(map.path,folder,records,"",Store.READ_WORKERS,Index.Snapshot.RETAIN_LIMIT,false,{},{},true)
	check(built.get("ok",false) and built.get("rows",[]).size()==1 and built.rows[0].get("bounds_known",false) and built.get("models",{}).has(model),"strict native index build retains model bounds without GLB")
	var issued:=Index.read_for_loading(map.path,folder,"",Index.Snapshot.RETAIN_LIMIT,Index.MAX_BYTES,Store.READ_WORKERS,false,null,true)
	check(issued.get("ok",false) and issued.get("index",{}).get("rows",[]).size()==1 and issued.index.rows[0].get("bounds_known",false) and issued.index.get("models",{}).has(model),"strict native index read retains model bounds without GLB")
	check(issued.get("ok",false) and issued.index.rows[0].get("classification")=="group" and issued.index.groups.has("building:one"),"strict native index preserves the real model-building group and its bounds")
	var token:=Drainer.CancelToken.new()
	var warm:Dictionary=await worker(Cross.prepare.bind(map.path,Vector3.ZERO,folder,token,Cross.LEASE_BYTES))
	check(warm.get("packet")!=null and warm.packet.selected==[0],"strict cross-map prefetch selects the real source-less native model from a warm index")
	DirAccess.remove_absolute(Index.cache_path(map.path,folder))
	var cold:Dictionary=await worker(Cross.prepare.bind(map.path,Vector3.ZERO,folder,token,Cross.LEASE_BYTES))
	check(cold.get("packet")!=null and cold.packet.selected==[0],"strict cross-map prefetch rebuilds a missing index using native metadata")
	var loader:=Loader.new();loader.near_first=true;root.add_child(loader)
	loader.start(map.path,Vector3.ZERO)
	var loaded:Array=await loader.finished
	check(loaded[0]!=null and loaded[2].is_empty(),"strict game MapLoader loads the real source-less native map")
	if not loaded[2].is_empty():print("STRICT_GAME_LOADER_ERROR ",loaded[2])
	if loaded[0]!=null:loaded[0].queue_free()
	loader.queue_free();await process_frame
	var document:=preload("res://scripts/world3d/world_document.gd").new()
	document.load_box_meshes={};document.load_model_signatures={}
	var art:Dictionary={"asset_path":model,"module":"wall"}
	var record:Dictionary={"uuid":"fort","kind":"box","size":[4,2,1],"position":[0,0,0],"rotation":[0,0,0],"fortification_art":art,"fortification_materials":{},"surface_paint":[]}
	var old_key:Array=["fortification",record.size,{},[],{},record.fortification_art,record.fortification_materials,record.surface_paint,[publication.source_sha,publication.payload_sha]]
	var old_mesh:=BoxMesh.new();document.load_box_meshes[old_key]={"mesh":old_mesh,"source":old_mesh}
	for required:bool in [false,true]:
		document.load_require_native_products=required
		var visual:MeshInstance3D=document._mesh(record,true)
		check(not visual.has_meta("paint_error") and visual.mesh==old_mesh and document.load_model_signatures[model]==publication.source_sha,"editor and strict game use the same source-less native fortification identity")
		visual.free()
	var descriptor_path:=Footprint.descriptor_path(model,folder)
	check(document.load_native_model_identities.size()==1 and DirAccess.rename_absolute(descriptor_path,descriptor_path+".held")==OK,"one operation retains one native identity for repeated fortification instances")
	var cached_visual:MeshInstance3D=document._mesh(record,true)
	check(not cached_visual.has_meta("paint_error") and cached_visual.mesh==old_mesh,"same operation reuses the retained identity without reopening its descriptor")
	cached_visual.free();DirAccess.rename_absolute(descriptor_path+".held",descriptor_path)
	if issued.get("ok",false) and issued.get("index",{}).get("models",{}).has(model):
		var old_memory:Dictionary=issued.index.models[model].memory
		check(old_memory.get("native_source_sha")==publication.source_sha and old_memory.get("native_payload_sha")==publication.payload_sha,"index records published source and payload identities with the native budget")
		check(republish_same_source(model,source_bytes,publication),"publish a different real native scene under the same source bytes")
		document.load_native_model_identities.clear() # Explicit next load observes a newly published product.
		var now:=NativeFixture.Native.read(model,folder)
		var new_key:Array=["fortification",record.size,{},[],{},record.fortification_art,record.fortification_materials,record.surface_paint,[now.native_source_sha,now.native_payload_sha]]
		var new_mesh:=BoxMesh.new();document.load_box_meshes[new_key]={"mesh":new_mesh,"source":new_mesh}
		var after:MeshInstance3D=document._mesh(record,true)
		check(after.mesh==new_mesh and document.load_model_signatures[model]==now.native_source_sha,"same-source new native payload selects its own fortification cache entry")
		after.free()
		var product:String=now.native_candidate.product
		check(DirAccess.rename_absolute(product,product+".held")==OK,"temporarily hide the native product")
		document.load_native_model_identities.clear() # Begin another independent consumer operation.
		var missing:MeshInstance3D=document._mesh(record,true)
		check(missing.has_meta("paint_error"),"missing native product fails explicitly instead of accepting a cached mesh")
		missing.free();DirAccess.rename_absolute(product+".held",product)
		var changed:=Index.read_for_loading(map.path,folder,"",Index.Snapshot.RETAIN_LIMIT,Index.MAX_BYTES,Store.READ_WORKERS,false,null,true)
		check(not changed.get("ok",false) and changed.get("reason")=="native_model_changed","strict native index rejects old payload and its model-building group")
		var trusted:=Index.read_for_loading(map.path,folder,"",Index.Snapshot.RETAIN_LIMIT,Index.MAX_BYTES,Store.READ_WORKERS,true,null,true)
		check(not trusted.get("ok",false) and trusted.get("reason")=="native_model_changed","trusted native index also rejects old payload and budget")
		var rebuilt:=Index.build(map.path,folder,records,"",Store.READ_WORKERS,Index.Snapshot.RETAIN_LIMIT,false,{},{},true)
		check(rebuilt.get("ok",false) and rebuilt.models[model].memory.native_source_sha==publication.source_sha and rebuilt.models[model].memory.native_payload_sha!=publication.payload_sha,"strict rebuild binds the new native payload to unchanged source")
		var resource_uri:String=map.extras.rmmo_records[0].rmmo_ref.uri
		var resource_path:String=folder.path_join(resource_uri)
		var original:=FileAccess.get_file_as_bytes(resource_path)
		var corrupt:=original.duplicate();corrupt[corrupt.size()-1]^=1
		check(NativeFixture.write_bytes(resource_path,corrupt),"alter isolated rmres after native index rebuild")
		var invalid:=Index.build(map.path,folder,records,"",Store.READ_WORKERS,Index.Snapshot.RETAIN_LIMIT,false,{},{},true)
		check(not invalid.get("ok",false),"strict native index still rejects changed rmres bytes")
		NativeFixture.write_bytes(resource_path,original)
	print("STRICT_NATIVE_INDEX_RESULT ",JSON.stringify({"build_ok":built.get("ok",false),"build_reason":built.get("reason",""),"build_rows":built.get("rows",[]),"build_models":built.get("models",{}).size(),"read_ok":issued.get("ok",false),"read_reason":issued.get("reason","")}))
	helper.free();manager.content_root_override=previous_root;Policy.verify_packages=previous_policy
	OS.remove_logger(errors);check(errors.errors.is_empty(),"no script or engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("STRICT_NATIVE_INDEX passed=",passed," failed=",failed);quit(1 if failed else 0)
