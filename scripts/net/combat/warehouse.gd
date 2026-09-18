extends RefCounted
## Personal warehouse / bank (MockServer in-memory only).
## Same stack shape as the bag Inventory; larger capacity; no starter kit.

const Inventory = preload("res://scripts/net/combat/inventory.gd")
const MAX_SLOTS := 60

var _bag = null

var max_slots: int:
	get:
		return int(_bag.max_slots) if _bag != null else MAX_SLOTS
	set(v):
		if _bag != null:
			_bag.max_slots = maxi(int(v), 1)


func _init() -> void:
	_bag = Inventory.new()
	_bag.max_slots = MAX_SLOTS


func set_catalog(p_catalog) -> void:
	_bag.set_catalog(p_catalog)


func clear() -> void:
	_bag.clear()


func get_gold() -> int:
	return int(_bag.get_gold())


func add_gold(amount: int) -> int:
	return int(_bag.add_gold(amount))


func try_spend_gold(amount: int) -> bool:
	return bool(_bag.try_spend_gold(amount))


func get_qty(item_id: String) -> int:
	return int(_bag.get_qty(item_id))


func has_item(item_id: String, qty: int = 1) -> bool:
	return bool(_bag.has_item(item_id, qty))


func slot_count() -> int:
	return int(_bag.slot_count())


func can_accept(item_id: String, qty: int = 1) -> bool:
	return bool(_bag.can_accept(item_id, qty))


func try_add_item(item_id: String, qty: int = 1) -> Dictionary:
	return _bag.try_add_item(item_id, qty)


func add_item(item_id: String, qty: int = 1) -> int:
	return int(_bag.add_item(item_id, qty))


func consume(item_id: String, qty: int = 1) -> bool:
	return bool(_bag.consume(item_id, qty))


func snapshot() -> Array:
	return _bag.snapshot()


func snapshot_state() -> Dictionary:
	return {
		"items": snapshot(),
		"gold": get_gold(),
		"max_slots": max_slots,
		"used_slots": slot_count(),
	}
