extends RefCounted
## One mounted operation's immutable source metadata, never pixels or RIDs.
## Call on the scheduler owner only. Workers borrow immutable row values from
## private plan dictionaries. Explicit source refresh starts a new generation.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const ModelBinding=preload("res://scripts/world3d/model_texture_bindings.gd")
const MAX_ENTRIES=1024
const RESERVED_BYTES=16*1024*1024 # 16 KiB/entry, capped 1024-character source/root keys.
var _rows:Dictionary={}
var _context:Array=[]
var hits:=0
var misses:=0
var _pending:Dictionary={}
var _serial:=0
var revision:=0
var async_reads:=0
var async_total_us:=0
var async_max_us:=0
var start_max_us:=0
var error:=""
# CPU-only dependency injection for deterministic blocked-I/O tests.
var header_reader:Callable=_read_header
var model_reader:Callable=_read_model
# A byte-bounded cache, never a model-count limit. Active consumers may retain
# a larger table; its full conservative metadata cost remains accounted.
var native_cache_bytes:=RESERVED_BYTES
var _models:Dictionary={}
var _model_budgets:Dictionary={}
var _model_cache_order:Dictionary={}
var _native_consumers:=0
var _native_retired:=0
var native_hits:=0
var native_async_reads:=0
var native_async_total_us:=0
var native_async_max_us:=0
var native_metadata_reserved_bytes:=0

func reset()->void:
	abandon();_rows.clear();_context.clear();hits=0;misses=0
	async_reads=0;async_total_us=0;async_max_us=0;start_max_us=0;error="";revision+=1
	native_hits=0;native_async_reads=0;native_async_total_us=0;native_async_max_us=0

func _set_context(root:String)->void:
	var context:Array=[root,Paint.source_generation,Paint.compressed_sidecars_enabled,Prep.Pixels.upload_preparation_enabled,Prep.Streamed.enabled()]
	if context!=_context:
		abandon();_rows.clear();_context=context;revision+=1

static func _read_header(key:String,source:Array,root:String)->Dictionary:
	return Prep.estimate({key:source},root).rows.get(key,{})

static func _prepare(reader:Callable,key:String,source:Array,root:String,token:RefCounted)->Dictionary:
	var began:=Time.get_ticks_usec()
	var row:Dictionary={} if token.is_cancelled() else reader.call(key,source,root)
	return {"row":row,"elapsed_us":Time.get_ticks_usec()-began}

static func _read_model(candidate:Dictionary,root:String,_token:RefCounted)->Dictionary:
	return ModelBinding.candidate_plan(candidate,root,{})

static func _scalar_metadata(value:Variant)->bool:
	# The normal reader constructs scalars from JSON only. Keep the injectable
	# reader's result under that same CPU-only Drainer ownership contract.
	if value is Dictionary:
		for key:Variant in value:
			if not (key is String or key is StringName) or not _scalar_metadata(value[key]):return false
		return true
	if value is Array:
		for item:Variant in value:
			if not _scalar_metadata(item):return false
		return true
	return value==null or value is bool or value is int or value is float or value is String or value is StringName

static func _prepare_model(reader:Callable,candidate:Dictionary,root:String,token:RefCounted)->Dictionary:
	var began:=Time.get_ticks_usec()
	var prepared:Dictionary={"ok":false,"error":"Native texture preparation cancelled"} if token.is_cancelled() else reader.call(candidate,root,token)
	# The production JSON reader already constructs only scalar table data.
	# Audit custom test readers, without walking every production
	# row a second time merely to rediscover that construction contract.
	if reader!=_read_model and not _scalar_metadata(prepared):prepared={"ok":false,"error":"Native texture plan must contain scalar metadata only"}
	return {"row":prepared,"elapsed_us":Time.get_ticks_usec()-began}

