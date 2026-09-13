extends RefCounted
## Server-side paperdoll equipment (MockServer authoritative).
## Slot keys are stable string ids; bag transfers happen in try_*_bag helpers.

## L2-like equip slots (order used by snapshot / HUD).
const SLOT_IDS: Array[String] = [
	"head",
	"chest",
	"hands",
	"legs",
	"feet",
	"weapon_main",
	"weapon_off",
	"necklace",
	"earring_l",
	"earring_r",
	"ring_l",
	"ring_r",
]

## Short Chinese hint for empty slots (tooltip / label).
const SLOT_LABELS_ZH: Dictionary = {
	"head": "头",
	"chest": "胸",
	"hands": "手",
	"legs": "腿",
	"feet": "脚",
	"weapon_main": "主手",
	"weapon_off": "副手",
	"necklace": "项链",
	"earring_l": "耳L",
	"earring_r": "耳R",
	"ring_l": "戒L",
	"ring_r": "戒R",
}

## slot_id -> item_id (empty string = empty)
var _equipped: Dictionary = {}
## Optional ItemCatalog for equip_slot / bonuses / names.
var catalog = null


func set_catalog(p_catalog) -> void:
	catalog = p_catalog


func clear() -> void:
	_equipped.clear()
	for sid in SLOT_IDS:
		_equipped[sid] = ""


func _ensure_slots() -> void:
	for sid in SLOT_IDS:
		if not _equipped.has(sid):
			_equipped[sid] = ""


func get_item_in(slot: String) -> String:
	_ensure_slots()
	return str(_equipped.get(slot.strip_edges(), "")).strip_edges()


func is_empty(slot: String) -> bool:
	return get_item_in(slot).is_empty()


## First paperdoll slot holding item_id, or "" if not equipped.
func find_slot_of(item_id: String) -> String:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return ""
	_ensure_slots()
	for sid in SLOT_IDS:
		if get_item_in(sid) == item_id:
			return sid
	return ""


## HUD-friendly snapshot: Array of {slot, item_id, name, icon_index?, icon?, icon_ref?}.
func snapshot() -> Array:
	_ensure_slots()
	var out: Array = []
	for sid in SLOT_IDS:
		var iid := get_item_in(sid)
		var nm := ""
		var row := {"slot": sid, "item_id": iid, "name": nm, "icon_index": -1}
		if not iid.is_empty():
			nm = _item_name(iid)
			row["name"] = nm
			var def: Dictionary = _item_def(iid)
			if not def.is_empty():
				row["icon_index"] = int(def.get("icon_index", -1))
				var ic := str(def.get("icon", "")).strip_edges()
				if not ic.is_empty():
					row["icon"] = ic
					row["icon_ref"] = str(def.get("icon_ref", "content://icon/%s" % ic))
		out.append(row)
	return out


## Flat bonus sum across equipped items (e.g. {"p_atk":3,"p_def":1}).
func total_bonuses() -> Dictionary:
	_ensure_slots()
	var totals: Dictionary = {}
	for sid in SLOT_IDS:
		var iid := get_item_in(sid)
		if iid.is_empty():
			continue
		var def: Dictionary = _item_def(iid)
		var bonus_v: Variant = def.get("bonuses", def.get("bonus", {}))
		if typeof(bonus_v) != TYPE_DICTIONARY:
			continue
		for k in (bonus_v as Dictionary).keys():
			var key := str(k)
			totals[key] = int(totals.get(key, 0)) + int(bonus_v[k])
	return totals


## Validate catalog equip_slot against a concrete paperdoll slot.
func slot_compatible(equip_slot_key: String, paperdoll_slot: String) -> bool:
	equip_slot_key = equip_slot_key.strip_edges()
	paperdoll_slot = paperdoll_slot.strip_edges()
	if equip_slot_key.is_empty() or paperdoll_slot.is_empty():
		return false
	if not SLOT_IDS.has(paperdoll_slot):
		return false
	if equip_slot_key == paperdoll_slot:
		return true
	# Generic family keys: ring → ring_l/ring_r; earring → earring_l/earring_r
	if equip_slot_key == "ring" and (paperdoll_slot == "ring_l" or paperdoll_slot == "ring_r"):
		return true
	if equip_slot_key == "earring" and (paperdoll_slot == "earring_l" or paperdoll_slot == "earring_r"):
		return true
	return false


## Resolve preferred / auto target slot for an item def's equip_slot field.
## Returns "" if no valid slot.
func resolve_slot(equip_slot_key: String, preferred_slot: String = "") -> String:
	equip_slot_key = equip_slot_key.strip_edges()
	preferred_slot = preferred_slot.strip_edges()
	if equip_slot_key.is_empty():
		return ""
	# Exact paperdoll key.
	if SLOT_IDS.has(equip_slot_key):
		if preferred_slot.is_empty() or preferred_slot == equip_slot_key:
			return equip_slot_key
		return "" if preferred_slot != equip_slot_key else equip_slot_key
	# Family: ring / earring — prefer preferred if compatible, else first empty, else replace first.
	var family: Array[String] = []
	if equip_slot_key == "ring":
		family = ["ring_l", "ring_r"]
	elif equip_slot_key == "earring":
		family = ["earring_l", "earring_r"]
	else:
		return ""
	if not preferred_slot.is_empty():
		if family.has(preferred_slot):
			return preferred_slot
		return ""
	for sid in family:
		if is_empty(sid):
			return sid
	return family[0]


