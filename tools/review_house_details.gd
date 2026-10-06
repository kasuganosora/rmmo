extends "res://tools/build_house_playground.gd"

func render_gallery()->void:
	editor._ground_batches.enabled=false;editor._ground_batches.clear();editor._grid.hide()
	editor._canvas.get_child(0).msaa_3d=Viewport.MSAA_4X
	var origin:=Blueprint.vec(houses[0].position)
	for bias in [.65,1.0,1.3]:
		editor._sun.shadow_normal_bias=bias
		await capture("shadow_"+str(bias),origin+Vector3(16,9,-18),origin+Vector3(0,5,-1),17)
	editor._sun.shadow_normal_bias=.65
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE;editor._camera.fov=65
	editor._camera.position=origin+Vector3(9,2.1,-11);editor._camera.look_at(origin+Vector3(0,3,-3))
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	editor._canvas.get_child(0).get_texture().get_image().save_png(Review.review_path(review_directory+"/eye_level.png"))
