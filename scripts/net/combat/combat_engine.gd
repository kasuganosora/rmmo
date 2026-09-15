extends RefCounted
## Damage resolve, death, cooldowns, counter-attack. Called by MockServer facade.

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const SkillCatalog = preload("res://scripts/net/combat/skill_catalog.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const Inventory = preload("res://scripts/net/combat/inventory.gd")
const CastState = preload("res://scripts/net/combat/cast_state.gd")

var stats: RefCounted = null
var skills: RefCounted = null
var items: RefCounted = null
var bag: RefCounted = null
## Cast / channel runtime (spend MP+CD at start; interrupt wastes MP).
var cast = CastState.new()
## Optional: Callable(npc_id) -> bool for "is hostile" when not in stats yet.
var hostile_lookup: Callable = Callable()


func setup(p_stats, p_skills, p_items, p_bag) -> void:
	stats = p_stats
	skills = p_skills
	items = p_items
	bag = p_bag
	if cast == null:
		cast = CastState.new()
	else:
		cast.clear()


func _player_stat_actions() -> Array:
	var p: Dictionary = stats.player
	return [
		{
			"type": "set_stat",
			"target": "player",
			"hp": int(p.get("hp", 0)),
			"hp_max": int(p.get("hp_max", 0)),
			"mp": int(p.get("mp", 0)),
			"mp_max": int(p.get("mp_max", 0)),
		}
	]


func _damage_npc(npc_id: String, amount: int, actions: Array) -> void:
	var st: Dictionary = stats.ensure_npc(npc_id)
	var def: int = _effective_def_npc(npc_id)
	var dealt: int = maxi(1, amount - def)
	var hp: int = maxi(0, int(st.get("hp", 0)) - dealt)
	var hp_max: int = int(st.get("hp_max", 1))
	st["hp"] = hp
	stats.npcs[npc_id] = st
	# Hate ≈ damage * attacker threat_mod (tank >1.0). Actor id from session when set.
	var actor_id := "player"
	if "player_actor_id" in stats:
		var aid := str(stats.player_actor_id).strip_edges()
		if aid != "":
			actor_id = aid
	var threat_mod := 1.0
	if stats.has_method("get_actor_threat_mod"):
		threat_mod = float(stats.get_actor_threat_mod(actor_id))
	elif typeof(stats.player) == TYPE_DICTIONARY:
		threat_mod = float(stats.player.get("threat_mod", 1.0))
	if stats.has_method("add_hate"):
		stats.add_hate(npc_id, actor_id, float(dealt), threat_mod)
	elif stats.has_method("add_threat"):
		stats.add_threat(npc_id, actor_id, float(dealt) * threat_mod)
	# Pack assist BEFORE remove_npc (killing blow must still wake allies).
	if stats.has_method("activate_group_allies"):
		stats.activate_group_allies(npc_id)
	# Surviving hit → chase/enrage self.
	if hp > 0:
		if stats.has_method("begin_chase"):
			stats.begin_chase(npc_id)
		elif stats.has_method("enrage_npc"):
			stats.enrage_npc(npc_id)
	actions.append({
		"type": "damage",
		"target": "npc",
		"id": npc_id,
		"amount": dealt,
		"hp": hp,
		"hp_max": hp_max,
	})
	if hp <= 0:
		var death_cell := {"x": 0, "y": 0}
		var has_death_cell := false
		if stats.has_method("get_npc_cell"):
			var dc: Vector2i = stats.get_npc_cell(npc_id)
			if dc.x > -9990:
				death_cell = {"x": dc.x, "y": dc.y}
				has_death_cell = true
		stats.remove_npc(npc_id)
		var kill_act := {"type": "kill_npc", "npc_id": npc_id}
		if has_death_cell:
			kill_act["cell"] = death_cell
		actions.append(kill_act)
		actions.append({"type": "system_message", "text": "击败了敌人。"})


func _damage_player(amount: int, actions: Array, source: String = "") -> void:
	var p: Dictionary = stats.player
	var def: int = _effective_def_player()
	var dealt: int = maxi(1, amount - def)
	var hp: int = maxi(0, int(p.get("hp", 0)) - dealt)
	var hp_max: int = int(p.get("hp_max", 1))
	p["hp"] = hp
	stats.player = p
	var act := {
		"type": "damage",
		"target": "player",
		"id": "player",
		"amount": dealt,
		"hp": hp,
		"hp_max": hp_max,
	}
	if source != "":
		act["source"] = source
	actions.append(act)
	if hp <= 0:
		if stats.statuses != null:
			stats.statuses.clear_all_on_death("player")
		actions.append({"type": "player_died"})
		actions.append({"type": "system_message", "text": "你被击败了……"})


func _heal_player(amount: int, actions: Array) -> void:
	var p: Dictionary = stats.player
	var hp_max: int = int(p.get("hp_max", 1))
	var before: int = int(p.get("hp", 0))
	var hp: int = mini(hp_max, before + amount)
	var gained: int = hp - before
	p["hp"] = hp
	stats.player = p
	actions.append({
		"type": "heal",
		"target": "player",
		"id": "player",
		"amount": gained,
		"hp": hp,
		"hp_max": hp_max,
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
	})


func _restore_mp(amount: int, actions: Array) -> void:
	var p: Dictionary = stats.player
	var mp_max: int = int(p.get("mp_max", 1))
	var before: int = int(p.get("mp", 0))
	var mp: int = mini(mp_max, before + amount)
	var gained: int = mp - before
	p["mp"] = mp
	stats.player = p
	actions.append({
		"type": "heal",
		"target": "player",
		"id": "player",
		"amount": 0,
		"mp_gain": gained,
		"hp": int(p.get("hp", 0)),
		"hp_max": int(p.get("hp_max", 0)),
		"mp": mp,
		"mp_max": mp_max,
	})


func _spend_mp(cost: int) -> bool:
	var p: Dictionary = stats.player
	var mp: int = int(p.get("mp", 0))
	if mp < cost:
		return false
	p["mp"] = mp - cost
	stats.player = p
	return true


func _in_range(npc_id: String, player_x: int, player_y: int, range_cells: int) -> bool:
	if range_cells <= 0:
		return true
	var cell: Vector2i = stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		# Cell unknown: do not trust client — reject until register_npc / try_npc_move.
		return false
	var dist: int = maxi(absi(cell.x - player_x), absi(cell.y - player_y))
	return dist <= range_cells


func _maybe_counter(npc_id: String, player_x: int, player_y: int, actions: Array) -> void:
	if not stats.npcs.has(npc_id):
		return
	var st: Dictionary = stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0:
		return
	if not bool(st.get("hostile", true)):
		return
	if not _in_range(npc_id, player_x, player_y, 1):
		return
	var atk: int = _effective_atk_npc(npc_id)
	_damage_player(atk, actions, npc_id)


func _effective_atk_player() -> int:
	var base: int = int(stats.player.get("atk", 10))
	if stats.statuses != null:
		return int(stats.statuses.effective_atk(base, "player"))
	return maxi(1, base)


func _effective_def_player() -> int:
	var base: int = int(stats.player.get("def", 0))
	if stats.statuses != null:
		return int(stats.statuses.effective_def(base, "player"))
	return maxi(0, base)


func _effective_atk_npc(npc_id: String) -> int:
	if not stats.npcs.has(npc_id):
		return 5
	var base: int = int(stats.npcs[npc_id].get("atk", 5))
	if stats.statuses != null:
		return int(stats.statuses.effective_atk(base, npc_id))
	return maxi(1, base)


func _effective_def_npc(npc_id: String) -> int:
	if not stats.npcs.has(npc_id):
		return 0
	var base: int = int(stats.npcs[npc_id].get("def", 0))
	if stats.statuses != null:
		return int(stats.statuses.effective_def(base, npc_id))
	return maxi(0, base)


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Living hostile NPCs within Chebyshev radius of center, nearest first, capped.
func _collect_aoe_hostiles(center: Vector2i, radius: int, max_targets: int) -> Array:
	radius = maxi(radius, 0)
	max_targets = maxi(max_targets, 1)
	var scored: Array = []
	for npc_id_v in stats.npcs.keys():
		var npc_id := str(npc_id_v)
		var st: Dictionary = stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0:
			continue
		if not bool(st.get("hostile", false)):
			continue
		var cell: Vector2i = stats.get_npc_cell(npc_id)
		if cell.x <= -9990:
			continue
		var dist: int = _chebyshev(center, cell)
		if dist > radius:
			continue
		scored.append({"id": npc_id, "dist": dist})
	scored.sort_custom(func(a, b): return int(a.get("dist", 0)) < int(b.get("dist", 0)))
	var out: Array = []
	for i in range(mini(scored.size(), max_targets)):
		out.append(str(scored[i]["id"]))
	return out


func _apply_status_to(target_key: String, status_def: Dictionary, source_id: String, actions: Array) -> void:
	if status_def.is_empty() or stats.statuses == null:
		return
	var dur: float = float(status_def.get("duration", 5.0))
	stats.statuses.apply_status(target_key, status_def, dur, source_id)
	actions.append(stats.statuses.status_update_action(target_key))


func _status_def_from_skill(def: Dictionary) -> Dictionary:
	var sv: Variant = def.get("status", {})
	if typeof(sv) != TYPE_DICTIONARY:
		return {}
	return (sv as Dictionary).duplicate(true)


## Basic / auto attack (extends former MockServer.try_attack).
func try_attack(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not stats.player_alive():
		return {"ok": false, "actions": []}
	if is_casting():
		return {"ok": false, "actions": [{"type": "system_message", "text": "施法中，无法普攻。"}]}
	if not stats.is_attack_ready():
		return {
			"ok": false,
			"actions": [{"type": "system_message", "text": "攻击冷却中。"}],
		}
	if not _in_range(npc_id, player_x, player_y, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "目标太远。"}]}
	var st: Dictionary = stats.ensure_npc(npc_id, true)
	if int(st.get("hp", 0)) <= 0:
		return {"ok": false, "actions": []}
	var cd: float = float(stats.player.get("atk_speed", 0.8))
	stats.set_attack_cooldown(cd)
	# Mirror basic_attack skill CD so hotbar shares timing.
	stats.set_skill_cooldown("basic_attack", cd)
	var actions: Array = []
	var atk: int = _effective_atk_player()
	_damage_npc(npc_id, atk, actions)
	_maybe_counter(npc_id, player_x, player_y, actions)
	actions.append_array(_player_stat_actions())
	actions.append({
		"type": "skill_cd",
		"skill_id": "basic_attack",
		"remaining": cd,
		"cooldown": cd,
	})
	return {"ok": true, "actions": actions}