func _model_descriptor(candidate:Dictionary)->Dictionary:
	var descriptor:Variant=candidate.get("texture_table")
	var products=ModelBinding.Products
	if not descriptor is Dictionary or descriptor.get("version")!=products.VERSION or not products._sha(descriptor.get("sha256")) or not products._integer(descriptor.get("bytes"),products.MAX_JSON_INTEGER,1) or not products._integer(descriptor.get("textures"),products.MAX_JSON_INTEGER) or not products._integer(descriptor.get("image_bytes"),products.MAX_JSON_INTEGER):
		error="Invalid native model texture descriptor";return {}
	return {"version":products.VERSION,"sha256":descriptor.sha256,"bytes":int(descriptor.bytes),"textures":int(descriptor.textures),"image_bytes":int(descriptor.image_bytes)}

static func _model_key(descriptor:Dictionary,root:String)->String:
	return "native_table:"+root.replace("\\","/").simplify_path()+":"+str(descriptor.sha256)

func _same_model_descriptor(entry:Dictionary,descriptor:Dictionary)->bool:
	if entry.descriptor==descriptor:return true
	error="Conflicting native model texture descriptor";return false

func _model_estimate(descriptor:Dictionary,root:String)->Dictionary:
	# Conservative scheduling bounds, not measured RSS: JSON bytes/UTF strings,
	# parsed dictionaries, final row/source/key maps, mip arrays and path copies.
	var metadata_float:float=4096.0+float(descriptor.bytes)*2.0+float(descriptor.textures)*(8192.0+float(root.length())*24.0)+float(root.length())*8.0
	var workspace_float:float=65536.0+float(descriptor.bytes)*32.0+metadata_float*2.0
	if workspace_float>=9223372036854775807.0:
		error="Native texture metadata estimate exceeds supported integer accounting";return {}
	return {"estimated_bytes":int(workspace_float),"metadata_bytes":int(metadata_float),"exclusive":false,"stage":"native_texture_table"}

func prepare_model_async(candidate:Dictionary,root:String,admission:RefCounted,tree:SceneTree,consumer:String="")->bool:
	root=root.replace("\\","/").simplify_path();_set_context(root)
	var descriptor:=_model_descriptor(candidate)
	if descriptor.is_empty():return false
	var key:=_model_key(descriptor,root)
	if _models.has(key):
		var entry:Dictionary=_models[key]
		if not _same_model_descriptor(entry,descriptor):return false
		if not entry.visible:_native_retired-=1
		entry.visible=true;_touch_model(entry);_pin_model(entry,consumer)
		if not entry.prepared.get("ok",false):error=str(entry.prepared.get("error","Native texture table preparation failed"));return false
		return true
	if _pending.has(key):
		var job:Dictionary=_pending[key]
		if not _same_model_descriptor(job,descriptor):return false
		_pin_model(job,consumer)
		return false
	var estimate:=_model_estimate(descriptor,root)
	if estimate.is_empty():return false
	_trim_models(admission,int(estimate.estimated_bytes))
	var scope:Dictionary=_model_budgets.get(admission.get_instance_id(),{})
	# One necessary oversize table may enter the ordinary exclusive policy.
	# Once ready it can feed its model, but more new tables wait for consumers
	# to release metadata. There is no persistent admission entry blocking that
	# model's own exclusive geometry/pixel job.
	if not scope.is_empty() and int(scope.bytes)>=int(scope.base_limit):return false
	var lease_key:="native_texture_table:%d:%d"%[get_instance_id(),_serial];_serial+=1
	if not admission.reserve(lease_key,estimate):return false
	var worker:=Thread.new();var token:=Drainer.CancelToken.new()
	token.set_meta("cpu_metadata_only",true)
	token.set_meta("admission_owner",admission);token.set_meta("admission_release",admission.release.bind(lease_key))
	var drainer:=Drainer.for_tree(tree);drainer.watch(worker,token)
	var began:=Time.get_ticks_usec()
	var code:=_start(worker,_prepare_model.bind(model_reader,{"texture_table":descriptor},root,token))
	start_max_us=maxi(start_max_us,Time.get_ticks_usec()-began)
	if code!=OK:
		drainer.forget(worker);admission.release(lease_key)
		token.remove_meta("admission_owner");token.remove_meta("admission_release")
		error="Cannot start native texture table preparation: "+str(descriptor.sha256);return false
	var consumers:Dictionary={}
	if not consumer.is_empty():consumers[consumer]=true;_native_consumers+=1
	_pending[key]={"kind":"native","worker":worker,"token":token,"drainer":drainer,"lease_key":lease_key,"admission":admission,
		"descriptor":descriptor,"metadata_bytes":int(estimate.metadata_bytes),"consumers":consumers}
	return false

