extends RefCounted
## A split-native initial batch uses the existing shared image pool and one
## admission ledger for geometry, pixels and binding continuations. Each model
## starts geometry before its pixels, preventing an exclusive pixel lease from
## blocking the geometry it needs in order to finish and hand off residency.
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Binding=preload("res://scripts/world3d/model_texture_bindings.gd")
const Textures=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Scope=preload("res://scripts/world3d/initial_native_texture_scope.gd")
const Catalog=preload("res://scripts/world3d/texture_plan_catalog.gd")
var controller:RefCounted
var ledger:RefCounted
var scope:RefCounted
var content_root:String
var models:Array[Dictionary]=[]
var pending:Array[Dictionary]=[]
var queued_preparation:Array[Dictionary]=[]
var tables:Dictionary={}
var metadata_bytes:=0
var waiting_residents:Array[Dictionary]=[]
var retiring_residents:Array[Dictionary]=[]
var working_byte_limit:=0
var _products:Dictionary={}
var queued_pixels:Array[Dictionary]=[]
var waiting_pixels:Array[Dictionary]=[]
var queued_bindings:Array[Dictionary]=[]
var unfinished:=0
var peak_live_estimate_bytes:=0
var profile:Dictionary={"unique_products":0,"table_jobs":0,"table_us":0,"metadata_peak_bytes":0,"geometry_jobs":0,"pixel_jobs":0,"binding_jobs":0,"pixel_continuations":0,"threads_started":0,"threads_joined":0,"synchronous_fallbacks":0,"geometry_us":0,"pixel_us":0,"binding_us":0,"worker_slots_peak":0,"geometry_retained_bytes":0}
var _failed:=false
var _mutex:=Mutex.new()

func is_cancelled()->bool:
	_mutex.lock();var stopped:=_failed;_mutex.unlock()
	return stopped or controller.is_cancelled()

func _stop()->void:
	_mutex.lock();_failed=true;_mutex.unlock()
	if scope!=null and scope.resident_run!=null:scope.resident_run.close()

func run(owner:RefCounted,paths:Array,candidates:Dictionary,estimates:Dictionary,root:String,limit:int,byte_limit:int,starter:Callable)->Dictionary:
	controller=owner;content_root=root
	ledger=Admission.new();ledger.worker_limit=limit;ledger.byte_limit=byte_limit
	scope=Scope.new();scope.pool=owner.native_texture_pool if owner.native_texture_pool!=null else Pool.new();scope.pool.admission=ledger
	scope.resident_bridge=owner.native_resident_bridge;scope.resident_run=owner.open_native_resident_run()
	scope.resident_budget_limit=byte_limit
	working_byte_limit=byte_limit
	var started:=Time.get_ticks_usec();var catalog:=Catalog.new()
	for path:String in paths:
		var candidate:Dictionary=candidates.get(path,{})
		var model:={"path":path,"candidate":candidate,"estimate":estimates[path],"plan":{},"table_key":"",
			"geometry":"queued","pixels":"unplanned","binding":"queued",
			"consumer":"initial_pixels:"+path,"shared":{},"result":{},"pixels_result":{}}
		models.append(model)
		queued_preparation.append({"stage":"geometry","owner":model,"key":"initial_geometry:"+path,"estimate":model.estimate})
		if not candidate.has("texture_table"):
			model.plan=Binding.candidate_plan(candidate,root,{});model.pixels="done";continue
		var descriptor:Dictionary=catalog._model_descriptor(candidate)
		if descriptor.is_empty():return _preflight_error(path,catalog.error,paths.size(),started)
		var custom:bool=owner.native_texture_preparer.is_valid() or (owner.native_texture_pool!=null and owner.native_texture_pool.get_script()!=Pool)
		var capability_error:String=preload("res://scripts/world3d/native_texture_capability.gd").error_for(descriptor,custom)
		if not capability_error.is_empty():return _preflight_error(path,capability_error,paths.size(),started)
		var key:String=Catalog._model_key(descriptor,root);model.table_key=key
		if tables.has(key):
			if tables[key].descriptor!=descriptor:return _preflight_error(path,"Conflicting native model texture descriptor",paths.size(),started)
		else:
			var estimate:Dictionary=catalog._model_estimate(descriptor,root)
			if estimate.is_empty():return _preflight_error(path,catalog.error,paths.size(),started)
			var entry:={"key":key,"candidate":{"texture_table":descriptor},"descriptor":descriptor,"models":[],"remaining":0,"plan":{},"metadata_bytes":int(estimate.metadata_bytes),"resident":false}
			tables[key]=entry
			# Interleave model and unique table jobs. Slow metadata never fences
			# geometry or a later table behind a serial read-all preflight.
			queued_preparation.append({"stage":"table","owner":entry,"key":"initial_table:"+key,"estimate":estimate})
		tables[key].models.append(model);tables[key].remaining+=1
	unfinished=models.size();profile.tables=tables.size()
	while true:
		_join_finished()
		_poll_residents()
		if is_cancelled():
			if pending.is_empty():break
			OS.delay_usec(500);continue
		var dispatched:=_dispatch_ready(starter)
		dispatched=_dispatch_pixels(starter) or dispatched
		dispatched=_dispatch_preparation(starter) or dispatched
		if unfinished==0 and pending.is_empty():break
		if not dispatched and pending.is_empty() and waiting_residents.is_empty() and retiring_residents.is_empty():
			# Do not spin forever if a malformed fixture/admission contract cannot
			# complete. Normal producers have either a running task or a resumable
			# binding that transfers their retained outputs to streaming residency.
			for model:Dictionary in models:
				if model.binding!="done":model.result.error=ERR_OUT_OF_MEMORY;model.result.error_message="Initial native admission cannot make progress: "+model.path;break
			_stop();continue
		OS.delay_usec(500)
	return _result(paths.size(),started)

