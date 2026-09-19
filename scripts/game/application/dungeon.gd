extends RefCounted
## Application layer: dungeon server result handling.

static func _apply_dungeon_server_result(ctrl, result: Dictionary) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		return
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	# Prefer map_transfer so loading starts; fold sibling actions for system messages.
	var deferred: Array = []
	var transfer_act: Dictionary = {}
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) == "map_transfer" and bool(a.get("ok", true)):
			transfer_act = a
		else:
			deferred.append(a)
	if not transfer_act.is_empty():
		var merged: Dictionary = transfer_act.duplicate(true)
		merged["actions"] = deferred
		ctrl._on_transfer_requested(merged)
		return
	ctrl._apply_server_actions(deferred)

