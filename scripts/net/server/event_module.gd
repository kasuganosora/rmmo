extends RefCounted
## Domain module: map event runtime (switches/pages, npc step/face, touch, choice).

var ctrl
func _init(c):
	ctrl = c


const SHELL_REMOTE_COUNT := 1

func _event_server_ctx(npc_name: String = "") -> Dictionary:
	return {
		"inventory": ctrl.inventory,
		"shop_catalog": ctrl.shop_catalog,
		"npc_name": npc_name,
		"transfer_cb": Callable(ctrl, "_event_perform_transfer"),
		"item_name_cb": Callable(ctrl, "item_display_name"),
		"quest_item_cb": Callable(ctrl, "_quest_note_item_actions"),
		"weather_cb": Callable(ctrl, "set_weather"),
		"npc_step_cb": Callable(ctrl, "_event_npc_step"),
		"npc_face_cb": Callable(ctrl, "_event_npc_face"),
		"npc_cell_cb": Callable(ctrl, "_event_npc_cell"),
		"npc_facing_cb": Callable(ctrl, "_event_npc_facing"),
		"inn_rest_cb": Callable(ctrl, "try_inn_rest"),
		"open_shop_cb": Callable(ctrl, "_try_open_shop_action"),
		"repair_cb": Callable(ctrl, "try_repair"),
		"collision": ctrl.map_collision,
		"player_cell": ctrl.player_cell,
	}



func _event_npc_step(npc_id: String, from_x: int, from_y: int, dir: int) -> Dictionary:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty():
		return {"ok": false, "x": from_x, "y": from_y}
	# Ensure cell is known so later AI / interact use the moved position.
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("set_npc_cell"):
		var cur: Vector2i = Vector2i(-9999, -9999)
		if ctrl.combat_stats.has_method("get_npc_cell"):
			cur = ctrl.combat_stats.get_npc_cell(npc_id)
		if cur.x < -9000:
			ctrl.combat_stats.set_npc_cell(npc_id, from_x, from_y)
	var moved: Dictionary = ctrl.try_npc_move(npc_id, from_x, from_y, dir)
	if bool(moved.get("ok", false)) and ctrl.event_runtime != null:
		if ctrl.event_runtime.has_method("has_event") and ctrl.event_runtime.has_event(npc_id):
			if ctrl.event_runtime.has_method("update_event_cell"):
				ctrl.event_runtime.update_event_cell(npc_id, int(moved.get("x", from_x)), int(moved.get("y", from_y)))
	return moved



func _event_npc_face(npc_id: String, facing: int) -> void:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty() or ctrl.combat_stats == null:
		return
	if ctrl.combat_stats.has_method("set_npc_facing"):
		ctrl.combat_stats.set_npc_facing(npc_id, facing)



func _event_npc_cell(npc_id: String) -> Vector2i:
	npc_id = str(npc_id).strip_edges()
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("get_npc_cell"):
		var c: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id)
		if c.x > -9000:
			return c
	if ctrl.event_runtime != null and ctrl.event_runtime.has_method("get_event"):
		var ev: Dictionary = ctrl.event_runtime.get_event(npc_id)
		var cv: Variant = ev.get("cell", {})
		if typeof(cv) == TYPE_DICTIONARY:
			return Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
	return Vector2i.ZERO



func _event_npc_facing(npc_id: String) -> int:
	npc_id = str(npc_id).strip_edges()
	if ctrl.combat_stats != null and ctrl.combat_stats.npc_ai.has(npc_id):
		var f = int(ctrl.combat_stats.npc_ai[npc_id].get("facing", 2))
		if f in [2, 4, 6, 8]:
			return f
	return 2





