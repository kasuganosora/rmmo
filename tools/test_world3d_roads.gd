extends "res://tools/test_world3d_city_layout.gd"
const PlanTest=preload("res://tools/test_road_plan.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
const RoadPlan=preload("res://scripts/world3d/road_plan.gd")
var map_path: String

func zone_request(changes: Dictionary) -> Dictionary:
	return {"expected_token":JSON.stringify(City.resolve(editor._doc.map_meta).get("zones",[])).sha256_text()}.merged(changes)
func physics() -> void:
	for i in 4: await physics_frame
func run() -> void:
	create_timer(240).timeout.connect(func():quit(2))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("roads_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(20,-.3,0),Vector3(220,.6,160)); check(doc.save(map_path)==OK,"isolated road map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=29930
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"road HTTP server starts"); await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.size()==118 and defs.filter(func(d):return d.name=="preview_road_surface")[0].annotations.readOnlyHint,"118 3D tools include readonly road preview")
	await call_tool("create_road_path",{"points":[[-60,0,0],[50,0,0]],"width":6})
	await call_tool("create_road_path",{"points":[[0,0,-40],[0,0,40]],"width":6})
	await atomic_reject("generate_road_surface",{})
	var split:=await call_tool("split_road_intersections"); check(split.added_nodes==1 and split.added_edges==2,"real HTTP intersection split")
	var count: int=editor._doc._undo.size(); await call_tool("split_road_intersections"); check(editor._doc._undo.size()==count,"repeat split creates no undo entry")
	var curve:=PlanTest.graph([[[65,0,-30],[105,0,30]]]); curve.nodes[0].id="curve_a"; curve.nodes[1].id="curve_b"; curve.edges[0].id="curve"; curve.edges[0].from="curve_a"; curve.edges[0].to="curve_b"; curve.edges[0].controls=[[65,0,20],[100,0,-25]]
	await call_tool("update_road_graph",graph_request(curve))
	var material_args:={"material_id":"pack:default:paving/historic_cobble/material"}
	var preview:=await call_tool("preview_road_surface",material_args)
	if not preview.ok: editor.queue_free(); await settle(); quit(1); return
	await atomic_reject("generate_road_surface",material_args.merged({"plan_token":"stale"}))
	await call_tool("set_floor_view",{"isolation":true,"base_height":30}); await atomic_reject("generate_road_surface",material_args); await call_tool("undo")
	count=editor._doc._undo.size()
	await call_tool("generate_road_surface",material_args.merged({"plan_token":preview.plan_token}))
	check(editor._doc._undo.size()==count+1,"all road chunks generated in one undo")
	var roads: Array=editor._doc.records.filter(func(r):return r.has("road_mesh")); var baseline: Dictionary=editor._doc.recovery_snapshot()
	check(roads.size()==preview.chunks and roads.all(func(r):return r.has("surface_paint")),"all road chunks have default PBR surface paint")
	var sample_node: MeshInstance3D=editor._doc._mesh(roads[0]); var textured:=false
	for i in sample_node.mesh.get_surface_count():
		var mat: Material=sample_node.mesh.surface_get_material(i)
		if mat is StandardMaterial3D and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null: textured=true
	check(textured,"generated runtime mesh actually binds albedo and normal textures"); sample_node.free()
	await call_tool("undo"); check(not editor._doc.records.any(func(r):return r.has("road_mesh")),"undo removes physical geometry and manifest together")
	await call_tool("redo"); check(equivalent(baseline,editor._doc.recovery_snapshot()),"redo restores records and road manifest")
	count=editor._doc._undo.size(); await call_tool("generate_road_surface"); check(editor._doc._undo.size()==count,"unchanged generation is a no-op and retains material settings")
	var id: String=roads[0].uuid
	await call_tool("set_object_properties",{"ids":[id],"locked":true})
	await atomic_reject("generate_road_surface",{}); await atomic_reject("detach_road_surface",{})
	await call_tool("set_object_properties",{"ids":[id],"locked":false})
	# Node protection applies to generating from the entire source graph.
	var node: Dictionary=City.resolve(editor._doc.map_meta).roads.nodes[0].duplicate(true); node.locked=true
	await call_tool("update_road_graph",graph_request({"nodes":[node]})); await atomic_reject("generate_road_surface",{})
	node.locked=false; await call_tool("update_road_graph",graph_request({"nodes":[node]})); await call_tool("generate_road_surface")
	# Actual road corridor blocks house placement; support-ground exemption never skips roads.
	await atomic_reject("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[0,0,0]}]})
	var zone:={"id":"market","name":"集市保留地","polygon":[[-55,15],[-10,15],[-10,55],[-55,55]],"min_y":-2,"max_y":100,"purpose":"reserved_passage"}
	await call_tool("update_planning_zones",zone_request({"zones":[zone]}))
	await atomic_reject("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[-30,0,30]}]})
	zone.hidden=true; await call_tool("update_planning_zones",zone_request({"zones":[zone]}))
	await atomic_reject("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[-30,0,30]}]})
	await atomic_reject("update_planning_zones",zone_request({"remove":["market"]}))
	await atomic_reject("update_planning_zones",{"expected_token":"stale","zones":[]})
	var bad:=zone.duplicate(true); bad.id="crossed"; bad.polygon=[[0,0],[10,10],[0,10],[10,0]]
	await atomic_reject("update_planning_zones",zone_request({"zones":[bad]}))
	zone.hidden=false; await call_tool("update_planning_zones",zone_request({"zones":[zone]}))
	# UI polygon gesture shares the same transaction and schema.
	editor._dock_tabs.current_tab=9
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":160})
	var zone_ui:={"id":"ui_zone","name":"画布区域","min_y":0,"max_y":100,"purpose":"no_build","locked":false,"hidden":false}
	check(editor._city.begin_zone(zone_ui).ok,"UI begins polygon drawing")
	for p in [Vector3(30,0,20),Vector3(50,0,20),Vector3(50,0,35),Vector3(30,0,35)]:
		var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=editor._canvas.global_position+editor._camera.unproject_position(p); Input.parse_input_event(event); await settle()
		var release:=event.duplicate(); release.pressed=false; Input.parse_input_event(release); await settle()
	check(editor._city.pending.size()==4,"canvas picks zone vertices")
	var enter:=InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; Input.parse_input_event(enter); await settle()
	if editor._city.busy(): print("ZONE_DRAW_FAILURE ",editor._status.text," ",editor._city.pending," ",editor._city.zone_draft); editor._city.finish_draw(true)
	check(City.resolve(editor._doc.map_meta).zones.size()==2 and not editor._city.busy(),"Enter closes one polygon transaction")
	await call_tool("undo"); check(City.resolve(editor._doc.map_meta).zones.size()==1,"zone drawing undo"); await call_tool("redo")
	# Hand-painted material must survive a no-op; incompatible geometry must fail atomically.
	await call_tool("clear_surface_material",{"id":id})
	await call_tool("generate_road_surface"); check(not editor._doc._find(id).has("surface_paint"),"manual material clearing is retained")
	var original_graph: Dictionary=City.resolve(editor._doc.map_meta).roads
	var edits: Array=original_graph.edges.duplicate(true)
	for edge in edits: edge.width_start=10; edge.width_end=10
	await call_tool("update_road_graph",graph_request({"edges":edits})); check((await call_tool("get_city_layout")).surface_stale,"source edits explicitly mark old pavement stale")
	await atomic_reject("generate_road_surface",{})
	await call_tool("undo"); await call_tool("undo") # Undo source edit and manual clear (generation was no-op).
	await call_tool("generate_road_surface")
	var old_parts: Array=City.resolve(editor._doc.map_meta).road_surface.parts.duplicate(true)
	# Add a far road: all earlier IDs and geometry signatures remain.
	await call_tool("create_road_path",{"points":[[-70,0,-74],[-30,0,-74]],"width":4}); var diff:=await call_tool("generate_road_surface")
	check(diff.diff.added>0 and diff.diff.updated==0,"distant branch only adds chunks")
	check(old_parts.all(func(p):return Surface.signature(editor._doc._find(p.id))==p.signature),"unaffected pavement retains IDs and signatures")
	await call_tool("save_editor_draft"); await call_tool("save_world")
	baseline=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path})
	check(equivalent(baseline.records,editor._doc.records) and equivalent(baseline.map_meta,editor._doc.map_meta),"roads, zones, PBR and stable ownership survive reopening")
	await call_tool("generate_road_surface")
	if DisplayServer.get_name()!="headless":
		await call_tool("set_editor_camera",{"projection":"perspective","center":[20,0,0],"distance":155,"pitch":-65,"yaw":10})
		await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(directory.path_join("roads.png"))
		var image_response:=await rpc("tools/call",{"name":"preview_map","arguments":{"include_layout":true}}); check(image_response.result.content.any(func(p):return p.type=="image"),"real HTTP preview renders road surface and planning overlay")
		await call_tool("set_editor_camera",{"projection":"perspective","center":[0,0,0],"distance":23,"pitch":-55,"yaw":25}); editor._grid.hide(); await settle(); await RenderingServer.frame_post_draw
		var closeup:=await rpc("tools/call",{"name":"preview_map","arguments":{}})
		for part in closeup.result.content:
			if part.type=="image":
				var shot:=Image.new(); shot.load_png_from_buffer(Marshalls.base64_to_raw(part.data)); shot.save_png(directory.path_join("road_material.png"))
	# Remove editor physics before loading exactly the saved runtime geometry.
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"saved road runtime loads")
	if loaded[0]!=null: await runtime_checks(loaded[0])
	print("ROAD_ARTIFACTS "+directory); print("WORLD3D_ROADS_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)

func runtime_checks(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3.ZERO); await physics()
	var space:=host.get_world_3d().direct_space_state
	for p in [Vector3(0,0,0),Vector3(32,0,0),Vector3(-32,0,0),Vector3(0,0,32)]:
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP))
		check(not hit.is_empty() and absf(hit.position.y-.025)<.003,"real collision at junction / chunk seam "+str(p))
	var empty:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(15,2,15),Vector3(15,-1,15)))
	check(not empty.is_empty() and absf(empty.position.y)<.001,"empty cell corner has only original ground, no phantom road collision")
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.2
	for points in [[Vector3(-40,1.08,0),Vector3(40,1.08,0)],[Vector3(0,1.08,-35),Vector3(0,1.08,35)]]:
		body.position=points[0]; body.velocity=Vector3.ZERO; var direction: Vector3=(points[1]-points[0]).normalized(); var grounded:=true
		for i in 630:
			await physics_frame
			body.velocity=direction*9+Vector3.DOWN*2; body.move_and_slide()
			if i>5: grounded=grounded and body.is_on_floor()
			if (points[1]-body.position).dot(direction)<.15: break
		check(grounded and (points[1]-body.position).dot(direction)<.3,"2.1m capsule walks through junction and 32m seams without snagging")
	host.free()
