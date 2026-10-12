extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("sloped_road_bridge_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory);var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("stone",Vector3(0,-5.25,0),Vector3(130,.5,80))
	var start_y:float=.5-20./46.;var end_y:float=.5+20./46.
	# The sloped span includes the approaches; horizontal banks stop where the
	# road's ramp begins, so the fixture does not bury the original road.
	doc.add_box("grass",Vector3(-39,-.25,0),Vector3(32,.5,24));doc.add_box("grass",Vector3(39,.75,0),Vector3(32,.5,24))
	var graph:={"nodes":[],"edges":[]}
	for i in 4:graph.nodes.append({"id":"n%d"%i,"position":[[-50.,-26.,26.,50.][i],0. if i<2 else 1.,0.]})
	for i in 3:graph.edges.append({"id":"e%d"%i,"from":"n%d"%i,"to":"n%d"%(i+1),"width_start":6.,"width_end":6.,"kind":"bridge" if i==1 else "ground"})
	var data:=City.resolve({});data.roads=graph;var settings:=Plan.defaults();settings.material_id="pack:default:paving/outdoor_flagstone/material";settings.lift=.04;settings.kerb_enabled=true
	var plan:=Plan.build(graph,settings);check(plan.ok,"initial sloped road")
	var paint:=preload("res://scripts/world_editor/road_tools.gd").new();var material:=preload("res://scripts/world_editor/surface_material_library.gd").new().find(settings.material_id);var parts:Array=[]
	for r:Dictionary in plan.records:
		check(paint.paint_default(r,material).ok,"sloped road material");doc.records.append(r);parts.append({"key":r.road_source,"id":r.uuid,"signature":Surface.signature(r),"paint_signature":City.token(r.surface_paint)})
	data.road_surface={"version":1,"settings":settings,"graph_token":City.token(graph),"parts":parts};doc.map_meta.editor_layout=data
	check(doc.save(path)==OK,"sloped fixture save")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31030
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"sloped bridge HTTP starts")
	var args:={"id":"inclined","road_edge_id":"e1","start":[-20.,start_y+settings.lift,0.],"end":[20.,end_y+settings.lift,0.],"width":7.2,"depth":5.,"camber":.2}
	var before:Dictionary=editor._doc.recovery_snapshot();var preview:=await call_tool("preview_bridge",args)
	check(equivalent(before,editor._doc.recovery_snapshot()),"slope preview readonly")
	if not preview.get("ok",false):quit(1);return
	check(not preview.trimmed_roads.is_empty(),"sloped patches clipped")
	await call_tool("generate_bridge",args.merged({"plan_token":preview.plan_token}))
	check(absf(editor._doc._find(args.id).bridge_mesh.rise-(end_y-start_y))<.001,"bound bridge preserves endpoint rise")
	var kerbs_clear:=true
	for record:Dictionary in editor._doc.records:
		for part:Dictionary in record.get("road_mesh",{}).get("kerbs",[]):
			var middle:=City.vec(record.position)+(City.vec(part.a[0])+City.vec(part.b[0]))*.5
			if absf(middle.x)<19.99 and absf(middle.z)<3.6:kerbs_clear=false
	check(kerbs_clear,"conversion removes old kerbs throughout sloped bridge")
	var bound:Dictionary=editor._doc.recovery_snapshot();var current_graph:Dictionary=City.resolve(editor._doc.map_meta).roads
	var widened:Dictionary=current_graph.edges.filter(func(e):return e.id=="e0")[0].duplicate(true);widened.width_end=12.
	await call_tool("update_road_graph",{"expected_token":City.token(current_graph),"edges":[widened]},false)
	check(equivalent(bound,editor._doc.recovery_snapshot()),"neighbor widening cannot detach bound slope through HTTP")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"slope undo restores graph and painted patches");await call_tool("redo")
	await call_tool("preview_road_surface",{});await call_tool("generate_road_surface",{})
	var repaved:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("generate_road_surface",{"lift":.005},false);check(equivalent(repaved,editor._doc.recovery_snapshot()),"bound bridge rejects road lift changes atomically")
	var mask:=[Vector2(-19.99,-3.),Vector2(19.99,-3.),Vector2(19.99,3.),Vector2(-19.99,3.)];var area:=0.
	for r:Dictionary in editor._doc.records:
		if not r.has("road_mesh"):continue
		for shape:Dictionary in preload("res://scripts/world_editor/building_footprint.gd").record_shapes(r):
			var overlap:=Plan.intersection(Array(shape.polygon).slice(0,-1),mask)
			if not overlap.is_empty():area+=preload("res://scripts/world3d/roof_plan.gd").area(overlap)
	check(area<.001,"rebuilding roads leaves no slab under sloped bridge")
	var ui:VBoxContainer=editor._city.panel.bridge_panel;ui.refresh();ui.load_road();check(ui.road_edge_id=="e1" and absf(ui.request().end[1]-ui.request().start[1])>.8,"UI reads sloped bound bridge")
	var stable:Dictionary=editor._doc.recovery_snapshot();await call_tool("generate_bridge",args.merged({"end":[20,20,0]},true),false);check(equivalent(stable,editor._doc.recovery_snapshot()),"invalid slope no effects")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":path});check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"sloped bridge save reopen exact")
	var bridge:Dictionary=editor._doc._find(args.id);var geometry:Array=[]
	for record:Dictionary in editor._doc.records:
		if not record.has("road_mesh"):continue
		var triangles:=0;var vertices:=0;var arrays:=Surface.arrays(record)
		for surface:Array in arrays:
			vertices+=surface[Mesh.ARRAY_VERTEX].size();triangles+=(surface[Mesh.ARRAY_INDEX].size() if surface[Mesh.ARRAY_INDEX]!=null and not surface[Mesh.ARRAY_INDEX].is_empty() else surface[Mesh.ARRAY_VERTEX].size())/3
		geometry.append({"id":record.uuid,"triangles":triangles,"vertices":vertices,"surfaces":arrays.size(),"kerb_sections":record.road_mesh.get("kerbs",[]).size(),"signature":Surface.signature(record)})
	var review:={"map":path,"map_sha256":FileAccess.get_sha256(path),"bridge_source":bridge.asset_path,"bridge_source_sha256":FileAccess.get_sha256(bridge.asset_path),"bridge_prefab_sha256":bridge.house_prefab.sha256,"bridge_prefab_decoded_bytes":bridge.house_prefab.length,"roads":geometry,"scope":"Affected road slab and automatic kerb clipping; bridge source geometry and textures unchanged. RAM/VRAM not measured.","screenshots":[]}
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,1000);root.content_scale_size=root.size;editor._grid.hide()
		for shot:Array in [["sloped_bridge",[0,1,0],48,-20,25],["bridge_far",[0,1,0],85,-25,25],["kerb_near",[-20,.5,0],15,-25,35],["kerb_detail",[-20,.5,-3],5,-25,35]]:
			var camera:={"projection":"perspective","center":shot[1],"distance":shot[2],"pitch":shot[3],"yaw":shot[4]}
			await call_tool("set_editor_camera",camera);await settle();await RenderingServer.frame_post_draw;editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(shot[0]+".png"));review.screenshots.append({"file":shot[0]+".png","camera":camera})
	var report:=FileAccess.open(directory.path_join("structure_review.json"),FileAccess.WRITE);report.store_string(JSON.stringify(review,"\t"));report.close()
	print("SLOPED_BRIDGE_ARTIFACTS ",directory);editor._mcp.stop();editor.queue_free();await settle();print("SLOPED_BRIDGE_FINISHED failures=",failed);quit(failed)
