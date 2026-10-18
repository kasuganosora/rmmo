extends RefCounted
## Mock server domain: interaction.

var ctrl

## Last NPC that opened non-event dialogue (for quest_* choice routing).
## @server-state
var _dialogue_npc_id: String = ""


func _init(owner):
	ctrl = owner

## @server-api
func try_interact(npc_id: String, player_x: int, player_y: int) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return {"ok": false, "actions": []}
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		return {"ok": false, "actions": []}
	# Prefer authoritative occupancy over client-reported coords.
	if ctrl.player_cell.x > -9990:
		player_x = ctrl.player_cell.x
		player_y = ctrl.player_cell.y
	if not ctrl._require_npc_adjacent(npc_id, player_x, player_y, 1):
		return {"ok": false, "actions": [{"type": "system_message", "text": "距离太远，无法互动。"}]}
	# Gather nodes (herb/ore): prefer try_gather over dialogue/events.
	if ctrl._gather_nodes.has(npc_id):
		return ctrl.try_gather(npc_id)
	# Fishing spots: prefer try_fish over dialogue/events.
	if ctrl._fish_spots.has(npc_id):
		return ctrl.try_fish(npc_id)
	var actions: Array = []
	var meta: Dictionary = ctrl.npc_meta.get(npc_id, {}) if typeof(ctrl.npc_meta.get(npc_id, {})) == TYPE_DICTIONARY else {}
	# MV event by npc/event id (or cell under the NPC).
	if ctrl.event_runtime != null:
		var ev: Dictionary = ctrl.event_runtime.get_event(npc_id)
		if ev.is_empty() and ctrl.combat_stats != null and ctrl.combat_stats.has_method("get_npc_cell"):
			var nc: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id)
			if nc.x > -9990:
				ev = ctrl.event_runtime.get_event_at_cell(nc.x, nc.y)
		if not ev.is_empty():
			var ctx: Dictionary = ctrl._event_server_ctx(str(meta.get("name", ev.get("name", npc_id))))
			var page: Dictionary = ctrl.event_runtime.select_page_with_ctx(ev, ctx)
			var trig := str(ev.get("trigger", "action"))
			if ctrl.event_runtime.has_method("page_trigger"):
				trig = str(ctrl.event_runtime.page_trigger(ev, page))
			if trig == "action":
				actions = ctrl.event_runtime.run_event(str(ev.get("id", npc_id)), ctx)
			if not actions.is_empty():
				actions.append_array(ctrl._quest_note_talk_actions(npc_id))
				return {"ok": true, "actions": actions}
			# Empty page (e.g. spent touch-style) — fall through to shop/text.
	var shop_id := str(meta.get("shop_id", "")).strip_edges()
	var quest_opts: Array = ctrl._build_quest_dialogue_options(npc_id)
	# Vendor: if quest accept/turn-in options exist, show dialogue (shop as option); else open shop.
	if shop_id != "" and ctrl.shop_catalog != null and ctrl.shop_catalog.has_shop(shop_id):
		if not quest_opts.is_empty():
			var npc_name_v := str(meta.get("name", npc_id))
			var body_v := str(meta.get("interact_text", "")).strip_edges()
			if body_v.is_empty():
				body_v = "有什么需要的吗？"
			body_v = ctrl._append_quest_offer_blurb(body_v, npc_id)
			var opts_v: Array = quest_opts.duplicate()
			opts_v.append({"id": "shop_open:%s" % shop_id, "label": "看看商品"})
			ctrl._dialogue_npc_id = npc_id
			actions.append({
				"type": "show_npc_dialogue",
				"npc_id": npc_id,
				"npc_name": npc_name_v if npc_name_v != "" else npc_id,
				"body": body_v,
				"options": opts_v,
			})
			actions.append_array(ctrl._quest_note_talk_actions(npc_id))
			return {"ok": true, "actions": actions}
		actions.append(ctrl._build_open_shop_payload(shop_id))
		# Talking to vendor still counts as talk progress.
		actions.append_array(ctrl._quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# Innkeeper: confirm rest for gold (full HP/MP + clear harmful).
	if bool(meta.get("inn_rest", false)):
		var inn_cost := int(meta.get("inn_cost", 25))
		if inn_cost < 0:
			inn_cost = 25
		var npc_name_i := str(meta.get("name", npc_id))
		var body_i := str(meta.get("interact_text", "")).strip_edges()
		if body_i.is_empty():
			body_i = "欢迎光临。休息可以完全恢复状态，需要 %d 金币。" % inn_cost
		body_i = ctrl._append_quest_offer_blurb(body_i, npc_id)
		var opts_i: Array = quest_opts.duplicate()
		opts_i.append({"id": "inn_rest:%d" % inn_cost, "label": "休息（%dG）" % inn_cost})
		ctrl._dialogue_npc_id = npc_id
		actions.append({
			"type": "show_npc_dialogue",
			"npc_id": npc_id,
			"npc_name": npc_name_i if npc_name_i != "" else npc_id,
			"body": body_i,
			"options": opts_i,
		})
		actions.append_array(ctrl._quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# Blacksmith: repair equipped gear for gold (durability).
	if bool(meta.get("blacksmith", false)):
		var cpp := int(meta.get("repair_cost_per_point", 1))
		if cpp < 0:
			cpp = 1
		var npc_name_b := str(meta.get("name", npc_id))
		var body_b := str(meta.get("interact_text", "")).strip_edges()
		if body_b.is_empty():
			body_b = "需要修理或强化装备吗？修理每点耐久 %d 金币；强化需强化石。" % cpp
		body_b = ctrl._append_quest_offer_blurb(body_b, npc_id)
		var opts_b: Array = quest_opts.duplicate()
		opts_b.append({"id": "repair:all:%d" % cpp, "label": "修理全部（%dG/点）" % cpp})
		if ctrl.inventory != null and ctrl.inventory.has_method("tools_need_repair") and ctrl.inventory.tools_need_repair():
			opts_b.append({"id": "repair:tools:%d" % cpp, "label": "修理工具（%dG/点）" % cpp})
		# Enhance options for each equipped piece under +5
		if ctrl.equipment != null:
			for sid in ctrl.equipment.SLOT_IDS:
				var iid_e := str(ctrl.equipment.get_item_in(sid)).strip_edges()
				if iid_e.is_empty():
					continue
				var enh_lv: int = int(ctrl.equipment.get_enhance(sid))
				if enh_lv >= int(ctrl.equipment.ENHANCE_MAX):
					continue
				var cost_e: int = int(ctrl.equipment.enhance_cost(enh_lv))
				var nm_e: String = ctrl.item_display_name(iid_e) if ctrl.has_method("item_display_name") else iid_e
				opts_b.append({
					"id": "enhance:%s" % sid,
					"label": "强化：%s +%d（强化石+%dG）" % [nm_e, enh_lv, cost_e],
				})
		ctrl._dialogue_npc_id = npc_id
		actions.append({
			"type": "show_npc_dialogue",
			"npc_id": npc_id,
			"npc_name": npc_name_b if npc_name_b != "" else npc_id,
			"body": body_b,
			"options": opts_b,
		})
		actions.append_array(ctrl._quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# Hardcoded + generic dialogue table.
	var npc_name := str(meta.get("name", npc_id))
	var body := str(meta.get("interact_text", "")).strip_edges()
	match npc_id:
		"actor_rest":
			npc_name = "休息中的少女"
			body = "有什么事吗？村里最近不安宁……" if body.is_empty() or body == "helloworld" else body
		_:
			pass
	if body != "" or not quest_opts.is_empty():
		if body.is_empty():
			body = "……"
		body = ctrl._append_quest_offer_blurb(body, npc_id)
		ctrl._dialogue_npc_id = npc_id
		actions.append({
			"type": "show_npc_dialogue",
			"npc_id": npc_id,
			"npc_name": npc_name if npc_name != "" else npc_id,
			"body": body,
			"options": quest_opts,
		})
		actions.append_array(ctrl._quest_note_talk_actions(npc_id))
		return {"ok": true, "actions": actions}
	# NPC exists but has no script / text.
	return {"ok": true, "actions": actions}

## @server-api
func _require_npc_adjacent(npc_id: String, player_x: int, player_y: int, range_cells: int) -> bool:
	if ctrl.combat_stats == null:
		return false
	var cell: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return false
	var dist: int = maxi(absi(cell.x - player_x), absi(cell.y - player_y))
	return dist <= range_cells
