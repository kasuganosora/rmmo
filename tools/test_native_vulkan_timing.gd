extends SceneTree
## Small real-render fixture for the opt-in native wait recorder. No map assets.
## Native timings are emitted by the engine at exit, not by this script.
var samples:Array=[]
var destination:=""
var began:=0

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):destination=arg.trim_prefix("--output=")
	run.call_deferred()

func run()->void:
	began=Time.get_ticks_usec()
	root.size=Vector2i(320,240)
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	var world:=Node3D.new()
	root.add_child(world)
	var box:=MeshInstance3D.new()
	box.mesh=BoxMesh.new()
	world.add_child(box)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(0,1,4)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	RenderingServer.frame_pre_draw.connect(pre_draw)
	RenderingServer.frame_post_draw.connect(post_draw)
	for i:int in 120:
		await process_frame
		box.rotation.y+=0.01
	RenderingServer.frame_pre_draw.disconnect(pre_draw)
	RenderingServer.frame_post_draw.disconnect(post_draw)
	world.free()
	var valid:=samples.size()>=200 and DisplayServer.get_name()!="headless"
	var report:={"synthetic_fixture":true,"not_map_performance_evidence":true,
		"accepted":valid,"display":DisplayServer.get_name(),"began_ticks_us":began,
		"samples":samples,"godot_thread_id":OS.get_thread_caller_id(),
		"engine":OS.get_executable_path(),"script_sha":FileAccess.get_sha256(get_script().resource_path)}
	if not destination.is_empty():
		var file:=FileAccess.open(destination,FileAccess.WRITE)
		if file==null:quit(2);return
		file.store_string(JSON.stringify(report))
	print("NATIVE_WAIT_RENDER_FIXTURE ",valid," markers=",samples.size())
	quit(0 if valid else 1)

func pre_draw()->void:
	samples.append({"stage":"pre","ticks_us":Time.get_ticks_usec(),"engine_frame":Engine.get_process_frames()})

func post_draw()->void:
	samples.append({"stage":"post","ticks_us":Time.get_ticks_usec(),"engine_frame":Engine.get_process_frames()})
