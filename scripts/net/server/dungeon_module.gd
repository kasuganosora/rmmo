extends RefCounted
## Domain module: dungeon (enter/exit, guards, countable kills, rewards, complete).

var ctrl
func _init(c):
	ctrl = c

const DEMO_PACK_PATH := "content://map_pack/demo_map"
const DUNGEON_STREET_PACK := "content://map_pack/street_map"
const DUNGEON_STREET_MAP_ID := "street_map"
const DUNGEON_STREET_SPAWN := Vector2i(41, 23)
const DUNGEON_KILLS_NEEDED := 2
const DUNGEON_REWARD_GOLD := 50
const DUNGEON_REWARD_EXP := 80
const DUNGEON_REWARD_STONE_QTY := 1

func in_dungeon() -> bool:
	return not ctrl._dungeon.is_empty() and bool(ctrl._dungeon.get("active", false))



func snapshot_dungeon() -> Dictionary:
	if ctrl._dungeon.is_empty():
		return {
			"active": false,
			"completed": false,
			"kills": 0,
			"kills_needed": 0,
		}
	var rc: Dictionary = {"x": 0, "y": 0}
	var rc_v: Variant = ctrl._dungeon.get("return_cell", {})
	if typeof(rc_v) == TYPE_DICTIONARY:
		rc = {
			"x": int((rc_v as Dictionary).get("x", 0)),
			"y": int((rc_v as Dictionary).get("y", 0)),
		}
	return {
		"active": bool(ctrl._dungeon.get("active", false)),
		"completed": bool(ctrl._dungeon.get("completed", false)),
		"kills": int(ctrl._dungeon.get("kills", 0)),
		"kills_needed": int(ctrl._dungeon.get("kills_needed", DUNGEON_KILLS_NEEDED)),
		"return_pack": str(ctrl._dungeon.get("return_pack", "")),
		"return_cell": rc,
	}



func _dungeon_update_action() -> Dictionary:
	return {"type": "dungeon_update", "dungeon": snapshot_dungeon()}



func _dungeon_force_clear_silent() -> void:
	ctrl._dungeon.clear()
	ctrl._dungeon_xfer_lock = false



func _dungeon_abandon_on_leave() -> Array:
	## Clear session without reward (early warp / leave).
	var actions: Array = []
	if ctrl._dungeon.is_empty():
		return actions
	var was_active = bool(ctrl._dungeon.get("active", false)) or bool(ctrl._dungeon.get("completed", false))
	ctrl._dungeon.clear()
	if was_active:
		actions.append(_dungeon_update_action())
		actions.append({"type": "system_message", "text": "试炼已放弃。"})
	return actions



func _dungeon_return_cell_dict() -> Dictionary:
	if ctrl.player_cell.x > -9990:
		return {"x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	return {"x": ctrl.respawn_cell.x, "y": ctrl.respawn_cell.y}



func _dungeon_pick_guard_cells(count: int) -> Array:
	## Free cells near street spawn for slim dungeon guards.
	var out: Array = []
	var origin = DUNGEON_STREET_SPAWN
	if ctrl.map_collision != null and ctrl.map_collision.has_method("find_spawn_near"):
		origin = ctrl.map_collision.find_spawn_near(DUNGEON_STREET_SPAWN.x, DUNGEON_STREET_SPAWN.y)
	var used: Dictionary = {}
	used["%d,%d" % [ctrl.player_cell.x, ctrl.player_cell.y]] = true
	var offsets: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
	]
	for off_v in offsets:
		if out.size() >= count:
			break
		var off: Vector2i = off_v
		var cx: int = origin.x + off.x
		var cy: int = origin.y + off.y
		var key = "%d,%d" % [cx, cy]
		if used.has(key):
			continue
		var ok = true
		if ctrl.map_collision != null and ctrl.map_collision.has_method("is_landable"):
			ok = ctrl.map_collision.is_landable(cx, cy)
		if not ok:
			continue
		used[key] = true
		out.append(Vector2i(cx, cy))
	while out.size() < count:
		var fallback = Vector2i(origin.x + out.size() + 1, origin.y)
		out.append(fallback)
	return out



func _dungeon_spawn_guards() -> Array:
	## Register 2 slim hostiles with meta dungeon=true; return spawn_npc actions.
	var actions: Array = []
	var cells: Array = _dungeon_pick_guard_cells(DUNGEON_KILLS_NEEDED)
	var guard_ids: Array = []
	for i in range(DUNGEON_KILLS_NEEDED):
		var gid = "dungeon_guard_%d" % i
		var cell: Vector2i = cells[i] if i < cells.size() else DUNGEON_STREET_SPAWN
		var spawn = {
			"id": gid,
			"name": "试炼守卫",
			"charset": "retira_slime",
			"index": 4,
			"cell": {"x": cell.x, "y": cell.y},
			"direction": 2,
			"hostile": true,
			"aggressive": true,
			"wander_radius": 1,
			"leash_radius": 8,
			"respawn_sec": -1.0,
			"dungeon": true,
			"hp_max": 40,
			"level": 3,
			"atk": 8,
			"def": 2,
			"kind": "monster",
		}
		ctrl.register_npc(gid, cell.x, cell.y, true, true, 2, 1, 0, spawn)
		if ctrl.map_collision != null and ctrl.map_collision.has_method("set_extra_blocked"):
			ctrl.map_collision.set_extra_blocked(cell.x, cell.y, true)
		actions.append({"type": "spawn_npc", "npc": spawn.duplicate(true)})
		guard_ids.append(gid)
	ctrl._dungeon["guard_ids"] = guard_ids
	return actions



