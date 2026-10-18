extends "res://tools/test_deferred_native_preparation_gpu.gd"
const ModelOwners=preload("res://scripts/world3d/model_resource_owners.gd")
const Retirement=preload("res://scripts/world3d/resource_retirement.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
class CancelAt extends RefCounted:
	var calls:=0
	var limit:=0
	func is_cancelled()->bool:
		calls+=1;return calls>=limit
func cancelled_raw(path:String,digest:String,limit:int)->void:
	var token:=CancelAt.new();token.limit=limit
	var worker:=Thread.new();check(worker.start(Deferred.prepare_scene.bind(path,digest,token,{},true,content_root,true,2,true))==OK,"post-allocation cancellation worker starts")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.get("cancelled",false) and packet.get("resource_owners") is ModelOwners,"post-allocation cancellation returns explicit importer owners at gate %d"%limit)
	var owners:ModelOwners=packet.get("resource_owners")
	if owners==null:return
	var watches:Array=[weakref(owners.document),weakref(owners.state)]
	if is_instance_valid(packet.get("scene")):watches.append(weakref(packet.scene))
	check(is_instance_valid(packet.get("scene"))==(limit==5),"cancellation exercises parsed state and generated-scene branches")
	var ledger:=Admission.new();ledger.reserve("cancel",{"estimated_bytes":4096,"exclusive":false})
	Retirement.defer_model_packet(packet,Callable(ledger,"release").bind("cancel"),ledger);Drainer.dispose_result(packet);owners=null
	var service:Node=root.get_node(Retirement.NODE_NAME);var deadline:=Time.get_ticks_msec()+15000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	Drainer.synchronize_transfer();await process_frame
	check(ledger.reserved_bytes==0 and service.pending.is_empty() and watches.all(func(w):return w.get_ref()==null),"post-allocation cancellation drains every importer/scene owner before completion")
func test_raw_root_rejection(path:String,digest:String)->void:
	await super.test_raw_root_rejection(path,digest)
	var token:=Drainer.CancelToken.new()
	var worker:=Thread.new()
	check(worker.start(Deferred.prepare_scene.bind(path,digest,token,{},true,content_root,true,2,true))==OK,"actual raw model worker starts with typed ownership")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.get("error", "failure")=="" and packet.get("resource_owners") is ModelOwners and not packet.has("retained_resources"),"actual producer emits typed handoff without nested retained containers")
	var owners:ModelOwners=packet.get("resource_owners")
	if owners==null:return
	check(owners.document!=null and owners.state!=null and owners.packed==packet.get("packed") and not owners.visuals.is_empty() and not packet.has("scene"),"worker fields explicitly retain parser, template and visual dependencies")
	var watches:Array=[weakref(owners.document),weakref(owners.state),weakref(owners.packed)]
	for resource:Resource in owners.visuals:watches.append(weakref(resource))
	var author:Dictionary={"uuid":"still-borrowed","nested":[1,2,3]};packet.records=[author]
	var ledger:=Admission.new();ledger.reserve("raw",{"estimated_bytes":8192,"exclusive":false})
	check(Retirement.defer_model_packet(packet,Callable(ledger,"release").bind("raw"),ledger),"actual producer transfers ownership to retirement")
	Drainer.dispose_result(packet);owners=null
	var service:Node=root.get_node(Retirement.NODE_NAME)
	var deadline:=Time.get_ticks_msec()+15000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	Drainer.synchronize_transfer();await process_frame
	for w:WeakRef in watches:
		if w.get_ref()!=null:print("TYPED_OWNER_ALIVE ",w.get_ref().get_class()," ",w.get_ref().get_instance_id())
	print("TYPED_OWNER_PENDING ",service.pending.size()," bytes=",ledger.reserved_bytes)
	check(service.pending.is_empty() and ledger.reserved_bytes==0 and watches.all(func(w):return w.get_ref()==null),"actual raw GPU/parser/template owners fully release and return admission")
	check(author=={"uuid":"still-borrowed","nested":[1,2,3]},"actual producer disposal preserves borrowed records")
	token.cancel();packet=Deferred.prepare_scene(path,digest,token,{},false,content_root,true)
	check(packet.get("cancelled",false) and not packet.has("resource_owners"),"pre-cancelled model creates no resource owner")

	await cancelled_raw(path,digest,4)
	await cancelled_raw(path,digest,5)
