extends RefCounted
## 用例编排（应用层）：服务器动作分发与 ~40 个 action applier。
## 全部为静态方法，接收组合根 ctrl；applier 间互相调用用 apply_x(ctrl, ...)（同脚本内）。
## 仅搬运「对 action 字典 / 会话状态 / 纯数据做变换」的逻辑；节点创建、输入、场景树操作仍留在 World。

const Net = preload("res://scripts/net/net.gd")
const NpcActor = preload("res://scripts/game/npc_actor.gd")
const CombatFloater = preload("res://scripts/game/combat_floater.gd")
const CombatLogScript = preload("res://scripts/game/combat_log.gd")

static func apply_server_actions(ctrl, actions: Array, npc = null) -> void:
	## Execute MockServer/GameServer action opcodes. Chat opens only via show_npc_dialogue.
	## A wait action parks the rest of this batch until tick_event_wait elapses.
	if ctrl.hud == null:
		ctrl.hud = ctrl.get_node_or_null("CanvasLayer/GameHud")
	ctrl.last_applied_action_types = []
	var i = 0
	while i < actions.size():
		var item: Variant = actions[i]
		i += 1
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = item
		var atype = str(action.get("type", ""))
		if atype == "wait":
			var dur = maxf(float(action.get("duration", 0.0)), 0.0)
			if dur > 0.0:
				ctrl.last_applied_action_types.append("wait")
				ctrl._event_wait_left = dur
				ctrl._deferred_event_actions = actions.slice(i)
				ctrl._deferred_event_npc = npc
				return
			continue
		ctrl.last_applied_action_types.append(atype)
		match atype:
			"show_npc_dialogue":
				var display_name = str(action.get("npc_name", "")).strip_edges()
				if display_name == "" and npc != null:
					if "npc_name" in npc and str(npc.npc_name).strip_edges() != "":
						display_name = str(npc.npc_name)
				var body = str(action.get("body", ""))
				var options_v: Variant = action.get("options", [])
				var options: Array = options_v if typeof(options_v) == TYPE_ARRAY else []
				if ctrl.hud != null and ctrl.hud.has_method("show_npc_dialogue"):
					var face = {
						"id": str(action.get("face", "")).strip_edges(),
						"index": int(action.get("face_index", 0)),
						"pack_dir": str(ctrl.map_field.pack.pack_dir) if ctrl.map_field != null and ctrl.map_field.pack != null else "",
					}
					ctrl.hud.show_npc_dialogue(display_name, body, options, face)
			"damage":
				apply_damage_action(ctrl, action, npc)
			"heal":
				apply_heal_action(ctrl, action)
			"miss":
				apply_miss_action(ctrl, action)
			"set_stat":
				apply_set_stat(ctrl, action)
			"skill_cd":
				apply_skill_cd(ctrl, action)
			"status_update":
				apply_status_update(ctrl, action)
			"inventory_update":
				apply_inventory_update(ctrl, action)
			"equipment_update":
				apply_equipment_update(ctrl, action)
			"quest_update":
				apply_quest_update(ctrl, action)
			"kill_npc":
				apply_kill_npc(ctrl, str(action.get("npc_id", "")), npc)
			"spawn_npc":
				apply_spawn_npc(ctrl, action)
			"gather_update":
				apply_gather_update(ctrl, action)
				if action.has("gather_level") and ctrl.hud != null and ctrl.hud.has_method("apply_gather_update"):
					ctrl.hud.apply_gather_update(action)
			"fish_update":
				apply_fish_update(ctrl, action)
			"player_died":
				ctrl._clear_pending_engage()
				ctrl.stop_follow()
				ctrl._auto_attack = false
				if ctrl.player != null:
					ctrl.player.input_locked = true
					if ctrl.player.has_method("clear_move_path"):
						ctrl.player.clear_move_path()
				if ctrl.hud != null and ctrl.hud.has_method("clear_target"):
					ctrl.hud.clear_target()
				if ctrl.hud != null and ctrl.hud.has_method("show_death_dialog"):
					ctrl.hud.show_death_dialog()
			"respawn":
				apply_respawn(ctrl, action)
			"recall":
				apply_recall(ctrl, action)
			"player_move":
				apply_player_move(ctrl, action)
			"sit":
				apply_sit(ctrl, action)
			"npc_move":
				apply_npc_move(ctrl, action)
			"event_graphic":
				apply_event_graphic(ctrl, action)
			"play_audio":
				ctrl._play_pack_audio(str(action.get("channel", "se")), str(action.get("id", "")))
			"npc_reset":
				apply_npc_reset(ctrl, action)
			"loot_drop":
				pass  # informational; ground bags + loot UI driven separately
			"ground_spawn":
				apply_ground_spawn(ctrl, action)
			"ground_update":
				apply_ground_update(ctrl, action)
			"ground_despawn":
				apply_ground_despawn(ctrl, action)
			"loot_open":
				apply_loot_open(ctrl, action)
			"loot_update":
				apply_loot_update(ctrl, action)
			"loot_close":
				apply_loot_close(ctrl, action)
			"loot_roll_start":
				if ctrl.hud != null and ctrl.hud.has_method("show_loot_roll"):
					ctrl.hud.show_loot_roll(action)
			"loot_roll_choice":
				if ctrl.hud != null and ctrl.hud.has_method("apply_loot_roll_choice"):
					ctrl.hud.apply_loot_roll_choice(action)
			"loot_roll_resolve":
				if ctrl.hud != null and ctrl.hud.has_method("hide_loot_roll"):
					ctrl.hud.hide_loot_roll(action)
			"exp_gain":
				apply_exp_gain(ctrl, action)
			"level_up":
				apply_level_up(ctrl, action)
			"open_shop":
				apply_open_shop(ctrl, action)
			"map_transfer":
				if bool(action.get("ok", true)):
					ctrl._on_transfer_requested(action)
			"cast_start":
				var npc_caster = str(action.get("npc_id", "")).strip_edges()
				if npc_caster.is_empty():
					var c0 = str(action.get("caster", "")).strip_edges()
					if c0 != "" and c0 != "player":
						npc_caster = c0
				var ckind = str(action.get("anim", "cast")).strip_edges()
				if ckind.is_empty():
					ckind = "cast"
				if npc_caster.is_empty():
					if ctrl.hud != null and ctrl.hud.has_method("apply_cast_start"):
						ctrl.hud.apply_cast_start(action)
					apply_skill_anim(ctrl, {
						"actor": "player",
						"kind": ckind,
						"skill_id": str(action.get("skill_id", "")),
					})
				else:
					apply_skill_anim(ctrl, {
						"actor": npc_caster,
						"kind": ckind,
						"skill_id": str(action.get("skill_id", "")),
					})
			"cast_update":
				var npc_cu = str(action.get("npc_id", "")).strip_edges()
				if npc_cu.is_empty():
					var c1 = str(action.get("caster", "")).strip_edges()
					if c1 != "" and c1 != "player":
						npc_cu = c1
				if npc_cu.is_empty() and ctrl.hud != null and ctrl.hud.has_method("apply_cast_update"):
					ctrl.hud.apply_cast_update(action)
			"cast_end":
				var npc_ce = str(action.get("npc_id", "")).strip_edges()
				if npc_ce.is_empty():
					var c2 = str(action.get("caster", "")).strip_edges()
					if c2 != "" and c2 != "player":
						npc_ce = c2
				if npc_ce.is_empty() and ctrl.hud != null and ctrl.hud.has_method("apply_cast_end"):
					ctrl.hud.apply_cast_end(action)
			"skill_fx":
				apply_skill_fx(ctrl, action)
			"skill_anim":
				apply_skill_anim(ctrl, action)
			"skill_book_update":
				apply_skill_book_update(ctrl, action)
			"attr_update":
				apply_attr_update(ctrl, action)
			"skill_respec":
				apply_skill_respec(ctrl, action)
			"party_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_party_update"):
					ctrl.hud.apply_party_update(action)
			"party_invite":
				if ctrl.hud != null and ctrl.hud.has_method("apply_party_invite"):
					ctrl.hud.apply_party_invite(action)
			"trade_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_trade_update"):
					ctrl.hud.apply_trade_update(action)
			"duel_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_duel_update"):
					ctrl.hud.apply_duel_update(action)
			"safe_zone":
				if ctrl.hud != null and ctrl.hud.has_method("apply_safe_zone"):
					ctrl.hud.apply_safe_zone(action)
			"dungeon_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_dungeon_update"):
					ctrl.hud.apply_dungeon_update(action)
			"rested_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_rested_update"):
					ctrl.hud.apply_rested_update(action)
				elif ctrl.hud != null and ctrl.hud.has_method("apply_combat_stats"):
					ctrl.hud.apply_combat_stats({
						"rested_exp": int(action.get("rested_exp", 0)),
						"rested_exp_max": int(action.get("rested_exp_max", 0)),
					})
			"craft_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_craft_update"):
					ctrl.hud.apply_craft_update(action)
			"threat_update":
				apply_threat_update(ctrl, action)
			"dps_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_dps_update"):
					ctrl.hud.apply_dps_update(action)
			"warehouse_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_warehouse_update"):
					ctrl.hud.apply_warehouse_update(action)
			"friends_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_friends_update"):
					ctrl.hud.apply_friends_update(action)
			"map_pins_update":
				ctrl._radar_blips_ready = false
				if ctrl.hud != null and ctrl.hud.has_method("apply_map_pins_update"):
					ctrl.hud.apply_map_pins_update(action)
				else:
					ctrl._sync_map_pins_from_server(action.get("map_pins", {}))
			"guild_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_guild_update"):
					ctrl.hud.apply_guild_update(action)
			"guild_invite":
				if ctrl.hud != null and ctrl.hud.has_method("apply_guild_invite"):
					ctrl.hud.apply_guild_invite(action)
			"mail_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_mail_update"):
					ctrl.hud.apply_mail_update(action)
			"auction_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_auction_update"):
					ctrl.hud.apply_auction_update(action)
			"title_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_title_update"):
					ctrl.hud.apply_title_update(action)
			"achievement_update":
				if ctrl.hud != null and ctrl.hud.has_method("apply_achievement_update"):
					ctrl.hud.apply_achievement_update(action)
			"shop_buyback":
				if ctrl.hud != null and ctrl.hud.has_method("apply_shop_buyback"):
					ctrl.hud.apply_shop_buyback(action.get("buyback", []))
				if action.has("gold") and ctrl.hud != null:
					ctrl.hud._server_gold = int(action.get("gold", ctrl.hud._server_gold))
			"trade_close":
				if ctrl.hud != null and ctrl.hud.has_method("hide_trade"):
					ctrl.hud.hide_trade()
			"remote_spawn":
				var rp_v: Variant = action.get("player", {})
				if typeof(rp_v) == TYPE_DICTIONARY:
					ctrl._upsert_remote_marker(rp_v)
			"remote_despawn":
				ctrl._remove_remote_marker(str(action.get("player_id", "")))
			"remote_move":
				apply_remote_move(ctrl, action)
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
				ctrl._upsert_pet_marker(pet_s)
			"pet_despawn":
				ctrl._remove_pet_marker()
			"pet_move":
				apply_pet_move(ctrl, action)
			"chat_message":
				if ctrl.hud != null and ctrl.hud.has_method("apply_chat_message"):
					ctrl.hud.apply_chat_message(action)
			"emote":
				apply_emote(ctrl, action)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if msg != "" and ctrl.hud != null and ctrl.hud.has_method("append_system"):
					ctrl.hud.append_system(msg)
			"weather":
				apply_weather_action(ctrl, action)

