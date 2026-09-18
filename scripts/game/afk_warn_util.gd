extends RefCounted
## Idle AFK warn helpers (client-only; no kick / logout).


## True when idle meets threshold and we have not warned this streak.
## threshold_sec <= 0 means disabled.
static func should_warn(idle_sec: float, threshold_sec: float, already_warned: bool) -> bool:
	if threshold_sec <= 0.0:
		return false
	if already_warned:
		return false
	return idle_sec >= threshold_sec


## Valid minutes: 0 (off) or 5–60 inclusive.
static func clamp_minutes(v: int) -> int:
	if int(v) <= 0:
		return 0
	return clampi(int(v), 5, 60)


static func threshold_sec_from_minutes(minutes: int) -> float:
	var m := clamp_minutes(minutes)
	if m <= 0:
		return 0.0
	return float(m) * 60.0
