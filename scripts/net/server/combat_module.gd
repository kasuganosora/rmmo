extends RefCounted
## Domain module: combat (layers/tick, skills, threat/hate, auto-potion, revive).

var ctrl
func _init(c):
	ctrl = c

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
const AUTO_POTION_INTERVAL := 0.5
const SKILL_RESPEC_GOLD_COST := 50

func _init_combat_layers() -> void:
	ctrl.combat_stats = CombatStats.new()
	ctrl.skill_catalog = SkillCatalog.new()
	ctrl.skill_catalog.load_catalog()
	ctrl.item_catalog = ItemCatalog.new()
	ctrl.item_catalog.load_catalog()
	ctrl.recipe_catalog = RecipeCatalog.new()
	ctrl.recipe_catalog.load_catalog()
	ctrl.gather_catalog = GatherCatalog.new()
	ctrl.gather_catalog.load_catalog()
	ctrl._gather_state.clear()
	ctrl._gather_nodes.clear()
	ctrl.fish_catalog = FishCatalog.new()
	ctrl.fish_catalog.load_catalog()
	ctrl._fish_state.clear()
	ctrl._fish_spots.clear()
	ctrl._fish_busy_until = 0.0
	ctrl.title_catalog = TitleCatalog.new()
	ctrl.title_catalog.load_catalog()
	ctrl.achievement_catalog = AchievementCatalog.new()
	ctrl.achievement_catalog.load_catalog()
	ctrl.safe_zone_catalog = SafeZoneCatalog.new()
	ctrl.safe_zone_catalog.load_catalog()
	ctrl._safe_zone_known = false
	ctrl._safe_zone_inside = false
	ctrl.loot_catalog = LootCatalog.new()
	ctrl.loot_catalog.load_catalog()
	ctrl.inventory = Inventory.new()
	ctrl.inventory.set_catalog(ctrl.item_catalog)
	ctrl.inventory.grant_starter()
	ctrl.warehouse = Warehouse.new()
	ctrl.warehouse.set_catalog(ctrl.item_catalog)
	ctrl.warehouse.clear()
	ctrl.friend_list = FriendList.new()
	ctrl.friend_list.clear()
	ctrl.guild = Guild.new()
	ctrl.guild.clear()
	ctrl._guild_invites.clear()
	ctrl.mailbox = Mailbox.new()
	ctrl.mailbox.clear()
	ctrl.auction = Auction.new()
	ctrl.auction.clear()
	ctrl._auction_seed_npc_stubs()
	ctrl._mail_welcome_sent = false
	ctrl._attendance_last_ymd = ""
	ctrl.equipment = Equipment.new()
	ctrl.equipment.set_catalog(ctrl.item_catalog)
	ctrl.equipment.clear()
	ctrl.quest_journal = QuestJournal.new()
	ctrl.quest_journal.load_catalog()
	ctrl.quest_journal.grant_starter()
	ctrl.shop_catalog = ShopCatalog.new()
	ctrl.shop_catalog.set_catalog(ctrl.item_catalog)
	ctrl.shop_catalog.load_catalog()
	ctrl.event_runtime = EventRuntime.new()
	ctrl.combat_engine = CombatEngine.new()
	ctrl.combat_engine.setup(ctrl.combat_stats, ctrl.skill_catalog, ctrl.item_catalog, ctrl.inventory, ctrl.equipment)
	ctrl.combat_engine.combat_randf = ctrl._combat_randf_override
	ctrl.combat_stats.reset_player(1)
	ctrl.combat_stats.reset_titles()
	ctrl.combat_stats.reset_achievements()
	_reset_skill_book()



func poll_combat_tick() -> Array:
	var invite_acts: Array = ctrl._tick_party_invites()
	if not invite_acts.is_empty():
		ctrl._pending_tick_actions.append_array(invite_acts)
	var loot_roll_acts: Array = ctrl._tick_loot_rolls()
	if not loot_roll_acts.is_empty():
		ctrl._pending_tick_actions.append_array(loot_roll_acts)
	var duel_acts: Array = ctrl._tick_duel()
	if not duel_acts.is_empty():
		ctrl._pending_tick_actions.append_array(duel_acts)
	# Keep party self HP fresh while grouped (shell: no net peers).
	if ctrl.in_party():
		if ctrl._party_refresh_self_member() or ctrl._party_poll_pending:
			ctrl._pending_tick_actions.append(ctrl._party_update_action())
			ctrl._party_poll_pending = false
	elif ctrl._party_poll_pending:
		ctrl._pending_tick_actions.append(ctrl._party_update_action())
		ctrl._party_poll_pending = false
	if ctrl._pending_tick_actions.is_empty():
		return []
	var out: Array = ctrl._pending_tick_actions.duplicate(true)
	ctrl._pending_tick_actions.clear()
	return out



