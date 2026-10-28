extends SceneTree
## RED: canonical content-addressed file changed by an editor/external tool.
## --root must name a fresh isolated external content root. Requires a build
## with Image.compress_from_channels_cpu to keep a real DDS sidecar in scope.
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const DDS=preload("res://scripts/world3d/compressed_texture_source.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);print("FAIL ",label)
	else:print("PASS ",label)
func _initialize()->void:run.call_deferred()
func _work(task:Callable)->Dictionary:
	var worker:=Thread.new()
	if worker.start(task)!=OK:return {"ok":false,"error":"cannot start test worker"}
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()
func _sha(path:String)->String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
func run()->void:
	var root_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):root_path=arg.trim_prefix("--root=").replace("\\","/")
	if root_path.is_empty() or not root_path.is_absolute_path():push_error("--root=<fresh external directory> required");quit(1);return
	if not Image.new().has_method("compress_from_channels_cpu"):push_error("CPU compression API candidate required for the real DDS fixture");quit(1);return
	var folder:=root_path.path_join("import_conflict_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(folder):push_error("fixture must be fresh");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create fresh external content")
	var source:=folder.path_join("source_a.png");var library:=folder.path_join("materials")
	var a:=Image.create(32,32,false,Image.FORMAT_RGBA8);a.fill(Color(.1,.2,.7,1))
	var b:=Image.create(32,32,false,Image.FORMAT_RGBA8);b.fill(Color(.8,.3,.1,1))
	check(a.save_png(source)==OK,"write actual source A")
	var source_sha:=_sha(source)
	var token:=Drainer.CancelToken.new()
	var first:Dictionary=await _work(Worker.run.bind(source,library,"conflict",token,root_path))
	check(first.get("ok",false) and first.get("dds_ready",false),"initial import produces real canonical PNG and DDS")
	if not first.get("ok",false) or not first.get("dds_ready",false):
		print("IMPORT_CONFLICT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder,"stage":"initial"}));quit(1);return
	var target:String=first.material.texture_path
	var sidecar:=DDS.sidecar_path(target)
	var dds_identity:=sidecar+".source.json"
	var material_identity:=library.path_join(str(first.material_id)+".json")
	var thumb:=target+".thumbnail.png";var thumb_identity:=target+".thumbnail.json"
	var prior_a:=_sha(target)
	check(not sidecar.is_empty() and FileAccess.file_exists(dds_identity) and FileAccess.file_exists(material_identity),"capture actual sidecar and material identities")
	check(b.save_png(target)==OK and _sha(target)!=prior_a,"externally replace canonical target with different B")
	var b_sha:=_sha(target)
	var artifacts:Dictionary={}
	for item:String in [sidecar,dds_identity,material_identity,thumb,thumb_identity]:artifacts[item]=_sha(item)
	var second:Dictionary=await _work(Worker.run.bind(source,library,"conflict",token,root_path))
	check(not second.get("ok",false),"RED: reimport A refuses the existing different B without silently reusing its path")
	check(_sha(source)==source_sha and _sha(target)==b_sha,"source A and externally modified target B remain byte-identical")
	for item:String in artifacts:check(_sha(item)==artifacts[item],"DDS and metadata are not rewritten after conflict: "+item.get_file())
	var reopened:=Image.load_from_file(target)
	check(reopened!=null and reopened.get_width()==32 and reopened.get_height()==32 and reopened.get_pixel(0,0).is_equal_approx(b.get_pixel(0,0)),"actual reopened image remains B")
	print("IMPORT_CONFLICT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder,"source_sha":source_sha,"first_png_sha":prior_a,"modified_b_sha":b_sha,"second_ok":second.get("ok",false),"second_error":str(second.get("error","")),"sidecar":sidecar,"artifacts":artifacts}))
	quit(0 if failures.is_empty() else 1)
