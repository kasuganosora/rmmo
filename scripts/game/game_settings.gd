extends Node
## Client game settings: display / audio / gameplay. Persists to user://.

signal changed

const PATH := "user://game_settings.cfg"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"

const WINDOW_MODES := [
	["窗口", "windowed"],
	["全屏", "fullscreen"],
	["无边框全屏", "borderless"],
]

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

const FPS_CAPS: Array[int] = [0, 30, 60, 120, 144]
const UI_SCALES: Array[float] = [0.85, 1.0, 1.15, 1.3]

var persist_path: String = PATH
var persist_enabled: bool = true

var window_mode: String = "windowed"
var resolution: Vector2i = Vector2i(1280, 720)
var vsync: bool = true
var max_fps: int = 0
var ui_scale: float = 1.0

var master_volume: int = 80
var bgm_volume: int = 80
var sfx_volume: int = 80
var ambient_volume: int = 70
var mute: bool = false

var show_npc_names: bool = true
var show_player_names: bool = true
var show_hp_bars: bool = true
var show_damage_numbers: bool = true
var show_exp_floats: bool = true
var show_gold_floats: bool = true
var show_item_floats: bool = true
var screen_shake: bool = true
var combat_camera_frame: bool = true
var always_run: bool = false
var weather_fx: bool = true
var auto_pickup: bool = false
## Auto-loot filter when auto_pickup is on: all | no_equip | consumable_gold
var auto_pickup_filter: String = "all"
## Auto-use HP/MP potions when below threshold (server-driven).
var auto_potion_hp: bool = false
var auto_potion_hp_pct: int = 40
var auto_potion_mp: bool = false
var auto_potion_mp_pct: int = 30
var hud_locked: bool = false
var show_quest_tracker: bool = true
var show_dps_meter: bool = true
var show_chat_timestamps: bool = true
## Pet periodic assist damage while fighting (server-driven).
var pet_assist: bool = true
## Combat log B-panel kind filters (default all visible).
var combat_log_show_damage: bool = true
var combat_log_show_heal: bool = true
var combat_log_show_miss: bool = true
var combat_log_show_kill: bool = true
var camera_zoom: float = 1.0
## Chebyshev cell radius for NPC/remote nameplates (4–32).
var nameplate_distance: int = 12
## Radar / minimap view radius in tiles (allowed: RADAR_VIEW_RADII; default 11).
var radar_view_radius: int = 11
## Idle AFK warn after N minutes (0=off; else 5–60). Client toast only; no kick.
var afk_warn_minutes: int = 10
var window_layouts: Dictionary = {}
var keybinds: Dictionary = {}

const AUTO_PICKUP_FILTERS := [
	["全部", "all"],
	["不拾取装备", "no_equip"],
	["金币与消耗品", "consumable_gold"],
]
const AUTO_PICKUP_FILTER_IDS := ["all", "no_equip", "consumable_gold"]

const CAMERA_ZOOMS: Array[float] = [0.85, 1.0, 1.15]
## Circular radar coverage in tiles (Chebyshev-ish radius). Smaller = zoomed in.
const RADAR_VIEW_RADII: Array[int] = [8, 11, 16, 22]
const KEYBIND_ACTIONS := [
	["角色", "character"],
	["背包", "inventory"],
	["技能", "skills"],
	["任务", "quest"],
	["地图", "map"],
	["系统", "system"],
	["队伍", "party"],
	["仓库", "warehouse"],
	["好友", "friends"],
	["邮件", "mail"],
	["制作", "craft"],
	["表情", "emote"],
	["称号", "titles"],
	["成就", "achievements"],
	["公会", "guild"],
	["拍卖", "auction"],
	["循环目标", "cycle_target"],
	["拾取", "pickup"],
	["自动攻击", "auto_attack"],
	["战斗日志", "combat_log"],
	["坐下", "sit"],
	["任务追踪", "quest_tracker"],
]
const KEYBIND_DEFAULTS := {
	"character": KEY_C,
	"inventory": KEY_I,
	"skills": KEY_K,
	"quest": KEY_L,
	"map": KEY_M,
	"system": KEY_X,
	"party": KEY_P,
	"warehouse": KEY_U,
	"friends": KEY_O,
	"mail": KEY_N,
	"craft": KEY_J,
	"emote": KEY_E,
	"titles": KEY_T,
	"achievements": KEY_V,
	"guild": KEY_G,
	"auction": KEY_H,
	"cycle_target": KEY_TAB,
	"pickup": KEY_F,
	"auto_attack": KEY_Z,
	"combat_log": KEY_B,
	"sit": KEY_R,
	"quest_tracker": KEY_Y,
}


