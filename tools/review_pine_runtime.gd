extends SceneTree
const Library=preload("res://scripts/world_editor/asset_library.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/pine_dense_v3"
func _initialize()->void:run.call_deferred()
func run()->void:
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/validation.json"))
	var vp:=SubViewport.new();vp.size=Vector2i(1200,1000);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.32,.36,.39);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.8,.88,1);env.environment.ambient_light_energy=.6;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;vp.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);floor.mesh=plane;vp.add_child(floor)
	var cam:=Camera3D.new();cam.projection=Camera3D.PROJECTION_ORTHOGONAL;vp.add_child(cam)
	for row in report.assets:
		var model:=Library.instantiate_preview(row.entry.asset_path);vp.add_child(model);var bounds:=Library.bounds_of(model);var center:=bounds.get_center()
		cam.size=maxf(bounds.size.x,bounds.size.y)*1.2;cam.position=center+Vector3(14,6,20);cam.look_at(center)
		for i in 64:await process_frame
		await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+"/"+row.id+".png")
		if row.id=="pine_dense_mature":
			cam.size=3.;cam.position=Vector3(6,8,10);cam.look_at(Vector3(0,7,0))
			for i in 64:await process_frame
			await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+"/needles_close.png")
		model.queue_free();await process_frame
	print("PINE_REVIEW_PROJECT_AA_COMPLETE");quit()
