extends SceneTree
## Experimental cache measurement only. Run on the private graphics desktop.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Footprint=preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Reader=preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Estimate=preload("res://scripts/world3d/asset_memory_estimate.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const BASE="D:/code/rmmo_runtime/review_artifacts/shared_resource_20261010"
var output:=BASE+"/candidate.json"
var mode:="build"
var input:="D:/code/rmmo_runtime/review_artifacts/native_budget_20261010/initial_paths.json"
var content_root:=""
var identities:Dictionary={}
var descriptors:Dictionary={}
var estimates:Dictionary={}
var pool:RefCounted
var active_worker:Thread
var active_job:RefCounted
var timed_out:=false
var report:Dictionary={"failures":0,"models":[],"runs":[]}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->bool:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:report.failures+=1
	return ok
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
func timeout()->void:
	timed_out=true;report.timeout=true;report.failures+=1
	if active_job!=null:active_job.cancel()
	# The normal bench coroutine owns the join and main-thread release.
	# Do not quit while a worker may still own GPU resources.
	if active_worker==null:
		if pool!=null:pool.dispose();pool=null
		persist();quit(2)
static func sha(value:Variant)->String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(var_to_bytes(value));return hash_.finish().hex_encode()
func value_digest(value:Variant,cache:Dictionary)->String:
	if value is Resource:
		var id:int=value.get_instance_id()
		if cache.has(id):return cache[id]
		var properties:Dictionary={"class":value.get_class()}
		if value is ImageTexture or value is Image:
			var image:Image=value.get_image() if value is ImageTexture else value
			properties.pixels=sha([image.get_width(),image.get_height(),image.get_format(),image.has_mipmaps(),image.get_data()])
		for info:Dictionary in value.get_property_list():
			var key:String=info.name
			if int(info.usage)&PROPERTY_USAGE_STORAGE==0 or key in ["resource_scene_unique_id","resource_path","script"]:continue
			if value is ImageTexture and key=="image":continue
			if value is Image and key=="data":continue
			properties[key]=value_digest(value.get(key),cache)
		var result:=value_digest(properties,cache);cache[id]=result;return result
	if value is Dictionary:
		var keys:Array=value.keys();keys.sort_custom(func(a,b):return str(a)<str(b))
		var pairs:Array=[]
		for key in keys:pairs.append([value_digest(key,cache),value_digest(value[key],cache)])
		return sha(pairs)
	if value is Array:
		var values:Array=[]
		for item in value:values.append(value_digest(item,cache))
		return sha(values)
	return sha(value)
func fingerprint(packed:PackedScene)->String:
	var state:=packed.get_state();var rows:Array=[];var cache:Dictionary={}
	for node in state.get_node_count():
		var properties:Dictionary={}
		for index in state.get_node_property_count(node):
			properties[str(state.get_node_property_name(node,index))]=value_digest(state.get_node_property_value(node,index),cache)
		rows.append([str(state.get_node_path(node)),str(state.get_node_type(node)),value_digest(properties,cache)])
	return sha(rows)
func original(path:String)->Dictionary:return Reader.read(path,identities[path],content_root)
func shared(path:String)->Dictionary:return pool.read(descriptors[path])
func run()->void:
	create_timer(360).timeout.connect(timeout)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
		elif arg.begins_with("--input="):input=arg.trim_prefix("--input=")
	if not Paths.allowed(output,BASE) or DisplayServer.get_name()=="headless":quit(2);return
	content_root=Paths.external_root();Engine.max_fps=60
	var sources:Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not sources is Array or sources.is_empty() or sources.size()>32:quit(2);return
	var candidate:Script=load("res://tools/shared_texture_cook_candidate.gd")
	if candidate==null:quit(2);return
	var saved:Dictionary={}
	if mode=="bench":saved=JSON.parse_string(FileAccess.get_file_as_string(BASE+"/candidate.json"))
	for path:String in sources:
		var identity:=Footprint._identity(path,content_root)
		if identity.is_empty():check(false,"native identity required: "+path);persist();quit(1);return
		identities[path]=identity
		var raw:Dictionary=Estimate.estimate(path)
		var native:Dictionary=Footprint.candidate(path,content_root)
		estimates[path]={"estimated_bytes":mini(int(raw.estimated_bytes),int(native.get("estimated_bytes",raw.estimated_bytes))),"exclusive":false}
		if mode=="build":
			var built:Dictionary=candidate.build(path,BASE+"/cook")
			check(built.get("error",FAILED)==OK,"shared texture candidate builds: "+path.get_file())
			if built.get("error",FAILED)!=OK:report.models.append(built);persist();quit(1);return
			descriptors[path]=built.descriptor
			var baseline:Dictionary=original(path)
			check(baseline.get("error",FAILED)==OK and baseline.get("packed")!=null,"baseline read succeeds")
			if baseline.get("packed")==null:persist();quit(1);return
			var expected:=fingerprint(baseline.packed)
			Drainer.synchronize_transfer();baseline.clear()
			pool=candidate.Pool.new()
			var restored:Dictionary=shared(path)
			check(restored.get("error",FAILED)==OK and restored.get("packed")!=null,"shared texture reconstruction succeeds")
			var actual:=fingerprint(restored.packed) if restored.get("packed")!=null else ""
			check(expected==actual,"complete scene, geometry, material, metadata and all mip pixel identity")
			report.models.append({"path":path,"descriptor":built.descriptor,"stats":built.stats,"expected":expected,"actual":actual})
			Drainer.synchronize_transfer();restored.clear();pool.dispose();pool=null
			persist();await process_frame
		else:
			for model:Dictionary in saved.models:
				if model.path==path:descriptors[path]=model.descriptor
	if mode=="bench":
		for enabled:bool in [false,true,true,false]:
			pool=candidate.Pool.new()
			var job:=Preparation.new();job.memory_estimator=func(path:String):return estimates[path].duplicate()
			var parser:Callable=shared if enabled else original
			var worker:=Thread.new();var started:=Time.get_ticks_usec()
			active_worker=worker;active_job=job
			if not check(worker.start(job.run.bind(sources,parser,4))==OK,"parallel batch starts"):
				active_worker=null;active_job=null;pool.dispose();pool=null
				persist();quit(1);return
			while worker.is_alive():await process_frame
			var result:Dictionary=worker.wait_to_finish()
			var elapsed:=Time.get_ticks_usec()-started
			check(result.error==OK and result.entries.size()==sources.size(),"batch returns complete successful resources")
			var run_:Dictionary={"shared":enabled,"elapsed_us":elapsed,"preparation_us":result.elapsed_us,"admission":result.admission_profile,"peak_jobs":result.peak_inflight_jobs}
			var stats:Array=[]
			for entry:Dictionary in result.entries:stats.append(entry.get("stats",{}))
			run_.stats=stats;report.runs.append(run_);print("SHARED_COOK_RUN ",enabled," ",elapsed/1000.)
			Drainer.synchronize_transfer();result.clear();pool.dispose();pool=null
			active_worker=null;active_job=null
			if timed_out:persist();quit(2);return
			persist();await process_frame
	persist();print("SHARED_COOK_COMPLETE failures=",report.failures);quit(0 if report.failures==0 else 1)