func is_casting() -> bool:
	return cast != null and cast.is_busy()


func clear_cast() -> void:
	if cast != null:
		cast.clear()


## Interrupt active cast/channel. Returns actions (may be empty if idle).
func interrupt_cast(reason: String = "move") -> Array:
	if cast == null or not cast.is_busy():
		return []
	return cast.interrupt(reason)


## Advance cast/channel; on finish resolves skill effect. Returns action list.
func tick_cast(delta: float) -> Array:
	var actions: Array = []
	if cast == null or not cast.is_busy():
		return actions
	var tick_r: Dictionary = cast.tick(delta)
	actions.append_array(tick_r.get("actions", []))
	if not bool(tick_r.get("finished", false)):
		return actions
	# Snapshot then clear before resolve so nested casts are impossible.
	var snap: Dictionary = cast.snapshot()
	cast.clear()
	var skill_id := str(snap.get("skill_id", ""))
	var target_id := str(snap.get("target_id", ""))
	var px: int = int(snap.get("player_x", 0))
	var py: int = int(snap.get("player_y", 0))
	var def_v: Variant = snap.get("def", {})
	var def: Dictionary = def_v if typeof(def_v) == TYPE_DICTIONARY else {}
	var mode := str(snap.get("mode", "cast"))
	var sname := str(snap.get("name", skill_id))
	if def.is_empty() and skills != null:
		def = skills.get_skill(skill_id)
	if def.is_empty() or not stats.player_alive():
		actions.append({
			"type": "cast_end",
			"skill_id": skill_id,
			"name": sname,
			"mode": mode,
			"ok": false,
			"cancelled": false,
		})
		return actions
	# Re-validate target at finish (move interrupt should have fired if moved).
	var needs_target: bool = bool(def.get("requires_target", false))
	var range_cells: int = int(def.get("range", 1))
	if needs_target:
		if target_id.is_empty() or not stats.npcs.has(target_id) or int(stats.npcs[target_id].get("hp", 0)) <= 0:
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
			})
			actions.append({"type": "system_message", "text": "目标已失效。"})
			actions.append_array(_player_stat_actions())
			return actions
		if not _in_range(target_id, px, py, range_cells):
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
			})
			actions.append({"type": "system_message", "text": "目标太远。"})
			actions.append_array(_player_stat_actions())
			return actions
	var resolve_actions: Array = []
	_resolve_skill_effect(def, skill_id, target_id, px, py, resolve_actions)
	actions.append_array(resolve_actions)
	actions.append({
		"type": "cast_end",
		"skill_id": skill_id,
		"name": sname,
		"mode": mode,
		"ok": true,
		"cancelled": false,
	})
	return actions


