extends RefCounted
## Runtime buff / debuff / DoT / HoT instances (MockServer-authoritative).
## Owned by CombatStats; CombatEngine applies + ticks.

## target_key ("player" | npc_id) -> Array[Dictionary]
var _by_target: Dictionary = {}


func apply_status(target_key: String, def: Dictionary, duration: float = -1.0, source_id: String = "") -> Dictionary:
	target_key = target_key.strip_edges()
	if target_key.is_empty() or def.is_empty():
		return {}
	var sid := str(def.get("id", "")).strip_edges()
	if sid.is_empty():
		return {}
	var dur: float = duration
	if dur < 0.0:
		dur = float(def.get("duration", 5.0))
	dur = maxf(dur, 0.0)
	var list: Array = _list_mut(target_key)
	var stack_max: int = maxi(1, int(def.get("stack_max", 1)))
	# Same id: refresh duration to max; stack_max>1 increments stacks (else stay 1).
	for i in range(list.size()):
		var ex: Variant = list[i]
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		if str((ex as Dictionary).get("id", "")) != sid:
			continue
		var refreshed: Dictionary = ex
		var cur_stacks: int = maxi(1, int(refreshed.get("stacks", 1)))
		_fill_from_def(refreshed, def, dur, source_id)
		refreshed["stack_max"] = stack_max
		if stack_max > 1:
			refreshed["stacks"] = mini(cur_stacks + 1, stack_max)
		else:
			refreshed["stacks"] = 1
		list[i] = refreshed
		_by_target[target_key] = list
		return refreshed.duplicate(true)
	var initial_stacks: int = clampi(maxi(1, int(def.get("stacks", 1))), 1, stack_max)
	var inst := {
		"id": sid,
		"name": str(def.get("name", sid)),
		"kind": _normalize_kind(str(def.get("kind", "buff"))),
		"target": target_key,
		"remaining_sec": dur,
		"duration_max": dur,
		"tick_interval": maxf(float(def.get("tick_interval", 0.0)), 0.0),
		"tick_acc": 0.0,
		"stacks": initial_stacks,
		"stack_max": stack_max,
		"tick_hp": int(def.get("tick_hp", 0)),
		"atk_mul": float(def.get("atk_mul", 1.0)),
		"def_mul": float(def.get("def_mul", 1.0)),
		"atk_add": float(def.get("atk_add", 0.0)),
		"def_add": float(def.get("def_add", 0.0)),
		"move_speed_mul": float(def.get("move_speed_mul", 1.0)),
		"absorb_ratio": float(def.get("absorb_ratio", 0.0)),
		"absorb_max": int(def.get("absorb_max", 0)),
		"hp_per_mp": maxi(int(def.get("hp_per_mp", 0)), 0),
		"source_id": source_id.strip_edges(),
	}
	# Nested mods dict (optional) overlays flat fields.
	var mods_v: Variant = def.get("mods", {})
	if typeof(mods_v) == TYPE_DICTIONARY:
		var mods: Dictionary = mods_v
		if mods.has("atk_mul"):
			inst["atk_mul"] = float(mods.get("atk_mul", 1.0))
		if mods.has("def_mul"):
			inst["def_mul"] = float(mods.get("def_mul", 1.0))
		if mods.has("atk_add"):
			inst["atk_add"] = float(mods.get("atk_add", 0.0))
		if mods.has("def_add"):
			inst["def_add"] = float(mods.get("def_add", 0.0))
		if mods.has("tick_hp"):
			inst["tick_hp"] = int(mods.get("tick_hp", 0))
		if mods.has("move_speed_mul"):
			inst["move_speed_mul"] = float(mods.get("move_speed_mul", 1.0))
		if mods.has("absorb_ratio"):
			inst["absorb_ratio"] = float(mods.get("absorb_ratio", 0.0))
		if mods.has("absorb_max"):
			inst["absorb_max"] = int(mods.get("absorb_max", 0))
		if mods.has("hp_per_mp"):
			inst["hp_per_mp"] = maxi(int(mods.get("hp_per_mp", 0)), 0)
	list.append(inst)
	_by_target[target_key] = list
	return inst.duplicate(true)


