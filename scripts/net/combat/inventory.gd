extends RefCounted
## Server-side player bag state (MockServer authoritative).
## Stack merges up to stack_max; soft slot capacity rejects adds when full.

## Default soft slot limit (distinct item stacks).
const MAX_SLOTS := 40
## Fallback when catalog has no stack_max.
const DEFAULT_STACK_MAX := 99

## item_id -> qty
var _slots: Dictionary = {}
## Wallet gold (not an inventory stack). MockServer authoritative.
var gold: int = 0
## Optional ItemCatalog for stack_max / display (set by MockServer).
var catalog = null
var max_slots: int = MAX_SLOTS

## Starter wallet on enter_world.
const STARTER_GOLD := 100


func set_catalog(p_catalog) -> void:
	catalog = p_catalog


func clear() -> void:
	_slots.clear()
	gold = 0


func grant_starter() -> void:
	## Default bag for a new session / enter_world.
	_slots = {
		"potion_hp_small": 5,
		"potion_mp_small": 3,
		"wooden_sword": 1,
		"leather_vest": 1,
	}
	gold = STARTER_GOLD


func get_gold() -> int:
	return maxi(gold, 0)


func add_gold(amount: int) -> int:
	## Returns new balance. Negative amounts ignored (use try_spend_gold).
	if amount <= 0:
		return get_gold()
	gold = get_gold() + amount
	return gold


func try_spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if get_gold() < amount:
		return false
	gold = get_gold() - amount
	return true


func get_qty(item_id: String) -> int:
	return int(_slots.get(item_id.strip_edges(), 0))


func has_item(item_id: String, qty: int = 1) -> bool:
	return get_qty(item_id) >= qty


func slot_count() -> int:
	var n: int = 0
	for k in _slots.keys():
		if int(_slots[k]) > 0:
			n += 1
	return n


func stack_max_for(item_id: String) -> int:
	item_id = item_id.strip_edges()
	if catalog != null and catalog.has_method("get_item"):
		var def: Dictionary = catalog.get_item(item_id)
		if not def.is_empty() and def.has("stack_max"):
			return maxi(int(def.get("stack_max", DEFAULT_STACK_MAX)), 1)
	return DEFAULT_STACK_MAX


## True if at least one unit of item_id can be accepted (new slot or stack room).
func can_accept(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or qty <= 0:
		return false
	var have: int = get_qty(item_id)
	var stack_max: int = stack_max_for(item_id)
	if have > 0:
		return have < stack_max
	return slot_count() < max_slots


## Add qty; merges into existing stack up to stack_max.
## Returns {ok, added, remaining, reason}. ok=false when nothing added (full / invalid).
func try_add_item(item_id: String, qty: int = 1) -> Dictionary:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or qty <= 0:
		return {"ok": false, "added": 0, "remaining": maxi(qty, 0), "reason": "invalid"}
	var stack_max: int = stack_max_for(item_id)
	var have: int = get_qty(item_id)
	if have <= 0 and slot_count() >= max_slots:
		return {"ok": false, "added": 0, "remaining": qty, "reason": "bag_full"}
	var room: int = stack_max - have
	if room <= 0:
		return {"ok": false, "added": 0, "remaining": qty, "reason": "stack_full"}
	var take: int = mini(room, qty)
	_slots[item_id] = have + take
	var left: int = qty - take
	return {
		"ok": true,
		"added": take,
		"remaining": left,
		"reason": ("stack_full" if left > 0 else ""),
	}


## Convenience: add as much as fits. Returns amount added.
func add_item(item_id: String, qty: int = 1) -> int:
	var r: Dictionary = try_add_item(item_id, qty)
	return int(r.get("added", 0))


func consume(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	if qty <= 0 or not has_item(item_id, qty):
		return false
	var left: int = get_qty(item_id) - qty
	if left <= 0:
		_slots.erase(item_id)
	else:
		_slots[item_id] = left
	return true


## Snapshot for inventory_update actions / client HUD (item stacks only).
func snapshot() -> Array:
	var out: Array = []
	for k in _slots.keys():
		var q: int = int(_slots[k])
		if q > 0:
			var iid := str(k)
			var row := {"id": iid, "qty": q}
			if catalog != null and catalog.has_method("get_item"):
				var def: Dictionary = catalog.get_item(iid)
				if not def.is_empty():
					row["icon_index"] = int(def.get("icon_index", -1))
					var ic := str(def.get("icon", "")).strip_edges()
					if not ic.is_empty():
						row["icon"] = ic
						row["icon_ref"] = str(def.get("icon_ref", "content://icon/%s" % ic))
			out.append(row)
	return out


## Full bag+wallet payload for inventory_update / enter_world.
func snapshot_state() -> Dictionary:
	return {"items": snapshot(), "gold": get_gold()}
