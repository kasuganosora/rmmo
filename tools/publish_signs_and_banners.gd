extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Prefabs=preload("res://scripts/world_editor/prefab_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Wind=preload("res://scripts/world3d/wind_response.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const BASE="D:/code/rmmo_runtime"
const SIGNS=BASE+"/art_sources/mmorpg_shop_signs/burned_brackets_v3_20261007"
const FLAGS=BASE+"/art_sources/wall_guild_banners"
const OUT=BASE+"/review_artifacts/signs_banners_20261007"
const CATEGORY="牌匾/旗帜"
const EXISTING=["古铜旗幡路灯（可换旗·随风）","跨街布彩旗","写实朱红燕尾长旗·苏联五星镰刀锤子","蓝色金丝带彩柱","红色金丝带彩柱","原木金丝带彩柱"]

func inspect(model:Node, cloth:bool)->void:
	var receivers=0
	for mesh in Paint.meshes(model):
		if mesh.get_meta("extras",{}).has("rmmo_wind"):
			receivers+=1
			check(Wind.mesh_error(mesh).is_empty(),"cloth supports wind")
			Wind.register(mesh)
		for slot in mesh.mesh.get_surface_count():
			var mat=Wind.base_material(mesh,slot)
			check(mat is StandardMaterial3D,"native PBR material")
			if mat is StandardMaterial3D and mat.albedo_texture!=null:
				check(mat.normal_texture!=null and mat.roughness_texture!=null,"textured material preserves normal and roughness")
	check(receivers==(1 if cloth else 0),"cloth independent from rigid support")

func run()->void:
	create_timer(900).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	DirAccess.make_dir_recursive_absolute(OUT)
	var specs:Array=[]
	for a in JSON.parse_string(FileAccess.get_file_as_string(SIGNS+"/manifest.json")).assets:
		specs.append({"id":a.id,"source":SIGNS+"/"+a.id+".glb","hash":a.sha256,"triangles":a.triangles,"label":("写实烙画木牌·" if a.kind=="board" else "写实木挂架·")+a.label,"cloth":false})
	for a in JSON.parse_string(FileAccess.get_file_as_string(FLAGS+"/manifest.json")).assets:
		specs.append({"id":a.id,"source":FLAGS+"/models/"+a.id+".glb","hash":a.sha256,"triangles":a.export_triangles,"label":"写实"+a.label,"cloth":true})
	check(specs.size()==24,"21 sign modules and three missing flags")
	var directory=Paths.cache_directory("signs_banners_%d"%Time.get_ticks_usec())
	var local=Library.new(directory+"/assets")
	var vp=SubViewport.new();vp.size=Vector2i(640,640);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.25,.28,.30);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.65;vp.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,-25,0);sun.shadow_enabled=true;sun.light_energy=1.5;vp.add_child(sun)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	var wind=preload("res://scripts/world3d/wind_runtime.gd").new();vp.add_child(wind);wind.camera=cam
	for spec in specs:
		check(FileAccess.get_sha256(spec.source)==spec.hash,"approved source "+spec.id)
		var imported=local.import_file(spec.source);check(imported.ok,"native import "+spec.id)
		if not imported.ok:quit(1);return
		spec.entry=imported.entry
		var model=Library.instantiate_preview(imported.entry.asset_path);inspect(model,spec.cloth)
		var triangles=0
		for mesh in Paint.meshes(model):triangles+=mesh.mesh.get_faces().size()/3
		check(triangles==spec.triangles,"optimized triangles "+spec.id)
		vp.add_child(model)
		var bounds=Library.bounds_of(model);var center=bounds.get_center();var extent=maxf(bounds.size.x,bounds.size.y)
		cam.size=extent*1.25;cam.position=center+Vector3(extent*.08,extent*.10,extent*2.5);cam.look_at(center)
		wind.refresh()
		wind.advance(Vector3.ZERO,0.0)
		for frame in 10:await process_frame
		await RenderingServer.frame_post_draw
		var still=vp.get_texture().get_image();still.save_png(OUT+"/"+spec.id+".png")
		if spec.cloth:
			wind.advance(Vector3(7,0,2),.8)
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw
			var moving=vp.get_texture().get_image();moving.save_png(OUT+"/"+spec.id+"_wind.png")
			check(still.get_data()!=moving.get_data(),"rendered cloth wind response "+spec.id)
		model.queue_free();await settle()
	vp.queue_free();await settle()
	if failed:quit(1);return
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=local;editor._shared_assets=[Library.new(BASE+"/packs/default/assets")]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	var discovery=await rpc("tools/list")
	var listing_schema=discovery.result.tools.filter(func(t):return t.name=="list_assets")
	check(listing_schema.size()==1 and listing_schema[0].inputSchema.properties.has("category"),"3D category schema discovery")
	await call_tool("list_resource_packs")
	var published:Array=[]
	for i in specs.size():
		var spec=specs[i]
		await call_tool("place_asset",{"asset_id":Thumb.key_for(spec.entry),"position":[i*3,0,0]})
		var id=doc.records.back().uuid;doc._find(id).collision="none"
		await call_tool("select_objects",{"ids":[id]})
		var lib=Library.new(BASE+"/packs/default/assets")
		var existing=lib.entries.filter(func(e):return e.get("label","")==spec.label and e.has("prefab_path"))
		check(existing.size()<=1,"unique label before publication")
		if failed:quit(1);return
		var saved:Dictionary
		if existing.is_empty():saved=await call_tool("save_prefab",{"name":spec.label,"pack_root":BASE+"/packs/default"})
		else:saved={"entry":existing[0],"asset_id":Thumb.key_for(existing[0])}
		if not saved.has("entry"):quit(1);return
		DirAccess.make_dir_recursive_absolute(saved.entry.thumbnail_path.get_base_dir())
		check(DirAccess.copy_absolute(OUT+"/"+spec.id+".png",saved.entry.thumbnail_path)==OK,"individual native thumbnail")
		lib=Library.new(lib.directory)
		var payload=Prefabs.read(saved.entry);check(payload.ok,"portable prefab payload")
		var dependency=payload.records[0].asset_path
		check(FileAccess.get_sha256(dependency)==dependency.get_file().get_basename(),"content-addressed dependency")
		lib.entries=lib.entries.filter(func(e):return str(e.get("asset_path","")).simplify_path()!=dependency)
		for entry in lib.entries:
			if entry.get("prefab_path","")==saved.entry.prefab_path:entry.category=CATEGORY
		check(lib.save()==OK,"atomic catalog save and hidden dependency")
		saved.entry.category=CATEGORY;published.append({"id":spec.id,"entry":saved.entry,"triangles":spec.triangles,"source_hash":spec.hash,"cloth":spec.cloth})
		editor._shared_assets=[Library.new(lib.directory)]
		await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[i*3,0,10]})
		var count=doc.records.size();await call_tool("undo");check(doc.records.size()==count-1,"undo module placement");await call_tool("redo");check(doc.records.size()==count,"redo module placement")
		await call_tool("select_objects",{"ids":[id]})
		await call_tool("delete_selection")
	var lib=Library.new(BASE+"/packs/default/assets");var moved:Array=[]
	for entry in lib.entries:
		if entry.get("label","") in EXISTING:entry.category=CATEGORY;moved.append(entry.label)
	check(moved.size()==EXISTING.size(),"all existing flag assets and matching poles recategorized")
	check(lib.save()==OK,"atomic existing category migration")
	editor._shared_assets=[Library.new(lib.directory)]
	var listing=await call_tool("list_assets",{"category":CATEGORY,"limit":100})
	check(listing.total==30 and listing.categories.has(CATEGORY),"one category with 30 unique entries")
	check(listing.assets.all(func(e):return e.category==CATEGORY),"exact category filtering")
	editor._asset_category=CATEGORY;editor._query="";editor._refresh_palette()
	check(editor._palette_items.size()==listing.total,"UI and MCP category parity")
	check(editor._asset_category_picker.get_item_metadata(editor._asset_category_picker.selected)==CATEGORY,"visible category selector")
	var before=doc.recovery_snapshot()
	await call_tool("list_assets",{"category":12},false)
	await call_tool("place_asset",{"asset_id":"missing_sign_banner","position":[0,0,0]},false)
	check(doc.recovery_snapshot()==before,"invalid calls leave document unchanged")
	var none=await call_tool("list_assets",{"category":"missing-category"});check(none.total==0,"unknown category empty")
	var narrow=await call_tool("list_assets",{"category":CATEGORY,"query":"烙画"});check(narrow.total==18,"combined text/category search")
	var save_result=await call_tool("save_world")
	if not save_result.get("ok",false):quit(1);return
	var open_result=await call_tool("open_world",{"path":path})
	if not open_result.get("ok",false):quit(1);return
	doc=editor._doc
	check(doc.records.size()==24 and doc.missing_assets().is_empty(),"24 temporary placements survive save and reopen")
	for record in doc.records:
		check(record.collision=="none","nonblocking module preserved")
	editor.queue_free();await settle()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start.call_deferred(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"game async map load")
	if loaded[0]!=null:loaded[0].free()
	if is_instance_valid(loader):loader.queue_free()
	# save_prefab queues generic thumbnails; restore the legible front reviews
	# after the editor and its queue have finished.
	for row in published:
		check(DirAccess.copy_absolute(OUT+"/"+row.id+".png",row.entry.thumbnail_path)==OK,"final front-view catalog thumbnail")
	FileAccess.open(OUT+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"new_assets":published,"moved_existing":moved,"category":CATEGORY,"total":listing.total,"real_http":true,"user_maps_modified":false,"test_map":path},"\t"))
	print("SIGNS_BANNERS_PUBLICATION_FAILURES ",failed);quit(1 if failed else 0)
