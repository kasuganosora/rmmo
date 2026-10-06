extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const BASE="D:/code/rmmo_runtime"
const OUT=BASE+"/review_artifacts/street_oak_game"
const LABEL="写实阔叶橡树·宽冠粗干"
func run()->void:
	if OS.get_cmdline_user_args().has("--catalog-cleanup"):
		var catalog=Library.new(BASE+"/packs/default/assets")
		var publication=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/publication.json"))
		if publication.failures!=0:quit(1);return
		var payload=JSON.parse_string(FileAccess.get_file_as_string(publication.entry.prefab_path))
		var dependency=catalog.directory.path_join(payload.records[0].asset_path).simplify_path()
		catalog.entries=catalog.entries.filter(func(e):return str(e.get("asset_path","")).simplify_path()!=dependency)
		if catalog.save()!=OK:quit(1);return
		var reread=Library.new(catalog.directory)
		if reread.entries.filter(func(e):return e.get("label","")==LABEL).size()!=1 or reread.entries.any(func(e):return str(e.get("asset_path","")).simplify_path()==dependency):quit(1);return
		publication.library_model_sha256=FileAccess.get_sha256(dependency)
		publication.single_catalog_entry=true
		FileAccess.open(OUT+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify(publication,"\t"))
		print("OAK_CATALOG_UNIQUE_VERIFIED");quit();return
	create_timer(420).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var tested=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/validation.json"))
	var review=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/visual_review.json"))
	var spec=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/street_oak_game/manifest.json"))[0]
	var hash_=FileAccess.get_sha256(spec.file)
	if tested.failures!=0 or not review.reviewed or hash_!=tested.sha256 or hash_!=review.sha256:quit(1);return
	var directory=Paths.cache_directory("oak_publication_%d"%Time.get_ticks_usec())
	var local=Library.new(directory+"/assets");var imported=local.import_file(spec.file)
	if not imported.ok:quit(1);return
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=local;editor._shared_assets=[Library.new(BASE+"/packs/default/assets")]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	var discovery=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="save_prefab"),"3D prefab tool discovered")
	await call_tool("list_resource_packs")
	var key=preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(imported.entry)
	await call_tool("place_asset",{"asset_id":key,"position":[0,0,0]})
	await call_tool("select_objects",{"ids":[doc.records.back().uuid]})
	var lib=Library.new(BASE+"/packs/default/assets")
	var existing=lib.entries.filter(func(e):return e.get("label","")==LABEL and e.has("prefab_path"))
	var saved:Dictionary
	if existing.size()==1:saved={"entry":existing[0],"asset_id":preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(existing[0])}
	elif existing.is_empty():saved=await call_tool("save_prefab",{"name":LABEL,"pack_root":BASE+"/packs/default"})
	else:push_error("Duplicate oak prefabs");quit(1);return
	if not saved.has("entry"):quit(1);return
	check(DirAccess.copy_absolute(OUT+"/runtime_lod_0.png",saved.entry.thumbnail_path)==OK,"reviewed thumbnail")
	# Keep a single visible prefab entry; retain its immutable model dependency.
	lib=Library.new(BASE+"/packs/default/assets")
	var payload=JSON.parse_string(FileAccess.get_file_as_string(saved.entry.prefab_path))
	var dependency=lib.directory.path_join(payload.records[0].asset_path).simplify_path()
	lib.entries=lib.entries.filter(func(e):return str(e.get("asset_path","")).simplify_path()!=dependency)
	check(lib.save()==OK,"atomic catalog save without duplicate model slot")
	editor._shared_assets=[Library.new(lib.directory)]
	var listing=await call_tool("list_assets",{"query":LABEL});check(listing.total==1,"one published prefab discoverable")
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[12,0,0]})
	check(doc.records.size()==2,"published prefab placed")
	await call_tool("undo");check(doc.records.size()==1,"undo");await call_tool("redo");check(doc.records.size()==2,"redo")
	var before=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"invalid_oak","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement atomic")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==2 and doc.missing_assets().is_empty(),"save reopen dependencies")
	for record in doc.records:
		var model=doc._asset(record);var meshes=Paint.meshes(model)
		check(meshes.size()==4,"trunk and three LODs")
		check(meshes.filter(func(m):return m.get_meta("extras",{}).has("rmmo_visibility_range")).size()==3,"LOD preserved")
		check(meshes.filter(func(m):return m.get_meta("extras",{}).has("rmmo_wind")).size()==2,"wind preserved")
		model.free()
	FileAccess.open(OUT+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"entry":saved.entry,"accepted_sha256":hash_,"real_http":true,"user_maps_modified":false,"test_map":path,"single_catalog_entry":true},"\t"))
	print("OAK_PUBLICATION_FAILURES ",failed);editor.queue_free();await settle();quit(1 if failed else 0)
