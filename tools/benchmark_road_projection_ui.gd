extends "res://tools/test_road_prepare_district_http.gd"
## Real UI callbacks and publication, on a disposable 64-cell terrain map.
## Run only with tools/run_godot_background.py on Windows.
const Fixture=preload("res://tools/road_prepare_fixture.gd")
const Baseline=preload("res://review_artifacts/road_projection_20261017/road_tools_ref.gd")
const Current=preload("res://scripts/world_editor/road_tools.gd")
const Evidence="D:/code/rmmo_runtime/review_artifacts/road_projection_20261017/"
var expected_document:PackedByteArray
var initial_document:PackedByteArray

func author_bytes()->PackedByteArray:
	return var_to_bytes([editor._doc.records,editor._doc.map_meta])

func ready()->Dictionary:
	var start:=Time.get_ticks_usec();var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		var records:Array=editor._doc.records.filter(func(r):return r.has("road_mesh"))
		var members:bool=records.all(func(r):return is_instance_valid(editor._view.get_node_or_null(r.uuid)) and not editor._bodies_by_uuid.get(r.uuid,[]).is_empty())
		if members and int(editor._ground_batches.stats().get("pending_groups",0))==0:
			await physics_frame;await physics_frame;await RenderingServer.frame_post_draw
			if int(editor._ground_batches.stats().get("pending_groups",0))==0:
				return {"ok":true,"wait_ms":(Time.get_ticks_usec()-start)/1000.,"batch_stats":editor._ground_batches.stats(),"draw_frame":Engine.get_frames_drawn(),"physics_frame":Engine.get_physics_frames()}
		await process_frame
	return {"ok":false,"wait_ms":(Time.get_ticks_usec()-start)/1000.,"batch_stats":editor._ground_batches.stats()}

func use_version(version:String)->void:
	editor._roads.editor=null
	editor._roads=Baseline.new() if version=="baseline" else Current.new()
	editor._roads.editor=editor

func sample(version:String,label_:String,profile:bool=false)->Dictionary:
	use_version(version);editor._roads.profile_enabled=profile
	check(author_bytes()==initial_document,label_+" exact initial authored state")
	var ui:VBoxContainer=editor._city.panel.road_surface_panel
	var params:Dictionary=RoadPlan.defaults().merged({"follow_terrain":true,"kerb_enabled":true,"material_id":pavement_material,"kerb_material_id":kerb_material_id},true)
	var form_values:=params.duplicate(true);form_values.erase("material_id");form_values.erase("kerb_material_id")
	check(ui.settings.update_values(form_values),label_+" all form fields accepted")
	MaterialChoice.choose(ui.material_select,pavement_material);MaterialChoice.choose(ui.kerb_material_select,kerb_material_id)
	check(Current._same(ui.args(),params),label_+" actual UI request exactly matches intended terrain and kerb settings")
	var before:=snapshot();var undos:int=editor._doc._undo.size()
	var start:=Time.get_ticks_usec();var pressed:=press("预览铺面变化")
	var preview_ms:float=(Time.get_ticks_usec()-start)/1000.
	var preview_profile:Dictionary=editor._roads.last_profile.duplicate(true)
	check(pressed and not ui.token.is_empty(),label_+" real preview button succeeds")
	same_snapshot(before,label_+" preview is read only")
	start=Time.get_ticks_usec();await RenderingServer.frame_post_draw
	var preview_draw_wait:float=(Time.get_ticks_usec()-start)/1000.
	start=Time.get_ticks_usec();pressed=press("应用铺面方案")
	var apply_ms:float=(Time.get_ticks_usec()-start)/1000.
	var apply_profile:Dictionary=editor._roads.last_profile.duplicate(true)
	# No assertion, serialization or hashing is inside callback-to-ready timing.
	var publication:Dictionary=await ready()
	var apply_to_ready_ms:float=(Time.get_ticks_usec()-start)/1000.
	var bytes:=author_bytes()
	if expected_document.is_empty():expected_document=bytes
	check(pressed and ui.token.is_empty() and editor._doc._undo.size()==undos+1,label_+" real apply creates one transaction")
	check(publication.ok,label_+" editor nodes picking bodies batches and later render ready")
	check(bytes==expected_document,label_+" complete committed author bytes equal")
	var value:={"version":version,"label":label_,"request":ui.args(),"profile_enabled":profile,"preview_callback_ms":preview_ms,"preview_draw_wait_ms":preview_draw_wait,"apply_callback_ms":apply_ms,"publication":publication,"apply_to_ready_ms":apply_to_ready_ms,"preview_profile":preview_profile,"apply_profile":apply_profile,"author_sha256":digest([editor._doc.records,editor._doc.map_meta])}
	report.get_or_add("samples",[]).append(value)
	print("ROAD_PROJECTION_UI_SAMPLE ",JSON.stringify(value))
	await call_tool("undo")
	check(author_bytes()==initial_document,label_+" native undo restores exact fixture")
	var restored:=await ready();check(restored.ok,label_+" undo publication ready before next sample")
	return value

