extends RefCounted
## Authored, continuous 24h cycle; no geographical/astronomical ephemeris implied.
const Settings = preload("res://scripts/world3d/environment_settings.gd")

static func hours(packet: Dictionary, stamp: float) -> float:
	return fposmod(float(packet.time_of_day_hours)+maxf(0,stamp-float(packet.server_time))*float(packet.time_speed)/3600.,24.)

static func sample(hour: float) -> Dictionary:
	hour=fposmod(hour,24.)
	var keys: Array[float]=[0.,5.,6.,8.,12.,16.,18.,20.,24.]
	var phases: Array[String]=["night","night","sunset","day","day","day","sunset","night","night"]
	var index:=0
	while index<keys.size()-2 and hour>keys[index+1]: index+=1
	var weight:=smoothstep(keys[index],keys[index+1],hour)
	var a:Dictionary=Settings.PRESETS[phases[index]]; var b:Dictionary=Settings.PRESETS[phases[index+1]]
	var result:Dictionary={}
	for key in ["sun_color","ambient_color","background_color"]:
		result[key]=Settings.color(a[key]).lerp(Settings.color(b[key]),weight)
	for key in ["sun_energy","ambient_energy"]: result[key]=lerpf(a[key],b[key],weight)
	var angle:float=(hour-6.)/24.*TAU
	var direction:=Vector3(cos(angle),sin(angle),sin(angle)*.28).normalized()
	var day:=smoothstep(-.10,.16,direction.y)
	result.sun_direction=direction; result.moon_direction=-direction
	result.day=day; result.night=1.-smoothstep(-.20,.06,direction.y)
	result.dusk=(1.-smoothstep(.04,.4,absf(direction.y)))*(1.-result.night*.7)
	result.sun_energy*=smoothstep(-.04,.12,direction.y)
	result.moon_energy=.04*smoothstep(.02,.25,-direction.y)
	return result
