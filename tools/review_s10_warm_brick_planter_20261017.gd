extends "res://tools/review_s12_residential_details_20261017.gd"
## Fresh actual native images/physics. Baseline and candidate use fixed cameras.
const PaintPlanter=preload("res://scripts/world3d/surface_materials.gd")
const WindResponse=preload("res://scripts/world3d/wind_response.gd")
const OUT_PLANTER="D:/code/rmmo_runtime/review_artifacts/s10_warm_brick_planter_20261017/v1/"

func functional(scene:Node3D,vp:SubViewport)->void:
	var editor:=EditorProbe.new();vp.add_child(editor);editor.set_process(false);editor.set_physics_process(false)
	scene.set_meta("asset_uuid","s12_review");make_bodies(editor,scene);await physics_frame;await physics_frame
	var bodies:Array=editor._bodies_by_uuid.get("s12_review",[]);report.picking_body_count=bodies.size()
	check(bodies.size()==2,"separate masonry and foliage stay pickable")
	for body:StaticBody3D in bodies:
		var visual:MeshInstance3D=body.get_meta("visual")
		check(bool(body.collision_layer&Walk.WALK_MASK)==Walk.physical(visual.get_meta("extras",{})),"native walk mask follows original semantic "+str(visual.name))
	var probes:Array=[["front wall blocks",Vector3(0,.25,1.5),Vector3(0,.25,0),true],["return wall blocks",Vector3(2.5,.25,0),Vector3(1.2,.25,0),true],["over plants clear",Vector3(0,.9,1.5),Vector3(0,.9,-1.5),false],["outside width clear",Vector3(1.9,.25,1.5),Vector3(1.9,.25,-1.5),false],["coping supported",Vector3(.4,1.4,.45),Vector3(.4,0,.45),true],["soil supported",Vector3(0,1.3,0),Vector3(0,0,0),true]]
	report.physical_probes=[]
	for p in probes:
		var ray:=hit(scene,p[1],p[2],Walk.WALK_MASK);check((not ray.is_empty())==p[3],p[0]);report.physical_probes.append({"name":p[0],"hit":not ray.is_empty(),"position":vec(ray.position) if not ray.is_empty() else []})
	editor.free();await physics_frame

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1200,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=false;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp);vp.add_child(scene)
	await functional(scene,vp)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.58;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1
	var we:=WorldEnvironment.new();we.environment=env;vp.add_child(we)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;vp.add_child(sun)
	var ground:=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(100,100);ground.position.y=-.015;var gm:=StandardMaterial3D.new();gm.albedo_color=Color(.25,.27,.25);gm.roughness=1;ground.material_override=gm;vp.add_child(ground)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.015;cam.far=120;vp.add_child(cam)
	var winds:Array=[];report.active_masonry_materials=[]
	for mesh:MeshInstance3D in PaintPlanter.meshes(scene):
		var cfg:Dictionary=mesh.get_meta("extras",{}).get("rmmo_wind",{})
		for slot in mesh.mesh.get_surface_count():
			var source:StandardMaterial3D=mesh.get_active_material(slot)
			if cfg.is_empty():report.active_masonry_materials.append({"name":source.resource_name,"normal_enabled":source.normal_enabled,"normal_scale":source.normal_scale,"roughness":source.roughness,"metallic":source.metallic,"has_albedo_texture":source.albedo_texture!=null})
			else:
				check(WindResponse.mesh_error(mesh).is_empty(),"existing foliage wind supported");var w:=Wind.make(source,cfg,mesh.get_aabb());mesh.set_surface_override_material(slot,w);winds.append(w)
	report.wind_surface_count=winds.size()
	var views:Array=[
		{"name":"near","eye":Vector3(3.4,2.2,5.7),"aim":Vector3(0,.43,0)},
		{"name":"medium","eye":Vector3(6.8,3.9,11.4),"aim":Vector3(0,.43,0)},
		{"name":"far","eye":Vector3(13.6,7.3,22.8),"aim":Vector3(0,.43,0)},
		{"name":"front","eye":Vector3(0,1.15,5.4),"aim":Vector3(0,.43,0)},
		{"name":"back","eye":Vector3(-3.4,2.2,-5.7),"aim":Vector3(0,.43,0)},
		{"name":"brick_detail","eye":Vector3(.45,.72,1.65),"aim":Vector3(.2,.32,.53)},
		{"name":"raking_light","eye":Vector3(.45,.72,1.65),"aim":Vector3(.2,.32,.53)},
		{"name":"corner_coping","eye":Vector3(2.45,1.65,1.6),"aim":Vector3(1.35,.51,.35)},
		{"name":"soil_and_roots","eye":Vector3(0,3.2,.6),"aim":Vector3(0,.45,0)},
		{"name":"leaf_edge_bright","eye":Vector3(1.4,1.55,2.1),"aim":Vector3(.5,.75,0)},
		{"name":"leaf_edge_dark","eye":Vector3(1.4,1.55,2.1),"aim":Vector3(.5,.75,0)},
		{"name":"ground_shadow","eye":Vector3(3.2,5,3.6),"aim":Vector3(0,.2,0)}]
	var diagnostic_mode:bool="diagnostics" in OS.get_cmdline_user_args()
	if diagnostic_mode:views=views.filter(func(v):return v.name in ["leaf_edge_bright","leaf_edge_dark","soil_and_roots"])
	report.screenshots=[]
	for v:Dictionary in views:
		ground.visible=not (diagnostic_mode and str(v.name).begins_with("leaf_edge"))
		for mesh:MeshInstance3D in PaintPlanter.meshes(scene):
			if str(mesh.name)=="Foliage":mesh.visible=not (diagnostic_mode and v.name=="soil_and_roots")
		cam.position=v.eye;cam.look_at(v.aim);sun.rotation_degrees=Vector3(-12,-75,0) if v.name=="raking_light" else Vector3(-38,-28,0)
		env.background_color=Color(.87,.89,.92) if v.name=="leaf_edge_bright" else Color(.005,.008,.01) if v.name=="leaf_edge_dark" else Color(.14,.17,.20)
		var poses:Array=[["still",Vector3.ZERO,0.]]
		if v.name=="near":poses.append_array([["wind_t1",Vector3(3,0,1),1.],["wind_t4",Vector3(3,0,1),4.]])
		for pose in poses:
			for w:ShaderMaterial in winds:w.set_shader_parameter("wind_velocity",pose[1]);w.set_shader_parameter("wind_time",pose[2])
			for f in 8:await process_frame;await RenderingServer.frame_post_draw
			var name:String=v.name+"_"+pose[0];check(vp.get_texture().get_image().save_png(folder+"/"+name+".png")==OK,"capture "+name)
			report.screenshots.append({"name":name,"eye":vec(v.eye),"aim":vec(v.aim),"wind_time":pose[2],"draw_calls_with_ground":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
	report.render_conditions={"size":[1200,1000],"exposure":1,"ambient":.58,"sun":1.5,"fov":42,"msaa":4,"raking_sun_degrees":[-12,-75,0]};report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	if DisplayServer.get_name()=="headless":print("S10_PLANTER_SYNTAX_OK");quit();return
	var pairs:Array=[["baseline","D:/code/rmmo_runtime/packs/default/assets/8072add85cdbbcb157b0c372961af898fa635d9c8973543713ee1d613aaf657a.glb"],["s10_warm_redbrick_planter","D:/code/rmmo_runtime/art_sources/s10_warm_brick_planter_20261017/v1/s10_warm_redbrick_planter.glb"]]
	for pair in pairs:
		if not OS.get_cmdline_user_args().is_empty() and not pair[0] in OS.get_cmdline_user_args():continue
		var folder:String=OUT_PLANTER+pair[0]+("_diagnostics" if "diagnostics" in OS.get_cmdline_user_args() else "");if FileAccess.file_exists(folder+"/report.json"):quit(2);return
		var path:String=pair[1];var identity:Dictionary={"id":pair[0],"path":path,"sha256":FileAccess.get_sha256(path),"source_bytes":size_of(path)}
		var scene:=load_source(path);await review_one(scene,identity,folder);report.passed=report.failures.is_empty();put(folder+"/report.json",report)
		if not report.passed:print("S10_PLANTER_FAILED ",pair[0],report.failures);quit(1);return
	print("S10_PLANTER_NATIVE_REVIEW complete");quit()
