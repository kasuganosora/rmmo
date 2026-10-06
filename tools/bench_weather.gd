extends SceneTree
## Optional baseline: git show HEAD:scripts/map/weather_fx.gd > ._weather_baseline.gd
## Measures script update cost only; excludes renderer and particle simulation.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var weather = load("res://scripts/map/weather.gd")
	for path in ["res://._weather_baseline.gd", "res://scripts/map/weather_fx.gd"]:
		if not FileAccess.file_exists(path):
			continue
		var fx = load(path).new()
		root.add_child(fx)
		fx.set_process(false)
		for kind in ["clear", "rain", "storm", "snow", "fog"]:
			fx.apply(weather.compose(0, kind, 1.0, false))
			fx._process(5.0)
			var start := Time.get_ticks_usec()
			for i in range(10000):
				fx._process(0.0)
				fx.display_modulate()
			print("BENCH ", path, " ", kind, " us/update=", float(Time.get_ticks_usec() - start) / 10000.0)
		fx.free()
	quit()
