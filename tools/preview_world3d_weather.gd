extends SceneTree
## Read-only art review of an external map. Never writes the source map or its assets.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
var output := "weather3d"

func _init() -> void: call_deferred("run")

func run() -> void:
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): path = arg.trim_prefix("--map=")
	if DisplayServer.get_name() == "headless" or not Paths.allowed(path):
		push_error("Use the background GPU runner and --map=<existing external map>"); quit(1); return
	var doc = preload("res://scripts/world3d/world_document.gd").open_file(path)
	if doc == null: quit(1); return
	root.size = Vector2i(1440,960); root.content_scale_size = root.size
	var host := Node3D.new(); root.add_child(host)
	var map: Node3D = doc.build(); host.add_child(map)
	preload("res://scripts/world3d/world_stream.gd").sync(map,host,Vector3.ZERO)
	var camera := Camera3D.new(); camera.position = Vector3(14,4.8,19); host.add_child(camera)
	camera.look_at(Vector3(0,3.4,0)); camera.current = true; camera.fov = 60
	var environment := Environment.new(); camera.environment = environment
	var sun := DirectionalLight3D.new(); host.add_child(sun)
	var weather := preload("res://scripts/world3d/weather_controller.gd").new(); weather.editor_preview = true
	host.add_child(weather); weather.bind(camera,sun,environment)
	for kind in ["clear","rain","storm","snow","fog"]:
		var values := Settings.updated(doc.map_meta,{"weather":kind,"weather_intensity":.9,"weather_transition":0,"sky_enabled":true,"lightning_enabled":false})
		weather.configure(values,true)
		for frame in 165: await physics_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var target := preload("res://scripts/asset/art_paths.gd").review_path(output+"/art_"+kind+".png")
		image.save_png(target); print("preview="+target)
	for preset in ["day","sunset","night"]:
		weather.configure(Settings.updated(doc.map_meta,{"preset":preset,"weather":"clear","sky_enabled":true}),true)
		for frame in 90: await physics_frame
		await RenderingServer.frame_post_draw
		var target := preload("res://scripts/asset/art_paths.gd").review_path(output+"/art_sky_"+preset+".png")
		root.get_texture().get_image().save_png(target); print("preview="+target)
	host.free(); quit()
