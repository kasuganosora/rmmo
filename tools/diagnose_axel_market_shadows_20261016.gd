extends "res://tools/review_axel_market_realism_20261016.gd"
## Read-only exact-native shading diagnosis. Disabled features are NOT a model fix.
const EnvironmentSettings=preload("res://scripts/world3d/environment_settings.gd")
var diagnostic_take:=""
var previous:Dictionary={}
var source_take:="gpu_realism_v5_01"

func shadow_values(sun:DirectionalLight3D)->Dictionary:
	return {"shadow_enabled":sun.shadow_enabled,"bias":sun.shadow_bias,"normal_bias":sun.shadow_normal_bias,"mode":sun.directional_shadow_mode,"max_distance":sun.directional_shadow_max_distance,"split_1":sun.directional_shadow_split_1,"split_2":sun.directional_shadow_split_2,"split_3":sun.directional_shadow_split_3,"blend_splits":sun.directional_shadow_blend_splits,"fade_start":sun.directional_shadow_fade_start}

func run()->void:
	if "--syntax-only" in OS.get_cmdline_user_args():print("MARKET_SHADOW_DIAGNOSTIC_SYNTAX_OK");quit();return
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--asset="):asset_name=arg.trim_prefix("--asset=")
		elif arg.begins_with("--take="):diagnostic_take=arg.trim_prefix("--take=")
		elif arg.begins_with("--source-take="):source_take=arg.trim_prefix("--source-take=")
		elif arg.begins_with("--plan-version="):plan_version=arg.trim_prefix("--plan-version=")
	if asset_name not in ["pottery","scroll"] or not diagnostic_take.is_valid_identifier():push_error("Invalid diagnostic scope");quit(2);return
	out=ROOT.path_join(diagnostic_take).path_join(asset_name);case_name="diagnostic"
	if FileAccess.file_exists(out.path_join(case_name+".json")):push_error("Diagnostic evidence already exists");quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	var baseline_report:String=ROOT.path_join(source_take).path_join(asset_name).path_join("candidate.json")
	previous=read_json(baseline_report);var plan:=read_json(ART.path_join(plan_version+"/review_plan.json"))
	for row:Dictionary in plan.rows:
		if row.asset==asset_name:pinned=row
	if not check(not pinned.is_empty() and previous.get("passed",false) and previous.original_sha==pinned.candidate_sha256,"fixed candidate evidence identity"):finish();return
	if not check(FileAccess.get_sha256(pinned.candidate)==pinned.candidate_sha256,"frozen candidate source unchanged"):finish();return
	var native:Dictionary=previous.native
	var fc:Dictionary={"product":native.payload,"payload_sha":native.payload_sha256}
	if not check(str(fc.product).begins_with(ROOT+"/") and FileAccess.get_sha256(fc.product)==fc.payload_sha,"read historical diagnostic payload by exact SHA without modifying cache"):finish();return
	var packed:PackedScene=ResourceLoader.load(fc.product,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	if not check(packed!=null,"read frozen historical packed scene for diagnosis only"):finish();return
	var scene:Node=packed.instantiate()
	report.merge({"asset":asset_name,"candidate_sha256":pinned.candidate_sha256,"native_payload":fc.product,"native_payload_sha256":fc.payload_sha,"source_review":{"path":baseline_report,"sha256":FileAccess.get_sha256(baseline_report)},"diagnostic_only":true,"no_final_visual_acceptance":true,"formal_writes":false,"environment_settings_sha256":FileAccess.get_sha256("res://scripts/world3d/environment_settings.gd"),"review_tool_sha256":FileAccess.get_sha256("res://tools/review_axel_market_realism_20261016.gd"),"helper_sha256":FileAccess.get_sha256("res://scripts/world_editor/asset_preview_environment.gd")},true)
	packed=null;Drainer.synchronize_transfer()
	report.native_generator=previous.get("generator","");report.current_generator=Compiled.generator()
	report.diagnostic_tool_sha256=FileAccess.get_sha256("res://tools/diagnose_axel_market_shadows_20261016.gd")
	var name_:String="back" if asset_name=="pottery" else "goods_raking"
	var view:Dictionary={}
	for item:Dictionary in previous.camera_views:
		if item.name==name_:view=item
	if not check(not view.is_empty(),"reuse exact original camera and lighting view"):scene.free();finish();return
	await draw_diagnostic(scene,view)
	check(FileAccess.get_sha256(pinned.candidate)==pinned.candidate_sha256 and FileAccess.get_sha256(fc.product)==fc.payload_sha,"source and native unchanged after diagnostic")
	finish()

func draw_diagnostic(scene:Node,view:Dictionary)->void:
	root.size=dimensions;var vp:=SubViewport.new();vp.size=dimensions;vp.own_world_3d=true
	vp.use_taa=false;vp.msaa_3d=Viewport.MSAA_DISABLED;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.14,.17,.20);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.18 if view.lighting=="raking" else .65
	env.environment.tonemap_mode=Environment.TONE_MAPPER_ACES;env.environment.tonemap_exposure=1.;PreviewEnvironment.apply_reflections(env.environment);vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-12,65,0) if view.lighting=="raking" else Vector3(-38,-28,0)
	sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=80.;vp.add_child(sun)
	var defaults:=shadow_values(sun)
	var bounds:=scene_bounds(scene);var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(24,24);ground.mesh=plane
	ground.position=Vector3(bounds.get_center().x,bounds.position.y-.02,bounds.get_center().z)
	var ground_mat:=StandardMaterial3D.new();ground_mat.albedo_color=Color(.29,.31,.30);ground_mat.roughness=.95;ground.material_override=ground_mat;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.near=.03;cam.far=200.;cam.position=vector(view.eye);cam.fov=float(view.fov);vp.add_child(cam);cam.look_at(vector(view.aim))
	var nodes:Array=[];gather(scene,nodes);var target:MeshInstance3D
	var target_name:String="CanopyTrim" if asset_name=="pottery" else "GoodsOpaque"
	for node:Node in nodes:
		if node is MeshInstance3D and str(node.name)==target_name:
			if not check(target==null,"unique diagnostic target node"):vp.queue_free();await process_frame;return
			target=node
	if not check(target!=null,"diagnostic target exists "+target_name):vp.queue_free();await process_frame;return
	var original_cast:int=target.cast_shadow
	var materials:Array=[]
	for surface in target.mesh.get_surface_count():
		var material:=target.get_active_material(surface)
		if material is BaseMaterial3D:
			var local:BaseMaterial3D=material.duplicate(true)
			target.set_surface_override_material(surface,local)
			materials.append({"material":local,"normal_enabled":local.normal_enabled})
	report.view=view;report.screenshots=[]
	report.render_spec={"dimensions":[dimensions.x,dimensions.y],"exposure":1.,"tonemap":"ACES","per_shot_settings":"Actual AA, camera, lighting, material overrides and normal flags are recorded for each image.","taa":false,"target":target_name,"original_cast_shadow":original_cast,"sky_reflection_recipe":1,"project_msaa_enum":ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")}
	for mode:String in ["current_defaults","current_msaa4","current_msaa4_normal","current_msaa4_close","current_msaa4_close_normal"]:
		sun.shadow_bias=defaults.bias;sun.shadow_normal_bias=defaults.normal_bias;sun.directional_shadow_mode=defaults.mode;sun.directional_shadow_max_distance=defaults.max_distance
		target.cast_shadow=original_cast
		target.material_override=null
		vp.msaa_3d=Viewport.MSAA_DISABLED
		cam.position=vector(view.eye);cam.fov=float(view.fov);cam.look_at(vector(view.aim))
		sun.rotation_degrees=Vector3(-12,65,0) if view.lighting=="raking" else Vector3(-38,-28,0)
		env.environment.ambient_light_energy=.18 if view.lighting=="raking" else .65
		for item:Dictionary in materials:item.material.normal_enabled=item.normal_enabled
		if mode=="production_shadow_settings":
			var values:=EnvironmentSettings.defaults();values.sun_rotation=vec(sun.rotation_degrees);values.sun_energy=sun.light_energy;values.sun_color=[1.,1.,1.];values.sun_shadows=true
			EnvironmentSettings.apply(values,sun,null)
		elif mode=="current_no_target_shadow":target.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif mode=="current_no_target_normal":
			for item:Dictionary in materials:item.material.normal_enabled=false
		elif mode.begins_with("current_msaa4"):
			vp.msaa_3d=Viewport.MSAA_4X
			if mode.contains("close"):
				cam.position=Vector3(-.30,1.22,1.08);cam.look_at(Vector3(-.53,1.057,.67));cam.fov=40.
			if mode.ends_with("normal"):
				sun.rotation_degrees=Vector3(-38,-28,0);env.environment.ambient_light_energy=.65
		elif mode.begins_with("matte_"):
			var matte:=StandardMaterial3D.new();matte.albedo_color=Color(.7,.7,.6);matte.roughness=.9;matte.cull_mode=BaseMaterial3D.CULL_DISABLED
			if mode.begins_with("matte_unshaded"):matte.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			target.material_override=matte
			if mode.ends_with("no_shadow"):target.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mode.ends_with("isolated"):
				for node:Node in nodes:
					if node is MeshInstance3D and node!=target:node.visible=false
		for frame in 10:await process_frame;await RenderingServer.frame_post_draw
		var image:Image=vp.get_texture().get_image();var path:=out.path_join(mode+".png")
		check(image.save_png(path)==OK,"diagnostic screenshot "+mode)
		var pixels:=normalized_image(image);var original_pixels:Dictionary={}
		for shot:Dictionary in previous.screenshots:
			if shot.view.name==view.name:original_pixels=shot.pixels
		var normal_flags:Array=[]
		for item:Dictionary in materials:normal_flags.append(item.material.normal_enabled)
		report.screenshots.append({"mode":mode,"path":path,"file_sha256":FileAccess.get_sha256(path),"pixels":pixels,"shadow_settings":shadow_values(sun),"target_cast_shadow":target.cast_shadow,"original_view":view,"actual_eye":vec(cam.position),"actual_camera_transform":str(cam.transform),"actual_fov":cam.fov,"actual_msaa_enum":vp.msaa_3d,"actual_normal_enabled":normal_flags,"material_override":target.material_override!=null,"sun_rotation":vec(sun.rotation_degrees),"sun_energy":sun.light_energy,"ambient_energy":env.environment.ambient_light_energy,"original_review_pixel_identity":pixels==original_pixels,"interpretation":"Exact native supplement; per-shot camera and lighting/AA changes explicit, no model or global quality modifications."})
	target.cast_shadow=original_cast;vp.queue_free();await process_frame;Drainer.synchronize_transfer()
