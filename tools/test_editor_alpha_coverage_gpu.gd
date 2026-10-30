extends "res://tools/test_world3d_mcp.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Streamed=preload("res://scripts/world3d/streamed_texture_source.gd")
var ui_result:Dictionary={}
var stream_observation:Dictionary={}
func observed_stream(value:Dictionary)->void:stream_observation=value

func painted_material(id:String)->StandardMaterial3D:
	var visual:Node=editor._view.get_node_or_null(id)
	if visual==null:return null
	for mesh:MeshInstance3D in Paint.meshes(visual):
		for slot:int in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(slot)
			if material is StandardMaterial3D and material.albedo_texture!=null:return material
	return null
func imported_ui(_id:int,result:Dictionary)->void:ui_result=result

func capture_mips(folder:String,plain:Texture2D,kept:Texture2D,streamed:bool)->void:
	# Inspect the published mip chains independently from streaming residency.
	# Real editor ownership/streaming is verified above; these are test-only
	# full-resident copies, so an initial coarse-mip request cannot bias A/B.
	var plain_resident:Texture2D
	var kept_resident:Texture2D
	if streamed:
		plain_resident=ClassDB.instantiate("StreamedTexture2D");kept_resident=ClassDB.instantiate("StreamedTexture2D")
		check(plain_resident.call("load",plain.get("load_path"))==OK and kept_resident.call("load",kept.get("load_path"))==OK,"fresh native owners for cold streaming observation")
	else:
		plain_resident=ImageTexture.create_from_image(plain.get_image());kept_resident=ImageTexture.create_from_image(kept.get_image())
	var view:=SubViewport.new();view.size=Vector2i(768,512);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.12,.12,.12);view.add_child(env)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.5;camera.position=Vector3(0,0,5);view.add_child(camera);camera.look_at(Vector3.ZERO)
	for col:int in 2:
		var label:=Label.new();label.text="Ordinary mips / cutout 0.5" if col==0 else "Coverage mips / cutout 0.5";label.position=Vector2(25+384*col,5);view.add_child(label)
		for row:int in 3:
			var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;mat.alpha_scissor_threshold=.5
			mat.albedo_texture=plain_resident if col==0 else kept_resident;mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var quad:=QuadMesh.new();quad.size=Vector2.ONE*[1.4,.42,.105][row];quad.material=mat
			var node:=MeshInstance3D.new();node.mesh=quad;node.position=Vector3(-1.3125+col*2.625,1.-row*1.1,0);view.add_child(node)
	var streaming:Object=Engine.get_singleton("TextureStreaming")
	var ticket:=int(streaming.call("begin_texture_observation",[plain_resident,kept_resident])) if streamed else 0
	for _frame:int in 45:await process_frame
	if streamed:
		stream_observation={};streaming.call("query_texture_observation",ticket,Callable(self,"observed_stream"))
		var deadline:=Time.get_ticks_msec()+3000
		while stream_observation.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(stream_observation.get("covered",false),"native feedback observation completed")
		print("ALPHA_STREAM_OBSERVATION ",JSON.stringify({"plain_id":plain_resident.get_instance_id(),"kept_id":kept_resident.get_instance_id(),"observation":stream_observation}))
		streaming.call("cancel_texture_observation",ticket)
	await RenderingServer.frame_post_draw
	var capture:=view.get_texture().get_image()
	var counts:Array=[]
	for col:int in 2:
		var column:Array=[]
		for row:Vector2i in [Vector2i(30,220),Vector2i(225,330),Vector2i(380,480)]:
			var green:=0
			for y:int in range(row.x,row.y):
				for x:int in range(col*384,(col+1)*384):
					var pixel:=capture.get_pixel(x,y)
					green+=int(pixel.g>pixel.r*1.5 and pixel.g>pixel.b*1.5)
			column.append(green)
		counts.append(column)
	if streamed:
		check(counts[1].all(func(n):return n>0),"opt-in cold streamed cutout is visible near/mid/far")
	print("ALPHA_RENDER_COUNTS ",JSON.stringify({"streamed":streamed,"counts":counts}))
	check(capture.save_png(folder.path_join("coverage_streamed.png" if streamed else "coverage_near_mid_far.png"))==OK,"capture same-camera near/mid/far with declared residency")
	view.queue_free();await settle()

