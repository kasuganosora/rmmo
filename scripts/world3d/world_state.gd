extends RefCounted
## MockServer session state, independent of scene residency. No Nodes/resources.
var maps := {}
var home := {}
var summons := {}
var stowed_pet := {}
func clear() -> void:
	maps.clear()
	home.clear()
	summons.clear()
	stowed_pet.clear()
func read_map(key: String) -> Dictionary:
	return maps.get(key, {}).duplicate(true)
func write_map(key: String, data: Dictionary) -> void:
	maps[key] = data.duplicate(true)
