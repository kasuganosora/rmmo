extends RefCounted
## Server-owned map seeds and future meteor commands. No per-client random stream.
const SkyState = preload("res://scripts/world3d/night_sky.gd")
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Profile = preload("res://scripts/world3d/weather_profile.gd")
var maps := {}
var rng := RandomNumberGenerator.new()
var epoch := ""
var serial := 0

func _init() -> void:
	rng.randomize(); epoch = Crypto.new().generate_random_bytes(12).hex_encode()

func configure(map_id: String, seed: int, rate: float, enabled := true) -> bool:
	if map_id.is_empty() or seed < 0 or seed > 2147483647 or not is_finite(rate) or rate < 0 or rate > 12: return false
	var environment := Settings.updated({}, {"meteor_frequency":rate,"meteors_enabled":enabled})
	serial += 1
	maps[map_id] = {"seed":seed,"rate":rate if enabled else 0.0,"events":[],"next_at":-1.0,
		"environment":environment,"source_profile":Profile.encode(Profile.sample(environment)),"transition_at":0.0,"wind_origin":[0.0,0.0],"environment_revision":serial,"lightning_events":[],"next_lightning":-1.0,"clock_hours":12.0,"clock_at":0.0}
	return true

func ensure_map(map_id: String, settings: Dictionary) -> void:
	if maps.has(map_id): return
	configure(map_id,rng.randi_range(0,2147483647),float(settings.get("meteor_frequency",3)),bool(settings.get("meteors_enabled",true)))
	var environment := Settings.resolve({"environment":settings})
	maps[map_id].environment = environment
	maps[map_id].source_profile = Profile.encode(Profile.sample(environment))
	maps[map_id].transition_at = SkyState.local_time()
	maps[map_id].clock_hours = environment.time_hours; maps[map_id].clock_at = SkyState.local_time()

static func clock_hours(state: Dictionary, now: float) -> float:
	return fposmod(float(state.clock_hours)+maxf(0,now-float(state.clock_at))*float(state.environment.time_speed)/3600.0,24.0)

func set_environment(map_id: String, changes: Dictionary, now: float, update_clock := true) -> Dictionary:
	var error := Settings.Schema.validate(changes,Settings.schema())
	if not maps.has(map_id) or not error.is_empty() or not is_finite(now) or now < 0: return {"ok":false,"error":"Invalid map or environment: "+error}
	var state: Dictionary = maps[map_id]
	var target := Settings.updated({"environment":state.environment},changes)
	if target == state.environment: return {"ok":true,"environment":target.duplicate(true)}
	if update_clock and (changes.has("preset") or changes.has("time_hours") or changes.has("time_speed")):
		state.clock_hours = target.time_hours if changes.has("preset") or changes.has("time_hours") else clock_hours(state,now)
		state.clock_at = now
	var origin := Profile.drift_at(state,now)
	state.source_profile = Profile.encode(Profile.at(state,now)); state.wind_origin = [origin.x,origin.y]; state.transition_at = now
	var rate: float = target.meteor_frequency if target.meteors_enabled else 0.0
	if rate != state.rate: state.events.clear(); state.next_at = -1; state.rate = rate
	state.environment = target; serial += 1; state.environment_revision = serial
	if target.weather != "storm" or not target.lightning_enabled:
		# Already emitted strikes retain their travelling sound after the rain stops.
		state.lightning_events=state.lightning_events.filter(func(event):return event.start_at<=now)
		state.next_lightning = -1
	return {"ok":true,"environment":target.duplicate(true)}

func lightning(map_id: String, event: Dictionary) -> bool:
	if not maps.has(map_id) or not SkyState.valid_lightning(event): return false
	var events:Array=maps[map_id].lightning_events
	if events.size()>=64: return false
	for other in events:
		if other.id==event.id or absf(float(other.start_at)-float(event.start_at))<.4: return false
	events.append(event.duplicate(true)); return true

func meteor(map_id: String, event: Dictionary) -> bool:
	if not maps.has(map_id) or not SkyState.valid_event(event): return false
	var rows: Array = maps[map_id].events
	if rows.size() >= 64: return false
	for row in rows:
		if row.id == event.id: return false
	var candidate := event.duplicate(true); candidate.kind = event.get("kind","meteor"); candidate.brightness = event.get("brightness",1.0)
	var combined := rows.duplicate(true); combined.append(candidate)
	if not concurrency_ok(combined): return false
	rows.append(candidate); return true

static func concurrency_ok(events: Array) -> bool:
	for event in events:
		var count := 0
		for other in events:
			if other.start_at <= event.start_at and other.start_at+other.duration > event.start_at: count += 1
		if count > 8: return false
	return true

