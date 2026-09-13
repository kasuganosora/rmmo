extends RefCounted
## RPG Maker MV–inspired map event runtime (MockServer-authoritative subset).
## Triggers v1: action / action_button, player_touch.
## Skipped (stub): event_touch, autorun, parallel; battles, move routes, pictures, BGM, common events.

## Global switches: id -> bool (session-wide).
var switches: Dictionary = {}
## Self-switches: "mapId:eventId:LETTER" -> bool (session-wide; map id in key).
var self_switches: Dictionary = {}
## Current pack event defs (id -> Dictionary).
var events_by_id: Dictionary = {}
## Cell index "x,y" -> event id (first wins if duplicates).
var events_by_cell: Dictionary = {}
var map_id: String = ""
## Pending choice after a choices op: {event_id, branches:[{label,id,commands}]}
var _pending_choice: Dictionary = {}


func clear_session() -> void:
	## New character enter_world — wipe switch state + pending choice.
	switches.clear()
	self_switches.clear()
	_pending_choice.clear()


func clear_pack_events() -> void:
	events_by_id.clear()
	events_by_cell.clear()
	_pending_choice.clear()


func set_map_id(p_map_id: String) -> void:
	map_id = str(p_map_id).strip_edges()


## Load events from a TilemapPack (or pack-like) + merge inline npc "event" shortcuts.
func load_from_pack(pack) -> void:
	clear_pack_events()
	if pack == null:
		return
	set_map_id(str(pack.map_id) if "map_id" in pack else "")
	var list: Array = []
	if "events" in pack and typeof(pack.events) == TYPE_ARRAY:
		list = pack.events
	for item in list:
		if typeof(item) == TYPE_DICTIONARY:
			_register_event(item)
	# Inline shortcuts on npcs.json entries: "event": { pages / trigger / ... }
	if "npcs" in pack and typeof(pack.npcs) == TYPE_ARRAY:
		_merge_inline_npc_events(pack.npcs)


func load_events_array(events: Array, p_map_id: String = "", npcs: Array = []) -> void:
	clear_pack_events()
	set_map_id(p_map_id)
	for item in events:
		if typeof(item) == TYPE_DICTIONARY:
			_register_event(item)
	if not npcs.is_empty():
		_merge_inline_npc_events(npcs)


func _merge_inline_npc_events(npcs: Array) -> void:
	for n in npcs:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var nd: Dictionary = n
		if not nd.has("event"):
			continue
		var ev_v: Variant = nd.get("event")
		if typeof(ev_v) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = (ev_v as Dictionary).duplicate(true)
		var eid := str(ev.get("id", nd.get("id", ""))).strip_edges()
		if eid.is_empty():
			continue
		ev["id"] = eid
		if not ev.has("cell") and nd.has("cell"):
			ev["cell"] = nd.get("cell")
		if not ev.has("name") and nd.has("name"):
			ev["name"] = nd.get("name")
		if not ev.has("through") and nd.has("through"):
			ev["through"] = nd.get("through")
		# Existing file-based event wins; only fill missing.
		if events_by_id.has(eid):
			var base: Dictionary = events_by_id[eid]
			for k in ev.keys():
				if not base.has(k):
					base[k] = ev[k]
			_register_event(base)
		else:
			_register_event(ev)


func _register_event(raw: Dictionary) -> void:
	var ev: Dictionary = raw.duplicate(true)
	var eid := str(ev.get("id", "")).strip_edges()
	if eid.is_empty():
		return
	ev["id"] = eid
	# Normalize trigger aliases.
	var trig := str(ev.get("trigger", "action")).strip_edges().to_lower()
	match trig:
		"action_button", "action", "interact":
			trig = "action"
		"player_touch", "touch":
			trig = "player_touch"
		"event_touch", "autorun", "parallel":
			# v1 stub — keep tag but never auto-fire.
			pass
		_:
			trig = "action"
	ev["trigger"] = trig
	ev["through"] = bool(ev.get("through", false))
	# Normalize cell.
	var cell_v: Variant = ev.get("cell", null)
	if typeof(cell_v) == TYPE_DICTIONARY:
		var c: Dictionary = cell_v
		ev["cell"] = {"x": int(c.get("x", 0)), "y": int(c.get("y", 0))}
	# Pages array.
	var pages_v: Variant = ev.get("pages", [])
	if typeof(pages_v) != TYPE_ARRAY:
		ev["pages"] = []
	else:
		ev["pages"] = pages_v
	events_by_id[eid] = ev
	if typeof(ev.get("cell", null)) == TYPE_DICTIONARY:
		var cell: Dictionary = ev["cell"]
		var key := "%d,%d" % [int(cell.get("x", 0)), int(cell.get("y", 0))]
		if not events_by_cell.has(key):
			events_by_cell[key] = eid


