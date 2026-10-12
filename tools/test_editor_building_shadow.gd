extends "res://tools/test_world3d_mcp.gd"
const Preview=preload("res://scripts/world_editor/building_shadow_preview.gd")
const Materials=preload("res://scripts/world3d/surface_materials.gd")
var directory:String

func source_nodes()->Array:
	return Materials.meshes(editor._view).filter(func(n):return n.has_meta("editor_shadow_monitor"))

func run()->void:
	create_timer(180).timeout.connect(func():push_error("editor shadow timeout");quit(2))
	check(Preview.enabled,"validated frozen-building shadows are automatic by default")
	Preview.enabled=true
	root.size=Vector2i(1440,960);root.content_scale_size=root.size
	directory=Paths.cache_directory("editor_shadow_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.1,0),Vector3(80,.2,80))
	check(doc.save(path)==OK,"temporary test map saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	editor._material_directory=directory.path_join("materials")
	root.add_child(editor);editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual loopback MCP started")
	var discovery:=await rpc("tools/list")
	check(discovery.result.tools.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size(),"3D tool discovery unchanged")
	await call_tool("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[0,0,0]}]})
	await settle()
	var nodes:=source_nodes();check(not nodes.is_empty(),"actual generated frozen building has eligible shadow proxies")
	if nodes.is_empty():editor.queue_free();await settle();quit(1);return
	var source:MeshInstance3D=nodes[0];var id:=str(source.name)
	var proxy_node:MeshInstance3D=source.get_meta("building_shadow_proxy")
	check(Materials.meshes(source)==[source],"derived proxy excluded from material and wind catalogs")
	var body_count:=0
	for bodies:Array in editor._bodies_by_uuid.values():
		for body:StaticBody3D in bodies:
			body_count+=1
			check(not body.get_meta("visual").get_meta("editor_shadow_proxy",false),"picking body belongs to authoring mesh")
	check(body_count>0 and not editor._picking_node_enabled(proxy_node),"proxy rejected before synchronous and sliced picking traversal")
	var history:int=editor._doc._undo.size()
	await call_tool("select_objects",{"ids":[id]})
	check(source.material_overlay==null and source.transparency==0 and proxy_node.is_visible_in_tree(),"selection uses separate outline and preserves stable source contract")
	var initial:Transform3D=source.global_transform
	await call_tool("transform_selection",{"translation":[8,0,0]})
	source=editor._view.get_node(id)
	check(source.has_meta("editor_shadow_monitor") and source.get_meta("building_shadow_proxy").global_transform==source.global_transform and source.global_transform!=initial,"HTTP whole-house move carries exact shadow transform")
	await call_tool("undo");await settle()
	source=editor._view.get_node(id)
	check(source.has_meta("editor_shadow_monitor") and source.global_transform.is_equal_approx(initial),"undo recreates eligible source and shadow")
	await call_tool("redo");await call_tool("undo");await settle()
	check(editor._doc._undo.size()==history,"selection and derived shadows add no undo transaction")
	await call_tool("set_floor_view",{"isolation":true,"base_height":100,"floor_height":3,"outside":"dim"});await settle()
	check(source_nodes().is_empty(),"dim excluded floors never gain opaque shadow proxies")
	await call_tool("set_floor_view",{"outside":"hide"});await settle()
	for candidate in source_nodes():check(not candidate.get_meta("building_shadow_proxy").is_visible_in_tree(),"hidden floor hides derived shadow")
	await call_tool("set_floor_view",{"isolation":false});await settle()
	source=editor._view.get_node(id);proxy_node=source.get_meta("building_shadow_proxy")
	source.hide();check(not proxy_node.is_visible_in_tree(),"direct roof/cutaway hiding propagates without polling")
	source.show();check(proxy_node.is_visible_in_tree(),"showing source restores its shadow")
	await call_tool("set_editor_wind_preview",{"enabled":true});await settle()
	check(not source.has_meta("wind_original") and source.has_meta("editor_shadow_monitor"),"wind preview does not bind immutable baked building or its proxy")
	await call_tool("set_editor_wind_preview",{"enabled":false})
	await call_tool("select_objects",{"ids":[]})
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,2,0],"distance":24,"pitch":-25,"yaw":35})
	if DisplayServer.get_name()!="headless":await compare_images()
	await call_tool("save_world")
	var json:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(json.nodes.all(func(n):return n.get("name","")!="OpaqueShadow" and not n.get("extras",{}).has("editor_shadow_proxy")),"actual HTTP export contains no shadow proxy nodes")
	await call_tool("open_world",{"path":path});await settle()
	check(not source_nodes().is_empty(),"save reopen rebuilds only derived editor shadows")
	source=source_nodes()[0];id=str(source.name)
	var material:Material=source.get_active_material(0)
	var connections:int=material.changed.get_connections().size()
	# Equivalent to any unsupported resource mutation: immediately recover the
	# original renderer and disconnect, without an expensive per-frame scan.
	material.emit_changed()
	check(not source.has_meta("building_shadow_proxy") and source.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"material resource change restores original shadows immediately")
	check(material.changed.get_connections().size()<connections,"invalidated resource disconnects weak listeners")
	var refresh_ids:Array[String]=[id]
	editor._refresh_records(refresh_ids);source=editor._view.get_node(id)
	check(source.has_meta("editor_shadow_monitor"),"record rebuild reestablishes the validated immutable contract")
	source.mesh.emit_changed()
	check(not source.has_meta("building_shadow_proxy"),"geometry resource change invalidates shadow")
	editor._refresh_records(refresh_ids);source=editor._view.get_node(id)
	material=source.get_active_material(0);connections=material.changed.get_connections().size()
	await call_tool("select_objects",{"ids":[id]});await call_tool("delete_selection");await settle()
	check(editor._view.get_node_or_null(id)==null and material.changed.get_connections().size()<connections,"deletion removes proxies and disconnects resource listeners")
	await call_tool("undo");await settle();check(not source_nodes().is_empty(),"delete undo restores derived shadows")
	editor.queue_free();await settle()
	print("EDITOR_BUILDING_SHADOW_FINISHED failures=",failed," images=",directory)
	quit(1 if failed else 0)

