extends SceneTree
const Lights=preload("res://scripts/world3d/house_candle_lights.gd")
const Sconce=preload("res://scripts/world3d/candle_sconce_mesh.gd")
var viewport:SubViewport
func _initialize()->void:run.call_deferred()
func sample()->Dictionary:
	for i in 20:await process_frame
	var samples:Array=[];var cpu:Array=[]
	for i in 100:
		var begin:=Time.get_ticks_usec();await process_frame;cpu.append((Time.get_ticks_usec()-begin)/1000.0)
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
	samples.sort();cpu.sort()
	return {"gpu_median_ms":samples[50],"gpu_p95_ms":samples[95],"frame_median_ms":cpu[50],"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
func run()->void:
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.06,.075,.1);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.25;viewport.add_child(env)
	var scene:=Node3D.new();viewport.add_child(scene);var records:Array=[];var meshes:Dictionary={}
	for z in 6:
		for x in 6:
			for f in 4:
				var p:=Vector3(x*12,2.15+(f/2)*4,z*14+(f%2)*6)
				var r:Dictionary={"uuid":"lamp_%d_%d_%d"%[x,z,f],"position":[p.x,p.y,p.z],"size":[.26,.54,.46],"rotation":[0,0,0],"collision":"none","building_shape":"candle_sconce","building":{"role":"light_sconce","floor_y":p.y-2.15}}
				var n:=MeshInstance3D.new();scene.add_child(n);n.mesh=Sconce.mesh(r);n.position=p;meshes[r.uuid]=n;records.append(r)
				var wall:=MeshInstance3D.new();var cube:=BoxMesh.new();cube.size=Vector3(10,4,.2);wall.mesh=cube;scene.add_child(wall);wall.position=p+Vector3(0,-.15,-.32)
	scene.set_meta("extras",{"rmmo_records":records});scene.set_meta("stream_meshes",meshes)
	var observer:=Node3D.new();observer.position=Vector3(25,0,18);scene.add_child(observer)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.position=Vector3(27,10,26);camera.look_at(Vector3(24,4,14));camera.fov=70
	var controller:=Lights.new();scene.add_child(controller);controller.bind_map(scene,observer)
	controller.set_hours(12);var day:=await sample()
	controller.set_hours(0);var night:=await sample()
	var begin:=Time.get_ticks_usec()
	for i in 250:controller.refresh()
	var update_ms:float=(Time.get_ticks_usec()-begin)/250000.0
	var result:Dictionary={"scope":"isolated 36 blocks / 144 fixtures; not full-house benchmark","fixtures":144,"shadow_lights":controller.lit_count(),"day":day,"night":night,"refresh_cpu_ms":update_ms}
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/candle_sconce/benchmark.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("CANDLE_BENCHMARK ",JSON.stringify(result));quit(0 if controller.lit_count()<=2 else 1)
