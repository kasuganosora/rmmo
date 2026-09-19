extends RefCounted
## Domain module: player combat state (stealth, mount, in-combat, chase breaking).

var ctrl
func _init(c):
	ctrl = c

func player_has_stealth() -> bool:
	return ctrl.stats != null and ctrl.stats.statuses != null and ctrl.stats.statuses.has_status("player", "stealth")



func break_stealth(actions: Array) -> bool:
	if not player_has_stealth():
		return false
	ctrl.stats.statuses.clear_status("player", "stealth")
	actions.append(ctrl.stats.statuses.status_update_action("player"))
	return true



func player_is_mounted() -> bool:
	return ctrl.stats != null and ctrl.stats.statuses != null and ctrl.stats.statuses.has_status("player", "mounted")



func player_in_combat() -> bool:
	if bool(ctrl._dps_fight.get("active", false)):
		return true
	if ctrl.stats == null:
		return false
	var actor = "player"
	if "player_actor_id" in ctrl.stats:
		var aid = str(ctrl.stats.player_actor_id).strip_edges()
		if aid != "":
			actor = aid
	if typeof(ctrl.stats.npc_ai) == TYPE_DICTIONARY:
		for nid_v in ctrl.stats.npc_ai.keys():
			var nid = str(nid_v)
			var ai: Dictionary = ctrl.stats.npc_ai[nid]
			var chase = str(ai.get("chase_target", "")).strip_edges()
			if chase == "player" or chase == actor or (chase != "" and str(ai.get("ai_state", "")) == "chase"):
				return true
			if ctrl.stats.has_method("get_hate_list"):
				for e in ctrl.stats.get_hate_list(nid, false):
					if typeof(e) != TYPE_DICTIONARY:
						continue
					var hid = str((e as Dictionary).get("id", "")).strip_edges()
					if hid == "player" or hid == actor:
						return true
	return false



func break_mount(actions: Array) -> bool:
	if not player_is_mounted():
		return false
	ctrl.stats.statuses.clear_status("player", "mounted")
	actions.append(ctrl.stats.statuses.status_update_action("player"))
	actions.append({"type": "system_message", "text": "已下马。"})
	return true



func _apply_mount_toggle(def: Dictionary, actions: Array) -> void:
	if player_is_mounted():
		break_mount(actions)
		return
	if player_in_combat():
		actions.append({"type": "system_message", "text": "战斗中无法骑乘。"})
		return
	var status_def: Dictionary = ctrl._status_def_from_skill(def)
	if status_def.is_empty():
		status_def = {
			"id": "mounted",
			"name": "骑乘",
			"kind": "buff",
			"duration": 999999.0,
			"tick_interval": 0,
			"move_speed_mul": 1.45,
		}
	if not status_def.has("move_speed_mul"):
		status_def["move_speed_mul"] = 1.45
	ctrl._apply_status_to("player", status_def, "player", actions)
	actions.append({"type": "system_message", "text": "已骑乘。"})



func _break_all_player_chases() -> void:
	if ctrl.stats == null or not ctrl.stats.has_method("clear_chase"):
		return
	var ids: Array = ctrl.stats.npc_ai.keys() if typeof(ctrl.stats.npc_ai) == TYPE_DICTIONARY else []
	for nid_v in ids:
		var nid = str(nid_v)
		if not ctrl.stats.npc_ai.has(nid):
			continue
		var ai: Dictionary = ctrl.stats.npc_ai[nid]
		var chasing = str(ai.get("chase_target", "")) != "" or str(ai.get("ai_state", "")) == "chase"
		if chasing:
			ctrl.stats.clear_chase(nid)


