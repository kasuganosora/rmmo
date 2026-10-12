extends SceneTree
const Policy=preload("res://scripts/world3d/definition_cache_policy.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
var failures:=0

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func run()->void:
	Policy.configure()
	check(Policy.reserved_bytes()==0 and Policy.work_budget(64*1024*1024)==64*1024*1024,"default leaves admission unchanged")
	Policy.enabled=true;Policy.configure()
	var generation:int=Policy.snapshot().generation
	Policy.configure()
	check(Policy.snapshot().generation==generation,"another loader with same policy keeps resident generation")
	var job:=Preparation.new();job.inflight_byte_limit=64*1024*1024
	job.memory_estimator=func(_path:String):return {"estimated_bytes":40*1024*1024,"exclusive":false}
	var result:Dictionary=job.run(["one","two"],func(path:String):return {"error":OK,"token":path},2)
	check(result.error==OK and result.entries.size()==2,"oversized work still completes after retained reserve")
	check(result.inflight_budget_bytes+Policy.reserved_bytes()==job.inflight_byte_limit,"retained capacity fits inside existing allowance")
	check(result.peak_inflight_jobs==1 and result.inflight_jobs_at_return==0 and result.inflight_reserved_at_return==0,"cache reserve is not a lease that deadlocks exclusive work")
	var deferred:=Deferred.new();deferred._configure_admission_budget()
	var physical:=int(OS.get_memory_info().get("physical",16*1024*1024*1024))
	check(deferred._admission.byte_limit+Policy.reserved_bytes()==clampi(physical/4,512*1024*1024,8*1024*1024*1024),"stream admission charges the same reserve")
	deferred.free()
	job=Preparation.new();job.cancel()
	result=job.run(["never"],func(_path:String):return {"error":OK})
	check(result.cancelled and result.entries.is_empty(),"retained cache does not bypass cancelled preparation")
	Policy.enabled=false;Policy.configure()
	check(Policy.reserved_bytes()==0 and Store.definition_cache_stats().resident_bytes==0,"disabled comparison releases retained capacity")
	print("DEFINITION_CACHE_POLICY failures=",failures)
	quit(1 if failures else 0)
