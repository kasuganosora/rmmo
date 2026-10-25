extends SceneTree
## Independent source-refresh and post-warmup work regressions for d1121df.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Save=preload("res://scripts/world3d/pose_save.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Admission=preload("res://scripts/world3d/resource_admission.gd")
const CpuService=preload("res://scripts/world3d/cross_map_prefetch.gd")
const GpuService=preload("res://scripts/world3d/target_scene_prefetch.gd")
const Errors=preload("res://tools/test_prefab_texture_preparation.gd").Errors
var checks:=0
var failures:=0
var folder:=""
var receipt:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func write_image(path:String,color:Color)->void:
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8);image.fill(color)
	check(image.save_png(path)==OK,"write isolated paint source")
func pixels(texture:Texture2D)->String:
	var image:=texture.get_image()
	return image.get_data().hex_encode() if image!=null else ""
func source_refresh()->void:
	# This test deliberately edits bytes behind the package/importer contract.
	# SHA assertions belong to the diagnostic reader; production stays trusted.
	var policy=preload("res://scripts/world3d/runtime_package_policy.gd")
	var previous_verification:bool=policy.verify_packages;policy.verify_packages=true
	var path:=folder.path_join("paint.png")
	var normal_path:=folder.path_join("normal.png")
	write_image(path,Color.RED);write_image(normal_path,Color(.5,.25,1))
	var definition:={"name":"blind_source","color":[1.,1.,1.,1.],"roughness":.7,"tile_size":[2.,2.],"texture_path":path,"normal_path":normal_path,"normal_format":"directx"}
	var live:=Paint.make_material(definition)
	var original_pixels:=pixels(live.albedo_texture);var original_normal:=pixels(live.normal_texture)
	var original_sha:=FileAccess.get_sha256(path)
	check(live.albedo_texture.get_meta("runtime_source_sha256","")==original_sha,"initial live material carries original complete source identity")
	# Model an editor/live map still owning the old material while export refreshes.
	write_image(path,Color.BLUE);write_image(normal_path,Color(.75,.6,1))
	var latest_sha:=FileAccess.get_sha256(path)
	var document:=Doc.new();Save.refresh_export_sources(document)
	var refreshed:=Paint.make_material(definition)
	var refreshed_pixels:=pixels(refreshed.albedo_texture)
	receipt.refresh={"same_material":refreshed==live,"same_texture":refreshed.albedo_texture==live.albedo_texture,"original_sha":original_sha,"disk_sha":latest_sha,"refreshed_sha":refreshed.albedo_texture.get_meta("runtime_source_sha256","")}
	check(refreshed!=live and refreshed.albedo_texture!=live.albedo_texture,"export refresh rejects weak aliases to the previous material and texture")
	check(refreshed.albedo_texture.get_meta("runtime_source_sha256","")==latest_sha,"refreshed texture identity matches current disk bytes")
	check(refreshed_pixels!=original_pixels,"same-path image replacement changes exported material pixels")
	check(pixels(refreshed.normal_texture)!=original_normal and refreshed.normal_texture.get_meta("runtime_source_sha256","")==FileAccess.get_sha256(normal_path),"source refresh also replaces flipped DirectX normal-map aliases")
	check(pixels(live.albedo_texture)==original_pixels and pixels(live.normal_texture)==original_normal,"old live consumer remains immutable across source refresh")
	var old_texture:WeakRef=weakref(live.albedo_texture);live=null
	Paint.trim_cached_resources()
	check(old_texture.get_ref()==null,"retired source is released after its independent live consumer ends")
	policy.verify_packages=previous_verification
func admission_policy()->void:
	var too_small:=Admission.new();too_small.byte_limit=64
	var cancel:=func():pass
	var granted:=too_small.reserve_background("speculative",128,cancel)
	check(not granted and too_small.reserved_bytes==0,"speculative reservation declines an envelope larger than its byte budget")
	too_small.release("speculative")
	check(too_small.reserve("required",{"estimated_bytes":128,"exclusive":true}),"required oversize foreground work retains its exclusive escape path")
	too_small.release("required")
	var ledger:=Admission.new();ledger.byte_limit=1024
	var probe:={"cancelled":0}
	check(ledger.reserve_background("cpu",512,func():probe.cancelled+=1) and ledger.park("cpu"),"park actual background reservation without releasing retained bytes")
	check(not ledger.reserve_background("gpu",1024,cancel,2),"larger speculative upgrade waits for enough unreserved capacity")
	check(probe.cancelled==0 and ledger.reserved_bytes==512,"denied background upgrade preserves the useful existing background result")
	check(not ledger.reserve("critical",{"estimated_bytes":1024,"exclusive":true}) and probe.cancelled==1 and ledger.reserved_bytes==512,"foreground preemption still cancels background without prematurely releasing its lease")
	ledger.release("cpu")
	receipt.admission={"oversize_background_granted":granted,"foreground_cancel_calls":probe.cancelled,"final_reserved_bytes":ledger.reserved_bytes}
