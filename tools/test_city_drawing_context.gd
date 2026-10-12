extends "res://tools/test_world3d_mcp.gd"

func click_world(point:Vector3)->void:
	var at:Vector2=editor._camera.unproject_position(point)+editor._canvas.global_position
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at
		Input.parse_input_event(event);await settle()

func key(code:Key)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=down;Input.parse_input_event(event);await settle()

func choose(control:OptionButton,id:String)->void:
	for index in control.item_count:
		if control.get_item_metadata(index)==id:control.select(index);control.item_selected.emit(index);return

func run()->void:
	create_timer(150).timeout.connect(func():quit(2));Engine.max_fps=60;rpc_timeout_ms=60000
	root.size=Vector2i(1280,800);root.content_scale_size=root.size
	var directory:=Paths.cache_directory("city_draw_context_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();check(doc.save(path)==OK,"isolated drawing fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31866
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"drawing fixture serves real HTTP MCP")
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":120})
	var city=editor._city;var fort=city.panel.fortification_panel
	var initial:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	editor._dock_tabs.current_tab=11;await settle();fort.new_region();fort.draw_button.pressed.emit();await settle()
	check(city.drawing and city.fortification_draft and city.draw_tab_index==11 and editor._dock_tabs.current_tab==11,"castle draw button stays in its standalone page")
	check((await call_tool("editor_state")).fortification_drawing,"MCP observes the same castle drawing state")
	await click_world(Vector3(-20,0,0));check(city.pending.size()==1,"real canvas pointer collects castle point on page 11")
	await key(KEY_ENTER)
	check(city.drawing and city.draw_tab_index==11 and editor._dock_tabs.current_tab==11 and fort.info.text.contains("至少"),"invalid path retains its drawing context and local error")
	await click_world(Vector3(20,0,0));await key(KEY_ENTER)
	check(not city.drawing and city.draw_tab_index==-1 and fort.current.points.size()==2 and editor._dock_tabs.current_tab==11,"Enter finishes castle path without switching panels")
	check(fort.info.text.contains("预览") and equivalent(initial,editor._doc.recovery_snapshot()) and editor._doc._undo.size()==history,"finished castle draft remains a read-only plan with local next-step feedback")
	var path_points:Array=fort.current.points.duplicate(true)
	fort.draw_button.pressed.emit();await click_world(Vector3(0,0,10));await key(KEY_ESCAPE)
	check(not city.drawing and not city.fortification_draft and city.pending.is_empty() and city.draw_tab_index==-1 and equivalent(path_points,fort.current.points) and editor._dock_tabs.current_tab==11,"Escape clears only the temporary path and retains castle page")
	fort.draw_button.pressed.emit();await click_world(Vector3(0,0,10));check(city.finish_draw(true).ok and editor._dock_tabs.current_tab==11,"explicit cancellation also retains the originating page")
	choose(fort.fields.fields.shape,"ellipse");fort.draw_button.pressed.emit();await click_world(Vector3(-30,0,-20));await click_world(Vector3(30,0,20));await key(KEY_ENTER)
	check(not city.drawing and is_equal_approx(fort.fields.values().radius_x,30.) and is_equal_approx(fort.fields.values().radius_z,20.) and editor._dock_tabs.current_tab==11,"ring bounds use real canvas input on the standalone castle page")
	fort.draw_button.pressed.emit();await click_world(Vector3(0,0,10));editor._dock_tabs.current_tab=1
	var motion:=InputEventMouseMotion.new();motion.position=editor._canvas.get_global_rect().get_center();Input.parse_input_event(motion);await settle()
	check(not city.drawing and city.pending.is_empty() and city.draw_tab_index==-1 and editor._dock_tabs.current_tab==1,"leaving the owner page cancels its draft without navigating back")
	var castle_recipe:Dictionary=fort.request()
	check(city.begin_draw(7,0,"ground").ok and city.draw_tab_index==9 and editor._dock_tabs.current_tab==9,"ordinary road drawing still belongs to the city page")
	await settle();await click_world(Vector3(-20,0,25));await click_world(Vector3(20,0,25))
	check(city.pending.size()==2 and city.finish_draw().ok and city.draw_tab_index==-1 and editor._dock_tabs.current_tab==9,"real road pointer input and direct finish use the original city context")
	check(editor._doc._undo.size()==history+1 and city.data.roads.edges.size()==1 and equivalent(castle_recipe,fort.request()),"road completion uses one shared undo transaction and preserves castle draft")
	await call_tool("undo");check(equivalent(initial,editor._doc.recovery_snapshot()),"shared HTTP undo restores the road operation")
	city.begin_draw(7,0,"ground");await click_world(Vector3(0,0,25));await key(KEY_ESCAPE)
	check(not city.drawing and editor._dock_tabs.current_tab==9 and equivalent(initial,editor._doc.recovery_snapshot()),"road Escape remains side-effect-free on the city page")
	editor._mcp.stop();editor.queue_free();await settle()
	print("CITY_DRAWING_CONTEXT_ARTIFACTS ",directory);print("CITY_DRAWING_CONTEXT_FINISHED failures=",failed);quit(0 if failed==0 else 1)
