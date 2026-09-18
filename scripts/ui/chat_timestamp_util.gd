extends RefCounted
## Pure helpers for optional [HH:MM:SS] chat line prefixes.

## Zero-padded [HH:MM:SS] from a time dict (hour/minute/second).
static func format(time_dict: Dictionary = {}) -> String:
	var t: Dictionary = time_dict
	if t.is_empty():
		t = Time.get_time_dict_from_system()
	var h: int = int(t.get("hour", 0))
	var m: int = int(t.get("minute", 0))
	var s: int = int(t.get("second", 0))
	return "[%02d:%02d:%02d]" % [h, m, s]


## Current local system time as [HH:MM:SS].
static func format_now() -> String:
	return format(Time.get_time_dict_from_system())


## Whether a string looks like [HH:MM:SS].
static func looks_like_ts(s: String) -> bool:
	if s.length() != 10:
		return false
	if s[0] != "[" or s[9] != "]" or s[3] != ":" or s[6] != ":":
		return false
	for i in [1, 2, 4, 5, 7, 8]:
		if not (s[i] >= "0" and s[i] <= "9"):
			return false
	return true
