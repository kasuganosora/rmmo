extends "res://tools/test_world3d_mcp.gd"
## Focused HTTP regression: unrelated terrain layout alongside owned outlets.
const City=preload("res://scripts/world3d/city_layout.gd")
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const Layout=preload("res://scripts/world_editor/terrain_layout_tools.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
var cases:Array=[]
var ground_id:String
func snapshot()->Dictionary:
	var value:Dictionary=editor._doc.recovery_snapshot()
	for key:String in ["next","disk_signature","disk_path","dirty"]:value.erase(key)
	return value
func plot(point:Array,y:float)->Dictionary:
	return {"id":ground_id,"mode":"flatten","shape":"rectangle","points":[point],"plot_width":4.,"plot_depth":4.,"blend_margin":1.,"target_height":y,"strength":1.,"cross_tiles":true}
func rejected(args:Dictionary,label:String)->void:
	var before:=snapshot();var history:int=editor._doc._undo.size()
	var result:=await call_tool("apply_terrain_layout",args,false)
	check(equivalent(before,snapshot()) and history==editor._doc._undo.size(),label+" is atomic")
	cases.append({"case":label,"result":result})
func changed(item:Dictionary,i:int)->bool:
	return not Layer.same(item.before.terrain_mesh.heights[i],item.after.terrain_mesh.heights[i])
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("terrain_layout_outlet_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native outlet-layout fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32640
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real current 3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="preview_terrain_layout") and definitions.any(func(t):return t.name=="apply_terrain_layout"),"shared layout tools discovered")
	var ground:=await call_tool("create_terrain",{"center":[0,0,0],"width":64.,"depth":64.,"cell_size":1.});ground_id=ground.id
	var main:={"id":"receiver","terrain_ids":[ground_id],"points":[[-25,0],[25,0]],"width":6.,"bank_width":1.,"water_level":-1.,"depth":.8,"curved":false,"natural_materials":false}
	await call_tool("generate_terrain_river",main)
	var branch:={"id":"branch","terrain_ids":[ground_id],"points":[[0,25],[0,12],[0,8],[0,0]],"width":3.,"bank_width":1.,"water_level":-.2,"water_levels":[-.2,-1.,-1.,-1.],"depth":1.1,"curved":false,"natural_materials":false,"outlet":{"river_id":"receiver","endpoint":"end"}}
	await call_tool("generate_terrain_river",branch)
	var sibling:=branch.duplicate(true);sibling.id="sibling";sibling.points=[[18,25],[18,12],[18,8],[18,0]]
	await call_tool("generate_terrain_river",sibling)
	if failed:quit(1);return
	var layers:Array=editor._doc.map_meta.terrain_rivers
	var direct:=Layer.restore(editor._doc._find(ground_id),layers[0].terrains[0].before,layers[0].terrains[0].after)
	check(not direct.ok,"fixture has actual shared mouth deltas; single-layer restore remains strict")
	var shared_index:=-1;var exclusive_index:=-1
	for i in layers[0].terrains[0].after.terrain_mesh.heights.size():
		if changed(layers[0].terrains[0],i) and changed(layers[1].terrains[0],i):shared_index=i
		if changed(layers[0].terrains[0],i) and not changed(layers[1].terrains[0],i) and not changed(layers[2].terrains[0],i):exclusive_index=i
	check(shared_index>=0 and exclusive_index>=0,"shared and exclusive receiver samples exist")
	var args:={"strokes":[plot([-20.,20.],.25)]}
	var baseline:=snapshot();var history:int=editor._doc._undo.size()
	var preview:=await call_tool("preview_terrain_layout",args)
	check(equivalent(baseline,snapshot()) and history==editor._doc._undo.size(),"valid outlet preview preserves actual records and history")
	var panel=editor._terrain_panel.terrain_layout
	panel.strokes=args.strokes.duplicate(true);panel.road_nodes=[];panel.road_token=""
	var ui_args:Dictionary=panel.request()
	check(equivalent(ui_args.strokes,args.strokes),"UI uses identical native strokes")
	panel._execute(false)
	check(equivalent(baseline,snapshot()) and equivalent(Layout.preview(editor,args),preview),"UI preview is read-only and shares HTTP business")
	await rejected({"strokes":[plot([0.,0.],.25)]},"real owned riverbed edit")
	# Persisted malformed fixtures are private, never passed through map saving.
	for index:int in [shared_index,exclusive_index]:
		var terrain:Dictionary=editor._doc._find(ground_id);var old:float=terrain.terrain_mesh.heights[index]
		terrain.terrain_mesh.heights[index]=old+.125
		await rejected(args,"hand-edited current owned sample "+str(index))
		terrain.terrain_mesh.heights[index]=old
	var old_meta:Dictionary=editor._doc.map_meta.duplicate(true)
	editor._doc.map_meta.terrain_rivers[1].request.erase("outlet")
	check(Layer.valid(editor._doc.map_meta),"undeclared overlap fixture otherwise has valid snapshots")
	await rejected(args,"matching snapshot chain without an outlet")
	editor._doc.map_meta=old_meta.duplicate(true)
	editor._doc.map_meta.terrain_rivers[1].request.outlet.river_id="sibling"
	await rejected(args,"declared but geometrically unrelated outlet")
	editor._doc.map_meta=old_meta.duplicate(true)
	editor._doc.map_meta.terrain_rivers[0].request.outlet={"river_id":"branch","endpoint":"end"}
	await rejected(args,"cyclic outlet history")
	editor._doc.map_meta=old_meta.duplicate(true)
	# A valid mouth cannot authorize additional overlap far from that mouth.
	var terrain:Dictionary=editor._doc._find(ground_id);var old:float=terrain.terrain_mesh.heights[exclusive_index]
	editor._doc.map_meta.terrain_rivers[1].terrains[0].after.terrain_mesh.heights[exclusive_index]=old-.1
	terrain.terrain_mesh.heights[exclusive_index]=old-.1
	await rejected(args,"valid outlet cannot launder unrelated distant overlap")
	terrain.terrain_mesh.heights[exclusive_index]=old;editor._doc.map_meta=old_meta.duplicate(true)
	var water_id:String=old_meta.terrain_rivers[1].water[0].id
	var water:Dictionary=editor._doc._find(water_id);var color:Variant=water.color.duplicate();water.color=[.13,.17,.21]
	await rejected(args,"hand-edited tributary water signature")
	water.color=color
	# Dependency order, not array order, determines virtual restoration.
	editor._doc.map_meta.terrain_rivers=[old_meta.terrain_rivers[2],old_meta.terrain_rivers[0],old_meta.terrain_rivers[1]].duplicate(true)
	await call_tool("preview_terrain_layout",args)
	editor._doc.map_meta=old_meta.duplicate(true)
	check(equivalent(baseline,snapshot()),"all negative fixtures restored exactly")
	var applied:=await call_tool("apply_terrain_layout",args)
	var after:=snapshot()
	check(editor._doc._undo.size()==history+1,"unrelated layout remains one native transaction")
	check(Layer.same(baseline.map_meta,after.map_meta),"river requests, snapshots and ownership history unchanged")
	await call_tool("undo");check(equivalent(baseline,snapshot()),"undo restores complete terrain and metadata")
	await call_tool("redo");check(equivalent(after,snapshot()),"redo restores complete valid result")
	await call_tool("undo")
	panel.strokes=args.strokes.duplicate(true);panel.road_nodes=[];panel.road_token="";panel._execute(true)
	check(equivalent(after,snapshot()) and panel.strokes.is_empty(),"real UI apply equals HTTP native transaction")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(after,snapshot()) and Layer.valid(editor._doc.map_meta),"save and reopen preserve legal ownership stack")
	await rejected({"strokes":[plot([0.,0.],.25)]},"owned riverbed still protected after reopen")
	await call_tool("remove_terrain_river",{"id":"receiver"},false)
	await call_tool("remove_terrain_river",{"id":"sibling"})
	await call_tool("remove_terrain_river",{"id":"branch"})
	await call_tool("remove_terrain_river",{"id":"receiver"})
	check(absf(float(editor._doc._find(ground_id).terrain_mesh.heights[52*65+12])-.25)<.00001,"strict native river removal preserves unrelated grading")
	var report:={"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"preview":preview,"apply":applied,"cases":cases,"source_sha256":FileAccess.get_sha256("res://scripts/world_editor/terrain_layout_tools.gd"),"scope":"isolated headless real 3D HTTP and UI shared transaction; no candidate or formal map mutation"}
	FileAccess.open(OUT+"/terrain_layout_outlet_http_review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_LAYOUT_OUTLET_HTTP failures=",failed);quit(1 if failed else 0)
