extends "res://tools/test_world3d_roads.gd"
func bridge_spec() -> Dictionary: return {"id":"crossing","segment":0,"t":.5,"width":5,"approach":3,"rail_height":1.1}
func run() -> void:
	create_timer(300).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("road_links_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); var ground:=doc.add_box("ground",Vector3(0,-.25,0),Vector3(160,.5,140)); doc.add_box("stone",Vector3(-62.5,2.75,0),Vector3(35,.5,12)); check(doc.save(map_path)==OK,"temporary linked road map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30110
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"road connection HTTP starts")
	var definitions: Array=(await rpc("tools/list")).result.tools; check(definitions.size()==118 and definitions.any(func(t):return t.name=="get_road_connectivity" and t.annotations.readOnlyHint),"118 tools expose bridge linkage and readonly network checks")
	await call_tool("generate_waterway",{"id":"river","ground_ids":[ground],"points":[[0,-55],[0,55]],"bridges":[bridge_spec()]})
	var before: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size()
	var linked:=await call_tool("connect_waterway_bridge",{"waterway_id":"river","bridge_id":"crossing"})
	if not linked.get("ok",false): quit(1); return
	check(editor._doc._undo.size()==history+1 and editor._doc.records==before.records,"bridge connects without duplicating physical deck")
	var after: Dictionary=editor._doc.recovery_snapshot(); await call_tool("undo"); check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"link undo restores graph only"); await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"link redo exact")
	history=editor._doc._undo.size(); await call_tool("connect_waterway_bridge",{"waterway_id":"river","bridge_id":"crossing"}); check(history==editor._doc._undo.size(),"repeat link is no-op")
	await atomic_reject("connect_waterway_bridge",{"waterway_id":"river","bridge_id":"missing"})
	await atomic_reject("generate_waterway",{"id":"river","width":15}); await atomic_reject("remove_waterway",{"id":"river"})
	var linked_node: Dictionary=City.resolve(editor._doc.map_meta).roads.nodes[0].duplicate(true); linked_node.position[0]+=1
	await atomic_reject("update_road_graph",graph_request({"nodes":[linked_node]})); await atomic_reject("update_road_graph",graph_request({"remove_edges":[linked.edge_id]}))
	await atomic_reject("create_road_path",{"points":[linked.endpoints[0],[20,0,20]],"width":5})
	# The panel invokes the same transaction and retains the chosen bridge.
	var road_panel: VBoxContainer=editor._city.panel.road_surface_panel
	for button in road_panel.host.find_children("*","Button",true,false):
		if button.text=="解除所选桥梁路网绑定": button.pressed.emit(); break
	check(not City.resolve(editor._doc.map_meta).roads.edges.any(func(e):return e.has("bridge_ref")),"UI bridge unlink shares graph operation"); await call_tool("undo")
	await call_tool("create_road_path",{"points":[[-65,3,0],[-48,3,0],[-11,0,0]],"width":6})
	await call_tool("create_road_path",{"points":[[11,0,0],[58,0,0]],"width":6})
	var audit:=await call_tool("get_road_connectivity"); check(audit.components.size()==1 and audit.dead_end_nodes.size()==2,"approach roads and bridge form one connected component")
	if not audit.buildability.ok: print(audit.buildability)
	var preview:=await call_tool("preview_road_surface",{"material_id":"pack:default:paving/historic_cobble/material"})
	if not preview.get("ok",false): quit(1); return
	await atomic_reject("generate_road_surface",{"lift":.04}); await atomic_reject("generate_road_surface",{"plan_token":"stale"})
	await call_tool("generate_road_surface",{"material_id":"pack:default:paving/historic_cobble/material","plan_token":preview.plan_token})
	check(editor._doc.records.any(func(r):return r.get("road_mesh",{}).has("grade")),"ramp patches store actual sloped geometry")
	check(not editor._doc.records.filter(func(r):return r.has("road_mesh")).any(func(r):return Foot.record_shapes(r).any(func(s):return Geometry2D.is_point_in_polygon(Vector2.ZERO,s.polygon))),"road paving does not duplicate bridge surface")
	await call_tool("generate_waterway",{"id":"river"})
	var edge: Dictionary=City.resolve(editor._doc.map_meta).roads.edges[0].duplicate(true); edge.locked=true; await call_tool("update_road_graph",graph_request({"edges":[edge]})); await atomic_reject("disconnect_waterway_bridge",{"edge_id":linked.edge_id}); await call_tool("undo")
	await call_tool("disconnect_waterway_bridge",{"edge_id":linked.edge_id}); check((await call_tool("get_road_connectivity")).components.size()==2,"unlink preserves approach roads and separates graph"); await call_tool("undo")
	await call_tool("save_editor_draft"); await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"sloped PBR and linked road graph survive reopen"); await call_tool("save_world")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[-10,1,0],"distance":100,"pitch":-45,"yaw":20}); await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("road_links.png"))
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"saved linked road runtime loads")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0]); Stream.sync(loaded[0],host,Vector3.ZERO); await physics()
		var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.25
		for direction in [1,-1]:
			body.position=Vector3(-63,4.08,0) if direction==1 else Vector3(56,1.08,0); var grounded:=true
			for i in 1100:
				await physics_frame; body.velocity=Vector3(10*direction,-2,0); body.move_and_slide()
				if i>5: grounded=grounded and body.is_on_floor()
				if body.position.x>56 and direction==1 or body.position.x< -63 and direction==-1: break
			check(grounded and (body.position.x>56 if direction==1 else body.position.x< -63),"2.1m capsule traverses upper road, ramp, bridge and opposite bank direction %d"%direction)
			host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-30,8,0),Vector3(-30,-1,0)))
		host.free()
	if is_instance_valid(loader): loader.queue_free()
	print("ROAD_CONNECTION_ARTIFACTS "+directory); print("ROAD_CONNECTIONS_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