func _fill_from_def(inst: Dictionary, def: Dictionary, dur: float, source_id: String) -> void:
	inst["name"] = str(def.get("name", inst.get("name", "")))
	inst["kind"] = _normalize_kind(str(def.get("kind", inst.get("kind", "buff"))))
	inst["remaining_sec"] = dur
	inst["duration_max"] = dur
	inst["tick_interval"] = maxf(float(def.get("tick_interval", inst.get("tick_interval", 0.0))), 0.0)
	# Preserve tick_acc on refresh so DoT/HoT cadence continues.
	# (New applies still start at 0 via apply_status initial dict.)
	inst["tick_hp"] = int(def.get("tick_hp", inst.get("tick_hp", 0)))
	inst["atk_mul"] = float(def.get("atk_mul", inst.get("atk_mul", 1.0)))
	inst["def_mul"] = float(def.get("def_mul", inst.get("def_mul", 1.0)))
	inst["atk_add"] = float(def.get("atk_add", inst.get("atk_add", 0.0)))
	inst["def_add"] = float(def.get("def_add", inst.get("def_add", 0.0)))
	inst["move_speed_mul"] = float(def.get("move_speed_mul", inst.get("move_speed_mul", 1.0)))
	inst["absorb_ratio"] = float(def.get("absorb_ratio", inst.get("absorb_ratio", 0.0)))
	inst["absorb_max"] = int(def.get("absorb_max", inst.get("absorb_max", 0)))
	inst["hp_per_mp"] = maxi(int(def.get("hp_per_mp", inst.get("hp_per_mp", 0))), 0)
	if source_id.strip_edges() != "":
		inst["source_id"] = source_id.strip_edges()
	var mods_v: Variant = def.get("mods", {})
	if typeof(mods_v) == TYPE_DICTIONARY:
		var mods: Dictionary = mods_v
		if mods.has("atk_mul"):
			inst["atk_mul"] = float(mods.get("atk_mul", 1.0))
		if mods.has("def_mul"):
			inst["def_mul"] = float(mods.get("def_mul", 1.0))
		if mods.has("atk_add"):
			inst["atk_add"] = float(mods.get("atk_add", 0.0))
		if mods.has("def_add"):
			inst["def_add"] = float(mods.get("def_add", 0.0))
		if mods.has("tick_hp"):
			inst["tick_hp"] = int(mods.get("tick_hp", 0))
		if mods.has("move_speed_mul"):
			inst["move_speed_mul"] = float(mods.get("move_speed_mul", 1.0))
		if mods.has("absorb_ratio"):
			inst["absorb_ratio"] = float(mods.get("absorb_ratio", 0.0))
		if mods.has("absorb_max"):
			inst["absorb_max"] = int(mods.get("absorb_max", 0))
		if mods.has("hp_per_mp"):
			inst["hp_per_mp"] = maxi(int(mods.get("hp_per_mp", 0)), 0)


func clear_status(target_key: String, status_id: String) -> void:
	target_key = target_key.strip_edges()
	status_id = status_id.strip_edges()
	if target_key.is_empty() or status_id.is_empty() or not _by_target.has(target_key):
		return
	var list: Array = _by_target[target_key]
	var kept: Array = []
	for ex in list:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		if str((ex as Dictionary).get("id", "")) == status_id:
			continue
		kept.append(ex)
	if kept.is_empty():
		_by_target.erase(target_key)
	else:
		_by_target[target_key] = kept


func clear_all(target_key: String) -> void:
	target_key = target_key.strip_edges()
	if target_key.is_empty():
		return
	if _by_target.has(target_key):
		_by_target.erase(target_key)


func clear_harmful(target_key: String) -> void:
	target_key = target_key.strip_edges()
	if target_key.is_empty() or not _by_target.has(target_key):
		return
	var list: Array = _by_target[target_key]
	var kept: Array = []
	for ex in list:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		var kind := str((ex as Dictionary).get("kind", ""))
		if kind == "debuff" or kind == "dot":
			continue
		kept.append(ex)
	if kept.is_empty():
		_by_target.erase(target_key)
	else:
		_by_target[target_key] = kept


func clear_all_on_death(target_key: String) -> void:
	clear_all(target_key)


func clear_everything() -> void:
	_by_target.clear()


func clear_non_player() -> void:
	var keep: Array = snapshot_statuses("player")
	_by_target.clear()
	for s in keep:
		if typeof(s) == TYPE_DICTIONARY:
			apply_status("player", s, float(s.get("remaining_sec", 0.0)), str(s.get("source_id", "")))


