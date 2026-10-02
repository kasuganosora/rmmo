extends Node
## Shared combat rules with authoritative 3D reach and physics visibility.
const Net = preload("res://scripts/net/net.gd")
var world: Node3D
var targets := {}
var selected := ""
var actors := {}
var defeated := {}
var loot: Array = []
var ground_target: Variant = null
var area_target := ""
var ground_mode := false
var respawn_point := Vector3.ZERO
var _map_key := ""
var _ambient := 0.0
var _previous := Vector3.ZERO
var _death_applied := false
var _npc_ground := {}
var _npc_forward := {}
var _npc_ready := {}
var _npc_markers := {}
var summons

func setup(owner: Node3D) -> void:
	world = owner
	_map_key = world._map_path.simplify_path()
	respawn_point = world._player.global_position
	_previous = respawn_point
	var server = Net.server()
	if server.world3d_state.home.is_empty(): server.world3d_state.home = {"path": world._map_path, "position": respawn_point}
	server.combat_stats.clear_npcs()
	server.combat_engine.clear_cast()
	server.combat_engine.spatial_range = in_range
	server.combat_engine.spatial_in_combat = in_combat
	server.combat_engine.spatial_ground = valid_ground
	server.combat_engine.spatial_area = area_targets
	server.combat_engine.spatial_counter = counter_attack
	server.combat_engine.spatial_charge = charge
	server.combat_engine.spatial_revive = revive_error
	server.combat_engine.spatial_npc_check = npc_skill_space
	server.world3d_authority.movement_allowed = can_move
	server.world3d_authority.speed_multiplier = server.player_move_speed_mul
	for spec in world._map_root.get_meta("stream_library", []):
		var extras: Dictionary = spec.get("extras", {})
		if not bool(extras.get("hostile", false)) and not bool(extras.get("ally", false)): continue
		var id := str(spec.uuid)
		targets[id] = spec
		var stats: Dictionary = server.combat_stats.ensure_npc(id, not bool(targets[id].extras.get("ally", false)))
		for key in ["level", "hp_max", "atk", "def"]:
			if extras.has(key): stats[key] = maxi(1, int(extras[key]))
		stats.hp = stats.hp_max
		stats["ally"] = bool(extras.get("ally", false))
		var actor = preload("res://scripts/world3d/world_npc.gd").new()
		actor.configure(spec)
		add_child(actor)
		actor.authority.mount(actor, world._navigation, world._map_ref())
		actors[id] = actor
	_restore_map_state()
	summons = preload("res://scripts/world3d/world_summons.gd").new(self)
	server.world3d_summons = weakref(self)
	summons.restore()

func can_move() -> bool:
	return is_instance_valid(world) and is_instance_valid(world._player) and not world._player.input_locked and Net.server().combat_stats.player_alive()

func in_combat() -> bool:
	for id in actors:
		if actors[id].engaged and Net.server().combat_stats.npcs.has(id): return true
	return false

