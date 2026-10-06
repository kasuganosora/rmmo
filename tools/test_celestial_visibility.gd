extends SceneTree
const Weather = preload("res://scripts/world3d/weather_controller.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const OUT = "D:/code/rmmo_runtime/review_artifacts/celestial_visibility_20261006"
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func capture(label: String) -> Image:
	for i in 35: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OUT.path_join(label+".png"))
	return image
func run() -> void:
	root.size=Vector2i(960,640); root.use_taa=false; Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute(OUT)
	var host:=Node3D.new(); root.add_child(host)
	var camera:=Camera3D.new(); host.add_child(camera); camera.current=true
	var sun:=DirectionalLight3D.new(); host.add_child(sun)
	var env:=Environment.new(); camera.environment=env
	var weather:=Weather.new(); host.add_child(weather); weather.bind(camera,sun,env)
	weather.process_mode=Node.PROCESS_MODE_DISABLED
	for cycle in [false,true]:
		for preset in ["day","night"]:
			weather.configure(Settings.updated({}, {"preset":preset,"celestial_cycle":cycle,"weather_transition":0.,"environment_audio":false}),true)
			var axis:Vector3=weather.sky_material.get_shader_parameter("moon_direction" if preset=="night" else "sun_direction")
			check(axis.y>0.,"visible hemisphere %s cycle=%s"%[preset,cycle])
			camera.look_at(camera.position+axis,Vector3.FORWARD)
			weather.sky_material.set_shader_parameter("cloud_cover",0.)
			weather.sky_material.set_shader_parameter("cirrus_amount",0.)
			var disc:=await capture("%s_%s_disc"%[preset,cycle])
			check(disc.get_pixel(480,320).get_luminance()>.5,"disc visible %s cycle=%s"%[preset,cycle])
			weather._apply()
			await capture("%s_%s_clouds"%[preset,cycle])
	var ground:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(40,40); ground.mesh=plane; host.add_child(ground)
	var box:=MeshInstance3D.new(); box.mesh=BoxMesh.new(); box.position=Vector3(0,.5,0); host.add_child(box)
	camera.position=Vector3(4,3,6); camera.look_at(Vector3.ZERO)
	weather.configure(Settings.updated({}, {"time_hours":22.,"celestial_cycle":true,"environment_audio":false}),true)
	var lit:=await capture("moonlit_ground")
	check(weather.moon.light_energy>.1 and weather.moon.shadow_enabled,"moon casts directional light and shadows")
	weather.moon.light_energy=0.
	var dark:=await capture("without_moonlight")
	check(lit.get_data()!=dark.get_data(),"moonlight changes ground pixels")
	host.free(); print("CELESTIAL_VISIBILITY failures=",failures); quit(1 if failures else 0)
