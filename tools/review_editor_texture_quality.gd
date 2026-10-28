extends "res://tools/test_world3d_mcp.gd"
## Actual editor import, same material/UV/camera, original pixels versus the
## published GPU representation. Writes external evidence only. Lossy DDS needs
## visual assessment; successful publication does not imply quality approval.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var evidence:Dictionary={"views":[],"failures":[]}
var output:String

func check(ok:bool,label:String)->void:
	super.check(ok,label)
	if not ok:evidence.failures.append(label)

func capture(viewport:SubViewport,path:String)->void:
	for i:int in 8:await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(path)==OK,"capture "+path.get_file())

func run()->void:
	create_timer(180).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var args:Dictionary={}
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:args[arg.get_slice("=",0).trim_prefix("--")]=arg.substr(arg.find("=")+1)
	output=args.get("output","");var source:String=args.get("source","");var native:String=args.get("native","")
	if output.is_empty() or (source.is_empty() and native.is_empty()) or not Paths.allowed(output) or (not source.is_empty() and not Paths.allowed(source)) or DirAccess.dir_exists_absolute(output):quit(1);return
	check(DirAccess.make_dir_recursive_absolute(output)==OK,"fresh external evidence directory")
	var native_sha:=""
	if not native.is_empty():
		if not Paths.allowed(native) or native.get_extension()!="scn":quit(1);return
		native_sha=FileAccess.get_sha256(native)
		var packed:=ResourceLoader.load(native,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var instance:=packed.instantiate();var foliage:=instance.get_node("Foliage") as MeshInstance3D
		var foliage_material:=foliage.get_active_material(0) as StandardMaterial3D
		var image:=foliage_material.albedo_texture.get_image()
		if image.is_compressed():check(image.decompress()==OK,"decode actual native embedded foliage")
		image.convert(Image.FORMAT_RGBA8)
		var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(image.get_data())
		var pixels_sha:=digest.finish().hex_encode()
		check(pixels_sha==args.get("pixels-sha",""),"extracted native foliage matches previously reviewed mip pixels")
		evidence.extraction={"native":native,"native_sha256":native_sha,"node":"Foliage","slot":0,"normalized_mip_pixels_sha256":pixels_sha,"transparency":foliage_material.transparency,"alpha_scissor_threshold":foliage_material.alpha_scissor_threshold,"cull_mode":foliage_material.cull_mode}
		image.clear_mipmaps();source=output.path_join("embedded_foliage.png")
		check(image.save_png(source)==OK,"export actual native leaf pixels to isolated import source")
		instance.free();packed=null
	var source_sha:=FileAccess.get_sha256(source)
	var original:=Image.load_from_file(source)
	if original==null:check(false,"source decodes");quit(1);return
	original.convert(Image.FORMAT_RGBA8)
	var alpha:=original.detect_alpha()!=Image.ALPHA_NONE
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._material_directory=output.path_join("materials");editor._draft_directory=output.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual editor HTTP import server")
	var compression:String=args.get("compression","dds")
	var imported:=await call_tool("import_surface_material",{"path":source,"name":"real texture quality","compression":compression})
	if not imported.get("ok",false):editor.queue_free();await settle();quit(1);return
	var expected_dds:bool=compression=="dds" and original.get_width()%4==0 and original.get_height()%4==0
	check(imported.get("dds_ready",false)==expected_dds,"actual import chooses eligible DDS or exact-size PNG fallback")
	if not expected_dds:check(imported.get("dds_reason","")==("source_requested" if compression=="source" else "dimensions_not_multiple_of_four"),"explicit source or original-size fallback is retained")
	var canonical:=Image.load_from_file(imported.material.texture_path);canonical.convert(Image.FORMAT_RGBA8)
	check(canonical.get_size()==original.get_size() and canonical.get_data()==original.get_data(),"canonical source preserves original dimensions and RGBA pixels")
	var actual:=Paint.make_material(imported.material)
	var gpu:Texture2D=actual.albedo_texture
	check(gpu!=null and gpu==Paint.retained_texture(Paint.texture_key(imported.material.texture_path)),"review uses actual published import GPU owner")
	if gpu==null:editor.queue_free();await settle();quit(1);return
	var decoded:=gpu.get_image();var compressed_format:=decoded.get_format();var gpu_bytes:=decoded.get_data().size()
	check(decoded.has_mipmaps(),"actual GPU image has mipmaps")
	check(decoded.get_format()==(Image.FORMAT_DXT5 if alpha else Image.FORMAT_DXT1) if expected_dds else not decoded.is_compressed(),"actual GPU representation matches DXT1/DXT5/fallback")
	if decoded.is_compressed():check(decoded.decompress()==OK,"GPU DDS can be decoded for pixel evidence")
	decoded.clear_mipmaps();decoded.convert(Image.FORMAT_RGBA8)
	check(decoded.save_png(output.path_join("decoded.png"))==OK,"save decoded actual GPU level zero")
	check(original.save_png(output.path_join("original.png"))==OK,"save original level zero for bounded pixel comparison")
	original.generate_mipmaps();var source_gpu:=ImageTexture.create_from_image(original)
	var baseline:=actual.duplicate(false) as StandardMaterial3D;baseline.albedo_texture=source_gpu
	var viewport:=SubViewport.new();viewport.size=Vector2i(1024,768);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.2)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.65
	env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.
	var environment:=WorldEnvironment.new();environment.environment=env;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-38,-28,0);light.light_energy=1.5;light.shadow_enabled=true;world.add_child(light)
	var panel:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(4,4);panel.mesh=quad;panel.position=Vector3(0,2,0);world.add_child(panel)
	var floor_node:=MeshInstance3D.new();var floor_mesh:=PlaneMesh.new();floor_mesh.size=Vector2(30,30)
	var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color(.48,.48,.44);floor_material.roughness=.95
	floor_mesh.material=floor_material;floor_node.mesh=floor_mesh;floor_node.position.y=-.03;world.add_child(floor_node)
	var camera:=Camera3D.new();camera.fov=50;camera.near=.03;camera.far=100;world.add_child(camera);camera.current=true
	var views:Array=[
		{"name":"near","eye":Vector3(0,2,5),"aim":Vector3(0,2,0)},
		{"name":"medium","eye":Vector3(0,2,10),"aim":Vector3(0,2,0)},
		{"name":"far","eye":Vector3(0,2,20),"aim":Vector3(0,2,0)},
		{"name":"detail","eye":Vector3(-.7,2.7,1.4),"aim":Vector3(-.7,2.7,0)}]
	if alpha:
		for tone:String in ["bright","dark"]:
			views.append({"name":"alpha_"+tone,"eye":Vector3(0,2,5),"aim":Vector3(0,2,0),"background":Color(.9,.9,.9) if tone=="bright" else Color(.01,.01,.01)})
		views.append({"name":"shadow","eye":Vector3(5,6,6),"aim":Vector3(0,1,0)})
	for view:Dictionary in views:
		camera.position=view.eye;camera.look_at(view.aim);env.background_color=view.get("background",Color(.14,.17,.2))
		for arm:String in ["source","published"]:
			panel.material_override=baseline if arm=="source" else actual
			await capture(viewport,output.path_join(arm+"_"+view.name+".png"))
		evidence.views.append({"name":view.name,"eye":[view.eye.x,view.eye.y,view.eye.z],"aim":[view.aim.x,view.aim.y,view.aim.z],"background":str(env.background_color)})
	if not native.is_empty():
		# Separate mask sensitivity from the production paint blend mode. Keep
		# the reviewed tree's authored cutoff/culling identical in both arms.
		var mask_actual:=actual.duplicate(false) as StandardMaterial3D;var mask_source:=baseline.duplicate(false) as StandardMaterial3D
		for material:StandardMaterial3D in [mask_actual,mask_source]:
			material.transparency=evidence.extraction.transparency;material.alpha_scissor_threshold=evidence.extraction.alpha_scissor_threshold;material.cull_mode=evidence.extraction.cull_mode
		for view:Dictionary in views:
			camera.position=view.eye;camera.look_at(view.aim);env.background_color=view.get("background",Color(.14,.17,.2))
			for arm:String in ["source","published"]:
				panel.material_override=mask_source if arm=="source" else mask_actual
				await capture(viewport,output.path_join(arm+"_mask_"+view.name+".png"))
			evidence.views.append({"name":"mask_"+view.name,"eye":[view.eye.x,view.eye.y,view.eye.z],"aim":[view.aim.x,view.aim.y,view.aim.z],"background":str(env.background_color)})
		check(FileAccess.get_sha256(native)==native_sha,"native source bytes unchanged")
	check(FileAccess.get_sha256(source)==source_sha,"formal input bytes unchanged")
	evidence.merge({"source":source,"source_sha256":source_sha,"import":imported,"width":original.get_width(),"height":original.get_height(),"alpha":alpha,"gpu_format":compressed_format,"gpu_bytes":gpu_bytes,"source_mip_bytes":original.get_data().size(),"engine":Engine.get_version_info(),"engine_sha256":FileAccess.get_sha256(OS.get_executable_path()),"renderer":RenderingServer.get_current_rendering_method(),"camera_fov":50,"resolution":[1024,768],"tonemap":"ACES","exposure":1.,"ambient":.65,"sun_energy":1.5,"sun_rotation":[-38,-28,0],"scope":"actual editor-imported material on identical planar UVs; not a full vegetation model or continuous wind review"})
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"\t"));file.close()
	viewport.queue_free();editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("EDITOR_TEXTURE_QUALITY_FAILED=",failed);quit(1 if failed else 0)
