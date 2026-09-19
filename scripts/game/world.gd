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
	if hud == null:
		hud = get_node_or_null("CanvasLayer/GameHud")
	if hud == null:
		return
	if hud.has_method("bind_character"):
		hud.bind_character(ch)
	var map_id := str(spawn.get("map_id", "demo_map"))
	if hud.has_method("bind_radar"):
		hud.bind_radar(map_field, player, map_id, self)
	elif hud.has_method("set_minimap_hint"):
		hud.set_minimap_hint("%s\n%s" % [map_id, Net.session().server_address])
	if hud.has_method("apply_combat_stats"):
		var combat_v: Variant = spawn.get("combat", {})
		if typeof(combat_v) == TYPE_DICTIONARY and not (combat_v as Dictionary).is_empty():
			hud.apply_combat_stats(combat_v)
		elif Net.server() != null and Net.server().get("combat_stats") != null:
			hud.apply_combat_stats(Net.server().combat_stats.snapshot_player_stats())
	if hud.has_method("apply_inventory_snapshot"):
		var inv_v: Variant = spawn.get("inventory", [])
		var gold_v: int = int(spawn.get("gold", -1))
		if typeof(inv_v) == TYPE_ARRAY:
			hud.apply_inventory_snapshot(inv_v, gold_v)
	if hud.has_method("apply_equipment_snapshot"):
		var eq_v: Variant = spawn.get("equipment", [])
		var bon_v: Variant = spawn.get("equipment_bonuses", {})
		if typeof(eq_v) == TYPE_ARRAY:
			var bons: Dictionary = bon_v if typeof(bon_v) == TYPE_DICTIONARY else {}
			hud.apply_equipment_snapshot(eq_v, bons)
	if hud.has_method("apply_skill_catalog"):
		var srv_skills = Net.server()
		if srv_skills != null and srv_skills.has_method("snapshot_skill_catalog"):
			hud.apply_skill_catalog(srv_skills.snapshot_skill_catalog())
	if hud.has_method("apply_skill_book"):
		var book_v: Variant = spawn.get("skill_book", {})
		if typeof(book_v) == TYPE_DICTIONARY and not (book_v as Dictionary).is_empty():
			hud.apply_skill_book(book_v)
		else:
			var srv_book = Net.server()
			if srv_book != null and srv_book.has_method("snapshot_skill_book"):
				hud.apply_skill_book(srv_book.snapshot_skill_book())
	if hud.has_method("apply_quest_snapshot"):
		var quests_v: Variant = spawn.get("quests", [])
		if typeof(quests_v) == TYPE_ARRAY and not (quests_v as Array).is_empty():
			hud.apply_quest_snapshot(quests_v)
		else:
			var srv_q = Net.server()
			if srv_q != null and srv_q.has_method("get_quest_list"):
				hud.apply_quest_snapshot(srv_q.get_quest_list())
	if hud.has_method("apply_daily_board"):
		hud.apply_daily_board(spawn)
	if hud.has_method("apply_party_update"):
		var party_v: Variant = spawn.get("party", {})
		if typeof(party_v) == TYPE_DICTIONARY:
			hud.apply_party_update({"type": "party_update", "party": party_v})
		elif Net.server() != null and Net.server().has_method("snapshot_party"):
			hud.apply_party_update({"type": "party_update", "party": Net.server().snapshot_party()})
	if hud.has_method("apply_trade_update"):
		var trade_v: Variant = spawn.get("trade", {})
		if typeof(trade_v) == TYPE_DICTIONARY and bool(trade_v.get("active", false)):
			hud.apply_trade_update({"type": "trade_update", "trade": trade_v})
	if hud.has_method("apply_duel_update"):
		var duel_v: Variant = spawn.get("duel", {})
		if typeof(duel_v) == TYPE_DICTIONARY:
			hud.apply_duel_update({"type": "duel_update", "duel": duel_v})
		elif Net.server() != null and Net.server().has_method("snapshot_duel"):
			hud.apply_duel_update({"type": "duel_update", "duel": Net.server().snapshot_duel()})
	if hud.has_method("apply_safe_zone"):
		var sz_v: Variant = spawn.get("safe_zone", {})
		if typeof(sz_v) == TYPE_DICTIONARY:
			hud.apply_safe_zone({"type": "safe_zone", "inside": bool(sz_v.get("inside", false))})
		elif Net.server() != null and Net.server().has_method("player_in_safe_zone"):
			hud.apply_safe_zone({"type": "safe_zone", "inside": bool(Net.server().player_in_safe_zone())})
	if hud.has_method("apply_dungeon_update"):
		var dg_v: Variant = spawn.get("dungeon", {})
		if typeof(dg_v) == TYPE_DICTIONARY:
			hud.apply_dungeon_update({"type": "dungeon_update", "dungeon": dg_v})
		elif Net.server() != null and Net.server().has_method("snapshot_dungeon"):
			hud.apply_dungeon_update({"type": "dungeon_update", "dungeon": Net.server().snapshot_dungeon()})

	if hud.has_method("apply_craft_update"):
		var craft_act := {
			"type": "craft_update",
			"craft_level": int(spawn.get("craft_level", 1)),
			"craft_xp": int(spawn.get("craft_xp", 0)),
			"craft_xp_to_next": int(spawn.get("craft_xp_to_next", 30)),
		}
		if Net.server() != null and Net.server().has_method("snapshot_craft"):
			var cs: Dictionary = Net.server().snapshot_craft()
			craft_act["craft_level"] = int(cs.get("craft_level", craft_act["craft_level"]))
			craft_act["craft_xp"] = int(cs.get("craft_xp", craft_act["craft_xp"]))
			craft_act["craft_xp_to_next"] = int(cs.get("craft_xp_to_next", craft_act["craft_xp_to_next"]))
		elif spawn.has("craft_level") or spawn.has("craft_xp"):
			pass
		hud.apply_craft_update(craft_act)

	if hud.has_method("apply_gather_update"):
		var gather_act := {
			"type": "gather_update",
			"gather_level": int(spawn.get("gather_level", 1)),
			"gather_xp": int(spawn.get("gather_xp", 0)),
			"gather_xp_to_next": int(spawn.get("gather_xp_to_next", 30)),
		}
		if Net.server() != null and Net.server().has_method("snapshot_gather"):
			var gs: Dictionary = Net.server().snapshot_gather()
			gather_act["gather_level"] = int(gs.get("gather_level", gather_act["gather_level"]))
			gather_act["gather_xp"] = int(gs.get("gather_xp", gather_act["gather_xp"]))
			gather_act["gather_xp_to_next"] = int(gs.get("gather_xp_to_next", gather_act["gather_xp_to_next"]))
		hud.apply_gather_update(gather_act)

	if hud.has_method("apply_warehouse_update"):
		var wh_v: Variant = spawn.get("warehouse", {})
		if typeof(wh_v) == TYPE_DICTIONARY:
			hud.apply_warehouse_update({"type": "warehouse_update", "warehouse": wh_v})
		elif Net.server() != null and Net.server().has_method("snapshot_warehouse"):
			hud.apply_warehouse_update({"type": "warehouse_update", "warehouse": Net.server().snapshot_warehouse()})

	if hud.has_method("apply_friends_update"):
		var fr_v: Variant = spawn.get("friends", {})
		if typeof(fr_v) == TYPE_DICTIONARY:
			hud.apply_friends_update({"type": "friends_update", "friends": fr_v})
		elif Net.server() != null and Net.server().has_method("snapshot_friends"):
			hud.apply_friends_update({"type": "friends_update", "friends": Net.server().snapshot_friends()})

	if hud.has_method("apply_guild_update"):
		var gu_v: Variant = spawn.get("guild", {})
		if typeof(gu_v) == TYPE_DICTIONARY:
			hud.apply_guild_update({"type": "guild_update", "guild": gu_v})
		elif Net.server() != null and Net.server().has_method("snapshot_guild"):
			hud.apply_guild_update({"type": "guild_update", "guild": Net.server().snapshot_guild()})

	if hud.has_method("apply_mail_update"):
		var mail_v: Variant = spawn.get("mail", {})
		if typeof(mail_v) == TYPE_DICTIONARY:
			hud.apply_mail_update({"type": "mail_update", "mail": mail_v})
		elif Net.server() != null and Net.server().has_method("snapshot_mail"):
			hud.apply_mail_update({"type": "mail_update", "mail": Net.server().snapshot_mail()})

	if hud.has_method("apply_auction_update"):
		var ah_v: Variant = spawn.get("auction", {})
		if typeof(ah_v) == TYPE_DICTIONARY:
			hud.apply_auction_update({"type": "auction_update", "auction": ah_v})
		elif Net.server() != null and Net.server().has_method("snapshot_auction"):
			hud.apply_auction_update({"type": "auction_update", "auction": Net.server().snapshot_auction()})

	if hud.has_method("apply_title_update"):
		var titles_v: Variant = spawn.get("titles", {})
		if typeof(titles_v) == TYPE_DICTIONARY:
			hud.apply_title_update({"type": "title_update", "titles": titles_v})
		elif Net.server() != null and Net.server().has_method("snapshot_titles"):
			hud.apply_title_update({"type": "title_update", "titles": Net.server().snapshot_titles()})

	if hud.has_method("apply_achievement_update"):
		var ach_v: Variant = spawn.get("achievements", {})
		if typeof(ach_v) == TYPE_DICTIONARY:
			hud.apply_achievement_update({"type": "achievement_update", "achievements": ach_v})
		elif Net.server() != null and Net.server().has_method("snapshot_achievements"):
			hud.apply_achievement_update({"type": "achievement_update", "achievements": Net.server().snapshot_achievements()})

	var remotes_v: Variant = spawn.get("remote_players", [])
	if typeof(remotes_v) == TYPE_ARRAY:
		for rp in remotes_v:
			if typeof(rp) == TYPE_DICTIONARY:
				_upsert_remote_marker(rp)
	var pet_v: Variant = spawn.get("pet", {})
	if typeof(pet_v) == TYPE_DICTIONARY and bool(pet_v.get("active", false)):
		_upsert_pet_marker(pet_v)
	elif Net.server() != null and Net.server().has_method("snapshot_pet"):
		var pet2: Dictionary = Net.server().snapshot_pet()
		if bool(pet2.get("active", false)):
			_upsert_pet_marker(pet2)
	elif Net.server() != null and Net.server().has_method("snapshot_remote_players"):
		for rp2 in Net.server().snapshot_remote_players():
			if typeof(rp2) == TYPE_DICTIONARY:
				_upsert_remote_marker(rp2)
	if hud.has_method("bind_world_combat"):
		hud.bind_world_combat(self)
	var eq_bind: Variant = spawn.get("equipment", [])
	if typeof(eq_bind) == TYPE_ARRAY:
		_refresh_player_gear_look(eq_bind)
	_apply_camera_zoom()
	# Ground bags from spawn snapshot (map re-entry).
	var bags_v: Variant = spawn.get("ground_bags", [])
	if typeof(bags_v) == TYPE_ARRAY:
		for b in bags_v:
			if typeof(b) == TYPE_DICTIONARY:
				_upsert_ground_marker(b)
	elif Net.server() != null and Net.server().has_method("snapshot_ground_bags"):
		for b2 in Net.server().snapshot_ground_bags():
			if typeof(b2) == TYPE_DICTIONARY:
				_upsert_ground_marker(b2)
	if hud.has_method("append_system"):
		hud.append_system("进入角色：%s（Lv.%s）" % [str(ch.get("name", "?")), str(ch.get("level", 1))])
		var transfer_msg: String = str(spawn.get("transfer_message", "")).strip_edges()
		if transfer_msg != "":
			hud.append_system(transfer_msg)
			var sd: Dictionary = Net.session().spawn_data
			if sd.has("transfer_message"):
				sd.erase("transfer_message")
				Net.session().spawn_data = sd


