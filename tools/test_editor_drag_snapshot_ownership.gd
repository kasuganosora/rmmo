extends "res://tools/test_world3d_city_layout.gd"

func begin_drag(id: String, mode: int=0, handle: int=0) -> Vector2:
	editor._transform_mode=mode
	var center: Vector3=editor._selection_tools.pivot()
	var screen: Vector2=editor._camera.unproject_position(center)
	if mode==1: screen=editor._camera.unproject_position(center+Vector3(3,0,0))
	check(editor._inspector.selection==id and editor._transform_drag.begin(editor,screen,handle),"UI drag begins")
	return screen

func run() -> void:
	Engine.max_fps=60
	directory=Paths.cache_directory("drag_ownership_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new()
	var first: String=doc.add_box("block",Vector3.ZERO,Vector3(2,2,2))
	var second: String=doc.add_box("block",Vector3(8,0,0),Vector3(2,2,2))
	check(doc.save(path)==OK,"temporary drag fixture saved")
	doc._undo.clear(); doc._redo.clear()
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_doc=doc; session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor); editor._safety.enabled=false; await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"actual HTTP history server")
	await call_tool("select_objects",{"ids":[first]})
	editor._city.apply_camera({"center":[0,0,0],"distance":35.,"pitch":-35.,"yaw":0.,"span":40.,"projection":"perspective"}); await settle()
	var initial: Array=doc.records.duplicate(true)
	begin_drag(first); editor._transform_drag.finish()
	check(doc._undo.is_empty() and equivalent(initial,doc.records),"click without motion leaves history and document unchanged")
	var start:=begin_drag(first)
	var owned: Array=editor._transform_drag.before
	editor._transform_drag.update(start+Vector2(30,0),true); editor._transform_drag.finish()
	check(doc._undo.size()==1 and is_same(doc._undo.back(),owned) and editor._transform_drag.before.is_empty(),"UI commit transfers its private snapshot exactly once and drops caller reference")
	check(equivalent(initial,owned) and not is_same(doc.records,owned),"committed snapshot remains independent of live records")
	var moved: Array=doc.records.duplicate(true)
	start=begin_drag(first); editor._transform_drag.update(start+Vector2(45,0),true); editor._transform_drag.finish(true)
	check(doc._undo.size()==1 and equivalent(moved,doc.records) and equivalent(initial,owned),"later cancelled drag changes neither current state nor previous history")
	await atomic_reject("transform_selection",{"translation":[1000001,0,0]})
	await call_tool("transform_selection",{"translation":[0,2,0]})
	check(doc._undo.size()==2 and equivalent(doc._undo[0],initial) and equivalent(doc._undo[1],moved),"HTTP transform shares history semantics without aliasing earlier UI transaction")
	var http_state: Array=doc.records.duplicate(true)
	await call_tool("undo"); check(equivalent(doc.records,moved),"undo HTTP restores UI commit")
	await call_tool("undo"); check(equivalent(doc.records,initial),"undo UI restores original snapshot")
	await call_tool("redo"); check(equivalent(doc.records,moved),"redo UI restores exact pose")
	await call_tool("redo"); check(equivalent(doc.records,http_state),"redo HTTP restores exact pose")
	await call_tool("select_objects",{"ids":[first,second]})
	start=begin_drag(second,2,3)
	editor._transform_drag.update(start+Vector2(12,-12),true); editor._transform_drag.finish()
	var scaled: Array=doc.records.duplicate(true)
	check(doc._undo.size()==3 and equivalent(doc._undo[2],http_state) and equivalent(doc._undo[0],initial),"multi-object scale adds one independent full snapshot")
	await call_tool("undo"); check(equivalent(doc.records,http_state),"scale undo restores all sizes and poses")
	await call_tool("redo"); check(equivalent(doc.records,scaled),"scale redo preserves full snapshot semantics")
	await call_tool("save_world"); await call_tool("open_world",{"path":path})
	check(equivalent(editor._doc.records,scaled),"save/reopen preserves mixed UI/HTTP final state")
	var history_doc:=Doc.new(); history_doc.records=[{"position":[0,0,0]}]
	for i in 35:
		var snapshot: Array=history_doc.records.duplicate(true)
		history_doc.commit_owned_snapshot(snapshot); snapshot=[]
		history_doc.records[0].position[0]=i+1
	check(history_doc._undo.size()==32 and history_doc._undo[0][0].position[0]==3 and history_doc._undo.back()[0].position[0]==34,"owned snapshots retain existing 32-entry cap and independent nested arrays")
	editor.queue_free(); await settle()
	print("EDITOR_DRAG_OWNERSHIP_FAILED=",failed)
	quit(1 if failed else 0)