func snapshot_threat(npc_id: String) -> Dictionary:
	npc_id = str(npc_id).strip_edges()
	if ctrl.combat_stats == null or not ctrl.combat_stats.has_method("snapshot_threat"):
		return {
			"npc_id": npc_id,
			"threat_you": false,
			"threat_rank": 0,
			"threat_pct": 0.0,
			"victim_id": "",
		}
	return ctrl.combat_stats.snapshot_threat(npc_id)



func try_attack(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	if ctrl.player_cell.x > -9990:
		player_x = ctrl.player_cell.x
		player_y = ctrl.player_cell.y
	if ctrl.player_in_safe_zone() and ctrl._target_is_remote_player(npc_id):
		return ctrl._safe_zone_block_pvp_result()
	var duel_hit: Dictionary = ctrl._try_duel_attack_target(npc_id, player_x, player_y)
	if not duel_hit.is_empty():
		return duel_hit
	if ctrl.combat_engine == null:
		return {"ok": false, "actions": []}
	var result: Dictionary = ctrl.combat_engine.try_attack(npc_id, player_x, player_y)
	if bool(result.get("ok", false)):
		ctrl._player_combat_target_id = str(npc_id).strip_edges()
	_combat_stand_if_needed(result)
	return _finalize_combat_result(result)




func try_use_skill(	skill_id: String,
	target_npc_id: String = "",
	player_x: int = -9999,
	player_y: int = -9999,
	ground_x: int = -9999,
	ground_y: int = -9999
) -> Dictionary:
	if ctrl.player_cell.x > -9990:
		player_x = ctrl.player_cell.x
		player_y = ctrl.player_cell.y
	elif player_x <= -9990:
		player_x = ctrl.player_cell.x
		player_y = ctrl.player_cell.y
	if ctrl.player_in_safe_zone() and ctrl._target_is_remote_player(target_npc_id):
		return ctrl._safe_zone_block_pvp_result()
	var revive_skill: Dictionary = _try_revive_skill(skill_id, target_npc_id, player_x, player_y)
	if not revive_skill.is_empty():
		# Skip _finalize_combat_result: it forces ok=true when caster is already dead.
		_combat_stand_if_needed(revive_skill)
		return revive_skill
	# Mount while dead: skip finalize (it would force ok=true on dead caster).
	if skill_id.strip_edges() == "mount":
		if ctrl.awaiting_respawn or ctrl.combat_stats == null or not ctrl.combat_stats.player_alive():
			return {"ok": false, "actions": [{"type": "system_message", "text": "你已经倒下了。"}]}
	var duel_skill: Dictionary = ctrl._try_duel_skill_target(skill_id, target_npc_id, player_x, player_y)
	if not duel_skill.is_empty():
		return duel_skill
	if ctrl.combat_engine == null:
		return {"ok": false, "actions": []}
	ctrl.combat_engine.map_collision = ctrl.map_collision
	var result: Dictionary = ctrl.combat_engine.try_use_skill(
		skill_id, target_npc_id, player_x, player_y, ground_x, ground_y
	)
	ctrl._apply_player_move_actions(result)
	ctrl._bind_recall_actions(result)
	_combat_stand_if_needed(result)
	ctrl._maybe_party_skill_share(skill_id, result)
	return _finalize_combat_result(result)



func skill_def(skill_id: String) -> Dictionary:
	if ctrl.skill_catalog == null:
		return {}
	return ctrl.skill_catalog.get_skill(skill_id)



func _patch_npc_cast_skill_names(actions: Array) -> void:
	## Replace 【npc_id】 with display name in NPC cast resolve system messages.
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "system_message":
			continue
		var caster = str(a.get("caster", a.get("npc_id", ""))).strip_edges()
		if caster.is_empty():
			# Infer from message prefix if needed — also scan known npc ids in text.
			pass
		var txt = str(a.get("text", ""))
		var nid = str(a.get("npc_id", "")).strip_edges()
		if nid.is_empty():
			nid = caster
		if nid.is_empty():
			continue
		var nm = nid
		if ctrl.npc_meta.has(nid):
			var nms = str((ctrl.npc_meta[nid] as Dictionary).get("name", "")).strip_edges()
			if nms != "":
				nm = nms
		elif ctrl.combat_stats != null and ctrl.combat_stats.npcs.has(nid):
			var nms2 = str(ctrl.combat_stats.npcs[nid].get("name", "")).strip_edges()
			if nms2 != "":
				nm = nms2
		if nm != nid:
			a["text"] = txt.replace("【%s】" % nid, "【%s】" % nm)



func try_npc_skill(npc_id: String, skill_id: String, ground_x: int = -9999, ground_y: int = -9999) -> Dictionary:
	if ctrl.combat_engine == null or ctrl.combat_stats == null:
		return {"ok": false, "actions": []}
	npc_id = npc_id.strip_edges()
	var cell: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return {"ok": false, "actions": []}
	if ground_x <= -9990:
		ground_x = ctrl.player_cell.x
		ground_y = ctrl.player_cell.y
	ctrl.combat_engine.player_cell_hint = ctrl.player_cell
	var result: Dictionary = ctrl.combat_engine.try_npc_skill(
		npc_id, skill_id, cell.x, cell.y, ground_x, ground_y
	)
	var nm = npc_id
	if ctrl.npc_meta.has(npc_id):
		var nms = str((ctrl.npc_meta[npc_id] as Dictionary).get("name", "")).strip_edges()
		if nms != "":
			nm = nms
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) == TYPE_ARRAY:
		for a in acts_v:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			if str(a.get("type", "")) != "system_message":
				continue
			var txt = str(a.get("text", ""))
			a["text"] = txt.replace("【%s】" % npc_id, "【%s】" % nm)
	return _finalize_combat_result(result)



