extends "res://tools/publish_signs_and_banners.gd"
func run()->void:
	create_timer(780).timeout.connect(func():quit(2));rpc_timeout_ms=120000
	var lib=Library.new(BASE+"/packs/default/assets")
	var rows:Array=[]
	for a in JSON.parse_string(FileAccess.get_file_as_string(SIGNS+"/manifest.json")).assets:
		rows.append({"id":a.id,"source":SIGNS+"/"+a.id+".glb","source_hash":a.sha256,"triangles":a.triangles,"label":("写实烙画木牌·" if a.kind=="board" else "写实木挂架·")+a.label,"cloth":false})
	for a in JSON.parse_string(FileAccess.get_file_as_string(FLAGS+"/manifest.json")).assets:
		rows.append({"id":a.id,"source":FLAGS+"/models/"+a.id+".glb","source_hash":a.sha256,"triangles":a.export_triangles,"label":"写实"+a.label,"cloth":true})
	for row in rows:
		var entries=lib.entries.filter(func(e):return e.label==row.label and e.category==CATEGORY and e.has("prefab_path"))
		check(entries.size()==1,"unique published module "+row.id)
		if entries.size()!=1:quit(1);return
		row.entry=entries[0]
		var payload=Prefabs.read(row.entry);check(payload.ok and payload.records.size()==1,"independent portable module")
		check(FileAccess.get_sha256(row.source)==row.source_hash,"approved source unchanged")
		var dependency=payload.records[0].asset_path
		check(FileAccess.get_sha256(dependency)==dependency.get_file().get_basename(),"published immutable dependency")
		var model=Library.instantiate_preview(dependency);inspect(model,row.cloth)
		var triangles=0
		for mesh in Paint.meshes(model):triangles+=mesh.mesh.get_faces().size()/3
		check(triangles==row.triangles,"published optimized topology")
		model.free()
	if failed:quit(1);return
	var directory=Paths.cache_directory("signs_banners_groups_%d"%Time.get_ticks_usec())
	var doc=Doc.new();var path=directory+"/group_0.gltf";check(doc.save(path)==OK,"empty temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=Library.new(directory+"/assets");editor._shared_assets=[lib]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	var discovery=await rpc("tools/list")
	check(discovery.result.tools.any(func(t):return t.name=="list_assets" and t.inputSchema.properties.has("category")),"3D category schema discovery")
	var listing=await call_tool("list_assets",{"category":CATEGORY,"limit":100})
	check(listing.total==30,"30 category entries")
	var before=doc.recovery_snapshot()
	await call_tool("list_assets",{"category":12},false)
	await call_tool("place_asset",{"asset_id":"missing_sign_banner","position":[0,0,0]},false)
	check(doc.recovery_snapshot()==before,"invalid requests have no side effects")
	var maps:Array=[]
	for group in 6:
		if group>0:
			path=directory+"/group_%d.gltf"%group
			var empty=Doc.new();check(empty.save(path)==OK,"next empty temporary map")
			var opened=await call_tool("open_world",{"path":path})
			if not opened.get("ok",false):quit(1);return
			doc=editor._doc
		for i in range(group*4,group*4+4):
			await call_tool("place_asset",{"asset_id":Thumb.key_for(rows[i].entry),"position":[(i%4)*4,0,0]})
		check(doc.records.size()==4,"four independent modules")
		await call_tool("undo");check(doc.records.size()==3,"undo placement")
		await call_tool("redo");check(doc.records.size()==4,"redo placement")
		var saved=await call_tool("save_world")
		if not saved.get("ok",false):quit(1);return
		var reopened=await call_tool("open_world",{"path":path})
		if not reopened.get("ok",false):quit(1);return
		doc=editor._doc
		check(doc.records.size()==4 and doc.missing_assets().is_empty(),"group saved and reopened with all dependencies")
		check(doc.records.all(func(r):return r.collision=="none"),"nonblocking modules retained")
		maps.append(path)
	editor.queue_free();await settle()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader)
	# start may emit synchronously for an empty/error map; subscribe first.
	loader.start.call_deferred(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"game asynchronous map load")
	if loaded[0]!=null:loaded[0].free()
	if is_instance_valid(loader):loader.queue_free()
	for row in rows:check(DirAccess.copy_absolute(OUT+"/"+row.id+".png",row.entry.thumbnail_path)==OK,"front-view thumbnail restored")
	var moved:Array=[]
	for entry in lib.entries:
		if entry.label in EXISTING:
			check(entry.category==CATEGORY,"existing flag entry migrated")
			moved.append(entry.label)
	FileAccess.open(OUT+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"new_assets":rows,"moved_existing":moved,"category":CATEGORY,"total":listing.total,"real_http":true,"user_maps_modified":false,"test_maps":maps,"validation":"six bounded maps, four published modules each; initial large-map test timed out and is not counted as a pass"},"\t"))
	print("SIGNS_BANNERS_GROUPED_FAILURES ",failed);quit(1 if failed else 0)
