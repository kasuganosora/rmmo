extends SceneTree
## Native worker pipeline preparation must preserve first draw and cancellation.
## All generated resources stay in the supplied external review directory.
var failures:Array=[]
var checks:=0
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func draw_frame()->void:
	await process_frame;await RenderingServer.frame_post_draw
func product_owner(packet:Dictionary)->WeakRef:
	return weakref(packet.get("resource"))
func fixture(path:String,standard:bool=false,wrong_root_path:String="")->void:
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, cull_disabled; uniform vec4 tint : source_color; void fragment(){ ALBEDO=tint.rgb; }"
	var mesh:=ArrayMesh.new()
	for side:int in 2:
		var box:=BoxMesh.new();box.size=Vector3(.8,.8,.8)
		var arrays:=box.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for at:int in vertices.size():vertices[at].x+=(-.65 if side==0 else .65)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material:Material
		if standard:
			var base:=StandardMaterial3D.new();base.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			base.albedo_color=Color(.05,.8,.1) if side==0 else Color(.1,.15,.9);material=base
		else:
			var custom:=ShaderMaterial.new();custom.shader=shader
			custom.set_shader_parameter("tint",Color(.05,.8,.1) if side==0 else Color(.1,.15,.9));material=custom
		mesh.surface_set_material(side,material)
	if not wrong_root_path.is_empty():
		var wrong_source:=wrong_root_path.get_basename()+".res"
		check(ResourceSaver.save(mesh,wrong_source,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save valid native mesh resource")
		check(DirAccess.copy_absolute(wrong_source,wrong_root_path)==OK,"copy unchanged native bytes with invalid scene root type")
	var node:=MeshInstance3D.new();node.mesh=mesh
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack two actual material surfaces")
	check(ResourceSaver.save(packed,path,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save native fixture outside project")
	node.free()
static func read(path:String,capture_cpu:bool=true)->Dictionary:
	var began:=Time.get_ticks_usec()
	var method:=&"load_native_scene_with_cpu_surfaces" if capture_cpu else &"load_native_scene_with_pipeline_batch"
	var packet:Dictionary=ClassDB.class_call_static(&"ArrayMesh",method,path)
	packet.worker_us=Time.get_ticks_usec()-began
	return packet
static func pool_read(path:String,shared:Dictionary,capture_cpu:bool=true)->void:
	shared.packet=read(path,capture_cpu)
func check_batch(packet:Dictionary,label:String)->void:
	var expected:=OS.get_environment("RMMO_BATCH_MESH_PIPELINES")=="1"
	var stats:Dictionary=packet.get("pipeline_batch",{})
	check(bool(stats.get("enabled",false))==expected,label+" batch activates only when requested on a private reader")
	if expected:
		check(int(stats.unique_completions)>0,label+" joins actual compilation completions")
		check(int(stats.requests)>int(stats.unique_completions),label+" repeated surfaces share completion waits")
		check(stats.remaining_material_owners==0 and stats.remaining_completions==0,label+" temporary batch owners released before handoff")
	samples.append({"label":label,"worker_us":packet.get("worker_us",0),"pipeline_batch":stats})
func read_worker(path:String,capture_cpu:bool=true)->Dictionary:
	var worker:=Thread.new();check(worker.start(read.bind(path,capture_cpu))==OK,"native reader starts on actual worker")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.get("error",FAILED)==OK and packet.get("resource") is PackedScene,"native worker returns complete resource")
	check_batch(packet,"read")
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	return packet
func ordinary_reader(path:String,directory:String,stage:Node3D)->void:
	# Use the exact production entry used by load_job and editor readers.
	# The source GLB intentionally does not exist, and no CPU consumer is present.
	var folder:=preload("res://scripts/world3d/compiled_asset_cache.gd").directory(directory)
	DirAccess.make_dir_recursive_absolute(folder)
	var digest:=FileAccess.get_sha256(path);var product:=folder.path_join(digest+".scn")
	check(DirAccess.copy_absolute(path,product)==OK,"copy native fixture into isolated content root")
	var candidate:={"source_path":directory.path_join("absent.glb"),"product":product,"generator":"fixture","source_sha":"fixture".sha256_text(),"payload_sha":digest,"bytes":FileAccess.get_file_as_bytes(product).size()}
	check(not FileAccess.file_exists(candidate.source_path),"ordinary reader has no GLB source")
	var worker:=Thread.new()
	check(worker.start(preload("res://scripts/world3d/compiled_asset_preparation.gd").read.bind(candidate.source_path,candidate,directory,Callable(),true,false,"",true))==OK,"ordinary production reader starts")
	while worker.is_alive():await process_frame
	var result:Dictionary=worker.wait_to_finish()
	check(result.get("error",FAILED)==OK and result.get("packed") is PackedScene,"ordinary production read succeeds")
	check(not result.has("native_cpu_hint_meshes"),"ordinary read creates no CPU capture handoff")
	var packet:={"resource":result.get("packed"),"pipeline_batch":result.get("native_pipeline_batch",{})};result.clear()
	check_batch(packet,"ordinary production reader")
	var probe:MeshInstance3D=packet.resource.instantiate()
	check(not probe.mesh.has_meta(&"_rmmo_native_cpu_hint"),"ordinary mesh has no transient CPU hint")
	probe.free()
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	await render_packet(packet,stage,"ordinary production reader")
func render_packet(packet:Dictionary,stage:Node3D,label:String)->void:
	var owner:=product_owner(packet)
	var visual:MeshInstance3D=packet.resource.instantiate();stage.add_child(visual)
	var began:=Time.get_ticks_usec();await draw_frame();var first_us:=Time.get_ticks_usec()-began
	var first:=root.get_texture().get_image()
	for at:int in 4:await draw_frame()
	var settled:=root.get_texture().get_image()
	check(first.get_data()==settled.get_data(),label+" first visible pixels equal settled pixels")
	var left:=first.get_pixel(72,128);var right:=first.get_pixel(184,128)
	check(left.g>left.r+.2 and right.b>right.r+.2,label+" both distinct surfaces visible immediately")
	began=Time.get_ticks_usec();visual.free();var node_us:=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec();packet.clear();var owner_us:=Time.get_ticks_usec()-began
	check(owner.get_ref()==null,label+" native scene owner released")
	samples.append({"label":label,"first_draw_us":first_us,"remove_node_us":node_us,"release_owner_us":owner_us})
	await draw_frame()
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.substr(9).replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/") or DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(256,256);root.use_taa=false;root.msaa_3d=Viewport.MSAA_DISABLED
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var path:=output.get_base_dir().path_join("pipeline_fixture.scn")
	var wrong:=output.get_base_dir().path_join("pipeline_wrong_root.scn");fixture(path,false,wrong)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.01,.01,.01);stage.add_child(environment)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.;stage.add_child(camera);camera.current=true
	await draw_frame()
	var plain:Dictionary=await read_worker(path,false)
	check(not plain.has("capture"),"plain engine API creates no CPU capture context")
	await render_packet(plain,stage,"plain native API")
	await ordinary_reader(path,output.get_base_dir().path_join("content"),stage)
	var packet:Dictionary=await read_worker(path)
	await render_packet(packet,stage,"initial")
	# Three independent reads are retired immediately, before their first draw.
	# No blanket sync or extra frame is inserted before dropping the owners.
	for iteration:int in 3:
		packet=await read_worker(path);var owner:=product_owner(packet);var began:=Time.get_ticks_usec();packet.clear()
		samples.append({"label":"cancel_"+str(iteration),"release_owner_us":Time.get_ticks_usec()-began})
		check(owner.get_ref()==null,"cancel releases independent native scene owner")
		await draw_frame()
	var threads:Array[Thread]=[]
	for at:int in 2:
		var worker:=Thread.new();check(worker.start(read.bind(path))==OK,"parallel independent native worker starts");threads.append(worker)
	while threads.any(func(t:Thread):return t.is_alive()):await process_frame
	var a:Dictionary=threads[0].wait_to_finish();var b:Dictionary=threads[1].wait_to_finish()
	check(a.resource!=b.resource,"parallel readers retain independent resource owners")
	var cancelled:=product_owner(a)
	a.clear();check(cancelled.get_ref()==null,"cancelled parallel owner is freed")
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	await render_packet(b,stage,"parallel survivor")
	packet=await read_worker(path);await render_packet(packet,stage,"return after cancellation")
	# StandardMaterial readers share the engine's shader variant cache. Both
	# must finish safely even if another reader already consumed a task ID.
	var shared_path:=output.get_base_dir().path_join("pipeline_shared_material.scn");fixture(shared_path,true)
	threads.clear()
	var compiled_before:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)
	for at:int in 2:
		var worker:=Thread.new();check(worker.start(read.bind(shared_path,at==0))==OK,"shared shader native worker starts");threads.append(worker)
	while threads.any(func(t:Thread):return t.is_alive()):await process_frame
	a=threads[0].wait_to_finish();b=threads[1].wait_to_finish()
	check(a.get("error",FAILED)==OK and b.get("error",FAILED)==OK,"both shared shader reads complete")
	check(a.has("capture") and not b.has("capture"),"parallel plain reader does not inherit another reader's CPU capture")
	check_batch(a,"shared reader a");check_batch(b,"shared reader b")
	var compiled:=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)-compiled_before
	if OS.get_environment("RMMO_BATCH_MESH_PIPELINES")=="1":
		check(compiled>0 and compiled<=maxi(a.pipeline_batch.unique_completions,b.pipeline_batch.unique_completions),"parallel shared readers do not duplicate pipeline compilations")
	cancelled=product_owner(a);a.clear();check(cancelled.get_ref()==null,"shared cancelled native owner freed")
	await render_packet(b,stage,"shared shader survivor")
	# Binary loading prepares real mesh/material resources, then rejects the
	# root type. Exercise failure after preparation, without corrupting bytes.
	var failure_worker:=Thread.new();check(failure_worker.start(read.bind(wrong))==OK,"failed-root reader starts")
	while failure_worker.is_alive():await process_frame
	var failed:Dictionary=failure_worker.wait_to_finish()
	check(failed.get("error",OK)==ERR_INVALID_DATA and failed.get("resource") is ArrayMesh,"native scene rejects loaded non-scene root")
	check_batch(failed,"failed root")
	var capture_stats:Dictionary=failed.capture.get_statistics()
	check(capture_stats.closed and capture_stats.pending_payload_bytes==0,"failed read closes captured CPU buffers")
	var failed_owner:=product_owner(failed);failed.clear();check(failed_owner.get_ref()==null,"failed native resource owner released")
	failure_worker=Thread.new();check(failure_worker.start(read.bind(wrong,false))==OK,"plain failed-root reader starts")
	while failure_worker.is_alive():await process_frame
	failed=failure_worker.wait_to_finish()
	check(failed.get("error",OK)==ERR_INVALID_DATA and not failed.has("capture"),"plain failure reports error without allocating CPU capture")
	check_batch(failed,"plain failed root")
	failed_owner=product_owner(failed);failed.clear();check(failed_owner.get_ref()==null,"plain failed resource released")
	# A synchronous main-thread caller and a pool task must retain the ordinary
	# wait path; blocking compiler workers on this private-thread fence is unsafe.
	var main_packet:=read(path)
	check(main_packet.error==OK and not main_packet.get("pipeline_batch",{}).get("enabled",false),"main-thread read keeps ordinary pipeline completion")
	main_packet.clear()
	main_packet=read(path,false)
	check(main_packet.error==OK and not main_packet.pipeline_batch.enabled and not main_packet.has("capture"),"plain main-thread caller keeps ordinary waits and no CPU capture")
	main_packet.clear()
	var pool_result:Dictionary={}
	var task:=WorkerThreadPool.add_task(pool_read.bind(path,pool_result),true,"native pipeline pool fallback")
	while not WorkerThreadPool.is_task_completed(task):await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var pool_packet:Dictionary=pool_result.packet;pool_result.clear()
	check(pool_packet.error==OK and not pool_packet.get("pipeline_batch",{}).get("enabled",false),"pool reader retains collaborative wait without private-thread batch")
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer();pool_packet.clear()
	task=WorkerThreadPool.add_task(pool_read.bind(path,pool_result,false),true,"plain native pipeline pool fallback")
	while not WorkerThreadPool.is_task_completed(task):await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	pool_packet=pool_result.packet;pool_result.clear()
	check(pool_packet.error==OK and not pool_packet.pipeline_batch.enabled and not pool_packet.has("capture"),"plain pool caller keeps collaborative waits and no CPU capture")
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer();pool_packet.clear()
	stage.free();await draw_frame()
	var report:={"checks":checks,"failures":failures,"samples":samples,"shared_pipeline_compilations":compiled,"async_pipelines":OS.get_environment("RMMO_ASYNC_MESH_PIPELINES")=="1","batch_pipelines":OS.get_environment("RMMO_BATCH_MESH_PIPELINES")=="1"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATIVE_PIPELINE_FIRST_DRAW ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
