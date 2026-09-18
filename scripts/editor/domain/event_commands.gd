extends RefCounted
## EventRuntime-facing command helpers for the content editor.


const TRIGGERS := [
	{"id": "action", "label": "确定键"},
	{"id": "player_touch", "label": "接触"},
	{"id": "event_touch", "label": "事件接触"},
	{"id": "autorun", "label": "自动执行"},
]

const OPS := [
	{"id": "text", "label": "对话"},
	{"id": "system", "label": "系统消息"},
	{"id": "give_item", "label": "给物品"},
	{"id": "take_item", "label": "收物品"},
	{"id": "give_gold", "label": "给金币"},
	{"id": "take_gold", "label": "收金币"},
	{"id": "set_switch", "label": "开关"},
	{"id": "set_self_switch", "label": "独立开关"},
	{"id": "open_shop", "label": "商店"},
	{"id": "inn_rest", "label": "旅店休息"},
	{"id": "transfer", "label": "传送"},
	{"id": "choices", "label": "选项"},
	{"id": "wait", "label": "等待"},
	{"id": "play_bgm", "label": "播放 BGM"},
	{"id": "play_bgs", "label": "播放 BGS"},
	{"id": "play_me", "label": "播放 ME"},
	{"id": "play_se", "label": "播放 SE"},
	{"id": "weather", "label": "天气"},
	{"id": "move_route", "label": "移动路径"},
]


static func normalize_trigger(trig: String) -> String:
	match trig.strip_edges().to_lower():
		"action_button", "action", "interact", "确定键":
			return "action"
		"player_touch", "touch", "接触":
			return "player_touch"
		"event_touch", "eventtouch", "事件接触":
			return "event_touch"
		"autorun", "auto", "自动执行":
			return "autorun"
		"parallel":
			return "parallel"
		_:
			return "action"


static func trigger_label(trig: String) -> String:
	var key := normalize_trigger(trig)
	for row in TRIGGERS:
		if str(row["id"]) == key:
			return str(row["label"])
	return key


static func fill_trigger_option(opt: OptionButton) -> void:
	if opt == null:
		return
	opt.clear()
	for row in TRIGGERS:
		opt.add_item(str(row["label"]))
		opt.set_item_metadata(opt.item_count - 1, str(row["id"]))


static func trigger_id_of(opt: OptionButton) -> String:
	if opt == null or opt.item_count <= 0 or opt.selected < 0:
		return "action"
	return normalize_trigger(str(opt.get_item_metadata(opt.selected)))


static func select_trigger_option(opt: OptionButton, trig: String) -> void:
	if opt == null:
		return
	var want := normalize_trigger(trig)
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == want:
			opt.select(i)
			return
	opt.select(0)


static func op_label(op: String) -> String:
	var key := op.strip_edges().to_lower()
	for row in OPS:
		if str(row["id"]) == key:
			return str(row["label"])
	return key if key != "" else "指令"


static func default_command(op: String) -> Dictionary:
	match op.strip_edges().to_lower():
		"text", "show_text", "show_npc_dialogue":
			return {"op": "text", "text": "……", "face": "", "face_index": 0}
		"system", "message", "system_message":
			return {"op": "system", "text": ""}
		"give_item":
			return {"op": "give_item", "item_id": "potion_hp_small", "qty": 1}
		"take_item":
			return {"op": "take_item", "item_id": "potion_hp_small", "qty": 1}
		"give_gold":
			return {"op": "give_gold", "amount": 10}
		"take_gold":
			return {"op": "take_gold", "amount": 10}
		"set_switch":
			return {"op": "set_switch", "id": "switch_1", "value": true}
		"set_self_switch":
			return {"op": "set_self_switch", "letter": "A", "value": true}
		"open_shop":
			return {"op": "open_shop", "shop_id": "starter_goods"}
		"inn_rest", "rest_inn":
			return {"op": "inn_rest", "cost": 25}
		"transfer":
			return {"op": "transfer", "to_map": "Map002", "to_cell": {"x": 1, "y": 1}}
		"choices", "choice", "show_choices":
			return {
				"op": "choices",
				"text": "要怎么做？",
				"options": [
					{"id": "opt_0", "label": "是", "commands": []},
					{"id": "opt_1", "label": "否", "commands": []},
				],
			}
		"play_bgm":
			return {"op": "play_bgm", "id": ""}
		"play_bgs":
			return {"op": "play_bgs", "id": ""}
		"play_me":
			return {"op": "play_me", "id": ""}
		"play_se":
			return {"op": "play_se", "id": ""}
		"wait":
			return {"op": "wait", "duration": 0.5}
		"weather":
			return {"op": "weather", "kind": "rain", "intensity": 0.8, "duration": 60.0}
		"move_route", "set_move_route":
			return {
				"op": "move_route",
				"target": "self",
				"wait": true,
				"skippable": false,
				"route": [
					{"code": "move_right", "repeat": 1},
					{"code": "turn_down"},
				],
			}
		_:
			return {"op": op.strip_edges().to_lower()}


