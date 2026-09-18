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
	## View-only blips for HUD radar: { world, hostile, kind? }.
	## Includes thin POI dots (quest/inn/smith/gather/fish) from known positions.
	## Cache while NPC cells/hostile/POI flags + remotes unchanged.
	var sig := PackedInt32Array()
	var poi_sample := _radar_poi_sample()
	var poi_markers: Array = RadarPoi.build_markers(poi_sample)
	var poi_ids: Dictionary = {}
	for pm in poi_markers:
		if typeof(pm) != TYPE_DICTIONARY:
			continue
		var pid := str(pm.get("id", "")).strip_edges()
		if pid != "":
			poi_ids[pid] = true
		var cell_p: Vector2i = pm.get("cell", Vector2i.ZERO)
		sig.append(cell_p.x)
		sig.append(cell_p.y)
		sig.append(_radar_kind_code(str(pm.get("kind", ""))))
	for n in _npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid0 := str(n.npc_id) if "npc_id" in n else ""
		if poi_ids.has(nid0):
			continue
		if not _npc_shows_on_radar(n):
			continue
		var c: Vector2i = n.cell if "cell" in n else Vector2i.ZERO
		var hostile_i: int = 1 if ("hostile" in n and bool(n.hostile)) else 0
		sig.append(c.x)
		sig.append(c.y)
		sig.append(hostile_i)
	for rid in _remote_markers.keys():
		var rm = _remote_markers[rid]
		if rm == null or not is_instance_valid(rm):
			continue
		var rc_v: Variant = rm.get_meta("cell", Vector2i.ZERO)
		var rc := rc_v as Vector2i if typeof(rc_v) == TYPE_VECTOR2I else Vector2i(0, 0)
		if typeof(rc_v) == TYPE_DICTIONARY:
			rc = Vector2i(int(rc_v.get("x", 0)), int(rc_v.get("y", 0)))
		sig.append(rc.x)
		sig.append(rc.y)
		sig.append(2)  # friendly remote marker
	if _radar_blips_ready and _radar_blips_sig == sig:
		return _radar_blips_cache
	var out: Array = []
	for pm2 in poi_markers:
		if typeof(pm2) != TYPE_DICTIONARY:
			continue
		var cell2: Vector2i = pm2.get("cell", Vector2i.ZERO)
		var world_pos := Vector2.ZERO
		if map_field != null and map_field.has_method("cell_to_world"):
			world_pos = map_field.cell_to_world(cell2)
		else:
			world_pos = Vector2(float(cell2.x) + 0.5, float(cell2.y) + 0.5) * 48.0
		out.append({
			"world": world_pos,
			"hostile": false,
			"kind": str(pm2.get("kind", "")),
			"id": str(pm2.get("id", "")),
			"name": str(pm2.get("name", "")),
		})
	for n in _npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid1 := str(n.npc_id) if "npc_id" in n else ""
		if poi_ids.has(nid1):
			continue
		if not _npc_shows_on_radar(n):
			continue
		var world_pos2 := Vector2.ZERO
		if map_field != null and map_field.has_method("cell_to_world"):
			world_pos2 = map_field.cell_to_world(n.cell)
		else:
			world_pos2 = n.global_position
		out.append({
			"world": world_pos2,
			"hostile": bool(n.hostile) if "hostile" in n else false,
		})
	for rid2 in _remote_markers.keys():
		var rm2 = _remote_markers[rid2]
		if rm2 == null or not is_instance_valid(rm2) or not rm2.visible:
			continue
		out.append({
			"world": rm2.global_position,
			"hostile": false,
			"remote": true,
		})
	_radar_blips_cache = out
	_radar_blips_sig = sig
	_radar_blips_ready = true
	return out


## Same POI marker list as radar (quest/inn/smith/gather/fish); depleted gather/fish omitted.
func get_radar_poi_markers() -> Array:
	return RadarPoi.build_markers(_radar_poi_sample())


## Richer sample for quest-tracker pathfind: NPC cells + gather/fish yields + warps.
func get_quest_nav_context() -> Dictionary:
	var sample: Dictionary = _radar_poi_sample()
	var npcs: Array = sample.get("npcs", []) if typeof(sample.get("npcs", [])) == TYPE_ARRAY else []
	var gather: Array = sample.get("gather", []) if typeof(sample.get("gather", [])) == TYPE_ARRAY else []
	var fish: Array = sample.get("fish", []) if typeof(sample.get("fish", [])) == TYPE_ARRAY else []
	var srv = Net.server()
	# Attach yields from catalogs so gather/fish item matching works.
	if srv != null and "gather_catalog" in srv and srv.gather_catalog != null:
		var gcat = srv.gather_catalog
		for i in range(gather.size()):
			if typeof(gather[i]) != TYPE_DICTIONARY:
				continue
			var gid := str(gather[i].get("id", "")).strip_edges()
			if gid.is_empty() or not gcat.has_method("get_node"):
				continue
			var def: Dictionary = gcat.get_node(gid)
			if def.is_empty():
				continue
			if def.has("yields"):
				gather[i]["yields"] = def.get("yields", [])
			if str(gather[i].get("name", "")).strip_edges() == "" and def.has("name"):
				gather[i]["name"] = def.get("name")
	if srv != null and "fish_catalog" in srv and srv.fish_catalog != null:
		var fcat = srv.fish_catalog
		for j in range(fish.size()):
			if typeof(fish[j]) != TYPE_DICTIONARY:
				continue
			var fid := str(fish[j].get("id", "")).strip_edges()
			if fid.is_empty() or not fcat.has_method("get_spot"):
				continue
			var fdef: Dictionary = fcat.get_spot(fid)
			if fdef.is_empty():
				continue
			if fdef.has("yields"):
				fish[j]["yields"] = fdef.get("yields", [])
			if str(fish[j].get("name", "")).strip_edges() == "" and fdef.has("name"):
				fish[j]["name"] = fdef.get("name")
	var warps: Array = []
	if srv != null and "map_warps" in srv and typeof(srv.map_warps) == TYPE_ARRAY:
		warps = (srv.map_warps as Array).duplicate(true)
	return {"npcs": npcs, "gather": gather, "fish": fish, "warps": warps}



func _radar_kind_code(kind: String) -> int:
	match kind.strip_edges():
		RadarPoi.KIND_QUEST:
			return 10
		RadarPoi.KIND_INN:
			return 11
		RadarPoi.KIND_SMITH:
			return 12
		RadarPoi.KIND_GATHER:
			return 13
		RadarPoi.KIND_FISH:
			return 14
		RadarPoi.KIND_PIN:
			return 15
		RadarPoi.KIND_BOSS:
			return 16
		_:
			return 0


## Sample for RadarPoi.build_markers from live NPCs + MockServer catalogs/journal.
func _radar_poi_sample() -> Dictionary:
	var npcs_out: Array = []
	var gather_out: Array = []
	var fish_out: Array = []
	var srv = Net.server()
	var qj = null
	if srv != null and "quest_journal" in srv:
		qj = srv.quest_journal
	var gcat = null
	var fcat = null
	if srv != null and "gather_catalog" in srv:
		gcat = srv.gather_catalog
	if srv != null and "fish_catalog" in srv:
		fcat = srv.fish_catalog
	for n in _npcs:
		if n == null or not is_instance_valid(n):
			continue
		var nid := str(n.npc_id) if "npc_id" in n else ""
		if nid.is_empty():
			continue
		var cell: Vector2i = n.cell if "cell" in n else Vector2i.ZERO
		var row: Dictionary = {
			"id": nid,
			"name": str(n.npc_name) if "npc_name" in n else nid,
			"cell": {"x": cell.x, "y": cell.y},
		}
		var inn := bool(n.inn_rest) if "inn_rest" in n else false
		var smith := bool(n.blacksmith) if "blacksmith" in n else false
		if srv != null and "npc_meta" in srv and typeof(srv.npc_meta) == TYPE_DICTIONARY:
			var meta_v: Variant = srv.npc_meta.get(nid, {})
			if typeof(meta_v) == TYPE_DICTIONARY:
				var meta: Dictionary = meta_v
				if bool(meta.get("inn_rest", false)):
					inn = true
				if bool(meta.get("blacksmith", false)) or bool(meta.get("repair", false)):
					smith = true
		row["inn_rest"] = inn
		row["blacksmith"] = smith
		var quest_offer := false
		var quest_turn := false
		if qj != null:
			if qj.has_method("list_offers_for_npc"):
				var offers: Array = qj.list_offers_for_npc(nid)
				quest_offer = not offers.is_empty()
			if qj.has_method("can_turn_in_to"):
				var turns: Array = qj.can_turn_in_to(nid)
				quest_turn = not turns.is_empty()
		row["quest_offer"] = quest_offer
		row["quest_turn_in"] = quest_turn
		var is_gather := false
		var is_fish := false
		if gcat != null and gcat.has_method("has_node") and bool(gcat.has_node(nid)):
			is_gather = true
		if fcat != null and fcat.has_method("has_spot") and bool(fcat.has_spot(nid)):
			is_fish = true
		row["is_gather"] = is_gather
		row["is_fish"] = is_fish
		var is_boss := false
		if srv != null and "npc_meta" in srv and typeof(srv.npc_meta) == TYPE_DICTIONARY:
			var bm_v: Variant = srv.npc_meta.get(nid, {})
			if typeof(bm_v) == TYPE_DICTIONARY and bool(bm_v.get("world_boss", false)):
				is_boss = true
		if srv != null and "npc_spawn_templates" in srv and typeof(srv.npc_spawn_templates) == TYPE_DICTIONARY:
			var bt_v: Variant = srv.npc_spawn_templates.get(nid, {})
			if typeof(bt_v) == TYPE_DICTIONARY:
				var bt: Dictionary = bt_v
				if bool(bt.get("world_boss", false)) or bool(bt.get("is_boss", false)):
					is_boss = true
		if nid == "world_boss_king":
			is_boss = true
		row["world_boss"] = is_boss
		row["is_boss"] = is_boss
		# Depleted gather/fish: omit from NPC row; also push dedicated lists.
		var gather_dep := false
		var fish_dep := false
		if n.has_meta("gather_depleted") and bool(n.get_meta("gather_depleted")):
			gather_dep = true
		if n.has_meta("fish_depleted") and bool(n.get_meta("fish_depleted")):
			fish_dep = true
		if srv != null and srv.has_method("is_gather_depleted") and is_gather:
			gather_dep = gather_dep or bool(srv.is_gather_depleted(nid))
		if srv != null and srv.has_method("is_fish_depleted") and is_fish:
			fish_dep = fish_dep or bool(srv.is_fish_depleted(nid))
		if is_gather:
			gather_out.append({
				"id": nid,
				"name": row["name"],
				"cell": row["cell"],
				"depleted": gather_dep,
			})
			# Avoid double-classifying as npc+gather; gather list owns the marker.
			row["is_gather"] = false
		elif is_fish:
			fish_out.append({
				"id": nid,
				"name": row["name"],
				"cell": row["cell"],
				"depleted": fish_dep,
			})
			row["is_fish"] = false
		npcs_out.append(row)
	var pins_out: Array = []
	if srv != null and srv.has_method("list_map_pins_for_map"):
		var mid := ""
		if "map_pack_id" in srv:
			mid = str(srv.map_pack_id)
		pins_out = srv.list_map_pins_for_map(mid)
	elif srv != null and "_map_pins" in srv:
		for pv in srv._map_pins:
			if typeof(pv) == TYPE_DICTIONARY:
				pins_out.append((pv as Dictionary).duplicate(true))
	return {"npcs": npcs_out, "gather": gather_out, "fish": fish_out, "pins": pins_out}


