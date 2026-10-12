extends SceneTree
## CPU-only scheduler/API regression; these doubles do not grant source or
## physics authority. Real source/Store handoff has its separate GPU fixture.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Store extends Node:
	var states:Dictionary={}
	var append_pending:=false
	func _init()->void:name="CollisionInstanceResidency"
	func has_instances()->bool:return not states.is_empty()
	func publication_status(uuid:String)->Dictionary:return states.get(uuid,{})
	func preflight_promotion(_specs:Array)->Dictionary:
		if append_pending:return {"ok":false,"error":"promotion_collision_pending"}
		return {"ok":true,"token":RefCounted.new()}
	func commit_promotion(_token:RefCounted)->void:pass
class Document extends RefCounted:
	var calls:Dictionary={}
	var after_instance:Callable
	func _mesh(record:Dictionary)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		if after_instance.is_valid():after_instance.call(record.uuid)
		return Node3D.new()
class CollisionLoader extends Node:
	var states:Dictionary={}
	var tickets:Dictionary={}
	var requests:=0
	var history:Array=[]
	func _init()->void:name="CollisionDependencyLoader"
	func request(entries:Array,_priority:int=0,id:String="default")->Dictionary:
		requests+=1;tickets[id]=entries.duplicate(true);history.append(tickets.keys());return {"ok":true}
	func release_request(id:String)->void:tickets.erase(id);history.append(tickets.keys())
	func coverage(entries:Array)->Dictionary:
		for entry:Dictionary in entries:
			if states.get(entry.compact_record.uuid,{})!=entry:return {"ok":false,"reason":"pending"}
		return {"ok":true}
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failures+=1
func item(uuid:String,path:String="reference:shared",x:float=0)->Dictionary:
	return {"record":{"uuid":uuid},"path":path,"bounds":AABB(Vector3(x,0,0),Vector3.ONE),"native_reference":true}
func fixture(rows:Array)->Dictionary:
	var map:=Node3D.new();root.add_child(map);map.set_meta("stream_library",[]);map.set_meta("extras",{"rmmo_records":[]})
	var index:=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var store:=Store.new();map.add_child(store)
	var document:=Document.new();var queue:=Deferred.new();queue._doc=document;queue.pending=rows
	map.add_child(queue);queue.activate(map);queue._admission.worker_limit=0
	var paths:Dictionary={}
	for row:Dictionary in rows:
		if not paths.has(row.path):paths[row.path]=[]
		paths[row.path].append(row.record.uuid)
	for path:String in paths:
		queue._admission.worker_limit=8;queue._admission.reserve(path,{"estimated_bytes":8,"exclusive":false});queue._admission.park(path)
		queue._jobs[path]={"accepted":true,"result":{},"token":Deferred.Drainer.CancelToken.new(),"publication_ids":paths[path]};queue._prepared_paths[path]=true
	queue._admission.worker_limit=0
	queue.set_demand("player",AABB(Vector3(-1,-1,-1),Vector3(1000,4,4)),10);queue._refresh_demanded();queue.set_process(false)
	return {"map":map,"queue":queue,"document":document,"store":store}
func pump(queue:Node)->void:queue._publish_ready(Time.get_ticks_usec()-1000000,1)
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	blocked_and_cancelled();bounded_scan();late_installation();invalid_collision();coverage_and_scope()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_COLLISION_PUBLICATION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
func blocked_and_cancelled()->void:
	var f:=fixture([item("waiting"),item("sibling","reference:shared",1),item("other","reference:other",2)])
	var queue:Node=f.queue
	f.store.states.waiting={"owned":true,"pending":true,"error":""}
	for i in 4:pump(queue)
	check(f.document.calls.get("waiting",0)==0 and f.document.calls.get("sibling",0)==1 and f.document.calls.get("other",0)==1,"pending collision blocks no instantiation and does not starve same-model or independent ready instances")
	check(queue._publication_queues["reference:shared"].cursor==0,"waiting head keeps its consumption cursor")
	queue._process(0)
	check(queue._jobs.size()==1 and queue._admission.reserved_bytes==8 and queue.instance_errors.is_empty(),"waiting instance retains its admitted job while completed independent output releases")
	f.store.states.clear();pump(queue);queue._process(0)
	check(f.document.calls.get("waiting",0)==1 and queue.is_complete() and queue._admission.reserved_bytes==0,"cancelled collision optimization resumes the ordinary path exactly once and releases the last lease")
	f.map.free()
