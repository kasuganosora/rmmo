extends RefCounted
## Pure helpers: equipment hover tip vs currently equipped piece (Chinese plain text).
## Reads catalog fields only (type / equip_slot / bonuses). No nodes.

const Equipment = preload("res://scripts/net/combat/equipment.gd")

## Display order for known bonus keys (catalog uses these).
const STAT_ORDER: Array[String] = [
	"p_atk", "p_def", "m_atk", "m_def", "hp", "mp", "atk", "def",
]

const STAT_LABELS_ZH: Dictionary = {
	"p_atk": "物攻",
	"atk": "物攻",
	"p_def": "物防",
	"def": "物防",
	"m_atk": "魔攻",
	"m_def": "魔防",
	"hp": "HP",
	"mp": "MP",
}


## Catalog equip_slot for an item def, or "" if not equippable.
static func equip_slot_for_item(def: Dictionary) -> String:
	if def.is_empty():
		return ""
	if str(def.get("type", "")).strip_edges() != "equipment":
		return ""
	return str(def.get("equip_slot", "")).strip_edges()


static func is_equipment(def: Dictionary) -> bool:
	return not equip_slot_for_item(def).is_empty()


## Flat bonuses dict from item def (bonuses / legacy bonus).
static func bonuses_of(def: Dictionary) -> Dictionary:
	if def.is_empty():
		return {}
	var v: Variant = def.get("bonuses", def.get("bonus", {}))
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for k in (v as Dictionary).keys():
		out[str(k)] = int((v as Dictionary)[k])
	return out


## Stat key for enhance: weapons → p_atk else p_def (mirrors Equipment.enhance_stat_key).
static func enhance_stat_key_for_def(def: Dictionary) -> String:
	var eq_key := str(def.get("equip_slot", "")).strip_edges()
	if eq_key == "weapon_main" or eq_key == "weapon_off":
		return "p_atk"
	var bon := bonuses_of(def)
	if int(bon.get("p_atk", 0)) > 0 and int(bon.get("p_def", 0)) <= 0:
		return "p_atk"
	if int(bon.get("atk", 0)) > 0 and int(bon.get("def", 0)) <= 0 and int(bon.get("p_def", 0)) <= 0:
		return "p_atk"
	return "p_def"


## Catalog bonuses + enhance level (+1 p_atk or p_def per level).
static func effective_bonuses(def: Dictionary, enhance: int = 0) -> Dictionary:
	var out := bonuses_of(def)
	enhance = clampi(int(enhance), 0, 5)
	if enhance <= 0 or def.is_empty():
		return out
	var key := enhance_stat_key_for_def(def)
	out[key] = int(out.get(key, 0)) + enhance
	return out


## Paperdoll slot ids that can hold this catalog equip_slot key.
static func paperdoll_slots_for(equip_slot_key: String) -> Array[String]:
	equip_slot_key = equip_slot_key.strip_edges()
	var out: Array[String] = []
	if equip_slot_key.is_empty():
		return out
	if Equipment.SLOT_IDS.has(equip_slot_key):
		out.append(equip_slot_key)
		return out
	if equip_slot_key == "ring":
		out.append("ring_l")
		out.append("ring_r")
		return out
	if equip_slot_key == "earring":
		out.append("earring_l")
		out.append("earring_r")
		return out
	return out


## First occupied paperdoll item_id for this equip_slot family from a snapshot
## Array[{slot, item_id, ...}] (MockServer equipment.snapshot / HUD cache).
static func find_equipped_id(equip_slot_key: String, equipment_snapshot: Array) -> String:
	var entry := find_equipped_entry(equip_slot_key, equipment_snapshot)
	return str(entry.get("item_id", "")).strip_edges()


## First occupied paperdoll snapshot row for equip_slot family.
static func find_equipped_entry(equip_slot_key: String, equipment_snapshot: Array) -> Dictionary:
	var slots := paperdoll_slots_for(equip_slot_key)
	if slots.is_empty():
		return {}
	var by_slot: Dictionary = {}
	for it in equipment_snapshot:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var sid := str(it.get("slot", "")).strip_edges()
		if sid.is_empty():
			continue
		by_slot[sid] = it
	for sid in slots:
		var row: Variant = by_slot.get(sid, {})
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid2 := str(row.get("item_id", "")).strip_edges()
		if not iid2.is_empty():
			return row
	return {}


static func _stat_label(key: String) -> String:
	return str(STAT_LABELS_ZH.get(key, key))