func _dungeon_is_countable_kill(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not in_dungeon():
		return false
	var guards_v: Variant = ctrl._dungeon.get("guard_ids", [])
	if typeof(guards_v) == TYPE_ARRAY:
		for g in guards_v:
			if str(g) == npc_id:
				return true
	if npc_id.begins_with("dungeon_guard_"):
		return true
	if ctrl.npc_meta.has(npc_id) and typeof(ctrl.npc_meta[npc_id]) == TYPE_DICTIONARY:
		if bool(ctrl.npc_meta[npc_id].get("dungeon", false)):
			return true
	# Fallback: any hostile kill while dungeon.active counts if no guards tracked.
	var guards: Array = guards_v if typeof(guards_v) == TYPE_ARRAY else []
	if guards.is_empty():
		if ctrl.combat_stats != null and ctrl.combat_stats.npcs.has(npc_id):
			return bool(ctrl.combat_stats.npcs[npc_id].get("hostile", false))
		return true
	return false



func _dungeon_grant_rewards() -> Array:
	var actions: Array = []
	if ctrl.inventory != null and DUNGEON_REWARD_GOLD > 0:
		ctrl.inventory.add_gold(DUNGEON_REWARD_GOLD)
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "获得金币 %d" % DUNGEON_REWARD_GOLD})
	if ctrl.inventory != null and DUNGEON_REWARD_STONE_QTY > 0:
		ctrl.inventory.add_item("enhance_stone", DUNGEON_REWARD_STONE_QTY)
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "获得：强化石 ×%d" % DUNGEON_REWARD_STONE_QTY})
	if ctrl.combat_stats != null and DUNGEON_REWARD_EXP > 0:
		var summary: Dictionary = ctrl.combat_stats.grant_exp(DUNGEON_REWARD_EXP)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", DUNGEON_REWARD_EXP)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "获得经验 %d" % int(summary.get("amount", DUNGEON_REWARD_EXP))})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else ctrl.combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				actions.append({"type": "level_up", "level": int(lv_v), "combat": combat_snap})
			actions.append({"type": "set_stat", "target": "player", "combat": combat_snap})
	return actions



func _dungeon_complete() -> Array:
	var actions: Array = []
	if not in_dungeon() or bool(ctrl._dungeon.get("completed", false)):
		return actions
	ctrl._dungeon["completed"] = true
	ctrl._dungeon["active"] = false
	actions.append({"type": "system_message", "text": "试炼完成！"})
	actions.append_array(_dungeon_grant_rewards())
	actions.append(_dungeon_update_action())
	return actions



func _dungeon_note_kill(npc_id: String) -> Array:
	var actions: Array = []
	if not in_dungeon():
		return actions
	if not _dungeon_is_countable_kill(npc_id):
		return actions
	var kills: int = int(ctrl._dungeon.get("kills", 0)) + 1
	ctrl._dungeon["kills"] = kills
	var needed: int = int(ctrl._dungeon.get("kills_needed", DUNGEON_KILLS_NEEDED))
	actions.append(_dungeon_update_action())
	if kills >= needed:
		actions.append_array(_dungeon_complete())
	return actions