func in_range(id: String, range_units: int) -> bool:
	if not targets.has(id) or not Net.server().combat_stats.npcs.has(id): return false
	var feet: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
	var spec: Dictionary = targets[id]
	var bounds: AABB = spec.transform * spec.mesh.get_aabb()
	var target_feet: Vector3 = actors[id].feet() if actors.has(id) else Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	if absf(feet.y - target_feet.y) > 1.0: return false
	if feet.distance_to(target_feet) > maxf(2.0, float(range_units) * 2.0): return false
	var query := PhysicsRayQueryParameters3D.create(world._player.global_position, target_feet + Vector3(0, 0.9, 0))
	query.exclude = [world._player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or str(hit.collider.get_meta("uuid", "")) == id

func attack(id: String) -> Dictionary:
	if world.furniture.active():world.furniture.cancel()
	world.cancel_sit_preparation()
	if world._transfer_pending: return {"ok": false, "actions": []}
	if not targets.has(id): return {"ok": false, "actions": []}
	selected = id
	if not bool(targets[id].extras.get("hostile", false)): return {"ok": false, "actions": []}
	var result: Dictionary = Net.server().combat_engine.try_attack(id, -9999, -9999)
	if bool(result.get("ok", false)) and actors.has(id): actors[id].engaged = true
	return _apply(result)

func use_skill(id: String, ground: Variant = null) -> Dictionary:
	if world.furniture.active():world.furniture.cancel()
	world.cancel_sit_preparation()
	if world._transfer_pending: return {"ok": false, "actions": []}
	var engine = Net.server().combat_engine
	var definition: Dictionary = Net.server().skill_catalog.get_skill(id)
	var effect := str(definition.get("effect", ""))
	if effect in ["recall", "teleport_home", "pet_whistle", "party_summon", "summon"]:
		return _apply({"ok": false, "actions": [{"type": "system_message", "text": "该技能的三维空间规则尚未接入，未消耗 MP。"}]})
	if bool(definition.get("requires_target", false)) and actors.has(selected) and bool(targets[selected].extras.get("ally", false)) and effect not in ["revive", "heal"]:
		return _apply({"ok": false, "actions": [{"type": "system_message", "text": "不能对伙伴使用敌对技能。"}]})
	if not engine.is_casting():
		ground_mode = engine.skill_target_mode(definition) == "ground"
		ground_target = ground
		area_target = selected if bool(definition.get("requires_target", false)) else ""
	return _apply(engine.try_use_skill(id, selected, -9999, -9999))

func _apply(result: Dictionary) -> Dictionary:
	var actions: Array = result.get("actions", [])
	# 3D counters and status ticks call the engine directly, bypassing the
	# legacy combat module's sitting interruption wrapper.
	for action in actions:
		if str(action.get("type",""))=="damage" and str(action.get("target",action.get("id","")))=="player":
			world.cancel_sit_preparation()
			Net.server()._stand_if_sitting(actions)
			break
	if not Net.server().combat_stats.player_alive() and not _death_applied:
		_death_applied = true
		var server = Net.server()
		server.awaiting_respawn = true
		server.sitting = false
		server._clear_pending_loot_on_death(actions)
		var feet: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
		server._death_drops_module_logic._apply_death_drops(actions, func(items: Array): _create_loot(feet, items))
		actions.append_array(server._note_title_counter("deaths", 1))
		var wear: Dictionary = server.equipment.apply_death_wear(0.1)
		if int(wear.get("count", 0)) > 0: actions.append(server._equipment_update_action())
		if not server._actions_has_type(actions, "player_died"): actions.append({"type": "player_died"})
		result["actions"] = actions
	if actions.is_empty(): return result
	var rewards: Array = []
	for action in actions:
		_npc_cast_feedback(action)
		var actor_id := str(action.get("npc_id", action.get("id", "")))
		if str(action.get("type", "")) == "ally_downed" and actors.has(actor_id):
			actors[actor_id].route.clear()
			actors[actor_id].collision_layer = 0
			actors[actor_id].collision_mask = 0
			actors[actor_id].model.play("death", "front")
		if str(action.get("type", "")) == "ally_revived" and actors.has(actor_id):
			actors[actor_id].collision_layer = 1
			actors[actor_id].collision_mask = 1
			actors[actor_id].model.play("idle", "front")
		if str(action.get("type", "")) == "kill_npc":
			var id := str(action.get("npc_id", ""))
			if defeated.has(id) or not targets.has(id): continue
			defeated[id] = true
			_spawn_loot(id)
			var server = Net.server()
			var previous_template: Variant = server.npc_spawn_templates.get(id)
			server.npc_spawn_templates[id] = targets[id].extras
			rewards.append_array(server.grant_kill_exp(id))
			if previous_template == null: server.npc_spawn_templates.erase(id)
			else: server.npc_spawn_templates[id] = previous_template
			rewards.append_array(server._quest_note_kill_actions(str(targets[id].extras.get("npc_id", id))))
			for child in world.get_children():
				if str(child.get_meta("uuid", "")) == id and child is CollisionObject3D:
					child.collision_layer = 0
					child.collision_mask = 0
			if actors.has(id):
				var actor = actors[id]
				actor.route.clear()
				actor.model.play("death", "front")
				actor.collision_layer = 0
				actor.collision_mask = 0
				actor.respawn_remaining = float(targets[id].extras.get("respawn_seconds", 30.0))
			if selected == id: selected = ""
	actions.append_array(rewards)
	world.apply_actions(actions)
	if world._hud != null:
		world._hud.apply_combat_stats(Net.server().combat_stats.snapshot_player_stats())
		if selected != "" and Net.server().combat_stats.npcs.has(selected):
			var stats: Dictionary = Net.server().combat_stats.npcs[selected]
			world._hud.show_target(str(targets[selected].extras.get("name", selected)), float(stats.hp) / maxi(1, int(stats.hp_max)))
		else: world._hud.clear_target()
	return result

func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or not world.is_world_ready(): return
	if world._player.input_locked and Net.server().combat_stats.player_alive(): return
	var server = Net.server()
	var engine = server.combat_engine
	_tick_actors(delta)
	summons.tick(delta)
	if _previous.distance_to(world._player.global_position) > 0.001 and engine.is_casting() and engine.cast.should_interrupt_on_move():
		_apply({"actions": engine.interrupt_cast("move")})
	_previous = world._player.global_position
	_apply({"actions": engine.tick_cast(delta)})
	_apply({"actions": engine.tick_npc_casts(delta)})
	_ambient += delta
	if _ambient < 1.5: return
	var elapsed := _ambient
	_ambient = 0.0
	var actions: Array = server.combat_stats.statuses.tick_statuses(elapsed, server.combat_stats)
	_apply({"actions": actions})

func respawn() -> bool:
	var server = Net.server()
	if server.combat_stats.player_alive(): return false
	var feet := respawn_point - Vector3(0, 0.9, 0)
	if not world._navigation.near_surface(feet, 0.35, 0.65): return false
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.29
	capsule.height = float(world._player.get_meta("standing_height",1.8))-.02
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, capsule.height/2+.02, 0))
	query.exclude = [world._player.get_rid()]
	if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		world._status.text = "出生点被占用，请稍后重试。"
		return false
	server.combat_engine.clear_cast()
	server.combat_stats.restore_after_death()
	server.awaiting_respawn = false
	_death_applied = false
	world._player.global_position = respawn_point
	world._player.velocity = Vector3.ZERO
	world._player.click_target = null
	world._player._route.clear()
	world._player.input_locked = false
	world._previous_feet = feet
	_previous = respawn_point
	_ambient = 0.0
	world._player.get_node("CharacterModel3D").play("idle", "front")
	_apply({"actions": [{"type": "system_message", "text": "已在本地图出生点复活。"}]})
	return true

