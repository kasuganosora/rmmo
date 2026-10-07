extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Weather=preload("res://scripts/world3d/weather_controller.gd")
const Settings=preload("res://scripts/world3d/environment_settings.gd")
const Profile=preload("res://scripts/world3d/weather_profile.gd")
const Authority=preload("res://scripts/net/server/sky_module.gd")
var failures:=0
class LampStub extends Node3D:
	var refreshes:=0
	func refresh()->void:refreshes+=1
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func ordered(row:Dictionary,keys:Array)->bool:
	var previous:=0
	for key:String in keys:
		if int(row.get(key,0))<previous or int(row.get(key,0))<=0:return false
		previous=int(row[key])
	return true
func run()->void:
	create_timer(25).timeout.connect(func():push_error("detail timeline fixture timeout");quit(2))
	var weather:=Weather.new()
	weather.values=Settings.resolve({});weather.current=Profile.sample(weather.values)
	weather.sky_material=ShaderMaterial.new();weather.sky_material.shader=preload("res://scripts/world3d/weather_sky.gdshader")
	weather._tick_night_sky(0)
	check(weather._sky_profile_slots.is_empty() and weather.sky_profile_snapshot().is_empty(),"normal sky path allocates no diagnostic slots")
	weather.sun=DirectionalLight3D.new();weather.environment=Environment.new();weather.streetlamps=LampStub.new()
	var authority:=Authority.new();authority.configure("test/timeline",32,0)
	weather.bind_sky("test/timeline",func():return authority.snapshot("test/timeline",weather.night_sky.local_time()))
	weather.set_meta("profile_frame",true);weather.set_meta("profile_sky_details",true)
	weather._tick_night_sky(0)
	var sky:Dictionary=weather.sky_profile_snapshot();var row:Dictionary=sky.calls[0]
	check(sky.frame==Engine.get_process_frames() and row.polled==1 and row.accepted==1 and row.revision_changed==1,"sky provider receive and changed revision are correlated")
	check(ordered(row,["begin_us","setup_end_us","provider_begin_us","provider_end_us","receive_begin_us","receive_end_us","revision_end_us","sample_begin_us","sample_end_us","star_uniform_end_us","arrays_end_us","meteor_uniform_end_us","return_end_us"]),"sky full poll timestamps cover implementation and return")
	weather._tick_night_sky(0)
	var next:Dictionary=weather.sky_profile_snapshot()
	check(next.calls.size()==2 and next.calls[1].polled==0 and next.calls[1].provider_begin_us==0 and next.calls[1].receive_end_us==0,"same-frame non-poll retains both calls without stale provider timing")
	check(sky.calls.size()==1 and sky.calls[0]==row,"sky snapshot does not alias reused slots")
	weather.sky_provider=func():return 42
	weather.sky_poll=0;weather._tick_night_sky(0)
	next=weather.sky_profile_snapshot()
	check(next.calls.size()==3 and next.calls[2].polled==1 and next.calls[2].accepted==0,"invalid provider result preserves rejection and gets current timestamps")
	var prior_frame:=Engine.get_process_frames()
	while Engine.get_process_frames()==prior_frame:await process_frame
	for i in 6:weather._tick_night_sky(0)
	next=weather.sky_profile_snapshot()
	check(next.calls.size()==4 and next.dropped==2 and next.frame==Engine.get_process_frames(),"sky collection resets per frame and bounds repeated direct calls")
	weather.remove_meta("profile_sky_details")
	check(weather.sky_profile_snapshot().is_empty(),"disabled sky details expose no stale snapshot")
	weather.sun.free();weather.streetlamps.free();weather.free()
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	for i in 5:doc.add_box_silent("block",Vector3(i*4,1,0),Vector3(2,2,2))
	var host:=Node3D.new();root.add_child(host);var map:Node3D=doc.build();host.add_child(map)
	check(Stream.collision_wrapper_snapshot(map).is_empty(),"normal stream exposes no wrapper details")
	map.set_meta("profile_collision_details",true)
	for i in 60:
		Stream.sync(map,host,Vector3.ZERO,1)
		if map.has_meta("stream_chunk"):break
	var stream:Dictionary=Stream.collision_wrapper_snapshot(map)
	check(not stream.is_empty() and not stream.calls.is_empty(),"real paced stream sync records wrapper calls")
	var all_ordered:=true
	for item:Dictionary in stream.get("calls",[]):
		all_ordered=all_ordered and ordered(item,["outer_begin_us","wrapper_begin_us","impl_begin_us","impl_end_us","publish_begin_us","publish_end_us","return_begin_us","outer_end_us"])
	check(all_ordered,"stream outer interval includes prefix implementation metadata and return")
	var retained:Dictionary=stream.duplicate(true)
	prior_frame=Engine.get_process_frames()
	while Engine.get_process_frames()==prior_frame:await process_frame
	Stream._collision_wrapper_slots(map)
	check(stream==retained and Stream.collision_wrapper_snapshot(map).calls.is_empty(),"stream frame reset does not mutate a retained snapshot")
	map.remove_meta("profile_collision_details")
	check(Stream.collision_wrapper_snapshot(map).is_empty(),"disabled stream details expose no stale snapshot")
	host.free();await process_frame
	print("DETAIL_TIMELINE_FAILURES=",failures);quit(1 if failures else 0)
