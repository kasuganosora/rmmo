extends RefCounted
## Pure helpers for the target-bar threat / aggro chip (no nodes).

const LABEL_YOU := "仇恨"
const LABEL_OTHER := "无仇恨"

## Gold/red when you are victim; muted gray when target exists but you are not.
const COLOR_YOU := Color(1.0, 0.72, 0.28, 1.0)
const COLOR_OTHER := Color(0.55, 0.55, 0.58, 1.0)


## Chip caption for hostile target bar.
static func chip_text(threat_you: bool) -> String:
	return LABEL_YOU if threat_you else LABEL_OTHER


static func chip_color(threat_you: bool) -> Color:
	return COLOR_YOU if threat_you else COLOR_OTHER


## Hide chip when no hostile target selected.
static func should_show(has_hostile_target: bool) -> bool:
	return has_hostile_target


## Normalize a server threat snapshot / threat_update action.
## Returns {threat_you:bool, threat_rank:int, threat_pct:float, victim_id:String, npc_id:String}.
static func normalize(snap: Dictionary) -> Dictionary:
	if typeof(snap) != TYPE_DICTIONARY or snap.is_empty():
		return {
			"threat_you": false,
			"threat_rank": 0,
			"threat_pct": 0.0,
			"victim_id": "",
			"npc_id": "",
		}
	return {
		"threat_you": bool(snap.get("threat_you", false)),
		"threat_rank": int(snap.get("threat_rank", 0)),
		"threat_pct": float(snap.get("threat_pct", 0.0)),
		"victim_id": str(snap.get("victim_id", "")).strip_edges(),
		"npc_id": str(snap.get("npc_id", snap.get("id", ""))).strip_edges(),
	}


## Build threat fields from hate_list + victim_id + player actor id (pure).
## hate_sorted: Array[{id, threat, ...}] threat descending preferred.
static func compute_from_hate(
	player_actor_id: String,
	victim_id: String,
	hate_sorted: Array,
	npc_id: String = ""
) -> Dictionary:
	var you := player_actor_id.strip_edges()
	if you.is_empty():
		you = "player"
	var vid := victim_id.strip_edges()
	var threat_you := (not vid.is_empty()) and vid == you
	var your_threat := 0.0
	var top_threat := 0.0
	var rank := 0
	var i := 0
	for e in hate_sorted:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		i += 1
		var eid := str((e as Dictionary).get("id", "")).strip_edges()
		var t: float = float((e as Dictionary).get("threat", 0.0))
		if i == 1:
			top_threat = t
		if eid == you:
			your_threat = t
			rank = i
	var pct := 0.0
	if top_threat > 0.0 and your_threat > 0.0:
		pct = (your_threat / top_threat) * 100.0
	return {
		"type": "threat_update",
		"npc_id": npc_id.strip_edges(),
		"threat_you": threat_you,
		"threat_rank": rank,
		"threat_pct": pct,
		"victim_id": vid,
	}
