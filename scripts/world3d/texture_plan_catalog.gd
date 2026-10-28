extends RefCounted
## One mounted operation's immutable source metadata, never pixels or RIDs.
## Call on the scheduler owner only. Workers borrow immutable row values from
## private plan dictionaries. Explicit source refresh starts a new generation.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
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

func reset()->void:
	abandon();_rows.clear();_context.clear();hits=0;misses=0
	async_reads=0;async_total_us=0;async_max_us=0;start_max_us=0;error="";revision+=1

func _set_context(root:String)->void:
	var context:Array=[root,Paint.source_generation,Paint.compressed_sidecars_enabled,Prep.Pixels.upload_preparation_enabled]
	if context!=_context:
		abandon();_rows.clear();_context=context;revision+=1

static func _read_header(key:String,source:Array,root:String)->Dictionary:
	return Prep.estimate({key:source},root).rows.get(key,{})

static func _prepare(reader:Callable,key:String,source:Array,root:String,token:RefCounted)->Dictionary:
	var began:=Time.get_ticks_usec()
	var row:Dictionary={} if token.is_cancelled() else reader.call(key,source,root)
	return {"row":row,"elapsed_us":Time.get_ticks_usec()-began}

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
		_rows[key]=result.row;misses+=1;async_reads+=1
		async_total_us+=int(result.elapsed_us);async_max_us=maxi(async_max_us,int(result.elapsed_us))
		job.admission.release(job.lease_key)
		job.token.remove_meta("admission_release");job.token.remove_meta("admission_owner")
		_pending.erase(key);revision+=1

func pending_count()->int:return _pending.size()

func abandon()->void:
	for job:Dictionary in _pending.values():
		if is_instance_valid(job.drainer) and job.drainer.is_inside_tree():job.drainer.abandon(job.worker)
		else:Drainer.drain_shutdown(job.worker,job.token)
	_pending.clear();revision+=1

func shutdown()->void:
	for job:Dictionary in _pending.values():
		job.drainer.forget(job.worker);Drainer.drain_shutdown(job.worker,job.token)
	_pending.clear();revision+=1

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

func snapshot()->Dictionary:return {"hits":hits,"misses":misses,"entries":_rows.size(),"reserved_bytes":RESERVED_BYTES,"pending_headers":_pending.size(),"async_reads":async_reads,"async_total_us":async_total_us,"async_max_us":async_max_us,"start_max_us":start_max_us}
