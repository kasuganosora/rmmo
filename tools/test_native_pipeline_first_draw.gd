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
func fixture(path:String)->void:
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, cull_disabled; uniform vec4 tint : source_color; void fragment(){ ALBEDO=tint.rgb; }"
	var mesh:=ArrayMesh.new()
	for side:int in 2:
		var box:=BoxMesh.new();box.size=Vector3(.8,.8,.8)
		var arrays:=box.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for at:int in vertices.size():vertices[at].x+=(-.65 if side==0 else .65)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material:=ShaderMaterial.new();material.shader=shader
		material.set_shader_parameter("tint",Color(.05,.8,.1) if side==0 else Color(.1,.15,.9))
		mesh.surface_set_material(side,material)
	var node:=MeshInstance3D.new();node.mesh=mesh
	var packed:=PackedScene.new();check(packed.pack(node)==OK,"pack two actual material surfaces")
	check(ResourceSaver.save(packed,path,ResourceSaver.FLAG_BUNDLE_RESOURCES)==OK,"save native fixture outside project")
	node.free()
static func read(path:String)->Dictionary:
	var began:=Time.get_ticks_usec()
	var packet:Dictionary=ClassDB.class_call_static(&"ArrayMesh",&"load_native_scene_with_cpu_surfaces",path)
	packet.worker_us=Time.get_ticks_usec()-began
	return packet
func read_worker(path:String)->Dictionary:
	var worker:=Thread.new();check(worker.start(read.bind(path))==OK,"native reader starts on actual worker")
	while worker.is_alive():await process_frame
	var packet:Dictionary=worker.wait_to_finish()
	check(packet.get("error",FAILED)==OK and packet.get("resource") is PackedScene,"native worker returns complete resource")
	preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	return packet
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
	var path:=output.get_base_dir().path_join("pipeline_fixture.scn");fixture(path)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.01,.01,.01);stage.add_child(environment)
	var camera:=Camera3D.new();camera.position=Vector3(0,0,3);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.;stage.add_child(camera);camera.current=true
	await draw_frame()
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
	stage.free();await draw_frame()
	var report:={"checks":checks,"failures":failures,"samples":samples,"async_pipelines":OS.get_environment("RMMO_ASYNC_MESH_PIPELINES")=="1"}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NATIVE_PIPELINE_FIRST_DRAW ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
