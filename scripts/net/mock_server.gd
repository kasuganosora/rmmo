extends Node
## In-process fake game server. Swap for a real NetClient later without rewriting UI.
## Combat / skills / items live under scripts/net/combat/; this node is the facade.

signal login_finished(ok: bool, message: String)
signal characters_ready(list: Array)
signal character_created(ok: bool, message: String, character: Dictionary)
signal enter_world_ready(ok: bool, message: String, spawn: Dictionary)

const LATENCY_SEC := 0.35
const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const CombatEngine = preload("res://scripts/net/combat/combat_engine.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const Warehouse = preload("res://scripts/net/combat/warehouse.gd")
const FriendList = preload("res://scripts/net/combat/friend_list.gd")
const Guild = preload("res://scripts/net/combat/guild.gd")
const Mailbox = preload("res://scripts/net/combat/mailbox.gd")
const Auction = preload("res://scripts/net/combat/auction.gd")
const Equipment = preload("res://scripts/net/combat/equipment.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const LootCatalog = preload("res://scripts/net/combat/loot_catalog.gd")
const QuestJournal = preload("res://scripts/net/combat/quest_journal.gd")
const ShopCatalog = preload("res://scripts/net/combat/shop_catalog.gd")
const EventRuntime = preload("res://scripts/net/combat/event_runtime.gd")
const RecipeCatalog = preload("res://scripts/net/combat/recipe_catalog.gd")
const GatherCatalog = preload("res://scripts/net/combat/gather_catalog.gd")
const FishCatalog = preload("res://scripts/net/combat/fish_catalog.gd")
const TitleCatalog = preload("res://scripts/net/combat/title_catalog.gd")
const AchievementCatalog = preload("res://scripts/net/combat/achievement_catalog.gd")
const SafeZoneCatalog = preload("res://scripts/net/combat/safe_zone_catalog.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const WeatherGatherUtil = preload("res://scripts/game/weather_gather_util.gd")

const DEMO_PACK_PATH := "res://demo_map"
## External first-party pack id (resolved via AssetManager; not in res://).
const DEFAULT_PACK_ID := "default"
const PartyModule = preload("res://scripts/net/server/party_module.gd")
const GuildModule = preload("res://scripts/net/server/guild_module.gd")
const FriendsModule = preload("res://scripts/net/server/friends_module.gd")
const MailModule = preload("res://scripts/net/server/mail_module.gd")
const TradeModule = preload("res://scripts/net/server/trade_module.gd")
const DuelModule = preload("res://scripts/net/server/duel_module.gd")
const LootModule = preload("res://scripts/net/server/loot_module.gd")
var _loot_module_logic: LootModule = LootModule.new(self)
var _duel_module_logic: DuelModule = DuelModule.new(self)
var _trade_module_logic: TradeModule = TradeModule.new(self)
var _mail_module_logic: MailModule = MailModule.new(self)
var _friends_module_logic: FriendsModule = FriendsModule.new(self)
var _guild_module_logic: GuildModule = GuildModule.new(self)
var _party_module_logic: PartyModule = PartyModule.new(self)

## username -> { password, characters: [{ id, name, class_id, level, look_id, gender }] }
var _accounts: Dictionary = {
	"demo": {
		"password": "demo",
		"characters": [
			{"id": 1, "name": "Demo Hero", "class_id": "adventurer", "level": 3, "look_id": "1", "gender": "female", "customization": {}},
		],
	},
}
var _next_char_id: int = 10
var _session_user: String = ""
var _session_server: String = ""
## Active character id string for hate table (fallback "player").
var _session_character_id: String = ""
## Reentrancy guards so rapid repeated UI calls don't race the simulated latency.
var _login_inflight: bool = false
var _fetch_inflight: bool = false
var _create_inflight: bool = false
var _enter_inflight: bool = false

## Authoritative map collision for the currently loaded pack
var map_collision: RefCounted = null
var _map_pack: RefCounted = null
var map_tile_size: int = 48
var map_pack_id: String = "demo_map"
var map_pack_path: String = DEMO_PACK_PATH
var map_content_id: String = ""
var map_content_version: String = ""
## Warp list for the current pack (from pack.json).
var map_warps: Array = []
## Authoritative player grid cell (blocked for NPCs).
var player_cell: Vector2i = Vector2i(-9999, -9999)
## Map spawn / transfer landing used for death respawn.
var respawn_cell: Vector2i = Vector2i(0, 0)
## Last safe cell (updated on successful moves when not adjacent to hostiles).
var last_safe_cell: Vector2i = Vector2i(0, 0)
## True after player_died until try_respawn().
var awaiting_respawn: bool = false
## Cell where the player died (就地复活).
var death_cell: Vector2i = Vector2i(-9999, -9999)
## Sitting rest (HP/MP regen + rested EXP). Cleared on move / death / recall.
var sitting: bool = false
## Rested EXP cadence (~1s).
var _sit_acc: float = 0.0
## Out-of-combat sit HP/MP regen cadence (~3s).
var _sit_regen_acc: float = 0.0
const SIT_REGEN_INTERVAL := 3.0
const SIT_REGEN_HP := 3
const SIT_REGEN_MP := 2
## Once-per-fill system chat when rested pool hits cap (reset when pool drops below).
var _rested_cap_notified: bool = false
## Auto-potion (client GameSettings pushed via try_set_auto_potion).
var auto_potion_hp: bool = false
var auto_potion_hp_pct: int = 40
var auto_potion_mp: bool = false
var auto_potion_mp_pct: int = 30
var _auto_potion_acc: float = 0.0
const AUTO_POTION_INTERVAL := 0.5
## Throttle empty-bag system_message (seconds, Time.get_ticks_msec basis).
var _auto_potion_msg_at_ms: int = -999999
## Pet combat assist (client GameSettings pushed via try_set_pet_assist; default ON).
var pet_assist: bool = true
## Last hostile the player attacked / locked for pet assist.
var _player_combat_target_id: String = ""

## Text emote / emotion bubble (Label-only; no sprites).
const EMOTE_COOLDOWN_SEC := 1.5
const EMOTE_DURATION_SEC := 2.0
## id -> {label (Chinese UI), text (bubble)}
const EMOTE_CATALOG := {
	"wave": {"label": "挥手", "text": "（挥手）"},
	"laugh": {"label": "大笑", "text": "哈哈哈"},
	"bow": {"label": "鞠躬", "text": "（鞠躬）"},
	"cry": {"label": "哭泣", "text": "（呜呜）"},
	"angry": {"label": "生气", "text": "（哼！）"},
	"love": {"label": "爱心", "text": "❤"},
	"cheer": {"label": "加油", "text": "（加油！）"},
	"think": {"label": "思考", "text": "（思考中…）"},
	"shrug": {"label": "耸肩", "text": "（耸肩）"},
	"clap": {"label": "鼓掌", "text": "（啪啪啪）"},
	"sleepy": {"label": "困倦", "text": "（打哈欠）"},
	"wow": {"label": "惊讶", "text": "（哇！）"},
}
var _emote_cd_until: float = 0.0

## Layered combat (authoritative).
var combat_stats = null
var combat_engine = null
var skill_catalog = null
var item_catalog = null
var recipe_catalog = null
## Crafting profession level (separate from combat level).
var craft_level: int = 1
var craft_xp: int = 0
var craft_xp_to_next: int = 30  ## 20 + craft_level*10 at Lv.1
## Gathering/fishing profession level (shared; separate from combat/craft).
var gather_level: int = 1
var gather_xp: int = 0
var gather_xp_to_next: int = 30  ## 20 + gather_level*10 at Lv.1
var gather_catalog = null
## node_id -> { depleted: bool, ready_at: float }
var _gather_state: Dictionary = {}
## Active gather defs for current map (id -> def).
var _gather_nodes: Dictionary = {}
var fish_catalog = null
## spot_id -> { depleted: bool, ready_at: float }
var _fish_state: Dictionary = {}
## Active fish spot defs for current map (id -> def).
var _fish_spots: Dictionary = {}
## Player cast busy lock (now_sec basis).
var _fish_busy_until: float = 0.0
var title_catalog = null
var achievement_catalog = null
var safe_zone_catalog = null
## Last emitted safe-zone inside flag (for enter/leave actions).
var _safe_zone_inside: bool = false
var _safe_zone_known: bool = false
var inventory = null
var warehouse = null
var friend_list = null
var guild = null
## Pending incoming guild invites: [{id, guild_id, guild_name, from_id, from_name}]
var _guild_invites: Array = []
var _next_guild_seq: int = 1
var _next_guild_invite_seq: int = 1
var mailbox = null
## Welcome mail injected once per enter_world session.
var _mail_welcome_sent: bool = false
## Daily attendance last claim date (local YYYY-MM-DD); survives enter_world same day.
var _attendance_last_ymd: String = ""
## Personal map pins (max 3); survive map transfer within session; reset on enter_world.
const MAP_PIN_MAX := 3
var _map_pins: Array = [] ## [{id, slot, name, map_id, cell:{x,y}}]
var auction = null
## Companion pet shell (one at a time; follows player).
var _pet: Dictionary = {
	"active": false,
	"id": "",
	"name": "",
	"cell": {"x": 0, "y": 0},
	"look_id": "1",
	"facing": 2,
	"follow_acc": 0.0,
	"combat_acc": 0.0,
}
const PET_FOLLOW_INTERVAL_SEC := 0.45
const PET_COMBAT_INTERVAL_SEC := 1.5
const PET_COMBAT_RANGE := 2
## Stay 1–2 Chebyshev cells behind the player.
const PET_LAG_MIN := 1
const PET_LAG_MAX := 2
const PET_DEFS := {
	"default": {"name": "小跟班", "look_id": "1"},
}
var equipment = null
var loot_catalog = null
var quest_journal = null
var shop_catalog = null
## Vendor reputation 0–1000 per shop_id (demo: starter_goods).
var _rep_by_vendor: Dictionary = {}
## Convenience alias for starter_goods (tests / thin shell).
var vendor_rep: int = 0
## Last shop opened on this session (sell +1 rep when set).
var _active_shop_id: String = ""
## Last NPC that opened non-event dialogue (for quest_* choice routing).
var _dialogue_npc_id: String = ""
## MV-inspired map event runtime (switches / pages / commands).
var event_runtime = null
## npc_id -> { shop_id, name, interact_text } soft meta from pack spawn.
var npc_meta: Dictionary = {}
## Accumulator for adjacent-hostile tick counter-attacks.
var _combat_tick_acc: float = 0.0
const COMBAT_TICK_INTERVAL := 1.5
## Separate AI step rate for chase (≈ NPC step_duration).
var _ai_tick_acc: float = 0.0
const AI_TICK_INTERVAL := 0.45
## Default roam radius when pack has wander:true but no wander_radius.
const DEFAULT_FRIENDLY_WANDER_RADIUS := 2
## npc_id -> spawn template (id/name/charset/stats/AI fields/home) for dead-mob respawn.
var npc_spawn_templates: Dictionary = {}
## npc_id -> ready_at (combat_stats.now_sec basis) for pending hostile respawns.
var _npc_respawn_at: Dictionary = {}
## World ground bags: bag_id -> {id, cell:{x,y}, items:[{item_id,qty}], source, owner_id, created_at, npc_id?}.
## Same-cell drops merge into one bag. Free loot when owner_id empty.
var _ground_bags: Dictionary = {}
var _bag_seq: int = 0
## Currently open loot UI session (bag_id). Empty = no open window. Close keeps the bag.
var _open_loot_bag_id: String = ""
## Optional test override for softcore death drops: Callable() -> float in [0,1).
var death_drop_randf: Callable = Callable()
## Optional test override for combat hit/crit rolls: Callable() -> float in [0,1).
## Synced onto combat_engine.combat_randf (hit roll then crit roll per swing).
var _combat_randf_override: Callable = Callable()
var combat_randf: Callable:
	get:
		return _combat_randf_override
	set(value):
		_combat_randf_override = value
		if combat_engine != null:
			combat_engine.combat_randf = value
var map_environment: String = MapExt.ENV_OUTDOOR
var weather_kind: String = "clear"
var weather_intensity: float = 0.0
var weather_auto: bool = true
## Test override for rain/snow herb +1 qty roll (0..1); empty = randf().
var weather_gather_randf: Callable = Callable()
var _weather_left: float = 40.0
var _weather_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_init_combat_layers()
	_load_pack(DEMO_PACK_PATH)


func _init_combat_layers() -> void:
	combat_stats = CombatStats.new()
	skill_catalog = SkillCatalog.new()
	skill_catalog.load_catalog()
	item_catalog = ItemCatalog.new()
	item_catalog.load_catalog()
	recipe_catalog = RecipeCatalog.new()
	recipe_catalog.load_catalog()
	gather_catalog = GatherCatalog.new()
	gather_catalog.load_catalog()
	_gather_state.clear()
	_gather_nodes.clear()
	fish_catalog = FishCatalog.new()
	fish_catalog.load_catalog()
	_fish_state.clear()
	_fish_spots.clear()
	_fish_busy_until = 0.0
	title_catalog = TitleCatalog.new()
	title_catalog.load_catalog()
	achievement_catalog = AchievementCatalog.new()
	achievement_catalog.load_catalog()
	safe_zone_catalog = SafeZoneCatalog.new()
	safe_zone_catalog.load_catalog()
	_safe_zone_known = false
	_safe_zone_inside = false
	loot_catalog = LootCatalog.new()
	loot_catalog.load_catalog()
	inventory = Inventory.new()
	inventory.set_catalog(item_catalog)
	inventory.grant_starter()
	warehouse = Warehouse.new()
	warehouse.set_catalog(item_catalog)
	warehouse.clear()
	friend_list = FriendList.new()
	friend_list.clear()
	guild = Guild.new()
	guild.clear()
	_guild_invites.clear()
	mailbox = Mailbox.new()
	mailbox.clear()
	auction = Auction.new()
	auction.clear()
	_auction_seed_npc_stubs()
	_mail_welcome_sent = false
	_attendance_last_ymd = ""
	equipment = Equipment.new()
	equipment.set_catalog(item_catalog)
	equipment.clear()
	quest_journal = QuestJournal.new()
	quest_journal.load_catalog()
	quest_journal.grant_starter()
	shop_catalog = ShopCatalog.new()
	shop_catalog.set_catalog(item_catalog)
	shop_catalog.load_catalog()
	event_runtime = EventRuntime.new()
	combat_engine = CombatEngine.new()
	combat_engine.setup(combat_stats, skill_catalog, item_catalog, inventory, equipment)
	combat_engine.combat_randf = _combat_randf_override
	combat_stats.reset_player(1)
	combat_stats.reset_titles()
	combat_stats.reset_achievements()
	_reset_skill_book()


func _process(delta: float) -> void:
	_tick_weather(delta)
	if combat_engine == null or combat_stats == null:
		return
	if player_cell.x <= -9990:
		return
	# Cast / channel advances every frame (finer than ambient combat tick).
	if combat_engine.has_method("tick_cast") and combat_engine.is_casting():
		var cast_actions: Array = combat_engine.tick_cast(delta)
		if not cast_actions.is_empty():
			var cast_result := {"ok": true, "actions": cast_actions}
			cast_result = _finalize_combat_result(cast_result)
			var ca_v: Variant = cast_result.get("actions", [])
			if typeof(ca_v) == TYPE_ARRAY and not (ca_v as Array).is_empty():
				_pending_tick_actions.append_array(ca_v)
	# NPC casts (hostile cast_time skills).
	if combat_engine.has_method("tick_npc_casts"):
		var npc_cast_actions: Array = combat_engine.tick_npc_casts(delta)
		if not npc_cast_actions.is_empty():
			_patch_npc_cast_skill_names(npc_cast_actions)
			var npc_cast_result := {"ok": true, "actions": npc_cast_actions}
			npc_cast_result = _finalize_combat_result(npc_cast_result)
			var nca_v: Variant = npc_cast_result.get("actions", [])
			if typeof(nca_v) == TYPE_ARRAY and not (nca_v as Array).is_empty():
				_pending_tick_actions.append_array(nca_v)
	# Mob AI ticks (idle wander / chase / return_home / npc_move).
	_ai_tick_acc += delta
	if _ai_tick_acc >= AI_TICK_INTERVAL:
		var ai_dt: float = _ai_tick_acc
		_ai_tick_acc = 0.0
		var ai_actions: Array = _tick_mob_ai(ai_dt)
		if not ai_actions.is_empty():
			_pending_tick_actions.append_array(ai_actions)
		var remote_acts: Array = _tick_remote_patrol(ai_dt)
		if not remote_acts.is_empty():
			_pending_tick_actions.append_array(remote_acts)
		var pet_acts: Array = _tick_pet_follow(ai_dt)
		pet_acts.append_array(_tick_pet_combat(ai_dt))
		if not pet_acts.is_empty():
			_pending_tick_actions.append_array(pet_acts)
	# Dead-mob respawn timers (independent of AI step rate).
	var respawn_actions: Array = _tick_npc_respawns()
	if not respawn_actions.is_empty():
		_pending_tick_actions.append_array(respawn_actions)
	var gather_respawn_actions: Array = _tick_gather_respawns()
	if not gather_respawn_actions.is_empty():
		_pending_tick_actions.append_array(gather_respawn_actions)
	var fish_respawn_actions: Array = _tick_fish_respawns()
	if not fish_respawn_actions.is_empty():
		_pending_tick_actions.append_array(fish_respawn_actions)
	_tick_sit(delta)
	_tick_auto_potion(delta)
	_tick_dps_meter(delta)
	_combat_tick_acc += delta
	if _combat_tick_acc < COMBAT_TICK_INTERVAL:
		return
	_combat_tick_acc = 0.0
	# Tick result is buffered; client polls via poll_combat_tick().
	var result: Dictionary = combat_engine.tick(player_cell.x, player_cell.y, COMBAT_TICK_INTERVAL)
	result = _finalize_combat_result(result)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY and not (actions_v as Array).is_empty():
		_pending_tick_actions.append_array(actions_v)


var _pending_tick_actions: Array = []


## Client drains ambient combat actions (counter-attack ticks).
func poll_combat_tick() -> Array:
	var invite_acts: Array = _tick_party_invites()
	if not invite_acts.is_empty():
		_pending_tick_actions.append_array(invite_acts)
	var loot_roll_acts: Array = _tick_loot_rolls()
	if not loot_roll_acts.is_empty():
		_pending_tick_actions.append_array(loot_roll_acts)
	var duel_acts: Array = _tick_duel()
	if not duel_acts.is_empty():
		_pending_tick_actions.append_array(duel_acts)
	# Keep party self HP fresh while grouped (shell: no net peers).
	if in_party():
		if _party_refresh_self_member() or _party_poll_pending:
			_pending_tick_actions.append(_party_update_action())
			_party_poll_pending = false
	elif _party_poll_pending:
		_pending_tick_actions.append(_party_update_action())
		_party_poll_pending = false
	if _pending_tick_actions.is_empty():
		return []
	var out: Array = _pending_tick_actions.duplicate(true)
	_pending_tick_actions.clear()
	return out


func get_weather() -> Dictionary:
	return {
		"kind": weather_kind,
		"intensity": weather_intensity,
		"indoor": _map_indoor(),
		"environment": map_environment,
	}


func set_weather(kind: String, intensity: float = 0.75, duration: float = 60.0) -> Dictionary:
	if _map_indoor():
		kind = "clear"
		intensity = 0.0
	weather_kind = Weather.normalize(kind)
	weather_intensity = 0.0 if weather_kind == "clear" else clampf(intensity, 0.0, 1.0)
	_weather_left = maxf(duration, 0.0)
	var act := _weather_action()
	_pending_tick_actions.append(act)
	return act


func _map_indoor() -> bool:
	return MapExt.normalize_environment(map_environment) == MapExt.ENV_INDOOR


func _weather_action() -> Dictionary:
	return {"type": "weather", "kind": weather_kind, "intensity": weather_intensity}


func _reset_weather_for_map() -> void:
	_weather_rng.seed = 17041 + int(map_pack_id.hash())
	if _map_indoor():
		weather_kind = "clear"
		weather_intensity = 0.0
		_weather_left = 99999.0
	else:
		weather_kind = "clear"
		weather_intensity = 0.0
		var dur: Vector2 = Weather.duration_range()
		_weather_left = _weather_rng.randf_range(dur.x, dur.y)


func _tick_weather(delta: float) -> void:
	if not weather_auto:
		return
	if _map_indoor():
		if weather_kind != "clear" or weather_intensity > 0.001:
			set_weather("clear", 0.0, 99999.0)
		return
	_weather_left -= delta
	if _weather_left > 0.0:
		return
	var cycle: Array = Weather.cycle_list()
	if cycle.is_empty():
		cycle = ["clear"]
	var nxt := str(cycle[_weather_rng.randi() % cycle.size()])
	var inten := 0.0 if Weather.normalize(nxt) == "clear" else _weather_rng.randf_range(0.55, 1.0)
	var dur2: Vector2 = Weather.duration_range()
	set_weather(nxt, inten, _weather_rng.randf_range(dur2.x, dur2.y))


func load_world_pack(pack_path: String, map_id: String = "", cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if not _load_pack(pack_path, map_id):
		return false
	if cell.x >= 0 and cell.y >= 0:
		respawn_cell = cell
		last_safe_cell = cell
		set_player_cell(cell.x, cell.y)
	_collect_autorun()
	return true


func _load_pack(pack_path: String, map_id: String = "") -> bool:
	var pack = TilemapPack.load_pack(pack_path, map_id)
	if pack == null or pack.collision == null:
		push_error("MockServer: failed to load pack collision at %s" % pack_path)
		return false
	map_collision = pack.collision
	_map_pack = pack
	if map_collision != null and bool(map_collision.get("streaming")):
		_ingest_stream_around(respawn_cell if respawn_cell.x >= 0 else Vector2i.ZERO)
	map_tile_size = pack.tile_size
	map_pack_path = pack_path.rstrip("/")
	map_pack_id = str(pack.map_id) if str(pack.map_id) != "" else pack_path.get_file()
	map_content_id = ""
	map_content_version = ""
	var pack_meta: Dictionary = {}
	var pj := FileAccess.open("%s/pack.json" % map_pack_path, FileAccess.READ)
	if pj != null:
		var parsed: Variant = JSON.parse_string(pj.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			pack_meta = parsed
	map_content_id = str(pack_meta.get("content_id", "")).strip_edges()
	map_content_version = str(pack_meta.get("version", "")).strip_edges()
	map_warps = pack.warps.duplicate(true) if pack.warps != null else []
	map_environment = MapExt.normalize_environment(pack.environment) if "environment" in pack else MapExt.ENV_OUTDOOR
	# Map events for this pack (keep session switches; reload defs only).
	if event_runtime == null:
		event_runtime = EventRuntime.new()
	event_runtime.load_from_pack(pack)
	_reload_gather_for_map()
	_reload_fish_for_map()
	# Stale occupancy belongs to the previous pack; world re-applies after spawn.
	player_cell = Vector2i(-9999, -9999)
	# Keep respawn_cell until set_player_cell / enter_world / transfer updates it.
	if combat_stats != null:
		combat_stats.clear_npcs()
	npc_spawn_templates.clear()
	_npc_respawn_at.clear()
	_ground_bags.clear()
	_open_loot_bag_id = ""
	# Map-local shell stubs do not carry across packs.
	_remote_players.clear()
	# Escrow refund if a trade was open mid-warp.
	if has_method("_trade_force_cancel_silent"):
		_trade_force_cancel_silent()
	if has_method("_duel_force_clear_silent"):
		_duel_force_clear_silent()
	if combat_engine != null and combat_engine.has_method("clear_cast"):
		combat_engine.clear_cast()
	npc_meta.clear()
	_pending_tick_actions.clear()
	_combat_tick_acc = 0.0
	_ai_tick_acc = 0.0
	_reset_weather_for_map()
	return true


func _load_demo_map() -> void:
	_load_pack(DEMO_PACK_PATH)


func is_logged_in() -> bool:
	return _session_user != ""


func current_server() -> String:
	return _session_server


func login(username: String, password: String, server: String) -> void:
	if _login_inflight:
		return
	_login_inflight = true
	await get_tree().create_timer(LATENCY_SEC).timeout
	_login_inflight = false
	username = username.strip_edges()
	server = server.strip_edges()
	if username.is_empty() or password.is_empty():
		login_finished.emit(false, "请输入用户名和密码")
		return
	if server.is_empty():
		login_finished.emit(false, "请输入服务器地址")
		return
	if not _accounts.has(username):
		_accounts[username] = {"password": password, "characters": []}
	elif str(_accounts[username].get("password", "")) != password:
		login_finished.emit(false, "用户名或密码错误")
		return
	_session_user = username
	_session_server = server
	login_finished.emit(true, "登录成功 · %s" % server)


func fetch_characters() -> void:
	if _fetch_inflight:
		return
	_fetch_inflight = true
	await get_tree().create_timer(LATENCY_SEC * 0.6).timeout
	_fetch_inflight = false
	if not is_logged_in():
		characters_ready.emit([])
		return
	var list: Array = _accounts[_session_user]["characters"].duplicate(true)
	characters_ready.emit(list)


func create_character(char_name: String, class_id: String, look_id: String, gender: String = "female", customization: Dictionary = {}) -> void:
	if _create_inflight:
		return
	_create_inflight = true
	await get_tree().create_timer(LATENCY_SEC).timeout
	_create_inflight = false
	if not is_logged_in():
		character_created.emit(false, "未登录", {})
		return
	char_name = char_name.strip_edges()
	look_id = look_id.strip_edges()
	gender = gender.strip_edges().to_lower()
	if gender != "male":
		gender = "female"
	if char_name.is_empty():
		character_created.emit(false, "请输入角色名", {})
		return
	if char_name.length() > 12:
		character_created.emit(false, "名字太长（最多 12 字）", {})
		return
	var pid: Dictionary = customization.get("part_ids", {}) if typeof(customization) == TYPE_DICTIONARY else {}
	if look_id.is_empty() and (typeof(pid) != TYPE_DICTIONARY or (pid as Dictionary).is_empty()):
		character_created.emit(false, "请选择外观", {})
		return
	for c in _accounts[_session_user]["characters"]:
		if str(c.get("name", "")) == char_name:
			character_created.emit(false, "名字已被占用", {})
			return
	var ch := {
		"id": _next_char_id,
		"name": char_name,
		"class_id": class_id if class_id != "" else "adventurer",
		"level": 1,
		"look_id": look_id,
		"gender": gender,
		"customization": customization if typeof(customization) == TYPE_DICTIONARY else {},
	}
	_next_char_id += 1
	_accounts[_session_user]["characters"].append(ch)
	character_created.emit(true, "创建成功", ch)


func enter_world(character_id: int) -> void:
	if _enter_inflight:
		return
	_enter_inflight = true
	await get_tree().create_timer(LATENCY_SEC * 1.2).timeout
	_enter_inflight = false
	if not is_logged_in():
		enter_world_ready.emit(false, "未登录", {})
		return
	var found: Dictionary = {}
	for c in _accounts[_session_user]["characters"]:
		if int(c.get("id", -1)) == character_id:
			found = c
			break
	if found.is_empty():
		enter_world_ready.emit(false, "找不到该角色", {})
		return
	# Always start the session on the home demo pack.
	_load_pack(DEMO_PACK_PATH)
	var spawn_cell := Vector2i(0, 0)
	if map_collision != null and map_collision.has_method("find_spawn_near"):
		spawn_cell = map_collision.find_spawn_near()
	var ts: float = float(map_tile_size)
	# Reset combat for this character session.
	awaiting_respawn = false
	var lv: int = int(found.get("level", 1))
	_session_character_id = str(found.get("id", "")).strip_edges()
	if combat_stats != null:
		if combat_stats.has_method("set_player_actor_id"):
			combat_stats.set_player_actor_id(
				_session_character_id if _session_character_id != "" else "player"
			)
		combat_stats.reset_player(lv)
		combat_stats.reset_titles()
		combat_stats.reset_achievements()
		combat_stats.set_achievement_counter_at_least("level", lv)
		_reset_skill_book()
	_reset_craft_skill()
	if inventory != null:
		inventory.clear()
		inventory.grant_starter()
	if warehouse != null:
		warehouse.clear()
	_shop_buyback.clear()
	if equipment != null:
		equipment.clear()
	if quest_journal != null:
		quest_journal.clear()
		quest_journal.grant_starter()
	if event_runtime != null:
		# Keep event defs from _load_pack; wipe switches for the new character session.
		event_runtime.clear_session()
	if combat_engine != null and combat_engine.has_method("reset_dps_fight"):
		combat_engine.reset_dps_fight()
	_pending_tick_actions.clear()
	_collect_autorun()
	# Party shell: fresh session, no persistence.
	_party_clear()
	_party_poll_pending = false
	_trade_force_cancel_silent()
	_duel_force_clear_silent()
	# Friends shell: reset on new character session (survives map transfer only).
	if friend_list != null:
		friend_list.clear()
	else:
		friend_list = FriendList.new()
	if guild != null:
		guild.clear()
	else:
		guild = Guild.new()
	_guild_invites.clear()
	if mailbox != null:
		mailbox.clear()
	else:
		mailbox = Mailbox.new()
	_mail_welcome_sent = false
	_mail_inject_welcome()
	_attendance_try_grant()
	if auction != null:
		auction.clear()
	else:
		auction = Auction.new()
	_auction_seed_npc_stubs()
	_remote_players.clear()
	_next_remote_seq = 1
	_pet_reset()
	_map_pins.clear()
	_dungeon.clear()
	_dungeon_xfer_lock = false
	var daily_snap: Dictionary = snapshot_daily()
	var combat_snap: Dictionary = combat_stats.snapshot_player_stats() if combat_stats != null else {}
	if not combat_snap.is_empty():
		combat_snap["mounted"] = player_is_mounted()
		combat_snap["move_speed_mul"] = player_move_speed_mul()
	var spawn := {
		"character": found,
		"map_id": map_pack_id,
		"pack_path": map_pack_path if map_pack_path != "" else DEMO_PACK_PATH,
		"content_id": map_content_id,
		"content_version": map_content_version,
		"cell": {"x": spawn_cell.x, "y": spawn_cell.y},
		"position": {
			"x": float(spawn_cell.x) * ts + ts * 0.5,
			"y": float(spawn_cell.y) * ts + ts * 0.5,
		},
		"server": _session_server,
		"combat": combat_snap,
		"skill_book": snapshot_skill_book(),
		"inventory": inventory.snapshot() if inventory != null else [],
		"gold": inventory.get_gold() if inventory != null else 0,
		"equipment": equipment.snapshot() if equipment != null else [],
		"equipment_bonuses": equipment.total_bonuses() if equipment != null else {},
		"quests": quest_journal.snapshot() if quest_journal != null else [],
		"daily_date": str(daily_snap.get("daily_date", "")),
		"daily": daily_snap.get("daily", []) if typeof(daily_snap.get("daily", [])) == TYPE_ARRAY else [],
		"party": snapshot_party(),
		"trade": snapshot_trade(),
		"duel": snapshot_duel(),
		"dungeon": snapshot_dungeon(),
		"safe_zone": snapshot_safe_zone(),
		"warehouse": snapshot_warehouse(),
		"friends": snapshot_friends(),
		"guild": snapshot_guild(),
		"mail": snapshot_mail(),
		"auction": snapshot_auction(),
		"titles": snapshot_titles(),
		"achievements": snapshot_achievements(),
		"remote_players": snapshot_remote_players(),
		"ground_bags": snapshot_ground_bags(),
		"pet": snapshot_pet(),
		"map_pins": snapshot_map_pins(),
		"craft_level": craft_level,
		"craft_xp": craft_xp,
		"craft_xp_to_next": craft_xp_to_next,
		"gather_level": gather_level,
		"gather_xp": gather_xp,
		"gather_xp_to_next": gather_xp_to_next,
	}
	respawn_cell = spawn_cell
	last_safe_cell = spawn_cell
	_safe_zone_known = false
	set_player_cell(spawn_cell.x, spawn_cell.y)
	_ensure_shell_remotes(SHELL_REMOTE_COUNT)
	spawn["remote_players"] = snapshot_remote_players()
	spawn["safe_zone"] = snapshot_safe_zone()
	var _sz_enter: Array = _safe_zone_transition_actions(true)
	if not _sz_enter.is_empty():
		_pending_tick_actions.append_array(_sz_enter)
	# Map-reach objectives (demo_map start; street_map etc. via transfer).
	if quest_journal != null:
		quest_journal.note_reach(map_pack_id, map_content_id, map_pack_path)
		spawn["quests"] = quest_journal.snapshot()
	enter_world_ready.emit(true, "正在进入世界", spawn)


## Sync player occupancy into map_collision.extra_blocked.
func set_player_cell(x: int, y: int) -> void:
	if map_collision != null:
		if player_cell.x > -9990:
			map_collision.set_extra_blocked(player_cell.x, player_cell.y, false)
		map_collision.set_extra_blocked(x, y, true)
	player_cell = Vector2i(x, y)


## Register NPC presence for range checks / tick counter-attacks / mob AI.
## aggressive: base 主动 chase-on-sight; false = 被动 (chase only after enrage from damage).
## wander_radius: idle roam cells from home (0 = stand still). Spawn cell stored as home_cell.
## group_id: 0 = solo; same non-zero = pack (assist within hit mob wander_radius).
## spawn_data: optional full npcs.json entry (name/charset/leash_radius/respawn_sec/…) stored as respawn template.
## home_override: when respawning near home, keep original home_cell (Vector2i) instead of current x,y.

## --- Town safe zones (PvP / duel / hostile aggro blocked) ---

func is_in_safe_zone(map_id: String, x: int, y: int) -> bool:
	if safe_zone_catalog == null:
		return false
	return safe_zone_catalog.is_in_safe_zone(map_id, x, y)


func player_in_safe_zone() -> bool:
	if player_cell.x <= -9990:
		return false
	return is_in_safe_zone(map_pack_id, player_cell.x, player_cell.y)


## Threat / aggro snapshot for current player vs npc (hate_list + victim_id).
func snapshot_threat(npc_id: String) -> Dictionary:
	npc_id = str(npc_id).strip_edges()
	if combat_stats == null or not combat_stats.has_method("snapshot_threat"):
		return {
			"npc_id": npc_id,
			"threat_you": false,
			"threat_rank": 0,
			"threat_pct": 0.0,
			"victim_id": "",
		}
	return combat_stats.snapshot_threat(npc_id)


func snapshot_safe_zone() -> Dictionary:
	return {"inside": player_in_safe_zone()}


func _safe_zone_action(inside: bool) -> Dictionary:
	return {"type": "safe_zone", "inside": inside}


func _safe_zone_transition_actions(force: bool = false) -> Array:
	## Emit safe_zone action when inside flag changes (or force on enter_world).
	var inside := player_in_safe_zone()
	if not force and _safe_zone_known and inside == _safe_zone_inside:
		return []
	_safe_zone_known = true
	_safe_zone_inside = inside
	return [_safe_zone_action(inside)]


func _safe_zone_block_pvp_result() -> Dictionary:
	return {
		"ok": false,
		"reason": "safe_zone",
		"actions": [{"type": "system_message", "text": "安全区内无法决斗。"}],
	}


func _target_is_remote_player(target_id: String) -> bool:
	target_id = str(target_id).strip_edges()
	if target_id.is_empty():
		return false
	if _remote_players.has(target_id):
		return true
	# Name match against spawned remotes.
	for rid in _remote_players.keys():
		var row: Variant = _remote_players[rid]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("name", "")).strip_edges() == target_id:
			return true
	return false


func register_npc(
	npc_id: String,
	x: int,
	y: int,
	hostile: bool = false,
	aggressive: bool = false,
	facing: int = 2,
	wander_radius: int = 0,
	group_id: int = 0,
	spawn_data: Dictionary = {},
	home_override: Vector2i = Vector2i(-9999, -9999)
) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or combat_stats == null:
		return
	combat_stats.set_npc_cell(npc_id, x, y)
	if not TileId.is_dir(facing):
		facing = 2
	var leash_r: int = MobAI.DEFAULT_LEASH_RADIUS
	var respawn_s: float = MobAI.DEFAULT_RESPAWN_SEC
	if not spawn_data.is_empty():
		if spawn_data.has("leash_radius"):
			leash_r = int(spawn_data.get("leash_radius", leash_r))
		if spawn_data.has("respawn_sec"):
			respawn_s = float(spawn_data.get("respawn_sec", respawn_s))
		if spawn_data.has("wander_radius"):
			wander_radius = maxi(int(spawn_data.get("wander_radius", wander_radius)), 0)
		if spawn_data.has("group_id"):
			group_id = int(spawn_data.get("group_id", group_id))
		if spawn_data.has("aggressive"):
			aggressive = bool(spawn_data.get("aggressive", aggressive))
		if spawn_data.has("hostile"):
			hostile = bool(spawn_data.get("hostile", hostile))
		if spawn_data.has("direction"):
			var fd: int = int(spawn_data.get("direction", facing))
			if TileId.is_dir(fd):
				facing = fd
	var home_cell := Vector2i(x, y)
	if home_override.x > -9990:
		home_cell = home_override
	elif not spawn_data.is_empty():
		var hc_v: Variant = spawn_data.get("home_cell", spawn_data.get("cell", {}))
		if typeof(hc_v) == TYPE_VECTOR2I:
			home_cell = hc_v
		elif typeof(hc_v) == TYPE_DICTIONARY:
			var hcd: Dictionary = hc_v
			if hcd.has("x") and hcd.has("y"):
				home_cell = Vector2i(int(hcd.get("x", x)), int(hcd.get("y", y)))
	# Friendly pack flag wander:true with no radius → default roam radius.
	var want_wander := bool(spawn_data.get("wander", false)) or wander_radius > 0
	if want_wander and wander_radius <= 0:
		wander_radius = DEFAULT_FRIENDLY_WANDER_RADIUS
	if hostile or want_wander:
		combat_stats.ensure_npc(npc_id, hostile, aggressive if hostile else false)
		combat_stats.ensure_npc_ai(
			npc_id, facing, aggressive if hostile else false, home_cell, wander_radius, group_id, leash_r, respawn_s
		)
		# Keep aggressive flag on combat blob in sync.
		if combat_stats.npcs.has(npc_id):
			combat_stats.npcs[npc_id]["hostile"] = hostile
			combat_stats.npcs[npc_id]["aggressive"] = aggressive if hostile else false
			# Optional combat overrides from npcs.json / spawn_data (world boss etc.).
			_apply_npc_spawn_combat_overrides(npc_id, spawn_data)
		# Ensure home / wander / group / leash / respawn / state from spawn registration.
		if combat_stats.npc_ai.has(npc_id):
			var ai: Dictionary = combat_stats.npc_ai[npc_id]
			ai["home_cell"] = home_cell
			ai["wander_radius"] = maxi(wander_radius, 0)
			ai["group_id"] = group_id if hostile else 0
			ai["leash_radius"] = leash_r if hostile else -1
			ai["respawn_sec"] = respawn_s if hostile else -1.0
			ai["facing"] = facing
			ai["ai_state"] = MobAI.AI_IDLE
			ai["idle_wander_acc"] = 0.0
			ai["chase_target"] = ""
			ai["lose_sight_sec"] = 0.0
			ai["seen_target"] = false
			ai["enraged"] = false
			ai["hate_list"] = []
			ai["victim_id"] = ""
			ai["aggressive"] = aggressive if hostile else false
			ai.erase("threat")
			var skills_v: Variant = spawn_data.get("skills", [])
			if typeof(skills_v) == TYPE_ARRAY:
				var sl: Array = []
				for sid_v in skills_v:
					var sid := str(sid_v).strip_edges()
					if sid != "":
						sl.append(sid)
				ai["skills"] = sl
			if not ai.has("skill_ready_at"):
				ai["skill_ready_at"] = {}
			combat_stats.npc_ai[npc_id] = ai
		# Cancel any pending respawn for this id (alive again).
		if hostile and _npc_respawn_at.has(npc_id):
			_npc_respawn_at.erase(npc_id)
	# Soft meta for interact / shop (friend and hostile).
	var meta := {
		"name": str(spawn_data.get("name", npc_id)),
		"interact_text": str(spawn_data.get("interact_text", "")),
		"shop_id": str(spawn_data.get("shop_id", "")).strip_edges(),
		"inn_rest": bool(spawn_data.get("inn_rest", false)),
		"inn_cost": int(spawn_data.get("inn_cost", 25)),
		"blacksmith": bool(spawn_data.get("blacksmith", spawn_data.get("repair", false))),
		"repair_cost_per_point": int(spawn_data.get("repair_cost_per_point", 1)),
		"world_boss": bool(spawn_data.get("world_boss", spawn_data.get("is_boss", false))),
		"dungeon": bool(spawn_data.get("dungeon", false)),
	}
	npc_meta[npc_id] = meta
	# Store / refresh spawn template for dead-mob respawn (hostiles).
	_store_npc_spawn_template(
		npc_id, x, y, hostile, aggressive, facing, wander_radius, group_id, leash_r, respawn_s, spawn_data, home_cell
	)


## Authoritative grid step. dir in {2,4,6,8}. Returns {ok, x, y, facing}.
## Rejects (with resync coords) when from ≠ authoritative player_cell.
func _ingest_stream_around(cell: Vector2i) -> void:
	if map_collision == null or not bool(map_collision.get("streaming")):
		return
	if _map_pack == null or not _map_pack.has_method("load_chunk_data"):
		return
	var cc := 16
	if "chunk_cells" in map_collision:
		cc = maxi(int(map_collision.chunk_cells), 1)
	var oc := Vector2i(int(floor(float(cell.x) / float(cc))), int(floor(float(cell.y) / float(cc))))
	for cy in range(oc.y - 2, oc.y + 3):
		for cx in range(oc.x - 2, oc.x + 3):
			if cx < 0 or cy < 0:
				continue
			if map_collision.has_method("has_stream_chunk") and map_collision.has_stream_chunk(cx, cy):
				continue
			map_collision.ingest_stream_chunk(cx, cy, _map_pack.load_chunk_data(cx, cy))



## Player grid step speed multiplier from statuses (1.0 = normal walk/run tween).
func player_move_speed_mul() -> float:
	if combat_stats == null or combat_stats.statuses == null:
		return 1.0
	if combat_stats.statuses.has_method("move_speed_mul"):
		return float(combat_stats.statuses.move_speed_mul("player"))
	var m: Dictionary = combat_stats.statuses.get_mods("player") if combat_stats.statuses.has_method("get_mods") else {}
	var v: float = float(m.get("move_speed_mul", 1.0))
	if v < 0.25:
		return 0.25
	if v > 3.0:
		return 3.0
	return v


## Mount stub: mounted buff flag (status id `mounted`).
func player_is_mounted() -> bool:
	if combat_engine != null and combat_engine.has_method("player_is_mounted"):
		return bool(combat_engine.player_is_mounted())
	if combat_stats == null or combat_stats.statuses == null:
		return false
	return combat_stats.statuses.has_status("player", "mounted")


## Toggle mount via skill authority (`mount`「骑乘」).
func try_mount() -> Dictionary:
	return try_use_skill("mount", "", player_cell.x, player_cell.y)


func try_move(from_x: int, from_y: int, dir: int) -> Dictionary:
	if map_collision == null:
		return {"ok": false, "x": from_x, "y": from_y}
	_ingest_stream_around(Vector2i(from_x, from_y))
	if combat_stats != null and not combat_stats.player_alive():
		return {"ok": false, "x": player_cell.x, "y": player_cell.y}
	# Anti-desync / spoof: client from must match server occupancy.
	if player_cell.x > -9990:
		if from_x != player_cell.x or from_y != player_cell.y:
			return {
				"ok": false,
				"x": player_cell.x,
				"y": player_cell.y,
				"resync": true,
			}
		from_x = player_cell.x
		from_y = player_cell.y
	if not TileId.is_dir(dir):
		return {"ok": false, "x": from_x, "y": from_y}
	if not map_collision.can_pass(from_x, from_y, dir):
		return {"ok": false, "x": from_x, "y": from_y}
	# v1: player move interrupts cast/channel (still allows the step).
	var interrupt_actions: Array = []
	if combat_engine != null and combat_engine.has_method("is_casting") and combat_engine.is_casting():
		if combat_engine.cast == null or combat_engine.cast.should_interrupt_on_move():
			interrupt_actions = combat_engine.interrupt_cast("move")
	var delta: Vector2i = TileId.dir_delta(dir)
	var nx: int = from_x + delta.x
	var ny: int = from_y + delta.y
	set_player_cell(nx, ny)
	_maybe_mark_safe_cell(nx, ny)
	var out := {"ok": true, "x": nx, "y": ny, "facing": dir, "move_speed_mul": player_move_speed_mul()}
	if map_collision.has_method("no_dash_at") and map_collision.no_dash_at(nx, ny):
		out["no_dash"] = true
	var all_actions: Array = []
	if sitting:
		_stand_if_sitting(all_actions)
	if not interrupt_actions.is_empty():
		all_actions.append_array(interrupt_actions)
	var touch_actions: Array = _try_player_touch_events(nx, ny)
	if not touch_actions.is_empty():
		all_actions.append_array(touch_actions)
	var sz_actions: Array = _safe_zone_transition_actions()
	if not sz_actions.is_empty():
		all_actions.append_array(sz_actions)
	if not all_actions.is_empty():
		out["actions"] = all_actions
		# Also buffer for poll_combat_tick consumers that ignore try_move actions.
		_pending_tick_actions.append_array(all_actions)
	return out


## Authoritative NPC grid step (server AI only — client must not call).
## Blocks player_cell; updates extra_blocked + AI facing on success.
## Returns {ok, x, y, facing, npc_id}.
func try_npc_move(npc_id: String, from_x: int, from_y: int, dir: int) -> Dictionary:
	if map_collision == null:
		return {"ok": false, "x": from_x, "y": from_y}
	if not TileId.is_dir(dir):
		return {"ok": false, "x": from_x, "y": from_y}
	var delta: Vector2i = TileId.dir_delta(dir)
	var nx: int = from_x + delta.x
	var ny: int = from_y + delta.y
	var onto_player := player_cell.x > -9990 and nx == player_cell.x and ny == player_cell.y
	var touch_ev: Dictionary = {}
	if onto_player:
		touch_ev = _event_touch_event(npc_id, from_x, from_y)
		if touch_ev.is_empty():
			return {"ok": false, "x": from_x, "y": from_y}
		if map_collision.has_method("can_pass_tiles") and not map_collision.can_pass_tiles(from_x, from_y, dir):
			return {"ok": false, "x": from_x, "y": from_y}
	elif not map_collision.can_pass(from_x, from_y, dir):
		return {"ok": false, "x": from_x, "y": from_y}
	map_collision.set_extra_blocked(from_x, from_y, false)
	map_collision.set_extra_blocked(nx, ny, true)
	if combat_stats != null and str(npc_id).strip_edges() != "":
		var nid := str(npc_id).strip_edges()
		combat_stats.set_npc_cell(nid, nx, ny)
		if combat_stats.npc_ai.has(nid):
			var ai: Dictionary = combat_stats.npc_ai[nid]
			ai["facing"] = dir
			combat_stats.npc_ai[nid] = ai
	var out := {"ok": true, "x": nx, "y": ny, "npc_id": npc_id, "facing": dir}
	if not touch_ev.is_empty() and event_runtime != null:
		var ctx := _event_server_ctx(str(touch_ev.get("name", touch_ev.get("id", ""))))
		var touch_actions: Array = event_runtime.run_event(str(touch_ev.get("id", "")), ctx)
		if not touch_actions.is_empty():
			out["actions"] = touch_actions
			_pending_tick_actions.append_array(touch_actions)
	return out



## Shared fields after a successful pack switch (warp / event transfer).
func _transfer_result_extras() -> Dictionary:
	# Shop buyback is session/map-local — wipe on transfer.
	_clear_shop_session_buyback()
	return {
		"ground_bags": [],
		"remote_players": snapshot_remote_players(),
		"pet": snapshot_pet(),
		"bags_cleared": true,
		"loot_close": true,
		"transfer_cleanup": "ground_bags_and_remotes",
	}


## Authoritative map transfer when standing on a warp cell.
## Returns {ok, pack_path, map_id, cell:{x,y}, facing, message} or {ok:false}.
func try_transfer(from_x: int, from_y: int) -> Dictionary:
	var warp: Dictionary = {}
	for item in map_warps:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var w: Dictionary = item
		var fc: Variant = w.get("from_cell", {})
		if typeof(fc) != TYPE_DICTIONARY:
			continue
		var fcd: Dictionary = fc
		if int(fcd.get("x", -1)) == from_x and int(fcd.get("y", -1)) == from_y:
			warp = w
			break
	if warp.is_empty():
		return {"ok": false}
	var to_pack: String = str(warp.get("to_pack", "")).strip_edges()
	var to_map_local: String = str(warp.get("to_map", warp.get("to_map_id", ""))).strip_edges()
	if to_pack.is_empty():
		to_pack = map_pack_path
	if to_pack.is_empty():
		return {"ok": false}
	var dungeon_was_active: bool = (not _dungeon_xfer_lock) and (in_dungeon() or not _dungeon.is_empty())
	var to_cell_v: Variant = warp.get("to_cell", {})
	if typeof(to_cell_v) != TYPE_DICTIONARY:
		return {"ok": false}
	var to_cell: Dictionary = to_cell_v
	var tx: int = int(to_cell.get("x", 0))
	var ty: int = int(to_cell.get("y", 0))
	var facing: int = int(warp.get("facing", 2))
	var message: String = str(warp.get("message", ""))
	var to_map_id: String = to_map_local
	if not _load_pack(to_pack, to_map_id):
		# Reload previous pack if destination failed.
		_load_pack(map_pack_path if map_pack_path != "" else DEMO_PACK_PATH)
		return {"ok": false}
	if to_map_id.is_empty():
		to_map_id = map_pack_id
	# Prefer landable cell near destination if blocked.
	if map_collision != null and map_collision.has_method("is_landable"):
		if not map_collision.is_landable(tx, ty) and map_collision.has_method("find_spawn_near"):
			var near: Vector2i = map_collision.find_spawn_near(tx, ty)
			tx = near.x
			ty = near.y
	# Keep server occupancy in sync with the destination immediately.
	respawn_cell = Vector2i(tx, ty)
	last_safe_cell = Vector2i(tx, ty)
	set_player_cell(tx, ty)
	_ensure_shell_remotes(SHELL_REMOTE_COUNT)
	var reach_actions: Array = _quest_note_reach_actions(
		to_map_id if to_map_id != "" else map_pack_id, map_content_id, map_pack_path
	)
	var out := {
		"ok": true,
		"pack_path": map_pack_path,
		"map_id": to_map_id if to_map_id != "" else map_pack_id,
		"content_id": map_content_id,
		"content_version": map_content_version,
		"cell": {"x": tx, "y": ty},
		"facing": facing,
		"message": message,
		"quests": quest_journal.snapshot() if quest_journal != null else [],
	}
	out.merge(_transfer_result_extras())
	var actions: Array = []
	actions.append({"type": "loot_close"})
	actions.append({"type": "system_message", "text": "已切换地图：上一张图的地面掉落不会带入。"})
	if not reach_actions.is_empty():
		actions.append_array(reach_actions)
	if bool(_pet.get("active", false)):
		_pet_snap_near_player()
		actions.append(_pet_spawn_action())
	actions.append_array(_shell_remote_spawn_actions())
	actions.append_array(_safe_zone_transition_actions(true))
	if dungeon_was_active:
		actions.append_array(_dungeon_abandon_on_leave())
	out["actions"] = actions
	out["dungeon"] = snapshot_dungeon()
	return out


## Interact when adjacent. Uses authoritative player_cell + registered npc cell.
## Returns {ok, actions:[{type, ...}]} like future multi-opcode scripts.
func try_interact(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return {"ok": false, "actions": []}
	if combat_stats != null and not combat_stats.player_alive():
		return {"ok": false, "actions": []}
	# Prefer authoritative occupancy over client-reported coords.
	if player_cell.x > -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	if not _require_npc_adjacent(npc_id, player_x, player_y, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "距离太远，无法互动。"}]}
	# Gather nodes (herb/ore): prefer try_gather over dialogue/events.
	if _gather_nodes.has(npc_id):
		return try_gather(npc_id)
	# Fishing spots: prefer try_fish over dialogue/events.
	if _fish_spots.has(npc_id):
		return try_fish(npc_id)
	var actions: Array = []
	var meta: Dictionary = npc_meta.get(npc_id, {}) if typeof(npc_meta.get(npc_id, {})) == TYPE_DICTIONARY else {}
	# MV event by npc/event id (or cell under the NPC).
	if event_runtime != null:
		var ev: Dictionary = event_runtime.get_event(npc_id)
		if ev.is_empty() and combat_stats != null and combat_stats.has_method("get_npc_cell"):
			var nc: Vector2i = combat_stats.get_npc_cell(npc_id)
			if nc.x > -9990:
				ev = event_runtime.get_event_at_cell(nc.x, nc.y)
		if not ev.is_empty():
			var ctx := _event_server_ctx(str(meta.get("name", ev.get("name", npc_id))))
			var page: Dictionary = event_runtime.select_page_with_ctx(ev, ctx)
			var trig := str(ev.get("trigger", "action"))
			if event_runtime.has_method("page_trigger"):
				trig = str(event_runtime.page_trigger(ev, page))
			if trig == "action":
				actions = event_runtime.run_event(str(ev.get("id", npc_id)), ctx)
			if not actions.is_empty():
				actions.append_array(_quest_note_talk_actions(npc_id))
				return {"ok": true, "actions": actions}
			# Empty page (e.g. spent touch-style) — fall through to shop/text.
	var shop_id := str(meta.get("shop_id", "")).strip_edges()
	var quest_opts: Array = _build_quest_dialogue_options(npc_id)
	# Vendor: if quest accept/turn-in options exist, show dialogue (shop as option); else open shop.
	if shop_id != "" and shop_catalog != null and shop_catalog.has_shop(shop_id):
		if not quest_opts.is_empty():
			var npc_name_v := str(meta.get("name", npc_id))
			var body_v := str(meta.get("interact_text", "")).strip_edges()
			if body_v.is_empty():
				body_v = "有什么需要的吗？"
			body_v = _append_quest_offer_blurb(body_v, npc_id)
			var opts_v: Array = quest_opts.duplicate()
			opts_v.append({"id": "shop_open:%s" % shop_id, "label": "看看商品"})
			_dialogue_npc_id = npc_id
			actions.append({
				"type": "show_npc_dialogue",
				"npc_id": npc_id,
				"npc_name": npc_name_v if npc_name_v != "" else npc_id,
				"body": body_v,
				"options": opts_v,
			})
			actions.append_array(_quest_note_talk_actions(npc_id))
			return {"ok": true, "actions": actions}
		actions.append(_build_open_shop_payload(shop_id))
		# Talking to vendor still counts as talk progress.
		actions.append_array(_quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# Innkeeper: confirm rest for gold (full HP/MP + clear harmful).
	if bool(meta.get("inn_rest", false)):
		var inn_cost := int(meta.get("inn_cost", 25))
		if inn_cost < 0:
			inn_cost = 25
		var npc_name_i := str(meta.get("name", npc_id))
		var body_i := str(meta.get("interact_text", "")).strip_edges()
		if body_i.is_empty():
			body_i = "欢迎光临。休息可以完全恢复状态，需要 %d 金币。" % inn_cost
		body_i = _append_quest_offer_blurb(body_i, npc_id)
		var opts_i: Array = quest_opts.duplicate()
		opts_i.append({"id": "inn_rest:%d" % inn_cost, "label": "休息（%dG）" % inn_cost})
		_dialogue_npc_id = npc_id
		actions.append({
			"type": "show_npc_dialogue",
			"npc_id": npc_id,
			"npc_name": npc_name_i if npc_name_i != "" else npc_id,
			"body": body_i,
			"options": opts_i,
		})
		actions.append_array(_quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# Blacksmith: repair equipped gear for gold (durability).
	if bool(meta.get("blacksmith", false)):
		var cpp := int(meta.get("repair_cost_per_point", 1))
		if cpp < 0:
			cpp = 1
		var npc_name_b := str(meta.get("name", npc_id))
		var body_b := str(meta.get("interact_text", "")).strip_edges()
		if body_b.is_empty():
			body_b = "需要修理或强化装备吗？修理每点耐久 %d 金币；强化需强化石。" % cpp
		body_b = _append_quest_offer_blurb(body_b, npc_id)
		var opts_b: Array = quest_opts.duplicate()
		opts_b.append({"id": "repair:all:%d" % cpp, "label": "修理全部（%dG/点）" % cpp})
		if inventory != null and inventory.has_method("tools_need_repair") and inventory.tools_need_repair():
			opts_b.append({"id": "repair:tools:%d" % cpp, "label": "修理工具（%dG/点）" % cpp})
		# Enhance options for each equipped piece under +5
		if equipment != null:
			for sid in equipment.SLOT_IDS:
				var iid_e := str(equipment.get_item_in(sid)).strip_edges()
				if iid_e.is_empty():
					continue
				var enh_lv: int = int(equipment.get_enhance(sid))
				if enh_lv >= int(equipment.ENHANCE_MAX):
					continue
				var cost_e: int = int(equipment.enhance_cost(enh_lv))
				var nm_e := item_display_name(iid_e) if has_method("item_display_name") else iid_e
				opts_b.append({
					"id": "enhance:%s" % sid,
					"label": "强化：%s +%d（强化石+%dG）" % [nm_e, enh_lv, cost_e],
				})
		_dialogue_npc_id = npc_id
		actions.append({
			"type": "show_npc_dialogue",
			"npc_id": npc_id,
			"npc_name": npc_name_b if npc_name_b != "" else npc_id,
			"body": body_b,
			"options": opts_b,
		})
		actions.append_array(_quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# Hardcoded + generic dialogue table.
	var npc_name := str(meta.get("name", npc_id))
	var body := str(meta.get("interact_text", "")).strip_edges()
	match npc_id:
		"actor_rest":
			npc_name = "休息中的少女"
			body = "有什么事吗？村里最近不安宁……" if body.is_empty() or body == "helloworld" else body
		_:
			pass
	if body != "" or not quest_opts.is_empty():
		if body.is_empty():
			body = "……"
		body = _append_quest_offer_blurb(body, npc_id)
		_dialogue_npc_id = npc_id
		actions.append({
			"type": "show_npc_dialogue",
			"npc_id": npc_id,
			"npc_name": npc_name if npc_name != "" else npc_id,
			"body": body,
			"options": quest_opts,
		})
		actions.append_array(_quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# NPC exists but has no script / text.
	return {"ok": true, "actions": actions}


## Build EventRuntime server_ctx for command execution.
func _event_server_ctx(npc_name: String = "") -> Dictionary:
	return {
		"inventory": inventory,
		"shop_catalog": shop_catalog,
		"npc_name": npc_name,
		"transfer_cb": Callable(self, "_event_perform_transfer"),
		"item_name_cb": Callable(self, "item_display_name"),
		"quest_item_cb": Callable(self, "_quest_note_item_actions"),
		"weather_cb": Callable(self, "set_weather"),
		"npc_step_cb": Callable(self, "_event_npc_step"),
		"npc_face_cb": Callable(self, "_event_npc_face"),
		"npc_cell_cb": Callable(self, "_event_npc_cell"),
		"npc_facing_cb": Callable(self, "_event_npc_facing"),
		"inn_rest_cb": Callable(self, "try_inn_rest"),
		"open_shop_cb": Callable(self, "_try_open_shop_action"),
		"repair_cb": Callable(self, "try_repair"),
		"collision": map_collision,
		"player_cell": player_cell,
	}


## EventRuntime move_route step → try_npc_move (collision + occupancy).
func _event_npc_step(npc_id: String, from_x: int, from_y: int, dir: int) -> Dictionary:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty():
		return {"ok": false, "x": from_x, "y": from_y}
	# Ensure cell is known so later AI / interact use the moved position.
	if combat_stats != null and combat_stats.has_method("set_npc_cell"):
		var cur: Vector2i = Vector2i(-9999, -9999)
		if combat_stats.has_method("get_npc_cell"):
			cur = combat_stats.get_npc_cell(npc_id)
		if cur.x < -9000:
			combat_stats.set_npc_cell(npc_id, from_x, from_y)
	var moved: Dictionary = try_npc_move(npc_id, from_x, from_y, dir)
	if bool(moved.get("ok", false)) and event_runtime != null:
		if event_runtime.has_method("has_event") and event_runtime.has_event(npc_id):
			if event_runtime.has_method("update_event_cell"):
				event_runtime.update_event_cell(npc_id, int(moved.get("x", from_x)), int(moved.get("y", from_y)))
	return moved


func _event_npc_face(npc_id: String, facing: int) -> void:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty() or combat_stats == null:
		return
	if combat_stats.has_method("set_npc_facing"):
		combat_stats.set_npc_facing(npc_id, facing)


func _event_npc_cell(npc_id: String) -> Vector2i:
	npc_id = str(npc_id).strip_edges()
	if combat_stats != null and combat_stats.has_method("get_npc_cell"):
		var c: Vector2i = combat_stats.get_npc_cell(npc_id)
		if c.x > -9000:
			return c
	if event_runtime != null and event_runtime.has_method("get_event"):
		var ev: Dictionary = event_runtime.get_event(npc_id)
		var cv: Variant = ev.get("cell", {})
		if typeof(cv) == TYPE_DICTIONARY:
			return Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
	return Vector2i.ZERO


func _event_npc_facing(npc_id: String) -> int:
	npc_id = str(npc_id).strip_edges()
	if combat_stats != null and combat_stats.npc_ai.has(npc_id):
		var f := int(combat_stats.npc_ai[npc_id].get("facing", 2))
		if f in [2, 4, 6, 8]:
			return f
	return 2




## Transfer used by event `transfer` op (same landing rules as try_transfer / warps).
func _event_perform_transfer(
	to_pack: String,
	to_cell: Dictionary,
	facing: int = 2,
	message: String = "",
	to_map_id: String = ""
) -> Dictionary:
	to_pack = str(to_pack).strip_edges()
	if to_pack.is_empty():
		to_pack = map_pack_path
	if to_pack.is_empty():
		return {"ok": false}
	var dungeon_was_active: bool = (not _dungeon_xfer_lock) and (in_dungeon() or not _dungeon.is_empty())
	var tx: int = int(to_cell.get("x", 0))
	var ty: int = int(to_cell.get("y", 0))
	var prev_path := map_pack_path
	if not _load_pack(to_pack, to_map_id):
		_load_pack(prev_path if prev_path != "" else DEMO_PACK_PATH)
		return {"ok": false}
	if to_map_id.strip_edges().is_empty():
		to_map_id = map_pack_id
	if map_collision != null and map_collision.has_method("is_landable"):
		if not map_collision.is_landable(tx, ty) and map_collision.has_method("find_spawn_near"):
			var near: Vector2i = map_collision.find_spawn_near(tx, ty)
			tx = near.x
			ty = near.y
	respawn_cell = Vector2i(tx, ty)
	last_safe_cell = Vector2i(tx, ty)
	set_player_cell(tx, ty)
	_ensure_shell_remotes(SHELL_REMOTE_COUNT)
	var reach_actions: Array = _quest_note_reach_actions(
		to_map_id if to_map_id != "" else map_pack_id, map_content_id, map_pack_path
	)
	var out := {
		"ok": true,
		"pack_path": map_pack_path,
		"map_id": to_map_id if to_map_id != "" else map_pack_id,
		"content_id": map_content_id,
		"content_version": map_content_version,
		"cell": {"x": tx, "y": ty},
		"facing": facing if facing in [2, 4, 6, 8] else 2,
		"message": message,
		"quests": quest_journal.snapshot() if quest_journal != null else [],
	}
	out.merge(_transfer_result_extras())
	var actions: Array = []
	actions.append({"type": "loot_close"})
	actions.append({"type": "system_message", "text": "已切换地图：上一张图的地面掉落不会带入。"})
	if not reach_actions.is_empty():
		actions.append_array(reach_actions)
	actions.append_array(_shell_remote_spawn_actions())
	actions.append_array(_safe_zone_transition_actions(true))
	if dungeon_was_active:
		actions.append_array(_dungeon_abandon_on_leave())
	out["actions"] = actions
	out["dungeon"] = snapshot_dungeon()
	return out


## Fire matching autorun pages once after a play pack/map load.
func collect_autorun() -> Array:
	return _collect_autorun()


func _collect_autorun() -> Array:
	if event_runtime == null or not event_runtime.has_method("collect_autorun"):
		return []
	var acts: Array = event_runtime.collect_autorun(_event_server_ctx())
	if not acts.is_empty():
		_pending_tick_actions.append_array(acts)
	return acts


## After a successful step, fire player_touch events on the landing cell (once per page/self-switch).
func _try_player_touch_events(x: int, y: int) -> Array:
	if event_runtime == null:
		return []
	var ev: Dictionary = event_runtime.get_event_at_cell(x, y)
	if ev.is_empty():
		return []
	var ctx := _event_server_ctx(str(ev.get("name", ev.get("id", ""))))
	var page: Dictionary = event_runtime.select_page_with_ctx(ev, ctx) if event_runtime.has_method("select_page_with_ctx") else {}
	var trig := str(ev.get("trigger", ""))
	if event_runtime.has_method("page_trigger"):
		trig = str(event_runtime.page_trigger(ev, page))
	if trig != "player_touch":
		return []
	return event_runtime.run_event(str(ev.get("id", "")), ctx)


## Event whose selected page is event_touch (does not run commands).
func _event_touch_event(npc_id: String, from_x: int, from_y: int) -> Dictionary:
	if event_runtime == null:
		return {}
	var ev: Dictionary = event_runtime.get_event(npc_id)
	if ev.is_empty():
		ev = event_runtime.get_event_at_cell(from_x, from_y)
	if ev.is_empty():
		return {}
	var ctx := _event_server_ctx(str(ev.get("name", ev.get("id", ""))))
	var page: Dictionary = event_runtime.select_page_with_ctx(ev, ctx) if event_runtime.has_method("select_page_with_ctx") else {}
	var trig := str(ev.get("trigger", ""))
	if event_runtime.has_method("page_trigger"):
		trig = str(event_runtime.page_trigger(ev, page))
	if trig != "event_touch":
		return {}
	return ev


## Client dialogue option → quest_* / shop_open / MV event choices.
func try_event_choice(option_id: String = "", option_index: int = -1) -> Dictionary:
	return try_dialogue_choice(option_id, option_index)


## Generic dialogue option handler (quest accept/turn-in, shop reopen, event choices).
func try_dialogue_choice(option_id: String = "", option_index: int = -1) -> Dictionary:
	option_id = str(option_id).strip_edges()
	if option_id.begins_with("quest_accept:"):
		var qid := option_id.substr("quest_accept:".length()).strip_edges()
		return try_accept_quest(qid)
	if option_id.begins_with("quest_turn_in:"):
		var qid2 := option_id.substr("quest_turn_in:".length()).strip_edges()
		return try_turn_in_quest(qid2)
	if option_id.begins_with("shop_open:"):
		var sid := option_id.substr("shop_open:".length()).strip_edges()
		return _try_open_shop_action(sid)
	if option_id == "inn_rest" or option_id.begins_with("inn_rest:"):
		var inn_c := 25
		if option_id.begins_with("inn_rest:"):
			inn_c = int(option_id.substr("inn_rest:".length()).strip_edges())
		return try_inn_rest(inn_c)
	# repair / repair:all / repair:all:1 / repair:weapon_main / repair:weapon_main:1
	if option_id == "repair" or option_id.begins_with("repair:"):
		var r_slot := "all"
		var r_cpp := 1
		if option_id.begins_with("repair:"):
			var rest := option_id.substr("repair:".length()).strip_edges()
			var parts: PackedStringArray = rest.split(":")
			if parts.size() >= 1 and str(parts[0]).strip_edges() != "":
				r_slot = str(parts[0]).strip_edges()
			if parts.size() >= 2:
				r_cpp = int(str(parts[1]).strip_edges())
		return try_repair(r_slot, r_cpp)
	# enhance / enhance:weapon_main
	if option_id == "enhance" or option_id.begins_with("enhance:"):
		var e_slot := ""
		if option_id.begins_with("enhance:"):
			e_slot = option_id.substr("enhance:".length()).strip_edges()
		elif equipment != null:
			# First eligible under max
			for sid2 in equipment.SLOT_IDS:
				if not str(equipment.get_item_in(sid2)).strip_edges().is_empty():
					if int(equipment.get_enhance(sid2)) < int(equipment.ENHANCE_MAX):
						e_slot = sid2
						break
		return try_enhance(e_slot)
	if event_runtime == null:
		return {"ok": false, "actions": []}
	var actions: Array = event_runtime.try_event_choice(option_id, option_index)
	return {"ok": true, "actions": actions}


## Authoritative basic attack. Delegates to combat_engine.
func try_attack(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	if player_cell.x > -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	if player_in_safe_zone() and _target_is_remote_player(npc_id):
		return _safe_zone_block_pvp_result()
	var duel_hit: Dictionary = _try_duel_attack_target(npc_id, player_x, player_y)
	if not duel_hit.is_empty():
		return duel_hit
	if combat_engine == null:
		return {"ok": false, "actions": []}
	var result: Dictionary = combat_engine.try_attack(npc_id, player_x, player_y)
	if bool(result.get("ok", false)):
		_player_combat_target_id = str(npc_id).strip_edges()
	_combat_stand_if_needed(result)
	return _finalize_combat_result(result)



## Apply authoritative player_move actions from combat (e.g. charge).
func _apply_player_move_actions(result: Dictionary) -> void:
	if result.is_empty() or not bool(result.get("ok", false)):
		return
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "player_move":
			continue
		var cell_v: Variant = a.get("cell", {})
		var nx := int(a.get("x", -9999))
		var ny := int(a.get("y", -9999))
		if typeof(cell_v) == TYPE_DICTIONARY:
			nx = int(cell_v.get("x", nx))
			ny = int(cell_v.get("y", ny))
		if nx > -9990 and ny > -9990:
			set_player_cell(nx, ny)



func _npc_is_rooted(npc_id: String) -> bool:
	if combat_stats == null or combat_stats.statuses == null:
		return false
	if combat_stats.statuses.has_status(npc_id, "root"):
		return true
	if combat_stats.statuses.has_status(npc_id, "stun"):
		return true
	return false


func try_use_skill(	skill_id: String,
	target_npc_id: String = "",
	player_x: int = -9999,
	player_y: int = -9999,
	ground_x: int = -9999,
	ground_y: int = -9999
) -> Dictionary:
	if player_cell.x > -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	elif player_x <= -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	if player_in_safe_zone() and _target_is_remote_player(target_npc_id):
		return _safe_zone_block_pvp_result()
	var revive_skill: Dictionary = _try_revive_skill(skill_id, target_npc_id, player_x, player_y)
	if not revive_skill.is_empty():
		# Skip _finalize_combat_result: it forces ok=true when caster is already dead.
		_combat_stand_if_needed(revive_skill)
		return revive_skill
	# Mount while dead: skip finalize (it would force ok=true on dead caster).
	if skill_id.strip_edges() == "mount":
		if awaiting_respawn or combat_stats == null or not combat_stats.player_alive():
			return {"ok": false, "actions": [{"type": "system_message", "text": "你已经倒下了。"}]}
	var duel_skill: Dictionary = _try_duel_skill_target(skill_id, target_npc_id, player_x, player_y)
	if not duel_skill.is_empty():
		return duel_skill
	if combat_engine == null:
		return {"ok": false, "actions": []}
	combat_engine.map_collision = map_collision
	var result: Dictionary = combat_engine.try_use_skill(
		skill_id, target_npc_id, player_x, player_y, ground_x, ground_y
	)
	_apply_player_move_actions(result)
	_bind_recall_actions(result)
	_combat_stand_if_needed(result)
	_maybe_party_skill_share(skill_id, result)
	return _finalize_combat_result(result)


func skill_def(skill_id: String) -> Dictionary:
	if skill_catalog == null:
		return {}
	return skill_catalog.get_skill(skill_id)


func _patch_npc_cast_skill_names(actions: Array) -> void:
	## Replace 【npc_id】 with display name in NPC cast resolve system messages.
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		var caster := str(a.get("caster", a.get("npc_id", ""))).strip_edges()
		if caster.is_empty():
			# Infer from message prefix if needed — also scan known npc ids in text.
			pass
		var txt := str(a.get("text", ""))
		var nid := str(a.get("npc_id", "")).strip_edges()
		if nid.is_empty():
			nid = caster
		if nid.is_empty():
			continue
		var nm := nid
		if npc_meta.has(nid):
			var nms := str((npc_meta[nid] as Dictionary).get("name", "")).strip_edges()
			if nms != "":
				nm = nms
		elif combat_stats != null and combat_stats.npcs.has(nid):
			var nms2 := str(combat_stats.npcs[nid].get("name", "")).strip_edges()
			if nms2 != "":
				nm = nms2
		if nm != nid:
			a["text"] = txt.replace("【%s】" % nid, "【%s】" % nm)


func try_npc_skill(npc_id: String, skill_id: String, ground_x: int = -9999, ground_y: int = -9999) -> Dictionary:
	if combat_engine == null or combat_stats == null:
		return {"ok": false, "actions": []}
	npc_id = npc_id.strip_edges()
	var cell: Vector2i = combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return {"ok": false, "actions": []}
	if ground_x <= -9990:
		ground_x = player_cell.x
		ground_y = player_cell.y
	combat_engine.player_cell_hint = player_cell
	var result: Dictionary = combat_engine.try_npc_skill(
		npc_id, skill_id, cell.x, cell.y, ground_x, ground_y
	)
	var nm := npc_id
	if npc_meta.has(npc_id):
		var nms := str((npc_meta[npc_id] as Dictionary).get("name", "")).strip_edges()
		if nms != "":
			nm = nms
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		for a in acts_v:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if str(a.get("type", "")) != "system_message":
				continue
			var txt := str(a.get("text", ""))
			a["text"] = txt.replace("【%s】" % npc_id, "【%s】" % nm)
	return _finalize_combat_result(result)


func try_set_auto_potion(hp_on: bool, hp_pct: int, mp_on: bool, mp_pct: int) -> void:
	auto_potion_hp = bool(hp_on)
	auto_potion_hp_pct = clampi(int(hp_pct), 1, 90)
	auto_potion_mp = bool(mp_on)
	auto_potion_mp_pct = clampi(int(mp_pct), 1, 90)


func try_set_pet_assist(on: bool) -> void:
	pet_assist = bool(on)


## Client / tests: lock combat target for pet assist (hostile npc id).
func try_set_combat_target(npc_id: String = "") -> void:
	_player_combat_target_id = str(npc_id).strip_edges()


## Rate-limited auto HP/MP potion use. Failures stay silent (optional 10s empty msg).
func _tick_auto_potion(delta: float) -> void:
	_auto_potion_acc += delta
	if _auto_potion_acc < AUTO_POTION_INTERVAL:
		return
	_auto_potion_acc = 0.0
	if combat_stats == null or inventory == null:
		return
	if awaiting_respawn or not combat_stats.player_alive():
		return
	if combat_engine != null and combat_engine.has_method("is_casting") and combat_engine.is_casting():
		return
	var used := false
	if auto_potion_hp:
		var hp: int = int(combat_stats.player.get("hp", 0))
		var hp_max: int = maxi(1, int(combat_stats.player.get("hp_max", 1)))
		var hp_pct: int = int(floor(100.0 * float(hp) / float(hp_max)))
		if hp_pct <= auto_potion_hp_pct:
			var iid := _best_auto_potion("heal_hp")
			if iid.is_empty():
				_maybe_auto_potion_msg("背包中没有生命药水。")
			elif combat_stats.is_item_ready(iid):
				var r: Dictionary = try_use_item(iid)
				if bool(r.get("ok", false)):
					var acts_v: Variant = r.get("actions", [])
					if typeof(acts_v) == TYPE_ARRAY and not (acts_v as Array).is_empty():
						_pending_tick_actions.append_array(acts_v)
					used = true
	if used:
		return
	if auto_potion_mp:
		var mp: int = int(combat_stats.player.get("mp", 0))
		var mp_max: int = maxi(1, int(combat_stats.player.get("mp_max", 1)))
		var mp_pct: int = int(floor(100.0 * float(mp) / float(mp_max)))
		if mp_pct <= auto_potion_mp_pct:
			var mid := _best_auto_potion("heal_mp")
			if mid.is_empty():
				_maybe_auto_potion_msg("背包中没有魔法药水。")
			elif combat_stats.is_item_ready(mid):
				var r2: Dictionary = try_use_item(mid)
				if bool(r2.get("ok", false)):
					var acts2: Variant = r2.get("actions", [])
					if typeof(acts2) == TYPE_ARRAY and not (acts2 as Array).is_empty():
						_pending_tick_actions.append_array(acts2)


func _best_auto_potion(effect: String) -> String:
	effect = effect.strip_edges()
	if inventory == null or item_catalog == null or effect.is_empty():
		return ""
	var best_id := ""
	var best_amt := -1
	for row in inventory.snapshot():
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid := str(row.get("id", "")).strip_edges()
		if not iid.begins_with("potion_"):
			continue
		if int(row.get("qty", 0)) <= 0:
			continue
		var def: Dictionary = item_catalog.get_item(iid)
		if def.is_empty():
			continue
		var ue := str(def.get("use_effect", def.get("effect", ""))).strip_edges()
		if ue != effect:
			continue
		var amt: int = int(def.get("amount", 0))
		if amt > best_amt:
			best_amt = amt
			best_id = iid
	return best_id


func _maybe_auto_potion_msg(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _auto_potion_msg_at_ms < 10000:
		return
	_auto_potion_msg_at_ms = now_ms
	_pending_tick_actions.append({"type": "system_message", "text": text})


func try_use_item(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	# Pet whistle: summon companion (does not consume).
	if item_id == "pet_whistle":
		if inventory == null or not inventory.has_item("pet_whistle", 1):
			return {
				"ok": false,
				"reason": "missing",
				"actions": [{"type": "system_message", "text": "背包中没有宠物哨。"}],
			}
		return try_pet_summon("default")
	# Equipment: hotbar / inventory "use" toggles equip (not consume).
	if item_catalog != null and not item_id.is_empty():
		var def: Dictionary = item_catalog.get_item(item_id)
		if str(def.get("type", "")).strip_edges() == "equipment":
			return try_toggle_equip(item_id)
		# Recall / town scroll: fail before consume if dead / awaiting respawn / already safe.
		var ue := str(def.get("use_effect", def.get("effect", ""))).strip_edges()
		if ue == "party_summon" or item_id == "party_summon":
			return _try_party_summon_item(item_id, def)
		if ue == "recall" or ue == "teleport_home":
			var gate: Dictionary = _gate_recall_item_use()
			if not bool(gate.get("ok", false)):
				return gate
	if combat_engine == null:
		return {"ok": false, "actions": []}
	var result: Dictionary = combat_engine.try_use_item(item_id)
	_bind_recall_actions(result)
	_combat_stand_if_needed(result)
	_maybe_party_food_share(item_id, result)
	return _finalize_combat_result(result)


## Pre-consume checks for recall / teleport_home items (Chinese messages).
func _gate_recall_item_use() -> Dictionary:
	var actions: Array = []
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var dest: Vector2i = _town_dest()
	if player_cell == dest:
		actions.append({"type": "system_message", "text": "你已在安全点。"})
		return {"ok": false, "reason": "already_safe", "actions": actions}
	return {"ok": true, "actions": []}


func _town_dest() -> Vector2i:
	var dest: Vector2i = respawn_cell
	if dest.x <= -9990:
		dest = last_safe_cell
	if map_collision != null and map_collision.has_method("is_landable"):
		if not map_collision.is_landable(dest.x, dest.y) and map_collision.has_method("find_spawn_near"):
			dest = map_collision.find_spawn_near(dest.x, dest.y)
	elif map_collision != null and map_collision.has_method("find_spawn_near") and dest.x <= -9990:
		dest = map_collision.find_spawn_near()
	return dest


func _bind_recall_actions(result: Dictionary) -> void:
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	var acts: Array = acts_v
	var dest := _town_dest()
	var bound := false
	for i in range(acts.size()):
		var a: Variant = acts[i]
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str((a as Dictionary).get("type", "")) != "recall":
			continue
		var rec: Dictionary = a
		if dest.x > -9990:
			rec["cell"] = {"x": dest.x, "y": dest.y}
			set_player_cell(dest.x, dest.y)
		acts[i] = rec
		bound = true
	if bound:
		if sitting:
			_stand_if_sitting(acts)
		sitting = false
		_sit_acc = 0.0
		_sit_regen_acc = 0.0
	result["actions"] = acts


func _combat_stand_if_needed(result: Dictionary) -> void:
	if not sitting:
		return
	var acts_v: Variant = result.get("actions", [])
	var acts: Array = acts_v if typeof(acts_v) == TYPE_ARRAY else []
	_stand_if_sitting(acts)
	result["actions"] = acts


func _stand_if_sitting(actions: Array) -> bool:
	if not sitting:
		return false
	sitting = false
	_sit_acc = 0.0
	_sit_regen_acc = 0.0
	actions.append({"type": "sit", "on": false})
	actions.append({"type": "system_message", "text": "你站了起来。"})
	return true


func _tick_sit(delta: float) -> void:
	if not sitting or combat_stats == null:
		return
	if awaiting_respawn or not combat_stats.player_alive():
		sitting = false
		_sit_acc = 0.0
		_sit_regen_acc = 0.0
		return
	# Rested EXP keeps 1s cadence (independent of HP/MP regen interval).
	_sit_acc += delta
	while _sit_acc >= 1.0:
		_sit_acc -= 1.0
		_pending_tick_actions.append_array(_tick_rested_accumulate())
	# Out-of-combat sit HP/MP: +3 HP / +2 MP every ~3s (2× in safe zone). Silent set_stat.
	var in_combat := false
	if combat_engine != null and combat_engine.has_method("player_in_combat"):
		in_combat = bool(combat_engine.player_in_combat())
	if in_combat:
		_sit_regen_acc = 0.0
		return
	_sit_regen_acc += delta
	if _sit_regen_acc < SIT_REGEN_INTERVAL:
		return
	_sit_regen_acc = 0.0
	var p: Dictionary = combat_stats.player
	var hp_max: int = int(p.get("hp_max", 100))
	var mp_max: int = int(p.get("mp_max", 50))
	var hp: int = int(p.get("hp", 0))
	var mp: int = int(p.get("mp", 0))
	var base_h: int = SIT_REGEN_HP
	var base_m: int = SIT_REGEN_MP
	if player_in_safe_zone():
		base_h *= 2
		base_m *= 2
	var dh: int = 0
	var dm: int = 0
	if hp < hp_max:
		dh = mini(hp_max - hp, base_h)
	if mp < mp_max:
		dm = mini(mp_max - mp, base_m)
	if dh <= 0 and dm <= 0:
		return
	p["hp"] = hp + dh
	p["mp"] = mp + dm
	combat_stats.player = p
	var set_act := {
		"type": "set_stat",
		"target": "player",
		"hp": int(p.get("hp", 0)),
		"hp_max": hp_max,
		"mp": int(p.get("mp", 0)),
		"mp_max": mp_max,
	}
	if combat_stats.has_method("get_rested_exp"):
		set_act["rested_exp"] = int(combat_stats.get_rested_exp())
		set_act["rested_exp_max"] = int(combat_stats.rested_exp_max())
	_pending_tick_actions.append(set_act)


## +RESTED_EXP_PER_TICK while sitting in safe zone; clamp to rested_exp_max.
## System chat only on empty→nonzero and first hit of cap (not every tick).
func _tick_rested_accumulate() -> Array:
	var actions: Array = []
	if combat_stats == null or not sitting:
		return actions
	if not player_in_safe_zone():
		return actions
	if not combat_stats.has_method("add_rested_exp"):
		return actions
	combat_stats.ensure_rested()
	var before: int = int(combat_stats.get_rested_exp())
	var cap: int = int(combat_stats.rested_exp_max())
	if before >= cap:
		return actions
	var per: int = int(CombatStats.RESTED_EXP_PER_TICK) if CombatStats != null else 5
	var result: Dictionary = combat_stats.add_rested_exp(per)
	var after: int = int(result.get("rested_exp", before))
	if after == before:
		return actions
	actions.append({
		"type": "rested_update",
		"rested_exp": after,
		"rested_exp_max": int(result.get("rested_exp_max", cap)),
	})
	if bool(result.get("was_empty", false)) and after > 0:
		actions.append({"type": "system_message", "text": "开始积攒休息经验。"})
	if bool(result.get("hit_cap", false)) and not _rested_cap_notified:
		_rested_cap_notified = true
		actions.append({"type": "system_message", "text": "休息经验已满。"})
	elif after < cap:
		_rested_cap_notified = false
	return actions


## Equip from bag into paperdoll slot (preferred_slot optional). Emits inventory_update + equipment_update.
func try_equip_item(item_id: String, slot: String = "") -> Dictionary:
	item_id = item_id.strip_edges()
	slot = slot.strip_edges()
	if equipment == null or inventory == null:
		return {"ok": false, "reason": "no_equipment", "actions": []}
	var r: Dictionary = equipment.try_equip_from_bag(inventory, item_id, slot)
	var actions: Array = []
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", "fail"))
		var msg := str(r.get("message", "")).strip_edges()
		if msg.is_empty():
			msg = "无法装备。"
			match reason:
				"incompatible_slot":
					msg = "该物品不能装备到此栏位。"
				"not_in_bag":
					msg = "背包中没有该物品。"
				"not_equipment":
					msg = "该物品无法装备。"
				"bag_full":
					msg = "背包已满，无法替换装备。"
				"unknown_item":
					msg = "未知物品。"
				"two_hand_blocks_off":
					msg = "双手武器占用副手。"
				_:
					msg = "无法装备（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append(_equipment_update_action())
	var iname := item_display_name(item_id)
	var slot_used := str(r.get("slot", slot))
	actions.append({"type": "system_message", "text": "装备了【%s】。" % iname})
	if bool(r.get("newly_bound", false)):
		actions.append({"type": "system_message", "text": "已绑定：%s" % iname})
	return {
		"ok": true,
		"reason": "",
		"slot": slot_used,
		"unequipped_item_id": str(r.get("unequipped_item_id", "")),
		"newly_bound": bool(r.get("newly_bound", false)),
		"bound": bool(r.get("bound", false)),
		"actions": actions,
	}


## Unequip paperdoll slot back into bag.
func try_unequip_item(slot: String) -> Dictionary:
	slot = slot.strip_edges()
	if equipment == null or inventory == null:
		return {"ok": false, "reason": "no_equipment", "actions": []}
	var r: Dictionary = equipment.try_unequip_to_bag(inventory, slot)
	var actions: Array = []
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", "fail"))
		var msg := "无法卸下。"
		match reason:
			"empty":
				msg = "该栏位没有装备。"
			"bag_full":
				msg = "背包已满，无法卸下。"
			"invalid_slot":
				msg = "无效栏位。"
			_:
				msg = "无法卸下（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var iid := str(r.get("item_id", ""))
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append(_equipment_update_action())
	actions.append({"type": "system_message", "text": "卸下了【%s】。" % item_display_name(iid)})
	return {"ok": true, "reason": "", "item_id": iid, "slot": slot, "actions": actions}



## Toggle equip by item_id: unequip if on paperdoll, else equip from bag.
func try_toggle_equip(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if equipment == null or inventory == null:
		return {"ok": false, "reason": "no_equipment", "actions": []}
	if item_id.is_empty():
		return {"ok": false, "reason": "invalid", "actions": [{"type": "system_message", "text": "未知物品。"}]}
	var slot := ""
	if equipment.has_method("find_slot_of"):
		slot = str(equipment.find_slot_of(item_id)).strip_edges()
	else:
		for sid in Equipment.SLOT_IDS:
			if str(equipment.get_item_in(sid)).strip_edges() == item_id:
				slot = sid
				break
	if not slot.is_empty():
		return try_unequip_item(slot)
	# Not equipped — try equip from bag (auto slot).
	return try_equip_item(item_id, "")


func _equipment_update_action() -> Dictionary:
	return {
		"type": "equipment_update",
		"equipment": equipment.snapshot() if equipment != null else [],
		"bonuses": equipment.total_bonuses() if equipment != null else {},
	}



## Skill book snapshot for HUD / spawn / transfer.
func snapshot_skill_book() -> Dictionary:
	if combat_stats == null:
		return {"known": ["basic_attack"], "skill_points": 0}
	if combat_stats.has_method("snapshot_skill_book"):
		return combat_stats.snapshot_skill_book()
	if combat_stats.skill_book != null and combat_stats.skill_book.has_method("snapshot"):
		return combat_stats.skill_book.snapshot()
	return {"known": ["basic_attack"], "skill_points": 0}


func _reset_skill_book() -> void:
	if combat_stats == null:
		return
	combat_stats.ensure_skill_book()
	combat_stats.skill_book.grant_starters(skill_catalog)


## SP granted per level-up (tune reasonably).
const SP_PER_LEVEL := 1


func _append_level_up_sp(actions: Array, levels_gained: Array) -> void:
	if combat_stats == null or levels_gained.is_empty():
		return
	combat_stats.ensure_skill_book()
	var gained: int = int(levels_gained.size()) * SP_PER_LEVEL
	if gained > 0:
		combat_stats.skill_book.grant_skill_points(gained)
		var book: Dictionary = snapshot_skill_book()
		actions.append({
			"type": "skill_book_update",
			"known": book.get("known", []),
			"skill_points": int(book.get("skill_points", 0)),
		})
		actions.append({
			"type": "system_message",
			"text": "获得技能点 %d（当前 %d）。" % [gained, int(book.get("skill_points", 0))],
		})
	# Attr points already added inside grant_exp; announce + push snapshot.
	if combat_stats.has_method("ensure_attrs"):
		combat_stats.ensure_attrs()
	var attr_gained: int = int(levels_gained.size()) * 5
	var snap: Dictionary = combat_stats.snapshot_player_stats()
	actions.append({
		"type": "attr_update",
		"attr_points": int(snap.get("attr_points", 0)),
		"attrs": snap.get("attrs", {"str": 0, "agi": 0, "vit": 0, "intel": 0}),
		"combat": snap,
	})
	if attr_gained > 0:
		actions.append({
			"type": "system_message",
			"text": "获得属性点 %d（当前 %d）。" % [attr_gained, int(snap.get("attr_points", 0))],
		})


## Learn a catalog skill by spending SP when learn_level is met.
func try_learn_skill(skill_id: String) -> Dictionary:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty() or combat_stats == null or skill_catalog == null:
		return {"ok": false, "actions": [{"type": "system_message", "text": "无法学习技能。"}]}
	combat_stats.ensure_skill_book()
	var lv: int = maxi(int(combat_stats.player.get("level", 1)), 1)
	var result: Dictionary = combat_stats.skill_book.try_learn(skill_id, skill_catalog, lv)
	var actions: Array = []
	actions.append({"type": "system_message", "text": str(result.get("message", ""))})
	if bool(result.get("ok", false)):
		var book: Dictionary = snapshot_skill_book()
		actions.append({
			"type": "skill_book_update",
			"known": book.get("known", []),
			"skill_points": int(book.get("skill_points", 0)),
		})
	return {"ok": bool(result.get("ok", false)), "actions": actions}


## Flat gold cost to respec skills (independent of refunded SP).
const SKILL_RESPEC_GOLD_COST := 50


## Reset learned skills (keep basic_attack), refund SP, pay flat gold; scrub forgotten hotbar ids via action.
func try_skill_respec() -> Dictionary:
	var actions: Array = []
	if combat_stats == null or skill_catalog == null:
		actions.append({"type": "system_message", "text": "无法重置技能。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if not combat_stats.player_alive() or awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if in_duel():
		actions.append({"type": "system_message", "text": "决斗中无法重置技能。"})
		return {"ok": false, "reason": "duel", "actions": actions}
	combat_stats.ensure_skill_book()
	var book = combat_stats.skill_book
	# Peek: anything besides basic_attack?
	var has_extra := false
	for sid_v in book.list_known():
		if str(sid_v).strip_edges() != "basic_attack":
			has_extra = true
			break
	if not has_extra:
		actions.append({"type": "system_message", "text": "没有可重置的技能。"})
		return {"ok": false, "reason": "nothing", "actions": actions}
	var cost: int = SKILL_RESPEC_GOLD_COST
	if inventory == null:
		actions.append({"type": "system_message", "text": "无法重置技能。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	if inventory.get_gold() < cost:
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var result: Dictionary = book.try_respec(skill_catalog)
	if not bool(result.get("ok", false)):
		inventory.add_gold(cost)
		actions.append({"type": "system_message", "text": str(result.get("message", "无法重置技能。"))})
		return {"ok": false, "reason": str(result.get("reason", "fail")), "actions": actions}
	var refunded: int = int(result.get("refunded_sp", 0))
	var cleared: Array = []
	var cleared_v: Variant = result.get("cleared", [])
	if typeof(cleared_v) == TYPE_ARRAY:
		for c in cleared_v:
			var cid := str(c).strip_edges()
			if not cid.is_empty():
				cleared.append(cid)
	var snap: Dictionary = snapshot_skill_book()
	actions.append({
		"type": "skill_book_update",
		"known": snap.get("known", []),
		"skill_points": int(snap.get("skill_points", 0)),
	})
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "skill_respec",
		"cleared": cleared,
		"refunded_sp": refunded,
		"gold_spent": cost,
	})
	actions.append({
		"type": "system_message",
		"text": "已重置技能，返还技能点 %d。" % refunded,
	})
	return {
		"ok": true,
		"reason": "ok",
		"refunded_sp": refunded,
		"gold_spent": cost,
		"cleared": cleared,
		"actions": actions,
	}


## Flat gold cost to respec primary attributes.
const ATTR_RESPEC_GOLD_COST := 30


## Spend unspent attr_points into str|agi|vit|intel; recompute derived combat.
func try_allocate_attr(stat_key: String, amount: int = 1) -> Dictionary:
	var actions: Array = []
	if combat_stats == null:
		actions.append({"type": "system_message", "text": "无法分配属性点。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if not combat_stats.player_alive() or awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var result: Dictionary = combat_stats.try_allocate_attr(stat_key, amount)
	actions.append({"type": "system_message", "text": str(result.get("message", ""))})
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "fail")), "actions": actions}
	var combat_snap: Dictionary = result.get("combat", {}) if typeof(result.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
	actions.append({
		"type": "attr_update",
		"attr_points": int(result.get("attr_points", 0)),
		"attrs": result.get("attrs", {}),
		"combat": combat_snap,
	})
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(combat_snap.get("hp", 0)),
		"hp_max": int(combat_snap.get("hp_max", 0)),
		"mp": int(combat_snap.get("mp", 0)),
		"mp_max": int(combat_snap.get("mp_max", 0)),
		"level": int(combat_snap.get("level", 1)),
		"exp": int(combat_snap.get("exp", 0)),
		"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
		"atk": int(combat_snap.get("atk", 0)),
		"def": int(combat_snap.get("def", 0)),
		"attr_points": int(combat_snap.get("attr_points", 0)),
		"attrs": combat_snap.get("attrs", {}),
	})
	return {
		"ok": true,
		"reason": "ok",
		"attr_points": int(result.get("attr_points", 0)),
		"attrs": result.get("attrs", {}),
		"actions": actions,
	}


## Refund all allocated attrs to points for flat gold.
func try_attr_respec() -> Dictionary:
	var actions: Array = []
	if combat_stats == null:
		actions.append({"type": "system_message", "text": "无法重置属性。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if not combat_stats.player_alive() or awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if in_duel():
		actions.append({"type": "system_message", "text": "决斗中无法重置属性。"})
		return {"ok": false, "reason": "duel", "actions": actions}
	var cost: int = ATTR_RESPEC_GOLD_COST
	if inventory == null:
		actions.append({"type": "system_message", "text": "无法重置属性。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	# Peek: any allocated attrs?
	combat_stats.ensure_attrs()
	var peek: Dictionary = combat_stats.player.get("attrs", {})
	var allocated := 0
	for k in ["str", "agi", "vit", "intel"]:
		allocated += int(peek.get(k, 0))
	if allocated <= 0:
		actions.append({"type": "system_message", "text": "没有可重置的属性点。"})
		return {"ok": false, "reason": "nothing", "actions": actions}
	if inventory.get_gold() < cost:
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var result: Dictionary = combat_stats.try_attr_respec_refund()
	if not bool(result.get("ok", false)):
		inventory.add_gold(cost)
		actions.append({"type": "system_message", "text": str(result.get("message", "无法重置属性。"))})
		return {"ok": false, "reason": str(result.get("reason", "fail")), "actions": actions}
	var combat_snap: Dictionary = result.get("combat", {}) if typeof(result.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
	actions.append({
		"type": "attr_update",
		"attr_points": int(result.get("attr_points", 0)),
		"attrs": result.get("attrs", {}),
		"combat": combat_snap,
	})
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(combat_snap.get("hp", 0)),
		"hp_max": int(combat_snap.get("hp_max", 0)),
		"mp": int(combat_snap.get("mp", 0)),
		"mp_max": int(combat_snap.get("mp_max", 0)),
		"level": int(combat_snap.get("level", 1)),
		"exp": int(combat_snap.get("exp", 0)),
		"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
		"atk": int(combat_snap.get("atk", 0)),
		"def": int(combat_snap.get("def", 0)),
		"attr_points": int(combat_snap.get("attr_points", 0)),
		"attrs": combat_snap.get("attrs", {}),
	})
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": str(result.get("message", "已重置属性。")),
	})
	return {
		"ok": true,
		"reason": "ok",
		"refunded": int(result.get("refunded", 0)),
		"gold_spent": cost,
		"attr_points": int(result.get("attr_points", 0)),
		"actions": actions,
	}


## Skill catalog snapshot for HUD (includes icon_index / optional icon from JSON).
func snapshot_skill_catalog() -> Array:
	if skill_catalog == null:
		return []
	return skill_catalog.list_all()


## Quest journal snapshot for HUD (accepted quests only).
func get_quest_list() -> Array:
	if quest_journal == null:
		return []
	return quest_journal.get_quest_list()


func snapshot_quest_journal() -> Array:
	return get_quest_list()


## Grant kill EXP after loot. Emits exp_gain / level_up + Chinese system chat.
## Party bonus (MockServer): when in_party, N = online same-map members (stubs count as
## same-map / online). Self gets max(1, floor(base * (1 + 0.05*(N-1)))) capped +25%.
## Stub allies have no separate EXP bars — only the local player is granted EXP.
func grant_kill_exp(npc_id: String) -> Array:
	var actions: Array = []
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or combat_stats == null:
		return actions
	var npc_lv: int = 1
	if combat_stats.npcs.has(npc_id):
		npc_lv = maxi(int(combat_stats.npcs[npc_id].get("level", 1)), 1)
	elif npc_spawn_templates.has(npc_id):
		var tmpl: Dictionary = npc_spawn_templates[npc_id]
		if tmpl.has("level"):
			npc_lv = maxi(int(tmpl.get("level", 1)), 1)
		else:
			# Match combat_stats.ensure_npc hash fallback when template lacks level.
			npc_lv = 1 + absi(hash(npc_id + ":lv")) % 8
	else:
		npc_lv = 1 + absi(hash(npc_id + ":lv")) % 8
	var base_amount: int = combat_stats.kill_exp_for_npc_level(npc_lv)
	var amount: int = base_amount
	var party_n: int = 0
	if in_party():
		party_n = _party_online_same_map_count()
		amount = _party_kill_exp_with_bonus(base_amount, party_n)
	# Rested bonus: up to 2× while pool remains (bonus = min(pool, grant_base)).
	var grant_base: int = amount
	var rested_bonus: int = 0
	if combat_stats.has_method("spend_rested_for_kill"):
		rested_bonus = int(combat_stats.spend_rested_for_kill(grant_base))
		amount = grant_base + rested_bonus
		if rested_bonus > 0:
			_rested_cap_notified = false
	var summary: Dictionary = combat_stats.grant_exp(amount)
	var rested_now: int = int(combat_stats.get_rested_exp()) if combat_stats.has_method("get_rested_exp") else 0
	var rested_max: int = int(combat_stats.rested_exp_max()) if combat_stats.has_method("rested_exp_max") else 0
	actions.append({
		"type": "exp_gain",
		"amount": int(summary.get("amount", amount)),
		"exp": int(summary.get("exp", 0)),
		"exp_to_next": int(summary.get("exp_to_next", 0)),
		"level": int(summary.get("level", 1)),
		"rested_bonus": rested_bonus,
		"rested_exp": rested_now,
		"rested_exp_max": rested_max,
	})
	actions.append({
		"type": "system_message",
		"text": "获得经验 %d" % int(summary.get("amount", amount)),
	})
	if rested_bonus > 0:
		actions.append({
			"type": "system_message",
			"text": "休息加成 +%d" % rested_bonus,
		})
		actions.append({
			"type": "rested_update",
			"rested_exp": rested_now,
			"rested_exp_max": rested_max,
		})
	if party_n > 1 and grant_base > base_amount:
		actions.append({
			"type": "system_message",
			"text": "队伍加成",
		})
	if bool(summary.get("leveled", false)):
		var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
		for lv_v in summary.get("levels_gained", []):
			var new_lv: int = int(lv_v)
			actions.append({
				"type": "level_up",
				"level": new_lv,
				"combat": combat_snap,
			})
			actions.append({
				"type": "system_message",
				"text": "升级到 Lv.%d！" % new_lv,
			})
		_append_level_up_sp(actions, summary.get("levels_gained", []))
		# Also push set_stat so HUD bars pick up new max HP/MP.
		actions.append({
			"type": "set_stat",
			"target": "player",
			"hp": int(combat_snap.get("hp", 0)),
			"hp_max": int(combat_snap.get("hp_max", 0)),
			"mp": int(combat_snap.get("mp", 0)),
			"mp_max": int(combat_snap.get("mp_max", 0)),
			"level": int(combat_snap.get("level", 1)),
			"exp": int(combat_snap.get("exp", 0)),
			"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
			"atk": int(combat_snap.get("atk", 0)),
			"def": int(combat_snap.get("def", 0)),
			"attr_points": int(combat_snap.get("attr_points", 0)),
			"attrs": combat_snap.get("attrs", {}),
		})
		actions.append_array(_sync_achievement_level(int(combat_snap.get("level", 1))))
	return actions


## Apply structured quest reward via existing APIs. Returns action opcodes.
func _grant_quest_reward(reward: Dictionary) -> Array:
	var actions: Array = []
	if typeof(reward) != TYPE_DICTIONARY:
		return actions
	var exp_amt: int = maxi(int(reward.get("exp", 0)), 0)
	var gold_amt: int = maxi(int(reward.get("gold", 0)), 0)
	var items_v: Variant = reward.get("items", [])
	if exp_amt > 0 and combat_stats != null:
		var summary: Dictionary = combat_stats.grant_exp(exp_amt)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", exp_amt)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "获得经验 %d" % exp_amt})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				var new_lv: int = int(lv_v)
				actions.append({"type": "level_up", "level": new_lv, "combat": combat_snap})
				actions.append({"type": "system_message", "text": "升级到 Lv.%d！" % new_lv})
			_append_level_up_sp(actions, summary.get("levels_gained", []))
			actions.append({
				"type": "set_stat",
				"target": "player",
				"hp": int(combat_snap.get("hp", 0)),
				"hp_max": int(combat_snap.get("hp_max", 0)),
				"mp": int(combat_snap.get("mp", 0)),
				"mp_max": int(combat_snap.get("mp_max", 0)),
				"level": int(combat_snap.get("level", 1)),
				"exp": int(combat_snap.get("exp", 0)),
				"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
				"atk": int(combat_snap.get("atk", 0)),
				"def": int(combat_snap.get("def", 0)),
				"attr_points": int(combat_snap.get("attr_points", 0)),
				"attrs": combat_snap.get("attrs", {}),
			})
	var inv_dirty := false
	if gold_amt > 0 and inventory != null:
		inventory.add_gold(gold_amt)
		inv_dirty = true
		actions.append({"type": "system_message", "text": "获得金币 %d" % gold_amt})
	if typeof(items_v) == TYPE_ARRAY and inventory != null:
		for it in items_v:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid := str(it.get("id", it.get("item_id", ""))).strip_edges()
			var qty: int = maxi(int(it.get("qty", 1)), 1)
			if iid.is_empty():
				continue
			var add_r: Dictionary = _try_add_loot_item(iid, qty)
			var added: int = int(add_r.get("added", 0))
			if added > 0:
				inv_dirty = true
				actions.append({
					"type": "system_message",
					"text": "获得 %s×%d" % [item_display_name(iid), added],
				})
	if inv_dirty and inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
	return actions


func _build_quest_dialogue_options(npc_id: String) -> Array:
	var out: Array = []
	if quest_journal == null:
		return out
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return out
	# Turn-in first (ready), then offers.
	if quest_journal.has_method("can_turn_in_to"):
		for q in quest_journal.can_turn_in_to(npc_id):
			if typeof(q) != TYPE_DICTIONARY:
				continue
			var qid := str(q.get("id", "")).strip_edges()
			var title := str(q.get("title", qid))
			if qid.is_empty():
				continue
			out.append({"id": "quest_turn_in:%s" % qid, "label": "交付：%s" % title})
	if quest_journal.has_method("list_offers_for_npc"):
		for def in quest_journal.list_offers_for_npc(npc_id):
			if typeof(def) != TYPE_DICTIONARY:
				continue
			var oid := str(def.get("id", "")).strip_edges()
			var otitle := str(def.get("title", oid))
			if oid.is_empty():
				continue
			out.append({"id": "quest_accept:%s" % oid, "label": "接受：%s" % otitle})
	return out


func _append_quest_offer_blurb(body: String, npc_id: String) -> String:
	if quest_journal == null or not quest_journal.has_method("list_offers_for_npc"):
		return body
	var offers: Array = quest_journal.list_offers_for_npc(npc_id)
	if offers.is_empty():
		return body
	var lines: Array = []
	for def in offers:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var offer := str(def.get("offer_text", "")).strip_edges()
		var title := str(def.get("title", def.get("id", "")))
		if offer.is_empty():
			offer = "有任务可接：%s" % title
		lines.append(offer)
	if lines.is_empty():
		return body
	var blurb := ""
	for i in range(lines.size()):
		if i > 0:
			blurb += "\n"
		blurb += str(lines[i])
	return body + "\n\n" + blurb


func _try_open_shop_action(shop_id: String) -> Dictionary:
	shop_id = shop_id.strip_edges()
	var actions: Array = []
	if shop_id.is_empty() or shop_catalog == null or not shop_catalog.has_shop(shop_id):
		actions.append({"type": "system_message", "text": "商店不可用。"})
		return {"ok": false, "reason": "no_shop", "actions": actions}
	actions.append(_build_open_shop_payload(shop_id))
	return {"ok": true, "shop_id": shop_id, "actions": actions}


## Vendor rep 0–1000 for a shop (generic map; vendor_rep mirrors starter_goods).
func get_vendor_rep(shop_id: String = "starter_goods") -> int:
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		shop_id = "starter_goods"
	if shop_id == "starter_goods":
		return clampi(vendor_rep, 0, 1000)
	return clampi(int(_rep_by_vendor.get(shop_id, 0)), 0, 1000)


func set_vendor_rep(shop_id: String, value: int) -> void:
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		shop_id = "starter_goods"
	var v: int = clampi(value, 0, 1000)
	_rep_by_vendor[shop_id] = v
	if shop_id == "starter_goods":
		vendor_rep = v


func force_vendor_rep(shop_id: String, value: int) -> void:
	set_vendor_rep(shop_id, value)


func _vendor_discount_pct(rep: int) -> int:
	if rep >= 600:
		return 15
	if rep >= 300:
		return 10
	if rep >= 100:
		return 5
	return 0


func _discounted_buy_price(base: int, discount_pct: int) -> int:
	base = maxi(base, 0)
	if discount_pct <= 0:
		return maxi(base, 0)
	# Floor gold at least 1 when base > 0.
	if base <= 0:
		return 0
	return maxi(1, (base * (100 - discount_pct)) / 100)


## Snapshot shop with discounted listings + vendor_rep.
func snapshot_shop(shop_id: String = "starter_goods") -> Dictionary:
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		shop_id = "starter_goods"
	var rep: int = get_vendor_rep(shop_id)
	var pct: int = _vendor_discount_pct(rep)
	var listings: Array = []
	if shop_catalog != null and shop_catalog.has_shop(shop_id):
		for row_v in shop_catalog.build_listings(shop_id):
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = (row_v as Dictionary).duplicate(true)
			var base: int = int(row.get("buy_price", 0))
			row["base_buy_price"] = base
			row["buy_price"] = _discounted_buy_price(base, pct)
			listings.append(row)
	return {
		"shop_id": shop_id,
		"title": shop_catalog.shop_title(shop_id) if shop_catalog != null else shop_id,
		"listings": listings,
		"gold": inventory.get_gold() if inventory != null else 0,
		"vendor_rep": rep,
		"discount_pct": pct,
		"buyback": snapshot_shop_buyback(),
	}


func _build_open_shop_payload(shop_id: String) -> Dictionary:
	_active_shop_id = shop_id.strip_edges()
	var snap: Dictionary = snapshot_shop(shop_id)
	return {
		"type": "open_shop",
		"shop_id": str(snap.get("shop_id", shop_id)),
		"title": str(snap.get("title", shop_id)),
		"listings": snap.get("listings", []) if typeof(snap.get("listings", [])) == TYPE_ARRAY else [],
		"gold": int(snap.get("gold", 0)),
		"vendor_rep": int(snap.get("vendor_rep", 0)),
		"discount_pct": int(snap.get("discount_pct", 0)),
		"buyback": snap.get("buyback", []) if typeof(snap.get("buyback", [])) == TYPE_ARRAY else [],
	}


## +delta rep (cap 1000); system_message「声望提升」only when crossing 100/300/600.
func _add_vendor_rep(shop_id: String, delta: int) -> Array:
	var actions: Array = []
	if delta == 0:
		return actions
	shop_id = shop_id.strip_edges()
	if shop_id.is_empty():
		return actions
	var before: int = get_vendor_rep(shop_id)
	var after: int = clampi(before + delta, 0, 1000)
	set_vendor_rep(shop_id, after)
	for thr in [100, 300, 600]:
		if before < thr and after >= thr:
			actions.append({"type": "system_message", "text": "声望提升"})
	return actions


func try_accept_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	var actions: Array = []
	if quest_journal == null:
		actions.append({"type": "system_message", "text": "任务系统不可用。"})
		return {"ok": false, "reason": "no_journal", "actions": actions}
	var already := false
	var jr: Dictionary = {}
	if quest_journal.has_method("try_accept_quest"):
		jr = quest_journal.try_accept_quest(quest_id)
		if not bool(jr.get("ok", false)):
			var reason := str(jr.get("reason", "reject"))
			var msg := str(jr.get("message", "")).strip_edges()
			if msg.is_empty():
				msg = "无法接取该任务。"
				if reason == "daily_claimed":
					msg = "今日已领取该日常。"
			actions.append({"type": "system_message", "text": msg})
			return {"ok": false, "reason": reason, "actions": actions}
		already = bool(jr.get("already", false))
	else:
		if quest_journal.has_method("is_accepted"):
			already = bool(quest_journal.is_accepted(quest_id))
		elif quest_journal.get_quest(quest_id):
			already = not quest_journal.get_quest(quest_id).is_empty()
		var ok: bool = bool(quest_journal.accept_quest(quest_id))
		if not ok:
			actions.append({"type": "system_message", "text": "无法接取该任务。"})
			return {"ok": false, "reason": "reject", "actions": actions}
	# If accepted from the talk-target NPC in the same dialogue, count talk progress.
	var talk_npc := _dialogue_npc_id
	if talk_npc != "":
		actions.append_array(_quest_note_talk_actions(talk_npc))
	actions.append(_quest_update_action())
	var title := quest_id
	var q: Dictionary = quest_journal.get_quest(quest_id)
	if not q.is_empty():
		title = str(q.get("title", quest_id))
	elif quest_journal.has_method("get_catalog_entry"):
		var def0: Dictionary = quest_journal.get_catalog_entry(quest_id)
		if not def0.is_empty():
			title = str(def0.get("title", quest_id))
	if already:
		actions.append({"type": "system_message", "text": "任务已在日志中：%s" % title})
	else:
		actions.append({"type": "system_message", "text": "已接取任务：%s" % title})
		if quest_journal.has_method("get_catalog_entry"):
			var def: Dictionary = quest_journal.get_catalog_entry(quest_id)
			var at := str(def.get("accept_text", "")).strip_edges()
			if at != "":
				actions.append({"type": "system_message", "text": at})
	return {"ok": true, "quest_id": quest_id, "actions": actions}


func try_abandon_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	var actions: Array = []
	if quest_journal == null:
		actions.append({"type": "system_message", "text": "任务系统不可用。"})
		return {"ok": false, "reason": "no_journal", "actions": actions}
	var title := quest_id
	var before: Dictionary = quest_journal.get_quest(quest_id)
	if not before.is_empty():
		title = str(before.get("title", quest_id))
	var r: Dictionary = quest_journal.try_abandon_quest(quest_id)
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", "fail"))
		var msg := "无法放弃任务。"
		match reason:
			"completed":
				msg = "已完成的任务无法放弃。"
			"not_accepted":
				msg = "未接取该任务。"
			_:
				msg = "无法放弃任务（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	actions.append(_quest_update_action())
	actions.append({"type": "system_message", "text": "已放弃任务：%s" % title})
	return {"ok": true, "quest_id": quest_id, "actions": actions}


func try_turn_in_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if quest_journal == null:
		return {"ok": false, "reason": "no_journal", "actions": [{"type": "system_message", "text": "任务系统不可用。"}]}
	var title := quest_id
	var q_before: Dictionary = quest_journal.get_quest(quest_id)
	if not q_before.is_empty():
		title = str(q_before.get("title", quest_id))
	elif quest_journal.has_method("get_catalog_entry"):
		var def_ti: Dictionary = quest_journal.get_catalog_entry(quest_id)
		if not def_ti.is_empty():
			title = str(def_ti.get("title", quest_id))
	var r: Dictionary = quest_journal.try_turn_in(quest_id)
	var actions: Array = []
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", "fail"))
		var msg := "无法交付任务。"
		match reason:
			"not_ready":
				msg = "任务目标尚未完成。"
			"already_completed":
				msg = "该任务已完成。"
			"not_accepted":
				msg = "未接取该任务。"
			_:
				msg = "无法交付任务（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var reward: Dictionary = r.get("reward", {}) if typeof(r.get("reward", {})) == TYPE_DICTIONARY else {}
	actions.append_array(_grant_quest_reward(reward))
	actions.append(_quest_update_action())
	actions.append({"type": "system_message", "text": "任务完成：%s" % title})
	return {"ok": true, "quest_id": quest_id, "actions": actions}


func try_shop_buy(shop_id: String, item_id: String, qty: int = 1) -> Dictionary:
	shop_id = shop_id.strip_edges()
	item_id = item_id.strip_edges()
	qty = maxi(qty, 1)
	var actions: Array = []
	if shop_catalog == null or inventory == null:
		return {"ok": false, "reason": "no_shop", "actions": [{"type": "system_message", "text": "商店不可用。"}]}
	if not shop_catalog.has_shop(shop_id) or not shop_catalog.sells_item(shop_id, item_id):
		actions.append({"type": "system_message", "text": "该商店不出售此物品。"})
		return {"ok": false, "reason": "not_sold", "actions": actions}
	var base_unit: int = shop_catalog.buy_price_for(shop_id, item_id)
	if base_unit < 0:
		actions.append({"type": "system_message", "text": "价格无效。"})
		return {"ok": false, "reason": "bad_price", "actions": actions}
	var unit: int = _discounted_buy_price(base_unit, _vendor_discount_pct(get_vendor_rep(shop_id)))
	var total: int = unit * qty
	if not inventory.try_spend_gold(total):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % total})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(item_id, qty)
	var added: int = int(add_r.get("added", 0))
	if added <= 0:
		# Refund — use real try_add reason (stack merge path already handled when room exists).
		inventory.add_gold(total)
		var reason := str(add_r.get("reason", "bag_full"))
		var msg := "背包已满，无法购买。"
		if reason == "stack_full":
			msg = "该物品已达堆叠上限，无法购买。"
		elif reason == "invalid":
			msg = "无法购买该物品。"
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason if reason != "" else "bag_full", "actions": actions}
	if added < qty:
		# Partial: refund unused
		var refund: int = unit * (qty - added)
		inventory.add_gold(refund)
		total = unit * added
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "购买了 %s×%d（-%d 金币）" % [item_display_name(item_id), added, total],
	})
	# +1 rep per purchase (not per unit); threshold msgs before refresh.
	actions.append_array(_add_vendor_rep(shop_id, 1))
	# Refresh shop gold / discounted listings / rep for client.
	actions.append(_build_open_shop_payload(shop_id))
	return {"ok": true, "actions": actions, "unit_price": unit, "paid": total, "vendor_rep": get_vendor_rep(shop_id)}


func try_shop_sell(item_id: String, qty: int = 1) -> Dictionary:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 1)
	var actions: Array = []
	if inventory == null or item_catalog == null:
		return {"ok": false, "reason": "no_inv", "actions": [{"type": "system_message", "text": "无法出售。"}]}
	var def: Dictionary = item_catalog.get_item(item_id)
	if def.is_empty():
		actions.append({"type": "system_message", "text": "未知物品。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	var sell_price: int = maxi(int(def.get("sell_price", 0)), 0)
	if sell_price <= 0:
		actions.append({"type": "system_message", "text": "该物品无法出售。"})
		return {"ok": false, "reason": "no_sell", "actions": actions}
	if inventory.has_method("is_locked") and inventory.is_locked(item_id):
		actions.append({"type": "system_message", "text": "该物品已锁定，无法出售。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	# BoP bound stacks cannot be vendor-sold (BoE bound still can).
	if _item_binds_on_pickup(item_id):
		var unbound: int = inventory.unbound_qty(item_id) if inventory.has_method("unbound_qty") else 0
		if unbound < qty:
			actions.append({"type": "system_message", "text": "已绑定，无法出售。"})
			return {"ok": false, "reason": "bound", "actions": actions}
	if not inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "not_in_bag", "actions": actions}
	if not inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "出售失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var gained: int = sell_price * qty
	inventory.add_gold(gained)
	_push_shop_buyback(item_id, qty, sell_price)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "出售了 %s×%d（+%d 金币）" % [item_display_name(item_id), qty, gained],
	})
	# Small sell rep: +1 when a vendor shop is active.
	if _active_shop_id != "":
		actions.append_array(_add_vendor_rep(_active_shop_id, 1))
	actions.append(_shop_buyback_action())
	return {"ok": true, "actions": actions}


## Bulk sell junk from bag.
## Rules (sell-junk eligibility):
## - kind/type in [misc, material] (catalog uses `type`; accept `kind` alias)
## - not locked
## - unit sell_price ≤ 10 (catalog `sell_price`, fallback `price`)
## - exclude ids: pet_whistle, scroll_town
## - exclude id prefixes: potion_*, food_*, fish_* (even if type/price would match)
## try_shop_sell does not require shop open — same here (anytime + message).
func try_shop_sell_junk() -> Dictionary:
	var actions: Array = []
	if inventory == null or item_catalog == null:
		return {"ok": false, "reason": "no_inv", "actions": [{"type": "system_message", "text": "无法出售。"}]}
	var total_gained := 0
	var sold_any := false
	# Snapshot first — consume mutates bag stacks.
	var rows: Array = inventory.snapshot()
	for row_v in rows:
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var iid := str(row.get("id", "")).strip_edges()
		var qty: int = int(row.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		if not _is_shop_junk_item(iid):
			continue
		if inventory.has_method("is_locked") and inventory.is_locked(iid):
			continue
		if bool(row.get("locked", false)):
			continue
		if bool(row.get("bound", false)) and _item_binds_on_pickup(iid):
			continue
		var unit: int = _shop_junk_unit_price(iid)
		if unit <= 0 or unit > 10:
			continue
		# Re-check live qty (snapshot may be stale vs earlier consumes of same id).
		var have: int = inventory.get_qty(iid) if inventory.has_method("get_qty") else qty
		if have <= 0:
			continue
		var take: int = have
		if not inventory.consume(iid, take):
			continue
		var gained: int = unit * take
		total_gained += gained
		sold_any = true
		_push_shop_buyback(iid, take, unit)
	if not sold_any:
		actions.append({"type": "system_message", "text": "没有可出售的垃圾。"})
		return {"ok": false, "reason": "no_junk", "actions": actions, "gained": 0}
	inventory.add_gold(total_gained)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "出售垃圾获得 %d 金。" % total_gained,
	})
	actions.append(_shop_buyback_action())
	return {"ok": true, "actions": actions, "gained": total_gained}


func _shop_junk_unit_price(item_id: String) -> int:
	var def: Dictionary = item_catalog.get_item(item_id) if item_catalog != null else {}
	if def.is_empty():
		return 0
	var sp: int = int(def.get("sell_price", -1))
	if sp < 0:
		sp = int(def.get("price", 0))
	return maxi(sp, 0)


func _is_shop_junk_item(item_id: String) -> bool:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return false
	if item_id in ["pet_whistle", "scroll_town"]:
		return false
	if item_id.begins_with("potion_") or item_id.begins_with("food_") or item_id.begins_with("fish_"):
		return false
	var def: Dictionary = item_catalog.get_item(item_id) if item_catalog != null else {}
	if def.is_empty():
		return false
	# Catalog field is `type`; accept `kind` if present.
	var kind := str(def.get("kind", "")).strip_edges().to_lower()
	if kind.is_empty():
		kind = str(def.get("type", "")).strip_edges().to_lower()
	if kind not in ["misc", "material"]:
		return false
	var unit: int = _shop_junk_unit_price(item_id)
	return unit > 0 and unit <= 10


## Shop buyback ring (last N sold stacks this shop/map session).
const BUYBACK_MAX := 8
var _shop_buyback: Array = []


func snapshot_shop_buyback() -> Array:
	return _shop_buyback.duplicate(true)


func _clear_shop_session_buyback() -> void:
	_shop_buyback.clear()
	_active_shop_id = ""


## Client closed shop UI — drop buyback list for this session.
func try_shop_close() -> Dictionary:
	# Keep buyback until map transfer / ring overwrite — accidental close must not wipe it.
	return {"ok": true, "actions": [_shop_buyback_action()]}


func _push_shop_buyback(item_id: String, qty: int, unit_price: int, bound: bool = false) -> void:
	_shop_buyback.insert(0, {
		"item_id": item_id,
		"qty": qty,
		"unit_price": unit_price,
		"price": unit_price * qty,  # total buyback cost (= sell gold gained)
		"name": item_display_name(item_id),
		"bound": bound,
	})
	while _shop_buyback.size() > BUYBACK_MAX:
		_shop_buyback.pop_back()


func _shop_buyback_action() -> Dictionary:
	return {"type": "shop_buyback", "buyback": snapshot_shop_buyback(), "gold": inventory.get_gold() if inventory else 0}


func try_shop_buyback(index: int, qty: int = -1) -> Dictionary:
	var actions: Array = []
	if inventory == null:
		return {"ok": false, "reason": "no_inv", "actions": [{"type": "system_message", "text": "无法回购。"}]}
	if _shop_buyback.is_empty() or index < 0 or index >= _shop_buyback.size():
		actions.append({"type": "system_message", "text": "没有可回购的物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var row: Dictionary = _shop_buyback[index]
	var iid := str(row.get("item_id", "")).strip_edges()
	var have: int = maxi(int(row.get("qty", 0)), 0)
	var unit: int = maxi(int(row.get("unit_price", 0)), 0)
	var take: int = have if qty < 0 else clampi(qty, 1, have)
	if iid.is_empty() or take <= 0:
		actions.append({"type": "system_message", "text": "没有可回购的物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var total: int = unit * take
	if not inventory.try_spend_gold(total):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	# Respect bind: BoP always returns bound; otherwise restore sold bound flag.
	var restore_bound := bool(row.get("bound", false))
	if _item_binds_on_pickup(iid):
		restore_bound = true
	var add_r: Dictionary = inventory.try_add_item(iid, take, restore_bound)
	var added: int = int(add_r.get("added", 0))
	if added <= 0:
		inventory.add_gold(total)
		actions.append({"type": "system_message", "text": "背包已满，无法回购。"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	if added < take:
		inventory.add_gold(unit * (take - added))
		take = added
		total = unit * take
	var left: int = have - take
	if left <= 0:
		_shop_buyback.remove_at(index)
	else:
		row["qty"] = left
		row["price"] = unit * left
		_shop_buyback[index] = row
	var nm := item_display_name(iid)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append(_shop_buyback_action())
	actions.append({"type": "system_message", "text": "已回购：%s" % nm})
	return {"ok": true, "actions": actions, "item_id": iid, "qty": take, "paid": total}


func try_inventory_split(item_id: String, qty: int) -> Dictionary:
	var actions: Array = []
	if inventory == null or not inventory.has_method("try_split"):
		return {"ok": false, "reason": "no_inv", "actions": actions}
	item_id = item_id.strip_edges()
	var r: Dictionary = inventory.try_split(item_id, qty)
	if not bool(r.get("ok", false)):
		var why := str(r.get("reason", ""))
		var msg := "无法拆分。"
		if why == "bag_full":
			msg = "背包已满，无法拆分。"
		elif why == "too_small":
			msg = "数量不足，无法拆分。"
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": why, "actions": actions}
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}


func try_inventory_sort() -> Dictionary:
	var actions: Array = []
	if inventory == null or not inventory.has_method("sort_stacks"):
		return {"ok": false, "reason": "no_inv", "actions": actions}
	inventory.sort_stacks()
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}


func try_inventory_lock(item_id: String, on: bool) -> Dictionary:
	var actions: Array = []
	if inventory == null or not inventory.has_method("set_locked"):
		return {"ok": false, "reason": "no_inv", "actions": actions}
	inventory.set_locked(item_id, on)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}



## --- Ground bags + loot UI (bag-backed; close keeps items) ---

func snapshot_ground_bags() -> Array:
	return _loot_module_logic.snapshot_ground_bags()
func ground_bag_count() -> int:
	return _loot_module_logic.ground_bag_count()
func get_ground_bag(bag_id: String) -> Dictionary:
	return _loot_module_logic.get_ground_bag(bag_id)
## Compatibility: true when an open loot UI session has remaining items.
func has_pending_loot() -> bool:
	return _loot_module_logic.has_pending_loot()
func pending_loot_snapshot() -> Dictionary:
	return _loot_module_logic.pending_loot_snapshot()
## Clock used for ground bag created_at / party-loot free TTL (same as spawn).
func _ground_bag_now() -> float:
	return _loot_module_logic._ground_bag_now()
## True when bag owner_id blocks the local player (non-empty, not self, within 60s).
func _bag_loot_owner_blocks(bag: Dictionary) -> bool:
	return _loot_module_logic._bag_loot_owner_blocks(bag)
func _bag_loot_owner_fail_msg(bag: Dictionary) -> String:
	return _loot_module_logic._bag_loot_owner_fail_msg(bag)
## Public: whether local player may open/take from this bag (auto-pickup uses this).
func can_loot_ground_bag(bag_id: String) -> bool:
	return _loot_module_logic.can_loot_ground_bag(bag_id)
## Open loot UI for a ground bag when player is on/adjacent to its cell.
func try_open_ground_bag(bag_id: String) -> Dictionary:
	return _loot_module_logic.try_open_ground_bag(bag_id)
## Find bag id at cell (merged bags: one per cell).
func find_ground_bag_at(x: int, y: int) -> String:
	return _loot_module_logic.find_ground_bag_at(x, y)
## True when catalog marks item bind-on-pickup (BoP).
func _item_binds_on_pickup(item_id: String) -> bool:
	if item_catalog == null:
		return false
	var def: Dictionary = item_catalog.get_item(item_id.strip_edges())
	return Equipment.is_bind_on_pickup(def)


## Add looted/rewarded items; BoP stacks enter bag already bound.
func _try_add_loot_item(item_id: String, qty: int) -> Dictionary:
	return _loot_module_logic._try_add_loot_item(item_id, qty)
## Take one stack from the open ground bag. qty<=0 means all of that item_id.
func try_loot_take(item_id: String, qty: int = -1) -> Dictionary:
	return _loot_module_logic.try_loot_take(item_id, qty)
func try_loot_take_all() -> Dictionary:
	return _loot_module_logic.try_loot_take_all()
## Close loot UI only — ground bag remains until emptied or map change.
func try_loot_close() -> Dictionary:
	return _loot_module_logic.try_loot_close()
## Drop from inventory onto the ground at the player's cell (merge same-cell bag).
func try_drop_item(item_id: String, qty: int = 1) -> Dictionary:
	item_id = item_id.strip_edges()
	var actions: Array = []
	if inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inventory", "actions": actions}
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory.has_method("is_locked") and inventory.is_locked(item_id):
		actions.append({"type": "system_message", "text": "该物品已锁定，无法丢弃。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if not inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	if not inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "丢弃失败。"})
		return {"ok": false, "reason": "consume_failed", "actions": actions}
	var cell := {"x": player_cell.x, "y": player_cell.y}
	var bag_actions: Array = _add_items_to_ground(cell, [{"item_id": item_id, "qty": qty}], "player", "")
	actions.append_array(bag_actions)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "扔下了 %s×%d" % [item_display_name(item_id), qty],
	})
	return {"ok": true, "item_id": item_id, "qty": qty, "actions": actions}


## Unequip paperdoll slot and drop the item onto the ground (not into bag).
func try_drop_equipped(slot: String) -> Dictionary:
	slot = slot.strip_edges()
	var actions: Array = []
	if equipment == null:
		actions.append({"type": "system_message", "text": "装备不可用。"})
		return {"ok": false, "reason": "no_equipment", "actions": actions}
	if slot.is_empty():
		actions.append({"type": "system_message", "text": "无效栏位。"})
		return {"ok": false, "reason": "invalid_slot", "actions": actions}
	var r: Dictionary = equipment.try_unequip(slot)
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", "fail"))
		var msg := "无法丢弃装备。"
		match reason:
			"empty":
				msg = "该栏位没有装备。"
			"invalid_slot":
				msg = "无效栏位。"
			_:
				msg = "无法丢弃装备（%s）。" % reason
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var iid := str(r.get("item_id", "")).strip_edges()
	if iid.is_empty():
		actions.append({"type": "system_message", "text": "无效物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var cell := {"x": player_cell.x, "y": player_cell.y}
	actions.append_array(_add_items_to_ground(cell, [{"item_id": iid, "qty": 1}], "player", ""))
	actions.append(_equipment_update_action())
	actions.append({
		"type": "system_message",
		"text": "扔下了 %s×1" % item_display_name(iid),
	})
	return {"ok": true, "item_id": iid, "slot": slot, "qty": 1, "actions": actions}


func _open_bag_items() -> Array:
	if _open_loot_bag_id.is_empty() or not _ground_bags.has(_open_loot_bag_id):
		return []
	var items_v: Variant = _ground_bags[_open_loot_bag_id].get("items", [])
	return items_v if typeof(items_v) == TYPE_ARRAY else []



func _item_icon_fields(item_id: String) -> Dictionary:
	var out := {"icon_index": -1}
	if item_catalog == null or item_id.strip_edges().is_empty():
		return out
	var def: Dictionary = item_catalog.get_item(item_id)
	if def.is_empty():
		return out
	out["icon_index"] = int(def.get("icon_index", -1))
	var ic := str(def.get("icon", "")).strip_edges()
	if not ic.is_empty():
		out["icon"] = ic
	var iref := str(def.get("icon_ref", "")).strip_edges()
	if iref.is_empty() and not ic.is_empty():
		iref = "content://icon/%s" % ic
	if not iref.is_empty():
		out["icon_ref"] = iref
	return out


func _open_bag_items_dup() -> Array:
	var out: Array = []
	for d_v in _open_bag_items():
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = d_v
		var iid := str(d.get("item_id", "")).strip_edges()
		var q: int = int(d.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		var row := {"item_id": iid, "qty": q, "name": item_display_name(iid)}
		row.merge(_item_icon_fields(iid))
		out.append(row)
	return out


func _bag_items_dup(bag_id: String) -> Array:
	return _loot_module_logic._bag_items_dup(bag_id)
func _bag_snapshot(bag_id: String) -> Dictionary:
	return _loot_module_logic._bag_snapshot(bag_id)
func _loot_update_action() -> Dictionary:
	return _loot_module_logic._loot_update_action()
func _loot_open_action() -> Dictionary:
	return _loot_module_logic._loot_open_action()
func _ground_spawn_action(bag_id: String) -> Dictionary:
	return _loot_module_logic._ground_spawn_action(bag_id)
func _ground_update_action(bag_id: String) -> Dictionary:
	return {"type": "ground_update", "bag": _bag_snapshot(bag_id)}


func _remove_ground_bag(bag_id: String, actions: Array) -> void:
	_loot_module_logic._remove_ground_bag(bag_id, actions)
func _player_adjacent_or_on(x: int, y: int) -> bool:
	if player_cell.x <= -9990:
		return true  # shell tests without placed player
	var dist: int = absi(player_cell.x - x) + absi(player_cell.y - y)
	return dist <= 1


func _merge_item_into_list(items: Array, item_id: String, qty: int) -> void:
	for i in range(items.size()):
		var pe: Dictionary = items[i]
		if str(pe.get("item_id", "")) == item_id:
			pe["qty"] = int(pe.get("qty", 0)) + qty
			items[i] = pe
			return
	items.append({"item_id": item_id, "qty": qty})


## Add items to ground at cell (merge same-cell bag). Appends ground_spawn/update actions.
## owner_id empty = free-for-all. Merge keeps existing bag owner_id.
func _add_items_to_ground(cell: Dictionary, add_items: Array, source: String, npc_id: String = "", owner_id: String = "") -> Array:
	var actions: Array = []
	var cx: int = int(cell.get("x", 0))
	var cy: int = int(cell.get("y", 0))
	var existing_id := find_ground_bag_at(cx, cy)
	var created_at: float = 0.0
	if combat_stats != null and combat_stats.has_method("now_sec"):
		created_at = float(combat_stats.now_sec())
	else:
		created_at = float(Time.get_ticks_msec()) / 1000.0
	owner_id = str(owner_id).strip_edges()
	if existing_id != "":
		var bag: Dictionary = _ground_bags[existing_id]
		var items_v: Variant = bag.get("items", [])
		var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
		for d_v in add_items:
			if typeof(d_v) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = d_v
			var iid := str(d.get("item_id", "")).strip_edges()
			var q: int = int(d.get("qty", 0))
			if iid.is_empty() or q <= 0:
				continue
			_merge_item_into_list(items, iid, q)
		bag["items"] = items
		if npc_id != "" and str(bag.get("npc_id", "")) == "":
			bag["npc_id"] = npc_id
		_ground_bags[existing_id] = bag
		actions.append(_ground_update_action(existing_id))
		return actions
	_bag_seq += 1
	var bid := "bag_%d" % _bag_seq
	var pending_items: Array = []
	for d_v2 in add_items:
		if typeof(d_v2) != TYPE_DICTIONARY:
			continue
		var d2: Dictionary = d_v2
		var iid2 := str(d2.get("item_id", "")).strip_edges()
		var q2: int = int(d2.get("qty", 0))
		if iid2.is_empty() or q2 <= 0:
			continue
		_merge_item_into_list(pending_items, iid2, q2)
	if pending_items.is_empty():
		return actions
	_ground_bags[bid] = {
		"id": bid,
		"cell": {"x": cx, "y": cy},
		"items": pending_items,
		"source": source,
		"owner_id": owner_id,
		"npc_id": npc_id,
		"created_at": created_at,
	}
	actions.append(_ground_spawn_action(bid))
	return actions


## Softcore death-drop rules (tune here):
## - Gold: 5-15% of wallet (int, min 0). Spent gold becomes rusty_coin stacks in the
##   ground bag so the existing item loot pipeline can reclaim it (1 coin ~= 1G sell).
## - Items: drop 1-3 random eligible bag stacks. Prefer consumable / misc / material;
##   never equipment/weapon/armor types; never locked / quest-type items.
##   Partial stacks OK (drop ~half when qty>1, always leave >=1 in that stack when possible).
## - Softcore: never empty the entire bag — always keep >=1 stack if the bag had any
##   eligible/remaining stacks after selection. Equipped paperdoll is never touched.
## - Called once on first death from _finalize_combat_result alongside
##   _clear_pending_loot_on_death (UI close only). Death drops are a NEW bag from
##   inventory, not clearing previous pending loot.
func _death_drop_roll() -> float:
	if death_drop_randf.is_valid():
		return clampf(float(death_drop_randf.call()), 0.0, 0.999999)
	return randf()


func _death_drop_item_pref(item_id: String) -> int:
	## Lower = preferred for drop. Equipment / quest excluded by caller.
	var t := ""
	if item_catalog != null and item_catalog.has_method("get_item"):
		var def: Dictionary = item_catalog.get_item(item_id)
		t = str(def.get("type", "")).strip_edges().to_lower()
	match t:
		"consumable", "potion":
			return 0
		"misc":
			return 1
		"material":
			return 2
		_:
			return 3


func _death_drop_type_blocked(item_id: String) -> bool:
	var t := ""
	if item_catalog != null and item_catalog.has_method("get_item"):
		var def: Dictionary = item_catalog.get_item(item_id)
		t = str(def.get("type", "")).strip_edges().to_lower()
	return t in ["equipment", "weapon", "armor", "equip", "quest"]


func _apply_death_drops(actions: Array) -> void:
	if inventory == null:
		return
	var dropped_items: Array = []  # [{item_id, qty}, ...]
	var gold_lost := 0
	# --- gold ---
	var wallet: int = inventory.get_gold()
	if wallet > 0:
		var pct: int = 5 + int(_death_drop_roll() * 11.0)  # 5..15
		gold_lost = int(floor(float(wallet) * float(pct) / 100.0))
		gold_lost = clampi(gold_lost, 0, wallet)
		if gold_lost > 0 and inventory.try_spend_gold(gold_lost):
			dropped_items.append({"item_id": "rusty_coin", "qty": gold_lost})
		else:
			gold_lost = 0
	# --- bag stacks ---
	var candidates: Array = []  # {id, qty, pref}
	for row_v in inventory.snapshot():
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var iid := str(row.get("id", "")).strip_edges()
		var q: int = int(row.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		if inventory.has_method("is_locked") and inventory.is_locked(iid):
			continue
		if bool(row.get("locked", false)):
			continue
		if _death_drop_type_blocked(iid):
			continue
		candidates.append({"id": iid, "qty": q, "pref": _death_drop_item_pref(iid)})
	candidates.sort_custom(func(a, b):
		var pa: int = int(a.get("pref", 99))
		var pb: int = int(b.get("pref", 99))
		if pa != pb:
			return pa < pb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	# Softcore: never empty the entire bag — keep at least one stack.
	var max_picks: int = 1 + int(_death_drop_roll() * 3.0)  # 1..3
	if candidates.size() > 1:
		max_picks = mini(max_picks, candidates.size() - 1)
	elif candidates.size() == 1:
		# Only one eligible stack: allow partial drop only (leave >=1).
		max_picks = 1
	else:
		max_picks = 0
	var picked := 0
	var used_ids: Dictionary = {}
	while picked < max_picks and not candidates.is_empty():
		# Weighted toward preferred: pick among first half of remaining list.
		var pool_n: int = maxi(1, int(ceil(float(candidates.size()) * 0.5)))
		var idx: int = int(_death_drop_roll() * float(pool_n))
		idx = clampi(idx, 0, candidates.size() - 1)
		var cand: Dictionary = candidates[idx]
		candidates.remove_at(idx)
		var cid := str(cand.get("id", ""))
		if cid.is_empty() or used_ids.has(cid):
			continue
		var have: int = int(cand.get("qty", 0))
		if have <= 0:
			continue
		var drop_qty: int = have
		if have > 1:
			drop_qty = maxi(1, int(ceil(float(have) * 0.5)))
			# Softcore: never take the last unit of the last remaining stack.
			if candidates.is_empty() and inventory.slot_count() <= 1:
				drop_qty = mini(drop_qty, have - 1)
			var leave_one: bool = candidates.is_empty() and inventory.slot_count() <= 1
			drop_qty = clampi(drop_qty, 1, have - (1 if leave_one else 0))
			if drop_qty <= 0:
				continue
		else:
			# qty==1: only drop if another stack will remain in bag.
			if inventory.slot_count() <= 1 and candidates.is_empty():
				continue
		if not inventory.has_item(cid, drop_qty):
			continue
		if not inventory.consume(cid, drop_qty):
			continue
		dropped_items.append({"item_id": cid, "qty": drop_qty})
		used_ids[cid] = true
		picked += 1
	if dropped_items.is_empty():
		return
	var cell := {"x": death_cell.x, "y": death_cell.y}
	if death_cell.x <= -9990:
		cell = {"x": player_cell.x, "y": player_cell.y}
	actions.append_array(_add_items_to_ground(cell, dropped_items, "death", ""))
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "你损失了部分物品/金币。"})


## Close open loot UI on death; ground bags persist.
func _clear_pending_loot_on_death(actions: Array) -> void:
	_loot_module_logic._clear_pending_loot_on_death(actions)
func _quest_update_action() -> Dictionary:
	var a := {
		"type": "quest_update",
		"quests": quest_journal.snapshot() if quest_journal != null else [],
	}
	if quest_journal != null and quest_journal.has_method("snapshot_daily"):
		var d: Dictionary = quest_journal.snapshot_daily()
		a["daily_date"] = str(d.get("daily_date", ""))
		a["daily"] = d.get("daily", []) if typeof(d.get("daily", [])) == TYPE_ARRAY else []
	return a


func try_daily_board_list() -> Array:
	if quest_journal == null:
		return []
	if quest_journal.has_method("try_daily_board_list"):
		return quest_journal.try_daily_board_list()
	return []


func snapshot_daily() -> Dictionary:
	if quest_journal != null and quest_journal.has_method("snapshot_daily"):
		return quest_journal.snapshot_daily()
	return {"daily_date": "", "daily": []}


func _quest_note_kill_actions(npc_id: String) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_kill(npc_id):
		actions.append(_quest_update_action())
	return actions


func _quest_note_talk_actions(npc_id: String) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_talk(npc_id):
		actions.append(_quest_update_action())
	return actions


func _quest_note_item_actions(item_id: String, qty: int) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_item_gain(item_id, qty):
		actions.append(_quest_update_action())
	return actions



func _quest_note_fish_actions(item_id: String = "", qty: int = 1) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.has_method("note_fish") and quest_journal.note_fish(item_id, qty):
		actions.append(_quest_update_action())
	return actions


func _quest_note_reach_actions(map_id: String, content_id: String = "", pack_path: String = "") -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_reach(map_id, content_id, pack_path):
		actions.append(_quest_update_action())
	return actions


## Party food share (MockServer shell): local-only buff OK.
## Items with party_share + nested status: solo uses catalog duration;
## in_party and same-map N>1 → re-apply status at party_duration and emit party_buff + morale msg.
func _maybe_party_food_share(item_id: String, result: Dictionary) -> void:
	_party_module_logic._maybe_party_food_share(item_id, result)
## Party skill share (MockServer shell): local-only buff OK — mirrors party food share.
## Skills with party_share + nested status: solo uses catalog duration;
## in_party and same-map N>1 → re-apply status at party_duration and emit party_buff + share msg.
func _maybe_party_skill_share(skill_id: String, result: Dictionary) -> void:
	_party_module_logic._maybe_party_skill_share(skill_id, result)
## Party quest share eligible: grouped with ≥1 other online same-map member.
## Shell remotes/stubs have no journals — share means ally credit advances local journal.
func _party_quest_share_eligible() -> bool:
	return _party_module_logic._party_quest_share_eligible()
func _party_quest_share_result(changed: bool) -> Array:
	return _party_module_logic._party_quest_share_result(changed)
## Simulate an online same-map ally kill advancing local kill objectives.
## Player kills stay on the normal `_quest_note_kill_actions` path (no double credit).
## Tests / shell call this to credit ally kills. No-op when not share-eligible.
func note_party_kill(npc_kind: String) -> Array:
	return _party_module_logic.note_party_kill(npc_kind)
## Ally gather credit → local gather/item objectives (same eligibility as note_party_kill).
func note_party_gather(gather_id: String, qty: int = 1) -> Array:
	return _party_module_logic.note_party_gather(gather_id, qty)
## Ally fish credit → local fish objectives (same eligibility as note_party_kill).
func note_party_fish(item_id: String = "", qty: int = 1) -> Array:
	return _party_module_logic.note_party_fish(item_id, qty)
## Item catalog lookup helper for HUD labels.
func item_display_name(item_id: String) -> String:
	if item_catalog == null:
		return item_id
	var def: Dictionary = item_catalog.get_item(item_id)
	if def.is_empty():
		return item_id
	return str(def.get("name", item_id))


func logout() -> void:
	_session_user = ""
	_session_server = ""
	_session_character_id = ""


## NPC AI tick: hostiles idle/chase/return_home; friendlies with wander_radius idle-wander only.
func _tick_mob_ai(dt: float) -> Array:
	var actions: Array = []
	if combat_stats == null:
		return actions
	if not combat_stats.player_alive():
		# Drop chase when player is dead → evade / return home.
		for nid in combat_stats.npc_ai.keys():
			var aid: Dictionary = combat_stats.npc_ai[nid]
			if str(aid.get("chase_target", "")) != "" or str(aid.get("ai_state", "")) == MobAI.AI_CHASE:
				actions.append_array(_evade_npc(str(nid)))
		# Still process return_home / idle below? Player dead — continue for return/idle.
	var px: int = player_cell.x
	var py: int = player_cell.y
	var player_ok: bool = combat_stats.player_alive() and px > -9990
	# Snapshot keys — AI may erase on death elsewhere.
	var ids: Array = combat_stats.npc_ai.keys()
	for npc_id_v in ids:
		var npc_id: String = str(npc_id_v)
		if not combat_stats.npcs.has(npc_id):
			continue
		var st: Dictionary = combat_stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0:
			continue
		# Non-hostile (friendly wanderers): idle roam only — no chase / leash / vision.
		if not bool(st.get("hostile", false)):
			actions.append_array(_mob_ai_idle_wander_step(npc_id, dt))
			continue
		var ai: Dictionary = combat_stats.npc_ai[npc_id]
		var cell: Vector2i = combat_stats.get_npc_cell(npc_id)
		if cell.x <= -9990:
			continue
		var facing: int = int(ai.get("facing", 2))
		var state: String = str(ai.get("ai_state", MobAI.AI_IDLE))
		var home: Vector2i = MobAI.get_home_cell(ai)
		var wander_r: int = maxi(int(ai.get("wander_radius", 0)), 0)
		var in_vision: bool = false
		var player_stealthed := false
		if player_ok and combat_stats.statuses != null:
			player_stealthed = combat_stats.statuses.has_status("player", "stealth")
		if player_ok and not player_stealthed:
			in_vision = MobAI.player_in_vision(cell, facing, player_cell, map_collision)
		var chasing: bool = str(ai.get("chase_target", "")) != "" or state == MobAI.AI_CHASE
		var can_aggro: bool = MobAI.wants_chase(ai) and not player_stealthed

		# Leash reset in progress: no re-aggro / no chase until home (do not attack).
		if state == MobAI.AI_RETURN_HOME:
			var home_only: Array = _mob_ai_return_home_step(npc_id, ai, cell, home)
			actions.append_array(home_only)
			continue

		# Stealth: treat as invisible — break existing chase / no new aggro.
		if player_stealthed and chasing and player_ok:
			actions.append_array(_evade_npc(npc_id))
			ai = combat_stats.npc_ai[npc_id]
			state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
			chasing = false

		# Safe zone: no new aggro; break existing chase when player is inside.
		var player_safe := player_in_safe_zone()
		if player_safe and chasing and player_ok:
			actions.append_array(_evade_npc(npc_id))
			ai = combat_stats.npc_ai[npc_id]
			state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
			chasing = false
		# --- Aggro / lose-sight (only while player alive & outside safe zone) ---
		elif player_ok and (not player_safe) and can_aggro and in_vision:
			var tid := "player"
			if _session_character_id != "":
				tid = _session_character_id
			if combat_stats.has_method("select_victim"):
				var hv: String = combat_stats.select_victim(npc_id)
				if hv != "":
					tid = hv
			elif combat_stats.has_method("highest_threat_target"):
				var ht: String = combat_stats.highest_threat_target(npc_id)
				if ht != "":
					tid = ht
			ai["victim_id"] = tid
			ai["chase_target"] = tid
			ai["lose_sight_sec"] = 0.0
			ai["no_target_sec"] = 0.0
			ai["seen_target"] = true
			ai["ai_state"] = MobAI.AI_CHASE
			ai["idle_wander_acc"] = 0.0
			chasing = true
			state = MobAI.AI_CHASE
			facing = MobAI.facing_toward(cell, player_cell)
			ai["facing"] = facing
			combat_stats.npc_ai[npc_id] = ai
		elif chasing and player_ok:
			if in_vision:
				ai["lose_sight_sec"] = 0.0
				ai["seen_target"] = true
			else:
				# Pack assist / hit-from-behind start chase off-vision — do not
				# accumulate lose-sight until the mob has actually seen the player.
				if bool(ai.get("seen_target", false)):
					ai["lose_sight_sec"] = float(ai.get("lose_sight_sec", 0.0)) + dt
			if float(ai.get("lose_sight_sec", 0.0)) >= MobAI.LOSE_SIGHT_SEC:
				actions.append_array(_evade_npc(npc_id))
				# Fall through this tick into return_home / idle after clear.
				ai = combat_stats.npc_ai[npc_id]
				state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
				chasing = false
			else:
				ai["ai_state"] = MobAI.AI_CHASE
				combat_stats.npc_ai[npc_id] = ai
				state = MobAI.AI_CHASE

		# Home leash + no-valid-target: while chasing → evade / return_home.
		if chasing:
			ai = combat_stats.npc_ai[npc_id]
			home = MobAI.get_home_cell(ai)
			var leash_r: int = int(ai.get("leash_radius", MobAI.DEFAULT_LEASH_RADIUS))
			var engage_r: int = leash_r if leash_r >= 0 else MobAI.DEFAULT_ENGAGE_RANGE
			engage_r = maxi(engage_r, MobAI.DEFAULT_ENGAGE_RANGE)
			var target_ok: bool = player_ok and MobAI.target_in_engage_range(
				cell, player_cell, engage_r
			)
			if target_ok:
				ai["no_target_sec"] = 0.0
			else:
				ai["no_target_sec"] = float(ai.get("no_target_sec", 0.0)) + dt
			combat_stats.npc_ai[npc_id] = ai
			var no_tgt: bool = float(ai.get("no_target_sec", 0.0)) >= MobAI.NO_VALID_TARGET_SEC
			if MobAI.beyond_leash(cell, home, leash_r) or no_tgt:
				actions.append_array(_evade_npc(npc_id))
				ai = combat_stats.npc_ai[npc_id]
				state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
				chasing = false

		# Re-read state after possible clear_chase.
		ai = combat_stats.npc_ai[npc_id]
		state = str(ai.get("ai_state", MobAI.AI_IDLE))
		facing = int(ai.get("facing", facing))
		home = MobAI.get_home_cell(ai)
		wander_r = maxi(int(ai.get("wander_radius", 0)), 0)

		# Refresh sticky victim each AI tick while chasing (tank / multi-hate).
		if state == MobAI.AI_CHASE and combat_stats.has_method("select_victim"):
			var prev_victim := str(ai.get("victim_id", ""))
			var sv: String = combat_stats.select_victim(npc_id)
			ai = combat_stats.npc_ai[npc_id]
			if sv != "":
				ai["chase_target"] = sv
				combat_stats.npc_ai[npc_id] = ai
			var new_victim := str(ai.get("victim_id", sv))
			if new_victim != prev_victim:
				actions.append(_threat_update_action(npc_id))
			state = str(ai.get("ai_state", state))
		if state == MobAI.AI_CHASE and str(ai.get("chase_target", "")) != "" and player_ok:
			var chase_acts: Array = _mob_ai_chase_step(npc_id, ai, cell, facing, px, py)
			actions.append_array(chase_acts)
			continue

		if state == MobAI.AI_RETURN_HOME:
			var home_acts: Array = _mob_ai_return_home_step(npc_id, ai, cell, home)
			actions.append_array(home_acts)
			continue

		# Idle: wander_radius 0 → stand still; else low-frequency roam within radius.
		if state != MobAI.AI_IDLE:
			ai["ai_state"] = MobAI.AI_IDLE
			combat_stats.npc_ai[npc_id] = ai
		actions.append_array(_mob_ai_idle_wander_step(npc_id, dt))
	return actions


## Shared idle roam for hostiles and friendlies with wander_radius > 0.
func _mob_ai_idle_wander_step(npc_id: String, dt: float) -> Array:
	var actions: Array = []
	if combat_stats == null or not combat_stats.npc_ai.has(npc_id):
		return actions
	var ai: Dictionary = combat_stats.npc_ai[npc_id]
	var cell: Vector2i = combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return actions
	var home: Vector2i = MobAI.get_home_cell(ai)
	var wander_r: int = maxi(int(ai.get("wander_radius", 0)), 0)
	if wander_r <= 0:
		return actions
	ai["idle_wander_acc"] = float(ai.get("idle_wander_acc", 0.0)) + dt
	if float(ai.get("idle_wander_acc", 0.0)) < MobAI.IDLE_WANDER_INTERVAL_SEC:
		combat_stats.npc_ai[npc_id] = ai
		return actions
	ai["idle_wander_acc"] = 0.0
	var wdir: int = MobAI.next_idle_wander_dir(map_collision, cell, home, wander_r)
	combat_stats.npc_ai[npc_id] = ai
	if wdir == 0:
		return actions
	var wm: Dictionary = try_npc_move(npc_id, cell.x, cell.y, wdir)
	if bool(wm.get("ok", false)):
		ai["facing"] = wdir
		combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": int(wm.get("x", cell.x)),
			"y": int(wm.get("y", cell.y)),
			"facing": wdir,
		})
	return actions


func _mob_ai_chase_step(npc_id: String, ai: Dictionary, cell: Vector2i, facing: int, px: int, py: int) -> Array:
	var actions: Array = []
	var skill_acts: Array = _try_npc_skill_tick(npc_id, ai, cell, px, py)
	if not skill_acts.is_empty():
		return skill_acts
	var man: int = maxi(absi(cell.x - px), absi(cell.y - py))
	if man <= 1:
		var face: int = MobAI.facing_toward(cell, player_cell)
		if face != facing:
			ai["facing"] = face
			combat_stats.npc_ai[npc_id] = ai
			actions.append({
				"type": "npc_move",
				"npc_id": npc_id,
				"x": cell.x,
				"y": cell.y,
				"facing": face,
			})
		return actions
	if _npc_is_rooted(npc_id):
		var face_r: int = MobAI.facing_toward(cell, player_cell)
		if face_r != int(ai.get("facing", 2)):
			ai["facing"] = face_r
			combat_stats.npc_ai[npc_id] = ai
			actions.append({
				"type": "npc_move",
				"npc_id": npc_id,
				"x": cell.x,
				"y": cell.y,
				"facing": face_r,
			})
		return actions
	var step_dir: int = MobAI.next_chase_dir(map_collision, cell, player_cell)
	if step_dir == 0:
		var face2: int = MobAI.facing_toward(cell, player_cell)
		if face2 != int(ai.get("facing", 2)):
			ai["facing"] = face2
			combat_stats.npc_ai[npc_id] = ai
			actions.append({
				"type": "npc_move",
				"npc_id": npc_id,
				"x": cell.x,
				"y": cell.y,
				"facing": face2,
			})
		return actions
	var moved: Dictionary = try_npc_move(npc_id, cell.x, cell.y, step_dir)
	if bool(moved.get("ok", false)):
		ai["facing"] = step_dir
		combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": int(moved.get("x", cell.x)),
			"y": int(moved.get("y", cell.y)),
			"facing": step_dir,
		})
	else:
		var face3: int = MobAI.facing_toward(cell, player_cell)
		ai["facing"] = face3
		combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": cell.x,
			"y": cell.y,
			"facing": face3,
		})
	return actions


func _try_npc_skill_tick(npc_id: String, ai: Dictionary, cell: Vector2i, px: int, py: int) -> Array:
	var skills_v: Variant = ai.get("skills", [])
	if typeof(skills_v) != TYPE_ARRAY or (skills_v as Array).is_empty():
		return []
	if combat_engine == null or skill_catalog == null or combat_stats == null:
		return []
	if combat_engine.has_method("is_npc_casting") and combat_engine.is_npc_casting(npc_id):
		return []
	var ready_v: Variant = ai.get("skill_ready_at", {})
	var ready: Dictionary = ready_v if typeof(ready_v) == TYPE_DICTIONARY else {}
	var now: float = combat_stats.now_sec()
	for sid_v in skills_v:
		var sid := str(sid_v).strip_edges()
		if sid.is_empty():
			continue
		if now < float(ready.get(sid, 0.0)):
			continue
		var def: Dictionary = skill_catalog.get_skill(sid)
		if def.is_empty():
			continue
		var rng: int = int(def.get("range", 1))
		if rng <= 0:
			rng = 1
		if maxi(absi(cell.x - px), absi(cell.y - py)) > rng:
			continue
		var r: Dictionary = try_npc_skill(npc_id, sid, px, py)
		if not bool(r.get("ok", false)):
			continue
		var cd: float = float(def.get("cooldown", 3.0))
		ready[sid] = now + maxf(cd, 0.4)
		ai["skill_ready_at"] = ready
		combat_stats.npc_ai[npc_id] = ai
		var acts_v: Variant = r.get("actions", [])
		return acts_v if typeof(acts_v) == TYPE_ARRAY else []
	combat_stats.npc_ai[npc_id] = ai
	return []


func _mob_ai_return_home_step(npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i) -> Array:
	var actions: Array = []
	if home.x <= -9990:
		ai["ai_state"] = MobAI.AI_IDLE
		ai["return_stuck_ticks"] = 0
		combat_stats.npc_ai[npc_id] = ai
		return actions
	if cell == home:
		ai["ai_state"] = MobAI.AI_IDLE
		ai["idle_wander_acc"] = 0.0
		ai["return_stuck_ticks"] = 0
		combat_stats.npc_ai[npc_id] = ai
		return actions
	var dist_before: int = MobAI.chebyshev(cell, home)
	var step_dir: int = MobAI.next_home_dir(map_collision, cell, home)
	if step_dir == 0:
		return _mob_ai_return_home_stuck_or_face(npc_id, ai, cell, home, actions)
	var moved: Dictionary = try_npc_move(npc_id, cell.x, cell.y, step_dir)
	if bool(moved.get("ok", false)):
		var nx: int = int(moved.get("x", cell.x))
		var ny: int = int(moved.get("y", cell.y))
		var dest := Vector2i(nx, ny)
		var dist_after: int = MobAI.chebyshev(dest, home)
		ai["facing"] = step_dir
		# Strict improvement on best distance-to-home clears stuck; oscillation does not.
		var best: int = int(ai.get("return_best_dist", 99999))
		if dist_after < best:
			ai["return_best_dist"] = dist_after
			ai["return_stuck_ticks"] = 0
		else:
			ai["return_stuck_ticks"] = int(ai.get("return_stuck_ticks", 0)) + 1
			if int(ai.get("return_stuck_ticks", 0)) >= MobAI.RETURN_STUCK_TICKS:
				combat_stats.npc_ai[npc_id] = ai
				return _mob_ai_teleport_home(npc_id, ai, dest, home, actions)
		if dest == home:
			ai["ai_state"] = MobAI.AI_IDLE
			ai["idle_wander_acc"] = 0.0
			ai["return_stuck_ticks"] = 0
		combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": nx,
			"y": ny,
			"facing": step_dir,
		})
	else:
		return _mob_ai_return_home_stuck_or_face(npc_id, ai, cell, home, actions)
	return actions


## Increment stuck counter; teleport snap to home after RETURN_STUCK_TICKS, else face home.
func _mob_ai_return_home_stuck_or_face(
	npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i, actions: Array
) -> Array:
	var stuck: int = int(ai.get("return_stuck_ticks", 0)) + 1
	ai["return_stuck_ticks"] = stuck
	if stuck >= MobAI.RETURN_STUCK_TICKS:
		return _mob_ai_teleport_home(npc_id, ai, cell, home, actions)
	var face: int = MobAI.facing_toward(cell, home)
	if face != int(ai.get("facing", 2)):
		ai["facing"] = face
		combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": cell.x,
			"y": cell.y,
			"facing": face,
		})
	else:
		combat_stats.npc_ai[npc_id] = ai
	return actions


## Snap NPC to home_cell (leash reset when path blocked / oscillating); emit npc_move; idle.
func _mob_ai_teleport_home(
	npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i, actions: Array
) -> Array:
	var dest := home
	if map_collision != null:
		if map_collision.has_method("is_valid") and not bool(map_collision.is_valid(home.x, home.y)):
			dest = cell
	if map_collision != null and cell != dest:
		if map_collision.has_method("set_extra_blocked"):
			map_collision.set_extra_blocked(cell.x, cell.y, false)
			map_collision.set_extra_blocked(dest.x, dest.y, true)
	combat_stats.set_npc_cell(npc_id, dest.x, dest.y)
	var face: int = int(ai.get("facing", 2))
	if cell != dest:
		face = MobAI.facing_toward(cell, dest)
	ai["facing"] = face
	ai["ai_state"] = MobAI.AI_IDLE
	ai["idle_wander_acc"] = 0.0
	ai["return_stuck_ticks"] = 0
	ai["return_best_dist"] = 99999
	combat_stats.npc_ai[npc_id] = ai
	actions.append({
		"type": "npc_move",
		"npc_id": npc_id,
		"x": dest.x,
		"y": dest.y,
		"facing": face,
		"teleport": true,
	})
	return actions

func _evade_npc(npc_id: String) -> Array:
	var actions: Array = []
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or combat_stats == null:
		return actions
	if not combat_stats.npc_ai.has(npc_id):
		return actions
	combat_stats.clear_chase(npc_id)
	if not combat_stats.npcs.has(npc_id):
		return actions
	var st: Dictionary = combat_stats.npcs[npc_id]
	var hp: int = int(st.get("hp", 0))
	var hp_max: int = int(st.get("hp_max", 0))
	actions.append({
		"type": "npc_reset",
		"npc_id": npc_id,
		"hp": hp,
		"hp_max": hp_max,
		"reason": "evade",
	})
	# Hate cleared — notify target HUD (threat_you false).
	actions.append(_threat_update_action(npc_id))
	return actions


## Roll loot table for dead npc; spawn/merge ground bag at death cell (never home_cell).
## death_cell: Dictionary {x,y} or Vector2i from kill_npc action; fallback player_cell.
func _roll_and_grant_loot(npc_id: String, death_cell: Variant = null) -> Array:
	return _loot_module_logic._roll_and_grant_loot(npc_id, death_cell)
## True when NPC cell is registered and within Chebyshev range_cells (8-dir).
func _require_npc_adjacent(npc_id: String, player_x: int, player_y: int, range_cells: int) -> bool:
	if combat_stats == null:
		return false
	var cell: Vector2i = combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return false
	var dist: int = maxi(absi(cell.x - player_x), absi(cell.y - player_y))
	return dist <= range_cells


func _maybe_mark_safe_cell(x: int, y: int) -> void:
	## Update last_safe when no registered hostile is adjacent.
	if combat_stats == null:
		last_safe_cell = Vector2i(x, y)
		return
	for npc_id in combat_stats.npc_cells.keys():
		if not combat_stats.npcs.has(npc_id):
			continue
		var st: Dictionary = combat_stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
			continue
		var c: Vector2i = combat_stats.npc_cells[npc_id]
		if absi(c.x - x) + absi(c.y - y) <= 1:
			return
	last_safe_cell = Vector2i(x, y)


## Build threat_update action from combat_stats.snapshot_threat.
func _threat_update_action(npc_id: String) -> Dictionary:
	npc_id = str(npc_id).strip_edges()
	var thr: Dictionary = snapshot_threat(npc_id)
	return {
		"type": "threat_update",
		"npc_id": npc_id,
		"threat_you": bool(thr.get("threat_you", false)),
		"threat_rank": int(thr.get("threat_rank", 0)),
		"threat_pct": float(thr.get("threat_pct", 0.0)),
		"victim_id": str(thr.get("victim_id", "")),
	}


## Append threat_update for NPCs touched by combat actions (damage / kill / set_stat npc).

## Personal DPS meter snapshot (combat_engine session window).
func snapshot_dps() -> Dictionary:
	if combat_engine != null and combat_engine.has_method("snapshot_dps"):
		return combat_engine.snapshot_dps()
	return {"type": "dps_update", "dps": 0.0, "total": 0, "elapsed": 0.0, "active": false}


func _tick_dps_meter(delta: float) -> void:
	if combat_engine == null or not combat_engine.has_method("tick_dps"):
		return
	var acts: Array = combat_engine.tick_dps(delta)
	if not acts.is_empty():
		_pending_tick_actions.append_array(acts)


func _append_threat_updates(actions: Array) -> void:
	var seen: Dictionary = {}
	# Skip if already present for an id.
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "threat_update":
			continue
		var eid := str(a.get("npc_id", a.get("id", ""))).strip_edges()
		if eid != "":
			seen[eid] = true
	var ids: Array = []
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t := str(a.get("type", ""))
		var nid := ""
		if t == "damage" and str(a.get("target", "")) == "npc":
			nid = str(a.get("id", "")).strip_edges()
		elif t == "kill_npc":
			nid = str(a.get("npc_id", "")).strip_edges()
		elif t == "set_stat" and str(a.get("target", "")) == "npc":
			nid = str(a.get("id", "")).strip_edges()
		elif t == "npc_reset":
			nid = str(a.get("npc_id", "")).strip_edges()
		if nid.is_empty() or seen.has(nid):
			continue
		seen[nid] = true
		ids.append(nid)
	for nid2 in ids:
		actions.append(_threat_update_action(nid2))


func _finalize_combat_result(result: Dictionary) -> Dictionary:
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	_append_threat_updates(actions)
	result["actions"] = actions
	# Schedule dead-mob respawn + loot + exp + quest kill when a hostile is removed.
	var kill_extra: Array = []
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "kill_npc":
			continue
		var kid := str(a.get("npc_id", ""))
		_schedule_npc_respawn(kid)
		var death_cell: Variant = a.get("cell", null)
		kill_extra.append_array(_roll_and_grant_loot(kid, death_cell))
		kill_extra.append_array(grant_kill_exp(kid))
		if _is_world_boss_npc(kid):
			_rewrite_kill_announce(actions, kid)
			kill_extra.append_array(_world_boss_kill_bonus(kid))
		kill_extra.append_array(_quest_note_kill_actions(kid))
		kill_extra.append_array(_note_title_counter("kills", 1))
		kill_extra.append_array(_note_achievement_counter("kills", 1))
		kill_extra.append_array(_dungeon_note_kill(kid))
	if not kill_extra.is_empty():
		actions.append_array(kill_extra)
		result["actions"] = actions
	if sitting:
		for a in actions:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var t := str(a.get("type", ""))
			if t == "damage" and str(a.get("target", a.get("id", ""))) == "player":
				_stand_if_sitting(actions)
				break
			if t == "player_died":
				sitting = false
				_sit_acc = 0.0
				_sit_regen_acc = 0.0
				break
	var newly_dead: bool = _actions_has_type(actions, "player_died") or (combat_stats != null and not combat_stats.player_alive())
	if newly_dead:
		var first_death: bool = not awaiting_respawn
		awaiting_respawn = true
		sitting = false
		_sit_acc = 0.0
		_sit_regen_acc = 0.0
		death_cell = player_cell
		if not _actions_has_type(actions, "system_message"):
			actions.append({"type": "system_message", "text": "你死了。"})
		# Close open loot UI only — does not remove inventory; death drops are separate.
		_clear_pending_loot_on_death(actions)
		if first_death:
			_apply_death_drops(actions)
			actions.append_array(_note_title_counter("deaths", 1))
			# Death equipment durability wear (combat hit wear is separate — see wear_weapon).
			if equipment != null and equipment.has_method("apply_death_wear"):
				var wear: Dictionary = equipment.apply_death_wear(0.1)
				if int(wear.get("count", 0)) > 0:
					actions.append({"type": "system_message", "text": "装备因死亡受损。"})
					actions.append(_equipment_update_action())
		result["actions"] = actions
		result["ok"] = true
	return result


func _actions_has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


## Respawn at town spawn or death cell; clear combat CDs server-side.
func _append_respawn_actions(actions: Array, where: String = "town") -> void:
	if combat_stats == null:
		return
	# Avoid double-append if already respawned in this action list.
	if _actions_has_type(actions, "respawn"):
		return
	where = where.strip_edges().to_lower()
	var dest: Vector2i = respawn_cell
	var here := where == "here" or where == "place"
	if here and death_cell.x > -9990:
		dest = death_cell
	elif dest.x <= -9990:
		dest = last_safe_cell
	if map_collision != null and map_collision.has_method("is_landable"):
		if not map_collision.is_landable(dest.x, dest.y) and map_collision.has_method("find_spawn_near"):
			dest = map_collision.find_spawn_near(dest.x, dest.y)
	elif map_collision != null and map_collision.has_method("find_spawn_near") and (dest.x <= -9990):
		dest = map_collision.find_spawn_near()
	_clear_pending_loot_on_death(actions)
	combat_stats.restore_after_death(here)
	if combat_engine != null and combat_engine.has_method("clear_cast"):
		combat_engine.clear_cast()
	set_player_cell(dest.x, dest.y)
	last_safe_cell = dest
	sitting = false
	var p: Dictionary = combat_stats.player
	actions.append({
		"type": "status_update",
		"target": "player",
		"statuses": [],
	})
	actions.append({
		"type": "respawn",
		"cell": {"x": dest.x, "y": dest.y},
		"hp": int(p.get("hp", 0)),
		"hp_max": int(p.get("hp_max", 0)),
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
		"input_lock_sec": 1.2,
	})
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(p.get("hp", 0)),
		"hp_max": int(p.get("hp_max", 0)),
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
	})
	if here:
		actions.append({"type": "system_message", "text": "你就地复活了。"})
	else:
		actions.append({"type": "system_message", "text": "你已在安全点复活。"})
	awaiting_respawn = false


func try_respawn(where: String = "town") -> Dictionary:
	var actions: Array = []
	if combat_stats != null and combat_stats.player_alive() and not awaiting_respawn:
		actions.append({"type": "system_message", "text": "你还活着。"})
		return {"ok": false, "reason": "alive", "actions": actions}
	awaiting_respawn = true
	_append_respawn_actions(actions, where)
	return {"ok": true, "actions": actions}


func try_recall() -> Dictionary:
	var actions: Array = []
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var dest: Vector2i = _town_dest()
	if sitting:
		_stand_if_sitting(actions)
	sitting = false
	_sit_acc = 0.0
	_sit_regen_acc = 0.0
	set_player_cell(dest.x, dest.y)
	actions.append({
		"type": "recall",
		"cell": {"x": dest.x, "y": dest.y},
	})
	actions.append({"type": "system_message", "text": "你回到了安全点。"})
	return {"ok": true, "actions": actions}


func try_sit(on: bool = true) -> Dictionary:
	var actions: Array = []
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if sitting == on:
		actions.append({"type": "sit", "on": sitting})
		return {"ok": true, "reason": "same", "actions": actions}
	sitting = on
	_sit_acc = 0.0
	_sit_regen_acc = 0.0
	actions.append({"type": "sit", "on": sitting})
	if sitting:
		actions.append({"type": "system_message", "text": "你坐了下来。"})
	else:
		actions.append({"type": "system_message", "text": "你站了起来。"})
	return {"ok": true, "actions": actions}


## Pay gold at inn: full HP/MP restore + clear harmful statuses.
func try_inn_rest(cost: int = 25) -> Dictionary:
	var actions: Array = []
	cost = maxi(int(cost), 0)
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if combat_stats == null:
		actions.append({"type": "system_message", "text": "无法休息。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	var p: Dictionary = combat_stats.player
	var hp_max: int = int(p.get("hp_max", 100))
	var mp_max: int = int(p.get("mp_max", 50))
	var hp: int = int(p.get("hp", 0))
	var mp: int = int(p.get("mp", 0))
	var has_harmful := false
	if combat_stats.statuses != null:
		for s in combat_stats.statuses.snapshot_statuses("player"):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var kind := str((s as Dictionary).get("kind", ""))
			if kind == "debuff" or kind == "dot":
				has_harmful = true
				break
	if hp >= hp_max and mp >= mp_max and not has_harmful:
		actions.append({"type": "system_message", "text": "你已经状态全满。"})
		return {"ok": false, "reason": "already_full", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if sitting:
		_stand_if_sitting(actions)
	p["hp"] = hp_max
	p["mp"] = mp_max
	combat_stats.player = p
	if combat_stats.statuses != null:
		combat_stats.statuses.clear_harmful("player")
		actions.append(combat_stats.statuses.status_update_action("player"))
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max,
	})
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "你休息得很好。"})
	return {"ok": true, "actions": actions}


## Repair equipped gear at blacksmith. slot ""/"all" = every damaged piece; cost_per_point gold/point.
func try_repair(slot: String = "", cost_per_point: int = 1) -> Dictionary:
	var actions: Array = []
	slot = str(slot).strip_edges()
	cost_per_point = maxi(int(cost_per_point), 0)
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var do_tools := slot.is_empty() or slot == "all" or slot == "tools"
	var do_equip := slot != "tools"
	if do_equip and equipment == null:
		actions.append({"type": "system_message", "text": "无法修理。"})
		return {"ok": false, "reason": "no_equipment", "actions": actions}
	# Preview costs so equip+tools can be paid atomically.
	var eq_points := 0
	var eq_targets: Array = []
	if do_equip and equipment != null:
		if slot.is_empty() or slot == "all":
			for sid in equipment.SLOT_IDS:
				if not equipment.is_empty(sid) and equipment.get_durability(sid) < equipment.get_durability_max(sid):
					eq_targets.append(sid)
					eq_points += equipment.get_durability_max(sid) - equipment.get_durability(sid)
		elif equipment.SLOT_IDS.has(slot):
			if equipment.is_empty(slot):
				actions.append({"type": "system_message", "text": "该部位没有装备。"})
				return {"ok": false, "reason": "empty", "actions": actions}
			if equipment.get_durability(slot) >= equipment.get_durability_max(slot):
				# May still repair tools if slot was tools-only path — not here.
				pass
			else:
				eq_targets.append(slot)
				eq_points += equipment.get_durability_max(slot) - equipment.get_durability(slot)
		else:
			actions.append({"type": "system_message", "text": "该部位没有装备。"})
			return {"ok": false, "reason": "invalid_slot", "actions": actions}
	var tool_prev: Dictionary = {}
	var tool_points := 0
	if do_tools and inventory.has_method("preview_tool_repair_full"):
		tool_prev = inventory.preview_tool_repair_full()
		if bool(tool_prev.get("ok", false)):
			tool_points = int(tool_prev.get("points", 0))
	var total_points := eq_points + tool_points
	if total_points <= 0:
		if slot == "tools":
			actions.append({"type": "system_message", "text": "工具无需修理。"})
		else:
			actions.append({"type": "system_message", "text": "装备无需修理。"})
		return {"ok": false, "reason": "nothing_to_repair", "actions": actions, "cost": 0}
	var cost: int = total_points * cost_per_point
	if cost > 0 and not inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions, "cost": cost}
	var repaired: Array = []
	if eq_points > 0 and equipment != null:
		for sid_v in eq_targets:
			var sid: String = str(sid_v)
			var before: int = int(equipment.get_durability(sid))
			var dmax: int = int(equipment.get_durability_max(sid))
			equipment._durability[sid] = dmax
			repaired.append({
				"slot": sid,
				"item_id": equipment.get_item_in(sid),
				"before": before,
				"after": dmax,
				"max": dmax,
			})
	if tool_points > 0 and inventory.has_method("apply_tool_repair_full"):
		var tr: Dictionary = inventory.apply_tool_repair_full()
		for row in tr.get("repaired", []):
			repaired.append(row)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	if eq_points > 0:
		actions.append(_equipment_update_action())
	var spent: int = cost
	var pts: int = total_points
	if slot == "tools":
		actions.append({"type": "system_message", "text": "工具已修理（%d 点，花费 %dG）。" % [pts, spent]})
	elif tool_points > 0 and eq_points > 0:
		actions.append({"type": "system_message", "text": "装备与工具已修理（%d 点，花费 %dG）。" % [pts, spent]})
	elif tool_points > 0:
		actions.append({"type": "system_message", "text": "工具已修理（%d 点，花费 %dG）。" % [pts, spent]})
	elif slot.is_empty() or slot == "all":
		actions.append({"type": "system_message", "text": "装备已全部修理（%d 点，花费 %dG）。" % [pts, spent]})
	else:
		actions.append({"type": "system_message", "text": "装备已修理（%d 点，花费 %dG）。" % [pts, spent]})
	return {
		"ok": true,
		"reason": "",
		"actions": actions,
		"gold_spent": spent,
		"points": pts,
		"repaired": repaired,
	}


## Enhance equipped gear at blacksmith. Consumes 1 enhance_stone + gold (10*(level+1)).
func try_enhance(slot: String = "") -> Dictionary:
	var actions: Array = []
	slot = str(slot).strip_edges()
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if equipment == null:
		actions.append({"type": "system_message", "text": "无法强化。"})
		return {"ok": false, "reason": "no_equipment", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if slot.is_empty():
		actions.append({"type": "system_message", "text": "该部位没有装备。"})
		return {"ok": false, "reason": "empty", "actions": actions}
	var r: Dictionary = equipment.try_enhance(inventory, slot)
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", ""))
		match reason:
			"maxed":
				actions.append({"type": "system_message", "text": "已达强化上限 +%d。" % int(equipment.ENHANCE_MAX)})
			"no_stone":
				actions.append({"type": "system_message", "text": "需要强化石。"})
			"no_gold":
				actions.append({"type": "system_message", "text": "金币不足。"})
			"empty", "invalid_slot":
				actions.append({"type": "system_message", "text": "该部位没有装备。"})
			_:
				actions.append({"type": "system_message", "text": "无法强化。"})
		return {
			"ok": false,
			"reason": reason,
			"actions": actions,
			"cost": int(r.get("cost", 0)),
			"enhance": int(r.get("enhance", 0)),
		}
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append(_equipment_update_action())
	var enh_n: int = int(r.get("enhance", 0))
	var spent: int = int(r.get("gold_spent", 0))
	var iid := str(r.get("item_id", ""))
	var nm := item_display_name(iid) if has_method("item_display_name") else iid
	actions.append({
		"type": "system_message",
		"text": "强化成功：%s +%d（花费 %dG）。" % [nm, enh_n, spent],
	})
	return {
		"ok": true,
		"reason": "",
		"actions": actions,
		"slot": slot,
		"item_id": iid,
		"enhance": enh_n,
		"enhance_before": int(r.get("enhance_before", 0)),
		"gold_spent": spent,
		"stat_key": str(r.get("stat_key", "")),
	}



## Apply hp_max / level / atk / def from spawn_data (top-level or nested stats).
func _apply_npc_spawn_combat_overrides(npc_id: String, spawn_data: Dictionary) -> void:
	if combat_stats == null or spawn_data.is_empty() or not combat_stats.npcs.has(npc_id):
		return
	var st: Dictionary = combat_stats.npcs[npc_id]
	var stats_v: Variant = spawn_data.get("stats", {})
	var nested: Dictionary = stats_v if typeof(stats_v) == TYPE_DICTIONARY else {}
	if spawn_data.has("level") or nested.has("level"):
		st["level"] = maxi(int(spawn_data.get("level", nested.get("level", st.get("level", 1)))), 1)
	if spawn_data.has("hp_max") or nested.has("hp_max"):
		var hp_max: int = maxi(int(spawn_data.get("hp_max", nested.get("hp_max", st.get("hp_max", 30)))), 1)
		st["hp_max"] = hp_max
		st["hp"] = hp_max
		var mp_max: int = combat_stats.npc_mp_max_for(int(st.get("level", 1)), hp_max)
		st["mp_max"] = mp_max
		st["mp"] = mp_max
	if spawn_data.has("atk") or nested.has("atk"):
		st["atk"] = maxi(int(spawn_data.get("atk", nested.get("atk", st.get("atk", 1)))), 0)
	if spawn_data.has("def") or nested.has("def"):
		st["def"] = maxi(int(spawn_data.get("def", nested.get("def", st.get("def", 0)))), 0)
	combat_stats.npcs[npc_id] = st


func _is_world_boss_npc(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return false
	if npc_spawn_templates.has(npc_id):
		var tmpl: Dictionary = npc_spawn_templates[npc_id]
		if bool(tmpl.get("world_boss", false)) or bool(tmpl.get("is_boss", false)):
			return true
	if npc_meta.has(npc_id):
		var meta_v: Variant = npc_meta[npc_id]
		if typeof(meta_v) == TYPE_DICTIONARY:
			var meta: Dictionary = meta_v
			if bool(meta.get("world_boss", false)):
				return true
	return npc_id == "world_boss_king"


## Replace generic kill line with world-boss announce when present.
func _rewrite_kill_announce(actions: Array, npc_id: String) -> void:
	var boss_name := "森林霸主"
	if npc_spawn_templates.has(npc_id):
		var n := str(npc_spawn_templates[npc_id].get("name", "")).strip_edges()
		if n != "":
			boss_name = n
	elif npc_meta.has(npc_id) and typeof(npc_meta[npc_id]) == TYPE_DICTIONARY:
		var n2 := str(npc_meta[npc_id].get("name", "")).strip_edges()
		if n2 != "":
			boss_name = n2
	var msg := "击败了%s！" % boss_name
	var rewritten := false
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		if str(a.get("text", "")) == "击败了敌人。":
			a["text"] = msg
			rewritten = true
			break
	if not rewritten:
		actions.append({"type": "system_message", "text": msg})


## Bonus gold + exp beyond normal kill loot/exp for world bosses.
func _world_boss_kill_bonus(npc_id: String) -> Array:
	var actions: Array = []
	npc_id = npc_id.strip_edges()
	var bonus_gold: int = 100
	var bonus_exp: int = 200
	if npc_spawn_templates.has(npc_id):
		var tmpl: Dictionary = npc_spawn_templates[npc_id]
		bonus_gold = maxi(int(tmpl.get("boss_bonus_gold", bonus_gold)), 0)
		bonus_exp = maxi(int(tmpl.get("boss_bonus_exp", bonus_exp)), 0)
	if bonus_gold > 0 and inventory != null:
		inventory.add_gold(bonus_gold)
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "获得金币 %d" % bonus_gold})
	if bonus_exp > 0 and combat_stats != null:
		var summary: Dictionary = combat_stats.grant_exp(bonus_exp)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", bonus_exp)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "获得经验 %d" % int(summary.get("amount", bonus_exp))})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				var new_lv: int = int(lv_v)
				actions.append({"type": "level_up", "level": new_lv, "combat": combat_snap})
				actions.append({"type": "system_message", "text": "升级到 Lv.%d！" % new_lv})
			_append_level_up_sp(actions, summary.get("levels_gained", []))
	return actions


## Build / refresh spawn template used after kill_npc → timed respawn.
func _store_npc_spawn_template(
	npc_id: String,
	x: int,
	y: int,
	hostile: bool,
	aggressive: bool,
	facing: int,
	wander_radius: int,
	group_id: int,
	leash_radius: int,
	respawn_sec: float,
	spawn_data: Dictionary,
	home_cell: Vector2i
) -> void:
	if not hostile:
		# Friendlies are not combat-killed / respawned via this path.
		if npc_spawn_templates.has(npc_id):
			npc_spawn_templates.erase(npc_id)
		return
	var tmpl: Dictionary = {}
	if not spawn_data.is_empty():
		tmpl = spawn_data.duplicate(true)
	tmpl["id"] = npc_id
	if not tmpl.has("name") or str(tmpl.get("name", "")).strip_edges() == "":
		tmpl["name"] = npc_id
	tmpl["hostile"] = true
	tmpl["aggressive"] = aggressive
	tmpl["direction"] = facing
	tmpl["wander_radius"] = maxi(wander_radius, 0)
	tmpl["group_id"] = group_id
	tmpl["leash_radius"] = leash_radius
	tmpl["respawn_sec"] = respawn_sec
	tmpl["home_cell"] = {"x": home_cell.x, "y": home_cell.y}
	# Keep original home as the respawn target; cell may be overwritten on near-spawn.
	if not tmpl.has("cell") or typeof(tmpl.get("cell")) != TYPE_DICTIONARY:
		tmpl["cell"] = {"x": home_cell.x, "y": home_cell.y}
	# Snapshot combat stats once (stable HP/ATK across respawns). Do not overwrite
	# an existing template stats blob when re-registering after respawn (new ensure_npc
	# would otherwise roll a fresh random HP into the template).
	if combat_stats != null and combat_stats.npcs.has(npc_id):
		var st: Dictionary = combat_stats.npcs[npc_id]
		if not tmpl.has("level"):
			tmpl["level"] = maxi(int(st.get("level", 1)), 1)
		if not tmpl.has("stats"):
			tmpl["stats"] = {
				"hp_max": int(st.get("hp_max", 0)),
				"mp_max": int(st.get("mp_max", 0)),
				"atk": int(st.get("atk", 0)),
				"def": int(st.get("def", 0)),
			}
	elif not tmpl.has("stats") and npc_spawn_templates.has(npc_id):
		var prev: Dictionary = npc_spawn_templates[npc_id]
		if prev.has("stats"):
			tmpl["stats"] = prev["stats"]
	npc_spawn_templates[npc_id] = tmpl


## After kill_npc: queue respawn from stored template (default 30s).
func _schedule_npc_respawn(npc_id: String) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or combat_stats == null:
		return
	if not npc_spawn_templates.has(npc_id):
		return
	var tmpl: Dictionary = npc_spawn_templates[npc_id]
	var sec: float = float(tmpl.get("respawn_sec", MobAI.DEFAULT_RESPAWN_SEC))
	if sec < 0.0:
		return  # disabled
	_npc_respawn_at[npc_id] = combat_stats.now_sec() + sec


## Fire due respawns → re-register + spawn_npc action for client.
func _tick_npc_respawns() -> Array:
	var actions: Array = []
	if combat_stats == null or _npc_respawn_at.is_empty():
		return actions
	var now: float = combat_stats.now_sec()
	var due: Array = []
	for nid_v in _npc_respawn_at.keys():
		var nid: String = str(nid_v)
		if now >= float(_npc_respawn_at[nid]):
			due.append(nid)
	for nid2 in due:
		_npc_respawn_at.erase(nid2)
		var spawned: Dictionary = _respawn_npc_from_template(str(nid2))
		if not spawned.is_empty():
			actions.append(spawned)
	return actions


## Place hostile at home (or find_spawn_near), re-register, return spawn_npc action dict.
func _respawn_npc_from_template(npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not npc_spawn_templates.has(npc_id):
		return {}
	# Already alive (e.g. map re-register) → skip.
	if combat_stats != null and combat_stats.npcs.has(npc_id):
		return {}
	var tmpl: Dictionary = npc_spawn_templates[npc_id].duplicate(true)
	var home := Vector2i(0, 0)
	var hv: Variant = tmpl.get("home_cell", tmpl.get("cell", {}))
	if typeof(hv) == TYPE_VECTOR2I:
		home = hv
	elif typeof(hv) == TYPE_DICTIONARY:
		home = Vector2i(int(hv.get("x", 0)), int(hv.get("y", 0)))
	var spawn_cell := home
	if map_collision != null:
		var free := true
		if map_collision.has_method("is_landable"):
			free = bool(map_collision.is_landable(home.x, home.y))
		elif map_collision.has_method("is_extra_blocked"):
			free = not bool(map_collision.is_extra_blocked(home.x, home.y))
		if not free and map_collision.has_method("find_spawn_near"):
			spawn_cell = map_collision.find_spawn_near(home.x, home.y)
		# Occupy spawn cell.
		if map_collision.has_method("set_extra_blocked"):
			map_collision.set_extra_blocked(spawn_cell.x, spawn_cell.y, true)
	var facing: int = int(tmpl.get("direction", 2))
	if not TileId.is_dir(facing):
		facing = 2
	var aggressive: bool = bool(tmpl.get("aggressive", false))
	var wander_r: int = maxi(int(tmpl.get("wander_radius", 0)), 0)
	var gid: int = int(tmpl.get("group_id", 0))
	register_npc(
		npc_id,
		spawn_cell.x,
		spawn_cell.y,
		true,
		aggressive,
		facing,
		wander_r,
		gid,
		tmpl,
		home
	)
	# Restore snapshotted combat stats if present.
	if combat_stats != null and combat_stats.npcs.has(npc_id) and tmpl.has("stats"):
		var st: Dictionary = combat_stats.npcs[npc_id]
		var snap_v: Variant = tmpl.get("stats", {})
		if typeof(snap_v) == TYPE_DICTIONARY:
			var snap: Dictionary = snap_v
			var hp_max: int = int(snap.get("hp_max", st.get("hp_max", 30)))
			st["hp_max"] = hp_max
			st["hp"] = hp_max
			var mp_max: int = int(snap.get("mp_max", st.get("mp_max", 0)))
			if mp_max <= 0:
				mp_max = combat_stats.npc_mp_max_for(int(st.get("level", 1)), hp_max)
			st["mp_max"] = mp_max
			st["mp"] = mp_max
			if snap.has("atk"):
				st["atk"] = int(snap.get("atk"))
			if snap.has("def"):
				st["def"] = int(snap.get("def"))
			combat_stats.npcs[npc_id] = st
	tmpl["cell"] = {"x": spawn_cell.x, "y": spawn_cell.y}
	tmpl["direction"] = facing
	return {"type": "spawn_npc", "npc": tmpl}


## --- Party / multiplayer shell stubs (debug only; no real netcode) ---

## Empty party_id means not in a party.
var party_id: String = ""
var party_leader_id: String = ""
## [{id, name, hp, hp_max, online, statuses}, ...]
var _party_members: Array = []
var _next_party_seq: int = 1
var _stub_ally_seq: int = 1
## When true, next poll_combat_tick injects a party_update snapshot.
var _party_poll_pending: bool = false
## Shared assist target (npc_id); empty = none. Shell: leader sets, members see.
var party_shared_target_id: String = ""
var party_shared_target_name: String = ""
## Party kill loot: ffa | leader | round_robin | need_greed (default ffa).
var party_loot_mode: String = "ffa"
## Round-robin cursor over online same-map member ids.
var _party_loot_rr_index: int = 0
## Active need/greed rolls: roll_id -> Dictionary (see _start_party_loot_roll).
var _loot_rolls: Dictionary = {}
var _loot_tie_note: String = ""
var _next_loot_roll_seq: int = 1
## Controllable die for need/greed (tests may set loot_roll_rng_fn -> int 1..100).
var _loot_roll_rng := RandomNumberGenerator.new()
var loot_roll_rng_fn: Callable = Callable()
const LOOT_ROLL_WINDOW_SEC: float = 15.0
## Last emitted self hp fingerprint to avoid spammy party_update.
var _party_last_self_hp_fp: String = ""
## Last emitted self status fingerprint (id:remaining).
var _party_last_self_status_fp: String = ""
## Pending invites: {id, name, outgoing, ready_at, expires_at, member, from}
var _party_invites: Array = []
var _next_invite_seq: int = 1
## Party summon stone pending (same-map thin v1).
## {id, caster_id, caster_cell:{x,y}, map_id, invites:{member_id:{name,accepted,cell?}}, expires_at}
var _party_summon_pending: Dictionary = {}
var _next_party_summon_seq: int = 1
## Headless/debug: when true, try_use_item party_summon auto-accepts stub invites.
var party_summon_auto_accept: bool = false
const PARTY_SUMMON_WINDOW_SEC: float = 30.0


func snapshot_party() -> Dictionary:
	return _party_module_logic.snapshot_party()
func in_party() -> bool:
	return _party_module_logic.in_party()
## Online party members on the killer's map (stubs lack map_id → count as same-map).
## Used for kill EXP party bonus only. Stub allies do not receive separate EXP.
func _party_online_same_map_count() -> int:
	return _party_module_logic._party_online_same_map_count()
## Solo / N<=1: base unchanged. Else +5% per extra member, cap +25% (5 extras).
## amount = max(1, floor(base * (1.0 + 0.05*(N-1)))) with N capped extras at 5.
func _party_kill_exp_with_bonus(base: int, online_n: int = -1) -> int:
	return _party_module_logic._party_kill_exp_with_bonus(base, online_n)
## Online same-map party member ids (stable member-array order). Includes local + stubs/remotes.
func _party_online_same_map_ids() -> Array:
	return _party_module_logic._party_online_same_map_ids()
## Resolve owner_id for a party-eligible kill bag. Solo / ffa / need_greed → "". Advances RR index.
## need_greed is handled in _roll_and_grant_loot (roll window); this returns "" as fallback.
func _party_assign_kill_loot_owner() -> String:
	return _party_module_logic._party_assign_kill_loot_owner()
func try_party_set_loot_mode(mode: String) -> Dictionary:
	return _party_module_logic.try_party_set_loot_mode(mode)
## Snapshot active need/greed rolls (tests / thin HUD).
func snapshot_loot_rolls() -> Array:
	return _loot_module_logic.snapshot_loot_rolls()
func loot_roll_count() -> int:
	return _loot_module_logic.loot_roll_count()
func _loot_roll_now() -> float:
	return _loot_module_logic._loot_roll_now()
func _next_loot_die() -> int:
	return _loot_module_logic._next_loot_die()
func _party_member_display_name(member_id: String) -> String:
	return _party_module_logic._party_member_display_name(member_id)
## Start one roll per pending item. eligible must already be N>1 same-map ids.
func _start_party_loot_rolls(cell: Dictionary, pending_items: Array, npc_id: String, source: String, eligible: Array) -> Array:
	return _party_module_logic._start_party_loot_rolls(cell, pending_items, npc_id, source, eligible)
## Debug/test: open a roll without a kill. Returns {ok, roll_id, actions}.
func debug_start_loot_roll(item_id: String, qty: int = 1, eligible: Array = []) -> Dictionary:
	return _loot_module_logic.debug_start_loot_roll(item_id, qty, eligible)
func _start_party_loot_roll(cell: Dictionary, item_id: String, qty: int, npc_id: String, source: String, eligible: Array) -> Array:
	return _party_module_logic._start_party_loot_roll(cell, item_id, qty, npc_id, source, eligible)
## Local player choice: need | greed | pass. Optional roll_id (else first open roll).
func try_loot_roll(choice: String, roll_id: String = "") -> Dictionary:
	return _loot_module_logic.try_loot_roll(choice, roll_id)
## Member (incl. stubs) choice — used by shell + headless tests.
func try_loot_roll_for(member_id: String, choice: String, roll_id: String = "") -> Dictionary:
	return _loot_module_logic.try_loot_roll_for(member_id, choice, roll_id)
func _first_open_loot_roll_for(member_id: String) -> String:
	return _loot_module_logic._first_open_loot_roll_for(member_id)
func _loot_roll_all_voted(roll: Dictionary) -> bool:
	return _loot_module_logic._loot_roll_all_voted(roll)
func _tick_loot_rolls() -> Array:
	return _loot_module_logic._tick_loot_rolls()
## Force timeout resolve (tests). Empty roll_id → all open rolls.
func debug_force_loot_roll_timeout(roll_id: String = "") -> Dictionary:
	return _loot_module_logic.debug_force_loot_roll_timeout(roll_id)
func _resolve_loot_roll(roll_id: String) -> Array:
	return _loot_module_logic._resolve_loot_roll(roll_id)
## Highest need wins; else highest greed; all pass → "". Ties: earlier `at`; if still equal, one reroll.
func _pick_loot_roll_winner(choices: Dictionary) -> String:
	return _loot_module_logic._pick_loot_roll_winner(choices)
func _pick_highest_roll_with_tiebreak(pool: Array) -> String:
	_loot_tie_note = ""
	if pool.is_empty():
		return ""
	var best_roll := -1
	for p in pool:
		best_roll = maxi(best_roll, int(p.get("roll", 0)))
	var tied: Array = []
	for p2 in pool:
		if int(p2.get("roll", 0)) == best_roll:
			tied.append(p2)
	if tied.size() == 1:
		return str(tied[0].get("id", ""))
	# First roll (earliest at) wins.
	tied.sort_custom(func(a, b): return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	var earliest_at := float(tied[0].get("at", 0.0))
	var still: Array = []
	for t in tied:
		if is_equal_approx(float(t.get("at", 0.0)), earliest_at):
			still.append(t)
	if still.size() == 1:
		return str(still[0].get("id", ""))
	# Reroll once among remaining; if still tied, keep first (earliest).
	var best2 := -1
	var win_id := str(still[0].get("id", ""))
	var winners2: Array = []
	for s in still:
		var die := _next_loot_die()
		if die > best2:
			best2 = die
			win_id = str(s.get("id", ""))
			winners2 = [win_id]
		elif die == best2:
			winners2.append(str(s.get("id", "")))
	if winners2.size() > 1:
		_loot_tie_note = "掷骰平局，重掷后仍平，保留先手。"
		win_id = str(still[0].get("id", ""))
	else:
		_loot_tie_note = "掷骰平局，已重掷。"
	return win_id


func _party_update_action() -> Dictionary:
	return _party_module_logic._party_update_action()
func _mark_party_poll() -> void:
	_party_module_logic._mark_party_poll()
func _party_self_id() -> String:
	return _party_module_logic._party_self_id()
func _party_self_name() -> String:
	return _party_module_logic._party_self_name()
func _party_self_hp() -> Dictionary:
	return _party_module_logic._party_self_hp()
func _party_member_statuses(member_id: String) -> Array:
	return _party_module_logic._party_member_statuses(member_id)
func _party_statuses_fingerprint(statuses: Array) -> String:
	return _party_module_logic._party_statuses_fingerprint(statuses)
func _party_demo_stub_statuses(stub_key: String) -> Array:
	return _party_module_logic._party_demo_stub_statuses(stub_key)
func _party_make_self_member() -> Dictionary:
	return _party_module_logic._party_make_self_member()
func _party_self_hp_fingerprint() -> String:
	return _party_module_logic._party_self_hp_fingerprint()
## Update the local player's row in _party_members from combat_stats. Returns true if changed.
func _party_refresh_self_member() -> bool:
	return _party_module_logic._party_refresh_self_member()
func _party_find_member_index(member_id: String) -> int:
	return _party_module_logic._party_find_member_index(member_id)
func _party_find_member_by_name(member_name: String) -> int:
	return _party_module_logic._party_find_member_by_name(member_name)
func _party_clear() -> void:
	_party_module_logic._party_clear()
func _party_make_stub(stub_key: String = "") -> Dictionary:
	return _party_module_logic._party_make_stub(stub_key)
func try_cancel_status(status_id: String) -> Dictionary:
	## Player cancels own beneficial buff/hot only (not debuff/dot).
	var actions: Array = []
	status_id = str(status_id).strip_edges()
	if status_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的状态。"})
		return {"ok": false, "reason": "empty", "actions": actions}
	if combat_stats == null or combat_stats.statuses == null:
		actions.append({"type": "system_message", "text": "无法取消状态。"})
		return {"ok": false, "reason": "no_combat", "actions": actions}
	var statuses = combat_stats.statuses
	if not statuses.has_status("player", status_id):
		actions.append({"type": "system_message", "text": "未找到该状态。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var kind := ""
	for s in statuses.snapshot_statuses("player"):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str((s as Dictionary).get("id", "")) != status_id:
			continue
		kind = str((s as Dictionary).get("kind", "")).strip_edges().to_lower()
		break
	if kind != "buff" and kind != "hot":
		actions.append({"type": "system_message", "text": "该状态无法取消。"})
		return {"ok": false, "reason": "not_cancelable", "actions": actions}
	statuses.clear_status("player", status_id)
	actions.append(statuses.status_update_action("player"))
	if in_party():
		_party_refresh_self_member()
		actions.append(_party_update_action())
	return {"ok": true, "actions": actions}


func try_party_create() -> Dictionary:
	return _party_module_logic.try_party_create()
func try_party_invite(target: String = "") -> Dictionary:
	return _party_module_logic.try_party_invite(target)
func _party_clock() -> float:
	return _party_module_logic._party_clock()
func _tick_party_invites() -> Array:
	return _party_module_logic._tick_party_invites()
func try_party_invite_respond(invite_id: String, accept: bool) -> Dictionary:
	return _party_module_logic.try_party_invite_respond(invite_id, accept)
func try_party_incoming_invite(from_name: String = "旅人甲") -> Dictionary:
	return _party_module_logic.try_party_incoming_invite(from_name)
func try_party_leave() -> Dictionary:
	return _party_module_logic.try_party_leave()
func try_party_kick(member_id: String = "") -> Dictionary:
	return _party_module_logic.try_party_kick(member_id)
## Debug helper: ensure a party exists and fill 1–2 stub allies for HUD bars.
func try_party_debug_fill() -> Dictionary:
	return _party_module_logic.try_party_debug_fill()
## Leader (or solo shell) marks a shared assist target for the party panel.
func try_party_set_target(npc_id: String = "", display_name: String = "") -> Dictionary:
	return _party_module_logic.try_party_set_target(npc_id, display_name)
func try_party_clear_target() -> Dictionary:
	return _party_module_logic.try_party_clear_target()
## --- Party summon stone「集结石」(same-map thin v1) ---

func snapshot_party_summon() -> Dictionary:
	return _party_module_logic.snapshot_party_summon()
## Use consumable party_summon: require same-map party N>1 + free adjacent cell.
func _try_party_summon_item(item_id: String, def: Dictionary) -> Dictionary:
	return _party_module_logic._try_party_summon_item(item_id, def)
## List free Chebyshev-adjacent cells around (cx,cy). reserved: "x,y" -> true.
func _party_summon_list_free_cells(cx: int, cy: int, reserved: Dictionary) -> Array:
	return _party_module_logic._party_summon_list_free_cells(cx, cy, reserved)
func _party_summon_cell_free(x: int, y: int) -> bool:
	return _party_module_logic._party_summon_cell_free(x, y)
## Member accepts pending summon (MockServer API / headless). member_id required for stubs.
func try_party_summon_accept(member_id: String = "") -> Dictionary:
	return _party_module_logic.try_party_summon_accept(member_id)
func try_party_summon_decline(member_id: String = "") -> Dictionary:
	return _party_module_logic.try_party_summon_decline(member_id)
## Debug/headless: accept all pending invites (stubs).
func try_party_summon_accept_all() -> Dictionary:
	return _party_module_logic.try_party_summon_accept_all()
func _party_summon_apply_member_cell(member_id: String, dest: Vector2i, actions: Array) -> void:
	_party_module_logic._party_summon_apply_member_cell(member_id, dest, actions)
## --- Player trade shell (stub partner; escrow items/gold; no real netcode) ---

var _trade: Dictionary = {}  # empty = no session
var _next_trade_seq: int = 1


func snapshot_trade() -> Dictionary:
	return _trade_module_logic.snapshot_trade()
func in_trade() -> bool:
	return _trade_module_logic.in_trade()
func _trade_update_action() -> Dictionary:
	return _trade_module_logic._trade_update_action()
func _trade_close_action() -> Dictionary:
	return _trade_module_logic._trade_close_action()
func _trade_force_cancel_silent() -> void:
	_trade_module_logic._trade_force_cancel_silent()
func _trade_refund_my_escrow() -> void:
	_trade_module_logic._trade_refund_my_escrow()
func _trade_inventory_actions() -> Array:
	return _trade_module_logic._trade_inventory_actions()
func _trade_find_my_item(item_id: String) -> int:
	return _trade_module_logic._trade_find_my_item(item_id)
func try_trade_open(partner_name: String = "") -> Dictionary:
	return _trade_module_logic.try_trade_open(partner_name)
func try_trade_cancel() -> Dictionary:
	return _trade_module_logic.try_trade_cancel()
func try_trade_put_item(item_id: String, qty: int = 1) -> Dictionary:
	return _trade_module_logic.try_trade_put_item(item_id, qty)
func try_trade_take_item(item_id: String, qty: int = 1) -> Dictionary:
	return _trade_module_logic.try_trade_take_item(item_id, qty)
func try_trade_set_gold(amount: int) -> Dictionary:
	return _trade_module_logic.try_trade_set_gold(amount)
func _trade_fill_stub_offer() -> void:
	_trade_module_logic._trade_fill_stub_offer()
func try_trade_ready(ready: bool = true) -> Dictionary:
	return _trade_module_logic.try_trade_ready(ready)
func try_trade_confirm() -> Dictionary:
	return _trade_module_logic.try_trade_confirm()
## --- Crafting (static recipes; open anywhere; MockServer authority) ---

func _craft_xp_needed_for(level: int) -> int:
	level = maxi(int(level), 1)
	return 20 + level * 10


func _reset_craft_skill() -> void:
	craft_level = 1
	craft_xp = 0
	craft_xp_to_next = _craft_xp_needed_for(craft_level)


func snapshot_craft() -> Dictionary:
	return {
		"craft_level": craft_level,
		"craft_xp": craft_xp,
		"craft_xp_to_next": craft_xp_to_next,
	}


func snapshot_recipes() -> Array:
	if recipe_catalog == null:
		return []
	return recipe_catalog.list_all()


func try_craft(recipe_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	recipe_id = str(recipe_id).strip_edges()
	qty = int(qty)
	if recipe_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效的制作请求。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory == null or recipe_catalog == null:
		actions.append({"type": "system_message", "text": "制作不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	var recipe: Dictionary = recipe_catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		actions.append({"type": "system_message", "text": "未知配方。"})
		return {"ok": false, "reason": "unknown_recipe", "actions": actions}
	# Prefer recipe craft_level; fall back to learn_level mapped as craft req (not combat level).
	var need_craft: int = 1
	if recipe.has("craft_level"):
		need_craft = maxi(int(recipe.get("craft_level", 1)), 1)
	else:
		need_craft = maxi(int(recipe.get("learn_level", 1)), 1)
	if craft_level < need_craft:
		actions.append({"type": "system_message", "text": "制作等级不足（需要 %d）。" % need_craft})
		return {"ok": false, "reason": "craft_level", "actions": actions}
	var ings_v: Variant = recipe.get("ingredients", [])
	if typeof(ings_v) != TYPE_ARRAY or (ings_v as Array).is_empty():
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var scaled: Array = []
	for row in ings_v:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid := str(row.get("id", "")).strip_edges()
		var need: int = maxi(int(row.get("qty", 0)), 0) * qty
		if iid.is_empty() or need <= 0:
			continue
		scaled.append({"id": iid, "qty": need})
	if scaled.is_empty():
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	for row2 in scaled:
		var iid2 := str(row2.get("id", ""))
		var need2: int = int(row2.get("qty", 0))
		if not inventory.has_item(iid2, need2):
			actions.append({"type": "system_message", "text": "材料不足"})
			return {"ok": false, "reason": "missing_mats", "actions": actions}
	var gold_cost: int = maxi(int(recipe.get("gold_cost", 0)), 0) * qty
	if gold_cost > 0 and inventory.get_gold() < gold_cost:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var out_v: Variant = recipe.get("output", {})
	if typeof(out_v) != TYPE_DICTIONARY:
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var out_id := str(out_v.get("id", "")).strip_edges()
	var out_qty: int = maxi(int(out_v.get("qty", 1)), 1) * qty
	if out_id.is_empty() or out_qty <= 0:
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	# All-or-nothing: consume ingredients (+ gold), grant output; rollback on bag failure.
	for row3 in scaled:
		if not inventory.consume(str(row3.get("id", "")), int(row3.get("qty", 0))):
			# Should not happen after has_item; restore any partial consume.
			for row4 in scaled:
				var done_id := str(row4.get("id", ""))
				if done_id == str(row3.get("id", "")):
					break
				inventory.add_item(done_id, int(row4.get("qty", 0)))
			actions.append({"type": "system_message", "text": "材料不足"})
			return {"ok": false, "reason": "missing_mats", "actions": actions}
	if gold_cost > 0 and not inventory.try_spend_gold(gold_cost):
		for row5 in scaled:
			inventory.add_item(str(row5.get("id", "")), int(row5.get("qty", 0)))
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(out_id, out_qty)
	var added: int = int(add_r.get("added", 0))
	if added < out_qty:
		if added > 0:
			inventory.consume(out_id, added)
		for row6 in scaled:
			inventory.add_item(str(row6.get("id", "")), int(row6.get("qty", 0)))
		if gold_cost > 0:
			inventory.add_gold(gold_cost)
		var reason := str(add_r.get("reason", "bag_full"))
		var msg := "背包已满"
		if reason == "stack_full":
			msg = "背包已满"
		actions.append({"type": "system_message", "text": msg})
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var oname := item_display_name(out_id)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "制作成功：【%s】×%d" % [oname, out_qty]})
	actions.append_array(_note_title_counter("crafts", 1))
	# Craft profession XP (5 per crafted unit qty).
	var gained_xp: int = 5 * qty
	craft_xp += gained_xp
	while craft_xp >= craft_xp_to_next and craft_xp_to_next > 0:
		craft_xp -= craft_xp_to_next
		craft_level += 1
		craft_xp_to_next = _craft_xp_needed_for(craft_level)
		actions.append({"type": "system_message", "text": "制作等级提升至 %d！" % craft_level})
	actions.append({
		"type": "craft_update",
		"craft_level": craft_level,
		"craft_xp": craft_xp,
		"craft_xp_to_next": craft_xp_to_next,
	})
	return {"ok": true, "actions": actions}




## --- Gather profession (shared by try_gather / try_fish) ---

func _gather_xp_needed_for(level: int) -> int:
	level = maxi(int(level), 1)
	return 20 + level * 10


func _reset_gather_skill() -> void:
	gather_level = 1
	gather_xp = 0
	gather_xp_to_next = _gather_xp_needed_for(gather_level)


func snapshot_gather() -> Dictionary:
	return {
		"gather_level": gather_level,
		"gather_xp": gather_xp,
		"gather_xp_to_next": gather_xp_to_next,
	}


func _gather_skill_update_action() -> Dictionary:
	return {
		"type": "gather_update",
		"gather_level": gather_level,
		"gather_xp": gather_xp,
		"gather_xp_to_next": gather_xp_to_next,
	}


func _apply_gather_skill_xp(actions: Array, gained_xp: int = 5) -> void:
	gained_xp = maxi(int(gained_xp), 0)
	if gained_xp <= 0:
		return
	gather_xp += gained_xp
	while gather_xp >= gather_xp_to_next and gather_xp_to_next > 0:
		gather_xp -= gather_xp_to_next
		gather_level += 1
		gather_xp_to_next = _gather_xp_needed_for(gather_level)
		actions.append({"type": "system_message", "text": "采集等级提升至 %d！" % gather_level})
	actions.append(_gather_skill_update_action())


func _gather_level_required(def: Dictionary) -> int:
	return maxi(int(def.get("gather_level", 1)), 1)


func _fail_gather_level(actions: Array, need: int) -> Dictionary:
	actions.append({"type": "system_message", "text": "采集等级不足（需要 %d）。" % need})
	return {"ok": false, "reason": "gather_level", "actions": actions}


## --- World gather nodes (herb / ore / scrap) ---

func _reload_gather_for_map() -> void:
	_gather_nodes.clear()
	_gather_state.clear()
	if gather_catalog == null:
		return
	var mid := str(map_pack_id).strip_edges()
	if mid.is_empty():
		mid = map_pack_path.get_file()
	for def_v in gather_catalog.nodes_for_map(mid):
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = def_v
		var nid := str(d.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		_gather_nodes[nid] = d
		_gather_state[nid] = {"depleted": false, "ready_at": 0.0}


func _gather_now() -> float:
	if combat_stats != null and combat_stats.has_method("now_sec"):
		return float(combat_stats.now_sec())
	return float(Time.get_ticks_msec()) / 1000.0


func _gather_update_action(node_id: String, depleted: bool, display_name: String = "") -> Dictionary:
	return {
		"type": "gather_update",
		"node_id": node_id,
		"depleted": depleted,
		"name": display_name,
	}


func _gather_set_cell_blocked(node_id: String, blocked: bool) -> void:
	if map_collision == null or not map_collision.has_method("set_extra_blocked"):
		return
	var def: Dictionary = _gather_nodes.get(node_id, {})
	if def.is_empty():
		return
	var cell_v: Variant = def.get("cell", {})
	if typeof(cell_v) != TYPE_DICTIONARY:
		return
	map_collision.set_extra_blocked(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)), blocked)


func _gather_in_range(node_id: String, player_x: int, player_y: int) -> bool:
	## Chebyshev ≤ 1 against gather cell (or registered NPC cell).
	var def: Dictionary = _gather_nodes.get(node_id, {})
	var cx := -99999
	var cy := -99999
	if not def.is_empty():
		var cell_v: Variant = def.get("cell", {})
		if typeof(cell_v) == TYPE_DICTIONARY:
			cx = int(cell_v.get("x", -99999))
			cy = int(cell_v.get("y", -99999))
	if combat_stats != null and combat_stats.has_method("get_npc_cell"):
		var nc: Vector2i = combat_stats.get_npc_cell(node_id)
		if nc.x > -9990:
			cx = nc.x
			cy = nc.y
	if cx <= -99990:
		return false
	return maxi(absi(cx - player_x), absi(cy - player_y)) <= 1


func try_gather(node_id: String) -> Dictionary:
	var actions: Array = []
	node_id = str(node_id).strip_edges()
	if node_id.is_empty() or not _gather_nodes.has(node_id):
		actions.append({"type": "system_message", "text": "这里没有可采集的资源。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if combat_stats != null and not combat_stats.player_alive():
		return {"ok": false, "reason": "dead", "actions": []}
	var px: int = player_cell.x
	var py: int = player_cell.y
	if px <= -9990:
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	if not _gather_in_range(node_id, px, py):
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var def: Dictionary = _gather_nodes[node_id]
	var st: Dictionary = _gather_state.get(node_id, {"depleted": false, "ready_at": 0.0})
	if bool(st.get("depleted", false)):
		actions.append({"type": "system_message", "text": "资源尚未恢复"})
		actions.append(_gather_update_action(node_id, true, str(def.get("name", node_id))))
		return {"ok": false, "reason": "depleted", "actions": actions}
	var need_gather: int = _gather_level_required(def)
	if gather_level < need_gather:
		return _fail_gather_level(actions, need_gather)
	# Optional tool gate (durable tools wear on success; broken/missing fail).
	var tool_id := str(def.get("tool", "")).strip_edges()
	if tool_id != "":
		var usable := false
		if inventory != null:
			if inventory.has_method("has_usable_tool"):
				usable = bool(inventory.has_usable_tool(tool_id, 1))
			else:
				usable = bool(inventory.has_item(tool_id, 1))
		if not usable:
			var tname := item_display_name(tool_id)
			actions.append({"type": "system_message", "text": "需要工具：%s" % tname})
			return {"ok": false, "reason": "need_tool", "actions": actions}
	if inventory == null or gather_catalog == null:
		actions.append({"type": "system_message", "text": "采集不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	var yrow: Dictionary = gather_catalog.pick_yield(def)
	var iid := str(yrow.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(yrow.get("qty", 1)), 1)
	var weather_bonus := false
	if WeatherGatherUtil.is_herb_node(node_id, def) and WeatherGatherUtil.is_bonus_weather(weather_kind):
		var roll := randf()
		if weather_gather_randf.is_valid():
			roll = float(weather_gather_randf.call())
		if WeatherGatherUtil.roll_gather_qty_bonus(roll):
			qty = WeatherGatherUtil.apply_gather_qty_bonus(qty, true)
			weather_bonus = true
	if iid.is_empty():
		actions.append({"type": "system_message", "text": "这里什么也没有。"})
		return {"ok": false, "reason": "empty_yield", "actions": actions}
	# Bag space check (all-or-nothing).
	if inventory.has_method("can_accept") and not inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			inventory.consume(iid, added)
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	# Gathering is an active action — cancel stealth / mount.
	if combat_engine != null and combat_engine.has_method("break_stealth"):
		combat_engine.break_stealth(actions)
	elif combat_stats != null and combat_stats.statuses != null and combat_stats.statuses.has_status("player", "stealth"):
		combat_stats.statuses.clear_status("player", "stealth")
		actions.append(combat_stats.statuses.status_update_action("player"))
	if combat_engine != null and combat_engine.has_method("break_mount"):
		combat_engine.break_mount(actions)
	elif combat_stats != null and combat_stats.statuses != null and combat_stats.statuses.has_status("player", "mounted"):
		combat_stats.statuses.clear_status("player", "mounted")
		actions.append(combat_stats.statuses.status_update_action("player"))
		actions.append({"type": "system_message", "text": "已下马。"})
	# Deplete + schedule respawn.
	var respawn_sec: float = maxf(float(def.get("respawn_sec", 30.0)), 0.0)
	var ready_at: float = _gather_now() + respawn_sec
	_gather_state[node_id] = {"depleted": true, "ready_at": ready_at}
	_gather_set_cell_blocked(node_id, false)
	var iname := item_display_name(iid)
	var dname := str(def.get("name", node_id))
	var tool_broke := false
	if tool_id != "" and inventory != null and inventory.has_method("wear_tool"):
		var wr: Dictionary = inventory.wear_tool(tool_id, 1)
		if bool(wr.get("ok", false)) and bool(wr.get("broken", false)):
			tool_broke = true
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "采集获得：%s×%d" % [iname, qty]})
	if weather_bonus:
		actions.append({"type": "system_message", "text": WeatherGatherUtil.BONUS_MESSAGE})
	if tool_broke:
		actions.append({"type": "system_message", "text": "工具已损坏。"})
	actions.append(_gather_update_action(node_id, true, dname))
	actions.append_array(_quest_note_item_actions(iid, qty))
	_apply_gather_skill_xp(actions, 5)
	actions.append_array(_note_achievement_counter("gathers", 1))
	return {
		"ok": true,
		"actions": actions,
		"item_id": iid,
		"qty": qty,
		"node_id": node_id,
		"weather_bonus": weather_bonus,
		"tool_broke": tool_broke,
	}


func _tick_gather_respawns() -> Array:
	var actions: Array = []
	if _gather_state.is_empty():
		return actions
	var now: float = _gather_now()
	for nid_v in _gather_state.keys():
		var nid: String = str(nid_v)
		var st: Dictionary = _gather_state[nid]
		if not bool(st.get("depleted", false)):
			continue
		if now < float(st.get("ready_at", 0.0)):
			continue
		_gather_state[nid] = {"depleted": false, "ready_at": 0.0}
		_gather_set_cell_blocked(nid, true)
		var def: Dictionary = _gather_nodes.get(nid, {})
		var dname := str(def.get("name", nid))
		actions.append(_gather_update_action(nid, false, dname))
	return actions


## Test / debug: force one or all depleted gather nodes ready immediately.
func force_gather_respawn(node_id: String = "") -> Array:
	var actions: Array = []
	node_id = str(node_id).strip_edges()
	var ids: Array = [node_id] if node_id != "" else _gather_state.keys()
	for nid_v in ids:
		var nid: String = str(nid_v)
		if not _gather_state.has(nid):
			continue
		var st: Dictionary = _gather_state[nid]
		if not bool(st.get("depleted", false)):
			continue
		_gather_state[nid] = {"depleted": false, "ready_at": 0.0}
		_gather_set_cell_blocked(nid, true)
		var def: Dictionary = _gather_nodes.get(nid, {})
		actions.append(_gather_update_action(nid, false, str(def.get("name", nid))))
	return actions


func is_gather_depleted(node_id: String) -> bool:
	node_id = str(node_id).strip_edges()
	if not _gather_state.has(node_id):
		return false
	return bool((_gather_state[node_id] as Dictionary).get("depleted", false))


## --- World fishing spots ---

func _reload_fish_for_map() -> void:
	_fish_spots.clear()
	_fish_state.clear()
	_fish_busy_until = 0.0
	if fish_catalog == null:
		return
	var mid := str(map_pack_id).strip_edges()
	if mid.is_empty():
		mid = map_pack_path.get_file()
	for def_v in fish_catalog.spots_for_map(mid):
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = def_v
		var sid := str(d.get("id", "")).strip_edges()
		if sid.is_empty():
			continue
		_fish_spots[sid] = d
		_fish_state[sid] = {"depleted": false, "ready_at": 0.0}


func _fish_now() -> float:
	return _gather_now()


func _fish_update_action(spot_id: String, depleted: bool, display_name: String = "") -> Dictionary:
	return {
		"type": "fish_update",
		"spot_id": spot_id,
		"depleted": depleted,
		"name": display_name,
	}


func _fish_in_range(spot_id: String, player_x: int, player_y: int) -> bool:
	## Chebyshev ≤ 1 against fish spot cell (or registered NPC cell).
	var def: Dictionary = _fish_spots.get(spot_id, {})
	var cx := -99999
	var cy := -99999
	if not def.is_empty():
		var cell_v: Variant = def.get("cell", {})
		if typeof(cell_v) == TYPE_DICTIONARY:
			cx = int(cell_v.get("x", -99999))
			cy = int(cell_v.get("y", -99999))
	if combat_stats != null and combat_stats.has_method("get_npc_cell"):
		var nc: Vector2i = combat_stats.get_npc_cell(spot_id)
		if nc.x > -9990:
			cx = nc.x
			cy = nc.y
	if cx <= -99990:
		return false
	return maxi(absi(cx - player_x), absi(cy - player_y)) <= 1



## Prefer shiny bait over worm; empty if none.
func _best_fish_bait() -> String:
	if inventory == null:
		return ""
	if inventory.has_item("bait_shiny", 1):
		return "bait_shiny"
	if inventory.has_item("bait_worm", 1):
		return "bait_worm"
	return ""


## Weighted yield pick; optional bait boosts fish_shiny (worm +0.15, shiny +0.35);
## rain/snow adds +0.1 shiny weight via WeatherGatherUtil.
func _pick_fish_yield(spot_def: Dictionary, bait_id: String = "") -> Dictionary:
	if fish_catalog == null:
		return {}
	bait_id = str(bait_id).strip_edges()
	var bonus := 0.0
	if bait_id == "bait_shiny":
		bonus = 0.35
	elif bait_id == "bait_worm":
		bonus = 0.15
	var weather_shiny: float = WeatherGatherUtil.fish_shiny_bonus_for_weather(weather_kind)
	if bonus <= 0.0 and weather_shiny <= 0.0:
		return fish_catalog.pick_yield(spot_def)
	var yv: Variant = spot_def.get("yields", [])
	if typeof(yv) != TYPE_ARRAY or (yv as Array).is_empty():
		return {}
	var rows: Array = []
	var total := 0.0
	for row in yv:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid := str(row.get("item_id", "")).strip_edges()
		var qty: int = maxi(int(row.get("qty", 1)), 1)
		var w: float = maxf(float(row.get("weight", 1.0)), 0.0)
		if iid == "fish_shiny":
			w = WeatherGatherUtil.shiny_weight(w, weather_kind, bonus)
		if iid.is_empty() or w <= 0.0:
			continue
		rows.append({"item_id": iid, "qty": qty, "weight": w})
		total += w
	if rows.is_empty() or total <= 0.0:
		return fish_catalog.pick_yield(spot_def)
	var r := randf() * total
	var acc := 0.0
	for row2 in rows:
		acc += float(row2.get("weight", 0.0))
		if r <= acc:
			return {"item_id": str(row2.get("item_id", "")), "qty": maxi(int(row2.get("qty", 1)), 1)}
	var last: Dictionary = rows[rows.size() - 1]
	return {"item_id": str(last.get("item_id", "")), "qty": maxi(int(last.get("qty", 1)), 1)}


func try_fish(spot_id: String) -> Dictionary:
	var actions: Array = []
	spot_id = str(spot_id).strip_edges()
	if spot_id.is_empty() or not _fish_spots.has(spot_id):
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if combat_stats != null and not combat_stats.player_alive():
		return {"ok": false, "reason": "dead", "actions": []}
	var now: float = _fish_now()
	if now < _fish_busy_until:
		actions.append({"type": "system_message", "text": "还在甩杆…"})
		return {"ok": false, "reason": "busy", "actions": actions}
	var px: int = player_cell.x
	var py: int = player_cell.y
	if px <= -9990:
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	if not _fish_in_range(spot_id, px, py):
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var def: Dictionary = _fish_spots[spot_id]
	var st: Dictionary = _fish_state.get(spot_id, {"depleted": false, "ready_at": 0.0})
	if bool(st.get("depleted", false)):
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		actions.append(_fish_update_action(spot_id, true, str(def.get("name", spot_id))))
		return {"ok": false, "reason": "depleted", "actions": actions}
	var need_gather: int = _gather_level_required(def)
	if gather_level < need_gather:
		return _fail_gather_level(actions, need_gather)
	if inventory == null or fish_catalog == null:
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	# Optional tool gate (same durability rules as gather).
	var fish_tool_id := str(def.get("tool", "")).strip_edges()
	if fish_tool_id != "":
		var fish_usable := false
		if inventory.has_method("has_usable_tool"):
			fish_usable = bool(inventory.has_usable_tool(fish_tool_id, 1))
		else:
			fish_usable = bool(inventory.has_item(fish_tool_id, 1))
		if not fish_usable:
			var ftname := item_display_name(fish_tool_id)
			actions.append({"type": "system_message", "text": "需要工具：%s" % ftname})
			return {"ok": false, "reason": "need_tool", "actions": actions}
	# Optional bait: best available (shiny > worm). Consumed only on success.
	var bait_id := _best_fish_bait()
	var yrow: Dictionary = _pick_fish_yield(def, bait_id)
	var iid := str(yrow.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(yrow.get("qty", 1)), 1)
	if iid.is_empty():
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		return {"ok": false, "reason": "empty_yield", "actions": actions}
	if inventory.has_method("can_accept") and not inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			inventory.consume(iid, added)
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	# Consume 1 bait on successful catch (after bag accept).
	var bait_used := ""
	if bait_id != "" and inventory.has_item(bait_id, 1) and inventory.consume(bait_id, 1):
		bait_used = bait_id
	# Cast busy lock (optional short lock after a successful cast).
	var cast_sec: float = maxf(float(def.get("cast_sec", 0.0)), 0.0)
	_fish_busy_until = now + cast_sec
	# Deplete + schedule respawn (same shell as gather).
	var respawn_sec: float = maxf(float(def.get("respawn_sec", 20.0)), 0.0)
	var ready_at: float = now + respawn_sec
	_fish_state[spot_id] = {"depleted": true, "ready_at": ready_at}
	var iname := item_display_name(iid)
	var dname := str(def.get("name", spot_id))
	var fish_tool_broke := false
	if fish_tool_id != "" and inventory.has_method("wear_tool"):
		var fwr: Dictionary = inventory.wear_tool(fish_tool_id, 1)
		if bool(fwr.get("ok", false)) and bool(fwr.get("broken", false)):
			fish_tool_broke = true
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	var catch_msg := "钓到了：%s×%d" % [iname, qty]
	if bait_used != "":
		catch_msg += "（使用了%s。）" % item_display_name(bait_used)
	actions.append({"type": "system_message", "text": catch_msg})
	if fish_tool_broke:
		actions.append({"type": "system_message", "text": "工具已损坏。"})
	actions.append(_fish_update_action(spot_id, true, dname))
	actions.append_array(_quest_note_item_actions(iid, qty))
	actions.append_array(_quest_note_fish_actions(iid, qty))
	_apply_gather_skill_xp(actions, 5)
	return {
		"ok": true,
		"actions": actions,
		"item_id": iid,
		"qty": qty,
		"spot_id": spot_id,
		"bait_id": bait_used,
		"tool_broke": fish_tool_broke,
	}


func _tick_fish_respawns() -> Array:
	var actions: Array = []
	if _fish_state.is_empty():
		return actions
	var now: float = _fish_now()
	for sid_v in _fish_state.keys():
		var sid: String = str(sid_v)
		var st: Dictionary = _fish_state[sid]
		if not bool(st.get("depleted", false)):
			continue
		if now < float(st.get("ready_at", 0.0)):
			continue
		_fish_state[sid] = {"depleted": false, "ready_at": 0.0}
		var def: Dictionary = _fish_spots.get(sid, {})
		var dname := str(def.get("name", sid))
		actions.append(_fish_update_action(sid, false, dname))
	return actions


## Test / debug: force one or all depleted fish spots ready immediately.
func force_fish_respawn(spot_id: String = "") -> Array:
	var actions: Array = []
	spot_id = str(spot_id).strip_edges()
	var ids: Array = [spot_id] if spot_id != "" else _fish_state.keys()
	for sid_v in ids:
		var sid: String = str(sid_v)
		if not _fish_state.has(sid):
			continue
		var st: Dictionary = _fish_state[sid]
		if not bool(st.get("depleted", false)):
			continue
		_fish_state[sid] = {"depleted": false, "ready_at": 0.0}
		var def: Dictionary = _fish_spots.get(sid, {})
		actions.append(_fish_update_action(sid, false, str(def.get("name", sid))))
	_fish_busy_until = 0.0
	return actions


func is_fish_depleted(spot_id: String) -> bool:
	spot_id = str(spot_id).strip_edges()
	if not _fish_state.has(spot_id):
		return false
	return bool((_fish_state[spot_id] as Dictionary).get("depleted", false))


## --- Personal warehouse / bank (in-memory; survives map transfer; reset on enter_world) ---

func snapshot_warehouse() -> Dictionary:
	if warehouse == null:
		return {"items": [], "gold": 0, "max_slots": 60, "used_slots": 0}
	return warehouse.snapshot_state()


func _warehouse_update_action() -> Dictionary:
	return {"type": "warehouse_update", "warehouse": snapshot_warehouse()}


func _warehouse_inventory_actions() -> Array:
	var actions: Array = []
	if inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
	actions.append(_warehouse_update_action())
	return actions


func try_warehouse_open() -> Dictionary:
	var actions: Array = []
	actions.append(_warehouse_update_action())
	actions.append({"type": "system_message", "text": "仓库已打开。"})
	return {"ok": true, "actions": actions}


func try_warehouse_deposit(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效的存入数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory == null or warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if not inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "扣除背包物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var add_r: Dictionary = warehouse.try_add_item(item_id, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			warehouse.consume(item_id, added)
		inventory.add_item(item_id, qty)
		var reason := str(add_r.get("reason", "bag_full"))
		var msg := "仓库已满，无法存入。"
		if reason == "stack_full":
			msg = "仓库堆叠已满，无法存入。"
		actions.append({"type": "system_message", "text": msg})
		actions.append_array(_warehouse_inventory_actions())
		return {"ok": false, "reason": "warehouse_full", "actions": actions}
	var iname := item_display_name(item_id)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "存入【%s】×%d。" % [iname, qty]})
	return {"ok": true, "actions": actions}


func try_warehouse_withdraw(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效的取出数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory == null or warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not warehouse.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "仓库中没有足够的物品。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if not warehouse.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "扣除仓库物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(item_id, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			inventory.consume(item_id, added)
		warehouse.add_item(item_id, qty)
		var reason := str(add_r.get("reason", "bag_full"))
		var msg := "背包已满，无法取出。"
		if reason == "stack_full":
			msg = "背包堆叠已满，无法取出。"
		actions.append({"type": "system_message", "text": msg})
		actions.append_array(_warehouse_inventory_actions())
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var iname := item_display_name(item_id)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "取出【%s】×%d。" % [iname, qty]})
	return {"ok": true, "actions": actions}


func try_warehouse_deposit_gold(amount: int) -> Dictionary:
	var actions: Array = []
	amount = int(amount)
	if amount <= 0:
		actions.append({"type": "system_message", "text": "无效的金币数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory == null or warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not inventory.try_spend_gold(amount):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	warehouse.add_gold(amount)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "存入金币 %d。" % amount})
	return {"ok": true, "actions": actions}


func try_warehouse_withdraw_gold(amount: int) -> Dictionary:
	var actions: Array = []
	amount = int(amount)
	if amount <= 0:
		actions.append({"type": "system_message", "text": "无效的金币数量。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory == null or warehouse == null:
		actions.append({"type": "system_message", "text": "仓库不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	if not warehouse.try_spend_gold(amount):
		actions.append({"type": "system_message", "text": "仓库金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	inventory.add_gold(amount)
	actions.append_array(_warehouse_inventory_actions())
	actions.append({"type": "system_message", "text": "取出金币 %d。" % amount})
	return {"ok": true, "actions": actions}


## --- Remote players (AOI/chat shell stubs; not combat NPCs) ---

const NEARBY_CHAT_RANGE := 12  # Chebyshev cells
## Idle roam radius from spawn home (cells). 0 = stand still.
const REMOTE_WANDER_RADIUS := 4
## Shell demo: spawn wandering fake players on enter/transfer (no real netcode).
const AUTO_SPAWN_SHELL_REMOTES := true
const SHELL_REMOTE_COUNT := 1
const SHELL_REMOTE_NAMES := ["旅人甲", "旅人乙", "旅人丙"]
var _remote_players: Dictionary = {}  # id -> {id, name, cell:{x,y}}
var _next_remote_seq: int = 1


func snapshot_remote_players() -> Array:
	var out: Array = []
	for rid in _remote_players.keys():
		var d: Variant = _remote_players[rid]
		if typeof(d) == TYPE_DICTIONARY:
			out.append((d as Dictionary).duplicate(true))
	return out


func get_remote_player(remote_id: String) -> Dictionary:
	remote_id = remote_id.strip_edges()
	if remote_id.is_empty() or not _remote_players.has(remote_id):
		return {}
	return (_remote_players[remote_id] as Dictionary).duplicate(true)


func find_remote_by_name(remote_name: String) -> String:
	remote_name = remote_name.strip_edges()
	if remote_name.is_empty():
		return ""
	for rid in _remote_players.keys():
		var d: Variant = _remote_players[rid]
		if typeof(d) == TYPE_DICTIONARY and str(d.get("name", "")) == remote_name:
			return str(rid)
	# Case-insensitive fallback
	var low := remote_name.to_lower()
	for rid2 in _remote_players.keys():
		var d2: Variant = _remote_players[rid2]
		if typeof(d2) == TYPE_DICTIONARY and str(d2.get("name", "")).to_lower() == low:
			return str(rid2)
	return ""


func _remote_spawn_action(remote_id: String) -> Dictionary:
	var d: Dictionary = get_remote_player(remote_id)
	return {"type": "remote_spawn", "player": d}


func _chebyshev(ax: int, ay: int, bx: int, by: int) -> int:
	return maxi(absi(ax - bx), absi(ay - by))


func _player_xy() -> Vector2i:
	if player_cell.x > -9990:
		return player_cell
	return Vector2i(0, 0)



## Ensure N wandering shell remotes exist (quiet; used on enter/transfer).
func _ensure_shell_remotes(want: int = 1) -> void:
	if not AUTO_SPAWN_SHELL_REMOTES:
		return
	want = clampi(want, 0, SHELL_REMOTE_NAMES.size())
	var i := 0
	while _remote_players.size() < want and i < SHELL_REMOTE_NAMES.size():
		var nm: String = str(SHELL_REMOTE_NAMES[i])
		i += 1
		if find_remote_by_name(nm) != "":
			continue
		var r: Dictionary = try_remote_debug_spawn(nm)
		# Strip chatty system lines from pending — spawn already applied into _remote_players.
		if not bool(r.get("ok", false)):
			continue


func _shell_remote_spawn_actions() -> Array:
	var acts: Array = []
	for rid in _remote_players.keys():
		acts.append(_remote_spawn_action(str(rid)))
	return acts


## Spawn one stub remote near the local player for AOI / nearby chat demos.
func try_remote_debug_spawn(display_name: String = "") -> Dictionary:
	var actions: Array = []
	display_name = str(display_name).strip_edges()
	if display_name.is_empty():
		display_name = "旅人甲"
	# Avoid duplicate names
	if find_remote_by_name(display_name) != "":
		display_name = "%s%d" % [display_name, _next_remote_seq]
	var rid := "remote_%d" % _next_remote_seq
	_next_remote_seq += 1
	var pc := _player_xy()
	# Prefer a free adjacent cell (right, then down, …).
	var offsets: Array = [
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(3, 1), Vector2i(-3, 1), Vector2i(1, 3),
	]
	var cell := Vector2i(pc.x + 2, pc.y)
	for off_v in offsets:
		var off: Vector2i = off_v
		var cand := Vector2i(pc.x + off.x, pc.y + off.y)
		var blocked := false
		if map_collision != null and map_collision.has_method("is_blocked"):
			blocked = bool(map_collision.is_blocked(cand.x, cand.y))
		if cand == pc:
			blocked = true
		for other in _remote_players.values():
			if typeof(other) != TYPE_DICTIONARY:
				continue
			var oc: Variant = other.get("cell", {})
			if typeof(oc) == TYPE_DICTIONARY and int(oc.get("x", -9999)) == cand.x and int(oc.get("y", -9999)) == cand.y:
				blocked = true
				break
		if not blocked:
			cell = cand
			break
	var gender := "female" if (_next_remote_seq % 2) == 1 else "male"
	_remote_players[rid] = {
		"id": rid,
		"name": display_name,
		"cell": {"x": cell.x, "y": cell.y},
		"home": {"x": cell.x, "y": cell.y},
		"wander_radius": REMOTE_WANDER_RADIUS,
		"idle_wander_acc": 0.0,
		"facing": 2,
		"kind": "player",
		"gender": gender,
		"look_id": "1",
		"level": 1,
		"equipment": [],
	}
	actions.append(_remote_spawn_action(rid))
	actions.append({
		"type": "system_message",
		"text": "调试：假玩家【%s】出现在附近（%d,%d）。" % [display_name, cell.x, cell.y],
	})
	return {"ok": true, "remote_id": rid, "actions": actions}



## Fake-player idle patrol: roam within wander_radius of home (same cadence as mob idle).
func _tick_remote_patrol(dt: float) -> Array:
	var actions: Array = []
	if _remote_players.is_empty():
		return actions
	var pc := _player_xy()
	for rid in _remote_players.keys():
		var d: Variant = _remote_players[rid]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = d
		var wander_r: int = maxi(int(row.get("wander_radius", REMOTE_WANDER_RADIUS)), 0)
		if wander_r <= 0:
			continue
		row["idle_wander_acc"] = float(row.get("idle_wander_acc", 0.0)) + dt
		if float(row.get("idle_wander_acc", 0.0)) < MobAI.IDLE_WANDER_INTERVAL_SEC:
			_remote_players[rid] = row
			continue
		row["idle_wander_acc"] = 0.0
		var cell_v: Variant = row.get("cell", {})
		if typeof(cell_v) != TYPE_DICTIONARY:
			_remote_players[rid] = row
			continue
		var cell := Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
		var home_v: Variant = row.get("home", cell_v)
		if typeof(home_v) != TYPE_DICTIONARY:
			home_v = cell_v
		var home := Vector2i(int(home_v.get("x", cell.x)), int(home_v.get("y", cell.y)))
		var wdir: int = MobAI.next_idle_wander_dir(map_collision, cell, home, wander_r)
		if wdir == 0:
			_remote_players[rid] = row
			continue
		var delta: Vector2i = TileId.dir_delta(wdir)
		var next := Vector2i(cell.x + delta.x, cell.y + delta.y)
		if next == pc:
			_remote_players[rid] = row
			continue
		var stacked := false
		for oid in _remote_players.keys():
			if str(oid) == str(rid):
				continue
			var od: Variant = _remote_players[oid]
			if typeof(od) != TYPE_DICTIONARY:
				continue
			var oc: Variant = od.get("cell", {})
			if typeof(oc) == TYPE_DICTIONARY and int(oc.get("x", -9999)) == next.x and int(oc.get("y", -9999)) == next.y:
				stacked = true
				break
		if stacked:
			_remote_players[rid] = row
			continue
		row["cell"] = {"x": next.x, "y": next.y}
		row["facing"] = wdir
		_remote_players[rid] = row
		actions.append({
			"type": "remote_move",
			"player_id": str(rid),
			"x": next.x,
			"y": next.y,
			"facing": wdir,
		})
	return actions


func try_remote_despawn(remote_id: String = "") -> Dictionary:
	var actions: Array = []
	remote_id = str(remote_id).strip_edges()
	if remote_id.is_empty():
		# Despawn all
		for rid in _remote_players.keys():
			actions.append({"type": "remote_despawn", "player_id": str(rid)})
		_remote_players.clear()
		return {"ok": true, "actions": actions}
	if not _remote_players.has(remote_id):
		return {"ok": false, "reason": "not_found", "actions": actions}
	_remote_players.erase(remote_id)
	actions.append({"type": "remote_despawn", "player_id": remote_id})
	return {"ok": true, "actions": actions}


## Chat shell: channel = nearby|whisper|all|party|clan|trade|alliance
## whisper_to = display name or remote id for whisper.
func try_chat(channel: String, text: String, whisper_to: String = "") -> Dictionary:
	var actions: Array = []
	channel = str(channel).strip_edges().to_lower()
	text = str(text).strip_edges()
	whisper_to = str(whisper_to).strip_edges()
	if text.is_empty():
		return {"ok": false, "reason": "empty", "actions": actions}
	var speaker := _party_self_name()
	var speaker_id := _party_self_id()
	match channel:
		"whisper", "w", "tell":
			channel = "whisper"
			if whisper_to.is_empty():
				actions.append({"type": "system_message", "text": "私聊格式：/w 名字 内容"})
				return {"ok": false, "reason": "no_target", "actions": actions}
			var tid := find_remote_by_name(whisper_to)
			if tid.is_empty() and _remote_players.has(whisper_to):
				tid = whisper_to
			if tid.is_empty():
				actions.append({"type": "system_message", "text": "找不到玩家【%s】。" % whisper_to})
				return {"ok": false, "reason": "not_found", "actions": actions}
			var target: Dictionary = _remote_players[tid]
			var tname := str(target.get("name", whisper_to))
			actions.append({
				"type": "chat_message",
				"channel": "whisper",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"target": tname,
				"target_id": tid,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}
		"nearby", "say", "local":
			channel = "nearby"
			actions.append({
				"type": "chat_message",
				"channel": "nearby",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			var pc := _player_xy()
			var heard := 0
			for rid in _remote_players.keys():
				var d: Variant = _remote_players[rid]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				var row: Dictionary = d
				var cv: Variant = row.get("cell", {})
				if typeof(cv) != TYPE_DICTIONARY:
					continue
				var rx := int(cv.get("x", -9999))
				var ry := int(cv.get("y", -9999))
				if _chebyshev(pc.x, pc.y, rx, ry) > NEARBY_CHAT_RANGE:
					continue
				heard += 1
				var rname := str(row.get("name", rid))
				# Delivery echo: remote "hears" the line (shell AOI stub).
				actions.append({
					"type": "chat_message",
					"channel": "nearby",
					"speaker": speaker,
					"speaker_id": speaker_id,
					"text": text,
					"self": false,
					"heard_by": rname,
					"heard_by_id": str(rid),
				})
			if heard == 0:
				actions.append({"type": "system_message", "text": "附近没有人听到。"})
			return {"ok": true, "actions": actions}
		"party":
			if not in_party():
				actions.append({"type": "system_message", "text": "你尚未组队，队伍频道仅本地可见。"})
			actions.append({
				"type": "chat_message",
				"channel": "party",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}
		"all", "shout", "yell":
			channel = "all"
			actions.append({
				"type": "chat_message",
				"channel": "all",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}
		_:
			# clan / trade / alliance — local echo only for now
			actions.append({
				"type": "chat_message",
				"channel": channel,
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}




## --- Personal map pins (waypoints) -----------------------------------------

func snapshot_map_pins() -> Dictionary:
	var pins: Array = []
	for p in _map_pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		pins.append((p as Dictionary).duplicate(true))
	return {"pins": pins, "count": pins.size(), "max": MAP_PIN_MAX}


func list_map_pins_for_map(map_id: String = "") -> Array:
	map_id = str(map_id).strip_edges()
	if map_id.is_empty():
		map_id = str(map_pack_id).strip_edges()
	var out: Array = []
	for p in _map_pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var mid := str(p.get("map_id", "")).strip_edges()
		if mid != "" and map_id != "" and mid != map_id:
			continue
		out.append((p as Dictionary).duplicate(true))
	return out


func _map_pins_update_action() -> Dictionary:
	return {"type": "map_pins_update", "map_pins": snapshot_map_pins()}


func _map_pin_slot_free() -> int:
	var used: Dictionary = {}
	for p in _map_pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		used[int(p.get("slot", 0))] = true
	for s in range(1, MAP_PIN_MAX + 1):
		if not used.has(s):
			return s
	return 0


func _find_map_pin_index(x: int, y: int, map_id: String) -> int:
	map_id = str(map_id).strip_edges()
	for i in range(_map_pins.size()):
		var p: Variant = _map_pins[i]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var cell_v: Variant = p.get("cell", {})
		var cx := 0
		var cy := 0
		if typeof(cell_v) == TYPE_VECTOR2I:
			cx = cell_v.x
			cy = cell_v.y
		elif typeof(cell_v) == TYPE_DICTIONARY:
			cx = int(cell_v.get("x", 0))
			cy = int(cell_v.get("y", 0))
		else:
			continue
		if cx != x or cy != y:
			continue
		var mid := str(p.get("map_id", "")).strip_edges()
		if map_id != "" and mid != "" and mid != map_id:
			continue
		return i
	return -1


## Toggle personal pin at cell. Same cell clears; max MAP_PIN_MAX.
## Optional short_name overrides default 「标记N」.
func try_map_pin_toggle(x: int, y: int, map_id: String = "", short_name: String = "") -> Dictionary:
	var actions: Array = []
	map_id = str(map_id).strip_edges()
	if map_id.is_empty():
		map_id = str(map_pack_id).strip_edges()
	short_name = str(short_name).strip_edges()
	var idx := _find_map_pin_index(x, y, map_id)
	if idx >= 0:
		var old: Dictionary = _map_pins[idx]
		var old_name := str(old.get("name", "标记")).strip_edges()
		_map_pins.remove_at(idx)
		actions.append(_map_pins_update_action())
		actions.append({"type": "system_message", "text": "已清除标记：%s" % (old_name if old_name != "" else "标记")})
		return {"ok": true, "cleared": true, "actions": actions, "map_pins": snapshot_map_pins()}
	if _map_pins.size() >= MAP_PIN_MAX:
		actions.append({"type": "system_message", "text": "个人标记已满（最多 %d 个）。" % MAP_PIN_MAX})
		return {"ok": false, "reason": "full", "actions": actions, "map_pins": snapshot_map_pins()}
	var slot := _map_pin_slot_free()
	if slot <= 0:
		actions.append({"type": "system_message", "text": "个人标记已满（最多 %d 个）。" % MAP_PIN_MAX})
		return {"ok": false, "reason": "full", "actions": actions, "map_pins": snapshot_map_pins()}
	var nm := short_name if short_name != "" else "标记%d" % slot
	var pin := {
		"id": "pin_%d" % slot,
		"slot": slot,
		"name": nm,
		"map_id": map_id,
		"cell": {"x": x, "y": y},
	}
	_map_pins.append(pin)
	actions.append(_map_pins_update_action())
	actions.append({"type": "system_message", "text": "标记：%s (%d, %d)" % [nm, x, y]})
	return {"ok": true, "cleared": false, "pin": pin.duplicate(true), "actions": actions, "map_pins": snapshot_map_pins()}


func try_map_pin_clear() -> Dictionary:
	var actions: Array = []
	if _map_pins.is_empty():
		actions.append({"type": "system_message", "text": "当前没有个人标记。"})
		return {"ok": true, "cleared": 0, "actions": actions, "map_pins": snapshot_map_pins()}
	var n: int = _map_pins.size()
	_map_pins.clear()
	actions.append(_map_pins_update_action())
	actions.append({"type": "system_message", "text": "已清除全部标记（%d）" % n})
	return {"ok": true, "cleared": n, "actions": actions, "map_pins": snapshot_map_pins()}


func snapshot_friends() -> Dictionary:
	return _friends_module_logic.snapshot_friends()
func _friends_update_action() -> Dictionary:
	return _friends_module_logic._friends_update_action()
## Resolve name_or_id against remotes / party stubs / known shell display names.
## Returns {ok, id, name, reason}.
func _resolve_friend_target(name_or_id: String) -> Dictionary:
	return _friends_module_logic._resolve_friend_target(name_or_id)
func try_friend_add(name_or_id: String) -> Dictionary:
	return _friends_module_logic.try_friend_add(name_or_id)
func try_friend_remove(friend_id: String) -> Dictionary:
	return _friends_module_logic.try_friend_remove(friend_id)
## --- Personal mailbox shell (in-memory; survives map transfer; reset on enter_world) ---

func snapshot_mail() -> Dictionary:
	return _mail_module_logic.snapshot_mail()
func _mail_update_action() -> Dictionary:
	return _mail_module_logic._mail_update_action()
func _mail_inventory_actions() -> Array:
	return _mail_module_logic._mail_inventory_actions()
func _mail_inject_welcome() -> void:
	_mail_module_logic._mail_inject_welcome()
## Local calendar date YYYY-MM-DD (MockServer host clock).
func _attendance_today_ymd() -> String:
	var d: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0))]


## Test helper: set last claim ymd ("" clears so next grant can fire).
func force_attendance_ymd(ymd: String) -> void:
	_attendance_last_ymd = str(ymd).strip_edges()


## Once per local day: mail gold+potion from 系统; queue system_message. Returns actions.
func _attendance_try_grant() -> Array:
	var actions: Array = []
	var today := _attendance_today_ymd()
	if today.is_empty():
		return actions
	if _attendance_last_ymd == today:
		return actions
	if mailbox == null:
		mailbox = Mailbox.new()
	var to_name := _party_self_name()
	var attach: Array = [{"id": "potion_hp_small", "qty": 1}]
	var add_r: Dictionary = mailbox.try_add(
		"系统",
		to_name,
		"每日签到奖励",
		"感谢你今日登录！请领取签到奖励：金币与回复药水。",
		50,
		attach
	)
	if not bool(add_r.get("ok", false)):
		# Inbox full — skip claim so we can retry next enter; do not stamp last ymd.
		actions.append({"type": "system_message", "text": "邮箱已满，今日签到奖励未能送达。"})
		_pending_tick_actions.append_array(actions)
		return actions
	_attendance_last_ymd = today
	actions.append({"type": "system_message", "text": "今日签到奖励已发送至邮箱。"})
	actions.append(_mail_update_action())
	_pending_tick_actions.append_array(actions)
	return actions


func _resolve_mail_recipient(to_name: String) -> Dictionary:
	return _mail_module_logic._resolve_mail_recipient(to_name)
func try_mail_send(to: String, subject: String, body: String, gold: int = 0, item_id: String = "", qty: int = 1) -> Dictionary:
	return _mail_module_logic.try_mail_send(to, subject, body, gold, item_id, qty)
func try_mail_read(mail_id: String) -> Dictionary:
	return _mail_module_logic.try_mail_read(mail_id)
func try_mail_claim(mail_id: String) -> Dictionary:
	return _mail_module_logic.try_mail_claim(mail_id)
func try_mail_delete(mail_id: String) -> Dictionary:
	return _mail_module_logic.try_mail_delete(mail_id)
func emote_catalog() -> Array:
	## Fixed catalog rows: [{id, label, text}, ...]
	var out: Array = []
	for eid in EMOTE_CATALOG.keys():
		var row: Dictionary = EMOTE_CATALOG[eid]
		out.append({
			"id": str(eid),
			"label": str(row.get("label", eid)),
			"text": str(row.get("text", "")),
		})
	return out


func try_emote(emote_id: String) -> Dictionary:
	## Broadcast-ready text emote bubble above actor. Rate-limited server-side.
	var actions: Array = []
	emote_id = str(emote_id).strip_edges()
	if emote_id.is_empty() or not EMOTE_CATALOG.has(emote_id):
		actions.append({"type": "system_message", "text": "未知表情。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var now: float = _party_clock()
	if now < _emote_cd_until:
		actions.append({"type": "system_message", "text": "表情冷却中。"})
		return {"ok": false, "reason": "cooldown", "actions": actions}
	var def: Dictionary = EMOTE_CATALOG[emote_id]
	var bubble := str(def.get("text", "")).strip_edges()
	if bubble.is_empty():
		bubble = "（%s）" % str(def.get("label", emote_id))
	_emote_cd_until = now + EMOTE_COOLDOWN_SEC
	var actor_id := _party_self_id()
	actions.append({
		"type": "emote",
		"actor_id": actor_id,
		"emote_id": emote_id,
		"text": bubble,
		"duration_sec": EMOTE_DURATION_SEC,
	})
	return {"ok": true, "actions": actions}

## --- Player duel shell (v1: shell remotes auto-accept / instant start) ---
## Auto-accept rule: try_duel_challenge against a spawned shell remote starts the duel
## immediately in the same call (no pending UI). try_duel_accept / try_duel_decline exist
## for pending challenges (e.g. tests / future peers); remotes never wait.

const DUEL_DURATION_SEC := 60.0
const DUEL_STUB_HP := 100
const DUEL_RANGE_CELLS := 1

var _duel: Dictionary = {}  # empty = idle; pending or active session
var _duel_pending: Dictionary = {}  # optional pending challenge before accept

## --- Dungeon instance stub (one-shot → street_map) ---
const DUNGEON_STREET_PACK := "res://street_map"
const DUNGEON_STREET_MAP_ID := "street_map"
const DUNGEON_STREET_SPAWN := Vector2i(41, 23)
const DUNGEON_KILLS_NEEDED := 2
const DUNGEON_REWARD_GOLD := 50
const DUNGEON_REWARD_EXP := 80
const DUNGEON_REWARD_STONE_QTY := 1

var _dungeon: Dictionary = {}  # empty = idle; active one-shot session
var _dungeon_xfer_lock: bool = false  # suppress abandon during enter/exit transfers


func snapshot_duel() -> Dictionary:
	return _duel_module_logic.snapshot_duel()
func in_duel() -> bool:
	return _duel_module_logic.in_duel()
func _duel_update_action() -> Dictionary:
	return _duel_module_logic._duel_update_action()
func _duel_force_clear_silent() -> void:
	_duel_module_logic._duel_force_clear_silent()
func _duel_resolve_target(target_id_or_name: String) -> Dictionary:
	return _duel_module_logic._duel_resolve_target(target_id_or_name)
func _duel_is_opponent(target_id: String) -> bool:
	return _duel_module_logic._duel_is_opponent(target_id)
func _duel_seed_remote_hp(remote_id: String, hp: int, hp_max: int) -> void:
	_duel_module_logic._duel_seed_remote_hp(remote_id, hp, hp_max)
func _duel_clear_remote_hp(remote_id: String) -> void:
	_duel_module_logic._duel_clear_remote_hp(remote_id)
func _duel_start(opponent_id: String, opponent_name: String) -> Array:
	return _duel_module_logic._duel_start(opponent_id, opponent_name)
func _duel_end(reason: String, winner: String = "") -> Array:
	return _duel_module_logic._duel_end(reason, winner)
func _tick_duel() -> Array:
	return _duel_module_logic._tick_duel()
func try_duel_challenge(target_id_or_name: String) -> Dictionary:
	return _duel_module_logic.try_duel_challenge(target_id_or_name)
func try_duel_accept() -> Dictionary:
	return _duel_module_logic.try_duel_accept()
func try_duel_decline() -> Dictionary:
	return _duel_module_logic.try_duel_decline()
func try_duel_forfeit() -> Dictionary:
	return _duel_module_logic.try_duel_forfeit()
## Test / pending helper: queue a pending challenge without auto-start.
func try_duel_debug_pending(target_id_or_name: String) -> Dictionary:
	return _duel_module_logic.try_duel_debug_pending(target_id_or_name)
## Apply damage to duel opponent (tests + attack path). Prefer real try_attack when in range.
func try_duel_debug_hit(amount: int = 25) -> Dictionary:
	return _duel_module_logic.try_duel_debug_hit(amount)
func _duel_player_atk() -> int:
	return _duel_module_logic._duel_player_atk()
func _duel_apply_damage(amount: int) -> Array:
	return _duel_module_logic._duel_apply_damage(amount)
func _try_duel_attack_target(target_id: String, player_x: int, player_y: int) -> Dictionary:
	return _duel_module_logic._try_duel_attack_target(target_id, player_x, player_y)
## Thin resurrection: dead party ally / fake-player ally / ally-NPC same map.
## Returns {} when skill is not revive (fall through). Otherwise always a result dict.
func _try_revive_skill(skill_id: String, target_id: String, player_x: int, player_y: int) -> Dictionary:
	skill_id = str(skill_id).strip_edges()
	target_id = str(target_id).strip_edges()
	if skill_id.is_empty():
		return {}
	var def: Dictionary = skill_def(skill_id) if has_method("skill_def") else {}
	if def.is_empty() or str(def.get("effect", "")).strip_edges() != "revive":
		return {}
	var actions: Array = []
	# Caster must be alive (cannot self-revive while dead).
	if awaiting_respawn or (combat_stats != null and not combat_stats.player_alive()):
		actions.append({"type": "system_message", "text": "无法自我复活。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if combat_stats == null:
		actions.append({"type": "system_message", "text": "无法施放。"})
		return {"ok": false, "reason": "no_combat", "actions": actions}
	# Must know the skill.
	if combat_stats.skill_book != null and combat_stats.skill_book.has_method("is_known"):
		if not combat_stats.skill_book.is_known(skill_id):
			var sname := str(def.get("name", skill_id))
			actions.append({"type": "system_message", "text": "尚未学会【%s】。" % sname})
			return {"ok": false, "reason": "unlearned", "actions": actions}
	if combat_stats.has_method("is_skill_ready") and not combat_stats.is_skill_ready(skill_id):
		var rem: float = combat_stats.skill_cd_remaining(skill_id) if combat_stats.has_method("skill_cd_remaining") else 0.0
		actions.append({"type": "system_message", "text": "技能冷却中（%.1f 秒）。" % rem})
		actions.append({
			"type": "skill_cd",
			"skill_id": skill_id,
			"remaining": rem,
			"cooldown": float(def.get("cooldown", 30.0)),
		})
		return {"ok": false, "reason": "cooldown", "actions": actions}
	var mp_cost: int = int(def.get("mp_cost", 25))
	if int(combat_stats.player.get("mp", 0)) < mp_cost:
		actions.append({"type": "system_message", "text": "MP 不足。"})
		return {"ok": false, "reason": "mp", "actions": actions}
	if target_id.is_empty():
		actions.append({"type": "system_message", "text": "需要目标。"})
		return {"ok": false, "reason": "need_target", "actions": actions}
	var self_id := _party_self_id()
	if target_id == self_id or target_id == "player":
		actions.append({"type": "system_message", "text": "无法自我复活。"})
		return {"ok": false, "reason": "self", "actions": actions}
	var range_cells: int = maxi(1, int(def.get("range", 4)))
	var resolved: Dictionary = _revive_resolve_target(target_id)
	if resolved.is_empty():
		actions.append({"type": "system_message", "text": "只能复活队友。"})
		return {"ok": false, "reason": "not_ally", "actions": actions}
	var kind := str(resolved.get("kind", ""))
	var mid := str(resolved.get("id", target_id))
	var mname := str(resolved.get("name", mid)).strip_edges()
	if mname.is_empty():
		mname = mid
	# Same-map check for party/remote (empty map_id = same-map shell).
	var mmap := str(resolved.get("map_id", "")).strip_edges()
	if mmap != "" and mmap != map_pack_id:
		actions.append({"type": "system_message", "text": "只能复活队友。"})
		return {"ok": false, "reason": "not_same_map", "actions": actions}
	var tx: int = int(resolved.get("x", -9999))
	var ty: int = int(resolved.get("y", -9999))
	if tx <= -9990 or ty <= -9990:
		actions.append({"type": "system_message", "text": "目标太远。"})
		return {"ok": false, "reason": "no_cell", "actions": actions}
	if _chebyshev(player_x, player_y, tx, ty) > range_cells:
		actions.append({"type": "system_message", "text": "目标太远。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var hp_now: int = int(resolved.get("hp", 0))
	var awaiting: bool = bool(resolved.get("awaiting_respawn", false))
	if hp_now > 0 and not awaiting:
		actions.append({"type": "system_message", "text": "目标未死亡。"})
		return {"ok": false, "reason": "alive", "actions": actions}
	# Spend MP + CD.
	var p: Dictionary = combat_stats.player
	p["mp"] = int(p.get("mp", 0)) - mp_cost
	combat_stats.player = p
	var cd: float = float(def.get("cooldown", 30.0))
	if combat_stats.has_method("set_skill_cooldown"):
		combat_stats.set_skill_cooldown(skill_id, cd)
	actions.append({
		"type": "skill_cd",
		"skill_id": skill_id,
		"remaining": cd,
		"cooldown": cd,
	})
	var hp_max: int = maxi(1, int(resolved.get("hp_max", 100)))
	var pct: float = float(def.get("heal_pct", 0.3))
	if pct <= 0.0:
		pct = 0.3
	var new_hp: int = maxi(1, int(round(float(hp_max) * pct)))
	# Keep death cell (or nearest walkable).
	var dest := Vector2i(tx, ty)
	if map_collision != null and map_collision.has_method("is_landable"):
		if not map_collision.is_landable(dest.x, dest.y) and map_collision.has_method("find_spawn_near"):
			dest = map_collision.find_spawn_near(dest.x, dest.y)
	_revive_apply_to_target(kind, mid, new_hp, hp_max, dest, actions)
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(combat_stats.player.get("hp", 0)),
		"hp_max": int(combat_stats.player.get("hp_max", 0)),
		"mp": int(combat_stats.player.get("mp", 0)),
		"mp_max": int(combat_stats.player.get("mp_max", 0)),
	})
	actions.append({"type": "system_message", "text": "复活了%s！" % mname})
	actions.append({
		"type": "ally_revived",
		"id": mid,
		"kind": kind,
		"hp": new_hp,
		"hp_max": hp_max,
		"cell": {"x": dest.x, "y": dest.y},
	})
	if in_party():
		_party_refresh_self_member()
		actions.append(_party_update_action())
	return {"ok": true, "actions": actions}


## Resolve revive target: party member, fake remote ally, or ally-flagged NPC.
## Returns {kind, id, name, hp, hp_max, awaiting_respawn, x, y, map_id} or {}.
func _revive_resolve_target(target_id: String) -> Dictionary:
	target_id = target_id.strip_edges()
	if target_id.is_empty():
		return {}
	# Party member (stub / remote id / name).
	var pidx := _party_find_member_index(target_id)
	if pidx < 0:
		pidx = _party_find_member_by_name(target_id)
	if pidx >= 0 and in_party():
		var m: Dictionary = _party_members[pidx]
		var mid := str(m.get("id", "")).strip_edges()
		if mid == _party_self_id():
			return {}
		var cell := _revive_member_cell(m)
		return {
			"kind": "party",
			"id": mid,
			"name": str(m.get("name", mid)),
			"hp": int(m.get("hp", 0)),
			"hp_max": int(m.get("hp_max", 100)),
			"awaiting_respawn": bool(m.get("awaiting_respawn", false)),
			"x": cell.x,
			"y": cell.y,
			"map_id": str(m.get("map_id", "")),
		}
	# Fake remote player that is also in party (or marked ally).
	var rid := target_id
	if not _remote_players.has(rid):
		rid = find_remote_by_name(target_id)
	if rid != "" and _remote_players.has(rid):
		var rd: Dictionary = _remote_players[rid]
		var in_p := _party_find_member_index(rid) >= 0
		var marked_ally := bool(rd.get("ally", false)) or bool(rd.get("party_ally", false))
		if not in_p and not marked_ally:
			# Allow revive if currently in party with this remote by name match.
			var rn := str(rd.get("name", "")).strip_edges()
			if rn != "" and _party_find_member_by_name(rn) >= 0:
				in_p = true
		if in_p or marked_ally:
			var cell_v: Variant = rd.get("death_cell", rd.get("cell", {}))
			var cx := -9999
			var cy := -9999
			if typeof(cell_v) == TYPE_DICTIONARY:
				cx = int(cell_v.get("x", -9999))
				cy = int(cell_v.get("y", -9999))
			return {
				"kind": "remote",
				"id": rid,
				"name": str(rd.get("name", rid)),
				"hp": int(rd.get("hp", 0)),
				"hp_max": int(rd.get("hp_max", 100)),
				"awaiting_respawn": bool(rd.get("awaiting_respawn", false)),
				"x": cx,
				"y": cy,
				"map_id": str(rd.get("map_id", "")),
			}
	# Ally-flagged NPC (combat layer).
	if combat_stats != null and combat_stats.npcs.has(target_id):
		var st: Dictionary = combat_stats.npcs[target_id]
		if bool(st.get("ally", false)):
			var ncell: Vector2i = combat_stats.get_npc_cell(target_id)
			return {
				"kind": "npc",
				"id": target_id,
				"name": str(st.get("name", target_id)),
				"hp": int(st.get("hp", 0)),
				"hp_max": int(st.get("hp_max", 100)),
				"awaiting_respawn": bool(st.get("awaiting_respawn", false)),
				"x": ncell.x,
				"y": ncell.y,
				"map_id": "",
			}
	return {}


func _revive_member_cell(m: Dictionary) -> Vector2i:
	var cell_v: Variant = m.get("death_cell", m.get("cell", {}))
	if typeof(cell_v) == TYPE_DICTIONARY:
		var cx := int(cell_v.get("x", -9999))
		var cy := int(cell_v.get("y", -9999))
		if cx > -9990 and cy > -9990:
			return Vector2i(cx, cy)
	elif typeof(cell_v) == TYPE_VECTOR2I:
		var cv: Vector2i = cell_v
		if cv.x > -9990:
			return cv
	# Fallback: if member id is a remote, use remote cell.
	var mid := str(m.get("id", "")).strip_edges()
	if mid != "" and _remote_players.has(mid):
		var rd: Dictionary = _remote_players[mid]
		var rc: Variant = rd.get("death_cell", rd.get("cell", {}))
		if typeof(rc) == TYPE_DICTIONARY:
			return Vector2i(int(rc.get("x", -9999)), int(rc.get("y", -9999)))
	return Vector2i(-9999, -9999)


func _revive_apply_to_target(
	kind: String, mid: String, new_hp: int, hp_max: int, dest: Vector2i, actions: Array
) -> void:
	kind = kind.strip_edges()
	mid = mid.strip_edges()
	if kind == "party":
		var idx := _party_find_member_index(mid)
		if idx >= 0:
			var m: Dictionary = _party_members[idx]
			m["hp"] = new_hp
			m["hp_max"] = hp_max
			m["awaiting_respawn"] = false
			m["cell"] = {"x": dest.x, "y": dest.y}
			m.erase("death_cell")
			_party_members[idx] = m
		# Keep remote mirror in sync when party id is a remote.
		if _remote_players.has(mid):
			var rd: Dictionary = _remote_players[mid]
			rd["hp"] = new_hp
			rd["hp_max"] = hp_max
			rd["awaiting_respawn"] = false
			rd["cell"] = {"x": dest.x, "y": dest.y}
			rd.erase("death_cell")
			_remote_players[mid] = rd
			actions.append({
				"type": "remote_move",
				"player_id": mid,
				"x": dest.x,
				"y": dest.y,
				"facing": int(rd.get("facing", 2)),
			})
			actions.append({
				"type": "set_stat",
				"target": mid,
				"hp": new_hp,
				"hp_max": hp_max,
			})
	elif kind == "remote":
		if _remote_players.has(mid):
			var rd2: Dictionary = _remote_players[mid]
			rd2["hp"] = new_hp
			rd2["hp_max"] = hp_max
			rd2["awaiting_respawn"] = false
			rd2["cell"] = {"x": dest.x, "y": dest.y}
			rd2.erase("death_cell")
			_remote_players[mid] = rd2
			actions.append({
				"type": "remote_move",
				"player_id": mid,
				"x": dest.x,
				"y": dest.y,
				"facing": int(rd2.get("facing", 2)),
			})
			actions.append({
				"type": "set_stat",
				"target": mid,
				"hp": new_hp,
				"hp_max": hp_max,
			})
		var pidx := _party_find_member_index(mid)
		if pidx >= 0:
			var pm: Dictionary = _party_members[pidx]
			pm["hp"] = new_hp
			pm["hp_max"] = hp_max
			pm["awaiting_respawn"] = false
			pm["cell"] = {"x": dest.x, "y": dest.y}
			pm.erase("death_cell")
			_party_members[pidx] = pm
	elif kind == "npc":
		if combat_stats != null and combat_stats.npcs.has(mid):
			var st: Dictionary = combat_stats.npcs[mid]
			st["hp"] = new_hp
			st["hp_max"] = hp_max
			st["awaiting_respawn"] = false
			combat_stats.npcs[mid] = st
			combat_stats.set_npc_cell(mid, dest.x, dest.y)
			if combat_stats.statuses != null:
				combat_stats.statuses.clear_all_on_death(mid)
			if combat_stats.npc_ai.has(mid):
				var ai: Dictionary = combat_stats.npc_ai[mid]
				ai["ai_state"] = "idle"
				ai["chase_target"] = ""
				ai["victim_id"] = ""
				ai["respawn_acc"] = 0.0
				combat_stats.npc_ai[mid] = ai
			actions.append({
				"type": "set_stat",
				"target": mid,
				"id": mid,
				"hp": new_hp,
				"hp_max": hp_max,
			})


## Test/shell helper: mark a party member (or remote ally) dead at a cell.
func debug_ally_kill(member_id: String, cell_x: int = -9999, cell_y: int = -9999) -> Dictionary:
	member_id = str(member_id).strip_edges()
	var actions: Array = []
	if member_id.is_empty():
		return {"ok": false, "reason": "empty", "actions": actions}
	var dest := Vector2i(cell_x, cell_y)
	if dest.x <= -9990:
		dest = Vector2i(player_cell.x + 1, player_cell.y) if player_cell.x > -9990 else Vector2i(1, 0)
	var idx := _party_find_member_index(member_id)
	if idx < 0:
		idx = _party_find_member_by_name(member_id)
	if idx >= 0:
		var m: Dictionary = _party_members[idx]
		m["hp"] = 0
		m["awaiting_respawn"] = true
		m["death_cell"] = {"x": dest.x, "y": dest.y}
		m["cell"] = {"x": dest.x, "y": dest.y}
		_party_members[idx] = m
		var mid := str(m.get("id", member_id))
		if _remote_players.has(mid):
			var rd: Dictionary = _remote_players[mid]
			rd["hp"] = 0
			rd["awaiting_respawn"] = true
			rd["death_cell"] = {"x": dest.x, "y": dest.y}
			rd["cell"] = {"x": dest.x, "y": dest.y}
			if not rd.has("hp_max"):
				rd["hp_max"] = int(m.get("hp_max", 100))
			_remote_players[mid] = rd
		actions.append(_party_update_action())
		actions.append({"type": "system_message", "text": "%s倒下了。" % str(m.get("name", mid))})
		return {"ok": true, "actions": actions}
	if _remote_players.has(member_id) or find_remote_by_name(member_id) != "":
		var rid := member_id if _remote_players.has(member_id) else find_remote_by_name(member_id)
		var rd2: Dictionary = _remote_players[rid]
		rd2["hp"] = 0
		rd2["hp_max"] = int(rd2.get("hp_max", 100))
		rd2["awaiting_respawn"] = true
		rd2["ally"] = true
		rd2["death_cell"] = {"x": dest.x, "y": dest.y}
		rd2["cell"] = {"x": dest.x, "y": dest.y}
		_remote_players[rid] = rd2
		actions.append({"type": "system_message", "text": "%s倒下了。" % str(rd2.get("name", rid))})
		return {"ok": true, "remote_id": rid, "actions": actions}
	if combat_stats != null and combat_stats.npcs.has(member_id):
		var st: Dictionary = combat_stats.npcs[member_id]
		st["hp"] = 0
		st["awaiting_respawn"] = true
		st["ally"] = true
		combat_stats.npcs[member_id] = st
		combat_stats.set_npc_cell(member_id, dest.x, dest.y)
		actions.append({"type": "system_message", "text": "%s倒下了。" % str(st.get("name", member_id))})
		return {"ok": true, "actions": actions}
	return {"ok": false, "reason": "not_found", "actions": actions}


func _try_duel_skill_target(skill_id: String, target_id: String, player_x: int, player_y: int) -> Dictionary:
	return _duel_module_logic._try_duel_skill_target(skill_id, target_id, player_x, player_y)
## --- Title / achievement thin shell ---

func snapshot_titles() -> Dictionary:
	if combat_stats == null:
		return {
			"counters": {"kills": 0, "crafts": 0, "deaths": 0},
			"unlocked_titles": [],
			"active_title": "",
			"titles": [],
			"kills": 0,
			"crafts": 0,
			"deaths": 0,
		}
	var snap: Dictionary = combat_stats.snapshot_titles()
	var rows: Array = []
	var unlocked: Array = snap.get("unlocked_titles", [])
	var have: Dictionary = {}
	for u in unlocked:
		have[str(u)] = true
	var catalog_rows: Array = []
	if title_catalog != null:
		catalog_rows = title_catalog.list_all()
	for def in catalog_rows:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var tid := str(def.get("id", ""))
		var row: Dictionary = def.duplicate(true)
		row["unlocked"] = have.has(tid)
		row["active"] = tid == str(snap.get("active_title", ""))
		rows.append(row)
	snap["titles"] = rows
	return snap


func _title_update_action() -> Dictionary:
	return {"type": "title_update", "titles": snapshot_titles()}


## Bump counter + grant newly met titles. Returns actions (system_message unlocks + title_update).
func _note_title_counter(key: String, amount: int = 1) -> Array:
	var actions: Array = []
	if combat_stats == null or amount == 0:
		return actions
	combat_stats.bump_title_counter(key, amount)
	if title_catalog == null:
		actions.append(_title_update_action())
		return actions
	var newly: Array = title_catalog.check_unlocks(
		combat_stats.title_counters,
		combat_stats.unlocked_titles
	)
	for tid in newly:
		if combat_stats.unlock_title(str(tid)):
			var tname: String = str(title_catalog.title_name(str(tid)))
			actions.append({"type": "system_message", "text": "解锁称号：%s" % tname})
	actions.append(_title_update_action())
	return actions


## Equip unlocked title (empty id = unequip).
func try_title_equip(title_id: String) -> Dictionary:
	var actions: Array = []
	title_id = str(title_id).strip_edges()
	if combat_stats == null:
		actions.append({"type": "system_message", "text": "称号不可用。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if title_id.is_empty():
		var r0: Dictionary = combat_stats.try_title_equip("")
		actions.append(_title_update_action())
		actions.append({"type": "system_message", "text": "已卸下称号。"})
		return {"ok": bool(r0.get("ok", false)), "reason": str(r0.get("reason", "")), "actions": actions}
	if title_catalog != null and not title_catalog.has_title(title_id):
		actions.append({"type": "system_message", "text": "未知称号。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	var r: Dictionary = combat_stats.try_title_equip(title_id)
	if not bool(r.get("ok", false)):
		var reason := str(r.get("reason", "locked"))
		var msg := "尚未解锁该称号。"
		if reason == "unknown":
			msg = "未知称号。"
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var tname: String = title_id
	if title_catalog != null:
		tname = str(title_catalog.title_name(title_id))
	actions.append(_title_update_action())
	actions.append({"type": "system_message", "text": "已装备称号：%s" % tname})
	return {"ok": true, "actions": actions}


## --- Achievement thin shell ---

func snapshot_achievements() -> Dictionary:
	if combat_stats == null:
		return {
			"counters": {"kills": 0, "gathers": 0, "level": 1, "party": 0},
			"unlocked_achievements": [],
			"achievements": [],
			"kills": 0,
			"gathers": 0,
			"level": 1,
			"party": 0,
		}
	var snap: Dictionary = combat_stats.snapshot_achievements()
	var rows: Array = []
	var unlocked: Array = snap.get("unlocked_achievements", [])
	var have: Dictionary = {}
	for u in unlocked:
		have[str(u)] = true
	var catalog_rows: Array = []
	if achievement_catalog != null:
		catalog_rows = achievement_catalog.list_all()
	for def in catalog_rows:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var aid := str(def.get("id", ""))
		var row: Dictionary = def.duplicate(true)
		row["unlocked"] = have.has(aid)
		rows.append(row)
	snap["achievements"] = rows
	return snap


func _achievement_update_action() -> Dictionary:
	return {"type": "achievement_update", "achievements": snapshot_achievements()}


func _grant_achievement_reward(def: Dictionary) -> Array:
	var actions: Array = []
	var rew_v: Variant = def.get("reward", {})
	if typeof(rew_v) != TYPE_DICTIONARY:
		return actions
	var rew: Dictionary = rew_v
	var gold: int = maxi(int(rew.get("gold", 0)), 0)
	var exp_amt: int = maxi(int(rew.get("exp", 0)), 0)
	if gold > 0 and inventory != null:
		inventory.add_gold(gold)
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "成就奖励：金币 +%d" % gold})
	if exp_amt > 0 and combat_stats != null:
		var summary: Dictionary = combat_stats.grant_exp(exp_amt)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", exp_amt)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "成就奖励：经验 +%d" % int(summary.get("amount", exp_amt))})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				actions.append({"type": "level_up", "level": int(lv_v), "combat": combat_snap})
				actions.append({"type": "system_message", "text": "升级到 Lv.%d！" % int(lv_v)})
			_append_level_up_sp(actions, summary.get("levels_gained", []))
			actions.append({
				"type": "set_stat",
				"target": "player",
				"hp": int(combat_snap.get("hp", 0)),
				"hp_max": int(combat_snap.get("hp_max", 0)),
				"mp": int(combat_snap.get("mp", 0)),
				"mp_max": int(combat_snap.get("mp_max", 0)),
				"level": int(combat_snap.get("level", 1)),
				"exp": int(combat_snap.get("exp", 0)),
				"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
				"atk": int(combat_snap.get("atk", 0)),
				"def": int(combat_snap.get("def", 0)),
				"attr_points": int(combat_snap.get("attr_points", 0)),
				"attrs": combat_snap.get("attrs", {}),
			})
	return actions


func _flush_achievement_unlocks() -> Array:
	var actions: Array = []
	if combat_stats == null:
		return actions
	if achievement_catalog == null:
		actions.append(_achievement_update_action())
		return actions
	var newly: Array = achievement_catalog.check_unlocks(
		combat_stats.achievement_counters,
		combat_stats.unlocked_achievements
	)
	for aid in newly:
		if combat_stats.unlock_achievement(str(aid)):
			var def: Dictionary = achievement_catalog.get_achievement(str(aid))
			var aname: String = str(achievement_catalog.achievement_name(str(aid)))
			actions.append({"type": "system_message", "text": "成就解锁：%s" % aname})
			actions.append_array(_grant_achievement_reward(def))
	actions.append(_achievement_update_action())
	return actions


## Bump achievement counter + grant newly met achievements.
func _note_achievement_counter(key: String, amount: int = 1) -> Array:
	var actions: Array = []
	if combat_stats == null or amount == 0:
		return actions
	combat_stats.bump_achievement_counter(key, amount)
	actions.append_array(_flush_achievement_unlocks())
	return actions


## Raise a counter to at least value (level sync) then flush unlocks.
func _sync_achievement_level(level: int) -> Array:
	var actions: Array = []
	if combat_stats == null:
		return actions
	var before: int = int(combat_stats.achievement_counters.get("level", 1))
	var after: int = combat_stats.set_achievement_counter_at_least("level", level)
	if after == before and after < level:
		return actions
	if after == before:
		# Still flush in case require was already met but unlock pending (tests).
		pass
	actions.append_array(_flush_achievement_unlocks())
	return actions


## Test helper: force counter absolute value then unlock path.
func force_achievement_progress(key: String, value: int) -> Dictionary:
	var actions: Array = []
	key = str(key).strip_edges()
	if combat_stats == null or key.is_empty():
		return {"ok": false, "reason": "no_stats", "actions": actions}
	combat_stats.achievement_counters[key] = maxi(int(value), 0)
	actions.append_array(_flush_achievement_unlocks())
	return {"ok": true, "actions": actions, "achievements": snapshot_achievements()}


## Test helper: force unlock by id (ignores require).
func force_achievement_unlock(ach_id: String) -> Dictionary:
	var actions: Array = []
	ach_id = str(ach_id).strip_edges()
	if combat_stats == null:
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if achievement_catalog != null and not achievement_catalog.has_achievement(ach_id):
		actions.append({"type": "system_message", "text": "未知成就。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if not combat_stats.unlock_achievement(ach_id):
		return {"ok": false, "reason": "already", "actions": actions, "achievements": snapshot_achievements()}
	var def: Dictionary = {}
	if achievement_catalog != null:
		def = achievement_catalog.get_achievement(ach_id)
	var aname: String = ach_id
	if achievement_catalog != null:
		aname = str(achievement_catalog.achievement_name(ach_id))
	actions.append({"type": "system_message", "text": "成就解锁：%s" % aname})
	actions.append_array(_grant_achievement_reward(def))
	actions.append(_achievement_update_action())
	return {"ok": true, "actions": actions, "achievements": snapshot_achievements()}


## --- Guild / clan shell (in-memory; reset on enter_world) ---

func snapshot_guild() -> Dictionary:
	return _guild_module_logic.snapshot_guild()
func _guild_update_action() -> Dictionary:
	return _guild_module_logic._guild_update_action()
func in_guild() -> bool:
	return _guild_module_logic.in_guild()
func _guild_self_id() -> String:
	return _guild_module_logic._guild_self_id()
func _guild_self_name() -> String:
	return _guild_module_logic._guild_self_name()
func try_guild_create(guild_name: String) -> Dictionary:
	return _guild_module_logic.try_guild_create(guild_name)
## Invite by name / remote id / friend. Stub remotes & known names auto-join.
func try_guild_invite(target: String) -> Dictionary:
	return _guild_module_logic.try_guild_invite(target)
## Inject an incoming invite for local player (accept/decline shell).
func try_guild_incoming_invite(from_name: String = "旅人甲", guild_name: String = "测试公会") -> Dictionary:
	return _guild_module_logic.try_guild_incoming_invite(from_name, guild_name)
func try_guild_invite_respond(invite_id: String, accept: bool) -> Dictionary:
	return _guild_module_logic.try_guild_invite_respond(invite_id, accept)
func try_guild_kick(member_id: String) -> Dictionary:
	return _guild_module_logic.try_guild_kick(member_id)
func try_guild_leave() -> Dictionary:
	return _guild_module_logic.try_guild_leave()
func try_guild_disband() -> Dictionary:
	return _guild_module_logic.try_guild_disband()
## --- Auction house shell (in-memory; reset + NPC stubs on enter_world) ---

func snapshot_auction() -> Dictionary:
	if auction == null:
		return {"listings": [], "count": 0, "max_listings": 50}
	return auction.snapshot_state()


func _auction_update_action() -> Dictionary:
	return {"type": "auction_update", "auction": snapshot_auction()}


func _auction_inventory_actions() -> Array:
	var actions: Array = []
	if inventory != null:
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
	actions.append(_auction_update_action())
	return actions


func _auction_seed_npc_stubs() -> void:
	if auction == null:
		auction = Auction.new()
	# Prefer clear player state on enter_world; re-seed a few NPC stubs so browse works.
	var stubs: Array = [
		{"seller_id": "npc_ah_1", "seller_name": "行商·阿福", "item_id": "potion_hp_small", "qty": 3, "price_gold": 25},
		{"seller_id": "npc_ah_2", "seller_name": "旅商·小翠", "item_id": "potion_mp_small", "qty": 2, "price_gold": 30},
		{"seller_id": "npc_ah_3", "seller_name": "拍卖行代理人", "item_id": "slime_jelly", "qty": 5, "price_gold": 15},
		{"seller_id": "npc_ah_1", "seller_name": "行商·阿福", "item_id": "wild_herb", "qty": 10, "price_gold": 8},
		{"seller_id": "npc_ah_4", "seller_name": "黑市商人", "item_id": "wooden_sword", "qty": 1, "price_gold": 120},
	]
	for s in stubs:
		if auction.is_full():
			break
		var iid := str(s.get("item_id", ""))
		var iname := item_display_name(iid) if has_method("item_display_name") else iid
		auction.try_add(
			str(s.get("seller_id", "npc")),
			str(s.get("seller_name", "NPC")),
			iid,
			iname,
			int(s.get("qty", 1)),
			int(s.get("price_gold", 1)),
		)


func try_auction_list(item_id: String, qty: int = 1, price_gold: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = int(qty)
	price_gold = int(price_gold)
	if item_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "上架请求无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if price_gold <= 0:
		actions.append({"type": "system_message", "text": "售价必须大于 0。"})
		return {"ok": false, "reason": "bad_price", "actions": actions}
	if auction == null:
		auction = Auction.new()
	if inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	if auction.is_full():
		actions.append({"type": "system_message", "text": "拍卖行已满（最多 %d 件）。" % auction.max_listings()})
		return {"ok": false, "reason": "full", "actions": actions}
	if inventory.has_method("is_locked") and inventory.is_locked(item_id):
		actions.append({"type": "system_message", "text": "该物品已锁定，无法上架。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if not inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if inventory.has_method("can_transfer") and not inventory.can_transfer(item_id, qty):
		actions.append({"type": "system_message", "text": "已绑定物品无法上架拍卖。"})
		return {"ok": false, "reason": "bound", "actions": actions}
	var auc_consumed := false
	if inventory.has_method("consume_unbound"):
		auc_consumed = inventory.consume_unbound(item_id, qty)
	else:
		auc_consumed = inventory.consume(item_id, qty)
	if not auc_consumed:
		actions.append({"type": "system_message", "text": "扣除背包物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var iname := item_display_name(item_id)
	var add_r: Dictionary = auction.try_add(
		_party_self_id(),
		_party_self_name(),
		item_id,
		iname,
		qty,
		price_gold,
	)
	if not bool(add_r.get("ok", false)):
		inventory.add_item(item_id, qty)
		var ar := str(add_r.get("reason", "full"))
		if ar == "full":
			actions.append({"type": "system_message", "text": "拍卖行已满（最多 %d 件）。" % auction.max_listings()})
		else:
			actions.append({"type": "system_message", "text": "上架失败。"})
		actions.append_array(_auction_inventory_actions())
		return {"ok": false, "reason": ar, "actions": actions}
	actions.append_array(_auction_inventory_actions())
	actions.append({"type": "system_message", "text": "已上架【%s】×%d（售价 %d 金币）。" % [iname, qty, price_gold]})
	return {"ok": true, "actions": actions}


func try_auction_buy(listing_id: String) -> Dictionary:
	var actions: Array = []
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的拍卖编号。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if auction == null:
		actions.append({"type": "system_message", "text": "拍卖行不可用。"})
		return {"ok": false, "reason": "no_ah", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	var listing: Dictionary = auction.get_listing(listing_id)
	if listing.is_empty():
		actions.append({"type": "system_message", "text": "找不到该拍卖品。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var seller_id := str(listing.get("seller_id", "")).strip_edges()
	var self_id := _party_self_id()
	if seller_id == self_id or seller_id == "player":
		actions.append({"type": "system_message", "text": "不能购买自己的拍卖品，请使用下架。"})
		return {"ok": false, "reason": "own_listing", "actions": actions}
	var iid := str(listing.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(listing.get("qty", 0)), 0)
	var price: int = maxi(int(listing.get("price_gold", 0)), 0)
	var iname := str(listing.get("item_name", "")).strip_edges()
	if iname.is_empty():
		iname = item_display_name(iid)
	if iid.is_empty() or qty <= 0 or price <= 0:
		actions.append({"type": "system_message", "text": "拍卖数据无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory.get_gold() < price:
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % price})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if inventory.has_method("can_accept") and not inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满，无法购买。"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	if not inventory.try_spend_gold(price):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % price})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var rem: Dictionary = auction.try_remove(listing_id)
	if not bool(rem.get("ok", false)):
		inventory.add_gold(price)
		actions.append({"type": "system_message", "text": "购买失败，拍卖品已不存在。"})
		actions.append_array(_auction_inventory_actions())
		return {"ok": false, "reason": "not_found", "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		# Rollback: restore listing + refund gold; reverse partial add.
		if added > 0:
			inventory.consume(iid, added)
		inventory.add_gold(price)
		auction.try_add(
			seller_id,
			str(listing.get("seller_name", "")),
			iid,
			iname,
			qty,
			price,
		)
		var reason := str(add_r.get("reason", "bag_full"))
		var msg := "背包已满，无法购买。"
		if reason == "stack_full":
			msg = "该物品已达堆叠上限，无法购买。"
		actions.append({"type": "system_message", "text": msg})
		actions.append_array(_auction_inventory_actions())
		return {"ok": false, "reason": reason if reason != "" else "bag_full", "actions": actions}
	# Player sellers: credit gold (shell single-player rarely hits this path).
	if not seller_id.begins_with("npc_") and seller_id != self_id:
		pass  # remote stub seller — gold retained by house
	actions.append_array(_auction_inventory_actions())
	actions.append({"type": "system_message", "text": "已购买【%s】×%d（-%d 金币）。" % [iname, qty, price]})
	return {"ok": true, "actions": actions}


func try_auction_cancel(listing_id: String) -> Dictionary:
	var actions: Array = []
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		actions.append({"type": "system_message", "text": "无效的拍卖编号。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if auction == null:
		actions.append({"type": "system_message", "text": "拍卖行不可用。"})
		return {"ok": false, "reason": "no_ah", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	var listing: Dictionary = auction.get_listing(listing_id)
	if listing.is_empty():
		actions.append({"type": "system_message", "text": "找不到该拍卖品。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var seller_id := str(listing.get("seller_id", "")).strip_edges()
	var self_id := _party_self_id()
	if seller_id != self_id and seller_id != "player":
		actions.append({"type": "system_message", "text": "只能下架自己的拍卖品。"})
		return {"ok": false, "reason": "not_owner", "actions": actions}
	var iid := str(listing.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(listing.get("qty", 0)), 0)
	var iname := str(listing.get("item_name", "")).strip_edges()
	if iname.is_empty():
		iname = item_display_name(iid)
	if iid.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "拍卖数据无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if inventory.has_method("can_accept") and not inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满，无法取回拍卖品。"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var rem: Dictionary = auction.try_remove(listing_id)
	if not bool(rem.get("ok", false)):
		actions.append({"type": "system_message", "text": "下架失败。"})
		return {"ok": false, "reason": str(rem.get("reason", "not_found")), "actions": actions}
	var add_r: Dictionary = inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		# Restore listing; reverse partial
		if added > 0:
			inventory.consume(iid, added)
		auction.try_add(
			seller_id,
			str(listing.get("seller_name", "")),
			iid,
			iname,
			qty,
			int(listing.get("price_gold", 1)),
		)
		actions.append({"type": "system_message", "text": "背包已满，无法取回拍卖品。"})
		actions.append_array(_auction_inventory_actions())
		return {"ok": false, "reason": "bag_full", "actions": actions}
	actions.append_array(_auction_inventory_actions())
	actions.append({"type": "system_message", "text": "已下架【%s】×%d，物品已返还背包。" % [iname, qty]})
	return {"ok": true, "actions": actions}



func snapshot_pet() -> Dictionary:
	var active := bool(_pet.get("active", false))
	return {
		"active": active,
		"id": str(_pet.get("id", "")),
		"name": str(_pet.get("name", "")),
		"cell": (_pet.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true)
			if typeof(_pet.get("cell", {})) == TYPE_DICTIONARY
			else {"x": 0, "y": 0},
		"look_id": str(_pet.get("look_id", "1")),
		"facing": int(_pet.get("facing", 2)),
		"atk": _pet_atk() if active else 0,
		"assist": bool(pet_assist),
	}


func _pet_reset() -> void:
	_pet = {
		"active": false,
		"id": "",
		"name": "",
		"cell": {"x": 0, "y": 0},
		"look_id": "1",
		"facing": 2,
		"follow_acc": 0.0,
		"combat_acc": 0.0,
	}


func _pet_spawn_action() -> Dictionary:
	var snap: Dictionary = snapshot_pet()
	return {
		"type": "pet_spawn",
		"pet": snap,
		"id": str(snap.get("id", "")),
		"name": str(snap.get("name", "")),
		"x": int((snap.get("cell", {}) as Dictionary).get("x", 0)),
		"y": int((snap.get("cell", {}) as Dictionary).get("y", 0)),
		"look_id": str(snap.get("look_id", "1")),
		"facing": int(snap.get("facing", 2)),
	}


func _pet_despawn_action() -> Dictionary:
	return {
		"type": "pet_despawn",
		"id": str(_pet.get("id", "")),
	}


func _pet_pick_spawn_cell(pc: Vector2i) -> Vector2i:
	var offsets: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 0), Vector2i(-2, 0),
	]
	for off_v in offsets:
		var off: Vector2i = off_v
		var cand := Vector2i(pc.x + off.x, pc.y + off.y)
		if cand == pc:
			continue
		var blocked := false
		if map_collision != null and map_collision.has_method("is_blocked"):
			blocked = bool(map_collision.is_blocked(cand.x, cand.y))
		if blocked:
			continue
		return cand
	return Vector2i(pc.x + 1, pc.y)


func _pet_snap_near_player() -> void:
	if not bool(_pet.get("active", false)):
		return
	var pc := _player_xy()
	var cell := _pet_pick_spawn_cell(pc)
	_pet["cell"] = {"x": cell.x, "y": cell.y}
	_pet["facing"] = MobAI.facing_toward(cell, pc)
	_pet["follow_acc"] = 0.0
	_pet["combat_acc"] = 0.0


func try_pet_summon(pet_id: String = "default") -> Dictionary:
	var actions: Array = []
	pet_id = str(pet_id).strip_edges()
	if pet_id.is_empty():
		pet_id = "default"
	if bool(_pet.get("active", false)):
		actions.append({"type": "system_message", "text": "已有宠物。"})
		return {"ok": false, "reason": "already_active", "actions": actions}
	var def_v: Variant = PET_DEFS.get(pet_id, PET_DEFS.get("default", {}))
	var def: Dictionary = def_v if typeof(def_v) == TYPE_DICTIONARY else {"name": "小跟班", "look_id": "1"}
	if not PET_DEFS.has(pet_id) and pet_id != "default":
		# Unknown id → still allow as default-named custom id.
		def = {"name": str(PET_DEFS["default"].get("name", "小跟班")), "look_id": "1"}
	var pc := _player_xy()
	var cell := _pet_pick_spawn_cell(pc)
	_pet = {
		"active": true,
		"id": pet_id,
		"name": str(def.get("name", "小跟班")),
		"cell": {"x": cell.x, "y": cell.y},
		"look_id": str(def.get("look_id", "1")),
		"facing": MobAI.facing_toward(cell, pc),
		"follow_acc": 0.0,
		"combat_acc": 0.0,
	}
	actions.append(_pet_spawn_action())
	actions.append({
		"type": "system_message",
		"text": "召唤了宠物【%s】。" % str(_pet.get("name", "")),
	})
	return {"ok": true, "actions": actions}


func try_pet_dismiss() -> Dictionary:
	var actions: Array = []
	if not bool(_pet.get("active", false)):
		actions.append({"type": "system_message", "text": "当前没有宠物。"})
		return {"ok": false, "reason": "not_active", "actions": actions}
	var pname := str(_pet.get("name", "宠物"))
	actions.append(_pet_despawn_action())
	_pet_reset()
	actions.append({"type": "system_message", "text": "收回了宠物【%s】。" % pname})
	return {"ok": true, "actions": actions}


## Tick: move toward player when Chebyshev distance > PET_LAG_MAX; stay in lag 1–2.
func _tick_pet_follow(dt: float) -> Array:
	var actions: Array = []
	if not bool(_pet.get("active", false)):
		return actions
	_pet["follow_acc"] = float(_pet.get("follow_acc", 0.0)) + dt
	if float(_pet.get("follow_acc", 0.0)) < PET_FOLLOW_INTERVAL_SEC:
		return actions
	_pet["follow_acc"] = 0.0
	var cell_v: Variant = _pet.get("cell", {})
	if typeof(cell_v) != TYPE_DICTIONARY:
		return actions
	var cell := Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var pc := _player_xy()
	var dist: int = _chebyshev(cell.x, cell.y, pc.x, pc.y)
	if dist <= PET_LAG_MAX and dist >= PET_LAG_MIN:
		return actions
	if dist == 0:
		# Nudge off player cell.
		var nudge := _pet_pick_spawn_cell(pc)
		if nudge == cell:
			return actions
		_pet["cell"] = {"x": nudge.x, "y": nudge.y}
		_pet["facing"] = MobAI.facing_toward(nudge, pc)
		actions.append({
			"type": "pet_move",
			"id": str(_pet.get("id", "")),
			"x": nudge.x,
			"y": nudge.y,
			"facing": int(_pet.get("facing", 2)),
		})
		return actions
	if dist <= PET_LAG_MAX:
		return actions
	# Step toward player; do not enter player cell (lag stays ≥ 1).
	var wdir: int = MobAI.next_step_dir(map_collision, cell, pc, false)
	if wdir == 0:
		# Fallback greedy cardinal toward player (ignore collision if no map).
		wdir = MobAI.facing_toward(cell, pc)
		var delta0: Vector2i = TileId.dir_delta(wdir)
		var trial := Vector2i(cell.x + delta0.x, cell.y + delta0.y)
		if trial == pc:
			return actions
		if map_collision != null and map_collision.has_method("is_blocked"):
			if bool(map_collision.is_blocked(trial.x, trial.y)):
				return actions
		wdir = MobAI.facing_toward(cell, pc)
	var delta: Vector2i = TileId.dir_delta(wdir)
	var next := Vector2i(cell.x + delta.x, cell.y + delta.y)
	if next == pc:
		return actions
	if map_collision != null and map_collision.has_method("is_blocked"):
		if bool(map_collision.is_blocked(next.x, next.y)):
			return actions
	# Avoid stacking on shell remotes when possible.
	for oid in _remote_players.keys():
		var od: Variant = _remote_players[oid]
		if typeof(od) != TYPE_DICTIONARY:
			continue
		var oc: Variant = od.get("cell", {})
		if typeof(oc) == TYPE_DICTIONARY and int(oc.get("x", -9999)) == next.x and int(oc.get("y", -9999)) == next.y:
			return actions
	_pet["cell"] = {"x": next.x, "y": next.y}
	_pet["facing"] = wdir
	actions.append({
		"type": "pet_move",
		"id": str(_pet.get("id", "")),
		"x": next.x,
		"y": next.y,
		"facing": wdir,
	})
	return actions


func _pet_atk() -> int:
	var lv := 1
	if combat_stats != null and typeof(combat_stats.player) == TYPE_DICTIONARY:
		lv = maxi(1, int(combat_stats.player.get("level", 1)))
	return 3 + lv


func _npc_display_name_for_pet(npc_id: String) -> String:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty():
		return "敌人"
	if npc_spawn_templates.has(npc_id):
		var n := str(npc_spawn_templates[npc_id].get("name", "")).strip_edges()
		if n != "":
			return n
	if npc_meta.has(npc_id) and typeof(npc_meta[npc_id]) == TYPE_DICTIONARY:
		var n2 := str(npc_meta[npc_id].get("name", "")).strip_edges()
		if n2 != "":
			return n2
	return npc_id


## Resolve hostile the player is fighting; prefer locked target, else adjacent hate.
func _resolve_pet_combat_target() -> String:
	if combat_stats == null:
		return ""
	var cell_v: Variant = _pet.get("cell", {})
	if typeof(cell_v) != TYPE_DICTIONARY:
		return ""
	var pet_cell := Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var tid := str(_player_combat_target_id).strip_edges()
	if tid != "" and _pet_target_valid_in_range(tid, pet_cell):
		return tid
	# Fallback: hostile with player hate within pet range.
	var you := "player"
	if "player_actor_id" in combat_stats:
		var aid := str(combat_stats.player_actor_id).strip_edges()
		if aid != "":
			you = aid
	for nid_v in combat_stats.npcs.keys():
		var nid := str(nid_v)
		if not _pet_target_valid_in_range(nid, pet_cell):
			continue
		if not combat_stats.has_method("get_hate_list"):
			continue
		var hate: Array = combat_stats.get_hate_list(nid, false)
		for e in hate:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if str(e.get("id", "")).strip_edges() == you:
				return nid
	return ""


func _pet_target_valid_in_range(npc_id: String, pet_cell: Vector2i) -> bool:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty() or combat_stats == null or not combat_stats.npcs.has(npc_id):
		return false
	var st: Dictionary = combat_stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0:
		return false
	if not bool(st.get("hostile", false)):
		return false
	var tc: Vector2i = combat_stats.get_npc_cell(npc_id) if combat_stats.has_method("get_npc_cell") else Vector2i(-9999, -9999)
	if tc.x <= -9990:
		return false
	return _chebyshev(pet_cell.x, pet_cell.y, tc.x, tc.y) <= PET_COMBAT_RANGE


## Periodic small pet damage on player's combat target (hate → player).
func _tick_pet_combat(dt: float) -> Array:
	var actions: Array = []
	if not bool(_pet.get("active", false)):
		return actions
	if not bool(pet_assist):
		return actions
	if combat_stats == null or combat_engine == null:
		return actions
	if awaiting_respawn or not combat_stats.player_alive():
		return actions
	_pet["combat_acc"] = float(_pet.get("combat_acc", 0.0)) + dt
	if float(_pet.get("combat_acc", 0.0)) < PET_COMBAT_INTERVAL_SEC:
		return actions
	_pet["combat_acc"] = 0.0
	var tid := _resolve_pet_combat_target()
	if tid.is_empty():
		return actions
	var hit_actions: Array = []
	var amount: int = _pet_atk()
	# Guaranteed hit; attribute as player so hate / loot / exp stay player-side.
	if combat_engine.has_method("_damage_npc"):
		combat_engine._damage_npc(tid, amount, hit_actions, false, "player")
	if hit_actions.is_empty():
		return actions
	var nm := _npc_display_name_for_pet(tid)
	hit_actions.append({"type": "system_message", "text": "宠物攻击了%s" % nm})
	if combat_engine.has_method("_threat_update_action"):
		var thr_act: Dictionary = combat_engine._threat_update_action(tid)
		if not thr_act.is_empty():
			hit_actions.append(thr_act)
	var finalized: Dictionary = _finalize_combat_result({"ok": true, "actions": hit_actions})
	actions.append_array(finalized.get("actions", []))
	if not combat_stats.npcs.has(tid) or int(combat_stats.npcs[tid].get("hp", 0)) <= 0:
		if str(_player_combat_target_id).strip_edges() == tid:
			_player_combat_target_id = ""
	return actions


## --- Dungeon instance stub API ---

func in_dungeon() -> bool:
	return not _dungeon.is_empty() and bool(_dungeon.get("active", false))


func snapshot_dungeon() -> Dictionary:
	if _dungeon.is_empty():
		return {
			"active": false,
			"completed": false,
			"kills": 0,
			"kills_needed": 0,
		}
	var rc: Dictionary = {"x": 0, "y": 0}
	var rc_v: Variant = _dungeon.get("return_cell", {})
	if typeof(rc_v) == TYPE_DICTIONARY:
		rc = {
			"x": int((rc_v as Dictionary).get("x", 0)),
			"y": int((rc_v as Dictionary).get("y", 0)),
		}
	return {
		"active": bool(_dungeon.get("active", false)),
		"completed": bool(_dungeon.get("completed", false)),
		"kills": int(_dungeon.get("kills", 0)),
		"kills_needed": int(_dungeon.get("kills_needed", DUNGEON_KILLS_NEEDED)),
		"return_pack": str(_dungeon.get("return_pack", "")),
		"return_cell": rc,
	}


func _dungeon_update_action() -> Dictionary:
	return {"type": "dungeon_update", "dungeon": snapshot_dungeon()}


func _dungeon_force_clear_silent() -> void:
	_dungeon.clear()
	_dungeon_xfer_lock = false


func _dungeon_abandon_on_leave() -> Array:
	## Clear session without reward (early warp / leave).
	var actions: Array = []
	if _dungeon.is_empty():
		return actions
	var was_active := bool(_dungeon.get("active", false)) or bool(_dungeon.get("completed", false))
	_dungeon.clear()
	if was_active:
		actions.append(_dungeon_update_action())
		actions.append({"type": "system_message", "text": "试炼已放弃。"})
	return actions


func _dungeon_return_cell_dict() -> Dictionary:
	if player_cell.x > -9990:
		return {"x": player_cell.x, "y": player_cell.y}
	return {"x": respawn_cell.x, "y": respawn_cell.y}


func _dungeon_pick_guard_cells(count: int) -> Array:
	## Free cells near street spawn for slim dungeon guards.
	var out: Array = []
	var origin := DUNGEON_STREET_SPAWN
	if map_collision != null and map_collision.has_method("find_spawn_near"):
		origin = map_collision.find_spawn_near(DUNGEON_STREET_SPAWN.x, DUNGEON_STREET_SPAWN.y)
	var used: Dictionary = {}
	used["%d,%d" % [player_cell.x, player_cell.y]] = true
	var offsets: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
	]
	for off_v in offsets:
		if out.size() >= count:
			break
		var off: Vector2i = off_v
		var cx: int = origin.x + off.x
		var cy: int = origin.y + off.y
		var key := "%d,%d" % [cx, cy]
		if used.has(key):
			continue
		var ok := true
		if map_collision != null and map_collision.has_method("is_landable"):
			ok = map_collision.is_landable(cx, cy)
		if not ok:
			continue
		used[key] = true
		out.append(Vector2i(cx, cy))
	while out.size() < count:
		var fallback := Vector2i(origin.x + out.size() + 1, origin.y)
		out.append(fallback)
	return out


func _dungeon_spawn_guards() -> Array:
	## Register 2 slim hostiles with meta dungeon=true; return spawn_npc actions.
	var actions: Array = []
	var cells: Array = _dungeon_pick_guard_cells(DUNGEON_KILLS_NEEDED)
	var guard_ids: Array = []
	for i in range(DUNGEON_KILLS_NEEDED):
		var gid := "dungeon_guard_%d" % i
		var cell: Vector2i = cells[i] if i < cells.size() else DUNGEON_STREET_SPAWN
		var spawn := {
			"id": gid,
			"name": "试炼守卫",
			"charset": "retira_slime",
			"index": 4,
			"cell": {"x": cell.x, "y": cell.y},
			"direction": 2,
			"hostile": true,
			"aggressive": true,
			"wander_radius": 1,
			"leash_radius": 8,
			"respawn_sec": -1.0,
			"dungeon": true,
			"hp_max": 40,
			"level": 3,
			"atk": 8,
			"def": 2,
			"kind": "monster",
		}
		register_npc(gid, cell.x, cell.y, true, true, 2, 1, 0, spawn)
		if map_collision != null and map_collision.has_method("set_extra_blocked"):
			map_collision.set_extra_blocked(cell.x, cell.y, true)
		actions.append({"type": "spawn_npc", "npc": spawn.duplicate(true)})
		guard_ids.append(gid)
	_dungeon["guard_ids"] = guard_ids
	return actions


func _dungeon_is_countable_kill(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not in_dungeon():
		return false
	var guards_v: Variant = _dungeon.get("guard_ids", [])
	if typeof(guards_v) == TYPE_ARRAY:
		for g in guards_v:
			if str(g) == npc_id:
				return true
	if npc_id.begins_with("dungeon_guard_"):
		return true
	if npc_meta.has(npc_id) and typeof(npc_meta[npc_id]) == TYPE_DICTIONARY:
		if bool(npc_meta[npc_id].get("dungeon", false)):
			return true
	# Fallback: any hostile kill while dungeon.active counts if no guards tracked.
	var guards: Array = guards_v if typeof(guards_v) == TYPE_ARRAY else []
	if guards.is_empty():
		if combat_stats != null and combat_stats.npcs.has(npc_id):
			return bool(combat_stats.npcs[npc_id].get("hostile", false))
		return true
	return false


func _dungeon_grant_rewards() -> Array:
	var actions: Array = []
	if inventory != null and DUNGEON_REWARD_GOLD > 0:
		inventory.add_gold(DUNGEON_REWARD_GOLD)
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "获得金币 %d" % DUNGEON_REWARD_GOLD})
	if inventory != null and DUNGEON_REWARD_STONE_QTY > 0:
		inventory.add_item("enhance_stone", DUNGEON_REWARD_STONE_QTY)
		actions.append({
			"type": "inventory_update",
			"items": inventory.snapshot(),
			"gold": inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "获得：强化石 ×%d" % DUNGEON_REWARD_STONE_QTY})
	if combat_stats != null and DUNGEON_REWARD_EXP > 0:
		var summary: Dictionary = combat_stats.grant_exp(DUNGEON_REWARD_EXP)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", DUNGEON_REWARD_EXP)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "获得经验 %d" % int(summary.get("amount", DUNGEON_REWARD_EXP))})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				actions.append({"type": "level_up", "level": int(lv_v), "combat": combat_snap})
			actions.append({"type": "set_stat", "target": "player", "combat": combat_snap})
	return actions


func _dungeon_complete() -> Array:
	var actions: Array = []
	if not in_dungeon() or bool(_dungeon.get("completed", false)):
		return actions
	_dungeon["completed"] = true
	_dungeon["active"] = false
	actions.append({"type": "system_message", "text": "试炼完成！"})
	actions.append_array(_dungeon_grant_rewards())
	actions.append(_dungeon_update_action())
	return actions


func _dungeon_note_kill(npc_id: String) -> Array:
	var actions: Array = []
	if not in_dungeon():
		return actions
	if not _dungeon_is_countable_kill(npc_id):
		return actions
	var kills: int = int(_dungeon.get("kills", 0)) + 1
	_dungeon["kills"] = kills
	var needed: int = int(_dungeon.get("kills_needed", DUNGEON_KILLS_NEEDED))
	actions.append(_dungeon_update_action())
	if kills >= needed:
		actions.append_array(_dungeon_complete())
	return actions


func try_dungeon_enter() -> Dictionary:
	## One-shot: transfer demo → street_map, spawn 2 dungeon guards, start session.
	var actions: Array = []
	if in_dungeon():
		actions.append({"type": "system_message", "text": "试炼已在进行中。"})
		actions.append(_dungeon_update_action())
		return {"ok": false, "reason": "already", "actions": actions}
	if bool(_dungeon.get("completed", false)):
		actions.append({"type": "system_message", "text": "请先离开试炼。"})
		actions.append(_dungeon_update_action())
		return {"ok": false, "reason": "completed", "actions": actions}
	if combat_stats != null and not combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var return_pack: String = map_pack_path if map_pack_path != "" else DEMO_PACK_PATH
	var return_map: String = map_pack_id if map_pack_id != "" else "demo_map"
	var return_cell: Dictionary = _dungeon_return_cell_dict()
	_dungeon_xfer_lock = true
	var xfer: Dictionary = _event_perform_transfer(
		DUNGEON_STREET_PACK,
		{"x": DUNGEON_STREET_SPAWN.x, "y": DUNGEON_STREET_SPAWN.y},
		4,
		"进入试炼洞窟",
		DUNGEON_STREET_MAP_ID
	)
	_dungeon_xfer_lock = false
	if not bool(xfer.get("ok", false)):
		actions.append({"type": "system_message", "text": "无法进入试炼洞窟。"})
		return {"ok": false, "reason": "transfer", "actions": actions}
	_dungeon = {
		"active": true,
		"completed": false,
		"kills": 0,
		"kills_needed": DUNGEON_KILLS_NEEDED,
		"return_pack": return_pack,
		"return_map": return_map,
		"return_cell": return_cell,
		"guard_ids": [],
	}
	var spawn_actions: Array = _dungeon_spawn_guards()
	actions.append({
		"type": "map_transfer",
		"ok": true,
		"pack_path": str(xfer.get("pack_path", DUNGEON_STREET_PACK)),
		"map_id": str(xfer.get("map_id", DUNGEON_STREET_MAP_ID)),
		"content_id": str(xfer.get("content_id", "")),
		"content_version": str(xfer.get("content_version", "")),
		"cell": xfer.get("cell", {"x": DUNGEON_STREET_SPAWN.x, "y": DUNGEON_STREET_SPAWN.y}),
		"facing": int(xfer.get("facing", 4)),
		"message": "进入试炼洞窟",
		"quests": xfer.get("quests", []),
	})
	var xfer_acts_v: Variant = xfer.get("actions", [])
	if typeof(xfer_acts_v) == TYPE_ARRAY:
		actions.append_array(xfer_acts_v)
	actions.append_array(spawn_actions)
	actions.append({"type": "system_message", "text": "试炼开始：击败 %d 只守卫。" % DUNGEON_KILLS_NEEDED})
	actions.append(_dungeon_update_action())
	var out := {
		"ok": true,
		"pack_path": str(xfer.get("pack_path", DUNGEON_STREET_PACK)),
		"map_id": str(xfer.get("map_id", DUNGEON_STREET_MAP_ID)),
		"content_id": str(xfer.get("content_id", "")),
		"content_version": str(xfer.get("content_version", "")),
		"cell": xfer.get("cell", {"x": DUNGEON_STREET_SPAWN.x, "y": DUNGEON_STREET_SPAWN.y}),
		"facing": int(xfer.get("facing", 4)),
		"message": "进入试炼洞窟",
		"dungeon": snapshot_dungeon(),
		"actions": actions,
	}
	out.merge(_transfer_result_extras())
	return out


func try_dungeon_exit() -> Dictionary:
	## Transfer back to saved demo return cell; clear session.
	var actions: Array = []
	if _dungeon.is_empty():
		actions.append({"type": "system_message", "text": "当前没有试炼。"})
		return {"ok": false, "reason": "idle", "actions": actions}
	var ret_pack: String = str(_dungeon.get("return_pack", DEMO_PACK_PATH)).strip_edges()
	if ret_pack.is_empty():
		ret_pack = DEMO_PACK_PATH
	var ret_map: String = str(_dungeon.get("return_map", "demo_map")).strip_edges()
	var ret_cell_v: Variant = _dungeon.get("return_cell", {"x": 15, "y": 12})
	var ret_cell: Dictionary = ret_cell_v if typeof(ret_cell_v) == TYPE_DICTIONARY else {"x": 15, "y": 12}
	var completed := bool(_dungeon.get("completed", false))
	# Clear before transfer so abandon hook does not fire.
	_dungeon.clear()
	_dungeon_xfer_lock = true
	var xfer: Dictionary = _event_perform_transfer(
		ret_pack,
		{"x": int(ret_cell.get("x", 15)), "y": int(ret_cell.get("y", 12))},
		2,
		"离开试炼洞窟",
		ret_map
	)
	_dungeon_xfer_lock = false
	if not bool(xfer.get("ok", false)):
		actions.append({"type": "system_message", "text": "无法离开试炼。"})
		actions.append(_dungeon_update_action())
		return {"ok": false, "reason": "transfer", "actions": actions}
	actions.append({
		"type": "map_transfer",
		"ok": true,
		"pack_path": str(xfer.get("pack_path", ret_pack)),
		"map_id": str(xfer.get("map_id", ret_map)),
		"content_id": str(xfer.get("content_id", "")),
		"content_version": str(xfer.get("content_version", "")),
		"cell": xfer.get("cell", ret_cell),
		"facing": int(xfer.get("facing", 2)),
		"message": "离开试炼洞窟",
		"quests": xfer.get("quests", []),
	})
	var xfer_acts_v: Variant = xfer.get("actions", [])
	if typeof(xfer_acts_v) == TYPE_ARRAY:
		actions.append_array(xfer_acts_v)
	actions.append(_dungeon_update_action())
	if completed:
		actions.append({"type": "system_message", "text": "已返回。"})
	else:
		actions.append({"type": "system_message", "text": "试炼已中止，返回。"})
	var out := {
		"ok": true,
		"pack_path": str(xfer.get("pack_path", ret_pack)),
		"map_id": str(xfer.get("map_id", ret_map)),
		"cell": xfer.get("cell", ret_cell),
		"facing": int(xfer.get("facing", 2)),
		"dungeon": snapshot_dungeon(),
		"actions": actions,
	}
	out.merge(_transfer_result_extras())
	return out
