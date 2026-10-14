extends "res://tools/test_world3d_mcp.gd"
## CPU-only genuine HTTP regression for the near-collinear gate T junction.
const City=preload("res://scripts/world3d/city_layout.gd")
const Surface=preload("res://scripts/world3d/road_surface.gd")
func run()->void:
	rpc_timeout_ms=90000;create_timer(240).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("kerb_sliver_%d"%OS.get_process_id());var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(310,-.3,70),Vector3(160,.6,160));check(doc.save(path)==OK,"isolated flat support saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback HTTP starts")
	var defs:Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(d):return d.name=="generate_road_surface" and d.inputSchema.properties.has("kerb_enabled")),"3D road kerb schema discoverable")
	await call_tool("create_road_path",{"points":[[284,0,60],[329,0,60],[331.05,0,121.5]],"width":5})
	await call_tool("create_road_path",{"points":[[329,0,60],[329,0,50.70175],[329,0,12]],"width":5})
	var before:=doc.recovery_snapshot();var args:={"kerb_enabled":true,"material_id":"pack:default:paving/historic_cobble/material"}
	var preview:=await call_tool("preview_road_surface",args)
	check(equivalent(before,doc.recovery_snapshot()),"preview has no document mutation")
	if not preview.get("ok",false):editor._mcp.stop();quit(1);return
	await call_tool("generate_road_surface",args.merged({"plan_token":preview.plan_token}))
	var roads:Array=doc.records.filter(func(r):return r.has("road_mesh"))
	check(not roads.is_empty() and roads.all(func(r):return Surface.valid(r)),"all derived surfaces valid")
	check(roads.any(func(r):return not r.road_mesh.get("kerbs",[]).is_empty()),"real continuous kerbs remain enabled")
	var generated:=doc.recovery_snapshot()
	await call_tool("generate_road_surface",{"kerb_width":2},false)
	check(equivalent(generated,doc.recovery_snapshot()),"invalid width still rejects with no side effects")
	await call_tool("undo");check(equivalent(before,doc.recovery_snapshot()),"undo restores graph without generated pavement")
	await call_tool("redo");check(equivalent(generated,doc.recovery_snapshot()),"redo restores pavement and kerbs")
	await call_tool("save_world")
	var reopened=Doc.open_file(path)
	check(reopened!=null and equivalent(doc.records,reopened.records) and equivalent(doc.map_meta,reopened.map_meta),"native save/reopen retains exact road/kerb authoring")
	print("KERB_SLIVER_HTTP failures=",failed)
	editor._mcp.stop();editor.queue_free();await settle();quit(0 if failed==0 else 1)
