extends "res://tools/review_guild_full_batch.gd"
## Isolated asset/native review. No publication and no user map writes.
const DEST="D:/code/rmmo_runtime/review_artifacts/s10_court_variants_20261017/v2"
const MANIFEST="D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017/v2/tree_manifest.json"
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")

func gallery(scene:Node,folder:String)->void:
	var id:String=report.identity.id
	var tree:=id.begins_with("s10_")
	var bounds:=scene_bounds(scene);var center:=bounds.get_center();var radius:=bounds.size.length()*.5
	var distance:=maxf(1.,radius/sin(deg_to_rad(21))*1.03)
	var vp:=SubViewport.new();vp.size=Vector2i(1200,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.14,.17,.20);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.58;env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1.
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0);sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=250;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(300,300);floor.mesh=plane;floor.position.y=bounds.position.y-.015
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.25,.27,.25);mat.roughness=1.;floor.material_override=mat;vp.add_child(floor)
	var cam:=Camera3D.new();cam.current=true;cam.fov=42;cam.near=.015;cam.far=400;vp.add_child(cam)
	var wind_mats:Array=[];var mesh_nodes:=Paint.meshes(scene)
	for m:MeshInstance3D in mesh_nodes:
		var cfg:Dictionary=m.get_meta('extras',{}).get('rmmo_wind',{})
		if cfg.is_empty():continue
		check(Response.mesh_error(m).is_empty(),'wind material features supported')
		for slot in m.mesh.get_surface_count():
			var w:=Wind.make(m.get_active_material(slot),cfg,m.get_aabb());m.set_surface_override_material(slot,w);wind_mats.append(w)
	report.wind_surface_count=wind_mats.size()
	var dirs:=Vector3(.70,.40,1.55).normalized()
	var views:Array=[]
	for v in [['near',12.5 if tree else distance],['medium',50. if tree else distance*1.85],['far',110. if tree else distance*3.1]]:
		views.append({'name':v[0],'eye':center+dirs*v[1],'aim':center})
	views.append({'name':'back','eye':center+Vector3(-.8,.4,-1.4).normalized()*distance,'aim':center})
	views.append({'name':'detail','eye':center+dirs*distance*.42,'aim':center})
	var water:MeshInstance3D
	if id.begins_with('s12_water_step'):
		water=MeshInstance3D.new();var water_plane:=PlaneMesh.new();water_plane.size=Vector2(12,8);water.mesh=water_plane;water.position.y=.34
		var water_mat:=StandardMaterial3D.new();water_mat.albedo_color=Color(.18,.26,.25);water_mat.roughness=.3;water.material_override=water_mat;water.visible=false;vp.add_child(water)
		views.append({'name':'installation_waterline','eye':center+dirs*distance,'aim':center})
		report.waterline_scope='Flat neutral test plane at prescribed 0.34m water height; shows only reference-visible stone crown, not a production river/water-material acceptance.'
	if id=='s12_projecting_arch':views.append_array([{'name':'capital_join','eye':Vector3(2.4,4.2,3.2),'aim':Vector3(1.48,3.57,1.1)},{'name':'soffit_wall_connection','eye':Vector3(.1,1.6,2.4),'aim':Vector3(.3,3.9,.65)}])
	if tree:
		var fruit:Dictionary=report.identity.fruit_anchors[0];var p:Array=fruit.centre;var aim:=Vector3(p[0],p[2],-p[1])
		views.append_array([{'name':'fruit_detail','eye':aim+Vector3(aim.x,0.3,aim.z).normalized()*1.45,'aim':aim},{'name':'trunk','eye':Vector3(2.2,1.7,3.4),'aim':Vector3(0,1.5,0)},{'name':'leaf_edge_bright','eye':Vector3(4.9,4.7,4.9),'aim':Vector3(1.9,4.9,1.9)},{'name':'leaf_edge_dark','eye':Vector3(4.9,4.7,4.9),'aim':Vector3(1.9,4.9,1.9)},{'name':'ground_shadow','eye':Vector3(8,11,10),'aim':Vector3(1,1,1)}])
	report.screenshots=[];report.render_environment={'image_size':[1200,1000],'fov':42,'msaa':4,'taa':false,'ambient':.58,'sun':1.5,'sun_rotation':[-38,-28,0],'exposure':1,'renderer':RenderingServer.get_current_rendering_method()}
	if OS.get_environment('RMMO_STREET_QUICK_SHOULDERS')=='1':
		assert(id=='s12_water_steps_four')
		views=views.filter(func(v):return v.name in ['near','installation_waterline'])
		report.visual_scope='Two-view geometry iteration only; full gallery still required.'
	for view:Dictionary in views:
		cam.position=view.eye;cam.look_at(view.aim)
		if water!=null:water.visible=view.name=='installation_waterline'
		env.background_color=Color(.88,.9,.93) if view.name=='leaf_edge_bright' else Color(.005,.008,.01) if view.name=='leaf_edge_dark' else Color(.14,.17,.20)
		var poses:Array=[['still',Vector3.ZERO,0.]]
		if tree and view.name in ['near','fruit_detail','leaf_edge_bright','ground_shadow']:poses.append_array([['wind_t1',Vector3(3,0,1),1.],['wind_t4',Vector3(3,0,1),4.]])
		for pose in poses:
			for w:ShaderMaterial in wind_mats:w.set_shader_parameter('wind_velocity',pose[1]);w.set_shader_parameter('wind_time',pose[2])
			for frame in 8:await process_frame;await RenderingServer.frame_post_draw
			var name:String=view.name+'_'+pose[0]+'.png';check(vp.get_texture().get_image().save_png(folder+'/'+name)==OK,'screenshot '+name)
			report.screenshots.append({'name':name,'eye':vec(cam.position),'aim':vec(view.aim),'pose':pose[0],'draw_calls':vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),'primitives_with_ground':vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	if water!=null:water.visible=false
	if tree:
		# Actual range switching plus forced LOD0 at identical camera/light/wind.
		report.lod_samples=[]
		for d in [43.,47.,98.,102.]:
			cam.position=center+Vector3(0,0,d);cam.look_at(center)
			for w:ShaderMaterial in wind_mats:w.set_shader_parameter('wind_velocity',Vector3.ZERO);w.set_shader_parameter('wind_time',0.)
			for f in 8:await process_frame;await RenderingServer.frame_post_draw
			var auto_name:='lod_'+str(int(d))+'_auto.png';vp.get_texture().get_image().save_png(folder+'/'+auto_name)
			var auto_count:=vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
			for m:MeshInstance3D in mesh_nodes:
				if m.get_meta('extras',{}).has('rmmo_visibility_range'):
					m.visible=m.visibility_range_begin==0.;m.visibility_range_begin=0.;m.visibility_range_end=0.
			for f in 8:await process_frame;await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(folder+'/lod_'+str(int(d))+'_lod0.png')
			report.lod_samples.append({'distance':d,'auto_triangles_with_ground':auto_count,'forced_lod0_triangles_with_ground':vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
			for m:MeshInstance3D in mesh_nodes:m.visible=true
			preload('res://scripts/world3d/asset_visibility_range.gd').apply(scene)
		# Short continuous sequence, without duplicate GIF previews.
		cam.position=center+Vector3(8,2,10);cam.look_at(center)
		DirAccess.make_dir_recursive_absolute(folder+'/motion')
		for k in 24:
			for w:ShaderMaterial in wind_mats:w.set_shader_parameter('wind_velocity',Vector3(3,0,1));w.set_shader_parameter('wind_time',float(k)/24.)
			await process_frame;await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png(folder+'/motion/%03d.png'%k)
	# Exact exported collision semantics; real PhysicsServer rays.
	for m:MeshInstance3D in mesh_nodes:
		if m.get_meta('extras',{}).get('rmmo_collision','none')=='none':continue
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=m.mesh.create_trimesh_shape();body.add_child(shape);m.add_child(body)
	for f in 3:await physics_frame
	var space:=vp.find_world_3d().direct_space_state;report.collision_probes=[]
	var probes:Array=[]
	if id=='s12_projecting_arch' or id=='s12_facade_installation_demo':
		probes=[['clear central passage',Vector3(0,1.6,3),Vector3(0,1.6,-1),false],['column blocks',Vector3(1.48,1.6,3),Vector3(1.48,1.6,-1),true],['head clearance',Vector3(0,2.8,3),Vector3(0,2.8,-1),false]]
		if id=='s12_facade_installation_demo':
			probes.append_array([['curved arch crown remains open',Vector3(0,4.76,3),Vector3(0,4.76,-1),false],['old rectangular corner sealed left',Vector3(-1.43,4.64,3),Vector3(-1.43,4.64,-1),true],['old rectangular corner sealed right',Vector3(1.43,4.64,3),Vector3(1.43,4.64,-1),true]])
	elif id.begins_with('s12_water_step'):
		for x in ([0.,1.28,2.56,3.84] if id.ends_with('four') else [0.]):probes.append(['supported rock top',Vector3(x,1,0),Vector3(x,-.2,0),true])
	elif id.begins_with('s12_landing_steps'):
		var steps:=3 if id.ends_with('3') else 4
		# Probe tread interior; x=0 lies exactly in the 4mm mortar joint.
		for k in steps:probes.append(['supported tread '+str(k),Vector3(.18,2,-(.2+k*.4)),Vector3(.18,-.2,-(.2+k*.4)),true])
	elif tree:
		probes=[['trunk blocks',Vector3(.1,1,2),Vector3(.1,1,-2),true]]
		for x in [-1.6,-1.,1.,1.6]:
			for h in [.2,1.,2.1]:probes.append(['clear undercrown '+str(Vector2(x,h)),Vector3(x,h,2),Vector3(x,h,-2),false])
	for p in probes:
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p[1],p[2]));var hit_bool:=not hit.is_empty()
		check(hit_bool==p[3],p[0]);report.collision_probes.append({'name':p[0],'from':vec(p[1]),'to':vec(p[2]),'hit':hit_bool,'position':vec(hit.position) if hit_bool else []})
	for m:MeshInstance3D in mesh_nodes:
		for child in m.get_children():
			if child is StaticBody3D:child.free()
	report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free();await process_frame

func run()->void:
	if DisplayServer.get_name()=='headless':print('Syntax only');quit();return
	var manifest:=read_json(MANIFEST);var failures:Array=[];var done:Array=[]
	for row:Dictionary in manifest.assets:
		var filter:=OS.get_cmdline_user_args()
		if not filter.is_empty() and str(row.id) not in filter:continue
		var doc:=GLTFDocument.new();var state:=GLTFState.new();var code:=doc.append_from_file(row.path,state)
		if code!=OK:failures.append(str(row.id)+' import '+str(code));continue
		var scene:Node=Io.generate_scene(doc,state);doc=null;state=null
		var folder:=DEST+'/'+str(row.id)
		await review_one(scene,row,folder)
		check(report.get('gallery_completed',false),'gallery and physical probes fully completed')
		check(FileAccess.get_sha256(row.path)==row.sha256,'final exported SHA unchanged')
		report.passed=report.failures.is_empty();put(folder+'/report.json',report)
		if not report.passed:failures.append(row.id)
		done.append(row.id)
	put(DEST+'/summary_'+('all' if OS.get_cmdline_user_args().is_empty() else 'subset')+'.json',{'assets':done,'failures':failures,'generator':Compiled.generator(),'production_map_modified':false})
	print('REQUIRED_STREET_REVIEW ',done.size(),' failures=',failures);quit(0 if failures.is_empty() else 1)