func _event_perform_transfer(
	to_pack: String,
	to_cell: Dictionary,
	facing: int = 2,
	message: String = "",
	to_map_id: String = ""
) -> Dictionary:
	to_pack = str(to_pack).strip_edges()
	if to_pack.is_empty():
		to_pack = ctrl.map_pack_path
	if to_pack.is_empty():
		return {"ok": false}
	var dungeon_was_active: bool = (not ctrl._dungeon_xfer_lock) and (ctrl.in_dungeon() or not ctrl._dungeon.is_empty())
	var tx: int = int(to_cell.get("x", 0))
	var ty: int = int(to_cell.get("y", 0))
	var prev_path = ctrl.map_pack_path
	if not ctrl._load_pack(to_pack, to_map_id):
		ctrl._load_pack(prev_path if prev_path != "" else ctrl.start_map_pack_path())
		return {"ok": false}
	if to_map_id.strip_edges().is_empty():
		to_map_id = ctrl.map_pack_id
	if ctrl.map_collision != null and ctrl.map_collision.has_method("is_landable"):
		if not ctrl.map_collision.is_landable(tx, ty) and ctrl.map_collision.has_method("find_spawn_near"):
			var near: Vector2i = ctrl.map_collision.find_spawn_near(tx, ty)
			tx = near.x
			ty = near.y
	ctrl.respawn_cell = Vector2i(tx, ty)
	ctrl.last_safe_cell = Vector2i(tx, ty)
	ctrl.set_player_cell(tx, ty)
	ctrl._ensure_shell_remotes(SHELL_REMOTE_COUNT)
	var reach_actions: Array = ctrl._quest_note_reach_actions(
		to_map_id if to_map_id != "" else ctrl.map_pack_id, ctrl.map_content_id, ctrl.map_pack_path
	)
	var out = {
		"ok": true,
		"pack_path": ctrl.map_pack_path,
		"map_id": to_map_id if to_map_id != "" else ctrl.map_pack_id,
		"content_id": ctrl.map_content_id,
		"content_version": ctrl.map_content_version,
		"cell": {"x": tx, "y": ty},
		"facing": facing if facing in [2, 4, 6, 8] else 2,
		"message": message,
		"quests": ctrl.quest_journal.snapshot() if ctrl.quest_journal != null else [],
	}
	out.merge(ctrl._transfer_result_extras())
	var actions: Array = []
	actions.append({"type": "loot_close"})
	actions.append({"type": "system_message", "text": "已切换地图：上一张图的地面掉落不会带入。"})
	if not reach_actions.is_empty():
		actions.append_array(reach_actions)
	actions.append_array(ctrl._shell_remote_spawn_actions())
	actions.append_array(ctrl._safe_zone_transition_actions(true))
	if dungeon_was_active:
		actions.append_array(ctrl._dungeon_abandon_on_leave())
	out["actions"] = actions
	out["dungeon"] = ctrl.snapshot_dungeon()
	return out



func _try_player_touch_events(x: int, y: int) -> Array:
	if ctrl.event_runtime == null:
		return []
	var ev: Dictionary = ctrl.event_runtime.get_event_at_cell(x, y)
	if ev.is_empty():
		return []
	var ctx = _event_server_ctx(str(ev.get("name", ev.get("id", ""))))
	var page: Dictionary = ctrl.event_runtime.select_page_with_ctx(ev, ctx) if ctrl.event_runtime.has_method("select_page_with_ctx") else {}
	var trig = str(ev.get("trigger", ""))
	if ctrl.event_runtime.has_method("page_trigger"):
		trig = str(ctrl.event_runtime.page_trigger(ev, page))
	if trig != "player_touch":
		return []
	return ctrl.event_runtime.run_event(str(ev.get("id", "")), ctx)



func _event_touch_event(npc_id: String, from_x: int, from_y: int) -> Dictionary:
	if ctrl.event_runtime == null:
		return {}
	var ev: Dictionary = ctrl.event_runtime.get_event(npc_id)
	if ev.is_empty():
		ev = ctrl.event_runtime.get_event_at_cell(from_x, from_y)
	if ev.is_empty():
		return {}
	var ctx = _event_server_ctx(str(ev.get("name", ev.get("id", ""))))
	var page: Dictionary = ctrl.event_runtime.select_page_with_ctx(ev, ctx) if ctrl.event_runtime.has_method("select_page_with_ctx") else {}
	var trig = str(ev.get("trigger", ""))
	if ctrl.event_runtime.has_method("page_trigger"):
		trig = str(ctrl.event_runtime.page_trigger(ev, page))
	if trig != "event_touch":
		return {}
	return ev



func try_event_choice(option_id: String = "", option_index: int = -1) -> Dictionary:
	return ctrl.try_dialogue_choice(option_id, option_index)