static func get_i() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null:
		return null
	var r: Window = ml.root
	if r == null:
		return null
	return r.get_node_or_null("GameSettings")


static func flag(key: String, default: bool = true) -> bool:
	var gs := get_i()
	if gs == null:
		return default
	return bool(gs.get(key))


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")


var _loaded_from_disk: bool = false


func _ready() -> void:
	_loaded_from_disk = FileAccess.file_exists(persist_path)
	load_from_disk()
	ensure_buses()
	apply_audio()
	if _loaded_from_disk:
		apply_display()


func ensure_buses() -> void:
	_ensure_bus(BUS_BGM)
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_AMBIENT)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func apply_all() -> void:
	ensure_buses()
	apply_display()
	apply_audio()


func apply_display() -> void:
	if is_headless():
		return
	match window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var sz := _clamp_resolution(resolution)
			DisplayServer.window_set_size(sz)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = maxi(max_fps, 0)


func apply_audio() -> void:
	ensure_buses()
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, mute)
		AudioServer.set_bus_volume_db(master_idx, volume_to_db(master_volume))
	_set_bus_volume(BUS_BGM, bgm_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)
	_set_bus_volume(BUS_AMBIENT, ambient_volume)


func apply_hud_scale(hud: Control) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	var s: float = clampf(ui_scale, 0.7, 1.5)
	if is_equal_approx(s, 1.0):
		hud.scale = Vector2.ONE
		hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	var vp := hud.get_viewport()
	var vs := Vector2(1280, 720)
	if vp:
		vs = vp.get_visible_rect().size
	hud.scale = Vector2(s, s)
	hud.size = vs / s
	hud.position = Vector2.ZERO
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.offset_left = 0
	hud.offset_top = 0
	hud.offset_right = vs.x / s
	hud.offset_bottom = vs.y / s


func volume_to_db(v: int) -> float:
	v = clampi(v, 0, 100)
	if v <= 0:
		return -80.0
	return linear_to_db(float(v) / 100.0)


func _set_bus_volume(bus_name: String, v: int) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, volume_to_db(v))


func _clamp_resolution(sz: Vector2i) -> Vector2i:
	for r in RESOLUTIONS:
		if r == sz:
			return r
	return Vector2i(1280, 720)


func set_window_mode(mode: String) -> void:
	mode = mode.strip_edges()
	if mode not in ["windowed", "fullscreen", "borderless"]:
		mode = "windowed"
	if window_mode == mode:
		return
	window_mode = mode
	apply_display()
	_persist_and_notify()


func set_resolution(sz: Vector2i) -> void:
	sz = _clamp_resolution(sz)
	if resolution == sz:
		return
	resolution = sz
	apply_display()
	_persist_and_notify()


func set_vsync(on: bool) -> void:
	if vsync == on:
		return
	vsync = on
	apply_display()
	_persist_and_notify()


func set_max_fps(cap: int) -> void:
	if cap not in FPS_CAPS:
		cap = 0
	if max_fps == cap:
		return
	max_fps = cap
	apply_display()
	_persist_and_notify()


func set_ui_scale(s: float) -> void:
	var picked: float = 1.0
	var best := 99.0
	for cand in UI_SCALES:
		var d: float = absf(cand - s)
		if d < best:
			best = d
			picked = cand
	if is_equal_approx(ui_scale, picked):
		return
	ui_scale = picked
	_persist_and_notify()


func set_master_volume(v: int) -> void:
	v = clampi(v, 0, 100)
	if master_volume == v:
		return
	master_volume = v
	apply_audio()
	_persist_and_notify()


func set_bgm_volume(v: int) -> void:
	v = clampi(v, 0, 100)
	if bgm_volume == v:
		return
	bgm_volume = v
	apply_audio()
	_persist_and_notify()


func set_sfx_volume(v: int) -> void:
	v = clampi(v, 0, 100)
	if sfx_volume == v:
		return
	sfx_volume = v
	apply_audio()
	_persist_and_notify()


func set_ambient_volume(v: int) -> void:
	v = clampi(v, 0, 100)
	if ambient_volume == v:
		return
	ambient_volume = v
	apply_audio()
	_persist_and_notify()


func set_mute(on: bool) -> void:
	if mute == on:
		return
	mute = on
	apply_audio()
	_persist_and_notify()


