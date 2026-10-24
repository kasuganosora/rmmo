extends SceneTree
const Native=preload("res://scripts/world3d/native_residency.gd")
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func item(id:String)->Dictionary:
	return {"record":{"uuid":id},"bounds":AABB(Vector3.ZERO,Vector3.ONE),"path":"fixture","published":false}
func run()->void:
	var queue:=Queue.new();var service:=Native.new();service._queue=queue
	for i:int in 2400:queue.pending.append(item("part%d"%i))
	queue._index_pending()
	var ids:Dictionary=service._retirement_pending_ids()
	check(ids.size()==2400 and ids.has("part2399"),"resident guard sees every actual pending UUID")
	check(is_same(ids,queue._pending_by_record_id),"indexed queue lends its existing membership without a whole-pending rebuild")
	var removed:Dictionary=queue.pending.back()
	queue._unindex_pending_item(removed);queue.pending.pop_back()
	ids=service._retirement_pending_ids()
	check(not ids.has("part2399") and ids.size()==2399,"publication/removal is immediately visible")
	var added:=item("returning")
	queue.pending.append(added);queue._index_pending_item(added)
	check(service._retirement_pending_ids().has("returning"),"returning ownership is protected before the next poll")
	# Non-indexed/fallback producers still need a current complete membership.
	queue._indexed=false;queue.pending=[item("replacement")]
	ids=service._retirement_pending_ids()
	check(ids.size()==1 and ids.has("replacement"),"invalidated catalogue cannot bless the old pending set")
	queue._index_pending();queue.pending.append(item("unindexed_tail"))
	ids=service._retirement_pending_ids()
	check(ids.size()==2 and ids.has("unindexed_tail"),"out-of-sync count falls back without losing new pending ownership")
	queue._indexed=false;queue.pending.clear()
	for i:int in 2400:queue.pending.append(item("stress%d"%i))
	queue._index_pending();service.profile={}
	var began:=Time.get_ticks_usec();var accepted:=0
	for i:int in 160:
		ids=service._retirement_pending_ids();accepted+=int(ids.has("stress2399"))
	var elapsed:=Time.get_ticks_usec()-began
	check(accepted==160,"all stress polls use complete pending ownership")
	check(int(service.profile.get("pending_membership_rows",0))==0 and int(service.profile.get("pending_membership_reuses",0))==160,"steady indexed polls traverse zero pending rows")
	print("NATIVE_PENDING_CATALOGUE ",JSON.stringify({"us":elapsed,"profile":service.profile,"failures":failures}))
	service.free();queue.free();quit(1 if failures else 0)
