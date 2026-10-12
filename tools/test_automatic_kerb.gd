extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
const GraphTest=preload("res://tools/test_road_plan.gd")

func run()->void:
	rpc_timeout_ms=90000;create_timer(540).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("automatic_kerb_%d"%OS.get_process_id());var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.3,0),Vector3(150,.6,150));check(doc.save(path)==OK,"temporary map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP server started")
	var defs:Array=(await rpc("tools/list")).result.tools
	for name_ in ["preview_road_surface","generate_road_surface"]:
		var spec:Dictionary=defs.filter(func(d):return d.name==name_)[0];check(spec.inputSchema.properties.has("kerb_width"),name_+" discovers kerb schema")
	await call_tool("create_road_path",{"points":[[-45,0,0],[45,0,0]],"width":5})
	await call_tool("create_road_path",{"points":[[0,0,-28],[0,0,28]],"width":5})
	var args:={"kerb_enabled":true,"material_id":"pack:default:paving/historic_cobble/material"}
	var before:=doc.recovery_snapshot()
	var preview:=await call_tool("preview_road_surface",args)
	check(equivalent(before,doc.recovery_snapshot()),"preview leaves graph and records unchanged")
	if not preview.get("ok",false):editor.queue_free();await settle();quit(1);return
	check(preview.kerb_length>200,"preview reports exposed boundary length")
	await call_tool("generate_road_surface",args.merged({"plan_token":preview.plan_token}))
	var roads:Array=doc.records.filter(func(r):return r.has("road_mesh"));check(roads.any(func(r):return r.road_mesh.has("kerbs")),"continuous profiles stored in road chunks")
	check(City.analyze(City.resolve(doc.map_meta).roads).diagnostics.is_empty(),"same-height crossing automatically connected")
	var generated:=doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,doc.recovery_snapshot()),"undo restores graph and geometry together")
	await call_tool("redo");check(equivalent(generated,doc.recovery_snapshot()),"redo restores generated road")
	await call_tool("generate_road_surface",{"kerb_width":2},false)
	await call_tool("generate_road_surface",{"kerb_material_id":"missing"},false)
	check(equivalent(generated,doc.recovery_snapshot()),"invalid settings/material have no side effects")
	var graph:Dictionary=City.resolve(doc.map_meta).roads;var node:Dictionary=graph.nodes[0].duplicate(true);node.position[0]-=3
	await call_tool("update_road_graph",{"expected_token":City.token(graph),"nodes":[node]})
	check(City.resolve(doc.map_meta).road_surface.graph_token==City.token(City.resolve(doc.map_meta).roads),"node move regenerates edging automatically")
	check(not equivalent(generated.records,doc.recovery_snapshot().records),"node move changes actual derived geometry")
	await call_tool("undo");check(equivalent(generated,doc.recovery_snapshot()),"one undo restores both node movement and kerbs")
	await call_tool("redo")
	var edited:=doc.recovery_snapshot()
	await call_tool("create_road_path",{"points":[[20,0,0],[20,0,18]],"width":4})
	check(City.resolve(doc.map_meta).road_surface.graph_token==City.token(City.resolve(doc.map_meta).roads),"new branch automatically connects and opens kerb at junction")
	await call_tool("undo");check(equivalent(edited,doc.recovery_snapshot()),"undo new branch restores road and exposed edges")
	var sample:Dictionary=doc.records.filter(func(r):return r.get("road_mesh",{}).has("kerbs"))[0]
	sample.editor_locked=true
	var protected:=doc.recovery_snapshot()
	graph=City.resolve(doc.map_meta).roads;node=graph.nodes[0].duplicate(true);node.position[0]-=2
	await call_tool("update_road_graph",{"expected_token":City.token(graph),"nodes":[node]},false)
	check(equivalent(protected,doc.recovery_snapshot()),"locked derived road blocks graph and geometry atomically")
	sample.erase("editor_locked")
	var panel:VBoxContainer=editor._city.panel.road_surface_panel
	check(panel.settings.fields.has("kerb_enabled") and panel.settings.fields.has("kerb_height"),"UI exposes same automatic kerb parameters")
	panel.settings.fields.kerb_height.value=.14
	panel.preview();check(not panel.token.is_empty(),"UI previews raised kerb")
	panel.apply_surface();check(City.resolve(doc.map_meta).road_surface.settings.kerb_height==.14,"UI applies shared road transaction")
	await call_tool("undo")
	await call_tool("select_objects",{"ids":[]});await settle()
	var deadline:=Time.get_ticks_msec()+30000
	while editor._ground_batches.stats().get("pending_groups",0)>0 and Time.get_ticks_msec()<deadline:await process_frame
	print("KERB_BATCH ",editor._ground_batches.stats())
	var stats:Dictionary=editor._ground_batches.stats();check(stats.get("source_surfaces",0)>stats.get("render_surfaces",0),"actual static batching reduces surfaces")
	await review(doc)
	await call_tool("save_world")
	var reopened=Doc.open_file(path);check(reopened!=null,"saved map reopens")
	check(reopened.records.any(func(r):return r.has("road_kerb_material")),"kerb materials persist")
	editor._doc=reopened
	var regenerated:Dictionary=editor._roads.prepare({})
	check(regenerated.ok,"saved native road ownership signatures still permit regeneration")
	if not regenerated.ok:print(regenerated)
	editor._doc=doc
	editor.free();await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start.call_deferred(path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"runtime worker geometry and texture preparation loads kerbs")
	if loaded[0]!=null:loaded[0].free()
	await process_frame
	print("AUTOMATIC_KERB_FAILURES ",failed);quit(0 if failed==0 else 1)

func review(doc:RefCounted)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1280,900);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.36,.42,.48);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.75,.8,.9);env.environment.ambient_light_energy=.65;vp.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-25,0);sun.shadow_enabled=true;sun.light_energy=1.25;vp.add_child(sun)
	for record in doc.records:
		var visual:MeshInstance3D=doc._mesh(record)
		if not record.has("road_mesh"):
			var material:=StandardMaterial3D.new();material.albedo_color=Color(.18,.24,.10);visual.material_override=material
		vp.add_child(visual)
	var cam:=Camera3D.new();cam.position=Vector3(13,12,15);vp.add_child(cam);cam.look_at(Vector3(0,0,0));cam.fov=55
	await settle();await RenderingServer.frame_post_draw
	var output:="D:/code/rmmo_runtime/review_artifacts/automatic_kerb";DirAccess.make_dir_recursive_absolute(output);vp.get_texture().get_image().save_png(output+"/junction.png")
	cam.position=Vector3(4,1.2,5);cam.look_at(Vector3(2.4,.03,5));await settle();await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(output+"/detail.png");vp.queue_free();await settle()
