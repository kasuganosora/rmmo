extends SceneTree
const Pre=preload("res://scripts/world3d/cross_map_prefetch.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func wait_pre(service:Node)->bool:
	var deadline:=Time.get_ticks_msec()+20000
	while service._packet==null and Time.get_ticks_msec()<deadline:
		service.poll();await process_frame
	return service._packet!=null
func run()->void:
	create_timer(100).timeout.connect(func():quit(2))
	var dir:=Paths.cache_directory("approach_prefetch_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(dir)
	var path:=dir.path_join("map.gltf");var doc:=Doc.new()
	for i in 20:doc.add_box("ground",Vector3((i%5)*8,-.25,(i/5)*8),Vector3(8,.5,8))
	check(doc.save(path)==OK,"disposable native target saved")
	var ledger:=Admission.new();ledger.byte_limit=Pre.LEASE_BYTES*2
	var service:=Pre.new();root.add_child(service);var origin:=Vector3(2,.9,2)
	check(service.request(path,origin,ledger),"speculation borrows source admission byte ledger")
	check(ledger.reserved_bytes==Pre.LEASE_BYTES and ledger.active_workers()==1,"background CPU preparation shares the source worker and byte limits")
	check(await wait_pre(service),"native snapshot and selected dependency closure prepared")
	check(service._packet.restored.read_profile.threads_started==0,"hydration cannot spawn workers outside the shared single slot")
	check(ledger.reserved_bytes==Pre.LEASE_BYTES and ledger.active_workers()==0,"joined ready packet frees its worker slot while bytes remain charged")
	check(not ledger.reserve("exclusive",{"estimated_bytes":1,"exclusive":true}),"critical exclusive demand requests speculative preemption")
	service.poll()
	check(ledger.reserved_bytes==0 and service._packet==null,"preempted ready packet is discarded before byte release")
	check(ledger.reserve("exclusive",{"estimated_bytes":1,"exclusive":true}),"exclusive source work can proceed after retirement");ledger.release("exclusive")
	check(service.request(path,origin,ledger) and await wait_pre(service),"target can be requested again after preemption")
	var packet:=service.take(path,origin)
	check(packet!=null and ledger.reserved_bytes==0,"single-use handoff releases the shared lease")
	var loader:=Loader.new();loader.near_first=true;loader.source_prefetch=packet;packet=null;root.add_child(loader);loader.start(path,origin)
	var result:Array=await loader.finished;var scene:Node=result[0]
	check(scene!=null and result[2].is_empty(),"ordinary native loader accepts typed speculative packet")
	if scene!=null:
		var profile:Dictionary=scene.get_meta("load_profile",{})
		check(profile.get("source_prefetch_hit",false) and profile.get("hydration_prefetch_hit",false),"real parse and hydration consume preloaded source with normal integrity gates")
		preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	check(service.request(path,origin,ledger) and await wait_pre(service),"prepare source-change case")
	var stale:=service.take(path,origin);var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ");file.close()
	loader=Loader.new();loader.near_first=true;loader.source_prefetch=stale;stale=null;root.add_child(loader);loader.start(path,origin);result=await loader.finished;scene=result[0]
	check(scene!=null and not scene.get_meta("load_profile",{}).get("source_prefetch_hit",false),"changed target bytes fall back to fresh source; stale packet is never authoritative")
	if scene!=null:preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	var observed:Dictionary=service.profile.duplicate()
	check(not service.request("D:/outside.gltf",origin,ledger) and ledger.reserved_bytes==0,"resource-root violation has no lease side effect")
	check(not service.request(path,Vector3.INF,ledger),"nonfinite destination is rejected without starting work")
	var token:=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new();token.cancel()
	check(Pre.prepare(path,origin,Paths.external_root(),token,Pre.LEASE_BYTES).is_empty(),"cancelled speculative work produces no packet")
	check(service.request(path,origin,ledger),"exit case starts a real CPU worker")
	service.free()
	var deadline:=Time.get_ticks_msec()+20000
	while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(ledger.reserved_bytes==0,"owner exit drains late worker output and lease")
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new();queue._reference_index={"groups":{"building:a":{}}}
	var approach:=preload("res://scripts/world3d/approach_preparation.gd").new();approach.update(queue,Vector3.ZERO,Vector3(5,0,0))
	check(not queue._demands.is_empty() and queue._demands.values().all(func(d):return d.kind=="all" and d.priority==2),"forward corridor promotes every geometry kind below live player priority")
	check(queue._demands.values().any(func(d):return d.clip.has_point(Vector3(160,0,0))),"lookahead reaches beyond the live player ring")
	queue._reference_index={"groups":{"building:a":{"members":[0,1]}},"rows":[],"extras":{"rmmo_records":[]}}
	for i in 2:
		var compact:={"uuid":"member_%d"%i};queue._reference_index.extras.rmmo_records.append(compact)
		var row:={"group_id":"building:a","asset_path":"","memory_bytes":1};queue._reference_index.rows.append(row)
		var entry:=row.duplicate();entry.record_index=i
		queue.pending.append({"record":compact,"path":"reference:building:a","bounds":AABB(Vector3(160+i*100,0,0),Vector3.ONE),"group_id":"building:a","reference_entry":entry,"native_reference":true})
	queue._reference_index.groups["building:a"].bounds=AABB(Vector3(160,0,0),Vector3(101,1,1))
	queue._index_pending();queue._refresh_demanded()
	check(queue._demanded.size()==1 and queue._reference_requests("reference:building:a").size()==2,"touching one forward member prepares the whole indexed building, including the far side")
	queue.set_demand("current",AABB(Vector3(159,-1,-1),Vector3(3,3,3)),0);queue._refresh_demanded()
	check(queue._demanded_priority.member_0==0,"current player demand overrides forward-building preparation")
	approach.update(queue,Vector3.ZERO,Vector3.ZERO,PackedVector3Array(),Time.get_ticks_msec()+approach.STOP_HOLD_MSEC)
	check(queue._demands.keys()==["current"],"stopping expires only speculative demands, preserving live player demand")
	queue.free()
	var report:={"failures":failures,"checks":checks,"prefetch_profile":observed}
	FileAccess.open("D:/code/rmmo_runtime/review_artifacts/editor_runtime_followup_20261017/prefetch.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("APPROACH_PREFETCH ",JSON.stringify(report));quit(1 if failures else 0)
