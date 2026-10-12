extends SceneTree
## Isolated native-resource preparation experiment, not a game-entry benchmark.
## Run with profile_load_hardware.py on the private GPU desktop, one process/run.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Hashes=preload("res://scripts/world3d/model_source_hashes.gd")
const Estimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const EXPECTED_MODELS:=31
const SPAWN:=Vector3(321.2,.9,160.3)
var input:="D:/code/rmmo_runtime/review_artifacts/problem_chunk_basis_after_warm_20261009.json"
var output:="D:/code/rmmo_runtime/review_artifacts/problem_chunk_assets_w2.json"
var selection_report:=""
var selection_name:=""
var workers:=2
var byte_limit:=4*1024*1024*1024
var report:Dictionary={"failures":0,"checks":[],"phases":[],"scope":"Production ModelParsePreparation with default native cache/GLTF routes. Native load creates GPU resources but this experiment never instantiates a model or builds collisions/navigation. It does not measure a playable scene or first frame.","cache_condition":"Fresh Godot process; existing compiled products and OS file cache are retained. Full source verification before run warms source-file cache identically in every arm. No product is preloaded or rebuilt by the probe."}
var _preparation=Preparation.new()
var _hashes=Hashes.new()
var _deadline:=0
var _cancelled:=false
var _phase:="startup"
var _output_ok:=false

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->bool:
	report.checks.append({"ok":ok,"label":label})
	print("PASS " if ok else "FAIL ",label)
	if not ok:report.failures+=1
	return ok

func persist()->void:
	if not _output_ok:return
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func phase(value:String)->void:
	_phase=value;report.phases.append({"phase":value,"epoch_s":Time.get_unix_time_from_system(),"ticks_us":Time.get_ticks_usec()})
	persist();print("PROBLEM_ASSETS_PHASE ",value)

func launch(task:Callable)->Dictionary:
	var thread:=Thread.new();var error:=thread.start(task)
	if error!=OK:return {"error":error,"reason":"coordinator_thread_start_failed"}
	var frames:=0;var previous:=Time.get_ticks_usec();var maximum:=0
	while thread.is_alive():
		await process_frame
		frames+=1
		var now:=Time.get_ticks_usec();maximum=maxi(maximum,now-previous);previous=now
		if now>_deadline and not _cancelled:
			_cancelled=true;_preparation.cancel();_hashes.cancel()
	# Only a finished coordinator is joined on the main thread. Native workers
	# keep rendering uploads progressing while this loop yields scene frames.
	var result:Dictionary=thread.wait_to_finish()
	thread=null
	result.probe_scene_frames=frames;result.probe_max_scene_frame_us=maximum
	return result

