extends "res://tools/test_world3d_mcp.gd"
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Weather = preload("res://scripts/world3d/weather_controller.gd")
const Particles = preload("res://scripts/world3d/weather_precipitation.gd")
const Net = preload("res://scripts/net/net.gd")
const Review = preload("res://scripts/asset/art_paths.gd")

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Weather test timed out"); quit(2))
	root.size = Vector2i(1280,800); root.content_scale_size = root.size
	var directory := Paths.cache_directory("weather_test_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	var path := directory.path_join("map.gltf")
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0,-.2,0), Vector3(100,.4,100))
	doc.add_box("roof", Vector3(0,3.2,0), Vector3(6,.25,6))
	doc.add_box("wall", Vector3(-3,1.5,0), Vector3(.25,3,6))
	check(doc.save(path) == OK, "save isolated weather fixture")
	Net.session().world3d_editor_path = path; Net.session().world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled = false
	var probe := TCPServer.new()
	while probe.listen(port,"127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).ok, "start actual 3D HTTP MCP")
	await rpc("initialize", {"protocolVersion":"2025-03-26", "capabilities":{}, "clientInfo":{"name":"weather-test", "version":"1"}})
	var discovery := await rpc("tools/list")
	var spec: Dictionary = discovery.result.tools.filter(func(t): return t.name == "set_environment")[0]
	check(spec.inputSchema.properties.weather.enum == ["clear","rain","storm","snow","fog"] and spec.inputSchema.properties.wind_speed.maximum == 18, "discover shared weather schema over HTTP")
	check(not discovery.result.tools.any(func(t): return t.name == "set_map_weather"), "no retired 2D tools registered")
	var initial := await call_tool("get_environment")
	check(initial.environment.weather == "clear", "old maps resolve to clear weather")
	var before := doc.recovery_snapshot(); var history: int = doc._undo.size()
	for invalid in [{"weather":"hail"}, {"weather_intensity":1.01}, {"weather_intensity":"rain"}, {"wind_speed":-1}, {"wind_direction":181}, {"weather_transition":21}, {"lightning_enabled":1}, {"sky_enabled":"yes"}]:
		await call_tool("set_environment", invalid, false)
	check(doc.recovery_snapshot() == before and doc._undo.size() == history, "invalid weather calls leave document and undo stack intact")
	var result := await call_tool("set_environment", {"weather":"rain", "weather_intensity":.8, "wind_speed":4.5, "wind_direction":90, "weather_transition":0})
	check(doc._undo.size() == history+1 and editor._weather.current.rain == .8, "one transaction applies actual world-space rain")
	check(editor._environment_panel.form.fields.weather.get_selected_metadata() == "rain" and is_equal_approx(editor._environment_panel.form.fields.wind_speed.value,4.5), "HTTP edits synchronize environment panel")
	await call_tool("undo"); check(editor._weather.current.rain == 0 or editor._weather.target.rain == 0, "undo restores clear weather target")
	await call_tool("redo"); check(equivalent(Settings.resolve(doc.map_meta),result.environment), "redo restores complete weather record")
	editor._environment_panel.form.fields.weather_intensity.value = .65
	editor._environment_panel.apply()
	check(is_equal_approx(editor._weather.current.rain,.65), "UI uses same validated weather operation")
	await call_tool("undo")
	await call_tool("save_world")
	await call_tool("set_environment", {"weather":"snow"})
	await call_tool("open_world", {"path":path, "discard_changes":true})
	check(equivalent(Settings.resolve(editor._doc.map_meta),result.environment) and editor._weather.current.rain == .8, "save/reopen restores authored weather immediately")
	var rig = editor._weather
	rig.set_process(false); rig.precipitation.set_physics_process(false)
	var rain_config := Settings.updated({}, {"weather":"rain", "weather_intensity":1, "weather_transition":2})
	rig.configure(Settings.defaults(),true); rig.configure(rain_config); rig._process(.8)
	var midway: Dictionary = rig.current.duplicate(true)
	rig.configure(Settings.updated({}, {"weather":"snow", "weather_intensity":1, "weather_transition":2}))
	check(rig.source == midway and rig.current == midway, "interrupted rain-to-snow transition starts at current visual state")
	rig._process(.3); var elapsed: float = rig.mix_time
	rig.configure(rig.values)
	check(rig.mix_time == elapsed, "repeated target does not restart transition")
	rig._process(3); check(rig.current.snow == 1 and rig.current.rain == 0, "transition finishes at exact target")
	rig.configure(rain_config,true)
	editor._camera.position = Vector3(0,1.5,0)
	await physics_frame; await physics_frame
	rig.shelter_tick = 0; rig._physics_process(.2)
	check(rig.sheltered, "camera under roof is sheltered using physical geometry")
	var fx = rig.precipitation
	fx.clear(); fx.last_anchor = editor._camera.global_position
	fx.drops.append(Particles.Drop.new(0,Vector3(0,3.7,0),2,0,1))
	fx.simulate(.067)
	check(fx.hit_count > 0 and not fx.splashes.is_empty() and fx.splashes[0].p.y > 3.3, "swept rain hits thin roof and spawns surface-aligned ripple")
	var roof = editor._view.get_node(NodePath(editor._doc.records[1].uuid))
	roof.hide(); await physics_frame
	check(not fx.cast(Vector3(0,5,0),Vector3(0,1,0)).is_empty(), "runtime-style visual cutaway keeps physical rain shelter")
	roof.show()
	for frame in 45: fx.simulate(1.0/30.0)
	check(not fx.drops.any(func(d): return absf(d.p.x)<2.8 and absf(d.p.z)<2.8 and d.p.y<3.05), "no rain births or leaks under the roof")
	check(fx.drops.size() <= fx.LIMIT_RAIN+fx.LIMIT_SNOW and fx.splashes.size() <= fx.LIMIT_SPLASH, "particle and splash counts stay bounded")
	var positions: Array = fx.drops.map(func(d): return d.p)
	editor._camera.rotate_y(1.2)
	check(fx.drops.map(func(d): return d.p) == positions, "camera rotation never rotates or translates existing precipitation")
	rig.editor_preview = false
	var game_settings = root.get_node("GameSettings")
	var old_fx: bool = game_settings.weather_fx
	game_settings.weather_fx = false; rig._settings_changed()
	check(fx.drops.is_empty() and fx.batches[0].multimesh.visible_instance_count == 0 and not rig.audio.playing and rig.flash.light_energy == 0, "weather effect preference immediately clears particles, lightning and sound")
	game_settings.weather_fx = old_fx; rig.editor_preview = true; rig._settings_changed()
	rig.configure(Settings.updated({}, {"weather":"storm", "weather_intensity":1, "weather_transition":0}),true)
	var lightning_stamp:float=rig.night_sky.local_time()
	rig.preview_sky.lightning("editor-preview",{"id":"weather-test-strike","start_at":lightning_stamp,"position":[0.,0.,8.],"height":80.,"seed":42,"energy":1.})
	rig.sky_poll=0; rig._process(.01)
	check(rig.flash.light_energy > 0, "storm flash illuminates 3D geometry")
	rig.configure(Settings.updated({}, {"weather":"storm", "lightning_enabled":false, "weather_transition":0})); rig._process(.01)
	check(rig.flash.light_energy == 0, "lightning switch disables flash")
	rig.configure(Settings.updated({}, {"weather":"clear", "sky_enabled":false, "weather_transition":0})); rig._process(.01)
	check(not rig.environment.fog_enabled and is_equal_approx(rig.sun.light_energy,1.15) and rig.environment.background_mode == Environment.BG_COLOR, "clear weather restores authored lighting and optional plain background")
	if DisplayServer.get_name() != "headless":
		await capture_gallery(rig)
	editor.queue_free(); await settle()
	if DisplayServer.get_name() != "headless":
		preload("res://tools/world3d_test_character.gd").ensure(self)
		Net.session().world3d_map_path = path; Net.session().world3d_spawn = Vector3(8,.9,0)
		var live = load("res://scenes/world_3d.tscn").instantiate(); root.add_child(live)
		while not live.is_world_ready(): await process_frame
		check(live._weather != null and live._weather.values.weather == "rain" and live._weather.camera == live._camera.camera, "production scene binds saved weather to actual gameplay camera")
		var config: Dictionary = live._weather.values.duplicate(true)
		check(not live.set_weather("invalid",1).ok and config == live._weather.values, "runtime invalid weather has no side effects")
		check(live.set_weather("snow",.5).ok and live._weather.target.snow == .5, "runtime weather changes share profile and transition")
		live.set_night(true)
		check(live._weather.values.weather == "snow" and live._weather.values.preset == "night", "changing day/night preserves runtime weather")
		var destination := Doc.new(); destination.add_box("ground",Vector3(0,-.2,0),Vector3(30,.4,30))
		var destination_path := directory.path_join("next/map.gltf"); destination.save(destination_path)
		check(await live.transfer_map(destination_path,Vector3(0,.9,0)), "transfer to isolated clear map")
		check(live._weather.current.rain == 0 and live._weather.current.snow == 0 and live._weather.precipitation.drops.is_empty(), "map transfer clears prior weather particles and target")
		live.queue_free(); await settle()
	Net.session().world3d_editor_doc = null; Net.session().world3d_editor_path = ""
	if failed == 0: Io._remove_tree(directory)
	else: print("fixture="+directory)
	print("test_world3d_weather: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)

func capture_gallery(rig: Node3D) -> void:
	# An independent authored house gives depth, eaves, and a readable street horizon.
	var parameters: Dictionary = preload("res://scripts/world3d/building_blueprint.gd").medieval_presets()[0].parameters.duplicate(true)
	await call_tool("generate_buildings", {"parameters":parameters, "placements":[{"position":[11,0,-8]}]})
	editor._camera.position = Vector3(17,5,20); editor._camera.look_at(Vector3(6,3,-4)); editor._camera.fov = 65
	var fx = rig.precipitation
	for kind in ["clear","rain","storm","snow","fog"]:
		rig.configure(Settings.updated({}, {"weather":kind,"weather_intensity":.9,"weather_transition":0}),true)
		var samples: Array[int] = []
		for frame in 90:
			await physics_frame
			rig._process(1.0/30.0)
			if kind in ["rain","storm","snow"]: fx.simulate(1.0/30.0); samples.append(fx.last_step_usec)
		await RenderingServer.frame_post_draw
		var shot: Image = editor._canvas.get_child(0).get_texture().get_image()
		var output := Review.review_path("weather3d/"+kind+".png"); shot.save_png(output); print("preview="+output)
		if not samples.is_empty():
			samples.sort(); print("weather CPU step %s: median=%dus p95=%dus particles=%d" % [kind,samples[samples.size()/2],samples[int(samples.size()*.95)],fx.drops.size()])
		check(shot.get_width() > 500, "GPU renders " + kind + " preview")
	# Regress depth: an opaque wall must cover a bright world-space snowflake.
	rig.configure(Settings.updated({}, {"weather":"snow", "weather_transition":0}),true)
	fx.clear()
	fx.drops.append(Particles.Drop.new(1,Vector3(-4,1.5,0),2,0,18)); fx.drops[0].age = 1
	editor._camera.position = Vector3(1,1.5,0); editor._camera.look_at(Vector3(-4,1.5,0))
	fx._draw(editor._camera.position)
	await settle(); await RenderingServer.frame_post_draw
	var hidden: Image = editor._canvas.get_child(0).get_texture().get_image()
	fx.drops[0].p = Vector3(-1,1.5,0); fx.drops[0].previous = fx.drops[0].p; fx._draw(editor._camera.position)
	await settle(); await RenderingServer.frame_post_draw
	var visible: Image = editor._canvas.get_child(0).get_texture().get_image()
	var center := hidden.get_size()/2
	check(visible.get_pixelv(center).get_luminance() > hidden.get_pixelv(center).get_luminance()+.12, "GPU depth occludes snow behind walls, shows it in front")
