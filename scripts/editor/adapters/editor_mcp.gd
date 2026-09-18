extends Node
## Content-editor MCP: JSON-RPC 2.0 over HTTP. Off until 工具菜单 enables it.

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 18765
const PROTOCOL := "2025-03-26"
const SERVER_NAME := "rmmo-editor"
const MAX_BODY := 4194304
const PREVIEW_MAX_CELLS := 128
const PREVIEW_DEFAULT_CELLS := 24
const PREVIEW_MAX_PX := 1280

var editor: Node = null
var host: String = DEFAULT_HOST
var port: int = DEFAULT_PORT
var running: bool = false

var _tcp: TCPServer
var _clients: Array = []
var _session: String = ""
var extra: RefCounted = null


func _extra() -> RefCounted:
	if extra == null:
		extra = load("res://scripts/editor/adapters/editor_mcp_ops.gd").new()
	extra.mcp = self
	return extra


func url() -> String:
	return "http://%s:%d/mcp" % [host, port]


func start(p_port: int = DEFAULT_PORT) -> Dictionary:
	stop()
	port = p_port
	_tcp = TCPServer.new()
	var err := _tcp.listen(port, host)
	if err != OK:
		for try_port in range(p_port, p_port + 16):
			err = _tcp.listen(try_port, host)
			if err == OK:
				port = try_port
				break
	if err != OK:
		_tcp = null
		return {"ok": false, "error": "bind failed (%s)" % error_string(err)}
	running = true
	_session = "ed-%d" % int(Time.get_unix_time_from_system())
	set_process(true)
	return {"ok": true, "url": url(), "port": port, "session": _session}


func stop() -> void:
	running = false
	set_process(false)
	for c in _clients:
		if typeof(c) == TYPE_DICTIONARY:
			var peer: StreamPeerTCP = c.get("peer")
			if peer:
				peer.disconnect_from_host()
	_clients.clear()
	if _tcp:
		_tcp.stop()
		_tcp = null


func _exit_tree() -> void:
	stop()


func _process(_dt: float) -> void:
	if not running or _tcp == null:
		return
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if peer == null:
			break
		peer.set_no_delay(true)
		_clients.append({"peer": peer, "buf": PackedByteArray()})
	var i := 0
	while i < _clients.size():
		if not _pump(_clients[i]):
			var p: StreamPeerTCP = _clients[i].get("peer")
			if p:
				p.disconnect_from_host()
			_clients.remove_at(i)
		else:
			i += 1


func _pump(client: Dictionary) -> bool:
	var peer: StreamPeerTCP = client.get("peer")
	if peer == null:
		return false
	peer.poll()
	var st := peer.get_status()
	if st != StreamPeerTCP.STATUS_CONNECTED:
		return st == StreamPeerTCP.STATUS_CONNECTING
	if peer.get_available_bytes() > 0:
		var got: Array = peer.get_partial_data(peer.get_available_bytes())
		if got.size() < 2 or int(got[0]) != OK:
			return false
		var chunk: PackedByteArray = got[1]
		var buf: PackedByteArray = client.get("buf", PackedByteArray())
		buf.append_array(chunk)
		if buf.size() > MAX_BODY + 8192:
			_write_http(peer, 413, "text/plain", "too large")
			return false
		client["buf"] = buf
	var buf2: PackedByteArray = client.get("buf", PackedByteArray())
	var req: Dictionary = _extract_http(buf2)
	if bool(req.get("need_more", false)):
		return true
	if not bool(req.get("ok", false)):
		return false
	client["buf"] = buf2.slice(int(req.get("consumed", 0)))
	_handle_http(peer, str(req.get("method", "")), str(req.get("path", "")), str(req.get("body", "")))
	return true


func _find_headers_end(buf: PackedByteArray) -> int:
	if buf.size() < 4:
		return -1
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


func _header_value(headers: String, name: String) -> String:
	var want := name.to_lower() + ":"
	for line in headers.split("\n"):
		var t := line.strip_edges()
		if t.to_lower().begins_with(want):
			return t.substr(t.find(":") + 1).strip_edges()
	return ""


func _extract_http(buf: PackedByteArray) -> Dictionary:
	var split := _find_headers_end(buf)
	if split < 0:
		return {"need_more": true}
	var header_text := buf.slice(0, split).get_string_from_utf8()
	var first := header_text.get_slice("\r\n", 0)
	var method := first.get_slice(" ", 0).to_upper()
	var path := first.get_slice(" ", 1)
	if path.find("?") >= 0:
		path = path.get_slice("?", 0)
	var body_start := split + 4
	var te := _header_value(header_text, "Transfer-Encoding").to_lower()
	var clen_s := _header_value(header_text, "Content-Length")
	var body := PackedByteArray()
	var consumed := body_start
	if te.find("chunked") >= 0:
		var decoded: Dictionary = _decode_chunked(buf, body_start)
		if bool(decoded.get("need_more", false)):
			return {"need_more": true}
		if not bool(decoded.get("ok", false)):
			return {"ok": false}
		body = decoded.get("body", PackedByteArray())
		consumed = int(decoded.get("consumed", body_start))
	elif clen_s != "":
		var clen := maxi(int(clen_s), 0)
		if buf.size() < body_start + clen:
			return {"need_more": true}
		body = buf.slice(body_start, body_start + clen)
		consumed = body_start + clen
	else:
		body = PackedByteArray()
		consumed = body_start
	return {
		"ok": true,
		"method": method,
		"path": path,
		"body": body.get_string_from_utf8(),
		"consumed": consumed,
	}