func set_flag(key: String, on: bool) -> void:
	if key not in [
		"show_npc_names", "show_player_names", "show_hp_bars",
		"show_damage_numbers", "show_exp_floats", "show_gold_floats", "show_item_floats", "screen_shake", "combat_camera_frame", "always_run", "weather_fx",
		"auto_pickup", "auto_potion_hp", "auto_potion_mp", "hud_locked", "show_quest_tracker", "show_dps_meter", "show_chat_timestamps", "pet_assist",
		"combat_log_show_damage", "combat_log_show_heal", "combat_log_show_miss", "combat_log_show_kill",
	]:
		return
	if bool(get(key)) == on:
		return
	set(key, on)
	_persist_and_notify()


func set_auto_pickup_filter(mode: String) -> void:
	mode = _clamp_auto_pickup_filter(mode)
	if auto_pickup_filter == mode:
		return
	auto_pickup_filter = mode
	_persist_and_notify()


func set_auto_potion_hp(on: bool) -> void:
	if auto_potion_hp == on:
		return
	auto_potion_hp = on
	_persist_and_notify()


func set_auto_potion_mp(on: bool) -> void:
	if auto_potion_mp == on:
		return
	auto_potion_mp = on
	_persist_and_notify()


func set_auto_potion_hp_pct(v: int) -> void:
	v = clampi(int(v), 1, 90)
	if auto_potion_hp_pct == v:
		return
	auto_potion_hp_pct = v
	_persist_and_notify()


func set_auto_potion_mp_pct(v: int) -> void:
	v = clampi(int(v), 1, 90)
	if auto_potion_mp_pct == v:
		return
	auto_potion_mp_pct = v
	_persist_and_notify()


func _clamp_auto_pickup_filter(mode: String) -> String:
	mode = str(mode).strip_edges()
	if mode in AUTO_PICKUP_FILTER_IDS:
		return mode
	return "all"


## Whether item_id should be auto-looted under filter mode.
## catalog: optional object with get_item(id)->Dictionary (item_catalog).
static func matches_auto_pickup_filter(filter: String, item_id: String, catalog = null) -> bool:
	filter = str(filter).strip_edges()
	if filter.is_empty() or filter == "all":
		return true
	item_id = str(item_id).strip_edges()
	if item_id.is_empty():
		return false
	var t := ""
	if catalog != null and catalog.has_method("get_item"):
		var def: Dictionary = catalog.get_item(item_id)
		t = str(def.get("type", "")).strip_edges().to_lower()
	var is_equip := t in ["equipment", "weapon", "armor", "equip"]
	var is_consumable := t in ["consumable", "potion"]
	var is_gold := _is_gold_loot_item(item_id, t)
	match filter:
		"no_equip":
			return not is_equip
		"consumable_gold":
			return is_consumable or is_gold
		_:
			return true


static func _is_gold_loot_item(item_id: String, item_type: String = "") -> bool:
	item_id = item_id.strip_edges().to_lower()
	item_type = item_type.strip_edges().to_lower()
	if item_type in ["currency", "gold"]:
		return true
	if item_id in ["rusty_coin", "gold", "gold_coin", "coin"]:
		return true
	if item_id.ends_with("_coin") or item_id.begins_with("gold_"):
		return true
	return false


