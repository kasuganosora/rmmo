extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/signs_banners_20261007"
const CATEGORY="牌匾/旗帜"
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=30000
	var directory=Paths.cache_directory("sign_category_ui_%d"%Time.get_ticks_usec())
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temporary empty map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=Library.new(directory+"/assets");editor._shared_assets=[Library.new("D:/code/rmmo_runtime/packs/default/assets")];editor._refresh_palette()
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	var before=doc.recovery_snapshot()
	for index in editor._asset_category_picker.item_count:
		if editor._asset_category_picker.get_item_metadata(index)==CATEGORY:
			editor._asset_category_picker.select(index);editor._asset_category_picker.item_selected.emit(index);break
	check(editor._asset_category==CATEGORY and editor._palette_items.size()==30,"category dropdown signal filters UI")
	var listing=await call_tool("list_assets",{"category":CATEGORY,"limit":100})
	check(listing.total==30,"MCP category matches UI")
	var missing:Array=[]
	for entry in editor._palette_items:
		if not FileAccess.file_exists(Thumb.thumbnail_path(entry)):missing.append(Thumb.key_for(entry))
	if not missing.is_empty():await call_tool("repair_asset_thumbnails",{"asset_ids":missing})
	var deadline=Time.get_ticks_msec()+160000
	while Time.get_ticks_msec()<deadline:
		if editor._palette_items.all(func(e):return FileAccess.file_exists(Thumb.thumbnail_path(e))):break
		await create_timer(.25).timeout
	check(editor._palette_items.all(func(e):return FileAccess.file_exists(Thumb.thumbnail_path(e))),"all 30 catalog thumbnails present")
	check(doc.recovery_snapshot()==before,"category UI and thumbnail repair do not change map")
	for frame in 15:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/category_editor.png")
	FileAccess.open(OUT+"/category_ui_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"category":CATEGORY,"items":listing.total,"repaired_thumbnails":missing.size(),"user_maps_modified":false},"\t"))
	editor.queue_free();await settle();print("SIGN_CATEGORY_UI_FAILURES ",failed);quit(1 if failed else 0)
