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
## Per-slot durability while equipped (thin: not persisted into bag on unequip).
## Death wear: apply_death_wear(). Combat hit wear (weapons): wear_weapon().
var _durability: Dictionary = {}
var _durability_max: Dictionary = {}
## Per-slot soul-bind flag (survives unequip back into bag).
var _bound: Dictionary = {}
## Per-slot enhance level 0–5 (survives unequip back into bag metadata).
var _enhance: Dictionary = {}
## Default max when item def / catalog omits durability_max.
const DEFAULT_DURABILITY_MAX := 100
const ENHANCE_MAX := 5
const ENHANCE_STONE_ID := "enhance_stone"
## Optional ItemCatalog for equip_slot / bonuses / names.
var catalog = null


func set_catalog(p_catalog) -> void:
	catalog = p_catalog


func clear() -> void:
	_equipped.clear()
	_durability.clear()
	_durability_max.clear()
	_bound.clear()
	_enhance.clear()
	for sid in SLOT_IDS:
		_equipped[sid] = ""


func _ensure_slots() -> void:
	for sid in SLOT_IDS:
		if not _equipped.has(sid):
			_equipped[sid] = ""
		# Drop orphan durability when slot empty.
		if str(_equipped.get(sid, "")).strip_edges().is_empty():
			_durability.erase(sid)
			_durability_max.erase(sid)
			_bound.erase(sid)
			_enhance.erase(sid)


func get_item_in(slot: String) -> String:
	_ensure_slots()
	return str(_equipped.get(slot.strip_edges(), "")).strip_edges()


func is_empty(slot: String) -> bool:
	return get_item_in(slot).is_empty()


func _default_max_for(item_id: String) -> int:
	var def: Dictionary = _item_def(item_id)
	var m := int(def.get("durability_max", DEFAULT_DURABILITY_MAX))
	return maxi(m, 1)


func _init_slot_durability(slot: String, item_id: String) -> void:
	slot = slot.strip_edges()
	item_id = item_id.strip_edges()
	if slot.is_empty() or item_id.is_empty():
		return
	var m := _default_max_for(item_id)
	_durability_max[slot] = m
	_durability[slot] = m


func _clear_slot_durability(slot: String) -> void:
	slot = slot.strip_edges()
	_durability.erase(slot)
	_durability_max.erase(slot)


## Catalog: bind == "equip" or bind_on_equip true → soul-bind on first equip.
static func is_bind_on_equip(def: Dictionary) -> bool:
	if def.is_empty():
		return false
	if bool(def.get("bind_on_equip", false)):
		return true
	var b := str(def.get("bind", "")).strip_edges().to_lower()
	return b == "equip" or b == "on_equip" or b == "bind_on_equip"


## Catalog: bind == "pickup" / bind_on_pickup true → soul-bind when looted into bag.
static func is_bind_on_pickup(def: Dictionary) -> bool:
	if def.is_empty():
		return false
	if bool(def.get("bind_on_pickup", false)):
		return true
	var b := str(def.get("bind", "")).strip_edges().to_lower()
	return b == "pickup" or b == "on_pickup" or b == "bind_on_pickup" or b == "bop"


func is_slot_bound(slot: String) -> bool:
	return bool(_bound.get(slot.strip_edges(), false))


func set_slot_bound(slot: String, on: bool) -> void:
	slot = slot.strip_edges()
	if slot.is_empty():
		return
	if on:
		_bound[slot] = true
	else:
		_bound.erase(slot)


func get_enhance(slot: String) -> int:
	slot = slot.strip_edges()
	if is_empty(slot):
		return 0
	return clampi(int(_enhance.get(slot, 0)), 0, ENHANCE_MAX)


func set_enhance(slot: String, level: int) -> void:
	slot = slot.strip_edges()
	if slot.is_empty() or is_empty(slot):
		return
	level = clampi(int(level), 0, ENHANCE_MAX)
	if level <= 0:
		_enhance.erase(slot)
	else:
		_enhance[slot] = level


## Gold cost to go from current level → level+1.
static func enhance_cost(level: int) -> int:
	level = clampi(int(level), 0, ENHANCE_MAX)
	return 10 * (level + 1)


