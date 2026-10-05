extends "res://tools/test_world3d_bridges.gd"
func run() -> void:
	create_timer(420).timeout.connect(func():quit(2)); Engine.max_fps=60
	root.size=Vector2i(1500,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("road_stone_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("stone",Vector3(0,-5.25,0),Vector3(130,.5,80))
	var water_id: String=doc.add_box("water",Vector3(0,-2.04,0),Vector3(30,.08,60)); doc._find(water_id).collision="none"
	for side in [-1,1]: doc.add_box("grass",Vector3(side*35,-.25,0),Vector3(40,.5,24))
	var data:=City.resolve({}); var graph:={"nodes":[],"edges":[]}
	for i in 4: graph.nodes.append({"id":"n%d"%i,"position":[[-50,-26,26,50][i],0,0]})
	for i in 3: graph.edges.append({"id":"e%d"%i,"from":"n%d"%i,"to":"n%d"%(i+1),"width_start":6.,"width_end":6.,"kind":"bridge" if i==1 else "ground","name":"测试旧桥" if i==1 else "引道"})
	data.roads=graph; var settings:=RoadPlan.defaults(); settings.material_id="pack:default:paving/outdoor_flagstone/material"
	var plan:=RoadPlan.build(graph,settings); check(plan.ok,"initial old bridge slab planned")
	var paint:=preload("res://scripts/world_editor/road_tools.gd").new(); var material:=preload("res://scripts/world_editor/surface_material_library.gd").new().find(settings.material_id)
	var parts: Array=[]
	for r in plan.records:
		check(paint.paint_default(r,material).ok,"old road PBR"); doc.records.append(r); parts.append({"key":r.road_source,"id":r.uuid,"signature":Surface.signature(r),"paint_signature":City.token(r.surface_paint)})
	data.road_surface={"version":1,"settings":settings,"graph_token":City.token(graph),"parts":parts}; doc.map_meta.editor_layout=data
	check(doc.save(map_path)==OK,"temporary old bridge road map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=31430
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"road stone HTTP MCP starts")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.size()==118 and defs.filter(func(d):return d.name=="generate_bridge")[0].inputSchema.properties.has("auto_clearance"),"current 3D tools discover navigation clearance schema")
	var args:={"id":"stone_e1","road_edge_id":"e1","start":[-20,.025,0],"end":[20,.025,0],"width":7.2,"depth":5.,"camber":.6}
	var before: Dictionary=editor._doc.recovery_snapshot(); var preview:=await call_tool("preview_bridge",args)
	if not preview.get("ok",false): quit(1); return
	check(preview.navigation.applicable and preview.navigation.clearance>=2.5 and preview.camber>args.camber,"real water automatically raises the bridge to a 2m wide / 2.5m high passage")
	await atomic_reject("generate_bridge",args.merged({"auto_clearance":false},true))
	await call_tool("set_object_transform",{"id":water_id,"position":[0,-.54,0]})
	await atomic_reject("generate_bridge",args)
	await call_tool("undo")
	check(not preview.trimmed_roads.is_empty() and equivalent(before,editor._doc.recovery_snapshot()),"conversion preview is readonly and identifies old road slabs")
	for bad in [{"road_edge_id":"e0"},{"plan_token":"stale"},{"width":6},{"start":[-20,.025,1]}]: await atomic_reject("generate_bridge",args.merged(bad,true))
	var protected: String=preview.trimmed_roads[0]; await call_tool("set_object_properties",{"ids":[protected],"locked":true}); await atomic_reject("generate_bridge",args); await call_tool("undo")
	var retained: Node=editor._view.get_children().filter(func(n):return not n is MeshInstance3D or not n.has_meta("ground_batch_record") or not n.get_meta("ground_batch_record").has("road_mesh"))[0]; var retained_id:=retained.get_instance_id()
	await call_tool("generate_bridge",args.merged({"plan_token":preview.plan_token})); var after: Dictionary=editor._doc.recovery_snapshot()
	check(is_instance_valid(retained) and retained.get_instance_id()==retained_id,"bridge edit retains unrelated terrain render nodes")
	check(City.resolve(editor._doc.map_meta).roads.edges[1].stone_bridge.id==args.id,"bridge linked to the original edge")
	check((await call_tool("generate_bridge",args)).get("changed",true)==false,"same road bridge request is idempotent")
	await call_tool("undo"); check(equivalent(before,editor._doc.recovery_snapshot()),"single undo restores old deck, paint and graph")
	await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"redo exact across bridge, pavement and binding")
	check_no_old_deck()
	await call_tool("preview_road_surface",{}); await call_tool("generate_road_surface",{}); check_no_old_deck()
	var edited: Dictionary=City.resolve(editor._doc.map_meta).roads.nodes[1].duplicate(true); edited.position[0]-=1
	await atomic_reject("update_road_graph",graph_request({"nodes":[edited]}))
	var ui: VBoxContainer=editor._city.panel.bridge_panel; editor._dock_tabs.current_tab=9; ui.refresh(); ui.materials.deck.select(1); ui.load_road(); check(ui.road_edge_id=="e1" and ui.current_id==args.id,"UI reads linked bridge recipe")
	check(not ui.request().has("deck_material_id"),"loading a bridge clears unrelated pending material overrides")
	ui.fields.fields.camber.value=preview.camber+.1; ui.show_preview(); check(not ui.preview.is_empty(),"UI shares bound bridge preview"); ui.apply(); check(is_equal_approx(editor._doc._find(args.id).bridge_mesh.camber,preview.camber+.1),"UI edits bound bridge camber"); await call_tool("undo")
	await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"bound bridge, clipped PBR and graph survive reopen")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,-.5,0],"distance":42,"pitch":-25,"yaw":25}); await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("road_stone.png"))
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"converted bridge runtime loads")
	if loaded[0]!=null:
		cases=[args.merged({"prefab_id":"stone_segmental","camber":preview.camber},true)]; await bridge_runtime(loaded[0])
	print("ROAD_STONE_ARTIFACTS "+directory); print("ROAD_STONE_FINISHED failures=%d"%failed); quit(1 if failed else 0)
func check_no_old_deck() -> void:
	var overlap:=0.0
	var mask: Array=[Vector2(-19.99,-3.59),Vector2(19.99,-3.59),Vector2(19.99,3.59),Vector2(-19.99,3.59)]
	for r in editor._doc.records:
		if not r.has("road_mesh"): continue
		for shape in Foot.record_shapes(r):
			var intersection:=RoadPlan.intersection(Array(shape.polygon).slice(0,-1),mask)
			if not intersection.is_empty(): overlap+=preload("res://scripts/world3d/roof_plan.gd").area(intersection)
	check(overlap<.001,"no leftover old road slab under arches")