func _exit_tree() -> void:
	_save_map_state()
	var server = Net.server()
	if server.combat_engine.spatial_range == Callable(self, "in_range"):
		server.combat_engine.spatial_range = Callable()
		server.combat_engine.spatial_in_combat = Callable()
		server.combat_engine.spatial_ground = Callable()
		server.combat_engine.spatial_area = Callable()
		server.combat_engine.spatial_counter = Callable()
		server.combat_engine.spatial_charge = Callable()
		server.combat_engine.spatial_revive = Callable()
		server.combat_engine.spatial_npc_check = Callable()
		for id in actors: server.combat_engine.clear_npc_cast(id)
		server.combat_engine.clear_cast()
		server.world3d_authority.movement_allowed = Callable()
		server.world3d_authority.speed_multiplier = Callable()


func _tick_actors(delta: float) -> void:
	var server = Net.server()
	var player_feet: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
	var Stream = preload("res://scripts/world3d/world_stream.gd")
	var active_chunks: Dictionary = Stream.ring(player_feet, 1)
	for id in actors:
		var actor = actors[id]
		# Distant collision is not resident. Suspend physics rather than letting
		# actors fall through unloaded ground while the background map prepares.
		if not active_chunks.has(Stream.chunk_key(actor.feet())):
			actor.velocity = Vector3.ZERO
			if actor.respawn_remaining >= 0: actor.respawn_remaining = maxf(0, actor.respawn_remaining - delta)
			_apply({"actions": server.combat_engine.cancel_npc_cast(id, "unloaded")})
			continue
		if server.combat_stats.npcs.has(id) and int(server.combat_stats.npcs[id].hp) <= 0: continue
		if not server.combat_stats.npcs.has(id):
			if actor.respawn_remaining < 0: continue
			actor.respawn_remaining -= delta
			if actor.respawn_remaining > 0: continue
			# Do not materialize a collider inside the player.
			if actor.home.distance_to(player_feet) < 1.0 or not _landing_clear(actor, actor.home):
				actor.respawn_remaining = 1.0
				continue
			defeated.erase(id)
			actor.position = actor.home + Vector3(0, 0.9, 0)
			actor.velocity = Vector3.ZERO
			actor.collision_layer = 1
			actor.collision_mask = 1
			actor.engaged = false
			var stats: Dictionary = server.combat_stats.ensure_npc(id, not bool(targets[id].extras.get("ally", false)))
			for key in ["level", "hp_max", "atk", "def"]:
				if targets[id].extras.has(key): stats[key] = maxi(1, int(targets[id].extras[key]))
			stats.hp = stats.hp_max
		if bool(targets[id].extras.get("ally", false)):
			actor.repath -= delta
			if actor.feet().distance_to(player_feet) <= 2.0: actor.route.clear()
			elif actor.repath <= 0 and server.combat_stats.player_alive():
				actor.repath = 0.5
				actor.route = world._navigation.find_path(actor.feet(), player_feet).get("path", PackedVector3Array())
			actor.follow_path(delta, server.combat_stats.statuses.move_speed_mul(id))
			continue
		var distance: float = actor.feet().distance_to(player_feet)
		if distance < 10 and server.combat_stats.player_alive() and not actor.returning: actor.engaged = true
		if actor.feet().distance_to(actor.home) > 20 or not server.combat_stats.player_alive():
			actor.engaged = false
			actor.returning = true
		if actor.returning and actor.feet().distance_to(actor.home) < 0.3: actor.returning = false
		var goal: Vector3 = player_feet if actor.engaged else actor.home
		if actor.returning or not server.combat_stats.player_alive():
			_apply({"actions": server.combat_engine.cancel_npc_cast(id, "leash")})
		if server.combat_engine.is_npc_casting(id):
			actor.route.clear()
			continue
		if actor.engaged:
			var started := false
			for skill in targets[id].extras.get("skills", []):
				if npc_use_skill(id, str(skill)).get("ok", false):
					started = true
					break
			if started:
				actor.route.clear()
				continue
		actor.repath -= delta
		actor.attack_remaining -= delta
		if actor.engaged and in_range(id, 1):
			actor.route.clear()
			if actor.attack_remaining <= 0:
				var actions: Array = []
				counter_attack(id, actions)
				_apply({"actions": actions})
		elif actor.repath <= 0 and (actor.engaged or actor.feet().distance_to(actor.home) > 0.2):
			actor.repath = 0.5
			var result: Dictionary = world._navigation.find_path(actor.feet(), goal)
			actor.route = result.get("path", PackedVector3Array())
		actor.follow_path(delta, server.combat_stats.statuses.move_speed_mul(id))