func wait_cpu(service:Node)->bool:
	var deadline:=Time.get_ticks_msec()+30000
	while service._packet==null and Time.get_ticks_msec()<deadline:await process_frame
	return service._packet!=null
func wait_gpu(service:Node)->bool:
	var deadline:=Time.get_ticks_msec()+60000
	while not service._gpu_ready and Time.get_ticks_msec()<deadline:
		service._touched=Time.get_ticks_msec();await process_frame
	return service._gpu_ready
func gpu_idle()->void:
	var document:=Doc.new()
	document.add_box("ground",Vector3(0,-.25,0),Vector3(32,.5,32))
	for i in 12:document.add_box("block",Vector3((i%4)*2-3,1,(i/4)*2-3),Vector3(1.5,2,1.5))
	var path:=folder.path_join("target.gltf");check(document.save(path)==OK,"save isolated real target map")
	var source_sha:=FileAccess.get_sha256(path);var at:=Vector3(0,.9,0)
	var ledger:=Admission.new();ledger.byte_limit=GpuService.LEASE_BYTES*2
	var cpu:=CpuService.new();root.add_child(cpu)
	var gpu:=GpuService.new();root.add_child(gpu)
	check(cpu.request(path,at,ledger) and await wait_cpu(cpu),"real CPU preparation verifies target closure")
	check(gpu.request(path,at,ledger,cpu) and await wait_gpu(gpu),"real private GPU loader finishes draw warmup and verification")
	var modes:Array=[];var draws:Array=[];var total_draws:Array=[]
	for i in 8:
		await RenderingServer.frame_post_draw
		modes.append(gpu._viewport.render_target_update_mode if is_instance_valid(gpu._viewport) else SubViewport.UPDATE_DISABLED)
		draws.append(gpu._viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) if is_instance_valid(gpu._viewport) else 0)
		total_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	receipt.warmup={"ready_modes":modes,"last_viewport_draws":draws,"total_frame_draws":total_draws,"warmed_meshes":gpu._warm.size(),"parked_bytes":ledger.reserved_bytes}
	check(modes.all(func(mode):return mode==SubViewport.UPDATE_DISABLED),"completed speculative warmup no longer schedules a viewport draw every frame")
	check(total_draws.all(func(count):return count==0),"parked target contributes zero 3D draw calls across subsequent idle frames")
	check(gpu._gpu_ready and ledger.reserved_bytes==GpuService.LEASE_BYTES,"idle warm target keeps verified resources and its full parked byte lease")
	var owners:Array=[]
	for mesh:Mesh in gpu._warm:owners.append(weakref(mesh))
	var scene:Node=gpu.take(path,at)
	check(scene!=null and scene.get_meta("gpu_preload_hit",false),"quiescent GPU target remains consumable by confirmed transfer")
	check(ledger.reserved_bytes==0 and owners.all(func(ref):return ref.get_ref()!=null),"take transfers warmed resource owners before releasing admission")
	if scene!=null:preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(scene)
	scene=null
	for i in 4:await process_frame
	check(owners.all(func(ref):return ref.get_ref()==null),"last consumed target owner releases warmed GPU buffers")
	check(FileAccess.get_sha256(path)==source_sha,"preload lifecycle preserves authored target bytes")
	# A 1 GiB source ledger fits CPU preparation, but cannot also retain the
	# 1 GiB GPU upgrade. Repeated approach polling should reuse its ready CPU work.
	ledger.byte_limit=GpuService.LEASE_BYTES
	var starts:int=cpu.profile.started
	var denied:=0
	for attempt in 3:
		check(cpu.request(path,at,ledger) and await wait_cpu(cpu),"low-capacity approach obtains a verified CPU target")
		if not gpu.request(path,at,ledger,cpu):denied+=1
		for i in 3:await process_frame
	var work:int=cpu.profile.started-starts
	receipt.scarce_budget={"gpu_upgrades_denied":denied,"cpu_worker_starts":work,"cpu_result_retained":cpu._packet!=null,"reserved_bytes":ledger.reserved_bytes}
	check(denied==3 and work==1 and cpu._packet!=null,"repeated denied GPU upgrades reuse one completed CPU preparation")
	await cpu.drain();await gpu.drain()
	check(ledger.reserved_bytes==0,"scarce-budget cancellation releases all parked preparation owners")
	gpu.free();cpu.free()
func run()->void:
	create_timer(150).timeout.connect(func():quit(2))
	var logger:=Errors.new();OS.add_logger(logger)
	folder=Paths.cache_directory("blind_latest_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(folder)
	source_refresh()
	admission_policy()
	if not OS.get_cmdline_user_args().has("--material-only"):await gpu_idle()
	OS.remove_logger(logger);check(logger.errors.is_empty(),"no unexpected engine or script errors")
	for error:String in logger.errors:print("ENGINE_ERROR ",error)
	receipt.checks=checks;receipt.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file:=FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("LATEST_RUNTIME_REVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
