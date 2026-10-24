extends SceneTree
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	var root:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/path_context_fixture"
	DirAccess.make_dir_recursive_absolute(root.path_join("normal/deep"))
	var paths:Array[String]=[root,root+"/normal/deep/missing.glb",root+"/missing/ancestor/file",root+"/normal/../normal/deep",root+"X/escape",root+"/../escape","res://bad","relative","C:/outside",root+"/link/deep/file",root+"/link",root.replace("/","\\")+"\\normal\\deep"]
	for path:String in paths:
		Paths.reuse_path_access_enabled=false;var expected:=Paths.allowed(path,root)
		Paths.reuse_path_access_enabled=true;check(Paths.allowed(path,root)==expected,"same containment and link result: "+path)
	var directory:=DirAccess.open(root)
	if directory.is_link("link"):check(not Paths.allowed(root+"/link/deep/missing",root),"real directory link is rejected even with a missing descendant")
	else:print("SKIP optional directory-link fixture unavailable")
	var trials:Array=[]
	for fast:bool in [false,true,true,false]:
		Paths.reuse_path_access_enabled=fast;var began:=Time.get_ticks_usec();var accepted:=0
		for i:int in 1800:accepted+=int(Paths.allowed(paths[i%paths.size()],root))
		trials.append({"fast":fast,"us":Time.get_ticks_usec()-began,"accepted":accepted})
	check(trials.all(func(row):return row.accepted==trials[0].accepted),"all repeated queries preserve the exact decisions")
	Paths.reuse_path_access_enabled=true
	print("PATH_ACCESS_REUSE ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