func _dispatch_preparation(starter:Callable)->bool:
	var dispatched:=false;var index:=0
	while index<queued_preparation.size() and ledger.active_workers()<ledger.worker_limit:
		var work:Dictionary=queued_preparation[index];var item:Dictionary=work.owner
		# Retained scalar metadata is a separate allowance, not a persistent
		# admission entry that would block its own exclusive model.
		if work.stage=="table" and metadata_bytes+scope.resident_metadata_bytes>=working_byte_limit:index+=1;continue
		if not ledger.reserve(work.key,work.estimate):index+=1;continue
		queued_preparation.remove_at(index)
		if work.stage=="geometry":
			item.geometry="running"
			_launch(item,"geometry",controller._candidate_stage.bind(item.path,item.candidate,content_root),work.key,starter)
			if item.pixels=="queued":queued_pixels.append(item)
		else:_launch(item,"table",_read_table.bind(item.candidate),work.key,starter)
		dispatched=true;_dispatch_pixels(starter)
	return dispatched

func _read_table(candidate:Dictionary)->Dictionary:
	if not controller.native_texture_table_reader.is_valid():return Binding.candidate_plan(candidate,content_root,{})
	var reply:Variant=controller.native_texture_table_reader.call(candidate,content_root)
	if not reply is Dictionary or not Catalog._scalar_metadata(reply):
		return {"ok":false,"error":"Native metadata reader returned non-scalar data","retained_resources":[reply],"opaque_metadata":true}
	return reply

func _join_table(table:Dictionary,reply:Dictionary,key:String)->void:
	if reply.get("opaque_metadata",false):scope.retained_packets.append(reply);scope.retained_reservations.append(key);ledger.park(key)
	else:ledger.release(key)
	if not reply.get("ok",false):
		var first:Dictionary=table.models[0];first.failure=ERR_INVALID_DATA;first.failure_message=str(reply.get("error","Native metadata preparation failed"));_stop();return
	table.plan=reply;table.resident=true;metadata_bytes+=int(table.metadata_bytes)
	if scope.resident_run!=null and not reply.plan.rows.is_empty():
		table.ticket_bytes=scope.resident_run.request(table.key,reply.plan.rows)
		scope.resident_metadata_bytes+=int(table.ticket_bytes)
		waiting_residents.append(table)
	_reapply_budget()
	profile.metadata_peak_bytes=maxi(int(profile.metadata_peak_bytes),metadata_bytes)
	peak_live_estimate_bytes=maxi(peak_live_estimate_bytes,int(profile.geometry_retained_bytes)+metadata_bytes+scope.resident_metadata_bytes+ledger.reserved_bytes)
	for texture:String in reply.plan.rows:_products[texture]=true
	profile.unique_products=_products.size()
	if scope.resident_run==null or reply.plan.rows.is_empty():_accept_table_residents(table,{})

func _reapply_budget()->void:
	ledger.byte_limit=maxi(1,working_byte_limit-metadata_bytes-scope.resident_metadata_bytes)

