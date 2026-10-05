extends Node3D
## One presentation path for runtime and editor. Authored light remains the baseline.
const Settings = preload("res://scripts/world3d/environment_settings.gd")
const Profile = preload("res://scripts/world3d/weather_profile.gd")
const Clouds = preload("res://scripts/world3d/cloud_resources.gd")
var cloud_resources_ready := false
var cloud_quality := 1
const Cycle = preload("res://scripts/world3d/celestial_cycle.gd")
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var observer: Node3D
var precipitation: Node3D
var wind_objects: Node3D
var streetlamps:Node3D
var wind_time := 0.0
var wind_velocity := Vector3.ZERO
var sky_material: ShaderMaterial
var sky: Sky
var flash: OmniLight3D
var lightning: Node3D
var wet_surfaces: Node3D
var moon: DirectionalLight3D
var wetness := 0.0
var enclosure := 0.0
var enclosure_target := 0.0
var roof_cover := 0.0
var roof_sound_mix := 0.0
var wind_audio: AudioStreamPlayer
var roof_audio: AudioStreamPlayer
var celestial: Dictionary = {}
var audio: AudioStreamPlayer
var values: Dictionary = {}
var current: Dictionary = {}
var source: Dictionary = {}
var target: Dictionary = {}
var mix_time := 0.0
var drift := Vector2.ZERO
var sheltered := false
var shelter_tick := 0.0
var next_lightning := 9.0
var flash_left := 0.0
var visuals_enabled := true
var editor_preview := false
var rng := RandomNumberGenerator.new()
var night_sky := preload("res://scripts/world3d/night_sky.gd").new()
var sky_provider: Callable
var sky_map := ""
var sky_poll := 0.0
var preview_sky: RefCounted
var preview_sky_key := ""
var server_environment_key := ""
var server_environment_dirty := false
signal environment_changed(config: Dictionary)

func bind_sky(map_id: String, provider: Callable) -> void:
	sky_map = map_id; sky_provider = provider; sky_poll = 0; night_sky.reset()
	server_environment_key = ""
	if lightning != null: lightning.reset()

func bind(view: Camera3D, light: DirectionalLight3D, env: Environment, actor: Node3D = null) -> void:
	camera = view; sun = light; environment = env; observer = actor
	if precipitation != null:
		precipitation.camera = view
		wind_objects.camera = view
		streetlamps.camera=view
		wet_surfaces.camera = view
		return
	rng.seed = 39517
	precipitation = preload("res://scripts/world3d/weather_precipitation.gd").new()
	add_child(precipitation); precipitation.camera = camera
	wind_objects = preload("res://scripts/world3d/wind_runtime.gd").new()
	add_child(wind_objects); wind_objects.camera = camera
	streetlamps=preload("res://scripts/world3d/streetlamp_lights.gd").new()
	streetlamps.weather=self;streetlamps.camera=camera;add_child(streetlamps)
	wet_surfaces = preload("res://scripts/world3d/wet_surface_runtime.gd").new()
	add_child(wet_surfaces); wet_surfaces.camera = camera
	wet_surfaces.scene_root = light.get_parent()
	if actor is CollisionObject3D: precipitation.exclude.assign([actor.get_rid()])
	wet_surfaces.exclude = precipitation.exclude
	sky_material = ShaderMaterial.new(); sky_material.shader = preload("res://scripts/world3d/weather_sky.gdshader")
	cloud_resources_ready = Clouds.bind(sky_material)
	sky = Sky.new(); sky.sky_material = sky_material; sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Small incremental radiance map keeps PBR reflections usable during cloud motion.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	lightning = preload("res://scripts/world3d/lightning_runtime.gd").new(); add_child(lightning)
	flash = lightning.light
	moon = DirectionalLight3D.new(); moon.name = "WeatherMoon"; moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.; moon.light_color = Color(.45,.55,.82); moon.light_energy = 0.; add_child(moon)
	audio = AudioStreamPlayer.new(); audio.bus = "Ambient"; add_child(audio)
	wind_audio = AudioStreamPlayer.new(); wind_audio.bus = "Ambient"; add_child(wind_audio)
	roof_audio = AudioStreamPlayer.new(); roof_audio.bus = "Ambient"; add_child(roof_audio)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null: settings.changed.connect(_settings_changed)
	_settings_changed()

