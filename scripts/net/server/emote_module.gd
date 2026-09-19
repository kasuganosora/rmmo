extends RefCounted
## Domain module: text emotes (catalog, trigger).

var ctrl
func _init(c):
	ctrl = c

const EMOTE_COOLDOWN_SEC := 1.5
const EMOTE_DURATION_SEC := 2.0
const EMOTE_CATALOG := {
	"wave": {"label": "挥手", "text": "（挥手）"},
	"laugh": {"label": "大笑", "text": "哈哈哈"},
	"bow": {"label": "鞠躬", "text": "（鞠躬）"},
	"cry": {"label": "哭泣", "text": "（呜呜）"},
	"angry": {"label": "生气", "text": "（哼！）"},
	"love": {"label": "爱心", "text": "❤"},
	"cheer": {"label": "加油", "text": "（加油！）"},
	"think": {"label": "思考", "text": "（思考中…）"},
	"shrug": {"label": "耸肩", "text": "（耸肩）"},
	"clap": {"label": "鼓掌", "text": "（啪啪啪）"},
	"sleepy": {"label": "困倦", "text": "（打哈欠）"},
	"wow": {"label": "惊讶", "text": "（哇！）"},
}

func emote_catalog() -> Array:
	## Fixed catalog rows: [{id, label, text}, ...]
	var out: Array = []
	for eid in EMOTE_CATALOG.keys():
		var row: Dictionary = EMOTE_CATALOG[eid]
		out.append({
			"id": str(eid),
			"label": str(row.get("label", eid)),
			"text": str(row.get("text", "")),
		})
	return out



func try_emote(emote_id: String) -> Dictionary:
	## Broadcast-ready text emote bubble above actor. Rate-limited server-side.
	var actions: Array = []
	emote_id = str(emote_id).strip_edges()
	if emote_id.is_empty() or not EMOTE_CATALOG.has(emote_id):
		actions.append({"type": "system_message", "text": "未知表情。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var now: float = ctrl._party_clock()
	if now < ctrl._emote_cd_until:
		actions.append({"type": "system_message", "text": "表情冷却中。"})
		return {"ok": false, "reason": "cooldown", "actions": actions}
	var def: Dictionary = EMOTE_CATALOG[emote_id]
	var bubble = str(def.get("text", "")).strip_edges()
	if bubble.is_empty():
		bubble = "（%s）" % str(def.get("label", emote_id))
	ctrl._emote_cd_until = now + EMOTE_COOLDOWN_SEC
	var actor_id = ctrl._party_self_id()
	actions.append({
		"type": "emote",
		"actor_id": actor_id,
		"emote_id": emote_id,
		"text": bubble,
		"duration_sec": EMOTE_DURATION_SEC,
	})
	return {"ok": true, "actions": actions}

