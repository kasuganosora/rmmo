extends RefCounted
## Pure helpers for the on-screen quest tracker HUD (no nodes).
## Builds compact title + objective progress lines from a journal snapshot.

const MAX_TRACKED := 5


## Active = in_progress | ready (same as journal 「正在进行」 tab). Caps at max_count.
static func active_quests(quests: Array, max_count: int = MAX_TRACKED) -> Array:
	var out: Array = []
	if max_count <= 0:
		return out
	for row in quests:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var st := _normalize_status(str(row.get("status", "")))
		if st != "in_progress" and st != "ready":
			continue
		out.append(row)
		if out.size() >= max_count:
			break
	return out


static func format_objective(o: Dictionary) -> String:
	var text := str(o.get("text", "")).strip_edges()
	var cur := int(o.get("cur", 0))
	var mx := int(o.get("max", 0))
	if text.is_empty():
		text = "目标"
	return "%s %d/%d" % [text, cur, mx]


## Multi-line tracker body. Titles unmarked; objectives indented with two spaces.
## Example:
##   新手指引
##     假人 1/3
##   采集野草
##     野草 2/5
static func build_tracker_text(quests: Array, max_quests: int = MAX_TRACKED) -> String:
	var lines: PackedStringArray = []
	for q in active_quests(quests, max_quests):
		var title := str(q.get("title", "")).strip_edges()
		if title.is_empty():
			title = str(q.get("id", "任务"))
		var st := _normalize_status(str(q.get("status", "")))
		if st == "ready":
			lines.append("%s [可交付]" % title)
		else:
			lines.append(title)
		var objs_v: Variant = q.get("objectives", [])
		if typeof(objs_v) != TYPE_ARRAY:
			continue
		for o in objs_v:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			lines.append("  %s" % format_objective(o))
	return "\n".join(lines)


static func _normalize_status(status: String) -> String:
	match status.strip_edges():
		"completed", "complete":
			return "completed"
		"ready", "deliverable":
			return "ready"
		"active", "in_progress", "progress":
			return "in_progress"
		_:
			return "in_progress"


## --- Quest tracker → pathfind helpers (pure; headless-friendly) ---
## world_ctx: {
##   npcs: [{id, name, cell}],
##   gather: [{id, name, cell, depleted?, yields?/items?/item?}],
##   fish: [{id, name, cell, depleted?, yields?/items?/item?}],
##   warps: [{from_cell|{x,y}, to_map_id?, to_map?, to_pack?, message?}],
## }
## Returns {ok, cell: Vector2i, label, reason} — ok=false when no nav cell.


static func cell_of(row: Dictionary) -> Vector2i:
	var cell_v: Variant = row.get("cell", null)
	if typeof(cell_v) == TYPE_VECTOR2I:
		return cell_v
	if typeof(cell_v) == TYPE_DICTIONARY:
		return Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	if row.has("x") or row.has("y"):
		return Vector2i(int(row.get("x", 0)), int(row.get("y", 0)))
	return Vector2i(0, 0)


static func _has_explicit_cell(row: Dictionary) -> bool:
	var cell_v: Variant = row.get("cell", null)
	if typeof(cell_v) == TYPE_VECTOR2I:
		return true
	if typeof(cell_v) == TYPE_DICTIONARY and (cell_v.has("x") or cell_v.has("y")):
		return true
	if row.has("x") or row.has("y"):
		return true
	if row.has("reach_cell") and typeof(row.get("reach_cell")) == TYPE_DICTIONARY:
		return true
	return false


static func _explicit_cell(row: Dictionary) -> Vector2i:
	if row.has("reach_cell") and typeof(row.get("reach_cell")) == TYPE_DICTIONARY:
		var rc: Dictionary = row.get("reach_cell")
		return Vector2i(int(rc.get("x", 0)), int(rc.get("y", 0)))
	return cell_of(row)


