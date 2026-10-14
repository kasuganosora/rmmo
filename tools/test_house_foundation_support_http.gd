extends "res://tools/test_world3d_buildings.gd"
const Foot=preload("res://scripts/world_editor/building_footprint.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Library=preload("res://scripts/world_editor/prefab_library.gd")
func slope(id:String,x:float,base:float)->Dictionary:
	var heights:Array=[]
	for z in 19:
		for u in 17:heights.append(base+(u-8)*.02)
	var holes:Array=[];holes.resize(16*18);holes.fill(false)
	return {"uuid":id,"kind":"box","surface_id":"ground","position":[x,0.,0.],"rotation":[0,0,0],"size":[16.,1.,18.],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":16,"rows":18,"floor":-8.,"heights":heights,"holes":holes}}
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var p:Dictionary=Blueprint.defaults().merged({"layout":"townhouse","template":"house","width":9.,"depth":11.,"floors":1,"floor_height":3.5,"base_height":.3,"foundation_depth":1.,"style":"plaster","roof_axis":"depth","roof_pitch":36.,"chimney":false,"front_canopy":false},true)
	var plan:=Blueprint.generate(p);check(plan.ok,"native raised house fixture")
	var cap:float=Foot.foundation_support_height(p,0.,plan.records)
	check(absf(cap-.3)<.000001 and not Foot.supporting_ground(slope("baseline",0.,.12),.22,0.) and Foot.supporting_ground(slope("baseline",0.,.12),.22,cap),"regression: origin-only rejection becomes foundation contact below raised floor")
	check(Foot.foundation_support_height(p.merged({"foundation_depth":0.},true),0.,plan.records)==0.,"zero-depth foundation does not gain soil allowance")
	check(Foot.foundation_support_height(p.merged({"layout":"standard"},true),0.,plan.records)==0.,"unraised standard layout keeps its original origin limit")
	var metadata_cap:float=Foot.foundation_support_height(p.merged({"base_height":.9},true),0.,plan.records)
	check(metadata_cap<.319 and not Foot.supporting_ground(slope("baseline",0.,.12),.34,metadata_cap),"real floor geometry caps overstated prefab recipe headroom")
	check(Foot.foundation_support_height(p,0.,[])==0.,"missing real ground-floor geometry cannot grant raised allowance")
	var road:Dictionary={"surface_id":"ground","road_mesh":{}}
	check(not Foot.supporting_ground(road,.05,cap),"road meshes remain obstacles regardless of raised base")
	var directory:=Paths.external_root().path_join("__house_foundation_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"house_foundation_test","name":"临时斜地房基测试包"}))
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();doc.records=[slope("legal_generated",-15.,.12),slope("legal_prefab",15.,.12),slope("buried_floor",45.,.65)]
	check(doc.save(path)==OK,"disposable three-slope fixture saved")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await physics();editor._safety.enabled=false
	var probe:=TCPServer.new();port=31935
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback 3D HTTP MCP")
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	var args:Dictionary={"parameters":p,"placements":[{"position":[-15.,0.,0.]}]}
	var preview:=await call_tool("preview_buildings",args)
	check(preview.ok and equivalent(before,doc.recovery_snapshot()),"UI/shared generator preview accepts the real sloping foundation without terrain edits")
	await call_tool("generate_buildings",{"parameters":p.merged({"foundation_depth":0.},true),"placements":[{"position":[-15.,0.,0.]}]},false)
	await call_tool("generate_buildings",{"parameters":p,"placements":[{"position":[45.,0.,0.]}]},false)
	check(equivalent(before,doc.recovery_snapshot()) and history==doc._undo.size(),"buried interior and no-foundation failures are atomic")
	var made:=await call_tool("generate_buildings",args)
	if not made.get("ok",false):editor.free();quit(1);return
	var id:String=made.building_ids[0];var after:Array=doc.records.duplicate(true)
	check(doc.map_meta.building_instances[id].baked and equivalent(doc.records.slice(0,3),before.records),"native frozen placement keeps every original terrain vertex unchanged")
	await call_tool("undo");check(equivalent(doc.records,before.records),"undo restores original slope and empty site")
	await call_tool("redo");check(equivalent(doc.records,after),"redo restores the same raised house")
	var member:String=doc.map_meta.building_instances[id].parts.values()[0]
	await call_tool("select_objects",{"ids":[member]})
	var saved:=await call_tool("save_prefab",{"name":"斜地抬高房基","pack_root":directory})
	if not saved.get("ok",false):editor.free();quit(1);return
	before=doc.recovery_snapshot();history=doc._undo.size()
	# Saved prefab coordinates are relative to the author's chosen ground origin.
	await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[45.,0.,0.]},false)
	check(equivalent(before,doc.recovery_snapshot()) and history==doc._undo.size(),"library placement still rejects soil above the real indoor floor")
	var placed:=await call_tool("place_asset",{"asset_id":saved.asset_id,"position":[15.,0.,0.]})
	check(placed.get("ok",false) and doc.map_meta.building_instances.size()==2,"real HTTP library placement uses the same raised-floor allowance")
	if not placed.get("ok",false):editor.free();quit(1);return
	after=doc.records.duplicate(true)
	await call_tool("undo");check(equivalent(doc.records,before.records),"prefab undo restores the previous site")
	await call_tool("redo");check(equivalent(doc.records,after),"prefab redo restores identical geometry")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(equivalent(editor._doc.records,after) and editor._doc.map_meta.building_instances.size()==2,"native save/reopen retains both valid sloping-ground placements")
	editor._mcp.stop();editor.queue_free();await settle();Net.session().world3d_editor_path="";Net.session().world3d_editor_doc=null
	print("HOUSE_FOUNDATION_SUPPORT_HTTP ",directory," failures=",failed);quit(failed)