func model_plan(candidate:Dictionary,root:String)->Dictionary:
	var descriptor:=_model_descriptor(candidate)
	if descriptor.is_empty():return {}
	var key:=_model_key(descriptor,root)
	if not _models.has(key) or not _models[key].visible:return {}
	var entry:Dictionary=_models[key]
	if not _same_model_descriptor(entry,descriptor):return {"ok":false,"error":error}
	native_hits+=1;_touch_model(entry)
	# Borrowed immutable scalars. Retain a consumer before keeping this result
	# across other catalog calls, task dispatch, yields or source resets.
	return entry.prepared

func retain_model(candidate:Dictionary,root:String,consumer:String)->bool:
	if consumer.is_empty():return false
	var descriptor:=_model_descriptor(candidate)
	if descriptor.is_empty():return false
	var key:=_model_key(descriptor,root)
	var entry:Dictionary=_models.get(key,_pending.get(key,{}))
	if entry.is_empty() or not _same_model_descriptor(entry,descriptor):return false
	_pin_model(entry,consumer);return true

func release_model(candidate:Dictionary,root:String,consumer:String)->void:
	var descriptor:Variant=candidate.get("texture_table")
	if consumer.is_empty() or not descriptor is Dictionary or not descriptor.has("sha256"):return
	var key:=_model_key(descriptor,root)
	if _pending.has(key):
		var job:Dictionary=_pending[key]
		if not job.get("consumers",{}).has(consumer):return
		job.consumers.erase(consumer);_native_consumers-=1
		if job.consumers.is_empty():_abandon_job(job);_pending.erase(key);revision+=1
		return
	if not _models.has(key):return
	var entry:Dictionary=_models[key]
	if not entry.consumers.has(consumer):return
	entry.consumers.erase(consumer);_native_consumers-=1
	if entry.consumers.is_empty() and (not entry.visible or int(entry.metadata_bytes)>native_cache_bytes):_erase_model(key)
	else:
		if entry.consumers.is_empty():_set_model_cached(entry,true)
		_trim_models(entry.admission)
	revision+=1

func _touch_model(entry:Dictionary)->void:
	if entry.get("cached",false):_model_cache_order.erase(entry.key);_model_cache_order[entry.key]=true

func _pin_model(entry:Dictionary,consumer:String)->void:
	if consumer.is_empty() or entry.consumers.has(consumer):return
	if entry.get("cached",false):_set_model_cached(entry,false)
	entry.consumers[consumer]=true;_native_consumers+=1

func _set_model_cached(entry:Dictionary,cached:bool)->void:
	if entry.get("cached",false)==cached:return
	entry.cached=cached
	var scope:Dictionary=_model_budgets[entry.admission.get_instance_id()]
	scope.cached_bytes+=int(entry.metadata_bytes)*(1 if cached else -1)
	if cached:_model_cache_order[entry.key]=true
	else:_model_cache_order.erase(entry.key)

func _metadata_charge(admission:RefCounted,amount:int)->void:
	var id:int=admission.get_instance_id()
	if not _model_budgets.has(id):_model_budgets[id]={"admission":admission,"bytes":0,"cached_bytes":0,"deducted":0,"base_limit":admission.byte_limit}
	var scope:Dictionary=_model_budgets[id]
	scope.base_limit=int(admission.byte_limit)+int(scope.deducted)
	scope.bytes+=amount;native_metadata_reserved_bytes+=amount
	assert(scope.bytes>=0 and native_metadata_reserved_bytes>=0)
	scope.deducted=mini(int(scope.bytes),maxi(0,int(scope.base_limit)-1))
	admission.byte_limit=int(scope.base_limit)-int(scope.deducted)
	if scope.bytes==0:_model_budgets.erase(id)