func _poll_residents()->void:
	if scope.resident_run==null or is_cancelled():return
	var at:=0
	while at<retiring_residents.size():
		var table:Dictionary=retiring_residents[at];var reply:Dictionary=scope.resident_run.poll(table.key)
		if reply.get("cancelled",false):controller.cancel();return
		if not reply.get("retired",false):at+=1;continue
		scope.resident_metadata_bytes-=int(table.ticket_bytes);retiring_residents.remove_at(at);_reapply_budget()
	at=0
	while at<waiting_residents.size():
		var table:Dictionary=waiting_residents[at];var reply:Dictionary=scope.resident_run.poll(table.key)
		if reply.get("cancelled",false):controller.cancel();return
		if reply.get("pending",false):at+=1;continue
		waiting_residents.remove_at(at);_accept_table_residents(table,reply.tickets)

func _accept_table_residents(table:Dictionary,tickets:Dictionary)->void:
	for model:Dictionary in table.models:
		model.plan=table.plan;model.resident_tickets=tickets
		model.pixels="queued" if not table.plan.plan.rows.is_empty() else "done"
		if model.pixels=="queued" and model.geometry!="queued":queued_pixels.append(model)
		elif model.pixels=="done":_queue_binding(model)

func _release_table_consumer(model:Dictionary)->void:
	var key:String=model.get("table_key","")
	if key.is_empty() or model.get("metadata_released",false):return
	model.metadata_released=true;model.plan={}
	model.resident_tickets={}
	var table:Dictionary=tables[key];table.remaining-=1
	if table.remaining==0 and table.resident:
		if int(table.get("ticket_bytes",0))>0:scope.resident_run.retire(key);retiring_residents.append(table)
		table.plan={};table.models=[];table.resident=false
		metadata_bytes-=int(table.metadata_bytes);_reapply_budget()

func _dispatch_ready(starter:Callable)->bool:
	var dispatched:=false;var index:=0
	while index<queued_bindings.size() and ledger.active_workers()<ledger.worker_limit:
		var model:Dictionary=queued_bindings[index]
		var key:String=model.consumer if not model.shared.is_empty() else "initial_bind:"+model.path
		var reserved:bool=ledger.resume_worker(key) if not model.shared.is_empty() else ledger.reserve(key,{"estimated_bytes":65536,"exclusive":false,"stage":"initial_binding"})
		if not reserved:index+=1;continue
		queued_bindings.remove_at(index);model.binding="running"
		_launch(model,"binding",_bind.bind(model),key,starter);dispatched=true
	index=0
	while index<waiting_pixels.size() and ledger.active_workers()<ledger.worker_limit:
		var model:Dictionary=waiting_pixels[index]
		if not scope.pool.ready(model.consumer) or not ledger.resume_worker(model.consumer):index+=1;continue
		var shared:Dictionary=model.shared.duplicate();shared.leaders={}
		waiting_pixels.remove_at(index);model.pixels="running"
		_launch(model,"pixels",_pixels.bind(model.plan,shared),model.consumer,starter)
		profile.pixel_continuations+=1;dispatched=true
	return dispatched

func _dispatch_pixels(starter:Callable)->bool:
	var dispatched:=false;var index:=0
	while index<queued_pixels.size() and ledger.active_workers()<ledger.worker_limit:
		var model:Dictionary=queued_pixels[index];var cached:Dictionary={}
		for key:String in model.get("resident_tickets",{}):cached[key]=model.resident_tickets[key].source_sha
		var offer:Dictionary=scope.pool.offer(model.plan.plan,cached)
		if not ledger.reserve_bundle(model.consumer,{"estimated_bytes":offer.scratch_bytes,"exclusive":false,"stage":"initial_pixels"},offer.retained):index+=1;continue
		scope.pool.commit(model.consumer,offer);scope.consumers.append(model.consumer)
		model.shared={"pool":scope.pool,"consumer":model.consumer,"leaders":offer.leaders,"cached":offer.cached}
		queued_pixels.remove_at(index);model.pixels="running"
		_launch(model,"pixels",_pixels.bind(model.plan,model.shared),model.consumer,starter);dispatched=true
	return dispatched

func _queue_binding(model:Dictionary)->void:
	if model.geometry!="done" or model.pixels!="done" or model.binding!="queued":return
	if model.plan.table_sha.is_empty():model.binding="done";unfinished-=1;_release_table_consumer(model)
	else:model.binding="ready";queued_bindings.append(model)

func _launch(model:Dictionary,stage:String,call:Callable,key:String,starter:Callable)->void:
	ledger.set_stage(key,"initial_"+stage)
	var task:=_invoke.bind(call);var worker:=Thread.new()
	var error:int=starter.call(worker,task) if starter.is_valid() else worker.start(task)
	var item:Dictionary={"model":model,"stage":stage,"key":key}
	if error==OK:item.thread=worker;profile.threads_started+=1
	else:item.reply=task.call();profile.synchronous_fallbacks+=1
	pending.append(item);profile[("pixel" if stage=="pixels" else stage)+"_jobs"]+=1
	profile.worker_slots_peak=maxi(int(profile.worker_slots_peak),ledger.active_workers())
	peak_live_estimate_bytes=maxi(peak_live_estimate_bytes,int(profile.geometry_retained_bytes)+metadata_bytes+scope.resident_metadata_bytes+ledger.reserved_bytes)

