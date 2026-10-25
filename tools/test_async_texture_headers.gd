extends SceneTree
const Catalog=preload("res://scripts/world3d/texture_plan_catalog.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
class FailedStart extends Catalog:
	func _start(_worker:Thread,_task:Callable)->Error:return ERR_CANT_CREATE

class Reader extends RefCounted:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var calls:Dictionary={}
	var blocked_path:=""
	var delay_ms:=0
	func read(key:String,source:Array,_root:String)->Dictionary:
		mutex.lock();calls[key]=int(calls.get(key,0))+1
		var hold:bool=key==blocked_path and calls[key]==1
		mutex.unlock()
		if hold:gate.wait()
		if delay_ms>0:OS.delay_msec(delay_ms)
		if key.ends_with("missing.png"):return {}
		return {"path":source[0],"flip":source[1],"normal":source[2],"width":16,"height":16,"output_bytes":1364,"source_bytes":512,"cache_limit":65536,"extension":"png"}
	func count(key:String)->int:
		mutex.lock();var n:int=calls.get(key,0);mutex.unlock();return n

var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func sources(path:String)->Dictionary:return {path:[path,false,false]}
func wait_row(catalog:RefCounted,path:String)->void:
	var deadline:=Time.get_ticks_msec()+3000
	while not catalog._rows.has(path) and Time.get_ticks_msec()<deadline:
		catalog.poll();await process_frame

func run()->void:
	var root_path:String=Catalog.Prep.Paths.external_root()
	var slow:=root_path.path_join("async_header_slow.png")
	var fast:=root_path.path_join("async_header_fast.png")
	var next:=root_path.path_join("async_header_next.png")
	var absent:=root_path.path_join("async_header_missing.png")
	# Reproduce the old dispatch dependency with a deterministic 200 ms source.
	# Same estimate/plan algorithm; injected wait stands in for file-open latency.
	var baseline:=Catalog.new();var delayed:=Reader.new();delayed.delay_ms=200;baseline.header_reader=delayed.read
	var began:=Time.get_ticks_usec();baseline.estimate(sources(slow),root_path)
	var sync_us:=Time.get_ticks_usec()-began
	check(sync_us>=200000,"synchronous first metadata read occupies main for the full source delay")
	var queue:=Deferred.new();var catalog:RefCounted=queue._texture_plan_catalog
	var reader:=Reader.new();reader.blocked_path=slow;catalog.header_reader=reader.read
	queue._reference_root=root_path;queue._reference_index={"rows":[{"prefab_textures":sources(slow)},{"prefab_textures":sources(fast)}]}
	var admission:RefCounted=queue._admission;admission.worker_limit=2;admission.byte_limit=131072
	began=Time.get_ticks_usec()
	check(not queue._texture_headers_ready({},[{"record_index":0}],self),"production dispatch defers an unavailable header")
	check(not queue._texture_headers_ready({},[{"record_index":1}],self),"second source starts while first is blocked")
	var dispatch_us:=Time.get_ticks_usec()-began
	check(dispatch_us<sync_us/2,"main dispatch returns before the simulated slow read can finish")
	check(admission.active_workers()==2 and admission.reserved_bytes==131072,"both header workers use the shared worker and byte cap")
	check(not admission.reserve("geometry",{"estimated_bytes":1,"exclusive":false}),"geometry cannot bypass the header workers' common cap")
	await wait_row(catalog,fast)
	check(catalog._rows.has(fast) and not catalog._rows.has(slow),"fast header completes out of order without joining blocked worker")
	check(admission.active_workers()==1 and admission.reserved_bytes==65536,"completed header immediately frees its execution/workspace lease")
	check(queue._texture_headers_ready({},[{"record_index":1}],self),"ready source can dispatch while earlier source remains blocked")
	var plan:Dictionary=queue._prefab_texture_plan({"path":"reference:fast"},[{"record_index":1}])
	check(plan.rows.has(fast) and reader.count(fast)==1,"production plan consumes prepared metadata without synchronous reread")
	check(not catalog.prepare_async(sources(next),root_path,admission,self),"free second worker accepts another source")
	await wait_row(catalog,next)
	check(catalog._rows.has(next) and not catalog._rows.has(slow),"second worker continues working while first is paused")
	for i:int in 100:catalog.prepare_async(sources(slow),root_path,admission,self)
	check(reader.count(slow)==1,"one hundred shared pending requests never duplicate source work")
	catalog.prepare_async(sources(absent),root_path,admission,self);await wait_row(catalog,absent)
	check(catalog.prepare_async(sources(absent),root_path,admission,self) and reader.count(absent)==1,"negative metadata result is also shared and complete")
	check(not queue.is_idle() and not queue.is_complete(),"pending metadata remains part of full readiness")
	var old_revision:int=catalog.revision
	Paint.refresh_sources()
	check(not catalog.prepare_async(sources(slow),root_path,admission,self),"new source generation gets its own admitted read")
	await wait_row(catalog,slow)
	check(reader.count(slow)==2 and catalog.revision>old_revision,"cancelled old generation cannot block or populate the new catalog")
	check(admission.reserved_bytes==65536,"abandoned live read keeps its old charge until it actually returns")
	reader.gate.post()
	var deadline:=Time.get_ticks_msec()+3000
	while admission.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(admission.count()==0 and admission.reserved_bytes==0,"detached CPU metadata drains without a leaked lease")
	var cancelling:=Reader.new();cancelling.blocked_path=next;catalog.header_reader=cancelling.read
	catalog.prepare_async(sources(next),root_path,admission,self)
	deadline=Time.get_ticks_msec()+3000
	while cancelling.count(next)==0 and Time.get_ticks_msec()<deadline:await process_frame
	began=Time.get_ticks_usec();catalog.abandon();var cancel_us:=Time.get_ticks_usec()-began
	check(catalog.pending_count()==0 and admission.count()==1,"map detach transfers live ownership instead of waiting or releasing early")
	cancelling.gate.post()
	deadline=Time.get_ticks_msec()+3000
	while admission.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(admission.count()==0,"map detach eventually releases all header memory and slots")
	var failed_start:=FailedStart.new()
	check(not failed_start.prepare_async(sources(fast),root_path,admission,self) and not failed_start.error.is_empty() and admission.count()==0,"thread-start failure reports an error and returns the full reservation")
	var stress:=Catalog.new();var fast_reader:=Reader.new();stress.header_reader=fast_reader.read
	var all_sources:Dictionary={}
	for i:int in 256:
		var path:=root_path.path_join("header_stress_%d.png"%i);all_sources[path]=[path,false,false]
	deadline=Time.get_ticks_msec()+10000;var complete:=false;var dispatch_max_us:=0;var stress_start:=Time.get_ticks_usec()
	while not complete and Time.get_ticks_msec()<deadline:
		stress.poll();began=Time.get_ticks_usec()
		complete=stress.prepare_async(all_sources,root_path,admission,self)
		dispatch_max_us=maxi(dispatch_max_us,Time.get_ticks_usec()-began)
		await process_frame
	check(complete and stress.async_reads==256 and stress.misses==256,"256-source pressure performs exactly one header read per key")
	check(admission.peak_workers==2 and admission.peak_bytes==131072 and admission.count()==0,"pressure retains the original two-worker cap and returns all leases")
	print("HEADER_PRESSURE elapsed_us=",Time.get_ticks_usec()-stress_start," dispatch_max_us=",dispatch_max_us," reads=",stress.async_reads," start_max_us=",stress.start_max_us)
	print("HEADER_TIMING sync_us=",sync_us," dispatch_two_us=",dispatch_us," detach_us=",cancel_us)
	queue.free()
	print("ASYNC_TEXTURE_HEADERS failures=",failures);quit(1 if failures else 0)
