extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Response=preload("res://scripts/world3d/wind_response.gd")
const BASE="D:/code/rmmo_runtime"
func _initialize()->void:run.call_deferred()
func run()->void:
	var vp=SubViewport.new();vp.size=Vector2i(1400,850);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var scene=Node3D.new();vp.add_child(scene)
	var we=WorldEnvironment.new();we.environment=Environment.new();var env=we.environment;env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_sky_contribution=0;env.ambient_light_color=Color(.85,.88,.92);env.ambient_light_energy=.55;scene.add_child(we)
	var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,32,0);light.light_color=Color(1,.98,.94);light.light_energy=1.;light.shadow_enabled=true;scene.add_child(light)
	var cam=Camera3D.new();cam.fov=60;cam.position=Vector3(0,.8,2.3);scene.add_child(cam);cam.look_at(Vector3(0,.18,0))
	var ground=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(100,100);var gm=StandardMaterial3D.new();gm.albedo_color=Color(.24,.25,.17);gm.roughness=1.;ground.material_override=gm;ground.position.y=-.008;scene.add_child(ground)
	var weather=preload("res://scripts/world3d/weather_controller.gd").new();scene.add_child(weather);weather.bind(cam,light,env)
	var config=preload("res://scripts/world3d/environment_settings.gd").defaults().merged({"sun_rotation":[-55,32,0],"sun_energy":1.,"sun_color":[1.,.98,.94],"ambient_color":[.85,.88,.92],"ambient_energy":.55,"weather":"clear","surface_wetness":false,"environment_audio":false,"time_hours":12.,"time_speed":0.,"wind_speed":0.},true);weather.configure(config,true)
	for mode in ["before","after"]:
		var models=[]
		for i in 3:
			var id=["arch_A","arch_B","arch_C"][i]
			var path=BASE+"/assets/reference_grass_clumps/"+id+".glb"
			if mode=="before":path=BASE+"/packs/default/assets/"+["969a994264803e6d96758a94b253bfd5d3cb99a6c43ddccb09bdef3a83eed377","0235a8af6c8e48fe327170749f9086d66684cbaed8090781251ee657f57e1b62","ca2be6914cdc26a0ab7bfa149c35d42dfffdb9b8d728c91aa4fc6dddcefc3336"][i]+".glb"
			var n=Library.instantiate(path);scene.add_child(n);n.position=Vector3((i-1)*.73,0,-abs(i-1)*.12);models.append(n)
			for mesh in Paint.meshes(n):Response.register(mesh)
		weather.wind_objects.refresh()
		for frame in 100:await process_frame
		await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(BASE+"/review_artifacts/reference_grass_clumps/sky_"+mode+".png")
		for n in models:n.queue_free()
		await process_frame
	print("REFERENCE_GRASS_REAL_SKY_COMPLETE");vp.queue_free();await process_frame;quit()