func get_event(event_id: String) -> Dictionary:
	event_id = event_id.strip_edges()
	if events_by_id.has(event_id):
		return events_by_id[event_id]
	return {}


func get_event_at_cell(x: int, y: int) -> Dictionary:
	var key := "%d,%d" % [x, y]
	if not events_by_cell.has(key):
		return {}
	return get_event(str(events_by_cell[key]))


func has_event(event_id: String) -> bool:
	return events_by_id.has(event_id.strip_edges())


func get_switch(id: String) -> bool:
	return bool(switches.get(str(id).strip_edges(), false))


func set_switch(id: String, value: bool) -> void:
	id = str(id).strip_edges()
	if id.is_empty():
		return
	switches[id] = value


func _self_key(event_id: String, letter: String) -> String:
	letter = letter.strip_edges().to_upper()
	if letter not in ["A", "B", "C", "D"]:
		letter = "A"
	return "%s:%s:%s" % [map_id, event_id.strip_edges(), letter]


func get_self_switch(event_id: String, letter: String) -> bool:
	return bool(self_switches.get(_self_key(event_id, letter), false))


func set_self_switch(event_id: String, letter: String, value: bool) -> void:
	self_switches[_self_key(event_id, letter)] = value


## Highest page whose conditions pass wins (MV style: last matching in list).
func select_page(event: Dictionary) -> Dictionary:
	var pages_v: Variant = event.get("pages", [])
	if typeof(pages_v) != TYPE_ARRAY:
		return {}
	var pages: Array = pages_v
	var chosen: Dictionary = {}
	for i in range(pages.size()):
		var p: Variant = pages[i]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var page: Dictionary = p
		var when_v: Variant = page.get("when", {})
		var when: Dictionary = when_v if typeof(when_v) == TYPE_DICTIONARY else {}
		if _conditions_pass(when, str(event.get("id", ""))):
			chosen = page
	return chosen


func _conditions_pass(when: Dictionary, event_id: String) -> bool:
	if when.is_empty():
		return true
	# switch: "id" or switches: ["a","b"] — all must be ON
	if when.has("switch"):
		var sid := str(when.get("switch", "")).strip_edges()
		if sid != "" and not get_switch(sid):
			return false
	if when.has("switches"):
		var sw_v: Variant = when.get("switches")
		if typeof(sw_v) == TYPE_ARRAY:
			for s in sw_v:
				if not get_switch(str(s)):
					return false
		elif typeof(sw_v) == TYPE_STRING:
			if not get_switch(str(sw_v)):
				return false
	# self_switch: "A" (must be ON). Optional self_switch_value:bool default true.
	if when.has("self_switch"):
		var letter := str(when.get("self_switch", "A"))
		var want := true
		if when.has("self_switch_value"):
			want = bool(when.get("self_switch_value"))
		if get_self_switch(event_id, letter) != want:
			return false
	# item: "item_id" or {item_id, qty} — optional held check (needs inventory via ctx later).
	# Conditions evaluated here only for switches; item checked in select_page_with_ctx.
	return true


## Like select_page but also evaluates optional item-held conditions.
func select_page_with_ctx(event: Dictionary, server_ctx: Dictionary) -> Dictionary:
	var pages_v: Variant = event.get("pages", [])
	if typeof(pages_v) != TYPE_ARRAY:
		return {}
	var pages: Array = pages_v
	var chosen: Dictionary = {}
	var eid := str(event.get("id", ""))
	for i in range(pages.size()):
		var p: Variant = pages[i]
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var page: Dictionary = p
		var when_v: Variant = page.get("when", {})
		var when: Dictionary = when_v if typeof(when_v) == TYPE_DICTIONARY else {}
		if not _conditions_pass(when, eid):
			continue
		if not _item_condition_pass(when, server_ctx):
			continue
		chosen = page
	return chosen


