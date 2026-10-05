extends "res://tools/apply_medieval_town_finishing.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const BridgeTool=preload("res://scripts/world_editor/bridge_tools.gd")
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
func requests(doc) -> Array:
	var data: Dictionary=doc.map_meta.editor_layout; var nodes:={}; var water: Array=[]; var ground: Array=[]
	for n in data.roads.nodes: nodes[n.id]=n
	for r in doc.records:
		if r.get("surface_id")=="water":
			for s in Foot.record_shapes(r): water.append(s.polygon)
		if r.has("terrain_mesh"): ground.append(r)
	var result: Array=[]
	for e in data.roads.edges:
		if e.kind!="bridge": continue
		if e.has("stone_bridge"):
			var record: Dictionary=doc._find(e.stone_bridge.id); var d: Dictionary=record.bridge_mesh
			result.append({"id":record.uuid,"road_edge_id":e.id,"name":record.editor_name,"start":e.stone_bridge.start,"end":e.stone_bridge.end,"width":d.width,"depth":d.depth,"camber":d.camber,"prefab_id":d.prefab_id,"arches":d.arches,"auto_clearance":true})
			continue
		var a:=Vector3(nodes[e.from].position[0],.025,nodes[e.from].position[2]); var b:=Vector3(nodes[e.to].position[0],.025,nodes[e.to].position[2]); var direction:=(b-a).normalized(); var normal:=Vector3(-direction.z,0,direction.x)
		var length_:=a.distance_to(b); var first:=INF; var last:=-INF; var low:=0.0
		for i in ceili(length_)+1:
			var distance_: float=minf(i,length_); var center:=a+direction*distance_; low=minf(low,BridgeTool.ground_height(ground,center))
			for side in [-1,0,1]:
				var p: Vector3=center+normal*float(e.width_start)*.5*side
				if water.any(func(polygon):return Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),polygon)): first=minf(first,distance_); last=maxf(last,distance_)
		if not is_finite(first) or not is_finite(low): return []
		first=maxf(2.5,first-6); last=minf(length_-2.5,last+6)
		var n:=result.size()
		result.append({"id":"stone_"+e.id,"road_edge_id":e.id,"name":e.name+" · 石拱桥","start":xyz(a+direction*first),"end":xyz(a+direction*last),"width":maxf(e.width_start,e.width_end)+1.2,"depth":maxf(3.5,.025-low+.7),"camber":[.9,1.4,1.1,.8,.6][n],"prefab_id":"stone_pointed" if n==1 else ("stone_rustic" if n==4 else "stone_segmental"),"arches":0})
	return result
static func xyz(v: Vector3) -> Array: return [v.x,v.y,v.z]
func run() -> void:
	OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_stone_bridges"; CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_stone_bridges/map.gltf"
	if "--clearance" in OS.get_cmdline_user_args():
		OUTPUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_bridge_clearance"; CANDIDATE="D:/code/rmmo_runtime/cache/world3d/medieval_town_bridge_clearance/map.gltf"
	DirAccess.make_dir_recursive_absolute(OUTPUT); DirAccess.make_dir_recursive_absolute(CANDIDATE.get_base_dir()); rpc_timeout_ms=120000
	create_timer(1200).timeout.connect(func():quit(2)); Engine.max_fps=60
	if "--publish" in OS.get_cmdline_user_args():
		var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("runtime_result.json")))
		check(report is Dictionary and report.get("failures",1)==0 and report.get("candidate_sha256")==FileAccess.get_sha256(CANDIDATE),"five bridges passed reviewed runtime verification")
		if failed: quit(1); return
		publish(); return
	progress=FileAccess.open(OUTPUT.path_join("progress.log"),FileAccess.WRITE)
	var doc=Doc.open_file(SOURCE); check(doc!=null,"open formal town for isolated bridge validation")
	if doc==null: quit(1); return
	var source_hash:=FileAccess.get_sha256(SOURCE); var original: Array=doc.records.duplicate(true); var graph: Dictionary=doc.map_meta.editor_layout.roads.duplicate(true); var args:=requests(doc)
	check(args.size()==5,"derive exactly five bridges from actual water footprints")
	if args.size()!=5: quit(1); return
	print("TOWN_BRIDGE_REQUESTS ",JSON.stringify(args))
	root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=CANDIDATE; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=CANDIDATE.get_base_dir().path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false; await batches()
	var probe:=TCPServer.new(); port=31450
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"town bridge conversion through real HTTP MCP")
	var touched: Array=[]
	for request in args:
		var planned:=await call_tool("preview_bridge",request)
		if not planned.get("ok",false): quit(1); return
		print("BRIDGE_NAVIGATION ",request.id," camber=",planned.camber," ",JSON.stringify(planned.navigation))
		touched.append_array(planned.trimmed_roads); var count: int=editor._doc._undo.size()
		var result:=await call_tool("generate_bridge",request.merged({"plan_token":planned.plan_token}))
		if not result.get("ok",false): quit(1); return
		check(editor._doc._undo.size()==count+1,"bridge and old pavement share one transaction: "+request.id); await batches()
	var bridge_ids: Array=args.map(func(a):return a.id)
	var unchanged: Array=original.filter(func(r):return r.uuid not in touched and r.uuid not in bridge_ids)
	check(unchanged.all(func(r):return equivalent(r,editor._doc._find(r.uuid))),"all terrain, river, farms and roads outside the five bridge cuts are unchanged")
	var revised: Dictionary=editor._doc.map_meta.editor_layout.roads.duplicate(true)
	for e in revised.edges: e.erase("stone_bridge")
	for e in graph.edges: e.erase("stone_bridge")
	check(equivalent(graph,revised),"all original road nodes, curves, widths and topology retained")
	check(Paint.missing(editor._doc.records).is_empty(),"all bridge and town 2K PBR dependencies present")
	var expected: Array=editor._doc.records.duplicate(true)
	await call_tool("undo"); await call_tool("redo"); check(equivalent(expected,editor._doc.records),"town bridge undo/redo retains exact records")
	await call_tool("save_world"); await call_tool("open_world",{"path":CANDIDATE}); await batches(); check(equivalent(expected,editor._doc.records),"converted town native save/reopen exact")
	for i in args.size():
		var center:=(Vector3(args[i].start[0],0,args[i].start[2])+Vector3(args[i].end[0],0,args[i].end[2]))*.5
		await capture("bridge_%d"%i,{"projection":"perspective","center":xyz(center),"distance":Vector3(args[i].start[0],0,args[i].start[2]).distance_to(Vector3(args[i].end[0],0,args[i].end[2]))*1.05,"pitch":-30,"yaw":[25,5,15,45,0][i]})
	await capture("overview",{"projection":"top","center":[0,0,0],"span":1480})
	var metrics:=await measure(); check(FileAccess.get_sha256(SOURCE)==source_hash,"formal map unchanged during verification")
	var result:={"failures":failed,"source_sha256":source_hash,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"requests":args,"trimmed_roads":touched,"performance":metrics}
	var file:=FileAccess.open(OUTPUT.path_join("result.json"),FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	editor._mcp.stop(); editor.queue_free(); await settle(); print("TOWN_STONE_CANDIDATE_FINISHED failures=",failed); quit(1 if failed else 0)