func _decode_chunked(buf: PackedByteArray, start: int) -> Dictionary:
	var i := start
	var out := PackedByteArray()
	while true:
		var line_end := _find_crlf(buf, i)
		if line_end < 0:
			return {"need_more": true}
		var size_line := buf.slice(i, line_end).get_string_from_utf8().strip_edges()
		if size_line.find(";") >= 0:
			size_line = size_line.get_slice(";", 0)
		var n := size_line.hex_to_int()
		i = line_end + 2
		if n < 0:
			return {"ok": false}
		if n == 0:
			if buf.size() < i + 2:
				return {"need_more": true}
			if buf[i] == 13 and buf[i + 1] == 10:
				i += 2
			return {"ok": true, "body": out, "consumed": i}
		if buf.size() < i + n + 2:
			return {"need_more": true}
		out.append_array(buf.slice(i, i + n))
		i += n
		if buf[i] != 13 or buf[i + 1] != 10:
			return {"ok": false}
		i += 2
	return {"ok": false}


func _find_crlf(buf: PackedByteArray, from_idx: int) -> int:
	for i in range(from_idx, buf.size() - 1):
		if buf[i] == 13 and buf[i + 1] == 10:
			return i
	return -1


func _handle_http(peer: StreamPeerTCP, method: String, path: String, body: String) -> void:
	if method == "OPTIONS":
		_write_http(peer, 204, "text/plain", "")
		return
	if method == "GET" and (path.begins_with("/health") or path == "/"):
		_write_http(peer, 200, "application/json", JSON.stringify({
			"ok": true,
			"server": SERVER_NAME,
			"url": url(),
			"running": running,
			"map": _map_id(),
		}))
		return
	if method == "GET":
		_write_http(peer, 405, "text/plain", "method not allowed")
		return
	if method == "DELETE":
		_write_http(peer, 200, "text/plain", "")
		return
	if method != "POST":
		_write_http(peer, 405, "text/plain", "method not allowed")
		return
	var parsed: Variant = JSON.parse_string(body) if body.strip_edges() != "" else {}
	if typeof(parsed) != TYPE_DICTIONARY:
		_write_http(peer, 400, "application/json", _rpc_error(null, -32700, "Parse error"))
		return
	var msg: Dictionary = parsed
	var reply: Variant = handle_rpc(msg)
	if reply == null:
		_write_http(peer, 202, "application/json", "")
		return
	_write_http(peer, 200, "application/json", _stringify_rpc(reply))


func _write_http(peer: StreamPeerTCP, code: int, ctype: String, body: String) -> void:
	var reason := "OK"
	match code:
		202:
			reason = "Accepted"
		204:
			reason = "No Content"
		400:
			reason = "Bad Request"
		405:
			reason = "Method Not Allowed"
		413:
			reason = "Payload Too Large"
	var raw := body.to_utf8_buffer()
	var hdr := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nMcp-Session-Id: %s\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Accept, Mcp-Session-Id, MCP-Protocol-Version\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS, DELETE\r\nConnection: keep-alive\r\n\r\n" % [code, reason, ctype, raw.size(), _session]
	var out := hdr.to_utf8_buffer()
	out.append_array(raw)
	peer.put_data(out)


func _rpc_id_json(id: Variant) -> String:
	if id == null:
		return "null"
	match typeof(id):
		TYPE_INT:
			return str(int(id))
		TYPE_FLOAT:
			if is_equal_approx(float(id), roundf(float(id))):
				return str(int(roundf(float(id))))
			return str(id)
		TYPE_STRING:
			return JSON.stringify(id)
		_:
			return "null"


func _stringify_rpc(reply: Variant) -> String:
	if typeof(reply) != TYPE_DICTIONARY:
		return str(reply)
	var d: Dictionary = reply
	if d.has("error"):
		var err_v: Variant = d.get("error", {})
		var err: Dictionary = err_v if typeof(err_v) == TYPE_DICTIONARY else {}
		return '{"jsonrpc":"2.0","id":%s,"error":%s}' % [_rpc_id_json(d.get("id", null)), JSON.stringify(err)]
	return '{"jsonrpc":"2.0","id":%s,"result":%s}' % [_rpc_id_json(d.get("id", null)), JSON.stringify(d.get("result", {}))]


func _rpc_error(id: Variant, code: int, message: String) -> String:
	return '{"jsonrpc":"2.0","id":%s,"error":{"code":%d,"message":%s}}' % [_rpc_id_json(id), code, JSON.stringify(message)]