func _item_condition_pass(when: Dictionary, server_ctx: Dictionary) -> bool:
	if not when.has("item") and not when.has("item_id"):
		return true
	var inv = server_ctx.get("inventory", null)
	if inv == null:
		return false
	var item_id := ""
	var qty := 1
	var iv: Variant = when.get("item", when.get("item_id", ""))
	if typeof(iv) == TYPE_DICTIONARY:
		item_id = str(iv.get("item_id", iv.get("id", ""))).strip_edges()
		qty = maxi(int(iv.get("qty", 1)), 1)
	else:
		item_id = str(iv).strip_edges()
		qty = maxi(int(when.get("qty", 1)), 1)
	if item_id.is_empty():
		return true
	if inv.has_method("has_item"):
		return bool(inv.has_item(item_id, qty))
	return false


## Run active page commands. Returns Array of client actions.
## server_ctx keys: inventory, shop_catalog, npc_name, transfer_cb, item_name_cb, quest_item_cb (Callables)
func run_event(event_id: String, server_ctx: Dictionary = {}) -> Array:
	event_id = event_id.strip_edges()
	var event: Dictionary = get_event(event_id)
	if event.is_empty():
		return []
	var page: Dictionary = select_page_with_ctx(event, server_ctx)
	if page.is_empty():
		return []
	var cmds_v: Variant = page.get("commands", [])
	if typeof(cmds_v) != TYPE_ARRAY:
		return []
	return _run_commands(event_id, cmds_v, server_ctx)


func _run_commands(event_id: String, commands: Array, server_ctx: Dictionary) -> Array:
	var actions: Array = []
	var npc_name := str(server_ctx.get("npc_name", event_id))
	var i := 0
	while i < commands.size():
		var raw: Variant = commands[i]
		i += 1
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cmd: Dictionary = raw
		var op := str(cmd.get("op", cmd.get("type", ""))).strip_edges().to_lower()
		match op:
			"text", "show_text", "show_npc_dialogue":
				var body := str(cmd.get("text", cmd.get("body", "")))
				actions.append({
					"type": "show_npc_dialogue",
					"npc_id": event_id,
					"npc_name": str(cmd.get("npc_name", npc_name)),
					"body": body,
					"options": [],
				})
			"choices", "choice", "show_choices":
				var body := str(cmd.get("text", cmd.get("body", "")))
				var opts_v: Variant = cmd.get("options", cmd.get("choices", []))
				var opt_actions: Array = []
				var branches: Array = []
				if typeof(opts_v) == TYPE_ARRAY:
					var oi := 0
					for ov in opts_v:
						if typeof(ov) != TYPE_DICTIONARY:
							# Plain string option → continue (no branch)
							var lab := str(ov).strip_edges()
							if lab == "":
								continue
							var oid := "opt_%d" % oi
							opt_actions.append({"id": oid, "label": lab})
							branches.append({"id": oid, "label": lab, "commands": []})
							oi += 1
							continue
						var od: Dictionary = ov
						var lab2 := str(od.get("label", od.get("text", ""))).strip_edges()
						var oid2 := str(od.get("id", "opt_%d" % oi)).strip_edges()
						if oid2.is_empty():
							oid2 = "opt_%d" % oi
						var br_cmds: Array = []
						var cv: Variant = od.get("commands", od.get("branch", []))
						if typeof(cv) == TYPE_ARRAY:
							br_cmds = cv
						opt_actions.append({"id": oid2, "label": lab2 if lab2 != "" else oid2})
						branches.append({"id": oid2, "label": lab2, "commands": br_cmds})
						oi += 1
				_pending_choice = {
					"event_id": event_id,
					"branches": branches,
					"npc_name": npc_name,
					"server_ctx": server_ctx.duplicate(false),
				}
				actions.append({
					"type": "show_npc_dialogue",
					"npc_id": event_id,
					"npc_name": npc_name,
					"body": body,
					"options": opt_actions,
					"event_choice": true,
				})
				# Stop page until client picks an option.
				return actions
			"message", "system", "system_message":
				var msg := str(cmd.get("text", cmd.get("message", ""))).strip_edges()
				if msg != "":
					actions.append({"type": "system_message", "text": msg})
			"give_item":
				actions.append_array(_cmd_give_item(cmd, server_ctx))
			"take_item":
				actions.append_array(_cmd_take_item(cmd, server_ctx))
			"give_gold":
				actions.append_array(_cmd_give_gold(cmd, server_ctx))
			"take_gold":
				actions.append_array(_cmd_take_gold(cmd, server_ctx))
			"set_switch":
				var sid := str(cmd.get("id", cmd.get("switch", ""))).strip_edges()
				var val := bool(cmd.get("value", true))
				if sid != "":
					set_switch(sid, val)
			"set_self_switch":
				var letter := str(cmd.get("letter", cmd.get("self_switch", "A")))
				var sval := bool(cmd.get("value", true))
				set_self_switch(event_id, letter, sval)
			"transfer":
				actions.append_array(_cmd_transfer(cmd, server_ctx))
				# Transfer ends the page (map will unload).
				return actions
			"open_shop":
				actions.append_array(_cmd_open_shop(cmd, server_ctx))
			"end", "stop", "exit":
				return actions
			_:
				# Unknown / skipped MV ops (battle, move_route, picture, tint, bgm, …).
				pass
	return actions