func _clear_npcs() -> void:
	var am: Node = _asset_mgr
	for n in _npcs:
		if n != null and is_instance_valid(n):
			if am != null and "npc_id" in n and am.has_method("clear_actor_refs"):
				var nid := str(n.npc_id).strip_edges()
				if nid != "":
					am.clear_actor_refs(nid)
					if am.has_method("note_actor_ring"):
						am.note_actor_ring(nid, "COLD")
			n.queue_free()
	_npcs.clear()
	if _aoi != null:
		_aoi.reset()
	_radar_blips_cache.clear()
	_radar_blips_sig = PackedInt32Array()
	_radar_blips_ready = false
	if _npc_layer != null and is_instance_valid(_npc_layer):
		for c in _npc_layer.get_children():
			c.queue_free()
	_clear_ground_markers()


func _clear_ground_markers() -> void:
	_hovered_ground_bag_id = ""
	if hud != null and hud.has_method("hide_ground_tip"):
		hud.hide_ground_tip()
	for bid in _ground_markers.keys():
		var n = _ground_markers[bid]
		if n != null and is_instance_valid(n):
			n.queue_free()
	_ground_markers.clear()
	if _ground_layer != null and is_instance_valid(_ground_layer):
		for c in _ground_layer.get_children():
			c.queue_free()


func _ensure_ground_layer() -> Node2D:
	if _ground_layer != null and is_instance_valid(_ground_layer):
		return _ground_layer
	_ground_layer = get_node_or_null("GroundBagLayer") as Node2D
	if _ground_layer == null:
		_ground_layer = Node2D.new()
		_ground_layer.name = "GroundBagLayer"
		_ground_layer.z_index = 4
		_ground_layer.z_as_relative = false
		add_child(_ground_layer)
		if map_field != null:
			move_child(_ground_layer, map_field.get_index() + 1)
	return _ground_layer


func _ensure_npc_layer() -> Node2D:
	if _npc_layer != null and is_instance_valid(_npc_layer):
		return _npc_layer
	_npc_layer = get_node_or_null("NpcLayer") as Node2D
	if _npc_layer == null:
		_npc_layer = Node2D.new()
		_npc_layer.name = "NpcLayer"
		_npc_layer.y_sort_enabled = true
		_npc_layer.z_index = 5
		_npc_layer.z_as_relative = false
		add_child(_npc_layer)
		# Keep under map visuals but with player/npcs sorting among themselves.
		if map_field != null:
			move_child(_npc_layer, map_field.get_index() + 1)
	return _npc_layer


func _spawn_npcs_from_pack() -> void:
	_clear_npcs()
	if map_field == null or map_field.pack == null:
		return
	var pack = map_field.pack
	# Optional pack charset_root -> ProjectSettings for this session.
	var pack_root: String = str(pack.charset_root) if pack.get("charset_root") != null else ""
	if pack_root.strip_edges() != "":
		ProjectSettings.set_setting(CharsetSheet.SETTING_ROOT, pack_root.strip_edges())
	elif not ProjectSettings.has_setting(CharsetSheet.SETTING_ROOT):
		ProjectSettings.set_setting(CharsetSheet.SETTING_ROOT, CharsetSheet.DEFAULT_DEV_ROOT)

	var list: Array = pack.npcs if pack.get("npcs") != null else []
	var occupied: Dictionary = {}
	for item0 in list:
		if typeof(item0) != TYPE_DICTIONARY:
			continue
		var c0: Variant = item0.get("cell", {})
		if typeof(c0) == TYPE_DICTIONARY:
			occupied["%d,%d" % [int(c0.get("x", 0)), int(c0.get("y", 0))]] = true
	var evs: Array = pack.events if pack.get("events") != null else []
	var rt = null
	var srv0 = Net.server()
	if srv0 != null and "event_runtime" in srv0:
		rt = srv0.event_runtime
	for ev_v in evs:
		if typeof(ev_v) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_v
		var ec: Variant = ev.get("cell", {})
		if typeof(ec) != TYPE_DICTIONARY:
			continue
		var ekey := "%d,%d" % [int(ec.get("x", 0)), int(ec.get("y", 0))]
		if occupied.has(ekey):
			continue
		var page: Dictionary = {}
		if rt != null and rt.has_method("select_page"):
			page = rt.select_page(ev)
		var ev_actor: Dictionary = EventCommands.event_actor_data(ev, page)
		list.append(ev_actor)
		occupied[ekey] = true
	if list.is_empty():
		return
	var layer := _ensure_npc_layer()
	var pack_dir: String = str(pack.pack_dir)
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var npc_n = NpcActor.new()
		layer.add_child(npc_n)
		npc_n.setup(item, map_field, pack_dir)
		# Charset stream: AOI driver enqueues by ring; NpcActor may show placeholder
		_npcs.append(npc_n)
	# Sync occupancy onto MockServer collision (authoritative move checks).
	var srv = Net.server()
	if srv != null and srv.map_collision != null and srv.map_collision.has_method("apply_npc_blocks"):
		srv.map_collision.clear_extra_blocked()
		srv.map_collision.apply_npc_blocks(list)
		# Re-apply player occupancy wiped by clear_extra_blocked.
		if player != null and srv.has_method("set_player_cell"):
			srv.set_player_cell(player.cell.x, player.cell.y)
	# Register NPC cells for server-side range / tick counter-attacks.
	if srv != null and srv.has_method("register_npc"):
		for item in list:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = item
			var nid := str(n.get("id", "")).strip_edges()
			if nid.is_empty():
				continue
			var cell_v: Variant = n.get("cell", {})
			if typeof(cell_v) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = cell_v
			srv.register_npc(
				nid,
				int(cd.get("x", 0)),
				int(cd.get("y", 0)),
				bool(n.get("hostile", false)),
				bool(n.get("aggressive", false)),
				int(n.get("direction", 2)),
				maxi(int(n.get("wander_radius", 0)), 0),
				int(n.get("group_id", 0)),
				n
			)
	_sync_npc_combat_display()
	_refresh_aoi(true)


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
	if _event_wait_left <= 0.0:
		return
	_event_wait_left -= delta
	if _event_wait_left > 0.0:
		return
	var rest: Array = _deferred_event_actions
	var n = _deferred_event_npc
	_deferred_event_actions = []
	_deferred_event_npc = null
	_event_wait_left = 0.0
	if not rest.is_empty():
		_apply_server_actions(rest, n)