func run()->void:
	create_timer(150).timeout.connect(func():quit(2));Engine.max_fps=60;rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("alpha_coverage_gpu_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var pack_root:=Paths.external_root().path_join("__alpha_package_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(pack_root)
	var metadata:=FileAccess.open(pack_root.path_join("metadata.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id":"alpha_fixture","name":"Alpha coverage fixture"}));metadata.close()
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y:int in 64:
		for x:int in 64:image.set_pixel(x,y,Color(.2,.65,.3,1. if (x*37+y*67+x*y*13)%101<30 else 0.))
	var source:=directory.path_join("cutout.png");check(image.save_png(source)==OK,"write independent cutout source")
	var doc:=Doc.new();var ids:Array[String]=[]
	for i:int in 3:ids.append(doc.add_box("block",Vector3(i*3,1,0),Vector3(2,2,2)))
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"save isolated map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._material_directory=directory.path_join("materials");editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real HTTP MCP")
	var discovery:=await rpc("tools/list")
	var import_tools:Array=discovery.get("result",{}).get("tools",[]).filter(func(t):return t.name=="import_surface_material")
	check(import_tools.size()==1 and import_tools[0].inputSchema.properties.preserve_alpha_test_coverage.default==false and import_tools[0].inputSchema.properties.alpha_test_threshold.default==.5,"HTTP discovery exposes opt-in coverage defaults")
	var before:Dictionary=editor._surface_texture_imports.snapshot()
	await call_tool("import_surface_material",{"path":source,"preserve_alpha_test_coverage":true,"alpha_test_threshold":1.1},false)
	check(editor._surface_texture_imports.snapshot().broker.producers==before.broker.producers,"invalid cutoff creates no import work")
	var plain:=await call_tool("import_surface_material",{"path":source,"name":"cutout default"})
	var kept:=await call_tool("import_surface_material",{"path":source,"name":"cutout keep","preserve_alpha_test_coverage":true,"alpha_test_threshold":.5})
	check(plain.get("ok",false) and kept.get("ok",false),"HTTP imports default and opt-in variants")
	if not plain.get("ok",false) or not kept.get("ok",false):quit(1);return
	check(not plain.material.has("alpha_scissor_threshold") and kept.material.alpha_scissor_threshold==.5,"opt-in result carries matching cutout semantics")
	check(plain.material.texture_path!=kept.material.texture_path,"option variants retain independent source/product paths")
	var compressed:=await call_tool("import_surface_material",{"path":source,"name":"cutout DDS","compression":"dds","preserve_alpha_test_coverage":true,"alpha_test_threshold":.5})
	check(compressed.get("ok",false) and compressed.get("dds_ready",false) and compressed.get("alpha_test_threshold")==.5,"explicit DDS import also preserves coverage settings")
	if compressed.get("ok",false):
		var compressed_owner:=Paint.texture(compressed.material)
		check(compressed_owner.is_class("StreamedTexture2D") and compressed_owner.get_image().is_compressed(),"coverage DDS remains compressed and streamed")
	var plain_owner:=Paint.texture(plain.material);var kept_owner:=Paint.texture(kept.material)
	check(plain_owner.is_class("StreamedTexture2D") and kept_owner.is_class("StreamedTexture2D"),"both variants use actual streamed textures")
	var pixels:=kept_owner.get_image();pixels.clear_mipmaps();pixels.convert(Image.FORMAT_RGBA8)
	check(pixels.get_data()==image.get_data(),"streaming mip0 is byte-identical including alpha")
	# Exercise the actual import dialog controls and the existing shared service.
	editor._surface_texture_imports.finished.connect(imported_ui)
	editor._material_panel._import();await settle()
	var dialog:FileDialog
	for child:Node in editor.get_children():
		if child is FileDialog and child.title=="导入表面贴图":dialog=child
	check(dialog!=null,"UI exposes material import dialog")
	if dialog==null:quit(1);return
	var toggle:CheckBox=dialog.find_child("PreserveAlphaCoverage",true,false);var threshold:SpinBox=dialog.find_child("AlphaTestThreshold",true,false)
	check(toggle!=null and threshold!=null and not toggle.button_pressed and threshold.value==.5,"UI defaults preserve existing behavior")
	toggle.button_pressed=true;threshold.value=.7;dialog.file_selected.emit(source)
	var deadline:=Time.get_ticks_msec()+30000
	while ui_result.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(ui_result.get("ok",false) and ui_result.get("alpha_test_threshold")==.7,"UI imports its selected cutoff through shared pipeline")
	editor._surface_texture_imports.finished.disconnect(imported_ui)
	if not ui_result.get("ok",false):quit(1);return
	if not compressed.get("ok",false):quit(1);return
	var variants:Array=[kept,ui_result,compressed]
	for i:int in ids.size():
		var faces:=await call_tool("list_object_surfaces",{"id":ids[i]})
		await call_tool("paint_surface",{"id":ids[i],"target":faces.faces[0].target,"material_id":variants[i].material_id})
		var material:=painted_material(ids[i])
		check(material!=null and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(material.alpha_scissor_threshold,float(variants[i].alpha_test_threshold)),"actual drawn material uses requested alpha scissor")
	var records:Array=editor._doc.records.duplicate(true)
	await call_tool("undo");await call_tool("redo");check(equivalent(records,editor._doc.records),"cutout paint undo and redo preserve options")
	await call_tool("save_world");Paint.refresh_sources()
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(records,editor._doc.records),"save and reopen preserve both independent cutoffs")
	for i:int in ids.size():
		var material:=painted_material(ids[i])
		check(material!=null and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and material.albedo_texture.is_class("StreamedTexture2D"),"reopened actual scene retains scissor and streaming")
	check(editor._load_job.state().timings.preparation.ledger.jobs==0 and Paint.prepared_textures.is_empty(),"all preparation leases and borrowed owners retire")
	await call_tool("select_objects",{"ids":ids})
	await call_tool("list_resource_packs")
	var prefab:=await call_tool("save_prefab",{"name":"Alpha independent variants","pack_root":pack_root})
	if not prefab.get("ok",false):quit(1);return
	await call_tool("place_asset",{"asset_id":prefab.asset_id,"position":[15,0,0]})
	var placed_ids:Array=editor._selection_tools.ids.duplicate()
	check(placed_ids.size()==3 and editor._doc.records.size()==6,"portable prefab restores three editable members")
	var native_products:Dictionary={};var packed_cutoffs:Array=[]
	for id:String in placed_ids:
		var material:=painted_material(id)
		check(material!=null and material.albedo_texture.is_class("StreamedTexture2D"),"placed prefab retains native texture owner")
		if material==null:continue
		packed_cutoffs.append(material.alpha_scissor_threshold)
		var definitions:Array=Paint.definitions(editor._doc._find(id)).filter(func(d):return d.has("alpha_scissor_threshold"))
		check(definitions.size()==1,"packed record retains exact cutout definition")
		if definitions.size()!=1:continue
		var definition:Dictionary=definitions[0]
		var packed_source:String=definition.texture_path
		var compressed_product:bool=material.albedo_texture.get_image().is_compressed()
		var original:Dictionary=compressed if compressed_product else (kept if is_equal_approx(material.alpha_scissor_threshold,.5) else ui_result)
		var descriptor_path:=Streamed.descriptor_path(packed_source,false,false,compressed_product)
		var original_descriptor:=Streamed.descriptor_path(original.material.texture_path,false,false,compressed_product)
		check(packed_source.begins_with(pack_root+"/assets/") and FileAccess.get_sha256(descriptor_path)==FileAccess.get_sha256(original_descriptor),"packaged descriptor preserves variant and coverage metadata")
		var plan:=Streamed.plan_imported(packed_source,false,false,Paths.external_root())
		check(not plan.is_empty() and FileAccess.get_sha256(plan.product)==FileAccess.get_sha256(Paint.texture(original.material).get("load_path")),"packaged native mip payload is byte-identical")
		if not plan.is_empty():native_products[plan.product]=true
	packed_cutoffs.sort()
	check(packed_cutoffs.size()==3 and is_equal_approx(packed_cutoffs[0],.5) and is_equal_approx(packed_cutoffs[1],.5) and is_equal_approx(packed_cutoffs[2],.7) and native_products.size()==3,"source and DDS plus distinct cutoffs never alias when packaged")
	var packaged_records:Array=editor._doc.records.duplicate(true)
	await call_tool("undo");check(editor._doc.records.size()==3,"packaged placement undoes as one operation")
	await call_tool("redo");check(equivalent(packaged_records,editor._doc.records),"packaged placement redo restores independent variants")
	await call_tool("save_world");Paint.refresh_sources()
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(packaged_records,editor._doc.records),"save and reopen retain packaged cutout products")
	for id:String in placed_ids:
		var material:=painted_material(id)
		check(material!=null and material.albedo_texture.is_class("StreamedTexture2D"),"reopened packaged scene still streams")
	await capture_mips(directory,plain_owner,kept_owner,true)
	await capture_mips(directory,plain_owner,kept_owner,false)
	print("EDITOR_ALPHA_COVERAGE ",JSON.stringify({"failed":failed,"fixture":directory,"plain_path":plain.material.texture_path,"kept_path":kept.material.texture_path,"ui_path":ui_result.material.texture_path}))
	editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	quit(1 if failed else 0)
