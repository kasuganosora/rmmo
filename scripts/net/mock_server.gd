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
const Equipment = preload("res://scripts/net/combat/equipment.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const LootCatalog = preload("res://scripts/net/combat/loot_catalog.gd")
const QuestJournal = preload("res://scripts/net/combat/quest_journal.gd")
const ShopCatalog = preload("res://scripts/net/combat/shop_catalog.gd")
const EventRuntime = preload("res://scripts/net/combat/event_runtime.gd")

const DEMO_PACK_PATH := "res://demo_map"

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

## Authoritative map collision for the currently loaded pack
var map_collision: RefCounted = null
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

## Layered combat (authoritative).
var combat_stats = null
var combat_engine = null
var skill_catalog = null
var item_catalog = null
var inventory = null
var equipment = null
var loot_catalog = null
var quest_journal = null
var shop_catalog = null
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


func _ready() -> void:
	_init_combat_layers()
	_load_pack(DEMO_PACK_PATH)


func _init_combat_layers() -> void:
	combat_stats = CombatStats.new()
	skill_catalog = SkillCatalog.new()
	skill_catalog.load_catalog()
	item_catalog = ItemCatalog.new()
	item_catalog.load_catalog()
	loot_catalog = LootCatalog.new()
	loot_catalog.load_catalog()
	inventory = Inventory.new()
	inventory.set_catalog(item_catalog)
	inventory.grant_starter()
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
	combat_engine.setup(combat_stats, skill_catalog, item_catalog, inventory)
	combat_stats.reset_player(1)


func _process(delta: float) -> void:
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
	# Mob AI ticks (idle wander / chase / return_home / npc_move).
	_ai_tick_acc += delta
	if _ai_tick_acc >= AI_TICK_INTERVAL:
		var ai_dt: float = _ai_tick_acc
		_ai_tick_acc = 0.0
		var ai_actions: Array = _tick_mob_ai(ai_dt)
		if not ai_actions.is_empty():
			_pending_tick_actions.append_array(ai_actions)
	# Dead-mob respawn timers (independent of AI step rate).
	var respawn_actions: Array = _tick_npc_respawns()
	if not respawn_actions.is_empty():
		_pending_tick_actions.append_array(respawn_actions)
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


func _load_pack(pack_path: String) -> bool:
	var pack = TilemapPack.load_pack(pack_path)
	if pack == null or pack.collision == null:
		push_error("MockServer: failed to load pack collision at %s" % pack_path)
		return false
	map_collision = pack.collision
	# Build AStar graph once on load so the first click-to-move is hitch-free.
	if map_collision != null and map_collision.has_method("ensure_path_graph"):
		map_collision.ensure_path_graph()
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
	# Map events for this pack (keep session switches; reload defs only).
	if event_runtime == null:
		event_runtime = EventRuntime.new()
	event_runtime.load_from_pack(pack)
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
	if combat_engine != null and combat_engine.has_method("clear_cast"):
		combat_engine.clear_cast()
	npc_meta.clear()
	_pending_tick_actions.clear()
	_combat_tick_acc = 0.0
	_ai_tick_acc = 0.0
	return true


func _load_demo_map() -> void:
	_load_pack(DEMO_PACK_PATH)


func is_logged_in() -> bool:
	return _session_user != ""


func current_server() -> String:
	return _session_server


func login(username: String, password: String, server: String) -> void:
	await get_tree().create_timer(LATENCY_SEC).timeout
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
	await get_tree().create_timer(LATENCY_SEC * 0.6).timeout
	if not is_logged_in():
		characters_ready.emit([])
		return
	var list: Array = _accounts[_session_user]["characters"].duplicate(true)
	characters_ready.emit(list)


func create_character(char_name: String, class_id: String, look_id: String, gender: String = "female", customization: Dictionary = {}) -> void:
	await get_tree().create_timer(LATENCY_SEC).timeout
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
	await get_tree().create_timer(LATENCY_SEC * 1.2).timeout
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
	var lv: int = int(found.get("level", 1))
	_session_character_id = str(found.get("id", "")).strip_edges()
	if combat_stats != null:
		if combat_stats.has_method("set_player_actor_id"):
			combat_stats.set_player_actor_id(
				_session_character_id if _session_character_id != "" else "player"
			)
		combat_stats.reset_player(lv)
	if inventory != null:
		inventory.clear()
		inventory.grant_starter()
	if equipment != null:
		equipment.clear()
	if quest_journal != null:
		quest_journal.clear()
		quest_journal.grant_starter()
	if event_runtime != null:
		# Keep event defs from _load_pack; wipe switches for the new character session.
		event_runtime.clear_session()
	# Party shell: fresh session, no persistence.
	_party_clear()
	_party_poll_pending = false
	_trade_force_cancel_silent()
	_remote_players.clear()
	_next_remote_seq = 1
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
		"combat": combat_stats.snapshot_player_stats() if combat_stats != null else {},
		"inventory": inventory.snapshot() if inventory != null else [],
		"gold": inventory.get_gold() if inventory != null else 0,
		"equipment": equipment.snapshot() if equipment != null else [],
		"equipment_bonuses": equipment.total_bonuses() if equipment != null else {},
		"quests": quest_journal.snapshot() if quest_journal != null else [],
		"party": snapshot_party(),
		"trade": snapshot_trade(),
		"remote_players": snapshot_remote_players(),
		"ground_bags": snapshot_ground_bags(),
	}
	respawn_cell = spawn_cell
	last_safe_cell = spawn_cell
	set_player_cell(spawn_cell.x, spawn_cell.y)
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
	if facing not in [2, 4, 6, 8]:
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
			if fd in [2, 4, 6, 8]:
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
			combat_stats.npc_ai[npc_id] = ai
		# Cancel any pending respawn for this id (alive again).
		if hostile and _npc_respawn_at.has(npc_id):
			_npc_respawn_at.erase(npc_id)
	# Soft meta for interact / shop (friend and hostile).
	var meta := {
		"name": str(spawn_data.get("name", npc_id)),
		"interact_text": str(spawn_data.get("interact_text", "")),
		"shop_id": str(spawn_data.get("shop_id", "")).strip_edges(),
	}
	npc_meta[npc_id] = meta
	# Store / refresh spawn template for dead-mob respawn (hostiles).
	_store_npc_spawn_template(
		npc_id, x, y, hostile, aggressive, facing, wander_radius, group_id, leash_r, respawn_s, spawn_data, home_cell
	)


## Authoritative grid step. dir in {2,4,6,8}. Returns {ok, x, y, facing}.
## Rejects (with resync coords) when from ≠ authoritative player_cell.
func try_move(from_x: int, from_y: int, dir: int) -> Dictionary:
	if map_collision == null:
		return {"ok": false, "x": from_x, "y": from_y}
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
	if dir not in [2, 4, 6, 8]:
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
	var out := {"ok": true, "x": nx, "y": ny, "facing": dir}
	var all_actions: Array = []
	if not interrupt_actions.is_empty():
		all_actions.append_array(interrupt_actions)
	var touch_actions: Array = _try_player_touch_events(nx, ny)
	if not touch_actions.is_empty():
		all_actions.append_array(touch_actions)
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
	if dir not in [2, 4, 6, 8]:
		return {"ok": false, "x": from_x, "y": from_y}
	var delta: Vector2i = TileId.dir_delta(dir)
	var nx: int = from_x + delta.x
	var ny: int = from_y + delta.y
	# Mutual block with player (also mirrored via extra_blocked when set_player_cell used).
	if nx == player_cell.x and ny == player_cell.y:
		return {"ok": false, "x": from_x, "y": from_y}
	if not map_collision.can_pass(from_x, from_y, dir):
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
	return {"ok": true, "x": nx, "y": ny, "npc_id": npc_id, "facing": dir}