func handle_rpc(msg: Dictionary) -> Variant:
	var method := str(msg.get("method", "")).strip_edges()
	var has_id := msg.has("id")
	var id: Variant = msg.get("id", null) if has_id else null
	var params_v: Variant = msg.get("params", {})
	var params: Dictionary = params_v if typeof(params_v) == TYPE_DICTIONARY else {}
	if method.begins_with("notifications/") or not has_id:
		return null
	var result: Variant = null
	match method:
		"initialize":
			var ver := str(params.get("protocolVersion", PROTOCOL)).strip_edges()
			if ver == "":
				ver = PROTOCOL
			result = {
				"protocolVersion": ver,
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": SERVER_NAME, "version": "1.0.0"},
				"instructions": "RMMO content editor. Enable via 工具 → 启用 MCP 服务, or run tools/editor_mcp_host.gd.",
			}
		"ping":
			result = {}
		"tools/list":
			result = {"tools": tools_list()}
		"tools/call":
			var tname := str(params.get("name", "")).strip_edges()
			var args_v: Variant = params.get("arguments", {})
			var args: Dictionary = {}
			if typeof(args_v) == TYPE_DICTIONARY:
				args = args_v
			elif typeof(args_v) == TYPE_STRING:
				var parsed: Variant = JSON.parse_string(str(args_v))
				if typeof(parsed) == TYPE_DICTIONARY:
					args = parsed
			var payload: Dictionary = call_tool(tname, args)
			var is_err := bool(payload.get("isError", false)) or not bool(payload.get("ok", true))
			var img_b64 := str(payload.get("png_base64", ""))
			if payload.has("png_base64"):
				payload.erase("png_base64")
			var content: Array = [{"type": "text", "text": JSON.stringify(payload)}]
			if img_b64 != "":
				content.push_front({
					"type": "image",
					"data": img_b64,
					"mimeType": "image/png",
				})
			result = {
				"content": content,
				"isError": is_err,
			}
		_:
			return {
				"jsonrpc": "2.0",
				"id": id,
				"error": {"code": -32601, "message": "Method not found: %s" % method},
			}
	return {"jsonrpc": "2.0", "id": id, "result": result}


func tools_list() -> Array:
	var listed: Array = [
		_tool("editor_state", "当前内容包、地图、光标、图层。", {}),
		_tool("list_maps", "列出包内地图。", {}),
		_tool("select_map", "切换当前地图。", {"map_id": {"type": "string"}}),
		_tool("set_cursor", "设置编辑光标格。", {"x": {"type": "integer"}, "y": {"type": "integer"}}),
		_tool("paint_tile", "在当前图层写一个图块（走自动图块）。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"tile_id": {"type": "integer"},
			"z": {"type": "integer", "description": "MV 层 0-5，默认当前层"},
			"ext": {"type": "string"}, "erase": {"type": "boolean"}, "exact": {"type": "boolean"},
		}),
		_tool("set_meta", "格子标记位。bit: indoor=1 water=2 block=4 pass=8 nodash=16。可 w/h 或 cells 批量。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"bit": {"type": "integer"}, "erase": {"type": "boolean"},
			"w": {"type": "integer"}, "h": {"type": "integer"}, "cells": {"type": "array"},
		}),
		_tool("get_entity", "读取一格的事件/NPC/传送。", {"x": {"type": "integer"}, "y": {"type": "integer"}}),
		_tool("place_npc", "放置 NPC 或怪物。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"name": {"type": "string"}, "charset": {"type": "string"},
			"hostile": {"type": "boolean"}, "aggressive": {"type": "boolean"},
			"kind": {"type": "string", "description": "normal|monster|object"},
			"level": {"type": "integer"}, "wander_radius": {"type": "integer"},
			"through": {"type": "boolean"}, "interact_text": {"type": "string"},
		}),
		_tool("place_event", "放置事件（可带指令数组）。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"id": {"type": "string"}, "trigger": {"type": "string"},
			"text": {"type": "string"}, "commands": {"type": "array"},
			"through": {"type": "boolean"},
		}),
		_tool("place_warp", "放置传送格。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"to_map": {"type": "string"}, "to_x": {"type": "integer"}, "to_y": {"type": "integer"},
		}),
		_tool("delete_entity", "删除一格实体。", {"x": {"type": "integer"}, "y": {"type": "integer"}}),
		_tool("copy_entity", "复制一格实体到剪贴板。", {"x": {"type": "integer"}, "y": {"type": "integer"}}),
		_tool("paste_entity", "把剪贴板实体贴到目标格。", {"x": {"type": "integer"}, "y": {"type": "integer"}}),
		_tool("list_assets", "列出素材。kind: charset|faces|tilesheet|audio/bgm|audio/se", {"kind": {"type": "string"}}),
		_tool("list_switches", "收集包内用过的开关 id。", {}),
		_tool("save", "保存当前内容包。", {}),
		_tool("playtest", "从起始点或光标格试玩。", {"from_cursor": {"type": "boolean"}}),
		_tool("preview_map", "渲当前 chunk 的 PNG（默认光标所在 16×16）。overview=true 用离线大地图，不现场整图烘焙。", {
			"x": {"type": "integer"}, "y": {"type": "integer"},
			"w": {"type": "integer"}, "h": {"type": "integer"},
			"x2": {"type": "integer"}, "y2": {"type": "integer"},
			"grid": {"type": "boolean"},
			"entities": {"type": "boolean"},
			"overview": {"type": "boolean"},
			"chunk": {"type": "boolean"},
			"cell_px": {"type": "integer"},
			"max_px": {"type": "integer"},
			"path": {"type": "string"},
		}),
	]
	var more: Array = _extra().tools_list()
	for t in more:
		listed.append(t)
	return listed


