extends "res://tools/test_world3d_mcp.gd"
const Pose=preload("res://scripts/world3d/pose_save.gd")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("pose_http_%d"%Time.get_ticks_usec());var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();var box:String=doc.add_box("block",Vector3(40,2,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"isolated initial map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual HTTP MCP")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size() and definitions.any(func(t):return t.name=="save_world"),"3D save discovery")
	await call_tool("set_object_transform",{"id":box,"position":[42,2,0]})
	var moved:=await call_tool("save_world")
	check(moved.saved and moved.timings.export.mode=="pose_reuse" and moved.timings.export.texture_export_passes==0,"HTTP pose save skips exporter")
	var made:=await call_tool("generate_buildings",{"parameters":{"floors":1,"width":9,"depth":12,"rooms_per_floor":1},"placements":[{"position":[0,0,0]}]})
	var building:String=made.building_ids[0];var part:String=editor._buildings.instances()[building].parts.values()[0]
	var fixture_ids:Array=[]
	for record in doc.records:
		if record.has("fixture"):fixture_ids.append(record.uuid);record.fixture.open=.4
	# Changing hinge state is intentionally a full export; the next rigid move
	# must preserve that open pose in both baked and ordinary fixture records.
	var baseline:=await call_tool("save_world")
	check(baseline.saved and baseline.timings.export.mode=="full_export" and not fixture_ids.is_empty(),"baked building and open fixtures establish full baseline")
	var resources:=Pose.dependencies(Pose._json(path),path,Paths.external_root(),Io)
	await call_tool("select_objects",{"ids":[part]})
	await call_tool("transform_selection",{"translation":[5,3,2],"rotation":[0,31,0]})
	var expected:Dictionary=doc.recovery_snapshot()
	var saved:=await call_tool("save_world")
	check(saved.saved and saved.timings.export.mode=="pose_reuse","whole building rigid move uses pose save")
	check(Pose.same(resources,Pose.dependencies(Pose._json(path),path,Paths.external_root(),Io)),"building textures and buffers remain byte-identical")
	var raw:=Pose._json(path);var by_name:Dictionary={}
	for node in raw.nodes:by_name[node.get("name","")]=node
	for id in fixture_ids:
		check(Pose._node_pose(by_name[id]).is_equal_approx(Pose.pose(doc._find(id))),"saved open fixture follows whole-building pose "+id)
	for record in doc.records:
		if record.has("building"):check(Pose.same(by_name[record.uuid].extras.building,record.building),"saved floor elevation and ownership "+record.uuid)
	await call_tool("undo")
	var undone:=await call_tool("save_world")
	print("UNDO_SAVE ",undone.timings)
	check(undone.timings.export.mode=="pose_reuse","undo retains fast-save baseline")
	await call_tool("redo")
	check((await call_tool("save_world")).timings.export.mode=="pose_reuse","redo retains fast-save baseline")
	await call_tool("open_world",{"path":path})
	check(Pose.same(Pose.extras(editor._doc.records,editor._doc.map_meta),Pose.extras(expected.records,expected.map_meta)),"HTTP reopen preserves building registry and records")
	# Busy state and failed writes use the same shared asynchronous operation.
	Io.save_fault=func(stage):
		if stage=="resources_ready":OS.delay_msec(350)
		return false
	var started:=await call_tool("save_world",{"background":true})
	check(started.pending and editor.saving(),"background reuse reports a live job")
	await call_tool("undo",{},false)
	check((await call_tool("editor_state")).save.active,"reuse remains queryable during publication")
	await editor._save_job.wait_result();Io.save_fault=Callable()
	var signature:=FileAccess.get_sha256(path)
	Io.save_fault=func(stage):return stage=="before_publish"
	editor._dirty=true
	await call_tool("save_world",{},false)
	check(editor._dirty and not editor.saving() and FileAccess.get_sha256(path)==signature,"failed HTTP reuse unlocks editor and retains dirty map")
	Io.save_fault=Callable()
	check((await call_tool("save_world")).saved,"retry publishes safely")
	editor._mcp.stop();editor.queue_free();await settle();Io._remove_tree(directory)
	print("POSE_HTTP_FINISHED failures=",failed," metrics=",saved.timings)
	quit(0 if failed==0 else 1)
