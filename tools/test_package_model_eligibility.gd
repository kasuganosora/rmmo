extends SceneTree
## Raw authoring imports are exclusive; native-only reads must never fall back
## to an authoring source. No model or GPU resource is opened by this fixture.
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func job(path:String,checker:Callable=Callable())->Dictionary:
	var preparation:=Preparation.new()
	preparation.eligibility_checker=checker
	preparation.cache_reader=func(_path:String):return {"hit":false,"reason":"fixture"}
	preparation.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false}
	return preparation.run([path],func(_path:String):return {"error":OK,"token":"unchanged"})
func run()->void:
	var path:="no_file_is_opened_by_the_injected_parser.glb"
	var previous_policy:=Policy.verify_packages
	for strict:bool in [false,true]:
		Policy.verify_packages=strict
		var result:=job(path)
		check(result.error==OK and result.entries[0].token=="unchanged" and result.serial_fallbacks==1,"unknown authoring source uses the conservative serial fallback")
	var checks:Array=[0]
	var changed:=job(path,func(_path:String):checks[0]+=1;return checks[0]==1)
	check(checks[0]==2 and changed.serial_fallbacks==1 and changed.error==OK,"eligibility is rechecked and a changed route becomes serial")
	check(Preparation.try_enter_raw_import(true),"first private authoring import acquires the gate")
	check(not Preparation.try_enter_raw_import(true),"a second private import cannot overlap the first")
	check(not Preparation.try_enter_raw_import(false),"ordinary raw import cannot overlap the first")
	Preparation.leave_raw_import()
	check(Preparation.try_enter_raw_import(false),"gate is released after the owner finishes")
	Preparation.leave_raw_import()
	var native:=Preparation.new();native.require_native_products=true
	var calls:Array=[0]
	var rejected:Dictionary=native._guarded_fallback(path,func(_path:String):calls[0]+=1;return {"error":OK},false)
	check(rejected.get("error",OK)!=OK and calls[0]==0,"native-only rejects raw fallback before authoring input is touched")
	Policy.verify_packages=previous_policy
	print("PACKAGE_MODEL_ELIGIBILITY ",JSON.stringify({"failures":failures}));quit(1 if failures else 0)
