extends RefCounted
## Client-side combat-only ring buffer (last N short Chinese lines).
## Fed from world when applying damage / heal / miss / crit / kill — not a full chat.
## Entries are {kind, text} with kind in damage|heal|miss|kill|other.

const MAX_LINES := 50
const KINDS := ["damage", "heal", "miss", "kill", "other"]

## Stored buffer: Array of {kind: String, text: String}
var _entries: Array = []


func push(line: String) -> void:
	## Compat: infer kind from Chinese formatter prefixes.
	line = line.strip_edges()
	if line.is_empty():
		return
	push_typed(infer_kind(line), line)


func push_typed(kind: String, line: String) -> void:
	line = line.strip_edges()
	if line.is_empty():
		return
	kind = normalize_kind(kind)
	_entries.append({"kind": kind, "text": line})
	while _entries.size() > MAX_LINES:
		_entries.remove_at(0)


func clear() -> void:
	_entries.clear()


func size() -> int:
	return _entries.size()


func lines() -> PackedStringArray:
	## All stored texts (unfiltered) — buffer content, not display filter.
	var out := PackedStringArray()
	for e in _entries:
		out.append(str(e.get("text", "")))
	return out


func entries() -> Array:
	## Shallow copy of typed entries.
	var out: Array = []
	for e in _entries:
		out.append({"kind": str(e.get("kind", "other")), "text": str(e.get("text", ""))})
	return out


func latest() -> String:
	if _entries.is_empty():
		return ""
	return str(_entries[_entries.size() - 1].get("text", ""))


func latest_kind() -> String:
	if _entries.is_empty():
		return ""
	return str(_entries[_entries.size() - 1].get("kind", "other"))


## Filter display by kind visibility. "other" is always shown.
## flags: optional Dictionary with keys show_damage/show_heal/show_miss/show_kill (default true).
func filtered_lines(flags: Dictionary = {}) -> PackedStringArray:
	var show_damage := bool(flags.get("show_damage", flags.get("combat_log_show_damage", true)))
	var show_heal := bool(flags.get("show_heal", flags.get("combat_log_show_heal", true)))
	var show_miss := bool(flags.get("show_miss", flags.get("combat_log_show_miss", true)))
	var show_kill := bool(flags.get("show_kill", flags.get("combat_log_show_kill", true)))
	var out := PackedStringArray()
	for e in _entries:
		var k := str(e.get("kind", "other"))
		if not _kind_visible(k, show_damage, show_heal, show_miss, show_kill):
			continue
		out.append(str(e.get("text", "")))
	return out


func filtered_entries(flags: Dictionary = {}) -> Array:
	var show_damage := bool(flags.get("show_damage", flags.get("combat_log_show_damage", true)))
	var show_heal := bool(flags.get("show_heal", flags.get("combat_log_show_heal", true)))
	var show_miss := bool(flags.get("show_miss", flags.get("combat_log_show_miss", true)))
	var show_kill := bool(flags.get("show_kill", flags.get("combat_log_show_kill", true)))
	var out: Array = []
	for e in _entries:
		var k := str(e.get("kind", "other"))
		if not _kind_visible(k, show_damage, show_heal, show_miss, show_kill):
			continue
		out.append({"kind": k, "text": str(e.get("text", ""))})
	return out


static func _kind_visible(
	kind: String, show_damage: bool, show_heal: bool, show_miss: bool, show_kill: bool
) -> bool:
	match kind:
		"damage":
			return show_damage
		"heal":
			return show_heal
		"miss":
			return show_miss
		"kill":
			return show_kill
		_:
			return true


static func normalize_kind(kind: String) -> String:
	kind = kind.strip_edges().to_lower()
	if kind in KINDS:
		return kind
	return "other"


static func infer_kind(line: String) -> String:
	line = line.strip_edges()
	if line.is_empty():
		return "other"
	if line == "未命中" or line.begins_with("未命中"):
		return "miss"
	if line.begins_with("击败了"):
		return "kill"
	if line.begins_with("恢复 ") and (line.find("生命") >= 0 or line.find("魔法") >= 0):
		return "heal"
	if line.find("伤害") >= 0 or line.begins_with("暴击") or line.begins_with("受到暴击"):
		return "damage"
	return "other"


## --- Short Chinese formatters (HUD / world may call these) ---

static func line_damage_out(target_name: String, amount: int, crit: bool = false) -> String:
	var name := target_name.strip_edges()
	if name.is_empty():
		name = "敌人"
	if crit:
		return "暴击！%d（%s）" % [maxi(amount, 0), name]
	return "你对%s造成 %d 伤害" % [name, maxi(amount, 0)]


static func line_damage_in(amount: int, crit: bool = false) -> String:
	if crit:
		return "受到暴击！%d" % maxi(amount, 0)
	return "你受到 %d 伤害" % maxi(amount, 0)


static func line_miss() -> String:
	return "未命中"


static func line_heal(amount: int) -> String:
	return "恢复 %d 生命" % maxi(amount, 0)


static func line_mp(amount: int) -> String:
	return "恢复 %d 魔法" % maxi(amount, 0)


static func line_kill(target_name: String) -> String:
	var name := target_name.strip_edges()
	if name.is_empty():
		name = "敌人"
	return "击败了%s" % name


static func line_crit(amount: int) -> String:
	## Bare crit shorthand used when target name is unknown.
	return "暴击！%d" % maxi(amount, 0)
