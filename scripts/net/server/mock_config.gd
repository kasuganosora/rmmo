extends RefCounted
## Simulation tuning is independent of the transport's real-server settings.
## Bounds keep invalid project settings from disabling timers or busy-looping.
const SETTINGS := {
	"latency_sec": [0.35, 0.0, 30.0],
	"ai_tick_interval_sec": [0.45, 0.01, 30.0],
	"combat_tick_interval_sec": [1.5, 0.01, 30.0],
	"chunk_view_radius_m": [12.0, 1.0, 1024.0],
}

static func number(key: String) -> float:
	var bounds: Array = SETTINGS[key]
	var value: Variant = ProjectSettings.get_setting("rmmo/mock/" + key, bounds[0])
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return float(bounds[0])
	if not is_finite(float(value)):
		return float(bounds[0])
	return clampf(float(value), float(bounds[1]), float(bounds[2]))