## Server script command: a shared radiant and explicit cadence, generated once.
func meteor_shower(map_id: String, command: Dictionary) -> bool:
	if not maps.has(map_id) or not command.get("id") is String or command.id.is_empty(): return false
	if not SkyState.direction(command.get("radiant")): return false
	for key in ["start_at","count","interval","brightness"]:
		if not SkyState.finite_number(command.get(key)): return false
	if command.start_at < 0 or command.count != floor(command.count) or command.count < 1 or command.count > 24 or command.interval < .1 or command.interval > 3 or command.brightness < 0 or command.brightness > 5: return false
	if command.get("kind","meteor") not in ["meteor","fireball"]: return false
	var rows: Array = maps[map_id].events
	if rows.size()+int(command.count)>64: return false
	var previous_rng := rng.state
	var generated: Array = []
	var radiant := Vector3(command.radiant[0],command.radiant[1],command.radiant[2])
	var right := radiant.cross(Vector3.UP).normalized()
	if right.length()<.1: right = Vector3.RIGHT
	var vertical := right.cross(radiant).normalized()
	for i in int(command.count):
		var offset := right*rng.randf_range(-.2,.2)+vertical*rng.randf_range(-.08,.12)
		var start := (radiant+offset).normalized()
		var travel := (offset+Vector3.DOWN*.17).normalized()
		var finish := (start+travel*.25).normalized()
		var event := {"id":command.id+"/"+str(i),"start_at":command.start_at+i*command.interval,"duration":rng.randf_range(.85,1.35),"from":[start.x,start.y,start.z],"to":[finish.x,finish.y,finish.z],"kind":command.get("kind","meteor"),"brightness":command.brightness}
		if not SkyState.valid_event(event) or rows.any(func(row):return row.id==event.id): rng.state=previous_rng; return false
		generated.append(event)
	var combined := rows.duplicate(true); combined.append_array(generated)
	if not concurrency_ok(combined): rng.state=previous_rng; return false
	rows.append_array(generated); return true

func snapshot(map_id: String, now: float) -> Dictionary:
	if not maps.has(map_id) or not is_finite(now) or now < 0: return {"ok":false}
	var state: Dictionary = maps[map_id]
	var hours := clock_hours(state,now)
	if state.environment.time_speed > 0:
		var phase := Settings.time_preset(hours)
		if phase != state.environment.preset:
			var boundary: float = {"day":6.0,"sunset":17.0,"night":20.0}[phase]
			var changed_at := now-fposmod(hours-boundary,24.0)*3600.0/float(state.environment.time_speed)
			set_environment(map_id,{"preset":phase},maxf(float(state.clock_at),changed_at),false)
	state.lightning_events = state.lightning_events.filter(func(event): return event.start_at+25 > now)
	if state.environment.weather == "storm" and state.environment.lightning_enabled:
		if state.next_lightning < now: state.next_lightning = now+2+rng.randf_range(9,19)
		while state.next_lightning < now+65:
			serial += 1
			var angle:=rng.randf_range(-PI,PI); var radius:=rng.randf_range(.2,1.)*float(state.environment.lightning_radius)
			var center:Array=state.environment.lightning_center
			lightning(map_id,{"id":str(serial),"start_at":state.next_lightning,"position":[center[0]+cos(angle)*radius,center[1],center[2]+sin(angle)*radius],"seed":rng.randi_range(0,2147483647),"energy":rng.randf_range(.7,1.4),"height":rng.randf_range(70,160)})
			state.next_lightning += rng.randf_range(9,19)
	state.events = state.events.filter(func(event): return event.start_at+event.duration > now)
	if state.rate > 0:
		if state.next_at < now: state.next_at = now+2.0+rng.randf_range(.65,1.35)*60.0/state.rate
		while state.next_at < now+65 and state.events.size() < 64:
			var azimuth := rng.randf_range(-PI,PI); var elevation := rng.randf_range(.5,1.15)
			var start := Vector3(cos(azimuth)*cos(elevation),sin(elevation),sin(azimuth)*cos(elevation))
			var sideways := Vector3(-sin(azimuth),0,cos(azimuth))
			var down := (Vector3.DOWN-start*Vector3.DOWN.dot(start)).normalized()
			var travel := (down+sideways*rng.randf_range(-1.4,1.4)).normalized()
			var finish := (start*cos(.34)+travel*sin(.34)).normalized()
			serial += 1
			var fireball := rng.randf() < .08
			meteor(map_id,{"id":str(serial),"start_at":state.next_at,"duration":rng.randf_range(.85,1.35),"from":[start.x,start.y,start.z],"to":[finish.x,finish.y,finish.z],"kind":"fireball" if fireball else "meteor","brightness":rng.randf_range(1.5,2.8) if fireball else rng.randf_range(.65,1.25)})
			state.next_at += rng.randf_range(.65,1.35)*60.0/state.rate
	serial += 1
	return {"ok":true,"map_id":map_id,"epoch":epoch,"sequence":serial,"seed":state.seed,"server_time":now,"events":state.events.duplicate(true),
		"environment":state.environment.duplicate(true),"environment_revision":state.environment_revision,"source_profile":state.source_profile.duplicate(true),
		"transition_at":state.transition_at,"wind_origin":state.wind_origin.duplicate(),"lightning_events":state.lightning_events.duplicate(true),
		"time_of_day_hours":hours,"time_speed":state.environment.time_speed}
