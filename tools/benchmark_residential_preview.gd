extends "res://tools/test_world3d_mcp.gd"
## Private-desktop benchmark of the real editor service. No fixture is saved.
## --manifest=... --report=... --grid=32|64 --samples=3 --preview-only --quick
const City=preload("res://scripts/world3d/city_layout.gd")
const Net=preload("res://scripts/net/net.gd")
var manifest_path:="res://review_artifacts/editor_reliability/http_kerbs.json"
var report_path:=""
var directory:=""
var grid:=64
var prepare_samples:=3
var preview_only:=false
var quick:=false
var checks:Array=[]
var report:Dictionary={"version":1,"samples":[]}
var input_manifest:Dictionary={}
var source_map_sha:=""
var source_prefab_sha:=""
var input_state_sha:=""
var expected_geometry:=""
var last_plan_token:=""

func check(ok:bool,label_:String)->void:
	checks.append({"ok":ok,"label":label_});super.check(ok,label_)

func hash_value(value:Variant)->String:
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value));return hashing.finish().hex_encode()

func semantic(value:Variant)->Variant:
	if value is int or value is float:return float(value)
	if value is Array:return value.map(semantic)
	if value is Dictionary:
		var out:Dictionary={};var keys:Array=value.keys();keys.sort()
		for key in keys:
			if str(key).ends_with("_id") or str(key).ends_with("_ids") or key in ["input_version","base_version","plan_token","source_sha256","search","counts"]:continue
			out[key]=semantic(value[key])
		return out
	return value

func geometry_token(result:Dictionary)->String:
	var geometry:Dictionary={}
	for field:String in ["position","adjustment","road_points","setback","width","bounds","support","access","checks"]:geometry[field]=result.get(field)
	return hash_value(semantic(geometry))

func authored_state()->String:
	return hash_value([editor._doc.recovery_snapshot(),editor._doc._undo,editor._doc._redo,editor._doc.editor_dirty,editor._selection_tools.ids])

func choose(menu:OptionButton,id:String)->bool:
	for index in menu.item_count:
		if str(menu.get_item_metadata(index))==id:menu.select(index);return true
	return false

func work_counts(value:Variant,path:String="")->Dictionary:
	var found:Dictionary={}
	if value is Dictionary:
		for key in value:
			var child:String=str(key) if path.is_empty() else path+"."+str(key)
			if key=="counts":found[child]=value[key].duplicate(true)
			elif value[key] is Dictionary:found.merge(work_counts(value[key],child))
	return found

func measured_preview(args:Dictionary,label_:String,expect_cached:bool,profiling_on:bool=true)->Dictionary:
	editor._residential.profile_enabled=profiling_on
	var before:=authored_state()
	var began:=Time.get_ticks_usec()
	var result:Dictionary=editor._residential.preview(args)
	var wall_ms:float=(Time.get_ticks_usec()-began)/1000.
	var profile:Dictionary=editor._residential.last_profile.duplicate(true)
	var attributed:=0.0
	for value in profile.get("stages_ms",{}).values():attributed+=float(value)
	var token:=geometry_token(result) if result.get("ok",false) else ""
	var observed_cached:bool=result.get("ok",false) and str(result.get("plan_token",""))==last_plan_token
	var counts:Dictionary=work_counts(result)
	var sample:Dictionary={"label":label_,"profiling_on":profiling_on,"wall_ms":wall_ms,"profile":profile,"stage_sum_ms":attributed,"unattributed_ms":maxf(0.,wall_ms-attributed),"outcome":"ok" if result.get("ok",false) else str(result.get("code","error")),"cached":observed_cached,"attempts":0 if observed_cached else result.get("search",{}).get("attempts",0),"full_graph_checks":0 if observed_cached else result.get("search",{}).get("full_graph_checks",0),"candidate_search":result.get("search",{}).duplicate(true),"work_counts":{} if observed_cached else counts,"candidate_work_counts":counts,"geometry_sha256":token,"source_sha256":result.get("source_sha256",""),"input_state_sha256":input_state_sha,"fixture_map_sha256":source_map_sha}
	report.samples.append(sample)
	print("RESIDENTIAL_PREVIEW_SAMPLE ",JSON.stringify(sample))
	check(result.get("ok",false),label_+" succeeds")
	check(observed_cached==expect_cached and (not profiling_on or bool(profile.get("cached",false))==expect_cached),label_+" uses the expected candidate-cache path")
	check(before==authored_state(),label_+" leaves document, history and selection unchanged")
	if result.get("ok",false):
		if expected_geometry.is_empty():expected_geometry=token
		check(token==expected_geometry,label_+" preserves exact normalized geometry summary")
		last_plan_token=str(result.plan_token)
	else:report.last_failure=result
	return result