func validate_input(content_root:String)->Dictionary:
	var started:=Time.get_ticks_usec()
	var file:=FileAccess.open(input,FileAccess.READ)
	if file==null or file.get_length()>64*1024*1024:return {"error":ERR_INVALID_DATA,"reason":"invalid_input_report"}
	var text:=file.get_as_text();file.close()
	var raw:Variant=JSON.parse_string(text)
	if not raw is Dictionary or raw.get("failures",-1)!=0 or not raw.get("map_profile") is Dictionary:
		return {"error":ERR_INVALID_DATA,"reason":"input_report_not_successful"}
	var spawn:Variant=raw.get("requested_spawn")
	if not spawn is Array or spawn.size()!=3:return {"error":ERR_INVALID_DATA,"reason":"problem_spawn_missing"}
	for value:Variant in spawn:
		if not value is float and not value is int:return {"error":ERR_INVALID_DATA,"reason":"spawn_type"}
	var chunk:Variant=raw.get("requested_chunk")
	if not chunk is Array or chunk.size()!=2 or not (chunk[0] is int or chunk[0] is float) or not (chunk[1] is int or chunk[1] is float):
		return {"error":ERR_INVALID_DATA,"reason":"problem_chunk_missing"}
	if Vector3(spawn[0],spawn[1],spawn[2]).distance_to(SPAWN)>.001 or float(chunk[0])!=10. or float(chunk[1])!=5.:
		return {"error":ERR_INVALID_DATA,"reason":"wrong_problem_location"}
	var map_path:=str(raw.get("map",""));var map_sha:=str(raw.get("map_sha",""))
	if not Paths.allowed(map_path,content_root.path_join("cache/world3d")) or not FileAccess.file_exists(map_path):
		return {"error":ERR_INVALID_DATA,"reason":"temporary_checkpoint_required"}
	if not _sha(map_sha) or FileAccess.get_sha256(map_path)!=map_sha:return {"error":ERR_BUSY,"reason":"checkpoint_changed"}
	var profile:Dictionary=raw.map_profile
	var rows:Variant=profile.get("asset_parses");var expected:Variant=profile.get("source_hash_profile",{}).get("signatures")
	if not rows is Array or rows.size()!=EXPECTED_MODELS or not expected is Dictionary or expected.size()!=EXPECTED_MODELS:
		return {"error":ERR_INVALID_DATA,"reason":"expected_exactly_31_model_records"}
	var paths:Array=[];var seen:Dictionary={}
	for row:Variant in rows:
		if not row is Dictionary or not row.get("path") is String or row.get("error",-1)!=OK or not row.get("compiled",false):
			return {"error":ERR_INVALID_DATA,"reason":"invalid_historical_parse_row"}
		var path:String=row.path
		if seen.has(path) or not expected.has(path) or not _sha(expected[path]):return {"error":ERR_INVALID_DATA,"reason":"duplicate_or_unbound_source"}
		if not Paths.allowed(path,content_root) or not FileAccess.file_exists(path):return {"error":ERR_INVALID_PARAMETER,"reason":"model_missing_or_outside_root","path":path}
		seen[path]=true;paths.append(path)
	# This is a workload snapshot, not trusted identity: re-read all source
	# bytes through the production full-SHA helper before native preparation.
	var verified:Dictionary=_hashes.run(paths,content_root,4)
	if verified.error!=OK:return {"error":verified.error,"reason":"source_hash_failed","hash_profile":verified}
	if verified.signatures!=expected:return {"error":ERR_BUSY,"reason":"source_set_changed","hash_profile":verified}
	var selected:=select_workload(paths,verified.signatures,content_root,map_path,map_sha)
	if selected.error!=OK:return selected
	return {"error":OK,"paths":selected.paths,"signatures":selected.signatures,"selection":selected.selection,"baseline_model_count":paths.size(),"input_sha":text.sha256_text(),"map":map_path,"map_sha":map_sha,"spawn":spawn,"chunk":[10,5],"hash_profile":verified,"elapsed_us":Time.get_ticks_usec()-started}

