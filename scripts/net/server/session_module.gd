extends RefCounted
## Domain module: session/auth (login, characters, enter_world, logout).

var ctrl
func _init(c):
	ctrl = c

const LATENCY_SEC := 0.35
const FriendList = preload("res://scripts/net/combat/friend_list.gd")
const Guild = preload("res://scripts/net/combat/guild.gd")
const Mailbox = preload("res://scripts/net/combat/mailbox.gd")
const Auction = preload("res://scripts/net/combat/auction.gd")
const DEMO_PACK_PATH := "content://map_pack/demo_map"
const SHELL_REMOTE_COUNT := 1

func login(username: String, password: String, server: String) -> void:
	if ctrl._login_inflight:
		return
	ctrl._login_inflight = true
	await ctrl.get_tree().create_timer(LATENCY_SEC).timeout
	ctrl._login_inflight = false
	username = username.strip_edges()
	server = server.strip_edges()
	if username.is_empty() or password.is_empty():
		ctrl.login_finished.emit(false, "请输入用户名和密码")
		return
	if server.is_empty():
		ctrl.login_finished.emit(false, "请输入服务器地址")
		return
	if not ctrl._accounts.has(username):
		ctrl._accounts[username] = {"password": password, "characters": []}
	elif str(ctrl._accounts[username].get("password", "")) != password:
		ctrl.login_finished.emit(false, "用户名或密码错误")
		return
	ctrl._session_user = username
	ctrl._session_server = server
	ctrl.login_finished.emit(true, "登录成功 · %s" % server)



func fetch_characters() -> void:
	if ctrl._fetch_inflight:
		return
	ctrl._fetch_inflight = true
	await ctrl.get_tree().create_timer(LATENCY_SEC * 0.6).timeout
	ctrl._fetch_inflight = false
	if not ctrl.is_logged_in():
		ctrl.characters_ready.emit([])
		return
	var list: Array = ctrl._accounts[ctrl._session_user]["characters"].duplicate(true)
	ctrl.characters_ready.emit(list)



func create_character(char_name: String, class_id: String, look_id: String, gender: String = "female", customization: Dictionary = {}) -> void:
	if ctrl._create_inflight:
		return
	ctrl._create_inflight = true
	await ctrl.get_tree().create_timer(LATENCY_SEC).timeout
	ctrl._create_inflight = false
	if not ctrl.is_logged_in():
		ctrl.character_created.emit(false, "未登录", {})
		return
	char_name = char_name.strip_edges()
	look_id = look_id.strip_edges()
	gender = gender.strip_edges().to_lower()
	if gender != "male":
		gender = "female"
	if char_name.is_empty():
		ctrl.character_created.emit(false, "请输入角色名", {})
		return
	if char_name.length() > 12:
		ctrl.character_created.emit(false, "名字太长（最多 12 字）", {})
		return
	var pid: Dictionary = customization.get("part_ids", {}) if typeof(customization) == TYPE_DICTIONARY else {}
	if look_id.is_empty() and (typeof(pid) != TYPE_DICTIONARY or (pid as Dictionary).is_empty()):
		ctrl.character_created.emit(false, "请选择外观", {})
		return
	for c in ctrl._accounts[ctrl._session_user]["characters"]:
		if str(c.get("name", "")) == char_name:
			ctrl.character_created.emit(false, "名字已被占用", {})
			return
	var ch = {
		"id": ctrl._next_char_id,
		"name": char_name,
		"class_id": class_id if class_id != "" else "adventurer",
		"level": 1,
		"look_id": look_id,
		"gender": gender,
		"customization": customization if typeof(customization) == TYPE_DICTIONARY else {},
	}
	ctrl._next_char_id += 1
	ctrl._accounts[ctrl._session_user]["characters"].append(ch)
	ctrl.character_created.emit(true, "创建成功", ch)



