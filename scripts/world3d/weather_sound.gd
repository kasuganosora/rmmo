extends RefCounted
## Cached signed PCM, with continuous loop boundaries and separate roof/air spectra.
static var cache:Dictionary={}
static var _pending:Dictionary={}
static var _started:=0
static var _completed:=0
static var _background_us:=0
static var _synchronous_builds:=0
class Preparation extends RefCounted:
	var kind:String
	var task:=-1
	var data:PackedByteArray
	var elapsed_us:=0

## Main-thread consumers share one CPU-only preparation per sound. A cold
## request returns null; ambient playback polls on its ordinary next update.
static func request_stream(kind:String)->AudioStreamWAV:
	assert(Thread.is_main_thread())
	if cache.has(kind):return cache[kind]
	if _pending.has(kind):
		var job:Preparation=_pending[kind]
		if not WorkerThreadPool.is_task_completed(job.task):return null
		return _adopt(job)
	var job:=Preparation.new();job.kind=kind
	_pending[kind]=job
	job.task=WorkerThreadPool.add_task(_prepare.bind(job),false,"WeatherSound:"+kind)
	_started+=1
	return null

static func _prepare(job:Preparation)->void:
	var began:=Time.get_ticks_usec()
	job.data=_pcm(job.kind)
	job.elapsed_us=Time.get_ticks_usec()-began
	_complete.call_deferred(job)

static func _complete(job:Preparation)->void:
	# Main-only publication also reclaims jobs when rain/wind stopped, or the
	# requesting world disappeared, before its next playback update.
	if _pending.get(job.kind)!=job:return
	if not WorkerThreadPool.is_task_completed(job.task):
		# A deferred call can beat the worker's final return. Retry once on the
		# next frame instead of joining it or spinning in MessageQueue.flush().
		var tree:=Engine.get_main_loop() as SceneTree
		if tree!=null:tree.process_frame.connect(_complete.bind(job),CONNECT_ONE_SHOT)
		return
	_adopt(job)

static func _adopt(job:Preparation)->AudioStreamWAV:
	WorkerThreadPool.wait_for_task_completion(job.task)
	var wav:=_make_stream(job.kind,job.data)
	cache[job.kind]=wav;_pending.erase(job.kind)
	_completed+=1;_background_us+=job.elapsed_us
	return wav

static func preparation_profile()->Dictionary:
	return {"started":_started,"completed":_completed,"pending":_pending.size(),"background_us":_background_us,"synchronous_builds":_synchronous_builds}

static func stream(kind:String) -> AudioStreamWAV:
	if cache.has(kind): return cache[kind]
	# Existing synchronous users can adopt an already scheduled job. They must
	# never build a second copy while an ambient consumer prepares the same kind.
	if _pending.has(kind):return _adopt(_pending[kind])
	_synchronous_builds+=1
	var wav:=_make_stream(kind,_pcm(kind));cache[kind]=wav;return wav

static func _make_stream(kind:String,data:PackedByteArray)->AudioStreamWAV:
	var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=22050;wav.data=data
	if not kind.begins_with("thunder"):wav.loop_mode=AudioStreamWAV.LOOP_FORWARD;wav.loop_end=data.size()/2
	return wav

static func _pcm(kind:String)->PackedByteArray:
	var thunder:=kind.begins_with("thunder")
	var count:=22050*(4 if thunder else 2)
	var data:=PackedByteArray(); data.resize(count*2)
	var rng:=RandomNumberGenerator.new(); rng.seed=9281 if kind=="roof" else 4183
	var low:=0.; var bass:=0.
	var smoothing:=.045 if kind=="thunder_far" else .16 if thunder else .09 if kind=="wind" else .7
	var attack:=20 if kind=="thunder_near" else 4
	var roof:=kind=="roof"
	for i in count:
		var t:=float(i)/22050.; var noise:=rng.randf_range(-1,1)
		low=lerpf(low,noise,smoothing)
		bass=lerpf(bass,noise,.012)
		var sample:float=low*.34
		if thunder:
			var envelope:float=(1.-exp(-t*attack))*exp(-t*1.1)
			sample=(low*1.4+bass*3.+sin(t*TAU*42.)*.12)*envelope
		elif roof: sample*=.65+.35*pow(maxf(0,sin(t*TAU*37.)*sin(t*TAU*19.)),4)
		else: sample*=.7+.3*sin(t*PI)
		# Fade only at the periodic seam; no full-scale discontinuity when looping.
		sample*=minf(1.,minf(float(i),float(count-1-i))/220.)
		# Same signed little-endian PCM as MapSFX._write_s16, without a script
		# method call and repeated kind comparisons for every single sample.
		data.encode_s16(i*2,clampi(int(round(sample*22000.0)),-24000,24000))
	return data