func compare_images()->void:
	await call_tool("set_environment",{"celestial_cycle":false,"sun_rotation":[-35,-125,0],"sun_energy":1.0,"ambient_energy":.25,"sun_shadows":true})
	for i in 10:await process_frame
	editor._weather.process_mode=Node.PROCESS_MODE_DISABLED
	var nodes:=source_nodes()
	var images:Array[Image]=[]
	for mode in [false,true]:
		for source:MeshInstance3D in nodes:
			source.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			source.get_meta("building_shadow_proxy").visible=mode
		for i in 10:await process_frame
		await RenderingServer.frame_post_draw
		check(editor._camera.get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)>0,"visual comparison renders active directional shadows")
		var image:Image=editor._camera.get_viewport().get_texture().get_image()
		image.save_png(directory.path_join("proxy.png" if mode else "original.png"));images.append(image)
	var before:=images[0].get_data();var after:=images[1].get_data()
	var maximum:=0;var changed:=0
	for i in mini(before.size(),after.size()):
		maximum=maxi(maximum,absi(before[i]-after[i]))
		if before[i]!=after[i]:changed+=1
	print("EDITOR_SHADOW_PIXELS ",JSON.stringify({"max_channel_difference":maximum,"changed_channels":changed,"bytes":before.size(),"directory":directory,"note":"Retained images require visual review; byte differences alone are not a quality verdict."}))
	check(before.size()==after.size(),"same-camera shadow images captured for visual review")
	editor._weather.process_mode=Node.PROCESS_MODE_INHERIT
