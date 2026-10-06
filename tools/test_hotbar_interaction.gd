extends SceneTree
## Real viewport input + persistence regression; GPU captures via run_godot_background.py.
var failures := 0
var checks := 0
var hud
var logic
var combat
var last_mouse := Vector2.ZERO
var capture := false
var out_dir := ""

class CombatRecorder extends Node:
	var calls: Array = []
	func request_use_skill(id: String) -> void:
		calls.append(["skill", id])
	func request_use_item(id: String) -> void:
		calls.append(["item", id])

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures += 1

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	var gs = root.get_node("GameSettings")
	gs.persist_enabled = false
	gs.window_layouts = {}
	gs.hotbar_profiles = {}
	gs.hotbar_rows = 2
	gs.hotbar_locked = false
	gs.hud_locked = false
	gs.ui_scale = 1.0
	_expect(gs.set_keybind("inventory", KEY_1) == "快捷栏", "settings reject shortcuts reserved by the hotbar")
	root.content_scale_size = Vector2i.ZERO
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 800)
	if capture:
		DisplayServer.window_set_size(root.size)
	out_dir = preload("res://scripts/asset/art_paths.gd").review_path("hotbar")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var sess = root.get_node("GameSession")
	sess.selected_character = {"id": 99123, "name": "快捷栏测试"}
	sess.hotbar_initialized = false
	sess.hotbar_bindings = {}
	sess.hotbar_profile_key = ""
	var bg := ColorRect.new()
	bg.color = Color("202c30")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	hud = load("res://scenes/ui/game_hud.tscn").instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat = CombatRecorder.new()
	root.add_child(combat)
	hud._world_combat = combat
	logic = hud._skills_panel_logic
	hud._server_skills = [
		{"id": "basic_attack", "name": "普通攻击", "icon_index": 76},
		{"id": "power_strike", "name": "强力打击", "icon_index": 77},
		{"id": "heal_light", "name": "轻度治疗", "icon_index": 112},
		{"id": "weapon_mastery", "name": "武器精通", "category": "passive"}]
	hud._server_inventory = [{"id": "potion_hp_small", "qty": 12}, {"id": "potion_mp_small", "qty": 8}]
	await _settle()
	var panel = hud.get_node("%HotbarPanel")
	panel.move_to_front()
	_expect(not panel.get_global_rect().intersects(hud.get_node("%ChatPanel").get_global_rect().grow(8)), "default hotbar does not overlap chat or its tabs")
	logic._refresh_hotbar_slot_visuals()
	_expect(hud.hotbar.get_child_count() == 2 and hud._iter_skill_cells(hud.hotbar).size() == 24, "two rows, 24 slots by default")
	_expect(panel.get_theme_stylebox("panel") is StyleBoxEmpty and not hud.find_child("HotbarNav", true, false).visible, "floating hotbar has no outer frame or title toolbar")
	var page_handle: Control = hud.find_child("HotbarGrip", true, false).get_node("PageNumber")
	await _pointer(page_handle.get_global_rect().get_center(), true, MOUSE_BUTTON_RIGHT)
	await _pointer(page_handle.get_global_rect().get_center(), false, MOUSE_BUTTON_RIGHT)
	_expect(logic._hotbar_settings.visible and logic._hotbar_settings.get_item_index(13) >= 0, "right-click page number exposes row settings")
	await _shot("settings_menu")
	logic._hotbar_settings.hide()
	_expect(_cell(0, 1).bound_id == "basic_attack", "default actions have visible bindings")
	await _click(_center(0, 1))
	_expect(combat.calls == [["skill", "basic_attack"]], "click activates exactly once")
	combat.calls.clear()
	await _drag(_center(0, 1), _center(0, 2))
	_expect(_id(0, 1) == "power_strike" and _id(0, 2) == "basic_attack", "actual mouse drag swaps occupied slots")
	_expect(combat.calls.is_empty(), "rearranging does not cast")
	await _drag(_center(0, 2), _center(1, 6))
	_expect(_id(0, 2).is_empty() and _id(1, 6) == "basic_attack", "cross-row drag moves to empty slot")
	var before: Dictionary = hud._hotbar_bindings.duplicate(true)
	await _drag(_center(0, 4), Vector2(1180, 370))
	_expect(hud._hotbar_bindings == before, "dropping outside retains binding")
	_expect(not hud._ground_drop_armed, "hotbar item drag cannot discard inventory")
	await _motion(_center(0, 1))
	await _pointer(_center(0, 1), true)
	await _motion(_center(0, 1) + Vector2(16, -12), true)
	await _motion(Vector2(1130, 360), true)
	_expect(root.gui_is_dragging(), "drag threshold starts native drag")
	await _key(KEY_4, true)
	_expect(hud._hotbar_page == 0, "page shortcuts cannot retarget an active drag")
	await _key(KEY_ESCAPE)
	await _pointer(Vector2(1130, 360), false)
	_expect(hud._hotbar_bindings == before and combat.calls.is_empty(), "Escape cancels without loss or use")
	await _click(hud.find_child("HotbarLock", true, false).get_global_rect().get_center())
	_expect(logic._hotbar_locked, "lock toggle responds to mouse")
	await _drag(_center(0, 1), _center(0, 2))
	_expect(hud._hotbar_bindings == before and combat.calls.is_empty(), "locked drag neither edits nor casts")
	await _click(_center(0, 1))
	_expect(combat.calls == [["skill", "power_strike"]], "locked slots remain usable")
	combat.calls.clear()
	_expect(not logic._can_hotbar_drop(0, 8, {"kind": "skill", "skill_id": "basic_attack"}), "locked rejects incoming drops")
	logic._set_hotbar_locked(false)
	# Ctrl+drag copies without changing the source; modifier also drives row 2 keys.
	await _key_state(KEY_CTRL, true)
	await _drag(_center(0, 1), _center(1, 8))
	await _key_state(KEY_CTRL, false)
	_expect(_id(0, 1) == "power_strike" and _id(1, 8) == "power_strike", "Ctrl+drag copies across rows")
	before = hud._hotbar_bindings.duplicate(true)
	logic._on_hotbar_drop(0, 8, {"kind": "hotbar", "source_page": 0, "source_slot": 1, "binding": {"kind": "skill", "id": "stale"}})
	logic._on_hotbar_drop(9, 30, {"kind": "item", "item_id": "potion_hp_small"})
	logic._on_hotbar_drop(0, 8, {"kind": "skill", "skill_id": "weapon_mastery"})
	_expect(hud._hotbar_bindings == before, "stale, invalid and passive drops are side-effect free")
	# External skill source uses the real SkillSlot drag handler.
	var source = preload("res://scripts/ui/skill_slot.gd").new()
	root.add_child(source)
	source.position = Vector2(780, 380)
	source.size = Vector2(42, 42)
	source.skill_id = "heal_light"
	source.display_name = "轻度治疗"
	var used: Array = []
	source.activated.connect(func(id: String): used.append(id))
	await _drag(source.get_global_rect().get_center(), _center(1, 10))
	_expect(_id(1, 10) == "heal_light" and source.skill_id == "heal_light", "skill list drag copies binding")
	_expect(used.is_empty(), "skill list drag does not activate source")
	source.queue_free()
	var bag_source = preload("res://scripts/ui/inv_slot.gd").new()
	root.add_child(bag_source)
	bag_source.position = Vector2(780, 380)
	bag_source.size = Vector2(42, 42)
	bag_source.setup("potion_mp_small", 8, "魔法药水")
	await _drag(bag_source.get_global_rect().get_center(), _center(1, 12))
	_expect(_id(1, 12) == "potion_mp_small" and bag_source.qty == 8, "bag drag registers shortcut without consuming item")
	bag_source.queue_free()
	# Right click opens an explicit menu instead of clearing immediately.
	await _pointer(_center(0, 1), true, MOUSE_BUTTON_RIGHT)
	await _pointer(_center(0, 1), false, MOUSE_BUTTON_RIGHT)
	_expect(_cell(0, 1)._menu.visible and _id(0, 1) == "power_strike", "right click opens menu without removing")
	_expect(Vector2(_cell(0, 1)._menu.position).distance_to(_center(0, 1)) < 100, "context menu opens beside its slot")
	await _shot("context_menu")
	_cell(0, 1)._menu.hide()
	_cell(0, 1)._on_menu_action(1)
	_expect(_id(0, 1).is_empty(), "explicit remove clears binding")
	await _key(KEY_1)
	await _click(_center(0, 1))
	_expect(combat.calls.is_empty(), "cleared default slot is truly empty for keyboard and click")
	logic._set_hotbar_rows(3)
	await _settle()
	_expect(hud._iter_skill_cells(hud.hotbar).size() == 36, "three visible rows")
	logic._set_hotbar_binding(2, 1, "skill", "heal_light")
	logic._set_hotbar_binding(3, 1, "skill", "power_strike")
	logic._set_hotbar_binding(4, 1, "item", "potion_hp_small")
	var saved_rect: Rect2 = panel.get_global_rect()
	await _key(KEY_3, true)
	_expect(hud._hotbar_page == 2 and _cell(0, 1).page == 2 and _cell(2, 1).page == 4, "Shift+3 switches displayed pages and metadata")
	_expect(panel.get_global_rect() == saved_rect, "page switching preserves layout")
	await _key(KEY_1)
	await _key(KEY_F1)
	await _key(KEY_1, false, true)
	await _key(KEY_1, false, false, true)
	_expect(combat.calls == [["skill", "heal_light"], ["skill", "heal_light"], ["skill", "power_strike"], ["item", "potion_hp_small"]], "visible row keys, F-key alias, Ctrl and Alt route correctly")
	combat.calls.clear()
	await _key(KEY_1, false, true, true)
	await _key(KEY_1, true, true)
	_expect(combat.calls.is_empty() and hud._hotbar_page == 2, "unsupported modifier combinations never cast")
	logic._set_hotbar_binding(2, 11, "skill", "heal_light")
	logic._set_hotbar_binding(2, 12, "item", "potion_mp_small")
	await _key(KEY_MINUS)
	await _key(KEY_EQUAL)
	_expect(combat.calls == [["skill", "heal_light"], ["item", "potion_mp_small"]], "minus and equals are independent slots 11 and 12")
	combat.calls.clear()
	hud.chat_input.grab_focus()
	await _key(KEY_1)
	await _key(KEY_6, true)
	_expect(combat.calls.is_empty() and hud._hotbar_page == 2, "chat typing does not cast or change page")
	hud.chat_input.release_focus()
	await _key(KEY_6, true)
	await _key(KEY_PAGEDOWN, true)
	_expect(hud._hotbar_page == 0, "page 6 wraps to page 1")
	await _key(KEY_PAGEUP, true)
	_expect(hud._hotbar_page == 5, "previous-page shortcut wraps backwards")
	await _click(hud.find_child("HotbarNext", true, false).get_global_rect().get_center())
	_expect(hud._hotbar_page == 0, "mouse page control wraps and updates active page")
	await _click(hud.find_child("HotbarPrev", true, false).get_global_rect().get_center())
	_expect(hud._hotbar_page == 5, "upper page arrow also responds and wraps backwards")
	logic._select_hotbar_page(2)
	hud.note_skill_cooldown("power_strike", 8.0, 10.0)
	_expect(_cell(1, 1)._cd._cd_remaining > 7.0, "cooldown applies to secondary rows")
	logic._select_hotbar_page(3)
	_expect(_cell(0, 1)._cd._cd_remaining > 7.0, "cooldown survives page switching")
	logic._select_hotbar_page(2)
	hud._cast_active = true
	hud._cast_skill_id = "power_strike"
	hud._cast_duration = 4.0
	hud._cast_elapsed = 2.0
	logic._sync_skill_cast_overlays()
	_expect(_cell(1, 1)._cd._cast_frac > 0.4, "cast overlay applies across rows")
	hud._cast_active = false
	# Header drag and scale: slots don't move the panel, grip does.
	panel.global_position = Vector2(340, 560)
	var start: Vector2 = panel.global_position
	var grip: Control = hud.find_child("HotbarGrip", true, false).get_node("PageNumber")
	await _drag(grip.get_global_rect().get_center(), grip.get_global_rect().get_center() + Vector2(32, -30))
	_expect(panel.global_position.distance_to(start) > 20.0, "dedicated grip moves the hotbar")
	_expect(gs.window_layout("hotbar").has("x"), "hotbar position is saved")
	logic._set_hotbar_locked(true)
	var saved_bindings: Dictionary = hud._hotbar_bindings.duplicate(true)
	var saved_page: int = hud._hotbar_page
	var saved_profile: String = logic._hotbar_profile_key()
	# Disk round-trip uses a separate file and a detached settings instance.
	var isolated = load("res://scripts/game/game_settings.gd").new()
	isolated.persist_path = out_dir.path_join("settings_test.cfg")
	isolated.hotbar_profiles = gs.hotbar_profiles.duplicate(true)
	isolated.hotbar_rows = gs.hotbar_rows
	isolated.hotbar_locked = gs.hotbar_locked
	isolated.save_to_disk()
	var reopened = load("res://scripts/game/game_settings.gd").new()
	reopened.persist_path = isolated.persist_path
	reopened.load_from_disk()
	_expect(reopened.hotbar_rows == 3 and reopened.hotbar_locked and reopened.hotbar_profiles[saved_profile].bindings == saved_bindings, "rows, lock and character bindings survive save/reopen")
	isolated.free()
	reopened.free()
	sess.hotbar_bindings = {}
	sess.hotbar_initialized = false
	sess.hotbar_profile_key = ""
	logic._restore_hotbar_from_session()
	_expect(hud._hotbar_bindings == saved_bindings and hud._hotbar_page == saved_page, "new login restores character profile")
	logic._set_hotbar_locked(false)
	logic._select_hotbar_page(0)
	_expect(_id(0, 1).is_empty(), "removed defaults stay removed after profile reload")
	sess.selected_character = {"id": 99124}
	logic._restore_hotbar_from_session()
	_expect(_id(0, 1) == "basic_attack" and _id(2, 1).is_empty(), "another character has independent bindings")
	sess.selected_character = {"id": 99123}
	logic._restore_hotbar_from_session()
	_expect(hud._hotbar_bindings == saved_bindings, "switching back restores original profile")
	# Readable representative preview of all three rows, then small-screen scaling.
	logic._select_hotbar_page(0)
	logic._set_hotbar_binding(0, 1, "skill", "basic_attack")
	logic._set_hotbar_binding(0, 2, "skill", "power_strike")
	logic._set_hotbar_binding(1, 1, "skill", "heal_light")
	logic._set_hotbar_binding(1, 2, "item", "potion_hp_small")
	logic._set_hotbar_binding(2, 2, "item", "potion_mp_small")
	panel.set_meta("hotbar_auto_position", true)
	hud._fit_hotbar_panel()
	await _motion(Vector2(1150, 350))
	await _shot("three_rows")
	if capture:
		var arrow: Control = hud.find_child("HotbarPrev", true, false)
		await _motion(arrow.get_global_rect().get_center())
		await _shot("pager_hover")
		await _pointer(arrow.get_global_rect().get_center(), true)
		await _shot("pager_pressed")
		await _pointer(arrow.get_global_rect().get_center(), false)
		logic._select_hotbar_page(0)
		await _motion(Vector2(1150, 350))
	logic._set_hotbar_rows(1)
	await _settle()
	_expect(hud._iter_skill_cells(hud.hotbar).size() == 12, "one-row layout remains available")
	combat.calls.clear()
	await _key(KEY_1, false, true)
	_expect(combat.calls.is_empty(), "hidden rows have no active modifier shortcuts")
	await _shot("one_row")
	logic._set_hotbar_rows(3)
	gs.ui_scale = 1.3
	gs.apply_hud_scale(hud)
	root.size = Vector2i(900, 700)
	if capture: DisplayServer.window_set_size(root.size)
	await _settle()
	await _settle()
	var visual: Rect2 = Rect2(panel.global_position, panel.size * hud.scale)
	_expect(visual.end.x <= 901 and visual.end.y <= 701, "three rows fit 900x700 at 130% scale")
	_expect(not panel.get_global_rect().intersects(hud.get_node("%ChatPanel").get_global_rect().grow(8)), "compact scaled default keeps chat clear")
	var chat_rect: Rect2 = hud.get_node("%ChatPanel").get_global_rect()
	_expect(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(chat_rect), "chat remains on-screen after resize and UI scaling")
	await _motion(Vector2(450, 180))
	await _shot("compact_130")
	hud._world_combat = null
	hud.queue_free()
	combat.queue_free()
	await _settle()
	print("test_hotbar_interaction: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _cell(row: int, slot: int):
	return hud.hotbar.get_child(row).get_child(slot)

func _id(page: int, slot: int) -> String:
	return str(logic._get_hotbar_binding(page, slot).get("id", ""))

func _center(row: int, slot: int) -> Vector2:
	return _cell(row, slot).get_global_rect().get_center()

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _click(pos: Vector2) -> void:
	await _motion(pos)
	await _pointer(pos, true)
	await _pointer(pos, false)

func _pointer(pos: Vector2, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	event.pressed = down
	event.position = pos
	event.global_position = pos
	Input.parse_input_event(event)
	await process_frame

func _motion(pos: Vector2, down := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.relative = pos - last_mouse
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	last_mouse = pos
	Input.parse_input_event(event)
	await process_frame

func _drag(start: Vector2, finish: Vector2) -> void:
	await _motion(start)
	await _pointer(start, true)
	await _motion(start + Vector2(15, -8), true)
	await _motion(finish, true)
	await _pointer(finish, false)
	await process_frame

func _key(code: int, shift := false, control := false, alt := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.ctrl_pressed = control
	event.alt_pressed = alt
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _key_state(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame

func _shot(label: String) -> void:
	if not capture: return
	await _settle()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out_dir.path_join(label + ".png"))
	if label in ["three_rows", "one_row"]:
		var panel: Control = hud.get_node("%HotbarPanel")
		img.get_region(Rect2i(panel.get_global_rect().grow(12))).save_png(out_dir.path_join(label + "_detail.png"))