## Stat key granted per enhance level: weapons → p_atk, armor → p_def.
func enhance_stat_key(slot: String, item_id: String = "") -> String:
	slot = slot.strip_edges()
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		item_id = get_item_in(slot)
	if slot == "weapon_main" or slot == "weapon_off":
		return "p_atk"
	var def: Dictionary = _item_def(item_id)
	var bonus_v: Variant = def.get("bonuses", def.get("bonus", {}))
	if typeof(bonus_v) == TYPE_DICTIONARY:
		var b: Dictionary = bonus_v
		if int(b.get("p_atk", 0)) > 0 and int(b.get("p_def", 0)) <= 0:
			return "p_atk"
		if int(b.get("atk", 0)) > 0 and int(b.get("def", 0)) <= 0 and int(b.get("p_def", 0)) <= 0:
			return "p_atk"
	var eq_key := str(def.get("equip_slot", "")).strip_edges()
	if eq_key == "weapon_main" or eq_key == "weapon_off":
		return "p_atk"
	return "p_def"


## Flat bonuses from enhance level alone.
func enhance_bonuses_for(slot: String, level: int = -1) -> Dictionary:
	if level < 0:
		level = get_enhance(slot)
	level = clampi(int(level), 0, ENHANCE_MAX)
	if level <= 0 or is_empty(slot):
		return {}
	var key := enhance_stat_key(slot)
	return {key: level}


static func apply_enhance_to_bonuses(base: Dictionary, stat_key: String, level: int) -> Dictionary:
	var out: Dictionary = base.duplicate()
	level = clampi(int(level), 0, ENHANCE_MAX)
	stat_key = str(stat_key).strip_edges()
	if level <= 0 or stat_key.is_empty():
		return out
	out[stat_key] = int(out.get(stat_key, 0)) + level
	return out


func get_durability(slot: String) -> int:
	slot = slot.strip_edges()
	if is_empty(slot):
		return 0
	if not _durability.has(slot):
		_init_slot_durability(slot, get_item_in(slot))
	return maxi(int(_durability.get(slot, 0)), 0)


func get_durability_max(slot: String) -> int:
	slot = slot.strip_edges()
	if is_empty(slot):
		return 0
	if not _durability_max.has(slot):
		_init_slot_durability(slot, get_item_in(slot))
	return maxi(int(_durability_max.get(slot, DEFAULT_DURABILITY_MAX)), 1)


## Broken gear (dur ≤ 0) contributes no ATK/DEF until repaired.
func is_broken(slot: String) -> bool:
	if is_empty(slot):
		return false
	return get_durability(slot) <= 0


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


## HUD-friendly snapshot: Array of {slot, item_id, name, durability, durability_max, broken, icon_index?, icon?, icon_ref?}.
func snapshot() -> Array:
	_ensure_slots()
	var out: Array = []
	for sid in SLOT_IDS:
		var iid := get_item_in(sid)
		var nm := ""
		var row := {
			"slot": sid,
			"item_id": iid,
			"name": nm,
			"icon_index": -1,
			"durability": 0,
			"durability_max": 0,
			"broken": false,
			"enhance": 0,
		}
		if not iid.is_empty():
			nm = _item_name(iid)
			row["name"] = nm
			row["durability"] = get_durability(sid)
			row["durability_max"] = get_durability_max(sid)
			row["broken"] = is_broken(sid)
			var enh := get_enhance(sid)
			row["enhance"] = enh
			if is_slot_bound(sid):
				row["bound"] = true
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
## Broken pieces (durability ≤ 0) are excluded until repaired.
func total_bonuses() -> Dictionary:
	_ensure_slots()
	var totals: Dictionary = {}
	# Two-hand bonuses come only from weapon_main (off must be empty, but skip as safety).
	var skip_off := main_is_two_handed()
	for sid in SLOT_IDS:
		if sid == "weapon_off" and skip_off:
			continue
		var iid := get_item_in(sid)
		if iid.is_empty():
			continue
		if is_broken(sid):
			continue
		var def: Dictionary = _item_def(iid)
		var bonus_v: Variant = def.get("bonuses", def.get("bonus", {}))
		if typeof(bonus_v) == TYPE_DICTIONARY:
			for k in (bonus_v as Dictionary).keys():
				var key := str(k)
				totals[key] = int(totals.get(key, 0)) + int(bonus_v[k])
		var enh := get_enhance(sid)
		if enh > 0:
			var ek := enhance_stat_key(sid, iid)
			totals[ek] = int(totals.get(ek, 0)) + enh
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



