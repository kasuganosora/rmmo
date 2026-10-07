extends "res://tools/test_world3d_city_layout.gd"

func run() -> void:
	Engine.max_fps=60
	root.size=Vector2i(1440,960); root.content_scale_size=root.size
	directory=Paths.cache_directory("overlay_cache_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var object: String=doc.add_box("block",Vector3(0,1,0),Vector3(2,2,2))
	doc._find(object).wind_response={"profile":"foliage"}
	check(doc.save(path)==OK,"isolated overlay fixture")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"loopback MCP starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size(),"current 3D discovery matches schema")
	await check_wind_preview(object)
	await call_tool("create_road_path",{"points":[[-20,0,-5],[20,0,5]],"width":6})
	await check_static_preview_roads()
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":60})
	await settle()
	var overlay=editor._city.overlay
	var scene_count: int=overlay.draw_count; var mini_count: int=overlay.minimap_draw_count
	var road_count: int=overlay.road_draw_count
	for i in 10: await process_frame
	check(overlay.draw_count==scene_count and overlay.minimap_draw_count==mini_count,"stationary overlays retain drawing commands")
	await call_tool("set_editor_camera",{"center":[2,0,0]}); await settle()
	check(overlay.draw_count>scene_count and overlay.minimap_draw_count==mini_count,"camera updates projection and marker without redrawing static overview")
	check(overlay.road_draw_count==road_count,"orthographic pan reuses road drawing commands")
	var first_edge: Dictionary=editor._city.data.roads.edges[0]
	var before_side: Array=overlay._road_sides[first_edge.id][0].duplicate()
	var node: Dictionary=editor._city.data.roads.nodes[0].duplicate(true)
	node.position[2]+=4
	await call_tool("update_road_graph",graph_request({"nodes":[node]})); await settle()
	check(overlay._road_sides[first_edge.id][0]!=before_side and overlay.minimap_draw_count>mini_count,"HTTP road edit invalidates guides and overview")
	await atomic_reject("set_editor_camera",{"span":-1})
	await call_tool("undo"); await settle()
	check(overlay._road_sides[first_edge.id][0]==before_side,"undo restores cached road edges")
	await call_tool("redo"); await settle()
	await call_tool("select_objects",{"ids":[object]})
	var old_node: Node=editor._view.get_node(object)
	await call_tool("transform_selection",{"translation":[3,0,0]})
	for i in 20: await process_frame
	check(editor._view.get_node(object)==old_node and overlay._record_bounds[object].get_center().is_equal_approx(Vector3(3,1,0)),"object move retains node and updates only its cached bounds")
	await call_tool("save_world"); await call_tool("open_world",{"path":path}); await settle()
	check(editor._doc._find(object).position==[3.,1.,0.],"save/reopen retains object motion")
	check(not editor._wind_tools.preview_enabled and not editor._weather.wind_objects.enabled and editor._doc._find(object).wind_response.profile=="foliage","reopen keeps preview disabled and saved asset wind intact")
	for projection in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_FRUSTUM]:
		editor._camera.projection=projection
		editor._camera.h_offset=.2; editor._camera.v_offset=.3
		overlay.prepare_projection()
		var max_error:=0.; var clipping_matches:=true
		for i in 100:
			var local:=Vector3((i%7-3)*2.,(i%11-5)*1.,-.03 if i%9==0 else -2.-i)
			var world: Vector3=editor._camera.get_camera_transform()*local
			var pixels: PackedVector2Array=overlay.project([world])
			clipping_matches=clipping_matches and (pixels.is_empty()==editor._camera.is_position_behind(world))
			if not pixels.is_empty(): max_error=maxf(max_error,pixels[0].distance_to(editor._camera.unproject_position(world)))
		check(clipping_matches and max_error<.01,"cached projection matches Camera3D including offsets and near plane: %d"%projection)
	editor._camera.h_offset=0; editor._camera.v_offset=0
	editor._camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	await call_tool("set_editor_camera",{"projection":"top"}); await settle()
	if DisplayServer.get_name()!="headless" and not OS.get_cmdline_user_args().is_empty():
		await compare_legacy(OS.get_cmdline_user_args()[0])
	editor.queue_free(); await settle()
	print("EDITOR_OVERLAY_CACHE failures=",failed)
	quit(0 if failed==0 else 1)