func select_workload(baseline:Array,signatures:Dictionary,content_root:String,map_path:String,map_sha:String)->Dictionary:
	if selection_report.is_empty():return {"error":OK,"paths":baseline,"signatures":signatures,"selection":{"name":"baseline_31","model_count":baseline.size()}}
	var file:=FileAccess.open(selection_report,FileAccess.READ)
	if file==null or file.get_length()>64*1024*1024:return {"error":ERR_INVALID_DATA,"reason":"invalid_selection_report"}
	var text:=file.get_as_text();file.close()
	var raw:Variant=JSON.parse_string(text)
	if not raw is Dictionary or raw.get("ok")!=true or not raw.get("failures") is Array or not raw.failures.is_empty() or raw.get("source_unchanged")!=true or raw.get("index_unchanged")!=true or raw.get("map")!=map_path or raw.get("source_sha256")!=map_sha:
		return {"error":ERR_INVALID_DATA,"reason":"selection_report_identity_mismatch"}
	if not raw.get("queries") is Array:return {"error":ERR_INVALID_DATA,"reason":"selection_queries_missing"}
	var query:Dictionary={}
	for value:Variant in raw.queries:
		if not value is Dictionary:return {"error":ERR_INVALID_DATA,"reason":"invalid_selection_query"}
		if value.get("name")==selection_name:
			if not query.is_empty():return {"error":ERR_INVALID_DATA,"reason":"duplicate_selection_name"}
			query=value
	var expansion:=8. if selection_name=="cell_10_5_expanded_8m" else 0.
	var wanted:=[320.-expansion,160.-expansion,352.+expansion,192.+expansion]
	if query.is_empty() or not _json_equal(query.get("cell"),[10,5]) or not _json_equal(query.get("base_cell_xz"),[320,160,352,192]) or not _json_equal(query.get("clip_xz"),wanted) or query.get("safety_expansion_m")!=expansion or query.get("terrain_halo_m")!=8. or query.get("whole_building_groups")!=true or query.get("global_semantics_unchanged")!=true or query.get("is_neighbor_ring")!=false:
		return {"error":ERR_INVALID_DATA,"reason":"selection_geometry_mismatch"}
	# Recompute this report's subset from the current authenticated directory.
	# Report JSON is not a dependency proof; no arbitrary source path is accepted.
	var index:Dictionary=Index.read(map_path,content_root,map_sha)
	if not index.ok or raw.get("generator")!=Index.generator_key() or raw.get("index_path")!=Index.cache_path(map_path,content_root):
		return {"error":ERR_INVALID_DATA,"reason":"selection_index_changed"}
	var clip:=AABB(Vector3(wanted[0],-100000,wanted[1]),Vector3(wanted[2]-wanted[0],200000,wanted[3]-wanted[1]))
	var exact:Dictionary=Index.select(index,[clip])
	if not exact.ok or not _json_equal(exact.record_indices,query.get("record_indices")):
		return {"error":ERR_INVALID_DATA,"reason":"selection_records_changed"}
	var wanted_paths:Dictionary={};var uuids:Array=[]
	for order:int in exact.record_indices:
		var row:Dictionary=index.rows[order];uuids.append(row.uuid)
		if not str(row.asset_path).is_empty():wanted_paths[row.asset_path]=true
	var listed:Variant=query.get("breakdown",{}).get("unique_model_sources",{})
	if not listed is Dictionary or not listed.get("paths") is Array or not listed.get("files") is Array or not listed.get("missing") is Array or not listed.missing.is_empty() or not _json_equal(uuids,query.get("record_uuids")):
		return {"error":ERR_INVALID_DATA,"reason":"selection_path_list_invalid"}
	var expected_count:=9 if expansion==0. else 18
	var sorted_actual:Array=wanted_paths.keys();sorted_actual.sort()
	var sorted_report:Array=listed.paths.duplicate();sorted_report.sort()
	if sorted_actual!=sorted_report or sorted_actual.size()!=expected_count or listed.get("count")!=expected_count or listed.files.size()!=expected_count:
		return {"error":ERR_INVALID_DATA,"reason":"selection_path_set_changed"}
	var file_paths:Dictionary={};var source_bytes:=0
	for value:Variant in listed.files:
		if not value is Dictionary or not value.get("path") is String or not wanted_paths.has(value.path) or file_paths.has(value.path) or not signatures.has(value.path):
			return {"error":ERR_INVALID_DATA,"reason":"selection_is_not_baseline_subset"}
		var source:=FileAccess.open(value.path,FileAccess.READ)
		if source==null:return {"error":ERR_FILE_CANT_OPEN,"reason":"selected_source_missing"}
		var length:=source.get_length();source.close()
		if value.get("bytes")!=length:return {"error":ERR_BUSY,"reason":"selected_source_size_changed"}
		file_paths[value.path]=true;source_bytes+=length
	if listed.get("source_bytes")!=source_bytes:return {"error":ERR_INVALID_DATA,"reason":"selection_byte_total_mismatch"}
	var selected:Array=[];var selected_signatures:Dictionary={}
	# Keep the baseline production ordering; the report's lexical list must not
	# silently reorder admission and turn this into a scheduling experiment.
	for path:String in baseline:
		if wanted_paths.has(path):selected.append(path);selected_signatures[path]=signatures[path]
	if selected.size()!=expected_count:return {"error":ERR_INVALID_DATA,"reason":"selection_baseline_members_missing"}
	return {"error":OK,"paths":selected,"signatures":selected_signatures,"selection":{"name":selection_name,"report":selection_report,"report_sha":text.sha256_text(),"clip_xz":wanted,"model_count":selected.size(),"source_bytes":source_bytes,"records_in_report":exact.selected_count,"scope":"Only direct external GLB paths, not hydrated native/global/building dependencies or a complete ready chunk. Current production index selection was recomputed; source SHA remains verified against baseline."}}

func parse_models(paths:Array,signatures:Dictionary,content_root:String)->Dictionary:
	var begin_epoch:=Time.get_unix_time_from_system();var began:=Time.get_ticks_usec()
	var parsed:Dictionary=_preparation.run(paths,Callable(),workers,Callable(),content_root,signatures)
	parsed.probe_run_started_us=began;parsed.probe_run_finished_us=Time.get_ticks_usec()
	parsed.probe_run_epoch_s=begin_epoch;parsed.probe_run_end_epoch_s=Time.get_unix_time_from_system()
	return parsed

