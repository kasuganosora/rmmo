extends RefCounted
## Mock server domain: runtime.

var ctrl
const Config = preload("res://scripts/net/server/mock_config.gd")

## Accumulator for adjacent-hostile tick counter-attacks.
## @server-state
var _combat_tick_acc: float = 0.0

## Separate AI step rate for chase (≈ NPC step_duration).
## @server-state
var _ai_tick_acc: float = 0.0

## @server-state
var _pending_tick_actions: Array = []


func _init(owner):
	ctrl = owner

## @server-constant
const COMBAT_TICK_INTERVAL := 1.5

## @server-constant
const AI_TICK_INTERVAL := 0.45

## @server-api
func _tick_frame(delta:float)->void:
	var ai_interval := Config.number("ai_tick_interval_sec")
	var combat_interval := Config.number("combat_tick_interval_sec")
	ctrl._tick_weather(delta)
	if ctrl.combat_engine == null or ctrl.combat_stats == null:
		return
	if ctrl.player_cell.x <= -9990:
		return
	# Cast / channel advances every frame (finer than ambient combat tick).
	if ctrl.combat_engine.has_method("tick_cast") and ctrl.combat_engine.is_casting():
		var cast_actions: Array = ctrl.combat_engine.tick_cast(delta)
		if not cast_actions.is_empty():
			var cast_result := {"ok": true, "actions": cast_actions}
			cast_result = ctrl._finalize_combat_result(cast_result)
			var ca_v: Variant = cast_result.get("actions", [])
			if typeof(ca_v) == TYPE_ARRAY and not (ca_v as Array).is_empty():
				ctrl._pending_tick_actions.append_array(ca_v)
	# NPC casts (hostile cast_time skills).
	if ctrl.combat_engine.has_method("tick_npc_casts"):
		var npc_cast_actions: Array = ctrl.combat_engine.tick_npc_casts(delta)
		if not npc_cast_actions.is_empty():
			ctrl._patch_npc_cast_skill_names(npc_cast_actions)
			var npc_cast_result := {"ok": true, "actions": npc_cast_actions}
			npc_cast_result = ctrl._finalize_combat_result(npc_cast_result)
			var nca_v: Variant = npc_cast_result.get("actions", [])
			if typeof(nca_v) == TYPE_ARRAY and not (nca_v as Array).is_empty():
				ctrl._pending_tick_actions.append_array(nca_v)
	# Mob AI ticks (idle wander / chase / return_home / npc_move).
	ctrl._ai_tick_acc += delta
	if ctrl._ai_tick_acc >= ai_interval:
		var ai_dt: float = ctrl._ai_tick_acc
		ctrl._ai_tick_acc = 0.0
		var ai_actions: Array = ctrl._tick_mob_ai(ai_dt)
		if not ai_actions.is_empty():
			ctrl._pending_tick_actions.append_array(ai_actions)
		var remote_acts: Array = ctrl._tick_remote_patrol(ai_dt)
		if not remote_acts.is_empty():
			ctrl._pending_tick_actions.append_array(remote_acts)
		var pet_acts: Array = ctrl._tick_pet_follow(ai_dt)
		pet_acts.append_array(ctrl._tick_pet_combat(ai_dt))
		if not pet_acts.is_empty():
			ctrl._pending_tick_actions.append_array(pet_acts)
	# Dead-mob respawn timers (independent of AI step rate).
	var respawn_actions: Array = ctrl._tick_npc_respawns()
	if not respawn_actions.is_empty():
		ctrl._pending_tick_actions.append_array(respawn_actions)
	var gather_respawn_actions: Array = ctrl._tick_gather_respawns()
	if not gather_respawn_actions.is_empty():
		ctrl._pending_tick_actions.append_array(gather_respawn_actions)
	var fish_respawn_actions: Array = ctrl._tick_fish_respawns()
	if not fish_respawn_actions.is_empty():
		ctrl._pending_tick_actions.append_array(fish_respawn_actions)
	ctrl._tick_sit(delta)
	ctrl._tick_auto_potion(delta)
	ctrl._tick_dps_meter(delta)
	ctrl._combat_tick_acc += delta
	if ctrl._combat_tick_acc < combat_interval:
		return
	ctrl._combat_tick_acc = 0.0
	# Tick result is buffered; client polls via poll_combat_tick().
	var result: Dictionary = ctrl.combat_engine.tick(ctrl.player_cell.x, ctrl.player_cell.y, combat_interval)
	result = ctrl._finalize_combat_result(result)
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) == TYPE_ARRAY and not (actions_v as Array).is_empty():
		ctrl._pending_tick_actions.append_array(actions_v)
