extends RefCounted
## Reuse the existing page/command interpreter. Spatial validation lives in 3D.
const Runtime = preload("res://scripts/net/combat/event_runtime.gd")
var runtime = Runtime.new()
var server
var targets := {}
var _inside := {}


func _init(owner) -> void:
	server = owner


func mount(map_ref: String, specs: Array) -> void:
	targets.clear()
	_inside.clear()
	var events: Array = []
	for spec in specs:
		var data: Dictionary = spec.get("extras", {})
		var kind := str(data.get("kind", ""))
		if kind not in ["npc", "gather", "event"] or bool(data.get("hostile", false)) or bool(data.get("ally", false)):
			continue
		var id := str(spec["uuid"])
		var definition: Dictionary = data.get("event", {}).duplicate(true)
		definition["id"] = id
		definition["name"] = str(data.get("name", data.get("npc_id", id)))
		if not definition.has("pages"):
			var line := str(data.get("line", "你好"))
			var after := "已经谈过了"
			var commands: Array = [{"op": "text", "text": line}, {"op": "set_self_switch", "letter": "A"}]
			if kind == "gather":
				commands[0]["text"] = "采到了草药"
				after = "这里已经采过"
				if not str(data.get("item_id", "")).is_empty():
					commands.insert(0, {"op": "give_item", "item_id": data["item_id"], "qty": int(data.get("qty", 1))})
			definition["pages"] = [
				{"commands": commands},
				{"when": {"self_switch": "A"}, "commands": [{"op": "text", "text": after}]},
			]
		targets[id] = spec
		events.append(definition)
	runtime.load_events_array(events, map_ref)


func context() -> Dictionary:
	return {
		"inventory": server.inventory,
		"shop_catalog": server.shop_catalog,
		"item_name_cb": Callable(server, "item_display_name"),
		"quest_item_cb": Callable(server, "_quest_note_item_actions"),
		"world3d": true,
	}


func interact(id: String, body: CharacterBody3D, target: CollisionObject3D) -> Array:
	if not targets.has(id) or body == null or target == null:
		return []
	var center: Vector3 = targets[id]["position"]
	if absf(body.global_position.y - center.y) > 1.0 or Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(center.x, center.z)) > 2.0:
		return []
	var ray := PhysicsRayQueryParameters3D.create(body.global_position, center)
	ray.exclude = [body.get_rid(), target.get_rid()]
	if not body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return []
	var event: Dictionary = runtime.get_event(id)
	var page: Dictionary = runtime.select_page_with_ctx(event, context())
	if runtime.page_trigger(event, page) != "action":
		return []
	return runtime.run_event(id, context())


func choice(option: String, index: int) -> Array:
	return runtime.try_event_choice(option, index)


func touch_segment(previous_feet: Vector3, feet: Vector3) -> Array:
	var actions: Array = []
	for id in targets:
		var event: Dictionary = runtime.get_event(id)
		var page: Dictionary = runtime.select_page_with_ctx(event, context())
		if runtime.page_trigger(event, page) != "player_touch":
			continue
		var spec: Dictionary = targets[id]
		var inverse: Transform3D = spec["transform"].affine_inverse()
		var bounds: AABB = spec["mesh"].get_aabb().grow(0.05)
		var current_local := inverse * feet
		var previous_local := inverse * previous_feet
		var inside := bounds.has_point(current_local)
		var crossed := bounds.intersects_segment(previous_local, current_local) != null
		if not bool(_inside.get(id, false)) and (inside or crossed):
			actions.append_array(runtime.run_event(id, context()))
		_inside[id] = inside
	return actions