func validate_after(paths:Array,signatures:Dictionary,content_root:String,map_path:String,map_sha:String)->Dictionary:
	var after:Dictionary=Hashes.new().run(paths,content_root,4)
	var estimates:Dictionary={};var exclusive:Array=[];var unknown:Array=[];var total:=0
	# Keep this second header pass outside ModelParsePreparation timing. Do not
	# inject a different estimator or change any production admission decision.
	for path:String in paths:
		var estimate:Dictionary=Estimate.estimate(path);estimates[path]=estimate;total+=int(estimate.estimated_bytes)
		if estimate.exclusive or int(estimate.estimated_bytes)>byte_limit:exclusive.append(path)
		if not estimate.known:unknown.append(path)
	return {"error":after.error,"source_unchanged":after.error==OK and after.signatures==signatures,
		"map_unchanged":Paths.allowed(map_path,content_root) and FileAccess.get_sha256(map_path)==map_sha,
		"hash_profile":after,"estimates":estimates,"exclusive_paths":exclusive,"exclusive_count":exclusive.size(),"unknown_paths":unknown,"estimated_total_bytes":total}

func consume_metadata(parsed:Dictionary)->Dictionary:
	var weak:Dictionary={};var kinds:Dictionary={};var tasks:Array=[];var paths:Array=[]
	var complete:=true
	for entry:Dictionary in parsed.get("entries",[]):
		paths.append(str(entry.get("path","")))
		var packed:PackedScene=entry.get("packed")
		complete=complete and entry.get("error",-1)==OK and entry.get("compiled",false) and packed!=null and packed.can_instantiate()
		var row:={"path":entry.get("path",""),"error":entry.get("error",-1),"compiled":entry.get("compiled",false),"source_digest":entry.get("source_digest",""),"elapsed_us":entry.get("elapsed_us",0),"cache_us":entry.get("cache_us",0),"scene_nodes":0}
		if packed!=null:
			watch(packed,weak,kinds)
			var state:=packed.get_state();row.scene_nodes=state.get_node_count()
			for i in state.get_node_count():
				for j in state.get_node_property_count(i):watch(state.get_node_property_value(i,j),weak,kinds)
		tasks.append(row)
	return {"weak":weak,"resource_kinds":kinds,"tasks":tasks,"paths":paths,"complete":complete}

func watch(value:Variant,weak:Dictionary,kinds:Dictionary)->void:
	if value is Resource:
		var id:int=value.get_instance_id()
		if weak.has(id):return
		weak[id]=weakref(value)
		var kind:String=value.get_class();kinds[kind]=int(kinds.get(kind,0))+1
		# Resource identity only: no get_faces(), surface arrays or texture image
		# readback. PackedScene properties expose mesh/material references.
		if value is Mesh:
			for slot in value.get_surface_count():watch(value.surface_get_material(slot),weak,kinds)
		elif value is BaseMaterial3D:
			for slot in BaseMaterial3D.TEXTURE_MAX:watch(value.get_texture(slot),weak,kinds)
	elif value is Array:
		for item:Variant in value:watch(item,weak,kinds)
	elif value is Dictionary:
		for item:Variant in value.values():watch(item,weak,kinds)

func memory()->Dictionary:
	return {"static_bytes":OS.get_static_memory_usage(),"render_video_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),"render_texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),"render_buffer_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)}

static func _sha(value:Variant)->bool:
	return value is String and value.length()==64 and value.is_valid_hex_number(false)

static func _json_equal(a:Variant,b:Variant)->bool:
	return Index._json_equal(a,b,0,[2000000])

