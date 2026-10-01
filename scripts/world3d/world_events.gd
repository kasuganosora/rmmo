extends RefCounted
## Reuse the existing page/command interpreter. Spatial validation lives in 3D.
const Runtime = preload("res://scripts/net/combat/event_runtime.gd")
var runtime = Runtime.new()
var server
var targets := {}
var _inside := {}


func _init(owner) -> void:
	server = owner


func mount(map_ref: String, specs: Array, records: Array = []) -> void:
	targets.clear()
	_inside.clear()
	var events: Array = []
	var templates := {}
	var authored_specs: Array = []
	for record in records:
		if record.has("event_template") and preload("res://scripts/world3d/event_templates.gd").valid_record(record):
			templates[str(record.uuid)] = true
			authored_specs.append(preload("res://scripts/world3d/event_templates.gd").spec(record))
	for spec in specs:
		var covered := templates.has(str(spec.uuid))
		if not covered:
			for id in templates:
				if str(spec.uuid).begins_with(id + "__"): covered = true; break
		if covered: continue
		authored_specs.append(spec)
	for spec in authored_specs:
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
		"open_shop_cb": Callable(server, "_try_open_shop_action"),
		"world3d": true,
	}


func can_interact(id: String, body: CharacterBody3D, target: CollisionObject3D = null) -> bool:
	if not targets.has(id) or body == null:
		return false
	var event: Dictionary = runtime.get_event(id)
	var page: Dictionary = runtime.select_page_with_ctx(event, context())
	if page.is_empty() or runtime.page_trigger(event, page) != "action": return false
	var center: Vector3 = targets[id]["position"]
	var radius := float(targets[id].get("radius", 2))
	if absf(body.global_position.y - center.y) > radius or Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(center.x, center.z)) > radius: return false
	var ray := PhysicsRayQueryParameters3D.create(body.global_position, center)
	ray.exclude = [body.get_rid()]
	if target != null: ray.exclude = [body.get_rid(), target.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var uuid := str(hit.collider.get_meta("uuid", ""))
		if uuid != id and not uuid.begins_with(id + "__"): return false
	return true

func nearest(body: CharacterBody3D) -> String:
	var chosen := ""
	var distance := INF
	for id in targets:
		var d: float = body.global_position.distance_to(targets[id].position)
		if d < distance and can_interact(id, body): chosen = id; distance = d
	return chosen

func interact(id: String, body: CharacterBody3D, target: CollisionObject3D = null) -> Array:
	if not can_interact(id, body, target):
		return []
	return run(id)

func run(id: String) -> Array:
	var spec: Dictionary = targets.get(id, {})
	var template: Dictionary = spec.get("template", {})
	if not template.is_empty() and template.template in ["chest", "gather"]:
		var p: Dictionary = template.parameters
		var page := runtime.select_page_with_ctx(runtime.get_event(id), context())
		if page.is_empty(): return []
		if not p.item_id.is_empty() and not (p.once and runtime.get_self_switch(id, "A")):
			# Simulate the exact existing inventory operation, including partial stack
			# limits, before a one-shot reward can consume its self-switch.
			var probe = preload("res://scripts/net/combat/inventory.gd").new()
			probe.catalog = server.inventory.catalog
			probe.restore_session_state(server.inventory.capture_session_state())
			if probe.add_item(p.item_id, p.quantity) != p.quantity: return [{"type": "system_message", "text": "背包空间不足，请整理后再领取。"}]
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
			actions.append_array(run(id))
		_inside[id] = inside
	return actions
