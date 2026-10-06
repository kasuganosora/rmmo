extends "res://tools/apply_medieval_town_materials.gd"
const Curves=preload("res://tools/medieval_town_road_curves.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Plan=preload("res://scripts/world3d/road_plan.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Split=preload("res://scripts/world3d/road_intersections.gd")
const River=preload("res://tools/medieval_town_river_curves.gd")
var progress: FileAccess

func check(ok: bool, label: String) -> void:
	super.check(ok,label)
	if progress: progress.store_line(("PASS " if ok else "FAIL ")+label); progress.flush()

func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_curves"
	CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_curves/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	create_timer(1200).timeout.connect(func():quit(2))
	if "--publish" in OS.get_cmdline_user_args():
		var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("result.json")))
		if not report is Dictionary or not report.get("reviewed",false): check(false,"visual and HTTP review required before publication"); quit(1); return
		var runtime: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("runtime_result.json")))
		if not runtime is Dictionary or runtime.get("failures",1)!=0 or runtime.get("scope","")!="full" or runtime.get("candidate_sha256","")!=FileAccess.get_sha256(CANDIDATE): check(false,"runtime collision and walking verification required"); quit(1); return
		var geometry: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("geometry_result.json")))
		if not geometry is Dictionary or geometry.get("failures",1)!=0 or geometry.get("candidate_sha256","")!=FileAccess.get_sha256(CANDIDATE): check(false,"shoreline and map boundary geometry verification required"); quit(1); return
		publish(); return
	if "--review" in OS.get_cmdline_user_args(): await review(); return
	var doc=Doc.open_file(SOURCE)
	check(doc!=null,"open current town with native conflict baseline")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE)
	var original_graph: Dictionary=doc.map_meta.editor_layout.roads.duplicate(true)
	var other_records: Array=doc.records.filter(func(r):return not r.has("road_mesh"))
	var old_roads: Array=doc.records.filter(func(r):return r.has("road_mesh")); var old_cells:={}
	check(old_roads.all(func(r):return not r.get("editor_locked",false) and not r.get("editor_hidden",false) and not r.has("event") and not r.has("group_id")),"pavement is editable and has no attached groups/events")
	for r in old_roads: old_cells[Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))]=r
	var fitted:=Curves.fit(doc.map_meta.editor_layout.roads)
	if not fitted.ok: print(JSON.stringify(fitted)); quit(1); return
	check(fitted.curves>200,"fit %d continuous cubic road edges"%fitted.curves)
	check(fitted.graph.nodes==original_graph.nodes,"all 192 junction coordinates and identities remain fixed")
	var stripped: Dictionary=fitted.graph.duplicate(true)
	for edge in stripped.edges: edge.erase("controls")
	for edge in original_graph.edges: edge.erase("controls")
	check(equivalent(stripped,original_graph),"widths, bridge spans, edge identities and connectivity remain fixed")
	var plan:=Plan.build(fitted.graph,Plan.defaults())
	if not plan.ok: print(JSON.stringify(plan)); quit(1); return
	check(true,"continuous pavement: %d chunks / %d clipping operations"%[plan.chunks,plan.operations])
	var spec: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/medieval_town_layout.json"))
	var roads:=Curves.clip_map_bounds(Curves.merge_squares(plan.records,spec))
	var material: Dictionary=old_roads[0].surface_paint[0].material.duplicate(true)
	var painter:=preload("res://scripts/world_editor/road_tools.gd").new()
	var max_faces:=0
	for r in roads:
		var key:=Vector2i(floori(r.position[0]/32),floori(r.position[2]/32))
		r.uuid=old_cells[key].uuid if old_cells.has(key) else "town_"+r.uuid
		r.erase("road_source")
		var painted:=painter.paint_default(r,material)
		if not painted.ok: check(false,"paint "+r.uuid+" "+str(painted)); quit(1); return
		max_faces=maxi(max_faces,r.surface_paint.size())
	check(true,"preserved flagstone on %d road/plaza chunks; max %d painted faces per chunk"%[roads.size(),max_faces])
	doc.records=other_records+roads; doc.map_meta.editor_layout.roads=fitted.graph
	var river:=River.new(); river.setup(spec); var river_result:=river.apply(doc)
	check(river_result.ok,"smooth water, bed, banks and reserved corridor together: "+JSON.stringify(river_result))
	if failed: quit(1); return
	var audit:=City.analyze(fitted.graph); var support_errors:={}; var max_sagitta:=0.0
	for edge in fitted.graph.edges:
		var samples: Array=audit.paths[edge.id]
		for i in samples.size()-1:
			var mid:=Split.position(edge,audit.nodes,(i+.5)/(samples.size()-1))
			max_sagitta=maxf(max_sagitta,mid.distance_to((samples[i]+samples[i+1])*.5))
		if edge.kind=="bridge": continue
		for i in 101:
			var p:=Split.position(edge,audit.nodes,i/100.0)
			var h:=terrain_height(doc,p)
			if is_nan(h) or h<-.22 or h>.015: support_errors[edge.get("name",edge.id)]=h
	check(support_errors.is_empty(),"curved centerlines remain supported by existing terrain: "+JSON.stringify(support_errors))
	check(max_sagitta<.2,"maximum cubic sampling deviation %.4fm"%max_sagitta)
	check(doc.map_meta.editor_layout.get("road_surface",{}).is_empty(),"manually merged squares retain detached surface ownership")
	check(City.valid(doc.map_meta),"curved river reservation bands fit native 3D schema")
	check(terrain_seams(doc)<.00001,"river edits preserve shared terrain edges")
	if failed: quit(1); return
	check(doc.save(CANDIDATE)==OK,"save native review candidate")
	var reopened=Doc.open_file(CANDIDATE)
	check(reopened!=null and equivalent(reopened.records,doc.records) and equivalent(reopened.map_meta,doc.map_meta),"curve controls and pavement survive native save/reopen")
	var report:={"source":SOURCE,"source_sha256":source_hash,"candidate":CANDIDATE,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"failures":failed,"reviewed":false,"curves":fitted.curves,"road_chunks":roads.size(),"max_sampling_deviation_m":max_sagitta,"constrained_junctions":fitted.constrained_junctions,"unchanged_nodes":fitted.graph.nodes.size(),"clipping_operations":plan.operations,"max_painted_faces":max_faces}
	report.river=river_result
	write_report(report)
	quit(1 if failed else 0)

