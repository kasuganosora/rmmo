extends RefCounted
## Personal mailbox (MockServer session only; no disk persistence).
## Message shape: {id, from, to, subject, body, gold, items:[{id,qty}], read, claimed, created_at}

const MAX_MAIL := 30

var _messages: Array = []
var _next_id: int = 1


func clear() -> void:
	_messages.clear()
	_next_id = 1


func count() -> int:
	return _messages.size()


func max_mail() -> int:
	return MAX_MAIL


func is_full() -> bool:
	return _messages.size() >= MAX_MAIL


func find_index(mail_id: String) -> int:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return -1
	for i in range(_messages.size()):
		var m: Variant = _messages[i]
		if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) == mail_id:
			return i
	return -1


func get_mail(mail_id: String) -> Dictionary:
	var idx := find_index(mail_id)
	if idx < 0:
		return {}
	return (_messages[idx] as Dictionary).duplicate(true)


## Append a message. items: Array of {id, qty}. Returns {ok, reason, mail}.
func try_add(
	from_name: String,
	to_name: String,
	subject: String,
	body: String,
	gold: int = 0,
	items: Array = []
) -> Dictionary:
	from_name = str(from_name).strip_edges()
	to_name = str(to_name).strip_edges()
	subject = str(subject).strip_edges()
	body = str(body)
	gold = maxi(int(gold), 0)
	if from_name.is_empty() or to_name.is_empty():
		return {"ok": false, "reason": "invalid", "mail": {}}
	if subject.is_empty():
		subject = "（无主题）"
	if is_full():
		return {"ok": false, "reason": "full", "mail": {}}
	var clean_items: Array = []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var iid := str(it.get("id", it.get("item_id", ""))).strip_edges()
		var q: int = int(it.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		clean_items.append({"id": iid, "qty": q})
	var mid := "mail_%d" % _next_id
	_next_id += 1
	var created_at: int = int(Time.get_unix_time_from_system())
	var mail := {
		"id": mid,
		"from": from_name,
		"to": to_name,
		"subject": subject,
		"body": body,
		"gold": gold,
		"items": clean_items,
		"read": false,
		"claimed": false,
		"created_at": created_at,
	}
	# No attachments → already claimed.
	if gold <= 0 and clean_items.is_empty():
		mail["claimed"] = true
	_messages.append(mail)
	return {"ok": true, "reason": "", "mail": mail.duplicate(true)}


func try_mark_read(mail_id: String) -> Dictionary:
	var idx := find_index(mail_id)
	if idx < 0:
		return {"ok": false, "reason": "not_found"}
	var m: Dictionary = _messages[idx]
	m["read"] = true
	_messages[idx] = m
	return {"ok": true, "reason": "", "mail": m.duplicate(true)}


func try_mark_claimed(mail_id: String) -> Dictionary:
	var idx := find_index(mail_id)
	if idx < 0:
		return {"ok": false, "reason": "not_found"}
	var m: Dictionary = _messages[idx]
	if bool(m.get("claimed", false)):
		return {"ok": false, "reason": "already_claimed", "mail": m.duplicate(true)}
	m["claimed"] = true
	m["read"] = true
	_messages[idx] = m
	return {"ok": true, "reason": "", "mail": m.duplicate(true)}


func try_delete(mail_id: String) -> Dictionary:
	var idx := find_index(mail_id)
	if idx < 0:
		return {"ok": false, "reason": "not_found"}
	var m: Dictionary = (_messages[idx] as Dictionary).duplicate(true)
	_messages.remove_at(idx)
	return {"ok": true, "reason": "", "mail": m}


func snapshot() -> Array:
	var out: Array = []
	for m in _messages:
		if typeof(m) == TYPE_DICTIONARY:
			out.append((m as Dictionary).duplicate(true))
	return out


func snapshot_state() -> Dictionary:
	var mails: Array = snapshot()
	return {
		"mails": mails,
		"count": mails.size(),
		"max_mail": MAX_MAIL,
	}