func bounded_scan()->void:
	var rows:Array=[]
	for i in 140:rows.append(item("wait%d"%i,"reference:shared",float(i)))
	rows.append(item("tail","reference:shared",140))
	var f:=fixture(rows);var queue:Node=f.queue
	for i in 140:f.store.states["wait%d"%i]={"owned":true,"pending":true,"error":""}
	pump(queue)
	check(f.document.calls.is_empty() and queue._publication_queues["reference:shared"].scan<=64,"blocked same-path prefix is examined in a bounded scan")
	for i in 3:pump(queue)
	check(f.document.calls.get("tail",0)==1 and f.document.calls.size()==1,"saved scan position eventually reaches ready work beyond 140 blocked siblings")
	f.store.states.wait0={"owned":true,"pending":false,"error":""}
	for i in 4:pump(queue)
	check(f.document.calls.get("wait0",0)==1,"round-robin readiness revisits the formerly blocked earliest instance")
	queue.shutdown();check(queue._admission.reserved_bytes==0 and queue._jobs.is_empty(),"shutdown releases blocked jobs and their budget")
	f.map.free()
func late_installation()->void:
	var f:=fixture([item("racing")]);var queue:Node=f.queue
	var store:Node=f.store
	f.document.after_instance=func(uuid:String)->void:
		store.states[uuid]={"owned":true,"pending":true,"error":""};store.append_pending=true
	pump(queue)
	check(f.document.calls.get("racing",0)==1 and queue.instance_errors.is_empty() and queue._jobs["reference:shared"].collision_staged.has("racing"),"late collision installation retains built specs instead of making a permanent instance error")
	for i in 3:pump(queue)
	check(f.document.calls.get("racing",0)==1 and queue._admission.reserved_bytes==8,"late pending publication neither reinstantiates nor drops its reservation")
	f.store.states.racing.pending=false;f.store.append_pending=false
	pump(queue);queue._process(0)
	check(queue.is_complete() and f.document.calls.racing==1 and queue._admission.reserved_bytes==0,"completed collision retries retained publication without reconstructing the model")
	f.map.free()
	f=fixture([item("discard")]);queue=f.queue
	store=f.store
	f.document.after_instance=func(uuid:String)->void:
		store.states[uuid]={"owned":true,"pending":true,"error":""};store.append_pending=true
	pump(queue)
	var retained:=RefCounted.new();var observed:WeakRef=weakref(retained)
	queue._jobs["reference:shared"].collision_staged.discard.owner=retained;retained=null
	queue._discard_job("reference:shared")
	check(observed.get_ref()==null and queue._admission.reserved_bytes==0,"discard clears retained collision-publication resources before returning job admission")
	f.map.free()
