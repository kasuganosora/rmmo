extends SceneTree
## Read-only reproduction of an actual native model's runtime template packing.
const Assets=preload("res://scripts/world_editor/asset_library.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Drainer=preload("res://scripts/world3d/asset_worker_drainer.gd")
const Trace=preload("res://scripts/world3d/load_trace.gd")
const MODEL="D:/code/rmmo_runtime/packs/default/assets/2abd3fe0f222d1e7cf69fa26eb5a6f05e21aca2cf041beb7301bd1847bd16c15.glb"
var output:=""
var failures:Array=[]
var frames:Array=[]
var last:=0
var phase:="prepare"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func observe()->void:
	var now:=Time.get_ticks_usec()
	if last>0:frames.append({"at_us":now,"us":now-last,"phase":phase})
	last=now
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size=Vector2i(512,512)
	var candidate:=Assets.native_candidate(MODEL,"D:/code/rmmo_runtime")
	check(not candidate.is_empty(),"published native product exists independently of logical GLB key")
	if candidate.is_empty():quit(1);return
	var report:Dictionary={"candidate":candidate,"engine":Engine.get_version_info(),"failures":failures}
	var worker:=Thread.new();var began:=Time.get_ticks_usec()
	Trace.minimum_event_us=0;Trace.start();process_frame.connect(observe)
	check(worker.start(Deferred._prepare_fixed_scene.bind(MODEL,candidate.source_sha,null,{},false,"D:/code/rmmo_runtime",candidate,Deferred.CollisionGeometry.ALL,true,false))==OK,"existing native preparation runs on private worker")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	report.prepare_us=Time.get_ticks_usec()-began
	check(packet.get("error","missing")=="" and is_instance_valid(packet.get("scene")),"actual native preparation succeeds")
	if not packet.get("error","").is_empty() or not is_instance_valid(packet.get("scene")):Drainer.dispose_result(packet);quit(1);return
	var scene:Node=packet.scene
	report.nodes=scene.find_children("*","",true,false).size()+1
	report.scene_name=scene.name;report.scene_meta=scene.get_meta_list()
	if "--gdb-wait" in OS.get_cmdline_user_args():
		FileAccess.open(output.get_base_dir().path_join("phase.log"),FileAccess.WRITE).store_line("NATIVE_PACK_READY")
		var deadline:=Time.get_ticks_msec()+90000
		while not FileAccess.file_exists(output.get_base_dir().path_join("gdb_ready")) and Time.get_ticks_msec()<deadline:await process_frame
		if not FileAccess.file_exists(output.get_base_dir().path_join("gdb_ready")):quit(2);return
	phase="cache";last=Time.get_ticks_usec();began=last
	check(Assets.cache_scene(MODEL,scene,candidate.source_sha),"ordinary cache publication succeeds")
	report.cache_us=Time.get_ticks_usec()-began
	packet.erase("scene");scene=null
	await process_frame
	report.trace=Trace.stop();report.frames=frames
	process_frame.disconnect(observe)
	var packed:PackedScene=Assets._scenes.get(MODEL)
	check(packed!=null and packed.get_state().get_node_count()==report.nodes,"cached template preserves the complete node graph")
	report.packed_nodes=packed.get_state().get_node_count() if packed!=null else 0
	packed=null;Assets.evict_cached_scene(MODEL);Drainer.dispose_result(packet);Drainer.synchronize_transfer()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATIVE_TEMPLATE_PACK ",JSON.stringify({"nodes":report.nodes,"prepare_us":report.prepare_us,"cache_us":report.cache_us,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
