extends "res://tools/test_world3d_roads.gd"
func run() -> void:
	create_timer(120).timeout.connect(func():quit(2))
	directory=Paths.cache_directory("legacy_gate_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("grass",Vector3(0,-.25,0),Vector3(100,.5,100)); check(doc.save(map_path)==OK,"temporary legacy map")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var args:={"id":"legacy","style":"plain","height":6,"points":[[-20,0],[20,0]],"gates":[{"id":"gate","segment":0,"t":.5,"width":6,"height":4.5,"open":0}]}
	# Simulate the old document, not a publicly exposed generation bypass.
	check(editor._fortifications.generate(args,true).ok,"legacy 4.5m saved recipe fixture")
	var probe:=TCPServer.new(); port=30270
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"legacy HTTP starts")
	await atomic_reject("generate_fortification",args)
	await call_tool("set_fortification_gate",{"id":"legacy","gate_id":"gate","open":1})
	var settings: Dictionary=editor._fortifications.regions()[0].settings
	check(settings.gates[0].open==1 and settings.gates[0].height==4.5 and settings.height==6,"opening a legacy gate preserves existing dimensions")
	await call_tool("undo"); check(editor._fortifications.regions()[0].settings.gates[0].open==0,"legacy control undo")
	await atomic_reject("generate_fortification",{"id":"legacy","style":"medieval_stone"})
	await call_tool("generate_fortification",{"id":"legacy","style":"medieval_stone","height":7.5,"gates":[{"id":"gate","segment":0,"t":.5,"width":6,"height":5,"open":1}]})
	await call_tool("set_fortification_gate",{"id":"legacy","gate_id":"gate","open":0})
	await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records),"upgraded 5m masonry gate survives reopen")
	editor._mcp.stop(); editor.queue_free(); await settle(); print("LEGACY_GATE_FINISHED failures=",failed); quit(0 if failed==0 else 1)
