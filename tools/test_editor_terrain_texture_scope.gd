extends "res://tools/test_world3d_mcp.gd"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Prepare=preload("res://scripts/world_editor/terrain_texture_preparation.gd")

func base_texture(id:String)->Texture2D:
	return editor._view.get_node(id).get_active_material(0).get_shader_parameter("base_albedo")

func texture_timing_key()->String:return "terrain_texture_worker"

func setup_record(doc:RefCounted,id:String,definition:Dictionary)->Dictionary:
	var record:Dictionary=doc._find(id)
	record.terrain_mesh={"version":1,"columns":2,"rows":2,"floor":-8.,"heights":[0.,0.,0.,0.,0.,0.,0.,0.,0.],"holes":[false,false,false,false]}
	record.terrain_material=definition;record.terrain_saturation=1.
	return record

func run()->void:
	create_timer(90).timeout.connect(func():quit(2));Engine.max_fps=60
	var directory:=Paths.cache_directory("terrain_texture_scope_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var texture_path:=directory.path_join("color.png");var normal_path:=directory.path_join("normal.png")
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.RED);image.save_png(texture_path)
	image.fill(Color(.2,.25,1.,1.));image.save_png(normal_path)
	var definition:={"name":"Texture scope","color":[1.,1.,1.,1.],"roughness":.8,"texture_path":texture_path,"normal_path":normal_path,"normal_format":"directx"}
	var doc:=Doc.new();var id:String=doc.add_box("grass",Vector3.ZERO,Vector3(8,1,8))
	var record:Dictionary=setup_record(doc,id,definition)
	var requested:=Prepare.requests(record,{})
	var worker:=Thread.new();worker.start(Prepare.decode.bind(requested,Paths.external_root()))
	while worker.is_alive():await process_frame
	var payload:Dictionary=worker.wait_to_finish()
	var flipped:Image=payload.images[normal_path+"|flip_y"]
	check(absf(flipped.get_pixel(0,0).g-.75)<.01 and flipped.has_mipmaps(),"private texture worker retains DirectX normal flip and mipmaps")
	var denied:Dictionary=Prepare.decode({"outside":["C:/Windows/win.ini",false]},Paths.external_root())
	check(denied.images.is_empty() and denied.failed==["outside"],"worker confines paths to captured content root")
	var path:=directory.path_join("map.gltf");check(doc.save(path)==OK,"small terrain texture map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP terrain texture server")
	var sentinel:Dictionary={"unrelated":Image.create(1,1,false,Image.FORMAT_RGBA8)};Paint.prepared_images=sentinel
	await call_tool("open_world",{"path":path})
	check(is_same(Paint.prepared_images,sentinel) and sentinel.size()==1 and editor._load_job._terrain_texture_checked.is_empty(),"load texture scope restores caller images and clears load checks")
	check(editor._load_job.state().timings.build.units[texture_timing_key()].count==1,"declared textures decoded on private worker")
	var original_texture:=base_texture(id);var old_digest:=str(original_texture.get_meta("runtime_source_sha256"))
	# Exercise the real 64-entry LRU while the old shader retains its texture.
	image.fill(Color.WHITE)
	for i in 65:
		var extra:=directory.path_join("evict_%d.png"%i);image.save_png(extra)
		Paint.texture({"texture_path":extra})
	check(not Paint._textures.has(texture_path),"target texture was evicted by real LRU capacity")
	image.fill(Color.BLUE);image.save_png(texture_path)
	await call_tool("open_world",{"path":path})
	check(base_texture(id).get_meta("runtime_source_sha256")==FileAccess.get_sha256(texture_path) and base_texture(id)!=original_texture and original_texture.get_meta("runtime_source_sha256")==old_digest,"same-path changed pixels refresh shader after texture eviction without mutating old resource")
	FileAccess.open(texture_path,FileAccess.WRITE).store_string("broken_png")
	var before_save:=FileAccess.get_sha256(path)
	await call_tool("open_world",{"path":path})
	check(editor._view.get_node(id).has_meta("paint_error") and base_texture(id)==null,"existing but corrupt PNG cannot reuse old texture or shader")
	await call_tool("save_world",{},false)
	check(FileAccess.get_sha256(path)==before_save,"corrupt texture cannot overwrite formal map")
	image.fill(Color.GREEN);image.save_png(texture_path)
	await call_tool("save_world")
	check(FileAccess.get_sha256(path)!=before_save,"repair permits save in same editor without reopening")
	await call_tool("open_world",{"path":path,"discard_changes":true})
	check(not editor._view.get_node(id).has_meta("paint_error") and base_texture(id).get_meta("runtime_source_sha256")==FileAccess.get_sha256(texture_path),"next load repairs corrupted image with no persistent negative cache")
	before_save=FileAccess.get_sha256(path);DirAccess.remove_absolute(texture_path)
	await call_tool("save_world",{},false)
	check(FileAccess.get_sha256(path)==before_save,"missing image save fails without replacing map")
	image.fill(Color.BLUE);image.save_png(texture_path)
	await call_tool("save_world")
	check(editor._save_job.result.get("ok",false),"missing image repair permits save without restarting editor")
	Paint.prepared_images={};editor.queue_free();await settle()
	print("EDITOR_TERRAIN_TEXTURE_SCOPE_FAILED=",failed);quit(1 if failed else 0)
