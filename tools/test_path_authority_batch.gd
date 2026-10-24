extends SceneTree
## One-call ancestor reuse: independent calls still observe the filesystem.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var root:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/path_batch70_fixture"
	DirAccess.make_dir_recursive_absolute(root.path_join("normal/deep/map.gltf.resources"))
	var map_path:=root.path_join("normal/deep/map.gltf")
	var pair:Array[String]=[map_path,map_path+".resources"]
	var path_script:Script=Paths
	var available:=path_script.get_script_method_list().any(func(method):return method.name=="allowed_many")
	check(available,"related authority checks have a single-call ancestor batch")
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		var began:=Time.get_ticks_usec();var accepted:=0
		for i:int in 500:
			accepted+=int(path_script.call("allowed_many",pair,root)) if fast and available else int(Paths.allowed(pair[0],root) and Paths.allowed(pair[1],root))
		trials.append({"batch":fast,"us":Time.get_ticks_usec()-began,"accepted":accepted})
	if available:
		var cases:Array=[pair,[],[root],[root+"/missing/ancestor/file",map_path],pair+[root+"X/escape"],pair+[root+"/../escape"],pair+["relative"],pair+["res://bad"],pair+[root+"/bad"+String.chr(0)],pair+[root+"/link/deep/file"],pair+[root+"/link"],[map_path.replace("/","\\"),map_path+".resources"],[root+"/normal/../normal/deep"]]
		for values:Array in cases:
			var expected:=values.all(func(value):return Paths.allowed(value,root))
			check(path_script.call("allowed_many",values,root)==expected,"batch preserves singleton authority decisions: "+str(values))
		var directory:=DirAccess.open(root)
		check(directory.is_link("link"),"real junction fixture is present")
		check(not path_script.call("allowed_many",[map_path,root+"/link/deep/missing"],root),"a missing leaf cannot hide a linked ancestor")
		var profile:Dictionary={}
		check(path_script.call("allowed_many",pair,root,profile),"sibling map/resource paths are accepted")
		check(profile.access_opens+profile.access_reuses==1 and profile.reused_ancestors==1,"siblings share one access object and stop at their checked ancestor")
		var repeated:Dictionary={};path_script.call("allowed_many",pair,root,repeated)
		check(repeated.link_checks==profile.link_checks and repeated.reused_ancestors==profile.reused_ancestors,"a later call repeats every filesystem check; no persistent path cache")
		check(Store._base(map_path,root) and not Store._base(root+"/link/map.gltf",root),"resource-store entry uses the same authority decisions")
	check(trials.all(func(row):return row.accepted==500),"both timings check all 500 map/resource pairs")
	print("PATH_AUTHORITY_BATCH ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
