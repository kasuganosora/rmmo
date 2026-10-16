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
	var natural:={"id":"natural","terrain_ids":[terrain.id],"points":[[-12,0],[12,0]],"water_level":-.3,"width":3.,"depth":.6,"bank_width":1.,"natural_materials":true}
	await call_tool("generate_terrain_river",natural)
	var before:Dictionary=editor._doc.recovery_snapshot()
	var args:={"terrain_ids":[terrain.id],"water_level":-.3,"shore_end":2.4,"sand_material_id":"pack:default:terrain/natural_sand/material","rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"}
	await call_tool("set_river_materials",args)
	var after:Dictionary=editor._doc.recovery_snapshot()
	check(equivalent(editor._doc.map_meta.terrain_rivers[0].terrains[0].before,ground),"owned natural material before snapshot remains exact baseline")
	check(equivalent(editor._doc.map_meta.terrain_rivers[0].terrains[0].after.terrain_depth_blend,editor._doc._find(terrain.id).terrain_depth_blend),"owned terrain material after follows explicit update")
	var history:int=editor._doc._undo.size()
	await call_tool("set_river_materials",args)
	check(equivalent(after,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"identical material update does not mutate metadata or history")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"owned terrain appearance undo restores entire layer")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"owned terrain appearance redo restores entire layer")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	await call_tool("remove_terrain_river",{"id":"natural"})
	check(equivalent(ground,editor._doc._find(terrain.id)),"natural material updated then saved river removal restores exact pre-river terrain")
	await call_tool("undo")
	editor._doc._find(terrain.id).terrain_depth_blend.shore_end=3.1
	var manual:Dictionary=editor._doc.recovery_snapshot();history=editor._doc._undo.size()
	await call_tool("set_river_materials",args.merged({"shore_end":2.8},true),false)
	check(equivalent(manual,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"hand-edited owned bank material is not adopted and fails atomically")
	# Restore the original known test state, then verify unowned semantics.
	editor._doc.apply_recovery(after)
	await call_tool("remove_terrain_river",{"id":"natural"})
	natural.id="unowned";natural.natural_materials=false
	await call_tool("generate_terrain_river",natural)
	var unowned_before:Dictionary=editor._doc.map_meta.duplicate(true)
	await call_tool("set_river_materials",args)
	check(equivalent(unowned_before,editor._doc.map_meta),"unowned bank material does not become river-owned")
	var independent:Dictionary=editor._doc._find(terrain.id).terrain_depth_blend.duplicate(true)
	await call_tool("remove_terrain_river",{"id":"unowned"})
	check(equivalent(independent,editor._doc._find(terrain.id).terrain_depth_blend) and equivalent(ground.terrain_mesh,editor._doc._find(terrain.id).terrain_mesh),"river removal preserves independently authored bank material and restores only bed")
	await call_tool("set_river_materials",{"terrain_ids":[terrain.id],"enabled":false})
	var slope_before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("set_terrain_slope_materials",{"terrain_ids":[terrain.id],"rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"})
	var slope_after:Dictionary=editor._doc.recovery_snapshot()
	check(equivalent(slope_before.map_meta,slope_after.map_meta),"ordinary slope shared commit does not alter river metadata")
	await call_tool("undo");check(equivalent(slope_before,editor._doc.recovery_snapshot()),"ordinary slope undo unchanged by recovery-aware commit")
	await call_tool("redo");check(equivalent(slope_after,editor._doc.recovery_snapshot()),"ordinary slope redo unchanged by recovery-aware commit")
	print("RIVER_OWNED_MATERIALS failures=",failed);editor._mcp.stop();editor.queue_free();await settle();quit(failed)
