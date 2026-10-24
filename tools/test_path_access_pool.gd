extends SceneTree
## The harness replaces a previously accepted ancestor with a real junction.
## Access-object reuse must never reuse the previous filesystem decision.
const Paths=preload("res://scripts/world3d/map_paths.gd")
var fixture:=""
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):fixture=arg.trim_prefix("--fixture=")
	run.call_deferred()
func worker()->Dictionary:
	var good:=true;var began:=Time.get_ticks_usec()
	for i:int in 300:
		good=Paths.allowed(fixture+"/live/deep/missing",fixture) and good
		good=Paths.allowed_many([fixture+"/live/deep/map.gltf",fixture+"/live/deep/map.gltf.resources"],fixture) and good
	return {"ok":good,"us":Time.get_ticks_usec()-began}
func run()->void:
	check(not fixture.is_empty(),"isolated external fixture supplied")
	if fixture.is_empty():quit(1);return
	var trials:Array=[]
	for trial:int in 4:
		var began:=Time.get_ticks_usec();var threads:Array[Thread]=[]
		for i:int in 4:
			var thread:=Thread.new();check(thread.start(worker)==OK,"start independent path-check worker");threads.append(thread)
		var results:Array=[]
		for thread:Thread in threads:results.append(thread.wait_to_finish())
		trials.append({"us":Time.get_ticks_usec()-began,"workers":results})
		check(results.all(func(row):return row.ok),"parallel single and batched checks preserve valid paths")
	check(not Paths.allowed(fixture+"/../outside/missing",fixture) and not Paths.allowed_many([fixture+"/live",fixture+"X/escape"],fixture),"lexical root escape remains rejected")
	check(Paths._path_access_pool.size()>0 and Paths._path_access_pool.size()<=Paths.PATH_ACCESS_POOL_LIMIT,"finished workers leave only a bounded pool of access objects")
	var profile:Dictionary={}
	Paths.allowed_many([fixture+"/live/deep/map.gltf",fixture+"/live/deep/map.gltf.resources"],fixture,profile)
	check(profile.access_opens==0 and profile.access_reuses==1 and profile.link_checks>0,"a warm call avoids directory creation while retaining actual filesystem checks")
	check(Paths.allowed(fixture+"/live/deep/missing",fixture),"warm exact path before filesystem replacement")
	var ready:=FileAccess.open(fixture+"/ready",FileAccess.WRITE);ready.store_string("ready");ready.close()
	var deadline:=Time.get_ticks_msec()+15000
	while not FileAccess.file_exists(fixture+"/changed") and Time.get_ticks_msec()<deadline:await process_frame
	check(FileAccess.file_exists(fixture+"/changed"),"harness replaced the test-owned ancestor")
	check(not Paths.allowed(fixture+"/live/deep/missing",fixture),"same pooled object observes new junction despite missing leaf")
	check(not Paths.allowed_many([fixture+"/prior/deep/map.gltf",fixture+"/live/deep/missing"],fixture),"batch rechecks the changed ancestor independently")
	print("PATH_ACCESS_POOL ",JSON.stringify({"trials":trials,"failures":failures}))
	quit(1 if failures else 0)
