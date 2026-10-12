extends SceneTree
## CPU-only scheduler/identity regression. CpuTicket has no image/RID; real
## material consumption and rendering are covered by the private GPU tests.
const Base=preload("res://tools/test_prefab_texture_preparation.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
class CpuTicket extends Texture2D:
	func _get_width()->int:return 19
	func _get_height()->int:return 13
class Queue extends Deferred:
	var hold:=false
	var gate:=Semaphore.new()
	func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,faces:bool,root_:String,requests:Array,native:bool,need_model:bool)->Callable:
		var task:=super(path,digest,token,item,faces,root_,requests,native,need_model)
		return held.bind(task,gate) if hold else task
	static func held(task:Callable,barrier:Semaphore)->Dictionary:
		barrier.wait();return task.call()
var passed:=0
var failed:=0
var fixture:SceneTree
var source:Dictionary
var index:Dictionary
var entries:Array=[]
var paths:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func make_record()->Dictionary:
	var materials:Array=[]
	for group:int in 3:
		var material:Dictionary={"name":"bridge part %d"%group,"color":[1,1,1,1],"roughness":.8}
		for slot:int in (4 if group<2 else 3):
			var path:String=fixture.files.folder.path_join("source_%d.png"%paths.size())
			var image:=Image.create(19,13,false,Image.FORMAT_RGB8);image.fill(Color(.03*(paths.size()+1),.3,.7))
			image.save_png(path);paths.append(path);fixture.files.created.append(path)
			material[["texture_path","normal_path","roughness_path","ao_path"][slot]]=path
		materials.append(material)
	var record:Dictionary=fixture.bridge("targeted_bridge",100,materials[0])
	var data:Dictionary=Prefab.decode(record.house_prefab)
	data.materials=[]
	for material:Dictionary in materials:data.materials.append({"paint":material.duplicate(true),"cull":0})
	var arrays:Array=data.meshes[0].surfaces[0]
	data.meshes[0].surfaces=[arrays.duplicate(true),arrays.duplicate(true),arrays.duplicate(true)]
	data.meshes[0].materials=[0,1,2]
	var bytes:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Index.Store._sha(bytes),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}
	record.prefab_materials=materials
	record.bridge_materials={"deck":materials[0],"masonry":materials[1],"trim":materials[2]}
	return record
func tickets(count:int)->void:
	Paint._textures.clear()
	for i:int in count:
		var texture:=CpuTicket.new();texture.set_meta("runtime_source_sha256",FileAccess.get_sha256(paths[i]));Paint._textures[paths[i]]=texture
func make_queue(core_ready:bool=true)->Queue:
	var map:=Node.new();root.add_child(map)
	map.set_meta("entry_plan",{"core_resources_ready_us":1 if core_ready else 0})
	var queue:=Queue.new();map.add_child(queue);queue.configure_references(index,source.path,fixture.files.content_root)
	for entry:Dictionary in entries:
		queue.pending.append({"record":entry.compact_record,"path":"reference:"+entry.group_id,"bounds":entry.bounds,"digest":"","memory":{"estimated_bytes":entry.memory_bytes,"known":true,"exclusive":false},"reference_entry":entry,"native_reference":true,"reference_prepared":false,"group_id":entry.group_id})
	queue.activate(map);queue.set_process(false);queue._admission.worker_limit=2;queue.ready_job_limit=2
	queue.set_demand("entry_safety",entries[0].bounds.grow(1),-3);queue.set_demand_scope(["entry_safety"]);queue._refresh_demanded()
	return queue
func drop(queue:Queue)->void:
	var map:=queue.get_parent();await queue.quiesce();map.free()
func wait_ready(queue:Queue)->Dictionary:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		queue._refresh_demanded();queue._poll_jobs(queue._demanded_by_path);queue._resume_pixel_jobs(self);queue._dispatch_jobs(self)
		for job:Dictionary in queue._jobs.values():
			if job.has("result") and not job.has("worker") and not job.result.get("waiting_pixels",false):return job
		if not queue.path_errors.is_empty():break
		await process_frame
	check(false,"bounded CPU job reaches ready: "+str(queue.path_errors));return {}