func counter_attack(id: String, actions: Array) -> void:
	var server = Net.server()
	if server.combat_engine.is_npc_casting(id): return
	if not actors.has(id) or actors[id].attack_remaining > 0 or not server.combat_stats.player_alive() or not in_range(id, 1): return
	actors[id].attack_remaining = 1.5
	actors[id].engaged = true
	server.combat_engine._damage_player(server.combat_engine._effective_atk_npc(id), actions, id)


func use_item(id: String) -> Dictionary:
	if world._transfer_pending: return {"ok": false, "actions": []}
	var server = Net.server()
	var definition: Dictionary = server.item_catalog.get_item(id)
	if id == "pet_whistle": return summons.pet_summon()
	if str(definition.get("use_effect", "")) == "party_summon": return summons.party_start(id)
	if str(definition.get("type", "")) == "equipment": return _apply(server.try_toggle_equip(id))
	var effect := str(definition.get("use_effect", definition.get("effect", "")))
	if effect in ["recall", "teleport_home"]:
		if not server.combat_stats.player_alive() or in_combat() or server.combat_engine.is_casting():
			return _apply({"ok": false, "actions": [{"type": "system_message", "text": "死亡、战斗或施法中无法回城。"}]})
		if not server.inventory.has_item(id, 1) or not server.combat_stats.is_item_ready(id): return {"ok": false, "actions": []}
		var home: Dictionary = server.world3d_state.home
		if home.is_empty() or world._transfer_pending: return {"ok": false, "actions": []}
		world.transfer_map(str(home.path), home.position, func():
			var result: Dictionary = server.combat_engine.try_use_item(id)
			_apply(result)
			return bool(result.get("ok", false))
		)
		return {"ok": true, "pending": true, "actions": []}
	if effect not in ["heal_hp", "heal_mp", "apply_status", "clear_status", "cleanse", "repair_equip"]:
		return _apply({"ok": false, "actions": [{"type": "system_message", "text": "该物品的三维空间规则尚未接入，未消耗物品。"}]})
	return _apply(server.combat_engine.try_use_item(id))