## Item hand: "main"|"off"|"both" (both = two-handed). Inferred from equip_slot when omitted.
static func hand_of_def(def: Dictionary) -> String:
	if def.is_empty():
		return ""
	var h := str(def.get("hand", "")).strip_edges().to_lower()
	if h == "main" or h == "off" or h == "both":
		return h
	if h in ["two", "twohand", "two_hand", "2h", "2-hand"]:
		return "both"
	var eq := str(def.get("equip_slot", "")).strip_edges()
	if eq == "weapon_off":
		return "off"
	if eq == "weapon_main":
		return "main"
	return ""


func hand_of(item_id: String) -> String:
	return hand_of_def(_item_def(item_id))


func is_two_handed(item_id: String) -> bool:
	return hand_of(item_id) == "both"


## True when weapon_main holds a two-handed weapon (blocks offhand).
func main_is_two_handed() -> bool:
	var mid := get_item_in("weapon_main")
	return not mid.is_empty() and is_two_handed(mid)


## Whether item hand restriction allows this paperdoll weapon/armor slot.
static func hand_slot_compatible(hand: String, paperdoll_slot: String) -> bool:
	hand = hand.strip_edges().to_lower()
	paperdoll_slot = paperdoll_slot.strip_edges()
	if hand.is_empty():
		return true
	if hand == "off":
		return paperdoll_slot == "weapon_off"
	if hand == "main" or hand == "both":
		# Two-hand / main-hand only occupy weapon_main (off cleared separately for both).
		return paperdoll_slot == "weapon_main"
	return true




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
## Two-hand (`hand:"both"`) clears weapon_off; offhand blocked while two-hand main equipped.
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
	var hand := hand_of_def(def)
	var target := resolve_slot(eq_key, preferred_slot)
	if target.is_empty():
		return {"ok": false, "reason": "incompatible_slot"}
	if not preferred_slot.is_empty() and not slot_compatible(eq_key, preferred_slot):
		return {"ok": false, "reason": "incompatible_slot"}
	# If preferred given, use it when compatible (resolve_slot already checked).
	if not preferred_slot.is_empty() and slot_compatible(eq_key, preferred_slot):
		target = preferred_slot
	if not hand_slot_compatible(hand, target):
		return {"ok": false, "reason": "incompatible_slot"}
	# Cannot equip offhand while a two-hand weapon occupies main.
	if target == "weapon_off" and main_is_two_handed():
		return {
			"ok": false,
			"reason": "two_hand_blocks_off",
			"message": "双手武器占用副手。",
		}
	var cleared_off := ""
	var cleared_off_bound := false
	var cleared_off_enhance := 0
	if hand == "both":
		# Two-hand into main: clear offhand (bagless — caller may reclaim item).
		cleared_off = get_item_in("weapon_off")
		if not cleared_off.is_empty():
			cleared_off_bound = is_slot_bound("weapon_off")
			cleared_off_enhance = get_enhance("weapon_off")
			_equipped["weapon_off"] = ""
			_clear_slot_durability("weapon_off")
			set_slot_bound("weapon_off", false)
			_enhance.erase("weapon_off")
	var prev := get_item_in(target)
	var prev_bound := is_slot_bound(target)
	var prev_enhance := get_enhance(target)
	_equipped[target] = item_id
	_init_slot_durability(target, item_id)
	set_enhance(target, 0)
	var newly_bound := false
	if is_bind_on_equip(def):
		# Bagless path: bind on equip; message only when slot wasn't already this bound piece.
		newly_bound = not (prev == item_id and prev_bound)
		set_slot_bound(target, true)
	else:
		set_slot_bound(target, false)
	var out := {
		"ok": true,
		"reason": "",
		"unequipped_item_id": prev,
		"unequipped_enhance": prev_enhance,
		"slot": target,
		"newly_bound": newly_bound,
		"bound": is_slot_bound(target),
		"enhance": get_enhance(target),
	}
	if not cleared_off.is_empty():
		out["unequipped_offhand_item_id"] = cleared_off
		out["unequipped_offhand_bound"] = cleared_off_bound
		out["unequipped_offhand_enhance"] = cleared_off_enhance
	return out


