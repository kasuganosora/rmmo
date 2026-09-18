extends SceneTree
## NPC combat fields, entity copy/paste, meta force bits, event face/switches, MCP.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	var EventCommands = load("res://scripts/editor/domain/event_commands.gd")
	var ContentPack = load("res://scripts/editor/domain/content_pack.gd")
	var MapExt = load("res://scripts/map/map_ext.gd")
	var TilemapPack = load("res://scripts/map/tilemap_pack.gd")
	var EventRuntime = load("res://scripts/net/combat/event_runtime.gd")
	var EditorMcp = load("res://scripts/editor/adapters/editor_mcp.gd")
	var Editor = load("res://scripts/editor/content_editor.gd")
	var Inspector = load("res://scripts/editor/interface/entity_inspector.gd")

	var pack = ContentPack.new()
	pack.new_blank("ed_mcp_pack", "MCP测试", 16, 16)
	failed += _expect(pack.save_dir(), "save blank")
	var doc = pack.get_map("Map001")
	var n: Dictionary = doc.add_npc(Vector2i(3, 4), "Actor1", "史莱姆")
	n["hostile"] = true
	n["aggressive"] = false
	n["kind"] = "monster"
	n["level"] = 5
	n["wander_radius"] = 3
	n["wander"] = true
	failed += _expect(pack.save_dir(), "save npc")
	failed += _expect(pack.reload_map("Map001"), "reload npc map")
	doc = pack.get_map("Map001")
	var loaded_n: Dictionary = {}
	for item in doc.npcs:
		if typeof(item) == TYPE_DICTIONARY and str(item.get("name", "")) == "史莱姆":
			loaded_n = item
	failed += _expect(not loaded_n.is_empty(), "npc survived save")
	failed += _expect(bool(loaded_n.get("hostile", false)), "npc hostile")
	failed += _expect(not bool(loaded_n.get("aggressive", true)), "npc 被动")
	failed += _expect(str(loaded_n.get("kind", "")) == "monster", "npc kind monster")
	failed += _expect(int(loaded_n.get("level", 0)) == 5, "npc level 5")
	failed += _expect(int(loaded_n.get("wander_radius", 0)) == 3, "npc wander_radius 3")
	var play = TilemapPack.load_pack(pack.root, "Map001")
	var play_n: Dictionary = {}
	for pn in play.npcs:
		if typeof(pn) == TYPE_DICTIONARY and str(pn.get("name", "")) == "史莱姆":
			play_n = pn
	failed += _expect(bool(play_n.get("hostile", false)), "play pack hostile")
	failed += _expect(int(play_n.get("wander_radius", 0)) == 3, "play pack wander_radius")
	failed += _expect(str(play_n.get("kind", "")) == "monster", "play pack kind")

	var clip: Dictionary = doc.copy_entity_at(Vector2i(3, 4))
	failed += _expect(str(clip.get("kind", "")) == "npc", "copy npc")
	failed += _expect(doc.paste_entity_at(clip, Vector2i(6, 6)), "paste npc")
	var pasted: Dictionary = doc.entity_at(Vector2i(6, 6))
	failed += _expect(str(pasted.get("kind", "")) == "npc", "pasted kind")
	var pdata: Dictionary = pasted.get("data", {})
	failed += _expect(str(pdata.get("id", "")) == "npc_6_6", "pasted new id")
	failed += _expect(bool(pdata.get("hostile", false)), "pasted hostile")
	failed += _expect(str(doc.entity_at(Vector2i(3, 4)).get("kind", "")) == "npc", "original remains")

	doc.add_event(Vector2i(1, 1), "开关测试")
	var evs: Array = doc.events
	if not evs.is_empty() and typeof(evs[0]) == TYPE_DICTIONARY:
		var pages: Array = EventCommands.ensure_pages(evs[0])
		if not pages.is_empty() and typeof(pages[0]) == TYPE_DICTIONARY:
			pages[0]["commands"] = [
				{"op": "set_switch", "id": "door_open", "value": true},
				{"op": "text", "text": "开了", "face": "Actor1", "face_index": 2},
			]
			EventCommands.set_page_when(pages[0], "无", "quest_done")
	var switches: PackedStringArray = EventCommands.collect_switch_ids(pack)
	failed += _expect(switches.find("door_open") >= 0, "collect set_switch id")
	failed += _expect(switches.find("quest_done") >= 0, "collect when switch")
	var ret: Dictionary = EventCommands.retarget_entity("event", evs[0], Vector2i(8, 8))
	failed += _expect(str(ret.get("id", "")) == "ev_8_8", "retarget event id")

	var face_cmd: Dictionary = EventCommands.default_command("text")
	EventCommands.set_cmd_face(face_cmd, "Actor1", 2)
	failed += _expect(str(face_cmd.get("face", "")) == "Actor1", "set face")
	var rt = EventRuntime.new()
	rt.load_events_array([{
		"id": "talker",
		"cell": {"x": 0, "y": 0},
		"pages": [{"commands": [face_cmd]}],
	}], "Map001")
	var acts: Array = rt.run_event("talker", {"npc_name": "向导"})
	var face_ok := false
	for a in acts:
		if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "show_npc_dialogue":
			face_ok = str(a.get("face", "")) == "Actor1" and int(a.get("face_index", -1)) == 2
	failed += _expect(face_ok, "runtime face on dialogue")

	var ed = Editor.new()
	ed.pack = pack
	ed.doc = doc
	ed.current_map_id = "Map001"
	ed._cursor = Vector2i(2, 2)
	ed._spec_kind = "meta"
	ed._spec_meta_bit = MapExt.META_FORCE_BLOCK
	ed._spec_write(Vector2i(2, 2), false)
	failed += _expect((int(doc.ext_tile("meta", 2, 2)) & MapExt.META_FORCE_BLOCK) != 0, "force block")
	ed._spec_meta_bit = MapExt.META_FORCE_PASS
	ed._spec_write(Vector2i(2, 2), false)
	var meta_v: int = int(doc.ext_tile("meta", 2, 2))
	failed += _expect((meta_v & MapExt.META_FORCE_PASS) != 0, "force pass")
	failed += _expect((meta_v & MapExt.META_FORCE_BLOCK) == 0, "pass clears block")
	ed._spec_write(Vector2i(2, 2), true)
	failed += _expect((int(doc.ext_tile("meta", 2, 2)) & MapExt.META_FORCE_PASS) == 0, "erase pass")

	var ins = Inspector.new()
	root.add_child(ins)
	ins.bind_pack(pack)
	ins.load_cell(doc, Vector2i(3, 4))
	failed += _expect(ins._hostile != null and ins._hostile.button_pressed, "inspector hostile")
	failed += _expect(ins._npc_kind != null and str(ins._npc_kind.get_item_metadata(ins._npc_kind.selected)) == "monster", "inspector kind monster")
	failed += _expect(ins._level != null and int(ins._level.value) == 5, "inspector level")
	failed += _expect(ins._wander_r != null and int(ins._wander_r.value) == 3, "inspector radius")
	failed += _expect(ins._p_map_opt != null and ins._p_map_opt.item_count > 0, "transfer map dropdown")
	failed += _expect(ins._p_face_opt != null, "face dropdown")
	failed += _expect(ins._p_switch_opt != null and ins._p_switch_opt.item_count >= 1, "switch dropdown")
	failed += _expect(ins._p_audio_opt != null, "audio dropdown")
	ins.load_cell(doc, Vector2i(9, 9))
	ins._kind.select(1)
	ins._sync_kind()
	ins._name.text = "村民"
	ins._charset.text = "Actor1"
	ins._hostile.button_pressed = false
	ins._select_npc_kind("normal")
	ins._apply()
	var vill: Dictionary = doc.entity_at(Vector2i(9, 9))
	failed += _expect(str(vill.get("kind", "")) == "npc", "wrote villager")
	failed += _expect(not bool(vill.get("data", {}).get("hostile", true)), "villager not hostile")
	ins.queue_free()

	var mcp = EditorMcp.new()
	root.add_child(mcp)
	mcp.editor = ed
	var init: Variant = mcp.handle_rpc({
		"jsonrpc": "2.0",
		"id": 1,
		"method": "initialize",
		"params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}},
	})
	failed += _expect(typeof(init) == TYPE_DICTIONARY, "initialize dict")
	failed += _expect(str((init as Dictionary).get("result", {}).get("serverInfo", {}).get("name", "")) == "rmmo-editor", "server name")
	var listed: Variant = mcp.handle_rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
	var tools: Array = (listed as Dictionary).get("result", {}).get("tools", []) if typeof(listed) == TYPE_DICTIONARY else []
	var names := PackedStringArray()
	for t in tools:
		if typeof(t) == TYPE_DICTIONARY:
			names.append(str(t.get("name", "")))
	failed += _expect(names.find("place_npc") >= 0, "tool place_npc")
	failed += _expect(names.find("set_meta") >= 0, "tool set_meta")
	failed += _expect(names.find("save") >= 0, "tool save")
	failed += _expect(names.find("preview_map") >= 0, "tool preview_map")
	var placed: Dictionary = mcp.call_tool("place_npc", {
		"x": 7, "y": 7, "name": "狼", "charset": "Actor1",
		"hostile": true, "aggressive": true, "kind": "monster", "level": 4, "wander_radius": 2,
	})
	failed += _expect(bool(placed.get("ok", false)), "mcp place_npc ok")
	var wolf: Dictionary = doc.entity_at(Vector2i(7, 7))
	failed += _expect(str(wolf.get("kind", "")) == "npc", "mcp npc on map")
	failed += _expect(bool(wolf.get("data", {}).get("aggressive", false)), "mcp aggressive")
	var meta_r: Dictionary = mcp.call_tool("set_meta", {"x": 1, "y": 1, "bit": MapExt.META_FORCE_BLOCK})
	failed += _expect(bool(meta_r.get("ok", false)), "mcp set_meta")
	failed += _expect((int(doc.ext_tile("meta", 1, 1)) & MapExt.META_FORCE_BLOCK) != 0, "mcp force block cell")
	var evp: Dictionary = mcp.call_tool("place_event", {
		"x": 0, "y": 1, "text": "MCP 对话", "face": "Actor1", "face_index": 1,
	})
	failed += _expect(bool(evp.get("ok", false)), "mcp place_event")
	var copied: Dictionary = mcp.call_tool("copy_entity", {"x": 7, "y": 7})
	failed += _expect(bool(copied.get("ok", false)), "mcp copy")
	var pasted2: Dictionary = mcp.call_tool("paste_entity", {"x": 7, "y": 8})
	failed += _expect(bool(pasted2.get("ok", false)), "mcp paste")
	failed += _expect(str(doc.entity_at(Vector2i(7, 8)).get("kind", "")) == "npc", "mcp pasted npc")
	var prev: Dictionary = mcp.call_tool("preview_map", {
		"x": 6, "y": 6, "w": 4, "h": 4, "grid": true, "entities": true, "max_px": 512,
	})
	failed += _expect(bool(prev.get("ok", false)), "mcp preview_map ok")
	failed += _expect(int(prev.get("w", 0)) == 4, "preview width 4")
	failed += _expect(int(prev.get("h", 0)) == 4, "preview height 4")
	failed += _expect(str(prev.get("png_base64", "")).length() > 80, "preview png bytes")
	failed += _expect(int(prev.get("px_w", 0)) > 0 and int(prev.get("px_h", 0)) > 0, "preview pixels")
	var found_wolf := false
	for ent in prev.get("entities", []):
		if typeof(ent) == TYPE_DICTIONARY and str(ent.get("kind", "")) == "npc" and int(ent.get("x", -1)) == 7:
			found_wolf = true
	failed += _expect(found_wolf, "preview lists npc in range")
	var prev_path := str(prev.get("path", ""))
	if prev_path != "" and FileAccess.file_exists(prev_path):
		var shot := Image.new()
		failed += _expect(shot.load(prev_path) == OK, "preview png load")
		var mark: Color = shot.get_pixel(mini(shot.get_width() - 1, 72), mini(shot.get_height() - 1, 72))
		failed += _expect(mark.r > 0.15 or mark.g > 0.15 or mark.b > 0.15, "preview npc pixels")
	else:
		failed += _expect(false, "preview png path exists")
	var rpc_prev: Variant = mcp.handle_rpc({
		"jsonrpc": "2.0",
		"id": 4,
		"method": "tools/call",
		"params": {"name": "preview_map", "arguments": {"x": 7, "y": 7, "w": 2, "h": 2, "grid": false}},
	})
	var rpc_content: Array = []
	if typeof(rpc_prev) == TYPE_DICTIONARY:
		rpc_content = (rpc_prev as Dictionary).get("result", {}).get("content", [])
	var has_img := false
	for block in rpc_content:
		if typeof(block) == TYPE_DICTIONARY and str(block.get("type", "")) == "image":
			has_img = str(block.get("mimeType", "")) == "image/png" and str(block.get("data", "")).length() > 80
	failed += _expect(has_img, "rpc preview image content")

	var info: Dictionary = mcp.start(18765)
	failed += _expect(bool(info.get("ok", false)), "mcp listen")
	if bool(info.get("ok", false)):
		var body := JSON.stringify({
			"jsonrpc": "2.0",
			"id": 9,
			"method": "tools/call",
			"params": {"name": "editor_state", "arguments": {}},
		})
		var raw := body.to_utf8_buffer()
		var req := "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % raw.size()
		var client := StreamPeerTCP.new()
		client.connect_to_host("127.0.0.1", int(info.get("port", 18765)))
		var connected := false
		for _i in range(40):
			client.poll()
			mcp._process(0.0)
			if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				connected = true
				break
			OS.delay_msec(15)
		failed += _expect(connected, "tcp connected")
		if connected:
			client.put_data(req.to_utf8_buffer())
			client.put_data(raw)
			var got := PackedByteArray()
			for _j in range(40):
				mcp._process(0.0)
				client.poll()
				if client.get_available_bytes() > 0:
					var chunk: Array = client.get_partial_data(client.get_available_bytes())
					if chunk.size() >= 2 and int(chunk[0]) == OK:
						got.append_array(chunk[1])
					var txt := got.get_string_from_utf8()
					if txt.find("\r\n\r\n") >= 0 and txt.find("editor_state") < 0:
						# wait for body
						pass
					if txt.find("pack_id") >= 0:
						break
				OS.delay_msec(15)
			var resp := got.get_string_from_utf8()
			failed += _expect(resp.find("200") >= 0 or resp.find("pack_id") >= 0, "http 200 or pack_id")
			failed += _expect(resp.find("ed_mcp_pack") >= 0 or resp.find("pack_id") >= 0, "http state body")
		client.disconnect_from_host()
	mcp.stop()
	mcp.queue_free()
	ed.free()

	if failed == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILED %d" % failed)
		quit(1)


func _expect(cond: bool, label: String) -> int:
	if cond:
		print("PASS %s" % label)
		return 0
	print("FAIL %s" % label)
	return 1