## Shared fields after a successful pack switch (warp / event transfer).
func _transfer_result_extras() -> Dictionary:
	return {
		"ground_bags": [],
		"remote_players": [],
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
	if to_pack.is_empty():
		return {"ok": false}
	var to_cell_v: Variant = warp.get("to_cell", {})
	if typeof(to_cell_v) != TYPE_DICTIONARY:
		return {"ok": false}
	var to_cell: Dictionary = to_cell_v
	var tx: int = int(to_cell.get("x", 0))
	var ty: int = int(to_cell.get("y", 0))
	var facing: int = int(warp.get("facing", 2))
	var message: String = str(warp.get("message", ""))
	var to_map_id: String = str(warp.get("to_map_id", ""))
	if not _load_pack(to_pack):
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
	out["actions"] = actions
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
	var actions: Array = []
	var meta: Dictionary = npc_meta.get(npc_id, {}) if typeof(npc_meta.get(npc_id, {})) == TYPE_DICTIONARY else {}
	# MV event by npc/event id (or cell under the NPC).
	if event_runtime != null:
		var ev: Dictionary = event_runtime.get_event(npc_id)
		if ev.is_empty() and combat_stats != null and combat_stats.has_method("get_npc_cell"):
			var nc: Vector2i = combat_stats.get_npc_cell(npc_id)
			if nc.x > -9990:
				ev = event_runtime.get_event_at_cell(nc.x, nc.y)
		if not ev.is_empty() and str(ev.get("trigger", "action")) == "action":
			var ctx := _event_server_ctx(str(meta.get("name", ev.get("name", npc_id))))
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
		var gold_v: int = inventory.get_gold() if inventory != null else 0
		actions.append({
			"type": "open_shop",
			"shop_id": shop_id,
			"title": shop_catalog.shop_title(shop_id),
			"listings": shop_catalog.build_listings(shop_id),
			"gold": gold_v,
		})
		# Talking to vendor still counts as talk progress.
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
	}


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
		return {"ok": false}
	var tx: int = int(to_cell.get("x", 0))
	var ty: int = int(to_cell.get("y", 0))
	var prev_path := map_pack_path
	if not _load_pack(to_pack):
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
	out["actions"] = actions
	return out


## After a successful step, fire player_touch events on the landing cell (once per page/self-switch).
func _try_player_touch_events(x: int, y: int) -> Array:
	if event_runtime == null:
		return []
	var ev: Dictionary = event_runtime.get_event_at_cell(x, y)
	if ev.is_empty():
		return []
	if str(ev.get("trigger", "")) != "player_touch":
		return []
	var ctx := _event_server_ctx(str(ev.get("name", ev.get("id", ""))))
	return event_runtime.run_event(str(ev.get("id", "")), ctx)


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
	if event_runtime == null:
		return {"ok": false, "actions": []}
	var actions: Array = event_runtime.try_event_choice(option_id, option_index)
	return {"ok": true, "actions": actions}


## Authoritative basic attack. Delegates to combat_engine.
func try_attack(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	if combat_engine == null:
		return {"ok": false, "actions": []}
	if player_cell.x > -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	var result: Dictionary = combat_engine.try_attack(npc_id, player_x, player_y)
	return _finalize_combat_result(result)


func try_use_skill(skill_id: String, target_npc_id: String = "", player_x: int = -9999, player_y: int = -9999) -> Dictionary:
	if combat_engine == null:
		return {"ok": false, "actions": []}
	if player_cell.x > -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	elif player_x <= -9990:
		player_x = player_cell.x
		player_y = player_cell.y
	var result: Dictionary = combat_engine.try_use_skill(skill_id, target_npc_id, player_x, player_y)
	return _finalize_combat_result(result)


func try_use_item(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	# Equipment: hotbar / inventory "use" toggles equip (not consume).
	if item_catalog != null and not item_id.is_empty():
		var def: Dictionary = item_catalog.get_item(item_id)
		if str(def.get("type", "")).strip_edges() == "equipment":
			return try_toggle_equip(item_id)
	if combat_engine == null:
		return {"ok": false, "actions": []}
	var result: Dictionary = combat_engine.try_use_item(item_id)
	return _finalize_combat_result(result)


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
		var msg := "无法装备。"
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
	return {
		"ok": true,
		"reason": "",
		"slot": slot_used,
		"unequipped_item_id": str(r.get("unequipped_item_id", "")),
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
	var amount: int = combat_stats.kill_exp_for_npc_level(npc_lv)
	var summary: Dictionary = combat_stats.grant_exp(amount)
	actions.append({
		"type": "exp_gain",
		"amount": int(summary.get("amount", amount)),
		"exp": int(summary.get("exp", 0)),
		"exp_to_next": int(summary.get("exp_to_next", 0)),
		"level": int(summary.get("level", 1)),
	})
	actions.append({
		"type": "system_message",
		"text": "获得经验 %d" % int(summary.get("amount", amount)),
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
		})
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
			var added: int = inventory.add_item(iid, qty)
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
	var gold_v: int = inventory.get_gold() if inventory != null else 0
	actions.append({
		"type": "open_shop",
		"shop_id": shop_id,
		"title": shop_catalog.shop_title(shop_id),
		"listings": shop_catalog.build_listings(shop_id),
		"gold": gold_v,
	})
	return {"ok": true, "shop_id": shop_id, "actions": actions}


func try_accept_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	var actions: Array = []
	if quest_journal == null:
		actions.append({"type": "system_message", "text": "任务系统不可用。"})
		return {"ok": false, "reason": "no_journal", "actions": actions}
	var already := false
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
	actions.append({
		"type": "quest_update",
		"quests": quest_journal.snapshot(),
	})
	var title := quest_id
	var q: Dictionary = quest_journal.get_quest(quest_id)
	if not q.is_empty():
		title = str(q.get("title", quest_id))
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
	actions.append({
		"type": "quest_update",
		"quests": quest_journal.snapshot(),
	})
	actions.append({"type": "system_message", "text": "已放弃任务：%s" % title})
	return {"ok": true, "quest_id": quest_id, "actions": actions}


func try_turn_in_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if quest_journal == null:
		return {"ok": false, "reason": "no_journal", "actions": [{"type": "system_message", "text": "任务系统不可用。"}]}
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
	actions.append({
		"type": "quest_update",
		"quests": quest_journal.snapshot(),
	})
	var title := quest_id
	var q: Dictionary = quest_journal.get_quest(quest_id)
	if not q.is_empty():
		title = str(q.get("title", quest_id))
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
	var unit: int = shop_catalog.buy_price_for(shop_id, item_id)
	if unit < 0:
		actions.append({"type": "system_message", "text": "价格无效。"})
		return {"ok": false, "reason": "bad_price", "actions": actions}
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
	# Refresh shop gold payload for client.
	actions.append({
		"type": "open_shop",
		"shop_id": shop_id,
		"title": shop_catalog.shop_title(shop_id),
		"listings": shop_catalog.build_listings(shop_id),
		"gold": inventory.get_gold(),
	})
	return {"ok": true, "actions": actions}


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
	if not inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "背包中没有足够的物品。"})
		return {"ok": false, "reason": "not_in_bag", "actions": actions}
	if not inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "出售失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var gained: int = sell_price * qty
	inventory.add_gold(gained)
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": "出售了 %s×%d（+%d 金币）" % [item_display_name(item_id), qty, gained],
	})
	return {"ok": true, "actions": actions}



