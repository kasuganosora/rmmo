extends RefCounted
const Net = preload("res://scripts/net/net.gd")
const PET_ID := "summoned_pet"
var combat: Node
var pending := {}
var _tick := 0.0
func _init(owner: Node): combat = owner

func failure(reason: String) -> Dictionary:
	return combat._apply({"ok": false, "reason": reason, "actions": [{"type": "system_message", "text": reason}]})

func landing() -> Variant:
	var world = combat.world
	var origin: Vector3 = world._player.position - Vector3(0, 0.9, 0)
	for radius in [1.2, 2.0, 3.0]:
		for i in 8:
			var point: Vector3 = origin + Vector3(cos(i * PI / 4), 0, sin(i * PI / 4)) * radius
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.2, point - Vector3.UP * 1.2)
			ray.exclude = [world._player.get_rid()]
			var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
			if floor_hit.is_empty() or floor_hit.normal.y < cos(deg_to_rad(40)): continue
			point = floor_hit.position
			if not combat._landing_clear(world._player, point): continue
			var occupied := false
			for actor in combat.actors.values():
				if actor.collision_layer != 0 and actor.feet().distance_to(point) < 0.65: occupied = true
			if not occupied and world._navigation.find_path(origin, point).get("ok", false): return point
	return null

func allowed() -> bool:
	return not combat.world._transfer_pending and Net.server().combat_stats.player_alive()

func spawn(id: String, title: String, point: Vector3, saved: Dictionary = {}) -> void:
	var doc = preload("res://scripts/world3d/world_document.gd").new()
	var key: String = doc.add_npc(point + Vector3(0, 0.8, 0), id, "")
	var record: Dictionary = doc._find(key)
	record.merge({"uuid": id, "name": title, "ally": true, "summoned": true}, true)
	var visual: MeshInstance3D = doc._mesh(record)
	var spec: Dictionary = preload("res://scripts/world3d/world_stream.gd")._spec(visual)
	spec.extras["summoned"] = true
	visual.free()
	combat.targets[id] = spec
	var actor = preload("res://scripts/world3d/world_npc.gd").new()
	actor.configure(spec)
	combat.add_child(actor)
	actor.authority.mount(actor, combat.world._navigation, combat.world._map_ref())
	combat.actors[id] = actor
	var stats = Net.server().combat_stats
	var data: Dictionary = stats.ensure_npc(id, false)
	data.ally = true
	if not saved.is_empty():
		stats.npcs[id] = saved.stats.duplicate(true)
		stats.statuses.restore_runtime(id, saved.get("statuses", []))
		if int(stats.npcs[id].hp) <= 0:
			actor.collision_layer = 0
			actor.collision_mask = 0
			actor.model.play("death", "front")
	Net.server().world3d_state.summons[id] = {"name": title, "stats": stats.npcs[id].duplicate(true)}

func pet_summon(_id: String = "default") -> Dictionary:
	if not allowed(): return failure("当前无法召唤。")
	var server = Net.server()
	if server.world3d_state.summons.has(PET_ID): return failure("已有宠物。")
	if not server.inventory.has_item("pet_whistle", 1): return failure("需要宠物哨子。")
	var point: Variant = landing()
	if point == null: return failure("附近没有安全的召唤位置。")
	spawn(PET_ID, "小跟班", point, server.world3d_state.stowed_pet)
	return combat._apply({"ok": true, "actions": [{"type": "system_message", "text": "召唤了小跟班，哨子未消耗。"}]})

func pet_dismiss() -> Dictionary:
	if combat.in_combat(): return failure("战斗中无法收回宠物。")
	if not allowed(): return failure("当前无法收回宠物。")
	if not Net.server().world3d_state.summons.has(PET_ID): return failure("当前没有宠物。")
	if combat.actors.has(PET_ID) and int(Net.server().combat_stats.npcs.get(PET_ID, {}).get("hp", 0)) <= 0: return failure("请先复活倒地的宠物。")
	save()
	Net.server().world3d_state.stowed_pet = Net.server().world3d_state.summons[PET_ID].duplicate(true)
	remove(PET_ID)
	return combat._apply({"ok": true, "actions": [{"type": "system_message", "text": "已收回宠物。"}]})

func remove(id: String) -> void:
	if combat.actors.has(id): combat.actors[id].free()
	combat.actors.erase(id)
	combat.targets.erase(id)
	Net.server().combat_stats.remove_npc(id)
	Net.server().world3d_state.summons.erase(id)

func save() -> void:
	var server = Net.server()
	for id in combat.actors:
		if not bool(combat.targets[id].extras.get("summoned", false)): continue
		server.world3d_state.summons[id] = {"name": combat.targets[id].extras.get("name", id), "stats": server.combat_stats.npcs.get(id, {}).duplicate(true), "statuses": server.combat_stats.statuses.save_runtime(id)}

func restore() -> void:
	for id in Net.server().world3d_state.summons.keys():
		var saved: Dictionary = Net.server().world3d_state.summons[id]
		var point: Variant = landing()
		if point == null: continue # Keep in session; retry after player reaches space.
		spawn(id, str(saved.name), point, saved)

