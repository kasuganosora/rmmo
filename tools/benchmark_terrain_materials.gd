extends SceneTree
const Doc=preload("res://scripts/world3d/world_document.gd")
const River=preload("res://scripts/world3d/river_materials.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const OUTPUT="D:/code/rmmo_runtime/review_artifacts/river_bank_lab"
var viewport: SubViewport
var camera: Camera3D
var nodes: Array[MeshInstance3D]=[]
var report: Dictionary={}
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value: failures+=1; push_error(message)
	else: print("PASS: ",message)
func run() -> void:
	create_timer(300).timeout.connect(func():quit(2)); Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	viewport=SubViewport.new(); viewport.size=Vector2i(1920,1080); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.18,.24,.3)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.45; viewport.add_child(environment)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-55,32,0); viewport.add_child(light)
	camera=Camera3D.new(); camera.far=3000; viewport.add_child(camera)
	var doc=Doc.open_file("D:/code/rmmo_runtime/maps/river_bank_lab/map.gltf")
	var record: Dictionary=doc.records.filter(func(r):return r.get("editor_name","").begins_with("C 陡岸"))[0].duplicate(true)
	var mesh:=Terrain.mesh(record,null); var current:=River.terrain(record)
	var reference: ShaderMaterial=current.duplicate(); var old_shader:=Shader.new()
	var source:=FileAccess.get_file_as_string(OUTPUT.path_join("terrain_shader_before_optimization.gdshader"))
	if source.is_empty(): push_error("Provide captured baseline shader in review_artifacts/river_bank_lab"); quit(2); return
	old_shader.code=source; reference.shader=old_shader
	for z in 7:
		for x in 7:
			var node:=MeshInstance3D.new(); node.mesh=mesh; node.position=Vector3((x-3)*24,0,(z-3)*32); node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; viewport.add_child(node); nodes.append(node)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	report={"gpu":RenderingServer.get_video_adapter_name(),"viewport":[1920,1080],"baseline_sha256":source.sha256_text(),"scope":"paired viewport GPU timer, no editor/sky/water/physics, same geometry and 2K PBR; two AB/BA rounds after 60 warmup frames; 100 samples per pass. 49_patches shares a mesh/material; 49_unique_patches uses distinct meshes/heightfields/material instances.","cases":{}}
	for view in ["grass_close","cliff_close","49_patches","49_unique_patches"]:
		var variants: Array=[]
		for i in nodes.size():
			nodes[i].visible=view.begins_with("49_") or i==24
			if view=="49_unique_patches":
				var varied:=record.duplicate(true)
				for at in varied.terrain_mesh.heights.size(): varied.terrain_mesh.heights[at]+=.25*sin(at*.17+i*.2)
				nodes[i].mesh=Terrain.mesh(varied,null)
				var varied_material:=River.terrain(varied); var varied_old: ShaderMaterial=varied_material.duplicate(); varied_old.shader=old_shader
				variants.append([varied_old,varied_material])
		if view=="grass_close": camera.position=Vector3(9,6,0); camera.look_at(Vector3(9,1.5,-4))
		elif view=="cliff_close": camera.position=Vector3(0,4,5); camera.look_at(Vector3(5,0,0))
		else: camera.position=Vector3(0,140,190); camera.look_at(Vector3.ZERO)
		var times:={"before":[],"after":[]}; var images:={}
		for pass_id in ["before","after","after","before"]:
			for i in nodes.size(): nodes[i].material_override=variants[i][0 if pass_id=="before" else 1] if not variants.is_empty() else (reference if pass_id=="before" else current)
			for i in 60: await process_frame
			for i in 100:
				await process_frame
				var ms:=RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
				if ms>0: times[pass_id].append(ms)
			await RenderingServer.frame_post_draw
			images[pass_id]=viewport.get_texture().get_image()
		var data:={}
		for pass_id in times:
			var values: Array=times[pass_id]; values.sort()
			check(values.size()==200,"GPU timer samples "+view+" "+pass_id)
			data[pass_id]={"median_ms":values[values.size()/2] if not values.is_empty() else 0,"p95_ms":values[int(values.size()*.95)] if not values.is_empty() else 0}
		data.draw_calls=RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		data.rendered_objects=RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		data.pixel_error=difference(images.before,images.after)
		check(data.pixel_error<.003,"same appearance within .003 mean channel error: "+str(data.pixel_error))
		images.after.save_png(OUTPUT.path_join("performance_"+view+".png"))
		report.cases[view]=data; print("TERRAIN_GPU ",view," ",JSON.stringify(data))
	report.texture_memory_mib=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.
	# A hot entry survives pressure; inserting the 129th no longer clears all peers.
	River.cache.clear(); var hot:=River.terrain(record)
	for i in 160:
		River.cached(River.cache.keys().filter(func(k):return k.begins_with("terrain:"))[0])
		River.water({"absorption":.01+i*.001,"shallow_color":[.2,.3,.4],"deep_color":[.1,.2,.3]},null)
	check(River.cache.size()==128 and River.terrain(record)==hot,"bounded LRU retains hot terrain across 160 inserts")
	var begin:=Time.get_ticks_usec()
	for i in 500: River.terrain(record)
	report.cached_material_lookup_ms=(Time.get_ticks_usec()-begin)/500000.
	report.failures=failures
	var f:=FileAccess.open(OUTPUT.path_join("performance.json"),FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("TERRAIN_PERFORMANCE_FINISHED failures=",failures); quit(1 if failures else 0)
func difference(a: Image,b: Image) -> float:
	var total:=0.; var count:=0
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4):
			var c:=a.get_pixel(x,y); var d:=b.get_pixel(x,y)
			total+=absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b); count+=3
	return total/count
