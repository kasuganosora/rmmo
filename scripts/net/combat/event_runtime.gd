extends RefCounted

const TileId = preload("res://scripts/map/tile_id.gd")
## RPG Maker MV–inspired map event runtime (MockServer-authoritative subset).
## Triggers: action / player_touch / event_touch / autorun.
## Commands include thin move_route (turn/move/wait; server-authoritative).
## Skipped (stub): parallel; battles, pictures, common events, full MV route editor.

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
	ev["trigger"] = normalize_trigger(str(ev.get("trigger", "action")))
	var pages_norm_v: Variant = ev.get("pages", [])
	if typeof(pages_norm_v) == TYPE_ARRAY:
		for pv in pages_norm_v:
			if typeof(pv) == TYPE_DICTIONARY and str(pv.get("trigger", "")).strip_edges() != "":
				pv["trigger"] = normalize_trigger(str(pv.get("trigger", "")))
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


func normalize_trigger(trig: String) -> String:
	match trig.strip_edges().to_lower():
		"action_button", "action", "interact":
			return "action"
		"player_touch", "touch":
			return "player_touch"
		"event_touch", "eventtouch":
			return "event_touch"
		"autorun", "auto":
			return "autorun"
		"parallel":
			return "parallel"
		_:
			return "action"


## Page trigger, falling back to the event-level trigger when the page omits one.
func page_trigger(event: Dictionary, page: Dictionary = {}) -> String:
	var trig := ""
	if not page.is_empty():
		trig = str(page.get("trigger", "")).strip_edges()
	if trig == "":
		trig = str(event.get("trigger", "action")).strip_edges()
	return normalize_trigger(trig)


## One finite pass: run each currently matching autorun page once. Does not loop
## if a page stays autorun, and does not pick up events that become autorun
## mid-pass. Caller may collect again after a page change.
func collect_autorun(server_ctx: Dictionary = {}) -> Array:
	var matching: Array = []
	for eid_v in events_by_id.keys():
		var eid := str(eid_v)
		var ev: Dictionary = get_event(eid)
		if ev.is_empty():
			continue
		var page: Dictionary = select_page_with_ctx(ev, server_ctx)
		if page.is_empty():
			continue
		if page_trigger(ev, page) == "autorun":
			matching.append(eid)
	var actions: Array = []
	var ran: Dictionary = {}
	for eid2 in matching:
		var id2 := str(eid2)
		if ran.has(id2):
			continue
		ran[id2] = true
		var ev2: Dictionary = get_event(id2)
		var page2: Dictionary = select_page_with_ctx(ev2, server_ctx)
		if page2.is_empty() or page_trigger(ev2, page2) != "autorun":
			continue
		actions.append_array(run_event(id2, server_ctx))
	return actions


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
				var talk := {
					"type": "show_npc_dialogue",
					"npc_id": event_id,
					"npc_name": str(cmd.get("npc_name", npc_name)),
					"body": body,
					"options": [],
				}
				_attach_face(talk, cmd)
				actions.append(talk)
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
				var talk := {
					"type": "show_npc_dialogue",
					"npc_id": event_id,
					"npc_name": npc_name,
					"body": body,
					"options": opt_actions,
					"event_choice": true,
				}
				_attach_face(talk, cmd)
				actions.append(talk)
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
				actions.append(_graphic_action(event_id))
			"play_bgm":
				actions.append(_audio_action("bgm", cmd))
			"play_bgs":
				actions.append(_audio_action("bgs", cmd))
			"play_me":
				actions.append(_audio_action("me", cmd))
			"play_se", "se":
				actions.append(_audio_action("se", cmd))
			"weather":
				var wkind := str(cmd.get("kind", cmd.get("weather", "clear")))
				var wint := clampf(float(cmd.get("intensity", 0.75)), 0.0, 1.0)
				var wdur := maxf(float(cmd.get("duration", 60.0)), 0.0)
				var wcb: Variant = server_ctx.get("weather_cb", null)
				if wcb is Callable:
					var wact: Variant = wcb.call(wkind, wint, wdur)
					if typeof(wact) == TYPE_DICTIONARY:
						actions.append(wact)
					else:
						actions.append({"type": "weather", "kind": wkind, "intensity": wint})
				else:
					actions.append({"type": "weather", "kind": wkind, "intensity": wint})
			"wait":
				actions.append({
					"type": "wait",
					"duration": _wait_duration(cmd),
				})
			"transfer":
				actions.append_array(_cmd_transfer(cmd, server_ctx))
				# Transfer ends the page (map will unload).
				return actions
			"open_shop":
				actions.append_array(_cmd_open_shop(cmd, server_ctx))
			"inn_rest", "rest_inn":
				actions.append_array(_cmd_inn_rest(cmd, server_ctx))
			"move_route", "set_move_route":
				actions.append_array(_cmd_move_route(event_id, cmd, server_ctx))
			"end", "stop", "exit":
				return actions
			_:
				# Unknown / skipped MV ops (battle, picture, tint, common event, …).
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


