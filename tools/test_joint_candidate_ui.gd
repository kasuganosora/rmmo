extends "res://tools/test_joint_candidate_http.gd"

func run()->void:
	output="D:/code/rmmo_runtime/review_artifacts/joint_candidate_20261017/ui.json";rpc_timeout_ms=120000
	create_timer(400).timeout.connect(func():check(false,"timeout");finish())
	root.size=Vector2i(1440,1000);root.content_scale_size=root.size
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("http.json")))
	check(source.failures==0,"UI uses passing joint map as read-only source")
	directory=Paths.cache_directory("joint_ui_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc=Doc.open_file(source.map_path);check(doc!=null and doc.save(map_path)==OK,"UI edits separate temporary native map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job.active:await process_frame
	editor._safety.enabled=false
	var probe:=TCPServer.new();port=32600
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"UI regression loopback starts")
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":105})
	# Change a real native setting so preview exercises meshes and application,
	# not just an empty no-op ghost. This map is a disposable UI-only copy.
	editor._city.panel.road_surface_panel.material_select.select(0)
	var panel=editor._city.panel.joint_panel;choose_source(panel,"surface")
	var before:Dictionary=editor._doc.recovery_snapshot();panel.capture(false);panel.preview()
	check(panel.last_result.get("changed",false) and is_instance_valid(panel.ghost) and panel.ghost.get_child_count()>0,"UI previews actual changed road meshes")
	check(equivalent(before,editor._doc.recovery_snapshot()),"visible UI ghosts preserve live author records")
	panel.invalidate();panel.steps.clear();panel.refresh_queue()
	await ui_cases()
	check(not equivalent(before,editor._doc.recovery_snapshot()),"UI apply publishes the previewed native material change")
	await finish()
