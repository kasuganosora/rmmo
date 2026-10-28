extends "res://tools/test_background_texture_upload.gd"
## Real native products through the existing preparation/pool/material slices.
## Ordinary loads must not reopen/decode source pixels or start duplicate work.
const Native=preload("res://scripts/world3d/streamed_texture_source.gd")
const Slices=preload("res://scripts/world3d/material_publication.gd")
class NativeHeldPool extends Pool:
	var gate:=Semaphore.new()
	var signal_mutex:=Mutex.new()
	var held:=false
	var first:=true
	func _load_stream(plan:Dictionary,digest:String)->Texture2D:
		var texture:=super(plan,digest)
		signal_mutex.lock();var hold:=first;first=false;held=hold;signal_mutex.unlock()
		if hold:gate.wait()
		return texture
	func is_held()->bool:
		signal_mutex.lock();var value:=held;signal_mutex.unlock();return value

func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9)
	if output.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	create_timer(100).timeout.connect(func():quit(2))
	var logger:=Errors.new();OS.add_logger(logger)
	check(Native.enabled(),"candidate supports enabled native streaming")
	if not Native.enabled():quit(2);return
	Pixels.Policy.verify_packages=false;Pool.background_upload_enabled=false
	Paint.texture_profile_enabled=true;Pixels.profile_enabled=true;Paint.cache_byte_budget=0
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=output.get_base_dir()
	var path:String=files.folder.path_join("native_source.png")
	var image:=Image.create(256,256,false,Image.FORMAT_RGBA8);image.fill(Color(.1,.3,.7,.6))
	check(image.save_png(path)==OK,"write isolated source")
	var source_sha:=FileAccess.get_sha256(path);image.generate_mipmaps()
	image.set_meta("runtime_upload_has_alpha",true)
	var normal:=Image.create(256,256,false,Image.FORMAT_RGBA8);normal.fill(Color(.1,.7,.7,.6));normal.generate_mipmaps()
	normal.set_meta("runtime_upload_has_alpha",true)
	for variant:Array in [[image,false,false],[normal,true,true]]:
		var writer:=Thread.new()
		writer.start(Native.publish.bind(path,variant[0],source_sha,"source",files.content_root,variant[1],variant[2]))
		while writer.is_alive():await process_frame
		check(writer.wait_to_finish()==OK,"publish completed native product before loading")
	var descriptor:=Native.descriptor_path(path,false,false,false)
	var descriptor_bytes:=FileAccess.get_file_as_bytes(descriptor)
	var damaged:Dictionary=JSON.parse_string(descriptor_bytes.get_string_from_utf8());damaged.bytes=1
	var metadata_file:=FileAccess.open(descriptor,FileAccess.WRITE);metadata_file.store_string(JSON.stringify(damaged));metadata_file.close()
	check(Native.plan(path,false,false,files.content_root).is_empty(),"descriptor cannot understate native payload admission")
	metadata_file=FileAccess.open(descriptor,FileAccess.WRITE);metadata_file.store_buffer(descriptor_bytes);metadata_file.close()
	var cancelled:=CounterToken.new();var cancelled_path:String=files.folder.path_join("cancelled.png")
	check(Native.publish(cancelled_path,image,source_sha,"source",files.content_root,false,false,cancelled)==ERR_SKIP and not FileAccess.file_exists(Native.descriptor_path(cancelled_path,false,false,false)),"cancelled conversion advertises no product")
	var definition:={"name":"native","color":[1.,1.,1.,1.],"roughness":.7,"tile_size":[1.,1.],"texture_path":path,"normal_path":path,"normal_format":"directx"}
	var record:=bridge("native",100,definition)
	var requested:=Prep.sources(record)
	var plan:=Prep.estimate(requested,files.content_root)
	check(plan.rows.size()==2 and plan.rows[path].extension=="stex" and plan.rows[path+"|normal|flip_y"].extension=="stex","two role/orientation variants select native plans")
	check(plan.estimated_bytes>=plan.output_bytes*2,"full-chain conservative reservation remains in the shared ledger")
	var old_image_texture:=ImageTexture.create_from_image(image)
	old_image_texture.set_meta("runtime_source_sha256",path.sha256_text())
	Paint.remember_texture_owner(path,old_image_texture)
	check(Prefab.texture_tickets(plan.rows).is_empty(),"full ImageTexture ticket cannot bypass an admitted native product")
	old_image_texture=null;clear_render()
	var pool:=Pool.new();pool.admission=Admission.new()
	var producer:=admit(pool,"producer",plan);var follower:=admit(pool,"follower",plan)
	Pixels.reset_profile()
	var waiting:=await prepare_shared(requested,plan,follower)
	check(waiting.waiting_pixels and waiting.images.is_empty(),"native follower returns without occupying a worker")
	var packet:=await prepare_shared(requested,plan,producer)
	var followed:=await prepare_shared(requested,plan,follower)
	check(packet.error.is_empty() and followed.error.is_empty() and packet.images.is_empty() and followed.images.is_empty(),"native preparation returns no complete CPU images")
	check(pool.snapshot().get("streamed_loads",0)==2 and pool.snapshot().produced==2 and pool.snapshot().shared_hits==2,"two consumers load each native variant exactly once")
	check(packet.uploaded_textures[path]==followed.uploaded_textures[path],"native consumers share one exact GPU owner")
	var owners:Dictionary={};var state:Dictionary={};var phase:=Slices.PROGRESS;var steps:=0
	while phase==Slices.PROGRESS and steps<8:
		phase=Slices.step_record_prepared(record,{},owners,packet,state);steps+=1
	check(phase==Slices.READY and owners.size()==2,"ordinary material slices admit texture-only variants")
	var scope:=Slices.begin_record_scope(record,packet,owners,state)
	var material:=Paint.make_material(definition);Slices.end_record_scope(scope)
	check(material.albedo_texture==packet.uploaded_textures[path] and material.normal_texture==packet.uploaded_textures[path+"|normal|flip_y"],"ordinary publication binds both shared native RIDs")
	check(Prefab.texture_tickets(plan.rows).size()==2,"next admission reuses both live native identities")
	var counters:Dictionary=Pixels.profile_snapshot("").counters
	check(packet.profile.decoded==0 and packet.profile.get("source_sha_reads",0)==0 and counters.get("paint.texture.runtime_image_lookup",0)==0 and counters.get("paint.texture.upload_bytes",0)==0,"load and publication perform no source decode/hash or duplicate Image upload")
	# Verification only, after publication counters: this API intentionally reads
	# the full native file and must never be used by the runtime handoff itself.
	check(material.albedo_texture.get_image().get_data()==image.get_data() and material.normal_texture.get_image().get_data()==normal.get_data(),"published color and flipped normal preserve every mip byte")
	await cancel_native(plan)
	var weak:WeakRef=weakref(material.albedo_texture)
	material=null;owners.clear();state.clear();scope.clear();packet.clear();followed.clear();waiting.clear();clear_render()
	pool.release("producer");pool.admission.release("producer")
	check(alive(weak),"remaining native consumer retains the shared resource")
	pool.release("follower");pool.admission.release("follower")
	check(not alive(weak) and pool.admission.reserved_bytes==0,"final native consumer releases all project owners and leases")
	var streaming:=Engine.get_singleton("TextureStreaming");var deadline:=Time.get_ticks_msec()+8000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	check(int(streaming.call("get_memory_budget_bytes_used"))==0,"native streaming ledger drains after queued release")
	check(FileAccess.get_sha256(path)==source_sha,"source input unchanged")
	files.free();OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	var report:={"checks":passed+failed,"failures":failed,"shared":pool.snapshot(),"counters":counters,"scope":"shared producer and publication contract; no whole-map performance claim"}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	quit(1 if failed else 0)

