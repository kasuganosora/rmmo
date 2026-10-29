extends RefCounted
## Editor-only complete native preparation. Table IO, geometry, pixels and
## binding use the existing editor ledger. A model's worker runs its private
## stages sequentially; different models may use the shared worker allowance.
const Catalog=preload("res://scripts/world3d/texture_plan_catalog.gd")
const Shared=preload("res://scripts/world3d/shared_prefab_images.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Pixels=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Sharing=preload("res://scripts/world3d/native_texture_sharing.gd")
const Capability=preload("res://scripts/world3d/native_texture_capability.gd")
var catalog=Catalog.new()
var pool:RefCounted
var queue:Node
var content_root:String
var pixel_preparer:Callable
var claims:Dictionary={}
var retained_consumers:Array[String]=[]
var closed:=false
var serial:=0
var revision:=PoolRevision.new()
var profile:={"geometry_calls":0,"geometry_us":0,"pixel_calls":0,"pixel_us":0,"binding_calls":0,"binding_us":0,"binding_sets":0,"continuations":0,"cached_textures":0,"published_models":0,"factory_polls":0,"offer_builds":0,"resident_queries":0}

class PoolRevision extends RefCounted:
	var value:=0 # Only scheduler/join/main-thread retirement mutate pool identity.

class Scope extends RefCounted:
	var catalog:RefCounted
	var pool:RefCounted
	var candidate:Dictionary
	var root:String
	var consumer:String
	var prepared:Dictionary={}
	var cached:Dictionary={}
	var shared:Dictionary={}
	var cached_digests:Dictionary={}
	var offered:Dictionary={}
	var offer_stamp:Array=[]
	var dependency_estimate:Dictionary={}
	var pooled_keys:Array=[]
	var revision:PoolRevision
	var token:WeakRef
	var committed:=false
	var retained:=false
	var published:=false
	var released:=false
	func is_cancelled()->bool:
		var current:RefCounted=token.get_ref() if token!=null else null
		return current==null or current.is_cancelled()
	func release_now()->void:
		if released:return
		assert(Thread.is_main_thread());released=true
		prepared={};cached={};shared={};offered={};cached_digests={};pooled_keys=[];token=null
		if committed and not retained:
			pool.release(consumer);revision.value+=1
		if catalog!=null:catalog.release_model(candidate,root,consumer)
		catalog=null;pool=null;candidate={}

func configure(owner:Node,root:String,shared_pool:RefCounted=null,preparer:Callable=Callable())->void:
	queue=owner;content_root=root;pixel_preparer=preparer
	pool=shared_pool if shared_pool!=null else Shared.new();pool.admission=queue.ledger
	# Catalog deducts live scalar metadata from this same working allowance.
	# Do not let a lightweight host reset that allowance on every queue pump.
	queue.shared_ledger_enabled=true

func enqueue(key:String,path:String,candidate:Dictionary,reader:Callable)->bool:
	return queue.enqueue_prepared(key,_offer.bind(key,path,candidate,reader),"model")

func _offer(key:String,path:String,candidate:Dictionary,reader:Callable)->Dictionary:
	if closed:return {"failure":{"error":ERR_SKIP,"cancelled":true}}
	profile.factory_polls+=1
	var scope:Scope=claims.get(key)
	if scope==null or scope.released:
		scope=Scope.new();scope.catalog=catalog;scope.pool=pool;scope.candidate=candidate;scope.revision=revision
		serial+=1
		scope.root=content_root;scope.consumer="editor_native:%d:%d:%s"%[get_instance_id(),serial,key]
		claims[key]=scope
	var capability:String=Capability.error_for(candidate.get("texture_table",{}),pixel_preparer.is_valid() or pool.get_script()!=Shared)
	if not capability.is_empty():return _failure(scope,capability)
	if scope.prepared.is_empty():
		catalog.poll();catalog.error=""
		if scope.dependency_estimate.is_empty():
			var descriptor:Dictionary=catalog._model_descriptor(candidate)
			if descriptor.is_empty():return _failure(scope,catalog.error)
			scope.dependency_estimate=catalog._model_estimate(descriptor,content_root)
			if scope.dependency_estimate.is_empty():return _failure(scope,catalog.error)
		if not catalog.prepare_model_async(candidate,content_root,queue.ledger,queue.get_tree(),scope.consumer):
			return {"pending":true,"dependency_estimate":scope.dependency_estimate} if catalog.error.is_empty() else _failure(scope,catalog.error)
		var prepared:Dictionary=catalog.model_plan(candidate,content_root)
		if not prepared.get("ok",false):return _failure(scope,str(prepared.get("error","Native texture table unavailable")))
		scope.prepared=prepared
		# The table and any exact resident owner stay pinned by this scope. A
		# budget/slot retry must not rescan every row or repeat resident misses.
		for texture_key:String in prepared.plan.rows:
			profile.resident_queries+=1
			var ticket:=Sharing.ticket(texture_key,prepared.plan.rows[texture_key])
			if not ticket.is_empty():
				scope.cached[texture_key]=ticket;scope.cached_digests[texture_key]=ticket.source_sha
	var stamp:Array=[revision.value,Shared.Pixels.upload_preparation_enabled,Binding.Paint.source_generation,Shared.Pixels.Policy.trusted(),pool._upload_enabled]
	if scope.offer_stamp!=stamp:
		scope.offered=pool.offer(scope.prepared.plan,scope.cached_digests)
		scope.offer_stamp=stamp;profile.offer_builds+=1
	var offer:Dictionary=scope.offered
	var estimate:={"estimated_bytes":int(candidate.estimated_bytes)+int(offer.scratch_bytes),"exclusive":bool(candidate.exclusive),"stage":"native_model_and_textures"}
	return {"estimate":estimate,"retained":offer.retained,"task":_read.bind(path,reader,scope),
		"commit":_commit.bind(scope,offer),"joined":_joined,"resume":_resume}

func _failure(scope:Scope,message:String)->Dictionary:
	return {"failure":{"error":ERR_INVALID_DATA,"error_message":message,"native_texture_scope":scope}}

func _commit(token:RefCounted,continuation:bool,scope:Scope,offer:Dictionary)->void:
	scope.token=weakref(token)
	token.set_meta("native_texture_scope",scope)
	if not continuation:
		pool.commit(scope.consumer,offer);scope.committed=true;revision.value+=1
		scope.pooled_keys=offer.bindings.keys()
		scope.shared={"pool":pool,"consumer":scope.consumer,"leaders":offer.leaders,"cached":offer.cached}
		profile.cached_textures+=scope.cached.size()
	else:
		scope.shared=scope.shared.duplicate();scope.shared.leaders={}
		profile.continuations+=1
	# Cancellation invalidates the operation through this token. Keep its private
	# pool consumer until join: an upload already inside load_stream() must retain
	# its final Texture2D owner for main-thread disposal, even when its result will
	# never be published. Failed leaders are revoked by _joined/release_now.

func _read(_path:String,reader:Callable,scope:Scope)->Dictionary:
	var began:=Time.get_ticks_usec();var packet:Dictionary=reader.call()
	packet.native_texture_scope=scope
	packet.native_stages={"geometry_calls":1,"geometry_us":Time.get_ticks_usec()-began}
	if packet.get("error",FAILED)!=OK or scope.is_cancelled():return packet
	return _finish(packet,scope)

func _finish(packet:Dictionary,scope:Scope)->Dictionary:
	var began:=Time.get_ticks_usec()
	var pixels:Dictionary=pixel_preparer.call(scope.prepared,content_root,scope,scope.shared) if pixel_preparer.is_valid() else Pixels.prepare(scope.prepared.sources,scope.prepared.plan,content_root,scope,true,scope.shared,true)
	packet.prefab_texture_packet=pixels
	packet.native_stages.pixel_calls=int(packet.native_stages.get("pixel_calls",0))+1
	packet.native_stages.pixel_us=int(packet.native_stages.get("pixel_us",0))+Time.get_ticks_usec()-began
	if scope.is_cancelled() or not str(pixels.get("error","invalid pixels")).is_empty():
		packet.error=ERR_SKIP if scope.is_cancelled() else ERR_INVALID_DATA
		packet.error_message=str(pixels.get("error","Native pixels cancelled"));return packet
	if pixels.get("waiting_pixels",false):packet.native_waiting=true;return packet
	packet.native_waiting=false
	var owners:Dictionary=pixels.get("uploaded_textures",{}).duplicate()
	for key:String in scope.cached:owners[key]=scope.cached[key].texture
	pixels.uploaded_textures=owners
	began=Time.get_ticks_usec()
	var binding:=Binding.begin(packet.packed,scope.prepared.keys,scope.prepared.table_sha)
	packet.native_texture_plan=binding
	if not Binding.adopt(binding,owners):
		packet.error=ERR_INVALID_DATA;packet.error_message=str(binding.get("error","Native binding failed"));return packet
	var status:=Binding.PROGRESS
	while status==Binding.PROGRESS and not scope.is_cancelled():status=Binding.step(binding)
	packet.native_stages.binding_calls=1;packet.native_stages.binding_us=Time.get_ticks_usec()-began
	packet.native_stages.binding_sets=int(binding.get("sets",0))
	if status!=Binding.READY or scope.is_cancelled():packet.error=ERR_SKIP if scope.is_cancelled() else ERR_INVALID_DATA
	return packet

func _joined(packet:Dictionary)->bool:
	if packet.get("cancelled",false):packet.error=ERR_SKIP
	if packet.get("error",FAILED)==OK and packet.get("native_waiting",false):return false
	var scope:Scope=packet.get("native_texture_scope")
	if scope!=null and packet.get("error",FAILED)==OK:
		if not scope.pooled_keys.is_empty() and not pool.handoff_streamed(scope.consumer,packet.get("prefab_texture_packet",{}).get("uploaded_textures",{}),scope.pooled_keys):
			packet.error=ERR_INVALID_DATA;packet.error_message="Native texture residency handoff failed"
		elif not scope.retained and not scope.pooled_keys.is_empty():
			# A later first-use model may need these pixels before this ready
			# geometry is published. Retiring speculative geometry must not force
			# a second load of the completed, engine-managed texture.
			scope.retained=true;retained_consumers.append(scope.consumer)
	if scope!=null and packet.get("error",FAILED)!=OK:
		pool.cancel(scope.consumer);revision.value+=1
	for key:String in packet.get("native_stages",{}):profile[key]=int(profile.get(key,0))+int(packet.native_stages[key])
	return true

func _resume(packet:Dictionary)->Callable:
	var scope:Scope=packet.get("native_texture_scope")
	return _finish.bind(packet,scope) if scope!=null and pool.ready(scope.consumer) else Callable()

func published(packet:Dictionary)->void:
	var scope:Scope=packet.get("native_texture_scope")
	if scope==null or scope.released or scope.published:return
	# Retain this operation's pool identity for later models, even after this
	# packet is cleared. The full pixel envelope was already handed to engine.
	scope.published=true
	Sharing.publish(packet.get("prefab_texture_packet",{}).get("uploaded_textures",{}))
	profile.published_models+=1

func snapshot()->Dictionary:
	var result:=profile.duplicate();result.pool=pool.snapshot();result.tables=catalog.snapshot();return result

func close()->void:
	if closed:return
	assert(Thread.is_main_thread());closed=true
	# Queue.cancel owns running/ready scopes until aliases and workers retire.
	for scope:Scope in claims.values():
		if not scope.committed:scope.release_now()
	claims.clear()
	for consumer:String in retained_consumers:pool.release(consumer)
	retained_consumers.clear();catalog.abandon();queue=null
