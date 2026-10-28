extends SceneTree
## CPU-only: the cover has no controls and fake documents create empty nodes.
## Delays model an indivisible operation; no model, mesh, material or GPU work.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
class Host extends Node3D:
	var _ready_for_play:=true
	var _transfer_pending:=false
	var _transfer_request_serial:=7
	var _local_transfer:Dictionary={}
class QuietCover extends Deferred.TransferLoading:
	func _ready()->void:set_process(false)
	func _process(_delta:float)->void:pass
class Document extends RefCounted:
	var calls:Array=[]
	var delay_usec:=0
	var failure:=""
	func _mesh(record:Dictionary,_use_prepared:bool=true,_parts:Variant=null)->Node3D:
		calls.append(record.uuid)
		if delay_usec>0:OS.delay_usec(delay_usec)
		var holder:=Node3D.new()
		if record.uuid==failure:holder.set_meta("paint_error","fixture failure")
		return holder
class Probe extends Deferred:
	var acceptance_started:=0
	var acceptance_delay_usec:=0
	var publication_began:=0
	var publication_budget:=0
	func _accept_prepared_records(result:Dictionary)->void:
		acceptance_started=Time.get_ticks_usec()
		if acceptance_delay_usec>0:OS.delay_usec(acceptance_delay_usec)
		super._accept_prepared_records(result)
	func _publish_ready(began:int,budget_usec:int=INTERACTIVE_BUDGET_US)->Dictionary:
		publication_began=began;publication_budget=budget_usec
		return super._publish_ready(began,budget_usec)
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func fixture(count:int=6)->Dictionary:
	var host:=Host.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map);map.set_meta("stream_library",[])
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var service:=Probe.new();map.add_child(service)
	var document:=Document.new();service._doc=document
	var ids:Array=[]
	for i in count:
		var uuid:="item_%d"%i;ids.append(uuid)
		service.pending.append({"record":{"uuid":uuid},"path":"reference:test","native_reference":true,"bounds":AABB(Vector3(i,0,0),Vector3.ONE)})
	service.activate(host);service.set_process(false)
	service.set_demand("transfer:7",AABB(Vector3(-1,-1,-1),Vector3(100,3,3)))
	service._admission.reserve("reference:test",{"estimated_bytes":32,"exclusive":false})
	service._jobs["reference:test"]={"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":ids}
	# Never start real preparation, including after the fake completed job drains.
	service._admission.worker_limit=0
	var cover:=QuietCover.new();host.add_child(cover)
	host._local_transfer={"map":map,"deferred":service,"request":7,"cover":cover,"cancelled":false,"scope_applied":true,"demand_id":"transfer:7"}
	service.set_demand_scope(["transfer:7"]);service.set_process(false)
	return {"host":host,"map":map,"service":service,"document":document,"cover":cover}
func enable_cover(f:Dictionary)->void:
	f.host._transfer_pending=true;f.cover.drawn_frame=0;f.cover.opacity=1;f.cover.phase="waiting";root.disable_3d=true
