extends "res://scripts/editor/adapters/editor_mcp.gd"
## Reuses HTTP/JSON-RPC framing, never the retired 2D tool registry/dispatcher.
const Schema = preload("res://scripts/world_editor/mcp_schema.gd")
const Ops = preload("res://scripts/world_editor/mcp_ops.gd")
const PORT := 18766
const MAX_CLIENTS := 8
const CLIENT_IDLE_MS := 10000
var _ops := Ops.new()
var _definitions := {}
var _pending_saves := {}

func server_name() -> String:
	return "rmmo-world-editor"

func instructions() -> String:
	return "RMMO 3D map editor. XYZ are decimal meters, Y is up. UI and MCP share selection, transforms, groups, prefabs, auto-tiles and undo. The legacy 2D tools are retired. Query editor_state and list_assets before editing."

func _map_id() -> String:
	return str(editor._path) if editor != null else ""

func start(p_port: int = PORT) -> Dictionary:
	stop()
	if p_port < 1024 or p_port > 65535: return {"ok": false, "error": "Port must be between 1024 and 65535"}
	host = "127.0.0.1"
	port = p_port
	_tcp = TCPServer.new()
	var result := _tcp.listen(port, host)
	if result != OK:
		_tcp = null
		return {"ok": false, "error": "Port %d unavailable: %s" % [port, error_string(result)]}
	running = true
	_session = "world-" + Crypto.new().generate_random_bytes(16).hex_encode()
	set_process(true)
	return {"ok": true, "url": url(), "port": port, "session": _session}

func tools_list() -> Array:
	return Schema.tools()

func call_tool(name: String, args: Dictionary) -> Dictionary:
	if _definitions.is_empty():
		for definition in tools_list(): _definitions[definition.name] = definition
	if not _definitions.has(name): return {"ok": false, "error": "Unsupported 3D tool: " + name}
	var definition: Dictionary = _definitions[name]
	var validation := Schema.validate(args, definition.inputSchema)
	if not validation.is_empty(): return {"ok": false, "error": validation}
	if not is_instance_valid(editor) or editor._selection_tools == null: return {"ok": false, "error": "3D editor is not ready"}
	if not definition.annotations.readOnlyHint:
		if editor.saving(): return {"ok":false,"error":"正在保存，请等待当前保存完成；可用 editor_state 查询进度"}
		if editor._city.busy(): return {"ok":false,"error":"Finish or cancel the road draft/node drag first"}
		if editor._playtest.active() and name != "stop_playtest": return {"ok":false,"error":"Stop the playtest before editing the document"}
		if editor._authoring.picking: return {"ok":false,"error":"Finish or cancel spawn picking first"}
		if editor._building_area_busy(): return {"ok":false,"error":"Finish or cancel building region selection first"}
		if editor._load_failed and name not in ["open_world", "restore_editor_draft", "discard_editor_draft", "configure_autosave", "close_editor"]: return {"ok": false, "error": "Current map is read-only after a load failure"}
		if editor._safety.state().close_pending and name != "close_editor": return {"ok": false, "error": "Resolve or cancel the pending close dialog first"}
		if editor._transform_drag.active or editor._auto_stroke.active or editor._selection_tools.marquee or editor._stroke._open or editor._placement_tools.active or editor._material_tool.active or (editor._terrain_brush!=null and editor._terrain_brush.active):
			return {"ok": false, "error": "Editor interaction in progress; retry after it finishes"}
	_ops.editor = editor
	return _ops.execute(name, args)

func handle_rpc(msg: Dictionary) -> Variant:
	if msg.get("jsonrpc") != "2.0" or not msg.get("method") is String or (msg.has("params") and not msg.params is Dictionary):
		return {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32600, "message": "Invalid JSON-RPC request"}}
	if msg.get("method") == "tools/call" and not msg.get("params", {}).get("arguments", {}) is Dictionary:
		return {"jsonrpc": "2.0", "id": msg.get("id"), "error": {"code": -32602, "message": "arguments must be an object"}}
	var request := msg.duplicate(true)
	if request.method == "initialize":
		if not request.has("params"): request.params = {}
		request.params.protocolVersion = PROTOCOL
	return super.handle_rpc(request)