func _clear_ray(from: Vector3, to: Vector3, target_id: String = "") -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.9, 0), to + Vector3(0, 0.9, 0))
	query.exclude = [world._player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (target_id != "" and str(hit.collider.get_meta("uuid", "")) == target_id)

func valid_ground(range_units: int) -> bool:
	if not ground_target is Vector3 or not ground_target.is_finite(): return false
	var feet: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
	if absf(feet.y - ground_target.y) > 1.0 or feet.distance_to(ground_target) > maxf(2.0, range_units * 2.0): return false
	return world._navigation.near_surface(ground_target, 0.35, 0.4) and _clear_ray(feet, ground_target)

func area_targets(radius: int, max_targets: int, shape: String) -> Array:
	var origin: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
	if ground_mode:
		if not ground_target is Vector3: return []
		origin = ground_target
	elif actors.has(area_target): origin = actors[area_target].feet()
	var forward: Vector3 = world._player.global_basis.z
	var reach := maxf(0.1, radius * 2.0)
	var candidates: Array = []
	for id in actors:
		if not Net.server().combat_stats.npcs.has(id) or not bool(Net.server().combat_stats.npcs[id].get("hostile", false)): continue
		var feet: Vector3 = actors[id].feet()
		var offset := feet - origin
		if absf(offset.y) > 1.0: continue
		offset.y = 0
		var distance := offset.length()
		if distance > reach: continue
		match shape:
			"cross", "plus":
				if absf(offset.x) > 0.5 and absf(offset.z) > 0.5: continue
			"line":
				if offset.dot(forward) < 0 or offset.cross(forward).length() > 0.5: continue
			"cone":
				if distance > 0.01 and offset.normalized().dot(forward) < 0.5: continue
		if not _clear_ray(origin, feet, id): continue
		candidates.append({"id": id, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance if a.distance != b.distance else str(a.id) < str(b.id))
	var result: Array = []
	for i in mini(maxi(1, max_targets), candidates.size()): result.append(candidates[i].id)
	return result


func _spawn_loot(id: String) -> void:
	if not actors.has(id): return
	var items: Array = Net.server().loot_catalog.roll(str(targets[id].extras.get("npc_id", id)))
	if items.is_empty(): return
	_create_loot(actors[id].feet(), items)

func _create_loot(feet: Vector3, items: Array) -> void:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e5c462")
	marker.material_override = material
	add_child(marker)
	marker.position = feet + Vector3(0, 0.16, 0)
	loot.append({"feet": feet, "items": items, "marker": marker})

func pickup_nearby() -> bool:
	var server = Net.server()
	if not server.combat_stats.player_alive(): return false
	var feet: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
	for drop in loot:
		if absf(feet.y - drop.feet.y) > 1.0 or feet.distance_to(drop.feet) > 2.0 or not _clear_ray(feet, drop.feet): continue
		var actions: Array = []
		var remaining: Array = []
		for item in drop.items:
			var result: Dictionary = server.inventory.try_add_item(str(item.item_id), int(item.qty))
			var added := int(result.get("added", 0))
			if added > 0: actions.append_array(server._quest_note_item_actions(str(item.item_id), added))
			if int(result.get("remaining", 0)) > 0:
				remaining.append({"item_id": item.item_id, "qty": result.remaining})
		drop.items = remaining
		if remaining.is_empty():
			drop.marker.queue_free()
			loot.erase(drop)
		actions.append({"type": "inventory_update", "items": server.inventory.snapshot(), "gold": server.inventory.get_gold()})
		actions.append({"type": "system_message", "text": "已拾取掉落。" if remaining.is_empty() else "背包空间不足，剩余物品仍在地面。"})
		_apply({"actions": actions})
		return true
	return false


func _landing_clear(body: CharacterBody3D, point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.29
	shape.height = float(body.get_meta("standing_height",1.8))-.02
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3(0, shape.height/2+.02, 0))
	query.exclude = [body.get_rid()]
	return world._navigation.near_surface(point, 0.35, 0.4) and world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func charge(id: String, definition: Dictionary, apply: bool) -> String:
	if not actors.has(id) or not Net.server().combat_stats.npcs.has(id): return "目标不存在。"
	var body: CharacterBody3D = world._player
	var start := body.global_position - Vector3(0, 0.9, 0)
	var target: Vector3 = actors[id].feet()
	var distance := start.distance_to(target)
	if not in_range(id, int(definition.get("range", 1))): return "目标太远、跨层或被遮挡。"
	if distance < float(definition.get("min_range", 0)) * 2.0: return "目标太近，无法冲锋。"
	var destination := target + (start - target).normalized() * 1.1
	if not _landing_clear(body, destination): return "冲锋落点被阻挡。"
	var route: Dictionary = world._navigation.find_path(start, destination)
	if not bool(route.get("ok", false)): return "冲锋路径不连通。"
	var points: PackedVector3Array = route.path
	var path_length := 0.0
	for i in range(1, points.size()): path_length += points[i - 1].distance_to(points[i])
	if path_length > start.distance_to(destination) + 0.3: return "冲锋不能绕过障碍。"
	if body.test_move(body.global_transform, destination - start): return "冲锋路径被阻挡。"
	# A straight capsule sweep also needs support across its full span: do not
	# charge over a pit simply because both endpoints have navigation polygons.
	var samples := maxi(1, int(ceil(start.distance_to(destination) / 0.2)))
	for i in range(1, samples + 1):
		if not world._navigation.near_surface(start.lerp(destination, float(i) / samples), 0.2, 0.25): return "冲锋路径没有连续地面。"
	if apply:
		body.global_position = destination + Vector3(0, 0.9, 0)
		body.velocity = Vector3.ZERO
		body.click_target = null
		body._route.clear()
		body._sense_surface()
		Net.server().world3d_authority._publish(body)
	return ""

func revive_error(id: String) -> String:
	var stats = Net.server().combat_stats
	if not actors.has(id) or not stats.npcs.has(id) or not bool(stats.npcs[id].get("ally", false)): return "只能复活同伴。"
	if int(stats.npcs[id].hp) > 0: return "目标未死亡。"
	if not _landing_clear(actors[id], actors[id].feet()): return "同伴的位置被占用，暂时无法复活。"
	return ""


func _signature(spec: Dictionary) -> String:
	return var_to_str([spec.transform, spec.mesh.get_aabb(), spec.extras]).sha256_text()

func _save_map_state() -> void:
	if _map_key == "": return
	if summons != null: summons.save()
	var records := {}
	var stats = Net.server().combat_stats
	for id in actors:
		var actor = actors[id]
		if bool(targets[id].extras.get("summoned", false)): continue
		# Actors use map coordinates under this identity-transform host. Children
		# have already exited the tree when our _exit_tree saves the session.
		records[id] = {"signature": _signature(targets[id]), "position": actor.position, "stats": stats.npcs.get(id, {}).duplicate(true), "statuses": stats.statuses.save_runtime(id), "skill_ready": _npc_ready.get(id, {}).duplicate(true), "respawn_remaining": actor.respawn_remaining, "defeated": defeated.has(id)}
	var drops: Array = []
	for drop in loot: drops.append({"feet": drop.feet, "items": drop.items.duplicate(true)})
	Net.server().world3d_state.write_map(_map_key, {"actors": records, "loot": drops, "saved_ms": Time.get_ticks_msec()})

func _restore_map_state() -> void:
	var saved: Dictionary = Net.server().world3d_state.read_map(_map_key)
	if saved.is_empty(): return
	var elapsed := maxf(0, float(Time.get_ticks_msec() - int(saved.get("saved_ms", 0))) / 1000.0)
	var stats = Net.server().combat_stats
	for id in actors:
		var record: Dictionary = saved.get("actors", {}).get(id, {})
		if record.is_empty() or record.get("signature", "") != _signature(targets[id]): continue
		_npc_ready[id] = record.get("skill_ready", {}).duplicate(true)
		var actor = actors[id]
		var position: Vector3 = record.position
		if position.is_finite() and (not world._navigation.fully_ready or world._navigation.near_surface(position - Vector3(0, 0.9, 0), 0.35, 0.65)): actor.global_position = position
		var data: Dictionary = record.stats
		if data.is_empty(): stats.remove_npc(id)
		else: stats.npcs[id] = data.duplicate(true)
		# Unloaded NPC combat is suspended, including DoT cadence and durations.
		stats.statuses.restore_runtime(id, record.get("statuses", []))
		var dead := data.is_empty() or int(data.get("hp", 0)) <= 0
		if dead:
			actor.collision_layer = 0
			actor.collision_mask = 0
			actor.model.play("death", "front")
			var remaining: float = record.get("respawn_remaining", -1)
			actor.respawn_remaining = maxf(0, remaining - elapsed) if remaining >= 0 else -1.0
		if bool(record.get("defeated", false)): defeated[id] = true
	for drop in saved.get("loot", []):
		if drop.feet.is_finite() and (not world._navigation.fully_ready or world._navigation.near_surface(drop.feet, 0.35, 0.65)): _create_loot(drop.feet, drop.items.duplicate(true))


func npc_use_skill(id: String, skill: String) -> Dictionary:
	var server = Net.server()
	if world._transfer_pending or not actors.has(id) or actors[id].returning: return {"ok": false}
	var ready: Dictionary = _npc_ready.get(id, {})
	if server.combat_stats.now_sec() < float(ready.get(skill, 0)): return {"ok": false}
	var result: Dictionary = server.combat_engine.try_npc_skill(id, skill, -9999, -9999)
	if result.get("ok", false):
		ready[skill] = server.combat_stats.now_sec() + maxf(0.4, float(server.skill_catalog.get_skill(skill).get("cooldown", 3)))
		_npc_ready[id] = ready
	return _apply(result)


func npc_skill_space(id: String, definition: Dictionary, resolving: bool) -> bool:
	if not actors.has(id) or not Net.server().combat_stats.npcs.has(id): return false
	if not bool(targets[id].extras.get("hostile", false)) or actors[id].returning: return false
	var effect := str(definition.get("effect", "damage"))
	if effect not in ["damage", "damage_and_status", "aoe_damage", "apply_status"]: return false
	if not in_range(id, int(definition.get("range", 1))): return false
	var feet: Vector3 = world._player.global_position - Vector3(0, 0.9, 0)
	if not resolving:
		_npc_ground[id] = feet
		var direction: Vector3 = feet - actors[id].feet()
		direction.y = 0
		_npc_forward[id] = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
		return true
	if effect != "aoe_damage": return true
	if not _npc_ground.has(id): return false
	var center: Vector3 = _npc_ground[id]
	var offset := feet - center
	if absf(offset.y) > 1.0: return false
	offset.y = 0
	var radius := maxf(0.1, float(definition.get("aoe_radius", 0)) * 2.0)
	if offset.length() > radius: return false
	var forward: Vector3 = _npc_forward.get(id, Vector3.FORWARD)
	match str(definition.get("aoe_shape", "circle")):
		"cross", "plus": return absf(offset.x) <= 0.5 or absf(offset.z) <= 0.5
		"line": return offset.dot(forward) >= 0 and offset.cross(forward).length() <= 0.5
		"cone": return offset.length() < 0.01 or offset.normalized().dot(forward) >= 0.5
	return true


func _npc_cast_feedback(action: Dictionary) -> void:
	var id := str(action.get("caster", ""))
	if not actors.has(id): return
	var kind := str(action.get("type", ""))
	if kind not in ["cast_start", "cast_update", "cast_end"]: return
	var label: Label3D = actors[id].cast_label
	label.visible = kind != "cast_end"
	if kind == "cast_end":
		if _npc_markers.has(id):
			_npc_markers[id].queue_free()
			_npc_markers.erase(id)
		return
	label.text = "%s %.1fs" % [action.get("name", "施法"), maxf(0, float(action.get("duration", 0)) - float(action.get("elapsed", 0)))]
	var definition: Dictionary = Net.server().skill_catalog.get_skill(str(action.get("skill_id", "")))
	if kind != "cast_start" or str(definition.get("effect", "")) != "aoe_damage": return
	if _npc_markers.has(id): _npc_markers[id].queue_free()
	var marker := MeshInstance3D.new()
	var radius := maxf(0.1, float(definition.get("aoe_radius", 0)) * 2.0)
	var center: Vector3 = _npc_ground.get(id, actors[id].feet())
	var excluded: Array[RID] = [world._player.get_rid()]
	for actor in actors.values(): excluded.append(actor.get_rid())
	marker.mesh = preload("res://scripts/world3d/terrain_warning.gd").build(world.get_world_3d().direct_space_state, center, radius, excluded)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/world3d/skill_area.gdshader")
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("shape", {"cross": 1, "plus": 1, "line": 2, "cone": 3}.get(str(definition.get("aoe_shape", "circle")), 0))
	var forward: Vector3 = _npc_forward.get(id, Vector3.FORWARD)
	material.set_shader_parameter("facing", Vector2(forward.x, forward.z))
	marker.material_override = material
	add_child(marker)
	marker.global_position = center
	_npc_markers[id] = marker