func _apply_server_actions(actions: Array, npc = null) -> void:
	ActionApply.apply_server_actions(self, actions, npc)
func _apply_npc_move(action: Dictionary) -> void:
	ActionApply.apply_npc_move(self, action)
func _apply_npc_reset(action: Dictionary) -> void:
	ActionApply.apply_npc_reset(self, action)
func _apply_damage_action(action: Dictionary, npc = null) -> void:
	ActionApply.apply_damage_action(self, action, npc)
func _connect_game_settings() -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	if not gs.changed.is_connected(_on_game_settings_changed):
		gs.changed.connect(_on_game_settings_changed)
	_on_game_settings_changed()


func _on_game_settings_changed() -> void:
	_push_auto_potion_settings()
	_push_pet_assist_settings()
	_apply_camera_zoom()
	for npc in _npcs:
		if npc != null and is_instance_valid(npc) and npc.has_method("_refresh_nameplate"):
			npc._refresh_nameplate()
	_refresh_remote_nameplates()
	_apply_atmosphere()


func _push_auto_potion_settings() -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var srv = Net.server() if Net != null else null
	if srv == null or not srv.has_method("try_set_auto_potion"):
		return
	srv.try_set_auto_potion(
		bool(gs.auto_potion_hp),
		int(gs.auto_potion_hp_pct),
		bool(gs.auto_potion_mp),
		int(gs.auto_potion_mp_pct),
	)


func _push_pet_assist_settings() -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var srv = Net.server() if Net != null else null
	if srv == null or not srv.has_method("try_set_pet_assist"):
		return
	srv.try_set_pet_assist(bool(gs.get("pet_assist")) if "pet_assist" in gs else true)


func _trigger_crit_shake() -> void:
	## Brief Camera2D.offset jitter on crit; gated by GameSettings.screen_shake.
	if not GameSettingsScript.flag("screen_shake", true):
		return
	if _camera_shake == null:
		_camera_shake = CameraShake.new()
	_camera_shake.trigger()


func _desired_combat_frame_offset() -> Vector2:
	## Soft bias toward selected hostile; ZERO when off / no hostile / invalid.
	if not GameSettingsScript.flag("combat_camera_frame", true):
		return Vector2.ZERO
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	if _selected_npc_id.is_empty():
		return Vector2.ZERO
	var npc = _find_npc_by_id(_selected_npc_id)
	if npc == null or not is_instance_valid(npc):
		return Vector2.ZERO
	if not ("hostile" in npc and bool(npc.hostile)):
		return Vector2.ZERO
	return CombatCamera.compute_frame_offset(player.global_position, npc.global_position)


func _tick_camera_shake(delta: float) -> void:
	## Lerp combat frame offset, then apply shake additively on Camera2D.offset.
	var desired: Vector2 = _desired_combat_frame_offset()
	_combat_cam_offset = CombatCamera.lerp_offset(_combat_cam_offset, desired, delta)
	if _camera_shake != null:
		_camera_shake.tick(delta)
	if player == null or not is_instance_valid(player):
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if _camera_shake != null:
		_camera_shake.apply_to(cam, _combat_cam_offset)
	else:
		cam.offset = _combat_cam_offset


func _spawn_combat_floater(
	world_pos: Vector2,
	text: String,
	_color: Color = Color(),
	kind: String = "damage",
	target_key: String = "default",
	crit: bool = false
) -> Label:
	## Rising Label over target; capped per target_key via CombatFloater.
	if not GameSettingsScript.flag("show_damage_numbers", true):
		return null
	return CombatFloater.spawn(self, world_pos, text, kind, target_key, crit)


func _apply_miss_action(action: Dictionary) -> void:
	ActionApply.apply_miss_action(self, action)
func _resolve_emote_host(actor_id: String) -> Node2D:
	## Local player, remote marker, or NPC — whichever matches actor_id.
	actor_id = str(actor_id).strip_edges()
	if actor_id.is_empty() or actor_id == "player":
		return player
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		if actor_id == str(srv._party_self_id()):
			return player
	if _remote_markers.has(actor_id):
		var mk = _remote_markers[actor_id]
		if mk != null and is_instance_valid(mk):
			return mk
	var npc = _find_npc_by_id(actor_id)
	if npc != null and is_instance_valid(npc):
		return npc
	# Fallback: treat unknown as local self (client-originated emote).
	return player


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
	if npc == null:
		return false
	if range_cells <= 1:
		return _player_beside_npc(npc, pcell)
	var tcell := _npc_target_cell(npc)
	if tcell.x <= -9990:
		return false
	return _cheb(pcell, tcell) <= maxi(range_cells, 1)


## -1 = no chase (self buff/heal). Else Chebyshev cells.
func _skill_chase_range(def: Dictionary) -> int:
	if def.is_empty():
		return 1
	var tmode := str(def.get("target_mode", "")).strip_edges().to_lower()
	if tmode.is_empty() and bool(def.get("requires_target", false)):
		tmode = "unit"
	var req := bool(def.get("requires_target", false))
	var rng: int = int(def.get("range", 0))
	var effect := str(def.get("effect", "")).strip_edges()
	if effect == "heal" or effect == "recall" or effect == "teleport_home":
		if not req and tmode != "ground" and tmode != "unit":
			return -1
	if tmode == "none" and not req and rng <= 0:
		return -1
	if not req and tmode != "ground" and tmode != "unit" and rng <= 0:
		return -1
	return maxi(rng, 1)


func _path_to_npc_range(npc, range_cells: int) -> bool:
	if npc == null or player == null or not player.has_method("click_move_to"):
		return false
	var pcell: Vector2i = player.cell
	var tcell := _npc_target_cell(npc)
	if tcell.x <= -9990:
		return false
	var dest: Vector2i = _approach_cell(pcell, tcell, range_cells)
	if dest == pcell:
		return true
	return bool(player.click_move_to(dest))


## Double-click hostile: run to melee, face, keep auto-attacking.
func _request_npc_engage(npc) -> void:
	if npc == null or player == null:
		return
	if player.input_locked:
		return
	var pcell: Vector2i = player.cell if "cell" in player else Vector2i.ZERO
	var is_hostile := bool(npc.hostile) if "hostile" in npc else false
	if is_hostile:
		stop_follow()
		if not _auto_attack:
			_auto_attack = true
			if hud != null and hud.has_method("append_system"):
				hud.append_system("自动攻击：开")
		_face_toward_cell(_npc_target_cell(npc))
		if _player_beside_npc(npc, pcell):
			_clear_pending_engage()
			_try_attack_npc(npc)
			return
		_set_pending_engage(npc, "", 1)
		if not _path_to_npc_range(npc, 1):
			_clear_pending_engage()
			if hud != null and hud.has_method("append_system"):
				hud.append_system("无法到达该位置")
		return
	if _player_beside_npc(npc, pcell):
		_clear_pending_engage()
		_engage_npc(npc)
		return
	_set_pending_engage(npc)
	if not _path_to_npc_range(npc, 1):
		_clear_pending_engage()
		if hud != null and hud.has_method("append_system"):
			hud.append_system("无法到达该位置")


func _on_player_path_cancelled() -> void:
	# Keyboard / failed step: drop click-to-engage intent.
	_clear_pending_engage()
	if not _follow_id.is_empty() and player != null:
		var dir_vec := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if dir_vec.length() >= 0.5:
			stop_follow()


func _on_player_arrived_cell(cell: Vector2i, path_complete: bool) -> void:
	_sync_map_observer()
	_play_footstep()
	_refresh_npc_nameplates()
	_refresh_remote_nameplates()
	if GameSettingsScript.flag("auto_pickup", false):
		_try_auto_pickup_at(cell)
	if _pending_engage_npc_id.is_empty():
		return
	if player != null and player.input_locked:
		return
	var npc = _find_npc_by_id(_pending_engage_npc_id)
	if npc == null:
		_clear_pending_engage()
		return
	var sid := _pending_skill_id
	var rng: int = _pending_skill_range
	if not sid.is_empty():
		if _player_in_skill_range(npc, rng, cell):
			_face_toward_cell(_npc_target_cell(npc))
			_pending_skill_id = ""
			_pending_engage_npc_id = ""
			_pending_skill_range = 1
			if player != null and player.has_method("clear_move_path"):
				player.clear_move_path()
			request_use_skill(sid)
		elif path_complete:
			if not _path_to_npc_range(npc, rng):
				_clear_pending_engage()
		return
	var beside := _player_beside_npc(npc, cell)
	if not beside:
		if path_complete:
			if not _path_to_npc_range(npc, 1):
				_clear_pending_engage()
		return
	_clear_pending_engage()
	if player != null and player.has_method("clear_move_path"):
		player.clear_move_path()
	_face_toward_cell(_npc_target_cell(npc))
	_engage_npc(npc)