static func summarize(cmd: Dictionary) -> String:
	var op := str(cmd.get("op", cmd.get("type", ""))).strip_edges().to_lower()
	match op:
		"text", "show_text", "show_npc_dialogue":
			var face := str(cmd.get("face", cmd.get("faceName", ""))).strip_edges()
			var head := "对话：%s" % _clip(str(cmd.get("text", cmd.get("body", ""))))
			return head if face == "" else "%s  [%s]" % [head, face]
		"system", "message", "system_message":
			return "系统：%s" % _clip(str(cmd.get("text", cmd.get("message", ""))))
		"give_item":
			return "给物品：%s × %d" % [str(cmd.get("item_id", "")), int(cmd.get("qty", 1))]
		"take_item":
			return "收物品：%s × %d" % [str(cmd.get("item_id", "")), int(cmd.get("qty", 1))]
		"give_gold":
			return "给金币：%d" % int(cmd.get("amount", cmd.get("gold", 0)))
		"take_gold":
			return "收金币：%d" % int(cmd.get("amount", cmd.get("gold", 0)))
		"set_switch":
			return "开关 %s = %s" % [str(cmd.get("id", cmd.get("switch", ""))), "开" if bool(cmd.get("value", true)) else "关"]
		"set_self_switch":
			return "独立开关 %s = %s" % [str(cmd.get("letter", cmd.get("self_switch", "A"))), "开" if bool(cmd.get("value", true)) else "关"]
		"open_shop":
			return "商店：%s" % str(cmd.get("shop_id", cmd.get("id", "")))
		"inn_rest", "rest_inn":
			return "旅店休息：%dG" % int(cmd.get("cost", cmd.get("gold", cmd.get("amount", 25))))
		"transfer":
			var cell: Variant = cmd.get("to_cell", {})
			var cx := 0
			var cy := 0
			if typeof(cell) == TYPE_DICTIONARY:
				cx = int(cell.get("x", 0))
				cy = int(cell.get("y", 0))
			return "传送：%s (%d,%d)" % [str(cmd.get("to_map", cmd.get("map_id", ""))), cx, cy]
		"choices", "choice", "show_choices":
			return "选项：%s" % _clip(str(cmd.get("text", cmd.get("body", ""))))
		"play_bgm":
			return "BGM：%s" % str(cmd.get("id", cmd.get("name", "")))
		"play_bgs":
			return "BGS：%s" % str(cmd.get("id", cmd.get("name", "")))
		"play_me":
			return "ME：%s" % str(cmd.get("id", cmd.get("name", "")))
		"play_se":
			return "SE：%s" % str(cmd.get("id", cmd.get("name", "")))
		"wait":
			return "等待：%s 秒" % str(_wait_duration(cmd))
		"move_route", "set_move_route":
			var route_v: Variant = cmd.get("route", cmd.get("list", []))
			var n := 0
			if typeof(route_v) == TYPE_ARRAY:
				n = (route_v as Array).size()
			var tgt := str(cmd.get("target", "self")).strip_edges()
			return "移动路径：%s ×%d" % [tgt if tgt != "" else "self", n]
		"end", "stop", "exit":
			return "结束"
		_:
			return op_label(op)


