extends RefCounted
## Pure helpers for the personal fight DPS meter (no nodes).

const IDLE_TIMEOUT_SEC := 6.0
const LABEL_PREFIX := "DPS "


## DPS = total_damage / max(1.0, elapsed_sec).
static func calc_dps(total_damage: int, elapsed_sec: float) -> float:
	return float(maxi(0, total_damage)) / maxf(1.0, elapsed_sec)


static func format_label(dps: float) -> String:
	return "%s%d" % [LABEL_PREFIX, int(round(dps))]


## Normalize a dps_update / snapshot dict.
static func normalize(snap: Dictionary) -> Dictionary:
	if typeof(snap) != TYPE_DICTIONARY or snap.is_empty():
		return {
			"type": "dps_update",
			"dps": 0.0,
			"total": 0,
			"elapsed": 0.0,
			"active": false,
		}
	return {
		"type": "dps_update",
		"dps": float(snap.get("dps", 0.0)),
		"total": int(snap.get("total", 0)),
		"elapsed": float(snap.get("elapsed", 0.0)),
		"active": bool(snap.get("active", false)),
	}


## Whether the HUD should show the meter (setting on + optionally hide when idle).
static func should_show(setting_on: bool, active: bool, show_idle_zero: bool = false) -> bool:
	if not setting_on:
		return false
	if active:
		return true
	return show_idle_zero
