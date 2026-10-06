extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const BASE="D:/code/rmmo_runtime"
func run()->void:
	create_timer(180).timeout.connect(func():quit(2));rpc_timeout_ms=30000
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var directory=Paths.cache_directory("tree_library_check_%d"%Time.get_ticks_usec());var doc=Doc.new();var path=directory+"/map.gltf";doc.save(path)
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=Library.new(directory+"/assets");editor._shared_assets=[Library.new(BASE+"/packs/default/assets")]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP server")
	var listing=await call_tool("list_assets",{"query":"参数化松树"});check(listing.total==3,"three published parametric prefabs")
	if listing.total!=3:quit(1);return
	await call_tool("place_asset",{"asset_id":listing.assets[1].asset_id,"position":[0,0,0]});var id=doc.records[0].uuid
	var described=await call_tool("get_tree_parameters",{"id":id});check(described.supported,"published prefab editable")
	await call_tool("select_objects",{"ids":[id]})
	editor._camera.position=Vector3(12,7,18);editor._camera.look_at(Vector3(0,4,0))
	var scroll=editor._inspector.get_parent();editor._dock_tabs.current_tab=scroll.get_index()
	await settle();scroll.ensure_control_visible(editor._inspector.tree_panel.form)
	for i in 24:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(BASE+"/review_artifacts/pine_parametric/inspector.png")
	check(editor._inspector.tree_panel.visible,"native inspector visible")
	var f=FileAccess.open(BASE+"/review_artifacts/pine_parametric/library_check.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failed,"total":listing.total,"real_http":true,"user_maps_modified":false},"\t"));f.close()
	editor.queue_free();await settle();print("TREE_LIBRARY_FAILURES ",failed);quit(1 if failed else 0)