func check_static_preview_roads()->void:
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,0,0],"distance":60,"pitch":-45,"yaw":0})
	await settle()
	var overlay=editor._city.overlay
	overlay.profile_enabled=true
	# Same transient points used by the canvas's in-progress road preview.
	# They must redraw the preview, without changing the committed road graph.
	editor._city.pending=[[0.,0.,0.],[4.,0.,3.]]
	await settle()
	var roads:int=overlay.road_draw_count
	var main:int=overlay.draw_count
	var foreground:int=overlay.profile_calls.foreground
	for i in 10:await process_frame
	check(overlay.road_draw_count==roads,"stationary perspective preview retains committed road drawing commands")
	check(overlay.draw_count>main and overlay.profile_calls.foreground>foreground,"preview main and foreground still redraw while roads remain cached")
	await call_tool("set_editor_camera",{"center":[1,0,0]});await settle()
	check(overlay.road_draw_count>roads,"HTTP perspective camera motion still invalidates roads during preview")
	editor._city.pending.clear();await settle()
	roads=overlay.road_draw_count
	for i in 6:await process_frame
	check(overlay.road_draw_count==roads,"ending stationary preview does not redraw unchanged roads")
	var first:Dictionary=editor._city.data.roads.nodes[0].duplicate(true)
	first.position[2]+=2
	await call_tool("update_road_graph",graph_request({"nodes":[first]}));await settle()
	check(overlay.road_draw_count>roads,"HTTP road edit invalidates stationary perspective cache")
	roads=overlay.road_draw_count
	await call_tool("undo");await settle()
	check(overlay.road_draw_count>roads,"HTTP undo invalidates stationary perspective road cache")
	overlay.profile_enabled=false

func check_wind_preview(id: String) -> void:
	var runtime=editor._weather.wind_objects
	var node: MeshInstance3D=editor._view.get_node(id)
	var before: Dictionary=editor._doc.recovery_snapshot()
	var history: int=editor._doc._undo.size(); var dirty: bool=editor._dirty
	var state:=await call_tool("editor_state")
	check(not state.wind_preview and not runtime.enabled and runtime.receivers.is_empty(),"new editor defaults to wind preview off")
	await atomic_reject("set_editor_wind_preview",{"enabled":"yes"})
	check(not runtime.enabled,"invalid wind toggle has no preview side effects")
	await call_tool("set_editor_wind_preview",{"enabled":true})
	for i in 30: await process_frame
	check(runtime.enabled and node.has_meta("wind_original") and editor._environment_panel.wind_preview.button_pressed,"HTTP enables actual wind binding and UI toggle")
	editor._environment_panel.wind_preview.button_pressed=false
	check(not runtime.enabled and runtime.receivers.is_empty() and not node.has_meta("wind_original"),"UI switch restores original materials and stops wind work")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size() and dirty==editor._dirty,"preview switches do not change map/history/dirty state")
	var game_wind=preload("res://scripts/world3d/wind_runtime.gd").new()
	check(game_wind.enabled,"game runtime wind remains enabled by default"); game_wind.free()

func compare_legacy(legacy_path: String) -> void:
	# Render overlays alone, removing animated sky/water from pixel comparison.
	var viewport:=SubViewport.new(); viewport.size=Vector2i(editor._canvas.size)
	viewport.disable_3d=true; viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var current=editor._city.overlay
	var original=load(legacy_path).new()
	viewport.add_child(original); original.setup(editor._city)
	current.reparent(viewport,false); current.position=Vector2.ZERO; current.hide(); current.set_process(false)
	await settle(); await RenderingServer.frame_post_draw
	var before: Image=viewport.get_texture().get_image()
	original.hide(); original.set_process(false); current.show(); current.set_process(true)
	current.refresh(); await settle(); await RenderingServer.frame_post_draw
	var after: Image=viewport.get_texture().get_image()
	check(before.get_data()==after.get_data(),"cached overlay matches original drawing pixel for pixel")
	before.save_png(directory.path_join("overlay_before.png")); after.save_png(directory.path_join("overlay_after.png"))
	# Exercise retained road commands, including fractional screen translation.
	var center: Vector3=editor._orbit_center+Vector3(2.123,0,1.237)
	await call_tool("set_editor_camera",{"center":[center.x,center.y,center.z]})
	await settle(); await RenderingServer.frame_post_draw
	var panned: Image=viewport.get_texture().get_image()
	current.hide(); current.set_process(false); original.show(); original.set_process(true)
	await settle(); await RenderingServer.frame_post_draw
	var legacy_panned: Image=viewport.get_texture().get_image()
	panned.save_png(directory.path_join("pan_after.png")); legacy_panned.save_png(directory.path_join("pan_before.png"))
	check(panned.get_data()==legacy_panned.get_data(),"retained road pan matches original drawing pixel for pixel")
	current.show(); current.set_process(true)
	print("OVERLAY_IMAGES ",directory)
	current.reparent(editor._canvas,false); original.queue_free(); viewport.queue_free()
