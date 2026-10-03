extends "res://tools/test_ground_batching.gd"
const TOWN = "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
func run() -> void:
	create_timer(480).timeout.connect(func():quit(2)); Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var original_hash:=FileAccess.get_sha256(TOWN)
	viewport=SubViewport.new(); viewport.size=Vector2i(1920,1080); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.18,.24,.3); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.5; viewport.add_child(environment)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-65,30,0); viewport.add_child(light)
	camera=Camera3D.new(); camera.far=5000; viewport.add_child(camera); camera.position=Vector3(0,1500,950); camera.look_at(Vector3.ZERO); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1550
	var doc=Doc.open_file(TOWN)
	for i in doc.records.size():
		var node: MeshInstance3D=doc._mesh(doc.records[i]); viewport.add_child(node); sources.append(node)
		if i%25==0: await process_frame
	print("TOWN_GROUND_LOADED ",sources.size())
	var batcher:=Batch.new(); viewport.add_child(batcher)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var report:={"map":TOWN,"gpu":RenderingServer.get_video_adapter_name(),"viewport":[1920,1080],"before":await measure()}
	await RenderingServer.frame_post_draw; var before:=viewport.get_texture().get_image(); before.save_png(OUTPUT.path_join("town_before.png"))
	var begin:=Time.get_ticks_usec(); batcher.sync(sources)
	var frame_times: Array=[]; var previous:=Time.get_ticks_usec()
	while batcher.stats().pending_groups>0:
		await process_frame; var now:=Time.get_ticks_usec(); frame_times.append((now-previous)/1000.); previous=now
	frame_times.sort(); report.build_ms=(Time.get_ticks_usec()-begin)/1000.; report.build_frame_p95_ms=frame_times[int(frame_times.size()*.95)]; report.build_frame_max_ms=frame_times[-1]
	report.after=await measure(); report.stats=batcher.stats()
	await RenderingServer.frame_post_draw; var after:=viewport.get_texture().get_image(); after.save_png(OUTPUT.path_join("town_after.png"))
	report.pixel_error=difference(before,after)
	check(report.pixel_error<.003,"town rendered appearance preserved")
	check(report.after.draw_calls<report.before.draw_calls*.5,"town drawing submissions reduced by half")
	check(report.after.buffer_bytes<report.before.buffer_bytes,"town geometry GPU memory decreases")
	check(original_hash==FileAccess.get_sha256(TOWN),"user town files unchanged")
	report.failures=failed; var file:=FileAccess.open(OUTPUT.path_join("town_performance.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TOWN_GROUND_BATCH_RESULT ",JSON.stringify(report)); quit(1 if failed else 0)
