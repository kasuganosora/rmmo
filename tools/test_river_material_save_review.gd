extends "res://tools/test_world3d_mcp.gd"
const Layer=preload("res://scripts/world3d/terrain_river_layer.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
func run()->void:
	create_timer(420).timeout.connect(func():quit(2));rpc_timeout_ms=120000
	var directory:=Paths.cache_directory("river_material_save_review_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("original/map.gltf");var save_as:=directory.path_join("save_as/river.gltf")
	var doc:=Doc.new();check(doc.save(path)==OK,"material fixture saved in isolated directory")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31330
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"natural material review uses real HTTP")
	var ground:=await call_tool("create_terrain",{"center":[0,0,0],"width":32.,"depth":32.,"cell_size":1.})
	await call_tool("set_terrain_slope_materials",{"terrain_ids":[ground.id],"rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material","steep_start":30.,"steep_end":60.})
	# A fixture-owned copy makes this old material dependency unique to the
	# restore snapshot. The default art library is never removed or modified.
	var terrain:Dictionary=editor._doc._find(ground.id)
	var source:String=terrain.terrain_slope_blend.rock_material.texture_path
	var copied:=directory.path_join("restore_texture."+source.get_extension())
	check(DirAccess.copy_absolute(source,copied)==OK,"copied fixture-only old slope texture")
	terrain.terrain_slope_blend.rock_material.texture_path=copied
	check(Paint.texture(terrain.terrain_slope_blend.rock_material)!=null,"fixture old material texture decodes with original format")
	var original:=terrain.duplicate(true)
	var river:={"id":"natural_restore","terrain_ids":[ground.id],"points":[[-12,-4],[12,-4]],"width":4.,"bank_width":2.,"water_level":-.5,"depth":1.5,"natural_materials":true}
	await call_tool("generate_terrain_river",river)
	var layer:Dictionary=editor._doc.map_meta.terrain_rivers[0]
	check(layer.terrains[0].before.terrain_slope_blend.rock_material.texture_path==copied and layer.terrains[0].after.has("terrain_depth_blend"),"layer preserves old slope and replacement natural river materials")
	await call_tool("save_world",{"path":save_as});await call_tool("open_world",{"path":save_as})
	check(Layer.valid(editor._doc.map_meta) and Paint.missing(Layer.snapshot_records(editor._doc.map_meta)).is_empty(),"natural before/after materials remain valid after Save As reopen")
	check(Layer.same(editor._doc.map_meta.terrain_rivers[0].terrains[0].after,editor._doc._find(ground.id)),"saved natural material snapshot matches native live record exactly")
	await call_tool("remove_terrain_river",{"id":river.id})
	check(Layer.same(editor._doc._find(ground.id),original),"remove after Save As restores complete original slope material and bed")
	await call_tool("undo")
	river.points=[[-12,4],[12,4]]
	await call_tool("generate_terrain_river",river)
	await call_tool("save_world");await call_tool("open_world",{"path":save_as})
	var state:Dictionary=editor._doc.recovery_snapshot();var history:int=editor._doc._undo.size()
	var disk:=FileAccess.get_sha256(save_as)
	check(copied.begins_with(directory+"/") and copied.get_basename().get_file()=="restore_texture","fixture deletion stays in its own directory")
	check(DirAccess.remove_absolute(copied)==OK,"removed only isolated old slope texture")
	check(editor._doc.missing_assets().count(copied)==1,"latent old material is included once in missing dependency list")
	await call_tool("remove_terrain_river",{"id":river.id},false)
	check(equivalent(state,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"missing latent texture rejects restore without state or history effects")
	await call_tool("save_world",{},false)
	check(FileAccess.get_sha256(save_as)==disk and equivalent(state,editor._doc.recovery_snapshot()),"missing latent texture rejects save without replacing map")
	check(DirAccess.copy_absolute(source,copied)==OK,"fixture old texture restored")
	check(editor._doc.missing_assets().is_empty(),"restored latent dependency clears missing list")
	await call_tool("remove_terrain_river",{"id":river.id})
	check(Layer.same(editor._doc._find(ground.id),original),"restoration succeeds and exactly recovers old slope after texture returns")
	await call_tool("save_world");await call_tool("open_world",{"path":save_as})
	check(Layer.same(editor._doc._find(ground.id),original),"restored original survives final save and reopen")
	print("RIVER_MATERIAL_SAVE_REVIEW_ARTIFACTS ",directory)
	editor._mcp.stop();editor.queue_free();await settle();print("RIVER_MATERIAL_SAVE_REVIEW_FINISHED failures=",failed);quit(0 if failed==0 else 1)