func try_set_auto_potion(hp_on: bool, hp_pct: int, mp_on: bool, mp_pct: int) -> void:
	ctrl.auto_potion_hp = bool(hp_on)
	ctrl.auto_potion_hp_pct = clampi(int(hp_pct), 1, 90)
	ctrl.auto_potion_mp = bool(mp_on)
	ctrl.auto_potion_mp_pct = clampi(int(mp_pct), 1, 90)



func try_set_combat_target(npc_id: String = "") -> void:
	ctrl._player_combat_target_id = str(npc_id).strip_edges()



func _tick_auto_potion(delta: float) -> void:
	ctrl._auto_potion_acc += delta
	if ctrl._auto_potion_acc < AUTO_POTION_INTERVAL:
		return
	ctrl._auto_potion_acc = 0.0
	if ctrl.combat_stats == null or ctrl.inventory == null:
		return
	if ctrl.awaiting_respawn or not ctrl.combat_stats.player_alive():
		return
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("is_casting") and ctrl.combat_engine.is_casting():
		return
	var used = false
	if ctrl.auto_potion_hp:
		var hp: int = int(ctrl.combat_stats.player.get("hp", 0))
		var hp_max: int = maxi(1, int(ctrl.combat_stats.player.get("hp_max", 1)))
		var hp_pct: int = int(floor(100.0 * float(hp) / float(hp_max)))
		if hp_pct <= ctrl.auto_potion_hp_pct:
			var iid = _best_auto_potion("heal_hp")
			if iid.is_empty():
				_maybe_auto_potion_msg("背包中没有生命药水。")
			elif ctrl.combat_stats.is_item_ready(iid):
				var r: Dictionary = ctrl.try_use_item(iid)
				if bool(r.get("ok", false)):
					var acts_v: Variant = r.get("actions", [])
					if typeof(acts_v) == TYPE_ARRAY and not (acts_v as Array).is_empty():
						ctrl._pending_tick_actions.append_array(acts_v)
					used = true
	if used:
		return
	if ctrl.auto_potion_mp:
		var mp: int = int(ctrl.combat_stats.player.get("mp", 0))
		var mp_max: int = maxi(1, int(ctrl.combat_stats.player.get("mp_max", 1)))
		var mp_pct: int = int(floor(100.0 * float(mp) / float(mp_max)))
		if mp_pct <= ctrl.auto_potion_mp_pct:
			var mid = _best_auto_potion("heal_mp")
			if mid.is_empty():
				_maybe_auto_potion_msg("背包中没有魔法药水。")
			elif ctrl.combat_stats.is_item_ready(mid):
				var r2: Dictionary = ctrl.try_use_item(mid)
				if bool(r2.get("ok", false)):
					var acts2: Variant = r2.get("actions", [])
					if typeof(acts2) == TYPE_ARRAY and not (acts2 as Array).is_empty():
						ctrl._pending_tick_actions.append_array(acts2)