## Snapshot for HUD / status_update actions.
func snapshot_statuses(target_key: String) -> Array:
	target_key = target_key.strip_edges()
	if target_key.is_empty() or not _by_target.has(target_key):
		return []
	var out: Array = []
	for ex in _by_target[target_key]:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ex
		out.append({
			"id": str(d.get("id", "")),
			"name": str(d.get("name", "")),
			"kind": str(d.get("kind", "")),
			"remaining_sec": float(d.get("remaining_sec", 0.0)),
			"duration_max": float(d.get("duration_max", d.get("remaining_sec", 0.0))),
			"stacks": int(d.get("stacks", 1)),
			"tick_hp": int(d.get("tick_hp", 0)),
			"atk_mul": float(d.get("atk_mul", 1.0)),
			"def_mul": float(d.get("def_mul", 1.0)),
			"atk_add": float(d.get("atk_add", 0.0)),
			"def_add": float(d.get("def_add", 0.0)),
			"move_speed_mul": float(d.get("move_speed_mul", 1.0)),
			"absorb_ratio": float(d.get("absorb_ratio", 0.0)),
			"absorb_max": int(d.get("absorb_max", 0)),
			"hp_per_mp": int(d.get("hp_per_mp", 0)),
		})
	return out


func has_status(target_key: String, status_id: String) -> bool:
	status_id = status_id.strip_edges()
	for s in snapshot_statuses(target_key):
		if str(s.get("id", "")) == status_id:
			return true
	return false


## Full runtime instance (incl. absorb fields) or {}.
func get_status(target_key: String, status_id: String) -> Dictionary:
	target_key = target_key.strip_edges()
	status_id = status_id.strip_edges()
	if target_key.is_empty() or status_id.is_empty() or not _by_target.has(target_key):
		return {}
	for ex in _by_target[target_key]:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		if str((ex as Dictionary).get("id", "")) == status_id:
			return (ex as Dictionary).duplicate(true)
	return {}


func get_mods(target_key: String) -> Dictionary:
	var atk_mul := 1.0
	var def_mul := 1.0
	var atk_add := 0.0
	var def_add := 0.0
	var move_speed_mul := 1.0
	for s in snapshot_statuses(target_key):
		atk_mul *= float(s.get("atk_mul", 1.0))
		def_mul *= float(s.get("def_mul", 1.0))
		atk_add += float(s.get("atk_add", 0.0))
		def_add += float(s.get("def_add", 0.0))
		move_speed_mul *= float(s.get("move_speed_mul", 1.0))
	return {
		"atk_mul": atk_mul,
		"def_mul": def_mul,
		"atk_add": atk_add,
		"def_add": def_add,
		"move_speed_mul": move_speed_mul,
	}




## Combined move speed multiplier from statuses (1.0 = normal).
func move_speed_mul(target_key: String) -> float:
	var m: Dictionary = get_mods(target_key)
	var v: float = float(m.get("move_speed_mul", 1.0))
	if v < 0.25:
		return 0.25
	if v > 3.0:
		return 3.0
	return v

func effective_atk(base: int, target_key: String) -> int:
	var m: Dictionary = get_mods(target_key)
	var v: float = (float(base) + float(m.get("atk_add", 0.0))) * float(m.get("atk_mul", 1.0))
	return maxi(1, int(round(v)))


func effective_def(base: int, target_key: String) -> int:
	var m: Dictionary = get_mods(target_key)
	var v: float = (float(base) + float(m.get("def_add", 0.0))) * float(m.get("def_mul", 1.0))
	return maxi(0, int(round(v)))


## Advance timers; mutate HP via stats; return combat action dicts.
## Emits damage/heal + status_update for changed targets; kill_npc / player_died as needed.
func tick_statuses(delta: float, stats) -> Array:
	delta = maxf(delta, 0.0)
	if delta <= 0.0 or stats == null:
		return []
	var actions: Array = []
	var keys: Array = _by_target.keys()
	var dirty: Dictionary = {}  # target_key -> true
	for key_v in keys:
		var target_key := str(key_v)
		if not _by_target.has(target_key):
			continue
		var list: Array = _by_target[target_key]
		var kept: Array = []
		for ex in list:
			if typeof(ex) != TYPE_DICTIONARY:
				continue
			var st: Dictionary = ex
			var rem: float = float(st.get("remaining_sec", 0.0)) - delta
			st["remaining_sec"] = rem
			var interval: float = float(st.get("tick_interval", 0.0))
			var tick_hp: int = int(st.get("tick_hp", 0))
			if interval > 0.0 and tick_hp != 0 and rem + delta > 0.0:
				var acc: float = float(st.get("tick_acc", 0.0)) + delta
				while acc >= interval and rem + (acc - interval) > -0.0001:
					acc -= interval
					var stacks_n: int = maxi(1, int(st.get("stacks", 1)))
					var tick_actions: Array = _apply_tick_hp(target_key, tick_hp * stacks_n, stats)
					if not tick_actions.is_empty():
						actions.append_array(tick_actions)
						dirty[target_key] = true
					# Target may have died / been removed mid-tick.
					if target_key != "player" and (stats.npcs == null or not stats.npcs.has(target_key)):
						rem = -1.0
						break
					if target_key == "player" and stats.has_method("player_alive") and not stats.player_alive():
						rem = -1.0
						break
				st["tick_acc"] = acc
			if rem > 0.0:
				kept.append(st)
			else:
				dirty[target_key] = true
		if kept.is_empty():
			_by_target.erase(target_key)
		else:
			_by_target[target_key] = kept
		if dirty.has(target_key) or not kept.is_empty():
			# Always snapshot when we touched this target this frame.
			pass
	# Snapshot every target that still has statuses (HUD remaining) plus cleared dirty.
	var snap_keys: Dictionary = {}
	for dk in dirty.keys():
		snap_keys[str(dk)] = true
	for k in _by_target.keys():
		snap_keys[str(k)] = true
	for sk in snap_keys.keys():
		actions.append(_status_update_action(str(sk)))
	return actions


