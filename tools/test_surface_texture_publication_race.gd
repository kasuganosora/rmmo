extends SceneTree
## Independent actual no-replace publication race. RED adapter uses the old
## Atomic.publish; GREEN uses create-only publication. No production assets used.
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const Atomic=preload("res://scripts/world3d/atomic_file.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:Array[String]=[]
class Gate extends RefCounted:
	var mutex:=Mutex.new()
	var entered:=false
	var stage:=""
	var target:=""
	var proceed:=Semaphore.new()
	func wait_after_stage(staged:String,destination:String)->void:
		mutex.lock();stage=staged;target=destination;entered=true;mutex.unlock()
		proceed.wait()
	func waiting()->bool:
		mutex.lock();var result:=entered;mutex.unlock();return result
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);print("FAIL ",label)
	else:print("PASS ",label)
func _initialize()->void:run.call_deferred()
func _wait(test:Callable,ms:int=30000)->bool:
	var end:=Time.get_ticks_msec()+ms
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return test.call()
func _work(task:Callable)->Dictionary:
	var worker:=Thread.new()
	if worker.start(task)!=OK:return {"ok":false,"error":"thread start failed"}
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()
static func _unavailable(_image:Image,_channels:int)->int:return ERR_UNAVAILABLE
func _write(path:String,data:PackedByteArray)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(data);file.flush();var ok:=file.get_error()==OK;file.close();return ok
func _encode(prepared:Dictionary,token:RefCounted,root_path:String,gate:Gate)->Dictionary:
	var worker:=Thread.new()
	var task:=Worker.encode_publish.bind(prepared,token,root_path,Callable(self,"_unavailable"),Callable(),false,Callable(gate,"wait_after_stage"))
	if worker.start(task)!=OK:return {"ok":false,"error":"thread start failed"}
	check(await _wait(Callable(gate,"waiting")),"staged writer reaches deterministic gate")
	return {"worker":worker}
func _finish(worker:Thread)->Dictionary:
	while worker.is_alive():await process_frame
	return worker.wait_to_finish()