## --- Ground bags + loot UI (bag-backed; close keeps items) ---

func snapshot_ground_bags() -> Array:
	var out: Array = []
	for bid in _ground_bags.keys():
		out.append(_bag_snapshot(str(bid)))
	return out


func ground_bag_count() -> int:
	return _ground_bags.size()


func get_ground_bag(bag_id: String) -> Dictionary:
	bag_id = bag_id.strip_edges()
	if bag_id.is_empty() or not _ground_bags.has(bag_id):
		return {}
	return _bag_snapshot(bag_id)


## Compatibility: true when an open loot UI session has remaining items.
func has_pending_loot() -> bool:
	return not _open_loot_bag_id.is_empty() and not _open_bag_items().is_empty()


func pending_loot_snapshot() -> Dictionary:
	if _open_loot_bag_id.is_empty() or not _ground_bags.has(_open_loot_bag_id):
		return {}
	var bag: Dictionary = _ground_bags[_open_loot_bag_id]
	return {
		"session_id": _open_loot_bag_id,
		"bag_id": _open_loot_bag_id,
		"npc_id": str(bag.get("npc_id", "")),
		"cell": (bag.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true),
		"items": _open_bag_items_dup(),
	}


## Open loot UI for a ground bag when player is on/adjacent to its cell.
func try_open_ground_bag(bag_id: String) -> Dictionary:
	bag_id = bag_id.strip_edges()
	var actions: Array = []
	if bag_id.is_empty() or not _ground_bags.has(bag_id):
		actions.append({"type": "system_message", "text": "地上没有该掉落物。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var bag: Dictionary = _ground_bags[bag_id]
	var items_v: Variant = bag.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	if items.is_empty():
		_remove_ground_bag(bag_id, actions)
		actions.append({"type": "system_message", "text": "掉落物已空。"})
		return {"ok": false, "reason": "empty", "actions": actions}
	var cell: Dictionary = bag.get("cell", {"x": 0, "y": 0})
	var bx: int = int(cell.get("x", 0))
	var by: int = int(cell.get("y", 0))
	if not _player_adjacent_or_on(bx, by):
		actions.append({"type": "system_message", "text": "离掉落物太远。"})
		return {"ok": false, "reason": "too_far", "actions": actions}
	# Switch open session without destroying previous bag.
	if not _open_loot_bag_id.is_empty() and _open_loot_bag_id != bag_id:
		actions.append({"type": "loot_close", "session_id": _open_loot_bag_id, "bag_id": _open_loot_bag_id})
	_open_loot_bag_id = bag_id
	actions.append(_loot_open_action())
	return {"ok": true, "bag_id": bag_id, "actions": actions}


## Find bag id at cell (merged bags: one per cell).
func find_ground_bag_at(x: int, y: int) -> String:
	for bid in _ground_bags.keys():
		var bag: Dictionary = _ground_bags[bid]
		var cell: Dictionary = bag.get("cell", {})
		if int(cell.get("x", -99999)) == x and int(cell.get("y", -99999)) == y:
			return str(bid)
	return ""


## Take one stack from the open ground bag. qty<=0 means all of that item_id.
func try_loot_take(item_id: String, qty: int = -1) -> Dictionary:
	item_id = item_id.strip_edges()
	var actions: Array = []
	if _open_loot_bag_id.is_empty() or not _ground_bags.has(_open_loot_bag_id):
		actions.append({"type": "system_message", "text": "没有可拾取的掉落。"})
		return {"ok": false, "reason": "no_loot", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inventory", "actions": actions}
	if item_id.is_empty():
		actions.append({"type": "system_message", "text": "无效物品。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var bag: Dictionary = _ground_bags[_open_loot_bag_id]
	var items: Array = _open_bag_items()
	var idx: int = -1
	var have: int = 0
	for i in range(items.size()):
		var d: Dictionary = items[i]
		if str(d.get("item_id", "")) == item_id:
			idx = i
			have = int(d.get("qty", 0))
			break
	if idx < 0 or have <= 0:
		actions.append({"type": "system_message", "text": "掉落中没有该物品。"})
		return {"ok": false, "reason": "missing", "actions": actions}
	var want: int = have if qty <= 0 else mini(qty, have)
	var add_r: Dictionary = inventory.try_add_item(item_id, want)
	var added: int = int(add_r.get("added", 0))
	if added <= 0:
		var reason := str(add_r.get("reason", "bag_full"))
		var msg := "背包已满，无法拾取 %s。" % item_display_name(item_id)
		if reason == "stack_full":
			msg = "该物品已达堆叠上限，无法拾取 %s。" % item_display_name(item_id)
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason if reason != "" else "bag_full", "actions": actions}
	var left: int = have - added
	if left > 0:
		items[idx] = {"item_id": item_id, "qty": left}
	else:
		items.remove_at(idx)
	bag["items"] = items
	_ground_bags[_open_loot_bag_id] = bag
	actions.append({
		"type": "system_message",
		"text": "获得 %s×%d" % [item_display_name(item_id), added],
	})
	actions.append_array(_quest_note_item_actions(item_id, added))
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	if items.is_empty():
		var sid := _open_loot_bag_id
		_remove_ground_bag(sid, actions)
		_open_loot_bag_id = ""
		actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})
	else:
		actions.append(_ground_update_action(_open_loot_bag_id))
		actions.append(_loot_update_action())
	return {"ok": true, "added": added, "item_id": item_id, "actions": actions}


func try_loot_take_all() -> Dictionary:
	var actions: Array = []
	if _open_loot_bag_id.is_empty() or not _ground_bags.has(_open_loot_bag_id):
		actions.append({"type": "system_message", "text": "没有可拾取的掉落。"})
		return {"ok": false, "reason": "no_loot", "actions": actions}
	if inventory == null:
		actions.append({"type": "system_message", "text": "背包不可用。"})
		return {"ok": false, "reason": "no_inventory", "actions": actions}
	var sid := _open_loot_bag_id
	var any_ok := false
	var bag_blocked := false
	var pending_ids: Array = []
	for d_v in _open_bag_items():
		if typeof(d_v) == TYPE_DICTIONARY:
			pending_ids.append(str(d_v.get("item_id", "")))
	for iid in pending_ids:
		if _open_loot_bag_id.is_empty() or not _ground_bags.has(_open_loot_bag_id):
			break
		iid = str(iid).strip_edges()
		if iid.is_empty():
			continue
		var r: Dictionary = try_loot_take(iid, -1)
		var sub: Array = r.get("actions", [])
		for a in sub:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var t := str(a.get("type", ""))
			# Nested take emits update/close/despawn; we emit a single final set.
			if t in ["loot_update", "loot_close", "ground_update", "ground_despawn"]:
				continue
			actions.append(a)
		if bool(r.get("ok", false)):
			any_ok = true
		else:
			var reason := str(r.get("reason", ""))
			if reason in ["bag_full", "stack_full"]:
				bag_blocked = true
	if not _ground_bags.has(sid) or _open_bag_items().is_empty():
		if _ground_bags.has(sid):
			_remove_ground_bag(sid, actions)
		else:
			actions.append({"type": "ground_despawn", "bag_id": sid})
		_open_loot_bag_id = ""
		actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})
		return {"ok": any_ok, "reason": ("" if any_ok else "empty"), "actions": actions}
	actions.append(_ground_update_action(sid))
	actions.append(_loot_update_action())
	if not any_ok and bag_blocked:
		return {"ok": false, "reason": "bag_full", "actions": actions}
	return {"ok": any_ok, "actions": actions}


