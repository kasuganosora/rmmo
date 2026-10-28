extends SceneTree
## CPU-only capacity transitions; no imports, rendering resources or live workers.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Host extends Node3D:
	var _ready_for_play:=true
	var _transfer_pending:=false
	var _transfer_request_serial:=3
	var _local_transfer:Dictionary={}
class QuietCover extends Deferred.TransferLoading:
	func _ready()->void:set_process(false)
	func _process(_delta:float)->void:pass
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func update(service:Node)->void:
	service._update_loading_worker_capacity(service._main_thread_budget_usec())
func run()->void:
	for row:Array in [[-1,2],[0,2],[1,2],[2,2],[3,2],[4,2],[5,2],[6,3],[8,4],[10,5],[12,6],[24,6],[128,6]]:
		check(Deferred.automatic_loading_worker_limit(row[0])==row[1],"automatic cap for %d logical threads is %d"%row)
	var host:=Host.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map)
	var service:=Deferred.new();map.add_child(service);service.activate(host);service.set_process(false)
	var cover:=QuietCover.new();host.add_child(cover)
	host._local_transfer={"request":3,"map":map,"deferred":service,"cover":cover,"cancelled":false,"scope_applied":true,"demand_id":"transfer:3"}
	service.set_demand_scope(["transfer:3"]);service.set_process(false)
	service._admission.byte_limit=1024
	update(service)
	check(service._admission.worker_limit==2 and service.profile.worker_capacity.mode=="interactive","ordinary operation preserves its original two slots")
	var original_disable:=root.disable_3d
	host._transfer_pending=true;root.disable_3d=true
	update(service)
	check(service._admission.worker_limit==2,"undrawn loading cover cannot increase capacity")
	cover.drawn_frame=0;cover.opacity=1;cover.phase="waiting"
	update(service)
	check(service._admission.worker_limit==Deferred.automatic_loading_worker_limit(OS.get_processor_count()) and service._saved_interactive_worker_limit==2,"drawn scoped loading uses real CPU count while saving original interactive capacity")
	check(service.profile.worker_capacity.loading_override==0 and service.profile.worker_capacity.byte_limit==1024,"production auto selection is reported without increasing the byte allowance")
	for value:int in [2,4,6]:
		service.loading_worker_limit=value;update(service)
		check(service._admission.worker_limit==value and service._saved_interactive_worker_limit==2 and service.profile.worker_capacity.loading_override==value,"explicit %d-worker probe survives automatic capacity refresh"%value)
	for i in 6:
		var path:="reference:test_%d"%i
		check(service._admission.reserve(path,{"estimated_bytes":16,"exclusive":false}),"loading slot %d can be admitted within unchanged byte limit"%i)
		service._jobs[path]={"result":{"payload":RefCounted.new()},"accepted":true,"token":Deferred.Drainer.CancelToken.new(),"publication_ids":[]}
	var result_id:int=service._jobs["reference:test_5"].result.payload.get_instance_id()
	host._transfer_pending=false;update(service)
	check(service._admission.worker_limit==2 and service._saved_interactive_worker_limit==-1,"leaving covered loading restores saved interactive capacity")
	check(service._jobs.size()==6 and service._admission.count()==6 and service._admission.reserved_bytes==96 and service._jobs["reference:test_5"].result.payload.get_instance_id()==result_id,"reducing capacity preserves all completed results and their slots and bytes")
	check(service._jobs.values().all(func(job):return not job.token.is_cancelled()) and not service._admission.has_capacity(),"capacity reduction does not cancel admitted jobs and blocks fresh admission while over capacity")
	for i in 4:service._discard_job("reference:test_%d"%i)
	check(service._admission.count()==2 and service._admission.reserved_bytes==32 and not service._admission.has_capacity(),"normal consumption reaches the interactive limit without admitting too early")
	service._discard_job("reference:test_4")
	check(service._admission.has_capacity() and service._admission.count()==1 and service._admission.reserved_bytes==16,"only normal result consumption opens an interactive slot again")
	service._discard_job("reference:test_5")
	host._transfer_pending=true;service.loading_worker_limit=4;update(service)
	host._local_transfer.cancelled=true;update(service)
	check(service._admission.worker_limit==2 and service._admission.byte_limit==1024,"cancelling covered transfer restores capacity without changing bytes")
	host._local_transfer.cancelled=false;service._admission.worker_limit=3;service.loading_worker_limit=6;update(service)
	host._transfer_pending=false;update(service)
	check(service._admission.worker_limit==3,"an explicitly configured prior interactive limit is restored exactly")
	service._admission.worker_limit=2;host._transfer_pending=true;service.loading_worker_limit=6;update(service)
	service._admission.worker_limit=0;update(service)
	check(service._admission.worker_limit==0 and service._saved_interactive_worker_limit==-1 and service.profile.worker_capacity.mode=="disabled","explicit zero during loading disables dispatch and discards automatic restoration state")
	host._transfer_pending=false;update(service)
	check(service._admission.worker_limit==0,"leaving loading cannot revive explicitly disabled dispatch")
	host._transfer_pending=true;update(service)
	check(service._admission.worker_limit==0,"re-entering covered loading also preserves explicit zero")
	service._admission.worker_limit=2;host._local_transfer.scope_applied=false;update(service)
	check(service._admission.worker_limit==2,"cover without its current scope transaction cannot apply worker override")
	host._local_transfer.scope_applied=true;host._local_transfer.request=2;update(service)
	check(service._admission.worker_limit==2,"stale transaction cannot increase admission capacity")
	host._local_transfer.request=3;service.loading_worker_limit=0
	update(service);service.set_demand_scope([]);service.set_process(false)
	check(service._admission.worker_limit==2 and service._saved_interactive_worker_limit==-1,"scope cleanup synchronously restores capacity even when processing is stopped")
	service.set_demand_scope(["transfer:3"]);service.set_process(false)
	check(service._admission.worker_limit==2,"scope setter never raises capacity ahead of the processing guard")
	service.pending=[{"record":{"uuid":"still_far"},"path":"reference:far","bounds":AABB(Vector3(1000,0,0),Vector3.ONE)}]
	service._process(0)
	check(service._admission.worker_limit==Deferred.automatic_loading_worker_limit(OS.get_processor_count()),"real processing applies production automatic capacity before dispatch")
	host._transfer_pending=false;service._process(0)
	check(service._admission.worker_limit==2,"real processing restores interactive capacity before subsequent dispatch")
	host._transfer_pending=true;service.pending.clear();service._process(0)
	check(service.is_complete() and not service.is_processing() and service._admission.worker_limit==2 and service._saved_interactive_worker_limit==-1,"complete queue restores interactive capacity before stopping process callbacks")
	host.free();root.disable_3d=original_disable
	print("DEFERRED_LOADING_WORKERS passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
