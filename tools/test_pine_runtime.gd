extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Net=preload("res://scripts/net/net.gd")
const BASE="D:/code/rmmo_runtime"
var rpc_latencies:Dictionary={}
func game_cards()->bool:return OS.get_cmdline_user_args().has("--game-cards")
func revision_suffix()->String:
	if OS.get_cmdline_user_args().has("--game-cards"):return "_game"
	return "_fine" if OS.get_cmdline_user_args().has("--fine-clusters") else ""
func call_tool(name_:String,args:Dictionary={},expected_ok:bool=true)->Dictionary:
	var start:=Time.get_ticks_msec();var result:=await super.call_tool(name_,args,expected_ok)
	rpc_latencies[name_]=maxi(int(rpc_latencies.get(name_,0)),Time.get_ticks_msec()-start)
	return result
func check(ok:bool,label:String)->void:
	super.check(ok,label)
	var progress_path:=BASE+"/review_artifacts/pine_dense_v3"+revision_suffix()+"/progress.log"
	var progress:=FileAccess.open(progress_path,FileAccess.READ_WRITE) if FileAccess.file_exists(progress_path) else FileAccess.open(progress_path,FileAccess.WRITE)
	if progress!=null:progress.seek_end();progress.store_line(("PASS: " if ok else "FAIL: ")+label);progress.close()