func terrain_height(doc, p: Vector3) -> float:
	var x:=clampi(floori((p.x+700)/200),0,6); var z:=clampi(floori((p.z+700)/200),0,6)
	var r: Dictionary=doc._find("town_terrain_%d_%d"%[x,z])
	return Terrain.sample(r,p-City.vec(r.position))

func terrain_seams(doc) -> float:
	var values:={}; var worst:=0.0
	for r in doc.records:
		if not r.has("terrain_mesh"): continue
		for iz in [0,64]:
			for ix in 65:
				var key:=Vector2(r.position[0]+(ix/64.0-.5)*200,r.position[2]+(iz/64.0-.5)*200)
				var h: float=r.terrain_mesh.heights[iz*65+ix]
				if values.has(key): worst=maxf(worst,absf(values[key]-h))
				values[key]=h
		for ix in [0,64]:
			for iz in 65:
				var key:=Vector2(r.position[0]+(ix/64.0-.5)*200,r.position[2]+(iz/64.0-.5)*200)
				var h: float=r.terrain_mesh.heights[iz*65+ix]
				if values.has(key): worst=maxf(worst,absf(values[key]-h))
				values[key]=h
	return worst

func write_report(report: Dictionary) -> void:
	var f:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()

func review() -> void:
	Engine.max_fps=60
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("result.json")))
	check(report.failures==0 and report.candidate_sha256==FileAccess.get_sha256(CANDIDATE) and report.source_sha256==FileAccess.get_sha256(SOURCE),"review input hashes match successful build")
	if failed: quit(1); return
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=SOURCE; session.world3d_editor_doc=Doc.open_file(SOURCE)
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30560
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real loopback HTTP MCP")
	var defs: Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(d):return d.name=="update_road_graph" and d.inputSchema.properties.edges.items.properties.has("controls")) and defs.any(func(d):return d.name=="generate_road_surface") and not defs.any(func(d):return d.name=="paint_tile"),"discover current 3D cubic graph and surface tools; no retired 2D tools")
	hide_helpers()
	await capture("before_west",{"projection":"top","center":[-510,0,142],"span":380})
	await capture("before_east",{"projection":"top","center":[462,0,-195],"span":380})
	await capture("before_junction",{"projection":"top","center":[-632.8,0,-154],"span":95})
	await capture("before_river",{"projection":"top","center":[190,0,0],"span":650})
	await call_tool("open_world",{"path":CANDIDATE}); hide_helpers()
	var saved_graph: Dictionary=editor._doc.map_meta.editor_layout.roads.duplicate(true)
	await call_tool("get_city_layout")
	check(saved_graph.edges.filter(func(e):return e.has("controls")).size()==253,"HTTP open retains all cubic controls")
	var water: Dictionary=editor._doc.records.filter(func(r):return r.has("channel_mesh") and r.surface_id=="water")[0]
	await call_tool("get_object",{"id":water.uuid})
	check(editor._doc.map_meta.editor_layout.zones.filter(func(z):return str(z.id).begins_with("river_corridor")).size()==24,"MCP-opened map retains all curved river reservation bands")
	hide_helpers()
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	await capture("after_west",{"projection":"top","center":[-510,0,142],"span":380})
	await capture("after_east",{"projection":"top","center":[462,0,-195],"span":380})
	await capture("after_junction",{"projection":"top","center":[-632.8,0,-154],"span":95})
	await capture("after_river",{"projection":"top","center":[190,0,0],"span":650})
	await capture("curve_ground",{"projection":"perspective","center":[-560,0,64],"distance":75,"pitch":-42,"yaw":-30})
	await capture("river_bridge",{"projection":"perspective","center":[338,-1,-154],"distance":150,"pitch":-42,"yaw":-18})
	check(not editor._view.get_children().any(func(n):return n.has_meta("paint_error")),"rebuilt curved road surfaces have no material/signature errors")
	await verify_surface_mcp()
	editor._mcp.stop(); editor.queue_free(); await settle()
	report.failures=failed; report.reviewed=failed==0; report.candidate_sha256=FileAccess.get_sha256(CANDIDATE)
	write_report(report)
	print("TOWN_CURVES_REVIEWED failures=",failed); quit(1 if failed else 0)

