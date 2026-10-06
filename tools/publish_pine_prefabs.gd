extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const BASE="D:/code/rmmo_runtime"
func run()->void:
	create_timer(300).timeout.connect(func():quit(2));rpc_timeout_ms=30000
	var directory=Paths.cache_directory("pine_prefab_acceptance_%d"%Time.get_ticks_usec())
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=Library.new(directory+"/assets");editor._shared_assets=[Library.new(BASE+"/packs/default/assets")]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP")
	var discovery=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="save_prefab"),"prefab tool discovery")
	await call_tool("list_resource_packs")
	var published=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/review_artifacts/pine_dense_v3_game/published.json"))
	var entries=[]
	for index in published.items.size():
		var row=published.items[index]
		check(FileAccess.get_sha256(row.entry.asset_path)==row.sha256,"accepted model hash")
		var asset_id=preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(row.entry)
		await call_tool("place_asset",{"asset_id":asset_id,"position":[index*12,0,0]})
		var id=doc.records.back().uuid
		await call_tool("select_objects",{"ids":[id]})
		var name_=str(row.label)+"·预制件"
		var existing=await call_tool("list_assets",{"query":name_})
		var saved:Dictionary
		if existing.total>0:
			var lib=Library.new(BASE+"/packs/default/assets")
			var found=lib.entries.filter(func(e):return e.get("label","")==name_ and e.has("prefab_path"))
			check(found.size()==1,"unique accepted prefab")
			if found.size()!=1:quit(1);return
			saved={"entry":found[0],"asset_id":preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(found[0])}
		else:saved=await call_tool("save_prefab",{"name":name_,"pack_root":BASE+"/packs/default"})
		if not saved.has("entry"):quit(1);return
		check(DirAccess.copy_absolute(BASE+"/review_artifacts/pine_dense_v3_game/"+row.id+".png",saved.entry.thumbnail_path)==OK,"approved thumbnail")
		await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[index*12,0,16]})
		var count=doc.records.size();await call_tool("undo");check(doc.records.size()==count-1,"prefab undo");await call_tool("redo");check(doc.records.size()==count,"prefab redo")
		entries.append(saved.entry)
	var before=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"invalid_pine_prefab","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid prefab atomic")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==6 and doc.missing_assets().is_empty(),"six instances save reopen")
	for record in doc.records:
		var model=doc._asset(record);var meshes=Paint.meshes(model)
		check(meshes.filter(func(m):return m.get_meta("extras",{}).has("rmmo_visibility_range")).size()==3,"prefab preserves three LODs")
		check(meshes.any(func(m):return m.get_meta("extras",{}).has("rmmo_wind")),"prefab preserves wind")
		model.free()
	var file=FileAccess.open(BASE+"/review_artifacts/pine_density/prefab_publication.json",FileAccess.WRITE);file.store_string(JSON.stringify({"user_accepted":true,"failures":failed,"entries":entries,"real_http":true,"user_maps_modified":false,"test_map":path},"\t"));file.close()
	print("PINE_PREFAB_FAILURES ",failed);editor.queue_free();await settle();quit(1 if failed else 0)
