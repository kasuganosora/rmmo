extends SceneTree
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
var failures:=0
class Probe extends RefCounted:
	var mutex:=Mutex.new()
	var active:=0
	var peak:=0
	var weak:WeakRef
	func native(path:String,_candidate:Dictionary)->Dictionary:
		mutex.lock();active+=1;peak=maxi(peak,active);mutex.unlock()
		OS.delay_msec(15)
		mutex.lock();active-=1;mutex.unlock()
		if path=="miss":return {"error":OK,"fallback_required":true,"cache_reason":"missing_product"}
		var value:=RefCounted.new()
		if path=="bad":weak=weakref(value);return {"error":OK,"fallback_required":true,"packed":value}
		return {"error":OK,"compiled":true,"packed":value,"source_digest":"a".repeat(64)}
	func raw(_path:String)->Dictionary:
		OS.delay_msec(5);return {"error":OK}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func job(probe:Probe)->RefCounted:
	var result:=Preparation.new();result.inflight_byte_limit=100
	result.memory_estimator=func(_path:String):return {"estimated_bytes":60,"exclusive":false}
	result.eligibility_checker=func(_path:String):return true
	result.cache_reader=func(_path:String):return {"hit":false,"reason":"unexpected"}
	result.candidate_provider=func(_path:String):return {"estimated_bytes":20,"exclusive":false,"payload_sha":"b".repeat(64)}
	result.candidate_reader=probe.native
	return result
func larger_and_equal_bounds()->void:
	for native_bytes:int in [60,80,120]:
		var probe:=Probe.new();var controller:=job(probe)
		controller.candidate_provider=func(_path:String):return {"estimated_bytes":native_bytes,"exclusive":native_bytes>100,"payload_sha":"b".repeat(64)}
		var result:Dictionary=controller.run(["a","b","c"],probe.raw,4)
		check(result.error==OK and result.native_cache_hits==3 and result.native_cache_misses==0,"native >= raw still uses the fixed reader: "+str(native_bytes))
		check(probe.peak==1 and result.peak_inflight_jobs==1 and result.peak_inflight_estimate_bytes==native_bytes,"larger/equal bound restricts parallelism and oversized work stays exclusive: "+str(native_bytes))
		check(result.result_resident_estimate_bytes==native_bytes*3 and result.initial_required_resident_estimate_bytes==native_bytes*3,"larger/equal native result keeps its full known resident charge: "+str(native_bytes))
		check(result.inflight_reserved_at_return==0 and result.threads_started==result.threads_joined,"larger/equal bound joins and settles all in-flight credit: "+str(native_bytes))
		result.clear()
	# Opting out changes the reader, not permission to ignore its known cost.
	var previous:bool=Preparation.native_footprints_enabled
	Preparation.native_footprints_enabled=false
	for native_bytes:int in [20,80,120]:
		var controller:=job(Probe.new())
		controller.candidate_provider=func(_path:String):return {"estimated_bytes":native_bytes,"exclusive":native_bytes>100,"payload_sha":"b".repeat(64)}
		controller.cache_reader=func(_path:String):return {"hit":true,"packed":RefCounted.new()}
		var result:Dictionary=controller.run(["legacy"],func(_path:String):return {"error":ERR_BUG},4)
		var expected:int=maxi(60,native_bytes)
		check(result.error==OK and result.native_cache_hits==1 and result.peak_inflight_estimate_bytes==expected and result.result_resident_estimate_bytes==expected,"legacy opt-out reserves max(raw,native): "+str(native_bytes))
		check(result.admission_profile.tasks.legacy.memory.policy=="legacy_native_or_raw_max_envelope","legacy diagnostic identifies its combined envelope: "+str(native_bytes))
		result.clear()
	Preparation.native_footprints_enabled=previous
	# A resource-bearing source retry keeps the old packet charged until main
	# receives it; its fresh raw stage may legitimately require LESS than native.
	var controller:=job(Probe.new());var estimates:=[0];var weak:=[null];var raw_saw_native:=[false]
	controller.memory_estimator=func(_path:String):
		estimates[0]+=1;return {"estimated_bytes":40 if estimates[0]==1 else 30,"exclusive":false}
	controller.candidate_provider=func(_path:String):return {"estimated_bytes":80,"exclusive":false,"source_sha":"a".repeat(64),"payload_sha":"b".repeat(64)}
	controller.candidate_reader=func(_path:String,_candidate:Dictionary):
		var packed:=PackedScene.new();weak[0]=weakref(packed)
		return {"error":ERR_BUSY,"packed":packed,"compiled":true,"source_digest":"a".repeat(64),"native_source_retry":true,"cache_reason":"candidate_source_changed_after_read"}
	var result:Dictionary=controller.run(["retry"],func(_path:String):raw_saw_native[0]=weak[0].get_ref()!=null;return {"error":OK},4)
	var stages:Array=result.admission_profile.tasks.retry.stages
	check(result.error==OK and estimates[0]==2 and stages.size()==2 and stages[0].reserved_bytes==80 and stages[1].reserved_bytes==30,"larger native source retry obtains the fresh smaller raw reservation")
	check(raw_saw_native[0] and result.retired_native_estimate_bytes==80 and result.result_resident_estimate_bytes==110 and result.peak_live_estimate_bytes==110,"initial source retry retains and accounts both native quarantine and fresh raw output")
	check(weak[0].get_ref()!=null and result.inflight_reserved_at_return==0,"initial native retry resources survive until main takes the settled result")
	result.clear()
	check(weak[0].get_ref()==null,"main releases the larger native quarantine after receiving the complete result")
