extends RefCounted
## Cached signed PCM, with continuous loop boundaries and separate roof/air spectra.
static var cache:Dictionary={}
static func stream(kind:String) -> AudioStreamWAV:
	if cache.has(kind): return cache[kind]
	var wav:=AudioStreamWAV.new(); wav.format=AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate=22050
	var thunder:=kind.begins_with("thunder")
	var count:=22050*(4 if thunder else 2)
	var data:=PackedByteArray(); data.resize(count*2)
	var rng:=RandomNumberGenerator.new(); rng.seed=9281 if kind=="roof" else 4183
	var low:=0.; var bass:=0.
	for i in count:
		var t:=float(i)/22050.; var noise:=rng.randf_range(-1,1)
		low=lerpf(low,noise,.045 if kind=="thunder_far" else .16 if thunder else .09 if kind=="wind" else .7)
		bass=lerpf(bass,noise,.012)
		var sample:float=low*.34
		if thunder:
			var envelope:float=(1.-exp(-t*(20 if kind=="thunder_near" else 4)))*exp(-t*1.1)
			sample=(low*1.4+bass*3.+sin(t*TAU*42.)*.12)*envelope
		elif kind=="roof": sample*=.65+.35*pow(maxf(0,sin(t*TAU*37.)*sin(t*TAU*19.)),4)
		else: sample*=.7+.3*sin(t*PI)
		# Fade only at the periodic seam; no full-scale discontinuity when looping.
		sample*=minf(1.,minf(float(i),float(count-1-i))/220.)
		preload("res://scripts/map/map_sfx.gd")._write_s16(data,i,sample)
	wav.data=data
	if not thunder: wav.loop_mode=AudioStreamWAV.LOOP_FORWARD; wav.loop_end=count
	cache[kind]=wav; return wav