func enter_world(character_id: int) -> void:
	if ctrl._enter_inflight:
		return
	ctrl._enter_inflight = true
	await ctrl.get_tree().create_timer(LATENCY_SEC * 1.2).timeout
	ctrl._enter_inflight = false
	if not ctrl.is_logged_in():
		ctrl.enter_world_ready.emit(false, "未登录", {})
		return
	var found: Dictionary = {}
	for c in ctrl._accounts[ctrl._session_user]["characters"]:
		if int(c.get("id", -1)) == character_id:
			found = c
			break
	if found.is_empty():
		ctrl.enter_world_ready.emit(false, "找不到该角色", {})
		return
	# Always start the session on the home demo pack.
	ctrl._load_pack(DEMO_PACK_PATH)
	var spawn_cell = Vector2i(0, 0)
	if ctrl.map_collision != null and ctrl.map_collision.has_method("find_spawn_near"):
		spawn_cell = ctrl.map_collision.find_spawn_near()
	var ts: float = float(ctrl.map_tile_size)
	# Reset combat for this character session.
	ctrl.awaiting_respawn = false
	var lv: int = int(found.get("level", 1))
	ctrl._session_character_id = str(found.get("id", "")).strip_edges()
	if ctrl.combat_stats != null:
		if ctrl.combat_stats.has_method("set_player_actor_id"):
			ctrl.combat_stats.set_player_actor_id(
				ctrl._session_character_id if ctrl._session_character_id != "" else "player"
			)
		ctrl.combat_stats.reset_player(lv)
		ctrl.combat_stats.reset_titles()
		ctrl.combat_stats.reset_achievements()
		ctrl.combat_stats.set_achievement_counter_at_least("level", lv)
		ctrl._reset_skill_book()
	ctrl._reset_craft_skill()
	if ctrl.inventory != null:
		ctrl.inventory.clear()
		ctrl.inventory.grant_starter()
	if ctrl.warehouse != null:
		ctrl.warehouse.clear()
	ctrl._shop_buyback.clear()
	if ctrl.equipment != null:
		ctrl.equipment.clear()
	if ctrl.quest_journal != null:
		ctrl.quest_journal.clear()
		ctrl.quest_journal.grant_starter()
	if ctrl.event_runtime != null:
		# Keep event defs from _load_pack; wipe switches for the new character session.
		ctrl.event_runtime.clear_session()
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("reset_dps_fight"):
		ctrl.combat_engine.reset_dps_fight()
	ctrl._pending_tick_actions.clear()
	ctrl._collect_autorun()
	# Party shell: fresh session, no persistence.
	ctrl._party_clear()
	ctrl._party_poll_pending = false
	ctrl._trade_force_cancel_silent()
	ctrl._duel_force_clear_silent()
	# Friends shell: reset on new character session (survives map transfer only).
	if ctrl.friend_list != null:
		ctrl.friend_list.clear()
	else:
		ctrl.friend_list = FriendList.new()
	if ctrl.guild != null:
		ctrl.guild.clear()
	else:
		ctrl.guild = Guild.new()
	ctrl._guild_invites.clear()
	if ctrl.mailbox != null:
		ctrl.mailbox.clear()
	else:
		ctrl.mailbox = Mailbox.new()
	ctrl._mail_welcome_sent = false
	ctrl._mail_inject_welcome()
	ctrl._attendance_try_grant()
	if ctrl.auction != null:
		ctrl.auction.clear()
	else:
		ctrl.auction = Auction.new()
	ctrl._auction_seed_npc_stubs()
	ctrl._remote_players.clear()
	ctrl._next_remote_seq = 1
	ctrl._pet_reset()
	ctrl._map_pins.clear()
	ctrl._dungeon.clear()
	ctrl._dungeon_xfer_lock = false
	var daily_snap: Dictionary = ctrl.snapshot_daily()
	var combat_snap: Dictionary = ctrl.combat_stats.snapshot_player_stats() if ctrl.combat_stats != null else {}
	if not combat_snap.is_empty():
		combat_snap["mounted"] = ctrl.player_is_mounted()
		combat_snap["move_speed_mul"] = ctrl.player_move_speed_mul()
	var spawn = {
		"character": found,
		"map_id": ctrl.map_pack_id,
		"pack_path": ctrl.map_pack_path if ctrl.map_pack_path != "" else DEMO_PACK_PATH,
		"content_id": ctrl.map_content_id,
		"content_version": ctrl.map_content_version,
		"cell": {"x": spawn_cell.x, "y": spawn_cell.y},
		"position": {
			"x": float(spawn_cell.x) * ts + ts * 0.5,
			"y": float(spawn_cell.y) * ts + ts * 0.5,
		},
		"server": ctrl._session_server,
		"combat": combat_snap,
		"skill_book": ctrl.snapshot_skill_book(),
		"inventory": ctrl.inventory.snapshot() if ctrl.inventory != null else [],
		"gold": ctrl.inventory.get_gold() if ctrl.inventory != null else 0,
		"equipment": ctrl.equipment.snapshot() if ctrl.equipment != null else [],
		"equipment_bonuses": ctrl.equipment.total_bonuses() if ctrl.equipment != null else {},
		"quests": ctrl.quest_journal.snapshot() if ctrl.quest_journal != null else [],
		"daily_date": str(daily_snap.get("daily_date", "")),
		"daily": daily_snap.get("daily", []) if typeof(daily_snap.get("daily", [])) == TYPE_ARRAY else [],
		"party": ctrl.snapshot_party(),
		"trade": ctrl.snapshot_trade(),
		"duel": ctrl.snapshot_duel(),
		"dungeon": ctrl.snapshot_dungeon(),
		"safe_zone": ctrl.snapshot_safe_zone(),
		"warehouse": ctrl.snapshot_warehouse(),
		"friends": ctrl.snapshot_friends(),
		"guild": ctrl.snapshot_guild(),
		"mail": ctrl.snapshot_mail(),
		"auction": ctrl.snapshot_auction(),
		"titles": ctrl.snapshot_titles(),
		"achievements": ctrl.snapshot_achievements(),
		"remote_players": ctrl.snapshot_remote_players(),
		"ground_bags": ctrl.snapshot_ground_bags(),
		"pet": ctrl.snapshot_pet(),
		"map_pins": ctrl.snapshot_map_pins(),
		"craft_level": ctrl.craft_level,
		"craft_xp": ctrl.craft_xp,
		"craft_xp_to_next": ctrl.craft_xp_to_next,
		"gather_level": ctrl.gather_level,
		"gather_xp": ctrl.gather_xp,
		"gather_xp_to_next": ctrl.gather_xp_to_next,
	}
	ctrl.respawn_cell = spawn_cell
	ctrl.last_safe_cell = spawn_cell
	ctrl._safe_zone_known = false
	ctrl.set_player_cell(spawn_cell.x, spawn_cell.y)
	ctrl._ensure_shell_remotes(SHELL_REMOTE_COUNT)
	spawn["remote_players"] = ctrl.snapshot_remote_players()
	spawn["safe_zone"] = ctrl.snapshot_safe_zone()
	var _sz_enter: Array = ctrl._safe_zone_transition_actions(true)
	if not _sz_enter.is_empty():
		ctrl._pending_tick_actions.append_array(_sz_enter)
	# Map-reach objectives (demo_map start; street_map etc. via transfer).
	if ctrl.quest_journal != null:
		ctrl.quest_journal.note_reach(ctrl.map_pack_id, ctrl.map_content_id, ctrl.map_pack_path)
		spawn["quests"] = ctrl.quest_journal.snapshot()
	ctrl.enter_world_ready.emit(true, "正在进入世界", spawn)



func logout() -> void:
	ctrl._session_user = ""
	ctrl._session_server = ""
	ctrl._session_character_id = ""


