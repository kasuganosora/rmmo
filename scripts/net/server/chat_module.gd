extends RefCounted
## Domain module: chat (send).

var ctrl
func _init(c):
	ctrl = c

const NEARBY_CHAT_RANGE := 12  # Chebyshev cells

func try_chat(channel: String, text: String, whisper_to: String = "") -> Dictionary:
	var actions: Array = []
	channel = str(channel).strip_edges().to_lower()
	text = str(text).strip_edges()
	whisper_to = str(whisper_to).strip_edges()
	if text.is_empty():
		return {"ok": false, "reason": "empty", "actions": actions}
	var speaker = ctrl._party_self_name()
	var speaker_id = ctrl._party_self_id()
	match channel:
		"whisper", "w", "tell":
			channel = "whisper"
			if whisper_to.is_empty():
				actions.append({"type": "system_message", "text": "私聊格式：/w 名字 内容"})
				return {"ok": false, "reason": "no_target", "actions": actions}
			var tid = ctrl.find_remote_by_name(whisper_to)
			if tid.is_empty() and ctrl._remote_players.has(whisper_to):
				tid = whisper_to
			if tid.is_empty():
				actions.append({"type": "system_message", "text": "找不到玩家【%s】。" % whisper_to})
				return {"ok": false, "reason": "not_found", "actions": actions}
			var target: Dictionary = ctrl._remote_players[tid]
			var tname = str(target.get("name", whisper_to))
			actions.append({
				"type": "chat_message",
				"channel": "whisper",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"target": tname,
				"target_id": tid,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}
		"nearby", "say", "local":
			channel = "nearby"
			actions.append({
				"type": "chat_message",
				"channel": "nearby",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			var pc = ctrl._player_xy()
			var heard = 0
			for rid in ctrl._remote_players.keys():
				var d: Variant = ctrl._remote_players[rid]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				var row: Dictionary = d
				var cv: Variant = row.get("cell", {})
				if typeof(cv) != TYPE_DICTIONARY:
					continue
				var rx = int(cv.get("x", -9999))
				var ry = int(cv.get("y", -9999))
				if ctrl._chebyshev(pc.x, pc.y, rx, ry) > NEARBY_CHAT_RANGE:
					continue
				heard += 1
				var rname = str(row.get("name", rid))
				# Delivery echo: remote "hears" the line (shell AOI stub).
				actions.append({
					"type": "chat_message",
					"channel": "nearby",
					"speaker": speaker,
					"speaker_id": speaker_id,
					"text": text,
					"self": false,
					"heard_by": rname,
					"heard_by_id": str(rid),
				})
			if heard == 0:
				actions.append({"type": "system_message", "text": "附近没有人听到。"})
			return {"ok": true, "actions": actions}
		"party":
			if not ctrl.in_party():
				actions.append({"type": "system_message", "text": "你尚未组队，队伍频道仅本地可见。"})
			actions.append({
				"type": "chat_message",
				"channel": "party",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}
		"all", "shout", "yell":
			channel = "all"
			actions.append({
				"type": "chat_message",
				"channel": "all",
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}
		_:
			# clan / trade / alliance — local echo only for now
			actions.append({
				"type": "chat_message",
				"channel": channel,
				"speaker": speaker,
				"speaker_id": speaker_id,
				"text": text,
				"self": true,
			})
			return {"ok": true, "actions": actions}