func reapply_metadata_budget(admission:RefCounted)->void:
	# Call once AFTER the owner recalculates its full working byte limit. Never
	# deduct this again from reserved_bytes: those entries cover running jobs.
	var scope:Dictionary=_model_budgets.get(admission.get_instance_id(),{})
	if scope.is_empty():return
	scope.base_limit=int(admission.byte_limit)
	scope.deducted=mini(int(scope.bytes),maxi(0,int(scope.base_limit)-1))
	admission.byte_limit=int(scope.base_limit)-int(scope.deducted)

func _erase_model(key:String)->void:
	var entry:Dictionary=_models[key]
	_set_model_cached(entry,false)
	if not entry.visible:_native_retired-=1
	_models.erase(key);entry.prepared={}
	_metadata_charge(entry.admission,-int(entry.metadata_bytes));revision+=1

func _trim_models(admission:RefCounted,workspace:int=0,keep:String="")->void:
	while true:
		var scope:Dictionary=_model_budgets.get(admission.get_instance_id(),{})
		if scope.is_empty():return
		var need_workspace:bool=workspace>0 and admission.reserved_bytes+workspace>admission.byte_limit
		if int(scope.cached_bytes)<=native_cache_bytes and not need_workspace:return
		var oldest:=""
		# Ordered unpinned keys make normal lookup/dispatch O(1); walk only when
		# an actual eviction is required, never rescan every table per request.
		for key:String in _model_cache_order:
			if key!=keep and _models[key].admission==admission:oldest=key;break
		if oldest.is_empty():return
		_erase_model(oldest)

func _hide_models()->void:
	for key:String in _models.keys():
		var entry:Dictionary=_models[key]
		if entry.visible:entry.visible=false;_native_retired+=1
		if entry.consumers.is_empty():_erase_model(key)

static func _abandon_job(job:Dictionary)->void:
	if is_instance_valid(job.drainer) and job.drainer.is_inside_tree():job.drainer.abandon(job.worker)
	else:Drainer.drain_shutdown(job.worker,job.token)

func _start(worker:Thread,task:Callable)->Error:return worker.start(task)

func prepare_async(requested:Dictionary,root:String,admission:RefCounted,tree:SceneTree)->bool:
	# Preserve the existing standalone/strict and bounded-cache fallback. Normal
	# mounted sources use the SAME worker/byte ledger as geometry and pixels.
	if not Prep.Pixels.Policy.trusted() or not Prep.valid_sources(requested) or preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures:return true
	_set_context(root)
	var ready:=true
	for key:String in requested:
		if _rows.has(key):continue
		if _pending.has(key):ready=false;continue
		if root.length()>1024 or key.length()>1024 or _rows.size()+_pending.size()>=MAX_ENTRIES:continue
		ready=false
		if not admission.has_capacity():return false
		var lease_key:="texture_header:%d:%d"%[get_instance_id(),_serial];_serial+=1
		if not admission.reserve(lease_key,{"estimated_bytes":65536,"exclusive":false,"stage":"texture_header"}):continue
		var worker:=Thread.new();var token:=Drainer.CancelToken.new()
		token.set_meta("cpu_metadata_only",true)
		token.set_meta("admission_owner",admission);token.set_meta("admission_release",admission.release.bind(lease_key))
		var drainer:=Drainer.for_tree(tree);drainer.watch(worker,token)
		var began:=Time.get_ticks_usec()
		var code:=_start(worker,_prepare.bind(header_reader,key,requested[key].duplicate(),root,token))
		start_max_us=maxi(start_max_us,Time.get_ticks_usec()-began)
		if code!=OK:
			drainer.forget(worker);admission.release(lease_key)
			token.remove_meta("admission_owner");token.remove_meta("admission_release")
			error="Cannot start texture header preparation: "+key
			return false # Never retry forever or fall back to main-thread I/O.
		_pending[key]={"worker":worker,"token":token,"drainer":drainer,"lease_key":lease_key,"admission":admission}
	return ready

