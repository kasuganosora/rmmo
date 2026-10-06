extends SceneTree
const Profile=preload("res://scripts/world3d/weather_profile.gd")
const Settings=preload("res://scripts/world3d/environment_settings.gd")
func _initialize()->void:run.call_deferred()
func reference(state:Dictionary,now:float)->Vector2:
	var start:float=state.transition_at
	var end:=minf(now,start+float(state.environment.weather_transition))
	var displacement:=Vector3.ZERO
	if end>start:
		var step:=(end-start)/16.0
		for i in 16:
			var t:=start+(i+.5)*step
			displacement+=Profile.at(state,t).wind*Profile.gust(t)*step
	if now>end:displacement+=Profile.sample(state.environment).wind*Profile.gust_integral(maxf(start,end),now)
	return Vector2(state.wind_origin[0],state.wind_origin[1])+Vector2(displacement.x,displacement.z)*.0006
func run()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=66271
	var probes:Array=[];var mismatches:=0
	for i in 250:
		var source:=Settings.updated({}, {"weather":Profile.KINDS[i%5],"wind_speed":rng.randf_range(0,18),"wind_direction":rng.randf_range(-180,180)})
		var target:=Settings.updated({}, {"weather":Profile.KINDS[(i+1)%5],"wind_speed":rng.randf_range(0,18),"wind_direction":rng.randf_range(-180,180),"weather_transition":[0.,.0001,3.,20.][i%4]})
		var start:=rng.randf_range(-100,100000)
		var state:={"transition_at":start,"environment":target,"source_profile":Profile.encode(Profile.sample(source)),"wind_origin":[rng.randf(),rng.randf()]}
		for offset in [-1.,0.,.00005,.1,2.,5.,30.,3600.]:
			var now:float=start+offset
			if reference(state,now)!=Profile.drift_at(state,now):mismatches+=1
			probes.append([state,now])
	var began:=Time.get_ticks_usec()
	for row in probes:reference(row[0],row[1])
	var before:=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
	for row in probes:Profile.drift_at(row[0],row[1])
	var after:=Time.get_ticks_usec()-began
	print("WEATHER_DRIFT samples=",probes.size()," exact_mismatches=",mismatches," legacy_ms=",before/1000.0," optimized_ms=",after/1000.0)
	quit(1 if mismatches else 0)
