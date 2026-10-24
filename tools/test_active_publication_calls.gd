extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Probe extends Deferred:
	var discard_calls:=0
	var blocked:Dictionary={}
	func _publication_discarded(item:Dictionary,staged:Dictionary)->bool:
		discard_calls+=1;return super._publication_discarded(item,staged)
	func _runtime_supports_ready(uuid:String)->bool:return not blocked.has(uuid)
	func _collision_publication_status(uuid:String)->Dictionary:return blocked.get(uuid,{})
class Cursor extends RefCounted:
	var disposed:=false
	var profile:Dictionary={} # Production cancellation reads the cursor's work counters.
	func dispose()->void:disposed=true
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var service:=Probe.new();root.add_child(service);service.set_process(false)
	var items:Array=[]
	for i:int in 4096:
		var item:={"record":{"uuid":"item_%d"%i},"path":"same_model","native_reference":true}
		items.append(item);service._demanded_by_id[item.record.uuid]=item;service._demanded_rank[item.record.uuid]=i
	service._demanded_by_path.same_model=items;service._prepared_paths.same_model=true
	var cursor:=Cursor.new();service._jobs.same_model={"accepted":true,"instance_preparation":{"uuid":items.back().record.uuid,"cursor":cursor}}
	var began:=Time.get_ticks_usec();var found:=0
	# A demand refresh drops the publication queue while the same accepted
	# instance is still being assembled. It is the sole runnable item in this job.
	for frame:int in 120:
		if service._publication_ready()==[items.back()]:found+=1
	var elapsed:=Time.get_ticks_usec()-began
	if "--baseline" not in OS.get_cmdline_user_args():
		check(found==120,"active instance resumes immediately after queue reset")
		check(service.discard_calls<=240,"bounded active readiness checks independent of 4096 sibling count")
	service.blocked[items.back().record.uuid]={"owned":true,"pending":true}
	check(service._publication_ready()==[items.back()],"already allocated private work continues despite pending scene dependencies")
	service.blocked.clear();service._demanded_by_id.erase(items.back().record.uuid)
	service._publication_ready()
	check(cursor.disposed and not service._jobs.same_model.has("instance_preparation"),"lost demand disposes cursor and restores sibling selection")
	var calls:=service.discard_calls
	service._jobs.clear();service.free()
	print("ACTIVE_PUBLICATION_CALLS ",JSON.stringify({"found":found,"calls":calls,"us":elapsed,"failures":failures}));quit(1 if failures else 0)
