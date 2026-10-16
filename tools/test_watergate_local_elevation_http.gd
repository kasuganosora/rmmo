extends "res://tools/test_world3d_mcp.gd"
const F=preload("res://scripts/world3d/fortification_data.gd")
const Plan=preload("res://scripts/world3d/fortification_plan.gd")
const Fit=preload("res://scripts/world3d/fortification_terrain.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var directory:String
var evidence:Dictionary={}
func ground_record()->Dictionary:
	var heights:Array=[];var holes:Array=[]
	for z in 46:
		for x in 57:
			var wx:float=-56.+x*2.;var wz:float=-45.+z*2.;var h:float=4.+4.*clampf((wx+15.)/30.,0.,1.)
			if absf(absf(wx)-30.)<=4. and absf(wz)<4.:h-=1.
			heights.append(h)
	holes.resize(56*45);holes.fill(false)
	return {"uuid":"ground","kind":"box","surface_id":"ground","collision":"walk","position":[0,0,0],"rotation":[0,0,0],"size":[112,1,90],"color":[.3,.4,.2],"terrain_mesh":{"version":1,"columns":56,"rows":45,"floor":-5.,"heights":heights,"holes":holes}}
func recipe()->Dictionary:
	return {"id":"dual_water_elevations","points":[[-30,-24],[30,-24],[30,24],[-30,24]],"closed":true,"tower_indices":[0,2],"height":7.5,"thickness":3.5,"base_height":0.,"foundation":1.5,"follow_terrain":true,"style":"medieval_stone","corner_towers":true,"arrow_slits":true,"wall_access":true,"tower_layout":"manual","gates":[{"id":"west_water","kind":"water","segment":3,"t":.5,"width":12.,"height":5.,"open":0.,"grille":true,"water_depth":2.,"base_height":4.},{"id":"east_water","kind":"water","segment":1,"t":.5,"width":12.,"height":5.,"open":0.,"grille":true,"water_depth":2.,"base_height":8.},{"id":"land","kind":"land","segment":2,"t":1./6.,"width":6.,"height":5.,"open":1.}]}
func source_geometry(settings:Dictionary)->void:
	var s:Dictionary=F.defaults().merged(settings,true);s.layout_version=1
	var plan:Dictionary=Plan.new().build(s);check(plan.ok,"same closed group source geometry builds")
	if not plan.ok:print(plan);return
	var fit:Dictionary=Fit.fit(plan.records,[ground_record()],0.,1.5,s);check(fit.ok,"same group fits two bank elevations without lowering crowns")
	if not fit.ok:print(fit);return
	var crowns:=0;var parapets:=0;var clean:=true;var seams:Array=[]
	for r:Dictionary in fit.records:
		var x:float=r.position[0];var z:float=r.position[2];var top:float=r.position[1]+r.size[1]*.5
		if r.has("water_gate"):
			crowns+=1;clean=clean and absf(top-(11.5 if x<0. else 15.5))<.0001
		if r.fortification.role in ["parapet","battlement"] and absf(x)>27. and absf(z)<6.:
			parapets+=1;var lo:float=r.position[1]-r.size[1]*.5;clean=clean and lo>=(11.5 if x<0. else 15.5)-.0001 and not r.has("terrain_grade")
		if r.fortification.role=="wall" and not str(r.fortification.part).begins_with("water_") and absf(x)>28. and absf(absf(z)-6.)<3.:
			var basis:=Basis.from_euler(Data.vec(r.rotation)*PI/180.);var half:float=r.size[0]*.5
			for sign_:float in [-1.,1.]:
				var at:Vector3=Data.vec(r.position)+basis.x*half*sign_
				if absf(absf(at.z)-6.)<.02:
					var y:float=top+r.get("terrain_grade",[0.,0.])[0]*half*sign_;var wanted:float=11.5 if x<0. else 15.5;seams.append({"point":[at.x,y,at.z],"expected_y":wanted});clean=clean and absf(y-wanted)<.0001
	check(crowns==4 and parapets>4 and seams.size()==4 and clean,"both arches, water parapets and four wall-walk jamb seams use exact local datum")
	evidence.source={"parts":fit.records.size(),"arches":crowns,"over_water_battlements":parapets,"seams":seams}
	# Ring crown and 0-degree wrap use the same optional datum, without
	# changing old recipes that omit it. Curved bank continuity is fit later.
	var ring:Dictionary=s.duplicate(true);ring.shape="ellipse";ring.erase("tower_indices");ring.radius_x=30.;ring.radius_z=24.;ring.corner_towers=false;ring.wall_access=false;ring.arrow_slits=false
	ring.gates=[{"id":"ring_water","kind":"water","angle":0.,"width":12.,"height":5.,"open":0.,"base_height":8.}]
	var curved:=Plan.new().build(ring);var ring_ok:bool=curved.ok;var crown_count:=0
	if curved.ok:
		for r:Dictionary in curved.records:
			if str(r.fortification.part).begins_with("water_crown_"):crown_count+=1;ring_ok=ring_ok and absf(r.position[1]+r.size[1]*.5-15.5)<.0001
	check(ring_ok and crown_count>0,"ring curved crowns and wraparound water opening use local elevation")
	var legacy:Dictionary=ring.duplicate(true);legacy.gates[0].erase("base_height");var old:=Plan.new().build(legacy)
	check(old.ok and old.records.filter(func(r):return r.has("water_gate")).all(func(r):return is_equal_approx(float(r.position[1]+r.size[1]*.5),7.5)),"legacy water opening still uses unchanged region datum")
func assert_unchanged(before:Dictionary,label_:String)->void:check(equivalent(before,editor._doc.recovery_snapshot()),label_)
func run()->void:
	create_timer(900).timeout.connect(func():quit(2));rpc_timeout_ms=240000
	directory=Paths.cache_directory("watergate_local_elevation_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory);DirAccess.make_dir_recursive_absolute(OUT)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();doc.records=[ground_record()];check(doc.save(path)==OK,"isolated two-elevation terrain saved")
	var settings:=recipe();source_geometry(settings)
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31940
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"current 3D MCP starts")
	var discovery:=await rpc("tools/list");var tools_:Array=discovery.get("result",{}).get("tools",[])
	var discovered:Array=tools_.filter(func(t):return t.name in ["preview_fortification","generate_fortification"])
	check(discovered.size()==2 and discovered.all(func(t):return t.inputSchema.properties.gates.items.properties.has("base_height")),"both 3D tools discover optional water-bank datum")
	var ui=editor._city.panel.fortification_panel
	if ui!=null:
		ui.gate_form(settings.gates[0]);check(ui._gate_values().base_height==4.,"UI preserves explicit bank datum")
		ui.gate_fields.fields.local_water_base.button_pressed=false;check(not ui._gate_values().has("base_height"),"UI disabled override omits field rather than forcing zero")
	else:check(false,"fortification UI instance found")
	var before:Dictionary=editor._doc.recovery_snapshot()
	var preview:=await call_tool("preview_fortification",settings);assert_unchanged(before,"preview is read only")
	if not preview.ok:finish(path);return
	check(preview.access_routes.size()==2 and is_equal_approx(float(preview.access_routes[0].room[1]),4.) and is_equal_approx(float(preview.access_routes[1].room[1]),8.),"fitted tower route room coordinates use actual bank terrain")
	check(preview.access_routes.all(func(r):return is_equal_approx(float(r.deck[1]-r.room[1]),7.5)),"fitted internal stairs and roof retain wall height")
	check(preview.gates.filter(func(g):return g.id=="land").all(func(g):return is_equal_approx(float(g.center[1]),8.)),"land gate preview uses fitted world elevation")
	for mode in ["land_override","no_follow","unsupported_bank","short_pier"]:
		var invalid:Dictionary=settings.duplicate(true)
		if mode=="land_override":invalid.gates[2].base_height=8.
		elif mode=="no_follow":invalid.follow_terrain=false
		elif mode=="unsupported_bank":invalid.gates[0].base_height=5.
		else:invalid.gates[0].water_depth=.5
		var rejected:=await call_tool("generate_fortification",invalid,false);evidence[mode]=rejected.get("error","");assert_unchanged(before,mode+" failure has no document or history side effects")
	var generate:Dictionary=settings.duplicate(true);generate.plan_token=preview.plan_token
	var made:=await call_tool("generate_fortification",generate)
	if not made.ok:finish(path);return
	var changed:Dictionary=editor._doc.recovery_snapshot();check(editor._fortifications.regions().size()==1,"two-height walls remain one owned continuous group")
	check(editor._fortifications.catalog().regions[0].modified_or_missing.is_empty(),"native frozen components retain exact ownership")
	await call_tool("undo");assert_unchanged(before,"one undo restores complete original terrain")
	await call_tool("redo");assert_unchanged(changed,"one redo restores all local gate geometry")
	await call_tool("set_fortification_gate",{"id":settings.id,"gate_id":"east_water","open":.4})
	check(editor._fortifications.regions()[0].settings.gates[1].base_height==8.,"gate state operation preserves local elevation")
	await call_tool("undo");assert_unchanged(changed,"gate operation undo preserves native group")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"native save reopen preserves both independent bank elevations and frozen geometry")
	var follower:Dictionary=settings.duplicate(true)
	var regenerated:Dictionary=editor._fortifications.prepare(follower,true,editor._doc.records)
	check(regenerated.ok,"saved frozen recipe supports native terrain-follow regeneration")
	if regenerated.ok:check(regenerated.gates.filter(func(g):return g.id=="east_water")[0].center[1]==8.,"follower regeneration keeps water gate world datum")
	finish(path)
func finish(path:String)->void:
	var resources:Array=[]
	for r:Dictionary in editor._doc.records:
		if r.has("house_prefab"):resources.append({"uuid":r.uuid,"sha256":r.house_prefab.sha256,"bytes":r.house_prefab.length,"compressed_bytes":Marshalls.base64_to_raw(r.house_prefab.data).size()})
	evidence.merge({"status":"passed" if failed==0 else "failed","failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"frozen_resources":resources,"scope":"shared UI/3D HTTP and native geometry; no GPU or formal-map mutation","visual":"pending parent layout GPU","lod":"existing fortification Art/StructurePrefab LOD contract retained; no reduction requested"})
	FileAccess.open(OUT+"/watergate_local_elevation_http.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	editor._mcp.stop();editor.queue_free();await settle();print("WATERGATE_LOCAL_ELEVATION_FINISHED failures=",failed);quit(failed)
