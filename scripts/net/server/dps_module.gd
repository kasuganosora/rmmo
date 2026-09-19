extends RefCounted
## Domain module: DPS meter (snapshot, tick).

var ctrl
func _init(c):
	ctrl = c

func snapshot_dps() -> Dictionary:
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("snapshot_dps"):
		return ctrl.combat_engine.snapshot_dps()
	return {"type": "dps_update", "dps": 0.0, "total": 0, "elapsed": 0.0, "active": false}



func _tick_dps_meter(delta: float) -> void:
	if ctrl.combat_engine == null or not ctrl.combat_engine.has_method("tick_dps"):
		return
	var acts: Array = ctrl.combat_engine.tick_dps(delta)
	if not acts.is_empty():
		ctrl._pending_tick_actions.append_array(acts)


