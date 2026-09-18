extends CanvasLayer
## Screen-space rain/snow/fog/lightning. Stays below the HUD canvas.

const MapSfx = preload("res://scripts/map/map_sfx.gd")
const Weather = preload("res://scripts/map/weather.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

var _rain: CPUParticles2D
var _storm: CPUParticles2D
var _snow: CPUParticles2D
var _mist: CPUParticles2D
var _fog: ColorRect
var _flash: ColorRect
var _sfx: AudioStreamPlayer
var _sfx2: AudioStreamPlayer
var _atm: Dictionary = {}
var _from_atm: Dictionary = {}
var _tgt_atm: Dictionary = {}
var _mix: float = 1.0
var _eaves: bool = false
var _flash_left: float = 0.0
var _next_flash: float = 2.5


func _init() -> void:
	layer = Weather.CANVAS_ATMOSPHERE
	follow_viewport_enabled = false


func _ready() -> void:
	layer = Weather.CANVAS_ATMOSPHERE
	follow_viewport_enabled = false
	_rain = _make_particles("Rain", _load_fx("weather_storm.png", _streak_tex()), 340)
	_storm = _make_particles("Storm", _load_fx("weather_rain.png", _streak_tex()), 380)
	_snow = _make_particles("Snow", _load_fx("weather_snow.png", _dot_tex()), 110)
	_mist = _make_particles("Mist", _load_fx("weather_fog.png", _dot_tex()), 36)
	_setup_rain_flags(_rain)
	_setup_rain_flags(_storm)
	_fog = ColorRect.new()
	_fog.name = "Fog"
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.color = Color(0, 0, 0, 0)
	add_child(_fog)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	_sfx = _make_sfx("WeatherSfx")
	_sfx2 = _make_sfx("WeatherSfx2")
	_setup_rain(false, 0.0)
	_setup_storm(false, 0.0)
	_setup_snow(false, 0.0)
	_setup_mist(false, 0.0)


func apply(atm: Dictionary) -> void:
	atm = atm.duplicate(true)
	if _tgt_atm.is_empty():
		_from_atm = atm
		_tgt_atm = atm
		_mix = 1.0
		_atm = atm
		_sync_visuals()
		_sync_sfx()
		return
	if _visually_same(_tgt_atm, atm) and _mix >= 0.999:
		_tgt_atm = atm
		_from_atm = atm
		_atm = atm
		return
	_from_atm = blended()
	_tgt_atm = atm
	_atm = atm
	_mix = 0.0


func blended() -> Dictionary:
	return Weather.blend(_from_atm, _tgt_atm, _mix)


func display_modulate() -> Color:
	var b: Dictionary = blended()
	var c: Variant = b.get("modulate", Color.WHITE)
	if typeof(c) == TYPE_COLOR:
		return c
	return Color.WHITE


func mix_t() -> float:
	return _mix


func last_atmosphere() -> Dictionary:
	return _atm


func _visually_same(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("kind", "")) != str(b.get("kind", "")):
		return false
	if str(a.get("particles", "")) != str(b.get("particles", "")):
		return false
	if bool(a.get("map_indoor", false)) != bool(b.get("map_indoor", false)):
		return false
	if absf(float(a.get("intensity", 0.0)) - float(b.get("intensity", 0.0))) > 0.03:
		return false
	var ca := Weather._as_color(a.get("modulate", Color.WHITE))
	var cb := Weather._as_color(b.get("modulate", Color.WHITE))
	return ca.is_equal_approx(cb)


func _make_sfx(p_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = p_name
	p.volume_db = -12.0
	p.bus = "Ambient"
	add_child(p)
	return p


func set_eaves(on: bool) -> void:
	if _eaves == on:
		return
	_eaves = on
	_sync_visuals()
	_sync_sfx()


func _process(delta: float) -> void:
	if _mix < 1.0:
		_mix = minf(1.0, _mix + delta / Weather.transition_sec())
		_sync_visuals()
		_sync_sfx()
		if _mix >= 1.0:
			_from_atm = _tgt_atm
	var vs := Vector2(1280, 720)
	var vp := get_viewport()
	if vp:
		vs = vp.get_visible_rect().size
	if _rain:
		_rain.position = vs * 0.5
		_rain.emission_rect_extents = vs * Vector2(0.6, 0.15)
	if _storm:
		_storm.position = vs * 0.5
		_storm.emission_rect_extents = vs * Vector2(0.62, 0.16)
	if _snow:
		_snow.position = vs * Vector2(0.5, 0.08)
		_snow.emission_rect_extents = vs * Vector2(0.55, 0.08)
	if _mist:
		_mist.position = vs * 0.5
		_mist.emission_rect_extents = vs * Vector2(0.5, 0.28)
	var disp: Dictionary = blended()
	if GameSettingsScript.flag("weather_fx", true) and bool(disp.get("lightning", false)) and not _eaves and float(disp.get("intensity", 0)) > 0.25:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_flash_left = 0.12
			_next_flash = randf_range(2.2, 6.5)
			if _sfx and str(_atm.get("sfx", "")) == "storm":
				_sfx.pitch_scale = randf_range(0.92, 1.08)
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_flash.color = Color(1, 1, 1, clampf(_flash_left / 0.12 * 0.45, 0.0, 0.45))
	elif _flash:
		_flash.color = Color(1, 1, 1, 0)


func _sync_visuals() -> void:
	if _rain == null:
		return
	if not GameSettingsScript.flag("weather_fx", true):
		_setup_rain(false, 0.0)
		_setup_storm(false, 0.0)
		_setup_snow(false, 0.0)
		_setup_mist(false, 0.0)
		if _fog:
			_fog.color = Color(_fog.color.r, _fog.color.g, _fog.color.b, 0)
		if _flash:
			_flash.color = Color(1, 1, 1, 0)
		return
	var disp: Dictionary = blended()
	var hide := _eaves or bool(disp.get("map_indoor", false))
	var rain_w := float(disp.get("rain_weight", 0.0))
	var storm_w := float(disp.get("storm_weight", 0.0))
	var snow_w := float(disp.get("snow_weight", 0.0))
	var fog_w := float(disp.get("fog_weight", 0.0))
	if hide:
		rain_w = 0.0
		storm_w = 0.0
		snow_w = 0.0
		fog_w = 0.0
	_setup_rain(rain_w > 0.02, rain_w)
	_setup_storm(storm_w > 0.02, storm_w)
	_setup_snow(snow_w > 0.02, snow_w)
	_setup_mist(fog_w > 0.04, fog_w)
	var fog_a := float(disp.get("fog", 0.0))
	if hide:
		fog_a = 0.0
	var fc: Color = Weather._as_color(disp.get("fog_color", Color(0.7, 0.75, 0.8, 1)), Color(0.7, 0.75, 0.8, 1))
	_fog.color = Color(fc.r, fc.g, fc.b, clampf(fog_a, 0.0, 0.7))


func _sync_sfx() -> void:
	if _sfx == null:
		return
	if not GameSettingsScript.flag("weather_fx", true):
		_stop_sfx(_sfx)
		_stop_sfx(_sfx2)
		return
	var disp: Dictionary = blended()
	if bool(disp.get("map_indoor", false)):
		_stop_sfx(_sfx)
		_stop_sfx(_sfx2)
		return
	var from_k := str(disp.get("sfx_from", disp.get("sfx", ""))).strip_edges()
	var to_k := str(disp.get("sfx_to", disp.get("sfx", ""))).strip_edges()
	var t := float(disp.get("sfx_t", 1.0))
	var peek := -16.0 if _eaves else -10.0
	var mute := -48.0
	if from_k == to_k:
		_stop_sfx(_sfx2)
		_play_kind(_sfx, from_k, peek)
		return
	_play_kind(_sfx, from_k, lerpf(peek, mute, t))
	_play_kind(_sfx2, to_k, lerpf(mute, peek, t))


func _play_kind(p: AudioStreamPlayer, kind: String, vol: float) -> void:
	if p == null:
		return
	kind = kind.strip_edges()
	if kind == "":
		_stop_sfx(p)
		return
	var stream: AudioStream = MapSfx.ambient(kind)
	if stream == null:
		_stop_sfx(p)
		return
	if p.stream != stream:
		p.stream = stream
	p.volume_db = vol
	if not p.playing:
		p.play()


func _stop_sfx(p: AudioStreamPlayer) -> void:
	if p == null:
		return
	if p.playing:
		p.stop()
	p.stream = null


func _setup_rain(on: bool, amt: float) -> void:
	if _rain == null:
		return
	_rain.lifetime = 0.85
	_rain.direction = Vector2(0.16, 1)
	_rain.spread = 5.0
	_rain.gravity = Vector2(40, 980)
	_rain.initial_velocity_min = 360.0
	_rain.initial_velocity_max = 500.0
	_rain.scale_amount_min = 0.012
	_rain.scale_amount_max = 0.022
	_rain.modulate = Color(1, 1, 1, clampf(amt / 1.2, 0.0, 1.0))
	_rain.emitting = on


func _setup_storm(on: bool, amt: float) -> void:
	if _storm == null:
		return
	_storm.lifetime = 0.62
	_storm.direction = Vector2(0.28, 1)
	_storm.spread = 8.0
	_storm.gravity = Vector2(80, 1200)
	_storm.initial_velocity_min = 480.0
	_storm.initial_velocity_max = 640.0
	_storm.scale_amount_min = 0.016
	_storm.scale_amount_max = 0.028
	_storm.modulate = Color(1, 1, 1, clampf(amt / 1.7, 0.0, 1.0))
	_storm.emitting = on


func _setup_snow(on: bool, amt: float) -> void:
	if _snow == null:
		return
	_snow.lifetime = 4.2
	_snow.direction = Vector2(0.18, 1)
	_snow.spread = 36.0
	_snow.gravity = Vector2(8, 22)
	_snow.initial_velocity_min = 14.0
	_snow.initial_velocity_max = 38.0
	_snow.angular_velocity_min = -55.0
	_snow.angular_velocity_max = 55.0
	_snow.angle_min = -180.0
	_snow.angle_max = 180.0
	_snow.scale_amount_min = 0.011
	_snow.scale_amount_max = 0.022
	_snow.modulate = Color(1, 1, 1, clampf(amt, 0.0, 1.0))
	_snow.emitting = on


func _setup_mist(on: bool, amt: float) -> void:
	if _mist == null:
		return
	_mist.lifetime = 7.5
	_mist.direction = Vector2(1, 0.08)
	_mist.spread = 18.0
	_mist.gravity = Vector2(0, 2)
	_mist.initial_velocity_min = 8.0
	_mist.initial_velocity_max = 22.0
	_mist.scale_amount_min = 0.08
	_mist.scale_amount_max = 0.18
	_mist.modulate = Color(1, 1, 1, clampf(amt * 1.4, 0.0, 0.85))
	_mist.emitting = on


func _setup_rain_flags(p: CPUParticles2D) -> void:
	if p == null:
		return
	p.particle_flag_align_y = true


func _load_fx(fname: String, fallback: Texture2D) -> Texture2D:
	var path := "res://assets/fx/%s" % fname
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return fallback


func _make_particles(p_name: String, tex: Texture2D, count: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = p_name
	p.texture = tex
	p.emitting = false
	p.amount = count
	p.modulate = Color(1, 1, 1, 0)
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.z_index = 10
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(p)
	return p


func _streak_tex() -> Texture2D:
	var img := Image.create(2, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(10):
		var a := 0.15 + 0.08 * float(y)
		img.set_pixel(0, y, Color(0.82, 0.88, 0.95, a))
		img.set_pixel(1, y, Color(0.82, 0.88, 0.95, a * 0.6))
	return ImageTexture.create_from_image(img)


func _dot_tex() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(1, 1, Color(0.95, 0.97, 1.0, 0.9))
	img.set_pixel(2, 1, Color(0.95, 0.97, 1.0, 0.7))
	img.set_pixel(1, 2, Color(0.95, 0.97, 1.0, 0.7))
	img.set_pixel(2, 2, Color(0.95, 0.97, 1.0, 0.5))
	return ImageTexture.create_from_image(img)