func start_follow(target_id: String) -> void:
	target_id = target_id.strip_edges()
	if target_id.is_empty():
		return
	_follow_id = target_id
	if hud != null and hud.has_method("append_system"):
		hud.append_system("开始跟随。")
	_tick_follow()


func stop_follow() -> void:
	if _follow_id.is_empty():
		return
	_follow_id = ""
	if hud != null and hud.has_method("append_system"):
		hud.append_system("停止跟随。")


func is_following() -> bool:
	return not _follow_id.is_empty()


func get_follow_id() -> String:
	return _follow_id


func _tick_follow() -> void:
	if _follow_id.is_empty() or player == null or player.input_locked:
		return
	if player.moving:
		return
	var tcell := _follow_target_cell()
	if tcell.x <= -9990:
		stop_follow()
		return
	var pcell: Vector2i = player.cell
	var dist: int = maxi(absi(pcell.x - tcell.x), absi(pcell.y - tcell.y))
	if dist <= 1:
		return
	if player.has_method("click_move_to"):
		player.click_move_to(tcell)


func _follow_target_cell() -> Vector2i:
	if _remote_markers.has(_follow_id):
		var mk = _remote_markers[_follow_id]
		if mk != null and is_instance_valid(mk) and mk.has_meta("cell"):
			return mk.get_meta("cell")
	var npc = _find_npc_by_id(_follow_id)
	if npc != null and "cell" in npc:
		return npc.cell
	return Vector2i(-9999, -9999)


func _apply_remote_look(marker: Node2D, gender: String, look_id: String, equipment: Variant) -> void:
	var anim := marker.get_node_or_null("Anim") as AnimatedSprite2D
	if anim == null:
		return
	var LookCatalog = load("res://scripts/char/look_catalog.gd")
	var MV = load("res://scripts/char/mv_generator.gd")
	gender = LookCatalog.normalize_gender(gender) if LookCatalog != null else gender
	var frames: SpriteFrames = null
	var eq: Array = equipment if typeof(equipment) == TYPE_ARRAY else []
	if MV != null and MV.has_method("compose_frames"):
		var parts: Dictionary = MV.default_parts(gender) if MV.has_method("default_parts") else {}
		if PaperdollLook != null and not eq.is_empty():
			var catalog = null
			var srv = Net.server()
			if srv != null:
				catalog = srv.get("item_catalog")
			var overlay: Dictionary = PaperdollLook.equipment_to_mv_parts(gender, eq, catalog)
			parts = MV.apply_equipment(parts, overlay)
			parts = MV.validate_parts(gender, parts)
		frames = MV.compose_frames(gender, parts, {})
	if frames == null and LookCatalog != null and LookCatalog.has_method("build_walk_frames"):
		frames = LookCatalog.build_walk_frames(look_id if look_id != "" else "1", gender)
	if frames == null:
		if marker.get_node_or_null("Body") == null:
			var body := Polygon2D.new()
			body.name = "Body"
			body.polygon = PackedVector2Array([
				Vector2(-8, -20), Vector2(8, -20), Vector2(10, 4), Vector2(-10, 4)
			])
			body.color = Color(0.35, 0.55, 0.95, 0.9)
			marker.add_child(body)
		return
	var legacy := marker.get_node_or_null("Body")
	if legacy != null:
		legacy.queue_free()
	anim.sprite_frames = frames
	anim.scale = Vector2(1.35, 1.35)
	if frames.has_animation("idle_front"):
		anim.play("idle_front")
	elif frames.has_animation("idle_Front"):
		anim.play("idle_Front")


func inspect_remote(player_id: String) -> Dictionary:
	player_id = player_id.strip_edges()
	var out := {"id": player_id, "name": player_id, "level": 1, "gender": "female", "equipment": []}
	if _remote_markers.has(player_id):
		var mk = _remote_markers[player_id]
		if mk != null and is_instance_valid(mk):
			out["name"] = str(mk.get_meta("display_name", player_id))
			out["level"] = int(mk.get_meta("level", 1))
			out["gender"] = str(mk.get_meta("gender", "female"))
	var srv = Net.server()
	if srv != null and srv.has_method("get_remote_player"):
		var rd: Dictionary = srv.get_remote_player(player_id)
		if not rd.is_empty():
			if str(rd.get("name", "")) != "":
				out["name"] = str(rd.get("name"))
			if rd.has("level"):
				out["level"] = int(rd.get("level", 1))
			if rd.has("gender"):
				out["gender"] = str(rd.get("gender"))
			if typeof(rd.get("equipment", null)) == TYPE_ARRAY:
				out["equipment"] = rd.get("equipment")
	return out


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
	var markers: Array = get_radar_poi_markers() if has_method("get_radar_poi_markers") else []
	var hit: Dictionary = RadarPoi.marker_at_cell(markers, cell)
	if hit.is_empty():
		return ""
	return RadarPoi.marker_nav_label(hit)


func toggle_map_pin(cell: Vector2i, short_name: String = "") -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("try_map_pin_toggle"):
		var mid := str(srv.map_pack_id) if "map_pack_id" in srv else ""
		var result: Dictionary = srv.try_map_pin_toggle(cell.x, cell.y, mid, short_name)
		var actions_v: Variant = result.get("actions", [])
		if typeof(actions_v) == TYPE_ARRAY:
			_apply_server_actions(actions_v)
		_sync_map_pins_from_server(result.get("map_pins", {}))
		_radar_blips_ready = false
		return
	# Legacy single-pin fallback (no MockServer).
	if _map_pin == cell:
		_map_pin = Vector2i(-9999, -9999)
		if hud != null and hud.has_method("append_system"):
			hud.append_system("已清除地图标记")
	else:
		_map_pin = cell
		if hud != null and hud.has_method("append_system"):
			hud.append_system("标记 (%d, %d)" % [cell.x, cell.y])
	if hud != null and hud.has_method("set_map_pin"):
		hud.set_map_pin(_map_pin)


func clear_map_pins() -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("try_map_pin_clear"):
		var result: Dictionary = srv.try_map_pin_clear()
		var actions_v: Variant = result.get("actions", [])
		if typeof(actions_v) == TYPE_ARRAY:
			_apply_server_actions(actions_v)
		_sync_map_pins_from_server(result.get("map_pins", {}))
		_radar_blips_ready = false
		return
	_map_pin = Vector2i(-9999, -9999)
	if hud != null and hud.has_method("set_map_pin"):
		hud.set_map_pin(_map_pin)
	if hud != null and hud.has_method("append_system"):
		hud.append_system("已清除全部标记")


func _sync_map_pins_from_server(snap: Variant) -> void:
	var pins: Array = []
	if typeof(snap) == TYPE_DICTIONARY:
		var pv: Variant = snap.get("pins", [])
		if typeof(pv) == TYPE_ARRAY:
			pins = pv
	elif typeof(snap) == TYPE_ARRAY:
		pins = snap
	# Legacy first-pin cell for shell/HUD set_pin_cell.
	_map_pin = Vector2i(-9999, -9999)
	for p in pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var cell_v: Variant = p.get("cell", {})
		if typeof(cell_v) == TYPE_VECTOR2I:
			_map_pin = cell_v
		elif typeof(cell_v) == TYPE_DICTIONARY:
			_map_pin = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
		break
	if hud != null and hud.has_method("apply_map_pins_update"):
		hud.apply_map_pins_update({"type": "map_pins_update", "map_pins": {"pins": pins, "count": pins.size()}})
	elif hud != null and hud.has_method("set_map_pin"):
		hud.set_map_pin(_map_pin)


func map_pin_cell() -> Vector2i:
	return _map_pin


func map_pins_snapshot() -> Array:
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_map_pins"):
		var snap: Dictionary = srv.snapshot_map_pins()
		var pv: Variant = snap.get("pins", [])
		if typeof(pv) == TYPE_ARRAY:
			return pv
	return []


func cycle_hostile_target(dir: int = 1) -> void:
	var hostiles: Array = []
	for npc in _npcs:
		if npc == null or not is_instance_valid(npc):
			continue
		if not ("hostile" in npc and bool(npc.hostile)):
			continue
		hostiles.append(npc)
	if hostiles.is_empty():
		if hud != null and hud.has_method("append_system"):
			hud.append_system("附近没有敌人。")
		return
	if dir == 0:
		dir = 1
	var n: int = hostiles.size()
	var cur := -1
	for i in range(n):
		var npc = hostiles[i]
		var nid := str(npc.npc_id).strip_edges() if "npc_id" in npc else ""
		if nid != "" and nid == _selected_npc_id:
			cur = i
			break
	if cur < 0:
		_cycle_index = 0 if dir > 0 else n - 1
	else:
		_cycle_index = (cur + dir) % n
		if _cycle_index < 0:
			_cycle_index += n
	_select_npc(hostiles[_cycle_index])


