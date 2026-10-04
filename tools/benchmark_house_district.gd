extends "res://tools/test_ground_batching.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/house_district"
func run()->void:
	create_timer(1200).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute(OUT);Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var count:=36
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--houses="):count=int(arg.trim_prefix("--houses="))
	var checkpoint:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/house_revision_v10/checkpoint.json"))
	var templates:Dictionary={}
	for r:Dictionary in checkpoint.records:
		var id:String=r.get("building",{}).get("id","")
		if id.is_empty():continue
		if not templates.has(id):templates[id]=[]
		templates[id].append(r)
	var doc:=Doc.new();doc.add_box("ground",Vector3(80,-.25,80),Vector3(260,.5,260))
	for i in count:
		var house:Dictionary=checkpoint.houses[i%checkpoint.houses.size()]
		var at:=Vector3((i%6)*34,0,(i/6)*36);var shift:=at-B.vec(house.position)
		for original:Dictionary in templates[house.building_id]:
			var r:=original.duplicate(true);r.uuid="district_%d_"%i+str(r.uuid);r.building.id="district_house_%d"%i
			r.position=B.arr(B.vec(r.position)+shift);doc.records.append(r)
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_4X;viewport.use_taa=true;root.add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.45,.55,.65);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.55;viewport.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,145,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=160;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;viewport.add_child(sun)
	camera=Camera3D.new();viewport.add_child(camera);camera.far=1500;camera.position=Vector3(65,12,-22);camera.look_at(Vector3(75,6,40))
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var started:=Time.get_ticks_msec();var scene:=doc.build();viewport.add_child(scene)
	var build_ms:=Time.get_ticks_msec()-started
	print("DISTRICT_BUILT houses=",count," records=",doc.records.size()," ms=",build_ms," box_hits=",doc.load_box_hits)
	started=Time.get_ticks_msec();Stream.sync(scene,viewport,Vector3(70,0,30));var stream_ms:=Time.get_ticks_msec()-started
	var batch:Node=scene.get_node("GroundRenderBatches")
	print("DISTRICT_STREAM_READY ms=",stream_ms," phases=",JSON.stringify(scene.get_meta("stream_profile_ms",{}))," batches=",JSON.stringify(batch.stats()))
	print("DISTRICT_ADOPT ",JSON.stringify(scene.get_meta("stream_adopt_ms",{})))
	if "--load-only" in OS.get_cmdline_user_args():quit();return
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();viewport.add_child(nav)
	started=Time.get_ticks_msec();nav.build(scene.get_meta("stream_library"),Vector3(70,0,30))
	while not nav.fully_ready:await process_frame
	var nav_ms:=Time.get_ticks_msec()-started
	print("DISTRICT_NAV_READY ms=",nav_ms)
	var batch_process_us:=0
	for i in 100:
		var probe:=Time.get_ticks_usec();batch._process(1.0/60);batch_process_us+=Time.get_ticks_usec()-probe
	var observer:=Node3D.new();viewport.add_child(observer);observer.position=Vector3(0,2,0)
	var lights:=preload("res://scripts/world3d/house_candle_lights.gd").new();viewport.add_child(lights);lights.bind_map(scene,observer)
	var results:Array=[]
	for night in [false,true]:
		lights.set_hours(23 if night else 12);sun.light_energy=.03 if night else 1.15;environment.environment.ambient_light_energy=.16 if night else .55
		await frames(45);var samples:Array=[];var gpu:Array=[];var swaps:Array=[];var previous:=Time.get_ticks_usec()
		for i in 150:
			var point:=Vector3(60+float(i)*.35,12,-22)
			camera.position=point;camera.look_at(point+Vector3(0,-4,55))
			var start_sync:=Time.get_ticks_usec();Stream.sync(scene,viewport,Vector3(point.x,0,30),12);swaps.append((Time.get_ticks_usec()-start_sync)/1000.0)
			await process_frame;var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
			observer.position=Vector3(point.x,2,30)
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(OUT.path_join("night.png" if night else "day.png"))
		samples.sort();gpu.sort();swaps.sort()
		results.append({"night":night,"frame_median_ms":samples[75],"frame_p95_ms":samples[142],"frame_max_ms":samples.back(),"gpu_median_ms":gpu[75],"stream_median_ms":swaps[75],"stream_p95_ms":swaps[142],"stream_max_ms":swaps.back(),"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
		print("DISTRICT_PASS ",JSON.stringify(results.back()))
	var result:Dictionary={"houses":count,"records":doc.records.size(),"build_ms":build_ms,"stream_ms":stream_ms,"navigation_ms":nav_ms,"batch_process_ms":batch_process_us/100000.0,"batches":batch.stats(),"results":results,"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)}
	var file:=FileAccess.open(OUT.path_join("benchmark.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("DISTRICT_FINISHED ",JSON.stringify(result));quit()
