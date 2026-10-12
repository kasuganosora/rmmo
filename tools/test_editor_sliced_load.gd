extends "res://tools/test_world3d_mcp.gd"
const Pose=preload("res://scripts/world3d/pose_save.gd")
func data(count_:int)->Dictionary:
	var records:Array=[]
	for i in count_:records.append({"uuid":"obj_%d"%[i+1],"kind":"box","surface_id":"block","position":[i%12,1,i/12],"size":[1,1,1],"rotation":[0,0,0]})
	return {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"rmmo_world","extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":1,"rmmo_records":records}}]}
func run()->void:
	Engine.max_fps=60
	var directory:=Paths.cache_directory("sliced_load_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var initial:=directory.path_join("initial.gltf");var doc:=Doc.new();doc.add_box("block",Vector3.ZERO,Vector3.ONE)
	check(doc.save(initial)==OK,"initial isolated map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_doc=doc;session.world3d_editor_path=initial
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts")
	root.add_child(editor);editor._safety.enabled=false;await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP sliced-load server")
	editor._selection_tools.set_ids(["obj_1"]);doc.checkpoint()
	var selected:Dictionary={"id":"obj_1","target":{"test":"preserve"}}
	editor._material_tool.selected=selected.duplicate(true)
	var before:Dictionary=doc.recovery_snapshot();var history:int=doc._undo.size()
	var bad:=data(120);bad.nodes[0].extras.rmmo_records[119].uuid="obj_1"
	var broken:=directory.path_join("duplicate.gltf");FileAccess.open(broken,FileAccess.WRITE).store_string(JSON.stringify(bad))
	# A tiny private test budget guarantees many validation frames without
	# constructing a giant fixture or introducing production delay hooks.
	editor._load_job._validation_budget_us=1
	var job:=await call_tool("open_world",{"path":broken,"background":true})
	check(job.pending,"background HTTP open returns before sliced validation")
	while editor._load_job.active and editor._load_job.phase=="read":await process_frame
	check(editor._load_job.active and editor._load_job.phase=="validate","validation remains active across frames")
	await call_tool("undo",{},false)
	await call_tool("save_world",{},false)
	await call_tool("open_world",{"path":initial},false)
	var blocked:=await call_tool("set_object_transform",{"id":"obj_1","position":[0,1,0]},false)
	check("正在读取或保存" in blocked.get("error",""),"otherwise valid edit is rejected by the active-load guard")
	var state:=await call_tool("editor_state")
	check(state.load.active,"read-only HTTP state remains available while validating")
	while editor._load_job.active:await process_frame
	check(not editor._load_job.result.ok and editor._doc==doc and Pose.same(before,doc.recovery_snapshot()) and doc._undo.size()==history,"failed sliced validation preserves old document and history")
	check(editor._selection_tools.ids==["obj_1"] and editor._material_tool.selected==selected and not root.gui_disable_input,"failed validation preserves selections and unlocks UI")
	var valid:=data(120);var path:=directory.path_join("valid.gltf");FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(valid))
	job=await call_tool("open_world",{"path":path,"background":true})
	var old:RefCounted=doc;var replacements:=0;var validate_frames:=0
	while editor._load_job.active:
		if editor._doc!=old:replacements+=1;old=editor._doc
		if editor._load_job.phase=="validate":validate_frames+=1
		await process_frame
	if editor._doc!=old:replacements+=1
	check(editor._load_job.result.ok and replacements==1 and validate_frames>2,"successful sliced load publishes exactly one new document")
	var sync=Doc.open_file(path)
	check(sync!=null and Pose.same(sync.records,editor._doc.records) and Pose.same(sync.map_meta,editor._doc.map_meta),"HTTP async open equals synchronous document open")
	check(editor._material_tool.selected.is_empty() and editor._load_job.result.timings.validation.common_records==120,"success clears material selection and validates each root record once")
	editor._load_job._validation_budget_us=8000
	await call_tool("save_world")
	var saved:Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":path})
	check(Pose.same(saved,editor._doc.records),"shared HTTP save and default reopen retain every record")
	print("EDITOR_SLICED_LOAD_FINISHED ",failed," ",editor._load_job.result.timings)
	editor.queue_free();await settle();Io._remove_tree(directory);quit(0 if failed==0 else 1)
