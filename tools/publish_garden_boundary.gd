extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const BASE="D:/code/rmmo_runtime"
const ART=BASE+"/art_sources/garden_boundary/height_150"
const OUT=BASE+"/review_artifacts/garden_boundary"
const LABELS=["写实石围墙·1.5米高·2.4米直墙","写实石围墙·1.5米高·1.2米直墙","写实石立柱·1.95米","写实石立柱·1.8米","写实石围墙·1.5米高·L形转角","写实石围墙·1.5米高·0.8米短墙"]
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	DirAccess.make_dir_recursive_absolute(OUT)
	var specs=JSON.parse_string(FileAccess.get_file_as_string(ART+"/manifest.json")).assets
	var verified=JSON.parse_string(FileAccess.get_file_as_string(ART+"/validation.json"))
	if not verified.failures.is_empty() or specs.size()!=6:quit(1);return
	var directory=Paths.cache_directory("garden_boundary_%d"%Time.get_ticks_usec())
	var local=Library.new(directory+"/assets");var rows:Array=[]
	var vp=SubViewport.new();vp.size=Vector2i(800,600);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.25,.28,.26);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.65;vp.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-30,0);sun.shadow_enabled=true;sun.light_energy=1.5;vp.add_child(sun)
	var cam=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	for i in specs.size():
		var spec=specs[i];var file=ART+"/models/"+spec.id+".glb"
		check(FileAccess.get_sha256(file)==spec.sha256,"approved file hash "+spec.id)
		var imported=local.import_file(file);check(imported.ok,"native import "+spec.id)
		if not imported.ok:quit(1);return
		var model=Library.instantiate_preview(imported.entry.asset_path);var meshes=Paint.meshes(model);var tri=0
		check(meshes.size()==1,"one mesh per module")
		for mesh in meshes:
			check(mesh.mesh.get_surface_count()==2,"stone and mortar surfaces")
			var materials=[]
			for surface in mesh.mesh.get_surface_count():materials.append(mesh.mesh.surface_get_material(surface))
			var candidates=materials.filter(func(m):return m is StandardMaterial3D and m.albedo_texture!=null)
			check(candidates.size()==1,"one textured stone material")
			var mat=candidates[0]
			check(mat is StandardMaterial3D and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null and mat.roughness_texture!=null,"runtime PBR channels")
			tri+=mesh.mesh.get_faces().size()/3
		check(tri==spec.game_triangles,"triangle count "+spec.id)
		vp.add_child(model);var bounds=Library.bounds_of(model);var center=bounds.get_center()
		check(absf(bounds.end.y-spec.recipe.height)<.005,"approved physical height")
		cam.size=maxf(bounds.size.y,maxf(bounds.size.x,bounds.size.z))*1.6;cam.position=center+Vector3(.3,2,3);cam.look_at(center)
		await create_timer(2.0).timeout
		for frame in 30:await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT+"/"+spec.id+".png")
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
		doc._find(id).collision="block"
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
	var before=doc.recovery_snapshot();await call_tool("place_asset",{"asset_id":"missing_garden_wall","position":[0,0,0]},false);check(doc.recovery_snapshot()==before,"invalid placement atomic")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(doc.records.size()==12 and doc.missing_assets().is_empty(),"all prefabs save/reopen dependencies")
	for record in doc.records:
		check(record.get("collision","")=="block","blocking collision retained")
		var model=doc._asset(record);check(Paint.meshes(model).size()==1,"saved mesh retained");model.free()
	editor.queue_free();await settle()
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"game async loader")
	if loaded[0]!=null:
		var host=Node3D.new();root.add_child(host);host.add_child(loaded[0])
		preload("res://scripts/world3d/world_stream.gd").sync(loaded[0],host,Vector3.ZERO)
		check(not loaded[0].get_meta("stream_bodies",{}).is_empty(),"game collision bodies")
		host.queue_free();await settle()
	if is_instance_valid(loader):loader.queue_free()
	FileAccess.open(OUT+"/publication.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failed,"assets":published,"real_http":true,"test_map":path,"user_maps_modified":false,"count":published.size(),"pivot":"native bottom center; walls contain 4cm buried base, sink 0.04m; pillars sit at ground level"},"\t"))
	print("GARDEN_BOUNDARY_PUBLICATION_FAILURES ",failed);quit(1 if failed else 0)
