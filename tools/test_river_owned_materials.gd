extends "res://tools/test_world3d_mcp.gd"
const City=preload("res://scripts/world3d/city_layout.gd")
func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	var directory:=Paths.cache_directory("river_owned_materials_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");check(Doc.new().save(path)==OK,"isolated native fixture")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=32001
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP starts")
	var terrain:=await call_tool("create_terrain",{"center":[0,0,0],"width":32,"depth":32,"cell_size":1})
	var ground:Dictionary=editor._doc._find(terrain.id).duplicate(true)
	var request:={"id":"slope","terrain_ids":[terrain.id],"points":[[-12,0],[12,0]],"water_level":-.3,"water_levels":[-.3,-1.3],"width":3.,"depth":.6,"bank_width":1.,"natural_materials":false}
	var river:=await call_tool("generate_terrain_river",request)
	var before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("set_river_materials",{"water_ids":river.water_ids,"absorption":2.6})
	var after:Dictionary=editor._doc.recovery_snapshot();var layer:Dictionary=editor._doc.map_meta.terrain_rivers[0]
	check(layer.water.all(func(w):return w.signature==City.token(editor._doc._find(w.id))),"explicit water material edit refreshes owned signatures")
	check(editor._doc._find(river.water_ids[0]).water_depth_effect.absorption==2.6,"actual sloped water material updated")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"one undo restores appearance and owned signatures")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores appearance and owned signatures")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	await call_tool("remove_terrain_river",{"id":"slope"})
	check(equivalent(ground,editor._doc._find(terrain.id)),"recoloured saved river still removes and restores exact bed")
	await call_tool("undo")
	# Simulate an untracked imported/manual edit, not a semantic material command.
	editor._doc._find(river.water_ids[0]).color=[.9,.1,.1]
	var edited:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	await call_tool("set_river_materials",{"water_ids":river.water_ids,"absorption":2.4},false)
	check(equivalent(edited,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"hand-edited water cannot be silently adopted; failure is atomic")
	print("RIVER_OWNED_MATERIALS failures=",failed);editor._mcp.stop();editor.queue_free();await settle();quit(failed)