func configure(config: Dictionary, instant := false) -> void:
	var new_target := Profile.sample(config)
	var changed: bool = new_target != target
	values = config.duplicate(true)
	if current.is_empty() or instant:
		night_sky.reset()
		sky_poll = 0
		current = new_target.duplicate(true); source = current.duplicate(true); target = new_target
		mix_time = float(values.weather_transition)
		precipitation.clear(); flash_left = 0; flash.light_energy = 0; next_lightning = 9
		wetness = float(values.initial_wetness); wet_surfaces.reset(); lightning.reset()
		enclosure = 0.; enclosure_target = 0.; roof_cover = 0.; roof_sound_mix = 0.; sheltered = false
	elif changed:
		source = current.duplicate(true); target = new_target; mix_time = 0
	if float(values.weather_transition) == 0: current = target.duplicate(true)
	Settings.apply(values, sun, environment)
	_apply()

func _settings_changed() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	cloud_quality = ["low","medium","high"].find(str(settings.cloud_quality)) if settings != null else 1
	if not cloud_resources_ready: cloud_quality = -1
	if sky_material != null: sky_material.set_shader_parameter("cloud_quality",cloud_quality)
	visuals_enabled = editor_preview or settings == null or bool(settings.weather_fx)
	if precipitation != null:
		precipitation.enabled = visuals_enabled
		if not visuals_enabled: precipitation.clear()
	if not visuals_enabled and flash != null:
		flash_left = 0; flash.light_energy = 0; lightning.bolt.visible = false
		for node in lightning.get_children():
			if node is AudioStreamPlayer3D: node.queue_free()
	if wet_surfaces != null:
		wet_surfaces.enabled = visuals_enabled
		if not visuals_enabled: wet_surfaces.clear()
	if not values.is_empty(): _apply()
	if wind_objects != null: wind_objects.advance(wind_velocity if visuals_enabled else Vector3.ZERO,wind_time)

func _process(delta: float) -> void:
	if values.is_empty() or environment == null: return
	var profile_start:=Time.get_ticks_usec() if has_meta("profile_frame") else 0
	_tick_night_sky(delta)
	var sky_end:=Time.get_ticks_usec() if profile_start>0 else 0
	var synchronized: bool = night_sky.ready and sky_provider.is_valid() and not editor_preview
	var cloud_synchronized: bool = night_sky.ready and (editor_preview or synchronized)
	if synchronized:
		var stamp := night_sky.local_time()+night_sky.clock_offset
		current = Profile.at(night_sky.snapshot,stamp)
	if cloud_synchronized:
		var stamp := night_sky.local_time()+night_sky.clock_offset
		wind_time = stamp; drift = Profile.drift_at(night_sky.snapshot,stamp)
	var transitioning := current != target
	if transitioning and not synchronized:
		mix_time += delta
		var weight := clampf(mix_time / maxf(.001, values.weather_transition), 0, 1)
		current = Profile.blend(source, target, weight*weight*(3-2*weight))
		if weight == 1: current = target.duplicate(true)
	if not cloud_synchronized: wind_time += delta
	# One coherent gust drives precipitation, clouds and all flexible map objects.
	wind_velocity = current.wind * Profile.gust(wind_time)
	# Cosmetic wetness is deliberately local: joining players need not match.
	var tau: float = values.wetting_seconds if current.rain > wetness else values.drying_seconds
	wetness = float(current.rain)+(wetness-float(current.rain))*exp(-delta/tau)
	wet_surfaces.enabled = visuals_enabled and values.surface_wetness
	wet_surfaces.wetness = wetness; wet_surfaces.puddles = smoothstep(.45,.95,wetness)*float(values.puddle_strength)
	wet_surfaces.rain = current.rain; wet_surfaces.time = wind_time
	enclosure = lerpf(enclosure,enclosure_target,1.-exp(-delta*3.))
	roof_sound_mix = lerpf(roof_sound_mix,roof_cover,1.-exp(-delta*3.))
	if not cloud_synchronized: drift += Vector2(wind_velocity.x,wind_velocity.z)*delta*.0006
	_tick_lightning(delta)
	if values.sky_enabled:
		var flash_position: Vector3 = lightning.light.global_position
		sky_material.set_shader_parameter("cloud_flash",Vector4(flash_position.x,flash_position.y,flash_position.z,lightning.light.light_energy/8.))
	if transitioning or server_environment_dirty or values.celestial_cycle: server_environment_dirty = false; _apply()
	elif values.sky_enabled: sky_material.set_shader_parameter("drift", drift)
	precipitation.wind = wind_velocity
	wind_objects.advance(wind_velocity if visuals_enabled else Vector3.ZERO,wind_time)
	_sync_audio()
	if profile_start>0:set_meta("frame_timing",{"frame":Engine.get_process_frames(),"sky_ms":(sky_end-profile_start)/1000.0,"ms":(Time.get_ticks_usec()-profile_start)/1000.0})