func _tool(name: String, desc: String, props: Dictionary, required: Array = []) -> Dictionary:
	var req: Array = required.duplicate()
	if req.is_empty():
		for k in props.keys():
			if str(k) in ["x", "y", "map_id", "to_map", "tile_id", "bit"]:
				req.append(str(k))
		if name in ["list_maps", "editor_state", "save", "list_switches", "playtest", "preview_map"]:
			req.clear()
		if name == "list_assets":
			req = ["kind"]
		if name == "select_map":
			req = ["map_id"]
		if name == "paste_entity":
			req = ["x", "y"]
	return {
		"name": name,
		"description": desc,
		"inputSchema": {
			"type": "object",
			"properties": props,
			"required": req,
			"additionalProperties": true,
		},
	}


func call_tool(name: String, args: Dictionary) -> Dictionary:
	if editor == null:
		return _err("no editor")
	match name:
		"editor_state":
			var st := {
				"pack_id": str(editor.pack.pack_id) if editor.pack else "",
				"pack_root": str(editor.pack.root) if editor.pack else "",
				"map_id": _map_id(),
				"cursor": {"x": _cursor().x, "y": _cursor().y},
				"width": int(editor.doc.width) if editor.doc else 0,
				"height": int(editor.doc.height) if editor.doc else 0,
				"mode": int(editor.get("_mode")) if "_mode" in editor else 0,
				"mcp_url": url() if running else "",
			}
			var more_st: Dictionary = _extra().state_extra()
			for k in more_st.keys():
				st[k] = more_st[k]
			return _ok(st)
		"list_maps":
			return _ok({"maps": _maps()})
		"select_map":
			var mid := str(args.get("map_id", "")).strip_edges()
			if mid == "" or editor.pack == null:
				return _err("map_id required")
			_extra()._switch_map(mid)
			return _ok({"map_id": _map_id()})
		"set_cursor":
			var c := _cell(args)
			if editor.has_method("mcp_refresh"):
				editor.mcp_refresh(c)
			return _ok({"cursor": {"x": c.x, "y": c.y}})
		"paint_tile":
			return _extra().paint_one(args)
		"set_meta":
			return _extra().set_meta_batch(args)
		"get_entity":
			return _get_entity(args)
		"place_npc":
			return _place_npc(args)
		"place_event":
			return _place_event(args)
		"place_warp":
			return _place_warp(args)
		"delete_entity":
			return _delete_entity(args)
		"copy_entity":
			return _copy_entity(args)
		"paste_entity":
			return _paste_entity(args)
		"list_assets":
			var kind := str(args.get("kind", "charset"))
			return _ok({"kind": kind, "items": _extra().list_assets_merged(kind)})
		"list_switches":
			var EventCommands = load("res://scripts/editor/domain/event_commands.gd")
			return _ok({"switches": EventCommands.collect_switch_ids(editor.pack)})
		"save":
			if editor.has_method("_save"):
				editor._save()
			return _ok({"saved": true, "root": str(editor.pack.root) if editor.pack else ""})
		"playtest":
			if editor.has_method("_playtest"):
				editor._playtest(bool(args.get("from_cursor", false)))
			return _ok({"playtest": true, "from_cursor": bool(args.get("from_cursor", false))})
		"preview_map":
			return _preview_map(args)
		_:
			var hit: Dictionary = _extra().dispatch(name, args)
			if hit.is_empty():
				return _err("unknown tool %s" % name)
			return hit


func _maps() -> Array:
	var out: Array = []
	if editor == null or editor.pack == null:
		return out
	for item in editor.pack.map_tree:
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item)
	return out


func _map_id() -> String:
	if editor == null:
		return ""
	return str(editor.current_map_id)


func _cursor() -> Vector2i:
	if editor == null:
		return Vector2i.ZERO
	return editor.get("_cursor") if "_cursor" in editor else Vector2i.ZERO


func _cell(args: Dictionary) -> Vector2i:
	if args.has("x") or args.has("y"):
		return Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	return _cursor()


func _doc():
	return editor.doc if editor else null


