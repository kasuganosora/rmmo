extends RefCounted
## Server-side quest journal (MockServer authoritative).
## Catalog from quests.json; accepted entries carry live objective progress.
## Status: in_progress | ready | completed

const JsonUtil = preload("res://scripts/util/json_util.gd")

const DATA_PATHS: Array[String] = [
	"combat/quests.json",
]

## id -> catalog def Dictionary
var _catalog: Dictionary = {}
## Accepted quest ids in journal order.
var _order: Array = []
## id -> { objectives: [{text,cur,max,...}, ...], status: "in_progress"|"ready"|"completed" }
var _accepted: Dictionary = {}
## Injected YYYY-MM-DD for tests; empty = use Time.get_date_dict_from_system().
var _daily_date: String = ""
## date -> { quest_id: true } for completed dailies that day.
var _daily_log: Dictionary = {}


func load_catalog() -> void:
	_catalog.clear()
	var raw: Variant = JsonUtil.load_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get("quests", [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var qid := str(d.get("id", "")).strip_edges()
		if qid.is_empty():
			continue
		_catalog[qid] = d.duplicate(true)
	if _catalog.is_empty():
		_load_builtin_fallback()


func clear() -> void:
	_order.clear()
	_accepted.clear()


## Minimal auto-accept: main starter only. Side quests are offered by NPCs.
func grant_starter() -> void:
	clear()
	# Only auto-grant the tutorial quest; side/main offers come from NPC dialogue.
	var starter_ids: Array = ["starter_step"]
	for qid_v in starter_ids:
		var qid := str(qid_v)
		if _catalog.has(qid):
			accept_quest(qid)
	if _order.is_empty() and _catalog.has("starter_step"):
		accept_quest("starter_step")
	# Sample completed quests for 已完成 tab.
	var completed_ids: Array = ["welcome_gift", "rat_cleanup"]
	for qid_v in completed_ids:
		var qid := str(qid_v)
		if not _catalog.has(qid):
			continue
		accept_quest(qid)
		mark_completed(qid)


func accept_quest(quest_id: String) -> bool:
	return bool(try_accept_quest(quest_id).get("ok", false))


## Accept with daily gate. Returns {ok, quest_id, already?, reason?, message?}.
func try_accept_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty() or not _catalog.has(quest_id):
		return {"ok": false, "reason": "unknown", "quest_id": quest_id, "message": "无法接取该任务。"}
	var cat := _category_of(quest_id)
	if cat == "daily":
		if _is_daily_done_today(quest_id) or _accepted.has(quest_id):
			return {
				"ok": false,
				"reason": "daily_claimed",
				"quest_id": quest_id,
				"message": "今日已领取该日常。",
			}
	elif _accepted.has(quest_id):
		return {"ok": true, "quest_id": quest_id, "already": true}
	var def: Dictionary = (_catalog[quest_id] as Dictionary).duplicate(true)
	var objs: Array = _copy_objectives(def.get("objectives", []))
	var status := _derive_status(objs)
	_accepted[quest_id] = {"objectives": objs, "status": status}
	_order.append(quest_id)
	return {"ok": true, "quest_id": quest_id, "already": false}


## Mark quest completed (sticky; objectives filled). Used for sample 已完成 entries.
func mark_completed(quest_id: String) -> bool:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty() or not _accepted.has(quest_id):
		return false
	var live: Dictionary = (_accepted[quest_id] as Dictionary).duplicate(true)
	var objs: Array = []
	var live_objs_v: Variant = live.get("objectives", [])
	if typeof(live_objs_v) == TYPE_ARRAY:
		objs = (live_objs_v as Array).duplicate(true)
	for o in objs:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var mx: int = maxi(int(o.get("max", 1)), 1)
		o["cur"] = mx
		o["max"] = mx
	live["objectives"] = objs
	live["status"] = "completed"
	_accepted[quest_id] = live
	return true


## Progress kill objectives matching kill / kill_prefix / kill_contains.
## Returns true if any objective changed.
func note_kill(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return false
	var changed := false
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var live: Dictionary = _accepted[qid]
		var status := str(live.get("status", ""))
		if status == "completed" or status == "complete":
			continue
		var objs_v: Variant = live.get("objectives", [])
		if typeof(objs_v) != TYPE_ARRAY:
			continue
		var objs: Array = objs_v
		var q_changed := false
		for i in range(objs.size()):
			var o_v: Variant = objs[i]
			if typeof(o_v) != TYPE_DICTIONARY:
				continue
			var o: Dictionary = o_v
			if not _objective_matches_kill(o, npc_id):
				continue
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			if cur >= mx:
				continue
			o["cur"] = cur + 1
			objs[i] = o
			q_changed = true
		if q_changed:
			live["objectives"] = objs
			live["status"] = _derive_status(objs)
			_accepted[qid] = live
			changed = true
	return changed


## Progress talk objectives matching talk / talk_prefix.
func note_talk(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return false
	var changed := false
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var live: Dictionary = _accepted[qid]
		var status := str(live.get("status", ""))
		if status == "completed" or status == "complete":
			continue
		var objs_v: Variant = live.get("objectives", [])
		if typeof(objs_v) != TYPE_ARRAY:
			continue
		var objs: Array = objs_v
		var q_changed := false
		for i in range(objs.size()):
			var o_v: Variant = objs[i]
			if typeof(o_v) != TYPE_DICTIONARY:
				continue
			var o: Dictionary = o_v
			if not _objective_matches_talk(o, npc_id):
				continue
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			if cur >= mx:
				continue
			o["cur"] = mini(cur + 1, mx)
			objs[i] = o
			q_changed = true
		if q_changed:
			live["objectives"] = objs
			live["status"] = _derive_status(objs)
			_accepted[qid] = live
			changed = true
	return changed


## Progress item-collect objectives (item / item_id field) by qty gained.
func note_item_gain(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 0)
	if item_id.is_empty() or qty <= 0:
		return false
	var changed := false
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var live: Dictionary = _accepted[qid]
		var status := str(live.get("status", ""))
		if status == "completed" or status == "complete":
			continue
		var objs_v: Variant = live.get("objectives", [])
		if typeof(objs_v) != TYPE_ARRAY:
			continue
		var objs: Array = objs_v
		var q_changed := false
		for i in range(objs.size()):
			var o_v: Variant = objs[i]
			if typeof(o_v) != TYPE_DICTIONARY:
				continue
			var o: Dictionary = o_v
			var want := str(o.get("item", o.get("item_id", o.get("gather", o.get("gather_item", ""))))).strip_edges()
			if want.is_empty():
				want = str(o.get("gather", o.get("gather_item", ""))).strip_edges()
			if want.is_empty() or want != item_id:
				continue
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			if cur >= mx:
				continue
			o["cur"] = mini(cur + qty, mx)
			objs[i] = o
			q_changed = true
		if q_changed:
			live["objectives"] = objs
			live["status"] = _derive_status(objs)
			_accepted[qid] = live
			changed = true
	return changed


## Progress map-reach objectives (reach / map / map_id / content_id).
## Provided ids: map_pack_id, map_content_id, and pack path (basename / contains).
func note_reach(map_id: String, content_id: String = "", pack_path: String = "") -> bool:
	map_id = map_id.strip_edges()
	content_id = content_id.strip_edges()
	pack_path = pack_path.strip_edges().rstrip("/")
	var provided: Array = []
	for v in [map_id, content_id]:
		if str(v) != "" and not provided.has(str(v)):
			provided.append(str(v))
	if pack_path != "":
		var base := pack_path.get_file()
		if base != "" and not provided.has(base):
			provided.append(base)
		# Also keep full path for contains checks.
		if not provided.has(pack_path):
			provided.append(pack_path)
	if provided.is_empty():
		return false
	var changed := false
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var live: Dictionary = _accepted[qid]
		var status := str(live.get("status", ""))
		if status == "completed" or status == "complete":
			continue
		var objs_v: Variant = live.get("objectives", [])
		if typeof(objs_v) != TYPE_ARRAY:
			continue
		var objs: Array = objs_v
		var q_changed := false
		for i in range(objs.size()):
			var o_v: Variant = objs[i]
			if typeof(o_v) != TYPE_DICTIONARY:
				continue
			var o: Dictionary = o_v
			if not _objective_matches_reach(o, provided, pack_path):
				continue
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			if cur >= mx:
				continue
			o["cur"] = mini(cur + 1, mx)
			objs[i] = o
			q_changed = true
		if q_changed:
			live["objectives"] = objs
			live["status"] = _derive_status(objs)
			_accepted[qid] = live
			changed = true
	return changed


## Gather progress: treat gather_id as item id (falls through to note_item_gain).
## Matches objectives with item / item_id / gather / gather_item == gather_id.
func note_gather(gather_id: String, qty: int = 1) -> bool:
	return note_item_gain(gather_id, qty)


## Progress fish_catch / fish objectives on a successful catch.
## qty = number of catches (usually 1). item_id optional: if objective.fish_catch/fish
## is a specific item id, only that yield matches; "any"/"*"/empty matches any catch.
func note_fish(item_id: String = "", qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 0)
	if qty <= 0:
		return false
	var changed := false
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var live: Dictionary = _accepted[qid]
		var status := str(live.get("status", ""))
		if status == "completed" or status == "complete":
			continue
		var objs_v: Variant = live.get("objectives", [])
		if typeof(objs_v) != TYPE_ARRAY:
			continue
		var objs: Array = objs_v
		var q_changed := false
		for i in range(objs.size()):
			var o_v: Variant = objs[i]
			if typeof(o_v) != TYPE_DICTIONARY:
				continue
			var o: Dictionary = o_v
			if not _objective_matches_fish(o, item_id):
				continue
			var cur: int = int(o.get("cur", 0))
			var mx: int = maxi(int(o.get("max", 1)), 1)
			if cur >= mx:
				continue
			o["cur"] = mini(cur + qty, mx)
			objs[i] = o
			q_changed = true
		if q_changed:
			live["objectives"] = objs
			live["status"] = _derive_status(objs)
			_accepted[qid] = live
			changed = true
	return changed


## Turn in a ready quest. Returns {ok, quest_id, reward:{exp,gold,items}, reason?}.
## Does NOT grant rewards itself — MockServer applies reward via combat/inventory APIs.
func try_turn_in(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty() or not _accepted.has(quest_id):
		return {"ok": false, "reason": "not_accepted", "quest_id": quest_id}
	var live: Dictionary = _accepted[quest_id]
	var status := str(live.get("status", ""))
	# Refresh derived status.
	var objs_v: Variant = live.get("objectives", [])
	var objs: Array = objs_v if typeof(objs_v) == TYPE_ARRAY else []
	if status != "completed" and status != "complete":
		status = _derive_status(objs)
		live["status"] = status
		_accepted[quest_id] = live
	if status == "completed" or status == "complete":
		return {"ok": false, "reason": "already_completed", "quest_id": quest_id}
	if status != "ready":
		return {"ok": false, "reason": "not_ready", "quest_id": quest_id, "status": status}
	var reward: Dictionary = _reward_for(quest_id)
	var cat := _category_of(quest_id)
	if cat == "daily":
		_mark_daily_done(quest_id)
		_accepted.erase(quest_id)
		_order.erase(quest_id)
		return {"ok": true, "quest_id": quest_id, "reward": reward, "daily": true}
	mark_completed(quest_id)
	return {"ok": true, "quest_id": quest_id, "reward": reward}


func get_reward(quest_id: String) -> Dictionary:
	return _reward_for(quest_id)


## Abandon in-progress / ready quests. Completed cannot be abandoned.
func try_abandon_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty() or not _accepted.has(quest_id):
		return {"ok": false, "reason": "not_accepted", "quest_id": quest_id}
	var live: Dictionary = _accepted[quest_id]
	var status := str(live.get("status", "")).strip_edges()
	if status == "completed" or status == "complete":
		return {"ok": false, "reason": "completed", "quest_id": quest_id}
	_accepted.erase(quest_id)
	_order.erase(quest_id)
	return {"ok": true, "quest_id": quest_id}



func is_accepted(quest_id: String) -> bool:
	quest_id = quest_id.strip_edges()
	return not quest_id.is_empty() and _accepted.has(quest_id)


func get_catalog_entry(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if quest_id.is_empty() or not _catalog.has(quest_id):
		return {}
	return (_catalog[quest_id] as Dictionary).duplicate(true)


func get_giver(quest_id: String) -> String:
	var def: Dictionary = get_catalog_entry(quest_id)
	return str(def.get("giver", "")).strip_edges()


func get_turn_in_npc(quest_id: String) -> String:
	var def: Dictionary = get_catalog_entry(quest_id)
	var tin := str(def.get("turn_in_npc", "")).strip_edges()
	if tin.is_empty():
		tin = str(def.get("giver", "")).strip_edges()
	return tin


## Catalog quests this NPC can offer that are not yet accepted (and not completed sample).
func list_offers_for_npc(npc_id: String) -> Array:
	npc_id = npc_id.strip_edges()
	var out: Array = []
	if npc_id.is_empty():
		return out
	for qid_v in _catalog.keys():
		var qid := str(qid_v)
		if is_accepted(qid):
			continue
		if _category_of(qid) == "daily":
			continue
		if get_giver(qid) != npc_id:
			continue
		var entry: Dictionary = get_catalog_entry(qid)
		if entry.is_empty():
			continue
		out.append(entry)
	return out


func can_turn_in_to(npc_id: String) -> Array:
	## Accepted ready quests whose turn_in_npc (or giver) matches.
	npc_id = npc_id.strip_edges()
	var out: Array = []
	if npc_id.is_empty():
		return out
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var live: Dictionary = _accepted[qid]
		var status := str(live.get("status", "")).strip_edges()
		var objs_v: Variant = live.get("objectives", [])
		var objs: Array = objs_v if typeof(objs_v) == TYPE_ARRAY else []
		if status != "completed" and status != "complete":
			status = _derive_status(objs)
			live["status"] = status
			_accepted[qid] = live
		if status != "ready":
			continue
		if get_turn_in_npc(qid) != npc_id:
			continue
		var merged: Dictionary = _merge_entry(qid)
		if not merged.is_empty():
			out.append(merged)
	return out


func get_status(quest_id: String) -> String:
	quest_id = quest_id.strip_edges()
	if not _accepted.has(quest_id):
		return ""
	var live: Dictionary = _accepted[quest_id]
	var status := str(live.get("status", "")).strip_edges()
	if status == "completed" or status == "complete":
		return "completed"
	var objs_v: Variant = live.get("objectives", [])
	var objs: Array = objs_v if typeof(objs_v) == TYPE_ARRAY else []
	return _derive_status(objs)


func get_quest(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	if not _accepted.has(quest_id) or not _catalog.has(quest_id):
		return {}
	return _merge_entry(quest_id)


## Snapshot for quest_update / HUD — accepted quests only.
func get_quest_list() -> Array:
	return snapshot()


func snapshot() -> Array:
	var out: Array = []
	for qid_v in _order:
		var qid := str(qid_v)
		if not _accepted.has(qid):
			continue
		var entry: Dictionary = _merge_entry(qid)
		if not entry.is_empty():
			out.append(entry)
	return out


func get_daily_date() -> String:
	return _today_ymd()


## Test helper: inject YYYY-MM-DD ("" = system clock).
func force_daily_date(ymd: String) -> void:
	_daily_date = str(ymd).strip_edges()


func clear_daily_log() -> void:
	_daily_log.clear()


## Board rows: [{id,title,desc,rewards,reward,state,category}, ...]
## state: available | accepted | done_today
func try_daily_board_list() -> Array:
	var out: Array = []
	for qid_v in _catalog.keys():
		var qid := str(qid_v)
		if _category_of(qid) != "daily":
			continue
		var def: Dictionary = get_catalog_entry(qid)
		if def.is_empty():
			continue
		var state := "available"
		if _accepted.has(qid):
			state = "accepted"
		elif _is_daily_done_today(qid):
			state = "done_today"
		out.append({
			"id": qid,
			"title": str(def.get("title", qid)),
			"desc": str(def.get("desc", "")),
			"rewards": str(def.get("rewards", "")),
			"reward": _reward_for(qid),
			"category": "daily",
			"state": state,
			"giver": str(def.get("giver", "")),
			"turn_in_npc": str(def.get("turn_in_npc", def.get("giver", ""))),
		})
	# Stable order by id
	out.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	return out


## Companion to snapshot(): daily_date + board states.
func snapshot_daily() -> Dictionary:
	return {
		"daily_date": _today_ymd(),
		"daily": try_daily_board_list(),
	}


func _category_of(quest_id: String) -> String:
	quest_id = quest_id.strip_edges()
	if not _catalog.has(quest_id):
		return ""
	return str((_catalog[quest_id] as Dictionary).get("category", "")).strip_edges()


func _today_ymd() -> String:
	if not _daily_date.is_empty():
		return _daily_date
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0))]


func _is_daily_done_today(quest_id: String) -> bool:
	quest_id = quest_id.strip_edges()
	var today := _today_ymd()
	if today.is_empty() or quest_id.is_empty():
		return false
	var day_v: Variant = _daily_log.get(today, {})
	if typeof(day_v) != TYPE_DICTIONARY:
		return false
	return bool((day_v as Dictionary).get(quest_id, false))


func _mark_daily_done(quest_id: String) -> void:
	quest_id = quest_id.strip_edges()
	var today := _today_ymd()
	if today.is_empty() or quest_id.is_empty():
		return
	var day: Dictionary = {}
	var day_v: Variant = _daily_log.get(today, {})
	if typeof(day_v) == TYPE_DICTIONARY:
		day = (day_v as Dictionary).duplicate(true)
	day[quest_id] = true
	_daily_log[today] = day


func _reward_for(quest_id: String) -> Dictionary:
	quest_id = quest_id.strip_edges()
	var out := {"exp": 0, "gold": 0, "items": []}
	if not _catalog.has(quest_id):
		return out
	var def: Dictionary = _catalog[quest_id]
	var rv: Variant = def.get("reward", {})
	if typeof(rv) == TYPE_DICTIONARY:
		var r: Dictionary = rv
		out["exp"] = maxi(int(r.get("exp", 0)), 0)
		out["gold"] = maxi(int(r.get("gold", 0)), 0)
		var items_v: Variant = r.get("items", [])
		var items: Array = []
		if typeof(items_v) == TYPE_ARRAY:
			for it in items_v:
				if typeof(it) != TYPE_DICTIONARY:
					continue
				var iid := str(it.get("id", it.get("item_id", ""))).strip_edges()
				var qty: int = maxi(int(it.get("qty", 1)), 1)
				if iid.is_empty():
					continue
				items.append({"id": iid, "qty": qty})
		out["items"] = items
	return out


func _objective_matches_kill(o: Dictionary, npc_id: String) -> bool:
	var exact := str(o.get("kill", "")).strip_edges()
	if exact != "" and exact == npc_id:
		return true
	var prefix := str(o.get("kill_prefix", "")).strip_edges()
	if prefix != "" and npc_id.begins_with(prefix):
		return true
	var contains := str(o.get("kill_contains", "")).strip_edges()
	if contains != "" and npc_id.find(contains) >= 0:
		return true
	# Legacy: objective text mentions npc_id.
	if exact.is_empty() and prefix.is_empty() and contains.is_empty():
		var text := str(o.get("text", ""))
		if text.find(npc_id) >= 0:
			return true
	return false


func _objective_matches_talk(o: Dictionary, npc_id: String) -> bool:
	var exact := str(o.get("talk", "")).strip_edges()
	if exact != "" and exact == npc_id:
		return true
	var prefix := str(o.get("talk_prefix", "")).strip_edges()
	if prefix != "" and npc_id.begins_with(prefix):
		return true
	return false


func _reach_alias_set(id: String) -> Dictionary:
	id = id.strip_edges()
	var out := {}
	if id.is_empty():
		return out
	out[id] = true
	# street_map / street_central / street are interchangeable.
	var street_group: Array = ["street_map", "street_central", "street"]
	if id in street_group or id.find("street_map") >= 0 or id.find("street_central") >= 0:
		for s in street_group:
			out[str(s)] = true
	return out


func _objective_matches_reach(o: Dictionary, provided: Array, pack_path: String = "") -> bool:
	var wants: Array = []
	for key in ["reach", "map", "map_id", "content_id"]:
		var w := str(o.get(key, "")).strip_edges()
		if w != "" and not wants.has(w):
			wants.append(w)
	if wants.is_empty():
		return false
	var prov_set := {}
	for p in provided:
		var ps := str(p).strip_edges()
		if ps.is_empty():
			continue
		for a in _reach_alias_set(ps).keys():
			prov_set[str(a)] = true
		# pack path basename already in provided; also match path contains.
		if ps.find("/") >= 0 or ps.find(":") >= 0:
			for a in _reach_alias_set(ps.get_file()).keys():
				prov_set[str(a)] = true
	if pack_path != "":
		var pp := pack_path.strip_edges()
		for want in wants:
			if pp.find(want) >= 0:
				return true
			for a in _reach_alias_set(want).keys():
				if pp.find(str(a)) >= 0:
					return true
	for want in wants:
		var want_set: Dictionary = _reach_alias_set(want)
		for k in want_set.keys():
			if prov_set.has(str(k)):
				return true
	return false


func _objective_matches_fish(o: Dictionary, item_id: String) -> bool:
	var raw := ""
	if o.has("fish_catch"):
		raw = str(o.get("fish_catch", "")).strip_edges()
	elif o.has("fish"):
		raw = str(o.get("fish", "")).strip_edges()
	else:
		return false
	# any / * / empty / "1" / "true" → any successful catch
	var low := raw.to_lower()
	if low == "" or low == "any" or low == "*" or low == "1" or low == "true" or low == "yes":
		return true
	# Specific yield item id
	if item_id != "" and raw == item_id:
		return true
	return false


func _merge_entry(quest_id: String) -> Dictionary:
	if not _catalog.has(quest_id) or not _accepted.has(quest_id):
		return {}
	var def: Dictionary = (_catalog[quest_id] as Dictionary).duplicate(true)
	var live: Dictionary = _accepted[quest_id]
	var objs: Array = []
	var live_objs_v: Variant = live.get("objectives", [])
	if typeof(live_objs_v) == TYPE_ARRAY:
		objs = (live_objs_v as Array).duplicate(true)
	else:
		objs = _copy_objectives(def.get("objectives", []))
	var status := str(live.get("status", "")).strip_edges()
	# Sticky completed; otherwise derive from objectives.
	if status == "completed" or status == "complete":
		status = "completed"
	else:
		status = _derive_status(objs)
	live["status"] = status
	_accepted[quest_id] = live
	var reward: Dictionary = _reward_for(quest_id)
	return {
		"id": quest_id,
		"title": str(def.get("title", quest_id)),
		"category": str(def.get("category", "")),
		"desc": str(def.get("desc", "")),
		"objectives": objs,
		"rewards": str(def.get("rewards", "")),
		"reward": reward,
		"status": status,
		"giver": str(def.get("giver", "")),
		"turn_in_npc": str(def.get("turn_in_npc", def.get("giver", ""))),
	}


func _copy_objectives(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for o in raw:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = o
		var entry := {
			"text": str(d.get("text", "")),
			"cur": int(d.get("cur", 0)),
			"max": maxi(int(d.get("max", 1)), 1),
		}
		for key in ["kill", "kill_prefix", "kill_contains", "talk", "talk_prefix", "item", "item_id", "gather", "gather_item", "fish", "fish_catch", "reach", "map", "map_id", "content_id"]:
			if d.has(key) and str(d.get(key, "")).strip_edges() != "":
				entry[key] = str(d.get(key, "")).strip_edges()
		out.append(entry)
	return out


func _derive_status(objs: Array) -> String:
	if objs.is_empty():
		return "in_progress"
	for o in objs:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var cur: int = int(o.get("cur", 0))
		var mx: int = maxi(int(o.get("max", 1)), 1)
		if cur < mx:
			return "in_progress"
	return "ready"


func _load_builtin_fallback() -> void:
	_catalog = {
		"starter_step": {
			"id": "starter_step",
			"title": "新手的第一步",
			"category": "main",
			"giver": "actor_rest",
			"turn_in_npc": "actor_rest",
			"desc": "击败训练场假人，熟悉战斗基础。",
			"objectives": [{"text": "击败训练假人（史莱姆）", "cur": 0, "max": 3, "kill": "slime", "kill_contains": "slime"}],
			"rewards": "经验 80 · 红药水×3 · 铜币×30",
			"reward": {"exp": 80, "gold": 30, "items": [{"id": "potion_hp_small", "qty": 3}]},
		},
		"slime_hunt": {
			"id": "slime_hunt",
			"title": "清剿史莱姆",
			"category": "side",
			"desc": "清理街道北侧的粘液生物。",
			"objectives": [
				{"text": "击败史莱姆", "cur": 0, "max": 3, "kill": "street_slime", "kill_contains": "slime"},
				{"text": "收集史莱姆凝胶", "cur": 0, "max": 2, "item": "slime_jelly"},
			],
			"rewards": "经验 50 · 银币×20 · 蓝药水×2",
			"reward": {"exp": 50, "gold": 20, "items": [{"id": "potion_mp_small", "qty": 2}]},
		},
		"welcome_gift": {
			"id": "welcome_gift",
			"title": "初入村庄",
			"category": "main",
			"desc": "向村庄接待员报到，领取新人礼包。",
			"objectives": [
				{"text": "与接待员对话", "cur": 1, "max": 1, "talk": "actor_rest"},
				{"text": "领取新人礼包", "cur": 1, "max": 1},
			],
			"rewards": "经验 20 · 红药水×5 · 铜币×50",
			"reward": {"exp": 20, "gold": 50, "items": [{"id": "potion_hp_small", "qty": 5}]},
		},
		"rat_cleanup": {
			"id": "rat_cleanup",
			"title": "清理老鼠",
			"category": "side",
			"desc": "仓库管理员请你清理仓库里的老鼠。",
			"objectives": [{"text": "击败仓库老鼠", "cur": 5, "max": 5, "kill_prefix": "rat_"}],
			"rewards": "经验 40 · 银币×10",
			"reward": {"exp": 40, "gold": 10, "items": []},
		},
	}