func try_use_skill(skill_id: String, target_npc_id: String, player_x: int, player_y: int) -> Dictionary:
	skill_id = skill_id.strip_edges()
	target_npc_id = target_npc_id.strip_edges()
	if skill_id.is_empty() or not stats.player_alive():
		return {"ok": false, "actions": []}
	# basic_attack delegates to try_attack.
	if skill_id == "basic_attack":
		return try_attack(target_npc_id, player_x, player_y)
	if is_casting():
		return {"ok": false, "actions": [{"type": "system_message", "text": "正在施法中。"}]}
	var def: Dictionary = skills.get_skill(skill_id)
	if def.is_empty():
		return {"ok": false, "actions": [{"type": "system_message", "text": "未知技能。"}]}
	var cat := str(def.get("category", "")).strip_edges()
	if cat.is_empty():
		# Infer: passive_* effects are never castable.
		var eff0 := str(def.get("effect", ""))
		if eff0.begins_with("passive"):
			cat = "passive"
	if cat == "passive":
		return {"ok": false, "actions": [{"type": "system_message", "text": "被动，无需施放"}]}
	if not stats.is_skill_ready(skill_id):
		var rem: float = stats.skill_cd_remaining(skill_id)
		return {
			"ok": false,
			"actions": [
				{"type": "system_message", "text": "技能冷却中（%.1f 秒）。" % rem},
				{"type": "skill_cd", "skill_id": skill_id, "remaining": rem, "cooldown": float(def.get("cooldown", 0))},
			],
		}
	var mp_cost: int = int(def.get("mp_cost", 0))
	if int(stats.player.get("mp", 0)) < mp_cost:
		return {"ok": false, "actions": [{"type": "system_message", "text": "MP 不足。"}]}
	var needs_target: bool = bool(def.get("requires_target", false))
	var range_cells: int = int(def.get("range", 1))
	if needs_target:
		if target_npc_id.is_empty():
			return {"ok": false, "actions": [{"type": "system_message", "text": "需要目标。"}]}
		if not _in_range(target_npc_id, player_x, player_y, range_cells):
			return {"ok": false, "actions": [{"type": "system_message", "text": "目标太远。"}]}
		stats.ensure_npc(target_npc_id, true)
		if not stats.npcs.has(target_npc_id) or int(stats.npcs[target_npc_id].get("hp", 0)) <= 0:
			return {"ok": false, "actions": []}
	# Cast / channel: validate at start, lock CD + spend MP at start (interrupt wastes MP).
	var cast_time: float = float(def.get("cast_time", 0.0))
	var channel_time: float = float(def.get("channel_time", 0.0))
	var use_cast := cast_time > 0.0
	var use_channel := (not use_cast) and channel_time > 0.0
	if use_cast or use_channel:
		if not _spend_mp(mp_cost):
			return {"ok": false, "actions": [{"type": "system_message", "text": "MP 不足。"}]}
		var cd: float = float(def.get("cooldown", 1.0))
		stats.set_skill_cooldown(skill_id, cd)
		var mode := "cast" if use_cast else "channel"
		var duration: float = cast_time if use_cast else channel_time
		var interrupt_on_move: bool = bool(def.get("interrupt_on_move", true))
		var sname := str(def.get("name", skill_id))
		var start_act: Dictionary = cast.begin(
			skill_id, sname, mode, duration, target_npc_id, player_x, player_y, def, interrupt_on_move
		)
		var actions: Array = [start_act]
		actions.append_array(_player_stat_actions())
		actions.append({
			"type": "skill_cd",
			"skill_id": skill_id,
			"remaining": cd,
			"cooldown": cd,
		})
		actions.append({"type": "system_message", "text": "开始施放【%s】…" % sname})
		return {"ok": true, "actions": actions}
	# Instant path.
	if not _spend_mp(mp_cost):
		return {"ok": false, "actions": [{"type": "system_message", "text": "MP 不足。"}]}
	var cd_i: float = float(def.get("cooldown", 1.0))
	stats.set_skill_cooldown(skill_id, cd_i)
	var actions_i: Array = []
	_resolve_skill_effect(def, skill_id, target_npc_id, player_x, player_y, actions_i)
	actions_i.append({
		"type": "skill_cd",
		"skill_id": skill_id,
		"remaining": cd_i,
		"cooldown": cd_i,
	})
	return {"ok": true, "actions": actions_i}


