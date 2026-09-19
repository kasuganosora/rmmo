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
const ShopModule = preload("res://scripts/net/server/shop_module.gd")
const PetModule = preload("res://scripts/net/server/pet_module.gd")
const SessionModule = preload("res://scripts/net/server/session_module.gd")
const EventModule = preload("res://scripts/net/server/event_module.gd")
const WarehouseModule = preload("res://scripts/net/server/warehouse_module.gd")
const SustainModule = preload("res://scripts/net/server/sustain_module.gd")
const ProfessionModule = preload("res://scripts/net/server/profession_module.gd")
const QuestModule = preload("res://scripts/net/server/quest_module.gd")
const RemoteModule = preload("res://scripts/net/server/remote_module.gd")
const EmoteModule = preload("res://scripts/net/server/emote_module.gd")
const NpcAiModule = preload("res://scripts/net/server/npc_ai_module.gd")
const MovementModule = preload("res://scripts/net/server/movement_module.gd")
const DungeonModule = preload("res://scripts/net/server/dungeon_module.gd")
var _dungeon_module_logic: DungeonModule = DungeonModule.new(self)
const CombatModule = preload("res://scripts/net/server/combat_module.gd")
var _combat_module_logic: CombatModule = CombatModule.new(self)
const WorldModule = preload("res://scripts/net/server/world_module.gd")
var _world_module_logic: WorldModule = WorldModule.new(self)
var _movement_module_logic: MovementModule = MovementModule.new(self)
var _npc_ai_module_logic: NpcAiModule = NpcAiModule.new(self)
var _emote_module_logic: EmoteModule = EmoteModule.new(self)
var _remote_module_logic: RemoteModule = RemoteModule.new(self)
var _quest_module_logic: QuestModule = QuestModule.new(self)
var _profession_module_logic: ProfessionModule = ProfessionModule.new(self)
var _sustain_module_logic: SustainModule = SustainModule.new(self)
var _warehouse_module_logic: WarehouseModule = WarehouseModule.new(self)
var _event_module_logic: EventModule = EventModule.new(self)
var _session_module_logic: SessionModule = SessionModule.new(self)
var _pet_module_logic: PetModule = PetModule.new(self)
var _shop_module_logic: ShopModule = ShopModule.new(self)
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
	_combat_module_logic._init_combat_layers()
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
	return _combat_module_logic.poll_combat_tick()
func get_weather() -> Dictionary:
	return _world_module_logic.get_weather()
func set_weather(kind: String, intensity: float = 0.75, duration: float = 60.0) -> Dictionary:
	return _world_module_logic.set_weather(kind, intensity, duration)
func _map_indoor() -> bool:
	return _world_module_logic._map_indoor()
func _weather_action() -> Dictionary:
	return _world_module_logic._weather_action()
func _reset_weather_for_map() -> void:
	_world_module_logic._reset_weather_for_map()
func _tick_weather(delta: float) -> void:
	_world_module_logic._tick_weather(delta)
func load_world_pack(pack_path: String, map_id: String = "", cell: Vector2i = Vector2i(-1, -1)) -> bool:
	return _world_module_logic.load_world_pack(pack_path, map_id, cell)
func _load_pack(pack_path: String, map_id: String = "") -> bool:
	return _world_module_logic._load_pack(pack_path, map_id)
func _load_demo_map() -> void:
	_world_module_logic._load_demo_map()
func is_logged_in() -> bool:
	return _session_user != ""


func current_server() -> String:
	return _session_server


func login(username: String, password: String, server: String) -> void:
	_session_module_logic.login(username, password, server)
func fetch_characters() -> void:
	_session_module_logic.fetch_characters()
func create_character(char_name: String, class_id: String, look_id: String, gender: String = "female", customization: Dictionary = {}) -> void:
	_session_module_logic.create_character(char_name, class_id, look_id, gender, customization)
func enter_world(character_id: int) -> void:
	_session_module_logic.enter_world(character_id)
## Sync player occupancy into map_collision.extra_blocked.
func set_player_cell(x: int, y: int) -> void:
	_movement_module_logic.set_player_cell(x, y)
