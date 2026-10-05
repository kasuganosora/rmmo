extends SceneTree
## Real renderer regression: zero-energy lights must not spend shadow draws.
const Weather = preload("res://scripts/world3d/weather_controller.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const OUT = "D:/code/rmmo_runtime/review_artifacts/celestial_shadows_20261006"
var failed := 0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failed+=1
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(480,320)
	# Disable temporal jitter only in this pixel comparison fixture. The real
	# town benchmark keeps the player's normal TAA/MSAA and graphics settings.
	root.use_taa=false
	var host:=Node3D.new();root.add_child(host)
	var sun:=DirectionalLight3D.new();host.add_child(sun)
	var camera:=Camera3D.new();host.add_child(camera);camera.position=Vector3(0,8,14);camera.look_at(Vector3.ZERO);camera.current=true
	var env:=Environment.new();camera.environment=env
	var weather:=Weather.new();host.add_child(weather);weather.bind(camera,sun,env)
	weather.process_mode=Node.PROCESS_MODE_DISABLED
	for cycle in [false,true]:
		for shadows in [false,true]:
			for hour in [0.,5.8,6.,6.1,12.,17.9,18.,18.1,24.]:
				var config:=Settings.updated({}, {"celestial_cycle":cycle,"time_hours":hour,"sun_shadows":shadows,"sky_enabled":false})
				weather.configure(config,true)
				check(sun.shadow_enabled==(shadows and sun.light_energy>0) and weather.moon.shadow_enabled==(shadows and weather.moon.light_energy>0),"cycle=%s shadows=%s hour=%s energy=(%s,%s)"%[cycle,shadows,hour,sun.light_energy,weather.moon.light_energy])
	# Compare the production state against the old two-shadow-light behavior.
	# With both energies zero the image must be byte-identical, not just similar.
	weather.configure(Settings.updated({}, {"celestial_cycle":false,"sun_energy":0.,"sky_enabled":false,"ambient_occlusion":false}),true)
	for z in 12:
		for x in 12:
			var box:=MeshInstance3D.new();box.mesh=BoxMesh.new();box.position=Vector3(x-6,0,z-6);host.add_child(box)
	if DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(OUT)
		var images:Array[Image]=[];var calls:Array=[]
		for legacy in [true,false]:
			if legacy:sun.shadow_enabled=true;weather.moon.shadow_enabled=true
			else:weather._apply()
			for i in 40:await process_frame
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();images.append(image)
			image.save_png(OUT+("/zero_legacy.png" if legacy else "/zero_fixed.png"))
			calls.append(root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		check(calls[0]>0 and calls[1]==0,"shadow draws eliminated: "+str(calls))
		check(images[0].get_data()==images[1].get_data(),"zero-energy shadow removal preserves exact rendered pixels")
		# Active sunlight still casts visible shadows after the optimization.
		var ground:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30);ground.mesh=plane;ground.position.y=-.5;host.add_child(ground)
		weather.configure(Settings.updated({}, {"celestial_cycle":false,"sun_energy":1.,"sky_enabled":false,"ambient_occlusion":false}),true)
		for i in 40:await process_frame
		await RenderingServer.frame_post_draw
		var lit:=root.get_texture().get_image();lit.save_png(OUT+"/active_shadows.png")
		check(root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)>0,"active sunlight retains shadow draws")
		sun.shadow_enabled=false
		for i in 10:await process_frame
		await RenderingServer.frame_post_draw
		check(lit.get_data()!=root.get_texture().get_image().get_data(),"active shadow changes are visible on the ground")
	host.free();print("CELESTIAL_SHADOW_WORK_FINISHED failures=",failed);quit(1 if failed else 0)