func try_event_choice(option_id: String, option_index: int = -1) -> Array:
	## Resolve a pending choices branch. Clears pending regardless of match.
	if _pending_choice.is_empty():
		return []
	var pending: Dictionary = _pending_choice.duplicate(true)
	_pending_choice.clear()
	var branches_v: Variant = pending.get("branches", [])
	if typeof(branches_v) != TYPE_ARRAY:
		return []
	var branches: Array = branches_v
	var chosen: Dictionary = {}
	option_id = option_id.strip_edges()
	if option_id != "":
		for b in branches:
			if typeof(b) == TYPE_DICTIONARY and str(b.get("id", "")) == option_id:
				chosen = b
				break
	if chosen.is_empty() and option_index >= 0 and option_index < branches.size():
		var bv: Variant = branches[option_index]
		if typeof(bv) == TYPE_DICTIONARY:
			chosen = bv
	if chosen.is_empty() and branches.size() == 1:
		var b0: Variant = branches[0]
		if typeof(b0) == TYPE_DICTIONARY:
			chosen = b0
	if chosen.is_empty():
		return []
	var cmds_v: Variant = chosen.get("commands", [])
	if typeof(cmds_v) != TYPE_ARRAY or (cmds_v as Array).is_empty():
		# Text-only continue: no further commands.
		return []
	var eid := str(pending.get("event_id", ""))
	var ctx: Dictionary = {}
	var ctx_v: Variant = pending.get("server_ctx", {})
	if typeof(ctx_v) == TYPE_DICTIONARY:
		ctx = ctx_v
	if not ctx.has("npc_name"):
		ctx["npc_name"] = str(pending.get("npc_name", eid))
	return _run_commands(eid, cmds_v, ctx)


func _inventory_update_action(inv) -> Dictionary:
	if inv == null:
		return {"type": "inventory_update", "items": [], "gold": 0}
	return {
		"type": "inventory_update",
		"items": inv.snapshot() if inv.has_method("snapshot") else [],
		"gold": inv.get_gold() if inv.has_method("get_gold") else 0,
	}


func _item_display_name(item_id: String, server_ctx: Dictionary) -> String:
	var cb: Variant = server_ctx.get("item_name_cb", null)
	if typeof(cb) == TYPE_CALLABLE:
		return str((cb as Callable).call(item_id))
	return item_id


