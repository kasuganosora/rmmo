extends SceneTree
const Timeline=preload("res://scripts/util/debug_timeline.gd")
var output:=""
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
static func work(label_id:int)->void:
	var token:=Timeline.begin(label_id,7001)
	var sum_:=0
	for i in 100000:sum_+=i%17
	Timeline.mark(label_id,7001,sum_);Timeline.end(token)
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="):output=arg.trim_prefix("--output-dir=").replace("\\","/")
	if not output.begins_with("D:/code/rmmo_runtime/review_artifacts/"):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","real private desktop GPU")
	check(Timeline.available(),"native trace API exists")
	if not Timeline.available():quit(2);return
	root.size=Vector2i(320,240)
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,0,4);camera.current=true
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-30,-30,0)
	var label_id:=Timeline.label("test.gpu.worker")
	var resource_path:=output.path_join("temporary_material.tres")
	var source:=StandardMaterial3D.new();source.albedo_color=Color(.7,.3,.1)
	check(ResourceSaver.save(source,resource_path)==OK,"temporary native input saved before capture")
	check(Timeline.start(131072,true)==OK,"GPU capture starts")
	var mesh:=ArrayMesh.new();var primitive:=BoxMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,primitive.get_mesh_arrays())
	var material:Material=ResourceLoader.load(resource_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	mesh.surface_set_material(0,material)
	var node:=MeshInstance3D.new();node.mesh=mesh;world.add_child(node)
	var task:=WorkerThreadPool.add_task(work.bind(label_id),false,"Trace contract task")
	WorkerThreadPool.wait_for_task_completion(task)
	var group:=WorkerThreadPool.add_group_task(func(_index:int):work(label_id),4,2,false,"Trace group contract")
	WorkerThreadPool.wait_for_group_task_completion(group)
	for i in 6:await process_frame
	RenderingServer.force_sync()
	await RenderingServer.frame_post_draw
	var first:=root.get_texture().get_image()
	var stats:=Timeline.stop()
	check(stats.dropped==0 and stats.events>0,"GPU capture retains events")
	check(Timeline.export_capture(output.path_join("gpu.rmtrace"))==OK,"GPU capture exports after stop")
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var second:=root.get_texture().get_image()
	check(first.get_size()==second.get_size() and first.get_data()==second.get_data(),"capture controls preserve rendered pixels")
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"stats":stats},"\t"))
	world.free();quit(0 if failures.is_empty() else 1)
