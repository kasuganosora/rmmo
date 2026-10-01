extends SceneTree
const Doc = preload("res://scripts/world3d/world_document.gd")
const Io = preload("res://scripts/world3d/gltf_map_io.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Server = preload("res://scripts/world_editor/mcp_server.gd")
var editor: Node3D
var port := 28766
var failed := 0
var serial := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failed += 1

func settle() -> void:
	for i in 4: await process_frame

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not equivalent(a[index], b[index]): return false
		return true
	return a == b

func rpc(method: String, params: Dictionary = {}) -> Dictionary:
	serial += 1
	var body := JSON.stringify({"jsonrpc": "2.0", "id": serial, "method": method, "params": params}).to_utf8_buffer()
	var request := ("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % [port, body.size()]).to_utf8_buffer()
	request.append_array(body)
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 5000
	var sent := false
	var received := PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
		if not sent: peer.put_data(request); sent = true
		if peer.get_available_bytes() > 0: received.append_array(peer.get_partial_data(peer.get_available_bytes())[1])
		var split: int = editor._mcp._find_headers_end(received)
		if split < 0: continue
		var length := int(editor._mcp._header_value(received.slice(0, split).get_string_from_utf8(), "Content-Length"))
		if received.size() < split + 4 + length: continue
		peer.disconnect_from_host()
		var parsed: Variant = JSON.parse_string(received.slice(split + 4, split + 4 + length).get_string_from_utf8())
		if parsed is Dictionary: return parsed
		break
	peer.disconnect_from_host()
	check(false, "HTTP response for " + method)
	return {}

func call_tool(name_: String, args: Dictionary = {}, expected_ok: bool = true) -> Dictionary:
	var response := await rpc("tools/call", {"name": name_, "arguments": args})
	var result: Dictionary = response.get("result", {})
	var payload: Dictionary = {}
	for part in result.get("content", []):
		if part.type == "text": payload = JSON.parse_string(part.text)
	check(payload.get("ok", false) == expected_ok and result.get("isError", true) == not expected_ok, "HTTP " + name_ + (" succeeds" if expected_ok else " rejects invalid operation"))
	if expected_ok and not payload.get("ok", false): print(payload)
	return payload

func run() -> void:
	var legacy := preload("res://scripts/editor/adapters/editor_mcp.gd").new()
	check(not legacy.start().ok and legacy.tools_list().is_empty() and not legacy.call_tool("paint_tile", {}).ok, "2D startup, discovery and dispatch retired; historical source retained")
	check(legacy.has_method("_legacy_tools_list") and legacy.has_method("_legacy_call_tool"), "legacy implementation remains available for reference")
	legacy.free()
	var directory := Paths.external_root().path_join("__world_mcp_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata := FileAccess.open(directory.path_join("metadata.json"), FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id": "mcp_test", "name": "MCP 临时测试包"})); metadata.close()
	var path := directory.path_join("maps/test/map.gltf")
	var doc := Doc.new()
	var a: String = doc.add_box("block", Vector3(-2, 1, 0), Vector3(2, 2, 2))
	var b: String = doc.add_box("block", Vector3(2, 1, 0), Vector3(2, 2, 2))
	check(doc.save(path) == OK, "create isolated test map")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path
	session.world3d_editor_doc = null
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	root.add_child(editor)
	await settle()
	# Select a free test port; production start itself must never silently fall back.
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop()
	check(editor.start_mcp(port).ok, "start current 3D MCP on loopback")
	var conflict := Server.new()
	check(not conflict.start(port).ok and not conflict.running and conflict.port == port, "occupied port fails without moving to a different port")
	conflict.free()
	var initialized := await rpc("initialize", {"protocolVersion": "2025-03-26"})
	check(initialized.get("result", {}).get("serverInfo", {}).get("name") == "rmmo-world-editor", "initialize identifies only the 3D service")
	var discovery := await rpc("tools/list")
	var names: Array = discovery.get("result", {}).get("tools", []).map(func(t): return t.name)
	check(names.size() == 63 and not names.has("paint_tile") and not names.has("set_cursor") and names.has("paint_auto_tiles") and names.has("save_prefab"), "discovery contains 63 current tools and no legacy 2D tools")
	await call_tool("paint_tile", {"x": 0, "y": 0}, false)
	var state := await call_tool("editor_state")
	check(state.object_count == 2 and state.up_axis == "Y", "state uses 3D meters and current document")
	await call_tool("list_objects", {"limit": 1})
	await call_tool("get_object", {"id": a})
	await call_tool("select_objects", {"ids": [a]})
	await call_tool("configure_transform", {"mode": "rotate", "space": "local", "position_snap": 0.1, "rotation_snap": 45, "scale_snap": 0.25})
	check(editor._transform_mode == 1 and editor._local_transform and editor._snap_controls.position_snap.selected == 2 and editor._snap_controls.rotation_snap.selected == 3, "MCP transform settings update visible UI controls")
	await call_tool("set_object_transform", {"id": a, "position": [-2.123, 1.234, 0.456], "rotation": [12, 23, 34], "size": [1, 2, 3]})
	check(Geometry.vector(editor._doc._find(a), "position").is_equal_approx(Vector3(-2.123, 1.234, 0.456)), "exact decimal transforms survive HTTP without snapping")
	await call_tool("undo")
	check(Geometry.vector(editor._doc._find(a), "position") == Vector3(-2, 1, 0), "shared undo restores exact transform")
	await call_tool("redo")
	await call_tool("select_objects", {"ids": [a, b]})
	await call_tool("group_selection")
	var group_id: String = editor._doc._find(a).editor_group
	check(editor._doc._find(b).editor_group == group_id, "group identity shared by selected members")
	await call_tool("set_object_properties", {"group_id": group_id, "name": "测试组合"})
	await call_tool("configure_transform", {"space": "local"}, false)
	var before: Array = editor._doc.records.duplicate(true)
	var undo_count: int = editor._doc._undo.size()
	await call_tool("transform_selection", {"translation": [1, 2, 3], "rotation": [0, 90, 0], "scale": 2})
	check(editor._doc._undo.size() == undo_count + 1 and Geometry.vector(editor._doc._find(a), "size") == Vector3(2, 4, 6), "group transform is one transaction with uniform relative scaling")
	await call_tool("undo")
	check(editor._doc.records == before, "group undo restores every record")
	await call_tool("select_objects", {"group_id": group_id})
	await call_tool("focus_selection")
	await settle()
	await call_tool("select_rectangle", {"from": [0, 0], "to": [editor._canvas.size.x, editor._canvas.size.y]})
	check(editor._selection_tools.ids.size() == 2, "canvas rectangle selects the complete group")
	await call_tool("duplicate_selection")
	check(editor._doc.records.size() == 4 and editor._doc._find(editor._selection_tools.ids[0]).editor_group != group_id, "duplicate creates independent group identities")
	await call_tool("delete_selection")
	check(editor._doc.records.size() == 2, "delete affects only selected copy")
	await call_tool("select_objects", {"group_id": group_id})
	await call_tool("ungroup_selection")
	check(not editor._doc._find(a).has("editor_group"), "ungroup clears member group identity")
	await call_tool("set_object_properties", {"ids": [a], "locked": true, "hidden": true})
	before = editor._doc.records.duplicate(true)
	undo_count = editor._doc._undo.size()
	await call_tool("set_object_transform", {"id": a, "position": [0, 0, 0]}, false)
	await call_tool("select_objects", {"ids": [b, a]}, false)
	await call_tool("set_object_properties", {"ids": [a], "name": "blocked"}, false)
	await call_tool("set_object_transform", {"id": b, "size": [0, 1, 1]}, false)
	await call_tool("transform_selection", {"scale": "large"}, false)
	await call_tool("set_object_properties", {"ids": [b], "asset_path": "outside"}, false)
	await call_tool("paint_auto_tiles", {"family": "road", "cell_size": 1, "points": [[0, 0, 0], [5000, 0, 0]]}, false)
	check(editor._doc.records == before and editor._doc._undo.size() == undo_count, "invalid/protected edits and oversized strokes leave document and history untouched")
	await call_tool("set_object_properties", {"ids": [a], "locked": false, "hidden": false, "name": "blocked"}, false)
	await call_tool("set_object_properties", {"ids": [a], "locked": false, "hidden": false})
	await call_tool("select_objects", {"ids": [a, b]})
	await call_tool("list_resource_packs")
	var prefab := await call_tool("save_prefab", {"name": "MCP 测试预制件", "pack_root": directory})
	var found := await call_tool("list_assets", {"query": "MCP 测试预制件"})
	check(found.total == 1 and found.assets[0].asset_id == prefab.get("asset_id"), "saved prefab discoverable in resource library")
	if prefab.has("asset_id"):
		await call_tool("place_asset", {"asset_id": prefab.asset_id, "position": [10, 0, 0]})
		check(editor._selection_tools.ids.size() == 2 and editor._doc.records.size() == 4, "prefab placement restores editable component selection")
	undo_count = editor._doc._undo.size()
	await call_tool("paint_auto_tiles", {"family": "road", "points": [[0, 0, 20], [8, 0, 20]], "cell_size": 4})
	var roads: Array = editor._doc.records.filter(func(r): return r.get("tile3d", {}).get("family") == "road")
	check(roads.size() == 3 and roads[1].tile3d.mask == 10 and editor._doc._undo.size() == undo_count + 1, "road stroke interpolates three connected cells with one undo")
	await call_tool("paint_auto_tiles", {"family": "wall", "points": [[0, 0, 24], [4, 0, 24]], "cell_size": 4, "height": 2})
	await call_tool("paint_auto_tiles", {"family": "grass", "points": [[20, 0, 20], [24, 0, 20]]})
	await call_tool("paint_auto_tiles", {"family": "dirt", "points": [[20, 0, 24]]})
	await call_tool("paint_auto_tiles", {"family": "water", "points": [[24, 0, 24]]})
	var grass: Array = editor._doc.records.filter(func(r): return r.get("tile3d", {}).get("family") == "grass")
	check(grass.size() == 2 and grass[0].tile3d.neighbors.has("dirt") and grass[1].tile3d.neighbors.has("water"), "terrain automatically tracks dirt and water transitions")
	await call_tool("paint_auto_tiles", {"family": "road", "points": [[4, 0, 20]], "erase": true})
	check(not roads.is_empty() and editor._doc._find(roads[0].uuid).tile3d.mask == 0, "erase repairs neighboring automatic geometry")
	await call_tool("undo")
	await call_tool("save_world")
	before = editor._doc.records.duplicate(true)
	await call_tool("set_object_properties", {"ids": [a], "name": "unsaved"})
	await call_tool("open_world", {"path": path}, false)
	await call_tool("open_world", {"path": path, "discard_changes": true})
	check(equivalent(editor._doc.records, before), "save/reopen preserves full 3D records, groups, prefab transforms and auto rules")
	await call_tool("save_world", {"path": "D:/outside_mcp_test.gltf"}, false)
	var malformed := directory.path_join("invalid.gltf")
	var file := FileAccess.open(malformed, FileAccess.WRITE)
	file.store_string('{"buffers":42}'); file.close()
	await call_tool("open_world", {"path": malformed}, false)
	editor._stroke.begin(editor._doc)
	await call_tool("select_objects", {"ids": [a]}, false)
	await call_tool("editor_state")
	editor._stroke.end()
	editor._load_failed = true
	await call_tool("delete_selection", {}, false)
	editor._load_failed = false
	var invalid_rpc := await rpc("tools/call", {"name": "editor_state", "arguments": []})
	check(invalid_rpc.get("error", {}).get("code") == -32602, "non-object arguments produce protocol error")
	if DisplayServer.get_name() == "headless": await call_tool("preview_map", {}, false)
	else:
		await RenderingServer.frame_post_draw
		var preview := await rpc("tools/call", {"name": "preview_map", "arguments": {}})
		var content: Array = preview.get("result", {}).get("content", [])
		var valid_png := false
		for part in content:
			if part.type == "image":
				var image := Image.new()
				valid_png = image.load_png_from_buffer(Marshalls.base64_to_raw(part.data)) == OK and image.get_width() > 100
		check(valid_png, "graphical MCP returns actual PNG image content")
	var hostile := ("POST /mcp HTTP/1.1\r\nHost: evil.example\r\nContent-Length: 0\r\n\r\n").to_utf8_buffer()
	check(not editor._mcp._extract_http(hostile).get("ok", false), "untrusted Host header rejected")
	editor._mcp.stop()
	editor.queue_free()
	await settle()
	session.world3d_editor_doc = null
	session.world3d_editor_path = ""
	Io._remove_tree(directory)
	print("test_world3d_mcp: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)