## Apply skill damage/heal/status/aoe after validation + MP/CD already handled.
func _resolve_skill_effect(
	def: Dictionary,
	skill_id: String,
	target_npc_id: String,
	player_x: int,
	player_y: int,
	actions: Array
) -> void:
	var effect := str(def.get("effect", "damage"))
	var aoe_radius: int = int(def.get("aoe_radius", 0))
	var max_targets: int = int(def.get("max_targets", 8))
	var needs_target: bool = bool(def.get("requires_target", false))
	var status_def: Dictionary = _status_def_from_skill(def)
	var power: float = float(def.get("power", 1.0))
	var atk: int = _effective_atk_player()
	var amount: int = maxi(1, int(round(float(atk) * power)))
	match effect:
		"damage":
			_damage_npc(target_npc_id, amount, actions)
			_maybe_counter(target_npc_id, player_x, player_y, actions)
		"damage_and_status":
			_damage_npc(target_npc_id, amount, actions)
			if stats.npcs.has(target_npc_id) and int(stats.npcs[target_npc_id].get("hp", 0)) > 0:
				_apply_status_to(target_npc_id, status_def, "player", actions)
			_maybe_counter(target_npc_id, player_x, player_y, actions)
		"aoe_damage":
			var center := Vector2i(player_x, player_y)
			if needs_target:
				center = stats.get_npc_cell(target_npc_id)
				if center.x <= -9990:
					center = Vector2i(player_x, player_y)
			var radius: int = aoe_radius
			if radius <= 0:
				radius = 0
			var hits: Array = _collect_aoe_hostiles(center, radius, max_targets)
			# Ensure primary target is included when requires_target.
			if needs_target and not target_npc_id.is_empty() and stats.npcs.has(target_npc_id):
				if target_npc_id not in hits:
					hits.push_front(target_npc_id)
					while hits.size() > max_targets:
						hits.pop_back()
			if hits.is_empty() and needs_target and not target_npc_id.is_empty():
				hits = [target_npc_id]
			for hid_v in hits:
				var hid := str(hid_v)
				if not stats.npcs.has(hid) or int(stats.npcs[hid].get("hp", 0)) <= 0:
					continue
				_damage_npc(hid, amount, actions)
				if not status_def.is_empty() and stats.npcs.has(hid) and int(stats.npcs[hid].get("hp", 0)) > 0:
					_apply_status_to(hid, status_def, "player", actions)
			if needs_target and not target_npc_id.is_empty():
				_maybe_counter(target_npc_id, player_x, player_y, actions)
		"apply_status":
			if needs_target:
				_apply_status_to(target_npc_id, status_def, "player", actions)
			else:
				_apply_status_to("player", status_def, "player", actions)
		"heal":
			var heal_amt: int = int(def.get("heal_amount", 20))
			_heal_player(heal_amt, actions)
		_:
			actions.append({"type": "system_message", "text": "技能效果未实现：%s" % effect})
	actions.append_array(_player_stat_actions())
	var sname := str(def.get("name", skill_id))
	actions.append({"type": "system_message", "text": "使用了【%s】。" % sname})


