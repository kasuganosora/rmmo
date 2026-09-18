extends RefCounted
## Server-side player bag. Stacks occupy slots; add merges into existing stacks
## of the same id until stack_max, then opens a new slot. Split creates another stack.

const MAX_SLOTS := 40
const DEFAULT_STACK_MAX := 99
const STARTER_GOLD := 100

## [{id, qty}, ...] — one occupied bag cell each.
var _stacks: Array = []
var gold: int = 0
var catalog = null
var max_slots: int = MAX_SLOTS
## item_id -> true. Sell/drop blocked.
var locked: Dictionary = {}


func set_catalog(p_catalog) -> void:
	catalog = p_catalog


func clear() -> void:
	_stacks.clear()
	gold = 0
	locked.clear()


func grant_starter() -> void:
	_stacks.clear()
	gold = STARTER_GOLD
	add_item("potion_hp_small", 5)
	add_item("potion_mp_small", 3)
	add_item("wooden_sword", 1)
	add_item("leather_vest", 1)
	add_item("pet_whistle", 1)
	add_item("scroll_town", 2)
	add_item("bait_worm", 10)


func get_gold() -> int:
	return maxi(gold, 0)


func add_gold(amount: int) -> int:
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
	item_id = item_id.strip_edges()
	var n := 0
	for s in _stacks:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == item_id:
			n += int(s.get("qty", 0))
	return n


func has_item(item_id: String, qty: int = 1) -> bool:
	return get_qty(item_id) >= qty


func slot_count() -> int:
	var n := 0
	for s in _stacks:
		if typeof(s) == TYPE_DICTIONARY and int(s.get("qty", 0)) > 0:
			n += 1
	return n


func stack_max_for(item_id: String) -> int:
	item_id = item_id.strip_edges()
	if catalog != null and catalog.has_method("get_item"):
		var def: Dictionary = catalog.get_item(item_id)
		if not def.is_empty() and def.has("stack_max"):
			return maxi(int(def.get("stack_max", DEFAULT_STACK_MAX)), 1)
	return DEFAULT_STACK_MAX


func can_accept(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or qty <= 0:
		return false
	var stack_max: int = stack_max_for(item_id)
	var had := false
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) != item_id:
			continue
		had = true
		if int(s.get("qty", 0)) < stack_max:
			return true
	if had:
		return false
	return slot_count() < max_slots


func try_add_item(item_id: String, qty: int = 1, bound: bool = false, enhance: int = 0) -> Dictionary:
	item_id = item_id.strip_edges()
	enhance = clampi(int(enhance), 0, 5)
	if item_id.is_empty() or qty <= 0:
		return {"ok": false, "added": 0, "remaining": maxi(qty, 0), "reason": "invalid"}
	var stack_max: int = stack_max_for(item_id)
	var added := 0
	var left := qty
	var had_same := false
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) != item_id:
			continue
		# Bound/unbound, enhance, and tool durability never merge across mismatch.
		if bool(s.get("bound", false)) != bound:
			continue
		if clampi(int(s.get("enhance", 0)), 0, 5) != enhance:
			continue
		var dmax_m := catalog_tool_durability_max(item_id)
		if dmax_m > 0:
			_ensure_stack_tool_durability(s)
			# New stacks default to full; only merge into full stacks of same max.
			if int(s.get("durability", 0)) != dmax_m or int(s.get("durability_max", 0)) != dmax_m:
				continue
		had_same = true
		if left <= 0:
			continue
		var have: int = int(s.get("qty", 0))
		var room: int = stack_max - have
		if room <= 0:
			continue
		var take: int = mini(room, left)
		s["qty"] = have + take
		if bound:
			s["bound"] = true
		if enhance > 0:
			s["enhance"] = enhance
		added += take
		left -= take
	if left > 0 and slot_count() < max_slots:
		var take2: int = mini(stack_max, left)
		var row := {"id": item_id, "qty": take2}
		if bound:
			row["bound"] = true
		if enhance > 0:
			row["enhance"] = enhance
		var dmax_new := catalog_tool_durability_max(item_id)
		if dmax_new > 0:
			row["durability"] = dmax_new
			row["durability_max"] = dmax_new
		_stacks.append(row)
		added += take2
		left -= take2
		had_same = true
	if added <= 0:
		var reason := "bag_full"
		if had_same:
			reason = "stack_full"
		return {"ok": false, "added": 0, "remaining": qty, "reason": reason}
	return {
		"ok": true,
		"added": added,
		"remaining": left,
		"reason": ("stack_full" if left > 0 else ""),
	}


func add_item(item_id: String, qty: int = 1, bound: bool = false, enhance: int = 0) -> int:
	var r: Dictionary = try_add_item(item_id, qty, bound, enhance)
	return int(r.get("added", 0))