func run()->void:
	create_timer(600).timeout.connect(func():print("ROAD_PROJECTION_UI_TIMEOUT");quit(2))
	report_path=Evidence+"ui_final.json";rpc_timeout_ms=120000
	check(DisplayServer.get_name()!="headless","real renderer required")
	if failed:await finish();return
	Engine.max_fps=60;root.size=Vector2i(1280,900);root.content_scale_size=root.size
	directory=Paths.external_root().path_join("__projection_ui_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata:=FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE);metadata.store_string(JSON.stringify({"id":"projection_ui_%d"%OS.get_process_id(),"name":"Disposable road projection test"}));metadata.close()
	map_path=directory.path_join("maps/test/map.gltf")
	var fixture:=Fixture.local_terrain();var doc:=Doc.new();doc.records=fixture.records;doc.map_meta.editor_layout=fixture.layout
	check(doc.save(map_path)==OK,"isolated native fixture saved")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._safety.enabled=false
	var probe:=TCPServer.new();port=32020
	while port<32120 and probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(port<32120 and editor.start_mcp(port).ok,"private HTTP MCP loopback available")
	var defs:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	check(defs.any(func(t):return t.name=="preview_road_surface" and t.annotations.readOnlyHint and t.inputSchema.properties.has("follow_terrain")) and defs.any(func(t):return t.name=="generate_road_surface") and not defs.any(func(t):return t.name=="paint_tile"),"current 3D discovery and terrain-follow schema")
	pavement_material=await material_id("pack:default:paving/historic_cobble/material","pavement",Color(.4,.4,.4))
	kerb_material_id=await material_id("pack:default:paving/automatic_limestone_kerb/material","kerb",Color(.7,.7,.65))
	var baseline_ready:=await ready();check(baseline_ready.ok,"initial terrain derived state ready")
	initial_document=author_bytes()
	var hashes:Dictionary={}
	for path:String in ["res://tools/benchmark_road_projection_ui.gd","res://scripts/world3d/terrain_projection.gd","res://scripts/world_editor/road_tools.gd","res://scripts/world_editor/road_panel.gd","res://scripts/world_editor/mcp_schema.gd","res://scripts/world_editor/mcp_ops.gd"]:hashes[path]=FileAccess.get_sha256(path)
	report.method={"scope":"Real UI text preview callback and later rendered frame; actual apply callback to all road editor nodes/picking bodies, pending groups zero, two physics frames and rendered frame. No ghost mesh in this panel; not gameplay traversal, photon latency or GPU duration.","order":"One warmup per version, three A/A pairs, six alternating A/B pairs, final ON diagnostic per version. Native undo and derived settling between every observation. No cache reset, no cold claim; real PBR inputs identical.","criterion":"CPU prepare primary; UI callback-to-ready regression tolerance 10% after considering A/A variation. Small sample medians/raw values only; no tail or significance claim.","environment":"Private Windows desktop, other user/session load unmanaged, 1280x900, max_fps 60"}
	report.script_sha256=hashes;report.materials=[pavement_material,kerb_material_id];report.engine_executable_sha256=FileAccess.get_sha256(OS.get_executable_path())
	for version:String in ["baseline","current"]:await sample(version,"warmup_"+version)
	for i in 3:
		await sample("baseline","AA_%d_first"%i);await sample("baseline","AA_%d_second"%i)
	for i in 6:
		for version:String in (["baseline","current"] if i%2==0 else ["current","baseline"]):await sample(version,"AB_%d_"%i+version)
	for version:String in ["baseline","current"]:await sample(version,"ON_"+version,true)
	use_version("current")
	var params:Dictionary=RoadPlan.defaults().merged({"follow_terrain":true,"kerb_enabled":true,"material_id":pavement_material,"kerb_material_id":kerb_material_id},true)
	var before:=snapshot();var preview:=await call_tool("preview_road_surface",params);same_snapshot(before,"HTTP preview leaves author and undo state intact")
	await atomic_reject("generate_road_surface",params.merged({"plan_token":"stale"},true))
	await call_tool("generate_road_surface",params.merged({"plan_token":preview.plan_token},true))
	var http_bytes:=author_bytes()
	check(Current._same(bytes_to_var(http_bytes),bytes_to_var(expected_document)),"real HTTP and UI all fields exactly equal allowing only JSON numeric types and key order")
	for entry:Array in [["ui_authored.bin",expected_document],["http_authored.bin",http_bytes]]:
		var file:=FileAccess.open(Evidence+entry[0],FileAccess.WRITE);file.store_buffer(entry[1]);file.close()
	await call_tool("undo");check(author_bytes()==initial_document,"HTTP undo restores original")
	await call_tool("redo");check(author_bytes()==http_bytes,"HTTP redo restores exact road record and metadata bytes")
	await wait_batches();await call_tool("save_world")
	var saved:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"native save reopen preserves terrain road kerb material and IDs")
	await finish()