func _process(_dt: float) -> void:
	if not running or _tcp == null: return
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if peer == null: break
		if _clients.size() >= MAX_CLIENTS: peer.disconnect_from_host(); continue
		peer.set_no_delay(true)
		_clients.append({"peer": peer, "buf": PackedByteArray(), "last_active": Time.get_ticks_msec()})
	for i in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[i]
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		# A pending save owns this connection's response, but not the server loop.
		if _pending_saves.has(peer.get_instance_id()):
			client.last_active = Time.get_ticks_msec()
			continue
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0: client.last_active = Time.get_ticks_msec()
		if Time.get_ticks_msec() - int(client.last_active) > CLIENT_IDLE_MS or not _pump(client):
			peer.disconnect_from_host()
			_clients.remove_at(i)

func _extract_http(buf: PackedByteArray) -> Dictionary:
	var split := _find_headers_end(buf)
	if split < 0:
		return {"ok": false} if buf.size() > 8192 else {"need_more": true}
	var headers := buf.slice(0, split).get_string_from_utf8()
	var host_header := _header_value(headers, "Host").to_lower()
	if host_header not in ["127.0.0.1:%d" % port, "localhost:%d" % port]: return {"ok": false}
	var origin := _header_value(headers, "Origin").to_lower()
	if not origin.is_empty() and origin not in ["http://127.0.0.1:%d" % port, "http://localhost:%d" % port]: return {"ok": false}
	var length := _header_value(headers, "Content-Length")
	if not length.is_empty() and (not length.is_valid_int() or int(length) < 0 or int(length) > MAX_BODY): return {"ok": false}
	if not length.is_empty() and not _header_value(headers, "Transfer-Encoding").is_empty(): return {"ok": false}
	return super._extract_http(buf)

func _handle_http(peer: StreamPeerTCP, method: String, path: String, body: String) -> void:
	if path not in ["/", "/health", "/mcp"]:
		_write_http(peer, 404, "text/plain", "not found")
		return
	if method == "POST":
		var msg: Variant = JSON.parse_string(body)
		if msg is Dictionary and msg.get("method") == "tools/call" and msg.has("id") and msg.get("params") is Dictionary:
			var params: Dictionary = msg.params
			var args: Variant = params.get("arguments", {})
			var saving_close: bool = params.get("name") == "close_editor" and args is Dictionary and args.get("action") == "save"
			if params.get("name") == "save_world" or saving_close:
				var reply: Dictionary = handle_rpc(msg)
				var payload: Variant = JSON.parse_string(reply.get("result", {}).get("content", [{"text":"{}"}])[0].text)
				if payload is Dictionary and payload.get("pending", false) and (saving_close or not args.get("background", false)):
					_pending_saves[peer.get_instance_id()] = true
					editor._save_job.finished.connect(_saved_http.bind(peer,msg.id,saving_close), CONNECT_ONE_SHOT)
				else: _write_http(peer, 200, "application/json", _stringify_rpc(reply))
				return
	super._handle_http(peer, method, path, body)

func _saved_http(result: Dictionary, peer: StreamPeerTCP, id: Variant, close_after: bool) -> void:
	_pending_saves.erase(peer.get_instance_id())
	var payload := result.duplicate(true)
	if close_after: payload.closing = result.ok
	peer.poll()
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_write_http(peer, 200, "application/json", _stringify_rpc({"jsonrpc":"2.0","id":id,"result":{"isError":not result.ok,"content":[{"type":"text","text":JSON.stringify(payload)}]}}))
	if close_after and result.ok: editor._safety.call_deferred("_finish_exit")

func _write_http(peer: StreamPeerTCP, code: int, ctype: String, body: String) -> void:
	var raw := body.to_utf8_buffer()
	var reason := str({200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"}.get(code, "Error"))
	var headers := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nMcp-Session-Id: %s\r\nConnection: keep-alive\r\n\r\n" % [code, reason, ctype, raw.size(), _session]
	var response := headers.to_utf8_buffer()
	response.append_array(raw)
	peer.put_data(response)
