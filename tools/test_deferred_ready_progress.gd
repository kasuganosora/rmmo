extends SceneTree
## CPU-only scheduler regression. No Mesh, material, GLTF or GPU work.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
class Probe extends Deferred:
	var request_calls:=0
	func _reference_requests(path:String)->Array:
		request_calls+=1
		return super._reference_requests(path)
class Document extends RefCounted:
	var calls:Dictionary={}
	var failures:Dictionary={}
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		var holder:=Node3D.new()
		if failures.has(record.uuid):holder.set_meta("paint_error","fixture component error")
		return holder
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func fixture(member_count:int=2,props:bool=false,scene_root:Node=null)->Dictionary:
	var map:=Node3D.new();(scene_root if scene_root!=null else root).add_child(map);map.set_meta("stream_library",[])
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var service:=Probe.new();map.add_child(service);var document:=Document.new();service._doc=document
	for i in 10000:
		service.pending.append({"record":{"uuid":"waiting_%d"%i},"path":"reference:blocked","bounds":AABB(Vector3(i,0,0),Vector3.ONE)})
	service._reference_index={"groups":{},"extras":{"rmmo_records":[]}}
	for group in 2:
		var path:="reference:building:%d"%group;var group_id:="building:%d"%group;var ids:Array=[];var members:Array=[]
		for member in member_count:
			var uuid:="ready_%d_%d"%[group,member];ids.append(uuid)
			members.append(service._reference_index.extras.rmmo_records.size());service._reference_index.extras.rmmo_records.append({"uuid":uuid})
			service.pending.append({"record":{"uuid":uuid},"path":path,"native_reference":true,"group_id":group_id,"bounds":AABB(Vector3(10100+group,0,0),Vector3.ONE)})
		service._reference_index.groups[group_id]={"members":members}
		service._prepared_paths[path]=true
		service._admission.reserve(path,{"estimated_bytes":1,"exclusive":false})
		service._jobs[path]={"accepted":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":ids}
	if props:
		var ids:Array=[]
		for i in member_count:
			var uuid:="prop_%d"%i;ids.append(uuid)
			service.pending.append({"record":{"uuid":uuid},"path":"reference:props","native_reference":true,"bounds":AABB(Vector3(10500,0,0),Vector3.ONE)})
		service._prepared_paths["reference:props"]=true
		service._admission.worker_limit=3
		service._admission.reserve("reference:props",{"estimated_bytes":1,"exclusive":false})
		service._jobs["reference:props"]={"accepted":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":ids}
	# Ready jobs own their ledger slots. Prevent this pure CPU test from
	# starting imports after those slots are released; publication is unchanged.
	service._admission.worker_limit=0
	service.activate(map);service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(12000,2,2)));service.set_process(false)
	service._refresh_demanded()
	return {"map":map,"service":service,"document":document}
func run()->void:
	var f:=fixture();var service:Node=f.service
	check(service._jobs.size()==2 and service._demanded.size()==10004,"two ready building jobs occupy admission behind ten thousand higher-ranked unready instances")
	# An explicitly exhausted entry budget makes the fairness assertion
	# deterministic, independent of machine speed or timing of the blocked scan.
	service._publish_ready(Time.get_ticks_usec()-1000000)
	check(f.document.calls.size()==1 and service.pending.size()==10004,"expired soft budget still stages one real component without publishing a partial building")
	for i in 3:service._publish_ready(Time.get_ticks_usec()-1000000)
	check(f.document.calls.size()==4 and f.document.calls.values().all(func(value):return value==1),"subsequent frames advance all remaining ready components exactly once")
	check(service.pending.size()==10000 and int(service.profile.instances)==4,"both complete groups publish atomically despite the blocked high-priority prefix")
	service._process(0)
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0,"completed groups release their admission slots so waiting preparation can advance")
	check(int(service.profile.demand_refreshes)==1 and service._demanded.size()==10000 and service._demanded_rank.size()==10000 and not service._demanded_by_path.has("reference:building:0"),"pure publication incrementally removes completed demands without rebuilding or sorting live tickets")
	check(service.profile.has("ready_scan_us") and int(service.profile.publication_units)==4,"ready scanning and actual publication progress are measured separately")
	service.set_demand("test",AABB(Vector3(-1,-1,-1),Vector3(500,2,2)));service._refresh_demanded()
	check(int(service.profile.demand_refreshes)==2 and service._demanded.size()<10000 and service.profile.has("max_demand_refresh_us"),"a real changed demand still rebuilds ranks and reports its refresh cost")
	f.map.free()
	f=fixture();service=f.service;f.document.failures.ready_0_1=true
	for i in 4:service._publish_ready(Time.get_ticks_usec()-1000000)
	service._process(0)
	check(service.instance_errors.size()==2 and int(service.profile.instances)==2 and service.pending.size()==10002,"one malformed component prevents its whole group while an independent ready group publishes")
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0,"failed partial staging releases specs and admission instead of holding an occupied slot")
	f.map.free()
	f=fixture();service=f.service
	# Hold two accepted jobs without publishing while testing the actual refill
	# loop. Their publication IDs remain demanded, so neither slot is released.
	service._prepared_paths.clear();service._admission.worker_limit=2
	for i in 4:service._process(0)
	check(service._jobs.size()==2 and service._admission.count()==2 and service.request_calls==0,"full admission skips every waiting reference-closure construction")
	check(service.profile.has("dispatch_scan_us") and service.profile.has("max_dispatch_scan_us"),"dispatch overhead has separate cumulative and peak diagnostics")
	f.map.free()
	# Independent objects get turns within a long building, while building
	# order, whole-group publication and one-time construction stay intact.
	f=fixture(12,true);service=f.service
	for i in 8:service._publish_ready(Time.get_ticks_usec()-1000000)
	check(f.document.calls.size()==8 and f.document.calls.keys().filter(func(id):return id.begins_with("ready_0_")).size()==4 and f.document.calls.keys().filter(func(id):return id.begins_with("prop_")).size()==4,"independent objects receive bounded turns within a long prepared building")
	check(service.pending.size()==10032 and int(service.profile.instances)==4 and not f.document.calls.keys().any(func(id):return id.begins_with("ready_1_")),"independent publication preserves whole-building staging and original house order")
	for i in 28:service._publish_ready(Time.get_ticks_usec()-1000000)
	check(service.pending.size()==10000 and int(service.profile.instances)==36 and f.document.calls.values().all(func(value):return value==1),"ordered buildings finish atomically alongside independent props with one construction each")
	service._process(0)
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0,"interleaved completion retires every prepared job and reservation")
	f.map.free()
	print("DEFERRED_READY_PROGRESS passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