func coverage_and_scope()->void:
	var a:=item("a","model.glb");a.native_reference=false
	a.reference_entry={"record_index":0,"asset_path":"model.glb","compact_record":{"uuid":"a","rmmo_ref":{"sha256":"a".repeat(64)}}}
	var b:=item("native","reference:native",20)
	var camera:=item("camera","camera.glb",10);camera.native_reference=false
	camera.reference_entry={"record_index":1,"asset_path":"camera.glb","compact_record":{"uuid":"camera","rmmo_ref":{"sha256":"c".repeat(64)}}}
	var far:=item("far","far.glb",100);far.native_reference=false
	far.reference_entry={"record_index":2,"asset_path":"far.glb","compact_record":{"uuid":"far","rmmo_ref":{"sha256":"d".repeat(64)}}}
	var f:=fixture([a,b,camera,far]);var queue:Node=f.queue
	var loader:=CollisionLoader.new();f.map.add_child(loader)
	var old:=Deferred.collision_first_enabled;Deferred.collision_first_enabled=true
	var near:=AABB(Vector3(-1,-1,-1),Vector3(3,3,3))
	check(not queue.ensure_collision(near,"physics") and loader.tickets.physics==[a.reference_entry],"collision request contains exact pending author entry and waits for verified coverage")
	loader.states.a={"record_index":0,"asset_path":"model.glb","compact_record":{"uuid":"a","rmmo_ref":{"sha256":"b".repeat(64)}}}
	check(not queue.ensure_collision(near,"physics"),"same UUID with stale reference identity cannot stand in for coverage")
	loader.states.a=a.reference_entry.duplicate(true)
	check(queue.ensure_collision(near,"physics") and not queue.ensure_geometry(near,"nav"),"exact collision coverage can unblock physics while navigation still requires visual geometry")
	var revision:int=queue._demand_revision;var held:Dictionary=queue._demands.duplicate(true)
	check(not queue.geometry_published(near) and queue._demand_revision==revision and queue._demands==held,"narrow visual readiness query never modifies wider demand tickets")
	check(queue.ensure_collision(near,"player_collision") and loader.tickets.player_collision==[a.reference_entry,camera.reference_entry],"moving request prioritizes exact foot before camera margin without waiting for unseen surrounding visuals")
	queue.release_demand("player_collision");queue.release_demand("physics")
	queue.set_demand_scope(["entry_safety"]);queue._entry_loading={"previous_scope":[]}
	queue.ensure_collision(AABB(Vector3(-1,-1,-1),Vector3(14,3,3)),"entry_safety");loader.history.clear()
	queue.end_entry_loading(near)
	check(loader.history.size()==2 and loader.history[0].has("entry_safety") and loader.history[0].has("player_collision") and loader.history[1]==["player_collision"],"entry collision ticket is replaced atomically by player and camera holding before release")
	queue.release_demand("player_collision")
	queue.set_demand_scope(["entry_safety"]);queue._entry_loading={"previous_scope":["nav"]}
	queue.ensure_collision(AABB(Vector3(-1,-1,-1),Vector3(14,3,3)),"entry_safety");loader.history.clear()
	queue.end_entry_loading(near)
	check(queue.get_demand_scope().has("nav") and queue.get_demand_scope().has("player_collision") and not queue.get_demand_scope().has("entry_safety"),"nonempty prior scope explicitly admits the new player lease while preserving existing navigation scope")
	check(loader.history.size()==2 and loader.history[0].has("entry_safety") and loader.history[0].has("player_collision") and loader.history[1]==["player_collision"],"nonempty-scope handoff also retains old camera bodies until the replacement ticket exists")
	queue.set_demand_scope([])
	check(not queue.ensure_collision(AABB(Vector3(-1,-1,-1),Vector3(24,3,3)),"wide"),"unsupported native dependencies still require normal publication alongside covered assets")
	queue.set_demand_scope(["nav"])
	check(loader.tickets.is_empty() and not queue.ensure_collision(near,"physics") and loader.tickets.is_empty(),"scope change withdraws old collision tickets and excluded demand cannot recreate them")
	queue.set_demand_scope([]);queue.ensure_collision(near,"physics");queue.release_demand("physics")
	check(not loader.tickets.has("physics"),"release_demand withdraws its exact collision ticket")
	queue.ensure_collision(near,"physics");a.published=true
	check(queue.ensure_collision(near,"physics") and not loader.tickets.has("physics"),"render-first completion no longer retains a collision preparation request")
	check(queue.ensure_collision(near,"player_collision") and loader.tickets.player_collision==[camera.reference_entry],"published foot still holds unpromoted camera-area collision after entry ticket release")
	check(queue.ensure_collision(AABB(Vector3(29,-1,-1),Vector3(3,3,3)),"player_collision") and not loader.tickets.has("player_collision"),"moving beyond the camera hold withdraws obsolete collision instances without retaining the distant map")
	Deferred.collision_first_enabled=old;f.map.free()

func invalid_collision()->void:
	var f:=fixture([item("invalid"),item("healthy","reference:healthy",1)]);var queue:Node=f.queue
	f.store.states.invalid={"owned":true,"pending":false,"error":"collision_invalidated"}
	pump(queue);queue._process(0)
	check(queue.instance_errors.has("invalid") and not f.document.calls.has("invalid") and f.document.calls.get("healthy",0)==1,"invalidated owned collision remains a real error while an independent visual publishes")
	check(queue._jobs.is_empty() and queue._admission.reserved_bytes==0,"terminal collision publication failure retires prepared job ownership and reservation")
	f.map.free()