func _attach_face(action: Dictionary, cmd: Dictionary) -> void:
	var face := str(cmd.get("face", cmd.get("faceName", ""))).strip_edges()
	if face == "":
		return
	action["face"] = face
	action["face_index"] = int(cmd.get("face_index", cmd.get("faceIndex", 0)))


func _wait_duration(cmd: Dictionary) -> float:
	var dur := float(cmd.get("duration", cmd.get("seconds", cmd.get("sec", 0))))
	if dur <= 0.0:
		var frames := int(cmd.get("frames", 0))
		if frames > 0:
			dur = float(frames) / 60.0
	if dur <= 0.0:
		dur = 0.5
	return dur


func _audio_action(channel: String, cmd: Dictionary) -> Dictionary:
	return {
		"type": "play_audio",
		"channel": channel,
		"id": str(cmd.get("id", cmd.get("name", cmd.get("file", "")))).strip_edges(),
	}


func _graphic_action(event_id: String) -> Dictionary:
	var ev: Dictionary = get_event(event_id)
	var page: Dictionary = select_page(ev)
	var g_v: Variant = page.get("graphic", {})
	var g: Dictionary = g_v if typeof(g_v) == TYPE_DICTIONARY else {}
	return {
		"type": "event_graphic",
		"event_id": event_id,
		"charset": str(g.get("charset", g.get("characterName", ""))).strip_edges(),
		"index": int(g.get("index", g.get("characterIndex", 0))),
		"direction": int(g.get("direction", 2)),
	}


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
	var to_map := str(cmd.get("to_map", cmd.get("to_map_id", ""))).strip_edges()
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
			"map_id": to_map,
			"cell": {"x": int(to_cell.get("x", 0)), "y": int(to_cell.get("y", 0))},
			"facing": facing,
			"message": message,
		}]
	var result: Dictionary = (cb as Callable).call(to_pack, to_cell, facing, message, to_map)
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
	# Prefer MockServer open path (discounted listings + vendor_rep).
	var cb: Variant = server_ctx.get("open_shop_cb", null)
	if cb is Callable:
		var result: Variant = cb.call(shop_id)
		if typeof(result) == TYPE_DICTIONARY:
			var acts_v: Variant = (result as Dictionary).get("actions", [])
			if typeof(acts_v) == TYPE_ARRAY:
				return acts_v
	var gold_v: int = inv.get_gold() if inv != null and inv.has_method("get_gold") else 0
	return [{
		"type": "open_shop",
		"shop_id": shop_id,
		"title": shop_catalog.shop_title(shop_id) if shop_catalog.has_method("shop_title") else shop_id,
		"listings": shop_catalog.build_listings(shop_id) if shop_catalog.has_method("build_listings") else [],
		"gold": gold_v,
		"vendor_rep": 0,
	}]