func hide_helpers() -> void:
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()

func graph_args(changes: Dictionary) -> Dictionary:
	return {"expected_token":City.token(editor._doc.map_meta.editor_layout.roads)}.merged(changes)

func reject_atomic(name_: String, args: Dictionary) -> void:
	var before: Dictionary=editor._doc.recovery_snapshot(); var undos: int=editor._doc._undo.size(); var redos: int=editor._doc._redo.size()
	await call_tool(name_,args,false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and undos==editor._doc._undo.size() and redos==editor._doc._redo.size(),"failed call leaves document and history unchanged: "+name_)

func verify_surface_mcp() -> void:
	var path:=CANDIDATE.get_base_dir().path_join("mcp_fixture/map.gltf"); var doc:=Doc.new()
	doc.add_box("ground",Vector3(0,-.3,0),Vector3(160,.6,100))
	check(doc.save(path)==OK,"save separate small MCP pavement fixture")
	await call_tool("open_world",{"path":path})
	await call_tool("create_road_path",{"points":[[-60,0,0],[60,0,0]],"width":8})
	var edge: Dictionary=editor._doc.map_meta.editor_layout.roads.edges[0].duplicate(true)
	edge.controls=[[-20,0,36],[20,0,-36]]
	await reject_atomic("update_road_graph",{"expected_token":"stale","edges":[edge]})
	var invalid: Dictionary=edge.duplicate(true); invalid.controls=[[0,0,0]]
	await reject_atomic("update_road_graph",graph_args({"edges":[invalid]}))
	await call_tool("update_road_graph",graph_args({"edges":[edge]}))
	await call_tool("undo"); check(not editor._doc.map_meta.editor_layout.roads.edges[0].has("controls"),"HTTP curve edit undo restores straight source")
	await call_tool("redo"); check(equivalent(editor._doc.map_meta.editor_layout.roads.edges[0],edge),"HTTP curve edit redo restores exact handles")
	var args:={"material_id":"pack:default:paving/outdoor_flagstone/material"}
	var preview:=await call_tool("preview_road_surface",args)
	await reject_atomic("generate_road_surface",args.merged({"plan_token":"stale"}))
	await call_tool("generate_road_surface",args.merged({"plan_token":preview.get("plan_token","")}))
	var generated: Dictionary=editor._doc.recovery_snapshot()
	check(editor._doc.records.filter(func(r):return r.has("road_mesh")).size()==preview.get("chunks",-1),"HTTP generator creates curved slabs with shared edges")
	await call_tool("undo"); check(not editor._doc.records.any(func(r):return r.has("road_mesh")),"one undo removes all curved slabs and manifest")
	await call_tool("redo"); check(equivalent(editor._doc.recovery_snapshot(),generated),"redo restores identical curved slabs and paint")
	edge.locked=true; await call_tool("update_road_graph",graph_args({"edges":[edge]}))
	var protected: Dictionary=edge.duplicate(true); protected.controls[0][0]+=1
	await reject_atomic("update_road_graph",graph_args({"edges":[protected]}))
	await call_tool("undo")
	edge.locked=false; edge.hidden=true; await call_tool("update_road_graph",graph_args({"edges":[edge]}))
	await reject_atomic("generate_road_surface",args)
	await call_tool("undo"); await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,generated.records) and equivalent(editor._doc.map_meta,generated.map_meta),"generated curved surfaces and resource dependencies survive HTTP save/reopen")
