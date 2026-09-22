extends RefCounted
## Domain module: skill effect resolution + per-effect handlers (taunt, interrupt,
## mark, revive, charge, execute) and the _resolve_skill_effect dispatcher.
## Damage/heal/status/geometry helpers stay on the engine (ctrl).

var ctrl
func _init(c):
	ctrl = c

const GridPath = preload("res://scripts/map/grid_path.gd")

func _apply_taunt(npc_id: String, def: Dictionary, actions: Array) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.stats == null or not ctrl.stats.npcs.has(npc_id):
		return
	var st: Dictionary = ctrl.stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
		return
	var actor_id := "player"
	if "player_actor_id" in ctrl.stats:
		var aid := str(ctrl.stats.player_actor_id).strip_edges()
		if aid != "":
			actor_id = aid
	var base_spike: float = float(def.get("hate_amount", 1000.0))
	if base_spike <= 0.0:
		base_spike = 1000.0
	# Beat sticky victim hysteresis (THREAT_SWITCH_RATIO 1.10): ensure we outrank current top.
	var top_other := 0.0
	if ctrl.stats.has_method("get_hate_list"):
		for e in ctrl.stats.get_hate_list(npc_id, false):
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var eid := str((e as Dictionary).get("id", ""))
			if eid == actor_id:
				continue
			top_other = maxf(top_other, float((e as Dictionary).get("threat", 0.0)))
	var my_hate := 0.0
	if ctrl.stats.has_method("get_threat"):
		my_hate = float(ctrl.stats.get_threat(npc_id, actor_id))
	var switch_ratio := 1.10
	if "THREAT_SWITCH_RATIO" in ctrl.stats:
		switch_ratio = float(ctrl.stats.THREAT_SWITCH_RATIO)
	var need: float = top_other * switch_ratio - my_hate + 1.0
	var spike: float = maxf(base_spike, need)
	if ctrl.stats.has_method("add_hate"):
		ctrl.stats.add_hate(npc_id, actor_id, spike, 1.0)
	elif ctrl.stats.has_method("add_threat"):
		ctrl.stats.add_threat(npc_id, actor_id, spike)
	# Force victim onto player even if sticky edge cases remain.
	if ctrl.stats.npc_ai.has(npc_id):
		var ai: Dictionary = ctrl.stats.npc_ai[npc_id]
		ai["victim_id"] = actor_id
		ai["chase_target"] = actor_id
		ctrl.stats.npc_ai[npc_id] = ai
	if ctrl.stats.has_method("begin_chase"):
		ctrl.stats.begin_chase(npc_id, actor_id)
	var thr_act: Dictionary = ctrl._threat_update_action(npc_id)
	if not thr_act.is_empty():
		actions.append(thr_act)
	var nm := str(st.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = npc_id
	actions.append({"type": "system_message", "text": "嘲讽了%s" % nm})

func _apply_interrupt(npc_id: String, def: Dictionary, actions: Array) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.stats == null or not ctrl.stats.npcs.has(npc_id):
		return
	var st: Dictionary = ctrl.stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
		return
	var nm := str(st.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = npc_id
	var interrupted_cast: bool = ctrl.is_npc_casting(npc_id)
	if interrupted_cast:
		actions.append_array(ctrl.cancel_npc_cast(npc_id, "interrupt"))
		actions.append({"type": "system_message", "text": "打断了%s的施法！" % nm})
	var power: float = float(def.get("power", 0.35))
	if power <= 0.0:
		power = 0.35
	var amount: int = maxi(1, int(round(float(ctrl._effective_atk_player()) * power)))
	ctrl._damage_npc(npc_id, amount, actions, true, "player", true)
	var status_def: Dictionary = ctrl._status_def_from_skill(def)
	if status_def.is_empty():
		status_def = {
			"id": "silence",
			"name": "沉默",
			"kind": "debuff",
			"duration": 3.0,
			"tick_interval": 0,
		}
	if ctrl.stats.npcs.has(npc_id) and int(ctrl.stats.npcs[npc_id].get("hp", 0)) > 0:
		ctrl._apply_status_to(npc_id, status_def, "player", actions)
	# When a cast was canceled, keep one clear interrupt line (skip silence toast).
	if not interrupted_cast:
		actions.append({"type": "system_message", "text": "打断：沉默了%s！" % nm})

func _apply_mark(npc_id: String, def: Dictionary, actions: Array) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.stats == null or not ctrl.stats.npcs.has(npc_id):
		return
	var st: Dictionary = ctrl.stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
		return
	var status_def: Dictionary = ctrl._status_def_from_skill(def)
	if status_def.is_empty():
		status_def = {
			"id": "mark",
			"name": "标记",
			"kind": "debuff",
			"duration": 12.0,
			"tick_interval": 0,
			"def_mul": 0.85,
		}
	if not status_def.has("def_mul"):
		status_def["def_mul"] = 0.85
	ctrl._apply_status_to(npc_id, status_def, "player", actions)
	var nm := str(st.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = npc_id
	actions.append({"type": "system_message", "text": "标记了%s！" % nm})

func _apply_revive(npc_id: String, def: Dictionary, actions: Array) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.stats == null or not ctrl.stats.npcs.has(npc_id):
		return
	var st: Dictionary = ctrl.stats.npcs[npc_id]
	if not bool(st.get("ally", false)):
		return
	var deadish := int(st.get("hp", 0)) <= 0 or bool(st.get("awaiting_respawn", false))
	if not deadish:
		return
	var hp_max: int = maxi(1, int(st.get("hp_max", 1)))
	var pct: float = float(def.get("heal_pct", 0.3))
	if pct <= 0.0:
		pct = 0.3
	var new_hp: int = maxi(1, int(round(float(hp_max) * pct)))
	st["hp"] = new_hp
	st["awaiting_respawn"] = false
	ctrl.stats.npcs[npc_id] = st
	if ctrl.stats.statuses != null:
		ctrl.stats.statuses.clear_all_on_death(npc_id)
	# Clear AI dead/respawn wait if present so ally can act again.
	if ctrl.stats.npc_ai.has(npc_id):
		var ai: Dictionary = ctrl.stats.npc_ai[npc_id]
		ai["ai_state"] = "idle"
		ai["chase_target"] = ""
		ai["victim_id"] = ""
		ai["respawn_acc"] = 0.0
		ctrl.stats.npc_ai[npc_id] = ai
	actions.append_array(ctrl._npc_stat_actions(npc_id))
	var nm := str(st.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = npc_id
	actions.append({"type": "system_message", "text": "复活了%s！" % nm})
	actions.append({
		"type": "ally_revived",
		"id": npc_id,
		"hp": new_hp,
		"hp_max": hp_max,
	})

func _charge_dest_cell(npc_id: String, player_x: int, player_y: int) -> Vector2i:
	var tcell: Vector2i = ctrl.stats.get_npc_cell(npc_id)
	if tcell.x <= -9990:
		return Vector2i(-9999, -9999)
	var from := Vector2i(player_x, player_y)
	if ctrl._chebyshev(from, tcell) <= 1:
		return from
	# Step from target toward caster by 1 Chebyshev cell.
	var dx: int = clampi(from.x - tcell.x, -1, 1)
	var dy: int = clampi(from.y - tcell.y, -1, 1)
	var dest := Vector2i(tcell.x + dx, tcell.y + dy)
	if ctrl.map_collision != null:
		# Prefer landable adjacent cells closest to caster.
		var best := Vector2i(-9999, -9999)
		var best_d := 999999
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var c := Vector2i(tcell.x + ox, tcell.y + oy)
				if ctrl.map_collision.has_method("is_landable") and not bool(ctrl.map_collision.is_landable(c.x, c.y)):
					continue
				if ctrl.map_collision.has_method("is_extra_blocked") and bool(ctrl.map_collision.is_extra_blocked(c.x, c.y)):
					# Occupied by other units — skip unless it is our current cell.
					if c != from:
						continue
				var d: int = ctrl._chebyshev(from, c)
				if d < best_d:
					best_d = d
					best = c
		if best.x > -9990:
			return best
	return dest

func _charge_path_error(npc_id: String, player_x: int, player_y: int) -> String:
	var from := Vector2i(player_x, player_y)
	var dest: Vector2i = ctrl._charge_dest_cell(npc_id, player_x, player_y)
	if dest.x <= -9990:
		return "冲锋路径被阻挡。"
	if dest == from:
		return ""
	if ctrl.map_collision == null:
		return ""
	# Temporarily free player occupancy so pathing can leave the start cell.
	var had_block := false
	if ctrl.map_collision.has_method("is_extra_blocked"):
		had_block = bool(ctrl.map_collision.is_extra_blocked(from.x, from.y))
	if had_block and ctrl.map_collision.has_method("set_extra_blocked"):
		ctrl.map_collision.set_extra_blocked(from.x, from.y, false)
	var path: Array[Vector2i] = GridPath.find_path(ctrl.map_collision, from, dest)
	if path.is_empty():
		path = GridPath.find_path_near(ctrl.map_collision, from, dest, 1)
	if had_block and ctrl.map_collision.has_method("set_extra_blocked"):
		ctrl.map_collision.set_extra_blocked(from.x, from.y, true)
	if path.is_empty() and dest != from:
		return "冲锋路径被阻挡。"
	return ""

func _apply_charge(npc_id: String, def: Dictionary, player_x: int, player_y: int, actions: Array) -> Vector2i:
	npc_id = npc_id.strip_edges()
	var from := Vector2i(player_x, player_y)
	if npc_id.is_empty() or ctrl.stats == null or not ctrl.stats.npcs.has(npc_id):
		return from
	var st: Dictionary = ctrl.stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
		return from
	# Re-validate landing occupancy at apply time (path may have changed since cast start).
	var path_err: String = ctrl._charge_path_error(npc_id, player_x, player_y)
	if path_err != "":
		actions.append({"type": "system_message", "text": path_err})
		return from
	var dest: Vector2i = ctrl._charge_dest_cell(npc_id, player_x, player_y)
	if dest.x <= -9990:
		dest = from
	if dest != from:
		ctrl.player_cell_hint = dest
		var face: int = ctrl.facing_toward(from, dest)
		actions.append({
			"type": "player_move",
			"x": dest.x,
			"y": dest.y,
			"cell": {"x": dest.x, "y": dest.y},
			"facing": face,
			"kind": "charge",
		})
	var power: float = float(def.get("power", 1.2))
	if power <= 0.0:
		power = 1.2
	var amount: int = maxi(1, int(round(float(ctrl._effective_atk_player()) * power)))
	var hit: bool = ctrl._damage_npc(npc_id, amount, actions, true, "player", true)
	var status_def: Dictionary = ctrl._status_def_from_skill(def)
	if status_def.is_empty():
		status_def = {
			"id": "root",
			"name": "定身",
			"kind": "debuff",
			"duration": 0.75,
			"tick_interval": 0,
			"move_speed_mul": 0.0,
		}
	if not status_def.has("move_speed_mul"):
		status_def["move_speed_mul"] = 0.0
	if hit and ctrl.stats.npcs.has(npc_id) and int(ctrl.stats.npcs[npc_id].get("hp", 0)) > 0:
		ctrl._apply_status_to(npc_id, status_def, "player", actions)
	var nm := str(st.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = npc_id
	if hit:
		actions.append({"type": "system_message", "text": "冲锋了%s！" % nm})
		ctrl._maybe_counter(npc_id, dest.x, dest.y, actions)
	return dest

func _apply_execute(npc_id: String, def: Dictionary, player_x: int, player_y: int, actions: Array) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.stats == null or not ctrl.stats.npcs.has(npc_id):
		return
	var st: Dictionary = ctrl.stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0 or not bool(st.get("hostile", false)):
		return
	var power: float = float(def.get("power", 2.0))
	if power <= 0.0:
		power = 2.0
	var amount: int = maxi(1, int(round(float(ctrl._effective_atk_player()) * power)))
	var hit: bool = ctrl._damage_npc(npc_id, amount, actions, true, "player", true)
	var nm := str(st.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = npc_id
	if hit:
		actions.append({"type": "system_message", "text": "斩杀了%s！" % nm})
		ctrl._maybe_counter(npc_id, player_x, player_y, actions)

func _resolve_skill_effect(
	def: Dictionary,
	skill_id: String,
	target_npc_id: String,
	player_x: int,
	player_y: int,
	actions: Array,
	ground_x: int = -9999,
	ground_y: int = -9999,
	caster: String = "player"
) -> void:
	var effect := str(def.get("effect", "damage"))
	var aoe_radius: int = int(def.get("aoe_radius", 0))
	var max_targets: int = int(def.get("max_targets", 8))
	var needs_target: bool = bool(def.get("requires_target", false))
	var tmode: String = ctrl.skill_target_mode(def)
	var status_def: Dictionary = ctrl._status_def_from_skill(def)
	var power: float = float(def.get("power", 1.0))
	var from_player := caster == "player" or caster.is_empty()
	var atk: int = ctrl._effective_atk_player() if from_player else ctrl._effective_atk_npc(caster)
	var amount: int = maxi(1, int(round(float(atk) * power)))
	var shape := str(def.get("aoe_shape", "circle"))
	var center: Vector2i = ctrl._resolve_ground_cell(def, target_npc_id, player_x, player_y, ground_x, ground_y)
	if center.x <= -9990:
		center = Vector2i(player_x, player_y)
	var facing: int = ctrl.facing_toward(Vector2i(player_x, player_y), center)
	var hits: Array = []
	if from_player:
		# Damaging / taunt skills cancel stealth + mount; self-buffs / heals do not.
		if effect in ["damage", "damage_and_status", "aoe_damage", "taunt", "interrupt", "mark", "charge", "execute"]:
			ctrl.break_stealth(actions)
			ctrl.break_mount(actions)
		match effect:
			"damage":
				if ctrl._damage_npc(target_npc_id, amount, actions, true, "player", true):
					hits.append(target_npc_id)
				ctrl._maybe_counter(target_npc_id, player_x, player_y, actions)
			"damage_and_status":
				if ctrl._damage_npc(target_npc_id, amount, actions, true, "player", true):
					hits.append(target_npc_id)
					if ctrl.stats.npcs.has(target_npc_id) and int(ctrl.stats.npcs[target_npc_id].get("hp", 0)) > 0:
						ctrl._apply_status_to(target_npc_id, status_def, "player", actions)
				ctrl._maybe_counter(target_npc_id, player_x, player_y, actions)
			"aoe_damage":
				if tmode != "ground" and needs_target:
					var tc: Vector2i = ctrl.stats.get_npc_cell(target_npc_id)
					if tc.x > -9990:
						center = tc
				var radius: int = aoe_radius
				if radius <= 0:
					radius = 0
				hits = ctrl._collect_aoe_hostiles(center, radius, max_targets, shape, facing)
				if needs_target and not target_npc_id.is_empty() and ctrl.stats.npcs.has(target_npc_id):
					if target_npc_id not in hits:
						hits.push_front(target_npc_id)
						while hits.size() > max_targets:
							hits.pop_back()
				if hits.is_empty() and needs_target and not target_npc_id.is_empty():
					hits = [target_npc_id]
				var landed: Array = []
				var wear_first := true  # AoE: weapon wear once per cast, not per hit.
				for hid_v in hits:
					var hid := str(hid_v)
					if not ctrl.stats.npcs.has(hid) or int(ctrl.stats.npcs[hid].get("hp", 0)) <= 0:
						continue
					var do_wear := wear_first
					wear_first = false
					if ctrl._damage_npc(hid, amount, actions, true, "player", do_wear):
						landed.append(hid)
						if not status_def.is_empty() and ctrl.stats.npcs.has(hid) and int(ctrl.stats.npcs[hid].get("hp", 0)) > 0:
							ctrl._apply_status_to(hid, status_def, "player", actions)
				hits = landed
				if needs_target and not target_npc_id.is_empty():
					ctrl._maybe_counter(target_npc_id, player_x, player_y, actions)
			"apply_status":
				if needs_target:
					ctrl._apply_status_to(target_npc_id, status_def, "player", actions)
					hits.append(target_npc_id)
				else:
					ctrl._apply_status_to("player", status_def, "player", actions)
			"heal":
				var heal_amt: int = int(def.get("heal_amount", 20))
				ctrl._heal_player(heal_amt, actions)
			"taunt":
				ctrl._apply_taunt(target_npc_id, def, actions)
				hits.append(target_npc_id)
			"interrupt":
				ctrl._apply_interrupt(target_npc_id, def, actions)
				hits.append(target_npc_id)
				ctrl._maybe_counter(target_npc_id, player_x, player_y, actions)
			"mark":
				ctrl._apply_mark(target_npc_id, def, actions)
				hits.append(target_npc_id)
			"charge":
				var landed: Vector2i = ctrl._apply_charge(target_npc_id, def, player_x, player_y, actions)
				player_x = landed.x
				player_y = landed.y
				hits.append(target_npc_id)
			"execute":
				ctrl._apply_execute(target_npc_id, def, player_x, player_y, actions)
				hits.append(target_npc_id)
			"revive":
				ctrl._apply_revive(target_npc_id, def, actions)
				hits.append(target_npc_id)
			"mount":
				ctrl._apply_mount_toggle(def, actions)
			"recall", "teleport_home":
				actions.append({"type": "recall"})
			_:
				actions.append({"type": "system_message", "text": "技能效果未实现：%s" % effect})
		ctrl._append_skill_fx(actions, def, skill_id, "player", center, hits)
		actions.append_array(ctrl._player_stat_actions())
		var sname := str(def.get("name", skill_id))
		if effect == "taunt":
			# Message already appended in ctrl._apply_taunt («嘲讽了{名}»).
			pass
		elif effect == "interrupt":
			# Message already appended in ctrl._apply_interrupt («打断：沉默了{名}！»).
			pass
		elif effect == "mark":
			# Message already appended in ctrl._apply_mark («标记了{名}！»).
			pass
		elif effect == "charge":
			# Message already appended in ctrl._apply_charge («冲锋了{名}！»).
			pass
		elif effect == "execute":
			# Message already appended in ctrl._apply_execute («斩杀了{名}！»).
			pass
		elif effect == "revive":
			# Message already appended in ctrl._apply_revive («复活了{名}！»).
			pass
		elif effect == "mount" or skill_id == "mount":
			# Messages in _apply_mount_toggle / break_mount.
			pass
		elif skill_id == "battle_shout" or sname == "战吼":
			actions.append({"type": "system_message", "text": "战吼响起！"})
		else:
			actions.append({"type": "system_message", "text": "使用了【%s】。" % sname})
		return
	# NPC caster: damage/status the player if they sit in the skill footprint.
	var player_cell: Vector2i = ctrl.player_cell_hint
	if player_cell.x <= -9990:
		player_cell = Vector2i(ground_x, ground_y)
	var hit_player := false
	match effect:
		"damage", "damage_and_status":
			hit_player = true
		"aoe_damage":
			hit_player = ctrl.cell_in_aoe(center, player_cell, aoe_radius, shape, facing)
		"apply_status":
			hit_player = true
		_:
			hit_player = false
	if hit_player and ctrl.stats.player_alive():
		if effect == "apply_status":
			ctrl._apply_status_to("player", status_def, caster, actions)
			hits.append("player")
		elif ctrl._damage_player(amount, actions, caster):
			hits.append("player")
			if effect == "damage_and_status" or (effect == "aoe_damage" and not status_def.is_empty()):
				ctrl._apply_status_to("player", status_def, caster, actions)
	ctrl._append_skill_fx(actions, def, skill_id, caster, center, hits)
	actions.append_array(ctrl._player_stat_actions())
	var nsname := str(def.get("name", skill_id))
	actions.append({"type": "system_message", "text": "【%s】使用了【%s】。" % [caster, nsname]})
