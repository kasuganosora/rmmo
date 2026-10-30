extends Node
## Editor-owned requests over the existing preparation queue and shared ledger.
## A finite batch owns native metadata/pixels; accepted private templates belong
## to the caller, never to an unbounded preview cache.
const Library=preload("res://scripts/world_editor/asset_library.gd")
const Queue=preload("res://scripts/world_editor/load_preparation_queue.gd")
const Native=preload("res://scripts/world_editor/native_model_texture_preparation.gd")
const Preparation=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Ready=preload("res://scripts/world3d/model_texture_readiness.gd")
const Ownership=preload("res://scripts/world_editor/prepared_model_ownership.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const NODE_NAME:="EditorAssetPreparation"
const MAX_BATCH_MODELS:=8
const PRIVATE_PRUNE_STEP:=8

class Handle extends RefCounted:
	var packed:PackedScene
	var candidate:Dictionary
	var path:String
	var content_root:String
	func ready()->bool:
		return packed!=null and Ready.matches(packed,candidate)
	func current()->bool:
		return ready() and Library.native_candidate(path,content_root)==candidate
	func instantiate()->Node3D:
		return Library._instantiate(packed) if Thread.is_main_thread() and current() else null
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and packed!=null:
			preload("res://scripts/world3d/resource_retirement.gd").defer_scene(packed)

var ledger:RefCounted
var content_root:String
var native_texture_pool:RefCounted # Optional fixture injection.
var native_texture_preparer:Callable # Optional fixture injection.
var thread_starter:Callable # Optional fixture injection.
var ownership_tracker:Node # Optional protocol-only CPU fixture injection.
var profile:={"requests":0,"producers":0,"joined":0,"completed":0,"failed":0,"cancelled":0,"batches_closed":0,"table_reads":0,"private_reused":0,"private_scanned":0}
var _requests:Dictionary={}
var _bundles:Dictionary={}
var _groups:Dictionary={}
var _batches:Dictionary={}
var _next_request:=0
var _next_batch:=0
var _closed:=false
# Discover already adopted templates while their real callers still own them.
# Complete content candidates across logical aliases; rows own no resources.
var _private_models:Dictionary={}
var _private_order:Array[String]=[]
var _private_cursor:=0

static func for_consumer(consumer:Node)->Node:
	if not is_instance_valid(consumer) or not consumer.is_inside_tree():return null
	var host:Node=consumer
	while host!=null and not "_shared_preparation_ledger" in host:host=host.get_parent()
	if host==null:return null
	var existing:Node=host.get_node_or_null(NODE_NAME)
	if existing!=null:return existing if existing.get_script()==load("res://scripts/world_editor/editor_asset_preparation.gd") and not existing._closed else null
	var service=load("res://scripts/world_editor/editor_asset_preparation.gd").new()
	service.name=NODE_NAME;service.ledger=host._shared_preparation_ledger;service.content_root=Paths.external_root()
	host.add_child(service)
	return service

static func _identity(_path:String,candidate:Dictionary,root_:String)->String:
	# A pack-local alias changes only the logical lookup. Budget, table, product,
	# generator and every other candidate field must agree before sharing work.
	var content:Dictionary=candidate.duplicate();content.erase("source_path")
	return JSON.stringify([root_,content],"",true,true)

func request(path:String,consumer:Node,callback:Callable)->int:
	if _closed or ledger==null or not is_inside_tree() or not is_instance_valid(consumer) or not callback.is_valid():return 0
	_next_request+=1;var id:=_next_request;profile.requests+=1
	var request_:={"consumer":weakref(consumer),"callback":callback}
	_requests[id]=request_;set_process(true)
	path=path.replace("\\","/").simplify_path()
	_prune_private()
	var candidate:=Library.native_candidate(path,content_root)
	if candidate.is_empty():
		request_.result={"ok":false,"error":"模型缺少可用原生产物："+path};return id
	request_.path=path;request_.candidate=candidate
	if Library._native_cached(path,candidate):
		_remember_private(path,candidate,Library._scenes[path])
		request_.result={"ok":true,"handle":_handle(path,candidate,Library._scenes[path])};return id
	var borrowed:=_borrow_private(path,candidate)
	if borrowed!=null:
		request_.result={"ok":true,"handle":_handle(path,candidate,borrowed)};profile.private_reused+=1;return id
	var key:=_identity(path,candidate,content_root)
	request_.group=key
	if _groups.has(key):
		_groups[key].requests.append(id);profile.joined+=1;return id
	var batch:=_batch()
	var task:Callable=_read.bind(path,candidate,content_root,preload("res://scripts/world3d/runtime_package_policy.gd").trusted())
	var accepted:bool
	if candidate.has("texture_table"):accepted=batch.native.enqueue(key,path,candidate,task)
	else:accepted=batch.queue.enqueue(key,task,{"estimated_bytes":int(candidate.estimated_bytes),"exclusive":bool(candidate.exclusive),"stage":"compiled_read"},"model")
	if not accepted:
		request_.erase("group");request_.result={"ok":false,"error":"模型准备任务无法启动"}
		if batch.groups.is_empty():_close_batch(batch.id)
		return id
	_groups[key]={"path":path,"candidate":candidate,"requests":[id],"batch":batch.id}
	batch.groups.append(key);batch.models+=1;profile.producers+=1
	return id

func request_many(paths:Array,consumer:Node,callback:Callable)->int:
	if _closed or ledger==null or not is_inside_tree() or not is_instance_valid(consumer) or not callback.is_valid():return 0
	_next_request+=1;var id:=_next_request
	var bundle:={"consumer":weakref(consumer),"callback":callback,"children":{},"handles":{}}
	_bundles[id]=bundle;set_process(true)
	for value:Variant in paths:
		var path:=str(value).replace("\\","/").simplify_path()
		if bundle.children.has(path):continue
		var child:=request(path,consumer,_bundle_ready.bind(id,path))
		if child==0:
			bundle.result={"ok":false,"error":"模型准备服务不可用"};break
		bundle.children[path]=child
	if bundle.children.is_empty() and not bundle.has("result"):bundle.result={"ok":true,"handles":{}}
	return id

func _bundle_ready(_child:int,result:Dictionary,id:int,path:String)->void:
	if not _bundles.has(id):return
	var bundle:Dictionary=_bundles[id];bundle.children.erase(path)
	if not result.get("ok",false):
		for child:int in bundle.children.values():cancel(child)
		bundle.children.clear();bundle.handles.clear();bundle.result=result
		return
	bundle.handles[path]=result.handle
	if bundle.children.is_empty():bundle.result={"ok":true,"handles":bundle.handles}

func _batch()->Dictionary:
	if _batches.has(_next_batch) and _batches[_next_batch].models<MAX_BATCH_MODELS:return _batches[_next_batch]
	_next_batch+=1
	var queue:=Queue.new();queue.ledger=ledger;queue.shared_ledger_enabled=true;queue.worker_limit=ledger.worker_limit;queue.thread_starter=thread_starter
	add_child(queue)
	var native:=Native.new();native.configure(queue,content_root,native_texture_pool,native_texture_preparer)
	var batch:={"id":_next_batch,"queue":queue,"native":native,"models":0,"groups":[]}
	_batches[_next_batch]=batch
	return batch

static func _read(path:String,candidate:Dictionary,root_:String,trusted:bool)->Dictionary:
	return Preparation.read(path,candidate,root_,Callable(),trusted,false,"",true)

func _handle(path:String,candidate:Dictionary,packed:PackedScene)->Handle:
	var handle:=Handle.new();handle.path=path;handle.candidate=candidate;handle.content_root=content_root;handle.packed=packed
	return handle

static func _render_ready(packed:PackedScene,candidate:Dictionary)->bool:
	if not Ready.matches(packed,candidate) or packed.get_meta(Ready.GEOMETRY_ONLY_META,false):return false
	var state:=packed.get_state()
	if state.get_node_count()==0:return false
	# A geometry-query instance can be repacked. Its root marker must not become
	# a render-ready template even when there is no separate texture table.
	for index:int in state.get_node_property_count(0):
		if state.get_node_property_name(0,index)==StringName("metadata/"+str(Ready.GEOMETRY_ONLY_META)) and state.get_node_property_value(0,index):return false
	return true

func _private_key(path:String,candidate:Dictionary)->String:
	return _identity(path,candidate,content_root)

func _borrow_private(path:String,candidate:Dictionary)->PackedScene:
	var key:=_private_key(path,candidate)
	if not _private_models.has(key):return null
	var row:Dictionary=_private_models[key]
	var packed:PackedScene=row.packed.get_ref() as PackedScene
	var valid:bool=_render_ready(packed,candidate)
	valid=valid and packed.get_meta("compiled_asset_validated",false) and (preload("res://scripts/world3d/runtime_package_policy.gd").trusted() or packed.get_meta("_rmmo_native_audited",false)) and packed.get_meta("_rmmo_source_digest","")==candidate.get("source_sha") and packed.get_meta("_rmmo_native_payload_sha","")==candidate.get("payload_sha") and packed.get_meta("_rmmo_native_generator","")==candidate.get("generator")
	if valid:return packed
	_forget_private(key)
	# Another owner can release after get_ref. If this rejected borrow is now
	# the last reference, keep its release on the existing bounded scene queue.
	if packed!=null:preload("res://scripts/world3d/resource_retirement.gd").defer_scene(packed)
	return null

func _remember_private(path:String,candidate:Dictionary,packed:PackedScene)->void:
	# Called only after successful adoption/publication, while the original
	# charged packet still owns this complete allocation. No second adoption.
	_prune_private()
	var key:=_private_key(path,candidate)
	var slot:int
	if _private_models.has(key):slot=_private_models[key].slot
	else:slot=_private_order.size();_private_order.append(key)
	_private_models[key]={"packed":weakref(packed),"instance_id":packed.get_instance_id(),"slot":slot}

func _forget_private(key:String)->void:
	if not _private_models.has(key):return
	var slot:int=_private_models[key].slot
	var last:String=_private_order.back()
	_private_order[slot]=last;_private_order.pop_back()
	if last!=key:_private_models[last].slot=slot
	_private_models.erase(key)
	if _private_cursor>=_private_order.size():_private_cursor=0

func _prune_private()->void:
	for _index:int in mini(PRIVATE_PRUNE_STEP,_private_order.size()):
		if _private_order.is_empty():break
		var key:=_private_order[_private_cursor];profile.private_scanned+=1
		# Probe identity only: get_ref would acquire (and possibly finally release)
		# a large native allocation merely to clean its weak index row.
		if not is_instance_id_valid(_private_models[key].instance_id):_forget_private(key)
		else:_private_cursor=(_private_cursor+1)%_private_order.size()

func cancel(id:int)->bool:
	if _bundles.has(id):
		var bundle:Dictionary=_bundles[id];_bundles.erase(id)
		for child:int in bundle.children.values():cancel(child)
		return true
	if not _requests.has(id):return false
	var request_:Dictionary=_requests[id];_requests.erase(id);profile.cancelled+=1
	var key:String=request_.get("group","")
	if not _groups.has(key):return true
	var group:Dictionary=_groups[key];group.requests.erase(id)
	var batch:Dictionary=_batches[group.batch]
	# A sibling can still depend on this producer's texture. Cancel the existing
	# queue only when the entire finite batch has no live subscriber.
	for other:String in batch.groups:
		if not _groups[other].requests.is_empty():return true
	_close_batch(batch.id)
	return true

func _process(_delta:float)->void:
	for id:int in _bundles.keys():
		var owner:Node=_bundles[id].consumer.get_ref()
		if owner==null or not owner.is_inside_tree() or not _bundles[id].callback.is_valid():cancel(id)
	for id:int in _requests.keys():
		if not _requests.has(id):continue
		var owner:Node=_requests[id].consumer.get_ref()
		if owner==null or not owner.is_inside_tree() or not _requests[id].callback.is_valid():cancel(id)
	for key:String in _groups.keys():
		if not _groups.has(key):continue
		var group:Dictionary=_groups[key];var batch:Dictionary=_batches[group.batch]
		if batch.queue.is_ready(key):_accept(key,group,batch)
	for id:int in _requests.keys():
		if not _requests.has(id) or not _requests[id].has("result"):continue
		var request_:Dictionary=_requests[id];_requests.erase(id)
		var owner:Node=request_.consumer.get_ref()
		if owner!=null and owner.is_inside_tree() and request_.callback.is_valid():request_.callback.call(id,request_.result)
		if not is_inside_tree() or _closed:return
	for id:int in _bundles.keys():
		if not _bundles.has(id) or not _bundles[id].has("result"):continue
		var bundle:Dictionary=_bundles[id];_bundles.erase(id)
		var owner:Node=bundle.consumer.get_ref()
		if owner!=null and owner.is_inside_tree() and bundle.callback.is_valid():bundle.callback.call(id,bundle.result)
		if not is_inside_tree() or _closed:return
	if _requests.is_empty() and _groups.is_empty() and _bundles.is_empty():set_process(false)

func _accept(key:String,group:Dictionary,batch:Dictionary)->void:
	var packet:Dictionary=batch.queue.acquire(key)
	var current:Dictionary={}
	for id:int in group.requests:
		if not _requests.has(id):continue
		var request_:Dictionary=_requests[id]
		current[id]=Library.native_candidate(request_.path,content_root)==request_.candidate
	var accepted:bool=current.values().has(true) and packet.get("error",FAILED)==OK and not packet.get("cancelled",false) and packet.get("compiled",false)==true and packet.get("source_digest")==group.candidate.source_sha and packet.get("packed") is PackedScene
	accepted=accepted and _render_ready(packet.get("packed"),group.candidate)
	var reason:=str(packet.get("error_message","模型准备失败或原生产物已变化"))
	if accepted:
		var tracker:Node=ownership_tracker if is_instance_valid(ownership_tracker) else Ownership.for_tree(get_tree())
		var proof:Dictionary=tracker.preflight(group.candidate,packet,int(group.candidate.estimated_bytes)) if tracker!=null else {"ok":false,"reason":"ownership_tracker_unavailable"}
		if proof.get("ok",false):
			# The private result owns a published geometry baseline, including while
			# a prefab bundle waits for siblings. No AssetLibrary cache is inserted.
			# Keep the full queue packet charged through this main-thread handoff.
			packet.packed.set_meta("_rmmo_source_digest",packet.source_digest)
			proof=tracker.adopt(proof.ticket)
		accepted=proof.get("ok",false)
		if not accepted:reason="模型所有权交接失败："+str(proof.get("reason","unknown"))
	if accepted:
		batch.native.published(packet)
		_remember_private(group.path,group.candidate,packet.packed)
		profile.completed+=1
	else:
		profile.failed+=1
	for id:int in group.requests:
		if not _requests.has(id):continue
		var request_:Dictionary=_requests[id];request_.erase("group")
		request_.result={"ok":true,"handle":_handle(request_.path,request_.candidate,packet.packed)} if accepted and current.get(id,false) else {"ok":false,"error":reason}
	batch.queue.release(key);batch.queue.forget_terminal(key)
	_groups.erase(key);batch.groups.erase(key)
	if batch.groups.is_empty():_close_batch(batch.id)

func _close_batch(id:int)->void:
	if not _batches.has(id):return
	var batch:Dictionary=_batches[id];_batches.erase(id)
	for key:String in batch.groups:_groups.erase(key)
	batch.queue.cancel();batch.native.close()
	profile.table_reads+=int(batch.native.catalog.native_async_reads);profile.batches_closed+=1
	batch.queue.queue_free()

func snapshot()->Dictionary:
	return {"profile":profile.duplicate(),"requests":_requests.size(),"bundles":_bundles.size(),"groups":_groups.size(),"batches":_batches.size(),"private_templates":_private_models.size(),"ledger":ledger.snapshot() if ledger!=null else {}}

func close()->void:
	if _closed:return
	_closed=true;set_process(false);_requests.clear();_bundles.clear()
	_private_models.clear();_private_order.clear();_private_cursor=0
	for id:int in _batches.keys():_close_batch(id)

func _exit_tree()->void:close()
