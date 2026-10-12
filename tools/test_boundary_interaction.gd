extends "res://tools/test_world3d_mcp.gd"
func run()->void:
	create_timer(240).timeout.connect(func():quit(2));rpc_timeout_ms=60000
	var path:String=OS.get_cmdline_user_args()[0]
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=path.get_base_dir().path_join("interaction_drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31120
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"interaction HTTP starts")
	var panel:Node=editor._terrain_panel.tasks.get_node("中心线河道")
	panel.settings.fields.id.text="reroute";panel.load_existing()
	check(equivalent(panel.points,[[-12.,55.],[12.,55.]]),"river UI loads persisted centerline")
	panel.point_list.select(0);panel.coordinates.update_values({"point":[-11.,54.]});panel.replace_point()
	check(equivalent(panel.args().points,[[-11.,54.],[12.,55.]]),"river UI edits selected point without reordering")
	var before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("set_fortification_terrain_follow",{"id":"missing","enabled":true},false)
	check(equivalent(before,editor._doc.recovery_snapshot()),"invalid follow target atomic")
	var hill:Dictionary=editor._doc.records.filter(func(r):return r.has("terrain_mesh") and r.position[2]==150.)[0]
	var parts:Array=editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id")=="following_towers").duplicate(true)
	var brush:Control=editor._terrain_brush;brush.before_state=before;brush.before=before.records;brush.was_dirty=editor._dirty;brush.pointer_down=true;brush.target_id=hill.uuid
	var stroke:Dictionary=editor._terrain.sculpt({"id":hill.uuid,"mode":"raise","points":[[0,150]],"radius":32.,"hardness":1.,"strength":.1},true)
	check(stroke.ok,"interactive terrain dab succeeds")
	for id:String in stroke.get("changed_ids",[]):brush.changed_ids.append(id)
	check(equivalent(parts,editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id")=="following_towers")),"drag does not refreeze structures every dab")
	var history:int=editor._doc._undo.size();brush.finish()
	check(editor._doc._undo.size()==history+1 and not equivalent(parts,editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id")=="following_towers")),"mouse release follows towers once in same undo")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"interactive follow exact rollback via undo")
	brush.before_state=before;brush.before=before.records;brush.was_dirty=editor._dirty;brush.pointer_down=true;brush.target_id=hill.uuid
	stroke=editor._terrain.sculpt({"id":hill.uuid,"mode":"raise","points":[[-20,150]],"radius":3.,"hardness":.1,"strength":1.},true)
	check(stroke.ok,"uneven tower preview deferred until release")
	for id:String in stroke.get("changed_ids",[]):brush.changed_ids.append(id)
	history=editor._doc._undo.size();brush.finish()
	check(editor._doc._undo.size()==history and equivalent(before,editor._doc.recovery_snapshot()),"unlevel tower platform rolls back entire gesture without history")
	editor._mcp.stop();editor.queue_free();await settle();print("BOUNDARY_INTERACTION_FINISHED failures=",failed);quit(failed)