static func default_graphic(charset: String = "", index: int = 0, direction: int = 2) -> Dictionary:
	return {"charset": charset, "index": index, "direction": direction}


static func page_graphic(page: Dictionary) -> Dictionary:
	var g_v: Variant = page.get("graphic", {})
	var g: Dictionary = g_v if typeof(g_v) == TYPE_DICTIONARY else {}
	return {
		"charset": str(g.get("charset", g.get("characterName", ""))).strip_edges(),
		"index": int(g.get("index", g.get("characterIndex", 0))),
		"direction": int(g.get("direction", 2)),
	}


static func set_page_graphic(page: Dictionary, charset: String, index: int, direction: int) -> void:
	page["graphic"] = default_graphic(charset.strip_edges(), index, direction)


static func wait_duration(cmd: Dictionary) -> float:
	return _wait_duration(cmd)


static func _wait_duration(cmd: Dictionary) -> float:
	var dur := float(cmd.get("duration", cmd.get("seconds", cmd.get("sec", 0))))
	if dur <= 0.0:
		var frames := int(cmd.get("frames", 0))
		if frames > 0:
			dur = float(frames) / 60.0
	if dur <= 0.0:
		dur = 0.5
	return dur


static func default_page() -> Dictionary:
	return {
		"when": {},
		"trigger": "action",
		"graphic": default_graphic(),
		"commands": [{"op": "text", "text": "……"}],
	}


static func make_event(cell: Vector2i, text: String = "……") -> Dictionary:
	return {
		"id": "ev_%d_%d" % [cell.x, cell.y],
		"cell": {"x": cell.x, "y": cell.y},
		"trigger": "action",
		"through": true,
		"pages": [{
			"when": {},
			"graphic": default_graphic(),
			"commands": [{"op": "text", "text": text if text != "" else "……"}],
		}],
	}


static func make_chest(cell: Vector2i, item_id: String = "potion_hp_small", qty: int = 1, gold: int = 10) -> Dictionary:
	return {
		"id": "chest_%d_%d" % [cell.x, cell.y],
		"name": "宝箱",
		"cell": {"x": cell.x, "y": cell.y},
		"trigger": "action",
		"through": false,
		"pages": [
			{
				"when": {},
				"graphic": default_graphic("!Chest", 0, 2),
				"commands": [
					{"op": "text", "text": "打开了宝箱！"},
					{"op": "give_item", "item_id": item_id, "qty": qty},
					{"op": "give_gold", "amount": gold},
					{"op": "set_self_switch", "letter": "A", "value": true},
				],
			},
			{
				"when": {"self_switch": "A"},
				"graphic": default_graphic("!Chest", 1, 2),
				"commands": [{"op": "text", "text": "空的宝箱。"}],
			},
		],
	}


static func ensure_pages(ev: Dictionary) -> Array:
	var pages_v: Variant = ev.get("pages", [])
	var pages: Array = pages_v if typeof(pages_v) == TYPE_ARRAY else []
	if pages.is_empty():
		pages = [default_page()]
		ev["pages"] = pages
	return pages


static func page_when_label(page: Dictionary) -> String:
	var when_v: Variant = page.get("when", {})
	if typeof(when_v) != TYPE_DICTIONARY:
		return "始终"
	var when: Dictionary = when_v
	var bits: PackedStringArray = PackedStringArray()
	var ss := str(when.get("self_switch", "")).strip_edges()
	if ss != "":
		bits.append("独立%s" % ss)
	var sid := str(when.get("switch", when.get("switch_id", ""))).strip_edges()
	if sid != "":
		bits.append("开关 %s" % sid)
	var item_id := ""
	if when.has("item"):
		var iv: Variant = when.get("item")
		if typeof(iv) == TYPE_DICTIONARY:
			item_id = str(iv.get("item_id", iv.get("id", "")))
		else:
			item_id = str(iv)
	if item_id == "":
		item_id = str(when.get("item_id", "")).strip_edges()
	if item_id != "":
		bits.append("物品 %s" % item_id)
	if bits.is_empty():
		return "始终"
	return " / ".join(bits)