## Register NPC presence for range checks / tick counter-attacks / mob AI.
## aggressive: base 主动 chase-on-sight; false = 被动 (chase only after enrage from damage).
## wander_radius: idle roam cells from home (0 = stand still). Spawn cell stored as home_cell.
## group_id: 0 = solo; same non-zero = pack (assist within hit mob wander_radius).
## spawn_data: optional full npcs.json entry (name/charset/leash_radius/respawn_sec/…) stored as respawn template.
## home_override: when respawning near home, keep original home_cell (Vector2i) instead of current x,y.

## --- Town safe zones (PvP / duel / hostile aggro blocked) ---

func is_in_safe_zone(map_id: String, x: int, y: int) -> bool:
	return _world_module_logic.is_in_safe_zone(map_id, x, y)
func player_in_safe_zone() -> bool:
	return _world_module_logic.player_in_safe_zone()
## Threat / aggro snapshot for current player vs npc (hate_list + victim_id).
func snapshot_threat(npc_id: String) -> Dictionary:
	return _combat_module_logic.snapshot_threat(npc_id)
func snapshot_safe_zone() -> Dictionary:
	return _world_module_logic.snapshot_safe_zone()
func _safe_zone_action(inside: bool) -> Dictionary:
	return _world_module_logic._safe_zone_action(inside)
func _safe_zone_transition_actions(force: bool = false) -> Array:
	return _world_module_logic._safe_zone_transition_actions(force)
func _safe_zone_block_pvp_result() -> Dictionary:
	return _world_module_logic._safe_zone_block_pvp_result()
func _target_is_remote_player(target_id: String) -> bool:
	return _remote_module_logic._target_is_remote_player(target_id)
func register_npc( npc_id: String, x: int, y: int, hostile: bool = false, aggressive: bool = false, facing: int = 2, wander_radius: int = 0, group_id: int = 0, spawn_data: Dictionary = {}, home_override: Vector2i = Vector2i(-9999, -9999) ) -> void:
	_npc_ai_module_logic.register_npc(npc_id, x, y, hostile, aggressive, facing, wander_radius, group_id, spawn_data, home_override)
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
	return _movement_module_logic.player_move_speed_mul()
## Mount stub: mounted buff flag (status id `mounted`).
func player_is_mounted() -> bool:
	return _movement_module_logic.player_is_mounted()
## Toggle mount via skill authority (`mount`「骑乘」).
func try_mount() -> Dictionary:
	return _movement_module_logic.try_mount()
func try_move(from_x: int, from_y: int, dir: int) -> Dictionary:
	return _movement_module_logic.try_move(from_x, from_y, dir)
## Authoritative NPC grid step (server AI only — client must not call).
## Blocks player_cell; updates extra_blocked + AI facing on success.
## Returns {ok, x, y, facing, npc_id}.
func try_npc_move(npc_id: String, from_x: int, from_y: int, dir: int) -> Dictionary:
	return _npc_ai_module_logic.try_npc_move(npc_id, from_x, from_y, dir)
## Shared fields after a successful pack switch (warp / event transfer).
func _transfer_result_extras() -> Dictionary:
	return _world_module_logic._transfer_result_extras()
## Authoritative map transfer when standing on a warp cell.
## Returns {ok, pack_path, map_id, cell:{x,y}, facing, message} or {ok:false}.
func try_transfer(from_x: int, from_y: int) -> Dictionary:
	return _world_module_logic.try_transfer(from_x, from_y)
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
	return _event_module_logic._event_server_ctx(npc_name)
## EventRuntime move_route step → try_npc_move (collision + occupancy).
func _event_npc_step(npc_id: String, from_x: int, from_y: int, dir: int) -> Dictionary:
	return _event_module_logic._event_npc_step(npc_id, from_x, from_y, dir)
func _event_npc_face(npc_id: String, facing: int) -> void:
	_event_module_logic._event_npc_face(npc_id, facing)
func _event_npc_cell(npc_id: String) -> Vector2i:
	return _event_module_logic._event_npc_cell(npc_id)
func _event_npc_facing(npc_id: String) -> int:
	return _event_module_logic._event_npc_facing(npc_id)
## Transfer used by event `transfer` op (same landing rules as try_transfer / warps).
func _event_perform_transfer( to_pack: String, to_cell: Dictionary, facing: int = 2, message: String = "", to_map_id: String = "" ) -> Dictionary:
	return _event_module_logic._event_perform_transfer(to_pack, to_cell, facing, message, to_map_id)