func cancel_native(plan:Dictionary)->void:
	var key:String=plan.rows.keys()[0];var one:Dictionary=plan.duplicate();one.rows={key:plan.rows[key]}
	var pool:=NativeHeldPool.new();pool.admission=Admission.new()
	admit(pool,"old",one);admit(pool,"waiting",one);pool.admission.park("waiting")
	var digest:String=plan.rows[key].path.sha256_text()
	var worker:=Thread.new();worker.start(pool.load_stream.bind("old",key,digest,plan.rows[key]))
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.is_held() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.is_held() and not pool.ready("waiting"),"held native load is unavailable to followers")
	check(not pool.load_stream("old",key,digest,plan.rows[key]),"duplicate claim starts no second native load")
	pool.cancel("old");var charged:int=pool.admission.reserved_bytes
	admit(pool,"replacement",one)
	var replacement:=Thread.new();replacement.start(pool.load_stream.bind("replacement",key,digest,plan.rows[key]))
	while replacement.is_alive():await process_frame
	check(replacement.wait_to_finish() and pool.ready("waiting"),"replacement native producer finishes while old producer is held")
	var texture:Texture2D=pool.textures("replacement")[key]
	check(pool.admission.reserved_bytes>=charged,"old in-flight workspace stays charged during takeover")
	pool.gate.post()
	while worker.is_alive():await process_frame
	check(not worker.wait_to_finish() and pool.textures("waiting")[key]==texture,"late native result cannot replace accepted owner")
	check(pool.snapshot().streamed_loads==2 and pool.snapshot().discarded_uploads==1 and pool.snapshot().produced==1,"cancelled attempt and replacement are the only native loads")
	texture=null
	for consumer:String in ["old","replacement","waiting"]:pool.release(consumer);pool.admission.release(consumer)
	check(pool.admission.reserved_bytes==0,"native takeover retires all reservations")
