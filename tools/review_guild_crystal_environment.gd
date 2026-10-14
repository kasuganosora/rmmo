extends "res://tools/review_guild_reference_camera.gd"
## Frozen native model, fixed lighting/exposure, environment-only diagnostics.
## Sky-only is deliberately a diagnostic: it ignores room occlusion and is not
## approval to replace production interior reflections with outdoor lighting.

func gallery(scene:Node,folder:String)->void:
	var vp:=SubViewport.new();vp.size=Vector2i(1400,1000);vp.own_world_3d=true
	vp.msaa_3d=Viewport.MSAA_4X;vp.use_taa=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(vp);vp.add_child(scene)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.12,.15,.18)
	var sky:=Sky.new();var sm:=ProceduralSkyMaterial.new()
	sm.sky_top_color=Color(.25,.38,.57);sm.sky_horizon_color=Color(.72,.76,.80)
	sm.ground_bottom_color=Color(.18,.16,.13);sm.ground_horizon_color=Color(.65,.65,.64);sky.sky_material=sm;env.sky=sky
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.22
	env.tonemap_mode=Environment.TONE_MAPPER_ACES;env.tonemap_exposure=1
	env.ssao_enabled=true;env.ssao_radius=.7;env.ssao_intensity=1.2
	var world:=WorldEnvironment.new();world.environment=env;vp.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-28,0)
	sun.light_energy=1.5;sun.shadow_enabled=true;sun.directional_shadow_max_distance=500;vp.add_child(sun)
	var cam:=Camera3D.new();cam.current=true;cam.near=.02;cam.far=1000;cam.fov=35;vp.add_child(cam)
	var wd:=preload("res://scripts/world3d/world_document.gd").new()
	wd._namespace_asset(scene,'crystal_environment_review',scene)
	Components.apply(scene,{"kind":"asset","uuid":"crystal_environment_review"})
	var all:Array=[];gather(scene,all)
	for node in all:
		if node is MeshInstance3D and node.mesh!=null:
			preload("res://scripts/world3d/streetlamp_lights.gd").register(node)
	var weather:=ReviewWeather.new();weather.values.time_hours=12.;vp.add_child(weather)
	var lights:=preload("res://scripts/world3d/streetlamp_lights.gd").new()
	vp.add_child(lights);lights.weather=weather;lights.camera=cam
	var views:Array=[
		['crystal_front',Vector3(24.7,1.88,-8.95),Vector3(24.65,1.75,-10.4)],
		['crystal_side',Vector3(26,1.92,-9.7),Vector3(24.65,1.75,-10.4)]
	]
	var cases:Array=[
		{"id":"neutral_room","sky_background":false,"probe":"room","diagnostic_only":false},
		{"id":"sky_room","sky_background":true,"probe":"room","diagnostic_only":false},
		{"id":"sky_local","sky_background":true,"probe":"local","diagnostic_only":false},
		{"id":"sky_only","sky_background":true,"probe":"none","diagnostic_only":true}
	]
	report.review_environment={
		"size":[1400,1000],"msaa":4,"taa":true,"tone":"ACES","exposure":1,
		"ambient":.22,"sun_energy":1.5,"sun_rotation":[-38,-28,0],
		"ssao_radius":.7,"ssao_intensity":1.2,
		"fixed_controls":"All cases preserve source geometry, materials, emission, exposure, sun and production nearby light controller.",
		"changed_controls":"Background mode and reflection capture placement only; all captures refresh after scene/light readiness.",
		"limits":"No asset change, no formal map GI integration. Sky-only intentionally diagnoses missing reflection response and is not an interior lighting solution. TAA differs from original gallery, so comparisons are within this suite."
	}
	report.screenshots=[];report.environment_cases=[]
	for test_case:Dictionary in cases:
		env.background_mode=Environment.BG_SKY if test_case.sky_background else Environment.BG_COLOR
		var probe:ReflectionProbe
		var capture:Dictionary={"id":test_case.id,"sky_background":test_case.sky_background,"diagnostic_only":test_case.diagnostic_only}
		# Position the camera and refresh the actual production light selection
		# before adding the probe, to avoid baking a pre-light-controller state.
		cam.position=views[0][1];cam.look_at(views[0][2]);lights.refresh()
		for frame in 12:await process_frame;await RenderingServer.frame_post_draw
		if test_case.probe!='none':
			probe=ReflectionProbe.new();probe.name='CrystalEnvironmentProbe'
			probe.position=Vector3(16,4,-7) if test_case.probe=='room' else Vector3(24.65,2.1,-9.55)
			probe.size=Vector3(33,9,15) if test_case.probe=='room' else Vector3(5,4,5)
			probe.interior=true;probe.box_projection=true;probe.max_distance=40
			probe.ambient_mode=ReflectionProbe.AMBIENT_COLOR;probe.ambient_color=Color.WHITE;probe.ambient_color_energy=.22
			probe.update_mode=ReflectionProbe.UPDATE_ALWAYS;vp.add_child(probe)
			capture.probe={"position":vec(probe.position),"size":vec(probe.size),"box_projection":true,"interior":true,"update":"always","ambient_energy":.22}
		else:capture.probe={"mode":"none; outdoor sky reflection diagnostic"}
		report.environment_cases.append(capture)
		for view in views:
			cam.position=view[1];cam.look_at(view[2]);lights.refresh()
			# Warm the capture, reflection filtering and temporal AA after a move.
			for frame in 80:await process_frame;await RenderingServer.frame_post_draw
			var filename:String=test_case.id+'_'+view[0]+'.png'
			check(vp.get_texture().get_image().save_png(folder.path_join(filename))==OK,'capture '+filename)
			report.screenshots.append({"name":filename,"case":test_case.id,"eye":vec(view[1]),"aim":vec(view[2]),"fov":35,"taa":true,"nearby_lights":lights.lights.filter(func(l):return l.visible).size()})
		if probe!=null:
			probe.queue_free()
			for frame in 8:await process_frame;await RenderingServer.frame_post_draw
	report.gallery_completed=true
	vp.remove_child(scene);vp.queue_free()
	for frame in 8:await process_frame;await RenderingServer.frame_post_draw
