extends CanvasLayer
## Screen-space rain/snow/fog/lightning. Stays below the HUD canvas.

const MapSfx = preload("res://scripts/map/map_sfx.gd")
const Weather = preload("res://scripts/map/weather.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

var _rain: CPUParticles2D
var _storm: CPUParticles2D
var _snow: CPUParticles2D
var _snow_far: CPUParticles2D
var _snow_near: CPUParticles2D
var _snow_crystal: CPUParticles2D
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
var _display: Dictionary = {}
var _viewport_size := Vector2.ZERO
var _wind_time := 0.0
var _wind_tick := 0.0


func _init() -> void:
	layer = Weather.CANVAS_ATMOSPHERE
	follow_viewport_enabled = false


func _ready() -> void:
	layer = Weather.CANVAS_ATMOSPHERE
	follow_viewport_enabled = false
	_rain = _make_particles("Rain", _gradient_tex(Vector2i(2, 18), false), 220)
	_storm = _make_particles("Storm", _gradient_tex(Vector2i(2, 28), false), 360)
	_snow = _make_particles("Snow", _gradient_tex(Vector2i(8, 8), true), 260)
	_snow_far = _make_particles("SnowFar", _gradient_tex(Vector2i(4, 4), true), 180)
	_snow_near = _make_particles("SnowNear", _gradient_tex(Vector2i(16, 16), true), 65)
	_snow_crystal = _make_particles("SnowCrystal", _gradient_tex(Vector2i(32, 32), true), 24)
	var crystal_material := ShaderMaterial.new()
	crystal_material.shader = preload("res://scripts/map/snow_crystal.gdshader")
	_snow_crystal.material = crystal_material
	_mist = _make_particles("Mist", _gradient_tex(Vector2i(128, 64), true), 18)
	_setup_rain_flags(_rain)
	_setup_rain_flags(_storm)
	_fog = ColorRect.new()
	_fog.name = "Fog"
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog.color = Color(0, 0, 0, 0)
	add_child(_fog)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.z_index = 20
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	_sfx = _make_sfx("WeatherSfx")
	_sfx2 = _make_sfx("WeatherSfx2")
	_configure_particles()
	_resize_emitters()
	get_viewport().size_changed.connect(_resize_emitters)
	var settings := get_node_or_null("/root/GameSettings")
	if settings:
		settings.changed.connect(_settings_changed)


func apply(atm: Dictionary) -> void:
	atm = atm.duplicate(true)
	if _tgt_atm.is_empty():
		_from_atm = atm
		_tgt_atm = atm
		_mix = 1.0
		_atm = atm
		_refresh_display()
		_sync_visuals()
		_sync_sfx()
		return
	if _visually_same(_tgt_atm, atm):
		_tgt_atm = atm
		_atm = atm
		return
	_from_atm = blended()
	_tgt_atm = atm
	_atm = atm
	_mix = 0.0
	_refresh_display()
	_sync_visuals()
	_sync_sfx()


func blended() -> Dictionary:
	return _display.duplicate(true)


func display_modulate() -> Color:
	var b: Dictionary = _display
	var c: Variant = b.get("modulate", Color.WHITE)
	if typeof(c) == TYPE_COLOR:
		return c
	return Color.WHITE


func mix_t() -> float:
	return _mix


func last_atmosphere() -> Dictionary:
	return _atm


func _refresh_display() -> void:
	_display = Weather.blend(_from_atm, _tgt_atm, _mix)


func _visually_same(a: Dictionary, b: Dictionary) -> bool:
	for key in ["kind", "particles", "map_indoor", "intensity", "modulate", "particle_amount", "fog", "fog_color", "lightning", "sfx"]:
		if a.get(key) != b.get(key):
			return false
	return true


func _settings_changed() -> void:
	_sync_visuals()
	_sync_sfx()


func _resize_emitters() -> void:
	_viewport_size = get_viewport().get_visible_rect().size
	# Spawn throughout the view with lifetime fades: no horizontal birth band,
	# no long warm-up, and coverage is independent of fall speed / window height.
	for p in [_rain, _storm, _snow, _snow_far, _snow_near, _snow_crystal, _mist]:
		p.position = _viewport_size * 0.5
		p.emission_rect_extents = _viewport_size * 0.55
	_fog.size = _viewport_size
	_flash.size = _viewport_size


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
	if _snow.emitting:
		_wind_time += delta
		_wind_tick += delta
		if _wind_tick >= 0.1:
			_wind_tick = 0.0
			_snow.gravity.x = sin(_wind_time * 0.7) * 9.0
			_snow_far.gravity.x = sin(_wind_time * 0.5 + 1.0) * 3.0
			_snow_near.gravity.x = sin(_wind_time * 0.65 + 2.0) * 16.0
			_snow_crystal.gravity.x = sin(_wind_time * 0.8 + 0.7) * 11.0
	if _mix < 1.0:
		_mix = minf(1.0, _mix + delta / Weather.transition_sec())
		_refresh_display()
		_sync_visuals()
		_sync_sfx()
		if _mix >= 1.0:
			_from_atm = _tgt_atm
	var disp: Dictionary = _display
	if GameSettingsScript.flag("weather_fx", true) and bool(disp.get("lightning", false)) and not _eaves and not bool(_atm.get("map_indoor", false)) and float(disp.get("intensity", 0)) > 0.25:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_flash_left = 0.12
			_next_flash = randf_range(2.2, 6.5)
			if _sfx and str(_atm.get("sfx", "")) == "storm":
				_sfx.pitch_scale = randf_range(0.92, 1.08)
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		_flash.color = Color(1, 1, 1, clampf(_flash_left / 0.12 * 0.22, 0.0, 0.22))
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
		_flash_left = 0.0
		if _flash:
			_flash.color = Color(1, 1, 1, 0)
		return
	var disp: Dictionary = _display
	var hide := _eaves or bool(_atm.get("map_indoor", false))
	var rain_w := float(disp.get("rain_weight", 0.0))
	var storm_w := float(disp.get("storm_weight", 0.0))
	var snow_w := float(disp.get("snow_weight", 0.0))
	var fog_w := float(disp.get("fog_weight", 0.0))
	if hide:
		_flash_left = 0.0
		_flash.color.a = 0.0
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
	_fog.color = Color(fc.r, fc.g, fc.b, clampf(fog_a * 0.55, 0.0, 0.28))


func _sync_sfx() -> void:
	if _sfx == null:
		return
	if not GameSettingsScript.flag("weather_fx", true):
		_stop_sfx(_sfx)
		_stop_sfx(_sfx2)
		return
	var disp: Dictionary = _display
	if bool(_atm.get("map_indoor", false)):
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


# Constant particle properties are configured once, never during crossfades.
func _configure_particles() -> void:
	_rain.lifetime = 0.8
	_rain.direction = Vector2(0.12, 1)
	_rain.spread = 2.0
	_rain.gravity = Vector2.ZERO
	_rain.initial_velocity_min = 460.0
	_rain.initial_velocity_max = 600.0
	_rain.scale_amount_min = 0.55
	_rain.scale_amount_max = 0.9
	_storm.lifetime = 0.65
	_storm.direction = Vector2(0.38, 1)
	_storm.spread = 4.0
	_storm.gravity = Vector2.ZERO
	_storm.initial_velocity_min = 680.0
	_storm.initial_velocity_max = 880.0
	_storm.scale_amount_min = 0.65
	_storm.scale_amount_max = 1.15
	_snow.lifetime = 5.5
	_snow.direction = Vector2(0.2, 1)
	_snow.spread = 26.0
	_snow.gravity = Vector2(2, 3)
	_snow.initial_velocity_min = 18.0
	_snow.initial_velocity_max = 42.0
	_snow.scale_amount_min = 0.55
	_snow.scale_amount_max = 1.25
	_snow.angular_velocity_min = -35.0
	_snow.angular_velocity_max = 35.0
	_configure_snow_layer(_snow_far, 8.0, Vector2(10, 22), Vector2(0.6, 1.15), 4)
	_configure_snow_layer(_snow_near, 4.8, Vector2(38, 65), Vector2(0.65, 1.2), 12)
	_configure_snow_layer(_snow_crystal, 6.0, Vector2(22, 40), Vector2(0.35, 0.65), 13)
	var shimmer := Gradient.new()
	shimmer.offsets = PackedFloat32Array([0, 0.15, 0.3, 0.4, 0.55, 0.65, 0.8, 1])
	shimmer.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.75), Color.WHITE, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	_snow_crystal.color_ramp = shimmer
	_mist.lifetime = 9.0
	_mist.direction = Vector2(1, -0.06)
	_mist.spread = 10.0
	_mist.gravity = Vector2.ZERO
	_mist.initial_velocity_min = 8.0
	_mist.initial_velocity_max = 18.0
	_mist.scale_amount_min = 2.5
	_mist.scale_amount_max = 5.0
	_mist.z_index = 1