static func _row_item_ids(row: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen: Dictionary = {}
	var add := func(s: String) -> void:
		s = s.strip_edges()
		if s.is_empty() or seen.has(s):
			return
		seen[s] = true
		out.append(s)
	add.call(str(row.get("item", "")))
	add.call(str(row.get("item_id", "")))
	var items_v: Variant = row.get("items", [])
	if typeof(items_v) == TYPE_ARRAY:
		for it in items_v:
			if typeof(it) == TYPE_STRING:
				add.call(str(it))
			elif typeof(it) == TYPE_DICTIONARY:
				add.call(str(it.get("item_id", it.get("id", ""))))
	var yv: Variant = row.get("yields", [])
	if typeof(yv) == TYPE_ARRAY:
		for y in yv:
			if typeof(y) != TYPE_DICTIONARY:
				continue
			add.call(str(y.get("item_id", y.get("id", ""))))
	return out


static func _row_matches_item(row: Dictionary, want: String) -> bool:
	want = want.strip_edges()
	if want.is_empty():
		return false
	var low := want.to_lower()
	if low == "any" or low == "*" or low == "1" or low == "true":
		return true
	var nid := str(row.get("id", "")).strip_edges()
	if nid == want:
		return true
	for iid in _row_item_ids(row):
		if iid == want:
			return true
	return false


static func find_npc(npcs: Array, npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return {}
	for n in npcs:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		if str(n.get("id", "")).strip_edges() == npc_id:
			return n
	return {}


static func _nav_from_npc(npcs: Array, npc_id: String, reason: String) -> Dictionary:
	var n: Dictionary = find_npc(npcs, npc_id)
	if n.is_empty():
		return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}
	var name_s := str(n.get("name", "")).strip_edges()
	if name_s.is_empty():
		name_s = npc_id
	return {"ok": true, "cell": cell_of(n), "label": name_s, "reason": reason}


static func _objective_want_item(o: Dictionary) -> String:
	for key in ["gather_item", "gather", "item", "item_id", "fish_catch", "fish"]:
		var s := str(o.get(key, "")).strip_edges()
		if not s.is_empty():
			return s
	return ""


static func _objective_is_gather(o: Dictionary) -> bool:
	for key in ["gather", "gather_item"]:
		if str(o.get(key, "")).strip_edges() != "":
			return true
	return false


static func _objective_is_fish(o: Dictionary) -> bool:
	for key in ["fish", "fish_catch"]:
		if str(o.get(key, "")).strip_edges() != "":
			return true
	return false


static func _objective_reach_ids(o: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen: Dictionary = {}
	for key in ["reach", "map", "map_id", "content_id"]:
		var s := str(o.get(key, "")).strip_edges()
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out


static func _warp_matches(warp: Dictionary, want_ids: PackedStringArray) -> bool:
	if want_ids.is_empty():
		return false
	var candidates: PackedStringArray = []
	for key in ["to_map_id", "to_map", "to_pack", "map_id"]:
		var s := str(warp.get(key, "")).strip_edges()
		if s.is_empty():
			continue
		candidates.append(s)
		# strip res:// and trailing path for pack paths
		if s.begins_with("res://"):
			candidates.append(s.trim_prefix("res://"))
			candidates.append(s.get_file())
	for want in want_ids:
		for c in candidates:
			if c == want:
				return true
			if c.get_file() == want:
				return true
			if c.ends_with("/" + want) or c.ends_with("\\" + want):
				return true
	return false


static func _find_warp_nav(warps: Array, want_ids: PackedStringArray) -> Dictionary:
	for w in warps:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if not _warp_matches(w, want_ids):
			continue
		var cell := cell_of(w)
		if w.has("from_cell"):
			var fc: Variant = w.get("from_cell")
			if typeof(fc) == TYPE_DICTIONARY:
				cell = Vector2i(int(fc.get("x", 0)), int(fc.get("y", 0)))
			elif typeof(fc) == TYPE_VECTOR2I:
				cell = fc
		var label := str(w.get("message", "")).strip_edges()
		if label.is_empty():
			label = str(want_ids[0]) if want_ids.size() > 0 else "传送点"
		return {"ok": true, "cell": cell, "label": label, "reason": "reach_warp"}
	return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}


static func _find_resource_nav(rows: Array, want_item: String, reason: String) -> Dictionary:
	want_item = want_item.strip_edges()
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		if bool(r.get("depleted", false)):
			continue
		# Empty / any / * → first non-depleted; else match yields/id.
		if want_item != "" and not _row_matches_item(r, want_item):
			continue
		var name_s := str(r.get("name", "")).strip_edges()
		if name_s.is_empty():
			name_s = str(r.get("id", reason)).strip_edges()
		return {"ok": true, "cell": cell_of(r), "label": name_s, "reason": reason}
	return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}


