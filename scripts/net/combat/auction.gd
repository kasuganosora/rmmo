extends RefCounted
## In-memory auction-house listings (MockServer session only).
## Listing shape: {id, seller_id, seller_name, item_id, item_name, qty, price_gold, created_at}

const MAX_LISTINGS := 50

var _listings: Array = []
var _next_id: int = 1


func clear() -> void:
	_listings.clear()
	_next_id = 1


func count() -> int:
	return _listings.size()


func max_listings() -> int:
	return MAX_LISTINGS


func is_full() -> bool:
	return _listings.size() >= MAX_LISTINGS


func find_index(listing_id: String) -> int:
	listing_id = str(listing_id).strip_edges()
	if listing_id.is_empty():
		return -1
	for i in range(_listings.size()):
		var e: Variant = _listings[i]
		if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) == listing_id:
			return i
	return -1


func get_listing(listing_id: String) -> Dictionary:
	var idx := find_index(listing_id)
	if idx < 0:
		return {}
	return (_listings[idx] as Dictionary).duplicate(true)


## Append a listing. Returns {ok, reason, listing}.
func try_add(
	seller_id: String,
	seller_name: String,
	item_id: String,
	item_name: String,
	qty: int,
	price_gold: int
) -> Dictionary:
	seller_id = str(seller_id).strip_edges()
	seller_name = str(seller_name).strip_edges()
	item_id = str(item_id).strip_edges()
	item_name = str(item_name).strip_edges()
	qty = int(qty)
	price_gold = int(price_gold)
	if seller_id.is_empty() or item_id.is_empty() or qty <= 0 or price_gold <= 0:
		return {"ok": false, "reason": "invalid", "listing": {}}
	if is_full():
		return {"ok": false, "reason": "full", "listing": {}}
	if seller_name.is_empty():
		seller_name = seller_id
	if item_name.is_empty():
		item_name = item_id
	var lid := "ah_%d" % _next_id
	_next_id += 1
	var created_at: int = int(Time.get_unix_time_from_system())
	var listing := {
		"id": lid,
		"seller_id": seller_id,
		"seller_name": seller_name,
		"item_id": item_id,
		"item_name": item_name,
		"qty": qty,
		"price_gold": price_gold,
		"created_at": created_at,
	}
	_listings.append(listing)
	return {"ok": true, "reason": "", "listing": listing.duplicate(true)}


func try_remove(listing_id: String) -> Dictionary:
	var idx := find_index(listing_id)
	if idx < 0:
		return {"ok": false, "reason": "not_found", "listing": {}}
	var listing: Dictionary = (_listings[idx] as Dictionary).duplicate(true)
	_listings.remove_at(idx)
	return {"ok": true, "reason": "", "listing": listing}


func snapshot() -> Array:
	var out: Array = []
	for e in _listings:
		if typeof(e) == TYPE_DICTIONARY:
			out.append((e as Dictionary).duplicate(true))
	return out


func snapshot_state() -> Dictionary:
	var listings: Array = snapshot()
	return {
		"listings": listings,
		"count": listings.size(),
		"max_listings": MAX_LISTINGS,
	}
