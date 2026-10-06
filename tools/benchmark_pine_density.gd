extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/pine_density/"
func _initialize()->void:run.call_deferred()
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var proof=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/pine_dense_v3_game/published.json"))
	var vp=SubViewport.new();vp.size=Vector2i(1280,720);vp.own_world_3d=true;vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.4,.55,.7);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.5;vp.add_child(env)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.shadow_enabled=true;vp.add_child(sun)
	var floor_=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(180,180);floor_.mesh=plane;vp.add_child(floor_)
	var cam=Camera3D.new();cam.position=Vector3(0,6,35);vp.add_child(cam);cam.look_at(Vector3(0,4,-40))
	var wind=preload("res://scripts/world3d/wind_runtime.gd").new();vp.add_child(wind);wind.camera=cam;wind.set_physics_process(false)
	var source=Library.instantiate_preview(proof.items[1].entry.asset_path)
	for z in 16:
		for x in 16:
			var tree=source.duplicate();tree.position=Vector3((x-7.5)*7,0,-z*7);tree.rotation.y=fmod(x*2.17+z*.83,TAU);vp.add_child(tree)
			for mesh in Paint.meshes(tree):preload("res://scripts/world3d/wind_response.gd").register(mesh)
	source.free();wind.refresh()
	if OS.get_cmdline_user_args().has("--legacy-shader"):
		var replacements={}
		for row in wind.receivers.values():
			for material in row.materials:
				var original=material.shader
				if not replacements.has(original):
					var code=original.code
					var start=code.find("\t\t// bend depends")
					var end=code.find("\t\tVERTEX += d;",start)
					var old="\t\tmat3 jacobian = mat3(vec3(1.,0.,0.)+(bend(VERTEX+vec3(e,0.,0.),local_force,local_flutter,phase,speed)-d)/e, vec3(0.,1.,0.)+(bend(VERTEX+vec3(0.,e,0.),local_force,local_flutter,phase,speed)-d)/e, vec3(0.,0.,1.)+(bend(VERTEX+vec3(0.,0.,e),local_force,local_flutter,phase,speed)-d)/e);\n\t\tif (abs(determinant(jacobian)) > .0001) NORMAL = normalize(transpose(inverse(jacobian))*NORMAL);\n\t\tif (length(TANGENT) > .001) TANGENT = normalize(jacobian*TANGENT);\n\t\tif (length(BINORMAL) > .001) BINORMAL = normalize(jacobian*BINORMAL);\n"
					assert(start>=0 and end>start)
					var shader=Shader.new();shader.code=code.substr(0,start)+old+code.substr(end);replacements[original]=shader
				material.shader=replacements[original]
	for i in 90:wind.advance(Vector3(3,0,0),i*.016);await process_frame
	var refresh_times=[];var update_times=[];var frames=[];var gpu=[]
	for i in 120:
		var t=Time.get_ticks_usec();wind.advance(Vector3(3,0,0),i*.016);update_times.append((Time.get_ticks_usec()-t)/1000.)
		if i%10==0:
			t=Time.get_ticks_usec();wind.refresh();refresh_times.append((Time.get_ticks_usec()-t)/1000.)
		t=Time.get_ticks_usec();await process_frame;frames.append((Time.get_ticks_usec()-t)/1000.)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	frames.sort();refresh_times.sort();update_times.sort()
	# before.json/png are the captured pre-change baseline, never overwrite them.
	var label="after"
	if OS.get_cmdline_user_args().has("--legacy-shader"):label="legacy_shader"
	await RenderingServer.frame_post_draw;vp.get_texture().get_image().save_png(OUT+label+".png")
	var result={"trees":256,"bound_receivers":wind.receivers.size(),"refresh_median_ms":refresh_times[6],"advance_median_ms":update_times[60],"frame_wait_median_ms":frames[60],"frame_wait_p95_ms":frames[114],"draw_calls":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"note":"1280x720 MSAA4 TAA, frame waits include scheduling, synthetic scene, no user map edits"}
	gpu.sort();result.gpu_median_ms=gpu[60];result.gpu_p95_ms=gpu[114]
	result.active_receivers=wind.receivers.values().filter(func(r):return wind._range_active(r.node.get_ref())).size()
	var f=FileAccess.open(OUT+label+".json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close();print(result);quit()