func render_frame()->void:
	if DisplayServer.get_name()=="headless":await process_frame
	else:await RenderingServer.frame_post_draw

func wait_editor_ready(ids:Array=[],timeout_ms:int=60000)->Dictionary:
	var began:=Time.get_ticks_usec();var deadline:=Time.get_ticks_msec()+timeout_ms
	while Time.get_ticks_msec()<deadline:
		var stats:Dictionary=editor._ground_batches.stats()
		var members_ready:bool=ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(id)) and not editor._bodies_by_uuid.get(id,[]).is_empty())
		if int(stats.get("pending_groups",0))==0 and members_ready:
			# A later physics publication frame, then one rendered frame. This is
			# editor publication readiness, not a real-character traversal proof.
			await physics_frame;await physics_frame;await render_frame()
			if int(editor._ground_batches.stats().get("pending_groups",0))==0:return {"ok":true,"wait_ms":(Time.get_ticks_usec()-began)/1000.,"batch_stats":editor._ground_batches.stats(),"physics_frame":Engine.get_physics_frames(),"draw_frame":Engine.get_frames_drawn()}
		await process_frame
	return {"ok":false,"wait_ms":(Time.get_ticks_usec()-began)/1000.,"batch_stats":editor._ground_batches.stats()}

func finish()->void:
	if not input_manifest.is_empty():
		check(FileAccess.get_sha256(input_manifest.fixture)==source_map_sha,"benchmark does not write the successful source fixture")
		check(FileAccess.get_sha256(input_manifest.source_path)==source_prefab_sha,"benchmark does not write the frozen source asset")
	report.failures=failed;report.checks=checks;report.statistics=sample_statistics()
	if report_path.is_empty():report_path=directory.path_join("preview_benchmark.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	if is_instance_valid(editor):editor.queue_free();await settle()
	Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path=""
	print("RESIDENTIAL_PREVIEW_BENCHMARK ",report_path," failures=",failed)
	quit(1 if failed else 0)

func sample_statistics()->Dictionary:
	var groups:Dictionary={"first_prepare":[],"warm_profiled_prepare":[],"warm_unprofiled_prepare":[],"cache_hit":[]}
	for sample:Dictionary in report.samples:
		if sample.outcome!="ok":continue
		var group:String="cache_hit" if sample.cached else ("first_prepare" if sample.label=="first_prepare_in_editor" else ("warm_profiled_prepare" if sample.profiling_on else "warm_unprofiled_prepare"))
		groups[group].append(sample.wall_ms)
	var summary:Dictionary={}
	for group:String in groups:
		var raw:Array=groups[group];var ordered:Array=raw.duplicate();ordered.sort()
		var median:Variant=null
		if not ordered.is_empty():median=ordered[ordered.size()/2] if ordered.size()%2==1 else (float(ordered[ordered.size()/2-1])+float(ordered[ordered.size()/2]))*.5
		summary[group]={"n":raw.size(),"raw_wall_ms":raw,"median_wall_ms":median}
	return {"groups":summary,"method":"ordered fixed-input samples; raw values and median only, no percentile or statistical significance claim; ON/OFF pairs estimate possible probe cost but also include run-order variation"}

func run()->void:
	create_timer(600).timeout.connect(func():push_error("Residential preview benchmark timeout");quit(2))
	Engine.max_fps=60;root.size=Vector2i(1280,900);root.content_scale_size=root.size
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):manifest_path=argument.trim_prefix("--manifest=")
		elif argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		elif argument.begins_with("--grid="):grid=int(argument.trim_prefix("--grid="))
		elif argument.begins_with("--samples="):prepare_samples=int(argument.trim_prefix("--samples="))
		elif argument=="--preview-only":preview_only=true
		elif argument=="--quick":quick=true
	directory=Paths.external_root().path_join("__residential_preview_benchmark_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	check(grid in [32,64] and prepare_samples>=3 and prepare_samples<=8,"bounded benchmark configuration (32 or 64 cells per terrain axis)")
	check(FileAccess.file_exists(manifest_path),"explicit successful HTTP fixture manifest exists")
	if failed:await finish();return
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check(parsed is Dictionary and int(parsed.get("failures",1))==0 and parsed.get("kerbs_mode",false),"input is a successful real-kerb HTTP fixture")
	if failed:await finish();return
	input_manifest=parsed
	check(str(input_manifest.directory).get_file().begins_with("__residential_placement_") and Paths.allowed(input_manifest.fixture) and str(input_manifest.fixture).begins_with(str(input_manifest.directory)+"/"),"input belongs to the disposable test pack")
	source_map_sha=FileAccess.get_sha256(input_manifest.fixture);source_prefab_sha=FileAccess.get_sha256(input_manifest.source_path)
	check(source_map_sha==input_manifest.map_sha256 and source_prefab_sha==input_manifest.plan.source_sha256,"exact source map and frozen asset revisions match the passing fixture")
	if failed:await finish();return
	var setup_started:=Time.get_ticks_usec()
	var doc:RefCounted=Doc.open_file(input_manifest.fixture)
	check(doc!=null,"native fixture opens for an in-memory baseline")
	if failed:await finish();return
	var settings:Dictionary=City.resolve(doc.map_meta).road_surface.settings.duplicate(true)
	doc.records=doc.records.filter(func(record):return not input_manifest.house_ids.has(record.uuid) and not record.has("road_source"))
	doc.map_meta.building_instances.erase(input_manifest.house_id)
	var city:Dictionary=City.resolve(doc.map_meta)
	var nodes:Array=city.roads.nodes.filter(func(node):return node.id in ["main_a","main_b","far_a","far_b"])
	var far_edges:Array=city.roads.edges.filter(func(edge):return edge.id=="untouched_lane")
	check(nodes.size()==4 and far_edges.size()==1 and input_manifest.request.road_edge_id=="main_lane","known fixed fixture skeleton is available")
	if failed:await finish();return
	city.roads={"nodes":nodes,"edges":[{"id":"main_lane","from":"main_a","to":"main_b","width_start":3.5,"width_end":3.5,"kind":"ground"},far_edges[0]]}
	city.erase("road_surface");doc.map_meta.editor_layout=city
	for record:Dictionary in doc.records:
		if record.uuid!="residential_ground":continue
		check(record.terrain_mesh.heights.all(func(v):return float(v)==0.) and record.terrain_mesh.holes.all(func(v):return not v),"grid variant preserves the same flat solid terrain")
		record.terrain_mesh.columns=grid;record.terrain_mesh.rows=grid
		record.terrain_mesh.heights.resize((grid+1)*(grid+1));record.terrain_mesh.heights.fill(0.)
		record.terrain_mesh.holes.resize(grid*grid);record.terrain_mesh.holes.fill(false)
	if failed:await finish();return
	doc._undo.clear();doc._redo.clear()
	Net.session().world3d_editor_path=input_manifest.fixture;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts")
	# Material lookup is read-only. Preserve any fixture-local fallback library.
	editor._material_directory=str(input_manifest.directory).path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._material_tool.library.include_shared=true
	var generated:Dictionary=editor._roads.generate(settings)
	check(generated.get("ok",false),"baseline roads are rebuilt by the native full-graph service")
	if not generated.get("ok",false):report.last_failure=generated;await finish();return
	var ready:Dictionary=await wait_editor_ready()
	check(ready.ok,"baseline derived editor geometry is ready before timing")
	if failed:await finish();return
	editor._residential.profile_enabled=true
	input_state_sha=hash_value(semantic([editor._doc.records,editor._doc.map_meta]))
	var scripts:Dictionary={}
	for path:String in ["res://tools/benchmark_residential_preview.gd","res://scripts/world_editor/residential_placement_tools.gd","res://scripts/world_editor/residential_placement_panel.gd","res://scripts/world_editor/residential_support.gd","res://scripts/world_editor/residential_access.gd","res://scripts/world_editor/road_tools.gd","res://scripts/world3d/road_plan.gd","res://scripts/world3d/road_terrain_fit.gd"]:scripts[path]=FileAccess.get_sha256(path)
	var executable:String=OS.get_executable_path()
	report.merge({"manifest":manifest_path,"fixture":input_manifest.fixture,"fixture_map_sha256":source_map_sha,"source_sha256":source_prefab_sha,"input_state_sha256":input_state_sha,"grid":grid,"terrain_cells":grid*grid,"records":editor._doc.records.size(),"road_settings":settings,"setup_ms":(Time.get_ticks_usec()-setup_started)/1000.,"graphical":DisplayServer.get_name()!="headless","viewport":[1280,900],"engine":Engine.get_version_info(),"engine_executable":executable,"engine_executable_sha256":FileAccess.get_sha256(executable),"script_sha256":scripts,"method":{"service":"direct call to the actual WorldEditor shared service; includes argument/identity/SHA/version checks, candidate preparation and return","cold_label":"first residential preparation in this editor; document, native roads, engine and OS caches may already be warm","cache":"cache hit wall time is measured separately; candidate_search and candidate_work_counts are historical, not work performed by the cache hit","geometry":"SHA256 of exact float-normalized summary, sorted keys; excludes IDs, tokens, timings and counts; work counts are recorded separately","profiling":"first plus two warm ON preparations, then two warm OFF preparations; disabled probes have empty profile and the full wall is unattributed","scope":"fixed 40m terrain plus distant-road sentinel; no town benchmark, network latency or RSS/VRAM claim"}},true)
	var args:Dictionary=input_manifest.request.duplicate(true)
	var result:Dictionary={}
	for index in (1 if quick else prepare_samples):
		if not result.is_empty():editor._residential.discard(result.plan_token)
		result=measured_preview(args,"first_prepare_in_editor" if index==0 else "prepare_after_discard_%d"%index,false)
		if not result.get("ok",false):await finish();return
	if quick:await finish();return
	var cached:=measured_preview(args,"candidate_cache_hit",true)
	check(cached.get("plan_token","")==result.plan_token,"cache hit reuses the exact candidate authority")
	for index in 2:
		editor._residential.discard(result.plan_token)
		result=measured_preview(args,"unprofiled_prepare_after_discard_%d"%(index+1),false,false)
		if not result.get("ok",false):await finish();return
	if failed or preview_only:await finish();return
	editor._residential.profile_enabled=true
	await measure_ui_and_apply(args,result)
	await finish()

func measure_ui_and_apply(args:Dictionary,result:Dictionary)->void:
	var panel=editor._building_panel.residential
	panel.refresh_catalogs()
	check(choose(panel.asset_choice,args.asset_id) and choose(panel.road_choice,args.road_edge_id),"real UI selects the benchmark source and road")
	var values:Dictionary=args.duplicate(true);values.erase("asset_id");values.erase("road_edge_id");panel.form.update_values(values)
	check(equivalent(panel.request(),args),"UI benchmark uses identical service inputs")
	if failed:return
	var started:=Time.get_ticks_usec()
	var records:Array=editor._residential.preview_visual(result.plan_token)
	var extraction_ms:float=(Time.get_ticks_usec()-started)/1000.
	started=Time.get_ticks_usec();panel.show_visual(records)
	var construction_ms:float=(Time.get_ticks_usec()-started)/1000.
	var render_started:=Time.get_ticks_usec();await render_frame()
	var first_render_ms:float=(Time.get_ticks_usec()-render_started)/1000.
	check(is_instance_valid(panel.ghost),"first preview display constructs real ghost geometry")
	# show_visual alone owns no candidate token, so this removes only the ghost.
	panel.discard_preview()
	started=Time.get_ticks_usec();panel.preview_button.pressed.emit()
	var callback_ms:float=(Time.get_ticks_usec()-started)/1000.
	var ui_profile:Dictionary=editor._residential.last_profile.duplicate(true)
	render_started=Time.get_ticks_usec();await render_frame()
	var callback_render_ms:float=(Time.get_ticks_usec()-render_started)/1000.
	check(panel.last_result.get("ok",false) and geometry_token(panel.last_result)==expected_geometry and ui_profile.get("cached",false),"actual UI button reuses the cached equivalent candidate")
	report.ui={"records":records.size(),"preview_visual_copy_ms":extraction_ms,"first_show_visual_cpu_ms":construction_ms,"first_show_render_wait_ms":first_render_ms,"warm_cached_button_callback_ms":callback_ms,"warm_button_render_wait_ms":callback_render_ms,"button_service_profile":ui_profile,"method":"separate payload copy and first ghost construction; full UI button callback is then measured warm and includes its cached service call; render waits are measured after CPU return"}
	var before_undo:int=editor._doc._undo.size()
	started=Time.get_ticks_usec();panel.apply_button.pressed.emit()
	var apply_ms:float=(Time.get_ticks_usec()-started)/1000.
	check(panel.last_result.get("ok",false) and editor._doc._undo.size()==before_undo+1,"UI applies the complete candidate in one native undo transaction")
	if failed:return
	var ready:Dictionary=await wait_editor_ready(result.house_ids)
	check(ready.ok,"applied house reaches editor member picking-body, batch and later-frame readiness")
	report.apply={"callback_wall_ms":apply_ms,"publication_wait_ms":ready.wait_ms,"callback_to_ready_ms":apply_ms+ready.wait_ms,"ready":ready,"method":"actual UI apply callback plus separate wait for all house editor nodes/picking bodies, pending batch count zero, two physics frames and a rendered frame; picking bodies include collision:none decorations and are not gameplay collision proof or real-character traversal"}