func unbound_qty(item_id: String) -> int:
	item_id = item_id.strip_edges()
	var n := 0
	for s in _stacks:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == item_id:
			if not bool(s.get("bound", false)):
				n += int(s.get("qty", 0))
	return n


func is_bound(item_id: String) -> bool:
	item_id = item_id.strip_edges()
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) != item_id:
			continue
		if bool(s.get("bound", false)) and int(s.get("qty", 0)) > 0:
			return true
	return false


## True when enough unbound copies exist (trade / auction / mail).
func can_transfer(item_id: String, qty: int = 1) -> bool:
	return unbound_qty(item_id) >= maxi(qty, 1)


## Remove qty preferring unbound stacks first (shop sell may take bound).
func consume(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	if qty <= 0 or not has_item(item_id, qty):
		return false
	var left := qty
	# Pass 1: unbound
	left = _consume_prefer(item_id, left, false)
	# Pass 2: bound
	if left > 0:
		left = _consume_prefer(item_id, left, true)
	return left <= 0


## Consume only unbound stacks (player transfer paths).
func consume_unbound(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	if qty <= 0 or unbound_qty(item_id) < qty:
		return false
	return _consume_prefer(item_id, qty, false) <= 0


## Consume one unit; returns {ok, bound, enhance} for the stack taken (unbound preferred).
func consume_one(item_id: String) -> Dictionary:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or not has_item(item_id, 1):
		return {"ok": false, "bound": false, "enhance": 0}
	# Prefer unbound so a fresh bind-on-equip piece can still bind.
	for prefer_bound in [false, true]:
		var i := 0
		while i < _stacks.size():
			var s: Variant = _stacks[i]
			if typeof(s) != TYPE_DICTIONARY or str(s.get("id", "")) != item_id:
				i += 1
				continue
			if bool(s.get("bound", false)) != prefer_bound:
				i += 1
				continue
			var have: int = int(s.get("qty", 0))
			if have <= 0:
				_stacks.remove_at(i)
				continue
			var was_bound := bool(s.get("bound", false))
			var was_enh := clampi(int(s.get("enhance", 0)), 0, 5)
			s["qty"] = have - 1
			if int(s.get("qty", 0)) <= 0:
				_stacks.remove_at(i)
			return {"ok": true, "bound": was_bound, "enhance": was_enh}
	return {"ok": false, "bound": false, "enhance": 0}


func _consume_prefer(item_id: String, left: int, want_bound: bool) -> int:
	var i := 0
	while i < _stacks.size() and left > 0:
		var s: Variant = _stacks[i]
		if typeof(s) != TYPE_DICTIONARY or str(s.get("id", "")) != item_id:
			i += 1
			continue
		if bool(s.get("bound", false)) != want_bound:
			i += 1
			continue
		var have: int = int(s.get("qty", 0))
		var take: int = mini(have, left)
		s["qty"] = have - take
		left -= take
		if int(s.get("qty", 0)) <= 0:
			_stacks.remove_at(i)
		else:
			i += 1
	return left


func try_split(item_id: String, qty: int) -> Dictionary:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 1)
	if item_id.is_empty():
		return {"ok": false, "reason": "invalid"}
	if slot_count() >= max_slots:
		return {"ok": false, "reason": "bag_full"}
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) != item_id:
			continue
		var have: int = int(s.get("qty", 0))
		if have <= qty:
			continue
		s["qty"] = have - qty
		var nrow := {"id": item_id, "qty": qty}
		if bool(s.get("bound", false)):
			nrow["bound"] = true
		var enh := clampi(int(s.get("enhance", 0)), 0, 5)
		if enh > 0:
			nrow["enhance"] = enh
		_stacks.append(nrow)
		return {"ok": true, "qty": qty}
	return {"ok": false, "reason": "too_small"}


func sort_stacks() -> void:
	_stacks.sort_custom(func(a, b):
		var ia := str(a.get("id", "")) if typeof(a) == TYPE_DICTIONARY else ""
		var ib := str(b.get("id", "")) if typeof(b) == TYPE_DICTIONARY else ""
		var ra := _type_rank(ia)
		var rb := _type_rank(ib)
		if ra != rb:
			return ra < rb
		return ia < ib
	)


func _type_rank(item_id: String) -> int:
	var t := ""
	if catalog != null and catalog.has_method("get_item"):
		var def: Dictionary = catalog.get_item(item_id)
		t = str(def.get("type", "")).strip_edges().to_lower()
	match t:
		"consumable", "potion":
			return 0
		"weapon", "armor", "equipment", "equip":
			return 1
		"material":
			return 2
		"quest":
			return 3
		_:
			return 4


