extends "res://tools/test_world3d_mcp.gd"
const Banner=preload("res://scripts/world3d/streetlamp_banner.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Wind=preload("res://scripts/world3d/wind_material.gd")
var folder:String
func drain()->void:
	var deadline:=Time.get_ticks_msec()+60000
	while (editor._asset_operations.snapshot().pending>0 or not editor._inspector.banner_panel._copy.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	await settle()
func cloth(id:String)->MeshInstance3D:return Banner.slot(editor._view.get_node(NodePath(id)))
func run()->void:
	create_timer(180).timeout.connect(func():quit(2));rpc_timeout_ms=60000;Engine.max_fps=60
	folder=Paths.cache_directory("banner48_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var pack_root:=Paths.external_root().path_join("__banner_package_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(pack_root)
	var metadata:=FileAccess.open(pack_root.path_join("metadata.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id":"banner_streaming_test","name":"旗帜隔离测试"}));metadata.close()
	var source:=Paths.external_root().path_join("assets/banner_streetlamp/banner_streetlamp.glb")
	var library:=Library.new(folder.path_join("library"));var imported:=library.import_file(source)
	check(imported.get("ok",false),"real reviewed cloth-slot model imports natively")
	if not imported.get("ok",false):quit(1);return
	var doc:=Doc.new();var ids:Array=[]
	for i:int in 2:ids.append(doc.add_asset(imported.entry,Vector3(i*3,0,0)))
	var path:=folder.path_join("map.gltf");check(doc.save(path)==OK,"save isolated banner map")
	check(DirAccess.remove_absolute(source)==OK and DirAccess.remove_absolute(imported.entry.asset_path)==OK,"temporary original and imported GLBs removed")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=folder.path_join("drafts");root.add_child(editor);editor._safety.enabled=false
	await settle();await drain()
	var server:=TCPServer.new()
	while server.listen(port,"127.0.0.1")!=OK:port+=1
	server.stop();check(editor.start_mcp(port).ok,"start actual 3D HTTP")
	var discovery:=await rpc("tools/list")
	for spec:Dictionary in discovery.result.tools:
		if spec.name=="set_streetlamp_banner":check(not spec.inputSchema.properties.ids.has("maxItems"),"banner command has no arbitrary 256-selection cap")
	var image:=Image.create(256,128,false,Image.FORMAT_RGBA8);image.fill(Color(0,0,0,0))
	image.fill_rect(Rect2i(16,16,224,96),Color(.1,.5,.9,1));image.fill_rect(Rect2i(88,24,80,80),Color(.95,.8,.1,1))
	image.fill_rect(Rect2i(20,20,40,88),Color(1,.2,.1,.5))
	var picture:=folder.path_join("design.png");image.save_png(picture)
	var before:Array=editor._doc.records.duplicate(true)
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"shape":"rectangle","design":"flag","texture_path":picture}})
	var material:StandardMaterial3D=cloth(ids[0]).mesh.surface_get_material(0)
	check(material.detail_enabled and material.detail_albedo.is_class("StreamedTexture2D"),"first HTTP change uses source streamed texture as detail layer")
	check(cloth(ids[1]).mesh.surface_get_material(0).detail_albedo==material.detail_albedo,"both lamps share one source texture")
	check(material.albedo_texture==null,"no composed replacement albedo texture")
	check(editor._surface_texture_imports.snapshot().broker.producers==1,"one shared import producer for batch")
	check(editor._shared_preparation_ledger.snapshot().jobs==0,"model and texture preparation return shared budget")
	var changed:Array=editor._doc.records.duplicate(true)
	await call_tool("undo");check(equivalent(editor._doc.records,before),"undo whole banner batch")
	await call_tool("redo");check(equivalent(editor._doc.records,changed),"redo same immutable design")
	var invalid:=folder.path_join("broken.png");var file:=FileAccess.open(invalid,FileAccess.WRITE);file.store_string("invalid");file.close()
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"texture_path":invalid}},false)
	check(equivalent(editor._doc.records,changed),"failed background import changes no document records")
	await call_tool("select_objects",{"ids":ids})
	var panel:Node=editor._inspector.banner_panel
	check(panel.visible,"real inspector exposes banner controls")
	var external:=OS.get_environment("TEMP").path_join("external_banner.png");image.save_png(external)
	panel.image_mode="emblem";panel.import_image(external);await drain()
	check(editor._doc._find(ids[0]).banner.design=="emblem","UI file chooser stages external source asynchronously")
	material=cloth(ids[0]).mesh.surface_get_material(0)
	check(material.detail_albedo.is_class("StreamedTexture2D") and material.detail_mask!=null,"emblem preserves streamed source and independent coverage")
	check(material.detail_albedo.get_width()==256 and material.detail_albedo.get_height()==128,"original design dimensions preserved")
	var after:Array=editor._doc.records.duplicate(true)
	await call_tool("save_world");Paint.refresh_sources();Banner._meshes.clear();Banner._masks.clear()
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(equivalent(editor._doc.records,after),"native save/reopen preserves settings and source references without GLB")
	material=cloth(ids[0]).mesh.surface_get_material(0)
	check(material.detail_albedo.is_class("StreamedTexture2D"),"reopen remains streamed")
	check(cloth(ids[0]).get_meta("extras").rmmo_wind.anchor=="top","cloth keeps top wind anchor")
	await capture(cloth(ids[0]).mesh,material)
	await call_tool("set_streetlamp_banner",{"ids":ids,"settings":{"wind_enabled":false}})
	check(not cloth(ids[0]).get_meta("extras").has("rmmo_wind"),"wind can be disabled without losing design")
	check(editor._shared_preparation_ledger.snapshot().jobs==0,"final budget has no outstanding leases")
	await call_tool("select_objects",{"ids":ids})
	var packed:=await call_tool("save_prefab",{"name":"流式图案路灯","pack_root":pack_root})
	var before_place:Array=editor._doc.records.duplicate(true)
	if packed.has("asset_id"):
		await call_tool("place_asset",{"asset_id":packed.asset_id,"position":[12,0,0]})
		var placed_ids:Array=editor._selection_tools.ids.duplicate()
		check(placed_ids.size()==2,"native prefab restores two editable lamps without GLB")
		if placed_ids.size()==2:
			var first:StandardMaterial3D=cloth(placed_ids[0]).mesh.surface_get_material(0)
			check(first.detail_albedo.is_class("StreamedTexture2D") and first.detail_mask!=null,"prefab carries streamed source and emblem coverage")
			check(first.detail_albedo==cloth(placed_ids[1]).mesh.surface_get_material(0).detail_albedo,"placed lamps share the packaged source")
		var placed_records:Array=editor._doc.records.duplicate(true)
		await call_tool("undo");check(equivalent(editor._doc.records,before_place),"undo native textured lamp prefab")
		await call_tool("redo");check(equivalent(editor._doc.records,placed_records),"redo native textured lamp prefab")
		await call_tool("save_world");Paint.refresh_sources();Banner._meshes.clear();Banner._masks.clear()
		await call_tool("open_world",{"path":path,"discard_changes":true})
		check(equivalent(editor._doc.records,placed_records),"prefab and banner records survive cold reopen")
		if placed_ids.size()==2:check(cloth(placed_ids[0]).mesh.surface_get_material(0).detail_albedo.is_class("StreamedTexture2D"),"packaged banner remains streamed after reopen")
	editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("BANNER_STREAMING_HTTP ",JSON.stringify({"failures":failed,"fixture":folder}));quit(1 if failed else 0)

