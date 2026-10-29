extends SceneTree
## CPU-only, isolated table/header scheduling and retained-metadata contract.
const Catalog=preload("res://scripts/world3d/texture_plan_catalog.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Products=preload("res://scripts/world3d/model_texture_products.gd")
class FailedStart extends Catalog:
	func _start(_worker:Thread,_task:Callable)->Error:return ERR_CANT_CREATE
class Reader extends RefCounted:
	var gate:=Semaphore.new()
	var mutex:=Mutex.new()
	var calls:Dictionary={}
	var blocked:=""
	var on_main:=false
	var include_object:=false
	func count(key:String)->int:
		mutex.lock();var total:int=calls.get(key,0);mutex.unlock();return total
	func read(candidate:Dictionary,_root:String,_token:RefCounted)->Dictionary:
		var key:String=candidate.texture_table.sha256
		mutex.lock();calls[key]=int(calls.get(key,0))+1;on_main=on_main or Thread.is_main_thread();mutex.unlock()
		if key==blocked:gate.wait()
		var result:={"ok":true,"error":"","keys":{},"sources":{},"table_sha":key,"plan":{"rows":{},"output_bytes":0,"estimated_bytes":0}}
		if include_object:result.hidden={"nested":[RefCounted.new()]}
		return result
	func header(key:String,source:Array,_root:String)->Dictionary:
		mutex.lock();calls[key]=int(calls.get(key,0))+1;on_main=on_main or Thread.is_main_thread();mutex.unlock()
		if key==blocked:gate.wait()
		return {"path":source[0],"flip":false,"normal":false,"width":16,"height":16,"output_bytes":1364,"source_bytes":512,"cache_limit":65536,"extension":"png"}
var failures:Array[String]=[]
var checks:=0
var observations:Dictionary={}
var root_path:String
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func candidate(id:int,rows:int=0,bytes:int=128)->Dictionary:
	return {"texture_table":{"version":1,"sha256":str(id).sha256_text(),"bytes":bytes,"textures":rows,"image_bytes":0}}
func wait_plan(catalog:RefCounted,item:Dictionary)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while catalog.model_plan(item,root_path).is_empty() and catalog.error.is_empty() and Time.get_ticks_msec()<deadline:
		catalog.poll();await process_frame
func wait_calls(reader:RefCounted,key:String)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while reader.count(key)==0 and Time.get_ticks_msec()<deadline:await process_frame
func wait_drain(ledger:RefCounted)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while ledger.count()>0 and Time.get_ticks_msec()<deadline:await process_frame
func run()->void:
	root_path=str(ProjectSettings.get_setting("rmmo/content_root","")).path_join("native_plan_%d"%OS.get_process_id())
	if not root_path.is_absolute_path() or DirAccess.make_dir_recursive_absolute(root_path)!=OK:quit(2);return
	var catalog:RefCounted=Catalog.new()
	check(catalog.has_method("prepare_model_async") and catalog.has_method("model_plan"),"native tables have an asynchronous ready-only catalog API")
	if not failures.is_empty():finish();return
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=16*1024*1024
	var reader:=Reader.new();catalog.model_reader=reader.read;catalog.header_reader=reader.header
	var slow:=root_path.path_join("slow_header.png");reader.blocked=slow
	var fast:=candidate(1);var next:=candidate(2)
	check(catalog.model_plan(fast,root_path).is_empty() and reader.count(fast.texture_table.sha256)==0,"ready lookup never performs a synchronous first read")
	check(not catalog.prepare_async({slow:[slow,false,false]},root_path,ledger,self),"ordinary header starts under the common ledger")
	await wait_calls(reader,slow)
	var began:=Time.get_ticks_usec()
	check(not catalog.prepare_model_async(fast,root_path,ledger,self),"native table starts beside blocked ordinary header")
	observations.dispatch_us=Time.get_ticks_usec()-began
	check(ledger.active_workers()==2,"native and ordinary metadata share the two-worker cap")
	check(not ledger.reserve("competing_geometry",{"estimated_bytes":1,"exclusive":false}),"geometry cannot bypass the shared header worker cap")
	await wait_plan(catalog,fast)
	var plan:Dictionary=catalog.model_plan(fast,root_path)
	check(plan.get("ok",false) and not catalog._rows.has(slow),"native table completes while earlier header is still blocked")
	check(ledger.active_workers()==1 and catalog.snapshot().native_metadata_reserved_bytes>0,"joined table releases worker but retains charged metadata")
	for unused:int in 100:catalog.prepare_model_async(fast,root_path,ledger,self);catalog.model_plan(fast,root_path)
	check(reader.count(fast.texture_table.sha256)==1,"one hundred ready consumers reuse exactly one table read")
	check(not catalog.prepare_model_async(next,root_path,ledger,self),"free sibling continues taking native table work")
	await wait_plan(catalog,next)
	check(reader.count(next.texture_table.sha256)==1 and not reader.on_main,"all injected table/header reads run off main")
	var conflict:Dictionary=fast.duplicate(true);conflict.texture_table.bytes+=1
	var reserved:int=ledger.reserved_bytes
	check(not catalog.prepare_model_async(conflict,root_path,ledger,self) and catalog.error.contains("Conflicting"),"same SHA with contradictory descriptor is refused")
	check(ledger.reserved_bytes==reserved and reader.count(fast.texture_table.sha256)==1,"descriptor conflict creates no duplicate read or lease")
	began=Time.get_ticks_usec();catalog.abandon();observations.abandon_us=Time.get_ticks_usec()-began
	check(catalog.pending_count()==0 and ledger.active_workers()==1 and ledger.reserved_bytes==65536,"abandon drops ready metadata but keeps blocked read charged")
	reader.gate.post();await wait_drain(ledger)
	check(ledger.count()==0,"detached header eventually drains its original lease")
	await native_cancel(ledger)
	await lifecycle(ledger)
	await metadata_consumers()
	await bounded_cache()
	await real_table(ledger)
	await pressure()
	finish()
func native_cancel(ledger:RefCounted)->void:
	var catalog:RefCounted=Catalog.new();var reader:=Reader.new();var item:=candidate(3)
	reader.blocked=item.texture_table.sha256;catalog.model_reader=reader.read
	catalog.prepare_model_async(item,root_path,ledger,self,"first");await wait_calls(reader,reader.blocked)
	for unused:int in 100:catalog.prepare_model_async(item,root_path,ledger,self,"second")
	check(reader.count(reader.blocked)==1 and catalog.pending_count()==1,"one hundred pending consumers never duplicate a blocked native table")
	var charged:int=ledger.reserved_bytes;catalog.release_model(item,root_path,"first")
	check(catalog.pending_count()==1 and ledger.reserved_bytes==charged,"one pending consumer cannot cancel its sibling's table")
	var began:=Time.get_ticks_usec();catalog.release_model(item,root_path,"second")
	observations.native_abandon_us=Time.get_ticks_usec()-began
	check(ledger.reserved_bytes==charged and ledger.active_workers()==1,"native cancellation transfers the live task without early budget release")
	reader.gate.post();await wait_drain(ledger);catalog.poll()
	check(ledger.count()==0 and catalog.model_plan(item,root_path).is_empty(),"cancelled native result cannot repopulate the catalog")
func lifecycle(ledger:RefCounted)->void:
	var failed:RefCounted=FailedStart.new();var item:=candidate(4)
	check(not failed.prepare_model_async(item,root_path,ledger,self) and not failed.error.is_empty() and ledger.count()==0,"native start failure returns its complete reservation")
	var catalog:RefCounted=Catalog.new();var reader:=Reader.new();catalog.model_reader=reader.read
	var original_limit:int=ledger.byte_limit
	catalog.prepare_model_async(item,root_path,ledger,self);await wait_plan(catalog,item)
	var metadata:int=catalog.snapshot().native_metadata_reserved_bytes
	check(metadata>0 and ledger.reserved_bytes==0 and ledger.active_workers()==0 and ledger.byte_limit==original_limit-metadata,"metadata is counted once outside running admission entries")
	check(ledger.reserve("same_model_exclusive",{"estimated_bytes":1,"exclusive":true}),"ready table does not block its own model's exclusive admission")
	ledger.release("same_model_exclusive")
	catalog.shutdown();check(ledger.count()==0 and catalog.model_plan(item,root_path).is_empty(),"shutdown clears ready metadata and releases its lease")
	var bad:RefCounted=Catalog.new();var malformed:=Reader.new();malformed.include_object=true;bad.model_reader=malformed.read
	bad.prepare_model_async(candidate(5),root_path,ledger,self);await wait_plan(bad,candidate(5))
	check(not bad.error.is_empty() and bad.model_plan(candidate(5),root_path).get("ok",true)==false,"metadata result refuses nested object owners")
	bad.shutdown();check(ledger.count()==0,"rejected object result leaves no admission leak")
	var large:RefCounted=Catalog.new();large.model_reader=reader.read
	var small:=Admission.new();small.worker_limit=2;small.byte_limit=65536
	large.prepare_model_async(candidate(7),root_path,small,self,"earlier");await wait_plan(large,candidate(7))
	large.prepare_model_async(candidate(6,0,4096),root_path,small,self);await wait_plan(large,candidate(6,0,4096))
	check(large.model_plan(candidate(6,0,4096),root_path).get("ok",false) and small.active_workers()==0,"oversized parse workspace may finish into a smaller retained plan")
	check(large.model_plan(candidate(7),root_path).get("ok",false),"an earlier pinned table does not block another oversized workspace")
	check(small.reserve("geometry_after_parse",{"estimated_bytes":1,"exclusive":false}),"completed oversized workspace does not leave a permanent exclusive blocker")
	small.release("geometry_after_parse");large.release_model(candidate(7),root_path,"earlier");large.shutdown()
	check(small.count()==0,"oversized workspace and metadata both release cleanly")
func metadata_consumers()->void:
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=65536
	var catalog:RefCounted=Catalog.new();catalog.native_cache_bytes=8192
	var reader:=Reader.new();catalog.model_reader=reader.read
	var item:=candidate(20,16)
	catalog.prepare_model_async(item,root_path,ledger,self,"a");catalog.prepare_model_async(item,root_path,ledger,self,"b")
	await wait_plan(catalog,item)
	var charged:int=catalog.snapshot().native_metadata_reserved_bytes
	check(charged>65536 and ledger.byte_limit==1 and ledger.count()==0,"oversize table is supported and fully reported outside the worker ledger")
	check(ledger.reserve("large_geometry",{"estimated_bytes":200000,"exclusive":true}),"oversize table still permits its exclusive geometry to progress")
	ledger.release("large_geometry")
	check(not catalog.prepare_model_async(candidate(21),root_path,ledger,self,"next") and catalog.pending_count()==0 and catalog.error.is_empty(),"another table waits for metadata capacity without rejecting the large model")
	catalog.release_model(item,root_path,"a")
	check(catalog.snapshot().native_metadata_reserved_bytes==charged and catalog.snapshot().native_consumers==1,"one of two consumers cannot return shared metadata early")
	ledger.byte_limit=131072;catalog.reapply_metadata_budget(ledger)
	check(ledger.byte_limit==maxi(1,131072-charged),"working-budget reconfiguration reapplies the live metadata deduction")
	catalog.release_model(item,root_path,"b")
	check(catalog.snapshot().native_metadata_reserved_bytes==0 and ledger.byte_limit==131072,"last consumer releases an over-cache table and restores the new budget")
	var small:=candidate(22)
	catalog.prepare_model_async(small,root_path,ledger,self,"retiring");await wait_plan(catalog,small)
	charged=catalog.snapshot().native_metadata_reserved_bytes;catalog.abandon()
	check(catalog.model_plan(small,root_path).is_empty() and catalog.snapshot().native_metadata_reserved_bytes==charged,"abandon hides but still charges metadata borrowed by a retiring job")
	catalog.release_model(small,root_path,"retiring")
	check(catalog.snapshot().native_metadata_reserved_bytes==0 and ledger.byte_limit==131072,"retiring job's final release returns its metadata deduction")
func bounded_cache()->void:
	var ledger:=Admission.new();ledger.byte_limit=1024*1024
	var catalog:RefCounted=Catalog.new();catalog.native_cache_bytes=11000
	var reader:=Reader.new();catalog.model_reader=reader.read
	for id:int in range(30,35):
		catalog.prepare_model_async(candidate(id),root_path,ledger,self);await wait_plan(catalog,candidate(id))
	check(catalog.snapshot().native_metadata_reserved_bytes<=11000 and catalog.snapshot().native_entries<=2,"unclaimed ordinary plans stay within the metadata cache byte bound")
	check(catalog.model_plan(candidate(30),root_path).is_empty() and catalog.model_plan(candidate(34),root_path).get("ok",false),"cache pressure evicts old unpinned plans and retains the latest result")
	catalog.shutdown();check(ledger.byte_limit==1024*1024 and ledger.count()==0,"bounded cache restores all deducted capacity")
func real_table(ledger:RefCounted)->void:
	var pixels:=Image.create(4,4,false,Image.FORMAT_RGBA8);pixels.fill(Color(.3,.7,.2,.5));pixels.generate_mipmaps()
	var pixel_id:=Products._pixel_key(pixels);var product_path:=Products.directory(root_path).path_join(pixel_id+".stex")
	DirAccess.make_dir_recursive_absolute(Products.directory(root_path))
	var product:=FileAccess.open(product_path,FileAccess.WRITE);Products.Product.write(product,pixels);product.close()
	var row:={"pixel_sha":pixel_id,"file":"cache/world3d/model_textures_v1/"+pixel_id+".stex","width":4,"height":4,"format":Image.FORMAT_RGBA8,"bytes":84,"file_bytes":152,"alpha":true,"normal_xy":false,"mip_sizes":[64,16,4]}
	var text:=JSON.stringify({"version":1,"textures":{pixel_id:row},"image_bytes":84})
	var descriptor:={"version":1,"sha256":text.sha256_text(),"bytes":text.to_utf8_buffer().size(),"textures":1,"image_bytes":84}
	var directory:=Products.table_directory(root_path);DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join(descriptor.sha256+".json")
	FileAccess.open(path,FileAccess.WRITE).store_string(text)
	var item:={"texture_table":descriptor};var catalog:RefCounted=Catalog.new()
	check(not catalog.prepare_model_async(item,root_path,ledger,self),"real immutable table read is dispatched asynchronously")
	await wait_plan(catalog,item)
	observations.real_table_plan=catalog.model_plan(item,root_path)
	observations.real_table_error=catalog.error
	check(catalog.model_plan(item,root_path).get("table_sha","")==descriptor.sha256,"real published descriptor produces the expected ready table")
	var prepared:Dictionary=catalog.model_plan(item,root_path)
	check(prepared.get("plan",{}).get("output_bytes")==84 and prepared.get("sources",{}).size()==1,"real product layout and typed mip sizes survive scalar preparation")
	DirAccess.remove_absolute(path)
	check(catalog.prepare_model_async(item,root_path,ledger,self) and catalog.model_plan(item,root_path).get("ok",false),"ready table is consumed without reopening its source file")
	catalog.reset();check(ledger.count()==0,"source reset releases native metadata and invalidates ready plans")
func pressure()->void:
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=32*1024*1024
	var catalog:RefCounted=Catalog.new();var reader:=Reader.new();catalog.model_reader=reader.read
	var total:=1057;var next:=0;var finished:=0;var pending:Array[Dictionary]=[]
	var deadline:=Time.get_ticks_msec()+30000;var began:=Time.get_ticks_usec();var dispatch_max:=0
	while finished<total and Time.get_ticks_msec()<deadline:
		catalog.poll()
		for index:int in range(pending.size()-1,-1,-1):
			if not catalog.model_plan(pending[index],root_path).is_empty():finished+=1;pending.remove_at(index)
		while next<total and ledger.has_capacity():
			var item:=candidate(1000+next);var start:=Time.get_ticks_usec()
			catalog.prepare_model_async(item,root_path,ledger,self)
			dispatch_max=maxi(dispatch_max,Time.get_ticks_usec()-start);pending.append(item);next+=1
		await process_frame
	observations.pressure={"unique_tables":total,"completed":finished,"elapsed_us":Time.get_ticks_usec()-began,"dispatch_max_us":dispatch_max,"snapshot":catalog.snapshot(),"ledger":ledger.snapshot()}
	check(finished==total and catalog.snapshot().native_async_reads==total and reader.calls.size()==total,"1057-table pressure has no 1024-model cap or duplicate work")
	check(ledger.active_workers()==0 and ledger.peak_workers==2 and ledger.reserved_bytes==0 and ledger.byte_limit+catalog.snapshot().native_metadata_reserved_bytes==32*1024*1024,"pressure preserves two-worker cap and accounts every retained table")
	catalog.shutdown();check(ledger.count()==0 and ledger.reserved_bytes==0,"pressure shutdown releases every metadata lease")
func finish()->void:
	var result:={"checks":checks,"failures":failures,"observations":observations}
	FileAccess.open(root_path.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("ASYNC_MODEL_TEXTURE_PLANS ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