static func _invoke(call:Callable)->Dictionary:
	var began:=Time.get_ticks_usec();var reply:Variant=call.call()
	var packet:Dictionary=reply if reply is Dictionary else {"error":ERR_INVALID_DATA,"retained_resources":[reply]}
	packet.worker_elapsed_us=Time.get_ticks_usec()-began;return packet

func _pixels(plan:Dictionary,shared:Dictionary)->Dictionary:
	if controller.native_texture_preparer.is_valid():return controller.native_texture_preparer.call(plan,content_root,self,shared)
	return Textures.prepare(plan.sources,plan.plan,content_root,self,true,shared,true)

func _bind(model:Dictionary)->Dictionary:
	var packet:Dictionary={"error":ERR_SKIP}
	if is_cancelled():return packet
	# Borrowed reply dictionaries stay immutable and main-owned. Only the model's
	# private packet acquires these exact owners; pooled outputs are never replaced.
	var textures:Dictionary=model.pixels_result.get("uploaded_textures",{})
	for key:String in model.get("resident_tickets",{}):
		var ticket:Dictionary=model.resident_tickets[key];var row:Dictionary=model.plan.plan.rows[key]
		var texture:Texture2D=ticket.texture
		if textures.has(key) or texture.get_meta("runtime_source_sha256","")!=ticket.source_sha or model.pixels_result.get("sources",{}).get(row.path)!=ticket.source_sha or texture.get_meta("runtime_texture_representation","")!=row.representation:
			packet.error=ERR_INVALID_DATA;packet.error_message="Resident native texture changed before initial binding";return packet
		textures[key]=texture
	model.pixels_result.uploaded_textures=textures
	var state:=Binding.begin(model.result.get("packed"),model.plan["keys"],model.plan.table_sha)
	if not state.ok or not Binding.adopt(state,model.pixels_result.get("uploaded_textures",{})):
		packet.error=ERR_INVALID_DATA;packet.error_message=state.get("error","Native model texture binding failed");Binding.release(state);return packet
	while not is_cancelled():
		var progress:=Binding.step(state)
		if progress==Binding.READY:packet.error=OK;break
		if progress==Binding.FAILED:packet.error=ERR_INVALID_DATA;break
	packet.sets=int(state.sets);packet.unchanged=int(state.unchanged)
	if packet.error==OK:
		var private:Dictionary=model.result.get("private_preparation",{})
		if private.get("initial_native_cpu",false) and is_instance_valid(private.get("scene")):
			preload("res://scripts/world3d/model_texture_readiness.gd").inherit_instance(model.result.packed,private.scene)
	# The private native packet still owns its entire material graph, and the
	# pool/pixel packet still owns every texture. Only redundant references die
	# here; no final renderer owner is released on this worker.
	Binding.release(state)
	return packet

func _join_finished()->void:
	var at:=0
	while at<pending.size():
		var job:Dictionary=pending[at]
		if job.has("thread") and job.thread.is_alive():at+=1;continue
		var reply:Dictionary=job.thread.wait_to_finish() if job.has("thread") else job.reply
		if job.has("thread"):profile.threads_joined+=1
		pending.remove_at(at)
		var model:Dictionary=job.model;var stage:String=job.stage
		profile[("pixel" if stage=="pixels" else stage)+"_us"]+=int(reply.get("worker_elapsed_us",0))
		if stage=="table":
			_join_table(model,reply,job.key)
		elif stage=="geometry":
			ledger.release(job.key);model.result=reply;model.result.path=model.path
			model.result.elapsed_us=int(reply.get("worker_elapsed_us",0));model.geometry="done"
			profile.geometry_retained_bytes+=int(model.estimate.estimated_bytes)
			peak_live_estimate_bytes=maxi(peak_live_estimate_bytes,int(profile.geometry_retained_bytes)+metadata_bytes+scope.resident_metadata_bytes+ledger.reserved_bytes)
			if reply.get("error",ERR_INVALID_DATA)!=OK:model.failure=int(reply.get("error",ERR_INVALID_DATA));_stop()
			else:_queue_binding(model)
		elif stage=="pixels":
			ledger.park(job.key);scope.retained_packets.append(reply);model.pixels_result=reply
			if not str(reply.get("error","")).is_empty():model.failure=ERR_SKIP if reply.get("cancelled",false) else ERR_FILE_CORRUPT;model.failure_message=str(reply.error);_stop()
			else:
				model.pixels="waiting" if reply.get("waiting_pixels",false) else "done"
				if model.pixels=="waiting":waiting_pixels.append(model)
				else:_queue_binding(model)
		else:
			scope.retained_packets.append(reply)
			if reply.get("error",ERR_INVALID_DATA)!=OK:
				model.failure=int(reply.get("error",ERR_INVALID_DATA));model.failure_message=str(reply.get("error_message","Native texture binding cancelled"));_stop()
			elif not model.shared.is_empty() and not _handoff_model(model):
				model.failure=ERR_INVALID_DATA;model.failure_message="Native textures were not accepted by streaming residency";_stop()
			if not model.has("failure"):scope.completed_owners.merge(model.pixels_result.get("uploaded_textures",{}),true)
			ledger.release(job.key);model.binding="done";unfinished-=1;_release_table_consumer(model)

