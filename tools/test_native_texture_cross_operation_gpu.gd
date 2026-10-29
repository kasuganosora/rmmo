extends "res://tools/test_initial_native_texture_join_gpu.gd"
const DeferredFixture=preload("res://tools/test_deferred_native_texture_join_gpu.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
func native_owners(packed:PackedScene,plan:Dictionary)->Dictionary:
	var state:=Binding.begin(packed,plan["keys"],plan.table_sha);var result:Dictionary={}
	for row:Dictionary in state.bindings:
		for at:int in row.slots.size():
			var texture:Texture2D=row.material.get(row.slots[at])
			result[row.targets[at]]={"id":texture.get_instance_id(),"rid":texture.get_rid().get_id(),"weak":weakref(texture)}
	Binding.release(state);return result
func remember_initial(scope:RefCounted)->void:
	var loader:=Loader.new();loader._native_texture_scope=scope
	if loader.has_method("_publish_initial_native_textures"):loader.call("_publish_initial_native_textures")
	loader._native_texture_scope=null;loader.free()
func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root().path_join("cross_operation_native_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	create_timer(100).timeout.connect(func():quit(2))
	Paint.refresh_sources();Prep.Pixels.Policy.verify_packages=false;Prep.Pixels.profile_enabled=true
	var original:=fixture();original.get_child(1).material_override.resource_local_to_scene=true
	var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==2,"private fixture splits two texture products")
	var packed:=PackedScene.new();check(packed.pack(original)==OK,"pack image-free geometry")
	var directory:=Compiled.directory(folder);DirAccess.make_dir_recursive_absolute(directory);var staging:=directory.path_join("cross-staging.scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save private split-native geometry")
	Products.restore(prepared);packed=null
	var sha:=FileAccess.get_sha256(staging);var product:=directory.path_join(sha+".scn");DirAccess.rename_absolute(staging,product)
	var file:=FileAccess.open(product,FileAccess.READ);var bytes:=file.get_length();file.close()
	var a:=folder.path_join("initial.glb");var b:=folder.path_join("deferred.glb")
	for path:String in [a,b]:candidates[path]={"source_path":path,"source_sha":"a".repeat(64),"payload_sha":sha,"product":product,"bytes":bytes,"generator":Compiled.generator(),"estimated_bytes":4*1024*1024,"exclusive":false,"texture_table":prepared.texture_table,"direct_template_reuse_safe":false}
	var prep:=ModelPreparation.new();prep.candidate_provider=candidate_for;prep.require_native_products=true
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4*1024*1024,"exclusive":false}
	var worker:=Thread.new();worker.start(prep.run.bind([a],Callable(),2,Callable(),folder))
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();check(result.error==OK,"actual initial geometry and textures complete");report.initial=result.get("native_texture_profile",{})
	if result.error!=OK:Drainer.dispose_result(result);original.free();prepared.clear();finish();return
	check(Assets.cache_packed(a,result.entries[0].packed,candidates[a].source_sha),"initial cache accepts the completed native model")
	var plan:=Binding.candidate_plan(candidates[a],folder,{});var owners:=native_owners(Assets._scenes[a],plan)
	remember_initial(result.native_texture_scope)
	Drainer.dispose_result(result);result={};prep=null
	var weak_hits:=0
	for key:String in owners:
		if Paint.retained_texture(key)!=null and Paint.retained_texture(key).get_instance_id()==owners[key].id:weak_hits+=1
	check(weak_hits==2,"initial scope is gone but its cached model remains weakly discoverable")
	var queue:=DeferredFixture.Queue.new();queue.require_native_products=true;queue.loading_worker_limit=2;queue._reference_root=folder;queue.candidates={b:candidates[b]}
	var box:=AABB(Vector3.ZERO,Vector3.ONE)
	queue.pending.append({"record":{"uuid":"cross_native","collision":"none"},"path":b,"bounds":box,"digest":candidates[b].source_sha,"memory":{"estimated_bytes":4*1024*1024,"exclusive":false,"known":true}})
	check(queue.begin_entry_prefetch(self,box.grow(1),{}),"new Deferred operation starts after initial scope retirement")
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch()
		if queue._jobs.has(b):
			var job:Dictionary=queue._jobs[b]
			if not job.has("worker") and job.has("result") and not job.get("native_binding_pending",true):break
		if not queue.error.is_empty() or not queue.path_errors.is_empty():break
		await process_frame
	var job:Dictionary=queue._jobs.get(b,{});var packet:Dictionary=job.get("result",{});report.deferred_pool=queue._shared_images.snapshot();report.deferred_error=queue.error
	check(is_instance_valid(packet.get("scene")) and not job.get("native_binding_pending",true),"new model completes real private-scene binding")
	if not is_instance_valid(packet.get("scene")):await queue.quiesce();queue.shutdown();queue.free();Assets.evict_cached_scene(a);original.free();finish();return
	check(report.deferred_pool.get("streamed_loads",0)==0 and report.deferred_pool.produced==0,"second operation creates and loads zero extra StreamedTexture2D objects")
	var same:=0
	for key:String in owners:
		var texture:Texture2D=packet.prefab_texture_packet.uploaded_textures.get(key)
		if texture!=null and texture.get_instance_id()==owners[key].id and texture.get_rid().get_id()==owners[key].rid:same+=1
	check(same==2,"second model binds exactly the first texture instances and RIDs")
	report.pixel_profile=packet.prefab_texture_packet.get("profile",{})
	check(report.pixel_profile.get("source_sha_reads",0)==0 and report.pixel_profile.get("source_sha_bytes",0)==0,"resident preparation never rehashes source files")
	check(Assets.cache_scene(b,packet.scene,candidates[b].source_sha),"cache the second real model");packet.erase("scene")
	Paint._texture_refs.clear()
	if queue.has_method("_publish_native_texture_owners"):queue.call("_publish_native_texture_owners",b,job)
	weak_hits=0
	for key:String in owners:
		if Paint.retained_texture(key)!=null and Paint.retained_texture(key).get_instance_id()==owners[key].id:weak_hits+=1
	check(weak_hits==2,"Deferred cache publication preserves the shared weak identity")
	var source:=viewport(original);var target:=viewport(Assets._instantiate(Assets._scenes[b]))
	Assets.evict_cached_scene(a);await queue.quiesce();queue.shutdown();queue.free();queue=null;packet={};job={};candidates.clear();prepared.clear()
	var different:=-1;var visible:=0
	for frame:int in 180:
		await process_frame;await RenderingServer.frame_post_draw
		if frame<12 or frame%6!=0:continue
		var one:=source.get_texture().get_image().get_data();var two:=target.get_texture().get_image().get_data();different=0;visible=0
		for at:int in one.size():different+=int(one[at]!=two[at])
		for at:int in range(0,one.size(),4):
			if one[at]!=one[0] or one[at+1]!=one[1] or one[at+2]!=one[2]:visible+=1
		if different==0 and visible>1000:break
	check(different==0 and visible>1000,"second model renders exact source pixels after initial cache eviction")
	report.render_mismatched_bytes=different;report.render_visible_pixels=visible
	var streaming:=Engine.get_singleton("TextureStreaming");report.engine_before_release=int(streaming.call("get_memory_budget_bytes_used"))
	check(report.engine_before_release>0,"remaining real scene owns engine-accounted native residency")
	var pixels:=target.get_texture().get_image();pixels.save_png(folder.path_join("cross.png"));pixels.save_webp(folder.path_join("cross.webp"),true,.9)
	report.screenshot_encoding={"lossy":true,"quality":.9,"dimensions":[384,192]}
	source.free();target.free();original=null;Assets.evict_cached_scene(b)
	deadline=Time.get_ticks_msec()+8000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	report.engine_after_release=int(streaming.call("get_memory_budget_bytes_used"));check(report.engine_after_release==0,"final cache and scene release remove all engine-native charges")
	var alive:=0
	for item:Dictionary in owners.values():
		if item.weak.get_ref()!=null:alive+=1
	check(alive==0 and Paint._textures.is_empty(),"weak sharing leaves no texture or strong hot-cache owner")
	finish()