func run()->void:
	var root_path:=""
	var python_path:="";var competitor_script:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):root_path=arg.trim_prefix("--root=").replace("\\","/")
		elif arg.begins_with("--python="):python_path=arg.trim_prefix("--python=")
		elif arg.begins_with("--competitor="):competitor_script=arg.trim_prefix("--competitor=")
	if root_path.is_empty() or not root_path.is_absolute_path() or not Paths.allowed(root_path):push_error("--root must be a fresh external-root subdirectory");quit(1);return
	if not FileAccess.file_exists(python_path) or not FileAccess.file_exists(competitor_script):push_error("--python and --competitor must name the external test helper");quit(1);return
	var folder:=root_path.path_join("no replace '测试_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(folder):push_error("fixture exists");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated fixture")
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.15,.3,.8))
	var source:=folder.path_join("source.png");check(image.save_png(source)==OK,"create actual source A")
	var token:=Drainer.CancelToken.new()
	var first:Dictionary=await _work(Worker.prepare.bind(source,folder.path_join("different"),token,root_path))
	check(first.get("ok",false),"prepare canonical A")
	if not first.get("ok",false):quit(1);return
	var gate:=Gate.new();var started:Dictionary=await _encode(first,token,root_path,gate)
	if not started.has("worker") or not gate.waiting():gate.proceed.post();quit(1);return
	var image_b:=Image.create(32,32,false,Image.FORMAT_RGBA8);image_b.fill(Color(.9,.2,.1))
	var bytes_b:=image_b.save_png_to_buffer()
	var competitor_source:=folder.path_join("competitor_b.png")
	var competitor_marker:=folder.path_join("competitor_b.json")
	check(_write(competitor_source,bytes_b),"prepare independent competing image")
	var competitor_pid:=OS.create_process(python_path,PackedStringArray([competitor_script,gate.target,competitor_source,competitor_marker]))
	print("NO_REPLACE_COMPETITOR_PID ",competitor_pid)
	check(competitor_pid>0,"launch separate test-only competitor process")
	var child_done:=false
	if competitor_pid>0:
		child_done=await _wait(func():return not OS.is_process_running(competitor_pid),10000)
		if not child_done:OS.kill(competitor_pid)
		check(child_done,"owned competitor process exits before releasing the producer")
	var competitor_json:=JSON.new()
	var marker_error:=competitor_json.parse(FileAccess.get_file_as_string(competitor_marker)) if child_done and FileAccess.file_exists(competitor_marker) else ERR_FILE_NOT_FOUND
	var competitor_data:Variant=competitor_json.data if marker_error==OK else null
	check(competitor_data is Dictionary and competitor_data.get("ok",false) and FileAccess.get_file_as_bytes(gate.target)==bytes_b,"independent competitor creates complete B after A staged")
	gate.proceed.post()
	var conflict:Dictionary=await _finish(started.worker)
	check(not conflict.get("ok",false) and str(conflict.get("error","")).contains("冲突"),"different competitor causes explicit conflict")
	check(FileAccess.get_file_as_bytes(gate.target)==bytes_b,"competitor B remains byte-identical")
	check(not FileAccess.file_exists(gate.target+".thumbnail.png") and not FileAccess.file_exists(gate.target+".thumbnail.json") and not FileAccess.file_exists(gate.target+".dxt1.dds"),"conflict creates no dependent sidecars")
	check(not FileAccess.file_exists(gate.stage),"losing staging file is removed")
	var same:Dictionary=await _work(Worker.prepare.bind(source,folder.path_join("same"),token,root_path))
	var same_gate:=Gate.new();var same_start:Dictionary=await _encode(same,token,root_path,same_gate)
	if not same_start.has("worker") or not same_gate.waiting():same_gate.proceed.post();quit(1);return
	check(_write(same_gate.target,same.png),"competitor creates identical A after staging")
	same_gate.proceed.post();var matched:Dictionary=await _finish(same_start.worker)
	check(matched.get("ok",false) and FileAccess.get_file_as_bytes(same_gate.target)==same.png,"identical concurrent owner is reused")
	check(not FileAccess.file_exists(same_gate.stage),"identical loser staging is removed")
	var cancelled:=Drainer.CancelToken.new()
	var cancel_prepared:Dictionary=await _work(Worker.prepare.bind(source,folder.path_join("cancel"),cancelled,root_path))
	var cancel_gate:=Gate.new();var cancel_start:Dictionary=await _encode(cancel_prepared,cancelled,root_path,cancel_gate)
	if not cancel_start.has("worker") or not cancel_gate.waiting():cancel_gate.proceed.post();quit(1);return
	cancelled.cancel();cancel_gate.proceed.post();var stopped:Dictionary=await _finish(cancel_start.worker)
	check(not stopped.get("ok",false) and not FileAccess.file_exists(cancel_gate.target) and not FileAccess.file_exists(cancel_gate.stage),"cancellation before commit publishes nothing and cleans staging")
	# A destination that becomes a real directory must never be interpreted as
	# a request to create another link inside that directory.
	var dir_target:=folder.path_join("directory_target");DirAccess.make_dir_recursive_absolute(dir_target)
	var dir_stage:=folder.path_join("directory_stage");check(_write(dir_stage,PackedByteArray([42])),"prepare directory-target stage")
	var dir_status:int=Atomic.publish_new(dir_stage,dir_target)
	check(dir_status!=OK and DirAccess.dir_exists_absolute(dir_target) and DirAccess.get_files_at(dir_target).is_empty() and FileAccess.file_exists(dir_stage),"existing directory is never treated as target directory")
	if OS.get_name()!="Windows":
		var dir_access:=DirAccess.open(folder)
		var link_target:=folder.path_join("directory_link")
		var linked:=dir_access.create_link(dir_target,link_target) if dir_access!=null else FAILED
		check(linked==OK,"create controlled symlink-to-directory fixture")
		if linked==OK:
			var link_stage:=folder.path_join("link_stage");_write(link_stage,PackedByteArray([43]))
			var link_status:int=Atomic.publish_new(link_stage,link_target)
			check(link_status!=OK and dir_access.is_link(link_target) and DirAccess.get_files_at(dir_target).is_empty() and FileAccess.file_exists(link_stage),"symlink-to-directory is not replaced or used as target directory")
	print("NO_REPLACE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder,"conflict":conflict,"matched_ok":matched.get("ok",false),"cancellation_rejected":not stopped.get("ok",false)}))
	quit(0 if failures.is_empty() else 1)