static func apply_npc_move(ctrl, action: Dictionary) -> void:
	var npc_id = str(action.get("npc_id", "")).strip_edges()
	if npc_id.is_empty():
		return
	var target = ctrl._find_npc_by_id(npc_id)
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
	ctrl._radar_blips_ready = false

static func apply_npc_reset(ctrl, action: Dictionary) -> void:
	## Evade / return-home: restore client NPC HP bar to full.
	var npc_id = str(action.get("npc_id", "")).strip_edges()
	if npc_id.is_empty():
		return
	var target = ctrl._find_npc_by_id(npc_id)
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
	if npc_id == ctrl._selected_npc_id:
		var display_name = npc_id
		if "npc_name" in target and str(target.npc_name).strip_edges() != "":
			display_name = str(target.npc_name)
		var ratio: float = 1.0 if hp_max <= 0 else float(hp) / float(hp_max)
		ctrl._push_target_hud(target, display_name, ratio)

static func apply_damage_action(ctrl, action: Dictionary, npc = null) -> void:
	var target = str(action.get("target", "npc"))
	var amount: int = int(action.get("amount", 0))
	var hp: int = int(action.get("hp", 0))
	var hp_max: int = int(action.get("hp_max", 0))
	var id = str(action.get("id", ""))
	var is_miss = bool(action.get("miss", false)) or str(action.get("result", "")).strip_edges().to_lower() == "miss" or (amount <= 0 and bool(action.get("show_miss", false)))
	var is_crit = bool(action.get("crit", false)) or bool(action.get("critical", false))
	if target == "player":
		if ctrl.hud != null and ctrl.hud.has_method("apply_combat_stats"):
			ctrl.hud.apply_combat_stats({
				"hp": hp,
				"hp_max": hp_max,
				"mp": int(action.get("mp", -1)),
				"mp_max": int(action.get("mp_max", -1)),
			})
		if is_miss:
			ctrl._spawn_combat_floater(
				ctrl.player.global_position if ctrl.player != null else Vector2.ZERO,
				CombatFloater.text_for("miss"), Color(), "miss", "player", false
			)
			if ctrl.hud != null:
				if ctrl.hud.has_method("append_combat_typed"):
					ctrl.hud.append_combat_typed("miss", CombatLogScript.line_miss())
				elif ctrl.hud.has_method("append_combat"):
					ctrl.hud.append_combat(CombatLogScript.line_miss())
				elif ctrl.hud.has_method("append_system"):
					ctrl.hud.append_system(CombatLogScript.line_miss())
			return
		if ctrl.hud != null and amount > 0:
			var line_in = CombatLogScript.line_damage_in(amount, is_crit)
			if ctrl.hud.has_method("append_combat_typed"):
				ctrl.hud.append_combat_typed("damage", line_in)
			elif ctrl.hud.has_method("append_combat"):
				ctrl.hud.append_combat(line_in)
			elif ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system(line_in)
		if amount > 0:
			if ctrl.player != null and ctrl.player.has_method("flash_hurt"):
				ctrl.player.flash_hurt()
			var ppos: Vector2 = ctrl.player.global_position if ctrl.player != null else Vector2.ZERO
			ctrl._spawn_combat_floater(ppos, CombatFloater.text_for("damage", amount, is_crit), Color(), "damage", "player", is_crit)
			if is_crit:
				ctrl._trigger_crit_shake()
		return
	if target == "remote":
		var mk = ctrl._remote_markers.get(id, null) if id != "" else null
		var rname = id
		if mk != null and is_instance_valid(mk):
			rname = str(mk.get_meta("display_name", id))
			if is_miss:
				ctrl._spawn_combat_floater(mk.global_position, CombatFloater.text_for("miss"), Color(), "miss", "remote:%s" % id, false)
			elif amount > 0:
				ctrl._spawn_combat_floater(mk.global_position, CombatFloater.text_for("damage_out", amount, is_crit), Color(), "damage_out", "remote:%s" % id, is_crit)
		if is_miss:
			if ctrl.hud != null:
				if ctrl.hud.has_method("append_combat_typed"):
					ctrl.hud.append_combat_typed("miss", CombatLogScript.line_miss())
				elif ctrl.hud.has_method("append_combat"):
					ctrl.hud.append_combat(CombatLogScript.line_miss())
				elif ctrl.hud.has_method("append_system"):
					ctrl.hud.append_system(CombatLogScript.line_miss())
			return
		if ctrl.hud != null and amount > 0:
			var line_r = CombatLogScript.line_damage_out(rname, amount, is_crit)
			if ctrl.hud.has_method("append_combat_typed"):
				ctrl.hud.append_combat_typed("damage", line_r)
			elif ctrl.hud.has_method("append_combat"):
				ctrl.hud.append_combat(line_r)
			elif ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system(line_r)
		if amount > 0 and is_crit:
			ctrl._trigger_crit_shake()
		return
	var display_name = "敌人"
	var target_npc = npc
	if target_npc == null or ("npc_id" in target_npc and str(target_npc.npc_id) != id):
		target_npc = ctrl._find_npc_by_id(id)
	if target_npc != null:
		if "npc_name" in target_npc and str(target_npc.npc_name).strip_edges() != "":
			display_name = str(target_npc.npc_name)
		if "hp" in target_npc:
			target_npc.hp = hp
		if "hp_max" in target_npc:
			target_npc.hp_max = hp_max
		if id == ctrl._selected_npc_id or ctrl._selected_npc_id.is_empty():
			if ctrl._selected_npc_id.is_empty() or id == ctrl._selected_npc_id:
				ctrl._selected_npc_id = id
				if target_npc.has_method("set_selected"):
					target_npc.set_selected(true)
			var ratio: float = 1.0 if hp_max <= 0 else float(hp) / float(hp_max)
			ctrl._push_target_hud(target_npc, display_name, ratio)
	if is_miss:
		var mpos = Vector2.ZERO
		if target_npc != null:
			mpos = target_npc.global_position
		ctrl._spawn_combat_floater(mpos, CombatFloater.text_for("miss"), Color(), "miss", "npc:%s" % id, false)
		if ctrl.hud != null:
			if ctrl.hud.has_method("append_combat_typed"):
				ctrl.hud.append_combat_typed("miss", CombatLogScript.line_miss())
			elif ctrl.hud.has_method("append_combat"):
				ctrl.hud.append_combat(CombatLogScript.line_miss())
			elif ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system(CombatLogScript.line_miss())
		return
	if ctrl.hud != null and amount > 0:
		var line_n = CombatLogScript.line_damage_out(display_name, amount, is_crit)
		if ctrl.hud.has_method("append_combat_typed"):
			ctrl.hud.append_combat_typed("damage", line_n)
		elif ctrl.hud.has_method("append_combat"):
			ctrl.hud.append_combat(line_n)
		elif ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system(line_n)
	if amount > 0:
		if target_npc != null and target_npc.has_method("flash_hurt"):
			target_npc.flash_hurt()
		var npos = Vector2.ZERO
		if target_npc != null:
			npos = target_npc.global_position
		ctrl._spawn_combat_floater(npos, CombatFloater.text_for("damage_out", amount, is_crit), Color(), "damage_out", "npc:%s" % id, is_crit)
		if is_crit:
			ctrl._trigger_crit_shake()

