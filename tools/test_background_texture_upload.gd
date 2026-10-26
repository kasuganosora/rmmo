extends "res://tools/test_prefab_texture_preparation.gd"
## GPU contract: shared producer, immutable variants, cancellation takeover,
## zero hot-cache publication, source replacement and final owner retirement.
const Pool=preload("res://scripts/world3d/shared_prefab_images.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
class HeldPool extends Pool:
	var gate:=Semaphore.new()
	var signal_mutex:=Mutex.new()
	var held:=false
	var first:=true
	func _upload(image:Image)->ImageTexture:
		var texture:=super(image)
		signal_mutex.lock();var hold:=first;first=false;held=hold;signal_mutex.unlock()
		if hold:gate.wait()
		return texture
	func is_held()->bool:
		signal_mutex.lock();var value:=held;signal_mutex.unlock();return value
func admit(pool:RefCounted,name_:String,plan:Dictionary)->Dictionary:
	var offer:Dictionary=pool.offer(plan)
	check(pool.admission.reserve_bundle(name_,{"estimated_bytes":offer.scratch_bytes,"exclusive":false},offer.retained),"producer/follower admitted under the existing byte ledger")
	pool.commit(name_,offer)
	return {"pool":pool,"consumer":name_,"leaders":offer.leaders,"cached":offer.cached}
func prepare_shared(requests:Dictionary,plan:Dictionary,shared:Dictionary)->Dictionary:
	var worker:=Thread.new();check(worker.start(Prep.prepare.bind(requests,plan,files.content_root,null,true,shared))==OK,"shared preparation starts on worker")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish();shared.pool.admission.park(shared.consumer)
	packet.uploaded_textures=shared.pool.textures(shared.consumer)
	return packet
func clear_render()->void:
	Prefab._meshes.clear();Prefab._render_meshes.clear();Paint.refresh_sources()
func alive(reference:WeakRef)->bool:
	# Do not leave get_ref()'s strong temporary in this coroutine's VM registers.
	return reference.get_ref()!=null
func cancel_test(plan:Dictionary,image:Image)->void:
	var key:String=plan.rows.keys()[0];var one:Dictionary=plan.duplicate();one.rows={key:plan.rows[key]}
	var pool:=HeldPool.new();pool.admission=Admission.new()
	admit(pool,"old",one);admit(pool,"follower",one)
	pool.admission.park("follower") # This waiting consumer occupies no worker.
	var worker:=Thread.new();worker.start(pool.publish.bind("old",key,image.get_meta("runtime_source_sha256"),image))
	var deadline:=Time.get_ticks_msec()+5000
	while not pool.is_held() and Time.get_ticks_msec()<deadline:await process_frame
	check(pool.is_held() and not pool.ready("follower") and pool.textures("follower").is_empty(),"unfinished GPU upload stays unavailable to followers")
	check(not pool.publish("old",key,image.get_meta("runtime_source_sha256"),image),"duplicate publication cannot start a second upload")
	pool.cancel("old");var charged:int=pool.admission.reserved_bytes
	admit(pool,"new",one)
	var replacement:=Thread.new();replacement.start(pool.publish.bind("new",key,image.get_meta("runtime_source_sha256"),image))
	while replacement.is_alive():await process_frame
	check(replacement.wait_to_finish() and pool.ready("follower"),"replacement completes while cancelled producer remains held")
	var texture:Texture2D=pool.textures("new")[key]
	check(pool.admission.reserved_bytes>=charged,"cancelled in-flight workspace remains charged")
	pool.gate.post()
	while worker.is_alive():await process_frame
	check(not worker.wait_to_finish() and pool.textures("follower")[key]==texture,"late cancelled upload cannot replace new shared result")
	check(pool.snapshot().uploads==2 and pool.snapshot().discarded_uploads==1 and pool.snapshot().produced==1,"only cancelled attempt and its replacement performed GPU work")
	var weak:WeakRef=weakref(texture);texture=null
	for consumer:String in ["old","new","follower"]:pool.release(consumer);pool.admission.release(consumer)
	check(not alive(weak) and pool.admission.reserved_bytes==0,"cancel/takeover releases all GPU owners and reservations")
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if DisplayServer.get_name()=="headless" or output.is_empty() or FileAccess.file_exists(output):quit(2);return
	var logger:=Errors.new();OS.add_logger(logger)
	Pool.background_upload_enabled=true;Pixels.Policy.verify_packages=true
	Paint.texture_profile_enabled=true;Pixels.reset_profile();Paint.cache_byte_budget=0
	files=Files.new();files.content_root=Prep.Paths.external_root();files.folder=Prep.Paths.cache_directory("background_upload_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(files.folder)
	var path:String=files.folder.path_join("pixels.png");files.created.append(path)
	var authored:=Image.create(19,13,false,Image.FORMAT_RGBA8);authored.fill(Color(.1,.3,.7,1));authored.set_pixel(0,0,Color(.2,.8,.4,.5));authored.save_png(path)
	var definition:Dictionary={"name":"upload","color":[1,1,1,1],"roughness":.7,"texture_path":path,"normal_path":path,"normal_format":"directx"}
	var record:=bridge("upload",100,definition);var requested:=Prep.sources(record);var plan:=Prep.estimate(requested,files.content_root)
	var pool:=Pool.new();pool.admission=Admission.new()
	var a:=admit(pool,"a",plan);var b:=admit(pool,"b",plan)
	var waiting:=await prepare_shared(requested,plan,b)
	check(waiting.waiting_pixels and waiting.images.is_empty(),"followers return without blocking a worker")
	var packet:=await prepare_shared(requested,plan,a)
	var follower:=await prepare_shared(requested,plan,b)
	check(packet.error.is_empty() and follower.error.is_empty() and pool.snapshot().uploads==2 and pool.snapshot().produced==2,"two variants upload exactly once for two consumers")
	check(packet.uploaded_textures[path]==follower.uploaded_textures[path] and pool.snapshot().upload_bytes==plan.output_bytes,"same texture owner and exact fixed upload byte count")
	check(Paint._textures.is_empty() and Paint._texture_refs.is_empty(),"worker never installs main-thread render caches")
	var scope:=Prefab.begin_texture_publication(record,null,packet)
	var material:=Paint.make_material(definition);Prefab.end_texture_publication(scope)
	RenderingServer.force_sync()
	check(material.albedo_texture==packet.uploaded_textures[path] and material.normal_texture==packet.uploaded_textures[path+"|normal|flip_y"],"zero hot cache binds the exact worker textures without reupload")
	check(material.albedo_texture.get_image().get_data()==packet.images[path].get_data() and material.normal_texture.get_image().get_data()==packet.images[path+"|normal|flip_y"].get_data(),"real bound GPU pixels preserve alpha, flipped normal and complete mip chains")
	check(Paint.prepared_textures.is_empty() and Paint.prepared_images.is_empty(),"publication restores both temporary scopes")
	check(Prefab.texture_tickets(plan.rows).size()==2,"next admission reuses live weak textures even after hot caches evict them")
	var counters:Dictionary=Pixels.profile_snapshot("paint.").counters
	check(counters.get("paint.texture.background_handoffs",0)==2 and counters.get("paint.texture.upload_bytes",0)==0,"main publication creates no duplicate GPU uploads")
	await cancel_test(plan,packet.images[path])
	# Existing visible material keeps its old pixels while the editor/new load
	# installs a replacement generation with the same path and dimensions.
	Paint.cache_byte_budget=256*1024*1024
	Paint.remember_texture_owner(path,material.albedo_texture)
	authored.fill(Color.RED);authored.save_png(path)
	var changed_pool:=Pool.new();changed_pool.admission=Admission.new()
	var changed_plan:=Prep.estimate(requested,files.content_root)
	var changed:=await prepare_shared(requested,changed_plan,admit(changed_pool,"changed",changed_plan))
	scope=Prefab.begin_texture_publication(record,null,changed)
	var newer:=Paint.make_material(definition);Prefab.end_texture_publication(scope)
	RenderingServer.force_sync()
	check(newer.albedo_texture==changed.uploaded_textures[path] and newer.albedo_texture!=material.albedo_texture,"same-path source edit selects the new uploaded generation")
	check(newer.albedo_texture.get_image().get_data()==changed.images[path].get_data() and material.albedo_texture.get_image().get_data()==packet.images[path].get_data(),"source replacement preserves new and still-visible old pixels")
	var old_ref:WeakRef=weakref(material.albedo_texture);var new_ref:WeakRef=weakref(newer.albedo_texture)
	material=null;newer=null;scope.clear();clear_render();packet.clear();follower.clear();waiting.clear();changed.clear()
	pool.release("a");pool.admission.release("a");check(alive(old_ref),"remaining consumer retains the unique GPU owner")
	pool.release("b");pool.admission.release("b");changed_pool.release("changed");changed_pool.admission.release("changed")
	check(not alive(old_ref) and not alive(new_ref) and pool.admission.reserved_bytes==0 and changed_pool.admission.reserved_bytes==0,"last consumers release image/GPU owners and all bytes")
	for flip:bool in [false,true]:files.created.append(Pixels.cache_path(path,flip))
	for created:String in files.created:
		if FileAccess.file_exists(created):DirAccess.remove_absolute(created)
	DirAccess.remove_absolute(files.folder);files.free()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	var report:={"checks":passed+failed,"failures":failed,"shared":pool.snapshot(),"changed":changed_pool.snapshot()}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("BACKGROUND_TEXTURE_UPLOAD ",JSON.stringify(report));quit(1 if failed else 0)
