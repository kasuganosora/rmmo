extends RefCounted
## Render server commands at synchronized server time. Never generate client events.
var map_id := ""
var epoch := ""
var sequence := -1
var seed := 0
var events: Array = []
var clock_offset := 0.0
var ready := false
var head := Vector3.UP
var tail := Vector3.UP
var energy := 0.0
var time := 0.0
var active_id := ""
var snapshot := {}
var retired_epochs := {}
var meteors: Array = []

static func local_time() -> float: return Time.get_ticks_msec()/1000.0

func reset() -> void:
	map_id = ""; epoch = ""; sequence = -1; ready = false; events.clear(); energy = 0; active_id = ""
	snapshot.clear(); retired_epochs.clear()
	meteors.clear(); clock_offset = 0

static func finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func direction(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	for component in value:
		if not finite_number(component): return false
	var v := Vector3(value[0],value[1],value[2])
	return v.y > .05 and absf(v.length()-1.0) < .002

static func valid_event(event: Variant) -> bool:
	if not event is Dictionary or not event.get("id") is String or event.id.is_empty(): return false
	if not finite_number(event.get("start_at")) or event.start_at < 0: return false
	if not finite_number(event.get("duration")) or event.duration < .4 or event.duration > 3: return false
	if not direction(event.get("from")) or not direction(event.get("to")): return false
	if event.get("kind","meteor") not in ["meteor","fireball"]: return false
	if not finite_number(event.get("brightness",1.0)) or event.get("brightness",1.0) < 0 or event.get("brightness",1.0) > 5: return false
	var a := Vector3(event.from[0],event.from[1],event.from[2]); var b := Vector3(event.to[0],event.to[1],event.to[2])
	return a.angle_to(b) > .01 and a.angle_to(b) < .8

static func valid_lightning(event: Variant) -> bool:
	if not event is Dictionary or not event.get("id") is String or event.id.is_empty(): return false
	for key in ["start_at","seed","energy","height"]:
		if not finite_number(event.get(key)): return false
	if event.start_at<0 or event.seed<0 or event.seed>2147483647 or event.seed!=floor(event.seed) or event.energy<.1 or event.energy>4 or event.height<30 or event.height>300: return false
	var schema=preload("res://scripts/world3d/document_schema.gd")
	return schema.validate(event.get("position"),schema.vector(-100000,100000)).is_empty()

func receive(packet: Dictionary, expected_map: String, sent: float, received: float) -> bool:
	if not packet.get("ok",false) or packet.get("map_id") != expected_map: return false
	if not packet.get("epoch") is String or packet.epoch.is_empty(): return false
	if retired_epochs.has(packet.epoch): return false
	for field in ["sequence","seed"]:
		if not finite_number(packet.get(field)) or packet[field] != floor(packet[field]) or packet[field] < 0 or packet[field] > 2147483647: return false
	if epoch == packet.epoch and packet.sequence <= sequence: return false
	if not finite_number(packet.get("server_time")) or packet.server_time < 0 or received < sent: return false
	if epoch == packet.epoch and not snapshot.is_empty() and packet.server_time < snapshot.server_time: return false
	if not packet.get("events") is Array or packet.events.size() > 64: return false
	var settings = preload("res://scripts/world3d/environment_settings.gd")
	if not packet.get("environment") is Dictionary or not settings.Schema.validate(packet.environment,settings.schema()).is_empty(): return false
	if packet.environment.size() != settings.defaults().size(): return false
	if not finite_number(packet.get("environment_revision")) or packet.environment_revision < 0 or packet.environment_revision != floor(packet.environment_revision): return false
	if not finite_number(packet.get("time_of_day_hours")) or packet.time_of_day_hours < 0 or packet.time_of_day_hours >= 24: return false
	if not finite_number(packet.get("time_speed")) or packet.time_speed < 0 or packet.time_speed > 3600: return false
	if not finite_number(packet.get("transition_at")) or packet.transition_at < 0: return false
	if not settings.Schema.validate(packet.get("wind_origin"),{"type":"array","items":settings.Schema.number(-1e12,1e12),"minItems":2,"maxItems":2}).is_empty(): return false
	var profile_schema := {"type":"object","additionalProperties":false,"required":["rain","snow","cloud","sun","fog","storm","wind"],"properties":{}}
	for field in ["rain","snow","cloud","sun","fog","storm"]: profile_schema.properties[field] = settings.Schema.number(0,1)
	profile_schema.properties.wind = settings.Schema.vector(-18,18)
	if not settings.Schema.validate(packet.get("source_profile"),profile_schema).is_empty(): return false
	if not packet.get("lightning_events") is Array or packet.lightning_events.size() > 64: return false
	var lightning_ids:Dictionary={}
	for event in packet.lightning_events:
		if not valid_lightning(event) or lightning_ids.has(event.id): return false
		lightning_ids[event.id]=true
		for other in packet.lightning_events:
			if other is Dictionary and other.get("id")!=event.id and finite_number(other.get("start_at")) and absf(float(other.start_at)-float(event.start_at))<.4: return false
	var ids := {}
	for event in packet.events:
		if not valid_event(event) or ids.has(event.id): return false
		ids[event.id] = true
	for event in packet.events:
		var simultaneous := 0
		for other in packet.events:
			if other.start_at <= event.start_at and other.start_at+other.duration > event.start_at: simultaneous += 1
		if simultaneous > 8: return false
	if not epoch.is_empty() and epoch != packet.epoch: retired_epochs[epoch] = true
	map_id = expected_map; epoch = packet.epoch; sequence = int(packet.sequence); seed = int(packet.seed)
	events = packet.events.duplicate(true)
	snapshot = packet.duplicate(true)
	clock_offset = float(packet.server_time)-(sent+received)*.5
	ready = true
	return true

func sample(server_time: float) -> void:
	energy = 0; active_id = ""; time = fmod(server_time,3600.0)
	meteors.clear()
	if not ready: return
	for event in events:
		var progress: float = (server_time-float(event.start_at))/float(event.duration)
		if progress < 0 or progress >= 1: continue
		var a := Vector3(event.from[0],event.from[1],event.from[2]); var b := Vector3(event.to[0],event.to[1],event.to[2])
		var row := {"head":a.slerp(b,progress),"tail":a.slerp(b,maxf(0,progress-.32)),"energy":smoothstep(0,.12,progress)*(1-smoothstep(.65,1,progress)),"kind":event.get("kind","meteor"),"brightness":float(event.get("brightness",1.0)),"id":event.id}
		meteors.append(row)
		if meteors.size()==1: head=row.head; tail=row.tail; energy=row.energy; active_id=row.id
		if meteors.size()>=8: return
