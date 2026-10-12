extends "res://tools/test_world3d_mcp.gd"
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Thumb=preload("res://scripts/world_editor/asset_thumbnails.gd")
const ART="D:/code/rmmo_runtime/art_sources/house_stone_details"
const OUT="D:/code/rmmo_runtime/review_artifacts/house_stone_details"
func run()->void:
	create_timer(420).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	DirAccess.make_dir_recursive_absolute(OUT)
	var specs=JSON.parse_string(FileAccess.get_file_as_string(ART+"/manifest.json")).assets
	var directory:=Paths.cache_directory("stone_details_%d"%OS.get_process_id())
	var local:=Library.new(directory+"/assets")
	var vp:=SubViewport.new();vp.size=Vector2i(640,640);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.22,.25,.26);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.85,.9,1);env.environment.ambient_light_energy=.7;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-25,0);sun.light_energy=1.5;sun.shadow_enabled=true;vp.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(camera)
	var rows:Array=[]
	for spec in specs:
		var file:String=ART+"/models/"+spec.id+".glb"
		check(FileAccess.get_sha256(file)==spec.sha256,"approved GLB hash")
		var imported:=local.import_file(file);check(imported.ok,"native GLB import")
		if not imported.ok:quit(1);return
		var model:=Library.instantiate_preview(imported.entry.asset_path)
		var meshes:=Paint.meshes(model);check(meshes.size()==1,"one combined mesh per detail")
		var count:=0
		for mesh in meshes:
			count+=mesh.mesh.get_faces().size()/3
			var stone:Material=mesh.mesh.surface_get_material(0)
			check(stone is StandardMaterial3D and stone.albedo_texture!=null and stone.normal_enabled and stone.normal_texture!=null,"scanned stone albedo and normal survive conversion")
		check(count==int(spec.game_triangles),"optimized triangle count matches Blender")
		vp.add_child(model);var bounds:=Library.bounds_of(model);var center:=bounds.get_center()
		camera.size=maxf(bounds.size.x,bounds.size.y)*1.3;camera.position=center+Vector3(.5,.3,4);camera.look_at(center)
		await settle();await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(OUT+"/"+spec.id+".png")
		rows.append({"spec":spec,"entry":imported.entry})
		model.free()
	vp.queue_free();await settle()
	if failed:quit(1);return
	var doc:=Doc.new();var path:=directory+"/map.gltf";check(doc.save(path)==OK,"temporary test map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory+"/drafts";root.add_child(editor);await settle();editor._safety.enabled=false
	editor._assets=local;editor._shared_assets=[]
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP MCP")
	for i in rows.size():
		var result:=await call_tool("place_asset",{"asset_id":Thumb.key_for(rows[i].entry),"position":[i*4,0,0]})
		if not result.get("ok",false):quit(1);return
	await call_tool("undo");check(doc.records.size()==2,"undo placement")
	await call_tool("redo");check(doc.records.size()==3,"redo placement")
	var saved:=await call_tool("save_world")
	if not saved.get("ok",false):quit(1);return
	var opened:=await call_tool("open_world",{"path":path})
	if not opened.get("ok",false):quit(1);return
	check(editor._doc.records.size()==3 and editor._doc.missing_assets().is_empty(),"all detail models save/reopen with dependencies")
	if failed:quit(1);return
	# Publish only after the isolated import/save validation has passed.
	var published:Array=[]
	for row in rows:
		var lib:=Library.new("D:/code/rmmo_runtime/packs/default/assets")
		var imported:=lib.import_file(ART+"/models/"+row.spec.id+".glb")
		check(imported.ok,"publish validated detail")
		if not imported.ok:quit(1);return
		imported.entry.label=row.spec.label;imported.entry.category="建筑构件"
		check(lib.save()==OK,"atomic library metadata save")
		DirAccess.make_dir_recursive_absolute(imported.entry.thumbnail_path.get_base_dir())
		check(DirAccess.copy_absolute(OUT+"/"+row.spec.id+".png",imported.entry.thumbnail_path)==OK,"individual front thumbnail")
		published.append(imported.entry)
	var report:=FileAccess.open(OUT+"/publication.json",FileAccess.WRITE);report.store_string(JSON.stringify({"failures":failed,"entries":published},"  "));report.close()
	print("STONE DETAILS FAILURES ",failed)
	editor.free();quit(0 if failed==0 else 1)
