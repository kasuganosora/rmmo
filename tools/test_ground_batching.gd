extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Batch = preload("res://scripts/world3d/ground_batcher.gd")
const Cpu = preload("res://scripts/world3d/ground_cpu_mesh.gd")
const OUTPUT = "D:/code/rmmo_runtime/review_artifacts/ground_batching"
var failed := 0
var viewport: SubViewport
var camera: Camera3D
var sources: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failed += 1; push_error(message)
	else: print("PASS: ",message)
func frames(count: int = 20) -> void:
	for i in count: await process_frame
func measure() -> Dictionary:
	await frames(45)
	var samples: Array = []
	for i in 80:
		await process_frame
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
	samples.sort()
	return {"gpu_median_ms":samples[40],"gpu_p95_ms":samples[76],"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
func difference(a: Image,b: Image) -> float:
	var total := 0.
	for y in range(0,a.get_height(),2):
		for x in range(0,a.get_width(),2):
			var c := a.get_pixel(x,y); var d := b.get_pixel(x,y)
			total += absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)
	return total / (a.get_width()*a.get_height()*.75)
func run() -> void:
	create_timer(240).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT); Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport=SubViewport.new(); viewport.size=Vector2i(1280,720); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.18,.24,.3); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.45; viewport.add_child(environment)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-55,32,0); viewport.add_child(light)
	camera=Camera3D.new(); camera.far=3000; viewport.add_child(camera); camera.position=Vector3(91,240,310); camera.look_at(Vector3(91,0,118)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=300
	var doc = Doc.open_file("D:/code/rmmo_runtime/maps/river_bank_lab/map.gltf")
	var template: Dictionary = doc.records.filter(func(r):return r.get("editor_name","").begins_with("C 陡岸"))[0].duplicate(true)
	var fixture := Doc.new()
	for z in 7:
		for x in 7:
			var record := template.duplicate(true); record.uuid="patch_%d_%d"%[x,z]; record.position=[12+x*26,0,16+z*34]
			if x==6: record.rotation=[0,25.,0]
			for at in record.terrain_mesh.heights.size(): record.terrain_mesh.heights[at]+=.2*sin(at*.17+x*.2+z)
			if x==3 and z==3: record.terrain_mesh.holes[20]=true
			var node: MeshInstance3D=fixture._mesh(record); viewport.add_child(node); sources.append(node)
	var batcher:=Batch.new(); viewport.add_child(batcher)
	var source_hashes: Array=[]
	for node: MeshInstance3D in sources: source_hashes.append(var_to_bytes(node.mesh.get_faces()).hex_encode().sha256_text())
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"viewport":[1280,720],"before":await measure()}
	await RenderingServer.frame_post_draw; var before:=viewport.get_texture().get_image(); before.save_png(OUTPUT.path_join("before.png"))
	var begin:=Time.get_ticks_usec(); batcher.sync(sources)
	var frame_times: Array=[]; var previous:=Time.get_ticks_usec()
	while batcher.stats().pending_groups>0:
		await process_frame; var now:=Time.get_ticks_usec(); frame_times.append((now-previous)/1000.); previous=now
	frame_times.sort(); report.build_ms=(Time.get_ticks_usec()-begin)/1000.; report.build_frame_p95_ms=frame_times[int(frame_times.size()*.95)]; report.build_frame_max_ms=frame_times[-1]
	report.after=await measure(); report.stats=batcher.stats()
	await RenderingServer.frame_post_draw; var after:=viewport.get_texture().get_image(); after.save_png(OUTPUT.path_join("after.png"))
	report.pixel_error=difference(before,after)
	check(report.pixel_error<.004,"matching height-layer PBR/rotation/hole appearance: "+str(report.pixel_error))
	check(report.after.draw_calls<report.before.draw_calls*.5,"draw calls reduced by at least half")
	check(report.after.buffer_bytes<report.before.buffer_bytes,"GPU buffers released and flat underside compacted")
	check(sources.filter(func(n):return n.mesh is Cpu).size()==report.stats.source_objects,"merged sources have CPU meshes, no duplicate GPU allocation")
	for i in sources.size(): check(var_to_bytes(sources[i].mesh.get_faces()).hex_encode().sha256_text()==source_hashes[i],"immutable source triangles "+str(i))
	var built:=batcher.rebuild_count; batcher.sync(sources); batcher.flush(); check(batcher.rebuild_count==built,"unchanged sync performs zero builds")
	var node: MeshInstance3D=sources[0]; var faces:=node.mesh.get_faces(); var shape:=node.mesh.create_trimesh_shape()
	check(shape.get_faces()==faces,"batched source retains exact collision triangles")
	batcher.sync(sources,[str(node.name)]); batcher.flush(); check(not node.mesh is Cpu and node.mesh.get_faces()==faces,"selection restores only affected group with exact geometry")
	node.visible=false; batcher.sync(sources); batcher.flush()
	check(not node.mesh is Cpu,"hidden source excluded")
	var paint:=preload("res://scripts/world3d/surface_materials.gd").geometry(sources[1]); check(paint.ok,"batched terrain still has addressable original painted faces")
	batcher.clear(); check(sources.all(func(n):return not n.mesh is Cpu),"clear releases combined meshes and restores sources")
	report.failures=failed; var file:=FileAccess.open(OUTPUT.path_join("performance.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("GROUND_BATCH_RESULT ",JSON.stringify(report)); quit(1 if failed else 0)