func _configure_snow_layer(p: CPUParticles2D, life: float, speed: Vector2, sizes: Vector2, depth: int) -> void:
	p.lifetime = life
	p.direction = Vector2(0.25, 1)
	p.spread = 32.0
	p.gravity = Vector2(0, 2)
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.scale_amount_min = sizes.x
	p.scale_amount_max = sizes.y
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -28.0
	p.angular_velocity_max = 28.0
	p.z_index = depth


func _set_weight(p: CPUParticles2D, on: bool, weight: float, tint: Color) -> void:
	p.modulate = Color(tint.r, tint.g, tint.b, weight)
	p.visible = on
	p.emitting = on
	# Fully hidden systems stop simulation immediately, including live tails.
	p.set_process_internal(on)


func _setup_rain(on: bool, amt: float) -> void:
	_set_weight(_rain, on, clampf(amt * 0.52, 0.0, 0.65), Color(0.72, 0.83, 0.94))


func _setup_storm(on: bool, amt: float) -> void:
	_set_weight(_storm, on, clampf(amt * 0.38, 0.0, 0.7), Color(0.76, 0.84, 0.95))


func _setup_snow(on: bool, amt: float) -> void:
	_set_weight(_snow, on, clampf(amt, 0.0, 0.9), Color(0.93, 0.97, 1.0))
	_set_weight(_snow_far, on, clampf(amt * 0.6, 0.0, 0.65), Color(0.76, 0.87, 1.0))
	_set_weight(_snow_near, on, clampf(amt * 0.8, 0.0, 0.8), Color(0.92, 0.97, 1.0))
	_set_weight(_snow_crystal, on, clampf(amt, 0.0, 1.0), Color(0.88, 0.96, 1.0))


func _setup_mist(on: bool, amt: float) -> void:
	_set_weight(_mist, on, clampf(amt * 0.42, 0.0, 0.2), Color(0.77, 0.84, 0.89))


func _setup_rain_flags(p: CPUParticles2D) -> void:
	p.particle_flag_align_y = true


func _make_particles(p_name: String, tex: Texture2D, count: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = p_name
	p.texture = tex
	p.emitting = false
	p.visible = false
	p.amount = count
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.z_index = 10
	p.fixed_fps = 60 if p_name in ["Rain", "Storm"] else 30
	p.fract_delta = true
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.65, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	add_child(p)
	p.set_process_internal(false)
	return p


# Code-native gradients have explicit screen-pixel dimensions. No dependency on
# externally padded sprites or scale factors that erase fallback particles.
func _gradient_tex(size: Vector2i, radial: bool) -> Texture2D:
	var gradient := Gradient.new()
	if radial:
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0)])
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0.3)])
	var tex := GradientTexture2D.new()
	tex.width = size.x
	tex.height = size.y
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.5) if radial else Vector2(0.5, 0)
	tex.fill_to = Vector2(0.5, 1)
	return tex