func capture(mesh:Mesh,material:StandardMaterial3D)->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1100,720);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.12,.15,.18)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-25,0);viewport.add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.4;viewport.add_child(camera);camera.position=Vector3(-.51,2.25,5);camera.look_at(Vector3(-.51,2.25,0))
	# Test-only legacy CPU compositor for a same-lighting visual comparison.
	var input:=Image.load_from_file(folder.path_join("design.png"));input.convert(Image.FORMAT_RGBA8)
	var composed:=Image.create(512,1024,false,Image.FORMAT_RGBA8);composed.fill(material.albedo_color)
	var rect:=Banner.emblem_rect(input.get_size());input.resize(rect.size.x,rect.size.y,Image.INTERPOLATE_LANCZOS)
	composed.blend_rect(input,Rect2i(Vector2i.ZERO,input.get_size()),rect.position);composed.generate_mipmaps()
	var legacy_material:StandardMaterial3D=material.duplicate();legacy_material.detail_enabled=false;legacy_material.albedo_color=Color.WHITE;legacy_material.albedo_texture=ImageTexture.create_from_image(composed)
	var legacy:=MeshInstance3D.new();legacy.mesh=mesh;legacy.position.x=-.95;legacy.material_override=legacy_material;viewport.add_child(legacy)
	for column:Array in [["Legacy CPU",25],["Streamed detail",395],["Streamed + wind",765]]:
		var label:=Label.new();label.text=column[0];label.position=Vector2(column[1],15);viewport.add_child(label)
	var normal:=MeshInstance3D.new();normal.mesh=mesh;normal.position.x=.1;viewport.add_child(normal)
	var windy:=MeshInstance3D.new();windy.mesh=mesh;windy.position.x=1.15;viewport.add_child(windy)
	var config:=preload("res://scripts/world3d/wind_response.gd").defaults();config.profile="cloth";config.anchor="top"
	preload("res://scripts/world3d/wind_response.gd").annotate_mesh(windy,config)
	var runtime:=preload("res://scripts/world3d/wind_runtime.gd").new();runtime.camera=camera;viewport.add_child(runtime)
	runtime.set_physics_process(false);runtime.set_shared_state_enabled(false);runtime.refresh()
	check(runtime.receivers.has(windy.get_instance_id()),"actual runtime admits and binds the streamed banner")
	var animated:ShaderMaterial=windy.get_surface_override_material(0)
	if animated==null:viewport.queue_free();await settle();return
	check(animated.get_shader_parameter("detail_albedo_tex")==material.detail_albedo,"wind shader keeps identical streamed design owner")
	check(animated.get_shader_parameter("detail_mask_tex")==material.detail_mask,"wind shader keeps coverage and UV2 placement")
	check(Wind.variant_key(material)!=Wind.variant_key(StandardMaterial3D.new()),"detail wind variant does not alias old plain shader")
	for frame:Array in [["still",2.4,false],["wind",2.4,true],["mid",7.2,false],["far",24.0,false]]:
		var stage:String=frame[0];camera.size=frame[1]
		runtime.advance(Vector3(8,0,0) if frame[2] else Vector3.ZERO,1.2)
		for i:int in 8:await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(folder.path_join("banner_standard_wind_"+stage+".png"))
	viewport.queue_free();await settle()