func _physics_process(delta: float) -> void:
	if precipitation == null or not is_instance_valid(camera): return
	shelter_tick -= delta
	if shelter_tick > 0: return
	shelter_tick = .2
	var point: Vector3 = observer.global_position + Vector3.UP*.65 if is_instance_valid(observer) else camera.global_position
	sheltered = not precipitation.cast(point, point + Vector3.UP*180).is_empty()
	var covers := 1. if sheltered else 0.; var walls := 0.
	for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var offset := point+direction*.65
		if not precipitation.cast(offset,offset+Vector3.UP*180).is_empty(): covers+=1.
		if not precipitation.cast(point,point+direction*3.).is_empty(): walls+=1.
	roof_cover = covers/5.; enclosure_target = roof_cover*(.45+.55*walls/4.)

func _tick_night_sky(delta: float) -> void:
	var now := night_sky.local_time()
	sky_poll -= delta
	if editor_preview:
		if preview_sky == null: preview_sky = preload("res://scripts/net/server/sky_module.gd").new()
		var key := str(values)
		if key != preview_sky_key:
			preview_sky_key = key
			if not preview_sky.maps.has("editor-preview"): preview_sky.configure("editor-preview",7321,values.meteor_frequency,values.meteors_enabled)
			preview_sky.set_environment("editor-preview",values,now); sky_poll = 0
		if sky_poll <= 0:
			night_sky.receive(preview_sky.snapshot("editor-preview",now),"editor-preview",now,now); sky_poll = 1
	elif sky_provider.is_valid() and sky_poll <= 0:
		var packet: Variant = sky_provider.call()
		if packet is Dictionary and night_sky.receive(packet,sky_map,now,night_sky.local_time()):
			var key := str([packet.epoch,packet.environment_revision])
			if server_environment_key != key:
				server_environment_key = key; values = packet.environment.duplicate(true)
				source = Profile.decode(packet.source_profile); target = Profile.sample(values)
				current = Profile.at(packet,now+night_sky.clock_offset)
				Settings.apply(values,sun,environment); server_environment_dirty = true
				environment_changed.emit(values.duplicate(true))
				streetlamps.refresh()
		sky_poll = 1
	night_sky.sample(now+night_sky.clock_offset)
	var hour: float = Cycle.hours(night_sky.snapshot,now+night_sky.clock_offset) if night_sky.ready else values.time_hours
	celestial = Cycle.sample(hour)
	var night: float = (float(celestial.night) if values.celestial_cycle else 1.0 if values.preset == "night" else 0.0) if values.sky_enabled else 0.0
	var visibility: float = pow(1.0-current.cloud*.8,2.0) * (1.0-clampf(current.fog*18.0,0,1))
	sky_material.set_shader_parameter("cloud_seed_offset",Clouds.seed_offset(night_sky.seed))
	sky_material.set_shader_parameter("star_seed",night_sky.seed)
	sky_material.set_shader_parameter("star_intensity",values.star_intensity*visibility*night if night_sky.ready else 0.0)
	sky_material.set_shader_parameter("star_time",night_sky.time)
	var heads := PackedVector3Array(); var tails := PackedVector3Array(); var energies := PackedFloat32Array(); var kinds := PackedFloat32Array(); var brightness := PackedFloat32Array()
	for i in 8:
		var row: Dictionary = night_sky.meteors[i] if i<night_sky.meteors.size() else {}
		heads.append(row.get("head",Vector3.UP)); tails.append(row.get("tail",Vector3.UP))
		energies.append(row.get("energy",0.0)*visibility*night if visuals_enabled and values.meteors_enabled else 0.0)
		kinds.append(1.0 if row.get("kind")=="fireball" else 0.0); brightness.append(row.get("brightness",0.0))
	sky_material.set_shader_parameter("meteor_heads",heads); sky_material.set_shader_parameter("meteor_tails",tails)
	sky_material.set_shader_parameter("meteor_energies",energies); sky_material.set_shader_parameter("meteor_kinds",kinds); sky_material.set_shader_parameter("meteor_brightness",brightness)

func _tick_lightning(delta: float) -> void:
	if not night_sky.ready: return
	var point: Vector3 = observer.global_position if is_instance_valid(observer) else camera.global_position
	lightning.advance(night_sky.snapshot,night_sky.local_time()+night_sky.clock_offset,point,enclosure,visuals_enabled and values.lightning_enabled,visuals_enabled and values.environment_audio and values.thunder_enabled and not editor_preview)