func run()->void:
	var logger:=Base.Errors.new();OS.add_logger(logger)
	check(Deferred.bridge_texture_preparation_enabled,"verified targeted bridge preparation is enabled by default")
	check(not Deferred.prefab_texture_preparation_enabled and not Deferred.shared_prefab_texture_preparation_enabled and not Deferred.native_entry_prefetch_enabled,"old broad experiments remain disabled")
	fixture=Base.new();fixture.files=Base.Files.new();fixture.files.content_root=Prep.Paths.external_root();fixture.files.folder=Prep.Paths.cache_directory("targeted_bridge_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(fixture.files.folder)
	var record:=make_record();var far:Dictionary=record.duplicate(true);far.uuid="far_bridge";far.position=[900,-.4,0]
	source=fixture.files.fixture("targeted",[record,far],Base.Fixture.metadata([record,far]))
	check(Index.build(source.path,fixture.files.content_root,[record,far]).ok,"temporary native bridge directory builds")
	index=Index.read(source.path,fixture.files.content_root);entries=Index.select(index,[]).deferred_entries
	var sources:=Prep.sources(record);var plan:=Prep.estimate(sources,fixture.files.content_root)
	check(sources.size()==11 and plan.rows.size()==11,"three real material slots declare all eleven unique sources")
	var queue:=make_queue();var item:Dictionary=queue._demanded[0];var requests:Array=queue._reference_requests(item.path)
	Deferred.bridge_texture_preparation_enabled=false
	check(queue._prefab_texture_plan(item,requests).is_empty(),"explicit rollback keeps the previous route")
	Deferred.bridge_texture_preparation_enabled=true
	check(queue._targeted_bridge_textures(item) and queue._prefab_texture_plan(item,requests).rows.size()==11,"candidate uses actual demanded native bridge with complete declaration")
	check(queue._demanded.size()==1 and not queue._targeted_bridge_textures(queue.pending[1]),"far bridge sharing the same eleven sources is not selected")
	var house:Dictionary=item.duplicate(true);house.reference_entry.reason="native_building"
	check(not queue._targeted_bridge_textures(house) and queue._prefab_texture_plan(house,requests).is_empty(),"candidate does not enable house/group texture work")
	queue.get_parent().set_meta("entry_plan",{"core_resources_ready_us":0})
	check(not queue._targeted_bridge_textures(item),"core-not-published cannot enter candidate")
	queue.get_parent().set_meta("entry_plan",{"core_resources_ready_us":1});queue._entry_prefetch={"clip":entries[0].bounds}
	check(not queue._targeted_bridge_textures(item),"early prefetch cannot duplicate initial CPU images")
	queue._entry_prefetch.clear();queue._scene_handoff=true
	check(not queue._targeted_bridge_textures(item),"scene handoff suspends candidate dispatch")
	queue._scene_handoff=false
	queue.set_demand("player",entries[0].bounds.grow(1));queue.set_demand_scope(["player"]);queue.release_demand("entry_safety");queue._refresh_demanded()
	check(queue._targeted_bridge_textures(item),"later live demand keeps the same bounded bridge route")
	tickets(7);queue._dispatch_jobs(self)
	check(queue._jobs.size()==1 and queue._shared_images.snapshot().outputs==4,"exactly four missing outputs are leased; no far group is dispatched")
	var job:=await wait_ready(queue)
	if not job.is_empty():
		var packet:Dictionary=job.result.prefab_texture_packet
		check(job.result.error.is_empty() and packet.sources.size()==11 and packet.images.size()==4,"worker returns four Images while verifying all eleven source dependencies")
		check(packet.profile.get("resident_hits",0)==7 and job.pixel_tickets.size()==7,"seven resident immutable owners survive the worker without pixel decode")
		check(packet.profile.get("decoded",0)+packet.profile.get("cache_hits",0)==4,"only four missing image payloads are prepared")
		check(Prep.verify(packet,fixture.files.content_root) and Prefab.tickets_valid(job.pixel_tickets,packet.sources),"final source and exact ticket checks still gate acceptance")
		check(queue.profile.bridge_texture_jobs==1 and queue.profile.bridge_texture_declared_keys==11 and queue.profile.bridge_texture_missing_keys==4,"candidate report distinguishes full declarations from missing image work")
		var expected_retained:=0
		for missing:int in range(7,11):expected_retained+=int(plan.rows[paths[missing]].output_bytes)*2
		check(queue._shared_images.snapshot().retained_bytes==expected_retained,"only missing CPU/upload copies remain charged after worker join")
		var alias:Dictionary=packet;var weak:WeakRef=weakref(packet.images[paths[7]]);job={};packet={}
		await queue.quiesce()
		check(alias.is_empty() and weak.get_ref()==null and queue._admission.reserved_bytes==0,"quiesce clears ready aliases before releasing retained bytes")
	await drop(queue)
	tickets(11);queue=make_queue();queue._dispatch_jobs(self);job=await wait_ready(queue)
	if not job.is_empty():
		var packet:Dictionary=job.result.prefab_texture_packet
		check(packet.images.is_empty() and packet.sources.size()==11 and packet.profile.resident_hits==11,"complete resident materials still verify all sources without optional Images")
		check(queue._shared_images.snapshot().outputs==0 and queue.profile.bridge_texture_all_resident_jobs==1,"all-resident route creates no output lease")
		check(int(job.estimate.estimated_bytes)-int(job.estimate.pixel_retained_bytes)==Pool.HASH_SCRATCH,"all-resident route reserves only bounded SHA scratch beyond geometry")
	job={};await drop(queue)
	tickets(7);queue=make_queue();queue.hold=true;queue._dispatch_jobs(self)
	check(queue._jobs.size()==1 and queue._shared_images.snapshot().retained_bytes>0,"cancel fixture holds an admitted worker and output leases")
	for pending_job:Dictionary in queue._jobs.values():pending_job.token.cancel()
	check(queue._admission.reserved_bytes>0,"cancellation does not release a running worker's bytes early")
	queue.gate.post();await queue.quiesce()
	check(queue._admission.reserved_bytes==0 and queue._shared_images.snapshot().outputs==0 and queue._shared_images.snapshot().produced==0,"cancelled generation publishes no pixels and releases everything after join")
	await drop(queue)
	tickets(7);queue=make_queue();item=queue._demanded[0];requests=queue._reference_requests(item.path)
	var estimate:Dictionary=queue._estimate_job(item,requests);var cached:Dictionary={}
	for key:String in Paint._textures:cached[key]=Paint._textures[key].get_meta("runtime_source_sha256")
	var offer:Dictionary=queue._shared_images.offer(plan,cached);var total:int=int(estimate.estimated_bytes)-int(plan.estimated_bytes)+int(offer.scratch_bytes)
	for bytes:int in offer.retained.values():total+=bytes
	queue._admission.byte_limit=total-1;queue._admission.reserve("held",{"estimated_bytes":1,"exclusive":false});queue._dispatch_jobs(self)
	check(queue._jobs.is_empty() and queue._shared_images.snapshot().outputs==0 and queue._admission.reserved_bytes==1,"insufficient bundle budget admits no partial image owners")
	queue._admission.release("held");await drop(queue)
	var original:=FileAccess.get_file_as_bytes(paths[0]);var changed:=Image.create(19,13,false,Image.FORMAT_RGB8);changed.fill(Color.RED);changed.save_png(paths[0])
	var stale:=Prep.prepare(sources,Prep.estimate(sources,fixture.files.content_root),fixture.files.content_root,null,true,{"pool":Pool.new(),"consumer":"stale","leaders":{},"cached":cached})
	check(stale.get("retry_pixels",false) and stale.images.is_empty(),"same-dimension replacement cannot borrow an old resident proof")
	fixture.files.write_bytes(paths[0],original)
	var cancelled:=Drainer.CancelToken.new();cancelled.cancel()
	check(Prep.prepare(sources,plan,fixture.files.content_root,cancelled).cancelled,"already-cancelled generation cannot decode or validate")
	Paint._textures.clear();Deferred.bridge_texture_preparation_enabled=false
	for path:String in paths:fixture.files.created.append(Prep.Pixels.cache_path(path,false))
	for created:String in fixture.files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(fixture.files.folder)
	fixture.files.free();fixture.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	print("TARGETED_BRIDGE_TEXTURES passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
