extends "res://tools/test_world3d_mcp.gd"
const Current=preload("res://scripts/world_editor/terrain_tools.gd")
const Old=preload("res://review_artifacts/terrain_incremental_20261017/terrain_tools_baseline.gd")
const N=preload("res://scripts/world3d/terrain_neighbors.gd")
const ON=preload("res://review_artifacts/terrain_incremental_20261017/terrain_neighbors_baseline.gd")
const P=preload("res://scripts/world_editor/terrain_local_publish.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Incremental=preload("res://scripts/world_editor/terrain_mesh_incremental.gd")
var cpu_only_ab:=false
var measured_sources:Dictionary={}
var Output="D:/code/rmmo_runtime/review_artifacts/terrain_incremental_20261017/"
var initial:Dictionary
var expected:PackedByteArray
var rows:Array=[]
func ready()->Dictionary:
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		if editor._ground_batches.stats().pending_groups==0:
			await physics_frame;await physics_frame;await RenderingServer.frame_post_draw
			if editor._ground_batches.stats().pending_groups==0:return editor._ground_batches.stats()
		await process_frame
	check(false,"derived queue timed out");return {}
func event(at:Vector3,kind:String)->InputEvent:
	var screen:Vector2=editor._camera.unproject_position(at)+editor._canvas.global_position
	if kind=="motion":
		var value:=InputEventMouseMotion.new();value.position=screen;value.button_mask=MOUSE_BUTTON_MASK_LEFT;return value
	var value:=InputEventMouseButton.new();value.position=screen;value.button_index=MOUSE_BUTTON_LEFT;value.pressed=kind=="down";return value
func sample(version:String,label:String)->void:
	P.enabled=cpu_only_ab or version=="new"
	Incremental.enabled=version=="new"
	editor._terrain=Current.new() if P.enabled else Old.new();editor._terrain.editor=editor
	editor._doc.terrain_neighbors=N.new() if P.enabled else ON.new()
	editor._doc.apply_recovery(initial);editor._rebuild();await ready()
	var count:int=editor._doc._undo.size()
	check(editor._terrain_brush.begin("t0",{"mode":"raise","radius":2.,"strength":.1,"hardness":.25}).ok,"UI begins "+label)
	await settle();await physics_frame
	var inputs:Array=[event(Vector3(3,0,3),"down"),event(Vector3(5,0,3),"motion"),event(Vector3(7,0,3),"motion"),event(Vector3(7,0,3),"up")]
	var costs:Array=[];var jobs:Array=[];var started:=Time.get_ticks_usec()
	for input:InputEvent in inputs:
		var mark:=Time.get_ticks_usec();editor._terrain_brush.input(input);costs.append((Time.get_ticks_usec()-mark)/1000.)
		jobs.append(editor._view.get_node("t0").get_meta("terrain_local_stats",{}).duplicate(true) if P.enabled else {})
	var callbacks:float=(Time.get_ticks_usec()-started)/1000.
	var batches:Dictionary=await ready();var ready_ms:float=(Time.get_ticks_usec()-started)/1000.
	editor._terrain_brush.cancel()
	var author:=var_to_bytes(editor._doc.records)
	if expected.is_empty():expected=author
	check(author==expected,"same authored bytes "+label)
	check(editor._doc._undo.size()==count+1,"single UI transaction "+label)
	var record:={"version":version,"label":label,"callbacks_ms":callbacks,"callbacks":costs,"ready_ms":ready_ms,"local_work":jobs,"batches":batches}
	rows.append(record)
	FileAccess.open(Output+"ui_progress.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	print("TERRAIN_UI_SAMPLE ",JSON.stringify(record))
func run()->void:
	for path:String in ["scripts/world_editor/terrain_mesh_incremental.gd","scripts/world_editor/terrain_local_publish.gd","scripts/world_editor/terrain_tools.gd","scripts/world3d/terrain_neighbors.gd","scripts/world3d/terrain_surface.gd","scripts/world3d/surface_materials.gd"]:
		measured_sources[path]=FileAccess.get_sha256("res://"+path)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):Output=arg.trim_prefix("--evidence-dir=").trim_suffix("/")+"/"
		if arg=="--cpu-only-ab":cpu_only_ab=true
	DirAccess.make_dir_recursive_absolute(Output)
	create_timer(600).timeout.connect(func():quit(2));root.size=Vector2i(1280,900);root.content_scale_size=root.size;Engine.max_fps=60
	var dir:=Paths.cache_directory("terrain_incremental_ui_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(dir)
	var path:=dir.path_join("map.gltf");var doc:=Doc.new()
	for i in 4:
		var r:=preload("res://tools/test_terrain_incremental.gd").fixture();r.uuid="t%d"%i;r.position=[(i%2)*64,0,(i/2)*64];doc.records.append(r)
	check(doc.save(path)==OK,"temporary 4-tile native map")
	preload("res://scripts/net/net.gd").session().world3d_editor_path=path
	preload("res://scripts/net/net.gd").session().world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=dir.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._safety.enabled=false
	var probe:=TCPServer.new();port=32340
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"temporary loopback MCP")
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":32})
	initial=editor._doc.recovery_snapshot()
	for version in ["old","new"]:await sample(version,"warmup_"+version)
	for i in 3:
		await sample("old","AA_%d_a"%i);await sample("old","AA_%d_b"%i)
	for i in 8:
		for version in (["old","new"] if i%2==0 else ["new","old"]):await sample(version,"AB_%d_"%i+version)
	await sample("new","contract_setup")
	# Reuse the final live published geometry, including its material face cache.
	var r:Dictionary=editor._doc._find("t0");var node:MeshInstance3D=editor._view.get_node("t0")
	Paint.geometry(node);var before:Array=editor._doc.records.duplicate(true)
	await call_tool("sculpt_terrain",{"id":"t0","mode":"raise","points":[[8,3]],"radius":2.,"strength":.1})
	node=editor._view.get_node("t0")
	check(not node.has_meta("paint_geometry"),"local publish invalidates face-paint cache")
	var actual:Dictionary=Paint.geometry(node);var reference:MeshInstance3D=editor._doc._mesh(editor._doc._find("t0"))
	check(actual==Paint.geometry(reference),"material face IDs and geometry match full rebuild");reference.free()
	await call_tool("undo");check(editor._doc.records==before,"HTTP undo after local publications")
	await call_tool("redo");await ready();await call_tool("save_world")
	var saved:Array=editor._doc.records.duplicate(true);await call_tool("open_world",{"path":path});await ready()
	check(equivalent(saved,editor._doc.records),"HTTP local publication save reopen")
	var report:={"failures":failed,"samples":rows,"method":"Four 64x64 terrain tiles. Same real UI brush input handler, 3 dabs plus release. Warm caches; warmup, 3 A/A pairs, 8 alternating A/B pairs. Full author bytes compared. Callback-to-ready includes batch queue empty, two physics frames and drawn frame. Baseline frozen prepare/neighbors plus full publication; both use current canonical CPU array retention and current pick broadphase. Regression threshold 10% for ready median, report A/A range; no GPU-time or cold/tail claim."}
	if cpu_only_ab:report.method="Same current terrain tools, neighbor index, local GPU/collision publication and real UI input in both arms; only CPU interior meshing toggled. Four 64x64 tiles, 3 dabs plus release. Warmup, 3 A/A pairs and 8 alternating A/B pairs. Complete author bytes, transaction, HTTP undo/redo/save/reopen and face IDs compared. Ready includes queue empty, two physics frames and drawn frame. No cold/tail or GPU-time claim."
	report.sources=measured_sources
	FileAccess.open(Output+"ui.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("TERRAIN_UI_FINISHED failures=",failed)
	editor._mcp.stop();editor.queue_free();await settle();quit(1 if failed else 0)
