extends "res://tools/test_world3d_roads.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const RESULT="D:/code/rmmo_runtime/review_artifacts/medieval_town_base"
var log_file: FileAccess
var spec: Dictionary
func check(ok: bool,label: String) -> void:
	super.check(ok,label)
	if log_file: log_file.store_line(("PASS " if ok else "FAIL ")+label); log_file.flush()
func run() -> void:
	create_timer(1500).timeout.connect(func():quit(2)); Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute(RESULT)
	log_file=FileAccess.open(RESULT.path_join("progress.log"),FileAccess.WRITE)
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	spec=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	directory="D:/code/rmmo_runtime/cache/world3d/medieval_town_acceptance"; map_path=directory.path_join("map.gltf")
	var original=Doc.open_file(map_path)
	check(original!=null,"open independent acceptance copy")
	if original==null: quit(1); return
	check(original.records.filter(func(r):return r.has("terrain_mesh")).size()==49,"49 editable heightfield patches cover 1.4km square")
	check(original.records.all(func(r):return not r.has("building") and r.get("kind")!="asset"),"base map contains no buildings or prop assets")
	var graph: Dictionary=City.resolve(original.map_meta).roads; var audit:=City.analyze(graph)
	check(audit.ok and audit.diagnostics.is_empty(),"saved road graph has no unresolved crossings")
	check(components(graph)==1,"all streets and five crossings form one connected network")
	var support_errors:=0; var worst:=0.0; var wrong:={}
	for edge in graph.edges:
		if edge.kind=="bridge": continue
		var a:=City.vec(audit.nodes[edge.from].position); var b:=City.vec(audit.nodes[edge.to].position)
		for i in ceili(a.distance_to(b)/3)+1:
			var p:=a.lerp(b,float(i)/maxi(1,ceili(a.distance_to(b)/3))); var h:=terrain_height(original,p)
			worst=maxf(worst,absf(h))
			if is_nan(h) or h<-.22 or h>.015: support_errors+=1; wrong[edge.get("name",edge.id)]=h
	check(support_errors==0,"ground roads have level support; problems="+JSON.stringify(wrong)+" max_error="+str(worst))
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=original
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30400
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real HTTP 3D editor MCP")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(d):return d.name=="sculpt_terrain") and defs.any(func(d):return d.name=="update_road_graph"),"discover terrain and street tools")
	await call_tool("set_map_reference",{"path":spec.reference,"center":[0,0,0],"meters_per_pixel":1.4,"opacity":.4,"visible":false})
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":1480})
	await call_tool("save_view_bookmark",{"id":"whole_town","name":"全城底图"})
	await call_tool("set_playtest_spawn",{"position":[-35,.025,1.4]})
	# Verify editing on a remote patch, then restore the exact delivered content.
	var baseline: Array=editor._doc.records.duplicate(true)
	await atomic_reject("sculpt_terrain",{"id":"town_terrain_0_0","mode":"raise","points":[[-660,-660]],"radius":-1})
	await call_tool("sculpt_terrain",{"id":"town_terrain_0_0","mode":"raise","points":[[-660,-660]],"radius":8,"strength":.3})
	await call_tool("undo"); check(equivalent(baseline,editor._doc.records),"MCP terrain edit undo restores exact base map")
	await call_tool("redo"); await call_tool("undo")
	check(equivalent(baseline,editor._doc.records),"redo and second undo preserve delivered terrain")
	await call_tool("save_world")
	await call_tool("open_world",{"path":map_path})
	check(equivalent(baseline,editor._doc.records),"base map records survive HTTP save and reopen")
	editor._grid.hide(); editor._city.overlay.hide()
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	await capture("market_and_river",{"projection":"top","center":[-40,0,40],"span":850})
	await capture("river_bridge",{"projection":"perspective","center":[338,-1,-154],"distance":180,"pitch":-42,"yaw":-18})
	await capture("market_ground",{"projection":"perspective","center":[-35,0,1.4],"distance":65,"pitch":-35,"yaw":22})
	await call_tool("recall_view_bookmark",{"id":"whole_town"}); await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(RESULT.path_join("editor.png"))
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"native runtime loader reads town geometry")
	if loaded[0]!=null: await verify_runtime(loaded[0])
	var file:=FileAccess.open(RESULT.path_join("result.json"),FileAccess.WRITE); file.store_string(JSON.stringify({"failures":failed,"acceptance_map":map_path,"render_directory":RESULT},"\t")); file.close()
	print("MEDIEVAL_TOWN_VERIFIED failures=%d"%failed); quit(1 if failed else 0)