func toggle_auto_attack() -> void:
	_auto_attack = not _auto_attack
	if hud != null and hud.has_method("append_system"):
		hud.append_system("自动攻击：%s" % ("开" if _auto_attack else "关"))


func is_auto_attack() -> bool:
	return _auto_attack


func _tick_auto_attack(delta: float) -> void:
	if not _auto_attack or player == null or player.input_locked:
		return
	if not _pending_skill_id.is_empty():
		return
	_auto_attack_cd = maxf(0.0, _auto_attack_cd - delta)
	if _auto_attack_cd > 0.0:
		return
	# Duel shell: swing at selected remote opponent when adjacent.
	if not _selected_remote_id.is_empty():
		var dsrv = Net.server()
		if dsrv != null and dsrv.has_method("in_duel") and dsrv.in_duel():
			var dsnap: Dictionary = dsrv.snapshot_duel() if dsrv.has_method("snapshot_duel") else {}
			if str(dsnap.get("opponent_id", "")) == _selected_remote_id and dsrv.has_method("try_attack"):
				var mk = _remote_markers.get(_selected_remote_id, null)
				var beside := true
				if mk != null and is_instance_valid(mk):
					var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
					var rcell := Vector2i.ZERO
					if typeof(cv) == TYPE_VECTOR2I:
						rcell = cv
					elif typeof(cv) == TYPE_DICTIONARY:
						rcell = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
					var pcell: Vector2i = player.cell
					beside = maxi(absi(pcell.x - rcell.x), absi(pcell.y - rcell.y)) <= 1
				if beside:
					_auto_attack_cd = 0.85
					var result: Dictionary = dsrv.try_attack(_selected_remote_id, player.cell.x, player.cell.y)
					var acts_v: Variant = result.get("actions", [])
					if typeof(acts_v) == TYPE_ARRAY:
						_apply_server_actions(acts_v)
				else:
					_auto_attack_cd = 0.4
				return
	if _selected_npc_id.is_empty():
		return
	var npc = _find_npc_by_id(_selected_npc_id)
	if npc == null or not ("hostile" in npc and bool(npc.hostile)):
		return
	var pcell2: Vector2i = player.cell
	if _player_beside_npc(npc, pcell2):
		_auto_attack_cd = 0.85
		_face_toward_cell(_npc_target_cell(npc))
		_try_attack_npc(npc)
	elif player.has_method("click_move_to") and not player.moving:
		_auto_attack_cd = 0.4
		_path_to_npc_range(npc, 1)



func pickup_nearest() -> void:
	if player == null or player.input_locked:
		return
	var best_id := ""
	var best_d := 99
	var pcell: Vector2i = player.cell
	for bag_id in _ground_markers.keys():
		var mk = _ground_markers[bag_id]
		if mk == null or not is_instance_valid(mk) or not mk.has_meta("cell"):
			continue
		var c: Vector2i = mk.get_meta("cell")
		var d: int = maxi(absi(pcell.x - c.x), absi(pcell.y - c.y))
		if d < best_d:
			best_d = d
			best_id = str(bag_id)
	if best_id.is_empty() or best_d > 8:
		if hud != null and hud.has_method("append_system"):
			hud.append_system("附近没有掉落。")
		return
	if best_d <= 1:
		request_open_ground_bag(best_id)
		return
	var mk2 = _ground_markers[best_id]
	if player.has_method("click_move_to") and mk2.has_meta("cell"):
		player.click_move_to(mk2.get_meta("cell"))


func _try_auto_pickup_at(cell: Vector2i) -> void:
	var bag_id := _find_ground_bag_at(cell)
	if bag_id.is_empty():
		return
	var srv = Net.server()
	# Respect party loot ownership — do not auto-open/take teammates' bags.
	if srv != null and srv.has_method("can_loot_ground_bag") and not bool(srv.can_loot_ground_bag(bag_id)):
		return
	request_open_ground_bag(bag_id)
	call_deferred("_auto_take_all")


func _auto_take_all() -> void:
	var srv = Net.server()
	if srv == null:
		return
	var gs := GameSettingsScript.get_i()
	var filter := "all"
	if gs != null:
		filter = str(gs.get("auto_pickup_filter"))
	if filter not in GameSettingsScript.AUTO_PICKUP_FILTER_IDS:
		filter = "all"
	if filter == "all":
		if srv.has_method("try_loot_take_all"):
			var result: Dictionary = srv.try_loot_take_all()
			var actions_v: Variant = result.get("actions", [])
			if typeof(actions_v) == TYPE_ARRAY:
				_apply_server_actions(actions_v)
		return
	# Filtered auto-loot: take matching stacks only; leave rest on ground.
	if not srv.has_method("try_loot_take"):
		return
	var catalog = srv.get("item_catalog")
	var pending: Array = []
	if srv.has_method("pending_loot_snapshot"):
		var snap: Dictionary = srv.pending_loot_snapshot()
		var items_v: Variant = snap.get("items", [])
		if typeof(items_v) == TYPE_ARRAY:
			pending = items_v
	var ids: Array = []
	for d_v in pending:
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var iid := str(d_v.get("item_id", "")).strip_edges()
		if iid.is_empty():
			continue
		if GameSettingsScript.matches_auto_pickup_filter(filter, iid, catalog):
			ids.append(iid)
	for iid in ids:
		if not srv.has_method("has_pending_loot") or not bool(srv.has_pending_loot()):
			break
		var r: Dictionary = srv.try_loot_take(str(iid), -1)
		var sub_v: Variant = r.get("actions", [])
		if typeof(sub_v) == TYPE_ARRAY:
			_apply_server_actions(sub_v)
	# Close loot UI if leftovers remain (manual window still can take anything).
	if srv.has_method("has_pending_loot") and bool(srv.has_pending_loot()) and srv.has_method("try_loot_close"):
		var cr: Dictionary = srv.try_loot_close()
		var ca: Variant = cr.get("actions", [])
		if typeof(ca) == TYPE_ARRAY:
			_apply_server_actions(ca)


func _refresh_player_gear_look(equipment: Array) -> void:
	if player == null or not player.has_method("apply_gear_look"):
		return
	var ch: Dictionary = {}
	if Net.session() != null:
		ch = Net.session().active_character()
	var catalog = null
	var srv = Net.server()
	if srv != null:
		catalog = srv.get("item_catalog")
	player.apply_gear_look(ch, equipment, catalog)


func _apply_camera_zoom() -> void:
	if player == null or not player.has_method("apply_camera_zoom"):
		return
	var gs := GameSettingsScript.get_i()
	var z := 1.0
	if gs != null:
		z = float(gs.camera_zoom)
	player.apply_camera_zoom(z)


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
	## Hostile -> MockServer.try_attack; friendly/script -> try_interact.
	if npc == null:
		return false
	if player != null and player.input_locked:
		return false
	var is_hostile := bool(npc.hostile) if "hostile" in npc else false
	if is_hostile:
		return _try_attack_npc(npc)
	return _try_interact_npc(npc)


func _try_attack_npc(npc) -> bool:
	if npc == null or player == null:
		return false
	_face_toward_cell(_npc_target_cell(npc))
	# Local FX only (face toward player).
	if npc.has_method("try_interact"):
		npc.try_interact(player.cell)
	var srv = Net.server()
	if srv == null or not srv.has_method("try_attack"):
		return true
	var npc_id := str(npc.npc_id) if "npc_id" in npc else ""
	var result: Dictionary = srv.try_attack(npc_id, player.cell.x, player.cell.y)
	if not bool(result.get("ok", false)):
		return true
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_apply_server_actions(actions, npc)
	return true


func _try_interact_npc(npc) -> bool:
	if npc == null or player == null:
		return false
	# Local FX only (face toward player). Do NOT open Chat from interact_text.
	if npc.has_method("try_interact"):
		npc.try_interact(player.cell)
	var srv = Net.server()
	if srv == null or not srv.has_method("try_interact"):
		return true
	var npc_id := str(npc.npc_id) if "npc_id" in npc else ""
	var result: Dictionary = srv.try_interact(npc_id, player.cell.x, player.cell.y)
	if not bool(result.get("ok", false)):
		return true
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_apply_server_actions(actions, npc)
	return true


func _init_aoi_driver() -> void:
	if _aoi == null:
		_aoi = AoiDriver.new()
	_aoi.configure(aoi_view_radius_cells, aoi_radius_cells, aoi_prefetch_radius_cells, aoi_refresh_interval_sec)
	_aoi.reset()
	_refresh_aoi(true)


