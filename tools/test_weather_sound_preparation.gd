extends SceneTree
## Real PCM/cache lifecycle, with a saved original implementation as oracle.
const Sound=preload("res://scripts/world3d/weather_sound.gd")
const KINDS=["wind","roof","thunder_near","thunder_far"]
var failures:Array=[]
var checks:=0
var result:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var reference_path:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="):reference_path=arg.trim_prefix("--reference=")
	check(reference_path.begins_with("D:/code/rmmo_runtime/review_artifacts/") and FileAccess.file_exists(reference_path),"saved original oracle is external")
	if not failures.is_empty():finish();return
	var original:Script=load(reference_path)
	var expected:Dictionary={};var original_us:Dictionary={}
	for kind:String in KINDS:
		var began:=Time.get_ticks_usec()
		var wav:AudioStreamWAV=original.call("stream",kind)
		original_us[kind]=Time.get_ticks_usec()-began
		expected[kind]=wav
		check(wav.data.size()==22050*(4 if kind.begins_with("thunder") else 2)*2,kind+" has complete signed PCM")
	result.original_us=original_us;result.original_sha=FileAccess.get_sha256(reference_path)
	var script:Script=Sound
	var methods:Array=[]
	for method:Dictionary in script.get_script_method_list():methods.append(method.name)
	check("request_stream" in methods,"ambient sound preparation has a nonblocking entry")
	if not failures.is_empty():finish();return
	var before:Dictionary=script.call("preparation_profile")
	var request_us:Array=[];var received:Dictionary={}
	var began:=Time.get_ticks_usec()
	for kind:String in KINDS:
		var mark:=Time.get_ticks_usec()
		var wav:AudioStreamWAV=script.call("request_stream",kind)
		request_us.append(Time.get_ticks_usec()-mark)
		if wav!=null:received[kind]=wav
	# Repeated consumers share each in-flight job and the final resource.
	for repeat_ in 100:
		for kind:String in KINDS:
			var wav:AudioStreamWAV=script.call("request_stream",kind)
			if wav!=null:
				check(not received.has(kind) or received[kind]==wav,kind+" completed consumers share identity")
				received[kind]=wav
	var deadline:=Time.get_ticks_msec()+10000
	var poll_max_us:=0
	while received.size()<KINDS.size() and Time.get_ticks_msec()<deadline:
		await process_frame
		for kind:String in KINDS:
			var mark:=Time.get_ticks_usec()
			var wav:AudioStreamWAV=script.call("request_stream",kind)
			poll_max_us=maxi(poll_max_us,Time.get_ticks_usec()-mark)
			if wav!=null:received[kind]=wav
	result.ready_us=Time.get_ticks_usec()-began;result.request_us=request_us;result.poll_max_us=poll_max_us
	check(received.size()==KINDS.size(),"all background jobs publish")
	var after:Dictionary=script.call("preparation_profile")
	check(after.started-before.started==KINDS.size(),"400 repeated requests start exactly four jobs")
	check(after.completed-before.completed==KINDS.size() and after.pending==0,"completed task IDs are reclaimed")
	result.work=after;result.pcm_sha={}
	for kind:String in received:
		var wav:AudioStreamWAV=received[kind];var prior:AudioStreamWAV=expected[kind]
		check(wav.data==prior.data,kind+" every PCM byte matches original")
		check(wav.format==prior.format and wav.mix_rate==prior.mix_rate and wav.loop_mode==prior.loop_mode and wav.loop_end==prior.loop_end and wav.stereo==prior.stereo,kind+" playback and loop settings unchanged")
		check(Sound.stream(kind)==wav and script.call("request_stream",kind)==wav,kind+" synchronous and asynchronous consumers share cache")
		var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(wav.data);result.pcm_sha[kind]=hash_.finish().hex_encode()
	# The legacy synchronous contract can join an existing job, never synthesize
	# the same sound again. Ordinary ambient playback uses request_stream only.
	Sound.cache.erase("wind")
	before=script.call("preparation_profile")
	script.call("request_stream","wind")
	var joined:=Sound.stream("wind")
	after=script.call("preparation_profile")
	check(joined.data==expected.wind.data and after.started-before.started==1 and after.completed-before.completed==1 and after.pending==0,"legacy consumer adopts the same in-flight preparation")
	Sound.cache.erase("roof")
	before=script.call("preparation_profile")
	script.call("request_stream","roof")
	deadline=Time.get_ticks_msec()+10000
	# No playback consumer polls this request: stopping weather or leaving a
	# world must not strand a completed pool task and its private PCM buffer.
	while int(script.call("preparation_profile").pending)>0 and Time.get_ticks_msec()<deadline:await process_frame
	after=script.call("preparation_profile")
	check(after.pending==0 and after.started-before.started==1 and after.completed-before.completed==1 and Sound.cache.roof.data==expected.roof.data,"unobserved preparation publishes and reclaims itself")
	Sound.cache.erase("wind")
	var weather:Node=load("res://scripts/world3d/weather_controller.gd").new()
	var player:=AudioStreamPlayer.new();root.add_child(player)
	began=Time.get_ticks_usec();weather._loop(player,.5,"wind",-15.)
	result.ambient_cold_us=Time.get_ticks_usec()-began
	check(player.stream==null and not player.playing,"cold ambient update returns while PCM is being prepared")
	deadline=Time.get_ticks_msec()+10000
	while not Sound.cache.has("wind") and Time.get_ticks_msec()<deadline:await process_frame
	began=Time.get_ticks_usec();weather._loop(player,.5,"wind",-15.)
	result.ambient_warm_us=Time.get_ticks_usec()-began
	check(player.stream==Sound.cache.wind and player.playing,"ordinary ambient update plays the prepared shared sound")
	check(is_equal_approx(player.volume_db,linear_to_db(.5)-15.),"ambient volume is unchanged")
	weather._loop(player,0.,"wind",-15.)
	check(not player.playing,"disabling the ambient sound still stops it immediately")
	player.free();weather.free()
	finish()
func finish()->void:
	result.checks=checks;result.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WEATHER_SOUND_PREPARATION ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
