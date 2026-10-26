extends SceneTree
## External harness swaps a previously accepted ancestor for a real junction.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):folder=arg.trim_prefix("--fixture=")
	check(not folder.is_empty(),"external owned junction fixture supplied")
	if folder.is_empty():quit(1);return
	var path:=folder.path_join("live/deep/missing.png")
	var pool:=Pool.new();pool.commit("live",pool.offer({"rows":{}}));pool.remember_source_identity("live",path,path.sha256_text())
	var shared:={"pool":pool,"consumer":"live"};var sources:={path:path.sha256_text()}
	Prep.Pixels.Policy.verify_packages=false
	for fast:bool in [false,true]:
		Prep.batched_final_handoff_enabled=fast
		check(Prep.verify({"sources":sources},folder,null,shared,true),"initial ancestor is allowed")
	var ready:=FileAccess.open(folder.path_join("ready"),FileAccess.WRITE);ready.store_string("ready");ready.close()
	var deadline:=Time.get_ticks_msec()+15000
	while not FileAccess.file_exists(folder.path_join("changed")) and Time.get_ticks_msec()<deadline:await process_frame
	check(FileAccess.file_exists(folder.path_join("changed")),"harness completed junction swap")
	check(DirAccess.open(folder).is_link("live"),"replacement is an actual filesystem link")
	for fast:bool in [false,true]:
		Prep.batched_final_handoff_enabled=fast
		check(not Prep.verify({"sources":sources},folder,null,shared,true),"mounted identity does not authorize new junction")
		check(not Prep.verify({"sources":sources},folder),"standalone identity does not authorize new junction")
	pool.release("live")
	print("TEXTURE_HANDOFF_LINKS failures=",failures);quit(0 if failures==0 else 1)