## Equip without touching inventory. Returns {ok, reason, unequipped_item_id?, slot?}.
func try_equip(item_id: String, preferred_slot: String = "") -> Dictionary:
	item_id = item_id.strip_edges()
	preferred_slot = preferred_slot.strip_edges()
	_ensure_slots()
	if item_id.is_empty():
		return {"ok": false, "reason": "invalid"}
	var def: Dictionary = _item_def(item_id)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	if str(def.get("type", "")).strip_edges() != "equipment":
		return {"ok": false, "reason": "not_equipment"}
	var eq_key := str(def.get("equip_slot", "")).strip_edges()
	if eq_key.is_empty():
		return {"ok": false, "reason": "no_equip_slot"}
	var target := resolve_slot(eq_key, preferred_slot)
	if target.is_empty():
		return {"ok": false, "reason": "incompatible_slot"}
	if not preferred_slot.is_empty() and not slot_compatible(eq_key, preferred_slot):
		return {"ok": false, "reason": "incompatible_slot"}
	# If preferred given, use it when compatible (resolve_slot already checked).
	if not preferred_slot.is_empty() and slot_compatible(eq_key, preferred_slot):
		target = preferred_slot
	var prev := get_item_in(target)
	_equipped[target] = item_id
	return {
		"ok": true,
		"reason": "",
		"unequipped_item_id": prev,
		"slot": target,
	}


## Unequip without touching inventory. Returns {ok, item_id, reason}.
func try_unequip(slot: String) -> Dictionary:
	slot = slot.strip_edges()
	_ensure_slots()
	if not SLOT_IDS.has(slot):
		return {"ok": false, "item_id": "", "reason": "invalid_slot"}
	var iid := get_item_in(slot)
	if iid.is_empty():
		return {"ok": false, "item_id": "", "reason": "empty"}
	_equipped[slot] = ""
	return {"ok": true, "item_id": iid, "reason": ""}


## Remove 1 from bag, equip into slot, put previous (if any) back into bag.
## Returns {ok, reason, slot?, unequipped_item_id?, actions extras via caller}.
func try_equip_from_bag(inventory, item_id: String, preferred_slot: String = "") -> Dictionary:
	item_id = item_id.strip_edges()
	preferred_slot = preferred_slot.strip_edges()
	if inventory == null:
		return {"ok": false, "reason": "no_inventory"}
	if not inventory.has_item(item_id, 1):
		return {"ok": false, "reason": "not_in_bag"}
	# Pre-validate without mutating so we don't consume on reject.
	var def: Dictionary = _item_def(item_id)
	if def.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	if str(def.get("type", "")).strip_edges() != "equipment":
		return {"ok": false, "reason": "not_equipment"}
	var eq_key := str(def.get("equip_slot", "")).strip_edges()
	var target := resolve_slot(eq_key, preferred_slot)
	if target.is_empty() or (not preferred_slot.is_empty() and not slot_compatible(eq_key, preferred_slot)):
		return {"ok": false, "reason": "incompatible_slot"}
	if not preferred_slot.is_empty() and slot_compatible(eq_key, preferred_slot):
		target = preferred_slot
	var prev := get_item_in(target)
	# Ensure bag can accept the swap piece before consuming.
	if not prev.is_empty():
		# After removing item_id, room may open; still check capacity for different id.
		if prev != item_id and not inventory.can_accept(prev, 1):
			# Soft: if bag full and prev needs a new slot, reject.
			if inventory.slot_count() >= int(inventory.max_slots) and inventory.get_qty(prev) <= 0:
				return {"ok": false, "reason": "bag_full"}
	if not inventory.consume(item_id, 1):
		return {"ok": false, "reason": "not_in_bag"}
	_ensure_slots()
	_equipped[target] = item_id
	if not prev.is_empty():
		var added: int = inventory.add_item(prev, 1)
		if added < 1:
			# Rollback: restore previous to slot and return consumed item to bag.
			_equipped[target] = prev
			inventory.add_item(item_id, 1)
			return {"ok": false, "reason": "bag_full"}
	return {
		"ok": true,
		"reason": "",
		"slot": target,
		"unequipped_item_id": prev,
		"item_id": item_id,
	}


## Clear slot and put item into bag. Returns {ok, item_id, reason}.
func try_unequip_to_bag(inventory, slot: String) -> Dictionary:
	slot = slot.strip_edges()
	if inventory == null:
		return {"ok": false, "item_id": "", "reason": "no_inventory"}
	var r: Dictionary = try_unequip(slot)
	if not bool(r.get("ok", false)):
		return r
	var iid := str(r.get("item_id", ""))
	var added: int = inventory.add_item(iid, 1)
	if added < 1:
		# Rollback unequip.
		_equipped[slot] = iid
		return {"ok": false, "item_id": iid, "reason": "bag_full"}
	return {"ok": true, "item_id": iid, "reason": "", "slot": slot}


func _item_def(item_id: String) -> Dictionary:
	if catalog != null and catalog.has_method("get_item"):
		return catalog.get_item(item_id)
	return {}


func _item_name(item_id: String) -> String:
	var def: Dictionary = _item_def(item_id)
	if def.is_empty():
		return item_id
	var n := str(def.get("name", "")).strip_edges()
	return n if not n.is_empty() else item_id


static func label_zh(slot_id: String) -> String:
	return str(SLOT_LABELS_ZH.get(slot_id.strip_edges(), slot_id))