func _cmd_inn_rest(cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var cost := int(cmd.get("cost", cmd.get("gold", cmd.get("amount", 25))))
	if cost < 0:
		cost = 25
	var cb: Variant = server_ctx.get("inn_rest_cb", null)
	if cb is Callable:
		var result: Variant = cb.call(cost)
		if typeof(result) == TYPE_DICTIONARY:
			var acts_v: Variant = (result as Dictionary).get("actions", [])
			if typeof(acts_v) == TYPE_ARRAY:
				return acts_v
			return []
		if typeof(result) == TYPE_ARRAY:
			return result
	return [{"type": "system_message", "text": "无法休息。"}]


## Update event occupancy cell (events_by_id + events_by_cell). Used by move_route.
func update_event_cell(event_id: String, x: int, y: int) -> void:
	event_id = event_id.strip_edges()
	if event_id.is_empty() or not events_by_id.has(event_id):
		return
	var ev: Dictionary = events_by_id[event_id]
	var old_v: Variant = ev.get("cell", null)
	if typeof(old_v) == TYPE_DICTIONARY:
		var oc: Dictionary = old_v
		var old_key := "%d,%d" % [int(oc.get("x", 0)), int(oc.get("y", 0))]
		if str(events_by_cell.get(old_key, "")) == event_id:
			events_by_cell.erase(old_key)
	ev["cell"] = {"x": x, "y": y}
	var new_key := "%d,%d" % [x, y]
	events_by_cell[new_key] = event_id


## Thin MV move_route:
## {
##   "op": "move_route",
##   "target": "self" | "<npc_or_event_id>",
##   "route": [{"code":"move_down"|"move_left"|"move_right"|"move_up"|"turn_up"|...|"wait", "repeat":1}],
##   "wait": true,       # MV wait-for-completion; thin shell always runs sync
##   "skippable": false  # true = skip blocked step; false = stop route cleanly
## }
## Emits npc_move (and wait) actions the client already understands via _apply_npc_move.
func _cmd_move_route(event_id: String, cmd: Dictionary, server_ctx: Dictionary) -> Array:
	var target := str(cmd.get("target", "self")).strip_edges()
	if target == "" or target.to_lower() in ["self", "this", "event"]:
		target = event_id
	var route_v: Variant = cmd.get("route", cmd.get("list", cmd.get("steps", [])))
	if typeof(route_v) != TYPE_ARRAY:
		return []
	var route: Array = route_v
	if route.is_empty():
		return []
	var skippable := bool(cmd.get("skippable", false))
	var cell := _route_resolve_cell(target, server_ctx)
	var facing := _route_resolve_facing(target, server_ctx)
	var out: Array = []
	for raw_step in route:
		var steps: Array = _route_expand_step(raw_step)
		for step in steps:
			if typeof(step) != TYPE_DICTIONARY:
				continue
			var code := str(step.get("code", step.get("op", ""))).strip_edges().to_lower()
			if code == "" or code == "wait":
				var wait_src: Dictionary = step if code == "wait" else {"duration": 0.2}
				out.append({
					"type": "wait",
					"duration": _route_wait_duration(wait_src),
				})
				continue
			var turn_dir := _route_turn_dir(code)
			if turn_dir > 0:
				facing = turn_dir
				_route_apply_face(target, facing, server_ctx)
				out.append(_route_npc_move_action(target, cell.x, cell.y, facing))
				continue
			var move_dir := _route_move_dir(code)
			if move_dir <= 0:
				continue
			var moved: Dictionary = _route_try_step(target, cell.x, cell.y, move_dir, server_ctx)
			if not bool(moved.get("ok", false)):
				if skippable:
					continue
				# Stop cleanly on blocked tile — do not crash.
				return out
			cell = Vector2i(int(moved.get("x", cell.x)), int(moved.get("y", cell.y)))
			facing = int(moved.get("facing", move_dir))
			if not TileId.is_dir(facing):
				facing = move_dir
			out.append(_route_npc_move_action(target, cell.x, cell.y, facing))
			var extra_v: Variant = moved.get("actions", [])
			if typeof(extra_v) == TYPE_ARRAY and not (extra_v as Array).is_empty():
				out.append_array(extra_v)
	return out


func _route_expand_step(raw: Variant) -> Array:
	## One route entry → N identical step dicts (honours repeat).
	if typeof(raw) == TYPE_STRING:
		raw = {"code": str(raw)}
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	var step: Dictionary = raw
	var n := maxi(int(step.get("repeat", step.get("count", 1))), 1)
	n = mini(n, 32)
	var out: Array = []
	for _i in range(n):
		out.append(step)
	return out


func _route_wait_duration(step: Dictionary) -> float:
	var dur := float(step.get("duration", step.get("seconds", step.get("sec", 0))))
	if dur <= 0.0:
		var frames := int(step.get("frames", 0))
		if frames > 0:
			dur = float(frames) / 60.0
	if dur <= 0.0:
		dur = 0.2
	return dur


func _route_move_dir(code: String) -> int:
	match code:
		"move_down", "down", "move_2", "2":
			return 2
		"move_left", "left", "move_4", "4":
			return 4
		"move_right", "right", "move_6", "6":
			return 6
		"move_up", "up", "move_8", "8":
			return 8
		_:
			return 0


func _route_turn_dir(code: String) -> int:
	match code:
		"turn_down", "face_down", "turn_2":
			return 2
		"turn_left", "face_left", "turn_4":
			return 4
		"turn_right", "face_right", "turn_6":
			return 6
		"turn_up", "face_up", "turn_8":
			return 8
		_:
			return 0


func _route_resolve_cell(target_id: String, server_ctx: Dictionary) -> Vector2i:
	var cb: Variant = server_ctx.get("npc_cell_cb", null)
	if typeof(cb) == TYPE_CALLABLE:
		var v: Variant = (cb as Callable).call(target_id)
		if typeof(v) == TYPE_VECTOR2I:
			return v
		if typeof(v) == TYPE_DICTIONARY:
			return Vector2i(int(v.get("x", 0)), int(v.get("y", 0)))
	var ev: Dictionary = get_event(target_id)
	if not ev.is_empty():
		var c_v: Variant = ev.get("cell", {})
		if typeof(c_v) == TYPE_DICTIONARY:
			return Vector2i(int(c_v.get("x", 0)), int(c_v.get("y", 0)))
	return Vector2i.ZERO


func _route_resolve_facing(target_id: String, server_ctx: Dictionary) -> int:
	var cb: Variant = server_ctx.get("npc_facing_cb", null)
	if typeof(cb) == TYPE_CALLABLE:
		var v: Variant = (cb as Callable).call(target_id)
		var f := int(v)
		if f in [2, 4, 6, 8]:
			return f
	var ev: Dictionary = get_event(target_id)
	if not ev.is_empty():
		var page: Dictionary = select_page(ev)
		var g_v: Variant = page.get("graphic", {})
		if typeof(g_v) == TYPE_DICTIONARY:
			var d := int(g_v.get("direction", 2))
			if d in [2, 4, 6, 8]:
				return d
	return 2


func _route_apply_face(target_id: String, facing: int, server_ctx: Dictionary) -> void:
	var cb: Variant = server_ctx.get("npc_face_cb", null)
	if typeof(cb) == TYPE_CALLABLE:
		(cb as Callable).call(target_id, facing)


func _route_try_step(
	target_id: String, from_x: int, from_y: int, dir: int, server_ctx: Dictionary
) -> Dictionary:
	var cb: Variant = server_ctx.get("npc_step_cb", null)
	if typeof(cb) == TYPE_CALLABLE:
		var r: Variant = (cb as Callable).call(target_id, from_x, from_y, dir)
		if typeof(r) == TYPE_DICTIONARY:
			if bool(r.get("ok", false)) and has_event(target_id):
				update_event_cell(target_id, int(r.get("x", from_x)), int(r.get("y", from_y)))
			return r
		return {"ok": false, "x": from_x, "y": from_y}
	var col = server_ctx.get("collision", null)
	if col != null and col.has_method("can_pass"):
		if not bool(col.can_pass(from_x, from_y, dir)):
			return {"ok": false, "x": from_x, "y": from_y}
	elif col != null and col.has_method("is_blocked"):
		var delta: Vector2i = TileId.dir_delta(dir)
		var nx2: int = from_x + delta.x
		var ny2: int = from_y + delta.y
		if bool(col.is_blocked(nx2, ny2)):
			return {"ok": false, "x": from_x, "y": from_y}
	var delta2: Vector2i = TileId.dir_delta(dir)
	var nx: int = from_x + delta2.x
	var ny: int = from_y + delta2.y
	var pc_v: Variant = server_ctx.get("player_cell", null)
	if typeof(pc_v) == TYPE_VECTOR2I:
		var pc: Vector2i = pc_v
		if nx == pc.x and ny == pc.y:
			return {"ok": false, "x": from_x, "y": from_y}
	elif typeof(pc_v) == TYPE_DICTIONARY:
		if nx == int(pc_v.get("x", -9999)) and ny == int(pc_v.get("y", -9999)):
			return {"ok": false, "x": from_x, "y": from_y}
	if has_event(target_id):
		update_event_cell(target_id, nx, ny)
	if col != null and col.has_method("set_extra_blocked"):
		col.set_extra_blocked(from_x, from_y, false)
		col.set_extra_blocked(nx, ny, true)
	return {"ok": true, "x": nx, "y": ny, "facing": dir, "npc_id": target_id}


func _route_npc_move_action(npc_id: String, x: int, y: int, facing: int) -> Dictionary:
	return {
		"type": "npc_move",
		"npc_id": npc_id,
		"x": x,
		"y": y,
		"facing": facing,
	}