## Close loot UI only — ground bag remains until emptied or map change.
func try_loot_close() -> Dictionary:
	var actions: Array = []
	var sid := _open_loot_bag_id
	var had := not sid.is_empty() and _ground_bags.has(sid) and not _open_bag_items().is_empty()
	_open_loot_bag_id = ""
	actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})
	if had:
		actions.append({"type": "system_message", "text": "已关闭掉落窗口（物品仍在地上）。"})
	return {"ok": true, "actions": actions}


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
	var out: Array = []
	if not _ground_bags.has(bag_id):
		return out
	var items_v: Variant = _ground_bags[bag_id].get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	for d_v in items:
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


func _bag_snapshot(bag_id: String) -> Dictionary:
	if not _ground_bags.has(bag_id):
		return {}
	var bag: Dictionary = _ground_bags[bag_id]
	return {
		"id": bag_id,
		"cell": (bag.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true),
		"items": _bag_items_dup(bag_id),
		"source": str(bag.get("source", "")),
		"owner_id": str(bag.get("owner_id", "")),
		"npc_id": str(bag.get("npc_id", "")),
		"created_at": float(bag.get("created_at", 0.0)),
	}


func _loot_update_action() -> Dictionary:
	var npc := ""
	if _ground_bags.has(_open_loot_bag_id):
		npc = str(_ground_bags[_open_loot_bag_id].get("npc_id", ""))
	return {
		"type": "loot_update",
		"session_id": _open_loot_bag_id,
		"bag_id": _open_loot_bag_id,
		"npc_id": npc,
		"items": _open_bag_items_dup(),
	}


func _loot_open_action() -> Dictionary:
	var bag: Dictionary = _ground_bags.get(_open_loot_bag_id, {})
	return {
		"type": "loot_open",
		"session_id": _open_loot_bag_id,
		"bag_id": _open_loot_bag_id,
		"npc_id": str(bag.get("npc_id", "")),
		"cell": (bag.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true),
		"items": _open_bag_items_dup(),
	}


func _ground_spawn_action(bag_id: String) -> Dictionary:
	return {"type": "ground_spawn", "bag": _bag_snapshot(bag_id)}


func _ground_update_action(bag_id: String) -> Dictionary:
	return {"type": "ground_update", "bag": _bag_snapshot(bag_id)}


func _remove_ground_bag(bag_id: String, actions: Array) -> void:
	if bag_id.is_empty():
		return
	if _ground_bags.has(bag_id):
		_ground_bags.erase(bag_id)
	actions.append({"type": "ground_despawn", "bag_id": bag_id})
	if _open_loot_bag_id == bag_id:
		_open_loot_bag_id = ""


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
func _add_items_to_ground(cell: Dictionary, add_items: Array, source: String, npc_id: String = "") -> Array:
	var actions: Array = []
	var cx: int = int(cell.get("x", 0))
	var cy: int = int(cell.get("y", 0))
	var existing_id := find_ground_bag_at(cx, cy)
	var created_at: float = 0.0
	if combat_stats != null and combat_stats.has_method("now_sec"):
		created_at = float(combat_stats.now_sec())
	else:
		created_at = Time.get_unix_time_from_system()
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
		"owner_id": "",
		"npc_id": npc_id,
		"created_at": created_at,
	}
	actions.append(_ground_spawn_action(bid))
	return actions


## Close open loot UI on death; ground bags persist.
func _clear_pending_loot_on_death(actions: Array) -> void:
	if _open_loot_bag_id.is_empty():
		return
	var sid := _open_loot_bag_id
	_open_loot_bag_id = ""
	actions.append({"type": "loot_close", "session_id": sid, "bag_id": sid})


func _quest_note_kill_actions(npc_id: String) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_kill(npc_id):
		actions.append({"type": "quest_update", "quests": quest_journal.snapshot()})
	return actions


func _quest_note_talk_actions(npc_id: String) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_talk(npc_id):
		actions.append({"type": "quest_update", "quests": quest_journal.snapshot()})
	return actions


func _quest_note_item_actions(item_id: String, qty: int) -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_item_gain(item_id, qty):
		actions.append({"type": "quest_update", "quests": quest_journal.snapshot()})
	return actions


func _quest_note_reach_actions(map_id: String, content_id: String = "", pack_path: String = "") -> Array:
	var actions: Array = []
	if quest_journal == null:
		return actions
	if quest_journal.note_reach(map_id, content_id, pack_path):
		actions.append({"type": "quest_update", "quests": quest_journal.snapshot()})
	return actions


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
		if player_ok:
			in_vision = MobAI.player_in_vision(cell, facing, player_cell, map_collision)
		var chasing: bool = str(ai.get("chase_target", "")) != "" or state == MobAI.AI_CHASE
		var can_aggro: bool = MobAI.wants_chase(ai)

		# --- Aggro / lose-sight (only while player alive) ---
		if player_ok and can_aggro and in_vision:
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

		# Home leash: while chasing, if too far from home → same as lose-sight.
		if chasing:
			ai = combat_stats.npc_ai[npc_id]
			home = MobAI.get_home_cell(ai)
			var leash_r: int = int(ai.get("leash_radius", MobAI.DEFAULT_LEASH_RADIUS))
			if MobAI.beyond_leash(cell, home, leash_r):
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
			var sv: String = combat_stats.select_victim(npc_id)
			ai = combat_stats.npc_ai[npc_id]
			if sv != "":
				ai["chase_target"] = sv
				combat_stats.npc_ai[npc_id] = ai
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
	var man: int = absi(cell.x - px) + absi(cell.y - py)
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


func _mob_ai_return_home_step(npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i) -> Array:
	var actions: Array = []
	if home.x <= -9990:
		ai["ai_state"] = MobAI.AI_IDLE
		combat_stats.npc_ai[npc_id] = ai
		return actions
	if cell == home:
		ai["ai_state"] = MobAI.AI_IDLE
		ai["idle_wander_acc"] = 0.0
		combat_stats.npc_ai[npc_id] = ai
		return actions
	var step_dir: int = MobAI.next_home_dir(map_collision, cell, home)
	if step_dir == 0:
		# Blocked / no path: face home; stay in return_home to retry.
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
	var moved: Dictionary = try_npc_move(npc_id, cell.x, cell.y, step_dir)
	if bool(moved.get("ok", false)):
		var nx: int = int(moved.get("x", cell.x))
		var ny: int = int(moved.get("y", cell.y))
		ai["facing"] = step_dir
		if Vector2i(nx, ny) == home:
			ai["ai_state"] = MobAI.AI_IDLE
			ai["idle_wander_acc"] = 0.0
		combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": nx,
			"y": ny,
			"facing": step_dir,
		})
	else:
		var face2: int = MobAI.facing_toward(cell, home)
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


## Evade: clear_chase (full HP + clear threat/enrage) and emit npc_reset for client HP bar.
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
	return actions


