extends SceneTree
const Job=preload("res://scripts/world_editor/load_job.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Prepare=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
var checks:=0
var failures:Array[String]=[]
class GatedDecode extends RefCounted:
	var entered:=false
	var mutex:=Mutex.new()
	var gate:=Semaphore.new()
	var requested:Dictionary={}
	var plan:Dictionary={}
	var content_root:String
	func active()->bool:
		mutex.lock();var value:=entered;mutex.unlock();return value
	func run()->Dictionary:
		mutex.lock();entered=true;mutex.unlock();gate.wait()
		return Job._decode_textures(requested,content_root,plan)
func refresh_during_decode(gate:GatedDecode,fail_queue:Node=null)->void:
	while not gate.active():await process_frame
	Paint.refresh_sources()
	if fail_queue!=null:fail_queue.thread_starter=func(_worker:Thread,_task:Callable)->int:return ERR_CANT_CREATE
	gate.gate.post()
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	create_timer(60).timeout.connect(func():quit(2))
	var folder:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):folder=arg.trim_prefix("--root=")
	if folder.is_empty() or not Paths.allowed(folder):quit(2);return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"isolated source directory")
	var path:=folder.path_join("shared.png")
	var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(Color(.3,.4,.8))
	check(image.save_png(path)==OK,"actual source image")
	var key:=Paint.texture_key(path);var old_budget:=Paint.cache_byte_budget
	Paint.cache_byte_budget=0
	var job:=Job.new();root.add_child(job)
	job._timings={"build":{"units":{}}}
	job._terrain_texture_checked={key:true}
	job._preparation=Job.PreparationQueue.new();job.add_child(job._preparation)
	for kind:String in ["terrain_mesh","house_prefab"]:
		var definition:={"texture_path":path}
		var record:={"uuid":kind,kind:{}}
		if kind=="terrain_mesh":record.terrain_material=definition
		else:record.prefab_materials=[definition]
		var old_owner:=StandardMaterial3D.new();old_owner.albedo_texture=Paint.texture(definition)
		var texture:WeakRef=weakref(old_owner.albedo_texture)
		var packet:Dictionary=await job._prepare_record_textures(record)
		check(job._preparation.metrics.started==0 and packet.images.is_empty(),kind+": actual load preparation queues no duplicate worker")
		old_owner.albedo_texture=null;old_owner=null
		await process_frame
		check(texture.get_ref()!=null and Prepare.owners_current(packet),kind+": record borrows the texture through a publication yield")
		Pixels.reset_profile();Pixels.profile_enabled=true;Paint.texture_profile_enabled=true
		var previous:=Prepare.install(packet)
		var published:=StandardMaterial3D.new();published.albedo_texture=Paint.texture(definition)
		Prepare.restore(previous,packet.failed);job._release_texture_payload(packet)
		var counters:Dictionary=Pixels.profile_snapshot("").counters
		check(published.albedo_texture==texture.get_ref(),kind+": final material receives the identical GPU owner")
		check(counters.get("paint.texture.runtime_image_lookup",0)==0 and counters.get("paint.texture.sidecar_main_reads",0)==0 and counters.get("paint.texture.upload_bytes",0)==0,kind+": no fallback source read or upload after yielding")
		Pixels.profile_enabled=false;Paint.texture_profile_enabled=false
		packet=await job._prepare_record_textures(record)
		Paint.refresh_sources()
		check(not Prepare.owners_current(packet),kind+": an in-flight source refresh invalidates the borrowed generation")
		job._release_texture_payload(packet)
		check(Prepare.requests(record,job._terrain_texture_checked).has(key),kind+": invalidated source returns to asynchronous preparation")
		published.albedo_texture=null;published=null
		check(texture.get_ref()==null,kind+": release/cancellation retains no hidden owner")
		# Rebuild a genuine borrowed scope then dispose it without publication.
		var cancel_owner:=StandardMaterial3D.new();cancel_owner.albedo_texture=Paint.texture(definition)
		var cancel_ref:WeakRef=weakref(cancel_owner.albedo_texture)
		packet=await job._prepare_record_textures(record)
		cancel_owner.albedo_texture=null;cancel_owner=null
		check(cancel_ref.get_ref()!=null,kind+": pending record owns its borrowed resource")
		job._release_texture_payload(packet)
		await process_frame
		print("CANCEL_OWNERS ",JSON.stringify({"kind":kind,"alive":cancel_ref.get_ref()!=null,"hot":Paint._textures.has(key),"ledger":job._preparation.ledger.snapshot(),"packet":packet.keys()}))
		check(cancel_ref.get_ref()==null and job._preparation.ledger.count()==0,kind+": cancellation releases borrowed pixels and leaves budget empty")
	# A mixed packet was already consumed when its borrowed color was refreshed
	# at publication. Retrying its old planned key must not wait forever on done.
	var other:=folder.path_join("other.png");check(image.save_png(other)==OK,"second source for mixed preparation")
	var mixed:={"uuid":"mixed","terrain_mesh":{},"terrain_material":{"texture_path":path,"normal_path":other}}
	var color_owner:=StandardMaterial3D.new();color_owner.albedo_texture=Paint.texture({"texture_path":path})
	var planned:="textures:mixed"
	var normal_requests:={Paint.texture_key(other,false,true):[other,false,true]}
	job._texture_tasks.mixed=planned;job._texture_requests[planned]=normal_requests
	job._enqueue_textures(planned,normal_requests,Paths.external_root())
	var first:Dictionary=await job._prepare_record_textures(mixed)
	check(first.owners.has(key) and first.images.size()==1,"mixed preparation borrows color while decoding normal")
	Paint.refresh_sources();check(not Prepare.owners_current(first),"refresh invalidates a mixed packet before publication")
	job._release_texture_payload(first)
	check(job._preparation.rows[planned].state=="done","original mixed task reached its terminal state")
	var retried:Dictionary=await job._prepare_record_textures(mixed)
	check(retried.images.size()==2 and retried.owners.is_empty() and retried.queue_key!=planned,"retry asynchronously rebuilds both roles without waiting on a done row")
	job._release_texture_payload(retried);color_owner=null
	# Refresh during an incomplete planned task adds a previously borrowed key
	# to the repair. The old owner must not poison the newly prepared packet.
	color_owner=StandardMaterial3D.new();color_owner.albedo_texture=Paint.texture({"texture_path":path})
	var third:=folder.path_join("third.png");check(image.save_png(third)==OK,"third source for incomplete plan")
	var incomplete:=mixed.duplicate(true);incomplete.uuid="incomplete";incomplete.terrain_material.ao_path=third
	planned="textures:incomplete"
	job._texture_tasks.incomplete=planned;job._texture_requests[planned]=normal_requests
	job._enqueue_textures(planned,normal_requests,Paths.external_root())
	var gate:=GatedDecode.new();gate.requested=normal_requests;gate.content_root=Paths.external_root();gate.plan=Job.PrefabPixels.estimate(normal_requests,gate.content_root,true);job._preparation.rows[planned].task=gate.run
	refresh_during_decode.call_deferred(gate)
	var repaired:Dictionary=await job._prepare_record_textures(incomplete)
	check(repaired.images.size()==3 and repaired.owners.is_empty() and Prepare.owners_current(repaired),"mid-wait refresh clears old pins and repairs the complete new request once")
	job._release_texture_payload(repaired);color_owner=null
	check(job._preparation.ledger.count()==0,"mixed retry and refresh leave no budget leases")
	color_owner=StandardMaterial3D.new();color_owner.albedo_texture=Paint.texture({"texture_path":path})
	var failed_record:=incomplete.duplicate(true);failed_record.uuid="failed_repair"
	planned="textures:failed_repair";job._texture_tasks.failed_repair=planned;job._texture_requests[planned]=normal_requests
	job._enqueue_textures(planned,normal_requests,Paths.external_root())
	gate=GatedDecode.new();gate.requested=normal_requests;gate.content_root=Paths.external_root();gate.plan=Job.PrefabPixels.estimate(normal_requests,gate.content_root,true);job._preparation.rows[planned].task=gate.run
	refresh_during_decode.call_deferred(gate,job._preparation)
	var failed_packet:Dictionary=await job._prepare_record_textures(failed_record)
	check(failed_packet.images.is_empty() and failed_packet.failed.size()==3 and failed_packet.failed.has(key),"failed repair includes the formerly borrowed color in all failed keys")
	check(failed_packet.owners.is_empty() and job._preparation.metrics.start_failures==1,"failed repair retains no stale owner or synchronous fallback")
	job._release_texture_payload(failed_packet);color_owner=null
	check(job._preparation.ledger.count()==0,"failed launch releases its reserved budget")
	Paint.cache_byte_budget=old_budget
	job.queue_free();await process_frame
	print("EDITOR_TEXTURE_LIVE_OWNERS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