func _npc_shows_on_radar(n) -> bool:
	# Explicit radar: false force-hides; radar: true force-shows.
	if "radar_opt" in n and n.radar_opt != null:
		return bool(n.radar_opt)
	# Hostile always shows (red).
	if "hostile" in n and bool(n.hostile):
		return true
	# Object-like charset (!...) stays off radar (POI path covers gather/fish).
	var cs := str(n.charset) if "charset" in n else ""
	if cs.begins_with("!"):
		return false
	# Character sheets (non-! charset) show as friendly by default.
	return true


func _find_npc_at(cell: Vector2i):
	for n in _npcs:
		if n == null or not is_instance_valid(n) or not n.visible:
			continue
		if n.has_meta("gather_depleted") and bool(n.get_meta("gather_depleted")):
			continue
		if n.has_method("contains_cell") and n.contains_cell(cell):
			return n
	return null


func _find_remote_at(cell: Vector2i):
	## Pick remote marker on the same cell (Chebyshev 0). Visible markers only.
	for rid in _remote_markers.keys():
		var mk = _remote_markers[rid]
		if mk == null or not is_instance_valid(mk) or not mk.visible:
			continue
		var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
		var mc := Vector2i.ZERO
		if typeof(cv) == TYPE_VECTOR2I:
			mc = cv
		elif typeof(cv) == TYPE_DICTIONARY:
			mc = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
		if mc == cell:
			return mk
	return null


func _find_adjacent_npc(from_cell: Vector2i, prefer_dir: int = 0):
	# Prefer the cell the player faces (8-way).
	if TileId.is_dir(prefer_dir):
		var faced = _find_npc_at(from_cell + TileId.dir_delta(prefer_dir))
		if faced != null:
			return faced
	for n in _npcs:
		if n == null or not is_instance_valid(n) or not n.visible:
			continue
		if n.has_meta("gather_depleted") and bool(n.get_meta("gather_depleted")):
			continue
		if n.has_method("is_adjacent_to") and n.is_adjacent_to(from_cell):
			return n
	return null


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
	## Execute MockServer/GameServer action opcodes. Chat opens only via show_npc_dialogue.
	## A wait action parks the rest of this batch until tick_event_wait elapses.
	if hud == null:
		hud = get_node_or_null("CanvasLayer/GameHud")
	last_applied_action_types = []
	var i := 0
	while i < actions.size():
		var item: Variant = actions[i]
		i += 1
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = item
		var atype := str(action.get("type", ""))
		if atype == "wait":
			var dur := maxf(float(action.get("duration", 0.0)), 0.0)
			if dur > 0.0:
				last_applied_action_types.append("wait")
				_event_wait_left = dur
				_deferred_event_actions = actions.slice(i)
				_deferred_event_npc = npc
				return
			continue
		last_applied_action_types.append(atype)
		match atype:
			"show_npc_dialogue":
				var display_name := str(action.get("npc_name", "")).strip_edges()
				if display_name == "" and npc != null:
					if "npc_name" in npc and str(npc.npc_name).strip_edges() != "":
						display_name = str(npc.npc_name)
				var body := str(action.get("body", ""))
				var options_v: Variant = action.get("options", [])
				var options: Array = options_v if typeof(options_v) == TYPE_ARRAY else []
				if hud != null and hud.has_method("show_npc_dialogue"):
					var face := {
						"id": str(action.get("face", "")).strip_edges(),
						"index": int(action.get("face_index", 0)),
						"pack_dir": str(map_field.pack.pack_dir) if map_field != null and map_field.pack != null else "",
					}
					hud.show_npc_dialogue(display_name, body, options, face)
			"damage":
				_apply_damage_action(action, npc)
			"heal":
				_apply_heal_action(action)
			"miss":
				_apply_miss_action(action)
			"set_stat":
				_apply_set_stat(action)
			"skill_cd":
				_apply_skill_cd(action)
			"status_update":
				_apply_status_update(action)
			"inventory_update":
				_apply_inventory_update(action)
			"equipment_update":
				_apply_equipment_update(action)
			"quest_update":
				_apply_quest_update(action)
			"kill_npc":
				_apply_kill_npc(str(action.get("npc_id", "")), npc)
			"spawn_npc":
				_apply_spawn_npc(action)
			"gather_update":
				_apply_gather_update(action)
				if action.has("gather_level") and hud != null and hud.has_method("apply_gather_update"):
					hud.apply_gather_update(action)
			"fish_update":
				_apply_fish_update(action)
			"player_died":
				_clear_pending_engage()
				stop_follow()
				_auto_attack = false
				if player != null:
					player.input_locked = true
					if player.has_method("clear_move_path"):
						player.clear_move_path()
				if hud != null and hud.has_method("clear_target"):
					hud.clear_target()
				if hud != null and hud.has_method("show_death_dialog"):
					hud.show_death_dialog()
			"respawn":
				_apply_respawn(action)
			"recall":
				_apply_recall(action)
			"player_move":
				_apply_player_move(action)
			"sit":
				_apply_sit(action)
			"npc_move":
				_apply_npc_move(action)
			"event_graphic":
				_apply_event_graphic(action)
			"play_audio":
				_play_pack_audio(str(action.get("channel", "se")), str(action.get("id", "")))
			"npc_reset":
				_apply_npc_reset(action)
			"loot_drop":
				pass  # informational; ground bags + loot UI driven separately
			"ground_spawn":
				_apply_ground_spawn(action)
			"ground_update":
				_apply_ground_update(action)
			"ground_despawn":
				_apply_ground_despawn(action)
			"loot_open":
				_apply_loot_open(action)
			"loot_update":
				_apply_loot_update(action)
			"loot_close":
				_apply_loot_close(action)
			"loot_roll_start":
				if hud != null and hud.has_method("show_loot_roll"):
					hud.show_loot_roll(action)
			"loot_roll_choice":
				if hud != null and hud.has_method("apply_loot_roll_choice"):
					hud.apply_loot_roll_choice(action)
			"loot_roll_resolve":
				if hud != null and hud.has_method("hide_loot_roll"):
					hud.hide_loot_roll(action)
			"exp_gain":
				_apply_exp_gain(action)
			"level_up":
				_apply_level_up(action)
			"open_shop":
				_apply_open_shop(action)
			"map_transfer":
				# Event `transfer` op — same path as warp try_transfer.
				if bool(action.get("ok", true)):
					_on_transfer_requested(action)
			"cast_start":
				var npc_caster := str(action.get("npc_id", "")).strip_edges()
				if npc_caster.is_empty():
					var c0 := str(action.get("caster", "")).strip_edges()
					if c0 != "" and c0 != "player":
						npc_caster = c0
				var ckind := str(action.get("anim", "cast")).strip_edges()
				if ckind.is_empty():
					ckind = "cast"
				if npc_caster.is_empty():
					if hud != null and hud.has_method("apply_cast_start"):
						hud.apply_cast_start(action)
					_apply_skill_anim({
						"actor": "player",
						"kind": ckind,
						"skill_id": str(action.get("skill_id", "")),
					})
				else:
					# NPC cast: combat action / anim only (no player cast HUD).
					_apply_skill_anim({
						"actor": npc_caster,
						"kind": ckind,
						"skill_id": str(action.get("skill_id", "")),
					})
			"cast_update":
				var npc_cu := str(action.get("npc_id", "")).strip_edges()
				if npc_cu.is_empty():
					var c1 := str(action.get("caster", "")).strip_edges()
					if c1 != "" and c1 != "player":
						npc_cu = c1
				if npc_cu.is_empty() and hud != null and hud.has_method("apply_cast_update"):
					hud.apply_cast_update(action)
			"cast_end":
				var npc_ce := str(action.get("npc_id", "")).strip_edges()
				if npc_ce.is_empty():
					var c2 := str(action.get("caster", "")).strip_edges()
					if c2 != "" and c2 != "player":
						npc_ce = c2
				if npc_ce.is_empty() and hud != null and hud.has_method("apply_cast_end"):
					hud.apply_cast_end(action)
			"skill_fx":
				_apply_skill_fx(action)
			"skill_anim":
				_apply_skill_anim(action)
			"skill_book_update":
				_apply_skill_book_update(action)
			"attr_update":
				_apply_attr_update(action)
			"skill_respec":
				_apply_skill_respec(action)
			"party_update":
				if hud != null and hud.has_method("apply_party_update"):
					hud.apply_party_update(action)
			"party_invite":
				if hud != null and hud.has_method("apply_party_invite"):
					hud.apply_party_invite(action)
			"trade_update":
				if hud != null and hud.has_method("apply_trade_update"):
					hud.apply_trade_update(action)
			"duel_update":
				if hud != null and hud.has_method("apply_duel_update"):
					hud.apply_duel_update(action)
			"safe_zone":
				if hud != null and hud.has_method("apply_safe_zone"):
					hud.apply_safe_zone(action)
			"dungeon_update":
				if hud != null and hud.has_method("apply_dungeon_update"):
					hud.apply_dungeon_update(action)
			"rested_update":
				if hud != null and hud.has_method("apply_rested_update"):
					hud.apply_rested_update(action)
				elif hud != null and hud.has_method("apply_combat_stats"):
					hud.apply_combat_stats({
						"rested_exp": int(action.get("rested_exp", 0)),
						"rested_exp_max": int(action.get("rested_exp_max", 0)),
					})
			"craft_update":
				if hud != null and hud.has_method("apply_craft_update"):
					hud.apply_craft_update(action)
			"threat_update":
				_apply_threat_update(action)
			"dps_update":
				if hud != null and hud.has_method("apply_dps_update"):
					hud.apply_dps_update(action)
			"warehouse_update":
				if hud != null and hud.has_method("apply_warehouse_update"):
					hud.apply_warehouse_update(action)
			"friends_update":
				if hud != null and hud.has_method("apply_friends_update"):
					hud.apply_friends_update(action)
			"map_pins_update":
				_radar_blips_ready = false
				if hud != null and hud.has_method("apply_map_pins_update"):
					hud.apply_map_pins_update(action)
				else:
					_sync_map_pins_from_server(action.get("map_pins", {}))
			"guild_update":
				if hud != null and hud.has_method("apply_guild_update"):
					hud.apply_guild_update(action)
			"guild_invite":
				if hud != null and hud.has_method("apply_guild_invite"):
					hud.apply_guild_invite(action)
			"mail_update":
				if hud != null and hud.has_method("apply_mail_update"):
					hud.apply_mail_update(action)
			"auction_update":
				if hud != null and hud.has_method("apply_auction_update"):
					hud.apply_auction_update(action)
			"title_update":
				if hud != null and hud.has_method("apply_title_update"):
					hud.apply_title_update(action)
			"achievement_update":
				if hud != null and hud.has_method("apply_achievement_update"):
					hud.apply_achievement_update(action)
			"shop_buyback":
				if hud != null and hud.has_method("apply_shop_buyback"):
					hud.apply_shop_buyback(action.get("buyback", []))
				if action.has("gold") and hud != null:
					hud._server_gold = int(action.get("gold", hud._server_gold))
			"trade_close":
				if hud != null and hud.has_method("hide_trade"):
					hud.hide_trade()
			"remote_spawn":
				var rp_v: Variant = action.get("player", {})
				if typeof(rp_v) == TYPE_DICTIONARY:
					_upsert_remote_marker(rp_v)
			"remote_despawn":
				_remove_remote_marker(str(action.get("player_id", "")))
			"remote_move":
				_apply_remote_move(action)
			"pet_spawn":
				var pet_s: Variant = action.get("pet", {})
				if typeof(pet_s) != TYPE_DICTIONARY:
					pet_s = {
						"active": true,
						"id": str(action.get("id", "")),
						"name": str(action.get("name", "")),
						"cell": {"x": int(action.get("x", 0)), "y": int(action.get("y", 0))},
						"look_id": str(action.get("look_id", "1")),
						"facing": int(action.get("facing", 2)),
					}
				_upsert_pet_marker(pet_s)
			"pet_despawn":
				_remove_pet_marker()
			"pet_move":
				_apply_pet_move(action)
			"chat_message":
				if hud != null and hud.has_method("apply_chat_message"):
					hud.apply_chat_message(action)
			"emote":
				_apply_emote(action)
			"system_message":
				var msg := str(action.get("text", "")).strip_edges()
				if msg != "" and hud != null and hud.has_method("append_system"):
					hud.append_system(msg)
			"weather":
				_apply_weather_action(action)


