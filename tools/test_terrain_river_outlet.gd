extends "res://tools/test_world3d_mcp.gd"
const Channel=preload("res://scripts/world3d/channel_surface.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const Outlet=preload("res://scripts/world3d/terrain_river_outlet.gd")
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const Road=preload("res://scripts/world3d/road_plan.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")

func reject_atomic(tool:String,args:Dictionary,label:String)->void:
	var before:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	await call_tool(tool,args,false)
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),label)

func water_polys(layer:Dictionary)->Array:
	var result:Array=[]
	for part in layer.water:
		var r:Dictionary=editor._doc._find(part.id);var pose:=Terrain.transform(r)
		for local:Array in Channel.local_polygons(r):
			var p:Array=[];var y:Array=[]
			for v:Vector3 in local:
				var world:Vector3=pose*v;p.append(Vector2(world.x,world.z));y.append(world.y)
			result.append({"polygon":p,"heights":y})
	return result

func run()->void:
	create_timer(360).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("terrain_river_outlet_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated outlet fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31931
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"outlet real HTTP MCP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="generate_terrain_river" and t.inputSchema.properties.has("outlet")),"3D discovery exposes explicit outlet")
	var ground:=await call_tool("create_terrain",{"center":[0,0,0],"width":64.,"depth":64.,"cell_size":1.})
	var main:={"id":"receiver","terrain_ids":[ground.id],"points":[[-25,0],[25,0]],"width":6.,"bank_width":1.,"water_level":-1.,"depth":.8,"curved":false,"natural_materials":false}
	await call_tool("generate_terrain_river",main)
	var baseline:Dictionary=editor._doc.recovery_snapshot()
	var branch:={"id":"branch","terrain_ids":[ground.id],"points":[[0,25],[0,12],[0,8],[0,0]],"width":3.,"bank_width":1.,"water_level":-.2,"water_levels":[-.2,-1.,-1.,-1.],"depth":1.1,"curved":false,"natural_materials":false,"outlet":{"river_id":"receiver","endpoint":"end"}}
	var bad:=branch.duplicate(true);bad.erase("outlet");await reject_atomic("generate_terrain_river",bad,"undeclared overlap remains rejected")
	for target in ["missing","branch"]:
		bad=branch.duplicate(true);bad.outlet.river_id=target;await reject_atomic("generate_terrain_river",bad,"missing/self target rejected atomically")
	bad=branch.duplicate(true);bad.outlet.endpoint="start";await reject_atomic("generate_terrain_river",bad,"nonterminal outlet schema rejected atomically")
	bad=branch.duplicate(true);bad.water_levels=[-.2,-.9,-.9,-.9];await reject_atomic("generate_terrain_river",bad,"different mouth level rejected atomically")
	bad=branch.duplicate(true);bad.points=[[-15,20],[-15,-10],[0,-10],[0,0]];await reject_atomic("generate_terrain_river",bad,"nonterminal receiver overlap rejected atomically")
	var water_id:String=editor._doc.map_meta.terrain_rivers[0].water[0].id
	await call_tool("set_object_properties",{"ids":[water_id],"locked":true});await reject_atomic("generate_terrain_river",branch,"locked receiving water rejected atomically");await call_tool("undo")
	var target:Dictionary=editor._doc._find(water_id);var old_color:Variant=target.color.duplicate();target.color=[.1,.1,.1]
	await reject_atomic("generate_terrain_river",branch,"hand-edited receiving water rejected atomically");target.color=old_color
	# Directly tamper one owned receiver sample to exercise persisted protection.
	var terrain:Dictionary=editor._doc._find(ground.id);var index:=32*65+32;var original:float=terrain.terrain_mesh.heights[index];terrain.terrain_mesh.heights[index]=original+.1
	await reject_atomic("generate_terrain_river",branch,"hand-edited receiver bed rejected atomically")
	terrain.terrain_mesh.heights[index]=original
	await call_tool("preview_terrain_river",branch)
	check(equivalent(baseline,editor._doc.recovery_snapshot()),"outlet preview preserves receiver byte-equivalent state")
	await call_tool("generate_terrain_river",branch)
	check(Layer.valid(editor._doc.map_meta) and editor._doc.map_meta.terrain_rivers.size()==2,"outlet has valid explicit two-layer ownership")
	var received:Dictionary=editor._doc.map_meta.terrain_rivers[0];var tributary:Dictionary=editor._doc.map_meta.terrain_rivers[1]
	var area:=0.;var seam_points:=0;var seam_ok:=true
	for a in water_polys(tributary):
		for b in water_polys(received):
			var overlap:Array=Road.intersection(a.polygon,b.polygon)
			if overlap.size()>=3:area+=Poly.area(overlap)
		for i in a.polygon.size():
			var p:Vector2=a.polygon[i]
			if absf(p.y-3.)<.0001 and absf(p.x)<1.5001:seam_points+=1;seam_ok=seam_ok and absf(a.heights[i]+1.)<.00001
	check(area<.00001 and seam_points>0 and seam_ok,"water overlap area zero and shared mouth edge level equal")
	for part:Dictionary in received.water:check(preload("res://scripts/world3d/city_layout.gd").token(editor._doc._find(part.id))==part.signature,"receiver original water unchanged")
	var first_branch:Dictionary=editor._doc.recovery_snapshot()
	var other:=branch.duplicate(true);other.id="second_branch";other.points=[[18,25],[18,12],[18,8],[18,0]]
	await call_tool("generate_terrain_river",other)
	check(editor._doc.map_meta.terrain_rivers.size()==3,"remote independent mouth remains legal on same receiving terrain")
	await call_tool("remove_terrain_river",{"id":"second_branch"})
	check(equivalent(first_branch.records,editor._doc.records) and equivalent(first_branch.map_meta,editor._doc.map_meta),"removing remote mouth preserves first tributary")
	other=branch.duplicate(true);other.id="occupied_mouth"
	await reject_atomic("generate_terrain_river",other,"already owned mouth cannot be adopted by another tributary")
	await reject_atomic("remove_terrain_river",{"id":"receiver"},"dependent tributary blocks receiver deletion")
	await reject_atomic("generate_terrain_river",main,"dependent tributary blocks receiver modification")
	var cyc:=main.duplicate(true);cyc.outlet={"river_id":"branch"};await reject_atomic("generate_terrain_river",cyc,"dependency cycle rejected atomically")
	var meta:Dictionary=editor._doc.map_meta.duplicate(true);meta.terrain_rivers[0].request.outlet={"river_id":"branch"};check(not Layer.valid(meta),"persisted cycle invalid")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");await call_tool("undo");await call_tool("undo");check(equivalent(baseline,editor._doc.recovery_snapshot()),"branch undo restores complete receiving terrain")
	await call_tool("redo");await call_tool("redo");await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"branch redo restores exact mouth ownership")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(Layer.valid(editor._doc.map_meta),"dependency survives native save/reopen")
	await reject_atomic("remove_terrain_river",{"id":"receiver"},"dependency still enforced after reopen")
	await call_tool("remove_terrain_river",{"id":"branch"})
	check(Layer.same(editor._doc._find(ground.id).terrain_mesh,baseline.records.filter(func(r):return r.uuid==ground.id)[0].terrain_mesh),"removing reopened branch exactly restores receiver bed samples")
	check(editor._doc.map_meta.terrain_rivers.size()==1,"removal preserves receiver layer")
	await call_tool("remove_terrain_river",{"id":"receiver"})
	check(editor._doc.map_meta.terrain_rivers.is_empty(),"receiver removable after tributary removal")
	print("TERRAIN_RIVER_OUTLET_HTTP failures=",failed," path=",path);quit(failed)
