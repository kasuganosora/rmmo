extends SceneTree
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func exercise(path:String,content_root:String,count_:int)->Dictionary:
	var started:=Time.get_ticks_usec();var okay:=true
	for i:int in count_:
		var context:=Store._path_batch(path,content_root)
		for at:int in 8:okay=Store._batch_leaf(context,"resource%d.rmres"%at) and okay
		okay=Store._finish_paths(context) and okay
	return {"us":Time.get_ticks_usec()-started,"okay":okay}
func worker(path:String,content_root:String)->Dictionary:return exercise(path,content_root,100)
func run()->void:
	var content_root:="D:/code/rmmo_runtime/review_artifacts/axel_pipeline_blind_20261017/path_context_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var path:=content_root.path_join("map.gltf");var folder:=path+".resources"
	DirAccess.make_dir_recursive_absolute(folder)
	var before:=exercise(path,content_root,500)
	check(before.okay,"direct adjacent leaves use the same accepted path contract")
	var threads:Array=[]
	for i:int in 4:
		var thread:=Thread.new();check(thread.start(worker.bind(path,content_root))==OK,"worker starts");threads.append(thread)
	for thread:Thread in threads:check(thread.wait_to_finish().okay,"parallel contexts retain exclusive directory queries")
	var context:=Store._path_batch(path,content_root)
	check(not Store._batch_leaf(context,"../escape") and not Store._batch_leaf(context,"x/y") and not Store._batch_leaf(context,"C:escape"),"traversal and non-leaf names are rejected")
	# Directory junctions need no symlink privilege on this Windows account.
	# Their reparse-point leaf must be rejected just like a linked resource file.
	if OS.get_name()=="Windows":
		var target:=content_root.path_join("target");DirAccess.make_dir_recursive_absolute(target)
		var leaf:=folder.path_join("late.rmres");Store._batch_leaf(context,"late.rmres")
		var command:="$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path '%s' -Target '%s' | Out-Null"%[leaf.replace("'","''"),target.replace("'","''")]
		var output:Array=[]
		check(OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command",command],output,true,false)==0,"leaf junction fixture is created")
		check(not Store._batch_leaf(Store._path_batch(path,content_root),"late.rmres") and not Store._finish_paths(context),"leaf replacement by junction is rejected before and after IO")
	Store._batch_leaf(context,"resource0.rmres")
	# Only this process's newly created fixture directory is renamed; both
	# absolute sibling paths stay under the explicit external fixture root.
	check(DirAccess.rename_absolute(folder,folder+".prior")==OK,"temporary resource directory is replaced between checks")
	check(not Store._finish_paths(context),"nonempty transaction detects its directory disappearing")
	var empty:=Store._path_batch(path,content_root)
	check(Store._finish_paths(empty) and not Store._batch_leaf(empty,"resource0.rmres"),"empty missing directory and missing leaf preserve prior behavior")
	check(Store._path_batch(content_root.path_join("../outside.gltf"),content_root).is_empty(),"outside root is rejected")
	Paths.reuse_path_access_enabled=false
	DirAccess.make_dir_recursive_absolute(folder)
	check(exercise(path,content_root,2).okay,"unpooled diagnostic fallback retains equivalent leaf decisions")
	Paths.reuse_path_access_enabled=true
	print("RESOURCE_PATH_CONTEXT ",JSON.stringify({"us":before.us,"transactions":500,"leaves":4000,"failures":failures}));quit(1 if failures else 0)