func try_use_item(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or not stats.player_alive():
		return {"ok": false, "actions": []}
	var def: Dictionary = items.get_item(item_id)
	if def.is_empty():
		return {"ok": false, "actions": [{"type": "system_message", "text": "未知物品。"}]}
	# Equipment is equipped via MockServer.try_equip_item, not consumed here.
	if str(def.get("type", "")).strip_edges() == "equipment" or not bool(def.get("consumable", false)):
		var ue := str(def.get("use_effect", def.get("effect", ""))).strip_edges()
		if str(def.get("type", "")).strip_edges() == "equipment" or ue.is_empty():
			return {"ok": false, "actions": [{"type": "system_message", "text": "无法直接使用该物品。"}]}
	if not bag.has_item(item_id, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "背包中没有该物品。"}]}
	if not stats.is_item_ready(item_id):
		return {"ok": false, "actions": [{"type": "system_message", "text": "物品冷却中。"}]}
	if not bag.consume(item_id, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "背包中没有该物品。"}]}
	var cd: float = float(def.get("cooldown", 1.0))
	stats.set_item_cooldown(item_id, cd)
	var actions: Array = []
	# Prefer use_effect (item_template); fall back to legacy effect.
	var effect := str(def.get("use_effect", "")).strip_edges()
	if effect.is_empty():
		effect = str(def.get("effect", "")).strip_edges()
	var amount: int = int(def.get("amount", 0))
	match effect:
		"heal_hp":
			_heal_player(amount, actions)
		"heal_mp":
			_restore_mp(amount, actions)
		_:
			actions.append({"type": "system_message", "text": "物品效果未实现：%s" % effect})
	actions.append({
		"type": "inventory_update",
		"items": bag.snapshot(),
		"gold": bag.get_gold() if bag != null and bag.has_method("get_gold") else 0,
	})
	actions.append_array(_player_stat_actions())
	var iname := str(def.get("name", item_id))
	actions.append({"type": "system_message", "text": "使用了【%s】。" % iname})
	return {"ok": true, "actions": actions}


## Periodic tick: status DoT/HoT then adjacent hostile counter.
func tick(player_x: int, player_y: int, delta: float) -> Dictionary:
	# Lightweight: every ~1.5s of accumulated time handled by MockServer.
	var actions: Array = []
	if stats.statuses != null:
		actions.append_array(stats.statuses.tick_statuses(delta, stats))
	if not stats.player_alive():
		if not actions.is_empty():
			actions.append_array(_player_stat_actions())
		return {"ok": true, "actions": actions}
	for npc_id in stats.npc_cells.keys():
		if not stats.npcs.has(npc_id):
			continue
		var st: Dictionary = stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
			continue
		if not _in_range(str(npc_id), player_x, player_y, 1):
			continue
		_damage_player(_effective_atk_npc(str(npc_id)), actions, str(npc_id))
		actions.append_array(_player_stat_actions())
		return {"ok": true, "actions": actions}
	if not actions.is_empty():
		actions.append_array(_player_stat_actions())
	return {"ok": true, "actions": actions}
