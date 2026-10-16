extends "res://tools/propose_axel_functional_grass.gd"
## Read-only, focused building/fortification occupancy and real graph connectivity.
## Does not run editor mutation, GPU, or save any map.
func run()->void:
	output=OUT+"/functional_integration_preflight.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):target=arg.trim_prefix("--map=")
		elif arg.begins_with("--expected-sha="):expected_sha=arg.trim_prefix("--expected-sha=")
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=")
	prepare_inputs()
	check(expected_sha.length()==64 and FileAccess.get_sha256(target)==expected_sha,"exact current candidate pin")
	if stop():return
	var doc=Doc.open_file(target);check(doc!=null,"native read-only candidate opens")
	if stop():return
	before=doc.recovery_snapshot();editor=Context.new();editor._doc=doc
	report.input_sha256=expected_sha;report.map=target;report.read_only=true;report.phase="local_geometry_preparation";persist()
	terrain_cache(doc.records);add_buildings();prepare_ground()
	if stop():return
	prepare_roads()
	if stop():return
	var request:Dictionary=report.road_request;var composed:=compose_graph(request)
	var joined:=preload("res://scripts/world3d/road_intersections.gd").split(composed)
	check(joined.get("ok",false),"actual shared road intersections resolve")
	if stop():return
	var graph:Dictionary=joined.graph;var analyzed:=City.analyze(graph)
	report.graph={"nodes":graph.nodes.size(),"edges":graph.edges.size(),"token":City.token(graph),"diagnostics":analyzed.get("diagnostics",[]),"access":[]}
	var unrelated:Array=analyzed.get("diagnostics",[]).filter(func(d):return d.code=="unconnected_crossing" and d.edges.any(func(id):return str(id).begins_with("functional_")))
	check(unrelated.is_empty(),"new access roads contain no disconnected crossing")
	for key:String in KEYS:
		var access:Dictionary=sources[key].site.access
		var route:Array=access.get("points_xz",[access.get("split_at_xz",[]),access.get("new_branch_end_xz",[])])
		var selected:Array=[];var segments:Array=[]
		for at:Array in route:
			var found:Array=graph.nodes.filter(func(n):return Vector2(n.position[0],n.position[2]).distance_to(Vector2(at[0],at[1]))<.002)
			check(found.size()==1,"unique actual access node "+key+" "+str(at))
			if found.size()==1:selected.append(found[0])
		if selected.size()!=route.size():continue
		for i:int in selected.size()-1:
			var a:Dictionary=selected[i];var b:Dictionary=selected[i+1]
			var matches:Array=graph.edges.filter(func(e):return (e.from==a.id and e.to==b.id) or (e.from==b.id and e.to==a.id))
			check(matches.size()==1,"shared-ID connected access edge "+key+" "+str(i))
			segments.append({"from":a.id,"to":b.id,"edges":matches})
		var anchor:Dictionary=selected[0];var degree:Array=graph.edges.filter(func(e):return e.from==anchor.id or e.to==anchor.id)
		check(degree.size()>=2,"access anchor shares existing road node: "+key)
		report.graph.access.append({"key":key,"nodes":selected,"segments":segments,"anchor_incident_edges":degree})
	report.occupancy=[]
	for key:String in KEYS:
		var s:Dictionary=sources[key];var r:Dictionary={"uuid":"proposed_"+key,"kind":"asset","asset_path":s.asset_path,"position":s.site.position,"rotation":s.site.rotation,"size":[1,1,1],"bounds_position":s.entry.bounds_position,"bounds_size":s.entry.bounds_size}
		var full:=complete_source_shape(key,r);var pieces:=part_shapes(key,r);var hits:Array=[];var frozen_broad:Array=[]
		for old:Dictionary in doc.records:
			if old.has("terrain_mesh") or old.has("road_mesh"):continue
			if key=="watermill" and old.get("surface_id","")=="water" and old.has("channel_mesh"):continue
			var shapes:=Foot.record_shapes(old)
			if not Foot.batches_overlap([full],shapes):continue
			if old.has("fortification"):frozen_broad.append({"id":old.uuid,"bounds_min":City.xyz(shapes[0].bounds.position),"bounds_max":City.xyz(shapes[0].bounds.end)})
			var touching:Array=pieces.filter(func(piece):return Foot.batches_overlap([piece],shapes))
			if not touching.is_empty():hits.append({"id":old.uuid,"kind":old.kind,"frozen":old.has("house_prefab"),"fortification":old.get("fortification",{}),"asset_path":old.get("asset_path",""),"parts":touching.map(func(p):return p.part)})
		var roads:Array=[]
		for road:Dictionary in proposed_roads:
			var shapes:=road_shapes(road)
			if not Foot.batches_overlap([full],shapes):continue
			var touching:Array=pieces.filter(func(piece):return Foot.batches_overlap([piece],shapes))
			if not touching.is_empty():roads.append({"road":road.get("uuid",road.road_source),"parts":touching.map(func(p):return p.part)})
		report.occupancy.append({"key":key,"position":r.position,"rotation":r.rotation,"source_sha256":s.source_sha256,"source_component_count":pieces.size(),"hinge_sweeps":hinge_envelopes(key,r),"bounds_min":City.xyz(full.bounds.position),"bounds_max":City.xyz(full.bounds.end),"frozen_fortification_broad_phase":frozen_broad,"source_component_envelope_hits":hits,"actual_local_road_and_kerb_hits":roads,"reservation_conflict":Foot.batches_overlap([full],Zones.obstacles(doc.map_meta))})
	check(FileAccess.get_sha256(target)==expected_sha,"candidate untouched")
	verify_live_building_inputs()
	report.phase="read_only_occupancy_and_topology_complete";report.limits=["Reported component-envelope hits remain conservative until genuine source triangles are checked; absence proves broad-phase clearance.","Final native authoring still enforces terrain/road protections and exact current market SHA; no map placement claimed."]
	persist();print("FUNCTIONAL_INTEGRATION ",JSON.stringify({"failures":failed,"occupancy":report.occupancy.map(func(row):return {"key":row.key,"fortification_broad":row.frozen_fortification_broad_phase,"objects":row.source_component_envelope_hits.map(func(h):return h.id),"roads":row.actual_local_road_and_kerb_hits,"reservation":row.reservation_conflict}),"diagnostics":report.graph.diagnostics}));editor.free();quit(0 if failed==0 else 1)