func _apply_npc_move(action: Dictionary) -> void:
	var npc_id := str(action.get("npc_id", "")).strip_edges()
	if npc_id.is_empty():
		return
	var target = _find_npc_by_id(npc_id)
	if target == null:
		return
	var nx: int = int(action.get("x", target.cell.x if "cell" in target else 0))
	var ny: int = int(action.get("y", target.cell.y if "cell" in target else 0))
	var facing: int = int(action.get("facing", 2))
	if target.has_method("apply_server_move"):
		target.apply_server_move(nx, ny, facing)
	else:
		if "cell" in target:
			target.cell = Vector2i(nx, ny)
		if target.has_method("face_dir"):
			target.face_dir(facing)
		if target.has_method("_place"):
			target._place()
	# Keep radar cache fresh when cells move.
	_radar_blips_ready = false


func _apply_npc_reset(action: Dictionary) -> void:
	## Evade / return-home: restore client NPC HP bar to full.
	var npc_id := str(action.get("npc_id", "")).strip_edges()
	if npc_id.is_empty():
		return
	var target = _find_npc_by_id(npc_id)
	if target == null:
		return
	var hp: int = int(action.get("hp", 0))
	var hp_max: int = int(action.get("hp_max", 0))
	if "hp" in target:
		target.hp = hp
	if "hp_max" in target:
		target.hp_max = hp_max
	if target.has_method("apply_combat_display"):
		target.apply_combat_display({"hp": hp, "hp_max": hp_max})
	elif target.has_method("_refresh_nameplate"):
		target._refresh_nameplate()
	if npc_id == _selected_npc_id:
		var display_name := npc_id
		if "npc_name" in target and str(target.npc_name).strip_edges() != "":
			display_name = str(target.npc_name)
		var ratio: float = 1.0 if hp_max <= 0 else float(hp) / float(hp_max)
		_push_target_hud(target, display_name, ratio)


func _apply_damage_action(action: Dictionary, npc = null) -> void:
	var target := str(action.get("target", "npc"))
	var amount: int = int(action.get("amount", 0))
	var hp: int = int(action.get("hp", 0))
	var hp_max: int = int(action.get("hp_max", 0))
	var id := str(action.get("id", ""))
	var is_miss := bool(action.get("miss", false)) or str(action.get("result", "")).strip_edges().to_lower() == "miss" or (amount <= 0 and bool(action.get("show_miss", false)))
	var is_crit := bool(action.get("crit", false)) or bool(action.get("critical", false))
	if target == "player":
		if hud != null and hud.has_method("apply_combat_stats"):
			hud.apply_combat_stats({
				"hp": hp,
				"hp_max": hp_max,
				"mp": int(action.get("mp", -1)),
				"mp_max": int(action.get("mp_max", -1)),
			})
		if is_miss:
			_spawn_combat_floater(
				player.global_position if player != null else Vector2.ZERO,
				CombatFloater.text_for("miss"), Color(), "miss", "player", false
			)
			if hud != null:
				if hud.has_method("append_combat_typed"):
					hud.append_combat_typed("miss", CombatLogScript.line_miss())
				elif hud.has_method("append_combat"):
					hud.append_combat(CombatLogScript.line_miss())
				elif hud.has_method("append_system"):
					hud.append_system(CombatLogScript.line_miss())
			return
		if hud != null and amount > 0:
			var line_in := CombatLogScript.line_damage_in(amount, is_crit)
			if hud.has_method("append_combat_typed"):
				hud.append_combat_typed("damage", line_in)
			elif hud.has_method("append_combat"):
				hud.append_combat(line_in)
			elif hud.has_method("append_system"):
				hud.append_system(line_in)
		if amount > 0:
			if player != null and player.has_method("flash_hurt"):
				player.flash_hurt()
			var ppos := player.global_position if player != null else Vector2.ZERO
			_spawn_combat_floater(ppos, CombatFloater.text_for("damage", amount, is_crit), Color(), "damage", "player", is_crit)
			if is_crit:
				_trigger_crit_shake()
		return
	if target == "remote":
		var mk = _remote_markers.get(id, null) if id != "" else null
		var rname := id
		if mk != null and is_instance_valid(mk):
			rname = str(mk.get_meta("display_name", id))
			if is_miss:
				_spawn_combat_floater(mk.global_position, CombatFloater.text_for("miss"), Color(), "miss", "remote:%s" % id, false)
			elif amount > 0:
				_spawn_combat_floater(mk.global_position, CombatFloater.text_for("damage_out", amount, is_crit), Color(), "damage_out", "remote:%s" % id, is_crit)
		if is_miss:
			if hud != null:
				if hud.has_method("append_combat_typed"):
					hud.append_combat_typed("miss", CombatLogScript.line_miss())
				elif hud.has_method("append_combat"):
					hud.append_combat(CombatLogScript.line_miss())
				elif hud.has_method("append_system"):
					hud.append_system(CombatLogScript.line_miss())
			return
		if hud != null and amount > 0:
			var line_r := CombatLogScript.line_damage_out(rname, amount, is_crit)
			if hud.has_method("append_combat_typed"):
				hud.append_combat_typed("damage", line_r)
			elif hud.has_method("append_combat"):
				hud.append_combat(line_r)
			elif hud.has_method("append_system"):
				hud.append_system(line_r)
		if amount > 0 and is_crit:
			_trigger_crit_shake()
		return
	var display_name := "敌人"
	var target_npc = npc
	if target_npc == null or ("npc_id" in target_npc and str(target_npc.npc_id) != id):
		target_npc = _find_npc_by_id(id)
	if target_npc != null:
		if "npc_name" in target_npc and str(target_npc.npc_name).strip_edges() != "":
			display_name = str(target_npc.npc_name)
		if "hp" in target_npc:
			target_npc.hp = hp
		if "hp_max" in target_npc:
			target_npc.hp_max = hp_max
		if id == _selected_npc_id or _selected_npc_id.is_empty():
			# Keep target frame in sync while fighting this mob.
			if _selected_npc_id.is_empty() or id == _selected_npc_id:
				_selected_npc_id = id
				if target_npc.has_method("set_selected"):
					target_npc.set_selected(true)
			var ratio: float = 1.0 if hp_max <= 0 else float(hp) / float(hp_max)
			_push_target_hud(target_npc, display_name, ratio)
	if is_miss:
		var mpos := Vector2.ZERO
		if target_npc != null:
			mpos = target_npc.global_position
		_spawn_combat_floater(mpos, CombatFloater.text_for("miss"), Color(), "miss", "npc:%s" % id, false)
		if hud != null:
			if hud.has_method("append_combat_typed"):
				hud.append_combat_typed("miss", CombatLogScript.line_miss())
			elif hud.has_method("append_combat"):
				hud.append_combat(CombatLogScript.line_miss())
			elif hud.has_method("append_system"):
				hud.append_system(CombatLogScript.line_miss())
		return
	if hud != null and amount > 0:
		var line_n := CombatLogScript.line_damage_out(display_name, amount, is_crit)
		if hud.has_method("append_combat_typed"):
			hud.append_combat_typed("damage", line_n)
		elif hud.has_method("append_combat"):
			hud.append_combat(line_n)
		elif hud.has_method("append_system"):
			hud.append_system(line_n)
	if amount > 0:
		if target_npc != null and target_npc.has_method("flash_hurt"):
			target_npc.flash_hurt()
		var npos := Vector2.ZERO
		if target_npc != null:
			npos = target_npc.global_position
		_spawn_combat_floater(npos, CombatFloater.text_for("damage_out", amount, is_crit), Color(), "damage_out", "npc:%s" % id, is_crit)
		if is_crit:
			_trigger_crit_shake()


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
	## Gray 「未命中」 over the intended target (player / npc / remote).
	var target := str(action.get("target", "npc")).strip_edges()
	var id := str(action.get("id", action.get("npc_id", ""))).strip_edges()
	var pos := Vector2.ZERO
	var key := "default"
	if target == "player":
		pos = player.global_position if player != null else Vector2.ZERO
		key = "player"
	elif target == "remote":
		var mk = _remote_markers.get(id, null) if id != "" else null
		if mk != null and is_instance_valid(mk):
			pos = mk.global_position
		key = "remote:%s" % id
	else:
		var npc = _find_npc_by_id(id) if id != "" else null
		if npc != null and is_instance_valid(npc):
			pos = npc.global_position
		key = "npc:%s" % (id if id != "" else "unknown")
	_spawn_combat_floater(pos, CombatFloater.text_for("miss"), Color(), "miss", key, false)
	if hud != null:
		if hud.has_method("append_combat_typed"):
			hud.append_combat_typed("miss", CombatLogScript.line_miss())
		elif hud.has_method("append_combat"):
			hud.append_combat(CombatLogScript.line_miss())
		elif hud.has_method("append_system"):
			hud.append_system(CombatLogScript.line_miss())


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
	## Floating text bubble above actor for duration_sec, then queue_free.
	var text := str(action.get("text", "")).strip_edges()
	if text.is_empty():
		return
	var actor_id := str(action.get("actor_id", "")).strip_edges()
	var duration := maxf(float(action.get("duration_sec", 2.0)), 0.1)
	var host := _resolve_emote_host(actor_id)
	if host == null or not is_instance_valid(host):
		return
	var old = host.get_node_or_null("EmoteBubble")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var lab := Label.new()
	lab.name = "EmoteBubble"
	lab.text = text
	lab.z_index = 90
	lab.z_as_relative = false
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	lab.add_theme_constant_override("outline_size", 4)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Rough center-above-head offset; Label is Control so parent Node2D works in Godot 4.
	lab.position = Vector2(-40, -72)
	host.add_child(lab)
	var tw := create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(func():
		if is_instance_valid(lab):
			lab.queue_free()
	)


