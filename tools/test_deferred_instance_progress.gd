extends "res://tools/test_deferred_collision_publication.gd"
## Real private Node/spec cursors; injected dependencies never sleep or import.
class ProgressQueue extends Deferred:
	var missing_support:Dictionary={}
	func _runtime_supports_ready(uuid:String)->bool:return not missing_support.has(uuid)
class GraphDocument extends Document:
	var owners:Dictionary={}
	func _mesh(record:Dictionary,_effects:bool=true,_timings:Variant=null)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		var holder:=Node3D.new()
		# More than one mandatory cursor step, independently of machine speed.
		for i:int in 32:holder.add_child(Node3D.new())
		var owner:=RefCounted.new();holder.set_meta("probe_owner",owner);owners[record.uuid]=weakref(owner)
		if after_instance.is_valid():after_instance.call(record.uuid)
		return holder
func fixture(rows:Array)->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var store:=Store.new();map.add_child(store)
	var document:=GraphDocument.new();var queue:=ProgressQueue.new();queue._doc=document;queue.pending=rows
	map.add_child(queue);queue.activate(map);queue._admission.worker_limit=8
	var paths:Dictionary={}
	for row:Dictionary in rows:
		if not paths.has(row.path):paths[row.path]=[]
		paths[row.path].append(row.record.uuid)
	for path:String in paths:
		queue._admission.reserve(path,{"estimated_bytes":65536,"exclusive":false});queue._admission.park(path)
		queue._jobs[path]={"accepted":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":paths[path]};queue._prepared_paths[path]=true
	queue._admission.worker_limit=0
	queue.set_demand("player",AABB(Vector3(-100,-1,-1),Vector3(200,4,4)),10);queue._refresh_demanded();queue.set_process(false)
	return {"map":map,"queue":queue,"document":document,"store":store}
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	for dependency:String in ["collision","support"]:partial_progress(dependency)
	packet_dependencies();cancel_partial();failed_partial();workspace_pressure();invalid_staged_packet();selection_reservation();failed_last_group_member()
	reuse_workspace_bound(524288,0,"shared model");reuse_workspace_bound(131072,786432,"direct instance")
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_INSTANCE_PROGRESS passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
func partial_progress(dependency:String)->void:
	var a:=item("a");var b:=item("b","reference:shared",10)
	var f:=fixture([a,b]);var queue:Node=f.queue
	queue._publish_ready(Time.get_ticks_usec()-1000000,1)
	check(queue._jobs[a.path].has("instance_preparation") and f.document.calls.get("a",0)==1,"%s: starts a real incomplete private graph"%dependency)
	if dependency=="collision":f.store.states.a={"owned":true,"pending":true}
	else:queue.missing_support.a=true
	# Demand refresh must not lose the old cursor or hide the new urgent sibling.
	queue.set_demand("urgent",b.bounds,-2);queue._refresh_demanded();queue.set_process(false)
	for i:int in 8:pump(queue)
	check(b.get("published",false) and not a.get("published",false),"%s: healthy same-model sibling publishes while started predecessor waits"%dependency)
	check(f.document.calls.get("a",0)==1 and f.document.calls.get("b",0)==1,"%s: no instance is reconstructed or bound to the other's UUID"%dependency)
	check(queue._jobs[a.path].get("collision_staged",{}).has("a") and not queue._jobs[a.path].has("instance_preparation"),"%s: completed output owns the wait; construction workspace is free"%dependency)
	check(queue._admission.reserved_bytes==131072 and queue._jobs.size()==1 and queue._admission.count()==1,"%s: extra workspace explicitly charged to same lease without widening job cap"%dependency)
	check(f.document.owners.a.get_ref()==null,"%s: intermediate graph freed while final output waits"%dependency)
	f.store.states.clear();queue.missing_support.clear()
	for i:int in 8:pump(queue)
	queue._process(0)
	check(queue.is_complete() and queue._admission.reserved_bytes==0 and queue._jobs.is_empty(),"%s: resumed output finishes once and releases all ownership"%dependency)
	check(f.document.calls=={"a":1,"b":1} and int(queue.profile.instances)==2,"%s: exact final workload"%dependency)
	f.map.free()
func packet_dependencies()->void:
	var a:=item("group_a");var b:=item("group_b","reference:shared",1);var c:=item("healthy","reference:shared",2)
	var f:=fixture([a,b,c]);var queue:Node=f.queue
	queue.missing_support.group_b=true
	var committed:bool=queue._publish_items([a,b],[])
	check(not committed and not a.get("published",false) and not b.get("published",false),"atomic packet checks every member's support at commit")
	for i:int in 8:pump(queue)
	check(c.get("published",false) and not a.get("published",false) and not b.get("published",false),"ready packet representative cannot hide its blocked member or starve a healthy sibling")
	check(not f.document.calls.has("group_a") and not f.document.calls.has("group_b"),"retained group output never re-instantiates a member")
	queue.missing_support.clear();f.store.states.group_b={"owned":true,"pending":true}
	for i:int in 4:pump(queue)
	check(not a.get("published",false) and not b.get("published",false),"atomic packet also checks nonrepresentative collision ownership")
	f.store.states.clear()
	for i:int in 4:pump(queue)
	queue._process(0)
	check(a.get("published",false) and b.get("published",false) and queue.is_complete() and queue._admission.reserved_bytes==0,"entire packet commits only after all dependencies are ready")
	f.map.free()
func cancel_partial()->void:
	var a:=item("cancel");var b:=item("survivor","reference:shared",10)
	var f:=fixture([a,b]);var queue:Node=f.queue
	queue._publish_ready(Time.get_ticks_usec()-1000000,1);queue.missing_support.cancel=true
	queue.release_demand("player");queue.set_demand("only_b",b.bounds,0);queue._refresh_demanded();queue.set_process(false)
	for i:int in 8:pump(queue)
	check(f.document.owners.cancel.get_ref()==null and b.get("published",false) and not a.get("published",false),"lost demand destroys partial graph once and lets same-model sibling finish")
	queue.shutdown();check(queue._admission.reserved_bytes==0 and queue._jobs.is_empty(),"shutdown keeps all private owners under their lease until disposed")
	f.map.free()
func failed_partial()->void:
	var a:=item("fail");var b:=item("survivor","reference:shared",10)
	var f:=fixture([a,b]);var queue:Node=f.queue
	queue._publish_ready(Time.get_ticks_usec()-1000000,1);f.store.states.fail={"owned":true,"pending":false,"error":"fixture_failed"}
	for i:int in 8:pump(queue)
	queue._process(0)
	check(queue.instance_errors.has("fail") and not a.get("published",false) and b.get("published",false),"terminal dependency failure cancels only the failed instance")
	check(f.document.owners.fail.get_ref()==null and queue._admission.reserved_bytes==0,"failed private graph and lease are fully released")
	f.map.free()
func workspace_pressure()->void:
	var a:=item("held");var b:=item("sibling","reference:shared",10);var c:=item("other","reference:other",20)
	var f:=fixture([a,b,c]);var queue:Node=f.queue
	queue._publish_ready(Time.get_ticks_usec()-1000000,1);queue.missing_support.held=true
	queue._admission.byte_limit=131072 # Exactly the original two admitted jobs.
	for i:int in 8:pump(queue)
	check(c.get("published",false) and not b.get("published",false) and f.document.calls.get("sibling",0)==0,"byte pressure blocks only an unreserved replacement workspace; independent job progresses")
	check(queue._admission.reserved_bytes==131072 and int(queue.profile.get("publication_workspace_waits",0))>0,"blocked output never allocates beyond the original byte cap")
	queue._process(0) # Retire c, leaving enough room for the sibling workspace.
	for i:int in 8:pump(queue)
	check(b.get("published",false) and not a.get("published",false) and queue._admission.reserved_bytes==131072,"released bytes reopen same-model progress without enlarging any limit")
	queue.release_demand("player");queue._refresh_demanded();queue.set_process(false)
	queue._publication_ready()
	check(queue._jobs[a.path].get("collision_staged",{}).is_empty() and queue._admission.reserved_bytes==65536,"lost staged demand releases retained output and its extra workspace promptly")
	queue.shutdown();check(queue._admission.reserved_bytes==0,"pressure and cancellation leave zero byte ownership")
	f.map.free()
func invalid_staged_packet()->void:
	var a:=item("group_a");var b:=item("group_b","reference:shared",1);var c:=item("healthy","reference:shared",2)
	var f:=fixture([a,b,c]);var queue:Node=f.queue
	queue.missing_support.group_a=true
	queue._publish_items([a,b],[])
	f.store.states.group_b={"owned":true,"pending":false,"error":"fixture_failed"}
	for i:int in 8:pump(queue)
	check(queue.instance_errors.has("group_a") and queue.instance_errors.has("group_b") and c.get("published",false),"later member error is discovered even while the representative waits; atomic failure does not block siblings")
	check(queue._jobs[a.path].get("collision_staged",{}).is_empty(),"atomic failure clears every staged alias")
	queue._process(0);check(queue._admission.reserved_bytes==0,"failed packet and healthy sibling release their single lease")
	f.map.free()
func selection_reservation()->void:
	var a:=item("held_a","reference:a");var b:=item("ready_a","reference:a",1)
	var c:=item("held_b","reference:b",10);var d:=item("ready_b","reference:b",11)
	var f:=fixture([a,b,c,d]);var queue:Node=f.queue
	queue.missing_support.held_a=true;queue.missing_support.held_b=true
	queue._publish_items([a],[]);queue._publish_items([c],[])
	queue._admission.byte_limit=196608 # Two leases plus ONE replacement.
	var heads:Array=queue._publication_ready()
	check(heads.size()==2 and queue._admission.reserved_bytes==131072,"readiness considers both paths without reserving bytes for unselected work")
	queue._publish_ready(Time.get_ticks_usec()-1000000,1)
	check(f.document.calls.size()==1 and queue._admission.reserved_bytes==196608 and int(queue.profile.publication_workspace_reservations)==1,"only the chosen instance reserves the available replacement workspace")
	queue.shutdown();check(queue._admission.reserved_bytes==0,"shutdown releases a retained packet plus a partially built replacement exactly once")
	f.map.free()
func failed_last_group_member()->void:
	var a:=item("group_a");var b:=item("group_b","reference:shared",1);var c:=item("healthy","reference:shared",10)
	a.group_id="building:fixture";b.group_id=a.group_id
	var f:=fixture([a,b,c]);var queue:Node=f.queue
	queue._reference_index={"groups":{a.group_id:{"members":[0,1]}},"extras":{"rmmo_records":[a.record,b.record]}}
	f.store.states.group_b={"owned":true,"pending":true}
	for i:int in 8:pump(queue)
	var job:Dictionary=queue._jobs[a.path]
	check(job.get("staged",{}).has("group_a") and not a.get("published",false),"group prefix is privately staged while final member waits")
	f.store.states.group_b={"owned":true,"pending":false,"error":"fixture_failed"}
	for i:int in 8:pump(queue)
	check(queue.instance_errors.has("group_a") and queue.instance_errors.has("group_b") and job.get("staged",{}).is_empty(),"last member failure clears an incomplete group without another component arrival")
	queue._process(0)
	check(c.get("published",false) and queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"failed incomplete group cannot pin a consumed result or admission slot")
	check(f.document.calls=={"group_a":1,"healthy":1},"aborting incomplete group performs no repeated or failed-member construction")
	f.map.free()

func reuse_workspace_bound(model_bound:int,instance_bound:int,label:String)->void:
	# Only scheduling metadata is synthetic. Actual Node/spec cursors and the
	# production dependency, selection, reservation and release paths are used.
	var a:=item("held");var b:=item("sibling","reference:shared",10)
	var f:=fixture([a,b]);var queue:Node=f.queue
	var job:Dictionary=queue._jobs[a.path]
	job.estimate={"stage":"reuse_reference","shared_model_estimate_bytes":model_bound}
	var template_owner:=PackedScene.new()
	template_owner.set_meta(preload("res://scripts/world3d/asset_spec_template.gd").META,{"instance_bytes":instance_bound})
	job.publication_template_owner=template_owner
	var base:=65536
	var retained_bound:=maxi(model_bound,instance_bound+var_to_bytes(a.record).size()*8)
	var replacement_bound:=maxi(base,retained_bound)
	queue._publish_ready(Time.get_ticks_usec()-1000000,1);queue.missing_support.held=true
	queue._admission.byte_limit=base+replacement_bound-1
	for i:int in 8:pump(queue)
	check(job.get("collision_staged",{}).has("held") and not b.get("published",false) and not f.document.calls.has("sibling"),"%s: smaller reuse lease cannot stand in for the retained instance bound"%label)
	check(queue._admission.reserved_bytes==base and int(queue.profile.get("publication_workspace_waits",0))>0,"%s: insufficient instance bytes allocate no replacement graph or extra lease"%label)
	var packet:Dictionary=job.get("collision_staged",{}).get("held",{})
	check(int(packet.get("publication_workspace_bound",0))==retained_bound,"%s: packet caches the model/template/record bound"%label)
	for i:int in 16:queue._publication_ready()
	check(queue._admission.reserved_bytes==base and int(packet.get("publication_workspace_bound",0))==retained_bound,"%s: repeated readiness preserves the cached bound without speculative reservations"%label)
	queue._admission.byte_limit=base+replacement_bound
	for i:int in 8:pump(queue)
	check(b.get("published",false) and not a.get("published",false) and f.document.calls=={"held":1,"sibling":1},"%s: exact additional bound permits sibling progress without reconstruction"%label)
	check(queue._admission.reserved_bytes==base+replacement_bound and int(packet.get("workspace_charge",0))==replacement_bound and queue._admission.count()==1 and queue._admission.active_workers()==0,"%s: complete instance estimate stays on the same parked lease"%label)
	queue.release_demand("player");queue._refresh_demanded();queue.set_process(false)
	queue._publication_ready()
	check(job.get("publication_packets",{}).is_empty() and job.get("collision_staged",{}).is_empty() and queue._admission.reserved_bytes==base,"%s: pruning repays the larger extra bound exactly once"%label)
	queue.shutdown();check(queue._admission.reserved_bytes==0,"%s: final discard releases the original reuse lease"%label)
	f.map.free()
