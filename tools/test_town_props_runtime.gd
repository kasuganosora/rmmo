extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Net=preload("res://scripts/net/net.gd")
const BASE="D:/code/rmmo_runtime"
func run()->void:
	create_timer(900).timeout.connect(func():quit(2))
	var out:=BASE+"/review_artifacts/town_props_20261006"
	DirAccess.make_dir_recursive_absolute(out)
	var directory:=Paths.cache_directory("town_props_test_%d"%Time.get_ticks_usec())
	if not OS.get_environment("RMMO_PROP_TEST_REUSE").is_empty():directory=OS.get_environment("RMMO_PROP_TEST_REUSE")
	var lib:=Library.new(directory+"/assets")
	var specs:Variant=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/town_props_20261006/manifest.json"))
	var rows:Array=[]
	for spec in specs:
		var cached:=lib.entries.filter(func(e):return e.get("label","")==spec.id)
		var imported:=lib.import_file(cached[0].asset_path if not cached.is_empty() else spec.file);check(imported.ok,"import "+spec.id)
		if not imported.ok:continue
		var model:=Library.instantiate_preview(imported.entry.asset_path)
		var bounds:=Library.bounds_of(model);var meshes:=Paint.meshes(model);var triangles:=0
		for mesh in meshes:
			for s in mesh.mesh.get_surface_count():
				check(mesh.mesh.surface_get_material(s)!=null,"material "+spec.id+"/"+mesh.name)
				var a:=mesh.mesh.surface_get_arrays(s);triangles+=a[Mesh.ARRAY_INDEX].size()/3 if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size()/3
		check(bounds.size.is_finite() and bounds.size.y>0 and triangles>0,"finite actual mesh "+spec.id)
		rows.append({"id":spec.id,"triangles":triangles,"mesh_count":meshes.size(),"entry":imported.entry})
		model.free()
	var doc:=Doc.new();var path:=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	Net.session().world3d_editor_doc=doc;Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=lib;editor._shared_assets=[]
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP server")
	var discovered:=await rpc("tools/list");check(discovered.result.tools.any(func(t):return t.name=="place_asset"),"3D placement tool discovery")
	var listing:=await call_tool("list_assets",{"query":"town_festival_posts_bunting"});check(listing.assets.size()==1,"new bunting discoverable via HTTP")
	var before:=doc.recovery_snapshot()
	await call_tool("place_asset",{"asset_id":"missing_town_prop","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement has no side effects")
	await call_tool("place_asset",{"asset_id":listing.assets[0].asset_id,"position":[0,2,0]})
	check(doc.records.size()==1,"place actual packaged bunting")
	await call_tool("undo");check(doc.records.is_empty(),"placement undo")
	await call_tool("redo");check(doc.records.size()==1,"placement redo")
	var id:String=doc.records[0].uuid
	var object:=await call_tool("get_object",{"id":id});check(not object.get("wind_meshes",[]).is_empty(),"wind meshes exposed through existing MCP")
	await call_tool("set_object_properties",{"ids":[id],"wind":{"profile":"off"}})
	var built:=doc._asset(doc._find(id));check(not Paint.meshes(built).is_empty() and Paint.meshes(built).all(func(n):return not n.get_meta("extras",{}).has("rmmo_wind")),"explicit wind-off removes imported defaults");built.free()
	await call_tool("undo")
	listing=await call_tool("list_assets",{"query":"small_wall_lantern"})
	if listing.get("assets",[]).is_empty():check(false,"isolated lantern shelf exists");quit(1);return
	await call_tool("place_asset",{"asset_id":listing.assets[0].asset_id,"position":[3,2,0]})
	await call_tool("set_environment",{"preset":"night","time_hours":22,"time_speed":0})
	editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.fixtures.values().any(func(r):return r.warm and r.lit and r.light.visible and r.light.light_color.r>r.light.light_color.b),"wall lantern emits warm light from real game clock")
	await call_tool("set_environment",{"time_hours":12})
	editor._weather.streetlamps.refresh()
	check(editor._weather.streetlamps.fixtures.values().all(func(r):return not r.lit),"daytime wall lantern light switches off")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==2 and doc.missing_assets().is_empty(),"save and reopen packaged dependencies")
	editor.queue_free();await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished
	check(loaded[0]!=null,"game runtime loader reads saved props")
	if loaded[0]!=null:
		var host:=Node3D.new();root.add_child(host);host.add_child(loaded[0])
		preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3.ZERO)
		check(not loaded[0].get_meta("stream_bodies",{}).is_empty(),"runtime creates collision bodies")
		check(loaded[0].get_meta("stream_library",[]).any(func(s):return s.get("extras",{}).has("rmmo_wind")),"game stream retains authored cloth wind metadata")
		host.queue_free();await settle()
	if is_instance_valid(loader):loader.queue_free()
	var viewport:=SubViewport.new();viewport.size=Vector2i(1200,900);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.22,.25,.29);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.65;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;viewport.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);floor.mesh=plane;viewport.add_child(floor)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;viewport.add_child(cam)
	for row in rows:
		if not row.id in ["town_planters_01_wall_hedge","town_market_stalls_03_potion_vendor","town_festival_posts_bunting","small_wall_lantern"]:continue
		var model:=Library.instantiate_preview(row.entry.asset_path);viewport.add_child(model);var bounds:=Library.bounds_of(model);var center:=bounds.get_center()
		cam.size=maxf(bounds.size.x,bounds.size.y)*1.4;cam.position=center+Vector3(4,2.5,6);cam.look_at(center)
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(out+"/"+row.id+".png")
		model.queue_free();await process_frame
	var report:={"failures":failed,"assets":rows,"real_http":true,"user_maps_modified":false}
	var f:=FileAccess.open(out+"/validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("TOWN_PROPS_TEST_FAILURES ",failed);quit(1 if failed else 0)
