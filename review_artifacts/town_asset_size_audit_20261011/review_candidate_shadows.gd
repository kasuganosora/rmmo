extends "res://review_artifacts/town_asset_size_audit_20261011/review_lossless_candidates.gd"
## Complementary ground-shadow A/B; DOES NOT modify main reports or caches.
## --out=<completed pair review folder> --case=baseline|candidate|compare
## Optional --allow-texture-change; GPU cases use the private-desktop wrapper.
func finish()->void:
	report.passed=report.failures.is_empty()
	put(out.path_join("shadows").path_join(case_name+".json"),report)
	print("CANDIDATE_SHADOW_REVIEW ",case_name," passed=",report.passed)
	quit(0 if report.passed else 1)
func shadow_compare()->void:
	var folder:=out.path_join("shadows");var a:=read_json(folder.path_join("baseline.json"));var b:=read_json(folder.path_join("candidate.json"))
	if not check(a.get("passed",false) and b.get("passed",false),"both ground-shadow cases passed"):finish();return
	check(a.get("views")==b.get("views"),"identical paired shadow cameras")
	report.images=[]
	for shot:Dictionary in a.screenshots:
		var filename:String=shot.name
		var delta:=image_difference(folder.path_join("baseline").path_join(filename),folder.path_join("candidate").path_join(filename));delta.name=filename;report.images.append(delta)
		check(delta.get("valid",false),"paired shadow PNG "+filename)
		if not allow_texture_change:check(delta.get("exact",false),"lossless ground-shadow pixel equality "+filename)
	report.note="Texture candidates require visual inspection of these shadow pairs; errors are reported without treating image similarity as artistic approval."
	finish()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=").replace("\\","/").simplify_path().trim_suffix("/")
		elif arg.begins_with("--case="):case_name=arg.trim_prefix("--case=")
		elif arg=="--allow-texture-change":allow_texture_change=true
	var safe_out:=out.to_lower().begins_with("d:/code/rmmo/review_artifacts/town_asset_size_audit_20261011/") or out.to_lower().begins_with("d:/code/rmmo_runtime/art_sources/town_asset_size_optimization_20261011/")
	if not safe_out or case_name not in ["baseline","candidate","compare"]:push_error("Invalid isolated shadow output/case");quit(2);return
	DirAccess.make_dir_recursive_absolute(out.path_join("shadows"))
	report.scope="Supplementary shadow-receiving ground plane; no characters, production cache writes, cost claim or source edits."
	if case_name=="compare":shadow_compare();return
	if not check(DisplayServer.get_name()!="headless","private graphics process required"):finish();return
	var primary:=read_json(out.path_join(case_name+".json"));var baseline:=read_json(out.path_join("baseline.json"))
	if not check(primary.get("passed",false) and baseline.get("passed",false),"completed main asset review required"):finish();return
	dimensions=Vector2i(baseline.dimensions[0],baseline.dimensions[1]);report.original=primary.original;report.original_sha=primary.original_sha
	check(FileAccess.get_sha256(primary.original)==primary.original_sha,"original asset identity unchanged")
	var native:Dictionary=primary.native
	# This is a visual-only replay of the already validated, immutable payload.
	# Concurrent loader changes may invalidate its generator without changing pixels.
	if not check(str(native.payload).begins_with(str(native.content_root)+"/") and FileAccess.get_sha256(native.payload)==native.payload_sha256,"immutable isolated payload SHA and root"):finish();return
	var packed:PackedScene=ResourceLoader.load(native.payload,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	if not check(packed!=null and Compiled._valid_packed(packed),"isolated visual payload remains a valid PackedScene"):finish();return
	report.cache_scope="Visual replay by verified payload SHA; not a current-generator cache-hit performance test."
	var scene:Node=packed.instantiate();packed=null
	var bounds:=AABB(vector(baseline.bounds.position),vector(baseline.bounds.size));var ground_y:=bounds.position.y-.025
	var receiver_bounds:=bounds
	var ray_direction:Vector3=-(Basis.from_euler(Vector3(deg_to_rad(-38),deg_to_rad(-28),0))).z
	for endpoint in 8:
		var p:=bounds.get_endpoint(endpoint);var projected:=p+ray_direction*((ground_y-p.y)/ray_direction.y)
		receiver_bounds=receiver_bounds.expand(projected)
	var views:Array=[]
	for camera_view:Dictionary in baseline.camera_views:
		if camera_view.name=="near":views.append(camera_view.duplicate(true))
	var target:=receiver_bounds.get_center();var radius:=maxf(1,receiver_bounds.size.length()*.5)
	views.append({"name":"shadow_overview","eye":vec(target+Vector3(1,1.15,1.5).normalized()*radius/sin(deg_to_rad(19))*1.12),"aim":vec(target),"fov":38.0,"projection":"perspective"})
	report.views=views;report.dimensions=[dimensions.x,dimensions.y];report.receiver={"y":ground_y,"bounds":var_to_str(receiver_bounds)}
	var viewport:=SubViewport.new();viewport.size=dimensions;viewport.own_world_3d=true;viewport.use_taa=false;viewport.msaa_3d=Viewport.MSAA_DISABLED;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.size=dimensions;root.add_child(viewport);viewport.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.14,.17,.20)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65
	environment.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.environment.tonemap_exposure=1;viewport.add_child(environment)
	var ground:=MeshInstance3D.new();ground.name="Review_only_shadow_receiver";var plane:=PlaneMesh.new()
	plane.size=Vector2(maxf(8,receiver_bounds.size.x*1.7),maxf(8,receiver_bounds.size.z*1.7));ground.mesh=plane;ground.position=Vector3(receiver_bounds.get_center().x,ground_y,receiver_bounds.get_center().z);ground.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ground_mat:=StandardMaterial3D.new();ground_mat.albedo_color=Color(.48,.48,.44);ground_mat.roughness=.95;ground.material_override=ground_mat;viewport.add_child(ground)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;viewport.add_child(sun)
	var camera:=Camera3D.new();camera.current=true;camera.near=.03;camera.far=2000;viewport.add_child(camera)
	var winds:Array=[];var nodes:Array=[];gather(scene,nodes)
	for n:Node in nodes:
		if not n is MeshInstance3D or n.mesh==null:continue
		var config:Dictionary=n.get_meta("extras",{}).get("rmmo_wind",{})
		if config.is_empty() or config.get("profile","off")=="off":continue
		for slot in n.mesh.get_surface_count():
			var original:=n.get_active_material(slot) as StandardMaterial3D
			if not check(original!=null,"wind source material supported"):continue
			var mat:ShaderMaterial=Wind.make(original,config,n.get_aabb());n.set_surface_override_material(slot,mat);winds.append(mat)
	report.screenshots=[];report.wind_surface_count=winds.size();var folder:=out.path_join("shadows").path_join(case_name);DirAccess.make_dir_recursive_absolute(folder)
	for view:Dictionary in views:
		camera.position=vector(view.eye);camera.fov=view.fov;camera.look_at(vector(view.aim))
		for pose:Dictionary in [{"name":"still","velocity":Vector3.ZERO,"time":0.0},{"name":"wind_t1","velocity":Vector3(7,0,3),"time":1.0},{"name":"wind_t4","velocity":Vector3(7,0,3),"time":4.0}]:
			for mat:ShaderMaterial in winds:mat.set_shader_parameter("wind_velocity",pose.velocity);mat.set_shader_parameter("wind_time",pose.time)
			for frame in 8:await process_frame;await RenderingServer.frame_post_draw
			var image:Image=viewport.get_texture().get_image();var filename:String=str(view.name)+"_"+str(pose.name)+".png"
			check(image.save_png(folder.path_join(filename))==OK,"shadow screenshot "+filename);report.screenshots.append({"name":filename,"pixels":normalized_image(image)})
	viewport.queue_free();await process_frame;Drainer.synchronize_transfer();finish()