## Roll loot table for dead npc; spawn/merge ground bag at death cell (never home_cell).
## death_cell: Dictionary {x,y} or Vector2i from kill_npc action; fallback player_cell.
func _roll_and_grant_loot(npc_id: String, death_cell: Variant = null) -> Array:
	var actions: Array = []
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or loot_catalog == null:
		return actions
	var charset := ""
	var cell := {"x": player_cell.x, "y": player_cell.y}
	if typeof(death_cell) == TYPE_DICTIONARY:
		var dcd: Dictionary = death_cell
		cell = {"x": int(dcd.get("x", player_cell.x)), "y": int(dcd.get("y", player_cell.y))}
	elif typeof(death_cell) == TYPE_VECTOR2I:
		var dcv: Vector2i = death_cell
		if dcv.x > -9990:
			cell = {"x": dcv.x, "y": dcv.y}
	# Charset from spawn template only — NEVER use home_cell for loot placement.
	if npc_spawn_templates.has(npc_id):
		var tmpl: Dictionary = npc_spawn_templates[npc_id]
		charset = str(tmpl.get("charset", "")).strip_edges()
	var drops: Array = loot_catalog.roll(npc_id, charset)
	if drops.is_empty():
		return actions
	var pending_items: Array = []
	for d_v in drops:
		if typeof(d_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = d_v
		var iid := str(d.get("item_id", "")).strip_edges()
		var qty: int = int(d.get("qty", 0))
		if iid.is_empty() or qty <= 0:
			continue
		actions.append({
			"type": "loot_drop",
			"npc_id": npc_id,
			"item_id": iid,
			"qty": qty,
		})
		_merge_item_into_list(pending_items, iid, qty)
	if pending_items.is_empty():
		return actions
	actions.append_array(_add_items_to_ground(cell, pending_items, "monster", npc_id))
	actions.append({"type": "system_message", "text": "地上出现了掉落物。"})
	return actions


## True when NPC cell is registered and within manhattan range_cells.
func _require_npc_adjacent(npc_id: String, player_x: int, player_y: int, range_cells: int) -> bool:
	if combat_stats == null:
		return false
	var cell: Vector2i = combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return false
	var dist: int = absi(cell.x - player_x) + absi(cell.y - player_y)
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


func _finalize_combat_result(result: Dictionary) -> Dictionary:
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
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
		kill_extra.append_array(_quest_note_kill_actions(kid))
	if not kill_extra.is_empty():
		actions.append_array(kill_extra)
		result["actions"] = actions
	if _actions_has_type(actions, "player_died") or (combat_stats != null and not combat_stats.player_alive()):
		_append_respawn_actions(actions)
		result["actions"] = actions
		# Death always ok for apply path so client sees respawn opcodes.
		result["ok"] = true
	return result


func _actions_has_type(actions: Array, t: String) -> bool:
	for a in actions:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == t:
			return true
	return false


## Respawn at last safe / map spawn with full HP; clear combat CDs server-side.
func _append_respawn_actions(actions: Array) -> void:
	if combat_stats == null:
		return
	# Avoid double-append if already respawned in this action list.
	if _actions_has_type(actions, "respawn"):
		return
	var dest: Vector2i = last_safe_cell
	if dest.x <= -9990:
		dest = respawn_cell
	if map_collision != null and map_collision.has_method("is_landable"):
		if not map_collision.is_landable(dest.x, dest.y) and map_collision.has_method("find_spawn_near"):
			dest = map_collision.find_spawn_near(dest.x, dest.y)
	elif map_collision != null and map_collision.has_method("find_spawn_near") and (dest.x <= -9990):
		dest = map_collision.find_spawn_near()
	actions.append({"type": "system_message", "text": "你死了。"})
	_clear_pending_loot_on_death(actions)
	combat_stats.restore_after_death(false)
	if combat_engine != null and combat_engine.has_method("clear_cast"):
		combat_engine.clear_cast()
	set_player_cell(dest.x, dest.y)
	respawn_cell = dest
	last_safe_cell = dest
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
	actions.append({"type": "system_message", "text": "你已在安全点复活。"})

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
	if facing not in [2, 4, 6, 8]:
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
## [{id, name, hp, hp_max, online}, ...]
var _party_members: Array = []
var _next_party_seq: int = 1
var _stub_ally_seq: int = 1
## When true, next poll_combat_tick injects a party_update snapshot.
var _party_poll_pending: bool = false
## Shared assist target (npc_id); empty = none. Shell: leader sets, members see.
var party_shared_target_id: String = ""
var party_shared_target_name: String = ""
## Last emitted self hp fingerprint to avoid spammy party_update.
var _party_last_self_hp_fp: String = ""


func snapshot_party() -> Dictionary:
	return {
		"party_id": party_id,
		"leader": party_leader_id,
		"members": _party_members.duplicate(true),
		"shared_target_id": party_shared_target_id,
		"shared_target_name": party_shared_target_name,
	}


func in_party() -> bool:
	return party_id.strip_edges() != "" and not _party_members.is_empty()


func _party_update_action() -> Dictionary:
	_party_poll_pending = false
	return {"type": "party_update", "party": snapshot_party()}


func _mark_party_poll() -> void:
	_party_poll_pending = true


func _party_self_id() -> String:
	var aid := _session_character_id.strip_edges()
	if aid != "":
		return aid
	if combat_stats != null:
		var pa := str(combat_stats.player_actor_id).strip_edges()
		if pa != "":
			return pa
	return "player"


func _party_self_name() -> String:
	var sid := _party_self_id()
	if _session_user != "" and _accounts.has(_session_user):
		for c in _accounts[_session_user]["characters"]:
			if str(c.get("id", "")) == sid:
				var n := str(c.get("name", "")).strip_edges()
				if n != "":
					return n
	return "你"


func _party_self_hp() -> Dictionary:
	var hp := 100
	var hp_max := 100
	if combat_stats != null and not combat_stats.player.is_empty():
		hp = int(combat_stats.player.get("hp", 100))
		hp_max = int(combat_stats.player.get("hp_max", maxi(hp, 1)))
	return {"hp": hp, "hp_max": maxi(hp_max, 1)}


func _party_make_self_member() -> Dictionary:
	var hpinfo := _party_self_hp()
	return {
		"id": _party_self_id(),
		"name": _party_self_name(),
		"hp": int(hpinfo.get("hp", 100)),
		"hp_max": int(hpinfo.get("hp_max", 100)),
		"online": true,
	}


func _party_self_hp_fingerprint() -> String:
	var hpinfo := _party_self_hp()
	return "%d/%d" % [int(hpinfo.get("hp", 0)), int(hpinfo.get("hp_max", 0))]


## Update the local player's row in _party_members from combat_stats. Returns true if changed.
func _party_refresh_self_member() -> bool:
	if not in_party():
		return false
	var self_id := _party_self_id()
	var idx := _party_find_member_index(self_id)
	var fresh := _party_make_self_member()
	var fp := "%d/%d" % [int(fresh.get("hp", 0)), int(fresh.get("hp_max", 0))]
	if idx < 0:
		_party_members.insert(0, fresh)
		_party_last_self_hp_fp = fp
		return true
	var prev: Dictionary = _party_members[idx]
	var changed := (
		int(prev.get("hp", -1)) != int(fresh.get("hp", -2))
		or int(prev.get("hp_max", -1)) != int(fresh.get("hp_max", -2))
		or str(prev.get("name", "")) != str(fresh.get("name", ""))
	)
	_party_members[idx] = fresh
	if changed or fp != _party_last_self_hp_fp:
		_party_last_self_hp_fp = fp
		return true
	return false


func _party_find_member_index(member_id: String) -> int:
	member_id = member_id.strip_edges()
	if member_id.is_empty():
		return -1
	for i in range(_party_members.size()):
		var m: Variant = _party_members[i]
		if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) == member_id:
			return i
	return -1