func _apply_tick_hp(target_key: String, tick_hp: int, stats) -> Array:
	var actions: Array = []
	if tick_hp == 0:
		return actions
	if target_key == "player":
		var p: Dictionary = stats.player
		if typeof(p) != TYPE_DICTIONARY or p.is_empty():
			return actions
		var hp_max: int = int(p.get("hp_max", 1))
		var before: int = int(p.get("hp", 0))
		if before <= 0:
			return actions
		var hp: int = clampi(before + tick_hp, 0, hp_max)
		p["hp"] = hp
		stats.player = p
		var gained: int = hp - before
		if gained > 0:
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
		elif gained < 0:
			actions.append({
				"type": "damage",
				"target": "player",
				"id": "player",
				"amount": -gained,
				"hp": hp,
				"hp_max": hp_max,
			})
			if hp <= 0:
				actions.append({"type": "player_died"})
				actions.append({"type": "system_message", "text": "你被击败了……"})
				clear_all_on_death("player")
		return actions
	# NPC
	if not stats.npcs.has(target_key):
		return actions
	var st: Dictionary = stats.npcs[target_key]
	var hp_max_n: int = int(st.get("hp_max", 1))
	var before_n: int = int(st.get("hp", 0))
	if before_n <= 0:
		return actions
	var hp_n: int = clampi(before_n + tick_hp, 0, hp_max_n)
	st["hp"] = hp_n
	stats.npcs[target_key] = st
	var delta_hp: int = hp_n - before_n
	if delta_hp < 0:
		actions.append({
			"type": "damage",
			"target": "npc",
			"id": target_key,
			"amount": -delta_hp,
			"hp": hp_n,
			"hp_max": hp_max_n,
		})
	elif delta_hp > 0:
		# Client heal path is player-only; amount 0 damage syncs bar without chat spam.
		actions.append({
			"type": "damage",
			"target": "npc",
			"id": target_key,
			"amount": 0,
			"hp": hp_n,
			"hp_max": hp_max_n,
		})
	if hp_n <= 0:
		var death_cell := {"x": 0, "y": 0}
		var has_death_cell := false
		if stats.has_method("get_npc_cell"):
			var dc: Vector2i = stats.get_npc_cell(target_key)
			if dc.x > -9990:
				death_cell = {"x": dc.x, "y": dc.y}
				has_death_cell = true
		if stats.has_method("remove_npc"):
			stats.remove_npc(target_key)
		else:
			clear_all_on_death(target_key)
			stats.npcs.erase(target_key)
		var kill_act := {"type": "kill_npc", "npc_id": target_key}
		if has_death_cell:
			kill_act["cell"] = death_cell
		actions.append(kill_act)
		actions.append({"type": "system_message", "text": "击败了敌人。"})
	return actions


func status_update_action(target_key: String) -> Dictionary:
	return _status_update_action(target_key)


func _status_update_action(target_key: String) -> Dictionary:
	var act := {
		"type": "status_update",
		"target": "player" if target_key == "player" else "npc",
		"statuses": snapshot_statuses(target_key),
	}
	if target_key != "player":
		act["id"] = target_key
	return act


func _list_mut(target_key: String) -> Array:
	if _by_target.has(target_key) and typeof(_by_target[target_key]) == TYPE_ARRAY:
		return _by_target[target_key]
	var list: Array = []
	_by_target[target_key] = list
	return list


func _normalize_kind(kind: String) -> String:
	kind = kind.strip_edges().to_lower()
	match kind:
		"buff", "debuff", "dot", "hot":
			return kind
		_:
			return "buff"