func try_dungeon_enter() -> Dictionary:
	## One-shot: transfer demo → street_map, spawn 2 dungeon guards, start session.
	var actions: Array = []
	if in_dungeon():
		actions.append({"type": "system_message", "text": "试炼已在进行中。"})
		actions.append(_dungeon_update_action())
		return {"ok": false, "reason": "already", "actions": actions}
	if bool(ctrl._dungeon.get("completed", false)):
		actions.append({"type": "system_message", "text": "请先离开试炼。"})
		actions.append(_dungeon_update_action())
		return {"ok": false, "reason": "completed", "actions": actions}
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var return_pack: String = ctrl.map_pack_path if ctrl.map_pack_path != "" else DEMO_PACK_PATH
	var return_map: String = ctrl.map_pack_id if ctrl.map_pack_id != "" else "demo_map"
	var return_cell: Dictionary = _dungeon_return_cell_dict()
	ctrl._dungeon_xfer_lock = true
	var xfer: Dictionary = ctrl._event_perform_transfer(
		DUNGEON_STREET_PACK,
		{"x": DUNGEON_STREET_SPAWN.x, "y": DUNGEON_STREET_SPAWN.y},
		4,
		"进入试炼洞窟",
		DUNGEON_STREET_MAP_ID
	)
	ctrl._dungeon_xfer_lock = false
	if not bool(xfer.get("ok", false)):
		actions.append({"type": "system_message", "text": "无法进入试炼洞窟。"})
		return {"ok": false, "reason": "transfer", "actions": actions}
	ctrl._dungeon = {
		"active": true,
		"completed": false,
		"kills": 0,
		"kills_needed": DUNGEON_KILLS_NEEDED,
		"return_pack": return_pack,
		"return_map": return_map,
		"return_cell": return_cell,
		"guard_ids": [],
	}
	var spawn_actions: Array = _dungeon_spawn_guards()
	actions.append({
		"type": "map_transfer",
		"ok": true,
		"pack_path": str(xfer.get("pack_path", DUNGEON_STREET_PACK)),
		"map_id": str(xfer.get("map_id", DUNGEON_STREET_MAP_ID)),
		"content_id": str(xfer.get("content_id", "")),
		"content_version": str(xfer.get("content_version", "")),
		"cell": xfer.get("cell", {"x": DUNGEON_STREET_SPAWN.x, "y": DUNGEON_STREET_SPAWN.y}),
		"facing": int(xfer.get("facing", 4)),
		"message": "进入试炼洞窟",
		"quests": xfer.get("quests", []),
	})
	var xfer_acts_v: Variant = xfer.get("actions", [])
	if typeof(xfer_acts_v) == TYPE_ARRAY:
		actions.append_array(xfer_acts_v)
	actions.append_array(spawn_actions)
	actions.append({"type": "system_message", "text": "试炼开始：击败 %d 只守卫。" % DUNGEON_KILLS_NEEDED})
	actions.append(_dungeon_update_action())
	var out = {
		"ok": true,
		"pack_path": str(xfer.get("pack_path", DUNGEON_STREET_PACK)),
		"map_id": str(xfer.get("map_id", DUNGEON_STREET_MAP_ID)),
		"content_id": str(xfer.get("content_id", "")),
		"content_version": str(xfer.get("content_version", "")),
		"cell": xfer.get("cell", {"x": DUNGEON_STREET_SPAWN.x, "y": DUNGEON_STREET_SPAWN.y}),
		"facing": int(xfer.get("facing", 4)),
		"message": "进入试炼洞窟",
		"dungeon": snapshot_dungeon(),
		"actions": actions,
	}
	out.merge(ctrl._transfer_result_extras())
	return out



func try_dungeon_exit() -> Dictionary:
	## Transfer back to saved demo return cell; clear session.
	var actions: Array = []
	if ctrl._dungeon.is_empty():
		actions.append({"type": "system_message", "text": "当前没有试炼。"})
		return {"ok": false, "reason": "idle", "actions": actions}
	var ret_pack: String = str(ctrl._dungeon.get("return_pack", DEMO_PACK_PATH)).strip_edges()
	if ret_pack.is_empty():
		ret_pack = DEMO_PACK_PATH
	var ret_map: String = str(ctrl._dungeon.get("return_map", "demo_map")).strip_edges()
	var ret_cell_v: Variant = ctrl._dungeon.get("return_cell", {"x": 15, "y": 12})
	var ret_cell: Dictionary = ret_cell_v if typeof(ret_cell_v) == TYPE_DICTIONARY else {"x": 15, "y": 12}
	var completed = bool(ctrl._dungeon.get("completed", false))
	# Clear before transfer so abandon hook does not fire.
	ctrl._dungeon.clear()
	ctrl._dungeon_xfer_lock = true
	var xfer: Dictionary = ctrl._event_perform_transfer(
		ret_pack,
		{"x": int(ret_cell.get("x", 15)), "y": int(ret_cell.get("y", 12))},
		2,
		"离开试炼洞窟",
		ret_map
	)
	ctrl._dungeon_xfer_lock = false
	if not bool(xfer.get("ok", false)):
		actions.append({"type": "system_message", "text": "无法离开试炼。"})
		actions.append(_dungeon_update_action())
		return {"ok": false, "reason": "transfer", "actions": actions}
	actions.append({
		"type": "map_transfer",
		"ok": true,
		"pack_path": str(xfer.get("pack_path", ret_pack)),
		"map_id": str(xfer.get("map_id", ret_map)),
		"content_id": str(xfer.get("content_id", "")),
		"content_version": str(xfer.get("content_version", "")),
		"cell": xfer.get("cell", ret_cell),
		"facing": int(xfer.get("facing", 2)),
		"message": "离开试炼洞窟",
		"quests": xfer.get("quests", []),
	})
	var xfer_acts_v: Variant = xfer.get("actions", [])
	if typeof(xfer_acts_v) == TYPE_ARRAY:
		actions.append_array(xfer_acts_v)
	actions.append(_dungeon_update_action())
	if completed:
		actions.append({"type": "system_message", "text": "已返回。"})
	else:
		actions.append({"type": "system_message", "text": "试炼已中止，返回。"})
	var out = {
		"ok": true,
		"pack_path": str(xfer.get("pack_path", ret_pack)),
		"map_id": str(xfer.get("map_id", ret_map)),
		"cell": xfer.get("cell", ret_cell),
		"facing": int(xfer.get("facing", 2)),
		"dungeon": snapshot_dungeon(),
		"actions": actions,
	}
	out.merge(ctrl._transfer_result_extras())
	return out

