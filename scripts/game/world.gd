extends Node2D
const Net = preload("res://scripts/net/net.gd")
const NpcActor = preload("res://scripts/game/npc_actor.gd")
const CharsetSheet = preload("res://scripts/char/charset_sheet.gd")
const AoiDriver = preload("res://scripts/asset/aoi_driver.gd")
const MapSfx = preload("res://scripts/map/map_sfx.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const EventCommands = preload("res://scripts/editor/event_commands.gd")
const TileId = preload("res://scripts/map/tile_id.gd")

@onready var player: CharacterBody2D = %Player
@onready var hud: Control = %GameHud
@onready var map_field: Node2D = %MapField

var _npc_layer: Node2D = null
var _ground_layer: Node2D = null
var _ground_markers: Dictionary = {}  # bag_id -> Node2D
var _remote_markers: Dictionary = {}  # player_id -> Node2D
var _hovered_ground_bag_id: String = ""
var _npcs: Array = []
var _radar_blips_cache: Array = []
var _radar_blips_sig: PackedInt32Array = PackedInt32Array()
var _radar_blips_ready: bool = false
## Click-to-engage: NPC id to attack/interact when path arrives beside them.
var _pending_engage_npc_id: String = ""
## Currently selected NPC (nameplate highlight + foot ring). Empty = none.
var _selected_npc_id: String = ""
## Soft-selected remote/fake player id (nameplate only; no HP). Empty = none.
var _selected_remote_id: String = ""
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
	_pin_hud_canvas()
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
		var am: Node = get_node_or_null("/root/AssetManager")
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
	if hud.has_method("apply_quest_snapshot"):
		var quests_v: Variant = spawn.get("quests", [])
		if typeof(quests_v) == TYPE_ARRAY and not (quests_v as Array).is_empty():
			hud.apply_quest_snapshot(quests_v)
		else:
			var srv_q = Net.server()
			if srv_q != null and srv_q.has_method("get_quest_list"):
				hud.apply_quest_snapshot(srv_q.get_quest_list())
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
	var remotes_v: Variant = spawn.get("remote_players", [])
	if typeof(remotes_v) == TYPE_ARRAY:
		for rp in remotes_v:
			if typeof(rp) == TYPE_DICTIONARY:
				_upsert_remote_marker(rp)
	elif Net.server() != null and Net.server().has_method("snapshot_remote_players"):
		for rp2 in Net.server().snapshot_remote_players():
			if typeof(rp2) == TYPE_DICTIONARY:
				_upsert_remote_marker(rp2)
	if hud.has_method("bind_world_combat"):
		hud.bind_world_combat(self)
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
	var am: Node = get_node_or_null("/root/AssetManager")
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
	## View-only blips for HUD radar: { "world": Vector2, "hostile": bool }.
	## Cache while NPC cells/hostile flags + remotes unchanged.
	var sig := PackedInt32Array()
	for n in _npcs:
		if n == null or not is_instance_valid(n):
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
	for n in _npcs:
		if n == null or not is_instance_valid(n):
			continue
		if not _npc_shows_on_radar(n):
			continue
		var world_pos := Vector2.ZERO
		if map_field != null and map_field.has_method("cell_to_world"):
			world_pos = map_field.cell_to_world(n.cell)
		else:
			world_pos = n.global_position
		out.append({
			"world": world_pos,
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


func _npc_shows_on_radar(n) -> bool:
	# Explicit radar: false force-hides; radar: true force-shows.
	if "radar_opt" in n and n.radar_opt != null:
		return bool(n.radar_opt)
	# Hostile always shows (red).
	if "hostile" in n and bool(n.hostile):
		return true
	# Object-like charset (!...) stays off radar.
	var cs := str(n.charset) if "charset" in n else ""
	if cs.begins_with("!"):
		return false
	# Character sheets (non-! charset) show as friendly by default.
	return true


func _find_npc_at(cell: Vector2i):
	for n in _npcs:
		if n != null and is_instance_valid(n) and n.has_method("contains_cell") and n.contains_cell(cell):
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
		if n != null and is_instance_valid(n) and n.has_method("is_adjacent_to") and n.is_adjacent_to(from_cell):
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
			"player_died":
				_clear_pending_engage()
				if player != null:
					player.input_locked = true
					if player.has_method("clear_move_path"):
						player.clear_move_path()
				if hud != null and hud.has_method("clear_target"):
					hud.clear_target()
			"respawn":
				_apply_respawn(action)
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
				if hud != null and hud.has_method("apply_cast_start"):
					hud.apply_cast_start(action)
			"cast_update":
				if hud != null and hud.has_method("apply_cast_update"):
					hud.apply_cast_update(action)
			"cast_end":
				if hud != null and hud.has_method("apply_cast_end"):
					hud.apply_cast_end(action)
			"party_update":
				if hud != null and hud.has_method("apply_party_update"):
					hud.apply_party_update(action)
			"trade_update":
				if hud != null and hud.has_method("apply_trade_update"):
					hud.apply_trade_update(action)
			"trade_close":
				if hud != null and hud.has_method("hide_trade"):
					hud.hide_trade()
			"remote_spawn":
				var rp_v: Variant = action.get("player", {})
				if typeof(rp_v) == TYPE_DICTIONARY:
					_upsert_remote_marker(rp_v)
			"remote_despawn":
				_remove_remote_marker(str(action.get("player_id", "")))
			"chat_message":
				if hud != null and hud.has_method("apply_chat_message"):
					hud.apply_chat_message(action)
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
	if target == "player":
		if hud != null and hud.has_method("apply_combat_stats"):
			hud.apply_combat_stats({
				"hp": hp,
				"hp_max": hp_max,
				"mp": int(action.get("mp", -1)),
				"mp_max": int(action.get("mp_max", -1)),
			})
		if hud != null and hud.has_method("append_system") and amount > 0:
			hud.append_system("受到%d点伤害" % amount)
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
	if hud != null and hud.has_method("append_system") and amount > 0:
		hud.append_system("对%s造成%d点伤害" % [display_name, amount])


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
	if hud != null and hud.has_method("append_system"):
		if amount > 0:
			hud.append_system("恢复了%d点生命" % amount)
		elif mp_gain > 0:
			hud.append_system("恢复了%d点魔法" % mp_gain)


func _apply_set_stat(action: Dictionary) -> void:
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


func _apply_quest_update(action: Dictionary) -> void:
	var quests_v: Variant = action.get("quests", [])
	var quests: Array = quests_v if typeof(quests_v) == TYPE_ARRAY else []
	if hud != null and hud.has_method("apply_quest_snapshot"):
		hud.apply_quest_snapshot(quests)


func _apply_kill_npc(npc_id: String, npc = null) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id == _selected_npc_id:
		_clear_npc_selection()
	var target = npc
	if target == null or ("npc_id" in target and str(target.npc_id) != npc_id):
		target = _find_npc_by_id(npc_id)
	if target == null:
		return
	var cell: Vector2i = target.cell if "cell" in target else Vector2i.ZERO
	# Clear occupancy so the cell is walkable again.
	var srv = Net.server()
	if srv != null and srv.map_collision != null and srv.map_collision.has_method("set_extra_blocked"):
		srv.map_collision.set_extra_blocked(cell.x, cell.y, false)
	_npcs.erase(target)
	var am_kill: Node = get_node_or_null("/root/AssetManager")
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


func _push_target_hud(npc, display_name: String, ratio: float) -> void:
	if hud == null or not hud.has_method("show_target"):
		return
	var world_pos: Variant = npc.global_position if npc else null
	hud.show_target(display_name, ratio, world_pos, _npc_shows_target_hp(npc))


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


func _set_pending_engage(npc) -> void:
	if npc == null or not ("npc_id" in npc):
		_clear_pending_engage()
		return
	_pending_engage_npc_id = str(npc.npc_id).strip_edges()


func _player_beside_npc(npc, pcell: Vector2i) -> bool:
	if npc == null:
		return false
	if npc.has_method("is_adjacent_to") and npc.is_adjacent_to(pcell):
		return true
	if npc.has_method("contains_cell") and npc.contains_cell(pcell):
		return true
	return false


## Double-click: interact/attack if adjacent, otherwise path near the NPC then engage on arrival.
func _request_npc_engage(npc) -> void:
	if npc == null or player == null:
		return
	if player.input_locked:
		return
	var pcell: Vector2i = player.cell if "cell" in player else Vector2i.ZERO
	if _player_beside_npc(npc, pcell):
		_clear_pending_engage()
		_engage_npc(npc)
		return
	_set_pending_engage(npc)
	var dest: Vector2i = npc.cell if "cell" in npc else pcell
	if not player.has_method("click_move_to"):
		_clear_pending_engage()
		return
	var ok: bool = player.click_move_to(dest)
	if not ok:
		_clear_pending_engage()
		if hud != null and hud.has_method("append_system"):
			hud.append_system("无法到达该位置")


func _on_player_path_cancelled() -> void:
	# Keyboard / failed step: drop click-to-engage intent.
	_clear_pending_engage()


func _on_player_arrived_cell(cell: Vector2i, path_complete: bool) -> void:
	_sync_map_observer()
	_play_footstep()
	if _pending_engage_npc_id.is_empty():
		return
	if player != null and player.input_locked:
		return
	var npc = _find_npc_by_id(_pending_engage_npc_id)
	if npc == null:
		_clear_pending_engage()
		return
	var beside := _player_beside_npc(npc, cell)
	if not beside:
		if path_complete:
			_clear_pending_engage()
		return
	# Arrived beside target: stop leftover path and engage.
	_clear_pending_engage()
	if player != null and player.has_method("clear_move_path"):
		player.clear_move_path()
	_engage_npc(npc)


func _load_map_presets() -> void:
	_light_presets = _read_preset_file("res://data/map/light_presets.json")
	_sound_presets = _read_preset_file("res://data/map/sound_presets.json")
	_pin_hud_canvas()
	# Day/night tints World canvas items (map, actors). Do not use CanvasModulate —
	# it multiplies every canvas in the viewport, including the HUD.
	if _bgs_player == null:
		_bgs_player = AudioStreamPlayer.new()
		_bgs_player.name = "MapBgs"
		add_child(_bgs_player)
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "MapBgm"
		add_child(_bgm_player)
	if _se_player == null:
		_se_player = AudioStreamPlayer.new()
		_se_player.name = "MapSe"
		_se_player.volume_db = -4.0
		add_child(_se_player)
	if _foot_player == null:
		_foot_player = AudioStreamPlayer.new()
		_foot_player.name = "Footstep"
		_foot_player.volume_db = -8.0
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
		_apply_world_light(atm.get("modulate", MapExt.light_modulate(light_id)))
		var vis := str(atm.get("kind", "clear"))
		if vis != _last_weather_kind:
			_last_weather_kind = vis
			if vis != "clear" and hud != null and hud.has_method("append_system"):
				hud.append_system("天气：%s" % str(atm.get("label", vis)))
		return
	_apply_world_light(MapExt.light_modulate(light_id))


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
	var am: Node = get_node_or_null("/root/AssetManager") if is_inside_tree() else null
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


func _apply_respawn(action: Dictionary) -> void:
	_clear_pending_engage()
	var cell_v: Variant = action.get("cell", {})
	var cell := Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	if player != null:
		if player.has_method("clear_move_path"):
			player.clear_move_path()
		if player.has_method("place_at_cell"):
			player.place_at_cell(cell, map_field)
		else:
			player.cell = cell
		if player.has_method("snap_camera"):
			player.snap_camera()
		player.input_locked = true
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
	var am: Node = get_node_or_null("/root/AssetManager")
	if _aoi == null or am == null:
		return
	if force:
		_aoi.refresh(player, _npcs, am)
	else:
		_aoi.tick(0.0, player, _npcs, am, true)


func _process(delta: float) -> void:
	tick_event_wait(delta)
	_tick_ground_hover()
	_tick_remote_aoi()
	if _respawn_lock_left > 0.0:
		_respawn_lock_left = maxf(0.0, _respawn_lock_left - delta)
		if _respawn_lock_left <= 0.0 and player != null:
			player.input_locked = false
	# P2c: classify NPC asset rings by distance from local player.
	if _aoi != null:
		var am: Node = get_node_or_null("/root/AssetManager")
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
		hud.apply_combat_stats({
			"level": int(action.get("level", -1)),
			"exp": int(action.get("exp", -1)),
			"exp_to_next": int(action.get("exp_to_next", -1)),
		})


func _apply_level_up(action: Dictionary) -> void:
	var combat_v: Variant = action.get("combat", {})
	var combat: Dictionary = combat_v if typeof(combat_v) == TYPE_DICTIONARY else {}
	var lv: int = int(action.get("level", combat.get("level", 1)))
	if hud != null:
		if hud.has_method("apply_level_up"):
			hud.apply_level_up(lv, combat)
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
			int(action.get("gold", 0))
		)


func request_shop_buy(shop_id: String, item_id: String, qty: int = 1) -> void:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_shop_buy"):
		return
	var result: Dictionary = srv.try_shop_buy(shop_id, item_id, qty)
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
	var am: Node = get_node_or_null("/root/AssetManager")
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
	for d in PCM.item_defs():
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
		PCM.Action.WHISPER:
			if hud != null and hud.has_method("prefill_whisper"):
				hud.prefill_whisper(dname)
			elif hud != null and hud.has_method("append_system"):
				hud.append_system("密语：在聊天框输入 /w %s 内容" % dname)
		PCM.Action.FOLLOW:
			if hud != null and hud.has_method("append_system"):
				hud.append_system("跟随：暂未实现")


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
		var body := Polygon2D.new()
		body.name = "Body"
		body.polygon = PackedVector2Array([
			Vector2(-8, -20), Vector2(8, -20), Vector2(10, 4), Vector2(-10, 4)
		])
		body.color = Color(0.35, 0.55, 0.95, 0.9)
		marker.add_child(body)
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
	var lab2 := marker.get_node_or_null("Name") as Label
	if lab2 != null:
		lab2.text = display_name
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
	if player_id == _selected_remote_id:
		_selected_remote_id = ""
	if _remote_markers.has(player_id):
		var n = _remote_markers[player_id]
		_remote_markers.erase(player_id)
		if n != null and is_instance_valid(n):
			n.queue_free()


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

func request_use_skill(skill_id: String) -> void:
	if player == null or player.input_locked:
		return
	var srv = Net.server()
	if srv == null or not srv.has_method("try_use_skill"):
		return
	var target_id := ""
	var npc = null
	# Prefer selected hostile (ranged AoE / DoT skills).
	if not _selected_npc_id.is_empty():
		npc = _find_npc_by_id(_selected_npc_id)
		if npc != null and ("hostile" in npc and bool(npc.hostile)):
			target_id = _selected_npc_id
		else:
			npc = null
	if target_id.is_empty():
		var facing_dir: int = 2
		if player.has_method("get_facing"):
			facing_dir = CharsetSheet.dir_from_facing(str(player.get_facing()))
		npc = _find_adjacent_npc(player.cell, facing_dir)
		if npc != null and ("hostile" in npc and bool(npc.hostile)):
			target_id = str(npc.npc_id) if "npc_id" in npc else ""
	var result: Dictionary = srv.try_use_skill(skill_id, target_id, player.cell.x, player.cell.y)
	if not bool(result.get("ok", false)):
		var actions_v: Variant = result.get("actions", [])
		var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
		_apply_server_actions(actions, npc)
		return
	var ok_actions_v: Variant = result.get("actions", [])
	var ok_actions: Array = ok_actions_v if typeof(ok_actions_v) == TYPE_ARRAY else []
	_apply_server_actions(ok_actions, npc)


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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
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
	var world_pos: Vector2 = get_global_mouse_position()
	var target: Vector2i = map_field.world_to_cell(world_pos)
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
