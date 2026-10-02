extends SceneTree
## Read-only map/background and isolated entry interaction review; GPU on private desktop.
const Net = preload("res://scripts/net/net.gd")
const Background = preload("res://scripts/ui/entry_background.gd")
class ServerSpy extends Node:
	signal login_finished(ok: bool, message: String)
	signal characters_ready(characters: Array)
	var item_catalog
	var calls: Array = []
	func login(user, password, address): calls.append([user, password, address])
	func fetch_characters(): pass
class SessionSpy extends Node:
	var username := "旅人"
	var server_address := "127.0.0.1:7777"
	var characters: Array = []
	var selected_character := {}
	var pending_select_id := -1
	var spawn_data := {}
	var pending_world3d_playtest := false
	var world3d_map_path := ""
	var world3d_spawn := Vector3.ZERO
	var editor_return := false
	var world3d_switches := {}
	var loading_mode := ""
	var destinations: Array = []
	func go_character_select(): destinations.append("select")
	func go_character_create(): destinations.append("create")
	func go_login(): destinations.append("login")
	func go_loading(): destinations.append("world")
var failures := 0
var checks := 0
var out_dir := ""

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + message)

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Entry UI timed out"); quit(2))
	root.get_node("GameSettings").persist_enabled = false
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720); DisplayServer.window_set_size(root.size)
	out_dir = preload("res://scripts/asset/art_paths.gd").review_path("entry")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var server := ServerSpy.new(); server.item_catalog = Net.server().get("item_catalog"); root.add_child(server)
	var session := SessionSpy.new(); root.add_child(session)
	Net._server_override = server; Net._session_node = session
	var map_path := Background.resolve_map()
	var default_pack: Variant = ProjectSettings.get_setting("rmmo/default_pack")
	ProjectSettings.set_setting("rmmo/default_pack", "__entry_missing_pack")
	expect(Background.resolve_map().is_empty(), "missing pack degrades without creating a map")
	ProjectSettings.set_setting("rmmo/default_pack", default_pack)
	var entry_map: Variant = ProjectSettings.get_setting("rmmo/entry_map")
	ProjectSettings.set_setting("rmmo/entry_map", "__entry_missing_map")
	expect(not Background.resolve_map().is_empty(), "missing preferred map falls back within same pack")
	ProjectSettings.set_setting("rmmo/entry_map", entry_map)
	var before := FileAccess.get_sha256(map_path)
	var login = load("res://scenes/login.tscn").instantiate(); root.add_child(login)
	var background = login.get_node("EntryBackground")
	while not background.loaded and background.load_error.is_empty(): await process_frame
	expect(background.loaded, "existing default-pack map renders: " + background.load_error)
	expect(background.map_path.contains("/packs/default/maps/"), "map comes from configured default pack")
	expect(background._world.find_children("*", "Camera3D", true, false).size() == 1, "independent presentation camera")
	expect(background._world.find_children("*", "PhysicsBody3D", true, false).is_empty(), "background does not start gameplay physics")
	await shot("login")
	expect(login.pass_edit.secret and login.pass_edit.text.is_empty(), "password masked and never prefilled")
	await click(login._show_password)
	expect(not login.pass_edit.secret, "show-password pointer toggle")
	await click(login._show_password)
	await click(login._connection_toggle)
	expect(login._connection.visible, "connection settings expand")
	login.user_edit.text = "traveler"; login.pass_edit.text = "wrong"
	login.pass_edit.grab_focus(); await key(KEY_ENTER)
	expect(server.calls.size() == 1 and login.login_btn.disabled and not login.user_edit.editable, "Enter submits and locks pending identity")
	await key(KEY_ENTER); login._on_login_pressed()
	expect(server.calls.size() == 1, "repeat submit ignored while pending")
	server.login_finished.emit(false, "密码不正确，请重试")
	expect(not login.login_btn.disabled and login.user_edit.editable and login.user_edit.text == "traveler", "failed login restores controls and retains identity")
	await shot("login_error")
	root.size = Vector2i(800, 600); DisplayServer.window_set_size(root.size)
	await frames()
	expect(login._scroll.get_global_rect().end.x <= 800 and login._scroll.get_global_rect().end.y <= 600, "compact login stays within window")
	await shot("login_compact")
	login.free()
	root.size = Vector2i(1280, 720); DisplayServer.window_set_size(root.size)
	var select = load("res://scenes/character_select.tscn").instantiate(); root.add_child(select)
	background = select.get_node("EntryBackground")
	while not background.loaded and background.load_error.is_empty(): await process_frame
	expect(select.enter_btn.disabled, "enter disabled until character response")
	server.characters_ready.emit([]); await frames()
	expect(select.enter_btn.disabled and not select.create_btn.disabled and select._portrait.texture == null, "empty roster offers create without stale preview")
	await shot("select_empty")
	var characters := [
		{"id": 41, "name": "艾林", "gender": "male", "class_id": "warrior", "level": 12, "equipment": []},
		{"id": 42, "name": "霜月", "gender": "female", "class_id": "mage", "level": 8, "equipment": []},
	]
	for character in characters:
		for item in preload("res://scripts/char/starter_equipment.gd").ITEMS:
			character.equipment.append({"slot": item.equip_slot, "item_id": item.id})
	session.pending_select_id = 41
	server.characters_ready.emit(characters); await frames()
	expect(select.list.get_selected_items()[0] == 0 and select._identity.text == "艾林", "preferred selection and preview agree")
	await shot("select")
	select.list.grab_focus(); await key(KEY_DOWN)
	expect(select.list.get_selected_items()[0] == 1 and select._identity.text == "霜月", "arrow key changes selected character and preview")
	expect(select.find_children("CharacterViewport", "SubViewport", true, false).size() == 1, "single live character viewport for entire roster")
	await click(select._turn_right)
	expect(select._view.model.direction == "front_right", "rotation button changes preview facing")
	await shot("select_second")
	root.size = Vector2i(800, 600); DisplayServer.window_set_size(root.size); await frames()
	expect(select._scroll.get_global_rect().end.x <= 800 and select._scroll.get_global_rect().end.y <= 600, "compact roster stays within window")
	await shot("select_compact")
	select.list.grab_focus(); await key(KEY_ENTER)
	expect(session.destinations == ["world"] and session.selected_character.id == 42, "Enter starts the selected character")
	select._on_enter()
	expect(session.destinations == ["world"], "world entry is single-shot")
	expect(FileAccess.get_sha256(map_path) == before, "source map is unchanged")
	select.free()
	await font_capture()
	Net._server_override = null; Net._session_node = null
	print("ENTRY UI: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)

func frames() -> void:
	for i in 4: await process_frame
func font_capture() -> void:
	root.size = Vector2i(1280, 720); DisplayServer.window_set_size(root.size)
	var surface := ColorRect.new(); surface.color = Color("202228")
	root.add_child(surface); surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style = preload("res://scripts/ui/entry_style.gd")
	for column in 2:
		var host := Control.new(); surface.add_child(host)
		host.position = Vector2(48 + column * 620, 32)
		host.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if column == 0 else CanvasItem.TEXTURE_FILTER_LINEAR
		host.theme = preload("res://scripts/ui/l2_style.gd").hud_theme().duplicate()
		if column == 0:
			var old_font := host.theme.default_font.duplicate(); old_font.msdf_size = 48
			host.theme.default_font = old_font
		host.add_child(style.label("原采样" if column == 0 else "修复后", 24, style.GOLD))
		for row in 3:
			var sample := VBoxContainer.new(); host.add_child(sample)
			sample.position = Vector2(0, 70 + row * 192); sample.scale = Vector2.ONE * (1 + row * .25)
			sample.add_child(style.label("%d%% · 系统设置 / 背包 / 金币" % (100 + row * 25), 14))
			sample.add_child(style.label("欢迎归来", 30))
			sample.add_child(style.label("RMMO  0123456789", 24))
	await shot("text_sampling_comparison")
	surface.free()
func shot(name: String) -> void:
	await frames(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
func click(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed; event.position = control.get_global_rect().get_center(); event.global_position = event.position
		Input.parse_input_event(event); await process_frame
func key(code: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new(); event.keycode = code; event.pressed = pressed
		Input.parse_input_event(event); await process_frame
