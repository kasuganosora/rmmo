extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var queue:=Deferred.new()
	for i:int in 6000:queue.pending.append({"record":{"uuid":"item%d"%i},"path":"a.glb","bounds":AABB(Vector3.ZERO,Vector3.ONE)})
	queue._index_pending()
	var untouched:Dictionary=queue.pending[5999].record
	var began:=Time.get_ticks_usec()
	for i:int in 200:queue._accept_prepared_records({"records":[{"uuid":"item%d"%i,"prepared_value":i},{"uuid":"already_retired","prepared_value":-1}]})
	var elapsed:=Time.get_ticks_usec()-began
	check(is_same(untouched,queue.pending[5999].record),"unrelated compact owner is untouched")
	var exact:=true
	for i:int in 200:exact=exact and queue.pending[i].record.prepared_value==i and queue.pending[i].reference_prepared
	check(exact and queue.pending.size()==6000,"accepted live records hydrate once; absent retired records stay absent")
	if "--expect-full" not in OS.get_cmdline_user_args():check(int(queue.profile.get("acceptance_record_visits",-1))==400,"indexed acceptance visits result records, never the pending town")
	# Standalone/non-indexed callers retain the complete-scan route.
	queue._indexed=false;queue._accept_prepared_records({"records":[{"uuid":"item5999","prepared_value":42}]})
	check(queue.pending[5999].record.prepared_value==42,"non-indexed fallback preserves hydration")
	var rows:Array=[]
	for i:int in 6000:rows.append({"reason":"native_road","bounds_known":true,"bounds":AABB(Vector3.ZERO,Vector3.ONE),"terrain_halo":0.})
	var index:={"rows":rows};var selected:Array=[0,1,2]
	began=Time.get_ticks_usec()
	var empty:=true
	for i:int in 200:empty=empty and Index.terrain_context_rows(index,selected).is_empty()
	var context_us:=Time.get_ticks_usec()-began
	check(empty,"non-terrain job has no seam dependencies")
	rows[0].reason="terrain_context_global";rows[0].terrain_halo=2.
	rows[3].reason="terrain_context_global";rows[3].bounds=AABB(Vector3(2,0,0),Vector3.ONE)
	rows[4].reason="terrain_context_global";rows[4].bounds=AABB(Vector3(100,0,0),Vector3.ONE)
	check(Index.terrain_context_rows(index,selected)==[rows[0],rows[3]],"actual terrain retains exact neighboring rows in source order")
	queue.free();print("REFERENCE_ACCEPTANCE_WORK ",JSON.stringify({"accept_us":elapsed,"context_us":context_us,"failures":failures}));quit(1 if failures else 0)
