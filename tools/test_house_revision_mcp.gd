extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	var directory:=Paths.cache_directory("house_revision_mcp_%d"%Time.get_ticks_usec())
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.2,0),Vector3(70,.4,70));check(doc.save(path)==OK,"temporary native map")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await physics();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"loopback HTTP MCP")
	check((await rpc("tools/list")).result.tools.size()==118,"current 3D discovery")
	var catalog:=await call_tool("list_building_templates")
	for key in ["base_height","stair_layout","curtains"]:check(catalog.parameters_schema.properties.has(key),"shared schema "+key)
	check(not (await call_tool("get_environment")).environment.interior_cutaway,"cutaway disabled by default")
	await call_tool("set_environment",{"interior_cutaway":true})
	await call_tool("set_environment",{"interior_cutaway":false})
	await call_tool("undo");check((await call_tool("get_environment")).environment.interior_cutaway,"undo camera switch")
	await call_tool("redo");check(not (await call_tool("get_environment")).environment.interior_cutaway,"redo camera switch")
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	for invalid in [{"base_height":-1},{"stair_layout":"spiral"},{"curtains":1}]:await call_tool("generate_buildings",{"parameters":invalid,"placements":[{"position":[0,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid new controls have no side effects")
	var made:=await call_tool("generate_buildings",{"parameters":Blueprint.medieval_presets()[0].parameters,"placements":[{"position":[0,0,0]}]})
	if not made.get("ok",false):quit(1);return
	var id:String=made.building_ids[0];var records:Array=doc.records.duplicate(true)
	check(records.any(func(r):return r.has("wall_grid")),"continuous wall apertures authored")
	check(records.any(func(r):return r.get("building_shape")=="draped_cloth"),"continuous cloth authored through HTTP MCP")
	check(records.any(func(r):return r.get("building_shape")=="joined_box"),"coplanar joins trimmed through HTTP MCP")
	check(records.any(func(r):return r.get("building_shape")=="candle_sconce"),"wall-mounted candle lights authored through HTTP MCP")
	check(not records.any(func(r):return r.get("building",{}).get("part","").contains("/wall_hand")),"no residual wall handrails")
	await call_tool("undo");check(doc.records==before.records,"whole house undo")
	await call_tool("redo");check(doc.records==records,"whole house redo")
	await call_tool("save_world");await call_tool("open_world",{"path":path});doc=editor._doc
	check(not (await call_tool("get_environment")).environment.interior_cutaway,"disabled cutaway saved and reopened")
	check(equivalent(doc.records,records),"wall apertures and hardware survive save/reopen")
	var conflicts:Array=(await call_tool("list_buildings")).buildings[0].conflicts
	if not conflicts.is_empty():print("RECIPE_CONFLICTS ",JSON.stringify(conflicts))
	check(conflicts.is_empty(),"saved recipe signatures stable")
	editor.free();Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("HOUSE_REVISION_MCP_FINISHED failures=",failed);quit(1 if failed else 0)
