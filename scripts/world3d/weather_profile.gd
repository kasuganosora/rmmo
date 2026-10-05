extends RefCounted
## Meter-space art direction, independent of the retired CanvasLayer weather.
const KINDS := ["clear", "rain", "storm", "snow", "fog"]
const LABELS := ["晴朗", "下雨", "雷暴", "飘雪", "浓雾"]
const PROFILES := {
	"clear": [0.0, 0.0, .18, 1.0, 0.0],
	"rain": [1.0, 0.0, .78, .58, .009],
	"storm": [1.0, 0.0, .98, .28, .018],
	"snow": [0.0, 1.0, .72, .68, .014],
	"fog": [0.0, 0.0, .82, .56, .052],
}

static func sample(values: Dictionary) -> Dictionary:
	var kind: String = values.get("weather", "clear")
	var p: Array = PROFILES[kind]
	var amount: float = values.get("weather_intensity", .7)
	var angle := deg_to_rad(float(values.get("wind_direction", 25)))
	var speed: float = values.get("wind_speed", 2.5)
	return {"rain": float(p[0]) * amount, "snow": float(p[1]) * amount,
		"cloud": lerpf(.18, p[2], amount), "sun": lerpf(1, p[3], amount),
		"fog": float(p[4]) * amount, "storm": amount if kind == "storm" else 0.0,
		"wind": Vector3(cos(angle), 0, sin(angle)) * speed}

static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var out := {}
	for key in b: out[key] = a[key].lerp(b[key], weight) if b[key] is Vector3 else lerpf(a[key], b[key], weight)
	return out

static func encode(profile: Dictionary) -> Dictionary:
	var out := profile.duplicate(true); var wind: Vector3 = out.wind
	out.wind = [wind.x,wind.y,wind.z]; return out

static func decode(profile: Dictionary) -> Dictionary:
	var out := profile.duplicate(true); out.wind = Vector3(out.wind[0],out.wind[1],out.wind[2]); return out

static func at(state: Dictionary, now: float) -> Dictionary:
	var duration: float = state.environment.weather_transition
	var weight := clampf((now-float(state.transition_at))/maxf(.001,duration),0,1) if duration > 0 else 1.0
	return blend(decode(state.source_profile),sample(state.environment),weight*weight*(3-2*weight))

static func gust(time: float) -> float: return .82+.12*sin(time*.7)+.06*sin(time*1.9)

static func gust_integral(a: float, b: float) -> float:
	return .82*(b-a)-.12/.7*(cos(b*.7)-cos(a*.7))-.06/1.9*(cos(b*1.9)-cos(a*1.9))

static func drift_at(state: Dictionary, now: float) -> Vector2:
	var start: float = state.transition_at
	var end := minf(now,start+float(state.environment.weather_transition))
	var displacement := Vector3.ZERO
	var duration:float=state.environment.weather_transition
	var target_wind:Vector3=sample(state.environment).wind
	# Fixed quadrature is shared by server and clients, independent of frame rate.
	if end > start:
		var source_wind:Vector3=decode(state.source_profile).wind
		var step := (end-start)/16.0
		for i in 16:
			var t := start+(i+.5)*step
			# Only wind participates in this integral. Reuse the two endpoints
			# instead of rebuilding and blending entire weather dictionaries 16 times.
			var weight:=clampf((t-start)/maxf(.001,duration),0,1) if duration>0 else 1.0
			displacement += source_wind.lerp(target_wind,weight*weight*(3-2*weight))*gust(t)*step
	if now > end: displacement += target_wind*gust_integral(maxf(start,end),now)
	return Vector2(state.wind_origin[0],state.wind_origin[1])+Vector2(displacement.x,displacement.z)*.0006
