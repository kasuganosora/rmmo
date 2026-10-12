extends SceneTree
## Independent artefact-only A/B probe. Never writes production compiled cache.
const OUT="D:/code/rmmo_runtime/art_sources/bridge_long_pennant_optimization_20261009"
const Wind=preload("res://scripts/world3d/wind_material.gd")
const Estimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
var report:Dictionary={"checks":[],"failures":[],"scope":"One isolated asset. Not production chunk entry or the historical 4.439s preparation path."}
var case_name:="optimized"
var mode:="cpu"
var run_id:=""
var audit:Dictionary

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	report.checks.append({"label":label,"ok":ok})
	if not ok:report.failures.append(label)
func save_report()->void:
	var f:=FileAccess.open(OUT+"/"+mode+"_"+case_name+run_id+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "));f.close()
func bytes_sha(data:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(data);return h.finish().hex_encode()
func own(node:Node,owner_node:Node)->void:
	for child in node.get_children():child.owner=owner_node;own(child,owner_node)
func inspect(scene:Node)->Dictionary:
	var rows:Array=[];var texture_cache:Dictionary={};var wind_count:=0
	for n in scene.find_children("*","MeshInstance3D",true,false):
		var extra:Dictionary=n.get_meta("extras",{})
		if extra.has("rmmo_wind"):wind_count+=1
		var row:Dictionary={"path":str(scene.get_path_to(n)),"transform":var_to_str(n.transform),"extras":extra,"surfaces":[]}
		for slot in n.mesh.get_surface_count():
			var arrays:Array=n.mesh.surface_get_arrays(slot)
			var surface:Dictionary={"arrays_sha256":bytes_sha(var_to_bytes(arrays)),"material":{}}
			var mat:Material=n.get_active_material(slot)
			for prop in mat.get_property_list():
				var key:String=prop.name
				if not int(prop.usage)&PROPERTY_USAGE_STORAGE or key in ["resource_local_to_scene","resource_path","resource_name","script","resource_scene_unique_id"]:continue
				var value:Variant=mat.get(key)
				if value is Texture2D:
					var id:int=value.get_instance_id()
					if not texture_cache.has(id):
						var im:Image=value.get_image()
						texture_cache[id]={"width":im.get_width(),"height":im.get_height(),"format":im.get_format(),"mips":im.has_mipmaps(),"pixel_sha":bytes_sha(im.get_data())}
					surface.material[key]=texture_cache[id]
				elif value is Resource:
					surface.material[key]=str(value.get_class())
				else:surface.material[key]=var_to_str(value)
			row.surfaces.append(surface)
		rows.append(row)
	check(rows.size()==10,"ten independently named visual nodes")
	check(wind_count==9,"nine authored cloth wind configurations")
	return {"nodes":rows,"referenced_texture_resources":texture_cache.size()}
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
		if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--run="):run_id="_"+arg.trim_prefix("--run=")
	check(case_name in ["baseline","optimized"],"valid case")
	audit=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/lossless_audit.json"))
	var path:String=audit.source if case_name=="baseline" else audit.output
	var expected:String=audit.source_sha256 if case_name=="baseline" else audit.output_sha256
	check(FileAccess.get_sha256(path)==expected,"source hash before")
	report.case_name=case_name;report.mode=mode;report.gpu=DisplayServer.get_name()!="headless"
	report.source=path;report.source_sha256=expected;report.admission_estimate=Estimate.estimate(path)
	if mode!="cpu" and not report.gpu:check(false,"GPU mode requires private desktop");save_report();quit(1);return
	var scene:Node
	if mode=="native":
		var native_path:=OUT+"/"+case_name+".scn"
		var start:=Time.get_ticks_usec();var digest:=FileAccess.get_sha256(path);report.source_sha_us=Time.get_ticks_usec()-start
		check(digest==expected,"timed source hash")
		start=Time.get_ticks_usec();report.native_sha=FileAccess.get_sha256(native_path);report.payload_sha_us=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();var packed:=ResourceLoader.load(native_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		report.native_load_us=Time.get_ticks_usec()-start
		check(packed!=null,"isolated native resource load")
		if packed!=null:scene=packed.instantiate()
	else:
		var doc:=GLTFDocument.new();var state:=GLTFState.new();var start:=Time.get_ticks_usec()
		var error:=doc.append_from_file(path,state,0,path.get_base_dir());report.raw_append_us=Time.get_ticks_usec()-start
		check(error==OK,"GLTF parses")
		if error==OK:
			start=Time.get_ticks_usec();scene=doc.generate_scene(state);report.generate_us=Time.get_ticks_usec()-start
			report.decoded_image_entries=state.images.size()
			# Use the same production external-scene postprocessors.
			preload("res://scripts/world3d/grass_texture_cache.gd").apply(scene)
			preload("res://scripts/world3d/leaf_backlight.gd").apply(scene)
			preload("res://scripts/world3d/asset_visibility_range.gd").apply(scene)
	check(scene!=null,"scene generated")
	if scene==null:save_report();quit(1);return
	report.semantic=inspect(scene)
	if mode=="build":
		own(scene,scene);var packed:=PackedScene.new();check(packed.pack(scene)==OK,"native packing")
		var p:=OUT+"/"+case_name+".scn"
		check(ResourceSaver.save(packed,p,ResourceSaver.FLAG_BUNDLE_RESOURCES|ResourceSaver.FLAG_COMPRESS)==OK,"isolated native product saved")
		var f:=FileAccess.open(p,FileAccess.READ);report.native_bytes=f.get_length();f.close()
	# Renderer counters become meaningful only after completed GPU frames.
	report.texture_memory_bytes=null
	if mode=="render":await render_views(scene)
	else:scene.free()
	check(FileAccess.get_sha256(path)==expected,"source hash after")
	save_report();print("PENNANT_REVIEW ",mode," ",case_name," failures=",report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
func render_views(scene:Node)->void:
	root.size=Vector2i(1500,900)
	var view:=SubViewport.new();view.size=Vector2i(1500,900);view.own_world_3d=true;view.use_taa=false;view.msaa_3d=Viewport.MSAA_DISABLED;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view);view.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.14,.17,.20)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=1.5;sun.shadow_enabled=true;view.add_child(sun)
	var box:=AABB();var first:=true;var winds:Array=[]
	for n in scene.find_children("*","MeshInstance3D",true,false):
		var a:AABB=n.global_transform*n.get_aabb();box=a if first else box.merge(a);first=false
		var config:Dictionary=n.get_meta("extras",{}).get("rmmo_wind",{})
		if config.is_empty():continue
		for slot in n.mesh.get_surface_count():
			var material:=Wind.make(n.get_active_material(slot),config,n.get_aabb());n.set_surface_override_material(slot,material);winds.append(material)
	var camera:=Camera3D.new();view.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=maxf(box.size.x*.67,box.size.y*1.2);camera.position=box.get_center()+Vector3(0,.6,maxf(15,box.size.x));camera.look_at(box.get_center())
	report.bounds=var_to_str(box);report.camera_transform=var_to_str(camera.transform);report.camera_size=camera.size
	for pose in [{"label":"still","velocity":Vector3.ZERO,"time":0.0},{"label":"wind_t1","velocity":Vector3(7,0,3),"time":1.0},{"label":"wind_t4","velocity":Vector3(7,0,3),"time":4.0}]:
		for mat in winds:mat.set_shader_parameter("wind_velocity",pose.velocity);mat.set_shader_parameter("wind_time",pose.time)
		for frame in 6:await process_frame;await RenderingServer.frame_post_draw
		report.texture_memory_bytes=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
		var image:=view.get_texture().get_image();check(image.save_png(OUT+"/"+case_name+"_"+pose.label+".png")==OK,"saved "+pose.label)
	view.queue_free();await process_frame