func _party_find_member_by_name(member_name: String) -> int:
	member_name = member_name.strip_edges()
	if member_name.is_empty():
		return -1
	for i in range(_party_members.size()):
		var m: Variant = _party_members[i]
		if typeof(m) == TYPE_DICTIONARY and str(m.get("name", "")) == member_name:
			return i
	return -1


func _party_clear() -> void:
	party_id = ""
	party_leader_id = ""
	_party_members.clear()
	party_shared_target_id = ""
	party_shared_target_name = ""
	_party_last_self_hp_fp = ""


func _party_make_stub(stub_key: String = "") -> Dictionary:
	if stub_key.strip_edges() == "":
		stub_key = "stub_ally_%d" % _stub_ally_seq
		_stub_ally_seq += 1
	var names: Array = ["盟友甲", "盟友乙", "盟友丙", "队友丁"]
	var h: int = int(stub_key.hash())
	if h < 0:
		h = -h
	var idx: int = (_stub_ally_seq + h) % names.size()
	var hp_max: int = 80 + (h % 5) * 20
	var hp: int = maxi(1, int(float(hp_max) * 0.6) + (h % 20))
	return {
		"id": stub_key,
		"name": names[idx],
		"hp": hp,
		"hp_max": hp_max,
		"online": true,
	}


func try_party_create() -> Dictionary:
	var actions: Array = []
	if in_party():
		actions.append({"type": "system_message", "text": "你已在队伍中。"})
		actions.append(_party_update_action())
		return {"ok": false, "reason": "already_in_party", "actions": actions}
	party_id = "party_%d" % _next_party_seq
	_next_party_seq += 1
	party_leader_id = _party_self_id()
	_party_members = [_party_make_self_member()]
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已创建队伍。"})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