func _paint(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var c := _cell(args)
	var z := int(args.get("z", -1))
	if z < 0 and editor.paint:
		z = int(editor.paint.layer_z)
	if z < 0:
		z = 0
	var tid := int(args.get("tile_id", args.get("id", 0)))
	doc.set_tile(c.x, c.y, z, tid)
	_refresh(c)
	return _ok({"x": c.x, "y": c.y, "z": z, "tile_id": tid})


func _set_meta(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var MapExt = load("res://scripts/map/map_ext.gd")
	var c := _cell(args)
	var bit := int(args.get("bit", 0))
	if bit <= 0:
		return _err("bit required")
	var cur: int = int(doc.ext_tile("meta", c.x, c.y))
	var nxt := cur
	if bool(args.get("erase", false)):
		nxt = cur & ~bit
	else:
		nxt = cur | bit
		if bit == MapExt.META_FORCE_BLOCK:
			nxt &= ~MapExt.META_FORCE_PASS
		elif bit == MapExt.META_FORCE_PASS:
			nxt &= ~MapExt.META_FORCE_BLOCK
	doc.set_ext_tile("meta", c.x, c.y, nxt)
	_refresh(c)
	return _ok({"x": c.x, "y": c.y, "meta": nxt})


func _get_entity(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var c := _cell(args)
	var hit: Dictionary = doc.entity_at(c)
	return _ok({"cell": {"x": c.x, "y": c.y}, "entity": hit})


func _place_npc(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var c := _cell(args)
	doc.remove_entity_at(c)
	var cs := str(args.get("charset", "Actor1")).strip_edges()
	if cs == "":
		cs = "Actor1"
	var n: Dictionary = doc.add_npc(c, cs, str(args.get("name", "NPC")))
	n["hostile"] = bool(args.get("hostile", false))
	n["aggressive"] = bool(n["hostile"]) and bool(args.get("aggressive", false))
	var kind := str(args.get("kind", "")).strip_edges()
	if kind == "":
		kind = "monster" if bool(n["hostile"]) else "normal"
	n["kind"] = kind
	n["level"] = maxi(int(args.get("level", 1)), 1)
	n["wander_radius"] = maxi(int(args.get("wander_radius", 0)), 0)
	n["wander"] = bool(args.get("wander", n["wander_radius"] > 0))
	n["through"] = bool(args.get("through", false))
	n["interact_text"] = str(args.get("interact_text", ""))
	n["index"] = int(args.get("index", 0))
	n["direction"] = int(args.get("direction", 2))
	_refresh(c)
	return _ok({"npc": n})


func _place_event(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var EventCommands = load("res://scripts/editor/domain/event_commands.gd")
	var c := _cell(args)
	doc.remove_entity_at(c)
	var text := str(args.get("text", "……"))
	var ev: Dictionary = EventCommands.make_event(c, text)
	var eid := str(args.get("id", "")).strip_edges()
	if eid != "":
		ev["id"] = eid
	if args.has("trigger"):
		ev["trigger"] = EventCommands.normalize_trigger(str(args.get("trigger", "action")))
	if args.has("through"):
		ev["through"] = bool(args.get("through"))
	var cmds_v: Variant = args.get("commands", [])
	if typeof(cmds_v) == TYPE_ARRAY and not (cmds_v as Array).is_empty():
		var pages: Array = EventCommands.ensure_pages(ev)
		if not pages.is_empty() and typeof(pages[0]) == TYPE_DICTIONARY:
			pages[0]["commands"] = cmds_v
	if args.has("face"):
		var pages2: Array = EventCommands.ensure_pages(ev)
		if not pages2.is_empty() and typeof(pages2[0]) == TYPE_DICTIONARY:
			var cmds: Array = pages2[0].get("commands", [])
			if not cmds.is_empty() and typeof(cmds[0]) == TYPE_DICTIONARY:
				EventCommands.set_cmd_face(cmds[0], str(args.get("face", "")), int(args.get("face_index", 0)))
	doc.events.append(ev)
	doc.dirty = true
	_refresh(c)
	return _ok({"event": ev})


func _place_warp(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var c := _cell(args)
	doc.remove_entity_at(c)
	var w: Dictionary = doc.add_warp(
		c,
		str(args.get("to_map", "Map002")),
		Vector2i(int(args.get("to_x", 0)), int(args.get("to_y", 0))),
		int(args.get("facing", 2))
	)
	_refresh(c)
	return _ok({"warp": w})


func _delete_entity(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var c := _cell(args)
	var ok := bool(doc.remove_entity_at(c))
	_refresh(c)
	return _ok({"deleted": ok, "cell": {"x": c.x, "y": c.y}})


func _copy_entity(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null or not doc.has_method("copy_entity_at"):
		return _err("no map")
	var c := _cell(args)
	var clip: Dictionary = doc.copy_entity_at(c)
	if clip.is_empty():
		return _err("empty cell")
	editor._entity_clip = clip
	if editor._inspector != null:
		editor._inspector.clip = clip.duplicate(true)
	return _ok({"clip": clip})


func _paste_entity(args: Dictionary) -> Dictionary:
	var doc = _doc()
	if doc == null:
		return _err("no map")
	var clip: Dictionary = editor.get("_entity_clip") if editor else {}
	if (clip == null or clip.is_empty()) and editor.get("_inspector") != null:
		clip = editor._inspector.clip
	if clip == null or clip.is_empty():
		return _err("clipboard empty")
	var c := _cell(args)
	if not doc.paste_entity_at(clip, c):
		return _err("paste failed")
	_refresh(c)
	return _ok({"pasted": true, "cell": {"x": c.x, "y": c.y}, "kind": str(clip.get("kind", ""))})


func _refresh(cell: Vector2i) -> void:
	if editor and editor.has_method("mcp_refresh"):
		editor.mcp_refresh(cell)


func _preview_map(args: Dictionary) -> Dictionary:
	var field = _preview_field()
	if field == null or not field.has_method("render_preview"):
		return _err("no map field")
	var doc = _doc()
	var gw: int = int(doc.width) if doc else int(field.grid_width)
	var gh: int = int(doc.height) if doc else int(field.grid_height)
	if gw <= 0 or gh <= 0:
		return _err("empty map")
	var overview := bool(args.get("overview", false))
	var x0 := 0
	var y0 := 0
	var cw := gw
	var ch := gh
	var img: Image
	var ts: int = maxi(int(field.tile_size), 1)
	if overview:
		img = null
		if field.has_method("get_lofi_image"):
			img = field.get_lofi_image()
			if img != null:
				img = img.duplicate()
		if img == null and gw * gh <= 65536 and field.has_method("render_preview"):
			var cell_px := clampi(int(args.get("cell_px", 0)), 0, 8)
			if cell_px <= 0:
				var max_px0: int = int(args.get("max_px", PREVIEW_MAX_PX))
				if max_px0 <= 0:
					max_px0 = PREVIEW_MAX_PX
				cell_px = clampi(int(floor(float(max_px0) / float(maxi(gw, gh)))), 1, 3)
			img = field.render_preview(0, 0, gw, gh, cell_px)
			ts = cell_px
		if img == null:
			return _err("no overview (save the map to bake overview.png)")
		cw = gw
		ch = gh
		x0 = 0
		y0 = 0
	else:
		var rect: Dictionary = _preview_rect(args, gw, gh)
		x0 = int(rect.x)
		y0 = int(rect.y)
		cw = int(rect.w)
		ch = int(rect.h)
		img = field.render_preview(x0, y0, cw, ch)
		if img != null:
			cw = img.get_width() / ts
			ch = img.get_height() / ts
	if img == null:
		return _err("render failed")
	var entities: Array = []
	var do_ent := bool(args.get("entities", not overview))
	var do_grid := bool(args.get("grid", not overview))
	if do_ent:
		entities = _blit_preview_entities(img, x0, y0, cw, ch, ts)
	if do_grid:
		_blit_preview_grid(img, cw, ch, ts)
	if not overview:
		_blit_preview_cursor(img, x0, y0, cw, ch, ts)
	var max_px: int = int(args.get("max_px", PREVIEW_MAX_PX))
	if max_px <= 0:
		max_px = PREVIEW_MAX_PX
	var ow: int = img.get_width()
	var oh: int = img.get_height()
	var longest: int = maxi(ow, oh)
	if longest > max_px:
		var sc := float(max_px) / float(longest)
		img.resize(maxi(1, int(ow * sc)), maxi(1, int(oh * sc)), Image.INTERPOLATE_NEAREST)
	var save_path := str(args.get("path", "")).strip_edges()
	if save_path == "":
		save_path = ProjectSettings.globalize_path("res://.grok/mcp_preview.png")
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var save_err := img.save_png(save_path)
	var png: PackedByteArray = img.save_png_to_buffer()
	if png.is_empty():
		return _err("png encode failed")
	return _ok({
		"map_id": _map_id(),
		"x": x0,
		"y": y0,
		"w": cw,
		"h": ch,
		"tile_size": ts,
		"px_w": img.get_width(),
		"px_h": img.get_height(),
		"src_px_w": ow,
		"src_px_h": oh,
		"path": save_path,
		"saved": save_err == OK,
		"entities": entities,
		"png_base64": Marshalls.raw_to_base64(png),
	})


func _preview_field():
	if editor == null:
		return null
	var field = editor.get("map_field") if "map_field" in editor else null
	if field != null:
		field.edit_mode = true
		field.edit_doc = editor.doc
		if editor.pack:
			field.pack_path = str(editor.pack.root)
		field.edit_map_id = str(editor.current_map_id)
		if "_cursor" in editor:
			field.edit_cursor_cell = editor._cursor
		_apply_preview_sheets(field)
		return field
	var MapField = load("res://scripts/map/map_field.gd")
	field = MapField.new()
	field.skip_ready_rebuild = true
	field.edit_mode = true
	field.edit_doc = editor.doc
	if editor.pack:
		field.pack_path = str(editor.pack.root)
	field.edit_map_id = str(editor.current_map_id)
	add_child(field)
	_apply_preview_sheets(field)
	return field


func _apply_preview_sheets(field) -> void:
	if field == null or editor == null:
		return
	var pal = editor.get("_palette") if "_palette" in editor else null
	if pal == null or pal.sheets.size() == 0:
		return
	if field.pack == null:
		field.ensure_pack_for_preview()
	if field.pack != null:
		field.pack.sheets = pal.sheets
		if pal._flags.size() > 0:
			field.pack.flags = pal._flags


func _chunk_rect_at(cell: Vector2i, gw: int, gh: int) -> Dictionary:
	var cc := 16
	var field = editor.get("map_field") if editor and "map_field" in editor else null
	if field != null and field.get("CHUNK_CELLS") != null:
		cc = maxi(int(field.CHUNK_CELLS), 1)
	var x0 := int(floor(float(cell.x) / float(cc))) * cc
	var y0 := int(floor(float(cell.y) / float(cc))) * cc
	x0 = clampi(x0, 0, maxi(gw - 1, 0))
	y0 = clampi(y0, 0, maxi(gh - 1, 0))
	var w := mini(cc, gw - x0)
	var h := mini(cc, gh - y0)
	return {"x": x0, "y": y0, "w": maxi(w, 1), "h": maxi(h, 1)}


func _preview_rect(args: Dictionary, gw: int, gh: int) -> Dictionary:
	var field = editor.get("map_field") if editor and "map_field" in editor else null
	var x0 := 0
	var y0 := 0
	var x1 := 0
	var y1 := 0
	var has_range := args.has("w") or args.has("h") or args.has("x2") or args.has("y2")
	var force_chunk := bool(args.get("chunk", true)) and not has_range and not args.has("x") and not args.has("y")
	if force_chunk:
		var cell := _cursor()
		if field != null and field.has_method("current_chunk_rect"):
			if "_cursor" in editor:
				field.edit_cursor_cell = editor._cursor
			var r: Rect2i = field.current_chunk_rect(cell)
			return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}
		return _chunk_rect_at(cell, gw, gh)
	if (args.has("x") or args.has("y")) and not has_range:
		return _chunk_rect_at(Vector2i(int(args.get("x", _cursor().x)), int(args.get("y", _cursor().y))), gw, gh)
	if args.has("x") or args.has("y") or has_range:
		x0 = int(args.get("x", 0))
		y0 = int(args.get("y", 0))
		if args.has("x2") or args.has("y2"):
			x1 = int(args.get("x2", x0))
			y1 = int(args.get("y2", y0))
		else:
			var cw := clampi(int(args.get("w", 16)), 1, PREVIEW_MAX_CELLS)
			var ch := clampi(int(args.get("h", 16)), 1, PREVIEW_MAX_CELLS)
			x1 = x0 + cw - 1
			y1 = y0 + ch - 1
	elif field != null and int(field.edit_rect_a.x) >= 0 and int(field.edit_rect_b.x) >= 0:
		x0 = mini(int(field.edit_rect_a.x), int(field.edit_rect_b.x))
		y0 = mini(int(field.edit_rect_a.y), int(field.edit_rect_b.y))
		x1 = maxi(int(field.edit_rect_a.x), int(field.edit_rect_b.x))
		y1 = maxi(int(field.edit_rect_a.y), int(field.edit_rect_b.y))
	else:
		return _chunk_rect_at(_cursor(), gw, gh)
	if x1 < x0:
		var tmp := x0
		x0 = x1
		x1 = tmp
	if y1 < y0:
		var tmpy := y0
		y0 = y1
		y1 = tmpy
	x0 = clampi(x0, 0, gw - 1)
	y0 = clampi(y0, 0, gh - 1)
	x1 = clampi(x1, 0, gw - 1)
	y1 = clampi(y1, 0, gh - 1)
	var w := mini(x1 - x0 + 1, PREVIEW_MAX_CELLS)
	var h := mini(y1 - y0 + 1, PREVIEW_MAX_CELLS)
	return {"x": x0, "y": y0, "w": w, "h": h}


func _blit_preview_entities(img: Image, x0: int, y0: int, cw: int, ch: int, ts: int) -> Array:
	var out: Array = []
	var doc = _doc()
	if img == null or doc == null:
		return out
	var CharsetSheet = load("res://scripts/char/charset_sheet.gd")
	var EventCommands = load("res://scripts/editor/domain/event_commands.gd")
	var pack_dir := ""
	if editor.pack:
		pack_dir = str(editor.pack.root)
	var x1 := x0 + cw
	var y1 := y0 + ch
	if "events" in doc:
		for ev in doc.events:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var cell := _entity_cell(ev.get("cell", {}))
			if cell.x < x0 or cell.y < y0 or cell.x >= x1 or cell.y >= y1:
				continue
			var pages_v: Variant = ev.get("pages", [])
			var page: Dictionary = {}
			if typeof(pages_v) == TYPE_ARRAY and not (pages_v as Array).is_empty() and typeof((pages_v as Array)[0]) == TYPE_DICTIONARY:
				page = (pages_v as Array)[0]
			var g: Dictionary = EventCommands.page_graphic(page)
			var r := _cell_px(cell, x0, y0, ts)
			var drawn := bool(CharsetSheet.blit_idle_frame(img, r, str(g.get("charset", "")), int(g.get("index", 0)), int(g.get("direction", 2)), pack_dir))
			if not drawn:
				_fill_mark(img, r, Color(0.95, 0.78, 0.12, 0.92))
			out.append({"kind": "event", "x": cell.x, "y": cell.y, "id": str(ev.get("id", ""))})
	if "npcs" in doc:
		for n in doc.npcs:
			if typeof(n) != TYPE_DICTIONARY:
				continue
			var ncell := _entity_cell(n.get("cell", {}))
			if ncell.x < x0 or ncell.y < y0 or ncell.x >= x1 or ncell.y >= y1:
				continue
			var r2 := _cell_px(ncell, x0, y0, ts)
			var drawn2 := bool(CharsetSheet.blit_idle_frame(
				img, r2, str(n.get("charset", "")), int(n.get("index", 0)), int(n.get("direction", 2)), pack_dir
			))
			if not drawn2:
				var col := Color(0.92, 0.28, 0.22, 0.92) if bool(n.get("hostile", false)) else Color(0.25, 0.62, 0.95, 0.92)
				_fill_mark(img, r2, col)
			elif bool(n.get("hostile", false)):
				_stroke_rect(img, r2, Color(1.0, 0.2, 0.12, 1), 2)
			out.append({
				"kind": "npc",
				"x": ncell.x,
				"y": ncell.y,
				"name": str(n.get("name", "")),
				"hostile": bool(n.get("hostile", false)),
			})
	if "warps" in doc:
		for w in doc.warps:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			var wcell := _entity_cell(w.get("from_cell", {}))
			if wcell.x < x0 or wcell.y < y0 or wcell.x >= x1 or wcell.y >= y1:
				continue
			_fill_mark(img, _cell_px(wcell, x0, y0, ts), Color(0.78, 0.35, 0.95, 0.92))
			out.append({
				"kind": "warp",
				"x": wcell.x,
				"y": wcell.y,
				"to_map": str(w.get("to_map", "")),
			})
	return out


func _entity_cell(c: Variant) -> Vector2i:
	if typeof(c) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)
	return Vector2i(int(c.get("x", 0)), int(c.get("y", 0)))


func _cell_px(cell: Vector2i, x0: int, y0: int, ts: int) -> Rect2i:
	return Rect2i((cell.x - x0) * ts, (cell.y - y0) * ts, ts, ts)


func _fill_mark(img: Image, cell: Rect2i, col: Color) -> void:
	var pad := maxi(int(float(cell.size.x) * 0.12), 1)
	var r := Rect2i(cell.position + Vector2i(pad, pad), cell.size - Vector2i(pad * 2, pad * 2))
	_fill_rect_blend(img, r, col)
	_stroke_rect(img, r, Color(0, 0, 0, 0.7), 1)


func _fill_rect_blend(img: Image, r: Rect2i, col: Color) -> void:
	if img == null:
		return
	var x0 := clampi(r.position.x, 0, img.get_width())
	var y0 := clampi(r.position.y, 0, img.get_height())
	var x1 := clampi(r.position.x + r.size.x, 0, img.get_width())
	var y1 := clampi(r.position.y + r.size.y, 0, img.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			var d: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
				lerpf(d.r, col.r, col.a),
				lerpf(d.g, col.g, col.a),
				lerpf(d.b, col.b, col.a),
				1.0
			))


func _stroke_rect(img: Image, r: Rect2i, col: Color, thick: int) -> void:
	if img == null or thick <= 0:
		return
	for i in range(thick):
		var rr := Rect2i(r.position.x + i, r.position.y + i, r.size.x - i * 2, r.size.y - i * 2)
		if rr.size.x <= 0 or rr.size.y <= 0:
			return
		_h_line(img, rr.position.y, rr.position.x, rr.position.x + rr.size.x - 1, col)
		_h_line(img, rr.position.y + rr.size.y - 1, rr.position.x, rr.position.x + rr.size.x - 1, col)
		_v_line(img, rr.position.x, rr.position.y, rr.position.y + rr.size.y - 1, col)
		_v_line(img, rr.position.x + rr.size.x - 1, rr.position.y, rr.position.y + rr.size.y - 1, col)


func _h_line(img: Image, y: int, x0: int, x1: int, col: Color) -> void:
	if y < 0 or y >= img.get_height():
		return
	if x0 > x1:
		var t := x0
		x0 = x1
		x1 = t
	x0 = clampi(x0, 0, img.get_width() - 1)
	x1 = clampi(x1, 0, img.get_width() - 1)
	for x in range(x0, x1 + 1):
		img.set_pixel(x, y, col)


func _v_line(img: Image, x: int, y0: int, y1: int, col: Color) -> void:
	if x < 0 or x >= img.get_width():
		return
	if y0 > y1:
		var t := y0
		y0 = y1
		y1 = t
	y0 = clampi(y0, 0, img.get_height() - 1)
	y1 = clampi(y1, 0, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		img.set_pixel(x, y, col)


func _blit_preview_grid(img: Image, cw: int, ch: int, ts: int) -> void:
	var col := Color(1, 1, 1, 1)
	var mix := 0.28
	var w: int = img.get_width()
	var h: int = img.get_height()
	for gx in range(cw + 1):
		var px := clampi(gx * ts, 0, w - 1)
		for y in range(h):
			var d: Color = img.get_pixel(px, y)
			img.set_pixel(px, y, d.lerp(col, mix))
	for gy in range(ch + 1):
		var py := clampi(gy * ts, 0, h - 1)
		for x in range(w):
			var d2: Color = img.get_pixel(x, py)
			img.set_pixel(x, py, d2.lerp(col, mix))


func _blit_preview_cursor(img: Image, x0: int, y0: int, cw: int, ch: int, ts: int) -> void:
	var c := _cursor()
	if c.x < x0 or c.y < y0 or c.x >= x0 + cw or c.y >= y0 + ch:
		return
	_stroke_rect(img, _cell_px(c, x0, y0, ts), Color(1.0, 0.82, 0.15, 1), 2)


func _ok(extra: Dictionary = {}) -> Dictionary:
	extra["ok"] = true
	return extra


func _err(msg: String) -> Dictionary:
	return {"ok": false, "isError": true, "error": msg}
