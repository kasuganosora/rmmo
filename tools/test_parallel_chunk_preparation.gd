extends SceneTree
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
class Queue extends Deferred:
	var gate:=Semaphore.new()
	var pixel_gate:=Semaphore.new()
	var hold_geometry:=true
	var hold_pixels:=false
	var pixel_blocked:=false
	var blocked:=false
	func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,faces:bool,root_:String,requests:Array,native:bool,need_model:bool)->Callable:
		var task:=super(path,digest,token,item,faces,root_,requests,native,need_model)
		if hold_geometry and not blocked:blocked=true;return held.bind(task,gate)
		return task
	func _make_pixel_prepare_task(plan:Dictionary,root_:String,token:RefCounted,shared:Dictionary)->Callable:
		var task:=super(plan,root_,token,shared)
		if hold_pixels and not pixel_blocked:pixel_blocked=true;return held.bind(task,pixel_gate)
		return task
	static func held(task:Callable,barrier:Semaphore)->Dictionary:
		barrier.wait();return task.call()
	func _publish_ready(_began:int,_budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		return {"units":0,"unit_us":0,"max_unit_us":0,"scan_us":0}
var passed:=0
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func run()->void:
	var logger:=Base.Errors.new();OS.add_logger(logger)
	var fixture:=Base.new();fixture.files=Base.Files.new();fixture.files.content_root=Prep.Paths.external_root()
	fixture.files.folder=Prep.Paths.cache_directory("parallel_chunk_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(fixture.files.folder)
	var path:String=fixture.files.folder.path_join("shared.png");fixture.files.created.append(path)
	var image:=Image.create(19,13,false,Image.FORMAT_RGB8);image.fill(Color(.1,.3,.7));image.save_png(path)
	if "--dds" in OS.get_cmdline_user_args():
		var dds_fixture:=preload("res://tools/test_compressed_texture_source.gd").new()
		for suffix:String in [".dxt1.dds",".bc5.dds"]:
			fixture.files.write_bytes(path+suffix,dds_fixture.dds(19,13,"ATI2" if suffix==".bc5.dds" else "DXT1"));fixture.files.created.append(path+suffix)
		dds_fixture.free()
	var material:Dictionary={"name":"parallel","color":[1,1,1,1],"roughness":.7,"texture_path":path,"normal_path":path,"normal_format":"opengl"}
	var first:Dictionary=fixture.bridge("parallel_a",100,material)
	var source:Dictionary=fixture.files.fixture("parallel",[first],Base.Fixture.metadata([first]))
	var index:=Index.build(source.path,fixture.files.content_root,[first]);check(index.ok,"private parallel reference index builds")
	var entries:Array=Index.select(index,[]).deferred_entries
	var queue:=Queue.new();queue.configure_references(index,source.path,fixture.files.content_root);queue.loading_worker_limit=2;queue.ready_job_limit=2
	Deferred.native_entry_prefetch_enabled=true
	for entry:Dictionary in entries:
		var key:String=Deferred.reference_path(entry)
		queue.pending.append({"record":entry.compact_record,"path":key,"bounds":entry.bounds,"digest":"","memory":{"estimated_bytes":entry.memory_bytes,"known":true,"exclusive":false},"reference_entry":entry,"native_reference":true,"reference_prepared":false,"group_id":entry.group_id})
	check(queue.begin_entry_prefetch(self,entries[0].bounds.grow(1),{}),"real queue starts with two total workers")
	var deadline:=Time.get_ticks_msec()+5000
	while queue._jobs.is_empty() and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(queue._jobs.size()==1,"one owner holds the complete geometry/pixel transaction")
	var reserved:int=queue._admission.reserved_bytes
	deadline=Time.get_ticks_msec()+2000
	while queue._shared_images.snapshot().produced<2 and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(queue._shared_images.snapshot().produced==2,"textures finish while the geometry worker is deliberately stopped")
	queue.pump_entry_prefetch()
	check(queue._admission.active_workers()==1,"finished pixel task releases its slot without waiting for geometry")
	check(queue._admission.reserved_bytes==reserved,"geometry and shared image bytes stay charged after partial completion")
	check(Paint._textures.is_empty(),"CPU preparation never publishes GPU textures")
	queue.gate.post();deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch()
		if queue._jobs.size()==1 and queue._jobs.values()[0].has("result") and not queue._jobs.values()[0].has("worker"):break
		await process_frame
	var result:Dictionary=queue._jobs.values()[0].get("result",{}) if queue._jobs.size()==1 else {}
	check(not result.is_empty() and result.get("error","missing").is_empty() and not result.get("waiting_pixels",true),"both parts join into one complete publishable packet")
	check(queue._shared_images.snapshot().produced==2 and result.get("prefab_texture_packet",{}).get("images",{}).size()==2,"each unique color/normal role is produced exactly once")
	for prepared:Image in result.get("prefab_texture_packet",{}).get("images",{}).values():check(prepared.is_compressed()==("--dds" in OS.get_cmdline_user_args()),"parallel packet retains the expected compressed/uncompressed format")
	check(queue._admission.peak_workers<=2,"both tasks obey the original worker cap")
	await queue.quiesce()
	check(queue._admission.reserved_bytes==0 and queue._shared_images.snapshot().outputs==0,"quiesce releases every shared owner and admitted byte")
	queue.free()
	await follower_case(fixture,path,material)
	await follower_case(fixture,path,material,true)
	await cancel_case(fixture,path,source,index,entries,false)
	await cancel_case(fixture,path,source,index,entries,true)
	await solo_case(fixture,source,index,entries)
	for flip:bool in [false,true]:fixture.files.created.append(Prep.Pixels.cache_path(path,flip))
	for created:String in fixture.files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	fixture.files.free();fixture.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	print("PARALLEL_CHUNK_PREPARATION passed=",passed," failures=",failed);quit(0 if failed==0 else 1)

func new_queue(fixture:SceneTree,index:Dictionary,entries:Array,map_path:String)->Queue:
	var queue:=Queue.new();queue.configure_references(index,map_path,fixture.files.content_root);queue.loading_worker_limit=2;queue.ready_job_limit=16
	for entry:Dictionary in entries:
		queue.pending.append({"record":entry.compact_record,"path":Deferred.reference_path(entry),"bounds":entry.bounds,"digest":"","memory":{"estimated_bytes":entry.memory_bytes,"known":true,"exclusive":false},"reference_entry":entry,"native_reference":true,"reference_prepared":false,"group_id":entry.group_id})
	return queue

func complete(queue:Queue,total:int)->bool:
	if queue._jobs.size()!=total:return false
	for job:Dictionary in queue._jobs.values():
		if job.has("worker") or not job.has("result") or not job.result.get("error","missing").is_empty() or job.result.get("waiting_pixels",false):return false
	return true

func follower_case(fixture:SceneTree,path:String,material:Dictionary,cancel_producer:bool=false)->void:
	var records:Array=[]
	for i:int in 12:records.append(fixture.bridge("follower_"+str(i),100+i*40,material))
	var source:Dictionary=fixture.files.fixture("followers_cancel" if cancel_producer else "followers",records,Base.Fixture.metadata(records))
	var index:=Index.build(source.path,fixture.files.content_root,records);var entries:Array=Index.select(index,[]).deferred_entries
	var queue:=new_queue(fixture,index,entries,source.path);queue.hold_geometry=false;queue.hold_pixels=true
	var clip:AABB=entries[0].bounds
	for entry:Dictionary in entries:clip=clip.merge(entry.bounds)
	queue.begin_entry_prefetch(self,clip.grow(1),{})
	var deadline:=Time.get_ticks_msec()+10000
	while queue._jobs.size()<12 and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	var joined:=0
	deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch();joined=0
		for job:Dictionary in queue._jobs.values():
			if job.has("result") and not job.has("worker") and job.result.get("waiting_pixels",false):joined+=1
		if joined==11:break
		await process_frame
	check(joined==11 and queue._admission.active_workers()==1,"held pixels leave one slot for all eleven other geometries to finish and park")
	check(queue._shared_images.snapshot().produced==0 and queue.profile.get("parallel_pixel_jobs",0)==1,"twelve consumers admit exactly one unique pixel producer")
	if cancel_producer:
		for job:Dictionary in queue._jobs.values():
			if job.get("parallel_pixels",false):job.token.cancel();break
		# Keep the cancelled producer physically alive across scheduler turns.
		for i:int in 4:queue.pump_entry_prefetch();await process_frame
	queue.pixel_gate.post();deadline=Time.get_ticks_msec()+10000
	while not complete(queue,12) and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(complete(queue,12),"all twelve groups complete after the independent producer resumes")
	var observed:=observe_work(queue)
	if cancel_producer:print("CANCEL_WORK produced=",queue._shared_images.snapshot().produced," unique_images=",observed.images.size()," completed_reference_reads=",observed.reads," retries=",queue.profile.get("pixel_retries",0))
	check(queue._shared_images.snapshot().produced==2 and observed.images.size()==2 and observed.reads==12,"all consumers share two images; twelve completed reference packets" if cancel_producer else "all consumers share the exact two images and each geometry reference is read once")
	check(queue._admission.peak_workers<=2 and queue._admission.peak_bytes<=queue._admission.byte_limit,"stress stays within the total worker and byte limits")
	await queue.quiesce()
	var released:=true
	for weak:WeakRef in observed.images.values():released=released and weak.get_ref()==null
	if not released or queue._admission.reserved_bytes!=0:print("RETIREMENT ",queue._shared_images.snapshot()," bytes=",queue._admission.reserved_bytes," released=",released)
	check(released and queue._admission.reserved_bytes==0,"last shared consumer releases every image and byte after stress")
	queue.free()

func observe_work(queue:Queue)->Dictionary:
	# GDScript loop iterators retain their input Dictionary across an await in
	# the same frame. Let this observer's stack exit before testing owner death.
	var images:Dictionary={};var reads:=0
	for job:Dictionary in queue._jobs.values():
		for image:Image in job.result.get("prefab_texture_packet",{}).get("images",{}).values():images[image.get_instance_id()]=weakref(image)
		reads+=int(job.result.get("read_profile",{}).get("reads_started",0))
	return {"images":images,"reads":reads}

func cancel_case(fixture:SceneTree,_path:String,source:Dictionary,index:Dictionary,entries:Array,detach:bool)->void:
	var queue:=new_queue(fixture,index,entries,source.path);queue.hold_geometry=false;queue.hold_pixels=true
	queue.begin_entry_prefetch(self,entries[0].bounds.grow(1),{})
	var deadline:=Time.get_ticks_msec()+5000
	while not queue.pixel_blocked and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	var ledger:RefCounted=queue._admission;var pool:RefCounted=queue._shared_images;var gate:Semaphore=queue.pixel_gate
	check(ledger.reserved_bytes>0,"cancel fixture has live admitted work")
	if detach:
		root.add_child(queue);root.remove_child(queue);queue.free()
		check(ledger.reserved_bytes>0,"map detachment leaves the blocked CPU half charged to the drainer")
		gate.post();deadline=Time.get_ticks_msec()+5000
		while ledger.reserved_bytes>0 and Time.get_ticks_msec()<deadline:await process_frame
	else:
		release_after_frames(gate)
		await queue.quiesce();queue.free()
	check(ledger.reserved_bytes==0 and ledger.active_workers()==0 and pool.snapshot().outputs==0,"detach/quiesce joins both halves before clearing owners and leases")

func release_after_frames(gate:Semaphore)->void:
	for i:int in 4:await process_frame
	gate.post()

func solo_case(fixture:SceneTree,source:Dictionary,index:Dictionary,entries:Array)->void:
	var queue:=new_queue(fixture,index,entries,source.path);queue.hold_geometry=false
	queue.begin_entry_prefetch(self,entries[0].bounds.grow(1),{});queue._admission.worker_limit=1
	var deadline:=Time.get_ticks_msec()+10000
	while not complete(queue,1) and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(complete(queue,1) and queue.profile.get("parallel_pixel_jobs",0)==0 and queue._admission.peak_workers==1,"single available slot completes serially without extra thread or duplicate read")
	await queue.quiesce();queue.free()
