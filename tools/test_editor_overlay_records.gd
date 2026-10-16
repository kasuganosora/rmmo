extends "res://tools/test_world3d_mcp.gd"
## Small headless regression for delayed record bounds, no town/GPU fixture.
func run()->void:
	Engine.max_fps=60
	var directory:=Paths.cache_directory("overlay_records_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var old_id:String=doc.add_box("block",Vector3(80,1,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"isolated overlay record fixture saved")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);await settle();editor._safety.enabled=false
	var overlay=editor._city.overlay
	overlay.set_process(false)
	check(overlay._record_bounds.has(old_id),"initial native record cached")
	# Same ordering as a native remove followed by document-library placement.
	var baseline:Dictionary=doc.recovery_snapshot()
	check(doc.remove(old_id),"native old record removed")
	overlay.invalidate_uuid(old_id,{})
	var fresh:String=doc.add_box("block",Vector3(3,1,0),Vector3(4,2,2))
	var before_refresh:Dictionary=doc.recovery_snapshot()
	overlay._process(.25)
	check(overlay._record_bounds.has(fresh) and not overlay._record_bounds.has(old_id),"deferred removal reconciles unannounced native batch addition")
	check(overlay.boxes.size()==1 and overlay._record_bounds[fresh].get_center().is_equal_approx(Vector3(3,1,0)),"new bounds appear in overview instead of being skipped")
	check(overlay.bounds.end.x<20,"removed distant record leaves no stale world bounds")
	check(equivalent(before_refresh,doc.recovery_snapshot()),"derived reconciliation does not mutate document")
	# A queued stale transform must not overwrite a newer replacement or undo.
	var stale:Dictionary=doc._find(fresh).duplicate(true);stale.position=[200,1,0]
	overlay.invalidate_record(stale);doc._find(fresh).position=[5,1,0]
	overlay._process(.25)
	check(overlay._record_bounds[fresh].get_center().is_equal_approx(Vector3(5,1,0)),"queued transform resolves latest native record")
	check(doc.remove(fresh),"replacement removed before recovery")
	overlay.invalidate_uuid(fresh,{})
	doc.apply_recovery(baseline)
	overlay._process(.25)
	check(overlay._record_bounds.has(old_id) and not overlay._record_bounds.has(fresh),"recovery restores missing IDs and purges replaced IDs")
	check(overlay.boxes.size()==1 and overlay.bounds.has_point(Vector2(80,0)),"recovery overview contains current document extent")
	var restored:Dictionary=doc._find(old_id).duplicate(true)
	overlay.invalidate_uuid(old_id,{})
	overlay._process(.25)
	check(overlay._record_bounds.has(old_id) and equivalent(doc._find(old_id),restored),"late deletion tombstone cannot remove a restored live ID")
	# Publish direct batches through the existing shared city refresh, then use
	# real HTTP edit/undo/redo/save/open operations on this two-object fixture.
	var second:String=doc.add_box("block",Vector3(-6,1,0),Vector3(2,2,2))
	editor._city.refresh()
	check(overlay._record_bounds.has(second) and overlay._changed_records.is_empty(),"native batch city refresh publishes all IDs and clears pending invalidation")
	editor._rebuild();await settle()
	var probe:=TCPServer.new();port=31940
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real 3D HTTP starts")
	await call_tool("select_objects",{"ids":[second]})
	await call_tool("delete_selection",{})
	overlay._process(.25)
	check(not overlay._record_bounds.has(second),"HTTP deletion removes derived bounds")
	await call_tool("undo",{});overlay._process(.25)
	check(overlay._record_bounds.has(second),"HTTP undo restores derived bounds")
	await call_tool("redo",{});overlay._process(.25)
	check(not overlay._record_bounds.has(second),"HTTP redo removes derived bounds")
	await call_tool("save_world",{})
	await call_tool("open_world",{"path":path});await settle()
	check(editor._doc.records.size()==1 and editor._city.overlay._record_bounds.size()==1,"native save/reopen has exactly current bounds")
	editor._mcp.stop();editor.queue_free();await settle()
	print("EDITOR_OVERLAY_RECORDS failures=",failed)
	quit(0 if failed==0 else 1)
