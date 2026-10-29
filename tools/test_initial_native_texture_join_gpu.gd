extends "res://tools/test_model_texture_preparation_gpu.gd"
## Actual ModelParse.run, native ResourceLoader and streamed pool. Reuses only
## the fixture/camera/pixel-comparison helpers from the standalone product test.
const ModelPreparation=preload("res://scripts/world3d/model_parse_preparation.gd")
const Compiled=preload("res://scripts/world3d/compiled_asset_cache.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Ready=preload("res://scripts/world3d/model_texture_readiness.gd")
var candidates:Dictionary={}
func candidate_for(path:String)->Dictionary:return candidates.get(path,{})
func fixture()->Node3D:
	if "--small-native-fixture" in OS.get_cmdline_user_args():return super()
	var scene:=super();var enlarged:Dictionary={}
	for node:MeshInstance3D in scene.get_children():
		var material:StandardMaterial3D=node.material_override
		if material==null:material=node.get_surface_override_material(0)
		if material==null:material=node.mesh.surface_get_material(0)
		for slot:String in ["albedo_texture","normal_texture","detail_normal","bent_normal_texture","roughness_texture","ao_texture"]:
			var old:Texture2D=material.get(slot);var id:=old.get_instance_id()
			if not enlarged.has(id):
				var pixels:=old.get_image();var side:=256 if pixels.get_format()==Image.FORMAT_RGB8 else 128
				pixels.resize(side,side,Image.INTERPOLATE_NEAREST);pixels.generate_mipmaps();enlarged[id]=ImageTexture.create_from_image(pixels)
			material.set(slot,enlarged[id])
	return scene
func run()->void:
	if DisplayServer.get_name()=="headless" or not Prep.Streamed.enabled():quit(2);return
	folder=Prep.Paths.external_root().path_join("initial_native_gpu_%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	create_timer(100).timeout.connect(func():quit(2))
	Prep.Pixels.Policy.verify_packages=false;Prep.Pixels.profile_enabled=true
	var original:=fixture();var prepared:=Products.prepare(original,folder)
	check(prepared.ok and prepared.stats.textures==2,"private source publishes two native products for eighteen slots")
	var packed:=PackedScene.new();check(packed.pack(original)==OK,"pack image-free native geometry")
	var native_dir:=Compiled.directory(folder);DirAccess.make_dir_recursive_absolute(native_dir)
	var staging:=native_dir.path_join("initial-staging.scn")
	check(ResourceSaver.save(packed,staging,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save private native geometry")
	Products.restore(prepared);packed=null
	var payload_sha:=FileAccess.get_sha256(staging);var product:=native_dir.path_join(payload_sha+".scn")
	check(DirAccess.rename_absolute(staging,product)==OK,"publish immutable native geometry without import sources")
	var native_file:=FileAccess.open(product,FileAccess.READ);var bytes:=native_file.get_length();native_file.close()
	var first:=folder.path_join("first.glb");var second:=folder.path_join("second.glb")
	for path:String in [first,second]:candidates[path]={"source_path":path,"source_sha":"a".repeat(64),"payload_sha":payload_sha,"product":product,"bytes":bytes,"generator":Compiled.generator(),"estimated_bytes":4*1024*1024,"exclusive":false,"texture_table":prepared.texture_table}
	check(not FileAccess.file_exists(first) and not FileAccess.file_exists(second),"logical model IDs have no GLB files to fall back to")
	var prep:=ModelPreparation.new();prep.candidate_provider=candidate_for;prep.require_native_products=true
	prep.memory_estimator=func(_path:String)->Dictionary:return {"estimated_bytes":4*1024*1024,"exclusive":false}
	Prep.Pixels.reset_profile()
	var worker:=Thread.new();check(worker.start(prep.run.bind([first,second,first],Callable(),2,Callable(),folder))==OK,"actual initial coordinator starts off main")
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish();report.initial=result.get("native_texture_profile",{});report.error=result.get("error_message","")
	check(result.error==OK and result.entries.size()==2,"actual native initial batch joins two unique models")
	if result.error!=OK:Drainer.dispose_result(result);original.free();prepared.clear();finish();return
	check(result.native_texture_profile.geometry_jobs==2 and result.native_texture_profile.unique_products==2,"duplicate model ID and material texture roles add no duplicate work")
	check(result.native_texture_profile.pool.streamed_loads==2 and result.native_texture_profile.pool.uploads==0,"one streamed load per unique product and no ImageTexture upload")
	check(result.native_texture_profile.worker_slots_peak<=2 and result.threads_started==result.threads_joined,"geometry pixels and binding share the worker cap and join all workers")
	check(result.inflight_reserved_at_return==0 and result.inflight_jobs_at_return==0,"complete models hand texture accounting out of the production queue")
	check(result.native_texture_profile.pool.handoff_outputs==2,"shared native residency transfers each product once")
	for entry:Dictionary in result.entries:check(Ready.packed_ready(entry.packed),"actual PackedScene is bound before initial publication")
	var streaming:=Engine.get_singleton("TextureStreaming");report.engine_budget_on_join=int(streaming.call("get_memory_budget_bytes_used"))
	var source:=viewport(original);var instance:=Compiled.instantiate(result.entries[0].packed)
	check(instance!=null and Ready.scene_ready(instance),"public instantiation accepts the completed runtime proof")
	var target:=viewport(instance);var difference:=-1;var visible_pixels:=0
	for frame:int in 180:
		await process_frame;await RenderingServer.frame_post_draw
		if frame<12 or frame%6!=0:continue
		var a:=source.get_texture().get_image().get_data();var b:=target.get_texture().get_image().get_data();difference=0;visible_pixels=0
		for byte:int in a.size():difference+=int(a[byte]!=b[byte])
		for byte:int in range(0,a.size(),4):
			if a[byte]!=a[0] or a[byte+1]!=a[1] or a[byte+2]!=a[2]:visible_pixels+=1
		if difference==0 and visible_pixels>1000:break
	check(difference==0 and visible_pixels>1000,"actual initial publication renders identical source pixels")
	report.engine_budget_before_release=int(streaming.call("get_memory_budget_bytes_used"))
	if "--flush-native-probe" in OS.get_cmdline_user_args():
		streaming.call("flush_texture_streaming")
		await streaming.flush_completed
		report.engine_budget_after_explicit_flush=int(streaming.call("get_memory_budget_bytes_used"))
	check(report.engine_budget_before_release>0,"engine accounts actual rendered native residency after transient handoff")
	report.render_mismatched_bytes=difference;report.render_visible_pixels=visible_pixels
	var before:=source.get_texture().get_image();var after:=target.get_texture().get_image()
	before.save_png(folder.path_join("source.png"));after.save_png(folder.path_join("initial.png"))
	before.save_webp(folder.path_join("source.webp"),true,.9);after.save_webp(folder.path_join("initial.webp"),true,.9)
	report.screenshot_encoding={"lossy":true,"quality":.9,"dimensions":[384,192]}
	source.free();target.free();original=null;instance=null;prepared.clear();candidates.clear()
	Drainer.dispose_result(result);result.clear();prep=null
	var deadline:=Time.get_ticks_msec()+8000
	while int(streaming.call("get_memory_budget_bytes_used"))!=0 and Time.get_ticks_msec()<deadline:await process_frame
	report.engine_budget_after_release=int(streaming.call("get_memory_budget_bytes_used"))
	check(report.engine_budget_after_release==0,"main disposal retires operation pool and final material owners")
	finish()
