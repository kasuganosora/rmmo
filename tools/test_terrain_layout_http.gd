extends "res://tools/test_world3d_mcp.gd"
## Small real-HTTP regression for a jointly validated road/terrain layout.
const City=preload("res://scripts/world3d/city_layout.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014"
var ground_id:String
var evidence:Array=[]
func snapshot()->Dictionary:
	var value:Dictionary=editor._doc.recovery_snapshot()
	for key:String in ["next","disk_signature","disk_path","dirty"]:value.erase(key)
	return value
func token()->String:return City.token(City.resolve(editor._doc.map_meta).roads)
func rejected(tool:String,args:Dictionary,label:String)->Dictionary:
	var before:=snapshot();var history:int=editor._doc._undo.size()
	var result:=await call_tool(tool,args,false)
	check(equivalent(before,snapshot()) and history==editor._doc._undo.size(),label+" leaves records, metadata and history unchanged")
	evidence.append({"case":label,"tool":tool,"result":result})
	return result
func plot(center:Array,y:float)->Dictionary:
	return {"id":ground_id,"mode":"flatten","shape":"rectangle","points":[center],"plot_width":22.,"plot_depth":18.,"plot_yaw":0.,"plot_grade":[0.,0.],"blend_margin":1.,"target_height":y,"strength":1.,"cross_tiles":true}
func height(point:Vector3)->float:
	var r:Dictionary=editor._doc._find(ground_id)
	return (Terrain.transform(r)*Vector3(point.x,Terrain.sample(r,Terrain.transform(r).affine_inverse()*point),point.z)).y
func run()->void:
	create_timer(300).timeout.connect(func():quit(2));rpc_timeout_ms=90000
	var directory:=Paths.cache_directory("terrain_layout_http_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native layout fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32610
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP joint-layout fixture starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="preview_terrain_layout") and definitions.any(func(t):return t.name=="apply_terrain_layout"),"joint preview/apply discovered through current 3D MCP")
	var created:=await call_tool("create_terrain",{"center":[0,0,0],"width":40.,"depth":24.,"cell_size":1.})
	ground_id=created.id
	var layout:=await call_tool("get_city_layout",{})
	await call_tool("update_road_graph",{"expected_token":layout.road_token,"nodes":[{"id":"west","position":[-14,0,0]},{"id":"middle","position":[0,0,0]},{"id":"east","position":[14,0,0]}],"edges":[{"id":"left","from":"west","to":"middle","kind":"ground","width_start":3.,"width_end":3.},{"id":"right","from":"middle","to":"east","kind":"ground","width_start":3.,"width_end":3.}]})
	await call_tool("generate_road_surface",{"follow_terrain":true,"kerb_enabled":true,"kerb_width":.24,"kerb_height":.035})
	var left:=plot([-9.,0.],1.);var right:=plot([9.,0.],1.)
	var single:=await rejected("sculpt_terrain",left,"first half alone makes a real steep road transition")
	check(single.get("code","")=="terrain_projection_grade_limit","single-stroke failure is the intended actual road grade guard")
	var args:={"strokes":[left,right],"road_nodes":[{"id":"middle","position":[0.,1.,.5]}],"expected_road_token":token()}
	await rejected("apply_terrain_layout",args.merged({"expected_road_token":"stale"},true),"stale road token")
	await rejected("apply_terrain_layout",args.merged({"strokes":[]},true),"empty stroke list")
	await rejected("apply_terrain_layout",args.merged({"road_nodes":[{"id":"absent","position":[0.,1.,0.]}]},true),"unknown road node cannot create topology")
	var bad:=args.duplicate(true);bad.strokes[1].plot_grade=[.16,0.]
	await rejected("apply_terrain_layout",bad,"over-limit requested slope")
	await call_tool("set_object_properties",{"ids":[ground_id],"locked":true})
	await rejected("apply_terrain_layout",args,"locked terrain");await call_tool("undo")
	var road_id:String=editor._doc.records.filter(func(r):return r.has("road_mesh"))[0].uuid
	await call_tool("set_object_properties",{"ids":[road_id],"locked":true})
	await rejected("apply_terrain_layout",args,"locked derived road");await call_tool("undo")
	var before:=snapshot();var history:int=editor._doc._undo.size()
	var panel=editor._terrain_panel.terrain_layout
	panel.strokes=args.strokes.duplicate(true);panel.road_nodes=args.road_nodes.duplicate(true);panel.road_token=args.expected_road_token
	check(equivalent(panel.request(),args),"real UI draft emits the same joint request as HTTP")
	panel._execute(false)
	check(equivalent(before,snapshot()) and history==editor._doc._undo.size(),"real UI preview leaves document and history unchanged")
	var preview:=await call_tool("preview_terrain_layout",args)
	check(equivalent(before,snapshot()) and history==editor._doc._undo.size(),"valid preview is read-only")
	var shared=load("res://scripts/world_editor/terrain_layout_tools.gd")
	var ui:Dictionary=shared.preview(editor,args)
	check(equivalent(ui,preview),"UI business preview equals real HTTP preview")
	var applied:=await call_tool("apply_terrain_layout",args)
	if not applied.get("ok",false):
		print("TERRAIN_LAYOUT_HTTP early failure ",JSON.stringify(applied));quit(1);return
	var after:=snapshot()
	check(editor._doc._undo.size()==history+1,"all plots, node and regenerated roads create exactly one undo entry")
	check(absf(height(Vector3(-13,0,0))-1.)<.0001 and absf(height(Vector3(0,0,0))-1.)<.0001 and absf(height(Vector3(13,0,0))-1.)<.0001,"both halves form the intended continuous final surface")
	var middle:Array=City.resolve(editor._doc.map_meta).roads.nodes.filter(func(n):return n.id=="middle")[0].position
	check(equivalent(middle,[0.,1.,.5]),"existing node position is updated in the same transaction")
	check(editor._doc.records.filter(func(r):return r.has("road_mesh")).all(func(r):return r.has("terrain_follow")),"regenerated road retains editable terrain-follow semantics")
	await call_tool("undo");check(equivalent(before,snapshot()),"one undo restores both plots, graph and derived road")
	await call_tool("redo");check(equivalent(after,snapshot()),"one redo restores complete final joint layout")
	await call_tool("undo")
	panel.strokes=args.strokes.duplicate(true);panel.road_nodes=args.road_nodes.duplicate(true);panel.road_token=args.expected_road_token
	panel._execute(true)
	check(equivalent(after,snapshot()) and panel.strokes.is_empty(),"real UI apply uses identical shared transaction and clears its draft")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(after,snapshot()),"native save/reopen preserves terrain, graph and road ownership")
	# A second, disjoint fixture makes a genuine solid bridge collision. The
	# valid first stroke must not leak through when the later stroke is rejected.
	var bridge_ground:=await call_tool("create_terrain",{"center":[50,8.175,0],"width":20.,"depth":20.,"cell_size":.5})
	await call_tool("generate_bridge",{"id":"protected_arch","prefab_id":"stone_segmental","start":[46,8.2,0],"end":[54,8.2,0],"width":6.2,"depth":1.5,"camber":0.,"arches":1,"wing_length":0.,"auto_clearance":false,"clearance_mode":"stream"})
	var intrude:={"id":bridge_ground.id,"mode":"flatten","shape":"rectangle","points":[[50.,0.]],"plot_width":2.,"plot_depth":2.,"blend_margin":.5,"target_height":9.,"strength":1.,"cross_tiles":true}
	var blocked:=await rejected("apply_terrain_layout",{"strokes":[plot([-9.,0.],1.01),intrude],"road_nodes":[],"expected_road_token":token()},"genuine fill through the frozen bridge body")
	check(blocked.get("conflicts",[]).has("protected_arch"),"joint validation identifies the actual frozen bridge collision")
	var result:={"failures":failed,"map":path,"map_sha256":FileAccess.get_sha256(path),"preview":preview,"apply":applied,"cases":evidence,"scope":"isolated CPU/true loopback HTTP; no candidate or formal content changes"}
	FileAccess.open(OUT+"/terrain_layout_http_review.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	editor._mcp.stop();editor.queue_free();await settle();session.world3d_editor_path="";session.world3d_editor_doc=null
	print("TERRAIN_LAYOUT_HTTP failures=",failed);quit(1 if failed else 0)
