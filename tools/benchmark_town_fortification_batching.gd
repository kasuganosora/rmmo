extends "res://tools/test_ground_batching.gd"
const TOWN="D:/code/rmmo_runtime/cache/world3d/medieval_town_walls/map.gltf"
const OUT="D:/code/rmmo_runtime/review_artifacts/medieval_town_walls/batching"
func run() -> void:
	create_timer(1200).timeout.connect(func():quit(2)); Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); DirAccess.make_dir_recursive_absolute(OUT)
	var original_hash:=FileAccess.get_sha256(TOWN)
	viewport=SubViewport.new(); viewport.size=Vector2i(1920,1080); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.18,.24,.3); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.5; viewport.add_child(environment)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-65,30,0); viewport.add_child(light)
	camera=Camera3D.new(); camera.far=5000; viewport.add_child(camera); camera.position=Vector3(0,1500,950); camera.look_at(Vector3.ZERO); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1550
	# Native validity/save-reopen is covered by the authoring and runtime tests.
	# Keep this renderer benchmark focused on the exact reviewed candidate.
	var verified: Variant=JSON.parse_string(FileAccess.get_file_as_string(OUT.get_base_dir().path_join("result.json")))
	check(verified is Dictionary and verified.get("failures",1)==0 and verified.get("candidate_sha256")==original_hash,"saved wall candidate was independently validated")
	if failed: quit(1); return
	var raw:=Doc.authoritative_extras(TOWN); check(raw.has("extras"),"read verified candidate records")
	if not raw.has("extras"): quit(1); return
	var doc:=Doc.new(); doc.records.assign(raw.extras.rmmo_records)
	doc.terrain_neighbors.update(doc.records)
	for i in doc.records.size():
		var node: MeshInstance3D=doc._mesh(doc.records[i]); viewport.add_child(node); sources.append(node)
		if i%25==0: await process_frame
	var batcher:=Batch.new(); viewport.add_child(batcher)
	if "--diagnostic" in OS.get_cmdline_user_args():
		var started:=Time.get_ticks_usec(); batcher.sync(sources.filter(func(n):return n.get_meta("ground_batch_record",{}).has("fortification")))
		print("SYNC_PROFILE ",batcher.last_sync_ms," ",batcher.sync_profile)
		while batcher.stats().pending_groups>0: await process_frame
		print("CACHE_MS ",(Time.get_ticks_usec()-started)/1000.)
		print("COLLISION_DIAGNOSTIC ",await collision_benchmark()); quit(1 if failed else 0); return
	# Existing ground batching is enabled on both sides of the comparison.
	batcher.sync(sources.filter(func(n):return not n.get_meta("ground_batch_record",{}).has("fortification")))
	while batcher.stats().pending_groups>0: await process_frame
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var report:={"candidate_sha256":original_hash,"gpu":RenderingServer.get_video_adapter_name(),"viewport":[1920,1080],"before":await measure()}
	await RenderingServer.frame_post_draw; var before:=viewport.get_texture().get_image(); before.save_png(OUT.path_join("before.png"))
	var begin:=Time.get_ticks_usec(); batcher.sync(sources); report.sync_ms=(Time.get_ticks_usec()-begin)/1000.
	var times: Array=[]; var previous:=Time.get_ticks_usec()
	while batcher.stats().pending_groups>0:
		await process_frame; var now:=Time.get_ticks_usec(); times.append((now-previous)/1000.); previous=now
	times.sort(); report.build_frame_p95_ms=times[int(times.size()*.95)] if not times.is_empty() else 0.; report.build_frame_max_ms=times[-1] if not times.is_empty() else 0.
	report.build_ms=(Time.get_ticks_usec()-begin)/1000.; report.after=await measure(); report.stats=batcher.stats("fortification")
	await RenderingServer.frame_post_draw; var after:=viewport.get_texture().get_image(); after.save_png(OUT.path_join("after.png")); report.pixel_error=difference(before,after)
	check(report.pixel_error<.003,"town wall appearance preserved")
	check(report.after.draw_calls<report.before.draw_calls*.5,"whole-town submissions more than halved with ground already batched")
	check(report.after.buffer_bytes<=report.before.buffer_bytes*1.05,"wall batching does not inflate GPU geometry buffers")
	check(report.stats.source_objects>3000 and report.stats.render_surfaces<report.stats.source_surfaces*.3,"thousands of logical wall parts use bounded spatial draws")
	check(sources.filter(func(n):return n.get_meta("ground_batch_record",{}).has("fortification") and n.mesh is Cpu).size()==report.stats.source_objects,"merged source instances retain only CPU geometry")
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE; camera.position=Vector3(612,22,-150); camera.look_at(Vector3(591,3,-180)); await frames(30); await RenderingServer.frame_post_draw
	var close_after:=viewport.get_texture().get_image(); close_after.save_png(OUT.path_join("close_after.png"))
	batcher.clear(); batcher.sync(sources.filter(func(n):return not n.get_meta("ground_batch_record",{}).has("fortification"))); batcher.flush(); await frames(30); await RenderingServer.frame_post_draw
	var close_before:=viewport.get_texture().get_image(); close_before.save_png(OUT.path_join("close_before.png")); report.close_pixel_error=difference(close_before,close_after)
	check(report.close_pixel_error<.003,"near wall material UVs normals and silhouette preserved")
	check(original_hash==FileAccess.get_sha256(TOWN),"candidate records unchanged by renderer benchmark")
	report.collision=await collision_benchmark()
	report.failures=failed; var file:=FileAccess.open(OUT.path_join("performance.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("TOWN_FORTIFICATION_BATCH_RESULT ",JSON.stringify(report)); quit(1 if failed else 0)

func collision_benchmark() -> Dictionary:
	var collision_type=preload("res://scripts/world3d/fortification_collision_batcher.gd")
	var stream=preload("res://scripts/world3d/world_stream.gd")
	var host:=Node3D.new(); viewport.add_child(host); var entries: Array=[]; var probes: Array=[]
	var started:=Time.get_ticks_usec(); var count:=0
	for visual: MeshInstance3D in sources:
		if not collision_type.candidate(visual.get_meta("ground_batch_record",{})): continue
		entries.append(collision_type.entry(visual.mesh,visual.global_transform,str(visual.name),visual.get_meta("extras",{})))
		stream._make_body(host,stream._spec(visual)); count+=1
		if count%17==0:
			# Component origins can be exactly on a triangle-fan junction. Compare
			# interior samples here; exact fan centers and capsule support have their
			# own regression (the old independent meshes can also miss those rays).
			var p: Vector3=visual.global_position+Vector3(.0137,0,.0193)
			probes.append(PhysicsRayQueryParameters3D.create(p+Vector3.UP*15,p-Vector3.UP*15))
	var baseline_ms: float=(Time.get_ticks_usec()-started)/1000.
	for i in 4: await physics_frame
	var space:=host.get_world_3d().direct_space_state; var before: Array=[]
	started=Time.get_ticks_usec()
	for q in probes:
		var hit:=space.intersect_ray(q); before.append({"position":hit.get("position"),"normal":hit.get("normal"),"uuid":collision_type.hit_uuid(hit)})
	var ray_before: float=(Time.get_ticks_usec()-started)/1000.
	for body in host.get_children(): body.free()
	var batch=collision_type.new(); host.add_child(batch); started=Time.get_ticks_usec(); batch.sync(entries)
	var build_ms: float=(Time.get_ticks_usec()-started)/1000.
	for i in 4: await physics_frame
	var misses:=0; var ids_missing:=0; var after: Array=[]; started=Time.get_ticks_usec()
	for q in probes: after.append(space.intersect_ray(q))
	var ray_after: float=(Time.get_ticks_usec()-started)/1000.
	for i in probes.size():
		var hit: Dictionary=after[i]
		if before[i].position==null:
			if not hit.is_empty(): misses+=1
		elif hit.is_empty() or hit.position.distance_to(before[i].position)>.002 or hit.normal.dot(before[i].normal)<.99:
			misses+=1; print("COLLISION_DIFFERENCE ",i," ray ",probes[i].from," ",probes[i].to," before ",before[i]," after ",{"position":hit.get("position"),"normal":hit.get("normal"),"uuid":collision_type.hit_uuid(hit)})
		if not hit.is_empty() and collision_type.hit_uuid(hit).is_empty(): ids_missing+=1
	var stats: Dictionary=batch.stats()
	check(stats.bodies<count*.4,"whole town static collision body count reduced by over 60 percent")
	check(misses==0 and ids_missing==0,"whole town collision rays preserve surfaces and original object identity")
	var old_count: int=batch.rebuild_count; batch.sync(entries); check(batch.rebuild_count==old_count,"unchanged collision sources rebuild zero chunks")
	var result:={"source_bodies":count,"before_build_ms":baseline_ms,"after_build_ms":build_ms,"stats":stats,"ray_count":probes.size(),"before_ray_ms":ray_before,"after_ray_ms":ray_after,"surface_mismatches":misses,"missing_ids":ids_missing}
	host.free(); return result
