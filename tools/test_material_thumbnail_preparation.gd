extends SceneTree
## Headless-compatible real thumbnail coordinator contract. Use a fresh --root
## inside the configured external content root, never the user's map/library.
const Thumbnails=preload("res://scripts/world_editor/material_thumbnails.gd")
const Worker=preload("res://scripts/world_editor/surface_texture_import_worker.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:Array[String]=[]
var signals:Array[String]=[]
class Gate extends RefCounted:
	var lock:=Mutex.new()
	var entered:=false
	var release:=Semaphore.new()
	func start(thread:Thread,task:Callable)->int:return thread.start(run.bind(task),Thread.PRIORITY_LOW)
	func run(task:Callable)->Variant:
		lock.lock();entered=true;lock.unlock();release.wait()
		return task.call()
	func waiting()->bool:
		lock.lock();var value:=entered;lock.unlock();return value
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);print("FAIL ",label)
	else:print("PASS ",label)
func _initialize()->void:run.call_deferred()
func _wait(test:Callable,ms:int=30000)->bool:
	var end:=Time.get_ticks_msec()+ms
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await process_frame
	return test.call()
func _work(task:Callable)->Dictionary:
	var thread:=Thread.new()
	if thread.start(task)!=OK:return {"ok":false,"error":"worker start failed"}
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()
static func _unavailable(_image:Image,_channels:int)->int:return ERR_UNAVAILABLE
func _available(id:String,_texture:Texture2D)->void:signals.append(id)
func _entry(id:String,path:String,root_path:String)->Dictionary:
	var value:={"material_id":id,"material":{"name":id,"texture_path":path,"color":[1,1,1,1],"roughness":.9}}
	Thumbnails.prepare(value,root_path);return value
func _tga(path:String)->bool:
	# Tiny uncompressed 24-bit top-origin TGA, not PNG/JPEG/WebP.
	var bytes:=PackedByteArray();bytes.resize(18+3*16*8)
	bytes[2]=2;bytes[12]=16;bytes[14]=8;bytes[16]=24;bytes[17]=32
	for at in range(18,bytes.size(),3):bytes[at]=17;bytes[at+1]=83;bytes[at+2]=220
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_buffer(bytes);file.close();return true
func run()->void:
	var root_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):root_path=arg.trim_prefix("--root=").replace("\\","/")
	if root_path.is_empty() or not root_path.is_absolute_path() or not Paths.allowed(root_path):push_error("--root must be a fresh external-root subdirectory");quit(1);return
	var folder:=root_path.path_join("thumbnail_contract_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(folder):push_error("fixture must be fresh");quit(1);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"create isolated thumbnail fixture")
	var source:=folder.path_join("input.png")
	var image:=Image.create(32,16,false,Image.FORMAT_RGBA8);image.fill(Color(.2,.4,.8));check(image.save_png(source)==OK,"create source image")
	var token:=Drainer.CancelToken.new()
	var imported:Dictionary=await _work(Worker.run.bind(source,folder.path_join("materials"),"alpha",token,root_path,Callable(self,"_unavailable")))
	check(imported.get("ok",false),"prepare real imported thumbnail and canonical source")
	if not imported.get("ok",false):print("THUMBNAIL_CONTRACT ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder}));quit(1);return
	var ledger:=Admission.new();ledger.worker_limit=2;ledger.byte_limit=64*1024*1024
	var loader:=Thumbnails.new();loader.shared_ledger=ledger;loader.directory=folder.path_join("cache")
	loader.placeholder=ImageTexture.create_from_image(Image.create(1,1,false,Image.FORMAT_RGBA8))
	root.add_child(loader);loader._content_root=root_path;loader.available.connect(_available)
	check(loader._queue.ledger==ledger and loader._queue.shared_ledger_enabled,"real thumbnail queue shares the editor ledger")
	var one:=_entry("alpha",imported.material.texture_path,root_path)
	var two:=_entry("beta",imported.material.texture_path,root_path)
	check(one.thumbnail_key==two.thumbnail_key,"two labels bind the same source generation")
	loader.request([one,two])
	check(await _wait(func():return signals.has("alpha") and signals.has("beta")),"both subscribers receive the single thumbnail")
	check(loader.decode_count==1 and loader.imported_thumbnail_hits==1 and loader.source_decode_count==0,"same source uses one producer and imported small sidecar without source decode")
	check(await _wait(func():return ledger.count()==0),"sidecar lease retires after publication")
	# Forged huge dimensions in a small PNG are rejected by exact header check.
	var forged:=folder.path_join("forged.png")
	var bad:=image.save_png_to_buffer();bad[16]=0;bad[17]=0;bad[18]=32;bad[19]=0;bad[20]=0;bad[21]=0;bad[22]=32;bad[23]=0
	var out:=FileAccess.open(forged,FileAccess.WRITE);out.store_buffer(bad);out.close()
	check(Thumbnails._small_image(forged,root_path)==null,"small-cache parser rejects 8192x8192 declaration before accepting an Image")
	# A supported non-PNG/JPEG/WebP asset must use the conservative worker path.
	var tga:=folder.path_join("source.tga");check(_tga(tga),"create genuine TGA source")
	var extra:=_entry("tga",tga,root_path);loader.request([extra])
	check(await _wait(func():return signals.has("tga")),"supported other format reaches thumbnail publication")
	check(loader.lookup(extra)!=loader.placeholder and loader.source_decode_count==1,"TGA uses actual decoded image rather than fallback swatch")
	check(await _wait(func():return ledger.count()==0),"other-format preparation returns its lease")
	# Gate the real queued worker, cancel a request, then ensure it cannot publish.
	var gated_source:=folder.path_join("gated.png");image.fill(Color(.8,.1,.3));image.save_png(gated_source)
	var gated:=_entry("cancelled",gated_source,root_path)
	var blocker:=Gate.new();loader._queue.thread_starter=Callable(blocker,"start")
	loader.request([gated]);check(await _wait(Callable(blocker,"waiting")),"real thumbnail worker enters gate")
	check(ledger.count()>0 and ledger.active_workers()>0,"blocked thumbnail owns shared admission lease")
	loader.request([]);loader._queue.thread_starter=Callable();blocker.release.post()
	check(await _wait(func():return ledger.count()==0),"cancelled thumbnail releases lease after worker exit")
	check(not signals.has("cancelled"),"cancelled request never publishes")
	# Closing the node with a gated worker must detach without waiting on main.
	var close_entry:=_entry("closing",gated_source,root_path)
	var closing:=Gate.new();loader._queue.thread_starter=Callable(closing,"start")
	loader.request([close_entry]);check(await _wait(Callable(closing,"waiting")),"closing fixture has a live gated worker")
	loader.queue_free();await process_frame
	check(not is_instance_valid(loader) or loader.is_queued_for_deletion(),"thumbnail node closes before worker is released")
	closing.release.post()
	check(await _wait(func():return ledger.count()==0),"detached worker finally returns the shared lease")
	check(not signals.has("closing"),"closed loader publishes nothing")
	print("THUMBNAIL_CONTRACT ",JSON.stringify({"checks":checks,"failures":failures,"fixture":folder}))
	quit(0 if failures.is_empty() else 1)
