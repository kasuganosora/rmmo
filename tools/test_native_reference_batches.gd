extends SceneTree
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Fixtures=preload("res://tools/test_map_dependency_index.gd")
const Roads=preload("res://tools/test_native_road_preparation.gd")
class BudgetQueue extends Queue:
	var requests_used:=0
	func _estimate_job(_item:Dictionary,requests:Array,_need_model:bool=true)->Dictionary:
		return {"estimated_bytes":1000 if requests.size()>1 else 1,"exclusive":false,"known":true}
	func _make_prepare_task(_path:String,_digest:String,_token:RefCounted,_item:Dictionary,_faces:bool,_root:String,requests:Array,_native:bool,_need_model:bool)->Callable:
		requests_used=requests.size()
		return func():return {"error":""}
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var helper:=Fixtures.new();helper.content_root=Paths.external_root()
	helper.folder=Paths.cache_directory("native_reference_batches_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(helper.folder)
	var roads:=Roads.new();var records:Array=[]
	for i:int in 33:
		var record:Dictionary=roads.road();record.uuid="road_%d"%i;record.position[0]=float(i*64);records.append(record)
	var fixture:Dictionary=helper.fixture("roads",records)
	var index:=Index.build(fixture.path,helper.content_root,records)
	check(index.ok,"temporary road catalog builds without mesh or texture resources")
	if not index.ok:quit(1);return
	var entries:Array=[]
	for row:Dictionary in index.rows:
		entries.append({"record_index":row.order,"compact_record":index.extras.rmmo_records[row.order],"bounds":row.bounds,"classification":row.classification,"reason":row.reason,"asset_path":row.asset_path,"group_id":row.group_id,"memory_bytes":row.memory_bytes})
	Queue.native_reference_batching_enabled=true
	var loader:=Loader.new();loader._dependency_index=index;loader._register_reference_pending(entries)
	var queue:=Queue.new();queue.configure_references(index,fixture.path,helper.content_root);queue.pending=loader._deferred_assets
	var paths:Dictionary={}
	for item:Dictionary in queue.pending:
		if not paths.has(item.path):paths[item.path]=[]
		paths[item.path].append(item)
	queue._demanded_by_path=paths
	check(paths.size()==3 and paths.values().all(func(items):return items.size()<=16),"33 independent roads use three bounded IO transactions")
	var before:=FileAccess.get_sha256(fixture.path);var hydrated:=0
	for path:String in paths:
		for attempt:int in 16:
			var requests:Array=queue._reference_requests(path)
			if requests.is_empty():break
			var first:Dictionary=paths[path][0];var estimate:=queue._estimate_job(first,requests)
			var expected_bytes:=0
			for entry:Dictionary in requests:expected_bytes+=entry.memory_bytes
			check(estimate.estimated_bytes==maxi(65536,expected_bytes),"reservation includes every demanded road in "+path)
			var worker:=Thread.new();worker.start(Queue._prepare_job.bind(path,"",null,{},false,helper.content_root,index,fixture.path,requests,true,false))
			var result:Dictionary=worker.wait_to_finish();hydrated+=result.records.size()
			check(result.error.is_empty() and result.records.size()==requests.size() and result.surface_arrays.size()==requests.size(),"one verified worker prepares exact independent road UUIDs in "+path)
			for item:Dictionary in paths[path]:
				for record:Dictionary in result.records:
					if item.record.uuid==record.uuid:item.reference_prepared=true
	check(hydrated==33 and FileAccess.get_sha256(fixture.path)==before,"all original references hydrate without changing author bytes")
	for item:Dictionary in queue.pending:item.reference_prepared=false
	var path:String=paths.keys()[0];var items:Array=paths[path]
	queue._demanded_by_path[path]=[items[0]]
	check(queue._reference_requests(path).size()==1,"batch identity never pulls undemanded siblings into a job")
	queue._demanded_by_path[path]=items
	queue._path_first[path]=items[1]
	queue._demanded_priority[items[1].record.uuid]=-100
	for item:Dictionary in items:
		if item!=items[1]:queue._demanded_priority[item.record.uuid]=10
	var urgent:=queue._reference_requests(path)
	check(urgent.size()==1 and urgent[0].compact_record.uuid==items[1].record.uuid,"critical collision demand never waits for distant background siblings")
	check(queue._job_publication_ids(path,urgent)==[items[1].record.uuid],"partial admitted batch only waits for its own prepared publication identities")
	queue._demanded_priority.clear();queue._path_first.clear()
	var original_bytes:int=items[0].reference_entry.memory_bytes
	for item:Dictionary in items:item.reference_entry.memory_bytes=int(Queue.ROAD_REFERENCE_BATCH_BYTES/2)+1
	check(queue._reference_requests(path).size()==1,"batch byte cap prevents combining individually valid roads into an oversized job")
	items[0].reference_entry.memory_bytes=Queue.ROAD_REFERENCE_BATCH_BYTES+1
	var large:=queue._reference_requests(path)
	check(large.size()==1 and large[0].compact_record.uuid==items[0].record.uuid,"a large valid road retains its original complete solo reservation")
	for item:Dictionary in items:item.reference_entry.memory_bytes=original_bytes
	queue._demanded_by_id={items[0].record.uuid:items[0],items[1].record.uuid:items[1]};queue._path_first[path]=items[0]
	var token:=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new()
	queue._jobs[path]={"token":token,"native":true,"publication_ids":[items[0].record.uuid,items[1].record.uuid],"result":{"error":"bad isolated definition","reference_failure":true,"failed_uuid":items[0].record.uuid}}
	queue._poll_jobs({path:true})
	check(queue.instance_errors.has(items[0].record.uuid) and not queue.instance_errors.has(items[1].record.uuid) and queue.path_errors.is_empty() and queue._jobs.is_empty(),"one bad definition does not poison unrelated roads in the same IO page")
	queue.instance_errors.clear()
	queue._demanded_by_id={items[0].record.uuid:items[0],items[1].record.uuid:items[1]}
	queue._path_first[path]=items[1];queue._demanded_priority={items[0].record.uuid:10,items[1].record.uuid:-100}
	var background:Dictionary={"publication_ids":[items[0].record.uuid]}
	check(queue._road_batch_superseded(path,background),"new critical same-page demand supersedes a background-only preparation")
	queue._demanded_priority[items[0].record.uuid]=-100
	check(not queue._road_batch_superseded(path,background),"equal-priority prepared work progresses instead of cancelling on every rank change")
	queue._demanded_priority[items[0].record.uuid]=10
	var preempt_token:=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken.new()
	background.token=preempt_token;background.native=true;background.result={"error":""};queue._jobs[path]=background
	queue._poll_jobs({path:true})
	check(preempt_token.is_cancelled() and queue._jobs.is_empty() and queue.instance_errors.is_empty(),"actual poll cancels and retires the old job without rejecting either road")
	var grouped:Dictionary=entries[0].duplicate();grouped.group_id="building:whole"
	check(Queue.reference_path(grouped)=="reference:building:whole","complete building groups keep their independent atomic path")
	Queue.native_reference_batching_enabled=false
	check(Queue.reference_path(entries[0])=="reference:0","same-code control retains one transaction per independent road")
	Queue.native_reference_batching_enabled=true
	var budget_queue:=BudgetQueue.new();budget_queue.configure_references(index,fixture.path,helper.content_root)
	budget_queue.pending=items.slice(0,2);budget_queue._demanded_by_path={path:budget_queue.pending};budget_queue._path_first={path:items[0]}
	budget_queue._admission.byte_limit=100;budget_queue._dispatch_jobs(self)
	check(budget_queue.requests_used==1 and budget_queue._admission.reserved_bytes==1,"aggregate scratch larger than the ledger falls back to an admissible complete solo job")
	await budget_queue.quiesce();budget_queue.free()
	queue.free();loader.free();roads.free();helper.free()
	print("NATIVE_REFERENCE_BATCHES checks=",checks," failures=",failures);quit(1 if failures else 0)
