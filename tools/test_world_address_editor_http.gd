extends "res://tools/test_world3d_mcp.gd"
const AddressTools = preload("res://scripts/world_editor/world_address_tools.gd")
const MapCatalog = preload("res://scripts/world_editor/world_map_catalog.gd")
var fixture_root := ""
var map_path := ""
var second_path := ""

func write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data)); file.close()

func directory_state(listing: Dictionary) -> Dictionary:
	return listing.documents[0]

func history_args(state_: Dictionary) -> Dictionary:
	return {"document_id":state_.document_id, "expected_edit_revision":state_.edit_revision}

func pick_row(dialog: Window, path: String, document_id: String = "") -> void:
	var tree: Tree = dialog.find_child("WorldMapTree", true, false)
	var row := tree.get_root().get_first_child()
	while row != null:
		if row.get_metadata(0).path == path and (document_id.is_empty() or row.get_metadata(0).document_id == document_id):
			row.select(0)
			tree.item_selected.emit()
			return
		row = row.get_next()
	check(false, "UI map row exists")

func press(dialog: Window, name_: String) -> void:
	var button := dialog.find_child(name_, true, false) as Button
	check(button != null and not button.disabled, "UI " + name_ + " enabled")
	if button != null and not button.disabled: button.pressed.emit()

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1600, 1000)
	fixture_root = Paths.external_root().path_join("cache/world_address_http_%d" % Time.get_ticks_usec())
	var pack_root := fixture_root.path_join("packs/wa_http")
	write_json(pack_root.path_join("metadata.json"), {"id":"wa_http", "name":"地址验证资源包", "version":"1"})
	map_path = pack_root.path_join("maps/legacy_town/map.gltf")
	second_path = pack_root.path_join("maps/Map0002.gltf")
	var doc := Doc.new()
	doc.map_meta.map_ref = "wa_http/first"
	doc.add_box_silent("ground", Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	var object_id: String = doc.add_box_silent("block", Vector3(2.125, 1, -3.5), Vector3.ONE)
	check(doc.save(map_path) == OK, "legacy filename map fixture saved externally")
	var second := Doc.new(); second.map_meta.map_ref = "wa_http/second"
	second.add_box_silent("ground", Vector3.ZERO, Vector3(2, 0.2, 2))
	check(second.save(second_path) == OK, "numeric filename fixture saved externally")
	var before_sha := FileAccess.get_sha256(map_path)
	var second_sha := FileAccess.get_sha256(second_path)
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc = doc; session.world3d_editor_path = map_path
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._draft_directory = fixture_root.path_join("drafts")
	editor._world_address_tools = AddressTools.new(editor, fixture_root)
	root.add_child(editor); editor._safety.enabled = false
	await settle()
	var probe := TCPServer.new(); port = 28930
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop()
	check(editor.start_mcp(port).ok, "isolated loopback HTTP MCP starts")
	var definitions: Array = (await rpc("tools/list")).result.tools
	var names := definitions.map(func(item): return item.name)
	check(AddressTools.tool_specs().all(func(item): return names.has(item.name)) and not names.has("paint_tile"), "all D1 tools discovered through current 3D HTTP")
	var listing := await call_tool("list_world_maps")
	await call_tool("list_world_maps", {"offset":1.0e100}, false)
	check(listing.maps.size() == 2 and listing.maps.all(func(row): return row.status == "unregistered"), "discovery never assigns numbers")
	var state_ := directory_state(listing)
	var catalog_path: String = state_.path
	check(not FileAccess.file_exists(catalog_path), "read-only discovery creates no catalogue file")
	await call_tool("select_objects", {"ids":[object_id]})
	await call_tool("get_current_world_address", {"anchor_kind":"object_origin"}, false)
	var history: int = editor._doc._undo.size()
	var records: Array = editor._doc.records.duplicate(true)
	await call_tool("register_world_map", {"entry_id":"missing", "map_number":"1", "expected_edit_revision":0}, false)
	await call_tool("register_world_map", {"entry_id":listing.maps[0].entry_id, "map_number":1, "expected_edit_revision":0}, false)
	await call_tool("register_world_map", {"entry_id":listing.maps[0].entry_id, "map_number":"1", "expected_edit_revision":99}, false)
	for menu: Node in editor.find_children("*", "MenuButton", true, false):
		if menu.text == "文件": menu.get_popup().id_pressed.emit(8); break
	await settle()
	var dialog := editor.get_node_or_null("WorldAddressDialog") as Window
	check(dialog != null and dialog.visible, "File menu opens real world address UI")
	if dialog == null: quit(1); return
	pick_row(dialog, map_path)
	var number: LineEdit = dialog.find_child("MapNumberInput", true, false)
	number.text = "0001"; number.text_changed.emit(number.text)
	press(dialog, "RegisterWorldMapButton")
	listing = await call_tool("list_world_maps")
	state_ = directory_state(listing)
	check(state_.dirty and listing.maps.any(func(row): return row.path == map_path and row.map_number == "1"), "UI registration visible to HTTP with normalized number")
	check(not FileAccess.file_exists(catalog_path), "registration remains an explicit unsaved directory edit")
	await call_tool("close_editor", {"action":"save"}, false)
	await call_tool("close_editor", {"action":"discard"}, false)
	var current := await call_tool("get_current_world_address", {"anchor_kind":"object_origin"})
	check(current.address == "wa_http:1:2.125,1,-3.5" and not current.persisted, "selected object address preserves author origin and unsaved status")
	var saved_camera: Transform3D = editor._camera.transform
	var parsed := await call_tool("resolve_world_address", {"address":"wa_http:0001:-32.01,5.125,100"})
	check(parsed.map_ref == "wa_http/first" and parsed.anchor_kind == "point" and not parsed.can_transfer and parsed.surface_id == null, "address resolution gives no landing or world-layout authority")
	check(abs(parsed.position_m[0] + 32.01) < 0.000001 and editor._camera.transform == saved_camera, "read-only resolution preserves negative decimal and camera")
	var precise := await call_tool("resolve_world_address", {"address":"wa_http:1:999999999999.125,-123456789012.125,0"})
	check(abs(precise.position_m[0] - 999999999999.125) <= 0.001 and abs(precise.position_m[1] + 123456789012.125) <= 0.001, "actual HTTP structured coordinates retain millimeter precision at address envelope")
	for value: String in ["wa_http:1:1,2", "wa_http:1:NaN,0,0", "wa_http:9223372036854775808:0,0,0", "wa_http:1:1,2,3,4"]:
		await call_tool("resolve_world_address", {"address":value}, false)
	var address: LineEdit = dialog.find_child("WorldAddressInput", true, false)
	address.text = "wa_http:0001:-32.01,5.125,100"; address.text_changed.emit(address.text)
	press(dialog, "ResolveWorldAddressButton")
	var canonical: LineEdit = dialog.find_child("WorldAddressResult", true, false)
	check(canonical.text == parsed.address, "UI and HTTP use identical canonical resolver")
	var undo := await call_tool("undo_world_edit", history_args(state_))
	check(undo.document.dirty, "undo reserves allocated number as a tombstone")
	await call_tool("resolve_world_address", {"address":"wa_http:1:0,0,0"}, false)
	dialog.refresh(); pick_row(dialog, map_path)
	press(dialog, "RedoWorldCatalogButton")
	listing = await call_tool("list_world_maps"); state_ = directory_state(listing)
	var second_row: Dictionary = listing.maps.filter(func(row): return row.path == second_path)[0]
	await call_tool("register_world_map", {"entry_id":second_row.entry_id, "map_number":"3", "expected_edit_revision":state_.edit_revision}, false)
	var added := await call_tool("register_world_map", {"entry_id":second_row.entry_id, "map_number":"2", "expected_edit_revision":state_.edit_revision})
	dialog.refresh(); pick_row(dialog, map_path)
	press(dialog, "SaveWorldCatalogButton")
	listing = await call_tool("list_world_maps"); state_ = directory_state(listing)
	check(FileAccess.file_exists(catalog_path) and not state_.dirty, "UI saves the separate catalogue atomically")
	var reopened := MapCatalog.new(fixture_root)
	check(reopened.resolve_address("wa_http:1:2.125,1,-3.5").ok and reopened.resolve_address("wa_http:2:0,0,0").ok, "fresh service reopens both persisted identities")
	var saved_catalog_sha := FileAccess.get_sha256(catalog_path)
	await call_tool("save_world_catalog", history_args(state_).merged({"expected_disk_sha":"incorrect"}), false)
	check(FileAccess.get_sha256(catalog_path) == saved_catalog_sha, "invalid save baseline leaves persisted bytes unchanged")
	var undone := await call_tool("undo_world_edit", history_args(state_))
	dialog.refresh(); dialog.request_close()
	check(dialog.get_node("WorldCatalogCloseConfirmation").visible, "dirty directory close prompts instead of dropping edits")
	dialog.get_node("WorldCatalogCloseConfirmation").custom_action.emit("keep")
	check(not dialog.visible and editor._world_address_tools.has_dirty_catalogs(), "explicit close retains unsaved directory in session")
	editor._safety.request_exit(false)
	check(dialog.visible and is_instance_valid(editor), "editor exit reopens outstanding catalogue work")
	await call_tool("discard_world_catalog", history_args(undone.document))
	check(not editor._world_address_tools.has_dirty_catalogs(), "explicit discard reloads saved catalogue without touching maps")
	dialog.hide()
	await call_tool("set_editor_walk_mode", {"enabled":true, "position":[0,0,0]})
	for i in 6: await physics_frame
	var feet := await call_tool("get_current_world_address", {"anchor_kind":"feet"})
	check(feet.anchor_kind == "feet" and abs(feet.position_m[1]) < 0.05, "walk address uses actual capsule foot, not body or shape centre")
	await call_tool("get_current_world_address", {"anchor_kind":"feet", "object_id":object_id}, false)
	await call_tool("set_editor_walk_mode", {"enabled":false})
	check(editor._doc.records == records and editor._doc._undo.size() == history, "directory operations preserve map records and map undo history")
	check(FileAccess.get_sha256(map_path) == before_sha and FileAccess.get_sha256(second_path) == second_sha, "original map filenames and bytes unchanged")
	var status := await call_tool("editor_state")
	check(status.world_addresses.phase == "D1" and not status.world_addresses.dirty and status.world_addresses.world_layout_available and not status.world_layouts.continuous_runtime_available, "editor diagnostics distinguish address and authoring layout from pending continuous runtime")
	var third := Doc.new(); third.map_meta.map_ref = "wa_http/third"
	third.add_box_silent("ground", Vector3.ZERO, Vector3(2,0.2,2))
	var third_path := pack_root.path_join("maps/orphan_demo/map.gltf")
	check(third.save(third_path) == OK, "orphan-draft map fixture saved externally")
	listing = await call_tool("list_world_maps"); state_ = directory_state(listing)
	var third_row: Dictionary = listing.maps.filter(func(row): return row.path == third_path)[0]
	await call_tool("register_world_map", {"entry_id":third_row.entry_id,"map_number":"3","expected_edit_revision":state_.edit_revision})
	var metadata_path := pack_root.path_join("metadata.json")
	check(Paths.allowed(metadata_path, fixture_root), "orphan fixture mutation confined to temporary root")
	check(DirAccess.remove_absolute(metadata_path) == OK, "temporary pack becomes unavailable")
	listing = await call_tool("list_world_maps")
	check(listing.documents.any(func(item): return item.document_id == state_.document_id and item.dirty), "unavailable dirty catalogue stays discoverable")
	dialog.refresh(); pick_row(dialog, catalog_path, state_.document_id)
	press(dialog, "DiscardWorldCatalogButton")
	dialog.get_node("WorldCatalogDiscardConfirmation").confirmed.emit()
	check(not editor._world_address_tools.has_dirty_catalogs() and not FileAccess.file_exists(metadata_path), "UI can abandon unavailable draft without recreating package")
	write_json(metadata_path, {"id":"wa_http", "name":"地址验证资源包", "version":"1"})
	await call_tool("resolve_world_address", {"address":"wa_http:2:0,0,0"})
	write_json(metadata_path, {"id":"wa_http", "name":"地址验证资源包", "version":"2"})
	listing = await call_tool("list_world_maps"); state_ = directory_state(listing)
	check(state_.read_only and not state_.dirty and state_.reason_code == "pack_revision_changed", "clean catalogue reports externally changed package metadata")
	await call_tool("resolve_world_address", {"address":"wa_http:2:0,0,0"}, false)
	dialog.refresh(); pick_row(dialog, map_path, state_.document_id)
	press(dialog, "DiscardWorldCatalogButton")
	dialog.get_node("WorldCatalogDiscardConfirmation").confirmed.emit()
	await call_tool("resolve_world_address", {"address":"wa_http:2:0,0,0"})
	check(FileAccess.get_sha256(catalog_path) == saved_catalog_sha, "UI reload accepts new package revision without rewriting saved catalogue")
	dialog.refresh(); dialog.popup_centered_clamped(Vector2i(940,730),0.9)
	address.text = "wa_http:1:-32.01,5.125,100"; address.text_changed.emit(address.text)
	press(dialog, "ResolveWorldAddressButton")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := dialog.get_texture().get_image()
		var screenshot := Paths.external_root().path_join("review_artifacts/world_address_d1_20261101/ui.png")
		check(image != null and image.get_width() > 600 and image.save_png(screenshot) == OK, "real UI render captured outside project")
		var clipboard_capture := {"text":""}
		dialog.clipboard_writer = func(text: String): clipboard_capture.text = text
		press(dialog, "CopyWorldAddressButton")
		check(clipboard_capture.text == parsed.address, "real UI copy action matches HTTP without replacing user clipboard")
	editor._mcp.stop(); dialog.hide(); editor.queue_free(); await settle()
	session.world3d_editor_doc = null; session.world3d_editor_path = ""
	print("WORLD_ADDRESS_HTTP_FIXTURE ", fixture_root)
	print("test_world_address_editor_http: ", "PASS" if failed == 0 else "FAIL (%d)" % failed)
	quit(0 if failed == 0 else 1)
