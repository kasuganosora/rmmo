extends "res://tools/test_world3d_mcp.gd"
## Exercise a cold material-cache reopen after actual import and UI/HTTP paint.
## File-system cache is uncontrolled; this is a work-placement test, not cold IO.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")

func painted_texture(id:String)->Texture2D:
	var visual:Node3D=editor._view.get_node_or_null(id)
	if visual==null:return null
	for mesh:MeshInstance3D in Paint.meshes(visual):
		for slot:int in mesh.mesh.get_surface_count():
			var material:Material=mesh.get_active_material(slot)
			if material is StandardMaterial3D and material.albedo_texture!=null:return material.albedo_texture
	return null

func run()->void:
	create_timer(120).timeout.connect(func():quit(2));Engine.max_fps=60;rpc_timeout_ms=60000
	var directory:=Paths.cache_directory("painted_texture_reopen_%d"%Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(directory)==OK,"fresh external fixture")
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=Doc.new();session.world3d_editor_path=""
	editor=preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart=false;editor._material_directory=directory.path_join("materials");editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real editor HTTP MCP")
	for kind:String in ["dds","png"]:
		var image:=Image.create(32 if kind=="dds" else 31,32,false,Image.FORMAT_RGB8);image.fill(Color(.3,.5,.8))
		var source:=directory.path_join(kind+".png");check(image.save_png(source)==OK,kind+": save import source")
		var imported:=await call_tool("import_surface_material",{"path":source,"name":"reopen "+kind})
		check(imported.get("dds_ready",false)==(kind=="dds"),kind+": actual import selects DDS or genuine PNG fallback")
		if not imported.get("ok",false):editor.queue_free();await settle();quit(1);return
		var doc:=Doc.new();var ids:Array[String]=[]
		for i:int in 2:ids.append(doc.add_box("block",Vector3(i*3,1,0),Vector3(2,2,2)))
		var path:=directory.path_join(kind+".gltf");check(doc.save(path)==OK,kind+": save two ordinary boxes")
		await call_tool("open_world",{"path":path,"discard_changes":true})
		for i:int in ids.size():
			var faces:=await call_tool("list_object_surfaces",{"id":ids[i]})
			if faces.get("faces",[]).is_empty():check(false,"paintable box faces");quit(1);return
			if i==0:await call_tool("paint_surface",{"id":ids[i],"target":faces.faces[0].target,"material_id":imported.material_id})
			else:
				editor._material_tool.selected={"ok":true,"id":ids[i],"target":faces.faces[0].target}
				editor._material_tool.material_id=imported.material_id;editor._material_panel._apply()
				var deadline:=Time.get_ticks_msec()+30000
				while editor._doc._find(ids[i]).get("surface_paint",[]).is_empty() and Time.get_ticks_msec()<deadline:await process_frame
				check(not editor._doc._find(ids[i]).get("surface_paint",[]).is_empty(),kind+": real UI paints second box")
		var after:Array=editor._doc.records.duplicate(true)
		await call_tool("undo");check(editor._doc._find(ids[1]).get("surface_paint",[]).is_empty(),kind+": UI paint undo")
		await call_tool("redo");check(equivalent(editor._doc.records,after),kind+": UI paint redo")
		await call_tool("save_world")
		Paint.refresh_sources();Pixels.reset_profile();Pixels.profile_enabled=true;Paint.texture_profile_enabled=true
		await call_tool("open_world",{"path":path,"discard_changes":true})
		var state:Dictionary=editor._load_job.state();var counters:Dictionary=Pixels.profile_snapshot("").counters
		check(state.phase=="complete" and equivalent(editor._doc.records,after),kind+": full save/reopen preserves painted records")
		var first:=painted_texture(ids[0]);var second:=painted_texture(ids[1])
		check(first!=null and first==second,kind+": both published boxes share actual texture owner")
		var uploaded:Image=first.get_image() if first!=null else null
		check(uploaded!=null and uploaded.is_compressed()==(kind=="dds"),kind+": scene keeps selected DDS or PNG representation")
		check(state.timings.preparation.started==1,kind+": shared texture prepared by exactly one background job")
		check(state.timings.preparation.ledger.jobs==0,kind+": preparation budget fully returned")
		check(counters.get("paint.texture.sidecar_main_reads",0)==0,kind+": no synchronous DDS read during reopen publication")
		check(counters.get("paint.texture.runtime_image_lookup",0)==0,kind+": no synchronous source image lookup during reopen publication")
		check(counters.get("paint.texture.prepared_image_hit",0)>0,kind+": publication consumes worker pixels")
		print("PAINTED_TEXTURE_REOPEN ",JSON.stringify({"kind":kind,"state":state,"counters":counters,"fixture":directory}))
		Pixels.profile_enabled=false;Paint.texture_profile_enabled=false
	editor.queue_free();await settle();session.world3d_editor_doc=null;session.world3d_editor_path=""
	print("EDITOR_PAINTED_TEXTURE_REOPEN_FAILED=",failed);quit(1 if failed else 0)