func poll()->void:
	for key:String in _pending.keys():
		var job:Dictionary=_pending[key]
		if job.worker.is_alive():continue
		var result:Dictionary=job.worker.wait_to_finish()
		job.drainer.forget(job.worker)
		if job.get("kind")=="native":
			var prepared:Dictionary=result.row
			var charge:int=int(job.metadata_bytes) if prepared.get("ok",false) else mini(4096,int(job.metadata_bytes))
			var entry:={"key":key,"descriptor":job.descriptor,"prepared":prepared,"metadata_bytes":charge,"admission":job.admission,"consumers":job.consumers,"visible":true,"cached":false}
			_models[key]=entry;_metadata_charge(job.admission,charge)
			if entry.consumers.is_empty():_set_model_cached(entry,true)
			native_async_reads+=1;native_async_total_us+=int(result.elapsed_us);native_async_max_us=maxi(native_async_max_us,int(result.elapsed_us))
			if not prepared.get("ok",false):error=str(prepared.get("error","Native texture table preparation failed"))
		else:
			_rows[key]=result.row;misses+=1;async_reads+=1
			async_total_us+=int(result.elapsed_us);async_max_us=maxi(async_max_us,int(result.elapsed_us))
		job.admission.release(job.lease_key)
		job.token.remove_meta("admission_release");job.token.remove_meta("admission_owner")
		_pending.erase(key);revision+=1
		if job.get("kind")=="native":_trim_models(job.admission,0,key)

func pending_count()->int:return _pending.size()

func abandon()->void:
	for job:Dictionary in _pending.values():
		_native_consumers-=job.get("consumers",{}).size()
		_abandon_job(job)
	_pending.clear();_hide_models();revision+=1

func shutdown()->void:
	for job:Dictionary in _pending.values():
		_native_consumers-=job.get("consumers",{}).size()
		job.drainer.forget(job.worker);Drainer.drain_shutdown(job.worker,job.token)
	_pending.clear();_hide_models();revision+=1

func estimate(requested:Dictionary,root:String)->Dictionary:
	if not Prep.Pixels.Policy.trusted():return Prep.estimate(requested,root)
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures or not Prep.valid_sources(requested):return {"rows":{},"estimated_bytes":0,"output_bytes":0}
	_set_context(root)
	var result:Dictionary={};var output:=0;var scratch:=0
	var keys:Array=requested.keys();keys.sort()
	for key:String in keys:
		var row:Dictionary={}
		if _rows.has(key):row=_rows[key];hits+=1
		else:
			row=header_reader.call(key,requested[key],root);misses+=1
			# Long/unusual paths retain the original uncached behavior; this is a
			# cache bound, not a new package validation or authoring restriction.
			if _rows.size()<MAX_ENTRIES and key.length()<=1024 and root.length()<=1024:_rows[key]=row
		if row.is_empty():continue
		result[key]=row;output+=int(row.output_bytes);scratch=maxi(scratch,Prep.workspace_bytes(row))
	return {"rows":result,"estimated_bytes":output*2+scratch,"output_bytes":output}

func snapshot()->Dictionary:
	var native_pending:=0
	for job:Dictionary in _pending.values():
		if job.get("kind")=="native":native_pending+=1
	return {"hits":hits,"misses":misses,"entries":_rows.size(),"reserved_bytes":RESERVED_BYTES,"pending_headers":_pending.size()-native_pending,"async_reads":async_reads,"async_total_us":async_total_us,"async_max_us":async_max_us,"start_max_us":start_max_us,
		"native_entries":_models.size(),"native_retired_entries":_native_retired,"pending_native_tables":native_pending,"native_consumers":_native_consumers,"native_hits":native_hits,"native_async_reads":native_async_reads,"native_async_total_us":native_async_total_us,"native_async_max_us":native_async_max_us,"native_metadata_reserved_bytes":native_metadata_reserved_bytes}
