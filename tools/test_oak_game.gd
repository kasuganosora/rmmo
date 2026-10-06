extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Net=preload("res://scripts/net/net.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/street_oak_game"
func run()->void:
	create_timer(600).timeout.connect(func():quit(2))
	rpc_timeout_ms=30000
	var spec:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/assets/street_oak_game/manifest.json"))[0]
	var directory:=Paths.cache_directory("oak_game_test_%d"%Time.get_ticks_usec())
	var lib:=Library.new(directory+"/assets")
	var imported:Dictionary=lib.import_file(spec.file)
	check(imported.ok,"oak PBR imported")
	if not imported.ok:quit(1);return
	var model:=Library.instantiate_preview(imported.entry.asset_path)
	var meshes:=Paint.meshes(model);var triangles:=0;var masked:=0
	for mesh in meshes:
		for s in mesh.mesh.get_surface_count():
			var mat:=mesh.get_active_material(s) as StandardMaterial3D
			check(mat!=null and mat.albedo_texture!=null and mat.normal_texture!=null,"portable bark and leaf PBR")
			if mat!=null and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				masked+=1;check(mat.cull_mode==BaseMaterial3D.CULL_DISABLED and mat.backlight_enabled,"two-sided leaf transmission")
			var a:=mesh.mesh.surface_get_arrays(s);triangles+=a[Mesh.ARRAY_INDEX].size()/3 if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size()/3
	check(triangles==int(spec.stored_triangles) and masked==3,"three real LOD meshes and exact counts")
	check(meshes.size()==4,"one trunk plus three shared-material canopy LODs")
	model.free()
	var doc:=Doc.new();var path:=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	Net.session().world3d_editor_doc=doc;Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=lib;editor._shared_assets=[]
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"loopback HTTP MCP")
	var discovered:=await rpc("tools/list");check(discovered.result.tools.any(func(t):return t.name=="place_asset"),"native 3D discovery")
	var listing:=await call_tool("list_assets",{"query":"oak_riverside"});check(listing.assets.size()==1,"oak discoverable")
	var before:=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"missing_oak","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement atomic")
	await call_tool("place_asset",{"asset_id":listing.assets[0].asset_id,"position":[0,0,0]});check(doc.records.size()==1,"oak placed")
	await call_tool("undo");check(doc.records.is_empty(),"oak undo");await call_tool("redo");check(doc.records.size()==1,"oak redo")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==1 and doc.missing_assets().is_empty(),"save reopen retains dependencies")
	var built:=doc._asset(doc.records[0]);check(Paint.meshes(built).filter(func(m):return m.get_meta("extras",{}).has("rmmo_wind")).size()==2,"wind survives reopen")
	check(Paint.meshes(built).filter(func(m):return m.get_meta("extras",{}).has("rmmo_visibility_range")).size()==3,"LOD metadata survives reopen");built.free()
	editor.queue_free();await settle()
	var vp:=SubViewport.new();vp.size=Vector2i(1000,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.38,.42,.44);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.7;env.environment.ambient_light_sky_contribution=0.;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_energy=2.;sun.shadow_enabled=true;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(100,100);floor.mesh=plane;var fm:=StandardMaterial3D.new();fm.albedo_color=Color(.34,.35,.30);fm.roughness=1.;floor.material_override=fm;vp.add_child(floor)
	var cam:=Camera3D.new();vp.add_child(cam);cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=11.8;cam.position=Vector3(14,11,20);cam.look_at_from_position(cam.position,Vector3(0,4.2,0))
	model=Library.instantiate_preview(imported.entry.asset_path);vp.add_child(model)
	var ranged:=Paint.meshes(model).filter(func(m):return m.get_meta("extras",{}).has("rmmo_visibility_range"))
	for level in 3:
		for mesh in ranged:
			mesh.visible=mesh.name.contains("LOD"+str(level));mesh.visibility_range_begin=0.;mesh.visibility_range_end=0.
		for i in 24:await process_frame
		await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+"/runtime_lod_"+str(level)+".png")
	for mesh in ranged:mesh.visible=true
	preload("res://scripts/world3d/asset_visibility_range.gd").apply(model)
	cam.projection=Camera3D.PROJECTION_PERSPECTIVE;cam.fov=60
	for distance in [15.,30.,70.]:
		cam.position=Vector3(0,4.3,distance);cam.look_at(Vector3(0,4.3,0))
		for i in 20:await process_frame
		await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+"/runtime_distance_"+str(int(distance))+".png")
	var wind:=preload("res://scripts/world3d/wind_runtime.gd").new();vp.add_child(wind);wind.camera=cam
	for mesh in Paint.meshes(model):preload("res://scripts/world3d/wind_response.gd").register(mesh)
	wind.refresh();check(wind.receivers.size()==2,"two LOD wind receivers")
	cam.position=Vector3(0,4.3,15);cam.look_at(Vector3(0,4.3,0));wind.advance(Vector3(3,0,0),1.)
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+"/runtime_wind.png")
	# Reuse one imported mesh/material set. No duplicate imports or full-map writes.
	var prototype:=Library.instantiate_preview(imported.entry.asset_path)
	for i in 31:
		var copy:=prototype.duplicate() as Node3D;vp.add_child(copy);copy.position=Vector3((i%6-2)*12.,0.,-12.-(i/6)*13.)
		for mesh in Paint.meshes(copy):preload("res://scripts/world3d/wind_response.gd").register(mesh)
	prototype.free()
	wind.refresh();cam.position=Vector3(0,8,24);cam.look_at(Vector3(0,4,-25))
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
	var gpu:Array=[]
	for i in 80:
		wind.advance(Vector3(3,0,0),1./60.);await process_frame;await RenderingServer.frame_post_draw
		if i>=30:gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	gpu.sort()
	var performance:={"instances":32,"gpu_median_ms":gpu[25],"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"note":"1000x1000 MSAA4 TAA synthetic grove, not full-town FPS"}
	vp.get_texture().get_image().save_png(OUT+"/runtime_grove.png")
	var result:={"failures":failed,"entry":imported.entry,"triangles":triangles,"lod_triangles":spec.lod_triangles,"sha256":FileAccess.get_sha256(spec.file),"temporary_map":path,"real_http":true,"published":false,"performance":performance}
	FileAccess.open(OUT+"/validation.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("OAK_GAME_FAILURES ",failed);quit(0 if failed==0 else 1)
