extends RefCounted
## Domain module: world (weather, pack load, safe-zone, transfer, map pins).

var ctrl
func _init(c):
	ctrl = c

const TilemapPack = preload("res://scripts/map/tilemap_pack.gd")
const EventRuntime = preload("res://scripts/net/combat/event_runtime.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const DEMO_PACK_PATH := "res://demo_map"
const MAP_PIN_MAX := 3
const SHELL_REMOTE_COUNT := 1

func get_weather() -> Dictionary:
	return {
		"kind": ctrl.weather_kind,
		"intensity": ctrl.weather_intensity,
		"indoor": _map_indoor(),
		"environment": ctrl.map_environment,
	}



func set_weather(kind: String, intensity: float = 0.75, duration: float = 60.0) -> Dictionary:
	if _map_indoor():
		kind = "clear"
		intensity = 0.0
	ctrl.weather_kind = Weather.normalize(kind)
	ctrl.weather_intensity = 0.0 if ctrl.weather_kind == "clear" else clampf(intensity, 0.0, 1.0)
	ctrl._weather_left = maxf(duration, 0.0)
	var act = _weather_action()
	ctrl._pending_tick_actions.append(act)
	return act



func _map_indoor() -> bool:
	return MapExt.normalize_environment(ctrl.map_environment) == MapExt.ENV_INDOOR



func _weather_action() -> Dictionary:
	return {"type": "weather", "kind": ctrl.weather_kind, "intensity": ctrl.weather_intensity}



func _reset_weather_for_map() -> void:
	ctrl._weather_rng.seed = 17041 + int(ctrl.map_pack_id.hash())
	if _map_indoor():
		ctrl.weather_kind = "clear"
		ctrl.weather_intensity = 0.0
		ctrl._weather_left = 99999.0
	else:
		ctrl.weather_kind = "clear"
		ctrl.weather_intensity = 0.0
		var dur: Vector2 = Weather.duration_range()
		ctrl._weather_left = ctrl._weather_rng.randf_range(dur.x, dur.y)



func _tick_weather(delta: float) -> void:
	if not ctrl.weather_auto:
		return
	if _map_indoor():
		if ctrl.weather_kind != "clear" or ctrl.weather_intensity > 0.001:
			set_weather("clear", 0.0, 99999.0)
		return
	ctrl._weather_left -= delta
	if ctrl._weather_left > 0.0:
		return
	var cycle: Array = Weather.cycle_list()
	if cycle.is_empty():
		cycle = ["clear"]
	var nxt = str(cycle[ctrl._weather_rng.randi() % cycle.size()])
	var inten = 0.0 if Weather.normalize(nxt) == "clear" else ctrl._weather_rng.randf_range(0.55, 1.0)
	var dur2: Vector2 = Weather.duration_range()
	set_weather(nxt, inten, ctrl._weather_rng.randf_range(dur2.x, dur2.y))



func load_world_pack(pack_path: String, map_id: String = "", cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if not _load_pack(pack_path, map_id):
		return false
	if cell.x >= 0 and cell.y >= 0:
		ctrl.respawn_cell = cell
		ctrl.last_safe_cell = cell
		ctrl.set_player_cell(cell.x, cell.y)
	ctrl._collect_autorun()
	return true



func _load_pack(pack_path: String, map_id: String = "") -> bool:
	var pack = TilemapPack.load_pack(pack_path, map_id)
	if pack == null or pack.collision == null:
		push_error("MockServer: failed to load pack collision at %s" % pack_path)
		return false
	ctrl.map_collision = pack.collision
	ctrl._map_pack = pack
	if ctrl.map_collision != null and bool(ctrl.map_collision.get("streaming")):
		ctrl._ingest_stream_around(ctrl.respawn_cell if ctrl.respawn_cell.x >= 0 else Vector2i.ZERO)
	ctrl.map_tile_size = pack.tile_size
	ctrl.map_pack_path = pack_path.rstrip("/")
	ctrl.map_pack_id = str(pack.map_id) if str(pack.map_id) != "" else pack_path.get_file()
	ctrl.map_content_id = ""
	ctrl.map_content_version = ""
	var pack_meta: Dictionary = {}
	var pj = FileAccess.open("%s/pack.json" % ctrl.map_pack_path, FileAccess.READ)
	if pj != null:
		var parsed: Variant = JSON.parse_string(pj.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			pack_meta = parsed
	ctrl.map_content_id = str(pack_meta.get("content_id", "")).strip_edges()
	ctrl.map_content_version = str(pack_meta.get("version", "")).strip_edges()
	ctrl.map_warps = pack.warps.duplicate(true) if pack.warps != null else []
	ctrl.map_environment = MapExt.normalize_environment(pack.environment) if "environment" in pack else MapExt.ENV_OUTDOOR
	# Map events for this pack (keep session switches; reload defs only).
	if ctrl.event_runtime == null:
		ctrl.event_runtime = EventRuntime.new()
	ctrl.event_runtime.load_from_pack(pack)
	ctrl._reload_gather_for_map()
	ctrl._reload_fish_for_map()
	# Stale occupancy belongs to the previous pack; world re-applies after spawn.
	ctrl.player_cell = Vector2i(-9999, -9999)
	# Keep respawn_cell until set_player_cell / enter_world / transfer updates it.
	if ctrl.combat_stats != null:
		ctrl.combat_stats.clear_npcs()
	ctrl.npc_spawn_templates.clear()
	ctrl._npc_respawn_at.clear()
	ctrl._ground_bags.clear()
	ctrl._open_loot_bag_id = ""
	# Map-local shell stubs do not carry across packs.
	ctrl._remote_players.clear()
	# Escrow refund if a trade was open mid-warp.
	if ctrl.has_method("_trade_force_cancel_silent"):
		ctrl._trade_force_cancel_silent()
	if ctrl.has_method("_duel_force_clear_silent"):
		ctrl._duel_force_clear_silent()
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("clear_cast"):
		ctrl.combat_engine.clear_cast()
	ctrl.npc_meta.clear()
	ctrl._pending_tick_actions.clear()
	ctrl._combat_tick_acc = 0.0
	ctrl._ai_tick_acc = 0.0
	_reset_weather_for_map()
	return true



func _load_demo_map() -> void:
	_load_pack(DEMO_PACK_PATH)



func is_in_safe_zone(map_id: String, x: int, y: int) -> bool:
	if ctrl.safe_zone_catalog == null:
		return false
	return ctrl.safe_zone_catalog.is_in_safe_zone(map_id, x, y)



func player_in_safe_zone() -> bool:
	if ctrl.player_cell.x <= -9990:
		return false
	return is_in_safe_zone(ctrl.map_pack_id, ctrl.player_cell.x, ctrl.player_cell.y)



func snapshot_safe_zone() -> Dictionary:
	return {"inside": player_in_safe_zone()}



func _safe_zone_action(inside: bool) -> Dictionary:
	return {"type": "safe_zone", "inside": inside}



func _safe_zone_transition_actions(force: bool = false) -> Array:
	## Emit safe_zone action when inside flag changes (or force on enter_world).
	var inside = player_in_safe_zone()
	if not force and ctrl._safe_zone_known and inside == ctrl._safe_zone_inside:
		return []
	ctrl._safe_zone_known = true
	ctrl._safe_zone_inside = inside
	return [_safe_zone_action(inside)]



func _safe_zone_block_pvp_result() -> Dictionary:
	return {
		"ok": false,
		"reason": "safe_zone",
		"actions": [{"type": "system_message", "text": "安全区内无法决斗。"}],
	}



func _transfer_result_extras() -> Dictionary:
	# Shop buyback is session/map-local — wipe on transfer.
	ctrl._clear_shop_session_buyback()
	return {
		"ground_bags": [],
		"remote_players": ctrl.snapshot_remote_players(),
		"pet": ctrl.snapshot_pet(),
		"bags_cleared": true,
		"loot_close": true,
		"transfer_cleanup": "ground_bags_and_remotes",
	}



func try_transfer(from_x: int, from_y: int) -> Dictionary:
	var warp: Dictionary = {}
	for item in ctrl.map_warps:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var w: Dictionary = item
		var fc: Variant = w.get("from_cell", {})
		if typeof(fc) != TYPE_DICTIONARY:
			continue
		var fcd: Dictionary = fc
		if int(fcd.get("x", -1)) == from_x and int(fcd.get("y", -1)) == from_y:
			warp = w
			break
	if warp.is_empty():
		return {"ok": false}
	var to_pack: String = str(warp.get("to_pack", "")).strip_edges()
	var to_map_local: String = str(warp.get("to_map", warp.get("to_map_id", ""))).strip_edges()
	if to_pack.is_empty():
		to_pack = ctrl.map_pack_path
	if to_pack.is_empty():
		return {"ok": false}
	var dungeon_was_active: bool = (not ctrl._dungeon_xfer_lock) and (ctrl.in_dungeon() or not ctrl._dungeon.is_empty())
	var to_cell_v: Variant = warp.get("to_cell", {})
	if typeof(to_cell_v) != TYPE_DICTIONARY:
		return {"ok": false}
	var to_cell: Dictionary = to_cell_v
	var tx: int = int(to_cell.get("x", 0))
	var ty: int = int(to_cell.get("y", 0))
	var facing: int = int(warp.get("facing", 2))
	var message: String = str(warp.get("message", ""))
	var to_map_id: String = to_map_local
	if not _load_pack(to_pack, to_map_id):
		# Reload previous pack if destination failed.
		_load_pack(ctrl.map_pack_path if ctrl.map_pack_path != "" else DEMO_PACK_PATH)
		return {"ok": false}
	if to_map_id.is_empty():
		to_map_id = ctrl.map_pack_id
	# Prefer landable cell near destination if blocked.
	if ctrl.map_collision != null and ctrl.map_collision.has_method("is_landable"):
		if not ctrl.map_collision.is_landable(tx, ty) and ctrl.map_collision.has_method("find_spawn_near"):
			var near: Vector2i = ctrl.map_collision.find_spawn_near(tx, ty)
			tx = near.x
			ty = near.y
	# Keep server occupancy in sync with the destination immediately.
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
		"facing": facing,
		"message": message,
		"quests": ctrl.quest_journal.snapshot() if ctrl.quest_journal != null else [],
	}
	out.merge(_transfer_result_extras())
	var actions: Array = []
	actions.append({"type": "loot_close"})
	actions.append({"type": "system_message", "text": "已切换地图：上一张图的地面掉落不会带入。"})
	if not reach_actions.is_empty():
		actions.append_array(reach_actions)
	if bool(ctrl._pet.get("active", false)):
		ctrl._pet_snap_near_player()
		actions.append(ctrl._pet_spawn_action())
	actions.append_array(ctrl._shell_remote_spawn_actions())
	actions.append_array(_safe_zone_transition_actions(true))
	if dungeon_was_active:
		actions.append_array(ctrl._dungeon_abandon_on_leave())
	out["actions"] = actions
	out["dungeon"] = ctrl.snapshot_dungeon()
	return out



func _town_dest() -> Vector2i:
	var dest: Vector2i = ctrl.respawn_cell
	if dest.x <= -9990:
		dest = ctrl.last_safe_cell
	if ctrl.map_collision != null and ctrl.map_collision.has_method("is_landable"):
		if not ctrl.map_collision.is_landable(dest.x, dest.y) and ctrl.map_collision.has_method("find_spawn_near"):
			dest = ctrl.map_collision.find_spawn_near(dest.x, dest.y)
	elif ctrl.map_collision != null and ctrl.map_collision.has_method("find_spawn_near") and dest.x <= -9990:
		dest = ctrl.map_collision.find_spawn_near()
	return dest



func snapshot_map_pins() -> Dictionary:
	var pins: Array = []
	for p in ctrl._map_pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		pins.append((p as Dictionary).duplicate(true))
	return {"pins": pins, "count": pins.size(), "max": MAP_PIN_MAX}



func list_map_pins_for_map(map_id: String = "") -> Array:
	map_id = str(map_id).strip_edges()
	if map_id.is_empty():
		map_id = str(ctrl.map_pack_id).strip_edges()
	var out: Array = []
	for p in ctrl._map_pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var mid = str(p.get("map_id", "")).strip_edges()
		if mid != "" and map_id != "" and mid != map_id:
			continue
		out.append((p as Dictionary).duplicate(true))
	return out



func _map_pins_update_action() -> Dictionary:
	return {"type": "map_pins_update", "map_pins": snapshot_map_pins()}



func _map_pin_slot_free() -> int:
	var used: Dictionary = {}
	for p in ctrl._map_pins:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		used[int(p.get("slot", 0))] = true
	for s in range(1, MAP_PIN_MAX + 1):
		if not used.has(s):
			return s
	return 0



func _find_map_pin_index(x: int, y: int, map_id: String) -> int:
	map_id = str(map_id).strip_edges()
	for i in range(ctrl._map_pins.size()):
		var p: Variant = ctrl._map_pins[i]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var cell_v: Variant = p.get("cell", {})
		var cx = 0
		var cy = 0
		if typeof(cell_v) == TYPE_VECTOR2I:
			cx = cell_v.x
			cy = cell_v.y
		elif typeof(cell_v) == TYPE_DICTIONARY:
			cx = int(cell_v.get("x", 0))
			cy = int(cell_v.get("y", 0))
		else:
			continue
		if cx != x or cy != y:
			continue
		var mid = str(p.get("map_id", "")).strip_edges()
		if map_id != "" and mid != "" and mid != map_id:
			continue
		return i
	return -1



func try_map_pin_toggle(x: int, y: int, map_id: String = "", short_name: String = "") -> Dictionary:
	var actions: Array = []
	map_id = str(map_id).strip_edges()
	if map_id.is_empty():
		map_id = str(ctrl.map_pack_id).strip_edges()
	short_name = str(short_name).strip_edges()
	var idx = _find_map_pin_index(x, y, map_id)
	if idx >= 0:
		var old: Dictionary = ctrl._map_pins[idx]
		var old_name = str(old.get("name", "标记")).strip_edges()
		ctrl._map_pins.remove_at(idx)
		actions.append(_map_pins_update_action())
		actions.append({"type": "system_message", "text": "已清除标记：%s" % (old_name if old_name != "" else "标记")})
		return {"ok": true, "cleared": true, "actions": actions, "map_pins": snapshot_map_pins()}
	if ctrl._map_pins.size() >= MAP_PIN_MAX:
		actions.append({"type": "system_message", "text": "个人标记已满（最多 %d 个）。" % MAP_PIN_MAX})
		return {"ok": false, "reason": "full", "actions": actions, "map_pins": snapshot_map_pins()}
	var slot = _map_pin_slot_free()
	if slot <= 0:
		actions.append({"type": "system_message", "text": "个人标记已满（最多 %d 个）。" % MAP_PIN_MAX})
		return {"ok": false, "reason": "full", "actions": actions, "map_pins": snapshot_map_pins()}
	var nm = short_name if short_name != "" else "标记%d" % slot
	var pin = {
		"id": "pin_%d" % slot,
		"slot": slot,
		"name": nm,
		"map_id": map_id,
		"cell": {"x": x, "y": y},
	}
	ctrl._map_pins.append(pin)
	actions.append(_map_pins_update_action())
	actions.append({"type": "system_message", "text": "标记：%s (%d, %d)" % [nm, x, y]})
	return {"ok": true, "cleared": false, "pin": pin.duplicate(true), "actions": actions, "map_pins": snapshot_map_pins()}



func try_map_pin_clear() -> Dictionary:
	var actions: Array = []
	if ctrl._map_pins.is_empty():
		actions.append({"type": "system_message", "text": "当前没有个人标记。"})
		return {"ok": true, "cleared": 0, "actions": actions, "map_pins": snapshot_map_pins()}
	var n: int = ctrl._map_pins.size()
	ctrl._map_pins.clear()
	actions.append(_map_pins_update_action())
	actions.append({"type": "system_message", "text": "已清除全部标记（%d）" % n})
	return {"ok": true, "cleared": n, "actions": actions, "map_pins": snapshot_map_pins()}