## Fire matching autorun pages once after a play pack/map load.
func collect_autorun() -> Array:
	return _movement_module_logic.collect_autorun()
func _collect_autorun() -> Array:
	return _movement_module_logic._collect_autorun()
## After a successful step, fire player_touch events on the landing cell (once per page/self-switch).
func _try_player_touch_events(x: int, y: int) -> Array:
	return _event_module_logic._try_player_touch_events(x, y)
## Event whose selected page is event_touch (does not run commands).
func _event_touch_event(npc_id: String, from_x: int, from_y: int) -> Dictionary:
	return _event_module_logic._event_touch_event(npc_id, from_x, from_y)
## Client dialogue option → quest_* / shop_open / MV event choices.
func try_event_choice(option_id: String = "", option_index: int = -1) -> Dictionary:
	return _event_module_logic.try_event_choice(option_id, option_index)
## Generic dialogue option handler (quest accept/turn-in, shop reopen, event choices).
func try_dialogue_choice(option_id: String = "", option_index: int = -1) -> Dictionary:
	return _quest_module_logic.try_dialogue_choice(option_id, option_index)
## Authoritative basic attack. Delegates to combat_engine.
func try_attack(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	return _combat_module_logic.try_attack(npc_id, player_x, player_y)
## Apply authoritative player_move actions from combat (e.g. charge).
func _apply_player_move_actions(result: Dictionary) -> void:
	_movement_module_logic._apply_player_move_actions(result)
func _npc_is_rooted(npc_id: String) -> bool:
	if combat_stats == null or combat_stats.statuses == null:
		return false
	if combat_stats.statuses.has_status(npc_id, "root"):
		return true
	if combat_stats.statuses.has_status(npc_id, "stun"):
		return true
	return false


func try_use_skill( skill_id: String, target_npc_id: String = "", player_x: int = -9999, player_y: int = -9999, ground_x: int = -9999, ground_y: int = -9999 ) -> Dictionary:
	return _combat_module_logic.try_use_skill(skill_id, target_npc_id, player_x, player_y, ground_x, ground_y)
func skill_def(skill_id: String) -> Dictionary:
	return _combat_module_logic.skill_def(skill_id)
func _patch_npc_cast_skill_names(actions: Array) -> void:
	_combat_module_logic._patch_npc_cast_skill_names(actions)
func try_npc_skill(npc_id: String, skill_id: String, ground_x: int = -9999, ground_y: int = -9999) -> Dictionary:
	return _combat_module_logic.try_npc_skill(npc_id, skill_id, ground_x, ground_y)
func try_set_auto_potion(hp_on: bool, hp_pct: int, mp_on: bool, mp_pct: int) -> void:
	_combat_module_logic.try_set_auto_potion(hp_on, hp_pct, mp_on, mp_pct)
func try_set_pet_assist(on: bool) -> void:
	_pet_module_logic.try_set_pet_assist(on)
## Client / tests: lock combat target for pet assist (hostile npc id).
func try_set_combat_target(npc_id: String = "") -> void:
	_combat_module_logic.try_set_combat_target(npc_id)
## Rate-limited auto HP/MP potion use. Failures stay silent (optional 10s empty msg).
func _tick_auto_potion(delta: float) -> void:
	_combat_module_logic._tick_auto_potion(delta)
func _best_auto_potion(effect: String) -> String:
	return _combat_module_logic._best_auto_potion(effect)
func _maybe_auto_potion_msg(text: String) -> void:
	_combat_module_logic._maybe_auto_potion_msg(text)
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
	return _movement_module_logic._gate_recall_item_use()
func _town_dest() -> Vector2i:
	return _world_module_logic._town_dest()
func _bind_recall_actions(result: Dictionary) -> void:
	_movement_module_logic._bind_recall_actions(result)
func _combat_stand_if_needed(result: Dictionary) -> void:
	_combat_module_logic._combat_stand_if_needed(result)
func _stand_if_sitting(actions: Array) -> bool:
	return _sustain_module_logic._stand_if_sitting(actions)
func _tick_sit(delta: float) -> void:
	_sustain_module_logic._tick_sit(delta)
## +RESTED_EXP_PER_TICK while sitting in safe zone; clamp to rested_exp_max.
## System chat only on empty→nonzero and first hit of cap (not every tick).
func _tick_rested_accumulate() -> Array:
	return _sustain_module_logic._tick_rested_accumulate()
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
	return _combat_module_logic.snapshot_skill_book()
func _reset_skill_book() -> void:
	_combat_module_logic._reset_skill_book()
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
	return _combat_module_logic.try_learn_skill(skill_id)
## Flat gold cost to respec skills (independent of refunded SP).
const SKILL_RESPEC_GOLD_COST := 50


## Reset learned skills (keep basic_attack), refund SP, pay flat gold; scrub forgotten hotbar ids via action.
func try_skill_respec() -> Dictionary:
	return _combat_module_logic.try_skill_respec()
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
	return _combat_module_logic.snapshot_skill_catalog()
## Quest journal snapshot for HUD (accepted quests only).
func get_quest_list() -> Array:
	return _quest_module_logic.get_quest_list()
func snapshot_quest_journal() -> Array:
	return _quest_module_logic.snapshot_quest_journal()
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
	return _quest_module_logic._grant_quest_reward(reward)
func _build_quest_dialogue_options(npc_id: String) -> Array:
	return _quest_module_logic._build_quest_dialogue_options(npc_id)
func _append_quest_offer_blurb(body: String, npc_id: String) -> String:
	return _quest_module_logic._append_quest_offer_blurb(body, npc_id)
func _try_open_shop_action(shop_id: String) -> Dictionary:
	return _shop_module_logic._try_open_shop_action(shop_id)
## Vendor rep 0–1000 for a shop (generic map; vendor_rep mirrors starter_goods).
func get_vendor_rep(shop_id: String = "starter_goods") -> int:
	return _shop_module_logic.get_vendor_rep(shop_id)
func set_vendor_rep(shop_id: String, value: int) -> void:
	_shop_module_logic.set_vendor_rep(shop_id, value)
func force_vendor_rep(shop_id: String, value: int) -> void:
	_shop_module_logic.force_vendor_rep(shop_id, value)
func _vendor_discount_pct(rep: int) -> int:
	return _shop_module_logic._vendor_discount_pct(rep)
func _discounted_buy_price(base: int, discount_pct: int) -> int:
	return _shop_module_logic._discounted_buy_price(base, discount_pct)
## Snapshot shop with discounted listings + vendor_rep.
func snapshot_shop(shop_id: String = "starter_goods") -> Dictionary:
	return _shop_module_logic.snapshot_shop(shop_id)
func _build_open_shop_payload(shop_id: String) -> Dictionary:
	return _shop_module_logic._build_open_shop_payload(shop_id)
## +delta rep (cap 1000); system_message「声望提升」only when crossing 100/300/600.
func _add_vendor_rep(shop_id: String, delta: int) -> Array:
	return _shop_module_logic._add_vendor_rep(shop_id, delta)
func try_accept_quest(quest_id: String) -> Dictionary:
	return _quest_module_logic.try_accept_quest(quest_id)
func try_abandon_quest(quest_id: String) -> Dictionary:
	return _quest_module_logic.try_abandon_quest(quest_id)
func try_turn_in_quest(quest_id: String) -> Dictionary:
	return _quest_module_logic.try_turn_in_quest(quest_id)
func try_shop_buy(shop_id: String, item_id: String, qty: int = 1) -> Dictionary:
	return _shop_module_logic.try_shop_buy(shop_id, item_id, qty)
func try_shop_sell(item_id: String, qty: int = 1) -> Dictionary:
	return _shop_module_logic.try_shop_sell(item_id, qty)
## Bulk sell junk from bag.
## Rules (sell-junk eligibility):
## - kind/type in [misc, material] (catalog uses `type`; accept `kind` alias)
## - not locked
## - unit sell_price ≤ 10 (catalog `sell_price`, fallback `price`)
## - exclude ids: pet_whistle, scroll_town
## - exclude id prefixes: potion_*, food_*, fish_* (even if type/price would match)
## try_shop_sell does not require shop open — same here (anytime + message).
func try_shop_sell_junk() -> Dictionary:
	return _shop_module_logic.try_shop_sell_junk()
func _shop_junk_unit_price(item_id: String) -> int:
	return _shop_module_logic._shop_junk_unit_price(item_id)
func _is_shop_junk_item(item_id: String) -> bool:
	return _shop_module_logic._is_shop_junk_item(item_id)
## Shop buyback ring (last N sold stacks this shop/map session).
const BUYBACK_MAX := 8
var _shop_buyback: Array = []


func snapshot_shop_buyback() -> Array:
	return _shop_module_logic.snapshot_shop_buyback()
func _clear_shop_session_buyback() -> void:
	_shop_module_logic._clear_shop_session_buyback()
## Client closed shop UI — drop buyback list for this session.
func try_shop_close() -> Dictionary:
	return _shop_module_logic.try_shop_close()
func _push_shop_buyback(item_id: String, qty: int, unit_price: int, bound: bool = false) -> void:
	_shop_module_logic._push_shop_buyback(item_id, qty, unit_price, bound)
func _shop_buyback_action() -> Dictionary:
	return _shop_module_logic._shop_buyback_action()
func try_shop_buyback(index: int, qty: int = -1) -> Dictionary:
	return _shop_module_logic.try_shop_buyback(index, qty)
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
	return _quest_module_logic._quest_update_action()
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
	return _quest_module_logic._quest_note_kill_actions(npc_id)
func _quest_note_talk_actions(npc_id: String) -> Array:
	return _quest_module_logic._quest_note_talk_actions(npc_id)
func _quest_note_item_actions(item_id: String, qty: int) -> Array:
	return _quest_module_logic._quest_note_item_actions(item_id, qty)
func _quest_note_fish_actions(item_id: String = "", qty: int = 1) -> Array:
	return _quest_module_logic._quest_note_fish_actions(item_id, qty)
func _quest_note_reach_actions(map_id: String, content_id: String = "", pack_path: String = "") -> Array:
	return _quest_module_logic._quest_note_reach_actions(map_id, content_id, pack_path)
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
	_session_module_logic.logout()
## NPC AI tick: hostiles idle/chase/return_home; friendlies with wander_radius idle-wander only.
func _tick_mob_ai(dt: float) -> Array:
	return _npc_ai_module_logic._tick_mob_ai(dt)
## Shared idle roam for hostiles and friendlies with wander_radius > 0.
func _mob_ai_idle_wander_step(npc_id: String, dt: float) -> Array:
	return _npc_ai_module_logic._mob_ai_idle_wander_step(npc_id, dt)
func _mob_ai_chase_step(npc_id: String, ai: Dictionary, cell: Vector2i, facing: int, px: int, py: int) -> Array:
	return _npc_ai_module_logic._mob_ai_chase_step(npc_id, ai, cell, facing, px, py)
func _try_npc_skill_tick(npc_id: String, ai: Dictionary, cell: Vector2i, px: int, py: int) -> Array:
	return _combat_module_logic._try_npc_skill_tick(npc_id, ai, cell, px, py)
func _mob_ai_return_home_step(npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i) -> Array:
	return _npc_ai_module_logic._mob_ai_return_home_step(npc_id, ai, cell, home)
## Increment stuck counter; teleport snap to home after RETURN_STUCK_TICKS, else face home.
func _mob_ai_return_home_stuck_or_face( npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i, actions: Array ) -> Array:
	return _npc_ai_module_logic._mob_ai_return_home_stuck_or_face(npc_id, ai, cell, home, actions)
## Snap NPC to home_cell (leash reset when path blocked / oscillating); emit npc_move; idle.
func _mob_ai_teleport_home( npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i, actions: Array ) -> Array:
	return _npc_ai_module_logic._mob_ai_teleport_home(npc_id, ai, cell, home, actions)
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
	return _combat_module_logic._threat_update_action(npc_id)
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
	_combat_module_logic._append_threat_updates(actions)
func _finalize_combat_result(result: Dictionary) -> Dictionary:
	return _combat_module_logic._finalize_combat_result(result)
func _actions_has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


## Respawn at town spawn or death cell; clear combat CDs server-side.
func _append_respawn_actions(actions: Array, where: String = "town") -> void:
	_movement_module_logic._append_respawn_actions(actions, where)
func try_respawn(where: String = "town") -> Dictionary:
	return _movement_module_logic.try_respawn(where)
func try_recall() -> Dictionary:
	return _movement_module_logic.try_recall()
func try_sit(on: bool = true) -> Dictionary:
	return _sustain_module_logic.try_sit(on)
## Pay gold at inn: full HP/MP restore + clear harmful statuses.
func try_inn_rest(cost: int = 25) -> Dictionary:
	return _sustain_module_logic.try_inn_rest(cost)
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
	_combat_module_logic._apply_npc_spawn_combat_overrides(npc_id, spawn_data)
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
	return _movement_module_logic._schedule_npc_respawn(npc_id)
## Fire due respawns → re-register + spawn_npc action for client.
func _tick_npc_respawns() -> Array:
	return _movement_module_logic._tick_npc_respawns()
## Place hostile at home (or find_spawn_near), re-register, return spawn_npc action dict.
func _respawn_npc_from_template(npc_id: String) -> Dictionary:
	return _movement_module_logic._respawn_npc_from_template(npc_id)
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
	return _profession_module_logic._craft_xp_needed_for(level)
func _reset_craft_skill() -> void:
	_profession_module_logic._reset_craft_skill()
func snapshot_craft() -> Dictionary:
	return _profession_module_logic.snapshot_craft()
func snapshot_recipes() -> Array:
	return _profession_module_logic.snapshot_recipes()
func try_craft(recipe_id: String, qty: int = 1) -> Dictionary:
	return _profession_module_logic.try_craft(recipe_id, qty)
## --- Gather profession (shared by try_gather / try_fish) ---

func _gather_xp_needed_for(level: int) -> int:
	return _profession_module_logic._gather_xp_needed_for(level)
func _reset_gather_skill() -> void:
	_profession_module_logic._reset_gather_skill()
func snapshot_gather() -> Dictionary:
	return _profession_module_logic.snapshot_gather()
func _gather_skill_update_action() -> Dictionary:
	return _profession_module_logic._gather_skill_update_action()
func _apply_gather_skill_xp(actions: Array, gained_xp: int = 5) -> void:
	_profession_module_logic._apply_gather_skill_xp(actions, gained_xp)
func _gather_level_required(def: Dictionary) -> int:
	return _profession_module_logic._gather_level_required(def)
func _fail_gather_level(actions: Array, need: int) -> Dictionary:
	return _profession_module_logic._fail_gather_level(actions, need)
## --- World gather nodes (herb / ore / scrap) ---

func _reload_gather_for_map() -> void:
	_profession_module_logic._reload_gather_for_map()
func _gather_now() -> float:
	return _profession_module_logic._gather_now()
func _gather_update_action(node_id: String, depleted: bool, display_name: String = "") -> Dictionary:
	return _profession_module_logic._gather_update_action(node_id, depleted, display_name)
func _gather_set_cell_blocked(node_id: String, blocked: bool) -> void:
	_profession_module_logic._gather_set_cell_blocked(node_id, blocked)
func _gather_in_range(node_id: String, player_x: int, player_y: int) -> bool:
	return _profession_module_logic._gather_in_range(node_id, player_x, player_y)
func try_gather(node_id: String) -> Dictionary:
	return _profession_module_logic.try_gather(node_id)
func _tick_gather_respawns() -> Array:
	return _profession_module_logic._tick_gather_respawns()
## Test / debug: force one or all depleted gather nodes ready immediately.
func force_gather_respawn(node_id: String = "") -> Array:
	return _profession_module_logic.force_gather_respawn(node_id)
func is_gather_depleted(node_id: String) -> bool:
	return _profession_module_logic.is_gather_depleted(node_id)
## --- World fishing spots ---

func _reload_fish_for_map() -> void:
	_profession_module_logic._reload_fish_for_map()
func _fish_now() -> float:
	return _profession_module_logic._fish_now()
func _fish_update_action(spot_id: String, depleted: bool, display_name: String = "") -> Dictionary:
	return _profession_module_logic._fish_update_action(spot_id, depleted, display_name)
func _fish_in_range(spot_id: String, player_x: int, player_y: int) -> bool:
	return _profession_module_logic._fish_in_range(spot_id, player_x, player_y)
## Prefer shiny bait over worm; empty if none.
func _best_fish_bait() -> String:
	return _profession_module_logic._best_fish_bait()
## Weighted yield pick; optional bait boosts fish_shiny (worm +0.15, shiny +0.35);
## rain/snow adds +0.1 shiny weight via WeatherGatherUtil.
func _pick_fish_yield(spot_def: Dictionary, bait_id: String = "") -> Dictionary:
	return _profession_module_logic._pick_fish_yield(spot_def, bait_id)
func try_fish(spot_id: String) -> Dictionary:
	return _profession_module_logic.try_fish(spot_id)
func _tick_fish_respawns() -> Array:
	return _profession_module_logic._tick_fish_respawns()
## Test / debug: force one or all depleted fish spots ready immediately.
func force_fish_respawn(spot_id: String = "") -> Array:
	return _profession_module_logic.force_fish_respawn(spot_id)
func is_fish_depleted(spot_id: String) -> bool:
	return _profession_module_logic.is_fish_depleted(spot_id)
## --- Personal warehouse / bank (in-memory; survives map transfer; reset on enter_world) ---

func snapshot_warehouse() -> Dictionary:
	return _warehouse_module_logic.snapshot_warehouse()
func _warehouse_update_action() -> Dictionary:
	return _warehouse_module_logic._warehouse_update_action()
func _warehouse_inventory_actions() -> Array:
	return _warehouse_module_logic._warehouse_inventory_actions()
func try_warehouse_open() -> Dictionary:
	return _warehouse_module_logic.try_warehouse_open()
func try_warehouse_deposit(item_id: String, qty: int = 1) -> Dictionary:
	return _warehouse_module_logic.try_warehouse_deposit(item_id, qty)
func try_warehouse_withdraw(item_id: String, qty: int = 1) -> Dictionary:
	return _warehouse_module_logic.try_warehouse_withdraw(item_id, qty)
func try_warehouse_deposit_gold(amount: int) -> Dictionary:
	return _warehouse_module_logic.try_warehouse_deposit_gold(amount)
func try_warehouse_withdraw_gold(amount: int) -> Dictionary:
	return _warehouse_module_logic.try_warehouse_withdraw_gold(amount)
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
	return _remote_module_logic.snapshot_remote_players()
func get_remote_player(remote_id: String) -> Dictionary:
	return _remote_module_logic.get_remote_player(remote_id)
func find_remote_by_name(remote_name: String) -> String:
	return _remote_module_logic.find_remote_by_name(remote_name)
func _remote_spawn_action(remote_id: String) -> Dictionary:
	return _remote_module_logic._remote_spawn_action(remote_id)
func _chebyshev(ax: int, ay: int, bx: int, by: int) -> int:
	return maxi(absi(ax - bx), absi(ay - by))


func _player_xy() -> Vector2i:
	if player_cell.x > -9990:
		return player_cell
	return Vector2i(0, 0)



## Ensure N wandering shell remotes exist (quiet; used on enter/transfer).
func _ensure_shell_remotes(want: int = 1) -> void:
	_remote_module_logic._ensure_shell_remotes(want)
func _shell_remote_spawn_actions() -> Array:
	return _remote_module_logic._shell_remote_spawn_actions()
## Spawn one stub remote near the local player for AOI / nearby chat demos.
func try_remote_debug_spawn(display_name: String = "") -> Dictionary:
	return _remote_module_logic.try_remote_debug_spawn(display_name)
## Fake-player idle patrol: roam within wander_radius of home (same cadence as mob idle).
func _tick_remote_patrol(dt: float) -> Array:
	return _remote_module_logic._tick_remote_patrol(dt)
func try_remote_despawn(remote_id: String = "") -> Dictionary:
	return _remote_module_logic.try_remote_despawn(remote_id)
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
	return _world_module_logic.snapshot_map_pins()
func list_map_pins_for_map(map_id: String = "") -> Array:
	return _world_module_logic.list_map_pins_for_map(map_id)
func _map_pins_update_action() -> Dictionary:
	return _world_module_logic._map_pins_update_action()
func _map_pin_slot_free() -> int:
	return _world_module_logic._map_pin_slot_free()
func _find_map_pin_index(x: int, y: int, map_id: String) -> int:
	return _world_module_logic._find_map_pin_index(x, y, map_id)
## Toggle personal pin at cell. Same cell clears; max MAP_PIN_MAX.
## Optional short_name overrides default 「标记N」.
func try_map_pin_toggle(x: int, y: int, map_id: String = "", short_name: String = "") -> Dictionary:
	return _world_module_logic.try_map_pin_toggle(x, y, map_id, short_name)
func try_map_pin_clear() -> Dictionary:
	return _world_module_logic.try_map_pin_clear()
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
	return _emote_module_logic.emote_catalog()
func try_emote(emote_id: String) -> Dictionary:
	return _emote_module_logic.try_emote(emote_id)
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
	return _combat_module_logic._try_revive_skill(skill_id, target_id, player_x, player_y)
## Resolve revive target: party member, fake remote ally, or ally-flagged NPC.
## Returns {kind, id, name, hp, hp_max, awaiting_respawn, x, y, map_id} or {}.
func _revive_resolve_target(target_id: String) -> Dictionary:
	return _combat_module_logic._revive_resolve_target(target_id)
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


func _revive_apply_to_target( kind: String, mid: String, new_hp: int, hp_max: int, dest: Vector2i, actions: Array ) -> void:
	_combat_module_logic._revive_apply_to_target(kind, mid, new_hp, hp_max, dest, actions)
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
	return _shop_module_logic.try_auction_buy(listing_id)
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
	return _pet_module_logic.snapshot_pet()
func _pet_reset() -> void:
	_pet_module_logic._pet_reset()
func _pet_spawn_action() -> Dictionary:
	return _pet_module_logic._pet_spawn_action()
func _pet_despawn_action() -> Dictionary:
	return _pet_module_logic._pet_despawn_action()
func _pet_pick_spawn_cell(pc: Vector2i) -> Vector2i:
	return _pet_module_logic._pet_pick_spawn_cell(pc)
func _pet_snap_near_player() -> void:
	_pet_module_logic._pet_snap_near_player()
func try_pet_summon(pet_id: String = "default") -> Dictionary:
	return _pet_module_logic.try_pet_summon(pet_id)
func try_pet_dismiss() -> Dictionary:
	return _pet_module_logic.try_pet_dismiss()
## Tick: move toward player when Chebyshev distance > PET_LAG_MAX; stay in lag 1–2.
func _tick_pet_follow(dt: float) -> Array:
	return _pet_module_logic._tick_pet_follow(dt)
func _pet_atk() -> int:
	return _pet_module_logic._pet_atk()
func _npc_display_name_for_pet(npc_id: String) -> String:
	return _pet_module_logic._npc_display_name_for_pet(npc_id)
## Resolve hostile the player is fighting; prefer locked target, else adjacent hate.
func _resolve_pet_combat_target() -> String:
	return _pet_module_logic._resolve_pet_combat_target()
func _pet_target_valid_in_range(npc_id: String, pet_cell: Vector2i) -> bool:
	return _pet_module_logic._pet_target_valid_in_range(npc_id, pet_cell)
## Periodic small pet damage on player's combat target (hate → player).
func _tick_pet_combat(dt: float) -> Array:
	return _pet_module_logic._tick_pet_combat(dt)
## --- Dungeon instance stub API ---

func in_dungeon() -> bool:
	return _dungeon_module_logic.in_dungeon()
func snapshot_dungeon() -> Dictionary:
	return _dungeon_module_logic.snapshot_dungeon()
func _dungeon_update_action() -> Dictionary:
	return _dungeon_module_logic._dungeon_update_action()
func _dungeon_force_clear_silent() -> void:
	_dungeon_module_logic._dungeon_force_clear_silent()
func _dungeon_abandon_on_leave() -> Array:
	return _dungeon_module_logic._dungeon_abandon_on_leave()
func _dungeon_return_cell_dict() -> Dictionary:
	return _dungeon_module_logic._dungeon_return_cell_dict()
func _dungeon_pick_guard_cells(count: int) -> Array:
	return _dungeon_module_logic._dungeon_pick_guard_cells(count)
func _dungeon_spawn_guards() -> Array:
	return _dungeon_module_logic._dungeon_spawn_guards()
func _dungeon_is_countable_kill(npc_id: String) -> bool:
	return _dungeon_module_logic._dungeon_is_countable_kill(npc_id)
func _dungeon_grant_rewards() -> Array:
	return _dungeon_module_logic._dungeon_grant_rewards()
func _dungeon_complete() -> Array:
	return _dungeon_module_logic._dungeon_complete()
func _dungeon_note_kill(npc_id: String) -> Array:
	return _dungeon_module_logic._dungeon_note_kill(npc_id)
func try_dungeon_enter() -> Dictionary:
	return _dungeon_module_logic.try_dungeon_enter()
func try_dungeon_exit() -> Dictionary:
	return _dungeon_module_logic.try_dungeon_exit()