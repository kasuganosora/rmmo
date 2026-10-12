extends SceneTree
## CPU-only transaction and bounded-worker tests; no meshes, models or formal map writes.
const Warm=preload("res://scripts/world3d/prefab_warm_preparation.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cursor=preload("res://scripts/world3d/document_open_cursor.gd")
const Snapshot=preload("res://scripts/world3d/document_source_snapshot.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Io=preload("res://scripts/world3d/gltf_map_io.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const LoadJob=preload("res://scripts/world_editor/load_job.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")

class EditorShell extends Node3D:
	# Only the UI/document owner is a fixture. LoadJob.start(), source reading,
	# cursor hydration, warm workers, exit notification and drainer are real.
	var _canvas:Node
	var _preview:Node
	var _status:=Label.new()
	var _doc:=RefCounted.new()
	var edits_finished:=0
	func _init()->void:add_child(_status)
	func saving()->bool:return false
	func _finish_edits()->void:edits_finished+=1

class Probe extends RefCounted:
	var mutex:=Mutex.new()
	var gate:=Semaphore.new()
	var held:=false
	var entered:=0
	var active:=0
	var peak:=0
	func warm(_value:Dictionary)->bool:
		mutex.lock();entered+=1;active+=1;peak=maxi(peak,active);mutex.unlock()
		if held:gate.wait()
		else:OS.delay_msec(10)
		mutex.lock();active-=1;mutex.unlock();return true
	func counts()->Dictionary:
		mutex.lock();var result:={"entered":entered,"active":active,"peak":peak};mutex.unlock();return result

var passed:=0
var failures:=0
var folder:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if ok:passed+=1
	else:failures+=1
func payload(index:int)->Dictionary:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var data:={"materials":[{"values":{"albedo_color":Color(.7,.2,.1),"roughness":.5+index*.01}}],"meshes":[{"surfaces":[arrays],"materials":[0],"bounds":AABB(Vector3.ZERO,Vector3(1,1,0)),"box_size":Vector3.ZERO}],"entries":[[["fixture"],[0,0]]]}
	var bytes:=var_to_bytes(data)
	return {"version":1,"sha256":House.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
func record(value:Dictionary,id:String)->Dictionary:
	return {"uuid":id,"kind":"box","surface_id":"block","collision":"block","position":[0,0,0],"rotation":[0,0,0],"size":[1,1,1],"house_prefab":value,"prefab_materials":[],"prefab_locked":true,"building":{"id":"house","part":id,"role":"wall","floor":0,"floor_y":0}}
func clear_entries(records:Array)->void:
	House._decode_mutex.lock()
	for row:Dictionary in records:
		var digest:String=row.house_prefab.sha256
		if House._decoded.has(digest):House._decoded_bytes-=int(House._decoded[digest].length);House._decoded.erase(digest)
	House._decode_mutex.unlock()
func drained(stats:Dictionary)->bool:
	return stats.ledger.jobs==0 and stats.ledger.reserved_bytes==0 and stats.ledger.active_workers==0 and stats.threads_started==stats.threads_joined
func write(path:String,data:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func fixture(name_:String,records:Array)->Dictionary:
	var path:=folder.path_join(name_+".gltf");var saved:=Store.write_records(records,path,Paths.external_root())
	if not saved.ok:check(false,"fixture writer "+str(saved.reason));return {}
	var parts:Dictionary={};var signatures:Dictionary={}
	for row:Dictionary in records:parts[row.uuid]=row.uuid;signatures[row.uuid]="fixture"
	var registry:={"house":{"version":Blueprint.VERSION,"parameters":Blueprint.defaults(),"position":[0,0,0],"yaw":0,"parts":parts,"signatures":signatures,"baked":true}}
	var data:={"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"extras":{"rmmo_format":"rmmo_gltf_map","rmmo_version":2,"rmmo_storage":"references_v1","rmmo_records":saved.records,"rmmo_resource_dependencies":saved.dependencies,"building_instances":registry}}]}
	write(path,data);return {"path":path,"data":data}
func begin(path:String)->RefCounted:
	var cursor:=Cursor.new();cursor.begin_snapshot(Snapshot.read_file(path),true);return cursor
func drain(cursor:RefCounted,phase:String="")->void:
	var deadline:=Time.get_ticks_msec()+15000
	while not cursor.done and (phase.is_empty() or cursor._phase!=phase) and Time.get_ticks_msec()<deadline:
		cursor.advance(1)
		if not cursor.done:await process_frame
	check(cursor.done if phase.is_empty() else (not cursor.done and cursor._phase==phase),"cursor completes" if phase.is_empty() else "cursor reaches "+phase+" without publication")
func wait_for_count(probe:Probe,count:int)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while probe.counts().entered<count and Time.get_ticks_msec()<deadline:await process_frame
	check(probe.counts().entered==count,"exactly %d admitted workers reach barrier"%count)
func collect(thread:Thread)->Dictionary:
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()
func trace_count(label:String)->int:
	Trace._mutex.lock();var count_:=0
	for value:Dictionary in Trace._stats.values():
		if value.label==label:count_+=int(value.count)
	Trace._mutex.unlock();return count_
func load_job_exit(path:String,records:Array)->void:
	clear_entries(records)
	var editor:=EditorShell.new();root.add_child(editor)
	var old_document:RefCounted=editor._doc
	var job:=LoadJob.new();job.editor=editor;job._validation_budget_us=1;editor.add_child(job)
	var publications:Array=[];job.finished.connect(func(value:Dictionary):publications.append(value))
	var drainer:=Drainer.for_tree(self);var drained_before:int=drainer.drained
	var gui_before:bool=editor.get_viewport().gui_disable_input
	Trace.start()
	# Hold the actual decode cache mutex rather than replacing House.warm with a
	# stub. Hydration still runs normally; this keeps the production coordinator
	# in flight until the real LoadJob owner exits and cancels its cursor.
	House._decode_mutex.lock()
	var started:Dictionary=job.start(path)
	check(started.get("ok",false) and editor.edits_finished==1,"real LoadJob starts a reference-map transaction")
	var deadline:=Time.get_ticks_msec()+5000
	while job.active and trace_count("editor.hydrate")==0 and Time.get_ticks_msec()<deadline:await process_frame
	var inflight:bool=job._validation!=null and job._validation._reference_thread!=null and trace_count("editor.hydrate")==1
	check(inflight and trace_count("editor.prefab_prewarm")==0,"real LoadJob reaches hydrated reference preparation before exit")
	var worker:Thread=job._validation._reference_thread if inflight else null
	var token:RefCounted=job._validation._reference_cancel if inflight else null
	var operation:int=job._serial
	editor.remove_child(job) # Delivers the actual Node._exit_tree notification.
	check(not job.active and job._serial==operation+1 and job._validation==null and not job._operation_current(operation),"LoadJob exit invalidates its operation and drops the cursor owner")
	var adopted:=false
	for pending:Dictionary in drainer.jobs:
		if pending.worker==worker:adopted=pending.abandoned
	check(inflight and adopted and worker.is_started(),"real exit transfers the still-started reference worker to the shared drainer")
	# _run's await-local cursor is released when the stale operation resumes.
	# Keep the removed node alive for that return; no manually detached cursor.
	await process_frame
	check(token!=null and token.is_cancelled(),"stale LoadJob coroutine releases its cursor and signals warm cancellation")
	House._decode_mutex.unlock()
	deadline=Time.get_ticks_msec()+5000
	while worker!=null and worker.is_started() and Time.get_ticks_msec()<deadline:await process_frame
	check(worker!=null and not worker.is_started() and drainer.drained==drained_before+1 and drainer.jobs.is_empty(),"shared drainer joins and disposes the abandoned production coordinator")
	check(trace_count("editor.prefab_prewarm")==1 and editor._doc==old_document and publications.is_empty(),"cancelled production preparation finishes without publishing or replacing the old document")
	check(editor.get_viewport().gui_disable_input==gui_before,"LoadJob exit restores input after cancelling the loading overlay")
	Trace.stop();job.free();editor.free()
func run()->void:
	create_timer(90).timeout.connect(func():print("PREFAB_WARM_TIMEOUT");quit(2))
	var original_workers:int=Cursor.prefab_warm_workers
	folder=Paths.cache_directory("prefab_warm_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var rows:Array=[]
	for i in 6:rows.append(record(payload(i),"piece_%d"%i))
	rows.append(record(rows[0].house_prefab.duplicate(true),"same_payload"))
	var before:=var_to_bytes(rows);clear_entries(rows)
	var one:=Warm.prepare(rows)
	check(one.unique==6 and one.decoded==6 and one.attempted==6 and one.completed==6 and one.threads_started==0 and drained(one),"default serial warms each unique payload once and releases every credit")
	check(one.decode_cache_capacity_reserved_bytes==House.DECODE_BUDGET and one.total_budget_bytes==one.workspace_budget_bytes+one.decode_cache_capacity_reserved_bytes+one.definition_cache_capacity_reserved_bytes,"workspace excludes existing resident decode and definition cache capacity")
	check(one.elapsed_ms>0 and one.worker_elapsed_us>0 and one.ledger.peak_workers==1,"serial reports actual timing and admission metrics")
	clear_entries(rows);var two:=Warm.prepare(rows,{"workers":2})
	check(two.unique==one.unique and two.decoded==one.decoded and two.threads_started==2 and two.threads_joined==2 and drained(two),"two persistent workers preserve serial decode results and join")
	check(var_to_bytes(rows)==before and not House.decode(rows[0].house_prefab).is_empty(),"workers leave all authored records untouched and ordinary public decode works")
	var probe:=Probe.new();probe.held=true;var thread:=Thread.new()
	thread.start(Warm.prepare.bind(rows,{"workers":2},null,probe.warm));await wait_for_count(probe,2)
	check(probe.counts().active==2,"two tasks are actually concurrent while preparation coordinator remains off main")
	for i in 6:probe.gate.post()
	var parallel:Dictionary=await collect(thread)
	check(probe.counts().peak==2 and parallel.ledger.peak_workers==2 and drained(parallel),"persistent worker queue never exceeds two active jobs")
	var max_job:=0
	for row:Dictionary in rows:max_job=maxi(max_job,int(Warm.estimate(row.house_prefab).estimated_bytes))
	probe=Probe.new();var constrained:=Warm.prepare(rows,{"workers":2,"total_budget_bytes":one.decode_cache_capacity_reserved_bytes+one.definition_cache_capacity_reserved_bytes+max_job},null,probe.warm)
	check(probe.counts().peak==1 and constrained.ledger.peak_workers==1 and constrained.ledger.peak_bytes<=constrained.workspace_budget_bytes and constrained.blocked.has("byte_limit") and drained(constrained),"byte budget serializes eligible jobs while keeping both workers reusable")
	probe=Probe.new();var oversized:=Warm.prepare(rows,{"workers":2,"total_budget_bytes":one.decode_cache_capacity_reserved_bytes+one.definition_cache_capacity_reserved_bytes+1},null,probe.warm)
	check(probe.counts().peak==1 and oversized.attempted==6 and oversized.blocked.has("exclusive_drain") and drained(oversized),"oversized jobs use exclusive drain and cannot deadlock on resident cache reserve")
	var unknowns:Array=[{}, {"length":-1,"data":""}, {"length":INF,"data":""}, {"length":Warm.MAX_RAW_BYTES+1,"data":""}, {"length":"10","data":""}]
	var conservative:=true
	for value:Dictionary in unknowns:
		var estimate:=Warm.estimate(value);conservative=conservative and estimate.exclusive and not estimate.known and estimate.estimated_bytes==Warm.MAX_RAW_BYTES*32+Warm.MAX_ENCODED_CHARS*8+4*1024*1024
	check(conservative,"missing invalid and excessive length hints all charge conservative maximum exclusive workspace")
	var failed_start:=Warm.prepare(rows,{"workers":2},null,Callable(),func(_thread:Thread,_body:Callable)->int:return ERR_CANT_CREATE)
	check(failed_start.start_failures==2 and failed_start.threads_started==0 and failed_start.worker_limit==1 and failed_start.decoded==6 and drained(failed_start),"both thread start failures fall back to complete serial preparation")
	for failed_index in [0,1]:
		clear_entries(rows);var starts:Array=[0]
		var partial:=Warm.prepare(rows,{"workers":2},null,Callable(),func(worker:Thread,body:Callable)->int:
			var index:int=starts[0];starts[0]+=1
			return ERR_CANT_CREATE if index==failed_index else worker.start(body,Thread.PRIORITY_LOW))
		check(starts[0]==2 and partial.start_failures==1 and partial.threads_started==1 and partial.threads_joined==1 and partial.worker_limit==1 and partial.decoded==6 and partial.attempted==6 and partial.completed==6 and partial.ledger.peak_workers==1 and drained(partial),"single child failure at slot %d retains the other real House.warm worker and releases all credit"%failed_index)
	var cancel:=Warm.CancelToken.new();cancel.cancel();probe=Probe.new()
	var cancelled:=Warm.prepare(rows,{"workers":2},cancel,probe.warm)
	check(cancelled.cancelled and cancelled.attempted==0 and probe.counts().entered==0 and drained(cancelled),"pre-cancelled preparation launches no threads or work")
	cancel=Warm.CancelToken.new();probe=Probe.new();probe.held=true;thread=Thread.new()
	thread.start(Warm.prepare.bind(rows,{"workers":2},cancel,probe.warm));await wait_for_count(probe,2)
	var cancel_started:=Time.get_ticks_usec();cancel.cancel()
	check(Time.get_ticks_usec()-cancel_started<50000 and thread.is_alive(),"cancel only signals; caller never joins active worker barriers")
	probe.gate.post();probe.gate.post();cancelled=await collect(thread)
	check(cancelled.cancelled and cancelled.attempted==2 and cancelled.completed==2 and probe.counts().entered==2 and drained(cancelled),"cancel stops later dispatch and coordinator joins both active workers and releases all credit")
	var map:=fixture("valid",rows);var cursors:Array=[]
	for workers in [1,2]:
		Cursor.prefab_warm_workers=workers;var cursor:=begin(map.path);await drain(cursor)
		check(cursor.document!=null and Pose.same(cursor.document.records,rows) and cursor.metrics.common_records==rows.size() and cursor.metrics.document_records==rows.size(),"worker %d retains every per-record validation and exact document"%workers)
		check(cursor.metrics.prefab_warm.unique==6 and cursor.metrics.prefab_warm.configured_workers==workers and drained(cursor.metrics.prefab_warm),"worker %d cursor exposes exact preparation metrics"%workers)
		cursors.append(cursor)
	check(Pose.same(cursors[0].document.records,cursors[1].document.records),"one and two worker transactions publish equivalent records")
	var sync:=begin(map.path)
	while not sync.done:sync.advance()
	check(sync.document!=null and Pose.same(sync.document.records,rows) and sync.metrics.prefab_warm.configured_workers==2,"synchronous cursor drains the same bounded queue correctly")
	for field in ["data","length"]:
		var changed:Dictionary=rows[0].duplicate(true);changed.uuid="corrupt_"+field;changed.building.part=changed.uuid
		if field=="data":changed.house_prefab.data=Marshalls.raw_to_base64(PackedByteArray([1,2,3]))
		else:changed.house_prefab.length+=4
		for bad_first in [false,true]:
			var records:Array=[changed,rows[0]] if bad_first else [rows[0],changed]
			var bad:=fixture("malformed_%s_%s"%[field,bad_first],records);var invalid:=begin(bad.path);await drain(invalid)
			check(invalid.document==null and "building" in invalid.error and invalid.metrics.prefab_warm.unique==1,"same SHA %s variant first=%s still rejects after non-authoritative deduplicated hint"%[field,bad_first])
	var racing:=begin(map.path);await drain(racing,"signature")
	var modified:Dictionary=map.data.duplicate(true);modified.asset.generator="concurrent writer";write(map.path,modified);racing.advance()
	check(racing.document==null and racing.error=="Map changed while opening","final source snapshot check rejects changed map after all parallel work")
	write(map.path,map.data)
	var resource_map:=fixture("resource_race",rows);var resource_cursor:=begin(resource_map.path)
	await drain(resource_cursor,"signature")
	check(resource_cursor.metrics.prefab_warm.decoded==6 and drained(resource_cursor.metrics.prefab_warm),"resource-race fixture completes actual warm preparation before corruption")
	var compact_ref:Dictionary=resource_map.data.nodes[0].extras.rmmo_records[0].rmmo_ref
	var resource_path:String=resource_map.path.get_base_dir().path_join(compact_ref.uri)
	var resource_bytes:=FileAccess.get_file_as_bytes(resource_path);var resource_sha:=FileAccess.get_sha256(resource_path)
	var map_sha:=FileAccess.get_sha256(resource_map.path);var declared_sha:String=compact_ref.sha256
	var damaged:=FileAccess.open(resource_path,FileAccess.READ_WRITE)
	damaged.seek(resource_bytes.size()-1);damaged.store_8(resource_bytes[-1]^1);damaged.close()
	check(FileAccess.get_file_as_bytes(resource_path).size()==resource_bytes.size() and FileAccess.get_sha256(resource_path)!=resource_sha and FileAccess.get_sha256(resource_map.path)==map_sha and compact_ref.sha256==declared_sha,"rmres is corrupted in place at unchanged length with unchanged map and declared SHA")
	resource_cursor.advance()
	check(resource_cursor.done and resource_cursor.document==null and resource_cursor.error=="Reference resources changed while opening","final dependency verification rejects post-warm rmres corruption despite cached definitions")
	var repaired:=FileAccess.open(resource_path,FileAccess.WRITE);repaired.store_buffer(resource_bytes);repaired.close()
	var reopened:=begin(resource_map.path);await drain(reopened)
	check(reopened.document!=null and Pose.same(reopened.document.records,rows),"restoring the original rmres permits a fresh complete transaction")
	var abandoned:=begin(map.path);await drain(abandoned,"references");abandoned.advance(1)
	var detached:Thread=abandoned._reference_thread;var detached_cancel:RefCounted=abandoned._reference_cancel
	abandoned._reference_thread=null;abandoned=null
	# GDScript may keep the last assignment temporary alive to this frame's end.
	await process_frame
	check(detached_cancel.is_cancelled(),"detached editor-style cursor destruction signals independent cancellation token")
	var abandoned_result:Dictionary=await collect(detached)
	check(not abandoned_result.get("ok",false) and abandoned_result.get("cancelled",false),"detached coordinator terminates with cancellation instead of publishing a document")
	await load_job_exit(map.path,rows)
	Cursor.prefab_warm_workers=original_workers;Io._remove_tree(folder)
	print("PREFAB_WARM_PREPARATION_FINISHED passed=%d failures=%d"%[passed,failures]);quit(0 if failures==0 else 1)
