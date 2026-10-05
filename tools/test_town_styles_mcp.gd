extends "res://tools/test_world3d_mcp.gd"
const B=preload("res://scripts/world3d/building_blueprint.gd")
func run()->void:
	create_timer(300).timeout.connect(func():quit(2));rpc_timeout_ms=180000
	var directory:=Paths.cache_directory("town_styles_http_%d"%OS.get_process_id());var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(90,.5,90))
	var basis:=Basis(Vector3.UP,PI/4)
	var obstacle:String=doc.add_box("block",basis*Vector3(0,1,-11),Vector3(40,2,3));doc._find(obstacle).rotation=[0,45,0]
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start 3D HTTP")
	var templates:=await call_tool("list_building_templates")
	check(templates.town_presets.size()==11,"all reference families discoverable")
	check(templates.window_styles.size()==6 and templates.parameters_schema.properties.window_style.enum.has("random"),"whole-building window selection discoverable")
	var args:={"parameters":templates.town_presets[8].parameters,"placements":[{"position":[0,0,0],"yaw":45}]}
	args.parameters.window_style="round_arch"
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	var random_parameters:Dictionary=templates.town_presets[6].parameters.duplicate(true)
	random_parameters.window_style="random";random_parameters.seed=7
	var random_preview:=await call_tool("preview_buildings",{"parameters":random_parameters,"placements":[{"position":[-24,0,20],"seed_offset":0},{"position":[24,0,20],"seed_offset":17}]})
	check(random_preview.get("buildings",[]).size()==2,"random window batch preview")
	for i in random_preview.get("buildings",[]).size():
		var row:Dictionary=random_preview.buildings[i]
		var expected:=random_parameters.duplicate(true);expected.seed+=0 if i==0 else 17
		var resolved:Dictionary=B.generate(expected)
		check(row.parameters.window_style==resolved.parameters.window_style,"per-instance seed resolves one window family")
		check(row.openings.filter(func(o):return o.type=="window").all(func(o):return o.window_style==row.parameters.window_style),"HTTP entire house keeps one family")
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"random preview leaves map and undo unchanged")
	await call_tool("generate_buildings",{"parameters":{"window_style":"mixed_per_window"},"placements":[{"position":[0,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid window style leaves document untouched")
	await call_tool("preview_buildings",args)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"rotated preview without mutation")
	var made:=await call_tool("generate_buildings",args)
	if not made.get("ok",false):editor.free();quit(1);return
	var id:String=made.building_ids[0]
	check(doc.map_meta.building_instances[id].baked,"rotated street-side generation freezes immediately")
	var generated:Array=doc.records.duplicate(true)
	await call_tool("undo");check(doc.records==before.records,"undo generated style")
	await call_tool("redo");check(doc.records==generated,"redo generated style")
	before=doc.recovery_snapshot();history=doc._undo.size()
	await call_tool("generate_buildings",args,false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"actual overlap rejected atomically")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,generated),"rotated fixed style native save/reopen")
	editor.free();print("TOWN_STYLES_HTTP failures=",failed);quit(1 if failed else 0)