static func apply_miss_action(ctrl, action: Dictionary) -> void:
	## Gray 「未命中」 over the intended target (player / npc / remote).
	var target = str(action.get("target", "npc")).strip_edges()
	var id = str(action.get("id", action.get("npc_id", ""))).strip_edges()
	var pos = Vector2.ZERO
	var key = "default"
	if target == "player":
		pos = ctrl.player.global_position if ctrl.player != null else Vector2.ZERO
		key = "player"
	elif target == "remote":
		var mk = ctrl._remote_markers.get(id, null) if id != "" else null
		if mk != null and is_instance_valid(mk):
			pos = mk.global_position
		key = "remote:%s" % id
	else:
		var npc = ctrl._find_npc_by_id(id) if id != "" else null
		if npc != null and is_instance_valid(npc):
			pos = npc.global_position
		key = "npc:%s" % (id if id != "" else "unknown")
	ctrl._spawn_combat_floater(pos, CombatFloater.text_for("miss"), Color(), "miss", key, false)
	if ctrl.hud != null:
		if ctrl.hud.has_method("append_combat_typed"):
			ctrl.hud.append_combat_typed("miss", CombatLogScript.line_miss())
		elif ctrl.hud.has_method("append_combat"):
			ctrl.hud.append_combat(CombatLogScript.line_miss())
		elif ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system(CombatLogScript.line_miss())