static func set_page_when(page: Dictionary, self_switch: String, switch_id: String, item_id: String = "") -> void:
	var when := {}
	var ss := self_switch.strip_edges()
	if ss != "" and ss != "无":
		when["self_switch"] = ss
	var sid := switch_id.strip_edges()
	if sid != "":
		when["switch"] = sid
	var iid := item_id.strip_edges()
	if iid != "":
		when["item"] = iid
	page["when"] = when


static func event_actor_data(ev: Dictionary, page: Dictionary = {}) -> Dictionary:
	var use_page: Dictionary = page
	if use_page.is_empty():
		var pages_v: Variant = ev.get("pages", [])
		if typeof(pages_v) == TYPE_ARRAY and not (pages_v as Array).is_empty():
			var p0: Variant = (pages_v as Array)[0]
			if typeof(p0) == TYPE_DICTIONARY:
				use_page = p0
	var g: Dictionary = page_graphic(use_page)
	var cell_v: Variant = ev.get("cell", {})
	var cx := 0
	var cy := 0
	if typeof(cell_v) == TYPE_DICTIONARY:
		cx = int(cell_v.get("x", 0))
		cy = int(cell_v.get("y", 0))
	return {
		"id": str(ev.get("id", "")),
		"name": str(ev.get("name", ev.get("id", "事件"))),
		"cell": {"x": cx, "y": cy},
		"charset": str(g.get("charset", "")),
		"index": int(g.get("index", 0)),
		"direction": int(g.get("direction", 2)),
		"through": bool(ev.get("through", true)),
		"kind": "object",
		"wander": false,
		"hostile": false,
	}


