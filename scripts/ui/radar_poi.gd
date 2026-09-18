extends RefCounted
## Thin radar/minimap POI markers: colored dots only (no art sprites).
## Pure helpers — build marker lists from MockServer/world sample data.

const KIND_QUEST := "quest"
const KIND_INN := "inn"
const KIND_SMITH := "smith"
const KIND_GATHER := "gather"
const KIND_FISH := "fish"
const KIND_PIN := "pin"
const KIND_BOSS := "boss"

## Distinct blip colors (dots only).
const COLOR_QUEST := Color(0.95, 0.85, 0.2) ## yellow — quest giver / available
const COLOR_INN := Color(0.25, 0.9, 0.95) ## cyan — innkeeper
const COLOR_SMITH := Color(0.95, 0.55, 0.2) ## orange — blacksmith
const COLOR_GATHER := Color(0.3, 0.9, 0.35) ## green — gather node
const COLOR_FISH := Color(0.3, 0.55, 0.95) ## blue — fish spot
const COLOR_PIN := Color(0.95, 0.35, 0.95) ## magenta — personal map pin
const COLOR_BOSS := Color(0.85, 0.2, 0.95) ## purple/red — world boss


static func color_for_kind(kind: String) -> Color:
	match str(kind).strip_edges():
		KIND_QUEST:
			return COLOR_QUEST
		KIND_INN:
			return COLOR_INN
		KIND_SMITH:
			return COLOR_SMITH
		KIND_GATHER:
			return COLOR_GATHER
		KIND_FISH:
			return COLOR_FISH
		KIND_PIN:
			return COLOR_PIN
		KIND_BOSS:
			return COLOR_BOSS
		_:
			return Color(0.7, 0.7, 0.7)


static func label_for_kind(kind: String) -> String:
	match str(kind).strip_edges():
		KIND_QUEST:
			return "任务"
		KIND_INN:
			return "旅店"
		KIND_SMITH:
			return "铁匠"
		KIND_GATHER:
			return "采集"
		KIND_FISH:
			return "钓鱼"
		KIND_PIN:
			return "标记"
		KIND_BOSS:
			return "首领"
		_:
			return kind


## Legend lines for tooltip: [{kind, label, color}, ...]
static func legend() -> Array:
	return [
		{"kind": KIND_QUEST, "label": label_for_kind(KIND_QUEST), "color": COLOR_QUEST},
		{"kind": KIND_INN, "label": label_for_kind(KIND_INN), "color": COLOR_INN},
		{"kind": KIND_SMITH, "label": label_for_kind(KIND_SMITH), "color": COLOR_SMITH},
		{"kind": KIND_GATHER, "label": label_for_kind(KIND_GATHER), "color": COLOR_GATHER},
		{"kind": KIND_FISH, "label": label_for_kind(KIND_FISH), "color": COLOR_FISH},
		{"kind": KIND_PIN, "label": label_for_kind(KIND_PIN), "color": COLOR_PIN},
		{"kind": KIND_BOSS, "label": label_for_kind(KIND_BOSS), "color": COLOR_BOSS},
	]


static func legend_text() -> String:
	var lines: PackedStringArray = ["雷达标记"]
	for row in legend():
		lines.append("%s · %s" % [str(row.get("label", "")), str(row.get("kind", ""))])
	return "\n".join(lines)


## Classify one NPC/row. Priority: quest > inn > smith > boss > gather > fish > "".
## Row keys: inn_rest, blacksmith/repair, quest_offer/quest_offers/quest_turn_in,
##           is_gather, is_fish, world_boss/is_boss (bools); depleted hides boss like gather.
static func classify_npc(row: Dictionary) -> String:
	var quest_ok := bool(row.get("quest_offer", false)) or bool(row.get("quest_turn_in", false))
	if not quest_ok:
		var qo: Variant = row.get("quest_offers", 0)
		if typeof(qo) == TYPE_BOOL:
			quest_ok = bool(qo)
		elif typeof(qo) == TYPE_INT or typeof(qo) == TYPE_FLOAT:
			quest_ok = int(qo) > 0
		elif typeof(qo) == TYPE_ARRAY:
			quest_ok = not (qo as Array).is_empty()
	if quest_ok:
		return KIND_QUEST
	if bool(row.get("inn_rest", false)):
		return KIND_INN
	if bool(row.get("blacksmith", false)) or bool(row.get("repair", false)):
		return KIND_SMITH
	if bool(row.get("world_boss", false)) or bool(row.get("is_boss", false)):
		return KIND_BOSS
	if bool(row.get("is_gather", false)):
		return KIND_GATHER
	if bool(row.get("is_fish", false)):
		return KIND_FISH
	return ""


static func _cell_of(row: Dictionary) -> Vector2i:
	var cell_v: Variant = row.get("cell", {})
	if typeof(cell_v) == TYPE_VECTOR2I:
		return cell_v
	if typeof(cell_v) == TYPE_DICTIONARY:
		return Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	return Vector2i(int(row.get("x", 0)), int(row.get("y", 0)))


static func _marker(kind: String, row: Dictionary) -> Dictionary:
	var cell := _cell_of(row)
	var mid := str(row.get("id", "")).strip_edges()
	var name_s := str(row.get("name", mid)).strip_edges()
	return {
		"kind": kind,
		"id": mid,
		"name": name_s if name_s != "" else mid,
		"cell": cell,
		"label": label_for_kind(kind),
		"color": color_for_kind(kind),
		"hostile": false,
	}


