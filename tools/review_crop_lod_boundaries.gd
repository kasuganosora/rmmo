extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Wind=preload("res://scripts/world3d/wind_material.gd")
var directory:="D:/code/rmmo_runtime/review_artifacts/editor_boundaries_20261012/crops"
var failed:=0
var wind_materials:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failed+=1
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute(directory)
	var lib:=Library.new(directory.path_join("assets"));var report:Array=[];var models:Array=[]
	for variant:String in ["ripe","green"]:
		var source:="D:/code/rmmo_runtime/art_sources/editor_extensions_20261012/wheat_lod_v2/wheat_"+variant+".glb"
		var doc:=GLTFDocument.new();var state:=GLTFState.new();check(doc.append_from_file(source,state)==OK,"candidate parse "+variant)
		var audit:=preload("res://scripts/world3d/model_lod_preparation.gd").prepare(state)
		check(not audit.meshes.is_empty() and audit.meshes[0].levels.any(func(levels):return not levels.is_empty()),"generated indexed LOD "+variant)
		var imported:=lib.import_file(source);check(imported.ok,"real native import "+variant)
		if not imported.ok:quit(1);return
		check(lib.save()==OK,"candidate catalog saved")
		var model:=Library.instantiate_preview(imported.entry.asset_path);check(model!=null,"native reopened "+variant);models.append(model)
		report.append({"variant":variant,"source_sha":FileAccess.get_sha256(source),"asset":imported.entry.asset_path,"lod":audit,"compiled":imported.get("compiled_asset",{})})
	FileAccess.open(directory.path_join("audit.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if DisplayServer.get_name()=="headless":
		for model:Node in models:model.free()
		print("CROP_LOD_AUDIT_FINISHED failures=",failed);quit(failed);return
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	# Fixed A/B images cannot compare different temporal-jitter histories.
	# Continuous motion below restores the project's normal TAA setting.
	root.use_taa=false
	var world:=Node3D.new();root.add_child(world)
	var env:=WorldEnvironment.new();var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.25,.32,.41);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=.55;env.environment=environment;world.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-32,0);sun.light_energy=1.4;sun.shadow_enabled=true;world.add_child(sun)
	var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.19,.13,.075);mat.roughness=.95;plane.material=mat;ground.mesh=plane;world.add_child(ground)
	var camera:=Camera3D.new();camera.fov=55.;world.add_child(camera);camera.current=true
	for model:Node3D in models:world.add_child(model);model.hide()
	var crops:Array=[]
	for z in 12:
		for x in 16:
			var node:Node3D=models[(x+z)%2].duplicate();world.add_child(node);node.show();node.position=Vector3((x-7.5)*.6,0,(z-5.5)*.6);crops.append(node)
	var settings:={"profile":"foliage","amplitude":.12,"anchor":"bottom","stiffness":.6}
	for crop:Node3D in crops:
		for visual:MeshInstance3D in Paint.meshes(crop):
			visual.extra_cull_margin=.3
			for slot in visual.mesh.get_surface_count():
				var material:=Wind.make(visual.get_active_material(slot),settings,visual.mesh.get_aabb())
				material.set_shader_parameter("wind_velocity",Vector3.ZERO);visual.set_surface_override_material(slot,material);wind_materials.append(material)
	var metrics:Array=[]
	for shot:Dictionary in [{"name":"detail","camera":Vector3(0,1.1,2.0),"at":Vector3(0,.75,0)},{"name":"near","camera":Vector3(6,3,8),"at":Vector3(0,.5,0)},{"name":"mid","camera":Vector3(12,7,17),"at":Vector3(0,.5,0)},{"name":"far","camera":Vector3(23,12,33),"at":Vector3(0,.5,0)}]:
		camera.position=shot.camera;camera.look_at(shot.at)
		for threshold:float in [0.,1.]:
			root.mesh_lod_threshold=threshold
			for i in 8:await process_frame
			await RenderingServer.frame_post_draw
			var label:String=shot.name+("_base" if threshold==0 else "_lod")
			root.get_texture().get_image().save_png(directory.path_join(label+".png"))
			metrics.append({"view":label,"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"camera":[camera.position.x,camera.position.y,camera.position.z]})
	check(metrics[-1].primitives<metrics[-2].primitives,"far field actually submits fewer primitives")
	# Continuous deterministic sequences include two wind directions and the
	# LOD transition while the camera moves; no avatar exists in this fixture.
	root.use_taa=bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa",false))
	for direction in 2:
		for frame in 48:
			var time:float=frame/24.;var distance_:float=lerpf(9.,25.,float(frame)/47.)
			camera.position=Vector3(distance_*.6,distance_*.3,distance_);camera.look_at(Vector3(0,.5,0))
			for material:ShaderMaterial in wind_materials:
				material.set_shader_parameter("wind_velocity",Vector3(10,0,2) if direction==0 else Vector3(-2,0,10));material.set_shader_parameter("wind_time",time)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("wind_%d_%03d.png"%[direction,frame]))
	FileAccess.open(directory.path_join("render.json"),FileAccess.WRITE).store_string(JSON.stringify({"metrics":metrics,"frames":96,"fps":24,"static_taa":false,"motion_taa":root.use_taa,"wind_amplitude":.12,"wind_directions":[[10,0,2],[-2,0,10]],"viewport":[1280,800],"fov":55},"\t"))
	world.queue_free();await process_frame;print("CROP_LOD_REVIEW_FINISHED failures=",failed);quit(failed)