func _refresh_aoi(force: bool = false) -> void:
	var am: Node = _asset_mgr
	if _aoi == null or am == null:
		return
	if force:
		_aoi.refresh(player, _npcs, am)
	else:
		_aoi.tick(0.0, player, _npcs, am, true)


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
	var bag_id := str(bag.get("id", "")).strip_edges()
	if bag_id.is_empty():
		return
	var items_v: Variant = bag.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		_apply_ground_despawn({"bag_id": bag_id})
		return
	var cell_v: Variant = bag.get("cell", {"x": 0, "y": 0})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var layer := _ensure_ground_layer()
	var marker: Node2D = null
	if _ground_markers.has(bag_id) and is_instance_valid(_ground_markers[bag_id]):
		marker = _ground_markers[bag_id]
	else:
		marker = Node2D.new()
		marker.name = "GroundBag_%s" % bag_id
		marker.set_meta("bag_id", bag_id)
		marker.set_meta("cell", cell)
		layer.add_child(marker)
		# Small footprint: dim square + Sprite2D icon (letter fallback).
		var poly := Polygon2D.new()
		poly.name = "Mark"
		poly.polygon = PackedVector2Array([
			Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)
		])
		poly.color = Color(0.12, 0.10, 0.08, 0.72)
		marker.add_child(poly)
		var spr := Sprite2D.new()
		spr.name = "Icon"
		spr.centered = true
		spr.position = Vector2(0, 0)
		spr.visible = false
		marker.add_child(spr)
		var lab := Label.new()
		lab.name = "Letter"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 14)
		lab.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		lab.position = Vector2(-12, -10)
		lab.size = Vector2(24, 20)
		marker.add_child(lab)
		_ground_markers[bag_id] = marker
	marker.set_meta("bag_id", bag_id)
	marker.set_meta("cell", cell)
	if marker.get_node_or_null("Icon") == null:
		var spr_ensure := Sprite2D.new()
		spr_ensure.name = "Icon"
		spr_ensure.centered = true
		spr_ensure.visible = false
		marker.add_child(spr_ensure)
	if map_field != null and map_field.has_method("cell_to_world"):
		var wp: Vector2 = map_field.cell_to_world(cell)
		# Sit near tile center / feet.
		marker.global_position = Vector2(wp.x, wp.y - float(map_field.tile_size) * 0.35)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var letter := "物"
	var icon_tex: Texture2D = null
	if items.size() > 1:
		letter = "袋"
	else:
		var it0: Dictionary = items[0]
		var nm := str(it0.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = str(it0.get("item_id", "")).strip_edges()
		if not nm.is_empty():
			letter = nm.substr(0, 1)
		icon_tex = _resolve_ground_item_icon(it0)
	var spr2 := marker.get_node_or_null("Icon") as Sprite2D
	var lab2 := marker.get_node_or_null("Letter") as Label
	if icon_tex != null and spr2 != null:
		spr2.texture = icon_tex
		# Fit ~18px footprint over the square.
		var tw := float(icon_tex.get_width())
		var th := float(icon_tex.get_height())
		var sc := 18.0 / maxf(maxf(tw, th), 1.0)
		spr2.scale = Vector2(sc, sc)
		spr2.visible = true
		if lab2 != null:
			lab2.visible = false
			lab2.text = ""
	else:
		if spr2 != null:
			spr2.texture = null
			spr2.visible = false
		if lab2 != null:
			lab2.visible = true
			lab2.text = letter
	marker.set_meta("items", items.duplicate(true))
	marker.set_meta("tip_text", _ground_bag_tip_text(items))
	if _hovered_ground_bag_id == bag_id and hud != null and hud.has_method("show_ground_tip"):
		hud.show_ground_tip(str(marker.get_meta("tip_text", "")), get_viewport().get_mouse_position())



func _resolve_ground_item_icon(it: Dictionary) -> Texture2D:
	var iix := int(it.get("icon_index", -1))
	var iref := str(it.get("icon_ref", "")).strip_edges()
	if iref.is_empty():
		var ic := str(it.get("icon", "")).strip_edges()
		if not ic.is_empty():
			iref = ic if ic.begins_with("content:") else ("content://icon/%s" % ic)
	if iix < 0 or iref.is_empty():
		var iid := str(it.get("item_id", "")).strip_edges()
		if not iid.is_empty():
			var srv = Net.server()
			if srv != null and srv.get("item_catalog") != null:
				var cat = srv.item_catalog
				if iix < 0 and cat.has_method("icon_index_of"):
					iix = int(cat.icon_index_of(iid))
				elif iix < 0 and cat.has_method("get_item"):
					iix = int(cat.get_item(iid).get("icon_index", -1))
				if iref.is_empty() and cat.has_method("icon_ref_of"):
					iref = str(cat.icon_ref_of(iid)).strip_edges()
				elif iref.is_empty() and cat.has_method("get_item"):
					var def: Dictionary = cat.get_item(iid)
					iref = str(def.get("icon_ref", "")).strip_edges()
					if iref.is_empty():
						var ic2 := str(def.get("icon", "")).strip_edges()
						if not ic2.is_empty():
							iref = "content://icon/%s" % ic2
	var am: Node = _asset_mgr
	if am == null:
		return null
	if am.has_method("resolve_slot_icon_texture"):
		return am.resolve_slot_icon_texture(iix, iref)
	if iix >= 0 and am.has_method("load_mv_icon_texture"):
		return am.load_mv_icon_texture(iix)
	return null


func _ground_bag_tip_text(items: Array) -> String:
	## Inventory-like tip: name + id (+ qty); multi-item bags list stacks.
	var lines: PackedStringArray = PackedStringArray()
	if items.size() == 1 and typeof(items[0]) == TYPE_DICTIONARY:
		var it: Dictionary = items[0]
		var iid := str(it.get("item_id", "")).strip_edges()
		var nm := str(it.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = iid if not iid.is_empty() else "物品"
		var q: int = maxi(int(it.get("qty", 1)), 1)
		lines.append(nm)
		if not iid.is_empty():
			lines.append(iid)
		if q > 1:
			lines.append("×%d" % q)
		return "\n".join(lines)
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var iid2 := str(d.get("item_id", "")).strip_edges()
		var nm2 := str(d.get("name", "")).strip_edges()
		if nm2.is_empty():
			nm2 = iid2 if not iid2.is_empty() else "物品"
		var q2: int = maxi(int(d.get("qty", 1)), 1)
		if not iid2.is_empty():
			lines.append("%s\n%s ×%d" % [nm2, iid2, q2])
		else:
			lines.append("%s ×%d" % [nm2, q2])
	if lines.is_empty():
		return "地面物品"
	return "\n".join(lines)


func _tick_ground_hover() -> void:
	if hud == null:
		return
	var mouse_world: Vector2 = get_global_mouse_position()
	var best_id := ""
	var best_d := 22.0
	for bid in _ground_markers.keys():
		var n = _ground_markers[bid]
		if n == null or not is_instance_valid(n):
			continue
		var d: float = n.global_position.distance_to(mouse_world)
		if d < best_d:
			best_d = d
			best_id = str(bid)
	var screen_pos: Vector2 = get_viewport().get_mouse_position()
	if best_id != _hovered_ground_bag_id:
		_hovered_ground_bag_id = best_id
		if best_id.is_empty():
			if hud.has_method("hide_ground_tip"):
				hud.hide_ground_tip()
		else:
			var tip := ""
			var mk = _ground_markers.get(best_id)
			if mk != null and is_instance_valid(mk):
				tip = str(mk.get_meta("tip_text", ""))
			if tip.is_empty():
				tip = "地面物品"
			if hud.has_method("show_ground_tip"):
				hud.show_ground_tip(tip, screen_pos)
	elif not best_id.is_empty():
		if hud.has_method("move_ground_tip"):
			hud.move_ground_tip(screen_pos)


func _find_ground_bag_at(cell: Vector2i) -> String:
	for bid in _ground_markers.keys():
		var n = _ground_markers[bid]
		if n == null or not is_instance_valid(n):
			continue
		var c_v: Variant = n.get_meta("cell", Vector2i(-9999, -9999))
		if typeof(c_v) == TYPE_VECTOR2I and (c_v as Vector2i) == cell:
			return str(bid)
		if typeof(c_v) == TYPE_DICTIONARY:
			if int(c_v.get("x", -9999)) == cell.x and int(c_v.get("y", -9999)) == cell.y:
				return str(bid)
	# Fallback: ask server authority.
	var srv = Net.server()
	if srv != null and srv.has_method("find_ground_bag_at"):
		return str(srv.find_ground_bag_at(cell.x, cell.y))
	return ""


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
	if _selected_remote_id.is_empty():
		return
	if _remote_markers.has(_selected_remote_id):
		var mk = _remote_markers[_selected_remote_id]
		if mk != null and is_instance_valid(mk):
			var body := mk.get_node_or_null("Body") as Polygon2D
			if body != null:
				body.color = Color(0.35, 0.55, 0.95, 0.9)
	_selected_remote_id = ""


func _select_remote(marker: Node2D) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	var pid := str(marker.get_meta("player_id", "")).strip_edges()
	if pid.is_empty():
		return
	_clear_npc_selection()
	if _selected_remote_id != pid:
		_clear_remote_selection()
		_selected_remote_id = pid
		var body := marker.get_node_or_null("Body") as Polygon2D
		if body != null:
			body.color = Color(0.55, 0.75, 1.0, 1.0)
	var display_name := str(marker.get_meta("display_name", pid)).strip_edges()
	if display_name.is_empty():
		display_name = pid
	if hud != null and hud.has_method("show_target"):
		hud.show_target(display_name, 1.0, marker.global_position, false)
	_refresh_remote_nameplates()


func _ensure_player_context_menu() -> PopupMenu:
	if _player_ctx_menu != null and is_instance_valid(_player_ctx_menu):
		return _player_ctx_menu
	# Prefer GameHud-owned menu (CanvasLayer); fall back to a local PopupMenu.
	if hud != null and hud.has_method("ensure_player_context_menu"):
		_player_ctx_menu = hud.ensure_player_context_menu()
		if _player_ctx_menu != null:
			return _player_ctx_menu
	_player_ctx_menu = PopupMenu.new()
	_player_ctx_menu.name = "PlayerContextMenu"
	add_child(_player_ctx_menu)
	if not _player_ctx_menu.id_pressed.is_connected(_on_player_context_id):
		_player_ctx_menu.id_pressed.connect(_on_player_context_id)
	return _player_ctx_menu


func _close_player_context_menu() -> void:
	if hud != null and hud.has_method("close_player_context_menu"):
		hud.close_player_context_menu()
		return
	if _player_ctx_menu != null and is_instance_valid(_player_ctx_menu) and _player_ctx_menu.visible:
		_player_ctx_menu.hide()


func _open_player_context_menu(marker: Node2D, screen_pos: Vector2) -> void:
	if marker == null:
		return
	var pid := str(marker.get_meta("player_id", "")).strip_edges()
	var dname := str(marker.get_meta("display_name", pid)).strip_edges()
	if dname.is_empty():
		dname = pid
	if hud != null and hud.has_method("open_player_context_menu"):
		hud.open_player_context_menu(pid, dname, screen_pos)
		return
	var menu := _ensure_player_context_menu()
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	menu.clear()
	menu.set_meta("target_player_id", pid)
	menu.set_meta("target_display_name", dname)
	menu.add_item(dname, PCM.Action.HEADER)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	var follow_id := ""
	if is_following() and get_follow_id() == pid:
		follow_id = pid
	for d in PCM.item_defs(follow_id):
		menu.add_item(str(d.get("text", "")), int(d.get("id", 0)))
	menu.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	menu.reset_size()
	menu.popup()


func _on_player_context_id(id: int) -> void:
	## Fallback handler when HUD does not own the menu.
	if hud != null and hud.has_method("_on_player_context_id"):
		hud._on_player_context_id(id)
		return
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	var dname := ""
	var pid := ""
	if _player_ctx_menu != null:
		dname = str(_player_ctx_menu.get_meta("target_display_name", ""))
		pid = str(_player_ctx_menu.get_meta("target_player_id", ""))
	match id:
		PCM.Action.VIEW:
			if hud != null and hud.has_method("append_system"):
				hud.append_system("玩家【%s】（%s）" % [dname, pid])
		PCM.Action.INVITE:
			request_party_invite(dname)
		PCM.Action.TRADE:
			request_trade_open(dname)
		PCM.Action.DUEL:
			var duel_key := dname if not dname.is_empty() else pid
			request_duel_challenge(duel_key)
		PCM.Action.WHISPER:
			if hud != null and hud.has_method("prefill_whisper"):
				hud.prefill_whisper(dname)
			elif hud != null and hud.has_method("append_system"):
				hud.append_system("密语：在聊天框输入 /w %s 内容" % dname)
		PCM.Action.ADD_FRIEND:
			var add_key := dname if not dname.is_empty() else pid
			request_friend_add(add_key)
		PCM.Action.INVITE_GUILD:
			var gkey := dname if not dname.is_empty() else pid
			request_guild_invite(gkey)
		PCM.Action.FOLLOW:
			var fid := pid if not pid.is_empty() else dname
			if fid.is_empty():
				if hud != null and hud.has_method("append_system"):
					hud.append_system("无法跟随。")
			elif is_following() and _follow_id == fid:
				stop_follow()
			else:
				start_follow(fid)


func _tick_remote_aoi() -> void:
	## Show/hide fake players by Chebyshev ring (same radii as AssetManager AOI).
	if player == null or _remote_markers.is_empty():
		return
	var pc: Vector2i = player.cell if "cell" in player else Vector2i.ZERO
	var view_r := aoi_view_radius_cells
	var cold_r := aoi_prefetch_radius_cells
	for rid in _remote_markers.keys():
		var mk = _remote_markers[rid]
		if mk == null or not is_instance_valid(mk):
			continue
		var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
		var cell := Vector2i.ZERO
		if typeof(cv) == TYPE_VECTOR2I:
			cell = cv
		elif typeof(cv) == TYPE_DICTIONARY:
			cell = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
		var dist: int = maxi(absi(pc.x - cell.x), absi(pc.y - cell.y))
		# COLD: hide; PREFETCH/AOI/VIEW: show (simple polygon needs no stream).
		var show := dist <= cold_r
		if mk.visible != show:
			mk.visible = show
			_radar_blips_ready = false
		# Dim beyond VIEW
		var body := mk.get_node_or_null("Body") as CanvasItem
		if body != null:
			body.modulate = Color(1, 1, 1, 1) if dist <= view_r else Color(1, 1, 1, 0.55)
		# Nameplate draw distance (selected always shows).
		var lab := mk.get_node_or_null("Name") as Label
		if lab != null:
			var show_p := GameSettingsScript.flag("show_player_names", true)
			var max_d := _nameplate_max_dist()
			var is_sel := str(rid) == _selected_remote_id
			lab.visible = show_p and NameplateUtil.should_show(dist, max_d, is_sel)


func _apply_remote_move(action: Dictionary) -> void:
	ActionApply.apply_remote_move(self, action)
func _ensure_remote_layer() -> Node2D:
	var layer := get_node_or_null("RemotePlayerLayer") as Node2D
	if layer != null and is_instance_valid(layer):
		return layer
	layer = Node2D.new()
	layer.name = "RemotePlayerLayer"
	layer.z_index = 6
	layer.z_as_relative = false
	add_child(layer)
	return layer


func _upsert_remote_marker(data: Dictionary) -> void:
	var pid := str(data.get("id", "")).strip_edges()
	if pid.is_empty():
		return
	var cell_v: Variant = data.get("cell", {"x": 0, "y": 0})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var display_name := str(data.get("name", pid)).strip_edges()
	if display_name.is_empty():
		display_name = pid
	var layer := _ensure_remote_layer()
	var marker: Node2D = null
	if _remote_markers.has(pid) and is_instance_valid(_remote_markers[pid]):
		marker = _remote_markers[pid]
	else:
		marker = Node2D.new()
		marker.name = "Remote_%s" % pid
		layer.add_child(marker)
		var anim := AnimatedSprite2D.new()
		anim.name = "Anim"
		anim.centered = true
		anim.offset = Vector2(0, -32)
		anim.z_index = 5
		marker.add_child(anim)
		var lab := Label.new()
		lab.name = "Name"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 12)
		lab.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 2)
		lab.position = Vector2(-48, -40)
		lab.size = Vector2(96, 18)
		marker.add_child(lab)
		_remote_markers[pid] = marker
	marker.set_meta("player_id", pid)
	marker.set_meta("cell", cell)
	marker.set_meta("display_name", display_name)
	var gender := str(data.get("gender", "female"))
	var look_id := str(data.get("look_id", "1"))
	marker.set_meta("gender", gender)
	marker.set_meta("look_id", look_id)
	marker.set_meta("level", int(data.get("level", 1)))
	_apply_remote_look(marker, gender, look_id, data.get("equipment", []))
	var lab2 := marker.get_node_or_null("Name") as Label
	if lab2 != null:
		lab2.text = display_name
		var show_p := GameSettingsScript.flag("show_player_names", true)
		var pc: Vector2i = player.cell if player != null and "cell" in player else Vector2i.ZERO
		var dist := NameplateUtil.chebyshev(pc, cell)
		var is_sel := pid == _selected_remote_id
		lab2.visible = show_p and NameplateUtil.should_show(dist, _nameplate_max_dist(), is_sel)
	if map_field != null and map_field.has_method("cell_to_world"):
		var wp: Vector2 = map_field.cell_to_world(cell)
		marker.global_position = Vector2(wp.x, wp.y - float(map_field.tile_size) * 0.2)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)


