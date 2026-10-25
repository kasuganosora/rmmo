extends SceneTree
## CPU regression by default. --gpu adds real publication/pixel parity on the
## private desktop; uses only newly created maps and images.
const Prep=preload("res://scripts/world3d/prefab_texture_preparation.gd")
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Chunk=preload("res://scripts/world3d/chunk_reference_preparation.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const Files=preload("res://tools/test_map_dependency_index.gd")
const Fixture=preload("res://tools/structure_dependency_fixture.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Pixels=preload("res://scripts/world3d/runtime_texture_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
var passed:=0
var failed:=0
var files:SceneTree
class CounterToken extends RefCounted:
	var checks:=0
	var after:=1
	func is_cancelled()->bool:
		checks+=1;return checks>=after
class Errors extends Logger:
	var errors:Array[String]=[]
	var mutex:=Mutex.new()
	func _log_error(function:String,_file:String,_line:int,code:String,rationale:String,_editor_notify:bool,_type:int,_backtraces:Array)->void:
		mutex.lock();errors.append(function+": "+code+" "+rationale);mutex.unlock()
class ReplaceToken extends RefCounted:
	var checks:=0
	var path:=""
	var bytes:=PackedByteArray()
	func is_cancelled()->bool:
		checks+=1
		if checks==3:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes);file.close()
		return false
class NativeProbe extends Deferred:
	var accepted:=0
	var publication_calls:=0
	var hold_until_cancel:=false
	func _make_prepare_task(path:String,digest:String,token:RefCounted,item:Dictionary,faces:bool,root_:String,requests:Array,native:bool,need_model:bool)->Callable:
		var task:=super(path,digest,token,item,faces,root_,requests,native,need_model)
		return cancelled_task.bind(task,token) if hold_until_cancel else task
	static func cancelled_task(task:Callable,token:RefCounted)->Dictionary:
		while not token.is_cancelled():OS.delay_usec(100)
		return task.call()
	func _accept_prepared_records(result:Dictionary)->void:
		accepted+=1;super(result)
	func _publish_ready(_began:int,_budget:int=INTERACTIVE_BUDGET_US)->Dictionary:
		publication_calls+=1
		return {"units":0,"unit_us":0,"max_unit_us":0,"scan_us":0}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failed+=1
func canonical(image:Image)->PackedByteArray:
	var copy:=Image.create_from_data(image.get_width(),image.get_height(),image.has_mipmaps(),image.get_format(),image.get_data())
	if copy.get_format()==Image.FORMAT_RGB8:copy.convert(Image.FORMAT_RGBA8)
	return copy.get_data()
func prepare_worker(requests:Dictionary,plan:Dictionary,token:RefCounted=null)->Dictionary:
	var worker:=Thread.new();var started:=worker.start(Prep.prepare.bind(requests,plan,files.content_root,token))
	check(started==OK,"CPU image preparation worker starts")
	while worker.is_alive():await process_frame
	return worker.wait_to_finish() if started==OK else {"error":"start","images":{}}
func bridge(name_:String,x:float,material:Dictionary)->Dictionary:
	var record:=Fixture.bridge(name_,x,files.content_root)
	var data:=Prefab.decode(record.house_prefab).duplicate(true);data.materials=[{"paint":material.duplicate(true),"cull":0}]
	var encoded:=var_to_bytes(data)
	record.house_prefab={"version":1,"sha256":Index.Store._sha(encoded),"length":encoded.size(),"data":Marshalls.raw_to_base64(encoded.compress(FileAccess.COMPRESSION_ZSTD))}
	record.prefab_materials=[material.duplicate(true)]
	record.bridge_materials={"deck":material.duplicate(true),"masonry":material.duplicate(true),"trim":material.duplicate(true)}
	return record
func run()->void:
	Pixels.Policy.verify_packages=true # This fixture deliberately replaces source bytes.
	# Exercise the opt-in pipeline explicitly; whole-entry performance currently
	# keeps it disabled by default until shared image preparation is available.
	Deferred.prefab_texture_preparation_enabled=true
	Deferred.native_entry_prefetch_enabled=true
	var logger:=Errors.new();OS.add_logger(logger)
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("prefab_pixels_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("pixels.png");files.created.append(path)
	var image:=Image.create(19,13,false,Image.FORMAT_RGB8)
	for y:int in 13:
		for x:int in 19:image.set_pixel(x,y,Color(float(x%7)/6.,float(y%5)/4.,float((x+y)%9)/8.))
	check(image.save_png(path)==OK,"save temporary RGB source")
	var author_bytes:=FileAccess.get_file_as_bytes(path)
	var material:Dictionary={"name":"prepared bridge","color":[1,1,1,1],"roughness":.8,"texture_path":path,"normal_path":path,"normal_format":"directx"}
	var record:=bridge("bridge_a",100,material);var other:=bridge("bridge_b",200,material)
	var requests:=Prep.sources(record);requests.merge(Prep.sources(other),true)
	var plan:=Prep.estimate(requests,files.content_root)
	check(requests.size()==2 and plan.rows.size()==2,"shared references deduplicate per path and normal orientation")
	check(plan.estimated_bytes>plan.output_bytes*2 and plan.output_bytes==Prep.Headers._mip_bytes(19,13,4)*2,"admission includes retained unique outputs plus bounded sequential workspace")
	var ordered:Dictionary={};var reversed:Dictionary={}
	for i:int in 7:
		var large_path:String=files.folder.path_join("header_%d.png"%i);files.created.append(large_path)
		var header:=author_bytes.slice(0,33)
		for at:int in [16,20]:header[at]=0;header[at+1]=0;header[at+2]=16;header[at+3]=0
		files.write_bytes(large_path,header);ordered[large_path]=[large_path,false,false]
	for i:int in range(6,-1,-1):
		var large_path:String=files.folder.path_join("header_%d.png"%i);reversed[large_path]=[large_path,false,false]
	var bounded:=Prep.estimate(ordered,files.content_root)
	check(bounded.rows.size()==6 and bounded==Prep.estimate(reversed,files.content_root),"bounded image subset is deterministic across request and author ordering")
	var old_textures:=Paint._textures.duplicate();var old_materials:=Paint._materials.duplicate();var old_prepared:=Paint.prepared_images.duplicate()
	var packet:=await prepare_worker(requests,plan)
	check(packet.error.is_empty() and packet.images.size()==2 and packet.sources.size()==1,"worker prepares two orientations and binds one exact source digest")
	check(packet.profile.cache_writes==2 and packet.profile.decoded==2,"cold CPU preparation persists both compact orientations without a renderer")
	for flip:bool in [false,true]:files.created.append(Pixels.cache_path(path,flip))
	var stored:=FileAccess.get_file_as_bytes(Pixels.cache_path(path,false));var stored_data:Dictionary=bytes_to_var(stored.slice(32))
	check(Pixels.Envelope.checksum(stored.slice(32))==stored.slice(0,32) and stored_data.format==Image.FORMAT_RGB8 and stored_data.source==FileAccess.get_sha256(path),"atomic pixel envelope keeps compact RGB and exact source digest")
	check(packet.profile.has("header_us") and packet.profile.has("read_sha_us") and packet.profile.has("source_decode_us") and packet.profile.has("final_sha_us"),"preparation reports header, immutable read/hash, decode and final proof separately")
	var before_store:=FileAccess.get_file_as_bytes(Pixels.cache_path(path,false))
	var compact:=Image.load_from_file(path);compact.generate_mipmaps()
	check(not Pixels.store_pixels(path,false,compact,FileAccess.get_sha256(path),33) and FileAccess.get_file_as_bytes(Pixels.cache_path(path,false))==before_store,"bounded optional cache write preserves previous entry when envelope exceeds limit")
	check(not Pixels.store_pixels(path,false,compact,FileAccess.get_sha256(path),134217760,func():return false) and FileAccess.get_file_as_bytes(Pixels.cache_path(path,false))==before_store,"cancelled cache publication leaves no partial or replaced envelope")
	check(Array(DirAccess.get_files_at(Pixels.DIR)).filter(func(name_):return name_.begins_with(Pixels.cache_path(path,false).get_file()) and name_.ends_with(".tmp")).is_empty(),"vetoed atomic cache publication removes its temporary file")
	check(Paint._textures==old_textures and Paint._materials==old_materials and Paint.prepared_images==old_prepared,"worker does not mutate render or shared pixel caches")
	for flip:bool in [false,true]:
		var key:String=path+("|normal|flip_y" if flip else "")
		var reference:=Pixels.image(path,flip);files.created.append(Pixels.cache_path(path,flip))
		check(canonical(packet.images[key])==canonical(reference),"raw prepared pixels and every mip match existing decode with flip="+str(flip))
		check(packet.images[key].get_meta("runtime_source_sha256")==FileAccess.get_sha256(path),"image identity covers actual immutable source bytes")
	var cached:=await prepare_worker(requests,plan)
	check(cached.error.is_empty() and cached.profile.cache_hits==2,"bounded existing decoded pixel caches are consumed without rewriting")
	check(cached.profile.cache_writes==0 and cached.profile.decoded==0 and not cached.profile.has("persist_source_sha_us"),"warm preparation has no encode/write or cold-cache extra source hash")
	check(canonical(cached.images[path])==canonical(packet.images[path]),"cold decode and warm cache have identical pixels")
	var token:=CounterToken.new()
	var cancelled:=await prepare_worker(requests,plan,token)
	check(cancelled.get("cancelled",false) and cancelled.images.is_empty(),"cancel before IO retains no image output")
	token=CounterToken.new();token.after=3
	cancelled=await prepare_worker(requests,plan,token)
	check(cancelled.cancelled and cancelled.images.is_empty(),"cancel between images releases partial CPU output")
	var changed:=Image.create(20,13,false,Image.FORMAT_RGB8);changed.fill(Color.BLUE);changed.save_png(path)
	check(not Prep.verify(packet,files.content_root),"final full source SHA rejects replacement")
	var rejected_profile:Dictionary={}
	check(not Pixels.store_pixels(path,false,compact,Prep._digest(author_bytes),134217760,Prep._authorize_cache.bind(path,Prep._digest(author_bytes),files.content_root,null,rejected_profile)) and FileAccess.get_file_as_bytes(Pixels.cache_path(path,false))==before_store,"source replaced before atomic rename cannot publish a stale snapshot as current cache")
	check(not Prep.prepare(requests,plan,files.content_root).error.is_empty(),"changed dimensions reject old reservation before image allocation")
	var row:Dictionary=plan.rows[path]
	check(not Prep._snapshot_matches(row,FileAccess.get_file_as_bytes(path)),"immutable codec snapshot dimensions independently reject resize race")
	files.write_bytes(path,author_bytes)
	var variant_path:String=files.folder.path_join("same_length.png");files.created.append(variant_path)
	var first:=Image.create(1,1,false,Image.FORMAT_RGBA8);first.fill(Color.RED)
	var last:=Image.create(1,1,false,Image.FORMAT_RGBA8);last.fill(Color.BLUE)
	var first_bytes:=first.save_png_to_buffer();var last_bytes:=last.save_png_to_buffer()
	var padded_size:int=maxi(first_bytes.size(),last_bytes.size());first_bytes.resize(padded_size);last_bytes.resize(padded_size)
	files.write_bytes(variant_path,first_bytes)
	# Keep this race specifically between variants rather than in cold-cache
	# publication's additional cancellation/source check.
	for flip:bool in [false,true]:Pixels.image(variant_path,flip);files.created.append(Pixels.cache_path(variant_path,flip))
	var variants:Dictionary={variant_path:[variant_path,false,false],variant_path+"|normal|flip_y":[variant_path,true,true]}
	var mutator:=ReplaceToken.new();mutator.path=variant_path;mutator.bytes=last_bytes
	var mixed:=await prepare_worker(variants,Prep.estimate(variants,files.content_root),mutator)
	check(mixed.error=="Prefab texture changed between prepared variants" and mixed.images.is_empty(),"same-size source replacement between orientations cannot overwrite first digest")
	var outside:Dictionary={"D:/not_authorized.png":["D:/not_authorized.png",false,false]}
	check(Prep.estimate(outside,files.folder).rows.is_empty(),"out-of-root inputs never enter CPU image preparation")
	files.write_bytes(Pixels.cache_path(path,false),"corrupt".to_utf8_buffer())
	var repaired:=await prepare_worker(requests,plan)
	check(repaired.error.is_empty() and repaired.profile.decoded==1 and canonical(repaired.images[path])==canonical(packet.images[path]),"corrupt optional pixel cache falls back to exact source snapshot")
	var repaired_again:=await prepare_worker(requests,plan)
	check(repaired.profile.cache_writes==1 and repaired_again.profile.cache_hits==2,"corrupt-cache repair is atomically persistent for the next load")
	var source:Dictionary=files.fixture("bridge",[record,other],Fixture.metadata([record,other]))
	var source_sha:=FileAccess.get_sha256(source.path)
	var index:=Index.build(source.path,files.content_root,[record,other])
	check(index.ok,"temporary frozen bridge directory builds with texture path descriptors")
	if index.ok:
		var read:=Index.read(source.path,files.content_root)
		check(read.ok,"new derived directory schema roundtrips")
		var entries:Array=Index.select(read,[]).deferred_entries
		var queue:=Deferred.new();queue._reference_index=read;queue._reference_root=files.content_root
		Deferred.prefab_texture_preparation_enabled=false
		var old:=queue._estimate_job({"native_reference":true},entries)
		Deferred.prefab_texture_preparation_enabled=true
		var current:=queue._estimate_job({"native_reference":true},entries)
		check(current.estimated_bytes-old.estimated_bytes==plan.estimated_bytes,"two prefab rows reserve each shared image only once per job")
		var attempts:int=queue.profile.prefab_texture_plan_builds
		for attempt:int in 4:queue._estimate_job({"native_reference":true},entries)
		check(queue.profile.prefab_texture_plan_builds==attempts and queue.profile.prefab_texture_plan_hits>=4,"waiting admission and route retries do not reopen image headers every frame")
		queue._demand_revision+=1;queue._estimate_job({"native_reference":true},entries)
		check(queue.profile.prefab_texture_plan_builds==attempts+1,"new demand performs a fresh bounded header attempt")
		var oversized:Dictionary={}
		for i:int in 257:oversized[path+str(i)]=[path+str(i),false,false]
		var oversized_index:=read.duplicate(true);oversized_index.rows[0].prefab_textures=oversized
		queue.configure_references(oversized_index,source.path,files.content_root)
		check(queue._estimate_job({"native_reference":true},entries).prefab_texture_plan.is_empty(),"overlarge optional image union retains ordinary loading without a new failure")
		queue.configure_references(read,source.path,files.content_root)
		check(queue._admission.reserve("bridge",current) and queue._admission.reserved_bytes==current.estimated_bytes,"pixel outputs and scratch enter the same model/reference ledger")
		var worker:=Thread.new();worker.start(Chunk.prepare.bind(read,entries,source.path,files.content_root,null,null,current.prefab_texture_plan))
		while worker.is_alive():await process_frame
		var result:Dictionary=worker.wait_to_finish()
		check(result.error.is_empty() and result.prefab_texture_packet.images.size()==2 and result.prefab_cpu.size()==1,"real reference worker hands off unique CPU images with prepared geometry")
		check(queue._admission.reserved_bytes==current.estimated_bytes,"ready pixels remain charged until disposal")
		var reference:WeakRef=weakref(result.prefab_texture_packet.images[path])
		var packet_alias:Dictionary=result.prefab_texture_packet
		if "--gpu" in OS.get_cmdline_user_args():await gpu_publication(record,result.prefab_cpu[record.house_prefab.sha256],result.prefab_texture_packet)
		Drainer.dispose_result(result);queue._admission.release("bridge")
		check(reference.get_ref()==null and packet_alias.is_empty() and queue._admission.reserved_bytes==0,"main discard clears packet aliases and image owners before ledger bytes")
		var wrong:Dictionary=read.duplicate(true);wrong.rows[0].prefab_textures={}
		check(not Chunk.prepare(wrong,entries,source.path,files.content_root,null,null,plan).error.is_empty(),"forged dependency hint cannot bypass hydrated record comparison")
		queue.free()
		await native_prefetch_cases(read,entries,source.path,path)
	check(FileAccess.get_sha256(source.path)==source_sha and FileAccess.get_file_as_bytes(path)==author_bytes,"author source and map bytes are unchanged")
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors in addition to assertion results")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	for created:String in files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(source.path+".resources");DirAccess.remove_absolute(files.folder);files.free()
	print("PREFAB_TEXTURE_PREPARATION passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)
func gpu_publication(record:Dictionary,cpu:Dictionary,packet:Dictionary)->void:
	if not check_gpu():return
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint._textures.clear();Paint._materials.clear()
	var sentinel:=Image.create(1,1,false,Image.FORMAT_RGBA8);Paint.prepared_images={"sentinel":sentinel}
	var timings:Dictionary={};var pool:Dictionary={}
	check(Prefab.publish_prepared(record,cpu,{},pool,timings,packet),"real main publication consumes worker pixels")
	var entry:Dictionary=Prefab._meshes[record.house_prefab.sha256]
	check(entry.mesh._collision_faces==cpu.collision_faces[0],"publication retains exact prepared collision faces")
	var material:StandardMaterial3D=entry.mesh.materials[0];RenderingServer.force_sync()
	check(canonical(material.albedo_texture.get_image())==canonical(packet.images[record.prefab_materials[0].texture_path]),"GPU albedo pixels/mips equal worker image")
	check(Paint.prepared_images.size()==1 and Paint.prepared_images.sentinel==sentinel,"publication restores unrelated pixel handoff scope")
	check(timings.has("materials_ms") and timings.has("render_identity_ms"),"publication separates material CPU/upload from geometry identity")
	var again:Dictionary={};check(Prefab.publish_prepared(record,cpu,{},pool,again,packet) and again.get("geometry_cache_hit",false),"identical prepared publication retains geometry reuse")
	var retained_pool:=pool.duplicate()
	Paint._textures.clear()
	check(not retained_pool.is_empty() and Prefab.publish_prepared(record,cpu,{},pool,{},packet) and pool==retained_pool,"hot texture eviction preserves caller materials owning the verified source generation")
	var path:String=record.prefab_materials[0].texture_path
	var original:=FileAccess.get_file_as_bytes(path)
	var replacement:=Image.create(19,13,false,Image.FORMAT_RGBA8);replacement.fill(Color(.1,.9,.3,.5));replacement.save_png(path)
	var replaced:=await prepare_worker(Prep.sources(record),Prep.estimate(Prep.sources(record),files.content_root))
	var old_texture:Texture2D=material.albedo_texture;var old_pixels:=canonical(old_texture.get_image())
	check(Prefab.publish_prepared(record,cpu,{},pool,{},replaced),"unchanged prefab identity accepts verified replacement texture generation")
	var new_material:StandardMaterial3D=Prefab._meshes[record.house_prefab.sha256].mesh.materials[0];RenderingServer.force_sync()
	check(new_material!=material and new_material.albedo_texture!=old_texture and new_material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"replacement invalidates prefab render and caller material caches")
	check(canonical(new_material.albedo_texture.get_image())==canonical(replaced.images[path]) and canonical(old_texture.get_image())==old_pixels,"new publication gets current pixels while existing live material retains its immutable old pixels")
	files.write_bytes(path,original)
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint.prepared_images.clear();Paint._materials.clear();Paint._textures.clear();pool.clear();entry.clear();material=null
	new_material=null;old_texture=null;replaced.clear()
	await process_frame;RenderingServer.force_sync()
func check_gpu()->bool:
	Pixels.Policy.verify_packages=true # Publication regressions mutate source files in isolated roots.
	var ok:bool=DisplayServer.get_name()!="headless";check(ok,"--gpu requires private real renderer");return ok

func native_queue(index:Dictionary,entries:Array,map_path:String)->NativeProbe:
	var queue:=NativeProbe.new();queue.configure_references(index,map_path,files.content_root);queue.loading_worker_limit=2
	for entry:Dictionary in entries:
		var key:String="reference:"+entry.group_id if not entry.group_id.is_empty() else "reference:"+str(entry.record_index)
		queue.pending.append({"record":entry.compact_record,"path":key,"bounds":entry.bounds,"digest":"","memory":{"estimated_bytes":entry.memory_bytes,"known":true,"exclusive":false},"reference_entry":entry,"native_reference":true,"reference_prepared":false,"group_id":entry.group_id})
	return queue

func native_prefetch_cases(index:Dictionary,entries:Array,map_path:String,image_path:String)->void:
	var selected:Dictionary=entries[0];var clip:AABB=selected.bounds.grow(.1)
	var queue:=native_queue(index,entries,map_path)
	Deferred.native_entry_prefetch_enabled=false
	check(queue.begin_entry_prefetch(self,clip,{}),"real native reference queue enters the existing safety transaction")
	queue.pump_entry_prefetch()
	check(queue._jobs.is_empty(),"legacy switch excludes native work from core overlap")
	Deferred.native_entry_prefetch_enabled=true
	var meshes:=Prefab._meshes.duplicate();var renders:=Prefab._render_meshes.duplicate()
	var textures:=Paint._textures.duplicate();var materials:=Paint._materials.duplicate();var assets:=Deferred.Assets._scenes.duplicate()
	queue.pump_entry_prefetch()
	check(queue._jobs.size()==1 and queue.profile.entry_prefetch_native_jobs==1,"only the required native bridge group starts before core readiness")
	var key:String=queue._jobs.keys()[0];var job:Dictionary=queue._jobs[key];var charge:int=queue._admission.reserved_bytes
	var deadline:=Time.get_ticks_msec()+5000
	while not job.has("result") and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(job.has("result") and job.result.get("error","").is_empty() and job.result.prefab_texture_packet.images.size()==2,"real reference worker prepares geometry and pixels during core overlap")
	check(queue.accepted==0 and queue.publication_calls==0 and queue._prepared_paths.is_empty(),"prefetch cannot accept records, publish specs or fill the main handoff table")
	check(Prefab._meshes==meshes and Prefab._render_meshes==renders and Paint._textures==textures and Paint._materials==materials and Deferred.Assets._scenes==assets,"real native prefetch leaves all shared material, mesh and model caches unchanged")
	if job.estimate.has("pixel_retained_bytes"):
		var retained:int=int(job.estimate.pixel_retained_bytes)-int(job.estimate.get("collision_workspace_bytes",0))+int(queue._shared_images.profile.retained_bytes)
		check(queue._admission.reserved_bytes==retained and retained>0 and retained<=charge,"ready shared pixels and geometry remain charged after decoder scratch retires")
	else:check(queue._admission.reserved_bytes==charge and charge>=int(job.estimate.prefab_texture_plan.estimated_bytes),"ready native pixel packet retains its entire admission charge")
	var image_owner:WeakRef=weakref(job.result.prefab_texture_packet.images[image_path]);var alias:Dictionary=job.result.prefab_texture_packet
	queue.finish_entry_prefetch();var map:=Node3D.new();root.add_child(map);map.set_meta("extras",{"rmmo_records":[]});map.add_child(queue);queue.activate(null);queue.set_process(false);queue._admission.worker_limit=0
	queue._process(0)
	check(queue.accepted==1 and queue.publication_calls==1 and is_same(queue._jobs[key],job) and queue.profile.entry_prefetch_native_jobs==1,"normal entry accepts the identical native packet once without redispatch")
	await queue.quiesce()
	check(image_owner.get_ref()==null and alias.is_empty() and queue._admission.reserved_bytes==0,"cancel after handoff clears native image aliases before returning bytes")
	job.clear();map.free()
	# Diagnostic strict readers reject a changed file. Ordinary mounted package
	# snapshots deliberately keep their already-mounted map revision instead.
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd")
	var old_verify:bool=policy.verify_packages;policy.verify_packages=true
	var source_bytes:=FileAccess.get_file_as_bytes(map_path);files.write_bytes(map_path,source_bytes+PackedByteArray([32]))
	queue=native_queue(index,entries,map_path);queue.begin_entry_prefetch(self,clip,{});queue.pump_entry_prefetch()
	deadline=Time.get_ticks_msec()+5000
	while queue.path_errors.is_empty() and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	check(not queue.path_errors.is_empty() and queue.accepted==0 and queue.publication_calls==0 and queue._admission.reserved_bytes==0,"strict native prefetch rejects changed map identity without publishing or leaking its reservation")
	await queue.quiesce();queue.free();policy.verify_packages=old_verify
	var mounted:Dictionary=Chunk.prepare(index,entries,map_path,files.content_root,null,null,{}, {},0,true)
	check(FileAccess.get_sha256(map_path)!=index.source_sha256 and mounted.error.is_empty(),"trusted mounted preparation consumes its snapshot despite a different on-disk map revision")
	Drainer.dispose_result(mounted);files.write_bytes(map_path,source_bytes)
	queue=native_queue(index,entries,map_path);queue.hold_until_cancel=true
	queue.begin_entry_prefetch(self,clip,{});queue.pump_entry_prefetch()
	var worker:Thread=queue._jobs.values()[0].worker
	check(worker.is_started() and queue._admission.reserved_bytes>0,"in-flight native work holds its full reservation")
	await queue.quiesce()
	check(not worker.is_started() and queue._jobs.is_empty() and queue._admission.reserved_bytes==0 and queue.accepted==0,"cancelling running native prefetch joins the CPU task before retiring its charge")
	queue.free()
	queue=native_queue(index,entries,map_path);queue.begin_entry_prefetch(self,clip,{});queue.pump_entry_prefetch()
	key=queue._jobs.keys()[0];deadline=Time.get_ticks_msec()+5000
	while not queue._jobs[key].has("result") and Time.get_ticks_msec()<deadline:queue.pump_entry_prefetch();await process_frame
	image_owner=weakref(queue._jobs[key].result.prefab_texture_packet.images[image_path]);alias=queue._jobs[key].result.prefab_texture_packet
	var ledger:RefCounted=queue._admission
	queue.free()
	check(image_owner.get_ref()==null and alias.is_empty() and ledger.reserved_bytes==0,"loader abandonment before handoff disposes ready native images and their complete lease")
