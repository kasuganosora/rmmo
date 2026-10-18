extends SceneTree
## CPU-only source replacement probes; never generates scenes or edits a map.
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var passed:=0
var failures:=0
var folder:=""
var path:=""
var original:=""
var replacement:=""

class TrackedResource extends RefCounted:
	var observation:Dictionary
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:observation.released_on.append(OS.get_thread_caller_id())

func _initialize()->void:run.call_deferred()

func check(value:bool,label:String)->void:
	print("PASS: " if value else "FAIL: ",label)
	if value:passed+=1
	else:failures+=1

func write_source(value:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value);file.close()

func probe(source:String)->Dictionary:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
	return {"error":OK,"observed_x":data.nodes[0].translation[0],"document":RefCounted.new()}

func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
	folder=Paths.cache_directory("model_source_transaction_%d"%Time.get_ticks_usec())
	if folder.is_empty() or DirAccess.make_dir_recursive_absolute(folder)!=OK:quit(2);return
	path=folder.path_join("model.gltf")
	original=JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"SourceA","translation":[1,0,0]}]})
	replacement=JSON.stringify({"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"SourceB","translation":[2,0,0]}]})
	write_source(original)
	var digest:=FileAccess.get_sha256(path)
	var stable:=Preparation._parse_fallback(path,Paths.external_root(),digest)
	check(stable.error==OK and stable.get("source_digest")==digest and stable.has("state") and stable.has("document"),"actual raw GLTF parser returns the expected verified source digest")
	var direct:=Preparation.parse_gltf(path,Paths.external_root(),digest)
	check(direct.error==OK and direct.get("source_digest")==digest and not direct.get("compiled",false),"direct raw fallback retains source identity after compiled-cache miss")
	var unpinned:=Preparation._parse_fallback(path,Paths.external_root())
	check(unpinned.error==OK and unpinned.get("source_digest")==digest,"raw caller without a prior digest receives the observed stable source identity")
	write_source(replacement)
	var stale:=Preparation._parse_fallback(path,Paths.external_root(),digest)
	check(stale.error==ERR_BUSY and not stale.has("document") and not stale.has("state") and not stale.has("source_digest"),"replacement before raw parse cannot be stamped with the previous source digest")
	write_source(original)
	var calls:=[0]
	var during:=Preparation._source_transaction(path,Paths.external_root(),digest,func(source:String):
		calls[0]+=1
		var consumed:=probe(source)
		write_source(replacement)
		return consumed)
	check(calls[0]==1 and during.error==ERR_BUSY and not during.has("document") and not during.has("state") and not during.has("source_digest") and during.get("retained_resources",[]).size()==1,"replacement rejects consumable state but quarantines its private resource handoff")
	during.clear()
	write_source(original)
	var observation:={"released_on":[]}
	var references:Array[WeakRef]=[]
	var worker:=Thread.new()
	var content_root:=Paths.external_root()
	var worker_parse:=func(source:String):
		var document:=TrackedResource.new();document.observation=observation
		var state:=TrackedResource.new();state.observation=observation
		references.append(weakref(document));references.append(weakref(state))
		var file:=FileAccess.open(source,FileAccess.WRITE);file.store_string(replacement);file.close()
		return {"error":OK,"document":document,"state":state}
	var transaction:=func():return Preparation._source_transaction(path,content_root,digest,worker_parse)
	var launch:=worker.start(transaction)
	check(launch==OK,"source-change resource lifetime probe starts a real CPU worker")
	if launch==OK:
		var rejected:Dictionary=worker.wait_to_finish()
		check(rejected.error==ERR_BUSY and not rejected.has("document") and not rejected.has("state") and not rejected.has("source_digest"),"worker failure exposes no model that the loader can consume")
		check(references.size()==2 and references[0].get_ref()!=null and references[1].get_ref()!=null and observation.released_on.is_empty(),"both failed parser resources remain alive after the worker joins")
		rejected.clear()
		check(references[0].get_ref()==null and references[1].get_ref()==null,"clearing the quarantined result releases both last references")
		check(observation.released_on.size()==2 and observation.released_on.all(func(thread:int):return thread==OS.get_main_thread_id()),"failed parser resources are destroyed only on the main thread")
	write_source(original)
	var matching:=Preparation._source_transaction(path,Paths.external_root(),digest,probe)
	check(matching.error==OK and matching.observed_x==1 and matching.source_digest==digest,"unchanged transaction preserves parser payload and binds its digest")
	var denied:=Preparation._source_transaction(path,folder.path_join("outside"),digest,func(_source:String):calls[0]+=1;return {"error":OK})
	check(denied.error==ERR_INVALID_PARAMETER and calls[0]==1,"controlled-root failure precedes parser side effects")
	var invalid:=Preparation._source_transaction(path,Paths.external_root(),"not-a-sha",func(_source:String):calls[0]+=1;return {"error":OK})
	check(invalid.error==ERR_INVALID_PARAMETER and calls[0]==1,"malformed expected identity is never treated as an unpinned parse")
	var preparation:=Preparation.new()
	preparation.memory_estimator=func(_source:String):return {"estimated_bytes":1,"exclusive":false}
	preparation.eligibility_checker=func(_source:String):return false
	preparation.cache_reader=func(_source:String):
		write_source(replacement)
		return {"hit":false,"reason":"forced_replacement_before_fallback"}
	var queued:=preparation.run([path],Callable(),1,Callable(),Paths.external_root(),{path:digest})
	check(queued.error==ERR_BUSY and queued.entries.size()==1 and not queued.entries[0].has("state") and queued.threads_started==queued.threads_joined and queued.inflight_reserved_at_return==0,"default coordinator rejects replacement between cache miss and raw dispatch and releases its reservation")
	write_source(original)
	preparation=Preparation.new()
	preparation.cache_reader=func(_source:String):return {"hit":false,"reason":"forced_raw"}
	var loaded:=preparation.run([path],Callable(),1,Callable(),Paths.external_root(),{path:digest})
	check(loaded.error==OK and loaded.entries.size()==1 and loaded.entries[0].source_digest==digest and not loaded.entries[0].compiled,"default coordinator successful raw entries all carry the loader-verified digest")
	stable.clear();direct.clear();unpinned.clear();matching.clear();loaded.clear()
	if Paths.allowed(path,folder):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("MODEL_SOURCE_TRANSACTION passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