func _best_auto_potion(effect: String) -> String:
	effect = effect.strip_edges()
	if ctrl.inventory == null or ctrl.item_catalog == null or effect.is_empty():
		return ""
	var best_id = ""
	var best_amt = -1
	for row in ctrl.inventory.snapshot():
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid = str(row.get("id", "")).strip_edges()
		if not iid.begins_with("potion_"):
			continue
		if int(row.get("qty", 0)) <= 0:
			continue
		var def: Dictionary = ctrl.item_catalog.get_item(iid)
		if def.is_empty():
			continue
		var ue = str(def.get("use_effect", def.get("effect", ""))).strip_edges()
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
	if now_ms - ctrl._auto_potion_msg_at_ms < 10000:
		return
	ctrl._auto_potion_msg_at_ms = now_ms
	ctrl._pending_tick_actions.append({"type": "system_message", "text": text})



func _combat_stand_if_needed(result: Dictionary) -> void:
	if not ctrl.sitting:
		return
	var acts_v: Variant = result.get("actions", [])
	var acts: Array = acts_v if typeof(acts_v) == TYPE_ARRAY else []
	ctrl._stand_if_sitting(acts)
	result["actions"] = acts



func snapshot_skill_book() -> Dictionary:
	if ctrl.combat_stats == null:
		return {"known": ["basic_attack"], "skill_points": 0}
	if ctrl.combat_stats.has_method("snapshot_skill_book"):
		return ctrl.combat_stats.snapshot_skill_book()
	if ctrl.combat_stats.skill_book != null and ctrl.combat_stats.skill_book.has_method("snapshot"):
		return ctrl.combat_stats.skill_book.snapshot()
	return {"known": ["basic_attack"], "skill_points": 0}



func _reset_skill_book() -> void:
	if ctrl.combat_stats == null:
		return
	ctrl.combat_stats.ensure_skill_book()
	ctrl.combat_stats.skill_book.grant_starters(ctrl.skill_catalog)



func try_learn_skill(skill_id: String) -> Dictionary:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty() or ctrl.combat_stats == null or ctrl.skill_catalog == null:
		return {"ok": false, "actions": [{"type": "system_message", "text": "无法学习技能。"}]}
	ctrl.combat_stats.ensure_skill_book()
	var lv: int = maxi(int(ctrl.combat_stats.player.get("level", 1)), 1)
	var result: Dictionary = ctrl.combat_stats.skill_book.try_learn(skill_id, ctrl.skill_catalog, lv)
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