func run()->void:
	create_timer(600).timeout.connect(func():quit(2))
	rpc_timeout_ms=30000
	var out:=BASE+"/review_artifacts/pine_dense_v3"+revision_suffix()
	DirAccess.make_dir_recursive_absolute(out)
	var directory:=Paths.cache_directory("pine_dense_test_%d"%Time.get_ticks_usec())
	var lib:=Library.new(directory+"/assets")
	var specs:Variant=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/assets/baltic_pine_dense_v3"+revision_suffix()+"/manifest.json"))
	var reused:Dictionary={}
	if OS.get_cmdline_user_args().has("--reuse-imports"):
		var prior:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(out+"/validation.json"))
		for row in prior.assets:reused[row.id]=row.entry
	var rows:Array=[]
	for spec in specs:
		var imported:Dictionary
		if reused.has(spec.id):
			var entry:Dictionary=reused[spec.id].duplicate(true);var file:String=entry.asset_path
			var valid:=file.replace("\\","/").begins_with(BASE+"/cache/world3d/") and FileAccess.get_sha256(file)==file.get_file().get_basename()
			check(valid,"reuse immutable asset hash "+spec.id)
			if not valid:quit(1);return
			lib.entries.append(entry);imported={"ok":true,"entry":entry}
		else:imported=lib.import_file(spec.file)
		check(imported.ok,"import "+spec.id)
		if not imported.ok:continue
		var model:=Library.instantiate_preview(imported.entry.asset_path)
		var meshes:=Paint.meshes(model);var triangles:=0;var masked:=0
		for mesh in meshes:
			for s in mesh.mesh.get_surface_count():
				var mat:=mesh.get_active_material(s) as StandardMaterial3D
				check(mat!=null and mat.albedo_texture!=null,"portable PBR "+spec.id)
				if mat!=null and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					masked+=1
					if not game_cards() or not mat.resource_name.contains("LOD2"):check(mat.normal_enabled and mat.normal_texture!=null,"needle cluster normals")
					if not revision_suffix().is_empty() and (not game_cards() or not mat.resource_name.contains("LOD2")):check(mat.backlight_enabled,"needle transmission restored")
				var a:=mesh.mesh.surface_get_arrays(s);triangles+=a[Mesh.ARRAY_INDEX].size()/3 if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size()/3
		check(masked==(3 if game_cards() else 5) and triangles==int(spec.triangles) and triangles<(65000 if game_cards() else 5000000),"small-cluster foliage budget "+spec.id)
		if game_cards():
			var ranged:=meshes.filter(func(m):return m.get_meta("extras",{}).has("rmmo_visibility_range"))
			check(ranged.size()==3,"three authored LODs")
			for m in ranged:
				var raw:Dictionary=m.get_meta("extras").rmmo_visibility_range
				check(m.visibility_range_begin==float(raw.begin) and m.visibility_range_end==float(raw.end),"native LOD ranges applied")
		check(meshes.any(func(m):return m.get_meta("extras",{}).get("rmmo_collision","")=="none"),"foliage has no collision")
		check(meshes.any(func(m):return m.get_meta("extras",{}).get("rmmo_collision","")=="block"),"solid trunk collision")
		rows.append({"id":spec.id,"label":spec.label,"entry":imported.entry,"triangles":triangles,"lod_triangles":spec.get("lod_triangles",[])});model.free()
	var doc:=Doc.new();var path:=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	Net.session().world3d_editor_doc=doc;Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=lib;editor._shared_assets=[]
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP server")
	var discovered:=await rpc("tools/list");check(discovered.result.tools.any(func(t):return t.name=="place_asset"),"3D placement discovery")
	var listing:=await call_tool("list_assets",{"query":"pine_dense"});check(listing.assets.size()==3,"three trees discoverable")
	var before:=doc.recovery_snapshot()
	await call_tool("place_asset",{"asset_id":"missing_pine","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement atomic")
	await call_tool("place_asset",{"asset_id":listing.assets[0].asset_id,"position":[0,0,0]})
	check(doc.records.size()==1,"place actual pine");await call_tool("undo");check(doc.records.is_empty(),"undo pine");await call_tool("redo");check(doc.records.size()==1,"redo pine")
	var id:String=doc.records[0].uuid
	var object:=await call_tool("get_object",{"id":id});check(not object.get("wind_meshes",[]).is_empty(),"wind available through MCP")
	await call_tool("set_object_properties",{"ids":[id],"wind":{"profile":"off"}})
	var built:=doc._asset(doc._find(id));check(Paint.meshes(built).all(func(m):return not m.get_meta("extras",{}).has("rmmo_wind")),"wind disable");built.free();await call_tool("undo")
	await call_tool("set_environment",{"time_hours":12,"time_speed":0,"wind_speed":3})
	editor._weather.wind_objects.refresh()
	check(not editor._weather.wind_objects.receivers.is_empty(),"real GPU wind receiver bound")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==1 and doc.missing_assets().is_empty(),"save reopen dependencies")
	built=doc._asset(doc.records[0]);check(Paint.meshes(built).any(func(m):return m.get_meta("extras",{}).has("rmmo_wind")),"wind retained on reopen");built.free()
	if not revision_suffix().is_empty():
		built=doc._asset(doc.records[0]);var transmitted:=0
		for mesh in Paint.meshes(built):
			for slot in mesh.mesh.get_surface_count():
				var mat:=mesh.get_active_material(slot) as StandardMaterial3D
				if mat!=null and mat.backlight_enabled:transmitted+=1
		check(transmitted==(2 if game_cards() else 5),"leaf transmission retained on save reopen")
		if game_cards():
			var ranged:=Paint.meshes(built).filter(func(m):return m.get_meta("extras",{}).has("rmmo_visibility_range"))
			check(ranged.size()==3 and ranged.all(func(m):return m.visibility_range_begin==float(m.get_meta("extras").rmmo_visibility_range.begin)),"LOD retained on save reopen")
		built.free()
	editor.queue_free();await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"runtime load")
	if loaded[0]!=null:
		var host:=Node3D.new();root.add_child(host);host.add_child(loaded[0]);preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3.ZERO)
		check(not loaded[0].get_meta("stream_bodies",{}).is_empty(),"runtime trunk collision")
		check(loaded[0].get_meta("stream_library",[]).any(func(s):return s.get("extras",{}).has("rmmo_wind")),"runtime wind metadata")
		if game_cards():
			var ranged:Array=loaded[0].get_meta("stream_meshes",{}).values().filter(func(m):return is_instance_valid(m) and m.get_meta("extras",{}).has("rmmo_visibility_range"))
			check(not ranged.is_empty() and ranged.all(func(m):return m.visibility_range_begin==float(m.get_meta("extras").rmmo_visibility_range.begin) and m.visibility_range_end==float(m.get_meta("extras").rmmo_visibility_range.end)),"streamed instances retain LOD ranges")
		host.queue_free();await settle()
	if is_instance_valid(loader):loader.queue_free()
	var vp:=SubViewport.new();vp.size=Vector2i(1200,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.32,.36,.39);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.6;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);floor.mesh=plane;vp.add_child(floor)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	var perf:={}
	for row in rows:
		var model:=Library.instantiate_preview(row.entry.asset_path);vp.add_child(model);var bounds:=Library.bounds_of(model);var center:=bounds.get_center()
		cam.size=maxf(bounds.size.x,bounds.size.y)*1.2;cam.position=center+Vector3(14,6,20);cam.look_at(center)
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/"+row.id+".png")
		if row.id=="pine_dense_mature":
			cam.size=3.;cam.position=Vector3(6,8,10);cam.look_at(Vector3(0,7,0))
			for i in 8:await process_frame
			await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/needles_close.png")
			var wind:=preload("res://scripts/world3d/wind_runtime.gd").new();vp.add_child(wind);wind.camera=cam
			for mesh in Paint.meshes(model):preload("res://scripts/world3d/wind_response.gd").register(mesh)
			wind.refresh();check(wind.receivers.size()==(2 if game_cards() else 1),"isolated needle wind shader bound")
			if not revision_suffix().is_empty():
				var active_leaf:=Paint.meshes(model).filter(func(m):return m.get_meta("extras",{}).has("rmmo_leaf_backlight"))[0] as MeshInstance3D
				check(active_leaf.get_active_material(0).get_shader_parameter("backlight_enabled")==true,"wind shader retains leaf transmission")
			wind.advance(Vector3(3,0,0),0.5)
			for i in 4:await process_frame
			await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/wind_close.png")
			wind.queue_free();await process_frame
			if game_cards():
				for level in 3:
					for mesh in Paint.meshes(model):
						if mesh.has_meta("extras") and mesh.get_meta("extras").has("rmmo_visibility_range"):
							var begin:float=mesh.get_meta("extras").rmmo_visibility_range.begin
							mesh.visible=is_equal_approx(begin,[0.,35.,85.][level]);mesh.visibility_range_begin=0.;mesh.visibility_range_end=0.
					cam.size=13.;cam.position=Vector3(-15,8,20);cam.look_at(Vector3(0,5,0))
					for i in 16:await process_frame
					await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/lod_"+str(level)+".png")
				for mesh in Paint.meshes(model):mesh.visible=true
				preload("res://scripts/world3d/asset_visibility_range.gd").apply(model)
			if game_cards():
				cam.projection=Camera3D.PROJECTION_PERSPECTIVE;cam.fov=60
				for distance in [30.,40.,80.,90.]:
					cam.position=Vector3(0,5,distance);cam.look_at(Vector3(0,5,0))
					for i in 24:await process_frame
					await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/distance_"+str(int(distance))+"m.png")
				cam.projection=Camera3D.PROJECTION_ORTHOGONAL
			var copies:Array=[]
			for i in 15:
				var copy:=model.duplicate() as Node3D;copy.position=Vector3((i%4)*7,0,((i/4)+1)*7);vp.add_child(copy);copies.append(copy)
			cam.size=40;cam.position=Vector3(35,25,45);cam.look_at(Vector3(10,4,12))
			for i in 10:await process_frame
			var times:Array=[]
			for i in 60:
				var start:=Time.get_ticks_usec();await RenderingServer.frame_post_draw;times.append((Time.get_ticks_usec()-start)/1000.0);await process_frame
			times.sort();perf={"trees":16,"total_stored_tree_triangles":int(row.triangles)*16,"lod_triangles_per_tree":row.get("lod_triangles",[]),"frame_wait_median_ms":times[30],"frame_wait_p95_ms":times[57],"note":"Private desktop test, includes engine scheduling; not a GPU-only timer"}
			await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(out+"/sixteen_trees.png")
			for copy in copies:copy.queue_free()
			await process_frame
		model.queue_free();await process_frame
	var f:=FileAccess.open(out+"/validation.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failed,"assets":rows,"real_http":true,"user_maps_modified":false,"performance":perf,"rpc_max_ms":rpc_latencies,"reused_immutable_imports":not reused.is_empty(),"map_path":path},"\t"));f.close()
	print("PINE_RUNTIME_FAILURES ",failed);quit(1 if failed else 0)