func reset_defaults() -> void:
	window_mode = "windowed"
	resolution = Vector2i(1280, 720)
	vsync = true
	max_fps = 0
	ui_scale = 1.0
	master_volume = 80
	bgm_volume = 80
	sfx_volume = 80
	ambient_volume = 70
	mute = false
	show_npc_names = true
	show_player_names = true
	show_hp_bars = true
	show_damage_numbers = true
	show_exp_floats = true
	show_gold_floats = true
	show_item_floats = true
	screen_shake = true
	combat_camera_frame = true
	always_run = false
	weather_fx = true
	auto_pickup = false
	auto_pickup_filter = "all"
	auto_potion_hp = false
	auto_potion_hp_pct = 40
	auto_potion_mp = false
	auto_potion_mp_pct = 30
	hud_locked = false
	show_quest_tracker = true
	show_dps_meter = true
	show_chat_timestamps = true
	pet_assist = true
	combat_log_show_damage = true
	combat_log_show_heal = true
	combat_log_show_miss = true
	combat_log_show_kill = true
	camera_zoom = 1.0
	nameplate_distance = 12
	radar_view_radius = 11
	afk_warn_minutes = 10
	window_layouts = {}
	keybinds = KEYBIND_DEFAULTS.duplicate(true)
	apply_all()
	_persist_and_notify()


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(persist_path) != OK:
		return
	window_mode = str(cfg.get_value("display", "window_mode", window_mode))
	if window_mode not in ["windowed", "fullscreen", "borderless"]:
		window_mode = "windowed"
	var rx := int(cfg.get_value("display", "res_x", resolution.x))
	var ry := int(cfg.get_value("display", "res_y", resolution.y))
	resolution = _clamp_resolution(Vector2i(rx, ry))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	max_fps = int(cfg.get_value("display", "max_fps", max_fps))
	if max_fps not in FPS_CAPS:
		max_fps = 0
	ui_scale = float(cfg.get_value("display", "ui_scale", ui_scale))
	var picked: float = 1.0
	var best := 99.0
	for cand in UI_SCALES:
		var d: float = absf(cand - ui_scale)
		if d < best:
			best = d
			picked = cand
	ui_scale = picked
	master_volume = clampi(int(cfg.get_value("audio", "master", master_volume)), 0, 100)
	bgm_volume = clampi(int(cfg.get_value("audio", "bgm", bgm_volume)), 0, 100)
	sfx_volume = clampi(int(cfg.get_value("audio", "sfx", sfx_volume)), 0, 100)
	ambient_volume = clampi(int(cfg.get_value("audio", "ambient", ambient_volume)), 0, 100)
	mute = bool(cfg.get_value("audio", "mute", mute))
	show_npc_names = bool(cfg.get_value("game", "show_npc_names", show_npc_names))
	show_player_names = bool(cfg.get_value("game", "show_player_names", show_player_names))
	show_hp_bars = bool(cfg.get_value("game", "show_hp_bars", show_hp_bars))
	show_damage_numbers = bool(cfg.get_value("game", "show_damage_numbers", show_damage_numbers))
	show_exp_floats = bool(cfg.get_value("game", "show_exp_floats", show_exp_floats))
	show_gold_floats = bool(cfg.get_value("game", "show_gold_floats", show_gold_floats))
	show_item_floats = bool(cfg.get_value("game", "show_item_floats", show_item_floats))
	screen_shake = bool(cfg.get_value("game", "screen_shake", screen_shake))
	combat_camera_frame = bool(cfg.get_value("game", "combat_camera_frame", combat_camera_frame))
	always_run = bool(cfg.get_value("game", "always_run", always_run))
	weather_fx = bool(cfg.get_value("game", "weather_fx", weather_fx))
	auto_pickup = bool(cfg.get_value("game", "auto_pickup", auto_pickup))
	auto_pickup_filter = _clamp_auto_pickup_filter(str(cfg.get_value("game", "auto_pickup_filter", auto_pickup_filter)))
	auto_potion_hp = bool(cfg.get_value("game", "auto_potion_hp", auto_potion_hp))
	auto_potion_hp_pct = clampi(int(cfg.get_value("game", "auto_potion_hp_pct", auto_potion_hp_pct)), 1, 90)
	auto_potion_mp = bool(cfg.get_value("game", "auto_potion_mp", auto_potion_mp))
	auto_potion_mp_pct = clampi(int(cfg.get_value("game", "auto_potion_mp_pct", auto_potion_mp_pct)), 1, 90)
	hud_locked = bool(cfg.get_value("game", "hud_locked", hud_locked))
	show_quest_tracker = bool(cfg.get_value("game", "show_quest_tracker", show_quest_tracker))
	show_dps_meter = bool(cfg.get_value("game", "show_dps_meter", show_dps_meter))
	show_chat_timestamps = bool(cfg.get_value("game", "show_chat_timestamps", show_chat_timestamps))
	pet_assist = bool(cfg.get_value("game", "pet_assist", pet_assist))
	combat_log_show_damage = bool(cfg.get_value("game", "combat_log_show_damage", combat_log_show_damage))
	combat_log_show_heal = bool(cfg.get_value("game", "combat_log_show_heal", combat_log_show_heal))
	combat_log_show_miss = bool(cfg.get_value("game", "combat_log_show_miss", combat_log_show_miss))
	combat_log_show_kill = bool(cfg.get_value("game", "combat_log_show_kill", combat_log_show_kill))
	camera_zoom = _clamp_zoom(float(cfg.get_value("game", "camera_zoom", camera_zoom)))
	nameplate_distance = clampi(int(cfg.get_value("game", "nameplate_distance", nameplate_distance)), 4, 32)
	radar_view_radius = _clamp_radar_view_radius(int(cfg.get_value("game", "radar_view_radius", radar_view_radius)))
	afk_warn_minutes = _clamp_afk_warn_minutes(int(cfg.get_value("game", "afk_warn_minutes", afk_warn_minutes)))
	var layouts_v: Variant = cfg.get_value("hud", "layouts", {})
	if typeof(layouts_v) == TYPE_DICTIONARY:
		window_layouts = (layouts_v as Dictionary).duplicate(true)
	var binds_v: Variant = cfg.get_value("hud", "keybinds", {})
	keybinds = KEYBIND_DEFAULTS.duplicate(true)
	if typeof(binds_v) == TYPE_DICTIONARY:
		for k in (binds_v as Dictionary).keys():
			keybinds[str(k)] = int(binds_v[k])