func _apply_heal_action(action: Dictionary) -> void:
	var target := str(action.get("target", "player"))
	if target != "player":
		return
	if hud != null and hud.has_method("apply_combat_stats"):
		hud.apply_combat_stats({
			"hp": int(action.get("hp", -1)),
			"hp_max": int(action.get("hp_max", -1)),
			"mp": int(action.get("mp", -1)),
			"mp_max": int(action.get("mp_max", -1)),
		})
	var amount: int = int(action.get("amount", 0))
	var mp_gain: int = int(action.get("mp_gain", 0))
	if hud != null:
		if amount > 0:
			var line_h := CombatLogScript.line_heal(amount)
			if hud.has_method("append_combat_typed"):
				hud.append_combat_typed("heal", line_h)
			elif hud.has_method("append_combat"):
				hud.append_combat(line_h)
			elif hud.has_method("append_system"):
				hud.append_system(line_h)
		elif mp_gain > 0:
			var line_mp := CombatLogScript.line_mp(mp_gain)
			if hud.has_method("append_combat_typed"):
				hud.append_combat_typed("heal", line_mp)
			elif hud.has_method("append_combat"):
				hud.append_combat(line_mp)
			elif hud.has_method("append_system"):
				hud.append_system(line_mp)
	if amount > 0:
		var ppos := player.global_position if player != null else Vector2.ZERO
		_spawn_combat_floater(ppos, CombatFloater.text_for("heal", amount), Color(), "heal", "player", false)


func _apply_set_stat(action: Dictionary) -> void:
	if str(action.get("target", "player")) == "npc":
		var nid := str(action.get("id", "")).strip_edges()
		var actor = _find_npc_by_id(nid)
		if actor != null and actor.has_method("apply_combat_display"):
			actor.apply_combat_display({
				"hp": int(action.get("hp", -1)),
				"hp_max": int(action.get("hp_max", -1)),
				"mp": int(action.get("mp", -1)),
				"mp_max": int(action.get("mp_max", -1)),
			})
		elif actor != null:
			if "hp" in actor and action.has("hp"):
				actor.hp = int(action.get("hp", 0))
			if "hp_max" in actor and action.has("hp_max"):
				actor.hp_max = int(action.get("hp_max", 0))
			if "mp" in actor and action.has("mp"):
				actor.mp = int(action.get("mp", 0))
			if "mp_max" in actor and action.has("mp_max"):
				actor.mp_max = int(action.get("mp_max", 0))
			if actor.has_method("_refresh_nameplate"):
				actor._refresh_nameplate()
		if nid == _selected_npc_id and actor != null:
			var display_name := nid
			if "npc_name" in actor and str(actor.npc_name).strip_edges() != "":
				display_name = str(actor.npc_name)
			var hp_max: int = int(action.get("hp_max", actor.hp_max if "hp_max" in actor else 0))
			var hp: int = int(action.get("hp", actor.hp if "hp" in actor else 0))
			var ratio: float = 1.0 if hp_max <= 0 else float(hp) / float(hp_max)
			var thr := {}
			if action.has("threat_you"):
				thr = {
					"threat_you": bool(action.get("threat_you", false)),
					"threat_rank": int(action.get("threat_rank", 0)),
					"threat_pct": float(action.get("threat_pct", 0.0)),
					"victim_id": str(action.get("victim_id", "")),
				}
			_push_target_hud(actor, display_name, ratio, thr)
		return
	if str(action.get("target", "player")) != "player":
		return
	if hud != null and hud.has_method("apply_combat_stats"):
		var st := {
			"hp": int(action.get("hp", -1)),
			"hp_max": int(action.get("hp_max", -1)),
			"mp": int(action.get("mp", -1)),
			"mp_max": int(action.get("mp_max", -1)),
		}
		if action.has("level"):
			st["level"] = int(action.get("level", 1))
		if action.has("exp"):
			st["exp"] = int(action.get("exp", 0))
		if action.has("exp_to_next"):
			st["exp_to_next"] = int(action.get("exp_to_next", 0))
		if action.has("atk"):
			st["atk"] = int(action.get("atk", 0))
		if action.has("def"):
			st["def"] = int(action.get("def", 0))
		if action.has("attr_points"):
			st["attr_points"] = int(action.get("attr_points", 0))
		if action.has("attrs"):
			st["attrs"] = action.get("attrs", {})
		if action.has("rested_exp"):
			st["rested_exp"] = int(action.get("rested_exp", 0))
		if action.has("rested_exp_max"):
			st["rested_exp_max"] = int(action.get("rested_exp_max", 0))
		hud.apply_combat_stats(st)


func _apply_skill_cd(action: Dictionary) -> void:
	if hud != null and hud.has_method("note_skill_cooldown"):
		hud.note_skill_cooldown(
			str(action.get("skill_id", "")),
			float(action.get("remaining", 0.0)),
			float(action.get("cooldown", 0.0))
		)


func _apply_status_update(action: Dictionary) -> void:
	var statuses_v: Variant = action.get("statuses", [])
	var statuses: Array = statuses_v if typeof(statuses_v) == TYPE_ARRAY else []
	var target := str(action.get("target", "player"))
	if target == "player":
		if hud != null and hud.has_method("apply_status_chips"):
			hud.apply_status_chips(statuses)
		return
	# Optional: show selected-target statuses when matching selection.
	var nid := str(action.get("id", "")).strip_edges()
	if nid != "" and nid == _selected_npc_id and hud != null and hud.has_method("apply_target_status_chips"):
		hud.apply_target_status_chips(statuses)


func _apply_inventory_update(action: Dictionary) -> void:
	var items_v: Variant = action.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	var gold_v: int = int(action.get("gold", -1))
	if hud != null and hud.has_method("apply_inventory_snapshot"):
		hud.apply_inventory_snapshot(items, gold_v)


func _apply_equipment_update(action: Dictionary) -> void:
	var eq_v: Variant = action.get("equipment", [])
	var eq: Array = eq_v if typeof(eq_v) == TYPE_ARRAY else []
	var bon_v: Variant = action.get("bonuses", {})
	var bons: Dictionary = bon_v if typeof(bon_v) == TYPE_DICTIONARY else {}
	if hud != null and hud.has_method("apply_equipment_snapshot"):
		hud.apply_equipment_snapshot(eq, bons)
	_refresh_player_gear_look(eq)


func _apply_quest_update(action: Dictionary) -> void:
	var quests_v: Variant = action.get("quests", [])
	var quests: Array = quests_v if typeof(quests_v) == TYPE_ARRAY else []
	if hud != null and hud.has_method("apply_quest_snapshot"):
		hud.apply_quest_snapshot(quests)
	if hud != null and hud.has_method("apply_daily_board"):
		hud.apply_daily_board(action)
	_radar_blips_ready = false


func _apply_kill_npc(npc_id: String, npc = null) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id == _selected_npc_id:
		_clear_npc_selection()
	var target = npc
	if target == null or ("npc_id" in target and str(target.npc_id) != npc_id):
		target = _find_npc_by_id(npc_id)
	if target == null:
		return
	var kill_name := "敌人"
	if "npc_name" in target and str(target.npc_name).strip_edges() != "":
		kill_name = str(target.npc_name)
	if hud != null:
		var line_k := CombatLogScript.line_kill(kill_name)
		if hud.has_method("append_combat_typed"):
			hud.append_combat_typed("kill", line_k)
		elif hud.has_method("append_combat"):
			hud.append_combat(line_k)
		elif hud.has_method("append_system"):
			hud.append_system(line_k)
	var cell: Vector2i = target.cell if "cell" in target else Vector2i.ZERO
	# Clear occupancy so the cell is walkable again.
	var srv = Net.server()
	if srv != null and srv.map_collision != null and srv.map_collision.has_method("set_extra_blocked"):
		srv.map_collision.set_extra_blocked(cell.x, cell.y, false)
	_npcs.erase(target)
	var am_kill: Node = _asset_mgr
	if am_kill != null and am_kill.has_method("clear_actor_refs") and npc_id != "":
		am_kill.clear_actor_refs(npc_id)
		if am_kill.has_method("note_actor_ring"):
			am_kill.note_actor_ring(npc_id, "COLD")
	if is_instance_valid(target):
		target.queue_free()
	if hud != null and hud.has_method("clear_target"):
		hud.clear_target()



func _apply_spawn_npc(action: Dictionary) -> void:
	## Server timed respawn / pack-like recreate. `action.npc` mirrors npcs.json entry.
	var npc_v: Variant = action.get("npc", action)
	if typeof(npc_v) != TYPE_DICTIONARY:
		return
	var data: Dictionary = npc_v
	var nid := str(data.get("id", "")).strip_edges()
	if nid.is_empty():
		return
	# Replace stale client actor if any.
	var existing = _find_npc_by_id(nid)
	if existing != null:
		_apply_kill_npc(nid, existing)
	var layer := _ensure_npc_layer()
	var pack_dir := ""
	if map_field != null and map_field.pack != null:
		pack_dir = str(map_field.pack.pack_dir)
	var actor = NpcActor.new()
	layer.add_child(actor)
	actor.setup(data, map_field, pack_dir)
	_npcs.append(actor)
	_refresh_aoi(true)
	# Occupancy: server already blocked; ensure client-shared collision matches.
	var cell_v: Variant = data.get("cell", {})
	if typeof(cell_v) == TYPE_DICTIONARY:
		var cd: Dictionary = cell_v
		var cx: int = int(cd.get("x", 0))
		var cy: int = int(cd.get("y", 0))
		var srv = Net.server()
		if srv != null and srv.map_collision != null and srv.map_collision.has_method("set_extra_blocked"):
			srv.map_collision.set_extra_blocked(cx, cy, true)
	_radar_blips_ready = false


