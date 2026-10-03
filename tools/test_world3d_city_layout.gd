extends "res://tools/test_world3d_mcp.gd"
const City = preload("res://scripts/world3d/city_layout.gd")
var directory := ""

func atomic_reject(name_: String, args: Dictionary) -> void:
	var before: Dictionary=editor._doc.recovery_snapshot()
	var undos: int=editor._doc._undo.size(); var redos: int=editor._doc._redo.size()
	await call_tool(name_,args,false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and undos==editor._doc._undo.size() and redos==editor._doc._redo.size(),"rejection leaves document/history intact: "+name_)

func graph_request(changes: Dictionary) -> Dictionary:
	return {"expected_token":City.token(City.resolve(editor._doc.map_meta).roads)}.merged(changes)

func run() -> void:
	root.size=Vector2i(1440,1000)
	root.content_scale_size=root.size
	directory=Paths.cache_directory("city_layout_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	doc.add_box("ground",Vector3(0,-.1,0),Vector3(1400,.2,1400))
	var a: String=doc.add_box("block",Vector3(-600,12,-550),Vector3(24,24,30))
	var b: String=doc.add_box("block",Vector3(600,12,550),Vector3(24,24,30))
	doc._find(b).editor_locked=true
	check(doc.save(path)==OK,"isolated 1.4 km map saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path=path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts"); root.add_child(editor)
	await settle()
	var probe:=TCPServer.new(); port=29830
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"city HTTP starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var definitions: Array=(await rpc("tools/list")).result.tools
	var names:=definitions.map(func(t): return t.name)
	check(names.size()==114 and names.has("get_city_layout") and names.has("update_road_graph") and not names.has("paint_tile"),"114 current 3D tools, including 10 city operations")
	var initial:=(await call_tool("get_city_layout"))
	check(initial.layout.roads.nodes.is_empty() and not initial.runtime_geometry,"old map opens with empty planning graph")
	var undo_count: int=editor._doc._undo.size()
	await call_tool("focus_editor_view",{"target":"all","projection":"top"})
	check(editor._camera.projection==Camera3D.PROJECTION_ORTHOGONAL and editor._camera.size>1000,"whole kilometer map fits in real orthographic camera")
	for p in [Vector3(-700,0,-700),Vector3(700,0,700)]:
		check(Rect2(Vector2.ZERO,editor._canvas.size).has_point(editor._camera.unproject_position(p)),"full-map corner projects inside canvas")
	var top_ray: Vector3=editor._camera.project_ray_normal(Vector2(20,20))
	check(top_ray.dot(Vector3.DOWN)>.9999,"north-aligned top view rays are vertical")
	await physics_frame; await settle()
	var pick_pixel: Vector2=editor._camera.unproject_position(Vector3(-600,24,-550))
	check(editor._pick_object(pick_pixel)==a,"kilometer top view picks actual distant object")
	var surface:=await call_tool("pick_surface",{"screen":[pick_pixel.x,pick_pixel.y]})
	check(surface.get("id","")==a,"surface painter uses camera range in orthographic view")
	check(editor._doc._undo.size()==undo_count,"camera does not pollute document undo")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,0,0],"distance":1800,"pitch":-45,"yaw":25})
	await call_tool("focus_editor_view",{"target":"all"})
	for p in Geometry.corners(editor._doc._find(a))+Geometry.corners(editor._doc._find(b)):
		check(Rect2(Vector2.ZERO,editor._canvas.size).has_point(editor._camera.unproject_position(p)),"perspective fit contains a tall distant corner")
	await call_tool("set_editor_camera",{"projection":"top","span":1800})
	var origin: Vector3=editor._orbit_center
	editor._city.pan(Vector2(50,0))
	check(is_equal_approx(editor._orbit_center.x-origin.x,-50.0*1800/editor._canvas.size.y),"orthographic pan uses meters per pixel")
	editor._city.zoom(.5); check(is_equal_approx(editor._camera.size,900),"orthographic wheel zoom changes span")
	var saved_camera: Dictionary=editor._city.camera_state()
	await call_tool("save_view_bookmark",{"id":"whole_city","name":"全城总览"})
	await call_tool("set_editor_camera",{"projection":"perspective","center":[10,3,20],"distance":20})
	await call_tool("recall_view_bookmark",{"id":"whole_city"})
	check(equivalent(saved_camera,editor._city.camera_state()),"bookmarked projection, target, span and orbit restored")
	await atomic_reject("focus_editor_view",{"target":"region","from":[0,0,0]})
	await call_tool("focus_editor_view",{"target":"region","from":[-600,-1,-600],"to":[600,80,600],"projection":"top"})
	check(editor._camera.size>=1200 and editor._orbit_center.is_equal_approx(Vector3(0,39.5,0)),"explicit world region fits without selecting or changing physical records")
	await call_tool("recall_view_bookmark",{"id":"whole_city"})
	await atomic_reject("set_editor_camera",{"span":20000})
	await atomic_reject("save_view_bookmark",{"name":" "})
	await call_tool("delete_view_bookmark",{"id":"whole_city"})
	await call_tool("undo"); check(City.resolve(editor._doc.map_meta).bookmarks.size()==1,"bookmark deletion undo")
	# Import uses a bounded external fixture. Production APIs cannot read the user's Desktop.
	var ref_path:=directory.path_join("reference.png")
	var img:=Image.create(1000,1000,false,Image.FORMAT_RGB8); img.fill(Color("385355"))
	for x in range(0,1000,100): img.fill_rect(Rect2i(x,0,2,1000),Color("aec7b0")); img.fill_rect(Rect2i(0,x,1000,2),Color("aec7b0"))
	img.save_png(ref_path)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="):
			var source:=arg.trim_prefix("--reference="); var photo:=Image.load_from_file(source)
			if photo!=null: photo.save_png(ref_path)
	await call_tool("set_map_reference",{"path":ref_path,"meters_per_pixel":1.2,"opacity":.6})
	var ref: Dictionary=City.resolve(editor._doc.map_meta).reference
	check(ref.path!=ref_path and FileAccess.file_exists(ref.path),"reference copied to immutable content library")
	await call_tool("calibrate_map_reference",{"pixels":[[100,100],[900,100]],"world":[[100,0,400],[100,0,-400]]})
	ref=City.resolve(editor._doc.map_meta).reference
	check(is_equal_approx(ref.meters_per_pixel,1) and is_equal_approx(ref.yaw,90),"two pairs recover scale and rotation")
	var pixel:=Vector3(-400,0,-400)
	var world: Vector3=City.vec(ref.center)+Basis(Vector3.UP,deg_to_rad(ref.yaw))*pixel*ref.meters_per_pixel
	check(world.distance_to(Vector3(100,0,400))<.001,"two pairs recover translation too")
	await call_tool("set_map_reference",{"locked":true})
	await atomic_reject("set_map_reference",{"locked":false,"center":[2,0,3]})
	await atomic_reject("calibrate_map_reference",{"pixels":[[100,100],[900,100]],"world":[[100,0,400],[100,0,-400]]})
	await call_tool("set_map_reference",{"opacity":.4,"visible":false})
	await call_tool("set_map_reference",{"locked":false})
	await atomic_reject("calibrate_map_reference",{"pixels":[[1,1],[2,1]],"world":[[0,0,0],[100,0,0]]})
	await atomic_reject("set_map_reference",{"path":"C:/Windows/win.ini"})
	await atomic_reject("set_map_reference",{"path":ref_path,"meters_per_pixel":100})
	await call_tool("set_map_reference",{"center":[0,0,0],"yaw":0,"meters_per_pixel":1.2,"opacity":.6,"visible":true,"locked":true})
	# Stable IDs support explicit T/Y/cross topology; crossing strokes are diagnosed, not connected silently.
	await call_tool("create_road_path",{"points":[[-500,0,0],[0,0,0],[500,0,0]],"width":12})
	await call_tool("create_road_path",{"points":[[0,0,0],[0,0,-450]],"width":8})
	var graph: Dictionary=City.resolve(editor._doc.map_meta).roads
	check(graph.nodes.size()==4 and graph.edges.size()==3,"shared endpoints form connected T with 4 stable nodes")
	var previous_token:=City.token(graph)
	await call_tool("create_road_path",{"points":[[250,0,-450],[250,0,450]],"width":6})
	check(editor._city.analysis.diagnostics.any(func(d): return d.code=="unconnected_crossing"),"unconnected ground crossing diagnosed")
	await atomic_reject("update_road_graph",{"expected_token":previous_token,"nodes":[]})
	await call_tool("create_road_path",{"points":[[-250,6,-450],[-250,6,450]],"width":10,"kind":"bridge"})
	check(editor._city.analysis.diagnostics.any(func(d): return d.code=="grade_separated_crossing"),"bridge crossing remains separate graph level")
	graph=City.resolve(editor._doc.map_meta).roads
	var edge: Dictionary=graph.edges[0].duplicate(true); var id: String=edge.id
	edge.controls=[[-400,0,170],[-120,0,160]]; edge.width_end=18
	await call_tool("update_road_graph",graph_request({"edges":[edge]}))
	check(editor._city.analysis.paths[id].size()>2 and editor._city.analysis.paths[id][0]==Vector3(-500,0,0),"exact curve handles persist and sampled guide begins at source node")
	await atomic_reject("update_road_graph",graph_request({"remove_nodes":[graph.nodes[0].id]}))
	await atomic_reject("update_road_graph",graph_request({"nodes":[{"id":"bad id","position":[0,0,0]}]}))
	await atomic_reject("create_road_path",{"points":[[12,0,12],[12.01,0,12]],"width":4})
	edge.locked=true
	await call_tool("update_road_graph",graph_request({"edges":[edge]}))
	var node: Dictionary=graph.nodes[0].duplicate(true); node.position=[-490,0,0]
	await atomic_reject("update_road_graph",graph_request({"nodes":[node]}))
	var changed: Dictionary=edge.duplicate(true); changed.controls[0][1]=2
	await atomic_reject("update_road_graph",graph_request({"edges":[changed]}))
	edge.locked=false; await call_tool("update_road_graph",graph_request({"edges":[edge]}))
	await call_tool("update_road_graph",graph_request({"nodes":[node]}))
	await call_tool("undo"); check(City.vec(editor._city.analysis.nodes[node.id].position)==Vector3(-500,0,0),"graph edit undone using shared history")
	await call_tool("redo"); check(City.vec(editor._city.analysis.nodes[node.id].position)==Vector3(-490,0,0),"graph edit redone with stable node ID")
	check(editor._doc.records.size()==3,"all planning operations create zero physical records")
	await call_tool("set_floor_view",{"isolation":true,"base_height":40,"floor_height":4})
	check(editor._city.data.roads.edges.size()>0,"planning graph independent of runtime floor isolation")
	await call_tool("set_floor_view",{"isolation":false})
	# UI drawing calls the same transaction. Escape cancels without altering history.
	check(editor._city.begin_draw(7,0,"ground").ok,"UI begins road draw")
	await atomic_reject("set_editor_camera",{"span":100})
	await atomic_reject("generate_buildings",{"placements":[{"position":[0,0,0]}]})
	for point in [Vector3(300,0,200),Vector3(420,0,300)]:
		var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
		event.position=editor._canvas.global_position+editor._camera.unproject_position(point)
		Input.parse_input_event(event); await settle()
		var up:=event.duplicate(); up.pressed=false; Input.parse_input_event(up); await settle()
	check(editor._city.pending.size()==2,"real canvas pointer events collect road nodes")
	check(editor._city.finish_draw().ok,"UI point stroke commits shared road operation")
	var after_ui: Dictionary=editor._doc.recovery_snapshot()
	editor._city.begin_draw(8,0,"ground"); editor._city.pending=[[3,0,4],[10,0,4]]
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true
	check(editor._city.input(escape) and not editor._city.drawing and equivalent(after_ui,editor._doc.recovery_snapshot()),"Escape cancels temporary stroke atomically")
	editor._dock_tabs.current_tab=9; await settle()
	var mini: Control=editor._city.overlay.mini
	var jump:=InputEventMouseButton.new(); jump.button_index=MOUSE_BUTTON_LEFT; jump.pressed=true
	jump.position=mini.global_position+editor._city.overlay.mini_rect().get_center()
	Input.parse_input_event(jump); await settle()
	var jump_up:=jump.duplicate(); jump_up.pressed=false; Input.parse_input_event(jump_up); await settle()
	check(absf(editor._orbit_center.x)<1 and absf(editor._orbit_center.z)<1,"clicking minimap center recenters view without placing objects")
	var node_id: String=City.resolve(editor._doc.map_meta).roads.nodes[0].id
	var old_position:=City.vec(editor._city.analysis.nodes[node_id].position)
	var drag_pixel: Vector2=editor._camera.unproject_position(old_position)
	var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; press.position=editor._canvas.global_position+drag_pixel
	Input.parse_input_event(press); await settle()
	check(not editor._city.drag_node.is_empty(),"clicking a road node starts real pointer drag")
	await atomic_reject("save_world",{})
	var move:=InputEventMouseMotion.new(); move.position=press.position+Vector2(30,20); move.relative=Vector2(30,20); move.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move); await settle()
	check(City.vec(City.resolve(editor._doc.map_meta).roads.nodes[0].position)==old_position,"drag preview does not mutate saved graph before release")
	var release:=InputEventMouseButton.new(); release.button_index=MOUSE_BUTTON_LEFT; release.pressed=false; release.position=move.position
	Input.parse_input_event(release); await settle()
	check(editor._city.drag_node.is_empty() and City.vec(City.resolve(editor._doc.map_meta).roads.nodes[0].position).distance_to(old_position)>1,"release commits node and attached curve endpoint")
	await call_tool("undo"); check(City.vec(editor._city.analysis.nodes[node_id].position).distance_to(old_position)<.001,"whole road node drag is a single undo")
	# Shared form uses pixel vectors of length two without changing existing XYZ forms.
	check(editor._city.panel.reference.fields.center.get_child_count()==3,"reference world center uses three coordinates")
	var saved_layout:=City.resolve(editor._doc.map_meta)
	await call_tool("save_editor_draft")
	await call_tool("save_world")
	await call_tool("open_world",{"path":path})
	check(equivalent(saved_layout,City.resolve(editor._doc.map_meta)),"graph IDs, curve handles, reference, protection and bookmarks survive save/reopen")
	var runtime:=Io.load_scene(path)
	check(runtime!=null and runtime.get_child_count()==3,"saved runtime contains only original 3 physical objects")
	if runtime!=null: runtime.free()
	var malformed=Doc.open_file(path); malformed.map_meta.editor_layout.roads.edges[0].to="missing"
	check(malformed.save(directory.path_join("invalid.gltf"))==ERR_INVALID_DATA,"malformed persisted graph cannot be saved")
	check(not preload("res://scripts/world_editor/draft_store.gd").validate(malformed.recovery_snapshot()).is_empty(),"malformed graph cannot bypass draft validation")
	await call_tool("focus_editor_view",{"target":"layout","projection":"top"})
	editor._dock_tabs.current_tab=9
	if DisplayServer.get_name()!="headless":
		await settle(); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("city_layout.png"))
		var response:=await rpc("tools/call",{"name":"preview_map","arguments":{"include_layout":true}})
		check(response.result.content.any(func(p): return p.type=="image"),"real HTTP preview returns city canvas image")
		var plain:=await rpc("tools/call",{"name":"preview_map","arguments":{}})
		var overlay_png: String=response.result.content.filter(func(p): return p.type=="image")[0].data
		var plain_png: String=plain.result.content.filter(func(p): return p.type=="image")[0].data
		check(overlay_png!=plain_png,"MCP layout preview includes reference and guides, ordinary preview remains scene-only")
		var preview:=Image.new(); preview.load_png_from_buffer(Marshalls.base64_to_raw(overlay_png)); preview.save_png(directory.path_join("mcp_layout.png"))
	# Diagnostics are bounded and deterministic for a 64-road district plan.
	var benchmark:={"nodes":[],"edges":[]}
	for i in 32:
		for offset in 2:
			benchmark.nodes.append({"id":"n_%d_%d"%[i,offset],"position":[-620+40*i,0,-600+1200*offset]})
		benchmark.edges.append({"id":"r_%d"%i,"from":"n_%d_0"%i,"to":"n_%d_1"%i,"width_start":8,"width_end":8,"kind":"ground"})
	for i in 32:
		for offset in 2: benchmark.nodes.append({"id":"h_%d_%d"%[i,offset],"position":[-600+1200*offset,0,-620+40*i]})
		benchmark.edges.append({"id":"s_%d"%i,"from":"h_%d_0"%i,"to":"h_%d_1"%i,"width_start":8,"width_end":8,"kind":"ground"})
	var start:=Time.get_ticks_usec(); var audit:=City.analyze(benchmark); var duration:=(Time.get_ticks_usec()-start)/1000.0
	check(audit.ok and audit.diagnostics.size()>=900,"64-road 1.2 km planning grid diagnosed without runtime tiles")
	print("CITY_LAYOUT_BENCHMARK ms=%.2f segments=%d diagnostics=%d"%[duration,audit.get("sample_segments",0),audit.get("diagnostics",[]).size()])
	print("CITY_LAYOUT_ARTIFACTS "+directory)
	print("CITY_LAYOUT_FINISHED failures=%d"%failed)
	editor.queue_free(); await settle(); quit(0 if failed==0 else 1)
