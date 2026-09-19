extends RefCounted
## Domain module: professions (craft recipes, gather nodes, fishing spots, skill XP).

var ctrl
func _init(c):
	ctrl = c

const WeatherGatherUtil = preload("res://scripts/game/weather_gather_util.gd")
const RngUtil = preload("res://scripts/util/rng_util.gd")

func _craft_xp_needed_for(level: int) -> int:
	level = maxi(int(level), 1)
	return 20 + level * 10



func _reset_craft_skill() -> void:
	ctrl.craft_level = 1
	ctrl.craft_xp = 0
	ctrl.craft_xp_to_next = _craft_xp_needed_for(ctrl.craft_level)



func snapshot_craft() -> Dictionary:
	return {
		"craft_level": ctrl.craft_level,
		"craft_xp": ctrl.craft_xp,
		"craft_xp_to_next": ctrl.craft_xp_to_next,
	}



func snapshot_recipes() -> Array:
	if ctrl.recipe_catalog == null:
		return []
	return ctrl.recipe_catalog.list_all()



func try_craft(recipe_id: String, qty: int = 1) -> Dictionary:
	var actions: Array = []
	recipe_id = str(recipe_id).strip_edges()
	qty = int(qty)
	if recipe_id.is_empty() or qty <= 0:
		actions.append({"type": "system_message", "text": "无效的制作请求。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	if ctrl.inventory == null or ctrl.recipe_catalog == null:
		actions.append({"type": "system_message", "text": "制作不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	var recipe: Dictionary = ctrl.recipe_catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		actions.append({"type": "system_message", "text": "未知配方。"})
		return {"ok": false, "reason": "unknown_recipe", "actions": actions}
	# Prefer recipe craft_level; fall back to learn_level mapped as craft req (not combat level).
	var need_craft: int = 1
	if recipe.has("craft_level"):
		need_craft = maxi(int(recipe.get("craft_level", 1)), 1)
	else:
		need_craft = maxi(int(recipe.get("learn_level", 1)), 1)
	if ctrl.craft_level < need_craft:
		actions.append({"type": "system_message", "text": "制作等级不足（需要 %d）。" % need_craft})
		return {"ok": false, "reason": "craft_level", "actions": actions}
	var ings_v: Variant = recipe.get("ingredients", [])
	if typeof(ings_v) != TYPE_ARRAY or (ings_v as Array).is_empty():
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var scaled: Array = []
	for row in ings_v:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid = str(row.get("id", "")).strip_edges()
		var need: int = maxi(int(row.get("qty", 0)), 0) * qty
		if iid.is_empty() or need <= 0:
			continue
		scaled.append({"id": iid, "qty": need})
	if scaled.is_empty():
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	for row2 in scaled:
		var iid2 = str(row2.get("id", ""))
		var need2: int = int(row2.get("qty", 0))
		if not ctrl.inventory.has_item(iid2, need2):
			actions.append({"type": "system_message", "text": "材料不足"})
			return {"ok": false, "reason": "missing_mats", "actions": actions}
	var gold_cost: int = maxi(int(recipe.get("gold_cost", 0)), 0) * qty
	if gold_cost > 0 and ctrl.inventory.get_gold() < gold_cost:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var out_v: Variant = recipe.get("output", {})
	if typeof(out_v) != TYPE_DICTIONARY:
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	var out_id = str(out_v.get("id", "")).strip_edges()
	var out_qty: int = maxi(int(out_v.get("qty", 1)), 1) * qty
	if out_id.is_empty() or out_qty <= 0:
		actions.append({"type": "system_message", "text": "配方无效。"})
		return {"ok": false, "reason": "invalid", "actions": actions}
	# All-or-nothing: consume ingredients (+ gold), grant output; rollback on bag failure.
	for row3 in scaled:
		if not ctrl.inventory.consume(str(row3.get("id", "")), int(row3.get("qty", 0))):
			# Should not happen after has_item; restore any partial consume.
			for row4 in scaled:
				var done_id = str(row4.get("id", ""))
				if done_id == str(row3.get("id", "")):
					break
				ctrl.inventory.add_item(done_id, int(row4.get("qty", 0)))
			actions.append({"type": "system_message", "text": "材料不足"})
			return {"ok": false, "reason": "missing_mats", "actions": actions}
	if gold_cost > 0 and not ctrl.inventory.try_spend_gold(gold_cost):
		for row5 in scaled:
			ctrl.inventory.add_item(str(row5.get("id", "")), int(row5.get("qty", 0)))
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(out_id, out_qty)
	var added: int = int(add_r.get("added", 0))
	if added < out_qty:
		if added > 0:
			ctrl.inventory.consume(out_id, added)
		for row6 in scaled:
			ctrl.inventory.add_item(str(row6.get("id", "")), int(row6.get("qty", 0)))
		if gold_cost > 0:
			ctrl.inventory.add_gold(gold_cost)
		var reason = str(add_r.get("reason", "bag_full"))
		var msg = "背包已满"
		if reason == "stack_full":
			msg = "背包已满"
		actions.append({"type": "system_message", "text": msg})
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var oname = ctrl.item_display_name(out_id)
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "制作成功：【%s】×%d" % [oname, out_qty]})
	actions.append_array(ctrl._note_title_counter("crafts", 1))
	# Craft profession XP (5 per crafted unit qty).
	var gained_xp: int = 5 * qty
	ctrl.craft_xp += gained_xp
	while ctrl.craft_xp >= ctrl.craft_xp_to_next and ctrl.craft_xp_to_next > 0:
		ctrl.craft_xp -= ctrl.craft_xp_to_next
		ctrl.craft_level += 1
		ctrl.craft_xp_to_next = _craft_xp_needed_for(ctrl.craft_level)
		actions.append({"type": "system_message", "text": "制作等级提升至 %d！" % ctrl.craft_level})
	actions.append({
		"type": "craft_update",
		"craft_level": ctrl.craft_level,
		"craft_xp": ctrl.craft_xp,
		"craft_xp_to_next": ctrl.craft_xp_to_next,
	})
	return {"ok": true, "actions": actions}





func _gather_xp_needed_for(level: int) -> int:
	level = maxi(int(level), 1)
	return 20 + level * 10



func _reset_gather_skill() -> void:
	ctrl.gather_level = 1
	ctrl.gather_xp = 0
	ctrl.gather_xp_to_next = _gather_xp_needed_for(ctrl.gather_level)



func snapshot_gather() -> Dictionary:
	return {
		"gather_level": ctrl.gather_level,
		"gather_xp": ctrl.gather_xp,
		"gather_xp_to_next": ctrl.gather_xp_to_next,
	}



func _gather_skill_update_action() -> Dictionary:
	return {
		"type": "gather_update",
		"gather_level": ctrl.gather_level,
		"gather_xp": ctrl.gather_xp,
		"gather_xp_to_next": ctrl.gather_xp_to_next,
	}



func _apply_gather_skill_xp(actions: Array, gained_xp: int = 5) -> void:
	gained_xp = maxi(int(gained_xp), 0)
	if gained_xp <= 0:
		return
	ctrl.gather_xp += gained_xp
	while ctrl.gather_xp >= ctrl.gather_xp_to_next and ctrl.gather_xp_to_next > 0:
		ctrl.gather_xp -= ctrl.gather_xp_to_next
		ctrl.gather_level += 1
		ctrl.gather_xp_to_next = _gather_xp_needed_for(ctrl.gather_level)
		actions.append({"type": "system_message", "text": "采集等级提升至 %d！" % ctrl.gather_level})
	actions.append(_gather_skill_update_action())



func _gather_level_required(def: Dictionary) -> int:
	return maxi(int(def.get("gather_level", 1)), 1)



func _fail_gather_level(actions: Array, need: int) -> Dictionary:
	actions.append({"type": "system_message", "text": "采集等级不足（需要 %d）。" % need})
	return {"ok": false, "reason": "gather_level", "actions": actions}



func _reload_gather_for_map() -> void:
	ctrl._gather_nodes.clear()
	ctrl._gather_state.clear()
	if ctrl.gather_catalog == null:
		return
	var mid = str(ctrl.map_pack_id).strip_edges()
	if mid.is_empty():
		mid = ctrl.map_pack_path.get_file()
	for def_v in ctrl.gather_catalog.nodes_for_map(mid):
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = def_v
		var nid = str(d.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		ctrl._gather_nodes[nid] = d
		ctrl._gather_state[nid] = {"depleted": false, "ready_at": 0.0}



func _gather_now() -> float:
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("now_sec"):
		return float(ctrl.combat_stats.now_sec())
	return float(Time.get_ticks_msec()) / 1000.0



func _gather_update_action(node_id: String, depleted: bool, display_name: String = "") -> Dictionary:
	return {
		"type": "gather_update",
		"node_id": node_id,
		"depleted": depleted,
		"name": display_name,
	}



func _gather_set_cell_blocked(node_id: String, blocked: bool) -> void:
	if ctrl.map_collision == null or not ctrl.map_collision.has_method("set_extra_blocked"):
		return
	var def: Dictionary = ctrl._gather_nodes.get(node_id, {})
	if def.is_empty():
		return
	var cell_v: Variant = def.get("cell", {})
	if typeof(cell_v) != TYPE_DICTIONARY:
		return
	ctrl.map_collision.set_extra_blocked(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)), blocked)



func _gather_in_range(node_id: String, player_x: int, player_y: int) -> bool:
	## Chebyshev ≤ 1 against gather cell (or registered NPC cell).
	var def: Dictionary = ctrl._gather_nodes.get(node_id, {})
	var cx = -99999
	var cy = -99999
	if not def.is_empty():
		var cell_v: Variant = def.get("cell", {})
		if typeof(cell_v) == TYPE_DICTIONARY:
			cx = int(cell_v.get("x", -99999))
			cy = int(cell_v.get("y", -99999))
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("get_npc_cell"):
		var nc: Vector2i = ctrl.combat_stats.get_npc_cell(node_id)
		if nc.x > -9990:
			cx = nc.x
			cy = nc.y
	if cx <= -99990:
		return false
	return maxi(absi(cx - player_x), absi(cy - player_y)) <= 1



func try_gather(node_id: String) -> Dictionary:
	var actions: Array = []
	node_id = str(node_id).strip_edges()
	if node_id.is_empty() or not ctrl._gather_nodes.has(node_id):
		actions.append({"type": "system_message", "text": "这里没有可采集的资源。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		return {"ok": false, "reason": "dead", "actions": []}
	var px: int = ctrl.player_cell.x
	var py: int = ctrl.player_cell.y
	if px <= -9990:
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	if not _gather_in_range(node_id, px, py):
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var def: Dictionary = ctrl._gather_nodes[node_id]
	var st: Dictionary = ctrl._gather_state.get(node_id, {"depleted": false, "ready_at": 0.0})
	if bool(st.get("depleted", false)):
		actions.append({"type": "system_message", "text": "资源尚未恢复"})
		actions.append(_gather_update_action(node_id, true, str(def.get("name", node_id))))
		return {"ok": false, "reason": "depleted", "actions": actions}
	var need_gather: int = _gather_level_required(def)
	if ctrl.gather_level < need_gather:
		return _fail_gather_level(actions, need_gather)
	# Optional tool gate (durable tools wear on success; broken/missing fail).
	var tool_id = str(def.get("tool", "")).strip_edges()
	if tool_id != "":
		var usable = false
		if ctrl.inventory != null:
			if ctrl.inventory.has_method("has_usable_tool"):
				usable = bool(ctrl.inventory.has_usable_tool(tool_id, 1))
			else:
				usable = bool(ctrl.inventory.has_item(tool_id, 1))
		if not usable:
			var tname = ctrl.item_display_name(tool_id)
			actions.append({"type": "system_message", "text": "需要工具：%s" % tname})
			return {"ok": false, "reason": "need_tool", "actions": actions}
	if ctrl.inventory == null or ctrl.gather_catalog == null:
		actions.append({"type": "system_message", "text": "采集不可用。"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	var yrow: Dictionary = ctrl.gather_catalog.pick_yield(def)
	var iid = str(yrow.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(yrow.get("qty", 1)), 1)
	var weather_bonus = false
	if WeatherGatherUtil.is_herb_node(node_id, def) and WeatherGatherUtil.is_bonus_weather(ctrl.weather_kind):
		var roll = randf()
		if ctrl.weather_gather_randf.is_valid():
			roll = float(ctrl.weather_gather_randf.call())
		if WeatherGatherUtil.roll_gather_qty_bonus(roll):
			qty = WeatherGatherUtil.apply_gather_qty_bonus(qty, true)
			weather_bonus = true
	if iid.is_empty():
		actions.append({"type": "system_message", "text": "这里什么也没有。"})
		return {"ok": false, "reason": "empty_yield", "actions": actions}
	# Bag space check (all-or-nothing).
	if ctrl.inventory.has_method("can_accept") and not ctrl.inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			ctrl.inventory.consume(iid, added)
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	# Gathering is an active action — cancel stealth / mount.
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("break_stealth"):
		ctrl.combat_engine.break_stealth(actions)
	elif ctrl.combat_stats != null and ctrl.combat_stats.statuses != null and ctrl.combat_stats.statuses.has_status("player", "stealth"):
		ctrl.combat_stats.statuses.clear_status("player", "stealth")
		actions.append(ctrl.combat_stats.statuses.status_update_action("player"))
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("break_mount"):
		ctrl.combat_engine.break_mount(actions)
	elif ctrl.combat_stats != null and ctrl.combat_stats.statuses != null and ctrl.combat_stats.statuses.has_status("player", "mounted"):
		ctrl.combat_stats.statuses.clear_status("player", "mounted")
		actions.append(ctrl.combat_stats.statuses.status_update_action("player"))
		actions.append({"type": "system_message", "text": "已下马。"})
	# Deplete + schedule respawn.
	var respawn_sec: float = maxf(float(def.get("respawn_sec", 30.0)), 0.0)
	var ready_at: float = _gather_now() + respawn_sec
	ctrl._gather_state[node_id] = {"depleted": true, "ready_at": ready_at}
	_gather_set_cell_blocked(node_id, false)
	var iname = ctrl.item_display_name(iid)
	var dname = str(def.get("name", node_id))
	var tool_broke = false
	if tool_id != "" and ctrl.inventory != null and ctrl.inventory.has_method("wear_tool"):
		var wr: Dictionary = ctrl.inventory.wear_tool(tool_id, 1)
		if bool(wr.get("ok", false)) and bool(wr.get("broken", false)):
			tool_broke = true
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "采集获得：%s×%d" % [iname, qty]})
	if weather_bonus:
		actions.append({"type": "system_message", "text": WeatherGatherUtil.BONUS_MESSAGE})
	if tool_broke:
		actions.append({"type": "system_message", "text": "工具已损坏。"})
	actions.append(_gather_update_action(node_id, true, dname))
	actions.append_array(ctrl._quest_note_item_actions(iid, qty))
	_apply_gather_skill_xp(actions, 5)
	actions.append_array(ctrl._note_achievement_counter("gathers", 1))
	return {
		"ok": true,
		"actions": actions,
		"item_id": iid,
		"qty": qty,
		"node_id": node_id,
		"weather_bonus": weather_bonus,
		"tool_broke": tool_broke,
	}



func _tick_gather_respawns() -> Array:
	var actions: Array = []
	if ctrl._gather_state.is_empty():
		return actions
	var now: float = _gather_now()
	for nid_v in ctrl._gather_state.keys():
		var nid: String = str(nid_v)
		var st: Dictionary = ctrl._gather_state[nid]
		if not bool(st.get("depleted", false)):
			continue
		if now < float(st.get("ready_at", 0.0)):
			continue
		ctrl._gather_state[nid] = {"depleted": false, "ready_at": 0.0}
		_gather_set_cell_blocked(nid, true)
		var def: Dictionary = ctrl._gather_nodes.get(nid, {})
		var dname = str(def.get("name", nid))
		actions.append(_gather_update_action(nid, false, dname))
	return actions



func force_gather_respawn(node_id: String = "") -> Array:
	var actions: Array = []
	node_id = str(node_id).strip_edges()
	var ids: Array = [node_id] if node_id != "" else ctrl._gather_state.keys()
	for nid_v in ids:
		var nid: String = str(nid_v)
		if not ctrl._gather_state.has(nid):
			continue
		var st: Dictionary = ctrl._gather_state[nid]
		if not bool(st.get("depleted", false)):
			continue
		ctrl._gather_state[nid] = {"depleted": false, "ready_at": 0.0}
		_gather_set_cell_blocked(nid, true)
		var def: Dictionary = ctrl._gather_nodes.get(nid, {})
		actions.append(_gather_update_action(nid, false, str(def.get("name", nid))))
	return actions



func is_gather_depleted(node_id: String) -> bool:
	node_id = str(node_id).strip_edges()
	if not ctrl._gather_state.has(node_id):
		return false
	return bool((ctrl._gather_state[node_id] as Dictionary).get("depleted", false))



func _reload_fish_for_map() -> void:
	ctrl._fish_spots.clear()
	ctrl._fish_state.clear()
	ctrl._fish_busy_until = 0.0
	if ctrl.fish_catalog == null:
		return
	var mid = str(ctrl.map_pack_id).strip_edges()
	if mid.is_empty():
		mid = ctrl.map_pack_path.get_file()
	for def_v in ctrl.fish_catalog.spots_for_map(mid):
		if typeof(def_v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = def_v
		var sid = str(d.get("id", "")).strip_edges()
		if sid.is_empty():
			continue
		ctrl._fish_spots[sid] = d
		ctrl._fish_state[sid] = {"depleted": false, "ready_at": 0.0}



func _fish_now() -> float:
	return _gather_now()



func _fish_update_action(spot_id: String, depleted: bool, display_name: String = "") -> Dictionary:
	return {
		"type": "fish_update",
		"spot_id": spot_id,
		"depleted": depleted,
		"name": display_name,
	}



func _fish_in_range(spot_id: String, player_x: int, player_y: int) -> bool:
	## Chebyshev ≤ 1 against fish spot cell (or registered NPC cell).
	var def: Dictionary = ctrl._fish_spots.get(spot_id, {})
	var cx = -99999
	var cy = -99999
	if not def.is_empty():
		var cell_v: Variant = def.get("cell", {})
		if typeof(cell_v) == TYPE_DICTIONARY:
			cx = int(cell_v.get("x", -99999))
			cy = int(cell_v.get("y", -99999))
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("get_npc_cell"):
		var nc: Vector2i = ctrl.combat_stats.get_npc_cell(spot_id)
		if nc.x > -9990:
			cx = nc.x
			cy = nc.y
	if cx <= -99990:
		return false
	return maxi(absi(cx - player_x), absi(cy - player_y)) <= 1




func _best_fish_bait() -> String:
	if ctrl.inventory == null:
		return ""
	if ctrl.inventory.has_item("bait_shiny", 1):
		return "bait_shiny"
	if ctrl.inventory.has_item("bait_worm", 1):
		return "bait_worm"
	return ""



func _pick_fish_yield(spot_def: Dictionary, bait_id: String = "") -> Dictionary:
	if ctrl.fish_catalog == null:
		return {}
	bait_id = str(bait_id).strip_edges()
	var bonus = 0.0
	if bait_id == "bait_shiny":
		bonus = 0.35
	elif bait_id == "bait_worm":
		bonus = 0.15
	var weather_shiny: float = WeatherGatherUtil.fish_shiny_bonus_for_weather(ctrl.weather_kind)
	if bonus <= 0.0 and weather_shiny <= 0.0:
		return ctrl.fish_catalog.pick_yield(spot_def)
	var yv: Variant = spot_def.get("yields", [])
	if typeof(yv) != TYPE_ARRAY or (yv as Array).is_empty():
		return {}
	var rows: Array = []
	for row in yv:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var iid = str(row.get("item_id", "")).strip_edges()
		var qty: int = maxi(int(row.get("qty", 1)), 1)
		var w: float = maxf(float(row.get("weight", 1.0)), 0.0)
		if iid == "fish_shiny":
			w = WeatherGatherUtil.shiny_weight(w, ctrl.weather_kind, bonus)
		if iid.is_empty() or w <= 0.0:
			continue
		rows.append({"item_id": iid, "qty": qty, "weight": w})
	if rows.is_empty():
		return ctrl.fish_catalog.pick_yield(spot_def)
	var picked: Dictionary = RngUtil.weighted_pick(rows)
	if picked.is_empty():
		return ctrl.fish_catalog.pick_yield(spot_def)
	return {"item_id": str(picked.get("item_id", "")), "qty": maxi(int(picked.get("qty", 1)), 1)}



func try_fish(spot_id: String) -> Dictionary:
	var actions: Array = []
	spot_id = str(spot_id).strip_edges()
	if spot_id.is_empty() or not ctrl._fish_spots.has(spot_id):
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		return {"ok": false, "reason": "dead", "actions": []}
	var now: float = _fish_now()
	if now < ctrl._fish_busy_until:
		actions.append({"type": "system_message", "text": "还在甩杆…"})
		return {"ok": false, "reason": "busy", "actions": actions}
	var px: int = ctrl.player_cell.x
	var py: int = ctrl.player_cell.y
	if px <= -9990:
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	if not _fish_in_range(spot_id, px, py):
		actions.append({"type": "system_message", "text": "距离太远，无法互动。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var def: Dictionary = ctrl._fish_spots[spot_id]
	var st: Dictionary = ctrl._fish_state.get(spot_id, {"depleted": false, "ready_at": 0.0})
	if bool(st.get("depleted", false)):
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		actions.append(_fish_update_action(spot_id, true, str(def.get("name", spot_id))))
		return {"ok": false, "reason": "depleted", "actions": actions}
	var need_gather: int = _gather_level_required(def)
	if ctrl.gather_level < need_gather:
		return _fail_gather_level(actions, need_gather)
	if ctrl.inventory == null or ctrl.fish_catalog == null:
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		return {"ok": false, "reason": "no_store", "actions": actions}
	# Optional tool gate (same durability rules as gather).
	var fish_tool_id = str(def.get("tool", "")).strip_edges()
	if fish_tool_id != "":
		var fish_usable = false
		if ctrl.inventory.has_method("has_usable_tool"):
			fish_usable = bool(ctrl.inventory.has_usable_tool(fish_tool_id, 1))
		else:
			fish_usable = bool(ctrl.inventory.has_item(fish_tool_id, 1))
		if not fish_usable:
			var ftname = ctrl.item_display_name(fish_tool_id)
			actions.append({"type": "system_message", "text": "需要工具：%s" % ftname})
			return {"ok": false, "reason": "need_tool", "actions": actions}
	# Optional bait: best available (shiny > worm). Consumed only on success.
	var bait_id = _best_fish_bait()
	var yrow: Dictionary = _pick_fish_yield(def, bait_id)
	var iid = str(yrow.get("item_id", "")).strip_edges()
	var qty: int = maxi(int(yrow.get("qty", 1)), 1)
	if iid.is_empty():
		actions.append({"type": "system_message", "text": "这里没有鱼"})
		return {"ok": false, "reason": "empty_yield", "actions": actions}
	if ctrl.inventory.has_method("can_accept") and not ctrl.inventory.can_accept(iid, qty):
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	var add_r: Dictionary = ctrl.inventory.try_add_item(iid, qty)
	var added: int = int(add_r.get("added", 0))
	if added < qty:
		if added > 0:
			ctrl.inventory.consume(iid, added)
		actions.append({"type": "system_message", "text": "背包已满"})
		return {"ok": false, "reason": "bag_full", "actions": actions}
	# Consume 1 bait on successful catch (after bag accept).
	var bait_used = ""
	if bait_id != "" and ctrl.inventory.has_item(bait_id, 1) and ctrl.inventory.consume(bait_id, 1):
		bait_used = bait_id
	# Cast busy lock (optional short lock after a successful cast).
	var cast_sec: float = maxf(float(def.get("cast_sec", 0.0)), 0.0)
	ctrl._fish_busy_until = now + cast_sec
	# Deplete + schedule respawn (same shell as gather).
	var respawn_sec: float = maxf(float(def.get("respawn_sec", 20.0)), 0.0)
	var ready_at: float = now + respawn_sec
	ctrl._fish_state[spot_id] = {"depleted": true, "ready_at": ready_at}
	var iname = ctrl.item_display_name(iid)
	var dname = str(def.get("name", spot_id))
	var fish_tool_broke = false
	if fish_tool_id != "" and ctrl.inventory.has_method("wear_tool"):
		var fwr: Dictionary = ctrl.inventory.wear_tool(fish_tool_id, 1)
		if bool(fwr.get("ok", false)) and bool(fwr.get("broken", false)):
			fish_tool_broke = true
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	var catch_msg = "钓到了：%s×%d" % [iname, qty]
	if bait_used != "":
		catch_msg += "（使用了%s。）" % ctrl.item_display_name(bait_used)
	actions.append({"type": "system_message", "text": catch_msg})
	if fish_tool_broke:
		actions.append({"type": "system_message", "text": "工具已损坏。"})
	actions.append(_fish_update_action(spot_id, true, dname))
	actions.append_array(ctrl._quest_note_item_actions(iid, qty))
	actions.append_array(ctrl._quest_note_fish_actions(iid, qty))
	_apply_gather_skill_xp(actions, 5)
	return {
		"ok": true,
		"actions": actions,
		"item_id": iid,
		"qty": qty,
		"spot_id": spot_id,
		"bait_id": bait_used,
		"tool_broke": fish_tool_broke,
	}



func _tick_fish_respawns() -> Array:
	var actions: Array = []
	if ctrl._fish_state.is_empty():
		return actions
	var now: float = _fish_now()
	for sid_v in ctrl._fish_state.keys():
		var sid: String = str(sid_v)
		var st: Dictionary = ctrl._fish_state[sid]
		if not bool(st.get("depleted", false)):
			continue
		if now < float(st.get("ready_at", 0.0)):
			continue
		ctrl._fish_state[sid] = {"depleted": false, "ready_at": 0.0}
		var def: Dictionary = ctrl._fish_spots.get(sid, {})
		var dname = str(def.get("name", sid))
		actions.append(_fish_update_action(sid, false, dname))
	return actions



func force_fish_respawn(spot_id: String = "") -> Array:
	var actions: Array = []
	spot_id = str(spot_id).strip_edges()
	var ids: Array = [spot_id] if spot_id != "" else ctrl._fish_state.keys()
	for sid_v in ids:
		var sid: String = str(sid_v)
		if not ctrl._fish_state.has(sid):
			continue
		var st: Dictionary = ctrl._fish_state[sid]
		if not bool(st.get("depleted", false)):
			continue
		ctrl._fish_state[sid] = {"depleted": false, "ready_at": 0.0}
		var def: Dictionary = ctrl._fish_spots.get(sid, {})
		actions.append(_fish_update_action(sid, false, str(def.get("name", sid))))
	ctrl._fish_busy_until = 0.0
	return actions



func is_fish_depleted(spot_id: String) -> bool:
	spot_id = str(spot_id).strip_edges()
	if not ctrl._fish_state.has(spot_id):
		return false
	return bool((ctrl._fish_state[spot_id] as Dictionary).get("depleted", false))


