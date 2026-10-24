extends SceneTree
## Pure CPU scheduler regression: fake documents create no mesh/GPU resources.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
const MODEL="shared.glb"
const DIGEST="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
class Document extends RefCounted:
	var failures:Dictionary={"B":true}
	var calls:Dictionary={}
	func _begin_asset_instance(record:Dictionary,_prepared:Dictionary)->Dictionary:
		return {"holder":_asset(record),"model":null}
	func _finish_asset_instance(holder:Node3D,_record:Dictionary)->Node3D:return holder
	func _asset(record:Dictionary)->Node3D:
		calls[record.uuid]=int(calls.get(record.uuid,0))+1
		var holder:=Node3D.new()
		if failures.has(record.uuid):holder.set_meta("paint_error","missing instance texture")
		return holder
class Queue extends Deferred:
	var preparations:=0
	var imported_models:=0
	func _make_prepare_task(_path:String,digest:String,token:RefCounted,_item:Dictionary,_faces:bool,_root:String,_requests:Array,_native:bool,need_model:bool)->Callable:
		preparations+=1
		if need_model:imported_models+=1
		# This logical fixture substitutes only file verification, never the
		# scheduler, real Thread, admission, strong template lease or acceptance.
		return verified_reuse.bind(digest,token)
	static func verified_reuse(digest:String,token:RefCounted)->Dictionary:
		return {"error":"cancelled" if token.is_cancelled() else "","reused_model":true,"source_digest":digest,"elapsed_us":1}
var passed:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func clip(x:float)->AABB:return AABB(Vector3(x-.5,-1,-.5),Vector3(2,2,2))
func item(uuid:String,x:float)->Dictionary:
	return {"record":{"uuid":uuid},"path":MODEL,"digest":DIGEST,"model_verified":true,"bounds":AABB(Vector3(x,0,0),Vector3.ONE)}
func fixture()->Dictionary:
	# The scheduler checks the shared template before publishing. The fake
	# document below never instantiates it, so an empty CPU template suffices.
	preload("res://scripts/world_editor/asset_library.gd").cache_packed(MODEL,PackedScene.new(),DIGEST)
	var map:=Node3D.new();root.add_child(map)
	map.set_meta("stream_library",[])
	var index:Dictionary=Index.build([])
	for key:String in index:map.set_meta(key,index[key])
	var service:=Queue.new();map.add_child(service)
	var document:=Document.new();service._doc=document
	service.pending=[item("A",-10),item("B",0),item("C",10)]
	service._prepared_paths[MODEL]=true
	service.source_signatures[MODEL]=DIGEST
	service.activate(map)
	service.set_demand("test",AABB(Vector3(-20,-1,-20),Vector3(40,2,40)))
	# A verified template is not enough: production publication owns a joined,
	# accepted result and parked byte lease until all healthy instances retire.
	var estimate:Dictionary={"estimated_bytes":Deferred.REUSE_HASH_RESERVATION_BYTES+65536,"exclusive":false}
	assert(service._admission.reserve(MODEL,estimate));service._admission.park(MODEL)
	var token:=Deferred.Drainer.CancelToken.new();var owner:PackedScene=Deferred.Assets._scenes[MODEL]
	token.set_meta("admission_owner",service._admission);token.set_meta("admission_release",service._admission.release.bind(MODEL));token.set_meta("reuse_template_owner",owner)
	service._jobs[MODEL]={"accepted":true,"token":token,"result":{"error":"","reused_model":true,"source_digest":DIGEST},"publication_ids":["A","B","C"],"native":false,"estimate":estimate,"reuse_template_owner":owner,"publication_template_owner":owner}
	service.set_process(false)
	return {"map":map,"service":service,"document":document}
func advance(service:Node)->void:
	# Real publication loop, including its per-frame budget, without imports.
	for i in 20:
		service.set_process(false);service._process(0);await process_frame
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var world:=fixture();var service:Node=world.service;var document:Document=world.document
	await advance(service)
	check(service.pending.size()==1 and service.pending[0].record.uuid=="B","B instance paint failure does not block successful A/C publication from the same model")
	check(service.instance_errors.has("B") and service.path_errors.is_empty() and service.error.is_empty(),"instance failure does not become a model or whole-map error")
	check(service.error_for_clip(clip(-10)).is_empty() and service.error_for_clip(clip(10)).is_empty() and not service.error_for_clip(clip(0)).is_empty(),"only B's spatial demand receives its instance error")
	check(document.calls.get("B")==1 and document.calls.get("A")==1 and document.calls.get("C")==1,"failed instance is held until explicit retry while healthy siblings build once")
	service.retry_failed(clip(-10))
	check(service.instance_errors.has("B") and service.profile.failed_instances==1,"retry outside failed instance bounds preserves its error")
	document.failures.erase("B");service.retry_failed(clip(0));service.set_process(false)
	check(service.instance_errors.is_empty() and service.profile.failed_instances==0,"retry clears only the matching instance error and its diagnostics")
	await advance(service)
	check(service.is_complete() and document.calls.B==2 and document.calls.A==1 and document.calls.C==1,"fixed B retries and completes without rebuilding already published A/C")
	check(service._jobs.is_empty() and service._admission.reserved_bytes==0,"instance retry reuses the prepared model without background imports")
	check(service.preparations==1 and service.imported_models==0,"repaired instance revalidates through one bounded reuse worker after its old lease retired")
	world.map.free()
	world=fixture();service=world.service;document=world.document;document.failures.clear()
	service._path_failed(MODEL,"model bytes invalid");await advance(service)
	check(service.pending.size()==3 and document.calls.is_empty(),"genuine shared model error still blocks all its unpublished instances")
	check(service.error_for_clip(clip(-10))=="model bytes invalid" and service.error_for_clip(clip(10))=="model bytes invalid","shared model error is reported in every dependent demand")
	service.retry_failed(clip(-10));service.set_process(false);await advance(service)
	check(service.is_complete() and service.path_errors.is_empty() and service.profile.failed_paths==0,"retrying shared model clears its path error and unblocks dependent instances")
	world.map.free()
	world=fixture();service=world.service;document=world.document;document.failures.clear()
	service._refresh_demanded()
	service._jobs[MODEL].accepted=false
	check(service._publication_ready().is_empty(),"cached model and verified instance cannot bypass this task's acceptance")
	service._jobs[MODEL].accepted=true
	service._discard_job(MODEL)
	for row:Dictionary in service.pending:row.model_verified=true # Deliberately stale restoration marker.
	service._refresh_demanded()
	check(service._publication_ready().is_empty(),"an orphan verified flag cannot publish without a live accepted lease")
	await advance(service)
	check(service.is_complete() and service.preparations==1 and service.imported_models==0 and document.calls.size()==3,"orphan verified flags are re-admitted instead of silently stranded")
	check(service._admission.reserved_bytes==0 and service._jobs.is_empty(),"orphan recovery retains bounded ownership and retires its complete charge")
	world.map.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero unexpected engine or script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEFERRED_INSTANCE_ERRORS passed=",passed," failures=",failures)
	preload("res://scripts/world_editor/asset_library.gd").evict_cached_scene(MODEL)
	quit(0 if failures==0 else 1)
