extends SceneTree
## Event command helpers, chest pages, copy/paste, discard-reload.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var EventCommands = load("res://scripts/editor/domain/event_commands.gd")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var PaintTools = load("res://scripts/editor/domain/paint_tools.gd")
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")
	var Inventory = load("res://scripts/net/combat/inventory.gd")
	var ItemCatalog = load("res://scripts/net/combat/item_catalog.gd")

	failed += _expect(str(EventCommands.op_label("give_item")) == "给物品", "op_label give_item")
	failed += _expect(str(EventCommands.op_label("wait")) == "等待", "op_label wait")
	failed += _expect(EventCommands.normalize_trigger("自动执行") == "autorun", "normalize autorun")
	failed += _expect(EventCommands.normalize_trigger("事件接触") == "event_touch", "normalize event_touch")
	failed += _expect(str(EventCommands.trigger_label("autorun")) == "自动执行", "trigger_label autorun")
	failed += _expect(str(EventCommands.trigger_label("event_touch")) == "事件接触", "trigger_label event_touch")
	var wcmd: Dictionary = EventCommands.default_command("wait")
	failed += _expect(str(wcmd.get("op", "")) == "wait", "default wait op")
	failed += _expect(float(wcmd.get("duration", 0)) > 0.0, "default wait duration > 0")
	failed += _expect(str(EventCommands.summarize(wcmd)).begins_with("等待"), "summarize wait")
	var txt: Dictionary = EventCommands.default_command("text")
	failed += _expect(str(txt.get("op", "")) == "text", "default text op")
	failed += _expect(str(EventCommands.summarize(txt)).begins_with("对话"), "summarize text")
	var chest: Dictionary = EventCommands.make_chest(Vector2i(3, 4), "potion_hp_small", 2, 20)
	failed += _expect(str(chest.get("id", "")).begins_with("chest_"), "chest id")
	var pages: Array = EventCommands.ensure_pages(chest)
	failed += _expect(pages.size() == 2, "chest two pages")
	failed += _expect(EventCommands.page_when_label(pages[1]).find("独立") >= 0, "page 2 self switch")
	var when_probe: Dictionary = EventCommands.default_page()
	EventCommands.set_page_when(when_probe, "B", "door_open")
	failed += _expect(str((when_probe.get("when", {}) as Dictionary).get("self_switch", "")) == "B", "set self_switch")
	failed += _expect(str((when_probe.get("when", {}) as Dictionary).get("switch", "")) == "door_open", "set switch")
	var ch: Dictionary = EventCommands.default_command("choices")
	EventCommands.set_choice_labels(ch, PackedStringArray(["好", "不好", ""]))
	failed += _expect(EventCommands.choice_labels(ch).size() == 2, "choice labels drop empty")

	var pack = ContentPack.new()
	pack.new_blank("evt_ed_pack", "事件编辑测试", 16, 16)
	failed += _expect(pack.save_dir(), "save blank pack")
	var hall_ok: bool = pack.add_map("Hall", "大厅", "Map001", 12, 12)
	failed += _expect(hall_ok, "add Hall")
	var doc = pack.get_map("Map001")
	doc.set_tile(2, 2, 0, 2816)
	doc.set_tile(3, 2, 0, 2816)
	doc.set_tile(4, 2, 0, 2816)
	if doc.has_method("remove_entity_at"):
		doc.add_event(Vector2i(1, 1), "旧对话")
		failed += _expect(doc.remove_entity_at(Vector2i(1, 1)), "remove_entity_at")
		failed += _expect(doc.entity_at(Vector2i(1, 1)).is_empty(), "cell empty after remove")
	doc.events.append(chest)
	chest["cell"] = {"x": 5, "y": 5}
	doc.dirty = true
	failed += _expect(pack.save_dir(), "save with chest")

	var paint = PaintTools.new()
	paint.layer_z = 0
	var clip: Dictionary = paint.copy_rect(doc, Vector2i(2, 2), Vector2i(4, 2))
	failed += _expect(int(clip.get("w", 0)) == 3, "copy width 3")
	failed += _expect(int(clip.get("h", 0)) == 1, "copy height 1")
	var pasted: Array = paint.paste_at(doc, Vector2i(2, 6))
	failed += _expect(pasted.size() == 3, "paste 3 cells")
	failed += _expect(int(doc.tile(2, 6, 0)) == 2816, "pasted tile")
	failed += _expect(int(doc.tile(4, 6, 0)) == 2816, "pasted tile end")
	var cut: Array = paint.cut_rect(doc, Vector2i(2, 6), Vector2i(4, 6))
	failed += _expect(int(doc.tile(2, 6, 0)) == 0, "cut clears")
	failed += _expect(cut.size() >= 3, "cut dirty")
	failed += _expect(int(paint.clipboard.get("w", 0)) == 3, "cut keeps clipboard")

	doc.set_tile(8, 8, 0, 2816)
	failed += _expect(pack.save_dir(), "save before dirty")
	doc.set_tile(8, 8, 0, 0)
	failed += _expect(bool(doc.dirty), "dirty after edit")
	failed += _expect(pack.reload_map("Map001"), "reload_map")
	var doc2 = pack.get_map("Map001")
	failed += _expect(int(doc2.tile(8, 8, 0)) == 2816, "discard restored tile")
	failed += _expect(not bool(doc2.dirty), "clean after reload")
	failed += _expect(not doc2.events.is_empty(), "chest survived reload")

	var rt = EventRuntime.new()
	rt.load_events_array(doc2.events, "Map001")
	var cid := str(chest.get("id", ""))
	failed += _expect(rt.has_event(cid), "runtime has chest")
	var cat = ItemCatalog.new()
	cat.load_catalog()
	var inv = Inventory.new()
	inv.set_catalog(cat)
	inv.clear()
	inv.grant_starter()
	var pot0: int = inv.get_qty("potion_hp_small")
	var gold0: int = inv.get_gold()
	var acts: Array = rt.run_event(cid, {"inventory": inv, "npc_name": "宝箱"})
	failed += _expect(not acts.is_empty(), "chest run actions")
	failed += _expect(inv.get_qty("potion_hp_small") == pot0 + 2, "chest +2 potions")
	failed += _expect(inv.get_gold() == gold0 + 20, "chest +20 gold")
	failed += _expect(rt.get_self_switch(cid, "A"), "self switch A")
	var acts2: Array = rt.run_event(cid, {"inventory": inv, "npc_name": "宝箱"})
	var empty_ok := false
	for a in acts2:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("body", "")).find("空的宝箱") >= 0:
			empty_ok = true
	failed += _expect(empty_ok, "empty chest page")
	failed += _expect(inv.get_qty("potion_hp_small") == pot0 + 2, "no double loot")

	var ev: Dictionary = EventCommands.make_event(Vector2i(1, 2), "你好")
	var ev_pages: Array = EventCommands.ensure_pages(ev)
	ev_pages[0]["commands"] = [
		EventCommands.default_command("text"),
		EventCommands.default_command("give_gold"),
		EventCommands.default_command("set_switch"),
		EventCommands.default_command("open_shop"),
		EventCommands.default_command("transfer"),
	]
	(ev_pages[0]["commands"][0] as Dictionary)["text"] = "欢迎"
	(ev_pages[0]["commands"][1] as Dictionary)["amount"] = 7
	(ev_pages[0]["commands"][2] as Dictionary)["id"] = "met_guide"
	(ev_pages[0]["commands"][4] as Dictionary)["to_map"] = "Hall"
	(ev_pages[0]["commands"][4] as Dictionary)["to_cell"] = {"x": 2, "y": 3}
	doc2.events.append(ev)
	var rt2 = EventRuntime.new()
	rt2.load_events_array(doc2.events, "Map001")
	var acts3: Array = rt2.run_event(str(ev.get("id", "")), {
		"inventory": inv,
		"npc_name": "向导",
	})
	failed += _expect(rt2.get_switch("met_guide"), "set_switch from editor event")
	var xfer_map := ""
	for a4 in acts3:
		if typeof(a4) == TYPE_DICTIONARY and str(a4.get("type", "")) == "map_transfer":
			xfer_map = str(a4.get("map_id", ""))
	failed += _expect(xfer_map == "Hall", "transfer to Hall")
	var has_welcome := false
	for a3 in acts3:
		if typeof(a3) == TYPE_DICTIONARY and str(a3.get("body", "")).find("欢迎") >= 0:
			has_welcome = true
	failed += _expect(has_welcome, "welcome text")

	var g0: Dictionary = EventCommands.page_graphic(pages[0])
	failed += _expect(str(g0.get("charset", "")) == "!Chest", "chest closed graphic")
	var g1: Dictionary = EventCommands.page_graphic(pages[1])
	failed += _expect(int(g1.get("index", -1)) == 1, "chest open index")
	var actor: Dictionary = EventCommands.event_actor_data(chest, pages[0])
	failed += _expect(str(actor.get("kind", "")) == "object", "chest actor object")
	failed += _expect(str(actor.get("charset", "")) == "!Chest", "chest actor charset")
	var gfx := false
	for ag in acts:
		if typeof(ag) == TYPE_DICTIONARY and str(ag.get("type", "")) == "event_graphic":
			gfx = str(ag.get("charset", "")) == "!Chest" and int(ag.get("index", -1)) == 1
	failed += _expect(gfx, "self-switch emits open-chest graphic")
	var se: Dictionary = EventCommands.default_command("play_se")
	failed += _expect(str(se.get("op", "")) == "play_se", "play_se op")
	var audio_ev := {"id": "se1", "cell": {"x": 0, "y": 0}, "pages": [{"when": {}, "commands": [{"op": "play_bgm", "id": "Theme1"}]}]}
	var rt3 = EventRuntime.new()
	rt3.load_events_array([audio_ev], "Map001")
	var aacts: Array = rt3.run_event("se1", {})
	var has_bgm := false
	for aa in aacts:
		if typeof(aa) == TYPE_DICTIONARY and str(aa.get("type", "")) == "play_audio" and str(aa.get("channel", "")) == "bgm":
			has_bgm = str(aa.get("id", "")) == "Theme1"
	failed += _expect(has_bgm, "play_bgm action")
	var item_page: Dictionary = EventCommands.default_page()
	EventCommands.set_page_when(item_page, "无", "", "potion_hp_small")
	failed += _expect(EventCommands.page_when_label(item_page).find("物品") >= 0, "item when label")

	# --- inspector trigger labels + pack round-trip ---
	var Inspector = load("res://scripts/editor/interface/entity_inspector.gd")
	var ins = Inspector.new()
	root.add_child(ins)
	var trig_labels: PackedStringArray = PackedStringArray()
	if ins._trigger != null:
		for ti in range(ins._trigger.item_count):
			trig_labels.append(ins._trigger.get_item_text(ti))
	failed += _expect(trig_labels.find("确定键") >= 0, "inspector 确定键")
	failed += _expect(trig_labels.find("接触") >= 0, "inspector 接触")
	failed += _expect(trig_labels.find("事件接触") >= 0, "inspector 事件接触")
	failed += _expect(trig_labels.find("自动执行") >= 0, "inspector 自动执行")
	var add_ops: PackedStringArray = PackedStringArray()
	if ins._add_op != null:
		for oi in range(ins._add_op.item_count):
			add_ops.append(ins._add_op.get_item_text(oi))
	failed += _expect(add_ops.find("等待") >= 0, "inspector 等待 op")

	var tpack = ContentPack.new()
	tpack.new_blank("evt_trig_pack", "触发测试", 16, 16)
	failed += _expect(tpack.save_dir(), "save trig pack blank")
	var tdoc = tpack.get_map("Map001")
	ins.bind_pack(tpack)
	ins.load_cell(tdoc, Vector2i(2, 2))
	ins._kind.select(0)
	ins._sync_kind()
	ins._id.text = "auto_ev"
	EventCommands.select_trigger_option(ins._trigger, "autorun")
	ins._through.button_pressed = true
	ins._apply()
	ins.load_cell(tdoc, Vector2i(4, 4))
	ins._kind.select(0)
	ins._sync_kind()
	ins._id.text = "bump_ev"
	EventCommands.select_trigger_option(ins._trigger, "event_touch")
	ins._through.button_pressed = true
	ins._apply()
	failed += _expect(tpack.save_dir(), "save trig events")
	failed += _expect(tpack.reload_map("Map001"), "reload trig map")
	var tdoc2 = tpack.get_map("Map001")
	var got_auto := ""
	var got_bump := ""
	for tev in tdoc2.events:
		if typeof(tev) != TYPE_DICTIONARY:
			continue
		var tid := str(tev.get("id", ""))
		if tid == "auto_ev":
			got_auto = str(tev.get("trigger", ""))
			var tpages: Array = EventCommands.ensure_pages(tev)
			if not tpages.is_empty() and typeof(tpages[0]) == TYPE_DICTIONARY:
				var pt := str(tpages[0].get("trigger", ""))
				if pt != "":
					got_auto = pt if got_auto == "" else got_auto
		elif tid == "bump_ev":
			got_bump = str(tev.get("trigger", ""))
	failed += _expect(got_auto == "autorun", "pack roundtrip autorun")
	failed += _expect(got_bump == "event_touch", "pack roundtrip event_touch")
	ins.queue_free()

	# --- autorun collect: run once, self-switch stops later collect, no infinite loop ---
	var auto_ev := {
		"id": "intro",
		"cell": {"x": 1, "y": 1},
		"trigger": "autorun",
		"through": true,
		"pages": [
			{
				"when": {},
				"trigger": "autorun",
				"commands": [
					{"op": "text", "text": "开场白"},
					{"op": "set_self_switch", "letter": "A", "value": true},
				],
			},
			{
				"when": {"self_switch": "A"},
				"trigger": "action",
				"commands": [{"op": "text", "text": "已经介绍过了。"}],
			},
		],
	}
	var spin_ev := {
		"id": "spin",
		"cell": {"x": 2, "y": 2},
		"trigger": "autorun",
		"through": true,
		"pages": [{
			"when": {},
			"trigger": "autorun",
			"commands": [{"op": "give_gold", "amount": 3}],
		}],
	}
	var rt_auto = EventRuntime.new()
	rt_auto.load_events_array([auto_ev, spin_ev], "Map001")
	var gold_spin0: int = inv.get_gold()
	var auto1: Array = rt_auto.collect_autorun({"inventory": inv, "npc_name": "旁白"})
	var intro_txt := false
	for aa in auto1:
		if typeof(aa) == TYPE_DICTIONARY and str(aa.get("body", "")).find("开场白") >= 0:
			intro_txt = true
	failed += _expect(intro_txt, "autorun collect runs first page")
	failed += _expect(rt_auto.get_self_switch("intro", "A"), "autorun set self A")
	failed += _expect(inv.get_gold() == gold_spin0 + 3, "autorun collect gold once")
	var auto2: Array = rt_auto.collect_autorun({"inventory": inv, "npc_name": "旁白"})
	var intro_again := false
	for aa2 in auto2:
		if typeof(aa2) == TYPE_DICTIONARY and str(aa2.get("body", "")).find("开场白") >= 0:
			intro_again = true
	failed += _expect(not intro_again, "later collect does not re-run first autorun page")
	failed += _expect(inv.get_gold() == gold_spin0 + 6, "second collect spin gold +3 not loop")

	# --- wait op order + play path delays later batch actions ---
	var wait_ev := {
		"id": "waiter",
		"cell": {"x": 0, "y": 0},
		"trigger": "action",
		"pages": [{
			"when": {},
			"commands": [
				{"op": "text", "text": "先说"},
				{"op": "wait", "duration": 0.4},
				{"op": "play_se", "id": "Bell1"},
				{"op": "text", "text": "后说"},
			],
		}],
	}
	var rt_wait = EventRuntime.new()
	rt_wait.load_events_array([wait_ev], "Map001")
	var wacts: Array = rt_wait.run_event("waiter", {"npc_name": "钟"})
	failed += _expect(wacts.size() >= 3, "wait batch size")
	var wait_idx := -1
	var se_idx := -1
	var later_idx := -1
	var wait_dur := 0.0
	for wi in range(wacts.size()):
		if typeof(wacts[wi]) != TYPE_DICTIONARY:
			continue
		var wt := str(wacts[wi].get("type", ""))
		if wt == "wait" and wait_idx < 0:
			wait_idx = wi
			wait_dur = float(wacts[wi].get("duration", 0))
		elif wt == "play_audio" and se_idx < 0:
			se_idx = wi
		elif wt == "show_npc_dialogue" and str(wacts[wi].get("body", "")).find("后说") >= 0:
			later_idx = wi
	failed += _expect(wait_idx > 0, "wait after first text")
	failed += _expect(wait_dur > 0.0, "wait duration positive")
	failed += _expect(se_idx > wait_idx, "play_se after wait")
	failed += _expect(later_idx > wait_idx, "later text after wait")
	var WorldSc = load("res://scripts/game/world.gd")
	var world = WorldSc.new()
	world._apply_server_actions(wacts)
	var applied1: Array = world.last_applied_action_types.duplicate()
	failed += _expect(applied1.find("show_npc_dialogue") >= 0, "play applied first text")
	failed += _expect(applied1.find("wait") >= 0, "play consumed wait")
	failed += _expect(applied1.find("play_audio") < 0, "play did not apply later audio same instant")
	world.tick_event_wait(0.1)
	failed += _expect(world.last_applied_action_types.find("play_audio") < 0, "wait not elapsed yet")
	world.tick_event_wait(0.5)
	failed += _expect(world.last_applied_action_types.find("play_audio") >= 0, "later audio after wait")
	world.free()

	# --- MockServer play-load autorun + event_touch occupancy ---
	var srv = root.get_node_or_null("MockServer")
	failed += _expect(srv != null, "MockServer autoload")
	if srv != null:
		var bump_ev := {
			"id": "bumper",
			"cell": {"x": 3, "y": 3},
			"trigger": "event_touch",
			"through": true,
			"pages": [{
				"when": {},
				"trigger": "event_touch",
				"commands": [{"op": "text", "text": "撞到了！"}, {"op": "set_self_switch", "letter": "A", "value": true}],
			}, {
				"when": {"self_switch": "A"},
				"trigger": "action",
				"commands": [{"op": "text", "text": "已经撞过。"}],
			}],
		}
		var load_auto := {
			"id": "boot",
			"cell": {"x": 1, "y": 1},
			"trigger": "autorun",
			"through": true,
			"pages": [{
				"when": {},
				"trigger": "autorun",
				"commands": [
					{"op": "text", "text": "地图载入自动执行"},
					{"op": "set_self_switch", "letter": "A", "value": true},
				],
			}, {
				"when": {"self_switch": "A"},
				"trigger": "action",
				"commands": [{"op": "text", "text": "载入后页"}],
			}],
		}
		var touch_mat := {
			"id": "walk_mat",
			"cell": {"x": 6, "y": 6},
			"trigger": "player_touch",
			"through": true,
			"pages": [{
				"when": {},
				"trigger": "player_touch",
				"commands": [{"op": "system", "text": "踩到地毯"}],
			}],
		}
		tdoc2.events = [load_auto, bump_ev, touch_mat]
		tdoc2.dirty = true
		failed += _expect(tpack.save_dir(), "save play pack")
		var pack_path := str(tpack.root)
		if srv.event_runtime == null and srv.has_method("_init_combat_layers"):
			srv._init_combat_layers()
		if srv.event_runtime != null:
			srv.event_runtime.clear_session()
		var loaded: bool = srv.load_world_pack(pack_path, "Map001", Vector2i(3, 4))
		failed += _expect(loaded, "load_world_pack trig pack")
		var boot_acts: Array = srv.poll_combat_tick()
		var boot_txt := false
		for ba in boot_acts:
			if typeof(ba) == TYPE_DICTIONARY and str(ba.get("body", "")).find("地图载入自动执行") >= 0:
				boot_txt = true
		failed += _expect(boot_txt, "play pack-load autorun actions")
		failed += _expect(srv.event_runtime.get_self_switch("boot", "A"), "boot self A after load")
		var boot2: Array = srv.collect_autorun()
		var boot_again := false
		for b2 in boot2:
			if typeof(b2) == TYPE_DICTIONARY and str(b2.get("body", "")).find("地图载入自动执行") >= 0:
				boot_again = true
		failed += _expect(not boot_again, "pack-load later collect skips first autorun page")

		if srv.combat_stats == null:
			srv._init_combat_layers()
		srv.set_player_cell(3, 4)
		srv.register_npc("bumper", 3, 3, false, false, 2, 0, 0, {"id": "bumper", "name": "撞人", "through": true})
		var nm: Dictionary = srv.try_npc_move("bumper", 3, 3, 2)
		failed += _expect(bool(nm.get("ok", false)), "event_touch npc occupies player cell")
		var nacts: Array = nm.get("actions", [])
		var bump_txt := false
		for na in nacts:
			if typeof(na) == TYPE_DICTIONARY and str(na.get("body", "")).find("撞到了") >= 0:
				bump_txt = true
		failed += _expect(bump_txt, "event_touch fires on npc step")
		failed += _expect(srv.event_runtime.get_self_switch("bumper", "A"), "bumper self A")

		# Walking the player onto an event_touch event must not fire it.
		srv.event_runtime.set_self_switch("bumper", "A", false)
		srv.set_player_cell(4, 3)
		var walk_bump: Dictionary = srv.try_move(4, 3, 4)
		var walk_bump_txt := false
		for wa in walk_bump.get("actions", []):
			if typeof(wa) == TYPE_DICTIONARY and str(wa.get("body", "")).find("撞到了") >= 0:
				walk_bump_txt = true
		failed += _expect(not walk_bump_txt, "player walk-on does not fire event_touch")

		srv.set_player_cell(6, 7)
		var walk_mat: Dictionary = srv.try_move(6, 7, 8)
		var mat_txt := false
		for ma in walk_mat.get("actions", []):
			if typeof(ma) == TYPE_DICTIONARY and str(ma.get("text", ma.get("body", ""))).find("踩到地毯") >= 0:
				mat_txt = true
		failed += _expect(mat_txt, "player_touch still fires on walk-on")

		# set_switch-only event_touch still occupies (empty action list is not a reject).
		var silent_ev := {
			"id": "silent_bump",
			"cell": {"x": 8, "y": 8},
			"trigger": "event_touch",
			"through": true,
			"pages": [{
				"when": {},
				"trigger": "event_touch",
				"commands": [{"op": "set_switch", "id": "bumped_silent", "value": true}],
			}],
		}
		tdoc2.events.append(silent_ev)
		tdoc2.dirty = true
		failed += _expect(tpack.save_dir(), "save silent bump")
		failed += _expect(bool(srv.load_world_pack(pack_path, "Map001", Vector2i(8, 9))), "reload with silent bump")
		srv.set_player_cell(8, 9)
		srv.register_npc("silent_bump", 8, 8, false, false, 2, 0, 0, {"id": "silent_bump", "through": true})
		var sm: Dictionary = srv.try_npc_move("silent_bump", 8, 8, 2)
		failed += _expect(bool(sm.get("ok", false)), "set_switch-only event_touch occupies")
		failed += _expect(int(sm.get("x", -1)) == 8 and int(sm.get("y", -1)) == 9, "silent bump cell is player cell")
		failed += _expect(srv.event_runtime.get_switch("bumped_silent"), "silent bump set_switch")

		# Transfer must not collect autorun; Loading's load_world_pack is the single collect.
		failed += _expect(tpack.add_map("Room", "房间", "Map001", 12, 12), "add Room")
		var hall = tpack.get_map("Map001")
		hall.add_warp(Vector2i(2, 2), "Room", Vector2i(4, 4), 2)
		var room = tpack.get_map("Room")
		room.events = [{
			"id": "room_boot",
			"cell": {"x": 4, "y": 4},
			"trigger": "autorun",
			"through": true,
			"pages": [
				{
					"when": {},
					"trigger": "autorun",
					"commands": [
						{"op": "text", "text": "房间过场"},
						{"op": "give_gold", "amount": 17},
						{"op": "set_self_switch", "letter": "A", "value": true},
					],
				},
				{
					"when": {"self_switch": "A"},
					"trigger": "action",
					"commands": [{"op": "text", "text": "房间已介绍"}],
				},
			],
		}]
		room.dirty = true
		hall.dirty = true
		failed += _expect(tpack.save_dir(), "save Room autorun")
		srv.event_runtime.clear_session()
		failed += _expect(bool(srv.load_world_pack(pack_path, "Map001", Vector2i(2, 2))), "load hall")
		srv.poll_combat_tick()
		var gold_hall: int = srv.inventory.get_gold() if srv.inventory != null else 0
		var tr: Dictionary = srv.try_transfer(2, 2)
		failed += _expect(bool(tr.get("ok", false)), "try_transfer to Room")
		var gold_after_xfer: int = srv.inventory.get_gold() if srv.inventory != null else 0
		failed += _expect(gold_after_xfer == gold_hall, "try_transfer does not collect autorun gold")
		failed += _expect(not srv.event_runtime.get_self_switch("room_boot", "A"), "try_transfer does not set room self A")
		var pending_xfer: Array = srv.poll_combat_tick()
		var xfer_boot := false
		for px in pending_xfer:
			if typeof(px) == TYPE_DICTIONARY and str(px.get("body", "")).find("房间过场") >= 0:
				xfer_boot = true
		failed += _expect(not xfer_boot, "try_transfer pending has no room autorun")
		failed += _expect(bool(srv.load_world_pack(pack_path, "Room", Vector2i(4, 4))), "Loading load_world_pack Room")
		var gold_room: int = srv.inventory.get_gold() if srv.inventory != null else 0
		failed += _expect(gold_room == gold_hall + 17, "single load_world_pack autorun gold once")
		failed += _expect(srv.event_runtime.get_self_switch("room_boot", "A"), "room self A after load_world_pack")
		var room_boot_txt := false
		for ra in srv.poll_combat_tick():
			if typeof(ra) == TYPE_DICTIONARY and str(ra.get("body", "")).find("房间过场") >= 0:
				room_boot_txt = true
		failed += _expect(room_boot_txt, "load_world_pack emits room autorun dialogue")
		failed += _expect(bool(srv.load_world_pack(pack_path, "Room", Vector2i(4, 4))), "second load_world_pack Room")
		var gold_room2: int = srv.inventory.get_gold() if srv.inventory != null else 0
		failed += _expect(gold_room2 == gold_room, "second load_world_pack does not double gold")
		var room_boot_again := false
		for ra2 in srv.poll_combat_tick():
			if typeof(ra2) == TYPE_DICTIONARY and str(ra2.get("body", "")).find("房间过场") >= 0:
				room_boot_again = true
		failed += _expect(not room_boot_again, "second load_world_pack skips first autorun page")

		srv.event_runtime.clear_session()
		failed += _expect(bool(srv.load_world_pack(pack_path, "Map001", Vector2i(2, 2))), "reload hall for event transfer")
		srv.poll_combat_tick()
		var gold_ev: int = srv.inventory.get_gold() if srv.inventory != null else 0
		var ev_tr: Dictionary = srv._event_perform_transfer("", {"x": 4, "y": 4}, 2, "", "Room")
		failed += _expect(bool(ev_tr.get("ok", false)), "event transfer to Room")
		var gold_ev_xfer: int = srv.inventory.get_gold() if srv.inventory != null else 0
		failed += _expect(gold_ev_xfer == gold_ev, "event transfer does not collect autorun gold")
		failed += _expect(not srv.event_runtime.get_self_switch("room_boot", "A"), "event transfer does not set room self A")
		failed += _expect(bool(srv.load_world_pack(pack_path, "Room", Vector2i(4, 4))), "Loading after event transfer")
		var gold_ev_load: int = srv.inventory.get_gold() if srv.inventory != null else 0
		failed += _expect(gold_ev_load == gold_ev + 17, "event-transfer then load_world_pack gold once")
		failed += _expect(srv.event_runtime.get_self_switch("room_boot", "A"), "room self A after event-transfer load")

	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED count=", failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS ", label)
		return 0
	print("FAIL ", label)
	return 1