func party_start(item: String) -> Dictionary:
	var server = Net.server()
	snapshot_party()
	if not allowed() or not server.in_party(): return failure("需要存活且已加入队伍。")
	if not pending.is_empty() and server.combat_stats.now_sec() > float(pending.expires): pending.clear()
	if not pending.is_empty(): return failure("已有进行中的集结。")
	if not server.inventory.has_item(item, 1) or not server.combat_stats.is_item_ready(item): return failure("缺少道具或道具冷却中。")
	var invites := {}
	for member in server._party_members:
		var id := str(member.get("id", ""))
		if id == "" or id == server._party_self_id() or not bool(member.get("online", true)): continue
		if str(member.get("map_id", "")) not in ["", server.map_pack_id, combat.world._map_ref()]: continue
		if not server.world3d_state.summons.has("summoned_party_" + id): invites[id] = str(member.get("name", id))
	if invites.is_empty() or landing() == null: return failure("没有可集结的队友或安全落点。")
	if not server.inventory.consume(item, 1): return failure("缺少集结道具。")
	server.combat_stats.set_item_cooldown(item, float(server.item_catalog.get_item(item).get("cooldown", 60)))
	pending = {"invites": invites, "expires": server.combat_stats.now_sec() + 30, "party_id": server.party_id, "id": "world3d_%d" % Time.get_ticks_usec()}
	var result: Dictionary = combat._apply({"ok": true, "actions": [{"type": "inventory_update", "items": server.inventory.snapshot(), "gold": server.inventory.get_gold()}, {"type": "system_message", "text": "已发出队伍集结，等待接受。"}]})
	if server.party_summon_auto_accept:
		for id in invites.keys(): party_accept(id)
	return result

func party_accept(id: String = "") -> Dictionary:
	if not allowed() or pending.is_empty(): return failure("没有可接受的集结。")
	if not Net.server().in_party() or str(pending.get("party_id", "")) != Net.server().party_id:
		pending.clear()
		return failure("队伍已变化，集结失效。")
	if Net.server().combat_stats.now_sec() > float(pending.expires):
		pending.clear()
		return failure("集结已过期。")
	if id == "": id = str(pending.invites.keys()[0])
	if not pending.invites.has(id): return failure("该邀请已处理。")
	var online := false
	for member in Net.server()._party_members:
		if str(member.get("id", "")) == id and bool(member.get("online", true)) and str(member.get("map_id", "")) in ["", Net.server().map_pack_id, combat.world._map_ref()]: online = true
	if not online: return failure("队友已离队或离线。")
	var point: Variant = landing()
	if point == null: return failure("落点被占用，请稍后接受。")
	spawn("summoned_party_" + id, str(pending.invites[id]), point)
	pending.invites.erase(id)
	if pending.invites.is_empty(): pending.clear()
	return combat._apply({"ok": true, "actions": [{"type": "system_message", "text": "队友已到达。"}]})

func party_decline(id: String = "") -> Dictionary:
	if pending.is_empty(): return {"ok": false}
	if id == "": id = str(pending.invites.keys()[0])
	if not pending.invites.has(id): return {"ok": false}
	pending.invites.erase(id)
	if pending.invites.is_empty(): pending.clear()
	return {"ok": true}


func tick(delta: float) -> void:
	_tick += delta
	if _tick < 1.5: return
	_tick = 0.0
	var server = Net.server()
	if not pending.is_empty() and server.combat_stats.now_sec() > float(pending.expires): pending.clear()
	if not allowed(): return
	for id in server.world3d_state.summons.keys():
		if str(id).begins_with("summoned_party_"):
			var exists := false
			for member in server._party_members:
				if str(member.get("id", "")) == str(id).trim_prefix("summoned_party_") and bool(member.get("online", true)): exists = true
			if not server.in_party() or not exists:
				remove(id)
				continue
		if combat.actors.has(id): continue
		var point: Variant = landing()
		if point == null: break
		var saved: Dictionary = server.world3d_state.summons[id]
		spawn(id, str(saved.name), point, saved)
	if not server.pet_assist or not combat.actors.has(PET_ID) or not server.combat_stats.npcs.has(PET_ID) or int(server.combat_stats.npcs[PET_ID].hp) <= 0: return
	var target: String = combat.selected
	if not combat.actors.has(target) or not server.combat_stats.npcs.has(target) or not bool(server.combat_stats.npcs[target].get("hostile", false)): return
	var from: Vector3 = combat.actors[PET_ID].feet()
	var to: Vector3 = combat.actors[target].feet()
	if absf(from.y - to.y) > 1 or from.distance_to(to) > 4: return
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.9, to + Vector3.UP * 0.9)
	ray.exclude = [combat.actors[PET_ID].get_rid()]
	var hit: Dictionary = combat.world.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider != combat.actors[target]: return
	var actions: Array = []
	server.combat_engine._damage_npc(target, server._pet_module_logic._pet_atk(), actions, false)
	combat._apply({"actions": actions})


func snapshot_pet() -> Dictionary:
	var server = Net.server()
	var saved: Dictionary = server.world3d_state.summons.get(PET_ID, {})
	if saved.is_empty(): return {"active": false, "assist": server.pet_assist}
	var actor = combat.actors.get(PET_ID)
	return {"active": true, "id": PET_ID, "name": saved.get("name", "小跟班"), "assist": server.pet_assist, "atk": server._pet_module_logic._pet_atk(), "resident": actor != null, "map_ref": combat.world._map_ref(), "position_m": actor.feet() if actor != null else null, "stats": server.combat_stats.npcs.get(PET_ID, saved.get("stats", {})).duplicate(true)}


func snapshot_party() -> Dictionary:
	var server = Net.server()
	if pending.is_empty(): return {"active": false}
	if not server.in_party() or str(pending.get("party_id", "")) != server.party_id or server.combat_stats.now_sec() > float(pending.expires):
		pending.clear()
		return {"active": false}
	var invites := {}
	for id in pending.invites: invites[id] = {"name": pending.invites[id], "accepted": false}
	return {"active": true, "id": pending.id, "caster_id": server._party_self_id(), "map_id": combat.world._map_ref(), "caster_position_m": combat.world._player.position - Vector3.UP * 0.9, "invites": invites, "expires_at": pending.expires}