func set_locked(item_id: String, on: bool) -> void:
	item_id = item_id.strip_edges()
	if item_id.is_empty():
		return
	if on:
		locked[item_id] = true
	else:
		locked.erase(item_id)


func is_locked(item_id: String) -> bool:
	return bool(locked.get(item_id.strip_edges(), false))


func snapshot() -> Array:
	var out: Array = []
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var q: int = int(s.get("qty", 0))
		if q <= 0:
			continue
		var iid := str(s.get("id", "")).strip_edges()
		if iid.is_empty():
			continue
		var row := {"id": iid, "qty": q, "locked": is_locked(iid)}
		if bool(s.get("bound", false)):
			row["bound"] = true
		var enh_s := clampi(int(s.get("enhance", 0)), 0, 5)
		if enh_s > 0:
			row["enhance"] = enh_s
		var dmax_s := catalog_tool_durability_max(iid)
		if dmax_s > 0:
			_ensure_stack_tool_durability(s)
			row["durability"] = maxi(int(s.get("durability", 0)), 0)
			row["durability_max"] = maxi(int(s.get("durability_max", dmax_s)), 1)
		if catalog != null and catalog.has_method("get_item"):
			var def: Dictionary = catalog.get_item(iid)
			if not def.is_empty():
				row["type"] = str(def.get("type", ""))
				row["icon_index"] = int(def.get("icon_index", -1))
				var ic := str(def.get("icon", "")).strip_edges()
				if not ic.is_empty():
					row["icon"] = ic
					row["icon_ref"] = str(def.get("icon_ref", "content://icon/%s" % ic))
		out.append(row)
	return out



## Catalog durability_max for bag tools (0 = not tracked / not a durable tool).
func catalog_tool_durability_max(item_id: String) -> int:
	item_id = item_id.strip_edges()
	if item_id.is_empty() or catalog == null or not catalog.has_method("get_item"):
		return 0
	var def: Dictionary = catalog.get_item(item_id)
	if def.is_empty():
		return 0
	# Equipment durability lives on equipment slots, not bag stacks.
	if str(def.get("type", "")).strip_edges() == "equipment":
		return 0
	return maxi(int(def.get("durability_max", 0)), 0)


func _ensure_stack_tool_durability(s: Dictionary) -> void:
	var iid := str(s.get("id", "")).strip_edges()
	var dmax := catalog_tool_durability_max(iid)
	if dmax <= 0:
		return
	if not s.has("durability_max") or int(s.get("durability_max", 0)) <= 0:
		s["durability_max"] = dmax
	else:
		s["durability_max"] = maxi(int(s.get("durability_max", dmax)), 1)
	if not s.has("durability"):
		s["durability"] = int(s.get("durability_max", dmax))


## True when bag has a usable copy (durability > 0, or no durability tracking).
func has_usable_tool(item_id: String, qty: int = 1) -> bool:
	item_id = item_id.strip_edges()
	qty = maxi(qty, 1)
	var dmax := catalog_tool_durability_max(item_id)
	if dmax <= 0:
		return has_item(item_id, qty)
	var n := 0
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) != item_id:
			continue
		if int(s.get("qty", 0)) <= 0:
			continue
		_ensure_stack_tool_durability(s)
		if int(s.get("durability", 0)) > 0:
			n += int(s.get("qty", 0))
			if n >= qty:
				return true
	return false


func get_tool_durability(item_id: String) -> int:
	item_id = item_id.strip_edges()
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) != item_id:
			continue
		if int(s.get("qty", 0)) <= 0:
			continue
		var dmax := catalog_tool_durability_max(item_id)
		if dmax <= 0:
			return 0
		_ensure_stack_tool_durability(s)
		return maxi(int(s.get("durability", 0)), 0)
	return 0


func get_tool_durability_max(item_id: String) -> int:
	return catalog_tool_durability_max(item_id.strip_edges())


## Wear one bag tool stack by amount. At 0: remove stack (broken).
## Returns {ok, broken, durability, durability_max, item_id}.
func wear_tool(item_id: String, amount: int = 1) -> Dictionary:
	item_id = item_id.strip_edges()
	amount = maxi(amount, 1)
	var dmax_cat := catalog_tool_durability_max(item_id)
	if dmax_cat <= 0:
		return {"ok": false, "broken": false, "durability": 0, "durability_max": 0, "item_id": item_id, "reason": "not_tracked"}
	var i := 0
	while i < _stacks.size():
		var s: Variant = _stacks[i]
		if typeof(s) != TYPE_DICTIONARY or str(s.get("id", "")) != item_id:
			i += 1
			continue
		if int(s.get("qty", 0)) <= 0:
			_stacks.remove_at(i)
			continue
		_ensure_stack_tool_durability(s)
		var cur := maxi(int(s.get("durability", 0)), 0)
		if cur <= 0:
			i += 1
			continue
		var dmax := maxi(int(s.get("durability_max", dmax_cat)), 1)
		var after := maxi(cur - amount, 0)
		s["durability"] = after
		if after <= 0:
			# Prefer consume/break: remove the tool stack.
			var q := int(s.get("qty", 0))
			if q <= 1:
				_stacks.remove_at(i)
			else:
				s["qty"] = q - 1
				s["durability"] = dmax
				s["durability_max"] = dmax
			return {"ok": true, "broken": true, "durability": 0, "durability_max": dmax, "item_id": item_id}
		return {"ok": true, "broken": false, "durability": after, "durability_max": dmax, "item_id": item_id}
	return {"ok": false, "broken": false, "durability": 0, "durability_max": dmax_cat, "item_id": item_id, "reason": "missing"}