func save_to_disk() -> void:
	if not persist_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "res_x", resolution.x)
	cfg.set_value("display", "res_y", resolution.y)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "max_fps", max_fps)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ambient", ambient_volume)
	cfg.set_value("audio", "mute", mute)
	cfg.set_value("game", "show_npc_names", show_npc_names)
	cfg.set_value("game", "show_player_names", show_player_names)
	cfg.set_value("game", "show_hp_bars", show_hp_bars)
	cfg.set_value("game", "show_damage_numbers", show_damage_numbers)
	cfg.set_value("game", "show_exp_floats", show_exp_floats)
	cfg.set_value("game", "show_gold_floats", show_gold_floats)
	cfg.set_value("game", "show_item_floats", show_item_floats)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("game", "combat_camera_frame", combat_camera_frame)
	cfg.set_value("game", "always_run", always_run)
	cfg.set_value("game", "weather_fx", weather_fx)
	cfg.set_value("game", "auto_pickup", auto_pickup)
	cfg.set_value("game", "auto_pickup_filter", auto_pickup_filter)
	cfg.set_value("game", "auto_potion_hp", auto_potion_hp)
	cfg.set_value("game", "auto_potion_hp_pct", auto_potion_hp_pct)
	cfg.set_value("game", "auto_potion_mp", auto_potion_mp)
	cfg.set_value("game", "auto_potion_mp_pct", auto_potion_mp_pct)
	cfg.set_value("game", "hud_locked", hud_locked)
	cfg.set_value("game", "show_quest_tracker", show_quest_tracker)
	cfg.set_value("game", "show_dps_meter", show_dps_meter)
	cfg.set_value("game", "show_chat_timestamps", show_chat_timestamps)
	cfg.set_value("game", "pet_assist", pet_assist)
	cfg.set_value("game", "combat_log_show_damage", combat_log_show_damage)
	cfg.set_value("game", "combat_log_show_heal", combat_log_show_heal)
	cfg.set_value("game", "combat_log_show_miss", combat_log_show_miss)
	cfg.set_value("game", "combat_log_show_kill", combat_log_show_kill)
	cfg.set_value("game", "camera_zoom", camera_zoom)
	cfg.set_value("game", "nameplate_distance", nameplate_distance)
	cfg.set_value("game", "radar_view_radius", radar_view_radius)
	cfg.set_value("game", "afk_warn_minutes", afk_warn_minutes)
	cfg.set_value("hud", "layouts", window_layouts.duplicate(true))
	cfg.set_value("hud", "keybinds", keybinds.duplicate(true))
	cfg.save(persist_path)


func snapshot() -> Dictionary:
	return {
		"window_mode": window_mode,
		"resolution": resolution,
		"vsync": vsync,
		"max_fps": max_fps,
		"ui_scale": ui_scale,
		"master_volume": master_volume,
		"bgm_volume": bgm_volume,
		"sfx_volume": sfx_volume,
		"ambient_volume": ambient_volume,
		"mute": mute,
		"show_npc_names": show_npc_names,
		"show_player_names": show_player_names,
		"show_hp_bars": show_hp_bars,
		"show_damage_numbers": show_damage_numbers,
		"show_exp_floats": show_exp_floats,
		"show_gold_floats": show_gold_floats,
		"show_item_floats": show_item_floats,
		"show_dps_meter": show_dps_meter,
		"show_chat_timestamps": show_chat_timestamps,
		"pet_assist": pet_assist,
		"combat_log_show_damage": combat_log_show_damage,
		"combat_log_show_heal": combat_log_show_heal,
		"combat_log_show_miss": combat_log_show_miss,
		"combat_log_show_kill": combat_log_show_kill,
		"screen_shake": screen_shake,
		"combat_camera_frame": combat_camera_frame,
		"always_run": always_run,
		"weather_fx": weather_fx,
		"auto_pickup": auto_pickup,
		"auto_pickup_filter": auto_pickup_filter,
		"auto_potion_hp": auto_potion_hp,
		"auto_potion_hp_pct": auto_potion_hp_pct,
		"auto_potion_mp": auto_potion_mp,
		"auto_potion_mp_pct": auto_potion_mp_pct,
		"hud_locked": hud_locked,
		"camera_zoom": camera_zoom,
		"nameplate_distance": nameplate_distance,
		"radar_view_radius": radar_view_radius,
		"afk_warn_minutes": afk_warn_minutes,
		"keybinds": keybinds.duplicate(true),
	}