func run()->void:
	var invalid_argument:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):input=arg.trim_prefix("--input=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--workers="):workers=arg.trim_prefix("--workers=").to_int()
		elif arg.begins_with("--byte-limit-bytes="):byte_limit=arg.trim_prefix("--byte-limit-bytes=").to_int()
		elif arg.begins_with("--selection-report="):selection_report=arg.trim_prefix("--selection-report=")
		elif arg.begins_with("--selection="):selection_name=arg.trim_prefix("--selection=")
		else:invalid_argument=true
	var content_root:=Paths.external_root();var artifacts:=content_root.path_join("review_artifacts")
	_output_ok=Paths.allowed(output,artifacts) and output.get_extension()=="json" and output!=input and output!=selection_report
	var selection_ok:=selection_report.is_empty() and selection_name.is_empty() or (Paths.allowed(selection_report,artifacts) and selection_name in ["cell_10_5","cell_10_5_expanded_8m"])
	if invalid_argument or not selection_ok or not _output_ok or not Paths.allowed(input,artifacts) or workers not in [2,4] or byte_limit<1:
		push_error("Invalid probe arguments: confined report paths, workers 2/4 and positive byte limit required");quit(1);return
	if not check(DisplayServer.get_name()!="headless","native GPU display backend is required"):persist();quit(1);return
	Engine.max_fps=60;root.size=Vector2i(320,180);root.disable_3d=true
	_deadline=Time.get_ticks_usec()+300000000
	_preparation.inflight_byte_limit=byte_limit
	report.input=input;report.worker_limit=workers;report.inflight_byte_limit=byte_limit;report.logical_cpus=OS.get_processor_count()
	report.renderer=ProjectSettings.get_setting("rendering/renderer/rendering_method","");report.display=DisplayServer.get_name()
	phase("validate_input_and_full_source_sha")
	var validated:=await launch(validate_input.bind(content_root))
	report.input_validation=validated
	if not check(validated.get("error",FAILED)==OK,"checkpoint, problem spawn, baseline 31 source SHA and requested exact subset are freshly verified"):
		persist();quit(1);return
	var paths:Array=validated.paths;var signatures:Dictionary=validated.signatures
	report.model_count=paths.size();report.selection=validated.selection
	report.workload_sha=JSON.stringify({"paths":paths,"signatures":signatures}).sha256_text()
	report.memory_before=memory()
	phase("model_parse_preparation")
	Trace.start()
	var parsed:=await launch(parse_models.bind(paths,signatures,content_root))
	report.load_trace=Trace.stop()
	var sync_started:=Time.get_ticks_usec();Drainer.synchronize_transfer()
	report.handoff_gpu_sync_us=Time.get_ticks_usec()-sync_started
	report.preparation=parsed.duplicate();report.preparation.erase("entries")
	var observed:=consume_metadata(parsed)
	report.tasks=observed.tasks;report.resource_kinds=observed.resource_kinds;report.memory_loaded=memory()
	check(parsed.get("error",FAILED)==OK and not parsed.get("cancelled",true),"production preparation completes without cancellation or errors")
	check(observed.complete and observed.paths==paths and observed.tasks.size()==paths.size(),"all %d native results are complete and preserve input order"%paths.size())
	check(parsed.get("native_cache_hits",0)==paths.size() and parsed.get("native_cache_misses",-1)==0,"all %d models use verified compiled cache hits"%paths.size())
	check(parsed.get("worker_limit",0)==workers and parsed.get("inflight_budget_bytes",0)==byte_limit,"production worker clamp and admission byte limit match requested experiment")
	check(parsed.get("threads_started",-1)==parsed.get("threads_joined",-2) and parsed.get("inflight_jobs_at_return",-1)==0 and parsed.get("inflight_reserved_at_return",-1)==0,"all worker ownership and in-flight reservations are recovered")
	var bound:=true
	for row:Dictionary in observed.tasks:bound=bound and row.source_digest==signatures.get(row.path,"")
	check(bound,"every returned model retains the freshly verified source digest")
	phase("release_native_results")
	parsed.clear();parsed={}
	Drainer.synchronize_transfer()
	for frame in 4:await process_frame
	var retained:Array=[]
	for id:Variant in observed.weak:
		if observed.weak[id].get_ref()!=null:retained.append({"id":id,"class":observed.weak[id].get_ref().get_class()})
	report.retained_resources=retained;report.watched_resource_count=observed.weak.size();report.memory_released=memory()
	check(retained.is_empty(),"PackedScenes and referenced mesh/material/texture resources are released without instantiation")
	observed.clear()
	phase("verify_sources_and_estimates_after_run")
	var after:=await launch(validate_after.bind(paths,signatures,content_root,validated.map,validated.map_sha))
	report.after=after
	check(after.get("error",FAILED)==OK and after.get("source_unchanged",false) and after.get("map_unchanged",false),"all source SHA and checkpoint bytes remain unchanged after preparation/release")
	check(after.get("estimated_total_bytes",-1)==report.preparation.get("initial_required_resident_estimate_bytes",-2),"reported per-path estimates reproduce production required-resident estimate")
	phase("complete")
	report.cancelled=_cancelled;persist()
	print("PROBLEM_CHUNK_ASSETS workers=",workers," run_ms=",float(report.preparation.get("elapsed_us",0))/1000.," peak_jobs=",report.preparation.get("peak_inflight_jobs",0)," exclusive_paths=",after.get("exclusive_count",0)," failures=",report.failures," output=",output)
	quit(1 if report.failures else 0)
