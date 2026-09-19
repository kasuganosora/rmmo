extends RefCounted
## Domain module: death drops (roll, item pref, type filter, apply).

var ctrl
func _init(c):
	ctrl = c

const Equipment = preload("res://scripts/net/combat/equipment.gd")

func _death_drop_roll() -> float:
	if ctrl.death_drop_randf.is_valid():
		return clampf(float(ctrl.death_drop_randf.call()), 0.0, 0.999999)
	return randf()



func _death_drop_item_pref(item_id: String) -> int:
	## Lower = preferred for drop. Equipment / quest excluded by caller.
	var t = ""
	if ctrl.item_catalog != null and ctrl.item_catalog.has_method("get_item"):
		var def: Dictionary = ctrl.item_catalog.get_item(item_id)
		t = str(def.get("type", "")).strip_edges().to_lower()
	match t:
		"consumable", "potion":
			return 0
		"misc":
			return 1
		"material":
			return 2
		_:
			return 3



func _death_drop_type_blocked(item_id: String) -> bool:
	var t = ""
	if ctrl.item_catalog != null and ctrl.item_catalog.has_method("get_item"):
		var def: Dictionary = ctrl.item_catalog.get_item(item_id)
		t = str(def.get("type", "")).strip_edges().to_lower()
	return t in ["equipment", "weapon", "armor", "equip", "quest"]



func _apply_death_drops(actions: Array) -> void:
	if ctrl.inventory == null:
		return
	var dropped_items: Array = []  # [{item_id, qty}, ...]
	var gold_lost = 0
	# --- gold ---
	var wallet: int = ctrl.inventory.get_gold()
	if wallet > 0:
		var pct: int = 5 + int(_death_drop_roll() * 11.0)  # 5..15
		gold_lost = int(floor(float(wallet) * float(pct) / 100.0))
		gold_lost = clampi(gold_lost, 0, wallet)
		if gold_lost > 0 and ctrl.inventory.try_spend_gold(gold_lost):
			dropped_items.append({"item_id": "rusty_coin", "qty": gold_lost})
		else:
			gold_lost = 0
	# --- bag stacks ---
	var candidates: Array = []  # {id, qty, pref}
	for row_v in ctrl.inventory.snapshot():
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var iid = str(row.get("id", "")).strip_edges()
		var q: int = int(row.get("qty", 0))
		if iid.is_empty() or q <= 0:
			continue
		if ctrl.inventory.has_method("is_locked") and ctrl.inventory.is_locked(iid):
			continue
		if bool(row.get("locked", false)):
			continue
		if _death_drop_type_blocked(iid):
			continue
		candidates.append({"id": iid, "qty": q, "pref": _death_drop_item_pref(iid)})
	candidates.sort_custom(func(a, b):
		var pa: int = int(a.get("pref", 99))
		var pb: int = int(b.get("pref", 99))
		if pa != pb:
			return pa < pb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	# Softcore: never empty the entire bag — keep at least one stack.
	var max_picks: int = 1 + int(_death_drop_roll() * 3.0)  # 1..3
	if candidates.size() > 1:
		max_picks = mini(max_picks, candidates.size() - 1)
	elif candidates.size() == 1:
		# Only one eligible stack: allow partial drop only (leave >=1).
		max_picks = 1
	else:
		max_picks = 0
	var picked = 0
	var used_ids: Dictionary = {}
	while picked < max_picks and not candidates.is_empty():
		# Weighted toward preferred: pick among first half of remaining list.
		var pool_n: int = maxi(1, int(ceil(float(candidates.size()) * 0.5)))
		var idx: int = int(_death_drop_roll() * float(pool_n))
		idx = clampi(idx, 0, candidates.size() - 1)
		var cand: Dictionary = candidates[idx]
		candidates.remove_at(idx)
		var cid = str(cand.get("id", ""))
		if cid.is_empty() or used_ids.has(cid):
			continue
		var have: int = int(cand.get("qty", 0))
		if have <= 0:
			continue
		var drop_qty: int = have
		if have > 1:
			drop_qty = maxi(1, int(ceil(float(have) * 0.5)))
			# Softcore: never take the last unit of the last remaining stack.
			if candidates.is_empty() and ctrl.inventory.slot_count() <= 1:
				drop_qty = mini(drop_qty, have - 1)
			var leave_one: bool = candidates.is_empty() and ctrl.inventory.slot_count() <= 1
			drop_qty = clampi(drop_qty, 1, have - (1 if leave_one else 0))
			if drop_qty <= 0:
				continue
		else:
			# qty==1: only drop if another stack will remain in bag.
			if ctrl.inventory.slot_count() <= 1 and candidates.is_empty():
				continue
		if not ctrl.inventory.has_item(cid, drop_qty):
			continue
		if not ctrl.inventory.consume(cid, drop_qty):
			continue
		dropped_items.append({"item_id": cid, "qty": drop_qty})
		used_ids[cid] = true
		picked += 1
	if dropped_items.is_empty():
		return
	var cell = {"x": ctrl.death_cell.x, "y": ctrl.death_cell.y}
	if ctrl.death_cell.x <= -9990:
		cell = {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	actions.append_array(ctrl._add_items_to_ground(cell, dropped_items, "death", ""))
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "你损失了部分物品/金币。"})


