extends SceneTree
## Wiring regression only. Loader's real worker/proof/budget/physics lifecycle
## is covered by test_collision_dependency_loader; these doubles grant no gate.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const MapLoader=preload("res://scripts/world3d/map_loader.gd")
const Proof=preload("res://scripts/world3d/dependency_index_proof.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
class Service extends Node:
	var context:Dictionary={}
	var tickets:Dictionary={}
	var phase:="new"
	var pumps:=0
	var adopts:=0
	var retained:RefCounted
	var reject_handoff:=false
	var reject_adopt:=false
	func _init()->void:name="CollisionDependencyLoader";set_process(false)
	func begin_prefetch(owner:Node,index:Dictionary,path:String,content:String,proof:RefCounted)->Dictionary:
		context={"index":index,"path":path,"root":content,"proof":proof};phase="prefetch"
		return {"ok":get_parent()==owner and is_inside_tree()}
	func matches_context(index:Dictionary,path:String,content:String,proof:RefCounted)->bool:
		return is_same(index,context.index) and path==context.path and content==context.root and is_same(proof,context.proof)
	func request(entries:Array,_priority:int=0,id:String="default")->Dictionary:
		tickets[id]=entries.duplicate(true);return {"ok":true}
	func release_request(id:String)->void:tickets.erase(id)
	func pump_prefetch()->void:
		if phase!="prefetch":return
		pumps+=1
		if retained==null:retained=RefCounted.new()
	func handoff(map:Node,_epoch:int)->Dictionary:
		if reject_handoff:return {"ok":false,"error":"fixture_handoff_failure"}
		phase="handoff";reparent(map);return {"ok":true}
	func adopt(map:Node,_epoch:int)->Dictionary:
		if reject_adopt:return {"ok":false,"error":"fixture_adoption_failure"}
		if not map.is_inside_tree() or get_parent()!=map:return {"ok":false,"error":"fixture_tree"}
		adopts+=1;phase="adopted";var store:=Node.new();store.name="CollisionInstanceResidency";map.add_child(store)
		return {"ok":true}
	func cancel(_reason:String)->void:phase="cancelled";retained=null;tickets.clear()
	func coverage(_entries:Array)->Dictionary:return {"ok":false}
class Queue extends Deferred:
	var created:Service
	func _new_collision_service()->Node:created=Service.new();return created
	func _dispatch_jobs(_tree:SceneTree,_prefetch_only:bool=false)->void:pass
class Loader extends MapLoader:
	var test_queue:Queue
	func _new_deferred()->Node:return test_queue
var passed:=0
var failures:=0
const CLIP=AABB(Vector3(-4,-100,-4),Vector3(8,200,8))
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func fixture()->Dictionary:
	var loader:=Loader.new();root.add_child(loader)
	var queue:=Queue.new();var rows:Array=[];var items:Array=[]
	for i in 5:
		var uuid:="item"+str(i);var group:String="building:test" if i==2 else ""
		var bounds:=AABB(Vector3(100 if i==1 else 0,0,0),Vector3.ONE)
		var entry:Dictionary={"record_index":i,"compact_record":{"uuid":uuid},"asset_path":"model.glb","bounds":bounds,"group_id":group}
		rows.append({"reason":"native_road" if i==3 else "model_accessor_bounds","bounds_known":true,"owner_keys":["owner"] if i==4 else []})
		items.append({"record":entry.compact_record,"path":"model.glb","bounds":bounds,"native_reference":i==3,"group_id":group,"reference_entry":entry})
	queue.pending=items;queue.configure_references({"rows":rows},"fixture.gltf","fixture",Proof.new())
	loader.test_queue=queue;loader._entry_plan={"safety_clip":CLIP};loader._deferred_assets=items
	return {"loader":loader,"queue":queue}
func dispose(f:Dictionary)->void:
	if is_instance_valid(f.loader):f.loader.free()
	if is_instance_valid(f.queue):f.queue.free()
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var old_flag:=Deferred.collision_first_enabled;var old_pipeline:=MapLoader.entry_pipeline_enabled
	MapLoader.entry_pipeline_enabled=true;Deferred.collision_first_enabled=false
	var f:=fixture();f.loader._start_entry_prefetch()
	check(f.queue.created==null and f.queue._collision_request_ids.is_empty(),"default-off MapLoader prefetch creates no collision queue")
	dispose(f);Deferred.collision_first_enabled=true
	f=fixture();f.loader._start_entry_prefetch()
	var queue:Node=f.queue;var service:Node=queue.created
	check(is_instance_valid(service) and service.get_parent()==f.loader and service.phase=="prefetch","actual MapLoader entry-prefetch hook owns the collision CPU queue before building the map")
	check(service.tickets.entry_safety.size()==1 and service.tickets.entry_safety[0].compact_record.uuid=="item0","prefetch excludes distant, complete building, native and owner-bound records")
	check(service.pumps>0 and service.retained!=null and service.get_node_or_null("CollisionInstanceResidency")==null,"ordinary prefetch pump advances CPU preparation without creating a Store")
	var output:RefCounted=service.retained;var identity:int=service.get_instance_id();var pump_count:int=service.pumps
	queue.finish_entry_prefetch();queue.pump_entry_prefetch()
	check(service.pumps==pump_count and is_same(service.retained,output),"finish stops pumping without dropping prepared output or tickets")
	var map:=Node3D.new();map.set_meta("source_map_sha256","fixture")
	map.add_child(queue);check(queue.handoff_collision_prefetch(map),"same queue transfers to an off-tree result map")
	f.loader._early_deferred=null;f.loader.free()
	check(is_instance_valid(service) and service.get_instance_id()==identity and service.tickets.has("entry_safety") and is_same(service.retained,output),"freeing the old MapLoader after handoff preserves the one queue and its retained output")
	check(not map.is_inside_tree() and map.get_node_or_null("CollisionInstanceResidency")==null,"off-tree handoff never installs collision shapes or Store")
	root.add_child(map);queue.activate(map);queue.set_process(false)
	check(service.adopts==1 and queue._collision_prefetch_service==null and map.get_node_or_null("CollisionDependencyLoader")==service and map.get_node_or_null("CollisionInstanceResidency")!=null,"live activation adopts the same service exactly once and creates its sole Store")
	queue.activate(map);queue.set_process(false)
	check(service.adopts==1,"repeated activation does not create another collision owner")
	check(not queue.ensure_collision(CLIP,"entry_safety") and not queue.geometry_published(CLIP),"prefetch/adoption alone grants neither collision readiness nor visual readiness")
	queue.release_demand("entry_safety");check(service.tickets.is_empty(),"normal ticket release controls the adopted prefetched request")
	map.free();output=null
	f=fixture();f.loader._start_entry_prefetch();queue=f.queue;service=queue.created
	var lease:WeakRef=weakref(service.retained)
	await queue.quiesce()
	check(service.phase=="cancelled" and lease.get_ref()==null and queue._collision_prefetch_service==null and queue._collision_request_ids.is_empty(),"quiescing an unadopted load cancels its collision work and clears private ownership")
	dispose(f);await process_frame
	f=fixture();f.loader._start_entry_prefetch();queue=f.queue;service=queue.created;service.reject_handoff=true
	map=Node3D.new();queue.finish_entry_prefetch()
	check(not queue.handoff_collision_prefetch(map) and service.phase=="cancelled" and queue._collision_request_ids.is_empty(),"handoff failure cancels optimization and removes its stale collision ticket")
	f.loader._early_deferred=null;map.add_child(queue);f.loader.free();root.add_child(map);queue.activate(map);queue.set_process(false)
	check(not queue.ensure_collision(CLIP,"entry_safety") and queue.error.is_empty() and queue._demands.has("entry_safety"),"failed handoff keeps ordinary visual demand without fake readiness or a fatal map error")
	for item:Dictionary in queue.pending:item.published=true
	check(queue.ensure_collision(CLIP,"entry_safety"),"failed handoff can finish through the ordinary full-geometry fallback")
	map.free();await process_frame
	f=fixture();f.loader._start_entry_prefetch();queue=f.queue;service=queue.created
	queue._reference_proof=Proof.new();map=Node3D.new()
	check(not queue.handoff_collision_prefetch(map) and service.phase=="cancelled","replaced proof prevents handing private results into a different reference context")
	map.free();dispose(f);await process_frame
	f=fixture();f.loader._start_entry_prefetch();queue=f.queue;service=queue.created;service.reject_adopt=true
	map=Node3D.new();queue.finish_entry_prefetch();map.add_child(queue);queue.handoff_collision_prefetch(map);f.loader._early_deferred=null;f.loader.free()
	root.add_child(map);queue.activate(map);queue.set_process(false)
	check(service.phase=="cancelled" and queue._collision_prefetch_service==null and queue._collision_request_ids.is_empty() and queue.error.is_empty(),"adoption failure discards only private optimization and leaves ordinary rendering available")
	map.free();await process_frame
	Deferred.collision_first_enabled=old_flag;MapLoader.entry_pipeline_enabled=old_pipeline
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_COLLISION_PREFETCH passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