func tools_need_repair() -> bool:
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var iid := str(s.get("id", "")).strip_edges()
		if iid.is_empty() or int(s.get("qty", 0)) <= 0:
			continue
		var dmax := catalog_tool_durability_max(iid)
		if dmax <= 0:
			continue
		_ensure_stack_tool_durability(s)
		if int(s.get("durability", 0)) < int(s.get("durability_max", dmax)):
			return true
	return false


## Kit repair for bag tools: +ceil(fraction * max) per damaged stack (no gold).
func apply_kit_repair_tools(fraction: float = 0.3) -> Dictionary:
	fraction = clampf(fraction, 0.0, 1.0)
	var repaired: Array = []
	var points := 0
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var iid := str(s.get("id", "")).strip_edges()
		if iid.is_empty() or int(s.get("qty", 0)) <= 0:
			continue
		var dmax_cat := catalog_tool_durability_max(iid)
		if dmax_cat <= 0:
			continue
		_ensure_stack_tool_durability(s)
		var before := maxi(int(s.get("durability", 0)), 0)
		var dmax := maxi(int(s.get("durability_max", dmax_cat)), 1)
		if before >= dmax:
			continue
		var gain: int = maxi(1, int(ceili(float(dmax) * fraction))) if fraction > 0.0 else 0
		var after: int = mini(dmax, before + gain)
		s["durability"] = after
		var gained: int = after - before
		points += gained
		repaired.append({"item_id": iid, "before": before, "after": after, "max": dmax})
	if repaired.is_empty():
		return {"ok": false, "reason": "nothing_to_repair", "repaired": [], "points": 0}
	return {"ok": true, "reason": "", "repaired": repaired, "points": points}


## Full repair bag tools for gold (cost_per_point * missing points). Does not spend — caller spends.
## Returns {ok, reason, points, cost, repaired}.
func preview_tool_repair_full() -> Dictionary:
	var repaired: Array = []
	var points := 0
	for s in _stacks:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var iid := str(s.get("id", "")).strip_edges()
		if iid.is_empty() or int(s.get("qty", 0)) <= 0:
			continue
		var dmax_cat := catalog_tool_durability_max(iid)
		if dmax_cat <= 0:
			continue
		_ensure_stack_tool_durability(s)
		var before := maxi(int(s.get("durability", 0)), 0)
		var dmax := maxi(int(s.get("durability_max", dmax_cat)), 1)
		if before >= dmax:
			continue
		var need := dmax - before
		points += need
		repaired.append({"item_id": iid, "before": before, "after": dmax, "max": dmax, "points": need, "stack": s})
	if repaired.is_empty():
		return {"ok": false, "reason": "nothing_to_repair", "points": 0, "cost": 0, "repaired": []}
	return {"ok": true, "reason": "", "points": points, "cost": points, "repaired": repaired}


func apply_tool_repair_full() -> Dictionary:
	var prev: Dictionary = preview_tool_repair_full()
	if not bool(prev.get("ok", false)):
		return prev
	for row in prev.get("repaired", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var s: Variant = row.get("stack", null)
		if typeof(s) != TYPE_DICTIONARY:
			continue
		s["durability"] = int(row.get("after", s.get("durability_max", 0)))
	# Strip stack refs from result
	var cleaned: Array = []
	for row2 in prev.get("repaired", []):
		if typeof(row2) != TYPE_DICTIONARY:
			continue
		cleaned.append({
			"item_id": str(row2.get("item_id", "")),
			"before": int(row2.get("before", 0)),
			"after": int(row2.get("after", 0)),
			"max": int(row2.get("max", 0)),
		})
	return {
		"ok": true,
		"reason": "",
		"points": int(prev.get("points", 0)),
		"cost": int(prev.get("cost", 0)),
		"repaired": cleaned,
	}


func snapshot_state() -> Dictionary:
	return {"items": snapshot(), "gold": get_gold()}
