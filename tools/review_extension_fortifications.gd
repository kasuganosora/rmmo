extends "res://tools/test_world3d_mcp.gd"
func run()->void:
	create_timer(420).timeout.connect(func():quit(2));rpc_timeout_ms=120000
	var directory:=Paths.cache_directory("fortification_visual_extensions_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.5,0),Vector3(700,1,200));check(doc.save(path)==OK,"visual fixture")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=30950
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP")
	for item:Dictionary in [{"id":"straight","shape":"path","points":[[-230,0],[-170,0]],"gates":[{"id":"gate","segment":0,"t":.5,"width":6.,"height":5.,"open":1.}]},{"id":"circle","shape":"ellipse","center_x":0.,"center_z":0.,"radius_x":35.,"radius_z":35.,"gates":[{"id":"gate","angle":0.,"width":6.,"height":5.,"open":1.}]},{"id":"ellipse","shape":"ellipse","center_x":200.,"center_z":0.,"radius_x":50.,"radius_z":30.,"gates":[{"id":"gate","angle":0.,"width":6.,"height":5.,"open":1.}]}]:
		item.merge({"style":"medieval_stone","tower_layout":"manual","tower_count":4,"height":7.5,"thickness":3.5})
		await call_tool("generate_fortification",item)
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size;editor._grid.hide()
	for shot:Array in [["straight",[-200,4,0],80,-20,25],["straight_detail",[-200,4,0],18,-8,10],["circle",[0,3,0],135,-35,35],["circle_detail",[35,5,0],20,-12,90],["ellipse",[200,3,0],155,-35,35],["ellipse_detail",[250,5,0],20,-12,90]]:
		await call_tool("set_editor_camera",{"projection":"perspective","center":shot[1],"distance":shot[2],"pitch":shot[3],"yaw":shot[4]});await settle();await RenderingServer.frame_post_draw
		editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(shot[0]+".png"))
	print("FORT_VISUAL_ARTIFACTS ",directory);editor._mcp.stop();editor.queue_free();await settle();print("FORT_VISUAL_FINISHED failures=",failed);quit(1 if failed else 0)