func try_skill_respec() -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats == null or ctrl.skill_catalog == null:
		actions.append({"type": "system_message", "text": "无法重置技能。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if not ctrl.combat_stats.player_alive() or ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.in_duel():
		actions.append({"type": "system_message", "text": "决斗中无法重置技能。"})
		return {"ok": false, "reason": "duel", "actions": actions}
	ctrl.combat_stats.ensure_skill_book()
	var book = ctrl.combat_stats.skill_book
	# Peek: anything besides basic_attack?
	var has_extra = false
	for sid_v in book.list_known():
		if str(sid_v).strip_edges() != "basic_attack":
			has_extra = true
			break
	if not has_extra:
		actions.append({"type": "system_message", "text": "没有可重置的技能。"})
		return {"ok": false, "reason": "nothing", "actions": actions}
	var cost: int = SKILL_RESPEC_GOLD_COST
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "无法重置技能。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	if ctrl.inventory.get_gold() < cost:
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not ctrl.inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var result: Dictionary = book.try_respec(ctrl.skill_catalog)
	if not bool(result.get("ok", false)):
		ctrl.inventory.add_gold(cost)
		actions.append({"type": "system_message", "text": str(result.get("message", "无法重置技能。"))})
		return {"ok": false, "reason": str(result.get("reason", "fail")), "actions": actions}
	var refunded: int = int(result.get("refunded_sp", 0))
	var cleared: Array = []
	var cleared_v: Variant = result.get("cleared", [])
	if typeof(cleared_v) == TYPE_ARRAY:
		for c in cleared_v:
			var cid = str(c).strip_edges()
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
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
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



func snapshot_skill_catalog() -> Array:
	if ctrl.skill_catalog == null:
		return []
	return ctrl.skill_catalog.list_all()



func _try_npc_skill_tick(npc_id: String, ai: Dictionary, cell: Vector2i, px: int, py: int) -> Array:
	var skills_v: Variant = ai.get("skills", [])
	if typeof(skills_v) != TYPE_ARRAY or (skills_v as Array).is_empty():
		return []
	if ctrl.combat_engine == null or ctrl.skill_catalog == null or ctrl.combat_stats == null:
		return []
	if ctrl.combat_engine.has_method("is_npc_casting") and ctrl.combat_engine.is_npc_casting(npc_id):
		return []
	var ready_v: Variant = ai.get("skill_ready_at", {})
	var ready: Dictionary = ready_v if typeof(ready_v) == TYPE_DICTIONARY else {}
	var now: float = ctrl.combat_stats.now_sec()
	for sid_v in skills_v:
		var sid = str(sid_v).strip_edges()
		if sid.is_empty():
			continue
		if now < float(ready.get(sid, 0.0)):
			continue
		var def: Dictionary = ctrl.skill_catalog.get_skill(sid)
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
		ctrl.combat_stats.npc_ai[npc_id] = ai
		var acts_v: Variant = r.get("actions", [])
		return acts_v if typeof(acts_v) == TYPE_ARRAY else []
	ctrl.combat_stats.npc_ai[npc_id] = ai
	return []



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



func _append_threat_updates(actions: Array) -> void:
	var seen: Dictionary = {}
	# Skip if already present for an id.
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "threat_update":
			continue
		var eid = str(a.get("npc_id", a.get("id", ""))).strip_edges()
		if eid != "":
			seen[eid] = true
	var ids: Array = []
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t = str(a.get("type", ""))
		var nid = ""
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
		var kid = str(a.get("npc_id", ""))
		ctrl._schedule_npc_respawn(kid)
		var death_cell: Variant = a.get("cell", null)
		kill_extra.append_array(ctrl._roll_and_grant_loot(kid, death_cell))
		kill_extra.append_array(ctrl.grant_kill_exp(kid))
		if ctrl._is_world_boss_npc(kid):
			ctrl._rewrite_kill_announce(actions, kid)
			kill_extra.append_array(ctrl._world_boss_kill_bonus(kid))
		kill_extra.append_array(ctrl._quest_note_kill_actions(kid))
		kill_extra.append_array(ctrl._note_title_counter("kills", 1))
		kill_extra.append_array(ctrl._note_achievement_counter("kills", 1))
		kill_extra.append_array(ctrl._dungeon_note_kill(kid))
	if not kill_extra.is_empty():
		actions.append_array(kill_extra)
		result["actions"] = actions
	if ctrl.sitting:
		for a in actions:
			if typeof(a) != TYPE_DICTIONARY:
				continue
			var t = str(a.get("type", ""))
			if t == "damage" and str(a.get("target", a.get("id", ""))) == "player":
				ctrl._stand_if_sitting(actions)
				break
			if t == "player_died":
				ctrl.sitting = false
				ctrl._sit_acc = 0.0
				ctrl._sit_regen_acc = 0.0
				break
	var newly_dead: bool = ctrl._actions_has_type(actions, "player_died") or (ctrl.combat_stats != null and not ctrl.combat_stats.player_alive())
	if newly_dead:
		var first_death: bool = not ctrl.awaiting_respawn
		ctrl.awaiting_respawn = true
		ctrl.sitting = false
		ctrl._sit_acc = 0.0
		ctrl._sit_regen_acc = 0.0
		ctrl.death_cell = ctrl.player_cell
		if not ctrl._actions_has_type(actions, "system_message"):
			actions.append({"type": "system_message", "text": "你死了。"})
		# Close open loot UI only — does not remove inventory; death drops are separate.
		ctrl._clear_pending_loot_on_death(actions)
		if first_death:
			ctrl._apply_death_drops(actions)
			actions.append_array(ctrl._note_title_counter("deaths", 1))
			# Death equipment durability wear (combat hit wear is separate — see wear_weapon).
			if ctrl.equipment != null and ctrl.equipment.has_method("apply_death_wear"):
				var wear: Dictionary = ctrl.equipment.apply_death_wear(0.1)
				if int(wear.get("count", 0)) > 0:
					actions.append({"type": "system_message", "text": "装备因死亡受损。"})
					actions.append(ctrl._equipment_update_action())
		result["actions"] = actions
		result["ok"] = true
	return result



func _apply_npc_spawn_combat_overrides(npc_id: String, spawn_data: Dictionary) -> void:
	if ctrl.combat_stats == null or spawn_data.is_empty() or not ctrl.combat_stats.npcs.has(npc_id):
		return
	var st: Dictionary = ctrl.combat_stats.npcs[npc_id]
	var stats_v: Variant = spawn_data.get("stats", {})
	var nested: Dictionary = stats_v if typeof(stats_v) == TYPE_DICTIONARY else {}
	if spawn_data.has("level") or nested.has("level"):
		st["level"] = maxi(int(spawn_data.get("level", nested.get("level", st.get("level", 1)))), 1)
	if spawn_data.has("hp_max") or nested.has("hp_max"):
		var hp_max: int = maxi(int(spawn_data.get("hp_max", nested.get("hp_max", st.get("hp_max", 30)))), 1)
		st["hp_max"] = hp_max
		st["hp"] = hp_max
		var mp_max: int = ctrl.combat_stats.npc_mp_max_for(int(st.get("level", 1)), hp_max)
		st["mp_max"] = mp_max
		st["mp"] = mp_max
	if spawn_data.has("atk") or nested.has("atk"):
		st["atk"] = maxi(int(spawn_data.get("atk", nested.get("atk", st.get("atk", 1)))), 0)
	if spawn_data.has("def") or nested.has("def"):
		st["def"] = maxi(int(spawn_data.get("def", nested.get("def", st.get("def", 0)))), 0)
	ctrl.combat_stats.npcs[npc_id] = st



func _try_revive_skill(skill_id: String, target_id: String, player_x: int, player_y: int) -> Dictionary:
	skill_id = str(skill_id).strip_edges()
	target_id = str(target_id).strip_edges()
	if skill_id.is_empty():
		return {}
	var def: Dictionary = skill_def(skill_id) if ctrl.has_method("skill_def") else {}
	if def.is_empty() or str(def.get("effect", "")).strip_edges() != "revive":
		return {}
	var actions: Array = []
	# Caster must be alive (cannot self-revive while dead).
	if ctrl.awaiting_respawn or (ctrl.combat_stats != null and not ctrl.combat_stats.player_alive()):
		actions.append({"type": "system_message", "text": "无法自我复活。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.combat_stats == null:
		actions.append({"type": "system_message", "text": "无法施放。"})
		return {"ok": false, "reason": "no_combat", "actions": actions}
	# Must know the skill.
	if ctrl.combat_stats.skill_book != null and ctrl.combat_stats.skill_book.has_method("is_known"):
		if not ctrl.combat_stats.skill_book.is_known(skill_id):
			var sname = str(def.get("name", skill_id))
			actions.append({"type": "system_message", "text": "尚未学会【%s】。" % sname})
			return {"ok": false, "reason": "unlearned", "actions": actions}
	if ctrl.combat_stats.has_method("is_skill_ready") and not ctrl.combat_stats.is_skill_ready(skill_id):
		var rem: float = ctrl.combat_stats.skill_cd_remaining(skill_id) if ctrl.combat_stats.has_method("skill_cd_remaining") else 0.0
		actions.append({"type": "system_message", "text": "技能冷却中（%.1f 秒）。" % rem})
		actions.append({
			"type": "skill_cd",
			"skill_id": skill_id,
			"remaining": rem,
			"cooldown": float(def.get("cooldown", 30.0)),
		})
		return {"ok": false, "reason": "cooldown", "actions": actions}
	var mp_cost: int = int(def.get("mp_cost", 25))
	if int(ctrl.combat_stats.player.get("mp", 0)) < mp_cost:
		actions.append({"type": "system_message", "text": "MP 不足。"})
		return {"ok": false, "reason": "mp", "actions": actions}
	if target_id.is_empty():
		actions.append({"type": "system_message", "text": "需要目标。"})
		return {"ok": false, "reason": "need_target", "actions": actions}
	var self_id = ctrl._party_self_id()
	if target_id == self_id or target_id == "player":
		actions.append({"type": "system_message", "text": "无法自我复活。"})
		return {"ok": false, "reason": "self", "actions": actions}
	var range_cells: int = maxi(1, int(def.get("range", 4)))
	var resolved: Dictionary = _revive_resolve_target(target_id)
	if resolved.is_empty():
		actions.append({"type": "system_message", "text": "只能复活队友。"})
		return {"ok": false, "reason": "not_ally", "actions": actions}
	var kind = str(resolved.get("kind", ""))
	var mid = str(resolved.get("id", target_id))
	var mname = str(resolved.get("name", mid)).strip_edges()
	if mname.is_empty():
		mname = mid
	# Same-map check for party/remote (empty map_id = same-map shell).
	var mmap = str(resolved.get("map_id", "")).strip_edges()
	if mmap != "" and mmap != ctrl.map_pack_id:
		actions.append({"type": "system_message", "text": "只能复活队友。"})
		return {"ok": false, "reason": "not_same_map", "actions": actions}
	var tx: int = int(resolved.get("x", -9999))
	var ty: int = int(resolved.get("y", -9999))
	if tx <= -9990 or ty <= -9990:
		actions.append({"type": "system_message", "text": "目标太远。"})
		return {"ok": false, "reason": "no_cell", "actions": actions}
	if ctrl._chebyshev(player_x, player_y, tx, ty) > range_cells:
		actions.append({"type": "system_message", "text": "目标太远。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var hp_now: int = int(resolved.get("hp", 0))
	var awaiting: bool = bool(resolved.get("awaiting_respawn", false))
	if hp_now > 0 and not awaiting:
		actions.append({"type": "system_message", "text": "目标未死亡。"})
		return {"ok": false, "reason": "alive", "actions": actions}
	# Spend MP + CD.
	var p: Dictionary = ctrl.combat_stats.player
	p["mp"] = int(p.get("mp", 0)) - mp_cost
	ctrl.combat_stats.player = p
	var cd: float = float(def.get("cooldown", 30.0))
	if ctrl.combat_stats.has_method("set_skill_cooldown"):
		ctrl.combat_stats.set_skill_cooldown(skill_id, cd)
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
	var dest = Vector2i(tx, ty)
	if ctrl.map_collision != null and ctrl.map_collision.has_method("is_landable"):
		if not ctrl.map_collision.is_landable(dest.x, dest.y) and ctrl.map_collision.has_method("find_spawn_near"):
			dest = ctrl.map_collision.find_spawn_near(dest.x, dest.y)
	_revive_apply_to_target(kind, mid, new_hp, hp_max, dest, actions)
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(ctrl.combat_stats.player.get("hp", 0)),
		"hp_max": int(ctrl.combat_stats.player.get("hp_max", 0)),
		"mp": int(ctrl.combat_stats.player.get("mp", 0)),
		"mp_max": int(ctrl.combat_stats.player.get("mp_max", 0)),
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
	if ctrl.in_party():
		ctrl._party_refresh_self_member()
		actions.append(ctrl._party_update_action())
	return {"ok": true, "actions": actions}



func _revive_resolve_target(target_id: String) -> Dictionary:
	target_id = target_id.strip_edges()
	if target_id.is_empty():
		return {}
	# Party member (stub / remote id / name).
	var pidx = ctrl._party_find_member_index(target_id)
	if pidx < 0:
		pidx = ctrl._party_find_member_by_name(target_id)
	if pidx >= 0 and ctrl.in_party():
		var m: Dictionary = ctrl._party_members[pidx]
		var mid = str(m.get("id", "")).strip_edges()
		if mid == ctrl._party_self_id():
			return {}
		var cell = ctrl._revive_member_cell(m)
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
	var rid = target_id
	if not ctrl._remote_players.has(rid):
		rid = ctrl.find_remote_by_name(target_id)
	if rid != "" and ctrl._remote_players.has(rid):
		var rd: Dictionary = ctrl._remote_players[rid]
		var in_p = ctrl._party_find_member_index(rid) >= 0
		var marked_ally = bool(rd.get("ally", false)) or bool(rd.get("party_ally", false))
		if not in_p and not marked_ally:
			# Allow revive if currently in party with this remote by name match.
			var rn = str(rd.get("name", "")).strip_edges()
			if rn != "" and ctrl._party_find_member_by_name(rn) >= 0:
				in_p = true
		if in_p or marked_ally:
			var cell_v: Variant = rd.get("death_cell", rd.get("cell", {}))
			var cx = -9999
			var cy = -9999
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
	if ctrl.combat_stats != null and ctrl.combat_stats.npcs.has(target_id):
		var st: Dictionary = ctrl.combat_stats.npcs[target_id]
		if bool(st.get("ally", false)):
			var ncell: Vector2i = ctrl.combat_stats.get_npc_cell(target_id)
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



func _revive_apply_to_target(
	kind: String, mid: String, new_hp: int, hp_max: int, dest: Vector2i, actions: Array
) -> void:
	kind = kind.strip_edges()
	mid = mid.strip_edges()
	if kind == "party":
		var idx = ctrl._party_find_member_index(mid)
		if idx >= 0:
			var m: Dictionary = ctrl._party_members[idx]
			m["hp"] = new_hp
			m["hp_max"] = hp_max
			m["awaiting_respawn"] = false
			m["cell"] = {"x": dest.x, "y": dest.y}
			m.erase("death_cell")
			ctrl._party_members[idx] = m
		# Keep remote mirror in sync when party id is a remote.
		if ctrl._remote_players.has(mid):
			var rd: Dictionary = ctrl._remote_players[mid]
			rd["hp"] = new_hp
			rd["hp_max"] = hp_max
			rd["awaiting_respawn"] = false
			rd["cell"] = {"x": dest.x, "y": dest.y}
			rd.erase("death_cell")
			ctrl._remote_players[mid] = rd
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
		if ctrl._remote_players.has(mid):
			var rd2: Dictionary = ctrl._remote_players[mid]
			rd2["hp"] = new_hp
			rd2["hp_max"] = hp_max
			rd2["awaiting_respawn"] = false
			rd2["cell"] = {"x": dest.x, "y": dest.y}
			rd2.erase("death_cell")
			ctrl._remote_players[mid] = rd2
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
		var pidx = ctrl._party_find_member_index(mid)
		if pidx >= 0:
			var pm: Dictionary = ctrl._party_members[pidx]
			pm["hp"] = new_hp
			pm["hp_max"] = hp_max
			pm["awaiting_respawn"] = false
			pm["cell"] = {"x": dest.x, "y": dest.y}
			pm.erase("death_cell")
			ctrl._party_members[pidx] = pm
	elif kind == "npc":
		if ctrl.combat_stats != null and ctrl.combat_stats.npcs.has(mid):
			var st: Dictionary = ctrl.combat_stats.npcs[mid]
			st["hp"] = new_hp
			st["hp_max"] = hp_max
			st["awaiting_respawn"] = false
			ctrl.combat_stats.npcs[mid] = st
			ctrl.combat_stats.set_npc_cell(mid, dest.x, dest.y)
			if ctrl.combat_stats.statuses != null:
				ctrl.combat_stats.statuses.clear_all_on_death(mid)
			if ctrl.combat_stats.npc_ai.has(mid):
				var ai: Dictionary = ctrl.combat_stats.npc_ai[mid]
				ai["ai_state"] = "idle"
				ai["chase_target"] = ""
				ai["victim_id"] = ""
				ai["respawn_acc"] = 0.0
				ctrl.combat_stats.npc_ai[mid] = ai
			actions.append({
				"type": "set_stat",
				"target": mid,
				"id": mid,
				"hp": new_hp,
				"hp_max": hp_max,
			})


