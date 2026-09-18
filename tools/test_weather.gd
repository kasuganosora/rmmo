extends SceneTree
## Daylight × weather compose, MapField fx, mock server, event op.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var Weather = load("res://scripts/map/weather.gd")
	var MapExt = load("res://scripts/map/map_ext.gd")
	var ContentPack = load("res://scripts/editor/content_pack.gd")
	var MapField = load("res://scripts/map/map_field.gd")
	var MockServer = load("res://scripts/net/mock_server.gd")
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")

	failed += _expect(Weather.normalize("雨") == "rain", "normalize rain")
	var day: Color = MapExt.light_modulate(0)
	var night: Color = MapExt.light_modulate(2)
	var day_clear: Dictionary = Weather.compose(0, "clear", 0.0, false)
	var day_rain: Dictionary = Weather.compose(0, "rain", 1.0, false)
	var night_rain: Dictionary = Weather.compose(2, "rain", 1.0, false)
	var day_m: Color = day_clear["modulate"]
	var rain_m: Color = day_rain["modulate"]
	var nr_m: Color = night_rain["modulate"]
	failed += _expect(day_m.is_equal_approx(day), "clear = daylight")
	failed += _expect(not rain_m.is_equal_approx(day_m), "day×rain != day")
	failed += _expect(not rain_m.is_equal_approx(Color(0.78, 0.84, 0.92, 1)), "day×rain != raw tint")
	failed += _expect(nr_m.b > nr_m.r, "night×rain stays bluish")
	failed += _expect(nr_m.v < night.v, "night×rain darker than night")
	var indoor_rain: Dictionary = Weather.compose(0, "rain", 1.0, true)
	failed += _expect(str(indoor_rain.get("kind", "")) == "clear", "indoor visual clear")
	failed += _expect((indoor_rain.get("modulate") as Color).is_equal_approx(day), "indoor rain = daylight")
	failed += _expect(str(indoor_rain.get("particles", "x")) == "", "indoor no particles")

	var pack = ContentPack.new()
	pack.new_blank("wx_pack", "天气", 16, 16)
	pack.save_dir()
	var doc = pack.get_map("Map001")
	doc.environment = MapExt.ENV_OUTDOOR
	pack.save_dir()
	var field: Node2D = MapField.new()
	root.add_child(field)
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = doc
	field.pack_path = pack.root
	field.edit_map_id = "Map001"
	field.rebuild()
	var atm: Dictionary = field.set_atmosphere(0, "rain", 1.0)
	failed += _expect(str(atm.get("kind", "")) == "rain", "outdoor field rain")
	failed += _expect(str(atm.get("particles", "")) == "rain", "rain particles on")
	failed += _expect(field.get_node_or_null("WeatherFx") != null, "WeatherFx on MapField")
	failed += _expect(FileAccess.file_exists("res://assets/fx/weather_rain.png"), "rain sprite")
	failed += _expect(FileAccess.file_exists("res://assets/fx/weather_snow.png"), "snow sprite")
	failed += _expect(FileAccess.file_exists("res://assets/fx/weather_storm.png"), "storm sprite")
	failed += _expect(FileAccess.file_exists("res://assets/fx/weather_fog.png"), "fog sprite")
	doc.environment = MapExt.ENV_INDOOR
	var atm_in: Dictionary = field.set_atmosphere(0, "rain", 1.0)
	failed += _expect(str(atm_in.get("kind", "")) == "clear", "indoor field clears rain")
	failed += _expect(str(atm_in.get("particles", "")) == "", "indoor no particle kind")

	doc.environment = MapExt.ENV_OUTDOOR
	field.set_atmosphere(0, "rain", 1.0)
	var fx = field.get_node_or_null("WeatherFx")
	failed += _expect(fx != null, "fx after rain")
	if fx:
		fx._process(Weather.transition_sec())
		fx.set_eaves(true)
		failed += _expect(bool(fx._eaves), "eaves hides precip")
		failed += _expect(not bool(fx._rain.emitting), "rain off under eaves")
		fx.set_eaves(false)
		failed += _expect(bool(fx._rain.emitting), "rain back")

	# Kind change blends instead of snapping the map tint / particles.
	field.set_atmosphere(0, "rain", 1.0)
	var rain_mod: Color = field.weather_display_modulate()
	field.set_atmosphere(0, "snow", 1.0)
	failed += _expect(fx.mix_t() < 0.05, "blend starts at 0")
	var mid_mod: Color = field.weather_display_modulate()
	failed += _expect(mid_mod.is_equal_approx(rain_mod), "tint still previous at mix 0")
	var b0: Dictionary = fx.blended()
	failed += _expect(float(b0.get("rain_weight", 0.0)) > 0.5, "rain still dominant at start")
	failed += _expect(float(b0.get("snow_weight", 1.0)) < 0.2, "snow not full yet")
	fx._process(Weather.transition_sec() * 0.5)
	failed += _expect(fx.mix_t() > 0.4 and fx.mix_t() < 0.7, "half blend")
	var b1: Dictionary = fx.blended()
	failed += _expect(float(b1.get("rain_weight", 0.0)) > 0.15, "crossfade keeps rain")
	failed += _expect(float(b1.get("snow_weight", 0.0)) > 0.15, "crossfade brings snow")
	var half_mod: Color = field.weather_display_modulate()
	failed += _expect(not half_mod.is_equal_approx(rain_mod), "map tint eased")
	fx._process(Weather.transition_sec())
	failed += _expect(fx.mix_t() >= 0.999, "blend completes")
	var b2: Dictionary = fx.blended()
	failed += _expect(float(b2.get("snow_weight", 0.0)) > 0.5, "snow wins")
	failed += _expect(float(b2.get("rain_weight", 1.0)) < 0.05, "rain faded")
	failed += _expect(bool(fx._snow.emitting), "snow emitting after blend")

	var srv = MockServer.new()
	root.add_child(srv)
	srv.weather_auto = false
	srv.map_environment = MapExt.ENV_OUTDOOR
	var wset: Dictionary = srv.set_weather("storm", 0.9, 30.0)
	failed += _expect(str(wset.get("type", "")) == "weather", "server action")
	failed += _expect(str(srv.get_weather().get("kind", "")) == "storm", "server storm")
	srv.map_environment = MapExt.ENV_INDOOR
	srv.set_weather("rain", 1.0, 10.0)
	failed += _expect(str(srv.get_weather().get("kind", "")) == "clear", "server indoor lock")

	srv.map_environment = MapExt.ENV_OUTDOOR
	var rt = EventRuntime.new()
	var ctx := {"weather_cb": Callable(srv, "set_weather")}
	var acts: Array = rt._run_commands("ev_w", [{"op": "weather", "kind": "snow", "intensity": 0.6}], ctx)
	var has_w := false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "weather":
			has_w = str(a.get("kind", "")) == "snow"
	failed += _expect(has_w, "event weather op")
	failed += _expect(str(srv.weather_kind) == "snow", "event set server")

	failed += _expect(Weather.CANVAS_ATMOSPHERE < Weather.CANVAS_HUD, "atmosphere canvas < HUD")
	var fx_layer := int(fx.layer) if fx else -1
	failed += _expect(fx_layer == Weather.CANVAS_ATMOSPHERE, "WeatherFx layer=%d" % fx_layer)
	failed += _expect(fx_layer < Weather.CANVAS_HUD, "weather below HUD")
	var world_sc: PackedScene = load("res://scenes/world.tscn")
	var world_n: Node = world_sc.instantiate()
	var hud_cl: CanvasLayer = world_n.get_node_or_null("CanvasLayer") as CanvasLayer
	failed += _expect(hud_cl != null, "world HUD CanvasLayer")
	failed += _expect(hud_cl != null and int(hud_cl.layer) == Weather.CANVAS_HUD, "HUD canvas %d" % Weather.CANVAS_HUD)
	failed += _expect(hud_cl != null and fx_layer < int(hud_cl.layer), "weather layer under HUD layer")
	failed += _expect(world_n.get_node_or_null("MapLight") == null, "no viewport-wide CanvasModulate")
	world_n.free()

	field.free()
	srv.queue_free()
	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED %d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS %s" % label)
		return 0
	print("FAIL %s" % label)
	return 1
