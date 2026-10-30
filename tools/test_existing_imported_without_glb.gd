extends "res://tools/test_world3d_mcp.gd"
## Read existing native products while the external runner withholds their GLBs.
## Never imports/rebuilds models or writes the original map/library.
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Preview=preload("res://scripts/world_editor/asset_preview.gd")
const Thumbnails=preload("res://scripts/world_editor/asset_thumbnails.gd")

func present(uuid:String)->bool:
	var node:Node=editor._view.get_node_or_null(NodePath(uuid))
	return node!=null and not node.get_meta("missing_asset",false) and node.get_child_count()>0

func wait_idle()->void:
	var deadline:=Time.get_ticks_msec()+90000
	while editor.saving() and Time.get_ticks_msec()<deadline:await process_frame
	check(not editor.saving(),"editor transaction finishes")

func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	rpc_timeout_ms=90000;Engine.max_fps=60
	var config_path:=OS.get_environment("RMMO_EXISTING_MODEL_PROBE")
	var output:=OS.get_environment("RMMO_EXISTING_MODEL_OUTPUT")
	if config_path.is_empty() or not output.contains("/review_artifacts/") or DisplayServer.get_name()=="headless":quit(2);return
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	check(Paths.external_root()==config.root,"probe reads actual existing content root")
	var absent:=OS.get_environment("RMMO_EXISTING_MODEL_WITHHELD")=="1"
	for entry:Dictionary in config.entries:
		check(FileAccess.file_exists(entry.asset_path)!=absent,"GLB presence matches cold-process sample "+entry.label)
		check(Assets.native_available(entry.asset_path),"existing native registration survives source state "+entry.label)
	if failed>0:quit(1);return
	var map_path:=output.path_join("map.gltf")
	var document:=Doc.new();document.add_box("ground",Vector3(0,-.1,0),Vector3(100,.2,100))
	check(document.save(map_path)==OK,"save only an isolated test map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=output.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle();await wait_idle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"actual editor HTTP endpoint")
	var preview:=Preview.new();preview.size=Vector2(320,240);editor.add_child(preview)
	var thumbnails:=Thumbnails.new();editor.add_child(thumbnails)
	var placed:Array[String]=[]
	for index:int in config.entries.size():
		var entry:Dictionary=config.entries[index]
		preview.show_asset(entry.asset_path)
		var thumbnail:Dictionary=entry.duplicate();thumbnail.thumbnail_path=output.path_join("thumbnail_%d.png"%index)
		thumbnails.queue_import(thumbnail)
		var deadline:=Time.get_ticks_msec()+60000
		while (preview.scene==null or preview._readiness.active() or not FileAccess.file_exists(thumbnail.thumbnail_path)) and Time.get_ticks_msec()<deadline:await process_frame
		check(preview.scene!=null and preview.streaming_error.is_empty(),"real preview opens "+entry.label)
		check(FileAccess.file_exists(thumbnail.thumbnail_path),"new thumbnail renders "+entry.label)
		var listing:=await call_tool("list_assets",{"query":entry.label})
		var rows:Array=listing.get("assets",[]).filter(func(row):return row.get("asset_id","")==Thumbnails.key_for(entry))
		check(not rows.is_empty(),"existing library advertises "+entry.label)
		if rows.is_empty():continue
		var result:=await call_tool("place_asset",{"asset_id":rows[0].asset_id,"position":[index*20,0,0]})
		var uuid:String=str(result.get("ids",[""])[0]);placed.append(uuid)
		check(not uuid.is_empty() and present(uuid),"real prepared placement renders "+entry.label)
		await call_tool("select_objects",{"ids":[uuid]});await call_tool("duplicate_selection")
		check(editor._doc.records.filter(func(row):return row.get("asset_path")==entry.asset_path).size()==2,"duplicate keeps both native models "+entry.label)
		await call_tool("undo");check(present(uuid),"undo keeps original native model "+entry.label)
	preview.free();thumbnails.free()
	await call_tool("save_world");await call_tool("open_world",{"path":map_path});await wait_idle()
	check(placed.size()==3 and placed.all(present),"saved three actual models reopen without placeholders")
	await call_tool("start_playtest",{"position":[0,0,10]})
	var deadline:=Time.get_ticks_msec()+90000
	while editor._playtest.phase in ["preparing","loading"] and Time.get_ticks_msec()<deadline:await process_frame
	check(editor._playtest.phase=="running","actual existing models enter gameplay: "+editor._playtest.last_error)
	if editor._playtest.phase=="running":
		var world_root:Node3D=editor._playtest.world._map_root
		var rendered:Dictionary={}
		for uuid:String in placed:
			# Runtime expands imported components into uuid__part siblings so each
			# part retains its own visibility/LOD and batching semantics.
			var meshes:Array=[]
			for model:Node in world_root.get_children():
				if str(model.name)!=uuid and not str(model.name).begins_with(uuid+"__"):continue
				if model is MeshInstance3D:meshes.append(model)
				meshes.append_array(model.find_children("*","MeshInstance3D",true,false))
			rendered[uuid]=meshes.filter(func(mesh):return mesh.mesh!=null and mesh.mesh.get_surface_count()>0).size()
		print("EXISTING_RUNTIME_GEOMETRY "+JSON.stringify({"models":rendered,"root_children":world_root.get_children().map(func(child):return str(child.name))}))
		check(placed.size()==3 and rendered.values().all(func(count):return count>0),"runtime contains actual mesh surfaces for all three imported models")
		await call_tool("stop_playtest")
	await wait_idle();check(placed.size()==3 and placed.all(present),"return to editor preserves actual models")
	for entry:Dictionary in config.entries:check(FileAccess.file_exists(entry.asset_path)!=absent,"operations did not reconstruct a source GLB")
	editor.free();editor=null;await settle()
	print("EXISTING_WITHOUT_GLB failed=%d"%failed);quit(0 if failed==0 else 1)