func run()->void:
	var original_disable_3d:=root.disable_3d
	var f:=fixture();var service:Probe=f.service
	check(service._main_thread_budget_usec()==2000,"ordinary play uses the two millisecond slice")
	f.host._transfer_pending=true;root.disable_3d=true
	check(service._main_thread_budget_usec()==2000,"pending transfer and disabled 3D cannot boost an undrawn cover")
	f.cover.drawn_frame=0;f.cover.opacity=1;f.cover.phase="waiting";root.disable_3d=false
	check(service._main_thread_budget_usec()==2000,"drawn cover without disabled 3D remains interactive")
	root.disable_3d=true
	check(service._main_thread_budget_usec()==16000,"matching current transfer with visible drawn cover and disabled 3D receives sixteen milliseconds")
	f.cover.opacity=.5
	check(service._main_thread_budget_usec()==2000,"partial opacity revokes covered publication budget")
	f.cover.opacity=1;f.cover.phase="revealing"
	check(service._main_thread_budget_usec()==2000,"reveal phase revokes covered publication budget")
	f.cover.phase="waiting"
	f.host._local_transfer.scope_applied=false
	check(service._main_thread_budget_usec()==2000,"drawn loading cover cannot boost before its destination scope is applied")
	f.host._local_transfer.scope_applied=true;service.set_demand_scope(["different:scope"]);service.set_process(false)
	check(service._main_thread_budget_usec()==2000,"a replaced demand scope cannot inherit the old transfer budget")
	service.set_demand_scope(["transfer:7"]);service.set_process(false)
	f.host._local_transfer.cancelled=true
	check(service._main_thread_budget_usec()==2000,"cancelled transfer immediately loses the larger budget")
	f.host._local_transfer.cancelled=false;f.host._local_transfer.request=6
	check(service._main_thread_budget_usec()==2000,"stale transaction serial cannot boost the queue")
	f.host._local_transfer.request=7;f.host._local_transfer.map=f.host
	check(service._main_thread_budget_usec()==2000,"a cover for another map cannot boost this queue")
	f.host._local_transfer.map=f.map;f.host._local_transfer.deferred=null
	check(service._main_thread_budget_usec()==2000,"transaction must name this exact deferred queue")
	f.host._local_transfer.deferred=service;f.cover.visible=false
	check(service._main_thread_budget_usec()==2000,"hidden cover cannot boost publication")
	f.cover.visible=true;f.host.remove_child(f.cover)
	check(service._main_thread_budget_usec()==2000,"detached cover cannot boost publication")
	f.host.add_child(f.cover);f.host._transfer_pending=false
	check(service._main_thread_budget_usec()==2000,"completed transfer restores the interactive slice without a reset API")
	f.host._transfer_pending=true;f.host._local_transfer={}
	check(service._main_thread_budget_usec()==2000,"cross-map transfer without a local cover transaction does not inherit a boost")
	f.host._local_transfer={"map":f.map,"deferred":service,"request":7,"cover":f.cover,"cancelled":false,"scope_applied":true,"demand_id":"transfer:7"}
	f.cover.queue_free()
	check(service._main_thread_budget_usec()==2000,"a cover queued for deletion cannot authorize more work")
	service._host=f.map
	check(service._main_thread_budget_usec()==2000,"a generic host without transfer properties safely defaults to interactive")
	f.host.free()

	f=fixture();service=f.service;root.disable_3d=false
	var byte_limit:int=service._admission.byte_limit
	service.acceptance_delay_usec=3000
	service._process(0)
	check(service.publication_budget==0 and service.profile.main_thread_budget_us==2000,"exhausted acceptance defers publication under the original interactive clock")
	check(f.document.calls.is_empty() and service.pending.size()==6,"acceptance exhausting the slice cannot stack another instance in the same frame")
	var interactive:Dictionary=service.profile.main_thread_budgets.interactive
	check(interactive.frames==1 and interactive.acceptance_units==1 and interactive.publication_units==0,"interactive metrics count acceptance and publication separately")
	check(interactive.acceptance_us>=3000 and interactive.max_acceptance_unit_us>=3000 and interactive.over_budget_frames==1,"uninterruptible acceptance overrun is exposed rather than reported as a hard two millisecond limit")
	check(service._admission.count()==1 and service._admission.reserved_bytes==32,"completed result remains charged while its publication is incomplete")
	service.acceptance_delay_usec=0;f.document.delay_usec=3000
	service._process(0)
	check(f.document.calls.size()==1 and interactive.frames==2 and interactive.publication_units==1,"subsequent fresh slice starts exactly one slow instance without starvation")
	check(interactive.max_publication_unit_us>=3000 and interactive.over_budget_frames==2,"single publication duration and soft-budget overrun are measured")
	f.document.delay_usec=0;enable_cover(f)
	var covered_frames:=0
	while not service.is_complete() and covered_frames<6:
		service._process(0);covered_frames+=1
	var covered:Dictionary=service.profile.main_thread_budgets.covered_loading
	check(service.publication_budget==16000 and service.profile.main_thread_budget_mode=="covered_loading","real publication uses the larger budget only after the cover state qualifies")
	var completed_calls:Array=f.document.calls.duplicate();completed_calls.sort()
	check(service.is_complete() and completed_calls==["item_0","item_1","item_2","item_3","item_4","item_5"] and service.profile.instances==6 and covered.acceptance_units==0,"covered publication drains all private cursors with exactly one instance per UUID")
	check(interactive.frames==2 and covered.frames==covered_frames and covered.budget_us==16000,"interactive and covered metrics stay in separate buckets")
	check(service._admission.count()==0 and service._admission.reserved_bytes==0 and service._admission.byte_limit==byte_limit and service._admission.worker_limit==0,"larger time slice releases consumed work without changing concurrency or byte limits")
	f.host._transfer_pending=false;service._process(0)
	check(service.profile.main_thread_budget_mode=="interactive" and service.publication_budget==2000,"ending the cover returns the next processing call to the smaller budget")
	f.host.free()

	f=fixture(2);service=f.service;service._prepared_paths["reference:test"]=true;service._refresh_demanded()
	check(service._publication_ready().is_empty(),"a cached path cannot publish this unaccepted test job")
	# This section calls publication directly, outside _process's acceptance.
	service._jobs["reference:test"].accepted=true
	var failed_uuid:String=service._demanded[0].record.uuid
	f.document.failure=failed_uuid
	var work:Dictionary=service._publish_ready(Time.get_ticks_usec()-1000000)
	check(work.units==1 and service.instance_errors.has(failed_uuid) and service.profile.publication_units==1,"default expired-budget call still counts one failed real unit and preserves UUID isolation")
	work=service._publish_ready(Time.get_ticks_usec()-1000000)
	check(work.units==1 and f.document.calls.size()==2,"failure cannot prevent a healthy sibling starting under the same default budget")
	for i:int in 8:
		if service.profile.instances==1:break
		work=service._publish_ready(Time.get_ticks_usec()-1000000)
		check(work.units==1,"expired soft budget still advances one private spec unit")
	check(service.profile.instances==1 and f.document.calls.size()==2,"healthy sibling finishes exactly once across private spec slices")
	f.host.free();root.disable_3d=original_disable_3d
	print("DEFERRED_LOADING_BUDGET passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