func _clear_remote_markers() -> void:
	for pid in _remote_markers.keys():
		var n = _remote_markers[pid]
		if n != null and is_instance_valid(n):
			n.queue_free()
	_remote_markers.clear()
	_selected_remote_id = ""
	_close_player_context_menu()


func _remove_remote_marker(player_id: String) -> void:
	player_id = player_id.strip_edges()
	if player_id.is_empty():
		return
	if is_following() and get_follow_id() == player_id:
		stop_follow()
	if player_id == _selected_remote_id:
		_selected_remote_id = ""
	if _remote_markers.has(player_id):
		var n = _remote_markers[player_id]
		_remote_markers.erase(player_id)
		if n != null and is_instance_valid(n):
			n.queue_free()



func _upsert_pet_marker(data: Dictionary) -> void:
	if not bool(data.get("active", true)):
		_remove_pet_marker()
		return
	var cell_v: Variant = data.get("cell", {"x": int(data.get("x", 0)), "y": int(data.get("y", 0))})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var display_name := str(data.get("name", "宠物")).strip_edges()
	if display_name.is_empty():
		display_name = "宠物"
	var layer := _ensure_remote_layer()
	var marker: Node2D = _pet_marker
	if marker == null or not is_instance_valid(marker):
		marker = Node2D.new()
		marker.name = "PetCompanion"
		layer.add_child(marker)
		var anim := AnimatedSprite2D.new()
		anim.name = "Anim"
		anim.centered = true
		anim.offset = Vector2(0, -32)
		anim.z_index = 5
		marker.add_child(anim)
		var lab := Label.new()
		lab.name = "Name"
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", 12)
		# Gold nameplate to distinguish from remote players.
		lab.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lab.add_theme_constant_override("outline_size", 2)
		lab.position = Vector2(-48, -40)
		lab.size = Vector2(96, 18)
		marker.add_child(lab)
		_pet_marker = marker
	marker.set_meta("kind", "pet")
	marker.set_meta("pet_id", str(data.get("id", "default")))
	marker.set_meta("cell", cell)
	marker.set_meta("display_name", display_name)
	var look_id := str(data.get("look_id", "1"))
	marker.set_meta("look_id", look_id)
	# Reuse remote look pipeline with a fixed gender (no new art).
	if has_method("_apply_remote_look"):
		_apply_remote_look(marker, "female", look_id, [])
	var lab2 := marker.get_node_or_null("Name") as Label
	if lab2 != null:
		lab2.text = display_name
	if map_field != null and map_field.has_method("cell_to_world"):
		var wp: Vector2 = map_field.cell_to_world(cell)
		marker.global_position = Vector2(wp.x, wp.y - float(map_field.tile_size) * 0.2)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)


