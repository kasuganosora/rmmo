extends RefCounted
## Domain module: personal DPS meter (session window, player->NPC damage only).

var ctrl
func _init(c):
	ctrl = c

const DPS_IDLE_TIMEOUT := 6.0

func _dps_attacker_is_player(attacker_id: String) -> bool:
	var aid = attacker_id.strip_edges()
	if aid == "" or aid == "player":
		return true
	if ctrl.stats != null and "player_actor_id" in ctrl.stats:
		var sid = str(ctrl.stats.player_actor_id).strip_edges()
		if sid != "" and aid == sid:
			return true
	return false



func reset_dps_fight() -> void:
	ctrl._dps_fight = {
		"active": false,
		"total_damage": 0,
		"fight_start": 0.0,
		"last_hit_time": 0.0,
	}
	ctrl._dps_last_snap = {"dps": 0.0, "total": 0, "elapsed": 0.0, "active": false}



func snapshot_dps() -> Dictionary:
	var s: Dictionary = ctrl._dps_last_snap.duplicate(true)
	s["type"] = "dps_update"
	# Live window while active.
	if bool(ctrl._dps_fight.get("active", false)):
		var elapsed: float = maxf(0.0, ctrl._dps_clock - float(ctrl._dps_fight.get("fight_start", 0.0)))
		var total: int = int(ctrl._dps_fight.get("total_damage", 0))
		var dps: float = float(total) / maxf(1.0, elapsed)
		s = {"type": "dps_update", "dps": dps, "total": total, "elapsed": elapsed, "active": true}
	return s



func _dps_update_action(active: bool) -> Dictionary:
	var total: int = int(ctrl._dps_fight.get("total_damage", 0))
	var start: float = float(ctrl._dps_fight.get("fight_start", 0.0))
	var last: float = float(ctrl._dps_fight.get("last_hit_time", start))
	var end_t: float = last if not active else ctrl._dps_clock
	var elapsed: float = maxf(0.0, end_t - start)
	var dps: float = float(total) / maxf(1.0, elapsed)
	var act = {
		"type": "dps_update",
		"dps": dps,
		"total": total,
		"elapsed": elapsed,
		"active": active,
	}
	ctrl._dps_last_snap = {
		"dps": dps,
		"total": total,
		"elapsed": elapsed,
		"active": active,
	}
	return act



func note_dps_hit(dealt: int) -> Dictionary:
	dealt = maxi(0, int(dealt))
	if dealt <= 0:
		return {}
	var now: float = ctrl._dps_clock
	if not bool(ctrl._dps_fight.get("active", false)):
		ctrl._dps_fight["active"] = true
		ctrl._dps_fight["total_damage"] = 0
		ctrl._dps_fight["fight_start"] = now
	ctrl._dps_fight["total_damage"] = int(ctrl._dps_fight.get("total_damage", 0)) + dealt
	ctrl._dps_fight["last_hit_time"] = now
	ctrl._dps_fight["active"] = true
	return _dps_update_action(true)



func tick_dps(delta: float) -> Array:
	ctrl._dps_clock += maxf(0.0, float(delta))
	if not bool(ctrl._dps_fight.get("active", false)):
		return []
	var last: float = float(ctrl._dps_fight.get("last_hit_time", 0.0))
	if ctrl._dps_clock - last < DPS_IDLE_TIMEOUT:
		return []
	# Finalize: keep last snapshot values, mark inactive.
	var act: Dictionary = _dps_update_action(false)
	ctrl._dps_fight["active"] = false
	# Keep totals in _dps_fight until next hit resets them in note_dps_hit.
	return [act]