static func apply_emote(ctrl, action: Dictionary) -> void:
	## Floating text bubble above actor for duration_sec, then queue_free.
	var text = str(action.get("text", "")).strip_edges()
	if text.is_empty():
		return
	var actor_id = str(action.get("actor_id", "")).strip_edges()
	var duration = maxf(float(action.get("duration_sec", 2.0)), 0.1)
	var host = ctrl._resolve_emote_host(actor_id)
	if host == null or not is_instance_valid(host):
		return
	var old = host.get_node_or_null("EmoteBubble")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var lab = Label.new()
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
	lab.position = Vector2(-40, -72)
	host.add_child(lab)
	var tw = ctrl.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(func():
		if is_instance_valid(lab):
			lab.queue_free()
	)

static func apply_heal_action(ctrl, action: Dictionary) -> void:
	var target = str(action.get("target", "player"))
	if target != "player":
		return
	if ctrl.hud != null and ctrl.hud.has_method("apply_combat_stats"):
		ctrl.hud.apply_combat_stats({
			"hp": int(action.get("hp", -1)),
			"hp_max": int(action.get("hp_max", -1)),
			"mp": int(action.get("mp", -1)),
			"mp_max": int(action.get("mp_max", -1)),
		})
	var amount: int = int(action.get("amount", 0))
	var mp_gain: int = int(action.get("mp_gain", 0))
	if ctrl.hud != null:
		if amount > 0:
			var line_h = CombatLogScript.line_heal(amount)
			if ctrl.hud.has_method("append_combat_typed"):
				ctrl.hud.append_combat_typed("heal", line_h)
			elif ctrl.hud.has_method("append_combat"):
				ctrl.hud.append_combat(line_h)
			elif ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system(line_h)
		elif mp_gain > 0:
			var line_mp = CombatLogScript.line_mp(mp_gain)
			if ctrl.hud.has_method("append_combat_typed"):
				ctrl.hud.append_combat_typed("heal", line_mp)
			elif ctrl.hud.has_method("append_combat"):
				ctrl.hud.append_combat(line_mp)
			elif ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system(line_mp)
	if amount > 0:
		var ppos: Vector2 = ctrl.player.global_position if ctrl.player != null else Vector2.ZERO
		ctrl._spawn_combat_floater(ppos, CombatFloater.text_for("heal", amount), Color(), "heal", "player", false)