## Unequip without touching inventory. Returns {ok, item_id, reason}.
## Thin: durability on slot is discarded (not stored in bag).
func try_unequip(slot: String) -> Dictionary:
	slot = slot.strip_edges()
	_ensure_slots()
	if not SLOT_IDS.has(slot):
		return {"ok": false, "item_id": "", "reason": "invalid_slot"}
	var iid := get_item_in(slot)
	if iid.is_empty():
		return {"ok": false, "item_id": "", "reason": "empty"}
	var was_bound := is_slot_bound(slot)
	var was_enhance := get_enhance(slot)
	_equipped[slot] = ""
	_clear_slot_durability(slot)
	set_slot_bound(slot, false)
	_enhance.erase(slot)
	return {"ok": true, "item_id": iid, "reason": "", "bound": was_bound, "enhance": was_enhance}


## Remove 1 from bag, equip into slot, put previous (if any) back into bag.
## Remove 1 from bag, equip into slot, put previous (if any) back into bag.
## Two-hand clears weapon_off into bag (prefer force unequip); fails with bag_full if no room.
## Returns {ok, reason, slot?, unequipped_item_id?, unequipped_offhand_item_id?}.
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
	var hand := hand_of_def(def)
	var target := resolve_slot(eq_key, preferred_slot)
	if target.is_empty() or (not preferred_slot.is_empty() and not slot_compatible(eq_key, preferred_slot)):
		return {"ok": false, "reason": "incompatible_slot"}
	if not preferred_slot.is_empty() and slot_compatible(eq_key, preferred_slot):
		target = preferred_slot
	if not hand_slot_compatible(hand, target):
		return {"ok": false, "reason": "incompatible_slot"}
	# Cannot equip offhand while two-hand is equipped.
	if target == "weapon_off" and main_is_two_handed():
		return {
			"ok": false,
			"reason": "two_hand_blocks_off",
			"message": "双手武器占用副手。",
		}
	var prev := get_item_in(target)
	var prev_bound := is_slot_bound(target)
	var off_id := ""
	var off_bound := false
	var off_enhance := 0
	if hand == "both":
		off_id = get_item_in("weapon_off")
		if not off_id.is_empty():
			off_bound = is_slot_bound("weapon_off")
			off_enhance = get_enhance("weapon_off")
	# Soft capacity: after consuming item_id, bag must accept prev (+ off for two-hand).
	if not prev.is_empty():
		if prev != item_id and not inventory.can_accept(prev, 1):
			if inventory.slot_count() >= int(inventory.max_slots) and inventory.get_qty(prev) <= 0:
				return {"ok": false, "reason": "bag_full"}
	if not off_id.is_empty() and off_id != item_id and off_id != prev:
		if not inventory.can_accept(off_id, 1):
			# After consume may free 1 slot; if still need room for prev+off, reject early when tight.
			if inventory.slot_count() >= int(inventory.max_slots) and inventory.get_qty(off_id) <= 0:
				# May still succeed after consume+prev merge — soft continue; hard-fail below.
				pass
	var taken: Dictionary = {"ok": false, "bound": false, "enhance": 0}
	if inventory.has_method("consume_one"):
		taken = inventory.consume_one(item_id)
	else:
		if inventory.consume(item_id, 1):
			taken = {"ok": true, "bound": false, "enhance": 0}
	if not bool(taken.get("ok", false)):
		return {"ok": false, "reason": "not_in_bag"}
	var from_bound := bool(taken.get("bound", false))
	var from_enhance := clampi(int(taken.get("enhance", 0)), 0, ENHANCE_MAX)
	_ensure_slots()
	# Force-unequip offhand to bag first when equipping two-hand.
	if not off_id.is_empty():
		var off_dur := int(_durability.get("weapon_off", -1))
		var off_dmax := int(_durability_max.get("weapon_off", -1))
		_equipped["weapon_off"] = ""
		_clear_slot_durability("weapon_off")
		set_slot_bound("weapon_off", false)
		_enhance.erase("weapon_off")
		var off_added: int = inventory.add_item(off_id, 1, off_bound, off_enhance)
		if off_added < 1:
			# Rollback off clear + restore consumed item.
			_equipped["weapon_off"] = off_id
			if off_dur >= 0:
				_durability["weapon_off"] = off_dur
				_durability_max["weapon_off"] = off_dmax if off_dmax > 0 else _default_max_for(off_id)
			else:
				_init_slot_durability("weapon_off", off_id)
			set_slot_bound("weapon_off", off_bound)
			set_enhance("weapon_off", off_enhance)
			inventory.add_item(item_id, 1, from_bound, from_enhance)
			return {"ok": false, "reason": "bag_full"}
	var prev_dur := int(_durability.get(target, -1))
	var prev_dmax := int(_durability_max.get(target, -1))
	var prev_enhance := get_enhance(target)
	_equipped[target] = item_id
	_init_slot_durability(target, item_id)
	set_enhance(target, from_enhance)
	var boe := is_bind_on_equip(def)
	var newly_bound := boe and not from_bound
	var slot_bound := from_bound or boe
	set_slot_bound(target, slot_bound)
	if not prev.is_empty():
		var added: int = inventory.add_item(prev, 1, prev_bound, prev_enhance)
		if added < 1:
			# Rollback: restore previous to slot, re-equip off if cleared, return consumed item.
			_equipped[target] = prev
			if prev_dur >= 0:
				_durability[target] = prev_dur
				_durability_max[target] = prev_dmax if prev_dmax > 0 else _default_max_for(prev)
			else:
				_init_slot_durability(target, prev)
			set_slot_bound(target, prev_bound)
			set_enhance(target, prev_enhance)
			if not off_id.is_empty():
				# Pull off back from bag if we added it.
				if inventory.has_method("consume_one"):
					inventory.consume_one(off_id)
				else:
					inventory.consume(off_id, 1)
				_equipped["weapon_off"] = off_id
				_init_slot_durability("weapon_off", off_id)
				set_slot_bound("weapon_off", off_bound)
				set_enhance("weapon_off", off_enhance)
			inventory.add_item(item_id, 1, from_bound, from_enhance)
			return {"ok": false, "reason": "bag_full"}
		# Previous piece left the paperdoll — drop its durability (thin).
	var result := {
		"ok": true,
		"reason": "",
		"slot": target,
		"unequipped_item_id": prev,
		"item_id": item_id,
		"newly_bound": newly_bound,
		"bound": slot_bound,
		"enhance": get_enhance(target),
	}
	if not off_id.is_empty():
		result["unequipped_offhand_item_id"] = off_id
	return result


