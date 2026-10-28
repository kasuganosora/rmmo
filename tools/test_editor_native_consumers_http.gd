extends "res://tools/test_world3d_mcp.gd"
## Full editor UI/HTTP consumers with a real imported native model and no GLB.
## Run only via run_godot_background.py in a private desktop.

func write_static_fixture(path:String)->void:
	var value:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"translation":[10,2,0],"children":[1]},{"mesh":0,"scale":[2,1,1]}],"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[-1,0,-2],"max":[1,4,2]}],"bufferViews":[{"buffer":0,"byteLength":36}],"buffers":[{"byteLength":36}]}
	var json:=JSON.stringify(value).to_utf8_buffer()
	while json.size()%4:json.append(32)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546c67);file.store_32(2);file.store_32(json.size()+64)
	file.store_32(json.size());file.store_32(0x4e4f534a);file.store_buffer(json)
	file.store_32(36);file.store_32(0x004e4942);file.store_buffer(PackedFloat32Array([-1,0,-2,1,4,2,0,1,0]).to_byte_array());file.close()

func run()->void:
	create_timer(180).timeout.connect(func():quit(2))
	Engine.max_fps=60
	var test_root:=OS.get_environment("RMMO_NATIVE_CONSUMER_TEST_ROOT")
	var manager:=root.get_node_or_null("AssetManager")
	if test_root.is_empty() or not test_root.is_absolute_path() or not DirAccess.dir_exists_absolute(test_root) or manager==null:
		check(false,"existing absolute isolated content root required");quit(1);return
	manager.content_root_override=test_root
	var source:=test_root.path_join("author_tree.glb")
	write_static_fixture(source);check(FileAccess.file_exists(source),"write real temporary author GLB")
	var library=preload("res://scripts/world_editor/asset_library.gd").new(test_root.path_join("assets"))
	var imported:Dictionary=library.import_file(source)
	check(imported.get("ok",false),"editor import publishes native product")
	if not imported.get("ok",false):print("IMPORT_FIXTURE_ERROR ",imported);quit(1);return
	var entry:Dictionary=imported.entry;var model_path:String=entry.asset_path
	check(library.native_available(model_path) and DirAccess.remove_absolute(model_path)==OK,"delete imported GLB after native publication")
	var map:=test_root.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(30,.5,30));check(doc.save(map)==OK,"save isolated scatter map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=test_root.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;editor._shared_assets.append(library);await settle()
	var diagnostic_candidate:Dictionary=library.native_candidate(model_path)
	var direct:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(model_path,diagnostic_candidate,test_root,Callable(),preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),false,"",true)
	print("NATIVE_DIRECT_READER_DIAGNOSTIC ",JSON.stringify({"error":direct.get("error",null),"reason":direct.get("cache_reason",""),"fallback":direct.get("fallback_required",false),"packed":direct.get("packed") is PackedScene,"root":test_root}))
	check(direct.get("error",FAILED)==OK and direct.get("packed") is PackedScene,"Windows backslash root and logical path read the admitted published native product")
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(direct)
	var normalized_root:String=preload("res://scripts/world3d/map_paths.gd").external_root()
	var direct_normal:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(model_path,diagnostic_candidate,normalized_root,Callable(),preload("res://scripts/world3d/runtime_package_policy.gd").trusted(),false,"",true)
	print("NATIVE_NORMAL_READER_DIAGNOSTIC ",JSON.stringify({"error":direct_normal.get("error",null),"reason":direct_normal.get("cache_reason",""),"fallback":direct_normal.get("fallback_required",false),"packed":direct_normal.get("packed") is PackedScene,"root":normalized_root,"input":model_path,"declared":diagnostic_candidate.get("source_path","")}))
	check(direct_normal.get("error",FAILED)==OK and direct_normal.get("packed") is PackedScene,"canonical root accepts the same Windows backslash logical path")
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(direct_normal)
	var forged:=diagnostic_candidate.duplicate();forged.product=test_root.get_base_dir().path_join("outside.scn")
	var outside:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(model_path,forged,test_root,Callable(),true,false,"",true)
	check(outside.get("fallback_required",false) and outside.get("cache_reason")=="candidate_product","different product path remains rejected before loading")
	var wrong_source:=test_root.get_base_dir().path_join(model_path.get_file())
	var forbidden:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read(wrong_source,diagnostic_candidate,test_root,Callable(),true,false,"",true)
	check(forbidden.get("fallback_required",false) and forbidden.get("cache_reason")=="candidate_identity","outside logical source remains rejected")
	var diagnostic_packet:Dictionary=library._read_published_native(model_path,diagnostic_candidate)
	print("NATIVE_PREVIEW_READER_DIAGNOSTIC ",JSON.stringify({"candidate":diagnostic_candidate,"error":diagnostic_packet.get("error",null),"hit":diagnostic_packet.get("hit",false),"reason":diagnostic_packet.get("cache_reason",""),"main":OS.get_main_thread_id(),"caller":OS.get_thread_caller_id(),"policy_trusted":preload("res://scripts/world3d/runtime_package_policy.gd").trusted()}))
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_result(diagnostic_packet)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real 3D HTTP service")
	var listed:=await call_tool("list_vegetation_scatter")
	check(listed.get("assets",[]).any(func(value):return value.get("asset_id","")==model_path),"native-only asset appears in 3D MCP scatter catalog")
	var args:={"id":"native_grove","asset_ids":[model_path],"polygon":[[-10,-10],[10,-10],[10,10],[-10,10]],"count":4,"seed":3,"spacing":3}
	var before:Array=editor._doc.records.duplicate(true);var history:int=editor._doc._undo.size()
	var preview:=await call_tool("preview_vegetation_scatter",args)
	check(preview.get("count",0)>0 and equivalent(before,editor._doc.records) and history==editor._doc._undo.size(),"HTTP scatter preview uses native geometry without mutating document")
	if preview.get("count",0)>0:
		await call_tool("generate_vegetation_scatter",args.merged({"plan_token":preview.plan_token}))
		check(editor._doc._undo.size()==history+1,"native scatter generation is one undo transaction")
		await call_tool("undo");check(equivalent(before,editor._doc.records),"native scatter undo restores original document")
		await call_tool("redo")
		var save_result:=await call_tool("save_world")
		var saved:Array=editor._doc.records.duplicate(true)
		var open_result:=await call_tool("open_world",{"path":map})
		check(save_result.get("ok",false) and open_result.get("ok",false) and equivalent(saved,editor._doc.records),"native scatter save and reopen preserve authored records")
		var original_signature:String=FileAccess.get_sha256(map)
		var external_edit:=FileAccess.open(map,FileAccess.READ_WRITE)
		external_edit.seek_end();external_edit.store_string(" ");external_edit.close()
		var external_signature:String=FileAccess.get_sha256(map)
		check(original_signature!=external_signature,"isolated map receives an external edit after reopening")
		var conflict:=await call_tool("save_world",{},false)
		check(not conflict.get("ok",true) and FileAccess.get_sha256(map)==external_signature,"Windows path normalization preserves conflict detection and external bytes")
	var thumb:String=editor._thumbnails.thumbnail_path(entry)
	if FileAccess.file_exists(thumb):DirAccess.remove_absolute(thumb)
	editor._thumbnails.set_visible_entries([entry])
	for i in 600:
		var status:Dictionary=editor._thumbnails.state(entry)
		if status.status in ["ready","failed"]:break
		await process_frame
	check(editor._thumbnails.state(entry).status=="ready" and FileAccess.file_exists(thumb),"visible native-only asset auto-repairs its thumbnail")
	check(not FileAccess.file_exists(model_path),"ordinary editor consumers never recreate removed GLB")
	editor.queue_free();await settle()
	print("EDITOR_NATIVE_CONSUMERS_HTTP_FAILED=",failed)
	quit(1 if failed else 0)