func _remove_pet_marker() -> void:
	if _pet_marker != null and is_instance_valid(_pet_marker):
		_pet_marker.queue_free()
	_pet_marker = null


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
	if typeof(result) != TYPE_DICTIONARY:
		return
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	# Prefer map_transfer so loading starts; fold sibling actions for system messages.
	var deferred: Array = []
	var transfer_act: Dictionary = {}
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "map_transfer" and bool(a.get("ok", true)):
			transfer_act = a
		else:
			deferred.append(a)
	if not transfer_act.is_empty():
		var merged: Dictionary = transfer_act.duplicate(true)
		merged["actions"] = deferred
		_on_transfer_requested(merged)
		return
	_apply_server_actions(deferred)


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
	return not _skill_aim_id.is_empty()


func begin_skill_aim(skill_id: String) -> void:
	_skill_aim_id = skill_id.strip_edges()
	_ensure_skill_aim()
	_skill_aim_hover = Vector2i(-9999, -9999)
	if hud != null and hud.has_method("append_system"):
		hud.append_system("选择释放地点（右键取消）")
	_update_skill_aim_preview()


func cancel_skill_aim() -> void:
	_skill_aim_id = ""
	if _skill_aim_overlay != null and _skill_aim_overlay.has_method("clear_preview"):
		_skill_aim_overlay.clear_preview()


func _ensure_skill_aim() -> void:
	if _skill_aim_overlay != null and is_instance_valid(_skill_aim_overlay):
		return
	_skill_aim_overlay = Node2D.new()
	_skill_aim_overlay.set_script(SkillAimOverlay)
	add_child(_skill_aim_overlay)
	if _skill_aim_overlay.has_method("setup"):
		_skill_aim_overlay.setup(map_field)


func _ensure_skill_fx() -> void:
	if _skill_fx != null and is_instance_valid(_skill_fx):
		return
	_skill_fx = Node2D.new()
	_skill_fx.set_script(SkillFxScript)
	add_child(_skill_fx)


func _skill_aim_def() -> Dictionary:
	var srv = Net.server()
	if srv == null or not srv.has_method("skill_def") or _skill_aim_id.is_empty():
		return {}
	return srv.skill_def(_skill_aim_id)


func _update_skill_aim_preview() -> void:
	if _skill_aim_id.is_empty() or player == null or map_field == null:
		return
	_ensure_skill_aim()
	var hover: Vector2i = map_field.world_to_cell(get_global_mouse_position())
	_skill_aim_hover = hover
	var def: Dictionary = _skill_aim_def()
	var radius: int = int(def.get("aoe_radius", 0))
	var shape := str(def.get("aoe_shape", "circle"))
	var rng: int = int(def.get("range", 1))
	var facing: int = 2
	if player.has_method("get_facing"):
		facing = CharsetSheet.dir_from_facing(str(player.get_facing()))
	var engine = null
	var srv = Net.server()
	if srv != null:
		engine = srv.get("combat_engine")
	var cells: Array[Vector2i] = []
	if engine != null and engine.has_method("aoe_cells"):
		for c_v in engine.aoe_cells(hover, radius, shape, facing):
			if typeof(c_v) == TYPE_VECTOR2I:
				cells.append(c_v)
	else:
		for y in range(hover.y - radius, hover.y + radius + 1):
			for x in range(hover.x - radius, hover.x + radius + 1):
				if maxi(absi(x - hover.x), absi(y - hover.y)) <= radius:
					cells.append(Vector2i(x, y))
	var in_range := maxi(absi(hover.x - player.cell.x), absi(hover.y - player.cell.y)) <= rng
	if rng <= 0:
		in_range = true
	_skill_aim_overlay.set_preview(hover, cells, in_range)


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
	if hud == null:
		return false
	if hud.has_method("blocks_world_click") and hud.blocks_world_click(screen_pos):
		return true
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hud.is_ancestor_of(hovered):
		return true
	return false


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
	## Hand off to Loading screen; do not rebuild map in-place or call enter_world.
	_clear_pending_engage()
	_clear_npc_selection()
	if player != null:
		player.input_locked = true
		if player.has_method("clear_move_path"):
			player.clear_move_path()
	_clear_npcs()
	# Client-side: drop old-map ground bags / remotes before scene swap.
	_clear_ground_markers()
	_clear_remote_markers()
	if hud != null:
		if hud.has_method("hide_loot"):
			hud.hide_loot()
		if hud.has_method("hide_ground_tip"):
			hud.hide_ground_tip()
		if hud.has_method("hide_trade"):
			hud.hide_trade()

	var pack_path: String = str(result.get("pack_path", ""))
	var map_id: String = str(result.get("map_id", ""))
	var cell_v: Variant = result.get("cell", {})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var facing: int = int(result.get("facing", 2))
	var message: String = str(result.get("message", ""))

	var spawn: Dictionary = Net.session().spawn_data.duplicate(true)
	spawn["map_id"] = map_id if map_id != "" else pack_path.get_file()
	spawn["pack_path"] = pack_path
	var cid := str(result.get("content_id", "")).strip_edges()
	if cid != "":
		spawn["content_id"] = cid
	var cver := str(result.get("content_version", "")).strip_edges()
	if cver != "":
		spawn["content_version"] = cver
	spawn["cell"] = {"x": cell.x, "y": cell.y}
	spawn["facing"] = facing
	if message != "":
		spawn["transfer_message"] = message
	# Never carry previous map's ground bags / remotes into the new spawn snapshot.
	spawn["ground_bags"] = []
	spawn["remote_players"] = []
	if bool(result.get("bags_cleared", true)):
		spawn["bags_cleared"] = true
	# Prefer fresh journal from transfer result / MockServer (reach objectives).
	var quests_v: Variant = result.get("quests", null)
	if typeof(quests_v) == TYPE_ARRAY:
		spawn["quests"] = quests_v
	else:
		var srv_q = Net.server()
		if srv_q != null and srv_q.has_method("get_quest_list"):
			spawn["quests"] = srv_q.get_quest_list()
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_party"):
		spawn["party"] = srv.snapshot_party()
	if not spawn.has("character") or typeof(spawn.get("character")) != TYPE_DICTIONARY:
		var ch: Dictionary = Net.session().active_character()
		if not ch.is_empty():
			spawn["character"] = ch
	# Apply transfer system messages (bag clear tip) before leaving World.
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY and hud != null:
		for a in actions_v:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if str(a.get("type", "")) == "system_message" and hud.has_method("append_system"):
				var msg := str(a.get("text", "")).strip_edges()
				if not msg.is_empty():
					hud.append_system(msg)
	Net.session().spawn_data = spawn
	Net.session().loading_mode = "transfer"
	Net.session().go_loading()
