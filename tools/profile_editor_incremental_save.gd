extends "res://tools/test_world3d_mcp.gd"
const Pose=preload("res://scripts/world3d/pose_save.gd")
const Art=preload("res://scripts/asset/art_paths.gd")
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,900);root.content_scale_size=root.size
	create_timer(1800).timeout.connect(func():quit(2))
	var source:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var signature:=FileAccess.get_sha256(source)
	var directory:=Paths.cache_directory("town_incremental_save_%d"%Time.get_ticks_usec());var path:=directory.path_join("map.gltf")
	var doc=Doc.open_file(source)
	check(doc!=null,"read-only current town source")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"full-town HTTP save server")
	var reports:Array=[]
	var asset:Dictionary={}
	var cloned_id:String=""
	for phase in ["baseline","asset_move","asset_clone","asset_delete"]:
		if phase=="asset_move":
			for record in doc.records:
				if record.get("kind")=="asset" and not record.has("house_prefab") and not record.has("bridge_mesh") and not record.get("editor_locked",false):asset=record;break
			check(not asset.is_empty(),"ordinary imported asset available")
			await call_tool("set_object_transform",{"id":asset.uuid,"position":[asset.position[0],asset.position[1]+1.,asset.position[2]]})
		if phase=="asset_clone":
			await call_tool("select_objects",{"ids":[asset.uuid]})
			await call_tool("duplicate_selection")
			cloned_id=str(editor._selection_tools.ids[0])
		if phase=="asset_delete":
			await call_tool("select_objects",{"ids":[cloned_id]})
			await call_tool("delete_selection")
		var pending:=await call_tool("save_world",{"background":true})
		check(pending.pending,"background town save started")
		var result:Dictionary=await editor._save_job.wait_result()
		reports.append({"phase":phase,"result":result})
		print("TOWN_INCREMENTAL_SAVE ",phase," ",result)
		if phase!="baseline":
			var exported:Dictionary=result.get("timings",{}).get("export",{})
			check(exported.get("mode")==("pose_reuse" if phase=="asset_move" else "incremental_reuse"),"full town reuses exports after "+phase)
			check(exported.get("images_written",-1)==0 and exported.get("texture_export_passes",-1)==0,"town "+phase+" exports no textures")
	var reopened=Doc.open_file(path)
	check(reopened!=null and Pose.same(Pose.extras(reopened.records,reopened.map_meta),Pose.extras(doc.records,doc.map_meta)),"temporary town reopens with every record and registry")
	check(FileAccess.get_sha256(source)==signature,"formal town source remains unchanged")
	var output:={"failures":failed,"source":source,"source_sha256":signature,"output":path,"records":doc.records.size(),"runs":reports}
	var file:=FileAccess.open(Art.review_path("editor_incremental_save_town_20261007.json"),FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("TOWN_INCREMENTAL_SAVE_FINISHED ",failed)
	editor._mcp.stop();editor.queue_free();await settle();quit(0 if failed==0 else 1)