static func choice_labels(cmd: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var opts_v: Variant = cmd.get("options", cmd.get("choices", []))
	if typeof(opts_v) != TYPE_ARRAY:
		return out
	for ov in opts_v:
		if typeof(ov) == TYPE_DICTIONARY:
			out.append(str(ov.get("label", ov.get("text", ""))))
		else:
			out.append(str(ov))
	return out


static func set_choice_labels(cmd: Dictionary, labels: PackedStringArray) -> void:
	var prev_v: Variant = cmd.get("options", [])
	var prev: Array = prev_v if typeof(prev_v) == TYPE_ARRAY else []
	var next: Array = []
	for i in range(labels.size()):
		var lab := labels[i].strip_edges()
		if lab == "":
			continue
		var prev_cmds: Array = []
		if i < prev.size() and typeof(prev[i]) == TYPE_DICTIONARY:
			var cv: Variant = prev[i].get("commands", [])
			if typeof(cv) == TYPE_ARRAY:
				prev_cmds = cv
		next.append({"id": "opt_%d" % next.size(), "label": lab, "commands": prev_cmds})
	cmd["options"] = next


static func options_of(cmd: Dictionary) -> Array:
	var opts_v: Variant = cmd.get("options", cmd.get("choices", []))
	if typeof(opts_v) != TYPE_ARRAY:
		var empty: Array = []
		cmd["options"] = empty
		return empty
	cmd["options"] = opts_v
	return opts_v


static func add_option(cmd: Dictionary, label: String = "") -> Dictionary:
	var opts := options_of(cmd)
	var lab := label.strip_edges()
	if lab == "":
		lab = "选项 %d" % (opts.size() + 1)
	var opt := {"id": "opt_%d" % opts.size(), "label": lab, "commands": []}
	opts.append(opt)
	return opt


static func remove_option(cmd: Dictionary, idx: int) -> void:
	var opts := options_of(cmd)
	if idx < 0 or idx >= opts.size():
		return
	opts.remove_at(idx)
	for i in range(opts.size()):
		if typeof(opts[i]) == TYPE_DICTIONARY:
			opts[i]["id"] = "opt_%d" % i


static func set_option_label(cmd: Dictionary, idx: int, label: String) -> void:
	var opts := options_of(cmd)
	if idx < 0 or idx >= opts.size() or typeof(opts[idx]) != TYPE_DICTIONARY:
		return
	opts[idx]["label"] = label.strip_edges()


static func option_commands(cmd: Dictionary, idx: int) -> Array:
	var opts := options_of(cmd)
	if idx < 0 or idx >= opts.size() or typeof(opts[idx]) != TYPE_DICTIONARY:
		return []
	var cv: Variant = opts[idx].get("commands", [])
	if typeof(cv) != TYPE_ARRAY:
		cv = []
		opts[idx]["commands"] = cv
	return cv


static func summarize_option(opt: Dictionary) -> String:
	var lab := str(opt.get("label", opt.get("text", "")))
	var n := 0
	var cv: Variant = opt.get("commands", [])
	if typeof(cv) == TYPE_ARRAY:
		n = (cv as Array).size()
	if n <= 0:
		return lab
	return "%s  (%d)" % [lab, n]


static func _clip(s: String, n: int = 22) -> String:
	var t := s.replace("\n", " ").strip_edges()
	if t.length() <= n:
		return t
	return t.substr(0, n) + "…"


static func retarget_entity(kind: String, data: Dictionary, cell: Vector2i) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	match kind.strip_edges().to_lower():
		"event":
			d["cell"] = {"x": cell.x, "y": cell.y}
			d["id"] = "ev_%d_%d" % [cell.x, cell.y]
		"npc":
			d["cell"] = {"x": cell.x, "y": cell.y}
			d["id"] = "npc_%d_%d" % [cell.x, cell.y]
		"warp":
			d["from_cell"] = {"x": cell.x, "y": cell.y}
		_:
			return {}
	return d


static func walk_commands(commands: Array, cb: Callable) -> void:
	for raw in commands:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var cmd: Dictionary = raw
		cb.call(cmd)
		var op := str(cmd.get("op", cmd.get("type", ""))).strip_edges().to_lower()
		if op in ["choices", "choice", "show_choices"]:
			for opt in options_of(cmd):
				if typeof(opt) != TYPE_DICTIONARY:
					continue
				var cv: Variant = opt.get("commands", [])
				if typeof(cv) == TYPE_ARRAY:
					walk_commands(cv, cb)


static func collect_switch_ids_from_events(events: Array) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	var add := func(sid: String) -> void:
		sid = sid.strip_edges()
		if sid == "" or seen.has(sid):
			return
		seen[sid] = true
		out.append(sid)
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var pages_v: Variant = ev.get("pages", [])
		if typeof(pages_v) != TYPE_ARRAY:
			continue
		for pv in pages_v:
			if typeof(pv) != TYPE_DICTIONARY:
				continue
			var page: Dictionary = pv
			var when_v: Variant = page.get("when", {})
			if typeof(when_v) == TYPE_DICTIONARY:
				add.call(str(when_v.get("switch", when_v.get("switch_id", ""))))
			var cmds_v: Variant = page.get("commands", [])
			if typeof(cmds_v) != TYPE_ARRAY:
				continue
			walk_commands(cmds_v, func(cmd: Dictionary) -> void:
				var op := str(cmd.get("op", "")).strip_edges().to_lower()
				if op == "set_switch":
					add.call(str(cmd.get("id", cmd.get("switch", ""))))
			)
	out.sort()
	return out


static func collect_switch_ids(pack) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	if pack == null:
		return out
	var maps_v: Variant = pack.maps if "maps" in pack else {}
	if typeof(maps_v) != TYPE_DICTIONARY:
		return out
	for mid in (maps_v as Dictionary).keys():
		var doc = (maps_v as Dictionary).get(mid)
		if doc == null or not ("events" in doc):
			continue
		for sid in collect_switch_ids_from_events(doc.events):
			if seen.has(sid):
				continue
			seen[sid] = true
			out.append(sid)
	out.sort()
	return out


static func cmd_face(cmd: Dictionary) -> Dictionary:
	return {
		"id": str(cmd.get("face", cmd.get("faceName", ""))).strip_edges(),
		"index": int(cmd.get("face_index", cmd.get("faceIndex", 0))),
	}


static func set_cmd_face(cmd: Dictionary, face_id: String, face_index: int) -> void:
	cmd["face"] = face_id.strip_edges()
	cmd["face_index"] = clampi(face_index, 0, 7)
