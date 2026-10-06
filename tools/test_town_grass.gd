extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
const BASE="D:/code/rmmo_runtime"
var out=BASE+"/review_artifacts/town_grass"
var entries=[]
var manifest=[]
var shared_textures={}
func run()->void:
	DirAccess.make_dir_recursive_absolute(out);create_timer(900).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	manifest=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/town_grass/manifest.json"))
	var directory=Paths.external_root().path_join("__town_grass_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var meta=FileAccess.open(directory+"/metadata.json",FileAccess.WRITE);meta.store_string(JSON.stringify({"id":"town_grass_test","name":"草丛临时验收"}));meta.close()
	var lib=Library.new(directory+"/assets")
	for row in manifest:
		var result=lib.import_file(row.file);check(result.ok,"import "+row.id)
		if not result.ok:quit(1);return
		var model=Library.instantiate(result.entry.asset_path);var meshes=Paint.meshes(model)
		var first_mat=meshes[0].get_active_material(0) as StandardMaterial3D
		if shared_textures.has(row.kind):check(first_mat.albedo_texture==shared_textures[row.kind],"family textures shared across GLBs")
		else:shared_textures[row.kind]=first_mat.albedo_texture
		check(meshes.size()==3,"three volumetric LODs "+row.id)
		for m in meshes:
			check(m.mesh.get_surface_count()==1,"single material draw "+m.name)
			var mat=m.get_active_material(0) as StandardMaterial3D
			check(mat!=null and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and mat.cull_mode==BaseMaterial3D.CULL_DISABLED,"double sided clipped leaves")
			check(mat.albedo_texture!=null and mat.normal_texture!=null and mat.roughness_texture!=null,"PBR channels")
			var rough_image=mat.roughness_texture.get_image();var rough_sum=0.
			for sample in 10:rough_sum+=rough_image.get_pixel(sample*rough_image.get_width()/10,rough_image.get_height()/2).g
			check(rough_sum/10.>.4,"Quixel R exported to ORM G roughness")
			check(rough_image.get_width()<=2048,"runtime PBR stays 2K")
			check(Response.mesh_error(m).is_empty(),"wind compatible material")
		check(meshes[0].get_aabb().size.y>.08,"upright grass height")
		model.free();entries.append({"id":row.id,"entry":result.entry,"sha256":FileAccess.get_sha256(row.file)})
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temp save")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false;editor._assets=lib;editor._shared_assets=[]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP server")
	var discovery=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="place_asset"),"current 3D tools")
	for index in [0,3]:
		var key=preload("res://scripts/world_editor/asset_thumbnails.gd").key_for(entries[index].entry)
		await call_tool("place_asset",{"asset_id":key,"position":[index*.4,0,0]})
	var before=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"nonexistent_grass","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement atomic")
	await call_tool("undo");check(doc.records.size()==1,"undo placement");await call_tool("redo");check(doc.records.size()==2,"redo placement")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==2 and doc.missing_assets().is_empty(),"save reopen dependencies")
	await call_tool("select_objects",{"ids":[doc.records[0].uuid]});await call_tool("list_resource_packs")
	var prefab=await call_tool("save_prefab",{"name":"矮草验收预制件","pack_root":directory})
	await call_tool("place_asset",{"asset_id":prefab.asset_id,"position":[2,0,0]})
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==3 and doc.missing_assets().is_empty(),"prefab save reopen")
	for r in doc.records:
		var n=doc._asset(r);check(Paint.meshes(n).filter(func(m):return m.visibility_range_end>0).size()==3,"LOD metadata persists");n.free()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path);var loaded:Array=await loader.finished
	check(loaded[0]!=null,"game runtime load")
	if loaded[0]!=null:
		var host=Node3D.new();root.add_child(host);host.add_child(loaded[0]);preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3.ZERO)
		var meshes:Array=loaded[0].get_meta("stream_meshes",{}).values();check(meshes.filter(func(m):return is_instance_valid(m) and m.get_meta("extras",{}).get("rmmo_grass",false)).size()==9,"runtime keeps three grass LODs per instance")
		host.queue_free();await settle()
	if is_instance_valid(loader):loader.queue_free()
	await render_review()
	var f=FileAccess.open(out+"/validation.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failed,"entries":entries,"real_http":true,"test_map":path,"user_maps_modified":false},"\t"));f.close()
	# De-register only this test pack; keep its evidence and immutable dependencies.
	DirAccess.rename_absolute(directory+"/metadata.json",directory+"/metadata.test.json")
	print("TOWN_GRASS_FAILURES ",failed);editor.queue_free();await settle();quit(1 if failed else 0)
func capture(vp:SubViewport,name_:String)->void:
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/"+name_+".png")
func render_review()->void:
	var vp=SubViewport.new();vp.size=Vector2i(1400,850);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var environment=WorldEnvironment.new();environment.environment=Environment.new();var env=environment.environment;env.background_mode=Environment.BG_COLOR;env.background_color=Color(.4,.5,.6);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_sky_contribution=0;env.ambient_light_color=Color(.82,.89,1);env.ambient_light_energy=1.;vp.add_child(environment)
	var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-35,0);light.shadow_enabled=true;light.light_energy=2.2;vp.add_child(light)
	var floor_=MeshInstance3D.new();floor_.mesh=PlaneMesh.new();floor_.mesh.size=Vector2(70,70);var ground=StandardMaterial3D.new();ground.albedo_color=Color(.35,.32,.24);ground.roughness=1.;floor_.material_override=ground;floor_.position.y=-.012;vp.add_child(floor_)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=3.6;cam.position=Vector3(3,3.2,5);vp.add_child(cam);cam.look_at(Vector3(0,.1,0))
	var gallery=Node3D.new();vp.add_child(gallery)
	for mode in ["baseline","optimized"]:
		for i in manifest.size():
			var row=manifest[i];var n=Library.instantiate_preview(row.baseline) if mode=="baseline" else Library.instantiate(entries[i].entry.asset_path);gallery.add_child(n)
			n.position=Vector3((i%4-1.5)*1.15,0,(i/4-1)*1.1)
			for m in Paint.meshes(n):
				if mode=="optimized" and not "LOD0" in m.name:m.visible=false
				m.visibility_range_begin=0;m.visibility_range_end=0
		await capture(vp,mode+"_gallery")
		for n in gallery.get_children():n.queue_free()
		await process_frame
	# Individual same-camera views used both for validation and catalogue thumbnails.
	cam.size=1.2;cam.position=Vector3(1,.65,1.3);cam.look_at(Vector3(0,.14,0))
	for i in entries.size():
		var n=Library.instantiate(entries[i].entry.asset_path);gallery.add_child(n)
		for m in Paint.meshes(n):m.visible="LOD0" in m.name;m.visibility_range_begin=0;m.visibility_range_end=0
		await capture(vp,entries[i].id);n.queue_free();await process_frame
	for index in [0,3]:
		for mode in ["baseline","optimized"]:
			var n=Library.instantiate_preview(manifest[index].baseline) if mode=="baseline" else Library.instantiate(entries[index].entry.asset_path);gallery.add_child(n)
			for m in Paint.meshes(n):
				if mode=="optimized":m.visible="LOD0" in m.name
				m.visibility_range_begin=0;m.visibility_range_end=0
			cam.size=.8;cam.position=Vector3(.8,.28,1.2);cam.look_at(Vector3(0,.14,0));await capture(vp,entries[index].id+"_"+mode+"_side");n.queue_free();await process_frame
	# Dense mixture: bounded distance rendering, native wind and shared source meshes.
	cam.projection=Camera3D.PROJECTION_PERSPECTIVE;cam.fov=60;cam.position=Vector3(0,1.3,6);cam.look_at(Vector3(0,.25,-6))
	for i in 400:
		var n=Library.instantiate(entries[(i*7)%entries.size()].entry.asset_path);gallery.add_child(n);n.position=Vector3((i%20-10)*.55,0,-(i/20)*.7);n.rotation.y=i*2.399963;n.scale=Vector3.ONE*(.8+(i%5)*.08)
		for mesh in Paint.meshes(n):Response.register(mesh)
	var wind=preload("res://scripts/world3d/wind_runtime.gd").new();vp.add_child(wind);wind.camera=cam;wind.set_physics_process(false);await physics_frame;wind.refresh();wind.advance(Vector3(8,0,2),1.)
	check(wind.receivers.size()>0,"native wind receivers bind");check(wind.receivers.values().all(func(r):return r.materials.size()==1),"one wind material per receiver")
	await capture(vp,"mixture_wind_a");wind.advance(Vector3(8,0,2),2.);await capture(vp,"mixture_wind_b")
	var perf={"instances":400,"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"active_wind":wind.active_rows.size(),"bound_wind":wind.receivers.size()}
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
	var gpu=[];var update=[]
	for i in 100:
		var begin=Time.get_ticks_usec();wind.advance(Vector3(8,0,2),i*.016);var cost=(Time.get_ticks_usec()-begin)/1000.;await process_frame
		if i>=40:gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()));update.append(cost)
	gpu.sort();update.sort();perf.gpu_median_ms=gpu[30];perf.wind_update_median_ms=update[30]
	var f=FileAccess.open(out+"/density.json",FileAccess.WRITE);f.store_string(JSON.stringify(perf,"\t"));f.close()
	cam.position=Vector3(0,.65,1.8);cam.look_at(Vector3(0,.1,-2.5));wind.refresh();await capture(vp,"mixture_day_close")
	light.light_energy=0;env.ambient_light_energy=.035;await capture(vp,"mixture_night")
	wind.queue_free();vp.queue_free();await settle()
