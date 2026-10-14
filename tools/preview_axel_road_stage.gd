extends "res://tools/build_axel_town_roads.gd"
## Read-only intermediate composition review; never marks the build accepted.
func persist()->void:
	report.failures=failed
	var f:=FileAccess.open(OUT.path_join("intermediate_preview_v2.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"));f.close()

func run()->void:
	create_timer(300).timeout.connect(func():check(false,"preview timeout");persist();quit(2))
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	report={"phase":"intermediate_only","images":[],"candidate_sha256":FileAccess.get_sha256(CANDIDATE)}
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=CANDIDATE;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor);await settle();await wait_view()
	var probe:=TCPServer.new();port=31570
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"read-only preview HTTP")
	await call_tool("select_objects",{"ids":[]})
	await capture("intermediate2_north_shoulder",{"projection":"perspective","center":[185,8,48],"distance":50,"yaw":-35,"pitch":-26})
	await capture("intermediate2_church_shoulder",{"projection":"perspective","center":[285,7,88],"distance":45,"yaw":40,"pitch":-27})
	await capture("intermediate2_bridge_3",{"projection":"perspective","center":[285,4.5,245.5],"distance":43,"yaw":30,"pitch":-27})
	var requests:Array=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("bridges.json"))).requests
	for bridge:Dictionary in requests:
		var center:Vector3=(City.vec(bridge.start)+City.vec(bridge.end))*.5
		await capture("intermediate2_"+bridge.id,{"projection":"perspective","center":City.xyz(center-Vector3.UP),"distance":43,"yaw":30,"pitch":-27})
	for view:Dictionary in editor._doc.map_meta.editor_layout.bookmarks:
		if view.id=="s1_bridge_banks":await capture("intermediate2_reference_s1",view.camera)
	check(FileAccess.get_sha256(CANDIDATE)==report.candidate_sha256,"read-only candidate unchanged")
	persist();editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)
