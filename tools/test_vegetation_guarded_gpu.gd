extends SceneTree
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const G=preload("res://scripts/world3d/ground_batch_geometry.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Policy=preload("res://scripts/world3d/vegetation_instance_policy.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Surface=preload("res://scripts/world3d/surface_materials.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018/"
var failures:=0
var report:Dictionary={"checks":[],"measurements":[]}
var view:SubViewport
var camera:Camera3D
var batch:Node3D
var nodes:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_);report.checks.append({"ok":ok,"label":label_})
	if not ok:failures+=1
func settle(n:int=25)->void:
	for i in n:await process_frame;await RenderingServer.frame_post_draw
func stats(values:Array)->Dictionary:
	var sorted:Array=values.duplicate();sorted.sort()
	return {"p50":sorted[sorted.size()/2],"p95":sorted[int(sorted.size()*.95)],"max":sorted.back(),"samples":values}
func measure(label_:String)->void:
	await settle(35)
	var cpu:Array=[];var gpu:Array=[];var setup:Array=[];var frames:Array=[]
	for i in 100:
		var before:=Time.get_ticks_usec();await process_frame;await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec()-before)/1000.)
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
		setup.append(RenderingServer.get_frame_setup_time_cpu())
	var total:Array=[]
	for i in cpu.size():total.append(cpu[i]+setup[i])
	report.measurements.append({"label":label_,"cpu_render_ms":stats(cpu),"gpu_ms":stats(gpu),"frame_setup_ms":stats(setup),"cpu_total_render_ms":stats(total),"frame_ms":stats(frames),"calls":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"batch":batch.stats("vegetation")})
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	create_timer(180).timeout.connect(func():quit(2))
	var import_report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"cutout_guarded_http.json"))
	var path:String=import_report.asset.import.asset_path
	var source:Node3D=Assets.instantiate(path);var mesh:Mesh=Surface.meshes(source)[0].mesh;source.free()
	view=SubViewport.new();view.size=Vector2i(1280,800);view.own_world_3d=true;view.use_taa=false;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=120
	camera=Camera3D.new();view.add_child(camera);camera.position=Vector3(16,40,120);camera.look_at(Vector3(16,.5,16));camera.fov=26.;camera.current=true;camera.far=500
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.08,.1,.16);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.5;view.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;view.add_child(sun)
	for z in 64:
		for x in 64:
			var node:=MeshInstance3D.new();node.name="plant_%d_%d"%[x,z];node.mesh=mesh;node.position=Vector3(.5*x,0,.5*z)
			node.set_meta("ground_batch_record",{"uuid":str(node.name),"kind":"asset","asset_path":path,"vegetation_batch":true});view.add_child(node);nodes.append(node)
	batch=Batch.new();view.add_child(batch);batch.set_process(false);G.static_scatter_instances_enabled=true
	var media:String=OUT+"field_%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(media)
	await settle(90)
	for label_:String in ["A1","B1","A2","B2","A3"]:
		batch.clear()
		if label_.begins_with("B"):batch.sync(nodes);batch.flush();batch.update_cutout_visibility()
		await measure(label_)
		if label_ in ["A1","B1"]:view.get_texture().get_image().save_png(media.path_join(label_+".png"))
	check(report.measurements[1].batch.active_cutout_groups>0,"dense distant field actually selects guarded instancing")
	var body:=StaticBody3D.new();body.position=nodes[0].position+Vector3.UP*.5
	var collision:=CollisionShape3D.new();var collider_shape:=BoxShape3D.new();collider_shape.size=Vector3(1,1,1);collision.shape=collider_shape;body.add_child(collision);view.add_child(body)
	var ray:=PhysicsRayQueryParameters3D.create(nodes[0].position+Vector3.UP*2,nodes[0].position-Vector3.UP*2,1)
	var extra:Array=[]
	batch.clear()
	for i in 128:
		var visual:=MeshInstance3D.new();visual.name="zz_extra_%d"%i;visual.mesh=mesh;visual.position=nodes[i].position+Vector3(0,0,.1)
		visual.set_meta("ground_batch_record",nodes[i].get_meta("ground_batch_record"));view.add_child(visual);extra.append(visual)
	batch.sync(nodes+extra);batch.flush();await settle(35)
	var suppressed:=0
	for group:Dictionary in batch.cutout_visuals.values():
		if group.cutout_instanced:suppressed+=group.members.size()
	check(suppressed>0 and suppressed<=Policy.MAX_ACTIVE_MEMBERS and batch.cutout_visuals.size()>batch.stats().active_cutout_groups,"extra dense groups respect the measured per-world transition cap")
	await physics_frame;await physics_frame
	check(body.get_world_3d().direct_space_state.intersect_ray(ray).get("collider")==body,"actual physical collider remains hittable while original renderer is suppressed")
	batch.clear()
	for visual:MeshInstance3D in extra:visual.free()
	batch.sync(nodes);batch.flush();batch.update_cutout_visibility();await settle(35)
	check(batch.stats().active_cutout_groups>0,"transition probes begin with actually active instance groups")
	# Moving into the stand and crossing a frustum edge restore the original instances.
	camera.position=Vector3(14,1.2,16);camera.fov=58;camera.look_at(Vector3(16,.5,16))
	var transition_started:=Time.get_ticks_usec();batch.update_cutout_visibility();report.near_transition_ms=(Time.get_ticks_usec()-transition_started)/1000.
	check(batch.stats().active_cutout_groups==0,"near camera restores fine source culling")
	check(body.get_world_3d().direct_space_state.intersect_ray(ray).get("collider")==body,"near fallback retains the same physical collider identity")
	camera.fov=26;camera.position=Vector3(16,40,120);camera.look_at(Vector3(45,.5,16));batch.update_cutout_visibility()
	check(batch.stats().active_cutout_groups==0,"screen-edge stand cannot use a coarse common-AABB draw")
	camera.look_at(Vector3(16,.5,16));view.use_occlusion_culling=true;batch.update_cutout_visibility()
	check(batch.stats().active_cutout_groups==0,"occlusion-enabled viewport retains independent source decisions")
	view.use_occlusion_culling=false
	camera.fov=26;batch.update_cutout_visibility()
	check(batch.stats().active_cutout_groups>0,"leaving occlusion fallback restores distant instancing")
	var old_mesh:Mesh=nodes[0].mesh;nodes[0].hide()
	check(not batch._member_groups.has(str(nodes[0].name)) and nodes[0].mesh==old_mesh,"hiding one member invalidates its draw and restores independent geometry immediately")
	nodes[0].show()
	batch.clear();batch.sync(nodes);batch.flush();await settle(35)
	check(batch.stats().active_cutout_groups>0,"lifetime probe begins with source renderer suppression active")
	view.remove_child(batch);await settle(4)
	check(view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)==report.measurements[0].primitives,"removing only the batch owner restores all live source draws")
	view.add_child(batch);await settle(4)
	check(batch.stats().active_cutout_groups>0,"reparented batch resumes its valid derived draw")
	batch.clear()
	var cpu:Mesh=Cpu.capture(mesh);var lod_mesh:=ArrayMesh.new()
	for slot in cpu.surfaces.size():
		var indices:PackedInt32Array=cpu.surfaces[slot][Mesh.ARRAY_INDEX]
		lod_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,cpu.surfaces[slot],[],{.03:indices.slice(0,indices.size()/2/3*3)})
		lod_mesh.surface_set_material(slot,mesh.surface_get_material(slot))
	check(not Policy.preserves_lods(lod_mesh),"native index LOD keeps per-source renderer selection")
	nodes[0].mesh=lod_mesh;nodes[1].mesh=lod_mesh;batch.sync([nodes[0],nodes[1]]);batch.flush()
	check(batch.stats().source_objects==0 and nodes[0].mesh==lod_mesh and nodes[1].mesh==lod_mesh,"LOD-bearing cutouts cannot enter common-AABB MultiMesh path")
	check(Policy.profitable(2.,.4) and not Policy.profitable(.4,2.) and not Policy.profitable(0.,0.),"measured CPU margin admits useful views and rejects GPU-bound or unavailable data")
	var alpha:=mesh.surface_get_material(0).duplicate();alpha.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	check(G.material_key(alpha,true).is_empty(),"blended transparency preserves original draw sorting")
	report.failures=failures;report.media=media;report.asset_path=path;report.count=nodes.size()
	FileAccess.open(OUT+"vegetation_performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	view.free();await process_frame
	print("VEGETATION_GUARDED_PERFORMANCE failures=",failures);quit(1 if failures else 0)