func run()->void:
	for invalid in [{"source_path":"x"},{"source_path":"x","product":"x","generator":"x","source_sha":"a".repeat(64),"payload_sha":"b".repeat(64),"bytes":"bad"}]:
		var rejected:Dictionary=preload("res://scripts/world3d/compiled_asset_preparation.gd").read("x",invalid,"x")
		check(rejected.get("fallback_required",false) and not rejected.has("packed"),"malformed fixed candidate fails before resource creation")
	var probe:=Probe.new();var controller:=job(probe)
	var result:Dictionary=controller.run(["a","b","c","miss"],probe.raw,4)
	check(result.error==OK and probe.peak==4 and result.peak_inflight_estimate_bytes<=100,"four bounded native products run concurrently within the same byte budget")
	var tasks:Dictionary=result.admission_profile.tasks
	check(tasks.miss.stages.size()==2 and tasks.miss.stages[0].reserved_bytes==20 and tasks.miss.stages[1].reserved_bytes==60,"native miss re-enters the full raw budget as a separate stage")
	check(result.result_resident_estimate_bytes==120 and tasks.miss.retained_charge_bytes==60 and tasks.a.retained_charge_bytes==20,"retained results use their actual admitted stage charge")
	check(result.inflight_jobs_at_return==0 and result.inflight_reserved_at_return==0 and result.threads_joined==result.threads_started,"all workers and byte reservations settle")
	result.clear()
	probe=Probe.new();controller=job(probe)
	result=controller.run(["bad"],probe.raw,4)
	check(result.error==ERR_INVALID_DATA and result.native_cache_misses==0 and not result.admission_profile.stages.has("raw_import"),"resource-bearing failure never enters raw fallback")
	check(probe.weak.get_ref()!=null,"failed native resource survives coordinator return for main disposal")
	result.clear()
	check(probe.weak.get_ref()==null,"main releases the failed resource after taking the result")
	probe=Probe.new();controller=job(probe);controller.cancel()
	result=controller.run(["a"],probe.raw,4)
	check(result.cancelled and result.entries.is_empty() and probe.peak==0,"cancel before dispatch creates no native resources")
	larger_and_equal_bounds()
	print("NATIVE_MODEL_BUDGET failures=",failures)
	quit(0 if failures==0 else 1)