## Clear slot and put item into bag. Returns {ok, item_id, reason}.
func try_unequip_to_bag(inventory, slot: String) -> Dictionary:
	slot = slot.strip_edges()
	if inventory == null:
		return {"ok": false, "item_id": "", "reason": "no_inventory"}
	# Snapshot durability before unequip clears it (rollback needs it).
	var saved_dur := get_durability(slot) if not is_empty(slot) else 0
	var saved_max := get_durability_max(slot) if not is_empty(slot) else 0
	var saved_enhance := get_enhance(slot) if not is_empty(slot) else 0
	var r: Dictionary = try_unequip(slot)
	if not bool(r.get("ok", false)):
		return r
	var iid := str(r.get("item_id", ""))
	var was_bound := bool(r.get("bound", false))
	var was_enhance := clampi(int(r.get("enhance", saved_enhance)), 0, ENHANCE_MAX)
	var added: int = inventory.add_item(iid, 1, was_bound, was_enhance)
	if added < 1:
		# Rollback unequip + durability + bound + enhance.
		_equipped[slot] = iid
		_durability[slot] = saved_dur
		_durability_max[slot] = saved_max if saved_max > 0 else _default_max_for(iid)
		set_slot_bound(slot, was_bound)
		set_enhance(slot, was_enhance)
		return {"ok": false, "item_id": iid, "reason": "bag_full"}
	return {"ok": true, "item_id": iid, "reason": "", "slot": slot, "bound": was_bound, "enhance": was_enhance}


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


