extends "res://tools/test_initial_native_texture_join_gpu.gd"
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Assets=preload("res://scripts/world_editor/asset_library.gd")
class Queue extends Deferred:
	var candidates:Dictionary={}
	var extra_plan:Dictionary={}
	func _candidate_for_job(path:String,_root:String,_digest:String)->Dictionary:return candidates[path]
	func _prefab_texture_plan(_item:Dictionary,_requests:Array)->Dictionary:return extra_plan
func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root().path_join("deferred_native_gpu_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	create_timer(100).timeout.connect(func():quit(2))
	Prep.Pixels.Policy.verify_packages=false;Prep.Pixels.profile_enabled=true
	var original:=fixture();original.get_child(1).material_override.resource_local_to_scene=true
	var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==2,"publish private split-native products with a local-to-scene material")
	var packed:=PackedScene.new();check(packed.pack(original)==OK,"pack native private fixture")
	var directory:=Compiled.directory(folder);DirAccess.make_dir_recursive_absolute(directory)
	var staging:=directory.path_join("deferred-staging.scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save image-free native geometry")
	Products.restore(prepared);packed=null
	var sha:=FileAccess.get_sha256(staging);var product:=directory.path_join(sha+".scn")
	check(DirAccess.rename_absolute(staging,product)==OK,"publish content-addressed native geometry")
	var file:=FileAccess.open(product,FileAccess.READ);var bytes:=file.get_length();file.close()
	var paths:Array[String]=[folder.path_join("first.glb"),folder.path_join("second.glb")]
	var queue:=Queue.new();queue.require_native_products=true;queue.loading_worker_limit=2;queue._reference_root=folder
	var box:=AABB(Vector3.ZERO,Vector3.ONE)
	for i:int in paths.size():
		var candidate:={"source_path":paths[i],"source_sha":"b".repeat(64),"payload_sha":sha,"product":product,"bytes":bytes,"generator":Compiled.generator(),"estimated_bytes":4*1024*1024,"exclusive":false,"texture_table":prepared.texture_table,"direct_template_reuse_safe":false}
		queue.candidates[paths[i]]=candidate
		queue.pending.append({"record":{"uuid":"native_%d"%i,"collision":"none"},"path":paths[i],"bounds":box,"digest":candidate.source_sha,"memory":{"estimated_bytes":candidate.estimated_bytes,"exclusive":false,"known":true}})
	# A normal image shares this transaction to prove subset handoff cannot erase
	# the ordinary retained charge. It is an explicit private test dependency.
	var ordinary:=Image.create(9,7,false,Image.FORMAT_RGB8);ordinary.fill(Color(.3,.5,.7));var ordinary_path:=folder.path_join("ordinary.png");ordinary.save_png(ordinary_path)
	var ordinary_key:=Binding.Paint.texture_key(ordinary_path)
	queue.extra_plan=Prep.estimate({ordinary_key:[ordinary_path,false,false]},folder)
	check(queue.extra_plan.rows.size()==1 and queue.extra_plan.rows[ordinary_key].extension=="png","mixed fixture retains one ordinary CPU image path")
	check(queue.begin_entry_prefetch(self,box.grow(1),{}),"actual deferred queue begins with one shared admission ledger")
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		queue.pump_entry_prefetch()
		if _complete(queue) or not queue.path_errors.is_empty() or not queue.instance_errors.is_empty() or not queue.error.is_empty():break
		await process_frame
	check(_complete(queue),"actual native geometry pixels and private binding all complete")
	report.path_errors=queue.path_errors.duplicate();report.instance_errors=queue.instance_errors.duplicate();report.error=queue.error
	report.pool=queue._shared_images.snapshot();report.admission=queue._admission.snapshot();report.metadata=queue._texture_plan_catalog.snapshot();report.binding=queue.profile.get("native_model_binding",{})
	if not _complete(queue):await queue.quiesce();queue.shutdown();queue.free();original.free();prepared.clear();finish();return
	check(report.pool.streamed_loads==2 and report.pool.produced==3,"two native products and one ordinary image are produced once across both models")
	check(report.pool.handoff_outputs==2 and report.pool.retained_bytes==int(queue.extra_plan.output_bytes)*2,"native subset transfers while ordinary CPU output stays fully charged")
	check(report.metadata.native_async_reads==1 and report.metadata.native_consumers==2,"one table read supports independent metadata pins")
	check(report.admission.peak_workers<=2 and report.binding.jobs==2,"native binding continuations respect the common worker cap")
	for path:String in paths:
		var job:Dictionary=queue._jobs[path];var scene:Node3D=job.result.scene
		var material:StandardMaterial3D=scene.get_child(1).material_override
		check(Ready.scene_ready(scene) and material.albedo_texture.is_class("StreamedTexture2D"),"actual private local-to-scene material has native pixels before cache publication")
		check(Assets.cache_scene(path,scene,job.result.source_digest),"existing cache publication accepts the completed private scene")
		job.result.erase("scene")
	var source:=viewport(original);var target:=viewport(Assets._instantiate(Assets._scenes[paths[0]]))
	var repeated:=Assets._instantiate(Assets._scenes[paths[0]])
	check(Ready.scene_ready(repeated),"repeated cached instance preserves completed texture proof");repeated.free();repeated=null
	var different:=-1;var visible:=0
	for frame:int in 180:
		await process_frame;await RenderingServer.frame_post_draw
		if frame<12 or frame%6!=0:continue
		var a:=source.get_texture().get_image().get_data();var b:=target.get_texture().get_image().get_data();different=0;visible=0
		for at:int in a.size():different+=int(a[at]!=b[at])
		for at:int in range(0,a.size(),4):
			if a[at]!=a[0] or a[at+1]!=a[1] or a[at+2]!=a[2]:visible+=1
		if different==0 and visible>1000:break
	check(different==0 and visible>1000,"deferred publication preserves source pixels on the real renderer")
	report.render_mismatched_bytes=different;report.render_visible_pixels=visible
	var streaming:=Engine.get_singleton("TextureStreaming");report.engine_budget_before_release=int(streaming.call("get_memory_budget_bytes_used"))
	check(report.engine_budget_before_release>0,"actual native residency remains in the engine budget after handoff")
	var before:=source.get_texture().get_image();var after:=target.get_texture().get_image()
	before.save_png(folder.path_join("source.png"));after.save_png(folder.path_join("deferred.png"));before.save_webp(folder.path_join("source.webp"),true,.9);after.save_webp(folder.path_join("deferred.webp"),true,.9)
	report.screenshot_encoding={"lossy":true,"quality":.9,"dimensions":[384,192]}
	source.free();target.free();original=null;prepared.clear()
	await queue.quiesce();queue.shutdown();queue.free();queue=null
	for path:String in paths:Assets.evict_cached_scene(path)
	deadline=Time.get_ticks_msec()+8000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	report.engine_budget_after_release=int(streaming.call("get_memory_budget_bytes_used"))
	check(report.engine_budget_after_release==0,"unload retires last native owner and its actual engine charge")
	finish()
func _complete(queue:Queue)->bool:
	if queue._jobs.size()!=2:return false
	for job:Dictionary in queue._jobs.values():
		if job.has("worker") or not job.has("result") or job.get("native_binding_pending",false) or job.result.get("waiting_pixels",false) or not str(job.result.get("error","missing")).is_empty():return false
	return true