static func apply_set_stat(ctrl, action: Dictionary) -> void:
	if str(action.get("target", "player")) == "npc":
		var nid = str(action.get("id", "")).strip_edges()
		var actor = ctrl._find_npc_by_id(nid)
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
		if nid == ctrl._selected_npc_id and actor != null:
			var display_name = nid
			if "npc_name" in actor and str(actor.npc_name).strip_edges() != "":
				display_name = str(actor.npc_name)
			var hp_max: int = int(action.get("hp_max", actor.hp_max if "hp_max" in actor else 0))
			var hp: int = int(action.get("hp", actor.hp if "hp" in actor else 0))
			var ratio: float = 1.0 if hp_max <= 0 else float(hp) / float(hp_max)
			var thr = {}
			if action.has("threat_you"):
				thr = {
					"threat_you": bool(action.get("threat_you", false)),
					"threat_rank": int(action.get("threat_rank", 0)),
					"threat_pct": float(action.get("threat_pct", 0.0)),
					"victim_id": str(action.get("victim_id", "")),
				}
			ctrl._push_target_hud(actor, display_name, ratio, thr)
		return
	if str(action.get("target", "player")) != "player":
		return
	if ctrl.hud != null and ctrl.hud.has_method("apply_combat_stats"):
		var st = {
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
		ctrl.hud.apply_combat_stats(st)

static func apply_skill_cd(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("note_skill_cooldown"):
		ctrl.hud.note_skill_cooldown(
			str(action.get("skill_id", "")),
			float(action.get("remaining", 0.0)),
			float(action.get("cooldown", 0.0))
		)

static func apply_status_update(ctrl, action: Dictionary) -> void:
	var statuses_v: Variant = action.get("statuses", [])
	var statuses: Array = statuses_v if typeof(statuses_v) == TYPE_ARRAY else []
	var target = str(action.get("target", "player"))
	if target == "player":
		if ctrl.hud != null and ctrl.hud.has_method("apply_status_chips"):
			ctrl.hud.apply_status_chips(statuses)
		return
	var nid = str(action.get("id", "")).strip_edges()
	if nid != "" and nid == ctrl._selected_npc_id and ctrl.hud != null and ctrl.hud.has_method("apply_target_status_chips"):
		ctrl.hud.apply_target_status_chips(statuses)

static func apply_inventory_update(ctrl, action: Dictionary) -> void:
	var items_v: Variant = action.get("items", [])
	var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
	var gold_v: int = int(action.get("gold", -1))
	if ctrl.hud != null and ctrl.hud.has_method("apply_inventory_snapshot"):
		ctrl.hud.apply_inventory_snapshot(items, gold_v)

static func apply_equipment_update(ctrl, action: Dictionary) -> void:
	var eq_v: Variant = action.get("equipment", [])
	var eq: Array = eq_v if typeof(eq_v) == TYPE_ARRAY else []
	var bon_v: Variant = action.get("bonuses", {})
	var bons: Dictionary = bon_v if typeof(bon_v) == TYPE_DICTIONARY else {}
	if ctrl.hud != null and ctrl.hud.has_method("apply_equipment_snapshot"):
		ctrl.hud.apply_equipment_snapshot(eq, bons)
	ctrl._refresh_player_gear_look(eq)

static func apply_quest_update(ctrl, action: Dictionary) -> void:
	var quests_v: Variant = action.get("quests", [])
	var quests: Array = quests_v if typeof(quests_v) == TYPE_ARRAY else []
	if ctrl.hud != null and ctrl.hud.has_method("apply_quest_snapshot"):
		ctrl.hud.apply_quest_snapshot(quests)
	if ctrl.hud != null and ctrl.hud.has_method("apply_daily_board"):
		ctrl.hud.apply_daily_board(action)
	ctrl._radar_blips_ready = false

static func apply_kill_npc(ctrl, npc_id: String, npc = null) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id == ctrl._selected_npc_id:
		ctrl._clear_npc_selection()
	var target = npc
	if target == null or ("npc_id" in target and str(target.npc_id) != npc_id):
		target = ctrl._find_npc_by_id(npc_id)
	if target == null:
		return
	var kill_name = "敌人"
	if "npc_name" in target and str(target.npc_name).strip_edges() != "":
		kill_name = str(target.npc_name)
	if ctrl.hud != null:
		var line_k = CombatLogScript.line_kill(kill_name)
		if ctrl.hud.has_method("append_combat_typed"):
			ctrl.hud.append_combat_typed("kill", line_k)
		elif ctrl.hud.has_method("append_combat"):
			ctrl.hud.append_combat(line_k)
		elif ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system(line_k)
	var cell: Vector2i = target.cell if "cell" in target else Vector2i.ZERO
	var srv = Net.server()
	if srv != null and srv.map_collision != null and srv.map_collision.has_method("set_extra_blocked"):
		srv.map_collision.set_extra_blocked(cell.x, cell.y, false)
	ctrl._npcs.erase(target)
	var am_kill: Node = ctrl._asset_mgr
	if am_kill != null and am_kill.has_method("clear_actor_refs") and npc_id != "":
		am_kill.clear_actor_refs(npc_id)
		if am_kill.has_method("note_actor_ring"):
			am_kill.note_actor_ring(npc_id, "COLD")
	if is_instance_valid(target):
		target.queue_free()
	if ctrl.hud != null and ctrl.hud.has_method("clear_target"):
		ctrl.hud.clear_target()

static func apply_spawn_npc(ctrl, action: Dictionary) -> void:
	## Server timed respawn / pack-like recreate. `action.npc` mirrors npcs.json entry.
	var npc_v: Variant = action.get("npc", action)
	if typeof(npc_v) != TYPE_DICTIONARY:
		return
	var data: Dictionary = npc_v
	var nid = str(data.get("id", "")).strip_edges()
	if nid.is_empty():
		return
	var existing = ctrl._find_npc_by_id(nid)
	if existing != null:
		apply_kill_npc(ctrl, nid, existing)
	var layer = ctrl._ensure_npc_layer()
	var pack_dir = ""
	if ctrl.map_field != null and ctrl.map_field.pack != null:
		pack_dir = str(ctrl.map_field.pack.pack_dir)
	var actor = NpcActor.new()
	layer.add_child(actor)
	actor.setup(data, ctrl.map_field, pack_dir)
	ctrl._npcs.append(actor)
	ctrl._refresh_aoi(true)
	var cell_v: Variant = data.get("cell", {})
	if typeof(cell_v) == TYPE_DICTIONARY:
		var cd: Dictionary = cell_v
		var cx: int = int(cd.get("x", 0))
		var cy: int = int(cd.get("y", 0))
		var srv = Net.server()
		if srv != null and srv.map_collision != null and srv.map_collision.has_method("set_extra_blocked"):
			srv.map_collision.set_extra_blocked(cx, cy, true)
	ctrl._radar_blips_ready = false

static func apply_gather_update(ctrl, action: Dictionary) -> void:
	## Hide depleted gather props; restore on respawn. No new art.
	var nid = str(action.get("node_id", "")).strip_edges()
	if nid.is_empty():
		return
	var actor = ctrl._find_npc_by_id(nid)
	if actor == null:
		return
	var depleted = bool(action.get("depleted", false))
	actor.visible = not depleted
	if depleted:
		actor.set_meta("gather_depleted", true)
		if "npc_name" in actor:
			var base = str(action.get("name", actor.npc_name)).strip_edges()
			if base.is_empty():
				base = nid
			actor.npc_name = "%s（已采空）" % base
			if actor.has_method("_refresh_nameplate"):
				actor._refresh_nameplate()
	else:
		if actor.has_meta("gather_depleted"):
			actor.remove_meta("gather_depleted")
		var nm = str(action.get("name", "")).strip_edges()
		if nm != "" and "npc_name" in actor:
			actor.npc_name = nm
		if actor.has_method("_refresh_nameplate"):
			actor._refresh_nameplate()
	ctrl._radar_blips_ready = false

static func apply_fish_update(ctrl, action: Dictionary) -> void:
	## Hide depleted fishing spots; restore on respawn. No new art.
	var sid = str(action.get("spot_id", action.get("node_id", ""))).strip_edges()
	if sid.is_empty():
		return
	var actor = ctrl._find_npc_by_id(sid)
	if actor == null:
		return
	var depleted = bool(action.get("depleted", false))
	actor.visible = not depleted
	if depleted:
		actor.set_meta("fish_depleted", true)
		if "npc_name" in actor:
			var base = str(action.get("name", actor.npc_name)).strip_edges()
			if base.is_empty():
				base = sid
			actor.npc_name = "%s（暂无鱼）" % base
			if actor.has_method("_refresh_nameplate"):
				actor._refresh_nameplate()
	else:
		if actor.has_meta("fish_depleted"):
			actor.remove_meta("fish_depleted")
		var nm = str(action.get("name", "")).strip_edges()
		if nm != "" and "npc_name" in actor:
			actor.npc_name = nm
		if actor.has_method("_refresh_nameplate"):
			actor._refresh_nameplate()
	ctrl._radar_blips_ready = false

static func apply_threat_update(ctrl, action: Dictionary) -> void:
	var nid = str(action.get("npc_id", action.get("id", ""))).strip_edges()
	if nid.is_empty():
		return
	if nid != ctrl._selected_npc_id:
		return
	var npc = ctrl._find_npc_by_id(nid)
	if npc == null or not ctrl._npc_shows_target_hp(npc):
		return
	if ctrl.hud != null and ctrl.hud.has_method("apply_threat_chip"):
		ctrl.hud.apply_threat_chip(true, bool(action.get("threat_you", false)))

static func apply_weather_action(ctrl, action: Dictionary) -> void:
	ctrl._weather_kind = str(action.get("kind", "clear"))
	ctrl._weather_intensity = clampf(float(action.get("intensity", 0.0)), 0.0, 1.0)
	ctrl._apply_atmosphere()

static func apply_event_graphic(ctrl, action: Dictionary) -> void:
	var eid = str(action.get("event_id", "")).strip_edges()
	if eid == "":
		return
	var npc = ctrl._find_npc_by_id(eid)
	if npc == null or not npc.has_method("apply_graphic"):
		return
	var pack_dir = ""
	if ctrl.map_field != null and ctrl.map_field.pack != null:
		pack_dir = str(ctrl.map_field.pack.pack_dir)
	npc.apply_graphic(
		str(action.get("charset", "")),
		int(action.get("index", 0)),
		int(action.get("direction", 2)),
		pack_dir
	)

static func apply_player_move(ctrl, action: Dictionary) -> void:
	var cell = Vector2i(int(action.get("x", -9999)), int(action.get("y", -9999)))
	var cell_v: Variant = action.get("cell", {})
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", cell.x)), int(cell_v.get("y", cell.y)))
	elif typeof(cell_v) == TYPE_VECTOR2I:
		cell = cell_v
	if cell.x <= -9990 or ctrl.player == null:
		return
	if ctrl.player.has_method("clear_move_path"):
		ctrl.player.clear_move_path()
	var facing = int(action.get("facing", -1))
	if ctrl.player.has_method("place_at_cell"):
		ctrl.player.place_at_cell(cell, ctrl.map_field)
	else:
		ctrl.player.cell = cell
	if facing >= 0 and "facing" in ctrl.player:
		ctrl.player.facing = facing
	if ctrl.player.has_method("snap_camera"):
		ctrl.player.snap_camera()
	ctrl._sync_map_observer()

static func apply_recall(ctrl, action: Dictionary) -> void:
	var cell_v: Variant = action.get("cell", {})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	elif typeof(cell_v) == TYPE_VECTOR2I:
		cell = cell_v
	if ctrl.player == null:
		return
	ctrl._clear_pending_engage()
	ctrl.stop_follow()
	ctrl._auto_attack = false
	if ctrl.player.has_method("set_sitting"):
		ctrl.player.set_sitting(false)
	if ctrl.player.has_method("clear_move_path"):
		ctrl.player.clear_move_path()
	if ctrl.player.has_method("place_at_cell"):
		ctrl.player.place_at_cell(cell, ctrl.map_field)
	else:
		ctrl.player.cell = cell
	if ctrl.player.has_method("snap_camera"):
		ctrl.player.snap_camera()
	ctrl._sync_map_observer()

static func apply_sit(ctrl, action: Dictionary) -> void:
	var on = bool(action.get("on", false))
	if ctrl.player != null and ctrl.player.has_method("set_sitting"):
		ctrl.player.set_sitting(on)

static func apply_respawn(ctrl, action: Dictionary) -> void:
	ctrl._clear_pending_engage()
	var cell_v: Variant = action.get("cell", {})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	if ctrl.player != null:
		if ctrl.player.has_method("set_sitting"):
			ctrl.player.set_sitting(false)
		if ctrl.player.has_method("clear_move_path"):
			ctrl.player.clear_move_path()
		if ctrl.player.has_method("place_at_cell"):
			ctrl.player.place_at_cell(cell, ctrl.map_field)
		else:
			ctrl.player.cell = cell
		if ctrl.player.has_method("snap_camera"):
			ctrl.player.snap_camera()
		ctrl.player.input_locked = true
	if ctrl.hud != null and ctrl.hud.has_method("hide_death_dialog"):
		ctrl.hud.hide_death_dialog()
	ctrl._respawn_lock_left = float(action.get("input_lock_sec", 1.2))
	if ctrl.hud != null and ctrl.hud.has_method("apply_combat_stats"):
		ctrl.hud.apply_combat_stats({
			"hp": int(action.get("hp", -1)),
			"hp_max": int(action.get("hp_max", -1)),
			"mp": int(action.get("mp", -1)),
			"mp_max": int(action.get("mp_max", -1)),
		})
	if ctrl.hud != null and ctrl.hud.has_method("clear_target"):
		ctrl.hud.clear_target()

static func apply_exp_gain(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("apply_combat_stats"):
		var st = {
			"level": int(action.get("level", -1)),
			"exp": int(action.get("exp", -1)),
			"exp_to_next": int(action.get("exp_to_next", -1)),
		}
		if action.has("rested_exp"):
			st["rested_exp"] = int(action.get("rested_exp", 0))
		if action.has("rested_exp_max"):
			st["rested_exp_max"] = int(action.get("rested_exp_max", 0))
		ctrl.hud.apply_combat_stats(st)
	var amt: int = int(action.get("amount", 0))
	if amt > 0 and ctrl.hud != null and ctrl.hud.has_method("show_exp_gain_float"):
		ctrl.hud.show_exp_gain_float(amt)

static func apply_level_up(ctrl, action: Dictionary) -> void:
	var combat_v: Variant = action.get("combat", {})
	var combat: Dictionary = combat_v if typeof(combat_v) == TYPE_DICTIONARY else {}
	var lv: int = int(action.get("level", combat.get("level", 1)))
	var sp_gained: int = int(action.get("skill_points_gained", action.get("sp_gained", 0)))
	if ctrl.hud != null:
		if ctrl.hud.has_method("apply_level_up"):
			ctrl.hud.apply_level_up(lv, combat, sp_gained)
		elif ctrl.hud.has_method("show_level_up_toast"):
			ctrl.hud.show_level_up_toast(lv, sp_gained)
			if ctrl.hud.has_method("apply_combat_stats"):
				if combat.is_empty():
					ctrl.hud.apply_combat_stats({"level": lv})
				else:
					ctrl.hud.apply_combat_stats(combat)
		elif ctrl.hud.has_method("apply_combat_stats"):
			if combat.is_empty():
				ctrl.hud.apply_combat_stats({"level": lv})
			else:
				ctrl.hud.apply_combat_stats(combat)

static func apply_open_shop(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("show_shop"):
		var listings_v: Variant = action.get("listings", [])
		var listings: Array = listings_v if typeof(listings_v) == TYPE_ARRAY else []
		ctrl.hud.show_shop(
			str(action.get("shop_id", "")),
			str(action.get("title", "商店")),
			listings,
			int(action.get("gold", 0)),
			int(action.get("vendor_rep", 0))
		)
		if ctrl.hud.has_method("apply_shop_buyback"):
			var bb: Variant = action.get("buyback", [])
			if typeof(bb) == TYPE_ARRAY:
				ctrl.hud.apply_shop_buyback(bb)

static func apply_ground_spawn(ctrl, action: Dictionary) -> void:
	var bag_v: Variant = action.get("bag", {})
	if typeof(bag_v) == TYPE_DICTIONARY:
		ctrl._upsert_ground_marker(bag_v)

static func apply_ground_update(ctrl, action: Dictionary) -> void:
	var bag_v: Variant = action.get("bag", {})
	if typeof(bag_v) == TYPE_DICTIONARY:
		ctrl._upsert_ground_marker(bag_v)

static func apply_ground_despawn(ctrl, action: Dictionary) -> void:
	var bag_id = str(action.get("bag_id", "")).strip_edges()
	if bag_id.is_empty():
		return
	if ctrl._ground_markers.has(bag_id):
		var n = ctrl._ground_markers[bag_id]
		ctrl._ground_markers.erase(bag_id)
		if n != null and is_instance_valid(n):
			n.queue_free()

static func apply_loot_open(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("show_loot"):
		var items_v: Variant = action.get("items", [])
		var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
		ctrl.hud.show_loot(
			str(action.get("session_id", action.get("bag_id", ""))),
			str(action.get("npc_id", "")),
			items
		)

static func apply_loot_update(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("refresh_loot"):
		var items_v: Variant = action.get("items", [])
		var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
		ctrl.hud.refresh_loot(str(action.get("session_id", action.get("bag_id", ""))), items)

static func apply_loot_close(ctrl, _action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("hide_loot"):
		ctrl.hud.hide_loot()

static func apply_attr_update(ctrl, action: Dictionary) -> void:
	if ctrl.hud == null:
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
	if ctrl.hud.has_method("apply_attr_update"):
		ctrl.hud.apply_attr_update(action)
	elif ctrl.hud.has_method("apply_combat_stats") and not st.is_empty():
		ctrl.hud.apply_combat_stats(st)

static func apply_skill_book_update(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("apply_skill_book"):
		ctrl.hud.apply_skill_book(action)

static func apply_skill_respec(ctrl, action: Dictionary) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("apply_skill_respec"):
		ctrl.hud.apply_skill_respec(action)

static func apply_skill_fx(ctrl, action: Dictionary) -> void:
	ctrl._ensure_skill_fx()
	var cell_v: Variant = action.get("cell", {})
	var cell = Vector2i(0, 0)
	if typeof(cell_v) == TYPE_DICTIONARY:
		cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var world_pos = Vector2.ZERO
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		world_pos = ctrl.map_field.cell_to_world(cell)
		var ts = 48.0
		if "tile_size" in ctrl.map_field:
			ts = float(ctrl.map_field.tile_size)
		world_pos.y -= ts * 0.5
	else:
		world_pos = Vector2(float(cell.x) * 48.0 + 24.0, float(cell.y) * 48.0 + 24.0)
	var radius: int = int(action.get("radius", 0))
	var ts2 = 48.0
	if ctrl.map_field != null and "tile_size" in ctrl.map_field:
		ts2 = float(ctrl.map_field.tile_size)
	var rpx: float = maxf(ts2 * float(maxi(radius, 1)), ts2)
	var effect = str(action.get("effect", ""))
	var sid = str(action.get("skill_id", ""))
	var anim = str(action.get("anim", "")).strip_edges()
	if anim == "strike" or anim == "dash" or anim == "spin" or anim == "cast":
		if effect == "aoe_damage" or radius > 0:
			ctrl._skill_fx.play_impact("flame", world_pos, rpx)
			ctrl._skill_fx.play_ring(world_pos, rpx)
		elif effect == "damage" or effect == "damage_and_status":
			ctrl._skill_fx.play_impact("bolt" if anim == "dash" else "flame", world_pos, 28.0)
		return
	if effect == "damage" or effect == "damage_and_status" or sid == "arcane_bolt" or sid == "poison_dart" or sid == "channel_beam":
		var from_pos = world_pos
		if ctrl.player != null:
			from_pos = ctrl.player.global_position
		var actor = str(action.get("actor", "player"))
		if actor != "player":
			var n = ctrl._find_npc_by_id(actor)
			if n != null:
				from_pos = n.global_position
		ctrl._skill_fx.play_bolt(from_pos, world_pos, "bolt")
	else:
		ctrl._skill_fx.play_impact("flame", world_pos, rpx)
		if radius > 0:
			ctrl._skill_fx.play_ring(world_pos, rpx)

static func apply_skill_anim(ctrl, action: Dictionary) -> void:
	ctrl._ensure_skill_fx()
	var kind = str(action.get("kind", "cast")).strip_edges()
	var actor = str(action.get("actor", "player"))
	var node: Node2D = null
	var facing = "front"
	if actor == "player" or actor.is_empty():
		node = ctrl.player
		if ctrl.player != null and ctrl.player.has_method("get_facing"):
			facing = str(ctrl.player.get_facing())
		elif ctrl.player != null and "_facing" in ctrl.player:
			facing = str(ctrl.player._facing)
	else:
		node = ctrl._find_npc_by_id(actor)
	if node == null:
		return
	if ctrl._skill_fx.has_method("play_action"):
		ctrl._skill_fx.play_action(kind, node, facing)
	else:
		ctrl._skill_fx.flash_actor(node)

static func apply_remote_move(ctrl, action: Dictionary) -> void:
	var pid = str(action.get("player_id", "")).strip_edges()
	if pid.is_empty() or not ctrl._remote_markers.has(pid):
		return
	var marker = ctrl._remote_markers[pid]
	if marker == null or not is_instance_valid(marker):
		return
	var cell = Vector2i(int(action.get("x", 0)), int(action.get("y", 0)))
	marker.set_meta("cell", cell)
	var facing: int = int(action.get("facing", 2))
	marker.set_meta("facing", facing)
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		var wp: Vector2 = ctrl.map_field.cell_to_world(cell)
		marker.global_position = Vector2(wp.x, wp.y - float(ctrl.map_field.tile_size) * 0.2)
	else:
		marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var anim = marker.get_node_or_null("Anim") as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null:
		var walk = "walk_front"
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
	ctrl._radar_blips_ready = false

static func apply_pet_move(ctrl, action: Dictionary) -> void:
	if ctrl._pet_marker == null or not is_instance_valid(ctrl._pet_marker):
		return
	var cell = Vector2i(int(action.get("x", 0)), int(action.get("y", 0)))
	ctrl._pet_marker.set_meta("cell", cell)
	var facing: int = int(action.get("facing", 2))
	ctrl._pet_marker.set_meta("facing", facing)
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		var wp: Vector2 = ctrl.map_field.cell_to_world(cell)
		ctrl._pet_marker.global_position = Vector2(wp.x, wp.y - float(ctrl.map_field.tile_size) * 0.2)
	else:
		ctrl._pet_marker.position = Vector2(cell.x * 48 + 24, cell.y * 48 + 24)
	var anim = ctrl._pet_marker.get_node_or_null("Anim") as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null:
		var walk = "walk_front"
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

static func tick_event_wait(ctrl, delta: float) -> void:
	if ctrl._event_wait_left <= 0.0:
		return
	ctrl._event_wait_left -= delta
	if ctrl._event_wait_left > 0.0:
		return
	var rest: Array = ctrl._deferred_event_actions
	var n = ctrl._deferred_event_npc
	ctrl._deferred_event_actions = []
	ctrl._deferred_event_npc = null
	ctrl._event_wait_left = 0.0
	if not rest.is_empty():
		ctrl._apply_server_actions(rest, n)

