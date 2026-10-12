extends SceneTree
## Private CPU singleflight/admission/continuation test. --gpu additionally
## checks real immutable Texture tickets and publication on the private desktop.
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
class Queue extends Deferred:
	var gate:=Semaphore.new()
	var blocked_path:=""
	var block_first:=true
	var accepted:=0
	func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,faces:bool,root_:String,requests:Array,native:bool,need_model:bool)->Callable:
		var task:=super(path,digest,token,item,faces,root_,requests,native,need_model)
		if block_first:block_first=false;blocked_path=path;return held.bind(task,gate)
		return task
	static func held(task:Callable,barrier:Semaphore)->Dictionary:
		barrier.wait();return task.call()
	func _accept_prepared_records(result:Dictionary)->void:
		accepted+=1;super(result)
	func _publish_ready(_began:int,_budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		return {"units":0,"unit_us":0,"max_unit_us":0,"scan_us":0}
var passed:=0
var failed:=0
var fixture:SceneTree
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func run()->void:
	var logger:=Base.Errors.new();OS.add_logger(logger)
	ledger_test()
	fixture=Base.new();fixture.files=Base.Files.new();fixture.files.content_root=Prep.Paths.external_root();fixture.files.folder=Prep.Paths.cache_directory("shared_prefab_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(fixture.files.folder)
	var path:String=fixture.files.folder.path_join("shared.png");fixture.files.created.append(path)
	var image:=Image.create(19,13,false,Image.FORMAT_RGB8);image.fill(Color(.1,.3,.7));image.save_png(path)
	var material:Dictionary={"name":"shared","color":[1,1,1,1],"roughness":.7,"texture_path":path,"normal_path":path,"normal_format":"directx"}
	var first:Dictionary=fixture.bridge("shared_a",100,material);var second:Dictionary=fixture.bridge("shared_b",200,material)
	var requested:=Prep.sources(first);var plan:=Prep.estimate(requested,fixture.files.content_root)
	await pool_test(requested,plan,path)
	var source:Dictionary=fixture.files.fixture("shared",[first,second],Base.Fixture.metadata([first,second]))
	check(Index.build(source.path,fixture.files.content_root,[first,second]).ok,"private two-consumer index builds")
	var index:=Index.read(source.path,fixture.files.content_root);var entries:Array=Index.select(index,[]).deferred_entries
	Deferred.prefab_texture_preparation_enabled=true;Deferred.shared_prefab_texture_preparation_enabled=true;Deferred.native_entry_prefetch_enabled=true
	await queue_test(index,entries,source.path,path,false)
	await queue_test(index,entries,source.path,path,true)
	if "--gpu" in OS.get_cmdline_user_args():await ticket_test(first,requested,plan,path)
	for flip:bool in [false,true]:fixture.files.created.append(Prep.Pixels.cache_path(path,flip))
	for created:String in fixture.files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(fixture.files.folder)
	fixture.files.free();fixture.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	print("SHARED_PREFAB_IMAGES passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
func ledger_test()->void:
	var ledger:=Admission.new();ledger.byte_limit=100;ledger.worker_limit=2
	check(ledger.reserve_bundle("a",{"estimated_bytes":30,"exclusive":false},{"image":40}) and ledger.reserved_bytes==70 and ledger.active_workers()==1,"atomic bundle charges one workspace and one shared output")
	check(not ledger.reserve_bundle("bad",{"estimated_bytes":10,"exclusive":false},{"image":40}) and ledger.reserved_bytes==70,"duplicate shared reservation fails without partial entries")
	check(not ledger.shrink_joined("a",10),"running worker cannot surrender temporary bytes")
	ledger.park("a");check(ledger.shrink_joined("a",10) and ledger.reserved_bytes==50,"only a joined worker shrinks to its retained bound")
	check(ledger.resume_worker("a") and ledger.reserved_bytes==50,"continuation reuses reserved scratch without acquiring extra bytes")
	ledger.park("a");ledger.release("a");check(ledger.reserved_bytes==40,"job retirement cannot release a shared output owned by other consumers")
	ledger.release("image");check(ledger.reserved_bytes==0,"last shared output retires its own charge")
func pool_test(requested:Dictionary,plan:Dictionary,path:String)->void:
	var ledger:=Admission.new();ledger.byte_limit=64*1024*1024;var pool:=Pool.new();pool.admission=ledger
	var a:=pool.offer(plan);check(ledger.reserve_bundle("a",{"estimated_bytes":a.scratch_bytes,"exclusive":false},a.retained),"first image producer reserves workspace and unique outputs")
	pool.commit("a",a)
	var b:=pool.offer(plan);check(b.retained.is_empty() and b.leaders.is_empty() and ledger.reserve_bundle("b",{"estimated_bytes":b.scratch_bytes,"exclusive":false},b.retained),"second consumer charges verification scratch but no duplicate image output")
	pool.commit("b",b)
	var token:=Drainer.CancelToken.new()
	var consumer:=Thread.new();consumer.start(Prep.prepare.bind(requested,plan,fixture.files.content_root,token,true,{"pool":pool,"consumer":"b","leaders":b.leaders,"cached":{}}))
	while consumer.is_alive():await process_frame
	var waiting:Dictionary=consumer.wait_to_finish()
	check(waiting.error.is_empty() and waiting.waiting_pixels and waiting.images.is_empty(),"missing image dependencies return immediately instead of blocking a worker")
	ledger.park("b")
	var producer:=Thread.new();producer.start(Prep.prepare.bind(requested,plan,fixture.files.content_root,token,true,{"pool":pool,"consumer":"a","leaders":a.leaders,"cached":{}}))
	while producer.is_alive():await process_frame
	var produced:Dictionary=producer.wait_to_finish();ledger.park("a")
	check(produced.error.is_empty() and pool.ready("b") and pool.snapshot().produced==2,"producer publishes exactly two immutable orientations")
	var resumed:=Prep.prepare(requested,plan,fixture.files.content_root,token,true,{"pool":pool,"consumer":"b","leaders":{},"cached":{}})
	check(resumed.error.is_empty() and not resumed.waiting_pixels and resumed.profile.get("shared_hits",0)==2 and resumed.images[path]==produced.images[path],"continuation consumes exact shared Images without a second decode")
	var weak:WeakRef=weakref(produced.images[path]);produced.clear();pool.release("a");ledger.release("a")
	check(weak.get_ref()!=null and pool.snapshot().retained_bytes==plan.output_bytes*2,"producer retirement leaves another consumer's images and charge intact")
	resumed.clear();waiting.clear();pool.release("b");ledger.release("b")
	check(weak.get_ref()==null and ledger.reserved_bytes==0 and pool.snapshot().outputs==0,"last consumer clears image owners before releasing unique bytes")
func make_queue(index:Dictionary,entries:Array,map_path:String)->Queue:
	var queue:=Queue.new();queue.configure_references(index,map_path,fixture.files.content_root);queue.loading_worker_limit=2;queue.ready_job_limit=2
	for entry:Dictionary in entries:
		var key:String="reference:"+entry.group_id if not entry.group_id.is_empty() else "reference:"+str(entry.record_index)
		queue.pending.append({"record":entry.compact_record,"path":key,"bounds":entry.bounds,"digest":"","memory":{"estimated_bytes":entry.memory_bytes,"known":true,"exclusive":false},"reference_entry":entry,"native_reference":true,"reference_prepared":false,"group_id":entry.group_id})
	return queue
func queue_test(index:Dictionary,entries:Array,map_path:String,path:String,cancel_producer:bool)->void:
	var queue:=make_queue(index,entries,map_path);var clip:AABB=entries[0].bounds.merge(entries[1].bounds).grow(1)
	check(queue.begin_entry_prefetch(self,clip,{}),"real native queue starts prepare-only shared transaction")
	queue.pump_entry_prefetch();var consumer_path:String=""
	var deadline:=Time.get_ticks_msec()+5000
	while queue._jobs.size()<2 and Time.get_ticks_msec()<deadline:await process_frame;queue.pump_entry_prefetch()
	check(queue._jobs.size()==2,"deadline-bounded dispatch eventually fills both producer/consumer slots at cap two")
	if queue._jobs.size()!=2:
		queue.gate.post();await queue.quiesce();queue.free();return
	for key:String in queue._jobs:
		if key!=queue.blocked_path:consumer_path=key
	deadline=Time.get_ticks_msec()+5000
	while not queue._jobs[consumer_path].has("result") and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(queue._jobs[consumer_path].result.waiting_pixels and not queue._jobs[consumer_path].has("worker") and queue._admission.active_workers()==1,"scheduler parks a dependent reference packet and frees its worker slot")
	var retained:int=queue._jobs[consumer_path].estimate.pixel_retained_bytes+Pool.HASH_SCRATCH
	check(queue._admission._entries[consumer_path].bytes==retained,"parked packet retains final-proof scratch and geometry until continuation")
	if cancel_producer:queue._jobs[queue.blocked_path].token.cancel()
	queue.gate.post()
	deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch()
		if queue._jobs.has(consumer_path) and queue._jobs[consumer_path].has("result") and not queue._jobs[consumer_path].result.get("waiting_pixels",false) and not queue._jobs[consumer_path].has("worker"):break
		await process_frame
	check(queue.path_errors.is_empty() and queue._jobs.has(consumer_path) and queue._jobs[consumer_path].result.error.is_empty() and not queue._jobs[consumer_path].result.waiting_pixels,"dependent reference resumes or safely retries after producer cancellation")
	check(queue.accepted==0 and Paint._textures.is_empty(),"shared ready packets remain unpublished before core handoff")
	var alias:Dictionary=queue._jobs[consumer_path].result.prefab_texture_packet;var weak:WeakRef=weakref(alias.images[path])
	await queue.quiesce()
	check(alias.is_empty() and weak.get_ref()==null and queue._admission.reserved_bytes==0 and queue._shared_images.snapshot().outputs==0,"quiesce clears all packets before final shared/resource ledger release")
	queue.free()
func ticket_test(record:Dictionary,requested:Dictionary,plan:Dictionary,path:String)->void:
	check(DisplayServer.get_name()!="headless","GPU ticket case runs with real private renderer")
	var packet:=Prep.prepare(requested,plan,fixture.files.content_root);var cpu:=Prefab.prepare_cpu(record)
	check(Prefab.publish_prepared(record,cpu,{},null,{},packet),"baseline publication creates real immutable material textures")
	var tickets:=Prefab.texture_tickets(plan.rows);var cached:Dictionary={}
	for key:String in tickets:cached[key]=tickets[key].source_sha
	var pool:=Pool.new();var shared:Dictionary={"pool":pool,"consumer":"cached","leaders":{},"cached":cached}
	var worker:=Thread.new();worker.start(Prep.prepare.bind(requested,plan,fixture.files.content_root,null,true,shared))
	while worker.is_alive():await process_frame
	var reused:Dictionary=worker.wait_to_finish()
	check(reused.error.is_empty() and reused.images.is_empty() and reused.profile.resident_hits==2 and reused.profile.decoded==0,"actual cached material consumers verify sources without decompressing pictures")
	reused.resident_textures=tickets
	var timings:Dictionary={};check(Prefab.publish_prepared(record,cpu,{},null,timings,reused) and timings.get("geometry_cache_hit",false),"verified texture tickets preserve prefab geometry-cache publication")
	var replacement:=Image.create(19,13,false,Image.FORMAT_RGB8);replacement.fill(Color.RED);replacement.save_png(path)
	var changed:=Prep.prepare(requested,Prep.estimate(requested,fixture.files.content_root),fixture.files.content_root,null,true,shared)
	check(changed.get("retry_pixels",false) and changed.images.is_empty(),"same dimensions but new pixels reject resident proof and request full readmission")
	# A texture LRU and an older prefab cache may coexist after independent cache
	# activity. A verified ticket must not let the older material win the hit.
	var fresh:=Prep.prepare(requested,Prep.estimate(requested,fixture.files.content_root),fixture.files.content_root)
	var old_material:Material=Prefab._meshes[record.house_prefab.sha256].mesh.materials[0]
	for key:String in fresh.images:
		var texture:=ImageTexture.create_from_image(fresh.images[key]);texture.set_meta("runtime_source_sha256",fresh.sources[path]);texture.set_meta("surface_has_alpha",false);Paint._textures[key]=texture
	var new_tickets:=Prefab.texture_tickets(plan.rows);var new_cached:Dictionary={}
	for key:String in new_tickets:new_cached[key]=new_tickets[key].source_sha
	var verified:=Prep.prepare(requested,Prep.estimate(requested,fixture.files.content_root),fixture.files.content_root,null,true,{"pool":pool,"consumer":"cached2","leaders":{},"cached":new_cached})
	verified.resident_textures=new_tickets
	check(Prefab.publish_prepared(record,cpu,{},null,{},verified) and Prefab._meshes[record.house_prefab.sha256].mesh.materials[0]!=old_material,"verified newer texture tickets invalidate an older prefab material generation")
	RenderingServer.force_sync()
	check(fixture.canonical(Prefab._meshes[record.house_prefab.sha256].mesh.materials[0].albedo_texture.get_image())==fixture.canonical(fresh.images[path]),"ticket-only rebuild preserves the exact new GPU pixels")
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint._textures.clear();Paint._materials.clear();packet.clear();reused.clear();tickets.clear();RenderingServer.force_sync()