## Resolve one objective → nav target (or ok=false).
static func resolve_objective_nav(objective: Dictionary, world_ctx: Dictionary) -> Dictionary:
	var npcs: Array = world_ctx.get("npcs", []) if typeof(world_ctx.get("npcs", [])) == TYPE_ARRAY else []
	var gather: Array = world_ctx.get("gather", []) if typeof(world_ctx.get("gather", [])) == TYPE_ARRAY else []
	var fish: Array = world_ctx.get("fish", []) if typeof(world_ctx.get("fish", [])) == TYPE_ARRAY else []
	var warps: Array = world_ctx.get("warps", []) if typeof(world_ctx.get("warps", [])) == TYPE_ARRAY else []

	# 1) Explicit map-reach / objective cell coords
	if _has_explicit_cell(objective):
		var cell := _explicit_cell(objective)
		var label := str(objective.get("text", "")).strip_edges()
		if label.is_empty():
			label = "(%d, %d)" % [cell.x, cell.y]
		return {"ok": true, "cell": cell, "label": label, "reason": "obj_cell"}

	# 2) Map-reach via warp (reach / map_id → from_cell)
	var reach_ids := _objective_reach_ids(objective)
	if not reach_ids.is_empty():
		var wnav: Dictionary = _find_warp_nav(warps, reach_ids)
		if bool(wnav.get("ok", false)):
			return wnav

	# 3) Gather POI (gather / gather_item, or plain item matching a yield)
	if _objective_is_gather(objective):
		var gnav: Dictionary = _find_resource_nav(gather, _objective_want_item(objective), "gather")
		if bool(gnav.get("ok", false)):
			return gnav

	# 4) Fish POI
	if _objective_is_fish(objective):
		var fnav: Dictionary = _find_resource_nav(fish, _objective_want_item(objective), "fish")
		if bool(fnav.get("ok", false)):
			return fnav

	# Plain item → gather yield match (e.g. slime_jelly collect)
	var item_only := str(objective.get("item", objective.get("item_id", ""))).strip_edges()
	if item_only != "" and not _objective_is_fish(objective):
		var gitem: Dictionary = _find_resource_nav(gather, item_only, "gather")
		if bool(gitem.get("ok", false)):
			return gitem

	# 5) Talk NPC
	var talk := str(objective.get("talk", objective.get("talk_prefix", ""))).strip_edges()
	if talk != "":
		var tnav: Dictionary = _nav_from_npc(npcs, talk, "talk")
		if bool(tnav.get("ok", false)):
			return tnav

	# 6) Kill target on map (training dummy / named mob)
	var kill_id := str(objective.get("kill", "")).strip_edges()
	if kill_id != "":
		var knav: Dictionary = _nav_from_npc(npcs, kill_id, "kill")
		if bool(knav.get("ok", false)):
			return knav

	return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}


## Resolve quest (and optional objective index) → nav target.
## objective_index < 0: quest-level (ready→turn-in; else first incomplete obj; else giver).
static func resolve_quest_nav(quest: Dictionary, world_ctx: Dictionary, objective_index: int = -1) -> Dictionary:
	var npcs: Array = world_ctx.get("npcs", []) if typeof(world_ctx.get("npcs", [])) == TYPE_ARRAY else []
	var st := _normalize_status(str(quest.get("status", "")))
	var giver := str(quest.get("giver", "")).strip_edges()
	var turn_in := str(quest.get("turn_in_npc", "")).strip_edges()
	if turn_in.is_empty():
		turn_in = giver

	var objs_v: Variant = quest.get("objectives", [])
	var objs: Array = objs_v if typeof(objs_v) == TYPE_ARRAY else []

	# Specific objective click
	if objective_index >= 0 and objective_index < objs.size():
		var o: Variant = objs[objective_index]
		if typeof(o) == TYPE_DICTIONARY:
			var onav: Dictionary = resolve_objective_nav(o, world_ctx)
			if bool(onav.get("ok", false)):
				return onav
		# fall through to quest-level

	# Ready → turn-in NPC
	if st == "ready" and turn_in != "":
		var rnav: Dictionary = _nav_from_npc(npcs, turn_in, "turn_in")
		if bool(rnav.get("ok", false)):
			return rnav

	# First incomplete objective with a resolvable dest
	for o2 in objs:
		if typeof(o2) != TYPE_DICTIONARY:
			continue
		var cur := int(o2.get("cur", 0))
		var mx := maxi(int(o2.get("max", 1)), 1)
		if cur >= mx:
			continue
		var inav: Dictionary = resolve_objective_nav(o2, world_ctx)
		if bool(inav.get("ok", false)):
			return inav

	# Giver / turn-in fallback
	if giver != "":
		var gnav: Dictionary = _nav_from_npc(npcs, giver, "giver")
		if bool(gnav.get("ok", false)):
			return gnav
	if turn_in != "" and turn_in != giver:
		var tnav2: Dictionary = _nav_from_npc(npcs, turn_in, "turn_in")
		if bool(tnav2.get("ok", false)):
			return tnav2

	return {"ok": false, "cell": Vector2i.ZERO, "label": "", "reason": ""}
