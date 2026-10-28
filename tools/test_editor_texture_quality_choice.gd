extends "res://tools/test_world3d_mcp.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const DDS=preload("res://scripts/world3d/compressed_texture_source.gd")
var replies:Dictionary={}
var ui_result:Dictionary={}

func import_one(key:String,path:String,mode:String,label:String="shared quality")->void:
	replies[key]=await call_tool("import_surface_material",{"path":path,"name":label,"compression":mode})

func import_finished(_id:int,result:Dictionary)->void:
	ui_result=result

func run()->void:
	create_timer(120).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var folder:=Paths.cache_directory("texture_quality_choice_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var source:=folder.path_join("leaf.png")
	var original:=Image.create(32,32,false,Image.FORMAT_RGBA8);original.fill(Color(.2,.4,.1,.6));original.fill_rect(Rect2i(0,0,12,32),Color(0,0,0,0))
	check(original.save_png(source)==OK,"isolated alpha source")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._material_directory=folder.path_join("materials");editor._draft_directory=folder.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual HTTP MCP")
	var discovery:=await rpc("tools/list");var schema:Dictionary={}
	for tool:Dictionary in discovery.get("result",{}).get("tools",[]):
		if tool.name=="import_surface_material":schema=tool.inputSchema
	check(schema.get("properties",{}).has("compression"),"HTTP schema exposes the quality choice")
	# Same input and label-independent content: two source subscribers must
	# coalesce while the distinct DDS representation retains its own producer.
	import_one.call_deferred("source_a",source,"source")
	import_one.call_deferred("source_b",source,"source")
	import_one.call_deferred("dds",source,"dds")
	var deadline:=Time.get_ticks_msec()+60000
	while replies.size()<3 and Time.get_ticks_msec()<deadline:await process_frame
	check(replies.size()==3,"concurrent representations finish")
	if not replies.get("source_a",{}).get("ok",false) or not replies.get("dds",{}).get("ok",false):editor.queue_free();await settle();print("EDITOR_TEXTURE_QUALITY_CHOICE_FAILED=",failed);quit(1);return
	var a:Dictionary=replies.source_a;var b:Dictionary=replies.source_b;var compressed:Dictionary=replies.dds
	check(not a.get("dds_ready",false) and a.get("dds_reason","")=="source_requested","explicit source choice skips lossy encoding")
	check(compressed.get("dds_ready",false),"explicit DDS choice still produces compressed pixels")
	check(a.material.texture_path==b.material.texture_path and a.material.texture_path!=compressed.material.texture_path,"source subscribers share content while representations cannot overwrite each other")
	check(a.material_id!=compressed.material_id,"quality variants have distinct material identities")
	check(a.material_id==b.material_id and editor._surface_texture_imports.snapshot().broker.producers==2,"same-quality subscribers share one producer and same-name material commit")
	var owner:=Paint.retained_texture(Paint.texture_key(a.material.texture_path));var dds_owner:=Paint.retained_texture(Paint.texture_key(compressed.material.texture_path))
	var image:Image=owner.get_image() if owner!=null else null
	if image!=null and not image.is_compressed():image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	check(image!=null and not image.is_compressed() and image.get_data()==original.get_data(),"actual source GPU pixels preserve alpha and color exactly")
	check(dds_owner!=null and dds_owner!=owner and dds_owner.get_image().get_format()==Image.FORMAT_DXT5,"actual DDS owner remains independent and DXT5")
	check(DDS.sidecar_path(a.material.texture_path,false,false).is_empty(),"source variant cannot accidentally pick the sibling DDS")
	var native=preload("res://scripts/world3d/streamed_texture_source.gd")
	if native.enabled():
		for pair:Array in [[a,owner,Image.FORMAT_RGBA8],[compressed,dds_owner,Image.FORMAT_DXT5]]:
			var imported:Dictionary=pair[0]
			var native_plan:Dictionary=native.plan(imported.material.texture_path,false,false,Paths.external_root())
			check(not native_plan.is_empty() and native_plan.format==pair[2],"real HTTP import publishes native product in the requested representation")
			if native_plan.is_empty():continue
			var worker:=Thread.new();worker.start(native.read.bind(native_plan,str(imported.material.texture_path).sha256_text()))
			while worker.is_alive():await process_frame
			var streamed:Texture2D=worker.wait_to_finish()
			check(streamed!=null and streamed.get_image().get_data()==pair[1].get_image().get_data(),"published native product retains every source pixel or existing DDS mip block")
	import_one.call_deferred("collision_source",source,"source","x")
	import_one.call_deferred("collision_dds",source,"dds","|source|x")
	deadline=Time.get_ticks_msec()+30000
	while replies.size()<5 and Time.get_ticks_msec()<deadline:await process_frame
	check(replies.size()==5 and replies.collision_source.material_id!=replies.collision_dds.material_id,"arbitrary labels cannot collide across quality namespaces")
	check(not replies.collision_source.dds_ready and replies.collision_dds.dds_ready,"concurrent collision-label requests retain their requested quality")
	var default_import:=await call_tool("import_surface_material",{"path":source,"name":"default quality"})
	check(default_import.get("compression","")=="source" and not default_import.get("dds_ready",false),"omitted MCP quality defaults to preserving pixels")
	var before:Dictionary=editor._surface_texture_imports.snapshot()
	await call_tool("import_surface_material",{"path":source,"compression":"invalid"},false)
	check(editor._surface_texture_imports.snapshot().queue.started==before.queue.started,"invalid quality does not start preparation")
	# Exercise the real UI dialog and its selected option, including the actual
	# file-selected callback rather than bypassing the UI with a direct submit.
	editor._material_panel._import();var dialog:FileDialog
	for child:Node in editor.get_children():
		if child is FileDialog:dialog=child
	check(dialog!=null and dialog.get_option_count()==1,"UI exposes one quality selection")
	if dialog!=null and dialog.get_option_count()==1:
		check(dialog.get_option_values(0).size()==2,"UI offers source preservation and lossy compression")
		dialog.set_option_default(0,0)
		editor._surface_texture_imports.finished.connect(import_finished)
		dialog.file_selected.emit(source);deadline=Time.get_ticks_msec()+30000
		while ui_result.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(ui_result.get("ok",false) and not ui_result.get("dds_ready",false) and ui_result.get("material",{}).get("texture_path","")==a.material.texture_path,"UI source selection reuses exactly the HTTP source representation")
		ui_result={};editor._material_panel._import()
		for child:Node in editor.get_children():
			if child is FileDialog and not child.is_queued_for_deletion():dialog=child
		dialog.set_option_default(0,1);dialog.file_selected.emit(source);deadline=Time.get_ticks_msec()+30000
		while ui_result.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(ui_result.get("ok",false) and ui_result.get("dds_ready",false) and ui_result.get("material",{}).get("texture_path","")==compressed.material.texture_path,"UI explicit DDS selection reuses exactly the HTTP compressed representation")
	else:
		if dialog!=null:dialog.queue_free()
	var doc:=Doc.new();var id:String=doc.add_box("block",Vector3(0,1,0),Vector3(2,2,2));var path:=folder.path_join("paint.gltf");doc.save(path)
	await call_tool("open_world",{"path":path,"discard_changes":true})
	var faces:=await call_tool("list_object_surfaces",{"id":id})
	await call_tool("paint_surface",{"id":id,"target":faces.faces[0].target,"material_id":a.material_id})
	var painted:Array=editor._doc.records.duplicate(true)
	await call_tool("undo");check(editor._doc._find(id).get("surface_paint",[]).is_empty(),"source material undo")
	await call_tool("redo");check(equivalent(editor._doc.records,painted),"source material redo")
	await call_tool("save_world");Paint.refresh_sources()
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(editor._doc.records,painted),"quality choice survives actual save/reopen")
	owner=Paint.retained_texture(Paint.texture_key(a.material.texture_path));image=owner.get_image() if owner!=null else null
	if image!=null and not image.is_compressed():image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
	check(image!=null and not image.is_compressed() and image.get_data()==original.get_data(),"reopen preserves source pixels even while sibling DDS exists")
	check(editor._shared_preparation_ledger.count()==0,"all preparation leases returned")
	editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("EDITOR_TEXTURE_QUALITY_CHOICE_FAILED=",failed);quit(1 if failed else 0)