func try_party_invite(target: String = "") -> Dictionary:
	var actions: Array = []
	target = str(target).strip_edges()
	if not in_party():
		# Auto-create so invite works as a shell shortcut.
		var created: Dictionary = try_party_create()
		var ca: Variant = created.get("actions", [])
		if typeof(ca) == TYPE_ARRAY:
			for a in ca:
				# Drop the create tip; invite tip below is clearer.
				if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
					continue
				actions.append(a)
		if not bool(created.get("ok", false)) and not in_party():
			actions.append({"type": "system_message", "text": "无法创建队伍。"})
			return {"ok": false, "reason": "no_party", "actions": actions}
	if party_leader_id != _party_self_id():
		actions.append({"type": "system_message", "text": "只有队长可以邀请。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	# Resolve target: existing id/name match → noop; else spawn stub.
	# Prefer matching an existing remote/fake player by id or display name.
	var remote_id := ""
	var remote_name := ""
	if target != "":
		if _remote_players.has(target):
			remote_id = target
			var rd0: Variant = _remote_players[target]
			if typeof(rd0) == TYPE_DICTIONARY:
				remote_name = str(rd0.get("name", target))
		else:
			remote_id = find_remote_by_name(target)
			if remote_id != "":
				var rd1: Dictionary = get_remote_player(remote_id)
				remote_name = str(rd1.get("name", target))
				if remote_name.is_empty():
					remote_name = target
	var stub_id := ""
	if target != "":
		if _party_find_member_index(target) >= 0 or _party_find_member_by_name(target) >= 0:
			actions.append({"type": "system_message", "text": "对方已在队伍中。"})
			actions.append(_party_update_action())
			return {"ok": false, "reason": "already_member", "actions": actions}
		if remote_id != "" and (_party_find_member_index(remote_id) >= 0 or _party_find_member_by_name(remote_name) >= 0):
			actions.append({"type": "system_message", "text": "对方已在队伍中。"})
			actions.append(_party_update_action())
			return {"ok": false, "reason": "already_member", "actions": actions}
		if target.begins_with("stub_ally_"):
			stub_id = target
		elif remote_id != "":
			# Keep remote id as party member id so UI/kick can refer to the fake player.
			stub_id = remote_id
		else:
			# Treat free-form name/id as a new stub id slug.
			stub_id = "stub_ally_%s" % target.to_lower().replace(" ", "_")
	else:
		stub_id = "stub_ally_%d" % _stub_ally_seq
		_stub_ally_seq += 1
	if _party_members.size() >= 8:
		actions.append({"type": "system_message", "text": "队伍已满。"})
		return {"ok": false, "reason": "full", "actions": actions}
	var stub := _party_make_stub(stub_id)
	# Prefer remote display name, else human-readable invite name when provided.
	if remote_name != "":
		stub["name"] = remote_name
	elif target != "" and not target.begins_with("stub_ally_"):
		stub["name"] = target
	_party_members.append(stub)
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已邀请【%s】加入队伍（调试占位）。" % str(stub.get("name", stub_id))})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


func try_party_leave() -> Dictionary:
	var actions: Array = []
	if not in_party():
		actions.append({"type": "system_message", "text": "你不在队伍中。"})
		actions.append(_party_update_action())
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	var self_id := _party_self_id()
	var was_leader := party_leader_id == self_id
	var idx := _party_find_member_index(self_id)
	if idx >= 0:
		_party_members.remove_at(idx)
	# Shell: leaving dissolves the local party (stubs vanish with you).
	_party_clear()
	actions.append(_party_update_action())
	if was_leader:
		actions.append({"type": "system_message", "text": "你已离开队伍（队长离队，队伍解散）。"})
	else:
		actions.append({"type": "system_message", "text": "你已离开队伍。"})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


func try_party_kick(member_id: String = "") -> Dictionary:
	var actions: Array = []
	member_id = str(member_id).strip_edges()
	if not in_party():
		actions.append({"type": "system_message", "text": "你不在队伍中。"})
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	if party_leader_id != _party_self_id():
		actions.append({"type": "system_message", "text": "只有队长可以踢人。"})
		return {"ok": false, "reason": "not_leader", "actions": actions}
	if member_id.is_empty():
		actions.append({"type": "system_message", "text": "未指定队员。"})
		return {"ok": false, "reason": "no_target", "actions": actions}
	if member_id == _party_self_id():
		actions.append({"type": "system_message", "text": "不能踢出自己，请使用离开队伍。"})
		return {"ok": false, "reason": "self", "actions": actions}
	var idx := _party_find_member_index(member_id)
	if idx < 0:
		idx = _party_find_member_by_name(member_id)
	if idx < 0:
		actions.append({"type": "system_message", "text": "队伍中没有该队员。"})
		return {"ok": false, "reason": "not_found", "actions": actions}
	var kicked: Dictionary = _party_members[idx]
	var kname := str(kicked.get("name", member_id))
	_party_members.remove_at(idx)
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已将【%s】移出队伍。" % kname})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


## Debug helper: ensure a party exists and fill 1–2 stub allies for HUD bars.
func try_party_debug_fill() -> Dictionary:
	var actions: Array = []
	if not in_party():
		var created: Dictionary = try_party_create()
		var ca: Variant = created.get("actions", [])
		if typeof(ca) == TYPE_ARRAY:
			for a in ca:
				if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
					continue
				actions.append(a)
		if not in_party():
			actions.append({"type": "system_message", "text": "调试组队失败。"})
			return {"ok": false, "reason": "create_failed", "actions": actions}
	# Count non-self members.
	var self_id := _party_self_id()
	var others := 0
	for m in _party_members:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) != self_id:
			others += 1
	var want := 2
	var added: Array = []
	while others < want and _party_members.size() < 8:
		var stub := _party_make_stub()
		# Avoid id collision.
		if _party_find_member_index(str(stub.get("id", ""))) >= 0:
			continue
		_party_members.append(stub)
		added.append(str(stub.get("name", stub.get("id", ""))))
		others += 1
	actions.append(_party_update_action())
	if added.is_empty():
		actions.append({"type": "system_message", "text": "调试队伍已就绪。"})
	else:
		actions.append({"type": "system_message", "text": "调试组队：加入 %s。" % "、".join(added)})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


## Leader (or solo shell) marks a shared assist target for the party panel.
func try_party_set_target(npc_id: String = "", display_name: String = "") -> Dictionary:
	var actions: Array = []
	npc_id = str(npc_id).strip_edges()
	display_name = str(display_name).strip_edges()
	if not in_party():
		actions.append({"type": "system_message", "text": "不在队伍中，无法共享目标。"})
		return {"ok": false, "reason": "not_in_party", "actions": actions}
	if party_leader_id != _party_self_id():
		# Non-leader: still allow assist mark in shell so click-to-share works for the local player.
		pass
	if npc_id.is_empty():
		return try_party_clear_target()
	var same := party_shared_target_id == npc_id
	party_shared_target_id = npc_id
	if display_name.is_empty():
		display_name = npc_id
	party_shared_target_name = display_name
	_party_refresh_self_member()
	actions.append(_party_update_action())
	if not same:
		actions.append({"type": "system_message", "text": "队伍目标：%s" % party_shared_target_name})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


func try_party_clear_target() -> Dictionary:
	var actions: Array = []
	if not in_party():
		party_shared_target_id = ""
		party_shared_target_name = ""
		return {"ok": true, "actions": actions}
	if party_shared_target_id.is_empty() and party_shared_target_name.is_empty():
		actions.append(_party_update_action())
		return {"ok": true, "actions": actions}
	party_shared_target_id = ""
	party_shared_target_name = ""
	_party_refresh_self_member()
	actions.append(_party_update_action())
	actions.append({"type": "system_message", "text": "已清除队伍目标。"})
	_mark_party_poll()
	return {"ok": true, "actions": actions}


## --- Player trade shell (stub partner; escrow items/gold; no real netcode) ---

var _trade: Dictionary = {}  # empty = no session
var _next_trade_seq: int = 1


func snapshot_trade() -> Dictionary:
	if _trade.is_empty():
		return {"active": false}
	return {
		"active": true,
		"session_id": str(_trade.get("session_id", "")),
		"partner_id": str(_trade.get("partner_id", "")),
		"partner_name": str(_trade.get("partner_name", "")),
		"my_items": (_trade.get("my_items", []) as Array).duplicate(true),
		"their_items": (_trade.get("their_items", []) as Array).duplicate(true),
		"my_gold": int(_trade.get("my_gold", 0)),
		"their_gold": int(_trade.get("their_gold", 0)),
		"my_ready": bool(_trade.get("my_ready", false)),
		"their_ready": bool(_trade.get("their_ready", false)),
	}


func in_trade() -> bool:
	return not _trade.is_empty()


func _trade_update_action() -> Dictionary:
	return {"type": "trade_update", "trade": snapshot_trade()}


func _trade_close_action() -> Dictionary:
	return {"type": "trade_close"}


func _trade_force_cancel_silent() -> void:
	# Return escrow without UI spam (map reload / logout shell).
	if _trade.is_empty():
		return
	_trade_refund_my_escrow()
	_trade.clear()


func _trade_refund_my_escrow() -> void:
	if inventory == null:
		return
	var items_v: Variant = _trade.get("my_items", [])
	if typeof(items_v) == TYPE_ARRAY:
		for it in items_v:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var iid := str(it.get("item_id", "")).strip_edges()
			var q: int = maxi(int(it.get("qty", 0)), 0)
			if iid.is_empty() or q <= 0:
				continue
			inventory.add_item(iid, q)
	var g: int = maxi(int(_trade.get("my_gold", 0)), 0)
	if g > 0:
		inventory.add_gold(g)
	_trade["my_items"] = []
	_trade["my_gold"] = 0


func _trade_inventory_actions() -> Array:
	var actions: Array = []
	if inventory == null:
		return actions
	actions.append({
		"type": "inventory_update",
		"items": inventory.snapshot(),
		"gold": inventory.get_gold(),
	})
	return actions


func _trade_find_my_item(item_id: String) -> int:
	item_id = item_id.strip_edges()
	var items: Array = _trade.get("my_items", [])
	for i in range(items.size()):
		var it: Variant = items[i]
		if typeof(it) == TYPE_DICTIONARY and str(it.get("item_id", "")) == item_id:
			return i
	return -1


func try_trade_open(partner_name: String = "") -> Dictionary:
	var actions: Array = []
	if in_trade():
		actions.append({"type": "system_message", "text": "已在交易中。"})
		actions.append(_trade_update_action())
		return {"ok": false, "reason": "already", "actions": actions}
	partner_name = str(partner_name).strip_edges()
	var partner_id := "stub_trader_%d" % _next_trade_seq
	# Resolve existing remote/fake player by id or display name when provided.
	if not partner_name.is_empty():
		var rid := ""
		if _remote_players.has(partner_name):
			rid = partner_name
		else:
			rid = find_remote_by_name(partner_name)
		if rid != "":
			var rd: Dictionary = get_remote_player(rid)
			partner_id = rid
			var rn := str(rd.get("name", "")).strip_edges()
			if not rn.is_empty():
				partner_name = rn
	if partner_name.is_empty():
		partner_name = "旅人乙"
	_trade = {
		"session_id": "trade_%d" % _next_trade_seq,
		"partner_id": partner_id,
		"partner_name": partner_name,
		"my_items": [],
		"their_items": [],
		"my_gold": 0,
		"their_gold": 0,
		"my_ready": false,
		"their_ready": false,
	}
	_next_trade_seq += 1
	actions.append(_trade_update_action())
	actions.append({"type": "system_message", "text": "与【%s】开始交易（调试占位）。" % partner_name})
	return {"ok": true, "actions": actions}


func try_trade_cancel() -> Dictionary:
	var actions: Array = []
	if not in_trade():
		actions.append(_trade_close_action())
		return {"ok": true, "actions": actions}
	_trade_refund_my_escrow()
	_trade.clear()
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_close_action())
	actions.append({"type": "system_message", "text": "交易已取消。"})
	return {"ok": true, "actions": actions}


