extends SceneTree

var worker := Thread.new()
var frames := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	world.add_child(mesh)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(3, 2, 4)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	world.add_child(light)
	print("REPRO_START ", JSON.stringify({"pid":OS.get_process_id(),"gpu_compression":ProjectSettings.get_setting("rendering/textures/vram_compression/compress_with_gpu"),"cache_gpu_compressor":ProjectSettings.get_setting("rendering/textures/vram_compression/cache_gpu_compressor"),"display":DisplayServer.get_name(),"method":RenderingServer.get_current_rendering_method(),"main_thread":OS.get_main_thread_id()}))
	for index in 60:
		await process_frame
		frames += 1
	print("DRAW_BEFORE ", Engine.get_frames_drawn())
	var initial_rd:RenderingDevice=RenderingServer.get_rendering_device()
	var initial_id:int=initial_rd.get_instance_id() if initial_rd!=null else 0
	print("GLOBAL_RD_BEFORE ",initial_id)
	var start_error := worker.start(_compress)
	if start_error != OK:
		print("THREAD_START_ERROR ", start_error)
		quit(2)
		return
	var deadline := Time.get_ticks_msec() + 60000
	while worker.is_alive() and Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
	if worker.is_alive():
		print("ENCODE_TIMEOUT frames=", frames)
		quit(3)
		return
	var result: Dictionary = worker.wait_to_finish()
	print("ENCODE_RESULT ", JSON.stringify(result))
	for index in 60:
		await process_frame
		frames += 1
	var final_rd:RenderingDevice=RenderingServer.get_rendering_device()
	var final_id:int=final_rd.get_instance_id() if final_rd!=null else 0
	print("GLOBAL_RD_AFTER ",final_id)
	if final_id!=initial_id:result.error=FAILED
	print("REPRO_DONE ", JSON.stringify({"frames":frames,"drawn":Engine.get_frames_drawn(),"rd_unchanged":initial_id==final_id}))
	quit(0 if result.get("error", -1) == OK else 4)

func _compress() -> Dictionary:
	var cpu_only:bool=ProjectSettings.get_setting("test/cpu_only",true)
	var setting_before:bool=ProjectSettings.get_setting("rendering/textures/vram_compression/compress_with_gpu")
	var rows:Array=[]
	var failure:=OK
	for index:int in 4:
		var side:=32 if index<2 else 64
		var img:=Image.create(side,side,false,Image.FORMAT_RGBA8)
		for y:int in side:
			for x:int in side:
				img.set_pixel(x,y,Color(float(x)/side,float(y)/side,float((x+y)%11)/11.0,1.0 if index%2==0 else float((x+y)%5)/4.0))
		img.generate_mipmaps()
		var channels:=Image.USED_CHANNELS_RGB if index%2==0 else Image.USED_CHANNELS_RGBA
		var begin:=Time.get_ticks_usec()
		var error:int=ERR_UNAVAILABLE
		if cpu_only:
			if img.has_method("compress_from_channels_cpu"):error=img.call("compress_from_channels_cpu",Image.COMPRESS_S3TC,channels)
		else:error=img.compress_from_channels(Image.COMPRESS_S3TC,channels)
		var elapsed:=Time.get_ticks_usec()-begin
		var expected:=Image.FORMAT_DXT1 if index%2==0 else Image.FORMAT_DXT5
		var valid:bool=error==OK and img.get_format()==expected and img.has_mipmaps() and img.get_width()==side and img.get_height()==side
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(img.get_data())
		rows.append({"case":index,"valid":valid,"error":error,"format":img.get_format(),"width":img.get_width(),"mips":img.get_mipmap_count(),"bytes":img.get_data().size(),"sha":hash.finish().hex_encode(),"elapsed_us":elapsed})
		if not valid:failure=FAILED
	var setting_after:bool=ProjectSettings.get_setting("rendering/textures/vram_compression/compress_with_gpu")
	if setting_before!=setting_after:failure=FAILED
	return {"error":failure,"cpu_only":cpu_only,"global_gpu_unchanged":setting_before==setting_after,"global_gpu":setting_after,"thread":OS.get_thread_caller_id(),"cases":rows}
