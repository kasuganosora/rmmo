extends CanvasLayer
## Screen-space rain/snow/fog/lightning. Stays below the HUD canvas.

const MapSfx = preload("res://scripts/map/map_sfx.gd")
const Weather = preload("res://scripts/map/weather.gd")

var _rain: CPUParticles2D
var _snow: CPUParticles2D
var _fog: ColorRect
var _flash: ColorRect
var _sfx: AudioStreamPlayer
var _atm: Dictionary = {}
var _eaves: bool = false
var _flash_left: float = 0.0
var _next_flash: float = 2.5


func _init() -> void:
	layer = Weather.CANVAS_ATMOSPHERE
	follow_viewport_enabled = false


func _ready() -> void:
	layer = Weather.CANVAS_ATMOSPHERE
	follow_viewport_enabled = false
	_rain = _make_particles("Rain", _streak_tex())
	_snow = _make_particles("Snow", _dot_tex())
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
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "WeatherSfx"
	_sfx.volume_db = -12.0
	add_child(_sfx)
	apply({})


func apply(atm: Dictionary) -> void:
	_atm = atm
	_sync_visuals()
	_sync_sfx()


func set_eaves(on: bool) -> void:
	if _eaves == on:
		return
	_eaves = on
	_sync_visuals()
	_sync_sfx()


func last_atmosphere() -> Dictionary:
	return _atm


func _process(delta: float) -> void:
	var vs := Vector2(1280, 720)
	var vp := get_viewport()
	if vp:
		vs = vp.get_visible_rect().size
	if _rain:
		_rain.position = vs * 0.5
		_rain.emission_rect_extents = vs * Vector2(0.6, 0.15)
	if _snow:
		_snow.position = vs * Vector2(0.5, 0.08)
		_snow.emission_rect_extents = vs * Vector2(0.55, 0.08)
	if bool(_atm.get("lightning", false)) and not _eaves and float(_atm.get("intensity", 0)) > 0.25:
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
	var hide := _eaves or bool(_atm.get("map_indoor", false))
	var pkind := str(_atm.get("particles", ""))
	var amt := float(_atm.get("particle_amount", 0.0))
	_setup_rain(pkind == "rain" and not hide and amt > 0.02, amt)
	_setup_snow(pkind == "snow" and not hide and amt > 0.02, amt)
	var fog_a := float(_atm.get("fog", 0.0))
	if hide:
		fog_a = 0.0
	var fc: Color = _atm.get("fog_color", Color(0.7, 0.75, 0.8, 1))
	if typeof(fc) != TYPE_COLOR:
		fc = Color(0.7, 0.75, 0.8, 1)
	_fog.color = Color(fc.r, fc.g, fc.b, clampf(fog_a, 0.0, 0.7))


func _sync_sfx() -> void:
	if _sfx == null:
		return
	var kind := str(_atm.get("sfx", "")).strip_edges()
	if kind == "" or bool(_atm.get("map_indoor", false)):
		if _sfx.playing:
			_sfx.stop()
		_sfx.stream = null
		return
	var stream: AudioStream = MapSfx.ambient(kind)
	if _sfx.stream != stream:
		_sfx.stream = stream
	_sfx.volume_db = -16.0 if _eaves else -10.0
	if not _sfx.playing:
		_sfx.play()


func _setup_rain(on: bool, amt: float) -> void:
	_rain.emitting = on
	if not on:
		return
	_rain.amount = clampi(int(80 * amt), 24, 160)
	_rain.lifetime = 0.7
	_rain.direction = Vector2(0.18, 1)
	_rain.spread = 6.0
	_rain.gravity = Vector2(0, 980)
	_rain.initial_velocity_min = 380.0
	_rain.initial_velocity_max = 520.0
	_rain.scale_amount_min = 0.8
	_rain.scale_amount_max = 1.4


func _setup_snow(on: bool, amt: float) -> void:
	_snow.emitting = on
	if not on:
		return
	_snow.amount = clampi(int(40 * amt), 12, 80)
	_snow.lifetime = 3.4
	_snow.direction = Vector2(0.12, 1)
	_snow.spread = 28.0
	_snow.gravity = Vector2(0, 28)
	_snow.initial_velocity_min = 18.0
	_snow.initial_velocity_max = 42.0
	_snow.scale_amount_min = 0.7
	_snow.scale_amount_max = 1.6


func _make_particles(p_name: String, tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = p_name
	p.texture = tex
	p.emitting = false
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.z_index = 10
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