func _cmd_give_item(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var inv = server_ctx.get("inventory", null)
	var item_id := str(cmd.get("item_id", cmd.get("id", ""))).strip_edges()
	var qty := maxi(int(cmd.get("qty", 1)), 1)
	var out: Array = []
	if inv == null or item_id.is_empty():
		return out
	var added := 0
	if inv.has_method("add_item"):
		added = int(inv.add_item(item_id, qty))
	elif inv.has_method("try_add_item"):
		var r: Dictionary = inv.try_add_item(item_id, qty)
		added = int(r.get("added", 0))
	out.append(_inventory_update_action(inv))
	if added > 0:
		out.append({
			"type": "system_message",
			"text": "获得了【%s】×%d。" % [_item_display_name(item_id, server_ctx), added],
		})
		var qcb: Variant = server_ctx.get("quest_item_cb", null)
		if typeof(qcb) == TYPE_CALLABLE:
			var qa: Variant = (qcb as Callable).call(item_id, added)
			if typeof(qa) == TYPE_ARRAY:
				out.append_array(qa)
	elif qty > 0:
		out.append({"type": "system_message", "text": "背包已满，无法获得物品。"})
	return out


func _cmd_take_item(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var inv = server_ctx.get("inventory", null)
	var item_id := str(cmd.get("item_id", cmd.get("id", ""))).strip_edges()
	var qty := maxi(int(cmd.get("qty", 1)), 1)
	var out: Array = []
	if inv == null or item_id.is_empty():
		return out
	var ok := false
	if inv.has_method("consume"):
		ok = bool(inv.consume(item_id, qty))
	out.append(_inventory_update_action(inv))
	if ok:
		out.append({
			"type": "system_message",
			"text": "失去了【%s】×%d。" % [_item_display_name(item_id, server_ctx), qty],
		})
	return out


func _cmd_give_gold(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var inv = server_ctx.get("inventory", null)
	var amount := maxi(int(cmd.get("amount", cmd.get("gold", 0))), 0)
	var out: Array = []
	if inv == null or amount <= 0:
		return out
	if inv.has_method("add_gold"):
		inv.add_gold(amount)
	out.append(_inventory_update_action(inv))
	out.append({"type": "system_message", "text": "获得了 %dG。" % amount})
	return out


func _cmd_take_gold(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var inv = server_ctx.get("inventory", null)
	var amount := maxi(int(cmd.get("amount", cmd.get("gold", 0))), 0)
	var out: Array = []
	if inv == null or amount <= 0:
		return out
	var ok := false
	if inv.has_method("try_spend_gold"):
		ok = bool(inv.try_spend_gold(amount))
	out.append(_inventory_update_action(inv))
	if ok:
		out.append({"type": "system_message", "text": "失去了 %dG。" % amount})
	else:
		out.append({"type": "system_message", "text": "金币不足。"})
	return out


func _cmd_transfer(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var to_pack := str(cmd.get("to_pack", "")).strip_edges()
	var to_cell_v: Variant = cmd.get("to_cell", {})
	var to_cell: Dictionary = to_cell_v if typeof(to_cell_v) == TYPE_DICTIONARY else {}
	var facing := int(cmd.get("facing", 2))
	var message := str(cmd.get("message", ""))
	var cb: Variant = server_ctx.get("transfer_cb", null)
	if typeof(cb) != TYPE_CALLABLE:
		# Fallback: emit map_transfer without loading (client/server must handle).
		return [{
			"type": "map_transfer",
			"ok": true,
			"pack_path": to_pack,
			"map_id": str(cmd.get("to_map_id", "")),
			"cell": {"x": int(to_cell.get("x", 0)), "y": int(to_cell.get("y", 0))},
			"facing": facing,
			"message": message,
		}]
	var result: Dictionary = (cb as Callable).call(to_pack, to_cell, facing, message, str(cmd.get("to_map_id", "")))
	if typeof(result) != TYPE_DICTIONARY or not bool(result.get("ok", false)):
		return [{"type": "system_message", "text": "无法传送。"}]
	# Same shape as try_transfer + action type for client.
	var actions: Array = [{
		"type": "map_transfer",
		"ok": true,
		"pack_path": str(result.get("pack_path", to_pack)),
		"map_id": str(result.get("map_id", "")),
		"content_id": str(result.get("content_id", "")),
		"content_version": str(result.get("content_version", "")),
		"cell": result.get("cell", {"x": int(to_cell.get("x", 0)), "y": int(to_cell.get("y", 0))}),
		"facing": int(result.get("facing", facing)),
		"message": str(result.get("message", message)),
		"quests": result.get("quests", []),
	}]
	var extra_v: Variant = result.get("actions", [])
	if typeof(extra_v) == TYPE_ARRAY:
		actions.append_array(extra_v)
	return actions


func _cmd_open_shop(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var shop_id := str(cmd.get("shop_id", cmd.get("id", ""))).strip_edges()
	var shop_catalog = server_ctx.get("shop_catalog", null)
	var inv = server_ctx.get("inventory", null)
	if shop_id.is_empty() or shop_catalog == null:
		return []
	if shop_catalog.has_method("has_shop") and not shop_catalog.has_shop(shop_id):
		return [{"type": "system_message", "text": "商店不存在。"}]
	var gold_v: int = inv.get_gold() if inv != null and inv.has_method("get_gold") else 0
	return [{
		"type": "open_shop",
		"shop_id": shop_id,
		"title": shop_catalog.shop_title(shop_id) if shop_catalog.has_method("shop_title") else shop_id,
		"listings": shop_catalog.build_listings(shop_id) if shop_catalog.has_method("build_listings") else [],
		"gold": gold_v,
	}]