func key_for(action: String) -> int:
	action = action.strip_edges()
	if keybinds.has(action):
		return int(keybinds[action])
	return int(KEYBIND_DEFAULTS.get(action, 0))


func set_keybind(action: String, keycode: int) -> String:
	action = action.strip_edges()
	if not KEYBIND_DEFAULTS.has(action):
		return "unknown"
	if keycode == KEY_ESCAPE or keycode == KEY_ENTER:
		return "reserved"
	for other in keybinds.keys():
		if str(other) != action and int(keybinds[other]) == keycode:
			return str(other)
	for other in KEYBIND_DEFAULTS.keys():
		if str(other) != action and not keybinds.has(other) and int(KEYBIND_DEFAULTS[other]) == keycode:
			return str(other)
	keybinds[action] = keycode
	_persist_and_notify()
	return ""


func set_camera_zoom(z: float) -> void:
	z = _clamp_zoom(z)
	if is_equal_approx(camera_zoom, z):
		return
	camera_zoom = z
	_persist_and_notify()


func set_nameplate_distance(v: int) -> void:
	v = clampi(int(v), 4, 32)
	if nameplate_distance == v:
		return
	nameplate_distance = v
	_persist_and_notify()


func set_radar_view_radius(v: int) -> void:
	v = _clamp_radar_view_radius(v)
	if radar_view_radius == v:
		return
	radar_view_radius = v
	_persist_and_notify()


func set_afk_warn_minutes(v: int) -> void:
	v = _clamp_afk_warn_minutes(v)
	if afk_warn_minutes == v:
		return
	afk_warn_minutes = v
	_persist_and_notify()


## 0 = off; otherwise clamp to 5–60.
func _clamp_afk_warn_minutes(v: int) -> int:
	if int(v) <= 0:
		return 0
	return clampi(int(v), 5, 60)


## Snap to nearest allowed radar radius (8 / 11 / 16 / 22).
func _clamp_radar_view_radius(v: int) -> int:
	var picked: int = 11
	var best := 9999
	for cand in RADAR_VIEW_RADII:
		var d: int = absi(int(cand) - int(v))
		if d < best:
			best = d
			picked = int(cand)
	return picked


## Cycle radar radius. dir > 0 = zoom out (larger radius); dir < 0 = zoom in.
func cycle_radar_view_radius(dir: int) -> int:
	var radii: Array[int] = RADAR_VIEW_RADII
	var cur := _clamp_radar_view_radius(radar_view_radius)
	var idx := 0
	for i in range(radii.size()):
		if int(radii[i]) == cur:
			idx = i
			break
	if dir > 0:
		idx = mini(idx + 1, radii.size() - 1)
	elif dir < 0:
		idx = maxi(idx - 1, 0)
	set_radar_view_radius(int(radii[idx]))
	return radar_view_radius


func _clamp_zoom(z: float) -> float:
	var picked: float = 1.0
	var best := 99.0
	for cand in CAMERA_ZOOMS:
		var d: float = absf(cand - z)
		if d < best:
			best = d
			picked = cand
	return picked


func save_window_layout(id: String, pos: Vector2, visible: bool) -> void:
	id = id.strip_edges()
	if id.is_empty():
		return
	window_layouts[id] = {"x": pos.x, "y": pos.y, "visible": visible}
	save_to_disk()


func window_layout(id: String) -> Dictionary:
	var v: Variant = window_layouts.get(id, {})
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}


func clear_window_layouts() -> void:
	window_layouts = {}
	_persist_and_notify()


func _persist_and_notify() -> void:
	save_to_disk()
	changed.emit()