func capture(name_: String, camera: Dictionary) -> void:
	await call_tool("set_editor_camera",camera); await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(RESULT.path_join(name_+".png")); check(true,"render "+name_)
func components(g: Dictionary) -> int:
	var neighbors:={}; var visited:={}; var total:=0
	for n in g.nodes: neighbors[n.id]=[]
	for e in g.edges: neighbors[e.from].append(e.to); neighbors[e.to].append(e.from)
	for n in g.nodes:
		if visited.has(n.id): continue
		total+=1; var pending: Array=[n.id]
		while not pending.is_empty():
			var id: String=pending.pop_back()
			if visited.has(id): continue
			visited[id]=true; pending.append_array(neighbors[id])
	return total
func terrain_height(doc, p: Vector3) -> float:
	var x:=clampi(floori((p.x+700)/200),0,6); var z:=clampi(floori((p.z+700)/200),0,6)
	var r: Dictionary=doc._find("town_terrain_%d_%d"%[x,z])
	return Terrain.sample(r,p-City.vec(r.position))
func verify_runtime(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene)
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.3
	for road in spec.roads:
		if road.size()<4: continue
		var a:=Vector3((road[2][0][0]-500)*1.4,0,(road[2][0][1]-500)*1.4); var b:=Vector3((road[2][1][0]-500)*1.4,0,(road[2][1][1]-500)*1.4)
		var delta: Vector3=(b-a).normalized(); var middle: Vector3=(a+b)*.5
		Stream.sync(scene,host,middle); await physics()
		var space:=host.get_world_3d().direct_space_state
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(middle+Vector3.UP*8,middle-Vector3.UP*10))
		check(not hit.is_empty() and absf(hit.position.y-.025)<.015,"bridge surface collision "+road[0])
		var water_point: Vector3=river_probe(road,a,b)
		var bed:=space.intersect_ray(PhysicsRayQueryParameters3D.create(water_point+Vector3.UP*8,water_point-Vector3.UP*10))
		check(not bed.is_empty() and bed.position.y< -1.5,"river has an excavated bed beside "+road[0])
		for reverse_ in [false,true]:
			var start: Vector3=(b+delta*3) if reverse_ else (a-delta*3); var end: Vector3=(a-delta*3) if reverse_ else (b+delta*3); var direction: Vector3=(end-start).normalized()
			body.position=start+Vector3.UP*1.12
			for i in 12: await physics_frame; body.velocity=Vector3(0,-4,0); body.move_and_slide()
			var max_drop:=0.0; var reached:=false
			for i in ceili(start.distance_to(end)/8*60)+120:
				await physics_frame; Stream.sync(scene,host,body.position); body.velocity=direction*8+Vector3(0,-4,0); body.move_and_slide(); max_drop=maxf(max_drop,1.075-body.position.y)
				if Vector2(body.position.x-end.x,body.position.z-end.z).length()<.4: reached=true; break
			check(reached and max_drop<.25,"2.1m capsule crosses "+road[0]+(" reverse" if reverse_ else " forward"))
	Stream.sync(scene,host,Vector3(-35,0,1.4)); await physics()
	body.position=Vector3(-35,1.2,1.4)
	for i in 30: await physics_frame; body.velocity=Vector3(0,-4,0); body.move_and_slide()
	check(body.is_on_floor(),"central market spawn stands on real collision")
	host.free()

func river_probe(road: Array, a: Vector3, b: Vector3) -> Vector3:
	var delta: Vector3=(b-a).normalized()
	return (a+b)*.5+Vector3(-delta.z,0,delta.x)*(road[1]*.5+4)
