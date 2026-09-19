extends Node2D
const Net = preload("res://scripts/net/net.gd")
const NpcActor = preload("res://scripts/game/npc_actor.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const AoiDriver = preload("res://scripts/asset/aoi_driver.gd")
const MapSfx = preload("res://scripts/map/map_sfx.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const NameplateUtil = preload("res://scripts/game/nameplate_util.gd")
const PaperdollLook = preload("res://scripts/char/paperdoll_look.gd")
const SkillFxScript = preload("res://scripts/game/skill_fx.gd")
const CombatFloater = preload("res://scripts/game/combat_floater.gd")
const CameraShake = preload("res://scripts/game/camera_shake.gd")
const CombatCamera = preload("res://scripts/game/combat_camera.gd")
const CombatLogScript = preload("res://scripts/game/combat_log.gd")
const RadarPoi = preload("res://scripts/ui/radar_poi.gd")
const ActionApply = preload("res://scripts/game/application/action_apply.gd")
const RequestAdapter = preload("res://scripts/game/application/request_adapter.gd")
const Targeting = preload("res://scripts/game/application/targeting.gd")
const WorldEnv = preload("res://scripts/game/infrastructure/world_env.gd")
const WorldQuery = preload("res://scripts/game/application/world_query.gd")
const SkillAimOverlay = preload("res://scripts/game/skill_aim_overlay.gd")
const SkillAim = preload("res://scripts/game/application/skill_aim.gd")
const CombatFeedback = preload("res://scripts/game/application/combat_feedback.gd")
const SettingsSync = preload("res://scripts/game/application/settings_sync.gd")
const Follow = preload("res://scripts/game/application/follow.gd")
const MapPins = preload("res://scripts/game/application/map_pins.gd")
const GroundLoot = preload("res://scripts/game/application/ground_loot.gd")
const HudBinding = preload("res://scripts/game/interface/hud_binding.gd")
const RemoteActors = preload("res://scripts/game/application/remote_actors.gd")
const Engage = preload("res://scripts/game/application/engage.gd")
const AutoAttack = preload("res://scripts/game/application/auto_attack.gd")
const Pickup = preload("res://scripts/game/application/pickup.gd")
const PlayerMenu = preload("res://scripts/game/interface/player_menu.gd")
const NpcSpawn = preload("res://scripts/game/application/npc_spawn.gd")
const Aoi = preload("res://scripts/game/application/aoi.gd")
const PlayerView = preload("res://scripts/game/application/player_view.gd")
const MapTransfer = preload("res://scripts/game/application/map_transfer.gd")
const Dungeon = preload("res://scripts/game/application/dungeon.gd")

@onready var player: CharacterBody2D = %Player
@onready var hud: Control = %GameHud
@onready var map_field: Node2D = %MapField

var _npc_layer: Node2D = null
var _ground_layer: Node2D = null
var _ground_markers: Dictionary = {}  # bag_id -> Node2D
var _remote_markers: Dictionary = {}  # player_id -> Node2D
var _pet_marker: Node2D = null  # companion pet marker
var _hovered_ground_bag_id: String = ""
var _npcs: Array = []
var _radar_blips_cache: Array = []
var _radar_blips_sig: PackedInt32Array = PackedInt32Array()
var _radar_blips_ready: bool = false
## Click-to-engage: NPC id to attack/interact when path arrives in range.
var _pending_engage_npc_id: String = ""
## If set, arrival casts this skill instead of a basic attack.
var _pending_skill_id: String = ""
var _pending_skill_range: int = 1
## Currently selected NPC (nameplate highlight + foot ring). Empty = none.
var _selected_npc_id: String = ""
## Soft-selected remote/fake player id (nameplate only; no HP). Empty = none.
var _selected_remote_id: String = ""
## Acc for ~4 Hz NPC nameplate distance refresh.
var _nameplate_tick_acc: float = 0.0
var _follow_id: String = ""
var _camera_shake = CameraShake.new()
## Soft combat framing offset (lerped); shake is added on top when applied.
var _combat_cam_offset: Vector2 = Vector2.ZERO
var _auto_attack: bool = false
var _auto_attack_cd: float = 0.0
var _cycle_index: int = 0
var _map_pin: Vector2i = Vector2i(-9999, -9999)
var _skill_aim_id: String = ""
var _skill_aim_overlay: Node2D = null
var _skill_fx: Node2D = null
var _skill_aim_hover: Vector2i = Vector2i(-9999, -9999)
var _player_ctx_menu: PopupMenu = null
## Brief input lock after death/respawn (seconds remaining).
var _respawn_lock_left: float = 0.0

var _map_modulate: CanvasModulate = null
var _bgs_player: AudioStreamPlayer
var _bgm_player: AudioStreamPlayer
var _se_player: AudioStreamPlayer
var _foot_player: AudioStreamPlayer
var _last_light_preset: int = -1
var _last_sound_preset: int = -1
var _last_foot_kind: int = 0
## Cached AssetManager autoload ref (resolved once in _ready) to avoid per-frame tree walks.
var _asset_mgr: Node = null
## Remaining event-batch wait (seconds) + deferred actions after a wait op.
var _event_wait_left: float = 0.0
var _deferred_event_actions: Array = []
var _deferred_event_npc = null
## Types consumed from the last immediate batch (test seam / wait split).
var last_applied_action_types: Array = []
var _light_presets: Dictionary = {}
var _sound_presets: Dictionary = {}
var _weather_kind: String = "clear"
var _weather_intensity: float = 0.0
var _last_weather_kind: String = ""

## Actor AOI preload rings (cells, Chebyshev). P2c — not map chunks.
@export var aoi_view_radius_cells: int = 14
@export var aoi_radius_cells: int = 22
@export var aoi_prefetch_radius_cells: int = 30
@export var aoi_refresh_interval_sec: float = 0.25
var _aoi: RefCounted = null


func _ready() -> void:
	_asset_mgr = get_node_or_null("/root/AssetManager")
	_pin_hud_canvas()
	_connect_game_settings()
	var spawn: Dictionary = Net.session().spawn_data.duplicate(true)
	var ch: Dictionary = Net.session().active_character()
	if ch.is_empty():
		push_error("World: no active character in session")
		Net.session().go_character_select.call_deferred()
		return

	if map_field == null:
		map_field = get_node_or_null("MapField")
	if map_field != null:
		var pack_path: String = str(spawn.get("pack_path", "res://demo_map"))
		var content_id: String = str(spawn.get("content_id", "")).strip_edges()
		var am: Node = _asset_mgr
		if am != null and am.has_method("resolve_map_pack_path"):
			var resolved := ""
			if content_id != "":
				resolved = str(am.resolve_map_pack_path(content_id))
			if resolved != "" and FileAccess.file_exists("%s/pack.json" % resolved):
				pack_path = resolved
			elif resolved != "" and resolved.begins_with("res://") and FileAccess.file_exists("%s/pack.json" % ProjectSettings.globalize_path(resolved)):
				pack_path = resolved
			else:
				pack_path = str(am.resolve_map_pack_path(pack_path))
		var prev_path: String = str(map_field.pack_path) if map_field.get("pack_path") != null else ""
		if map_field.get("pack_path") != null:
			map_field.pack_path = pack_path
		# Prefer Loading-phase bake (0.5x radar atlas + ground/upper). Rebuild only if missing.
		var applied := false
		if map_field.has_method("try_apply_session_bake"):
			applied = bool(map_field.try_apply_session_bake())
		if not applied and map_field.has_method("rebuild") and (prev_path != pack_path or map_field.pack == null):
			map_field.rebuild()

	var cell := Vector2i(0, 0)
	var cell_v: Variant = spawn.get("cell", null)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	elif map_field != null and map_field.collision != null and map_field.collision.has_method("find_spawn_near"):
		cell = map_field.collision.find_spawn_near()

	var sv = Net.server()
	if sv != null and sv.has_method("load_world_pack"):
		var cur := str(sv.get("map_pack_path")).rstrip("/").replace("\\", "/")
		var want := str(spawn.get("pack_path", "")).rstrip("/").replace("\\", "/")
		if map_field != null:
			want = str(map_field.pack_path).rstrip("/").replace("\\", "/")
		var want_map := str(spawn.get("map_id", "")).strip_edges()
		if want != "" and (cur != want or (want_map != "" and str(sv.get("map_pack_id")) != want_map)):
			sv.load_world_pack(want, want_map, cell)
		elif sv.has_method("set_player_cell"):
			sv.set_player_cell(cell.x, cell.y)

	if player.has_method("place_at_cell"):
		player.place_at_cell(cell, map_field)
	else:
		var pos: Dictionary = {}
		var pos_v: Variant = spawn.get("position", null)
		if typeof(pos_v) == TYPE_DICTIONARY:
			pos = pos_v
		else:
			pos = {"x": 640.0, "y": 360.0}
		player.global_position = Vector2(float(pos.get("x", 640)), float(pos.get("y", 360)))

	# Snap Camera2D onto spawn (no slide from scene default / prior map).
	if player.has_method("snap_camera"):
		player.snap_camera()

	if player.has_method("setup"):
		player.setup(str(ch.get("look_id", "1")), str(ch.get("gender", "female")), ch.get("customization", {}))
	if player.has_method("set_facing_dir") and spawn.has("facing"):
		player.set_facing_dir(int(spawn.get("facing", 2)))
	player.input_locked = false
	if player.has_signal("transfer_requested"):
		if not player.transfer_requested.is_connected(_on_transfer_requested):
			player.transfer_requested.connect(_on_transfer_requested)
	if player.has_signal("arrived_cell"):
		if not player.arrived_cell.is_connected(_on_player_arrived_cell):
			player.arrived_cell.connect(_on_player_arrived_cell)
	if player.has_signal("path_cancelled"):
		if not player.path_cancelled.is_connected(_on_player_path_cancelled):
			player.path_cancelled.connect(_on_player_path_cancelled)
	_spawn_npcs_from_pack()
	_init_aoi_driver()
	_load_map_presets()
	_play_map_bgm()
	_pull_server_weather()
	_sync_map_observer()
	call_deferred("_bind_hud", ch, spawn)


func _bind_hud(ch: Dictionary, spawn: Dictionary) -> void:
	HudBinding._bind_hud(self, ch, spawn)
func _clear_npcs() -> void:
	NpcSpawn._clear_npcs(self, )
func _clear_ground_markers() -> void:
	GroundLoot._clear_ground_markers(self, )
func _ensure_ground_layer() -> Node2D:
	return GroundLoot._ensure_ground_layer(self, )
func _ensure_npc_layer() -> Node2D:
	return NpcSpawn._ensure_npc_layer(self, )
func _spawn_npcs_from_pack() -> void:
	NpcSpawn._spawn_npcs_from_pack(self, )
func get_radar_blips() -> Array:
	return WorldQuery.get_radar_blips(self, )
## Same POI marker list as radar (quest/inn/smith/gather/fish); depleted gather/fish omitted.
func get_radar_poi_markers() -> Array:
	return WorldQuery.get_radar_poi_markers(self, )
## Richer sample for quest-tracker pathfind: NPC cells + gather/fish yields + warps.
func get_quest_nav_context() -> Dictionary:
	return WorldQuery.get_quest_nav_context(self, )
func _radar_kind_code(kind: String) -> int:
	return WorldQuery._radar_kind_code(self, kind)
## Sample for RadarPoi.build_markers from live NPCs + MockServer catalogs/journal.
func _radar_poi_sample() -> Dictionary:
	return WorldQuery._radar_poi_sample(self, )
func _npc_shows_on_radar(n) -> bool:
	return WorldQuery._npc_shows_on_radar(self, n)
func _find_npc_at(cell: Vector2i):
	return WorldQuery._find_npc_at(self, cell)
func _find_remote_at(cell: Vector2i):
	return WorldQuery._find_remote_at(self, cell)
func _find_adjacent_npc(from_cell: Vector2i, prefer_dir: int = 0):
	return WorldQuery._find_adjacent_npc(self, from_cell, prefer_dir)
func tick_event_wait(delta: float) -> void:
	ActionApply.tick_event_wait(self, delta)
func _apply_server_actions(actions: Array, npc = null) -> void:
	ActionApply.apply_server_actions(self, actions, npc)
func _apply_npc_move(action: Dictionary) -> void:
	ActionApply.apply_npc_move(self, action)
func _apply_npc_reset(action: Dictionary) -> void:
	ActionApply.apply_npc_reset(self, action)
func _apply_damage_action(action: Dictionary, npc = null) -> void:
	ActionApply.apply_damage_action(self, action, npc)
func _connect_game_settings() -> void:
	SettingsSync._connect_game_settings(self, )
func _on_game_settings_changed() -> void:
	SettingsSync._on_game_settings_changed(self, )
func _push_auto_potion_settings() -> void:
	SettingsSync._push_auto_potion_settings(self, )
func _push_pet_assist_settings() -> void:
	SettingsSync._push_pet_assist_settings(self, )
func _trigger_crit_shake() -> void:
	CombatFeedback._trigger_crit_shake(self, )
func _desired_combat_frame_offset() -> Vector2:
	return CombatFeedback._desired_combat_frame_offset(self, )
func _tick_camera_shake(delta: float) -> void:
	CombatFeedback._tick_camera_shake(self, delta)
func _spawn_combat_floater(world_pos: Vector2, text: String, _color: Color = Color(), kind: String = "damage", target_key: String = "default", crit: bool = false):
	return CombatFeedback._spawn_combat_floater(self, world_pos, text, _color, kind, target_key, crit)
func _apply_miss_action(action: Dictionary) -> void:
	ActionApply.apply_miss_action(self, action)
func _resolve_emote_host(actor_id: String) -> Node2D:
	return CombatFeedback._resolve_emote_host(self, actor_id)
func _apply_emote(action: Dictionary) -> void:
	ActionApply.apply_emote(self, action)
func _apply_heal_action(action: Dictionary) -> void:
	ActionApply.apply_heal_action(self, action)
func _apply_set_stat(action: Dictionary) -> void:
	ActionApply.apply_set_stat(self, action)
func _apply_skill_cd(action: Dictionary) -> void:
	ActionApply.apply_skill_cd(self, action)
func _apply_status_update(action: Dictionary) -> void:
	ActionApply.apply_status_update(self, action)
func _apply_inventory_update(action: Dictionary) -> void:
	ActionApply.apply_inventory_update(self, action)
func _apply_equipment_update(action: Dictionary) -> void:
	ActionApply.apply_equipment_update(self, action)
func _apply_quest_update(action: Dictionary) -> void:
	ActionApply.apply_quest_update(self, action)
func _apply_kill_npc(npc_id: String, npc = null) -> void:
	ActionApply.apply_kill_npc(self, npc_id, npc)
func _apply_spawn_npc(action: Dictionary) -> void:
	ActionApply.apply_spawn_npc(self, action)
func _apply_gather_update(action: Dictionary) -> void:
	ActionApply.apply_gather_update(self, action)
func _apply_fish_update(action: Dictionary) -> void:
	ActionApply.apply_fish_update(self, action)
func _find_npc_by_id(npc_id: String):
	return Targeting._find_npc_by_id(self, npc_id)
func _sync_npc_combat_display() -> void:
	Targeting._sync_npc_combat_display(self)
func _clear_npc_selection() -> void:
	Targeting._clear_npc_selection(self)
func clear_target_selection() -> void:
	Targeting.clear_target_selection(self)
func _npc_shows_target_hp(npc) -> bool:
	return Targeting._npc_shows_target_hp(self, npc)
func _push_target_hud(npc, display_name: String, ratio: float, threat_snap: Dictionary = {}) -> void:
	Targeting._push_target_hud(self, npc, display_name, ratio, threat_snap)
func _fetch_threat_snapshot(npc_id: String) -> Dictionary:
	return Targeting._fetch_threat_snapshot(self, npc_id)
func _apply_threat_update(action: Dictionary) -> void:
	ActionApply.apply_threat_update(self, action)
func _select_npc(npc) -> void:
	Targeting._select_npc(self, npc)
func _clear_pending_engage() -> void:
	Targeting._clear_pending_engage(self)
func _set_pending_engage(npc, skill_id: String = "", range_cells: int = 1) -> void:
	Targeting._set_pending_engage(self, npc, skill_id, range_cells)
func _player_beside_npc(npc, pcell: Vector2i) -> bool:
	return Targeting._player_beside_npc(self, npc, pcell)
func _cheb(a: Vector2i, b: Vector2i) -> int:
	return Targeting._cheb(self, a, b)
func _nameplate_max_dist() -> int:
	return Targeting._nameplate_max_dist(self)
func _refresh_npc_nameplates() -> void:
	Targeting._refresh_npc_nameplates(self)
func _refresh_remote_nameplates() -> void:
	Targeting._refresh_remote_nameplates(self)
func _tick_nameplate_distance(delta: float) -> void:
	Targeting._tick_nameplate_distance(self, delta)
## Stand at the far edge of `range_cells` from target, stepping from `from`.
func _approach_cell(from: Vector2i, target: Vector2i, range_cells: int) -> Vector2i:
	return Targeting._approach_cell(self, from, target, range_cells)
func _face_toward_cell(to: Vector2i) -> void:
	Targeting._face_toward_cell(self, to)
func _npc_target_cell(npc) -> Vector2i:
	return Targeting._npc_target_cell(self, npc)
func _player_in_skill_range(npc, range_cells: int, pcell: Vector2i) -> bool:
	return Engage._player_in_skill_range(self, npc, range_cells, pcell)
## -1 = no chase (self buff/heal). Else Chebyshev cells.
func _skill_chase_range(def: Dictionary) -> int:
	return Engage._skill_chase_range(self, def)
func _path_to_npc_range(npc, range_cells: int) -> bool:
	return Engage._path_to_npc_range(self, npc, range_cells)
## Double-click hostile: run to melee, face, keep auto-attacking.
func _request_npc_engage(npc) -> void:
	Engage._request_npc_engage(self, npc)
func _on_player_path_cancelled() -> void:
	Engage._on_player_path_cancelled(self, )
func _on_player_arrived_cell(cell: Vector2i, path_complete: bool) -> void:
	Engage._on_player_arrived_cell(self, cell, path_complete)
func start_follow(target_id: String) -> void:
	Follow.start_follow(self, target_id)
func stop_follow() -> void:
	Follow.stop_follow(self, )
func is_following() -> bool:
	return Follow.is_following(self, )
func get_follow_id() -> String:
	return Follow.get_follow_id(self, )
func _tick_follow() -> void:
	Follow._tick_follow(self, )
func _follow_target_cell() -> Vector2i:
	return Follow._follow_target_cell(self, )
func _apply_remote_look(marker: Node2D, gender: String, look_id: String, equipment: Variant) -> void:
	RemoteActors._apply_remote_look(self, marker, gender, look_id, equipment)
func inspect_remote(player_id: String) -> Dictionary:
	return RemoteActors.inspect_remote(self, player_id)
func request_party_invite_respond(invite_id: String, accept: bool) -> void:
	RequestAdapter.request_party_invite_respond(self, invite_id, accept)
func request_respawn(where: String = "town") -> void:
	RequestAdapter.request_respawn(self, where)
func request_recall() -> void:
	RequestAdapter.request_recall(self)
func request_sit(on: Variant = null) -> void:
	RequestAdapter.request_sit(self, on)
func request_map_move(cell: Vector2i, label: String = "") -> void:
	RequestAdapter.request_map_move(self, cell, label)
## POI display name at cell (radar/big-map markers), or "".
func _map_poi_label_at(cell: Vector2i) -> String:
	return MapPins._map_poi_label_at(self, cell)
func toggle_map_pin(cell: Vector2i, short_name: String = "") -> void:
	MapPins.toggle_map_pin(self, cell, short_name)
func clear_map_pins() -> void:
	MapPins.clear_map_pins(self, )
func _sync_map_pins_from_server(snap: Variant) -> void:
	MapPins._sync_map_pins_from_server(self, snap)
func map_pin_cell() -> Vector2i:
	return MapPins.map_pin_cell(self, )
func map_pins_snapshot() -> Array:
	return MapPins.map_pins_snapshot(self, )
func cycle_hostile_target(dir: int = 1) -> void:
	AutoAttack.cycle_hostile_target(self, dir)
func toggle_auto_attack() -> void:
	AutoAttack.toggle_auto_attack(self, )
func is_auto_attack() -> bool:
	return AutoAttack.is_auto_attack(self, )
func _tick_auto_attack(delta: float) -> void:
	AutoAttack._tick_auto_attack(self, delta)
func pickup_nearest() -> void:
	Pickup.pickup_nearest(self, )
func _try_auto_pickup_at(cell: Vector2i) -> void:
	Pickup._try_auto_pickup_at(self, cell)
func _auto_take_all() -> void:
	Pickup._auto_take_all(self, )
func _refresh_player_gear_look(equipment: Array) -> void:
	PlayerView._refresh_player_gear_look(self, equipment)
func _apply_camera_zoom() -> void:
	PlayerView._apply_camera_zoom(self, )
func _load_map_presets() -> void:
	return WorldEnv._load_map_presets(self, )
func _read_preset_file(path: String) -> Dictionary:
	return WorldEnv._read_preset_file(self, path)
func _sync_map_observer() -> void:
	return WorldEnv._sync_map_observer(self, )
func _apply_cell_settings(cell: Vector2i) -> void:
	return WorldEnv._apply_cell_settings(self, cell)
func _apply_light_preset(id: int) -> void:
	return WorldEnv._apply_light_preset(self, id)
func _apply_weather_action(action: Dictionary) -> void:
	ActionApply.apply_weather_action(self, action)
func _pull_server_weather() -> void:
	return WorldEnv._pull_server_weather(self, )
func _pin_hud_canvas() -> void:
	return WorldEnv._pin_hud_canvas(self, )
func _apply_world_light(c: Color) -> void:
	return WorldEnv._apply_world_light(self, c)
func _apply_atmosphere() -> void:
	return WorldEnv._apply_atmosphere(self, )
func _tick_weather_display() -> void:
	return WorldEnv._tick_weather_display(self, )
func _apply_sound_preset(id: int) -> void:
	return WorldEnv._apply_sound_preset(self, id)
func _apply_event_graphic(action: Dictionary) -> void:
	ActionApply.apply_event_graphic(self, action)
func _play_map_bgm() -> void:
	return WorldEnv._play_map_bgm(self, )
func _play_pack_audio(channel: String, id: String) -> void:
	return WorldEnv._play_pack_audio(self, channel, id)
func _load_pack_audio_stream(channel: String, id: String) -> AudioStream:
	return WorldEnv._load_pack_audio_stream(self, channel, id)
func _audio_from_file(path: String, ext: String) -> AudioStream:
	return WorldEnv._audio_from_file(self, path, ext)
func _play_footstep() -> void:
	return WorldEnv._play_footstep(self, )
func _apply_player_move(action: Dictionary) -> void:
	ActionApply.apply_player_move(self, action)
func _apply_recall(action: Dictionary) -> void:
	ActionApply.apply_recall(self, action)
func _apply_sit(action: Dictionary) -> void:
	ActionApply.apply_sit(self, action)
func _apply_respawn(action: Dictionary) -> void:
	ActionApply.apply_respawn(self, action)
func _engage_npc(npc) -> bool:
	return Engage._engage_npc(self, npc)
func _try_attack_npc(npc) -> bool:
	return Engage._try_attack_npc(self, npc)
func _try_interact_npc(npc) -> bool:
	return Engage._try_interact_npc(self, npc)
func _init_aoi_driver() -> void:
	Aoi._init_aoi_driver(self, )
func _refresh_aoi(force: bool = false) -> void:
	Aoi._refresh_aoi(self, force)
func _process(delta: float) -> void:
	tick_event_wait(delta)
	_tick_camera_shake(delta)
	_tick_weather_display()
	if is_skill_aiming():
		_update_skill_aim_preview()
	_tick_ground_hover()
	_tick_remote_aoi()
	_tick_nameplate_distance(delta)
	_tick_follow()
	_tick_auto_attack(delta)
	if _respawn_lock_left > 0.0:
		_respawn_lock_left = maxf(0.0, _respawn_lock_left - delta)
		if _respawn_lock_left <= 0.0 and player != null:
			player.input_locked = false
	# P2c: classify NPC asset rings by distance from local player.
	if _aoi != null:
		var am: Node = _asset_mgr
		_aoi.tick(delta, player, _npcs, am, false)
	# Drain ambient MockServer combat tick actions (adjacent counter-attacks).
	var srv = Net.server()
	if srv == null or not srv.has_method("poll_combat_tick"):
		return
	var actions: Array = srv.poll_combat_tick()
	if not actions.is_empty():
		_apply_server_actions(actions, null)


## Hotbar / UI: use skill against current adjacent hostile (or self-heal).
func _apply_exp_gain(action: Dictionary) -> void:
	ActionApply.apply_exp_gain(self, action)
func _apply_level_up(action: Dictionary) -> void:
	ActionApply.apply_level_up(self, action)
func request_event_choice(option_id: String = "", option_index: int = -1) -> void:
	RequestAdapter.request_event_choice(self, option_id, option_index)
func _apply_open_shop(action: Dictionary) -> void:
	ActionApply.apply_open_shop(self, action)
func request_shop_buy(shop_id: String, item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_shop_buy(self, shop_id, item_id, qty)
func request_shop_buyback(index: int, qty: int = -1) -> void:
	RequestAdapter.request_shop_buyback(self, index, qty)
func request_shop_close() -> void:
	RequestAdapter.request_shop_close(self)
func request_inventory_split(item_id: String, qty: int) -> void:
	RequestAdapter.request_inventory_split(self, item_id, qty)
func request_inventory_sort() -> void:
	RequestAdapter.request_inventory_sort(self)
func request_inventory_lock(item_id: String, on: bool) -> void:
	RequestAdapter.request_inventory_lock(self, item_id, on)
func request_shop_sell(item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_shop_sell(self, item_id, qty)
func request_shop_sell_junk() -> void:
	RequestAdapter.request_shop_sell_junk(self)
func _apply_ground_spawn(action: Dictionary) -> void:
	ActionApply.apply_ground_spawn(self, action)
func _apply_ground_update(action: Dictionary) -> void:
	ActionApply.apply_ground_update(self, action)
func _apply_ground_despawn(action: Dictionary) -> void:
	ActionApply.apply_ground_despawn(self, action)
func _upsert_ground_marker(bag: Dictionary) -> void:
	GroundLoot._upsert_ground_marker(self, bag)
func _resolve_ground_item_icon(it: Dictionary) -> Texture2D:
	return GroundLoot._resolve_ground_item_icon(self, it)
func _ground_bag_tip_text(items: Array) -> String:
	return GroundLoot._ground_bag_tip_text(self, items)
func _tick_ground_hover() -> void:
	GroundLoot._tick_ground_hover(self, )
func _find_ground_bag_at(cell: Vector2i) -> String:
	return GroundLoot._find_ground_bag_at(self, cell)
func _apply_loot_open(action: Dictionary) -> void:
	ActionApply.apply_loot_open(self, action)
func _apply_loot_update(action: Dictionary) -> void:
	ActionApply.apply_loot_update(self, action)
func _apply_loot_close(_action: Dictionary) -> void:
	ActionApply.apply_loot_close(self, _action)
func request_open_ground_bag(bag_id: String) -> void:
	RequestAdapter.request_open_ground_bag(self, bag_id)
func request_drop_item(item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_drop_item(self, item_id, qty)
func request_drop_equipped(slot: String) -> void:
	RequestAdapter.request_drop_equipped(self, slot)
func request_loot_take(item_id: String, qty: int = -1) -> void:
	RequestAdapter.request_loot_take(self, item_id, qty)
func request_loot_take_all() -> void:
	RequestAdapter.request_loot_take_all(self)
func request_loot_close() -> void:
	RequestAdapter.request_loot_close(self)
func request_loot_roll(choice: String, roll_id: String = "") -> void:
	RequestAdapter.request_loot_roll(self, choice, roll_id)
func request_turn_in_quest(quest_id: String) -> void:
	RequestAdapter.request_turn_in_quest(self, quest_id)
func request_accept_quest(quest_id: String) -> void:
	RequestAdapter.request_accept_quest(self, quest_id)
func request_abandon_quest(quest_id: String) -> void:
	RequestAdapter.request_abandon_quest(self, quest_id)
func request_cancel_status(status_id: String) -> void:
	RequestAdapter.request_cancel_status(self, status_id)
func request_party_debug_fill() -> void:
	RequestAdapter.request_party_debug_fill(self)
func request_party_create() -> void:
	RequestAdapter.request_party_create(self)
func request_party_invite(target: String = "") -> void:
	RequestAdapter.request_party_invite(self, target)
func request_party_leave() -> void:
	RequestAdapter.request_party_leave(self)
func request_party_kick(member_id: String) -> void:
	RequestAdapter.request_party_kick(self, member_id)
func request_party_set_target(npc_id: String, display_name: String = "") -> void:
	RequestAdapter.request_party_set_target(self, npc_id, display_name)
func request_party_clear_target() -> void:
	RequestAdapter.request_party_clear_target(self)
func request_party_set_loot_mode(mode: String) -> void:
	RequestAdapter.request_party_set_loot_mode(self, mode)
func _clear_remote_selection() -> void:
	RemoteActors._clear_remote_selection(self, )
func _select_remote(marker: Node2D) -> void:
	RemoteActors._select_remote(self, marker)
func _ensure_player_context_menu() -> PopupMenu:
	return PlayerMenu._ensure_player_context_menu(self, )
func _close_player_context_menu() -> void:
	PlayerMenu._close_player_context_menu(self, )
func _open_player_context_menu(marker: Node2D, screen_pos: Vector2) -> void:
	PlayerMenu._open_player_context_menu(self, marker, screen_pos)
func _on_player_context_id(id: int) -> void:
	PlayerMenu._on_player_context_id(self, id)
func _tick_remote_aoi() -> void:
	RemoteActors._tick_remote_aoi(self, )
func _apply_remote_move(action: Dictionary) -> void:
	ActionApply.apply_remote_move(self, action)
func _ensure_remote_layer() -> Node2D:
	return RemoteActors._ensure_remote_layer(self, )
func _upsert_remote_marker(data: Dictionary) -> void:
	RemoteActors._upsert_remote_marker(self, data)
func _clear_remote_markers() -> void:
	RemoteActors._clear_remote_markers(self, )
func _remove_remote_marker(player_id: String) -> void:
	RemoteActors._remove_remote_marker(self, player_id)
func _upsert_pet_marker(data: Dictionary) -> void:
	RemoteActors._upsert_pet_marker(self, data)
func _remove_pet_marker() -> void:
	RemoteActors._remove_pet_marker(self, )
func _apply_pet_move(action: Dictionary) -> void:
	ActionApply.apply_pet_move(self, action)
func request_chat(channel: String, text: String, whisper_to: String = "") -> void:
	RequestAdapter.request_chat(self, channel, text, whisper_to)
func request_remote_debug_spawn(display_name: String = "") -> void:
	RequestAdapter.request_remote_debug_spawn(self, display_name)
func request_trade_open(partner_name: String = "") -> void:
	RequestAdapter.request_trade_open(self, partner_name)
func request_trade_cancel() -> void:
	RequestAdapter.request_trade_cancel(self)
func request_trade_put_item(item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_trade_put_item(self, item_id, qty)
func request_trade_take_item(item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_trade_take_item(self, item_id, qty)
func request_trade_set_gold(amount: int) -> void:
	RequestAdapter.request_trade_set_gold(self, amount)
func request_trade_ready(ready: bool = true) -> void:
	RequestAdapter.request_trade_ready(self, ready)
func request_trade_confirm() -> void:
	RequestAdapter.request_trade_confirm(self)
func request_duel_challenge(target_id_or_name: String = "") -> void:
	RequestAdapter.request_duel_challenge(self, target_id_or_name)
func request_duel_accept() -> void:
	RequestAdapter.request_duel_accept(self)
func request_duel_decline() -> void:
	RequestAdapter.request_duel_decline(self)
func request_duel_forfeit() -> void:
	RequestAdapter.request_duel_forfeit(self)
func request_craft(recipe_id: String, qty: int = 1) -> void:
	RequestAdapter.request_craft(self, recipe_id, qty)
func request_emote(emote_id: String) -> void:
	RequestAdapter.request_emote(self, emote_id)
func request_dungeon_enter() -> void:
	RequestAdapter.request_dungeon_enter(self)
func request_dungeon_exit() -> void:
	RequestAdapter.request_dungeon_exit(self)
func _apply_dungeon_server_result(result: Dictionary) -> void:
	Dungeon._apply_dungeon_server_result(self, result)
func request_pet_summon(pet_id: String = "default") -> void:
	RequestAdapter.request_pet_summon(self, pet_id)
func request_pet_dismiss() -> void:
	RequestAdapter.request_pet_dismiss(self)
func request_warehouse_open() -> void:
	RequestAdapter.request_warehouse_open(self)
func request_warehouse_deposit(item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_warehouse_deposit(self, item_id, qty)
func request_warehouse_withdraw(item_id: String, qty: int = 1) -> void:
	RequestAdapter.request_warehouse_withdraw(self, item_id, qty)
func request_warehouse_deposit_gold(amount: int) -> void:
	RequestAdapter.request_warehouse_deposit_gold(self, amount)
func request_warehouse_withdraw_gold(amount: int) -> void:
	RequestAdapter.request_warehouse_withdraw_gold(self, amount)
func request_friend_add(name_or_id: String) -> void:
	RequestAdapter.request_friend_add(self, name_or_id)
func request_friend_remove(friend_id: String) -> void:
	RequestAdapter.request_friend_remove(self, friend_id)
func request_guild_create(guild_name: String) -> void:
	RequestAdapter.request_guild_create(self, guild_name)
func request_guild_invite(target: String) -> void:
	RequestAdapter.request_guild_invite(self, target)
func request_guild_kick(member_id: String) -> void:
	RequestAdapter.request_guild_kick(self, member_id)
func request_guild_leave() -> void:
	RequestAdapter.request_guild_leave(self)
func request_guild_disband() -> void:
	RequestAdapter.request_guild_disband(self)
func request_guild_invite_respond(invite_id: String, accept: bool) -> void:
	RequestAdapter.request_guild_invite_respond(self, invite_id, accept)
func request_mail_send(to: String, subject: String, body: String, gold: int = 0, item_id: String = "", qty: int = 1) -> void:
	RequestAdapter.request_mail_send(self, to, subject, body, gold, item_id, qty)
func request_mail_read(mail_id: String) -> void:
	RequestAdapter.request_mail_read(self, mail_id)
func request_mail_claim(mail_id: String) -> void:
	RequestAdapter.request_mail_claim(self, mail_id)
func request_mail_delete(mail_id: String) -> void:
	RequestAdapter.request_mail_delete(self, mail_id)
func request_auction_list(item_id: String, qty: int = 1, price_gold: int = 1) -> void:
	RequestAdapter.request_auction_list(self, item_id, qty, price_gold)
func request_auction_buy(listing_id: String) -> void:
	RequestAdapter.request_auction_buy(self, listing_id)
func request_auction_cancel(listing_id: String) -> void:
	RequestAdapter.request_auction_cancel(self, listing_id)
func request_learn_skill(skill_id: String) -> void:
	RequestAdapter.request_learn_skill(self, skill_id)
func _apply_attr_update(action: Dictionary) -> void:
	ActionApply.apply_attr_update(self, action)
func _apply_skill_book_update(action: Dictionary) -> void:
	ActionApply.apply_skill_book_update(self, action)
func request_skill_respec() -> void:
	RequestAdapter.request_skill_respec(self)
func _apply_skill_respec(action: Dictionary) -> void:
	ActionApply.apply_skill_respec(self, action)
func request_use_skill(skill_id: String, ground: Vector2i = Vector2i(-9999, -9999)) -> void:
	RequestAdapter.request_use_skill(self, skill_id, ground)
func is_skill_aiming() -> bool:
	return SkillAim.is_skill_aiming(self, )
func begin_skill_aim(skill_id: String) -> void:
	SkillAim.begin_skill_aim(self, skill_id)
func cancel_skill_aim() -> void:
	SkillAim.cancel_skill_aim(self, )
func _ensure_skill_aim() -> void:
	SkillAim._ensure_skill_aim(self, )
func _ensure_skill_fx() -> void:
	SkillAim._ensure_skill_fx(self, )
func _skill_aim_def() -> Dictionary:
	return SkillAim._skill_aim_def(self, )
func _update_skill_aim_preview() -> void:
	SkillAim._update_skill_aim_preview(self, )
func _apply_skill_fx(action: Dictionary) -> void:
	ActionApply.apply_skill_fx(self, action)
func _apply_skill_anim(action: Dictionary) -> void:
	ActionApply.apply_skill_anim(self, action)
func request_use_item(item_id: String) -> void:
	RequestAdapter.request_use_item(self, item_id)
func request_equip_item(item_id: String, slot: String = "") -> void:
	RequestAdapter.request_equip_item(self, item_id, slot)
func request_unequip_item(slot: String) -> void:
	RequestAdapter.request_unequip_item(self, slot)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if bool(Net.session().get("editor_return")):
			Net.session().go_content_editor.call_deferred()
		else:
			Net.session().go_character_select.call_deferred()
		return
	# Interact: Enter / ui_accept while adjacent to an NPC.
	if event.is_action_pressed("ui_accept"):
		if player != null and not player.input_locked:
			var facing_dir: int = 2
			if player.has_method("get_facing"):
				facing_dir = CharsetSheet.dir_from_facing(str(player.get_facing()))
			var npc = _find_adjacent_npc(player.cell, facing_dir)
			if npc != null:
				_engage_npc(npc)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if is_skill_aiming():
			cancel_skill_aim()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if is_skill_aiming():
				cancel_skill_aim()
				get_viewport().set_input_as_handled()
				return
			if _on_world_right_click(mb):
				get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_player_context_menu()
			_on_world_click(mb)
			get_viewport().set_input_as_handled()


func _hud_blocks_world(screen_pos: Vector2) -> bool:
	return HudBinding._hud_blocks_world(self, screen_pos)
func _on_world_right_click(mb: InputEventMouseButton) -> bool:
	## Right-click remote → player context menu. Returns true if consumed.
	if _hud_blocks_world(mb.position):
		_close_player_context_menu()
		return false
	if player == null or map_field == null:
		_close_player_context_menu()
		return false
	var world_pos: Vector2 = get_global_mouse_position()
	var target: Vector2i = map_field.world_to_cell(world_pos)
	var remote = _find_remote_at(target)
	if remote == null:
		_close_player_context_menu()
		return false
	_select_remote(remote)
	_open_player_context_menu(remote, mb.position)
	return true


func _on_world_click(mb: InputEventMouseButton) -> void:
	if hud != null:
		if hud.has_method("blocks_world_click") and hud.blocks_world_click(mb.position):
			return
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hud.is_ancestor_of(hovered):
			return
	if player == null or map_field == null:
		return
	if player.input_locked:
		return
	var world_pos: Vector2 = get_global_mouse_position()
	var target: Vector2i = map_field.world_to_cell(world_pos)
	if is_skill_aiming():
		request_use_skill(_skill_aim_id, target)
		return
	# Click ground bag when adjacent/on cell → open loot UI (no auto-path).
	var bag_id := _find_ground_bag_at(target)
	if bag_id != "":
		var pcell: Vector2i = player.cell if player != null and "cell" in player else Vector2i(-9999, -9999)
		var dist: int = absi(pcell.x - target.x) + absi(pcell.y - target.y)
		if pcell.x > -9990 and dist <= 1:
			_clear_pending_engage()
			clear_target_selection()
			request_open_ground_bag(bag_id)
			return
		# Too far: path toward the bag cell.
	# Click NPC: select. Double-click: engage (path if far, then attack/interact).
	var npc = _find_npc_at(target)
	if npc != null:
		_clear_remote_selection()
		_select_npc(npc)
		if mb.double_click:
			_request_npc_engage(npc)
		else:
			var nid := str(npc.npc_id).strip_edges() if "npc_id" in npc else ""
			if nid.is_empty() or _pending_engage_npc_id != nid:
				_clear_pending_engage()
		return
	# Click remote/fake player: soft select (name only, no HP).
	var remote = _find_remote_at(target)
	if remote != null:
		_clear_pending_engage()
		_select_remote(remote)
		return
	if not player.has_method("click_move_to"):
		return
	_clear_pending_engage()
	stop_follow()
	clear_target_selection()
	var ok: bool = player.click_move_to(target)
	if not ok and hud != null and hud.has_method("append_system"):
		hud.append_system("无法到达该位置")


func _on_transfer_requested(result: Dictionary) -> void:
	MapTransfer._on_transfer_requested(self, result)