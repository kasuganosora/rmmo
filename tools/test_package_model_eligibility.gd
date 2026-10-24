extends SceneTree
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func job(path:String,hints:Dictionary,checker:Callable=Callable())->Dictionary:
	var preparation:=Preparation.new();preparation.static_scene_paths=hints
	preparation.eligibility_checker=checker
	preparation.cache_reader=func(_path:String):return {"hit":false,"reason":"fixture"}
	preparation.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false}
	return preparation.run([path],func(_path:String):return {"error":OK,"token":"unchanged"})
func run()->void:
	var path:="no_file_is_opened_by_the_injected_parser.glb"
	Controls.white_materials=true;Controls.discard_map_textures=true
	var trials:Array=[]
	for variant:int in 5:
		Policy.verify_packages=variant==2;Controls.discard_map_textures=variant!=3
		var hints:Dictionary={path:{"known":variant!=1}}
		if variant==4:hints={}
		var result:=job(path,hints)
		check(result.error==OK and result.entries[0].token=="unchanged","parse result and scheduler ownership are unchanged")
		trials.append({"variant":variant,"serial_fallbacks":result.serial_fallbacks})
		if variant==0:check(result.serial_fallbacks==0,"trusted static white observation removes both redundant eligibility scans")
		if variant!=0:check(result.serial_fallbacks==1,"untrusted, unknown or textured routes retain conservative eligibility")
	Policy.verify_packages=false;Controls.discard_map_textures=true
	var checks:Array=[0]
	var result:=job(path,{path:{}},func(_path:String):checks[0]+=1;return checks[0]==1)
	check(checks[0]==2 and result.serial_fallbacks==1,"explicit eligibility checker still detects a changed route at import")
	# The real large package is only read; injected parsing avoids GPU allocation.
	var real_path:="D:/code/rmmo_runtime/packs/default/assets/7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd.glb"
	var began:=Time.get_ticks_usec();result=job(real_path,{real_path:{}})
	trials.append({"real_model_us":Time.get_ticks_usec()-began,"serial_fallbacks":result.serial_fallbacks})
	check(result.error==OK and result.serial_fallbacks==0,"real package model preserves its parallel raw route")
	Controls.white_materials=false;Controls.discard_map_textures=false
	print("PACKAGE_MODEL_ELIGIBILITY ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
