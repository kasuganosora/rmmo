extends RefCounted
## 基础设施层：世界环境 —— 光照/大气/天气、地图预设、音频加载与播放、地图观察器。
## 静态方法接收组合根 ctrl；节点创建（音频播放器）经 ctrl.add_child() 回调组合根。

const Net = preload("res://scripts/net/net.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const MapSfx = preload("res://scripts/map/map_sfx.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const JsonUtil = preload("res://scripts/util/json_util.gd")

static func _load_map_presets(ctrl) -> void:
	ctrl._light_presets = ctrl._read_preset_file("res://data/map/light_presets.json")
	ctrl._sound_presets = ctrl._read_preset_file("res://data/map/sound_presets.json")
	ctrl._pin_hud_canvas()
	# Day/night tints World canvas items (map, actors). Do not use CanvasModulate —
	# it multiplies every canvas in the viewport, including the HUD.
	if ctrl._bgs_player == null:
		ctrl._bgs_player = AudioStreamPlayer.new()
		ctrl._bgs_player.name = "MapBgs"
		ctrl._bgs_player.bus = "Ambient"
		ctrl.add_child(ctrl._bgs_player)
	if ctrl._bgm_player == null:
		ctrl._bgm_player = AudioStreamPlayer.new()
		ctrl._bgm_player.name = "MapBgm"
		ctrl._bgm_player.bus = "BGM"
		ctrl.add_child(ctrl._bgm_player)
	if ctrl._se_player == null:
		ctrl._se_player = AudioStreamPlayer.new()
		ctrl._se_player.name = "MapSe"
		ctrl._se_player.volume_db = -4.0
		ctrl._se_player.bus = "SFX"
		ctrl.add_child(ctrl._se_player)
	if ctrl._foot_player == null:
		ctrl._foot_player = AudioStreamPlayer.new()
		ctrl._foot_player.name = "Footstep"
		ctrl._foot_player.volume_db = -8.0
		ctrl._foot_player.bus = "SFX"
		ctrl.add_child(ctrl._foot_player)

static func _read_preset_file(ctrl, path: String) -> Dictionary:
	var parsed: Variant = JsonUtil.parse_file(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	if typeof(d.get("presets")) == TYPE_DICTIONARY:
		return d["presets"]
	return d

static func _sync_map_observer(ctrl) -> void:
	if ctrl.player == null or ctrl.map_field == null:
		return
	var cell: Vector2i = ctrl.player.cell if "cell" in ctrl.player else Vector2i.ZERO
	var facing := 2
	if ctrl.player.has_method("get_facing"):
		facing = int(CharsetSheet.dir_from_facing(str(ctrl.player.get_facing())))
	if ctrl.map_field.has_method("set_observer"):
		ctrl.map_field.set_observer(cell, facing)
	ctrl._apply_cell_settings(cell)

static func _apply_cell_settings(ctrl, cell: Vector2i) -> void:
	if ctrl.map_field == null or ctrl.map_field.collision == null:
		return
	var col = ctrl.map_field.collision
	if not col.has_method("settings_at"):
		return
	var packed: int = int(col.settings_at(cell.x, cell.y))
	var light_id: int = packed & 0xff
	var sound_id: int = (packed >> 8) & 0xff
	ctrl._last_foot_kind = (packed >> 16) & 0xff
	if packed == 0 and ctrl.map_field != null and ctrl.map_field.pack != null and "light_preset" in ctrl.map_field.pack:
		light_id = int(ctrl.map_field.pack.light_preset)
	if light_id != ctrl._last_light_preset:
		ctrl._last_light_preset = light_id
		ctrl._apply_light_preset(light_id)
	if sound_id != ctrl._last_sound_preset:
		ctrl._last_sound_preset = sound_id
		ctrl._apply_sound_preset(sound_id)

static func _apply_light_preset(ctrl, id: int) -> void:
	ctrl._last_light_preset = id
	ctrl._apply_atmosphere()

static func _pull_server_weather(ctrl) -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("get_weather"):
		var snap: Dictionary = srv.get_weather()
		ctrl._weather_kind = str(snap.get("kind", "clear"))
		ctrl._weather_intensity = clampf(float(snap.get("intensity", 0.0)), 0.0, 1.0)
	ctrl._apply_atmosphere()

static func _pin_hud_canvas(ctrl) -> void:
	var cl := ctrl.get_node_or_null("CanvasLayer") as CanvasLayer
	if cl:
		cl.layer = Weather.CANVAS_HUD

static func _apply_world_light(ctrl, c: Color) -> void:
	## Tint map + actors only. HUD lives on a higher CanvasLayer and must stay readable.
	ctrl.modulate = Color(c.r, c.g, c.b, 1.0)
	if ctrl._map_modulate != null and is_instance_valid(ctrl._map_modulate):
		ctrl._map_modulate.color = Color(1, 1, 1, 1)

static func _apply_atmosphere(ctrl) -> void:
	var light_id: int = ctrl._last_light_preset if ctrl._last_light_preset >= 0 else 0
	if ctrl.map_field != null and ctrl.map_field.has_method("set_atmosphere"):
		var atm: Dictionary = ctrl.map_field.set_atmosphere(light_id, ctrl._weather_kind, ctrl._weather_intensity)
		if ctrl.map_field.has_method("weather_display_modulate"):
			ctrl._apply_world_light(ctrl.map_field.weather_display_modulate())
		else:
			ctrl._apply_world_light(atm.get("modulate", MapExt.light_modulate(light_id)))
		var vis := str(atm.get("kind", "clear"))
		if vis != ctrl._last_weather_kind:
			ctrl._last_weather_kind = vis
			if vis != "clear" and ctrl.hud != null and ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system("天气：%s" % str(atm.get("label", vis)))
		return
	ctrl._apply_world_light(MapExt.light_modulate(light_id))

static func _tick_weather_display(ctrl) -> void:
	if ctrl.map_field != null and ctrl.map_field.has_method("weather_display_modulate"):
		ctrl._apply_world_light(ctrl.map_field.weather_display_modulate())

static func _apply_sound_preset(ctrl, id: int) -> void:
	if ctrl._bgs_player == null:
		return
	if id <= 0:
		ctrl._bgs_player.stop()
		ctrl._bgs_player.stream = null
		return
	var p: Dictionary = ctrl._sound_presets.get(str(id), ctrl._sound_presets.get(id, {}))
	if typeof(p) != TYPE_DICTIONARY or p.is_empty():
		return
	var stream: AudioStream = null
	var stream_path := str(p.get("stream", "")).strip_edges()
	if stream_path != "" and ResourceLoader.exists(stream_path):
		var res: Resource = load(stream_path)
		if res is AudioStream:
			stream = res
	if stream == null:
		var kind := str(p.get("kind", "")).strip_edges()
		if kind != "":
			stream = MapSfx.ambient(kind)
	if stream == null:
		return
	ctrl._bgs_player.stream = stream
	ctrl._bgs_player.volume_db = float(p.get("volume_db", 0.0))
	ctrl._bgs_player.play()

static func _play_map_bgm(ctrl) -> void:
	ctrl._load_map_presets()
	var id := ""
	if ctrl.map_field != null and ctrl.map_field.pack != null and "bgm" in ctrl.map_field.pack:
		id = str(ctrl.map_field.pack.bgm).strip_edges()
	if id == "":
		if ctrl._bgm_player != null:
			ctrl._bgm_player.stop()
			ctrl._bgm_player.stream = null
		return
	ctrl._play_pack_audio("bgm", id)

static func _play_pack_audio(ctrl, channel: String, id: String) -> void:
	id = id.strip_edges()
	channel = channel.strip_edges().to_lower()
	if id == "":
		return
	ctrl._load_map_presets()
	var stream: AudioStream = ctrl._load_pack_audio_stream(channel, id)
	if stream == null:
		return
	var player: AudioStreamPlayer = ctrl._se_player
	match channel:
		"bgm":
			player = ctrl._bgm_player
		"bgs":
			player = ctrl._bgs_player
		"me":
			player = ctrl._se_player
		_:
			player = ctrl._se_player
	if player == null:
		return
	player.stream = stream
	if channel == "bgm" or channel == "bgs":
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.play()

static func _load_pack_audio_stream(ctrl, channel: String, id: String) -> AudioStream:
	var folder := "audio/se"
	match channel:
		"bgm":
			folder = "audio/bgm"
		"bgs":
			folder = "audio/bgs"
		"me":
			folder = "audio/me"
		_:
			folder = "audio/se"
	var roots: PackedStringArray = PackedStringArray()
	if ctrl.map_field != null and ctrl.map_field.pack != null:
		roots.append("%s/assets/%s" % [str(ctrl.map_field.pack.pack_dir), folder])
		roots.append("%s/assets/audio" % str(ctrl.map_field.pack.pack_dir))
	var am: Node = ctrl._asset_mgr if ctrl.is_inside_tree() else null
	if am != null and am.has_method("content_root"):
		roots.append("%s/assets/%s" % [str(am.content_root()), folder])
	for root in roots:
		for ext in ["ogg", "wav", "mp3"]:
			var p := "%s/%s.%s" % [root, id, ext]
			var abs_p := p
			if p.begins_with("res://") or p.begins_with("user://"):
				abs_p = ProjectSettings.globalize_path(p)
			if FileAccess.file_exists(p) or FileAccess.file_exists(abs_p):
				var use_p := p if FileAccess.file_exists(p) else abs_p
				var st: AudioStream = ctrl._audio_from_file(use_p, ext)
				if st != null:
					return st
	return null

static func _audio_from_file(ctrl, path: String, ext: String) -> AudioStream:
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is AudioStream:
			return res
	return null

static func _play_footstep(ctrl) -> void:
	if ctrl._foot_player == null:
		return
	ctrl._foot_player.stream = MapSfx.footstep(ctrl._last_foot_kind)
	ctrl._foot_player.pitch_scale = randf_range(0.92, 1.08)
	ctrl._foot_player.play()

