extends SceneTree
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var queue:=Deferred.new();var owner:=PackedScene.new()
	var digest:="a".repeat(64);owner.set_meta("_rmmo_source_digest",digest)
	var paths:Array[String]=[]
	for i:int in 640:
		var path:="test://demanded_template_scan/%d"%i
		paths.append(path);Assets._scenes[path]=owner
		queue.source_signatures[path]=digest;queue._prepared_paths[path]=true
	var required:Dictionary={paths[0]:[],paths[1]:[],"reference:fixture":[]}
	queue._prepared_paths["reference:fixture"]=true
	Deferred.demanded_template_scan_enabled=true
	queue._retire_stale_prepared(required)
	check(queue.profile.template_checks==2 and queue._prepared_paths.size()==641,"only two demanded model templates are inspected; native references bypass template cache")
	Assets._scenes.erase(paths[3]);queue._retire_stale_prepared(required)
	check(queue._prepared_paths.has(paths[3]),"an unused stale flag owns no resource and creates no frame work")
	required[paths[3]]=[];queue._retire_stale_prepared(required)
	check(not queue._prepared_paths.has(paths[3]),"returning demand removes an evicted template before reuse")
	var replacement:=PackedScene.new();replacement.set_meta("_rmmo_source_digest","b".repeat(64))
	Assets._scenes[paths[1]]=replacement;queue._retire_stale_prepared(required)
	check(not queue._prepared_paths.has(paths[1]),"changed current template invalidates its prepared flag")
	var checks_before:int=queue.profile.template_checks
	for i:int in 100:queue._retire_stale_prepared({})
	check(queue.profile.template_checks==checks_before,"100 idle frames perform zero model-template checks")
	Assets._scenes[paths[1]]=owner;Assets._scenes[paths[3]]=owner
	queue._prepared_paths[paths[1]]=true;queue._prepared_paths[paths[3]]=true
	var measurements:Array=[]
	for enabled:bool in [false,true,true,false]:
		Deferred.demanded_template_scan_enabled=enabled
		checks_before=queue.profile.template_checks
		var began:=Time.get_ticks_usec()
		for frame:int in 100:queue._retire_stale_prepared(required)
		measurements.append({"demanded_only":enabled,"elapsed_us":Time.get_ticks_usec()-began,"checks":queue.profile.template_checks-checks_before})
	check(measurements[0].checks==64000 and measurements[1].checks==300,"100 active frames reduce template checks from 64000 to 300")
	Deferred.demanded_template_scan_enabled=true
	for path:String in paths:Assets._scenes.erase(path)
	queue.free()
	print("DEMANDED_TEMPLATE_SCAN ",JSON.stringify({"measurements":measurements,"failures":failures}))
	quit(1 if failures else 0)
