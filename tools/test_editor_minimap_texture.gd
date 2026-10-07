extends "res://tools/test_editor_overlay_cache.gd"

var visual_report := {}

func compare_legacy(legacy_path: String) -> void:
	if OS.get_cmdline_user_args().size()<2:
		check(false,"external minimap candidate path is required; production keeps direct drawing")
		return
	# Keep the inherited runner failing if a script error aborts this coroutine.
	failed+=1
	var viewport:=SubViewport.new(); viewport.size=Vector2i(editor._canvas.size)
	viewport.disable_3d=true; viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var backdrop:=ColorRect.new(); backdrop.size=Vector2(viewport.size)
	backdrop.color=Color(.23,.49,.71); backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	viewport.add_child(backdrop); backdrop.hide()
	var old=editor._city.overlay
	var current=load(OS.get_cmdline_user_args()[1]).new()
	old.get_parent().add_child(current); current.setup(editor._city)
	editor._city.overlay=current; old.free()
	var original=load(legacy_path).new()
	viewport.add_child(original); original.setup(editor._city)
	current.reparent(viewport,false); current.position=Vector2.ZERO
	current.minimap_cache_enabled=true
	# Include overlapping translucent schematic rectangles and crossing roads.
	var schematic: Array[Rect2]=[Rect2(-10,-5,8,12),Rect2(-8,-4,8,12),Rect2(0,0,10,3)]
	for overlay in [original,current]:
		overlay.boxes=schematic.duplicate()
		if overlay==current: overlay._invalidate_minimap()
		else: overlay.mini.queue_redraw()
	await capture_case(viewport,original,current,"transparent",true,false)
	backdrop.show()
	await capture_case(viewport,original,current,"opaque_blue",true,false)
	backdrop.color=Color(.8,.2,.15,.4)
	await capture_case(viewport,original,current,"translucent_red",true,false)
	for overlay in [original,current]: overlay.mini.size=Vector2(236,192); overlay.mini.queue_redraw()
	await capture_case(viewport,original,current,"resized",true,false)
	for overlay in [original,current]: overlay.position=Vector2(.25,.5)
	await capture_case(viewport,original,current,"fractional_position",false,true)
	for overlay in [original,current]: overlay.position=Vector2.ZERO; overlay.scale=Vector2(1.25,1.25)
	await capture_case(viewport,original,current,"scaled_125",false,true)
	for overlay in [original,current]: overlay.scale=Vector2.ONE
	root.content_scale_factor=1.25
	await capture_case(viewport,original,current,"window_content_scale",false,true)
	root.content_scale_factor=1.
	await capture_case(viewport,original,current,"restored_native",true,false)
	current.minimap_cache_enabled=false
	await capture_case(viewport,original,current,"disabled",false,true)
	current.minimap_cache_enabled=true
	current.show(); current.set_process(true); original.hide(); original.set_process(false)
	await settle(); await RenderingServer.frame_post_draw
	var count: int=current.minimap_draw_count
	await call_tool("set_editor_camera",{"center":[3.25,0,1.75]})
	await settle(); await RenderingServer.frame_post_draw
	check(current.minimap_draw_count==count,"marker motion retains cached static pixels")
	var node: Dictionary=editor._city.data.roads.nodes[0].duplicate(true)
	node.position[2]+=3
	await call_tool("update_road_graph",graph_request({"nodes":[node]}))
	await settle(); await RenderingServer.frame_post_draw
	check(current.minimap_draw_count>count,"HTTP road edit refreshes cached overview pixels")
	count=current.minimap_draw_count
	await call_tool("undo"); await settle(); await RenderingServer.frame_post_draw
	check(current.minimap_draw_count>count,"undo refreshes cached overview pixels")
	current.set_process(false); current.hide(); await settle()
	current.show(); current.set_process(true); await settle(); await RenderingServer.frame_post_draw
	check(current._mini_cached and current._mini_image.visible,"hide/show restores cached minimap")
	var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true
	click.position=current.mini_rect().get_center()
	current.minimap_input(click)
	check(Vector2(editor._orbit_center.x,editor._orbit_center.z).is_equal_approx(current.bounds.get_center()),"cached overview click retains camera targeting")
	visual_report.images=directory
	FileAccess.open(directory.path_join("minimap_visual.json"),FileAccess.WRITE).store_string(JSON.stringify(visual_report,"\t"))
	print("MINIMAP_VISUAL ",JSON.stringify(visual_report))
	current.reparent(editor._canvas,false); original.queue_free(); viewport.queue_free()
	failed-=1

func capture_case(viewport: SubViewport, original: Control, current: Control, label: String, cached: bool, exact: bool) -> void:
	current.hide(); current.set_process(false); original.show(); original.set_process(true)
	await settle(); await RenderingServer.frame_post_draw
	var before:=viewport.get_texture().get_image()
	original.hide(); original.set_process(false); current.show(); current.set_process(true)
	await settle(); await RenderingServer.frame_post_draw
	var after:=viewport.get_texture().get_image()
	check(current._mini_cached==cached,label+" chooses expected native cache/fallback")
	var a:=before.get_data(); var b:=after.get_data()
	var changed:=0; var maximum:=0; var alpha_max:=0
	for index in range(0,a.size(),4):
		var different:=false
		for channel in 4:
			var delta:=absi(int(a[index+channel])-int(b[index+channel]))
			maximum=maxi(maximum,delta); different=different or delta>0
			if channel==3: alpha_max=maxi(alpha_max,delta)
		if different: changed+=1
	visual_report[label]={"changed_pixels":changed,"max_channel_delta":maximum,"max_alpha_delta":alpha_max,"cached":current._mini_cached}
	check(maximum==0 if exact else maximum<=2,label+" preserves appearance within measured 8-bit composite rounding")
	before.save_png(directory.path_join(label+"_before.png")); after.save_png(directory.path_join(label+"_after.png"))