func try_trade_put_item(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = maxi(qty, 1)
	if not in_trade():
		actions.append({"type": "system_message", "text": "未在交易中。"})
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if bool(_trade.get("my_ready", false)):
		actions.append({"type": "system_message", "text": "已锁定，无法改动报价。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if inventory == null or not inventory.has_item(item_id, qty):
		actions.append({"type": "system_message", "text": "物品不足。"})
		return {"ok": false, "reason": "no_item", "actions": actions}
	if not inventory.consume(item_id, qty):
		actions.append({"type": "system_message", "text": "扣除物品失败。"})
		return {"ok": false, "reason": "consume_fail", "actions": actions}
	var idx := _trade_find_my_item(item_id)
	var items: Array = _trade.get("my_items", [])
	if idx >= 0:
		var row: Dictionary = items[idx]
		row["qty"] = int(row.get("qty", 0)) + qty
		items[idx] = row
	else:
		items.append({
			"item_id": item_id,
			"qty": qty,
			"name": item_display_name(item_id),
		})
	_trade["my_items"] = items
	_trade["their_ready"] = false
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_update_action())
	return {"ok": true, "actions": actions}


func try_trade_take_item(item_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	item_id = str(item_id).strip_edges()
	qty = maxi(qty, 1)
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if bool(_trade.get("my_ready", false)):
		actions.append({"type": "system_message", "text": "已锁定，无法改动报价。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	var idx := _trade_find_my_item(item_id)
	if idx < 0:
		return {"ok": false, "reason": "not_in_offer", "actions": actions}
	var items: Array = _trade.get("my_items", [])
	var row: Dictionary = items[idx]
	var have: int = int(row.get("qty", 0))
	var take: int = mini(qty, have)
	if take <= 0:
		return {"ok": false, "reason": "empty", "actions": actions}
	if inventory != null:
		inventory.add_item(item_id, take)
	have -= take
	if have <= 0:
		items.remove_at(idx)
	else:
		row["qty"] = have
		items[idx] = row
	_trade["my_items"] = items
	_trade["their_ready"] = false
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_update_action())
	return {"ok": true, "actions": actions}


func try_trade_set_gold(amount: int) -> Dictionary:
	var actions: Array = []
	amount = maxi(amount, 0)
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if bool(_trade.get("my_ready", false)):
		actions.append({"type": "system_message", "text": "已锁定，无法改动报价。"})
		return {"ok": false, "reason": "locked", "actions": actions}
	if inventory == null:
		return {"ok": false, "reason": "no_inv", "actions": actions}
	# Refund previous escrowed gold first, then re-escrow.
	var prev: int = maxi(int(_trade.get("my_gold", 0)), 0)
	if prev > 0:
		inventory.add_gold(prev)
		_trade["my_gold"] = 0
	if amount > 0:
		if not inventory.try_spend_gold(amount):
			actions.append({"type": "system_message", "text": "金币不足。"})
			actions.append_array(_trade_inventory_actions())
			actions.append(_trade_update_action())
			return {"ok": false, "reason": "no_gold", "actions": actions}
		_trade["my_gold"] = amount
	_trade["their_ready"] = false
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_update_action())
	return {"ok": true, "actions": actions}


func _trade_fill_stub_offer() -> void:
	## Canned counter-offer so the shell can complete a full swap.
	if int(_trade.get("their_gold", 0)) > 0 or not (_trade.get("their_items", []) as Array).is_empty():
		return
	_trade["their_gold"] = 15
	var oid := "potion_mp_small"
	_trade["their_items"] = [{
		"item_id": oid,
		"qty": 1,
		"name": item_display_name(oid),
	}]


func try_trade_ready(ready: bool = true) -> Dictionary:
	var actions: Array = []
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	_trade["my_ready"] = ready
	if ready:
		_trade_fill_stub_offer()
		_trade["their_ready"] = true
	else:
		_trade["their_ready"] = false
	actions.append(_trade_update_action())
	if ready:
		actions.append({"type": "system_message", "text": "你已锁定报价。对方（占位）已就绪。"})
	else:
		actions.append({"type": "system_message", "text": "已取消锁定。"})
	return {"ok": true, "actions": actions}


func try_trade_confirm() -> Dictionary:
	var actions: Array = []
	if not in_trade():
		return {"ok": false, "reason": "no_trade", "actions": actions}
	if not bool(_trade.get("my_ready", false)) or not bool(_trade.get("their_ready", false)):
		actions.append({"type": "system_message", "text": "双方需先锁定报价。"})
		return {"ok": false, "reason": "not_ready", "actions": actions}
	if inventory == null:
		return {"ok": false, "reason": "no_inv", "actions": actions}
	# Receive their offer (my escrow already removed from bag).
	var their_items: Array = _trade.get("their_items", [])
	for it in their_items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid := str(it.get("item_id", "")).strip_edges()
		var q: int = maxi(int(it.get("qty", 0)), 0)
		if iid.is_empty() or q <= 0:
			continue
		var add_r: Dictionary = inventory.try_add_item(iid, q)
		var added: int = int(add_r.get("added", 0)) if typeof(add_r) == TYPE_DICTIONARY else 0
		if added < q:
			# Rollback: refund remaining theirs not applied is lost in shell — prefer refund my escrow and abort.
			# Best-effort: put back what we couldn't take is already partial; keep shell simple: warn + keep trade open.
			actions.append({"type": "system_message", "text": "背包空间不足，交易未完成。"})
			actions.append_array(_trade_inventory_actions())
			actions.append(_trade_update_action())
			return {"ok": false, "reason": "bag_full", "actions": actions}
	var their_gold: int = maxi(int(_trade.get("their_gold", 0)), 0)
	if their_gold > 0:
		inventory.add_gold(their_gold)
	# My escrow stays with stub (consumed). Clear session.
	var pname := str(_trade.get("partner_name", "对方"))
	_trade.clear()
	actions.append_array(_trade_inventory_actions())
	actions.append(_trade_close_action())
	actions.append({"type": "system_message", "text": "与【%s】交易完成。" % pname})
	return {"ok": true, "actions": actions}


## --- Remote players (AOI/chat shell stubs; not combat NPCs) ---

const NEARBY_CHAT_RANGE := 12  # Chebyshev cells
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
	_remote_players[rid] = {
		"id": rid,
		"name": display_name,
		"cell": {"x": cell.x, "y": cell.y},
		"kind": "player",
	}
	actions.append(_remote_spawn_action(rid))
	actions.append({
		"type": "system_message",
		"text": "调试：假玩家【%s】出现在附近（%d,%d）。" % [display_name, cell.x, cell.y],
	})
	return {"ok": true, "remote_id": rid, "actions": actions}


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
			# Stub echo so shell feels two-way.
			actions.append({
				"type": "chat_message",
				"channel": "whisper",
				"speaker": tname,
				"speaker_id": tid,
				"target": speaker,
				"target_id": speaker_id,
				"text": "（占位回复）收到：%s" % text,
				"self": false,
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
			# Remotes in Chebyshev range auto-ack once (debug).
			var pc := _player_xy()
			var heard: Array = []
			for rid in _remote_players.keys():
				var d: Variant = _remote_players[rid]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				var cell_v: Variant = d.get("cell", {})
				if typeof(cell_v) != TYPE_DICTIONARY:
					continue
				var cx := int(cell_v.get("x", 0))
				var cy := int(cell_v.get("y", 0))
				if _chebyshev(pc.x, pc.y, cx, cy) <= NEARBY_CHAT_RANGE:
					heard.append(d)
			if heard.is_empty():
				actions.append({"type": "system_message", "text": "（附近）没有其他玩家听到。可菜单开调试假玩家。"})
			else:
				var first: Dictionary = heard[0]
				actions.append({
					"type": "chat_message",
					"channel": "nearby",
					"speaker": str(first.get("name", "旅人")),
					"speaker_id": str(first.get("id", "")),
					"text": "（附近）嗯。",
					"self": false,
				})
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