## Build POI marker list from sample data (headless-friendly).
## sample: {
##   npcs: [{id, cell, inn_rest?, blacksmith?, repair?, quest_offer?/quest_offers?/quest_turn_in?, is_gather?, is_fish?}],
##   gather: [{id, cell, depleted?}],
##   fish: [{id, cell, depleted?}],
##   pins: [{id, cell, name?}] — personal map pins (kind pin),
##   bosses: [{id, cell, depleted?/dead?}] — world boss POI (kind boss),
## }
## Skips depleted gather/fish. Returns [{kind, id, name, cell, label, color, hostile}, ...].
static func build_markers(sample: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {} ## id -> true (first kind wins)

	var npcs_v: Variant = sample.get("npcs", [])
	if typeof(npcs_v) == TYPE_ARRAY:
		for row_v in npcs_v:
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_v
			var kind := classify_npc(row)
			if kind.is_empty():
				continue
			# Hide dead/depleted world bosses (same idea as gather nodes).
			if kind == KIND_BOSS and (bool(row.get("depleted", false)) or bool(row.get("dead", false))):
				continue
			var nid := str(row.get("id", "")).strip_edges()
			if nid != "" and seen.has(nid):
				continue
			if nid != "":
				seen[nid] = true
			out.append(_marker(kind, row))

	var gather_v: Variant = sample.get("gather", [])
	if typeof(gather_v) == TYPE_ARRAY:
		for gv in gather_v:
			if typeof(gv) != TYPE_DICTIONARY:
				continue
			var g: Dictionary = gv
			if bool(g.get("depleted", false)):
				continue
			var gid := str(g.get("id", "")).strip_edges()
			if gid != "" and seen.has(gid):
				continue
			if gid != "":
				seen[gid] = true
			var grow: Dictionary = g.duplicate(true)
			grow["is_gather"] = true
			out.append(_marker(KIND_GATHER, grow))

	var fish_v: Variant = sample.get("fish", [])
	if typeof(fish_v) == TYPE_ARRAY:
		for fv in fish_v:
			if typeof(fv) != TYPE_DICTIONARY:
				continue
			var f: Dictionary = fv
			if bool(f.get("depleted", false)):
				continue
			var fid := str(f.get("id", "")).strip_edges()
			if fid != "" and seen.has(fid):
				continue
			if fid != "":
				seen[fid] = true
			var frow: Dictionary = f.duplicate(true)
			frow["is_fish"] = true
			out.append(_marker(KIND_FISH, frow))

	var bosses_v: Variant = sample.get("bosses", [])
	if typeof(bosses_v) == TYPE_ARRAY:
		for bv in bosses_v:
			if typeof(bv) != TYPE_DICTIONARY:
				continue
			var b: Dictionary = bv
			if bool(b.get("depleted", false)) or bool(b.get("dead", false)):
				continue
			var bid := str(b.get("id", "")).strip_edges()
			if bid != "" and seen.has(bid):
				continue
			if bid != "":
				seen[bid] = true
			var brow: Dictionary = b.duplicate(true)
			brow["world_boss"] = true
			out.append(_marker(KIND_BOSS, brow))

	var pins_v: Variant = sample.get("pins", [])
	if typeof(pins_v) == TYPE_ARRAY:
		for pv in pins_v:
			if typeof(pv) != TYPE_DICTIONARY:
				continue
			var pin: Dictionary = pv
			var pid := str(pin.get("id", "")).strip_edges()
			if pid != "" and seen.has(pid):
				continue
			if pid != "":
				seen[pid] = true
			out.append(_marker(KIND_PIN, pin))

	return out


## Count markers by kind (for tests).
static func count_by_kind(markers: Array) -> Dictionary:
	var counts: Dictionary = {}
	for m in markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var k := str(m.get("kind", "")).strip_edges()
		if k.is_empty():
			continue
		counts[k] = int(counts.get(k, 0)) + 1
	return counts


## Extract cell from a marker/row dict (Vector2i or {x,y}).
static func marker_cell(m: Dictionary) -> Vector2i:
	return _cell_of(m)


## Display label for system_message: prefer name, else kind label.
static func marker_nav_label(m: Dictionary) -> String:
	var name_s := str(m.get("name", "")).strip_edges()
	if name_s != "":
		return name_s
	var label := str(m.get("label", "")).strip_edges()
	if label != "":
		return label
	return label_for_kind(str(m.get("kind", "")))


## First marker whose cell equals `cell`, or {}.
static func marker_at_cell(markers: Array, cell: Vector2i) -> Dictionary:
	for m in markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if marker_cell(m) == cell:
			return m
	return {}


## Nearest marker whose screen_of(cell) is within hit_px of local. Empty {} if none.
## screen_of: Callable(cell: Vector2i) -> Vector2
static func pick_marker_at(
	markers: Array,
	local: Vector2,
	screen_of: Callable,
	hit_px: float = 14.0
) -> Dictionary:
	if markers.is_empty() or hit_px <= 0.0:
		return {}
	var best: Dictionary = {}
	var best_d2: float = hit_px * hit_px
	for m in markers:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var cell := marker_cell(m)
		var pos: Vector2 = screen_of.call(cell)
		var d2: float = local.distance_squared_to(pos)
		if d2 <= best_d2:
			best_d2 = d2
			best = m
	return best


## Resolve a map click: POI cell if a marker is within hit_px of local, else fallback_cell.
static func resolve_nav_cell(
	markers: Array,
	local: Vector2,
	screen_of: Callable,
	fallback_cell: Vector2i,
	hit_px: float = 14.0
) -> Vector2i:
	var hit: Dictionary = pick_marker_at(markers, local, screen_of, hit_px)
	if hit.is_empty():
		return fallback_cell
	return marker_cell(hit)