func _apply_gather_update(action: Dictionary) -> void:
	## Hide depleted gather props; restore on respawn. No new art.
	var nid := str(action.get("node_id", "")).strip_edges()
	if nid.is_empty():
		return
	var actor = _find_npc_by_id(nid)
	if actor == null:
		return
	var depleted := bool(action.get("depleted", false))
	actor.visible = not depleted
	if depleted:
		actor.set_meta("gather_depleted", true)
		if "npc_name" in actor:
			var base := str(action.get("name", actor.npc_name)).strip_edges()
			if base.is_empty():
				base = nid
			actor.npc_name = "%s（已采空）" % base
			if actor.has_method("_refresh_nameplate"):
				actor._refresh_nameplate()
	else:
		if actor.has_meta("gather_depleted"):
			actor.remove_meta("gather_depleted")
		var nm := str(action.get("name", "")).strip_edges()
		if nm != "" and "npc_name" in actor:
			actor.npc_name = nm
		if actor.has_method("_refresh_nameplate"):
			actor._refresh_nameplate()
	_radar_blips_ready = false


func _apply_fish_update(action: Dictionary) -> void:
	## Hide depleted fishing spots; restore on respawn. No new art.
	var sid := str(action.get("spot_id", action.get("node_id", ""))).strip_edges()
	if sid.is_empty():
		return
	var actor = _find_npc_by_id(sid)
	if actor == null:
		return
	var depleted := bool(action.get("depleted", false))
	actor.visible = not depleted
	if depleted:
		actor.set_meta("fish_depleted", true)
		if "npc_name" in actor:
			var base := str(action.get("name", actor.npc_name)).strip_edges()
			if base.is_empty():
				base = sid
			actor.npc_name = "%s（暂无鱼）" % base
			if actor.has_method("_refresh_nameplate"):
				actor._refresh_nameplate()
	else:
		if actor.has_meta("fish_depleted"):
			actor.remove_meta("fish_depleted")
		var nm := str(action.get("name", "")).strip_edges()
		if nm != "" and "npc_name" in actor:
			actor.npc_name = nm
		if actor.has_method("_refresh_nameplate"):
			actor._refresh_nameplate()
	_radar_blips_ready = false


func _find_npc_by_id(npc_id: String):
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return null
	for n in _npcs:
		if n != null and is_instance_valid(n) and "npc_id" in n and str(n.npc_id) == npc_id:
			return n
	return null


func _sync_npc_combat_display() -> void:
	## Pull MockServer combat_stats onto actors for nameplates (render-only).
	var srv = Net.server()
	if srv == null or srv.get("combat_stats") == null:
		return
	var stats = srv.combat_stats
	if stats == null or not ("npcs" in stats):
		return
	for actor in _npcs:
		if actor == null or not is_instance_valid(actor):
			continue
		var nid := str(actor.npc_id) if "npc_id" in actor else ""
		if nid.is_empty() or not stats.npcs.has(nid):
			continue
		var st_v: Variant = stats.npcs[nid]
		if typeof(st_v) != TYPE_DICTIONARY:
			continue
		if actor.has_method("apply_combat_display"):
			actor.apply_combat_display(st_v)


func _clear_npc_selection() -> void:
	if _selected_npc_id.is_empty():
		return
	var prev = _find_npc_by_id(_selected_npc_id)
	if prev != null and prev.has_method("set_selected"):
		prev.set_selected(false)
	_selected_npc_id = ""


func clear_target_selection() -> void:
	## HUD × / explicit clear: drop foot ring + top target frame.
	_clear_npc_selection()
	_clear_remote_selection()
	if hud != null and hud.has_method("clear_target"):
		hud.clear_target()


func _npc_shows_target_hp(npc) -> bool:
	## Only monsters get the red HP bar in the top target frame.
	if npc == null:
		return false
	if "kind" in npc and str(npc.kind) == "monster":
		return true
	if "hostile" in npc and bool(npc.hostile):
		return true
	return false


func _push_target_hud(npc, display_name: String, ratio: float, threat_snap: Dictionary = {}) -> void:
	if hud == null or not hud.has_method("show_target"):
		return
	var world_pos: Variant = npc.global_position if npc else null
	var mp_ratio := -1.0
	if npc != null and "mp_max" in npc and int(npc.mp_max) > 0:
		mp_ratio = clampf(float(npc.mp) / float(maxi(int(npc.mp_max), 1)), 0.0, 1.0)
	var show_threat := _npc_shows_target_hp(npc)  # hostile / monster only
	var threat_you := false
	if show_threat:
		if threat_snap.is_empty():
			threat_snap = _fetch_threat_snapshot(str(npc.npc_id) if npc != null and "npc_id" in npc else "")
		threat_you = bool(threat_snap.get("threat_you", false))
	hud.show_target(display_name, ratio, world_pos, _npc_shows_target_hp(npc), mp_ratio, show_threat, threat_you)


