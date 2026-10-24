extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func legacy(queue:Node,path:String)->void:
	for item:Dictionary in queue.pending:
		if item.path!=path:continue
		item.erase("model_verified")
		if item.has("reference_entry") and item.get("reference_prepared",false):
			item.record=item.reference_entry.compact_record;item.reference_prepared=false
func run()->void:
	var queue:=Deferred.new();root.add_child(queue);queue.set_process(false)
	var jobs:Dictionary={}
	for i:int in 8192:
		var path:="model%d"%(i/32);var uuid:="obj%d"%i
		var compact:={"uuid":uuid};var item:={"path":path,"record":{"uuid":uuid,"payload":[1,2,3]},"model_verified":true,"reference_prepared":true,"reference_entry":{"compact_record":compact},"bounds":AABB(Vector3(i,0,0),Vector3.ONE)}
		queue.pending.append(item)
		if not jobs.has(path):jobs[path]={"publication_ids":[],"result":{"records":[]}}
		# Include an accepted out-of-demand group member through the result set.
		if i%32!=31:jobs[path].publication_ids.append(uuid)
		else:jobs[path].result.records.append(item.record)
	queue._index_pending()
	var started:=Time.get_ticks_usec()
	for path:String in jobs:
		if queue.has_method("_discard_pending_preparation"):queue._discard_pending_preparation(path,jobs[path])
		else:legacy(queue,path)
	var elapsed:=Time.get_ticks_usec()-started
	var visits:int=queue.profile.get("discard_pending_visits",8192*256)
	check(queue.pending.all(func(item):return not item.has("model_verified") and not item.reference_prepared and is_same(item.record,item.reference_entry.compact_record)),"all accepted owners including non-demanded group members release hydrated definitions")
	if queue.has_method("_discard_pending_preparation"):
		check(queue.profile.discard_pending_visits==8192,"discard work visits affected owners once instead of all 8192 pending rows per job")
		var item:Dictionary=queue.pending[0];item.model_verified=true
		queue._discard_pending_preparation("different_model",{"publication_ids":[item.record.uuid],"result":{}})
		check(item.has("model_verified"),"stale IDs cannot clear another path's current owner")
		queue._indexed=false
		queue._discard_pending_preparation("model0",{})
		check(not item.has("model_verified"),"non-indexed diagnostic queue keeps full-scan cleanup")
	print("JOB_RELEASE_CATALOGUE ",JSON.stringify({"us":elapsed,"visits":visits,"failures":failures}))
	queue.free();quit(1 if failures else 0)