## Death durability loss. fraction of max, min 1 per piece (leaves piece equipped at 0 = broken).
## Returns {count, damaged:[{slot,item_id,before,after,max}]}.
func apply_death_wear(fraction: float = 0.1) -> Dictionary:
	_ensure_slots()
	fraction = clampf(fraction, 0.0, 1.0)
	var damaged: Array = []
	for sid in SLOT_IDS:
		var iid := get_item_in(sid)
		if iid.is_empty():
			continue
		var dmax := get_durability_max(sid)
		var before := get_durability(sid)
		if before <= 0:
			continue
		var loss: int = maxi(1, int(ceili(float(dmax) * fraction)))
		var after: int = maxi(0, before - loss)
		_durability[sid] = after
		damaged.append({
			"slot": sid,
			"item_id": iid,
			"before": before,
			"after": after,
			"max": dmax,
		})
	return {"count": damaged.size(), "damaged": damaged}


## Combat hit wear on an equipped weapon slot (default main-hand). amount ≥ 1.
## At 0: destroy (clear slot, no bag return) like gather tools. Offhand optional via slot.
## Returns {ok, broken, durability, durability_max, item_id, slot, reason?}.
func wear_weapon(amount: int = 1, slot: String = "weapon_main") -> Dictionary:
	slot = slot.strip_edges()
	amount = maxi(int(amount), 1)
	_ensure_slots()
	if slot != "weapon_main" and slot != "weapon_off":
		return {"ok": false, "broken": false, "durability": 0, "durability_max": 0, "item_id": "", "slot": slot, "reason": "not_weapon"}
	var iid := get_item_in(slot)
	if iid.is_empty():
		return {"ok": false, "broken": false, "durability": 0, "durability_max": 0, "item_id": "", "slot": slot, "reason": "empty"}
	var dmax := get_durability_max(slot)
	var before := get_durability(slot)
	if before <= 0:
		# Already broken (death wear) — still destroy on combat wear request.
		_equipped[slot] = ""
		_clear_slot_durability(slot)
		set_slot_bound(slot, false)
		_enhance.erase(slot)
		return {"ok": true, "broken": true, "durability": 0, "durability_max": dmax, "item_id": iid, "slot": slot}
	var after: int = maxi(0, before - amount)
	_durability[slot] = after
	if after > 0:
		return {"ok": true, "broken": false, "durability": after, "durability_max": dmax, "item_id": iid, "slot": slot}
	# Break + remove (no bag return).
	_equipped[slot] = ""
	_clear_slot_durability(slot)
	set_slot_bound(slot, false)
	_enhance.erase(slot)
	return {"ok": true, "broken": true, "durability": 0, "durability_max": dmax, "item_id": iid, "slot": slot}


## Repair one slot or all equipped pieces. cost_per_point gold per durability point restored.
## slot "" / "all" → every damaged piece. Returns {ok, reason, gold_spent, repaired, points}.
func try_repair(inventory, slot: String = "", cost_per_point: int = 1) -> Dictionary:
	_ensure_slots()
	slot = slot.strip_edges()
	cost_per_point = maxi(int(cost_per_point), 0)
	if inventory == null:
		return {"ok": false, "reason": "no_inventory", "gold_spent": 0, "repaired": [], "points": 0}
	var targets: Array[String] = []
	if slot.is_empty() or slot == "all":
		for sid in SLOT_IDS:
			if not is_empty(sid) and get_durability(sid) < get_durability_max(sid):
				targets.append(sid)
	else:
		if not SLOT_IDS.has(slot):
			return {"ok": false, "reason": "invalid_slot", "gold_spent": 0, "repaired": [], "points": 0}
		if is_empty(slot):
			return {"ok": false, "reason": "empty", "gold_spent": 0, "repaired": [], "points": 0}
		if get_durability(slot) >= get_durability_max(slot):
			return {"ok": false, "reason": "already_full", "gold_spent": 0, "repaired": [], "points": 0}
		targets.append(slot)
	if targets.is_empty():
		return {"ok": false, "reason": "nothing_to_repair", "gold_spent": 0, "repaired": [], "points": 0}
	var points := 0
	for sid in targets:
		points += get_durability_max(sid) - get_durability(sid)
	var cost: int = points * cost_per_point
	if cost > 0 and not inventory.try_spend_gold(cost):
		return {"ok": false, "reason": "no_gold", "gold_spent": 0, "repaired": [], "points": 0, "cost": cost}
	var repaired: Array = []
	for sid in targets:
		var before := get_durability(sid)
		var dmax := get_durability_max(sid)
		_durability[sid] = dmax
		repaired.append({
			"slot": sid,
			"item_id": get_item_in(sid),
			"before": before,
			"after": dmax,
			"max": dmax,
		})
	return {
		"ok": true,
		"reason": "",
		"gold_spent": cost,
		"repaired": repaired,
		"points": points,
		"cost": cost,
	}


