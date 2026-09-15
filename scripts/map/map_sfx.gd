extends RefCounted
## Tiny procedural SFX so map settings work without imported audio.
## Godot AudioStreamWAV 8-bit is signed PCM; unsigned-centered bytes (128=silence)
## decode as full-scale clicks. Write signed 16-bit instead.


static var _foot_cache: Dictionary = {}
static var _amb_cache: Dictionary = {}


static func footstep(kind: int) -> AudioStreamWAV:
	kind = clampi(kind, 0, 8)
	if _foot_cache.has(kind):
		return _foot_cache[kind]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var n := 1400
	var data := PackedByteArray()
	data.resize(n * 2)
	var seed := 1103 + kind * 97
	var lp := 0.0
	for i in range(n):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var t := float(i) / float(n)
		var env := 0.0
		if t < 0.08:
			env = t / 0.08
		else:
			env = (1.0 - (t - 0.08) / 0.92)
			env *= env
		env = clampf(env, 0.0, 1.0)
		var noise := float(seed % 255) / 255.0 - 0.5
		var cutoff := 0.78
		var tone := 0.0
		var mix_n := 0.22
		match kind:
			1:
				cutoff = 0.72
				tone = sin(float(i) * 0.048) * 0.28
				mix_n = 0.18
			2:
				cutoff = 0.88
				tone = sin(float(i) * 0.033) * 0.22
				mix_n = 0.28
			3:
				cutoff = 0.70
				tone = sin(float(i) * 0.055) * 0.32
				mix_n = 0.14
			_:
				cutoff = 0.80
				tone = sin(float(i) * 0.041) * 0.18
				mix_n = 0.20
		lp = lp * cutoff + noise * (1.0 - cutoff)
		var s := (lp * mix_n + tone) * env * 0.55
		_write_s16(data, i, s)
	wav.data = data
	_foot_cache[kind] = wav
	return wav


static func ambient(kind: String) -> AudioStreamWAV:
	var key := kind.strip_edges().to_lower()
	if _amb_cache.has(key):
		return _amb_cache[key]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var n := 22050
	var data := PackedByteArray()
	data.resize(n * 2)
	var seed := 4242
	match key:
		"water":
			seed = 9101
		"night":
			seed = 3331
		"rain":
			seed = 7711
		"storm":
			seed = 8801
		"wind":
			seed = 4242
		_:
			seed = 4242
	var lp := 0.0
	for i in range(n):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed % 255) / 255.0 - 0.5
		match key:
			"water":
				lp = lp * 0.92 + noise * 0.08
				noise = lp + sin(float(i) * 0.031) * 0.08
			"night":
				lp = lp * 0.97 + noise * 0.03
				noise = lp * 0.8 + sin(float(i) * 0.007) * 0.12
			"rain":
				lp = lp * 0.55 + noise * 0.45
				noise = lp * 0.7 + sin(float(i) * 0.11) * 0.05
			"storm":
				lp = lp * 0.48 + noise * 0.52
				noise = lp * 0.85 + sin(float(i) * 0.019) * 0.12
			"wind":
				lp = lp * 0.9 + noise * 0.1
				noise = lp + sin(float(i) * 0.009) * 0.1
			_:
				lp = lp * 0.88 + noise * 0.12
				noise = lp
		_write_s16(data, i, noise * 0.22)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	_amb_cache[key] = wav
	return wav


static func _write_s16(data: PackedByteArray, i: int, s: float) -> void:
	var v := clampi(int(round(s * 22000.0)), -24000, 24000)
	var o := i * 2
	data[o] = v & 0xff
	data[o + 1] = (v >> 8) & 0xff


static func sample_s16(wav: AudioStreamWAV, i: int) -> int:
	if wav == null or wav.data.size() < (i + 1) * 2:
		return 0
	var lo := int(wav.data[i * 2])
	var hi := int(wav.data[i * 2 + 1])
	var v := lo | (hi << 8)
	if v >= 32768:
		v -= 65536
	return v