func _apply() -> void:
	if current.is_empty(): return
	_tick_night_sky(0)
	var strength: float = current.sun
	sun.light_energy = float(values.sun_energy) * strength
	environment.ambient_light_energy = float(values.ambient_energy) * lerpf(.78,1,strength)
	var background := Settings.color(values.background_color)
	var night := clampf(float(values.sun_energy)/.8, .035, 1)
	moon.light_energy = 0.
	if values.celestial_cycle:
		if celestial.is_empty(): celestial = Cycle.sample(float(values.time_hours))
		background = celestial.background_color; night = lerpf(.035,1.,celestial.day)
		sun.look_at(sun.global_position-celestial.sun_direction,Vector3.FORWARD)
		moon.look_at(moon.global_position-celestial.moon_direction,Vector3.FORWARD)
		sun.light_color = celestial.sun_color; sun.light_energy = celestial.sun_energy*strength
		moon.light_energy = celestial.moon_energy*strength; moon.shadow_enabled = values.sun_shadows
		environment.ambient_light_color = celestial.ambient_color
		environment.ambient_light_energy = celestial.ambient_energy*lerpf(.78,1,strength)
	var cloud_color := background.lerp(Color(.61,.66,.72)*night, .62)
	var overcast: float = maxf(current.rain*.35, current.storm*.8)
	var sky_color := background.lerp(Color(.23,.28,.35)*night,overcast)
	var dusk := (1.0 if values.preset == "sunset" else 0.0) * (1.0-overcast)
	if values.celestial_cycle: dusk = float(celestial.dusk)*(1.-overcast)
	var zenith_color := (sky_color*Color(.62,.77,.96)).lerp(Color(.21,.27,.43),dusk*.85)
	var horizon_color := sky_color.lerp(cloud_color,.25).lerp(Color(.83,.48,.28),dusk*.7)
	environment.fog_enabled = bool(values.fog_enabled) or current.fog > .0001
	environment.fog_density = maxf(float(values.fog_density) if values.fog_enabled else 0, current.fog)
	environment.fog_light_color = Settings.color(values.fog_color) if values.fog_enabled else cloud_color
	# Distant geometry recedes into mist without replacing the entire sky with a flat color.
	environment.fog_sky_affect = lerpf(.18,.65,clampf((current.fog-.02)/.03,0,1))
	if values.sky_enabled:
		environment.background_mode = Environment.BG_SKY; environment.sky = sky
		sky_material.set_shader_parameter("zenith", zenith_color)
		sky_material.set_shader_parameter("horizon", horizon_color)
		sky_material.set_shader_parameter("dusk_amount",dusk)
		sky_material.set_shader_parameter("cloud_tint", cloud_color*lerpf(.66,1.28,strength))
		sky_material.set_shader_parameter("cloud_cover", current.cloud)
		sky_material.set_shader_parameter("cloud_storm", current.storm)
		for parameter in ["cloud_altitude","cloud_thickness","cloud_scale","cirrus_amount"]:
			sky_material.set_shader_parameter(parameter,values[parameter])
		sky_material.set_shader_parameter("sun_direction", sun.global_basis.z)
		sky_material.set_shader_parameter("moon_direction", celestial.moon_direction if values.celestial_cycle else sun.global_basis.z)
		sky_material.set_shader_parameter("sun_tint", sun.light_color)
		sky_material.set_shader_parameter("daylight", night)
		sky_material.set_shader_parameter("night_amount",celestial.night if values.celestial_cycle else 1.0 if values.preset == "night" else 0.0)
		sky_material.set_shader_parameter("drift", drift)
	else:
		environment.background_mode = Environment.BG_COLOR; environment.sky = null
	precipitation.rain = current.rain; precipitation.snow = current.snow; precipitation.storm = current.storm
	precipitation.wind = current.wind; precipitation.brightness = lerpf(.18,1,night)
	_sync_audio()

func _sync_audio() -> void:
	var enabled: bool = visuals_enabled and values.environment_audio and not editor_preview
	var amount: float = current.rain if enabled else 0.0
	_loop(audio,amount*(1.-enclosure*.78),"rain",-10.)
	_loop(roof_audio,amount*roof_sound_mix*(.25+.75*enclosure),"roof",-17.)
	_loop(wind_audio,clampf(wind_velocity.length()/18.,0,1)*(1.-enclosure*.94) if enabled else 0.,"wind",-15.)

func _loop(player: AudioStreamPlayer, volume: float, kind: String, gain: float) -> void:
	if volume<.005:
		if player.playing: player.stop()
		return
	if player.stream==null:
		player.stream=preload("res://scripts/map/map_sfx.gd").ambient("rain") if kind=="rain" else preload("res://scripts/world3d/weather_sound.gd").stream(kind)
	player.volume_db=linear_to_db(volume)+gain
	if not player.playing: player.play()