func _fetch_threat_snapshot(npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return {}
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_threat"):
		var s: Variant = srv.snapshot_threat(npc_id)
		if typeof(s) == TYPE_DICTIONARY:
			return s
	return {}


func _apply_threat_update(action: Dictionary) -> void:
	var nid := str(action.get("npc_id", action.get("id", ""))).strip_edges()
	if nid.is_empty():
		return
	# Only refresh HUD when this is the selected target.
	if nid != _selected_npc_id:
		return
	var npc = _find_npc_by_id(nid)
	if npc == null or not _npc_shows_target_hp(npc):
		return
	if hud != null and hud.has_method("apply_threat_chip"):
		hud.apply_threat_chip(true, bool(action.get("threat_you", false)))


func _select_npc(npc) -> void:
	if npc == null:
		clear_target_selection()
		return
	var nid := str(npc.npc_id).strip_edges() if "npc_id" in npc else ""
	if nid.is_empty():
		return
	_clear_remote_selection()
	if _selected_npc_id != nid:
		_clear_npc_selection()
		_selected_npc_id = nid
		if npc.has_method("set_selected"):
			npc.set_selected(true)
	# Refresh HUD target frame from actor display fields.
	var display_name := nid
	if "npc_name" in npc and str(npc.npc_name).strip_edges() != "":
		display_name = str(npc.npc_name)
	var ratio := 1.0
	if "hp_max" in npc and int(npc.hp_max) > 0:
		ratio = clampf(float(npc.hp) / float(npc.hp_max), 0.0, 1.0)
	_push_target_hud(npc, display_name, ratio)
	# Shell: selecting a target while grouped marks party shared assist target.
	request_party_set_target(nid, display_name)


func _clear_pending_engage() -> void:
	_pending_engage_npc_id = ""
	_pending_skill_id = ""
	_pending_skill_range = 1


func _set_pending_engage(npc, skill_id: String = "", range_cells: int = 1) -> void:
	if npc == null or not ("npc_id" in npc):
		_clear_pending_engage()
		return
	_pending_engage_npc_id = str(npc.npc_id).strip_edges()
	_pending_skill_id = skill_id.strip_edges()
	_pending_skill_range = maxi(range_cells, 1)


func _player_beside_npc(npc, pcell: Vector2i) -> bool:
	if npc == null:
		return false
	if npc.has_method("is_adjacent_to") and npc.is_adjacent_to(pcell):
		return true
	if npc.has_method("contains_cell") and npc.contains_cell(pcell):
		return true
	return false


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _nameplate_max_dist() -> int:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return 12
	return NameplateUtil.clamp_distance(int(gs.nameplate_distance))


func _refresh_npc_nameplates() -> void:
	for npc in _npcs:
		if npc != null and is_instance_valid(npc) and npc.has_method("_refresh_nameplate"):
			npc._refresh_nameplate()


func _refresh_remote_nameplates() -> void:
	var show_p := GameSettingsScript.flag("show_player_names", true)
	var max_d := _nameplate_max_dist()
	var pc: Vector2i = player.cell if player != null and "cell" in player else Vector2i.ZERO
	for rid in _remote_markers.keys():
		var mk = _remote_markers[rid]
		if mk == null or not is_instance_valid(mk):
			continue
		var lab := mk.get_node_or_null("Name") as Label
		if lab == null:
			continue
		var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
		var cell := Vector2i.ZERO
		if typeof(cv) == TYPE_VECTOR2I:
			cell = cv
		elif typeof(cv) == TYPE_DICTIONARY:
			cell = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
		var dist := NameplateUtil.chebyshev(pc, cell)
		var is_sel := str(rid) == _selected_remote_id
		lab.visible = show_p and NameplateUtil.should_show(dist, max_d, is_sel)


func _tick_nameplate_distance(delta: float) -> void:
	# Refresh NPC plates ~4 Hz; remotes update every frame in _tick_remote_aoi.
	_nameplate_tick_acc += delta
	if _nameplate_tick_acc < 0.25:
		return
	_nameplate_tick_acc = 0.0
	_refresh_npc_nameplates()


## Stand at the far edge of `range_cells` from target, stepping from `from`.
func _approach_cell(from: Vector2i, target: Vector2i, range_cells: int) -> Vector2i:
	range_cells = maxi(range_cells, 1)
	var dist: int = _cheb(from, target)
	if dist <= range_cells:
		return from
	var steps: int = dist - range_cells
	var x: int = from.x
	var y: int = from.y
	for i in range(steps):
		var tdx: int = target.x - x
		var tdy: int = target.y - y
		if tdx == 0 and tdy == 0:
			break
		if tdx > 0:
			x += 1
		elif tdx < 0:
			x -= 1
		if tdy > 0:
			y += 1
		elif tdy < 0:
			y -= 1
	return Vector2i(x, y)


func _face_toward_cell(to: Vector2i) -> void:
	if player == null or not player.has_method("set_facing_dir"):
		return
	var pcell: Vector2i = player.cell
	var d: int = TileId.dir_from_vec(Vector2(float(to.x - pcell.x), float(to.y - pcell.y)))
	if d != 0:
		player.set_facing_dir(d)


func _npc_target_cell(npc) -> Vector2i:
	if npc != null and "cell" in npc:
		return npc.cell
	return Vector2i(-9999, -9999)


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
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_invite_respond"):
		return
	var result: Dictionary = srv.try_party_invite_respond(invite_id, accept)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_respawn(where: String = "town") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_respawn"):
		return
	var result: Dictionary = srv.try_respawn(where)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_recall() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_recall"):
		return
	var result: Dictionary = srv.try_recall()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_sit(on: Variant = null) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_sit"):
		return
	var want := true
	if typeof(on) == TYPE_BOOL:
		want = bool(on)
	elif "sitting" in srv:
		want = not bool(srv.sitting)
	if want:
		stop_follow()
		_auto_attack = false
		_clear_pending_engage()
	var result: Dictionary = srv.try_sit(want)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_map_move(cell: Vector2i, label: String = "") -> void:
	if player == null or player.input_locked:
		return
	if not player.has_method("click_move_to"):
		return
	stop_follow()
	_auto_attack = false
	_clear_pending_engage()
	var ok: bool = bool(player.click_move_to(cell))
	if hud != null and hud.has_method("append_system"):
		var tag := str(label).strip_edges()
		if tag.is_empty():
			tag = _map_poi_label_at(cell)
		if ok:
			if tag != "":
				hud.append_system("前往：%s" % tag)
			else:
				hud.append_system("前往 (%d, %d)" % [cell.x, cell.y])
		else:
			if tag != "":
				hud.append_system("无法到达：%s" % tag)
			else:
				hud.append_system("无法到达 (%d, %d)" % [cell.x, cell.y])


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
	_light_presets = _read_preset_file("res://data/map/light_presets.json")
	_sound_presets = _read_preset_file("res://data/map/sound_presets.json")
	_pin_hud_canvas()
	# Day/night tints World canvas items (map, actors). Do not use CanvasModulate —
	# it multiplies every canvas in the viewport, including the HUD.
	if _bgs_player == null:
		_bgs_player = AudioStreamPlayer.new()
		_bgs_player.name = "MapBgs"
		_bgs_player.bus = "Ambient"
		add_child(_bgs_player)
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "MapBgm"
		_bgm_player.bus = "BGM"
		add_child(_bgm_player)
	if _se_player == null:
		_se_player = AudioStreamPlayer.new()
		_se_player.name = "MapSe"
		_se_player.volume_db = -4.0
		_se_player.bus = "SFX"
		add_child(_se_player)
	if _foot_player == null:
		_foot_player = AudioStreamPlayer.new()
		_foot_player.name = "Footstep"
		_foot_player.volume_db = -8.0
		_foot_player.bus = "SFX"
		add_child(_foot_player)


func _read_preset_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	if typeof(d.get("presets")) == TYPE_DICTIONARY:
		return d["presets"]
	return d


func _sync_map_observer() -> void:
	if player == null or map_field == null:
		return
	var cell: Vector2i = player.cell if "cell" in player else Vector2i.ZERO
	var facing := 2
	if player.has_method("get_facing"):
		facing = int(CharsetSheet.dir_from_facing(str(player.get_facing())))
	if map_field.has_method("set_observer"):
		map_field.set_observer(cell, facing)
	_apply_cell_settings(cell)


func _apply_cell_settings(cell: Vector2i) -> void:
	if map_field == null or map_field.collision == null:
		return
	var col = map_field.collision
	if not col.has_method("settings_at"):
		return
	var packed: int = int(col.settings_at(cell.x, cell.y))
	var light_id: int = packed & 0xff
	var sound_id: int = (packed >> 8) & 0xff
	_last_foot_kind = (packed >> 16) & 0xff
	if packed == 0 and map_field != null and map_field.pack != null and "light_preset" in map_field.pack:
		light_id = int(map_field.pack.light_preset)
	if light_id != _last_light_preset:
		_last_light_preset = light_id
		_apply_light_preset(light_id)
	if sound_id != _last_sound_preset:
		_last_sound_preset = sound_id
		_apply_sound_preset(sound_id)


func _apply_light_preset(id: int) -> void:
	_last_light_preset = id
	_apply_atmosphere()


func _apply_weather_action(action: Dictionary) -> void:
	_weather_kind = str(action.get("kind", "clear"))
	_weather_intensity = clampf(float(action.get("intensity", 0.0)), 0.0, 1.0)
	_apply_atmosphere()


func _pull_server_weather() -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("get_weather"):
		var snap: Dictionary = srv.get_weather()
		_weather_kind = str(snap.get("kind", "clear"))
		_weather_intensity = clampf(float(snap.get("intensity", 0.0)), 0.0, 1.0)
	_apply_atmosphere()


func _pin_hud_canvas() -> void:
	var cl := get_node_or_null("CanvasLayer") as CanvasLayer
	if cl:
		cl.layer = Weather.CANVAS_HUD


func _apply_world_light(c: Color) -> void:
	## Tint map + actors only. HUD lives on a higher CanvasLayer and must stay readable.
	modulate = Color(c.r, c.g, c.b, 1.0)
	if _map_modulate != null and is_instance_valid(_map_modulate):
		_map_modulate.color = Color(1, 1, 1, 1)


func _apply_atmosphere() -> void:
	var light_id: int = _last_light_preset if _last_light_preset >= 0 else 0
	if map_field != null and map_field.has_method("set_atmosphere"):
		var atm: Dictionary = map_field.set_atmosphere(light_id, _weather_kind, _weather_intensity)
		if map_field.has_method("weather_display_modulate"):
			_apply_world_light(map_field.weather_display_modulate())
		else:
			_apply_world_light(atm.get("modulate", MapExt.light_modulate(light_id)))
		var vis := str(atm.get("kind", "clear"))
		if vis != _last_weather_kind:
			_last_weather_kind = vis
			if vis != "clear" and hud != null and hud.has_method("append_system"):
				hud.append_system("天气：%s" % str(atm.get("label", vis)))
		return
	_apply_world_light(MapExt.light_modulate(light_id))


func _tick_weather_display() -> void:
	if map_field != null and map_field.has_method("weather_display_modulate"):
		_apply_world_light(map_field.weather_display_modulate())


func _apply_sound_preset(id: int) -> void:
	if _bgs_player == null:
		return
	if id <= 0:
		_bgs_player.stop()
		_bgs_player.stream = null
		return
	var p: Dictionary = _sound_presets.get(str(id), _sound_presets.get(id, {}))
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
	_bgs_player.stream = stream
	_bgs_player.volume_db = float(p.get("volume_db", 0.0))
	_bgs_player.play()


func _apply_event_graphic(action: Dictionary) -> void:
	var eid := str(action.get("event_id", "")).strip_edges()
	if eid == "":
		return
	var npc = _find_npc_by_id(eid)
	if npc == null or not npc.has_method("apply_graphic"):
		return
	var pack_dir := ""
	if map_field != null and map_field.pack != null:
		pack_dir = str(map_field.pack.pack_dir)
	npc.apply_graphic(
		str(action.get("charset", "")),
		int(action.get("index", 0)),
		int(action.get("direction", 2)),
		pack_dir
	)


func _play_map_bgm() -> void:
	_load_map_presets()
	var id := ""
	if map_field != null and map_field.pack != null and "bgm" in map_field.pack:
		id = str(map_field.pack.bgm).strip_edges()
	if id == "":
		if _bgm_player != null:
			_bgm_player.stop()
			_bgm_player.stream = null
		return
	_play_pack_audio("bgm", id)


func _play_pack_audio(channel: String, id: String) -> void:
	id = id.strip_edges()
	channel = channel.strip_edges().to_lower()
	if id == "":
		return
	_load_map_presets()
	var stream: AudioStream = _load_pack_audio_stream(channel, id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _se_player
	match channel:
		"bgm":
			player = _bgm_player
		"bgs":
			player = _bgs_player
		"me":
			player = _se_player
		_:
			player = _se_player
	if player == null:
		return
	player.stream = stream
	if channel == "bgm" or channel == "bgs":
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.play()


func _load_pack_audio_stream(channel: String, id: String) -> AudioStream:
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
	if map_field != null and map_field.pack != null:
		roots.append("%s/assets/%s" % [str(map_field.pack.pack_dir), folder])
		roots.append("%s/assets/audio" % str(map_field.pack.pack_dir))
	var am: Node = _asset_mgr if is_inside_tree() else null
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
				var st: AudioStream = _audio_from_file(use_p, ext)
				if st != null:
					return st
	return null


func _audio_from_file(path: String, ext: String) -> AudioStream:
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is AudioStream:
			return res
	return null


func _play_footstep() -> void:
	if _foot_player == null:
		return
	_foot_player.stream = MapSfx.footstep(_last_foot_kind)
	_foot_player.pitch_scale = randf_range(0.92, 1.08)
	_foot_player.play()



func _apply_player_move(action: Dictionary) -> void:
	var cell := Vector2i(int(action.get("x", -9999)), int(action.get("y", -9999)))
	var cell_v: Variant = action.get("cell", {})
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", cell.x)), int(cell_v.get("y", cell.y)))
	elif typeof(cell_v) == TYPE_VECTOR2I:
		cell = cell_v
	if cell.x <= -9990 or player == null:
		return
	if player.has_method("clear_move_path"):
		player.clear_move_path()
	var facing := int(action.get("facing", -1))
	if player.has_method("place_at_cell"):
		# place_at_cell signatures vary; prefer cell-only then set facing.
		player.place_at_cell(cell, map_field)
	else:
		player.cell = cell
	if facing >= 0 and "facing" in player:
		player.facing = facing
	if player.has_method("snap_camera"):
		player.snap_camera()
	_sync_map_observer()


func _apply_recall(action: Dictionary) -> void:
	var cell_v: Variant = action.get("cell", {})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	elif typeof(cell_v) == TYPE_VECTOR2I:
		cell = cell_v
	if player == null:
		return
	_clear_pending_engage()
	stop_follow()
	_auto_attack = false
	if player.has_method("set_sitting"):
		player.set_sitting(false)
	if player.has_method("clear_move_path"):
		player.clear_move_path()
	if player.has_method("place_at_cell"):
		player.place_at_cell(cell, map_field)
	else:
		player.cell = cell
	if player.has_method("snap_camera"):
		player.snap_camera()
	_sync_map_observer()


func _apply_sit(action: Dictionary) -> void:
	var on := bool(action.get("on", false))
	if player != null and player.has_method("set_sitting"):
		player.set_sitting(on)


func _apply_respawn(action: Dictionary) -> void:
	_clear_pending_engage()
	var cell_v: Variant = action.get("cell", {})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	if player != null:
		if player.has_method("set_sitting"):
			player.set_sitting(false)
		if player.has_method("clear_move_path"):
			player.clear_move_path()
		if player.has_method("place_at_cell"):
			player.place_at_cell(cell, map_field)
		else:
			player.cell = cell
		if player.has_method("snap_camera"):
			player.snap_camera()
		player.input_locked = true
	if hud != null and hud.has_method("hide_death_dialog"):
		hud.hide_death_dialog()
	_respawn_lock_left = float(action.get("input_lock_sec", 1.2))
	if hud != null and hud.has_method("apply_combat_stats"):
		hud.apply_combat_stats({
			"hp": int(action.get("hp", -1)),
			"hp_max": int(action.get("hp_max", -1)),
			"mp": int(action.get("mp", -1)),
			"mp_max": int(action.get("mp_max", -1)),
		})
	if hud != null and hud.has_method("clear_target"):
		hud.clear_target()


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
	if hud != null and hud.has_method("apply_combat_stats"):
		var st := {
			"level": int(action.get("level", -1)),
			"exp": int(action.get("exp", -1)),
			"exp_to_next": int(action.get("exp_to_next", -1)),
		}
		if action.has("rested_exp"):
			st["rested_exp"] = int(action.get("rested_exp", 0))
		if action.has("rested_exp_max"):
			st["rested_exp_max"] = int(action.get("rested_exp_max", 0))
		hud.apply_combat_stats(st)
	# Thin 「经验 +N」 float (coalesces if many gains same frame via HUD).
	var amt: int = int(action.get("amount", 0))
	if amt > 0 and hud != null and hud.has_method("show_exp_gain_float"):
		hud.show_exp_gain_float(amt)


func _apply_level_up(action: Dictionary) -> void:
	var combat_v: Variant = action.get("combat", {})
	var combat: Dictionary = combat_v if typeof(combat_v) == TYPE_DICTIONARY else {}
	var lv: int = int(action.get("level", combat.get("level", 1)))
	var sp_gained: int = int(action.get("skill_points_gained", action.get("sp_gained", 0)))
	if hud != null:
		if hud.has_method("apply_level_up"):
			hud.apply_level_up(lv, combat, sp_gained)
		elif hud.has_method("show_level_up_toast"):
			hud.show_level_up_toast(lv, sp_gained)
			if hud.has_method("apply_combat_stats"):
				if combat.is_empty():
					hud.apply_combat_stats({"level": lv})
				else:
					hud.apply_combat_stats(combat)
		elif hud.has_method("apply_combat_stats"):
			if combat.is_empty():
				hud.apply_combat_stats({"level": lv})
			else:
				hud.apply_combat_stats(combat)


func request_event_choice(option_id: String = "", option_index: int = -1) -> void:
	## Dialogue option → quest_* / shop_open / MV event choice.
	var srv = Net.server()
	if srv == null:
		return
	var result: Dictionary = {}
	if srv.has_method("try_dialogue_choice"):
		result = srv.try_dialogue_choice(option_id, option_index)
	elif srv.has_method("try_event_choice"):
		result = srv.try_event_choice(option_id, option_index)
	else:
		return
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v, null)


func _apply_open_shop(action: Dictionary) -> void:
	if hud != null and hud.has_method("show_shop"):
		var listings_v: Variant = action.get("listings", [])
		var listings: Array = listings_v if typeof(listings_v) == TYPE_ARRAY else []
		hud.show_shop(
			str(action.get("shop_id", "")),
			str(action.get("title", "商店")),
			listings,
			int(action.get("gold", 0)),
			int(action.get("vendor_rep", 0))
		)
		if hud.has_method("apply_shop_buyback"):
			var bb: Variant = action.get("buyback", [])
			if typeof(bb) == TYPE_ARRAY:
				hud.apply_shop_buyback(bb)


func request_shop_buy(shop_id: String, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_buy"):
		return
	var result: Dictionary = srv.try_shop_buy(shop_id, item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_shop_buyback(index: int, qty: int = -1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_buyback"):
		return
	var result: Dictionary = srv.try_shop_buyback(index, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_shop_close() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_close"):
		return
	var result: Dictionary = srv.try_shop_close()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_inventory_split(item_id: String, qty: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_inventory_split"):
		return
	var result: Dictionary = srv.try_inventory_split(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_inventory_sort() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_inventory_sort"):
		return
	var result: Dictionary = srv.try_inventory_sort()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_inventory_lock(item_id: String, on: bool) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_inventory_lock"):
		return
	var result: Dictionary = srv.try_inventory_lock(item_id, on)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_shop_sell(item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_sell"):
		return
	var result: Dictionary = srv.try_shop_sell(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_shop_sell_junk() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_sell_junk"):
		return
	var result: Dictionary = srv.try_shop_sell_junk()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func _apply_ground_spawn(action: Dictionary) -> void:
	var bag_v: Variant = action.get("bag", {})
	if typeof(bag_v) == TYPE_DICTIONARY:
		_upsert_ground_marker(bag_v)


func _apply_ground_update(action: Dictionary) -> void:
	var bag_v: Variant = action.get("bag", {})
	if typeof(bag_v) == TYPE_DICTIONARY:
		_upsert_ground_marker(bag_v)


func _apply_ground_despawn(action: Dictionary) -> void:
	var bag_id := str(action.get("bag_id", "")).strip_edges()
	if bag_id.is_empty():
		return
	if _ground_markers.has(bag_id):
		var n = _ground_markers[bag_id]
		_ground_markers.erase(bag_id)
		if n != null and is_instance_valid(n):
			n.queue_free()


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
	if hud != null and hud.has_method("show_loot"):
		var items_v: Variant = action.get("items", [])
		var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
		hud.show_loot(
			str(action.get("session_id", action.get("bag_id", ""))),
			str(action.get("npc_id", "")),
			items
		)


func _apply_loot_update(action: Dictionary) -> void:
	if hud != null and hud.has_method("refresh_loot"):
		var items_v: Variant = action.get("items", [])
		var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
		hud.refresh_loot(str(action.get("session_id", action.get("bag_id", ""))), items)


func _apply_loot_close(_action: Dictionary) -> void:
	if hud != null and hud.has_method("hide_loot"):
		hud.hide_loot()


func request_open_ground_bag(bag_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_open_ground_bag"):
		return
	var result: Dictionary = srv.try_open_ground_bag(bag_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_drop_item(item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_drop_item"):
		return
	var result: Dictionary = srv.try_drop_item(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_drop_equipped(slot: String) -> void:
	if player == null or player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_drop_equipped"):
		return
	var result: Dictionary = srv.try_drop_equipped(slot)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_loot_take(item_id: String, qty: int = -1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_take"):
		return
	var result: Dictionary = srv.try_loot_take(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_loot_take_all() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_take_all"):
		return
	var result: Dictionary = srv.try_loot_take_all()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_loot_close() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_close"):
		return
	var result: Dictionary = srv.try_loot_close()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)



func request_loot_roll(choice: String, roll_id: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_loot_roll"):
		return
	var result: Dictionary = srv.try_loot_roll(choice, roll_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_turn_in_quest(quest_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_turn_in_quest"):
		return
	var result: Dictionary = srv.try_turn_in_quest(quest_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_accept_quest(quest_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_accept_quest"):
		return
	var result: Dictionary = srv.try_accept_quest(quest_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_abandon_quest(quest_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_abandon_quest"):
		return
	var result: Dictionary = srv.try_abandon_quest(quest_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_cancel_status(status_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_cancel_status"):
		return
	var result: Dictionary = srv.try_cancel_status(status_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_debug_fill() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_debug_fill"):
		return
	var result: Dictionary = srv.try_party_debug_fill()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_create() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_create"):
		return
	var result: Dictionary = srv.try_party_create()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_invite(target: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_invite"):
		return
	var result: Dictionary = srv.try_party_invite(target)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_leave() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_leave"):
		return
	var result: Dictionary = srv.try_party_leave()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_kick(member_id: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_kick"):
		return
	var result: Dictionary = srv.try_party_kick(member_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_set_target(npc_id: String, display_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_set_target"):
		return
	if not srv.has_method("in_party") or not srv.in_party():
		return
	var result: Dictionary = srv.try_party_set_target(npc_id, display_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_clear_target() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_clear_target"):
		return
	var result: Dictionary = srv.try_party_clear_target()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_party_set_loot_mode(mode: String) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_party_set_loot_mode"):
		return
	var result: Dictionary = srv.try_party_set_loot_mode(mode)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)



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
	var pid := str(action.get("player_id", "")).strip_edges()
	if pid.is_empty() or not _remote_markers.has(pid):
		return
	var marker = _remote_markers[pid]
	if marker == null or not is_instance_valid(marker):
		return
	var cell := Vector2i(int(action.get("x", 0)), int(action.get("y", 0)))
	marker.set_meta("cell", cell)
	var facing: int = int(action.get("facing", 2))
	marker.set_meta("facing", facing)
	if map_field != null and map_field.has_method("cell_to_world"):
		var wp: Vector2 = map_field.cell_to_world(cell)
		marker.global_position = Vector2(wp.x, wp.y - float(map_field.tile_size) * 0.2)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var anim := marker.get_node_or_null("Anim") as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null:
		var walk := "walk_front"
		match facing:
			4:
				walk = "walk_left"
			6:
				walk = "walk_right"
			8:
				walk = "walk_back"
			1, 2, 3:
				walk = "walk_front"
			7:
				walk = "walk_left"
			9:
				walk = "walk_right"
			_:
				walk = "walk_front"
		if anim.sprite_frames.has_animation(walk):
			anim.play(walk)
	_radar_blips_ready = false


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
	if _pet_marker == null or not is_instance_valid(_pet_marker):
		return
	var cell := Vector2i(int(action.get("x", 0)), int(action.get("y", 0)))
	_pet_marker.set_meta("cell", cell)
	var facing: int = int(action.get("facing", 2))
	_pet_marker.set_meta("facing", facing)
	if map_field != null and map_field.has_method("cell_to_world"):
		var wp: Vector2 = map_field.cell_to_world(cell)
		_pet_marker.global_position = Vector2(wp.x, wp.y - float(map_field.tile_size) * 0.2)
	else:
		_pet_marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var anim := _pet_marker.get_node_or_null("Anim") as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null:
		var walk := "walk_front"
		match facing:
			4:
				walk = "walk_left"
			6:
				walk = "walk_right"
			8:
				walk = "walk_back"
			_:
				walk = "walk_front"
		if anim.sprite_frames.has_animation(walk):
			anim.play(walk)


func request_chat(channel: String, text: String, whisper_to: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_chat"):
		return
	var result: Dictionary = srv.try_chat(channel, text, whisper_to)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_remote_debug_spawn(display_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_remote_debug_spawn"):
		return
	var result: Dictionary = srv.try_remote_debug_spawn(display_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_open(partner_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_open"):
		return
	var result: Dictionary = srv.try_trade_open(partner_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_cancel() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_cancel"):
		return
	var result: Dictionary = srv.try_trade_cancel()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_put_item(item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_put_item"):
		return
	var result: Dictionary = srv.try_trade_put_item(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_take_item(item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_take_item"):
		return
	var result: Dictionary = srv.try_trade_take_item(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_set_gold(amount: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_set_gold"):
		return
	var result: Dictionary = srv.try_trade_set_gold(amount)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_ready(ready: bool = true) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_ready"):
		return
	var result: Dictionary = srv.try_trade_ready(ready)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_trade_confirm() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_trade_confirm"):
		return
	var result: Dictionary = srv.try_trade_confirm()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)



func request_duel_challenge(target_id_or_name: String = "") -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_challenge"):
		return
	var result: Dictionary = srv.try_duel_challenge(target_id_or_name)
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		_apply_server_actions(acts_v)


func request_duel_accept() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_accept"):
		return
	var result: Dictionary = srv.try_duel_accept()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		_apply_server_actions(acts_v)


func request_duel_decline() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_decline"):
		return
	var result: Dictionary = srv.try_duel_decline()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		_apply_server_actions(acts_v)


func request_duel_forfeit() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_duel_forfeit"):
		return
	var result: Dictionary = srv.try_duel_forfeit()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		_apply_server_actions(acts_v)


func request_craft(recipe_id: String, qty: int = 1) -> void:
	recipe_id = str(recipe_id).strip_edges()
	qty = int(qty)
	if recipe_id.is_empty() or qty <= 0:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_craft"):
		return
	var result: Dictionary = srv.try_craft(recipe_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_emote(emote_id: String) -> void:
	emote_id = str(emote_id).strip_edges()
	if emote_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_emote"):
		return
	var result: Dictionary = srv.try_emote(emote_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_dungeon_enter() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_enter"):
		return
	var result: Dictionary = srv.try_dungeon_enter()
	_apply_dungeon_server_result(result)


func request_dungeon_exit() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_dungeon_exit"):
		return
	var result: Dictionary = srv.try_dungeon_exit()
	_apply_dungeon_server_result(result)


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
	var srv = Net.server()
	if srv == null or not srv.has_method("try_pet_summon"):
		return
	var result: Dictionary = srv.try_pet_summon(pet_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_pet_dismiss() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_pet_dismiss"):
		return
	var result: Dictionary = srv.try_pet_dismiss()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_warehouse_open() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_open"):
		return
	var result: Dictionary = srv.try_warehouse_open()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_warehouse_deposit(item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_deposit"):
		return
	var result: Dictionary = srv.try_warehouse_deposit(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_warehouse_withdraw(item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_withdraw"):
		return
	var result: Dictionary = srv.try_warehouse_withdraw(item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_warehouse_deposit_gold(amount: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_deposit_gold"):
		return
	var result: Dictionary = srv.try_warehouse_deposit_gold(amount)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_warehouse_withdraw_gold(amount: int) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_warehouse_withdraw_gold"):
		return
	var result: Dictionary = srv.try_warehouse_withdraw_gold(amount)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_friend_add(name_or_id: String) -> void:
	name_or_id = str(name_or_id).strip_edges()
	if name_or_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_friend_add"):
		return
	var result: Dictionary = srv.try_friend_add(name_or_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_friend_remove(friend_id: String) -> void:
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_friend_remove"):
		return
	var result: Dictionary = srv.try_friend_remove(friend_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)



func request_guild_create(guild_name: String) -> void:
	guild_name = str(guild_name).strip_edges()
	if guild_name.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_create"):
		return
	var result: Dictionary = srv.try_guild_create(guild_name)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_guild_invite(target: String) -> void:
	target = str(target).strip_edges()
	if target.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_invite"):
		return
	var result: Dictionary = srv.try_guild_invite(target)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_guild_kick(member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_kick"):
		return
	var result: Dictionary = srv.try_guild_kick(member_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_guild_leave() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_leave"):
		return
	var result: Dictionary = srv.try_guild_leave()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_guild_disband() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_disband"):
		return
	var result: Dictionary = srv.try_guild_disband()
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_guild_invite_respond(invite_id: String, accept: bool) -> void:
	invite_id = str(invite_id).strip_edges()
	if invite_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_guild_invite_respond"):
		return
	var result: Dictionary = srv.try_guild_invite_respond(invite_id, accept)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_mail_send(to: String, subject: String, body: String, gold: int = 0, item_id: String = "", qty: int = 1) -> void:
	to = str(to).strip_edges()
	if to.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_send"):
		return
	var result: Dictionary = srv.try_mail_send(to, subject, body, gold, item_id, qty)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_mail_read(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_read"):
		return
	var result: Dictionary = srv.try_mail_read(mail_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_mail_claim(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_claim"):
		return
	var result: Dictionary = srv.try_mail_claim(mail_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_mail_delete(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_mail_delete"):
		return
	var result: Dictionary = srv.try_mail_delete(mail_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)

func request_auction_list(item_id: String, qty: int = 1, price_gold: int = 1) -> void:
	item_id = str(item_id).strip_edges()
	if item_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_auction_list"):
		return
	var result: Dictionary = srv.try_auction_list(item_id, qty, price_gold)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_auction_buy(listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_auction_buy"):
		return
	var result: Dictionary = srv.try_auction_buy(listing_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_auction_cancel(listing_id: String) -> void:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_auction_cancel"):
		return
	var result: Dictionary = srv.try_auction_cancel(listing_id)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY:
		_apply_server_actions(actions_v)


func request_learn_skill(skill_id: String) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_learn_skill"):
		return
	var result: Dictionary = srv.try_learn_skill(skill_id)
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		_apply_server_actions(acts_v)


func _apply_attr_update(action: Dictionary) -> void:
	if hud == null:
		return
	var st: Dictionary = {}
	if action.has("attr_points"):
		st["attr_points"] = int(action.get("attr_points", 0))
	if action.has("attrs"):
		st["attrs"] = action.get("attrs", {})
	var combat_v: Variant = action.get("combat", {})
	if typeof(combat_v) == TYPE_DICTIONARY and not (combat_v as Dictionary).is_empty():
		for k in (combat_v as Dictionary).keys():
			st[str(k)] = (combat_v as Dictionary)[k]
	if hud.has_method("apply_attr_update"):
		hud.apply_attr_update(action)
	elif hud.has_method("apply_combat_stats") and not st.is_empty():
		hud.apply_combat_stats(st)


func _apply_skill_book_update(action: Dictionary) -> void:
	if hud != null and hud.has_method("apply_skill_book"):
		hud.apply_skill_book(action)


func request_skill_respec() -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_skill_respec"):
		return
	var result: Dictionary = srv.try_skill_respec()
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		_apply_server_actions(acts_v)


func _apply_skill_respec(action: Dictionary) -> void:
	if hud != null and hud.has_method("apply_skill_respec"):
		hud.apply_skill_respec(action)


func request_use_skill(skill_id: String, ground: Vector2i = Vector2i(-9999, -9999)) -> void:
	if player == null or player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_use_skill"):
		return
	skill_id = skill_id.strip_edges()
	var def: Dictionary = {}
	if srv.has_method("skill_def"):
		def = srv.skill_def(skill_id)
	var tmode := str(def.get("target_mode", "")).strip_edges().to_lower()
	if tmode.is_empty() and bool(def.get("requires_target", false)):
		tmode = "unit"
	if tmode.is_empty():
		tmode = "none"
	var target_id := ""
	var npc = null
	if not _selected_npc_id.is_empty():
		npc = _find_npc_by_id(_selected_npc_id)
		if npc != null and ("hostile" in npc and bool(npc.hostile)):
			target_id = _selected_npc_id
		else:
			npc = null
	if target_id.is_empty() and tmode != "ground":
		var facing_dir: int = 2
		if player.has_method("get_facing"):
			facing_dir = CharsetSheet.dir_from_facing(str(player.get_facing()))
		npc = _find_adjacent_npc(player.cell, facing_dir)
		if npc != null and ("hostile" in npc and bool(npc.hostile)):
			target_id = str(npc.npc_id) if "npc_id" in npc else ""
	# Duel shell: selected remote opponent is a valid skill/attack target.
	if target_id.is_empty() and not _selected_remote_id.is_empty():
		var duel_srv = Net.server()
		if duel_srv != null and duel_srv.has_method("in_duel") and duel_srv.in_duel():
			var dsnap: Dictionary = duel_srv.snapshot_duel() if duel_srv.has_method("snapshot_duel") else {}
			if str(dsnap.get("opponent_id", "")) == _selected_remote_id:
				target_id = _selected_remote_id
	if tmode == "ground" and ground.x <= -9990:
		if npc != null and "cell" in npc:
			ground = npc.cell
		elif target_id.is_empty():
			begin_skill_aim(skill_id)
			return
	var chase_rng: int = _skill_chase_range(def)
	if chase_rng > 0 and npc != null and player != null:
		var pcell: Vector2i = player.cell
		if not _player_in_skill_range(npc, chase_rng, pcell):
			_set_pending_engage(npc, skill_id, chase_rng)
			if not _path_to_npc_range(npc, chase_rng):
				_clear_pending_engage()
				if hud != null and hud.has_method("append_system"):
					hud.append_system("无法到达施法距离")
			return
		_face_toward_cell(_npc_target_cell(npc))
	cancel_skill_aim()
	var gx: int = ground.x
	var gy: int = ground.y
	var result: Dictionary = srv.try_use_skill(skill_id, target_id, player.cell.x, player.cell.y, gx, gy)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_apply_server_actions(actions, npc)


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
	_ensure_skill_fx()
	var cell_v: Variant = action.get("cell", {})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var world_pos := Vector2.ZERO
	if map_field != null and map_field.has_method("cell_to_world"):
		world_pos = map_field.cell_to_world(cell)
		var ts := 48.0
		if "tile_size" in map_field:
			ts = float(map_field.tile_size)
		world_pos.y -= ts * 0.5
	else:
		world_pos = Vector2(float(cell.x) * 48.0 + 24.0, float(cell.y) * 48.0 + 24.0)
	var radius: int = int(action.get("radius", 0))
	var ts2 := 48.0
	if map_field != null and "tile_size" in map_field:
		ts2 = float(map_field.tile_size)
	var rpx: float = maxf(ts2 * float(maxi(radius, 1)), ts2)
	var effect := str(action.get("effect", ""))
	var sid := str(action.get("skill_id", ""))
	var anim := str(action.get("anim", "")).strip_edges()
	if anim == "strike" or anim == "dash" or anim == "spin" or anim == "cast":
		if effect == "aoe_damage" or radius > 0:
			_skill_fx.play_impact("flame", world_pos, rpx)
			_skill_fx.play_ring(world_pos, rpx)
		elif effect == "damage" or effect == "damage_and_status":
			_skill_fx.play_impact("bolt" if anim == "dash" else "flame", world_pos, 28.0)
		return
	if effect == "damage" or effect == "damage_and_status" or sid == "arcane_bolt" or sid == "poison_dart" or sid == "channel_beam":
		var from_pos := world_pos
		if player != null:
			from_pos = player.global_position
		var actor := str(action.get("actor", "player"))
		if actor != "player":
			var n = _find_npc_by_id(actor)
			if n != null:
				from_pos = n.global_position
		_skill_fx.play_bolt(from_pos, world_pos, "bolt")
	else:
		_skill_fx.play_impact("flame", world_pos, rpx)
		if radius > 0:
			_skill_fx.play_ring(world_pos, rpx)


func _apply_skill_anim(action: Dictionary) -> void:
	_ensure_skill_fx()
	var kind := str(action.get("kind", "cast")).strip_edges()
	var actor := str(action.get("actor", "player"))
	var node: Node2D = null
	var facing := "front"
	if actor == "player" or actor.is_empty():
		node = player
		if player != null and player.has_method("get_facing"):
			facing = str(player.get_facing())
		elif player != null and "_facing" in player:
			facing = str(player._facing)
	else:
		node = _find_npc_by_id(actor)
	if node == null:
		return
	if _skill_fx.has_method("play_action"):
		_skill_fx.play_action(kind, node, facing)
	else:
		_skill_fx.flash_actor(node)


func request_use_item(item_id: String) -> void:
	if player == null or player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_use_item"):
		return
	var result: Dictionary = srv.try_use_item(item_id)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_apply_server_actions(actions, null)


func request_equip_item(item_id: String, slot: String = "") -> void:
	if player == null or player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_equip_item"):
		return
	var result: Dictionary = srv.try_equip_item(item_id, slot)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_apply_server_actions(actions, null)


func request_unequip_item(slot: String) -> void:
	if player == null or player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_unequip_item"):
		return
	var result: Dictionary = srv.try_unequip_item(slot)
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_apply_server_actions(actions, null)


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
