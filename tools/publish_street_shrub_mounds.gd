extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const BASE="D:/code/rmmo_runtime"
const ART=BASE+"/art_sources/street_shrub_mounds/game_lod"
const OUT=BASE+"/review_artifacts/street_shrub_mounds"
const LABELS=["写实大团灌木·圆团","写实大团灌木·横向铺展","写实大团灌木·高冠"]
const Wind=preload("res://scripts/world3d/wind_response.gd")
func inspect(model:Node)->void:
	var meshes=Paint.meshes(model)
	check(meshes.size()==3,"two foliage LOD meshes and shared stems")
	var leaves=meshes.filter(func(m):return m.get_meta("extras",{}).has("rmmo_wind"))
	check(leaves.size()==2,"two foliage wind receivers")
	for m in leaves:
		check(Wind.mesh_error(m).is_empty(),"native wind compatible")
		var material=Wind.base_material(m,0)
		check(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,"leaf alpha mask")
		check(material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null,"scanned leaf PBR")
		var spec=m.get_meta("extras",{}).get("rmmo_visibility_range",{})
		check(not spec.is_empty(),"LOD range metadata")
		check(m.visibility_range_begin==float(spec.get("begin",-1)) and m.visibility_range_end==float(spec.get("end",-1)),"native LOD ranges applied")
		check(m.visibility_range_begin==0 or m.visibility_range_begin==20,"20 metre transition")
	for m in meshes:check(m.get_meta("extras",{}).get("rmmo_collision","")=="none","nonblocking foliage and stems")

func run()->void:
	create_timer(600).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	DirAccess.make_dir_recursive_absolute(OUT)
	var specs=JSON.parse_string(FileAccess.get_file_as_string(ART+"/manifest.json")).assets
	if specs.size()!=3:quit(1);return
	var directory=Paths.cache_directory("street_shrubs_%d"%Time.get_ticks_usec())
	var local=Library.new(directory+"/assets");var rows:Array=[]
	var vp=SubViewport.new();vp.size=Vector2i(800,600);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.25,.28,.26);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.65;vp.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.shadow_enabled=true;sun.light_energy=1.5;vp.add_child(sun)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	for i in specs.size():
		var spec=specs[i];var file=ART+"/"+spec.id+".glb"
		check(FileAccess.get_sha256(file)==spec.sha256,"approved file hash "+spec.id)
		var imported=local.import_file(file);check(imported.ok,"native import "+spec.id)
		if not imported.ok:quit(1);return
		var model=Library.instantiate_preview(imported.entry.asset_path);var meshes=Paint.meshes(model);var tri=0
		inspect(model)
		for mesh in meshes:tri+=mesh.mesh.get_faces().size()/3
		check(tri==spec.near_triangles+spec.far_triangles-180,"combined LOD geometry count")
		vp.add_child(model);var bounds=Library.bounds_of(model);var center=bounds.get_center()
		cam.size=maxf(bounds.size.y,maxf(bounds.size.x,bounds.size.z))*1.6;cam.position=center+Vector3(.3,2,3);cam.look_at(center)
		await create_timer(2.0).timeout
		for frame in 30:await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT+"/"+spec.id+".png")
		cam.position=center+Vector3(.3,8,30);cam.look_at(center)
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT+"/"+spec.id+"_far.png")
		rows.append({"id":spec.id,"label":LABELS[i],"entry":imported.entry,"source_sha256":spec.sha256,"triangles":tri})
		model.queue_free();await process_frame
	vp.queue_free();await settle()
	if failed:quit(1);return
	var doc=Doc.new();var path=directory+"/map.gltf";check(doc.save(path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=local;editor._shared_assets=[Library.new(BASE+"/packs/default/assets")]
	var probe=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	var discovery=await rpc("tools/list");check(discovery.result.tools.any(func(t):return t.name=="save_prefab"),"3D tool discovery")
	await call_tool("list_resource_packs")
	var published:Array=[]
	for i in rows.size():
		var row=rows[i]
		await call_tool("place_asset",{"asset_id":Thumb.key_for(row.entry),"position":[i*5,0,0]})
		var id=doc.records.back().uuid
		# Original source contains buried stone thickness; prefab uses native base pivot.
		doc._find(id).collision="none"
		await call_tool("select_objects",{"ids":[id]})
		var lib=Library.new(BASE+"/packs/default/assets");var existing=lib.entries.filter(func(e):return e.get("label","")==row.label and e.has("prefab_path"))
		var saved:Dictionary
		if existing.size()==1 and OS.get_cmdline_user_args().has("--replace"):
			lib.entries=lib.entries.filter(func(e):return e.get("label","")!=row.label)
			check(lib.save()==OK,"replace incompatible named prefab")
			editor._shared_assets=[Library.new(lib.directory)]
			saved=await call_tool("save_prefab",{"name":row.label,"pack_root":BASE+"/packs/default"})
		elif existing.size()==1:saved={"entry":existing[0],"asset_id":Thumb.key_for(existing[0])}
		elif existing.is_empty():saved=await call_tool("save_prefab",{"name":row.label,"pack_root":BASE+"/packs/default"})
		else:check(false,"duplicate catalog label");quit(1);return
		if not saved.has("entry"):quit(1);return
		check(DirAccess.copy_absolute(OUT+"/"+row.id+".png",saved.entry.thumbnail_path)==OK,"individual thumbnail")
		lib=Library.new(BASE+"/packs/default/assets")
		var payload=JSON.parse_string(FileAccess.get_file_as_string(saved.entry.prefab_path))
		var dependency=lib.directory.path_join(payload.records[0].asset_path).simplify_path()
		lib.entries=lib.entries.filter(func(e):return str(e.get("asset_path","")).simplify_path()!=dependency)
		check(lib.save()==OK,"atomic catalog save; no duplicate model slot")
		editor._shared_assets=[Library.new(lib.directory)]
		var listing=await call_tool("list_assets",{"query":row.label});check(listing.total==1,"unique prefab discoverable")
		await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[i*5,0,6]})
		var count=doc.records.size();await call_tool("undo");check(doc.records.size()==count-1,"undo prefab");await call_tool("redo");check(doc.records.size()==count,"redo prefab")
		row.published_entry=saved.entry;row.dependency_sha256=FileAccess.get_sha256(dependency);published.append(row)
	var before=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"missing_shrub","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement atomic")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==6 and doc.missing_assets().is_empty(),"all prefabs save/reopen dependencies")
	for record in doc.records:
		check(record.get("collision","")=="none","nonblocking collision retained")
		var model=doc._asset(record);inspect(model);model.free()
	editor.queue_free();await settle()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"game async loader")
	if loaded[0]!=null:
		var host=Node3D.new();root.add_child(host);host.add_child(loaded[0])
		preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3.ZERO)
		check(loaded[0].get_meta("stream_bodies",{}).is_empty(),"no blocking shrub collision bodies")
		host.queue_free();await settle()
	if is_instance_valid(loader):loader.queue_free()
	FileAccess.open(OUT+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"assets":published,"real_http":true,"test_map":path,"user_maps_modified":false,"count":published.size(),"pivot":"native bottom center; plant at ground level"},"\t"))
	print("STREET_SHRUB_PUBLICATION_FAILURES ",failed);quit(1 if failed else 0)