static func _ordered_stat_keys(a: Dictionary, b: Dictionary) -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for k in STAT_ORDER:
		if a.has(k) or b.has(k):
			out.append(k)
			seen[k] = true
	var rest: Array = []
	for k in a.keys():
		var ks := str(k)
		if not seen.has(ks):
			rest.append(ks)
			seen[ks] = true
	for k2 in b.keys():
		var ks2 := str(k2)
		if not seen.has(ks2):
			rest.append(ks2)
			seen[ks2] = true
	rest.sort()
	for r in rest:
		out.append(str(r))
	return out


static func _format_delta(label: String, cur_v: int, new_v: int) -> String:
	var d: int = new_v - cur_v
	var sign := "+%d" % d if d >= 0 else "%d" % d
	return "%s %d → %d (%s)" % [label, cur_v, new_v, sign]


static func _format_absolute(label: String, v: int) -> String:
	return "%s %d" % [label, v]


## Absolute bonus lines for an equipped / hovered piece (no compare).
## enhance adds +N to p_atk (weapon) or p_def (armor).
static func format_bonus_lines(def: Dictionary, enhance: int = 0) -> PackedStringArray:
	var lines: PackedStringArray = []
	var bon := effective_bonuses(def, enhance)
	if bon.is_empty():
		return lines
	for k in _ordered_stat_keys(bon, {}):
		var v: int = int(bon.get(k, 0))
		if v == 0:
			continue
		lines.append(_format_absolute(_stat_label(k), v))
	return lines


## Build Chinese tip. Non-equipment → base_lines unchanged.
## equipped_def_or_empty empty →「当前：空」+ absolute hovered stats.
## Otherwise → delta lines 物攻 5 → 8 (+3).
## item_enhance / equipped_enhance fold +N into compared bonuses.
static func format_compare_tip(
	item_def: Dictionary,
	equipped_def_or_empty: Dictionary,
	base_lines: String,
	item_enhance: int = 0,
	equipped_enhance: int = 0
) -> String:
	if not is_equipment(item_def):
		return base_lines
	item_enhance = clampi(int(item_enhance), 0, 5)
	equipped_enhance = clampi(int(equipped_enhance), 0, 5)
	var new_bon := effective_bonuses(item_def, item_enhance)
	var lines: PackedStringArray = []
	if not base_lines.strip_edges().is_empty():
		lines.append(base_lines.strip_edges())
	else:
		var nm := str(item_def.get("name", "")).strip_edges()
		var iid := str(item_def.get("id", "")).strip_edges()
		if not nm.is_empty():
			lines.append(nm)
		if not iid.is_empty():
			lines.append(iid)
	var eq_empty := equipped_def_or_empty.is_empty() or str(equipped_def_or_empty.get("id", "")).strip_edges().is_empty()
	# Same item already on paperdoll → still show absolute (no self-delta noise).
	if not eq_empty and str(equipped_def_or_empty.get("id", "")) == str(item_def.get("id", "")):
		lines.append("当前：已装备")
		for bl in format_bonus_lines(item_def, item_enhance):
			lines.append(bl)
		return "\n".join(lines)
	if eq_empty:
		lines.append("当前：空")
		var abs_lines := format_bonus_lines(item_def, item_enhance)
		if abs_lines.is_empty():
			for k in _ordered_stat_keys(new_bon, {}):
				lines.append(_format_absolute(_stat_label(k), int(new_bon.get(k, 0))))
		else:
			for bl2 in abs_lines:
				lines.append(bl2)
		return "\n".join(lines)
	var cur_bon := effective_bonuses(equipped_def_or_empty, equipped_enhance)
	var cur_name := str(equipped_def_or_empty.get("name", "")).strip_edges()
	if cur_name.is_empty():
		cur_name = str(equipped_def_or_empty.get("id", "已装备"))
	var eq_enh := equipped_enhance
	if eq_enh > 0:
		cur_name = "%s +%d" % [cur_name, eq_enh]
	lines.append("当前：%s" % cur_name)
	var keys := _ordered_stat_keys(new_bon, cur_bon)
	if keys.is_empty():
		lines.append("（无属性差值）")
	else:
		for k in keys:
			var cv: int = int(cur_bon.get(k, 0))
			var nv: int = int(new_bon.get(k, 0))
			if cv == 0 and nv == 0:
				continue
			lines.append(_format_delta(_stat_label(k), cv, nv))
	return "\n".join(lines)