func _handoff_model(model:Dictionary)->bool:
	var keys:Array[String]=[]
	for key:String in model.plan.plan.rows:
		if not model.get("resident_tickets",{}).has(key):keys.append(key)
	return keys.is_empty() or scope.pool.handoff_streamed(model.consumer,model.pixels_result.get("uploaded_textures",{}),keys)

func _preflight_error(path:String,message:String,count_:int,started:int)->Dictionary:
	models=[{"path":path,"result":{"path":path,"error":ERR_INVALID_DATA,"elapsed_us":0,"error_message":message}}]
	return _result(count_,started)

func _result(count_:int,started:int)->Dictionary:
	var entries:Array=[];var error:=OK;var hits:=0
	for model:Dictionary in models:
		var entry:Dictionary=model.result
		if model.has("failure"):entry.error=model.failure;entry.error_message=model.get("failure_message",entry.get("error_message","Native geometry preparation failed"))
		if entry.is_empty():continue
		entry.path=model.path
		if not entry.has("error"):entry.error=ERR_SKIP
		if not entry.has("elapsed_us"):entry.elapsed_us=0
		entries.append(entry)
		if entry.error!=OK and (error==OK or (error==ERR_SKIP and entry.error!=ERR_SKIP)):error=entry.error
		if entry.error==OK:hits+=1
	var cancelled:bool=controller.is_cancelled()
	if cancelled and error==OK:error=ERR_SKIP
	scope.completed_success=error==OK and not cancelled
	var message:=""
	for entry:Dictionary in entries:
		if entry.error==error and entry.has("error_message"):message=entry.error_message;break
	# All metadata workers are joined. Drop scalar plans before returning the
	# working allowance; renderer owners stay in main-owned entries/scope.
	for model:Dictionary in models:model.plan={};model.resident_tickets={}
	for table:Dictionary in tables.values():table.plan={};table.models=[]
	if scope.resident_run!=null:scope.resident_run.close();profile.resident_bridge=scope.resident_run.snapshot()
	waiting_residents.clear();retiring_residents.clear();metadata_bytes=0;_reapply_budget()
	profile.elapsed_us=Time.get_ticks_usec()-started;profile.pool=scope.pool.snapshot();profile.ledger=ledger.snapshot()
	profile.metadata_reserved_at_return=metadata_bytes
	profile.resident_metadata_reserved_at_return=scope.resident_metadata_bytes
	return {"error":error,"error_message":message,"cancelled":cancelled,"entries":entries,"retained_resources":entries.duplicate(),"native_texture_scope":scope,
		"unique_count":count_,"worker_limit":ledger.worker_limit,"native_cache_hits":hits,"native_cache_misses":0,
		"threads_started":profile.threads_started,"threads_joined":profile.threads_joined,"fallback_count":profile.synchronous_fallbacks,
		"parallel_batches":maxi(0,int(profile.worker_slots_peak)-1),"parallel_eligible_count":count_,"eligibility_us":0,
		"inflight_budget_bytes":ledger.byte_limit,"peak_inflight_estimate_bytes":ledger.peak_bytes,"peak_inflight_jobs":ledger.peak_jobs,
		"peak_live_estimate_bytes":peak_live_estimate_bytes,
		"result_resident_estimate_bytes":profile.geometry_retained_bytes,"initial_required_resident_estimate_bytes":profile.geometry_retained_bytes,
		"inflight_reserved_at_return":ledger.reserved_bytes,"inflight_jobs_at_return":ledger.count(),"native_texture_profile":profile,
		"admission_profile":{"policy":"split_native_shared_admission_then_engine_streaming_residency","ledger_at_return":ledger.snapshot(),"native_textures":profile}}