## Portable kit repair: restore ceil(fraction * durability_max) on every damaged equipped slot (no gold).
## Returns {ok, reason, repaired:[{slot,item_id,before,after,max}], points}.
func apply_kit_repair(fraction: float = 0.3) -> Dictionary:
	_ensure_slots()
	fraction = clampf(fraction, 0.0, 1.0)
	var targets: Array[String] = []
	for sid in SLOT_IDS:
		if not is_empty(sid) and get_durability(sid) < get_durability_max(sid):
			targets.append(sid)
	if targets.is_empty():
		return {"ok": false, "reason": "nothing_to_repair", "repaired": [], "points": 0}
	var repaired: Array = []
	var points := 0
	for sid in targets:
		var before := get_durability(sid)
		var dmax := get_durability_max(sid)
		var gain: int = maxi(1, int(ceili(float(dmax) * fraction))) if fraction > 0.0 else 0
		var after: int = mini(dmax, before + gain)
		_durability[sid] = after
		var gained: int = after - before
		points += gained
		repaired.append({
			"slot": sid,
			"item_id": get_item_in(sid),
			"before": before,
			"after": after,
			"max": dmax,
		})
	return {
		"ok": true,
		"reason": "",
		"repaired": repaired,
		"points": points,
	}


## Enhance equipped gear at blacksmith: +1 level (≤5), consume 1 enhance_stone + gold.
## Cost = 10 * (current_level + 1). Always succeeds in v1. Returns {ok, reason, ...}.
func try_enhance(inventory, slot: String) -> Dictionary:
	_ensure_slots()
	slot = slot.strip_edges()
	if inventory == null:
		return {"ok": false, "reason": "no_inventory", "gold_spent": 0, "enhance": 0}
	if not SLOT_IDS.has(slot):
		return {"ok": false, "reason": "invalid_slot", "gold_spent": 0, "enhance": 0}
	if is_empty(slot):
		return {"ok": false, "reason": "empty", "gold_spent": 0, "enhance": 0}
	var cur := get_enhance(slot)
	if cur >= ENHANCE_MAX:
		return {"ok": false, "reason": "maxed", "gold_spent": 0, "enhance": cur}
	var cost: int = enhance_cost(cur)
	if not inventory.has_item(ENHANCE_STONE_ID, 1):
		return {"ok": false, "reason": "no_stone", "gold_spent": 0, "enhance": cur, "cost": cost}
	if cost > 0 and inventory.get_gold() < cost:
		return {"ok": false, "reason": "no_gold", "gold_spent": 0, "enhance": cur, "cost": cost}
	if not inventory.consume(ENHANCE_STONE_ID, 1):
		return {"ok": false, "reason": "no_stone", "gold_spent": 0, "enhance": cur, "cost": cost}
	if cost > 0 and not inventory.try_spend_gold(cost):
		# Rollback stone
		inventory.add_item(ENHANCE_STONE_ID, 1)
		return {"ok": false, "reason": "no_gold", "gold_spent": 0, "enhance": cur, "cost": cost}
	var nxt := cur + 1
	set_enhance(slot, nxt)
	return {
		"ok": true,
		"reason": "",
		"slot": slot,
		"item_id": get_item_in(slot),
		"enhance_before": cur,
		"enhance": nxt,
		"gold_spent": cost,
		"cost": cost,
		"stat_key": enhance_stat_key(slot),
	}


## True when any equipped slot is below durability_max.
func needs_repair() -> bool:
	_ensure_slots()
	for sid in SLOT_IDS:
		if not is_empty(sid) and get_durability(sid) < get_durability_max(sid):
			return true
	return false


static func label_zh(slot_id: String) -> String:
	return str(SLOT_LABELS_ZH.get(slot_id.strip_edges(), slot_id))
