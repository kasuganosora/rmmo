extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(320,240)
	var host:=Node3D.new();root.add_child(host)
	for z in 16:
		for x in 16:
			var box:=MeshInstance3D.new();box.mesh=BoxMesh.new();box.position=Vector3(x-8,0,z-8);host.add_child(box)
	var actor:=MeshInstance3D.new();actor.mesh=SphereMesh.new();actor.layers=1<<19;host.add_child(actor)
	var light:=DirectionalLight3D.new();light.shadow_enabled=true;light.rotation_degrees=Vector3(-50,-20,0);host.add_child(light)
	var mask:=SubViewport.new();mask.size=Vector2i(320,240);mask.transparent_bg=true;mask.world_3d=root.world_3d;mask.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(mask)
	var camera:=Camera3D.new();camera.cull_mask=1<<19;camera.position=Vector3(0,2,5);mask.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
	var images:Array=[]
	for mode in [Viewport.DEBUG_DRAW_DISABLED,Viewport.DEBUG_DRAW_UNSHADED]:
		mask.debug_draw=mode
		for i in 50:await process_frame
		await RenderingServer.frame_post_draw
		images.append(mask.get_texture().get_image())
		print("MASK_MODE ",mode," visible_calls=",mask.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)," shadow_calls=",mask.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	var mismatches:=0;var occupied:=0
	for y in 240:
		for x in 320:
			if absf(images[0].get_pixel(x,y).a-images[1].get_pixel(x,y).a)>.001:mismatches+=1
			if images[1].get_pixel(x,y).a>.01:occupied+=1
	print("MASK_ALPHA mismatches=",mismatches," occupied=",occupied)
	host.free();quit(0 if mismatches==0 and occupied>0 else 1)
