extends RefCounted
## UI panel: skills, hotbar, cooldowns, learn/respec.

var ctrl
func _init(c):
	ctrl = c

const UIRequest = preload("res://scripts/ui/ui_request.gd")
const Net = preload("res://scripts/net/net.gd")
const HotbarSlot = preload("res://scripts/ui/hotbar_slot.gd")
const SkillSlot = preload("res://scripts/ui/skill_slot.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const GRID_CELL := 42
const GRID_SEP := 4
const SKILL_COLS := 5
const SKILL_TABS := [
	["物理", "physical"],
	["魔法", "magic"],
	["被动", "passive"],
]
const HOTBAR_PAGE_COUNT := 6
const HOTBAR_KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
var _hotbar_rows := 1
var _hotbar_locked := false
const HotbarStyle = preload("res://scripts/ui/hotbar_style.gd")
var _lock_button: Button
var _prev_button: Button
var _next_button: Button
var _hotbar_settings: PopupMenu


func _session_hotbar_store() -> Node:
	var net = ctrl.get_node_or_null("/root/Net")
	if net != null and net.has_method("session"):
		return net.session()
	return ctrl.get_node_or_null("/root/GameSession")


func _hotbar_profile_key() -> String:
	var sess = _session_hotbar_store()
	if sess == null or not sess.selected_character.has("id") or bool(sess.editor_return):
		return ""
	return JSON.stringify([sess.server_address, sess.username, str(sess.selected_character.id)])


func _restore_hotbar_from_session() -> void:
	var sess = _session_hotbar_store()
	var gs = ctrl.get_node_or_null("/root/GameSettings")
	if gs != null:
		_hotbar_rows = clampi(gs.hotbar_rows, 1, 3)
		_hotbar_locked = gs.hotbar_locked
	var raw: Dictionary = {}
	var initialized := false
	var profile := _hotbar_profile_key()
	if sess != null:
		var legacy_session: bool = not sess.hotbar_initialized and sess.hotbar_profile_key.is_empty() and not sess.hotbar_bindings.is_empty()
		if legacy_session or (sess.hotbar_profile_key == profile and sess.hotbar_initialized):
			raw = sess.hotbar_bindings
			ctrl._hotbar_page = clampi(sess.hotbar_page, 0, HOTBAR_PAGE_COUNT - 1)
			initialized = true
		elif gs != null and not profile.is_empty() and gs.hotbar_profiles.get(profile) is Dictionary:
			var saved: Dictionary = gs.hotbar_profiles[profile]
			if saved.get("bindings") is Dictionary:
				raw = saved.bindings
				ctrl._hotbar_page = clampi(int(saved.get("page", 0)), 0, HOTBAR_PAGE_COUNT - 1)
				initialized = true
	ctrl._hotbar_bindings = {}
	for key in raw:
		var parts := str(key).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		if _valid_hotbar_slot(int(parts[0]), int(parts[1])) and _valid_hotbar_binding(raw[key]):
			ctrl._hotbar_bindings[ctrl._hotbar_bind_key(int(parts[0]), int(parts[1]))] = raw[key].duplicate(true)
	if not initialized:
		ctrl._hotbar_page = 0
		var defaults := ["basic_attack", "power_strike", "heal_light", "potion_hp_small", "potion_mp_small"]
		for i in defaults.size():
			ctrl._hotbar_bindings[ctrl._hotbar_bind_key(0, i + 1)] = {"kind": "skill" if i < 3 else "item", "id": defaults[i]}
	_persist_hotbar_to_session()


func _persist_hotbar_to_session() -> void:
	var sess = _session_hotbar_store()
	if sess == null:
		return
	sess.hotbar_page = ctrl._hotbar_page
	sess.hotbar_bindings = ctrl._hotbar_bindings.duplicate(true)
	sess.hotbar_initialized = true
	sess.hotbar_profile_key = _hotbar_profile_key()
	var gs = ctrl.get_node_or_null("/root/GameSettings")
	if gs != null and not sess.hotbar_profile_key.is_empty():
		gs.hotbar_profiles[sess.hotbar_profile_key] = {"page": ctrl._hotbar_page, "bindings": ctrl._hotbar_bindings.duplicate(true)}
		gs.save_to_disk()


func _valid_hotbar_slot(page: int, slot: int) -> bool:
	return page >= 0 and page < HOTBAR_PAGE_COUNT and slot >= 1 and slot <= 12


func _valid_hotbar_binding(value: Variant) -> bool:
	return value is Dictionary and str(value.get("kind", "")) in ["item", "skill"] and not str(value.get("id", "")).strip_edges().is_empty()


func _get_hotbar_binding(page: int, slot: int) -> Dictionary:
	return ctrl._hotbar_bindings.get(ctrl._hotbar_bind_key(page, slot), {})


func _set_hotbar_binding(page: int, slot: int, kind: String, id: String) -> void:
	if not _valid_hotbar_slot(page, slot):
		return
	var key: String = ctrl._hotbar_bind_key(page, slot)
	if kind.is_empty() or id.strip_edges().is_empty():
		ctrl._hotbar_bindings.erase(key)
	elif kind in ["item", "skill"]:
		ctrl._hotbar_bindings[key] = {"kind": kind, "id": id.strip_edges()}
	else:
		return
	_persist_hotbar_to_session()
	_refresh_hotbar_slot_visuals()


func _clear_hotbar_binding(page: int, slot: int) -> void:
	if not _hotbar_locked:
		_set_hotbar_binding(page, slot, "", "")


func _layout_hotbar_side_nav(prev: Node, next: Node) -> void:
	var panel = ctrl.get_node("%HotbarPanel")
	panel.drag_anywhere = true
	panel.resizable = false
	panel.min_size = Vector2.ZERO
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin = panel.get_node("HotbarMarg")
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	var nav = ctrl.find_child("HotbarNav", true, false)
	nav.hide()
	_prev_button = prev
	_next_button = next
	HotbarStyle.page_button(_prev_button, true)
	HotbarStyle.page_button(_next_button, false)
	_prev_button.tooltip_text = "上一页 · Shift+PageUp"
	_next_button.tooltip_text = "下一页 · Shift+PageDown"
	_hotbar_settings = PopupMenu.new()
	_hotbar_settings.name = "HotbarSettings"
	ctrl.add_child(_hotbar_settings)
	_hotbar_settings.id_pressed.connect(_on_hotbar_setting)


func _open_hotbar_settings(point: Vector2) -> void:
	if ctrl.get_viewport().gui_is_dragging():
		return
	_hotbar_settings.clear()
	_hotbar_settings.add_check_item("锁定图标", 1)
	_hotbar_settings.set_item_checked(0, _hotbar_locked)
	_hotbar_settings.add_separator()
	for count in range(1, 4):
		_hotbar_settings.add_radio_check_item("显示 %d 排" % count, 10 + count)
		_hotbar_settings.set_item_checked(_hotbar_settings.item_count - 1, count == _hotbar_rows)
	_hotbar_settings.add_separator()
	for page in HOTBAR_PAGE_COUNT:
		_hotbar_settings.add_radio_check_item("第 %d 页    Shift+%d" % [page + 1, page + 1], 100 + page)
		_hotbar_settings.set_item_checked(_hotbar_settings.item_count - 1, page == ctrl._hotbar_page)
	_hotbar_settings.position = Vector2i(point if _hotbar_settings.is_embedded() else ctrl.get_viewport().get_screen_transform() * point)
	_hotbar_settings.popup()


func _on_hotbar_setting(id: int) -> void:
	if id == 1:
		_set_hotbar_locked(not _hotbar_locked)
	elif id >= 11 and id <= 13:
		_set_hotbar_rows(id - 10)
	elif id >= 100 and id < 100 + HOTBAR_PAGE_COUNT:
		_select_hotbar_page(id - 100)


func _save_hotbar_preferences() -> void:
	var gs = ctrl.get_node_or_null("/root/GameSettings")
	if gs != null:
		gs.hotbar_rows = _hotbar_rows
		gs.hotbar_locked = _hotbar_locked
		gs.save_to_disk()


func _sync_hotbar_preferences() -> void:
	var gs = ctrl.get_node_or_null("/root/GameSettings")
	if gs == null:
		return
	var rows := clampi(gs.hotbar_rows, 1, 3)
	var rebuild := rows != _hotbar_rows
	_hotbar_rows = rows
	_hotbar_locked = gs.hotbar_locked
	if rebuild:
		_build_hotbar()
	else:
		_refresh_hotbar_slot_visuals()


func _set_hotbar_rows(count: int) -> void:
	if ctrl.get_viewport().gui_is_dragging():
		return
	_hotbar_rows = clampi(count, 1, 3)
	_save_hotbar_preferences()
	_build_hotbar()


func _set_hotbar_locked(locked: bool) -> void:
	_hotbar_locked = locked
	_save_hotbar_preferences()
	_refresh_hotbar_slot_visuals()


func _select_hotbar_page(page: int) -> void:
	if ctrl.get_viewport().gui_is_dragging():
		return
	ctrl._hotbar_page = posmod(page, HOTBAR_PAGE_COUNT)
	# Reuse cells: no freed drag sources and no layout jump on a keyboard page change.
	_refresh_hotbar_slot_visuals()
	_persist_hotbar_to_session()


func _hotbar_keycode_to_slot(keycode: int) -> Vector2i:
	var keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
	var index := keys.find(keycode)
	if keycode >= KEY_F1 and keycode <= KEY_F12:
		index = keycode - KEY_F1
	return Vector2i(ctrl._hotbar_page, index) if index >= 0 else Vector2i(-1, -1)


func _try_hotbar_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or ctrl._text_input_focused() or event.meta_pressed:
		return false
	var code := int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if event.shift_pressed:
		if event.ctrl_pressed or event.alt_pressed:
			return false
		if code >= KEY_1 and code <= KEY_6:
			_select_hotbar_page(code - KEY_1)
			return true
		if code in [KEY_PAGEUP, KEY_PAGEDOWN]:
			_select_hotbar_page(ctrl._hotbar_page + (-1 if code == KEY_PAGEUP else 1))
			return true
		return false
	if event.ctrl_pressed and event.alt_pressed:
		return false
	var slot := _hotbar_keycode_to_slot(code)
	if slot.x < 0:
		return false
	var row := 1 if event.ctrl_pressed else (2 if event.alt_pressed else 0)
	# F keys are legacy aliases for the first row only.
	if row >= _hotbar_rows or (row > 0 and code >= KEY_F1 and code <= KEY_F12):
		return false
	if not ctrl.get_viewport().gui_is_dragging():
		_on_hotbar_pressed((ctrl._hotbar_page + row) % HOTBAR_PAGE_COUNT, slot.y + 1, HOTBAR_KEYS[slot.y])
	return true


func _build_hotbar() -> void:
	# Keep the two existing page controls alive when the row count changes.
	var nav = ctrl.find_child("HotbarNav", true, false)
	for button in [_prev_button, _next_button]:
		if button != null and button.get_parent() != nav:
			button.reparent(nav)
	while ctrl.hotbar.get_child_count() > 0:
		var child: Node = ctrl.hotbar.get_child(0)
		ctrl.hotbar.remove_child(child)
		child.queue_free()
	ctrl.hotbar.add_theme_constant_override("separation", 5)
	for row_index in _hotbar_rows:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		ctrl.hotbar.add_child(row)
		var grip := VBoxContainer.new()
		grip.name = "HotbarGrip"
		grip.custom_minimum_size.x = 26
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grip.add_theme_constant_override("separation", 0)
		row.add_child(grip)
		if row_index == 0:
			_prev_button.reparent(grip)
		var label = preload("res://scripts/ui/hotbar_grip.gd").new()
		label.name = "PageNumber"
		label.panel = ctrl.get_node("%HotbarPanel")
		label.settings_requested.connect(_open_hotbar_settings)
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13 if row_index == 0 else 11)
		label.add_theme_color_override("font_color", Color(0.9, 0.87, 0.76) if row_index == 0 else Color(0.74, 0.72, 0.64))
		label.add_theme_constant_override("outline_size", 2)
		label.tooltip_text = "拖动页码移动 · 右键设置排数\nShift+1–6 选页；Shift+PageUp / PageDown 翻页"
		grip.add_child(label)
		if row_index == 0:
			_next_button.reparent(grip)
		for i in 12:
			var slot = HotbarSlot.new()
			slot.custom_minimum_size = Vector2(40, 40)
			slot.set_meta("hotbar_row", row_index)
			slot.activated.connect(_on_hotbar_pressed)
			slot.binding_dropped.connect(_on_hotbar_drop)
			slot.binding_cleared.connect(_on_hotbar_binding_cleared)
			slot.drop_validator = _can_hotbar_drop
			row.add_child(slot)
		if row_index == 0:
			_lock_button = Button.new()
			_lock_button.name = "HotbarLock"
			_lock_button.custom_minimum_size = Vector2(22, 40)
			_lock_button.toggle_mode = true
			HotbarStyle.quiet_button(_lock_button)
			_lock_button.toggled.connect(_set_hotbar_locked)
			_lock_button.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					_open_hotbar_settings(_lock_button.get_global_transform_with_canvas() * event.position)
			)
			row.add_child(_lock_button)
		else:
			var spacer := Control.new()
			spacer.custom_minimum_size.x = 22
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(spacer)
	_refresh_hotbar_slot_visuals()
	ctrl.call_deferred("_fit_hotbar_panel")


func _refresh_hotbar_slot_visuals() -> void:
	ctrl._sync_equipment_cache()
	if ctrl.hotbar == null:
		return
	if is_instance_valid(_lock_button):
		_lock_button.set_pressed_no_signal(_hotbar_locked)
		_lock_button.icon = preload("res://scripts/ui/l2_chrome.gd").glyph("lock" if _hotbar_locked else "unlock", Color(0.75, 0.73, 0.65))
		_lock_button.tooltip_text = ("已锁定 · 左键解锁" if _hotbar_locked else "可整理 · 左键锁定") + "\n右键设置排数和页面"
	for row_index in ctrl.hotbar.get_child_count():
		var row: Node = ctrl.hotbar.get_child(row_index)
		var page: int = (ctrl._hotbar_page + row_index) % HOTBAR_PAGE_COUNT
		row.get_node("HotbarGrip/PageNumber").text = str(page + 1)
		for i in 12:
			var btn = row.get_child(i + 1)
			btn.configure(page, i + 1)
			btn.editing_locked = _hotbar_locked
			var prefix := "" if row_index == 0 else ("C+" if row_index == 1 else "A+")
			var key_label: String = prefix + HOTBAR_KEYS[i]
			var key_tip: String = ("" if row_index == 0 else ("Ctrl+" if row_index == 1 else "Alt+")) + HOTBAR_KEYS[i]
			if row_index == 0:
				key_tip += " / F%d" % (i + 1)
			var binding := _get_hotbar_binding(page, i + 1)
			var kind := str(binding.get("kind", ""))
			var bid := str(binding.get("id", ""))
			var help := "\n%s · 第 %d 页 / 槽 %d\n%s" % [key_tip, page + 1, i + 1,
				"已锁定 · 点击使用" if _hotbar_locked else "点击使用 · 拖动交换 · Ctrl+拖动复制 · 右键菜单"]
			if kind == "item":
				var dname: String = ctrl._item_label(bid)
				var qty: int = ctrl._inventory_qty(bid)
				var tip: String = ctrl._equip_compare_tip(bid, ctrl._item_rarity_name_line(bid, dname) + " ×%d" % qty)
				btn.set_binding_visual(kind, ctrl._letter_avatar(dname), qty, tip + help, ctrl._item_icon_index(bid), ctrl._item_icon_ref(bid))
			elif kind == "skill":
				var sname := _skill_display_name(bid)
				btn.set_binding_visual(kind, ctrl._letter_avatar(sname), 0, sname + help, _skill_icon_index(bid), _skill_icon_ref(bid))
			else:
				btn.set_binding_visual("", "", 0, "%s · 第 %d 页 / 槽 %d\n%s" % [key_tip, page + 1, i + 1,
					"已锁定 · 解锁后拖入技能或物品" if _hotbar_locked else "从技能列表或背包拖入"])
			btn.set_key_hint(key_label)
			btn.set_bound_id(bid)
			ctrl._apply_slot_cooldown_visual(btn, kind, bid)
	_sync_hotbar_cast_overlays()


func _can_hotbar_drop(page: int, slot: int, data: Variant) -> bool:
	if _hotbar_locked or not _valid_hotbar_slot(page, slot) or not data is Dictionary:
		return false
	var kind := str(data.get("kind", ""))
	if kind == "hotbar":
		var source_page := int(data.get("source_page", -1))
		var source_slot := int(data.get("source_slot", -1))
		return _valid_hotbar_slot(source_page, source_slot) and _valid_hotbar_binding(data.get("binding")) and _get_hotbar_binding(source_page, source_slot) == data.binding
	if kind == "item":
		return not str(data.get("item_id", "")).strip_edges().is_empty()
	if kind == "skill":
		var id := str(data.get("skill_id", data.get("id", ""))).strip_edges()
		return not id.is_empty() and not _is_passive_skill(id)
	return false


func _on_hotbar_drop(page: int, slot: int, data: Dictionary) -> void:
	if not _can_hotbar_drop(page, slot, data):
		return
	var kind := str(data.kind)
	if kind == "hotbar":
		var source_key: String = ctrl._hotbar_bind_key(int(data.source_page), int(data.source_slot))
		var target_key: String = ctrl._hotbar_bind_key(page, slot)
		if source_key == target_key:
			return
		var old := _get_hotbar_binding(page, slot).duplicate(true)
		ctrl._hotbar_bindings[target_key] = data.binding.duplicate(true)
		if not bool(data.get("copy", false)):
			if old.is_empty():
				ctrl._hotbar_bindings.erase(source_key)
			else:
				ctrl._hotbar_bindings[source_key] = old
		_persist_hotbar_to_session()
		_refresh_hotbar_slot_visuals()
	elif kind == "item":
		_set_hotbar_binding(page, slot, "item", str(data.item_id))
	elif kind == "skill":
		_set_hotbar_binding(page, slot, "skill", str(data.get("skill_id", data.get("id", ""))))


func _on_hotbar_item_dropped(page: int, slot: int, item_id: String) -> void:
	_on_hotbar_drop(page, slot, {"kind": "item", "item_id": item_id})


func _on_hotbar_skill_dropped(page: int, slot: int, skill_id: String) -> void:
	_on_hotbar_drop(page, slot, {"kind": "skill", "skill_id": skill_id})


func _on_hotbar_binding_cleared(page: int, slot: int) -> void:
	_clear_hotbar_binding(page, slot)


func _on_hotbar_pressed(page: int, slot: int, _key: String) -> void:
	if ctrl.get_viewport().gui_is_dragging():
		return
	var binding := _get_hotbar_binding(page, slot)
	if binding.is_empty() or ctrl._world_combat == null:
		return
	var kind := str(binding.get("kind", ""))
	var bid := str(binding.get("id", ""))
	if kind == "item" and ctrl._world_combat.has_method("request_use_item"):
		ctrl._world_combat.request_use_item(bid)
	elif kind == "skill" and not _is_passive_skill(bid) and ctrl._world_combat.has_method("request_use_skill"):
		ctrl._world_combat.request_use_skill(bid)


func apply_skill_catalog(skills: Array) -> void:
	ctrl._server_skills = skills.duplicate(true)
	_refresh_hotbar_slot_visuals()
	if ctrl._windows.has("skills") and ctrl._windows["skills"].visible:
		ctrl._refresh_window_contents()




func apply_skill_book(book: Dictionary) -> void:
	ctrl._skill_respec_armed = false
	var prev_sp: int = ctrl._skill_points
	ctrl._known_skills.clear()
	var known_v: Variant = book.get("known", book.get("known_skills", []))
	if typeof(known_v) == TYPE_ARRAY:
		for sid_v in known_v:
			var sid = str(sid_v).strip_edges()
			if not sid.is_empty():
				ctrl._known_skills[sid] = true
	ctrl._skill_points = maxi(int(book.get("skill_points", 0)), 0)
	# Always treat basic_attack as known locally for UI.
	ctrl._known_skills["basic_attack"] = true
	if ctrl._windows.has("skills") and ctrl._windows["skills"].visible:
		ctrl._fill_window("skills")
	# Level-up toast: skill_book_update often follows level_up with SP grant.
	if ctrl._level_toast_armed and ctrl._skill_points > prev_sp:
		ctrl._set_level_toast_sp_note(true)



func is_skill_known(skill_id: String) -> bool:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return false
	if skill_id == "basic_attack":
		return true
	if ctrl._known_skills.is_empty():
		# Before first book sync, assume starters only once catalog applied.
		return ctrl._known_skills.has(skill_id)
	return ctrl._known_skills.has(skill_id)




func _iter_skill_cells(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c == null:
			continue
		if c.has_method("set_cooldown") and c.has_method("tick_cooldown"):
			out.append(c)
		else:
			out.append_array(_iter_skill_cells(c))
	return out



func _skill_window_grid() -> Node:
	if not ctrl._windows.has("skills"):
		return null
	var panel: PanelContainer = ctrl._windows["skills"]
	if panel == null or not is_instance_valid(panel):
		return null
	return panel.find_child("SkillGrid", true, false)



func _tick_skill_cell_cooldowns(host: Node, delta: float) -> void:
	for cell in _iter_skill_cells(host):
		cell.tick_cooldown(delta)



func _tick_skill_window_cooldowns(delta: float) -> void:
	_tick_skill_cell_cooldowns(_skill_window_grid(), delta)



func _apply_cooldown_to_skill_window(id: String, remaining: float, total: float) -> void:
	ctrl._apply_cooldown_to_container(_skill_window_grid(), id, remaining, total)



func _apply_cast_to_skill_window(frac: float) -> void:
	ctrl._apply_cast_to_container(_skill_window_grid(), frac)



func _refresh_skill_window_cooldowns() -> void:
	var grid = _skill_window_grid()
	if grid == null:
		return
	for cell in _iter_skill_cells(grid):
		var bid = ctrl._cell_bound_id(cell)
		if bid.is_empty():
			if cell.has_method("clear_cooldown"):
				cell.clear_cooldown()
			continue
		var row: Variant = ctrl._skill_cd_hint.get(bid, {})
		if typeof(row) == TYPE_DICTIONARY and float(row.get("remaining", 0.0)) > 0.0:
			cell.set_cooldown(float(row.get("remaining", 0.0)), float(row.get("cooldown", 0.0)))
		elif cell.has_method("clear_cooldown"):
			cell.clear_cooldown()
	_sync_skill_cast_overlays()



func _tick_hotbar_cooldowns(delta: float) -> void:
	var dead: Array = []
	for sid in ctrl._skill_cd_hint.keys():
		var row: Variant = ctrl._skill_cd_hint[sid]
		if typeof(row) != TYPE_DICTIONARY:
			dead.append(sid)
			continue
		var rem: float = maxf(float(row.get("remaining", 0.0)) - delta, 0.0)
		row["remaining"] = rem
		ctrl._skill_cd_hint[sid] = row
		if rem <= 0.0:
			dead.append(sid)
	for sid2 in dead:
		ctrl._skill_cd_hint.erase(sid2)
	_tick_skill_cell_cooldowns(ctrl.hotbar, delta)
	_tick_skill_window_cooldowns(delta)



func _apply_hotbar_cooldown_for_id(id: String, remaining: float, total: float) -> void:
	if id.is_empty():
		return
	ctrl._apply_cooldown_to_container(ctrl.hotbar, id, remaining, total)
	_apply_cooldown_to_skill_window(id, remaining, total)



func _sync_hotbar_cast_overlays() -> void:
	_sync_skill_cast_overlays()



func _sync_skill_cast_overlays() -> void:
	var frac: float = -1.0
	if ctrl._cast_active and ctrl._cast_duration > 0.0 and not ctrl._cast_skill_id.is_empty():
		frac = clampf(ctrl._cast_elapsed / ctrl._cast_duration, 0.0, 1.0)
	ctrl._apply_cast_to_container(ctrl.hotbar, frac)
	_apply_cast_to_skill_window(frac)



func note_skill_cooldown(skill_id: String, remaining: float, cooldown: float = 0.0) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	var total: float = cooldown
	if total <= 0.0:
		total = remaining
	ctrl._skill_cd_hint[skill_id] = {"remaining": remaining, "cooldown": total}
	_apply_hotbar_cooldown_for_id(skill_id, remaining, total)
	if ctrl._windows.has("skills") and ctrl._windows["skills"].visible:
		ctrl._refresh_window_contents()


func hotbar_prev() -> void:
	_select_hotbar_page(ctrl._hotbar_page - 1)


func hotbar_next() -> void:
	_select_hotbar_page(ctrl._hotbar_page + 1)


func _lock_skills_window(panel: PanelContainer) -> void:
	## Fixed-size skills: same lock as bag; tab bar sits above Scroll (not inside body).
	if panel == null:
		return
	var base: Vector2 = panel.get_meta("base_size", Vector2(400, 420))
	panel.resizable = false
	panel.min_size = base
	panel.custom_minimum_size = base
	panel.default_size = base
	panel.size = base
	panel.set_meta("fixed_size", true)
	ctrl._apply_l2_chrome(panel)
	var scroll = panel.find_child("Scroll", true, false) as ScrollContainer
	if scroll == null:
		return
	var vbox = scroll.get_parent() as VBoxContainer
	if vbox == null:
		return
	var tabs = vbox.get_node_or_null("SkillsTabs") as HBoxContainer
	if tabs == null:
		tabs = HBoxContainer.new()
		tabs.name = "SkillsTabs"
		tabs.add_theme_constant_override("separation", 4)
		tabs.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(tabs)
		vbox.move_child(tabs, scroll.get_index())
	panel.set_meta("skills_tabs", tabs)
	_rebuild_skills_tab_bar(panel)



func _rebuild_skills_tab_bar(panel: PanelContainer) -> void:
	var tabs: HBoxContainer = panel.get_meta("skills_tabs", null) if panel else null
	if tabs == null or not is_instance_valid(tabs):
		return
	while tabs.get_child_count() > 0:
		var c: Node = tabs.get_child(0)
		tabs.remove_child(c)
		c.queue_free()
	for item in SKILL_TABS:
		var btn = Button.new()
		btn.text = str(item[0])
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(64, L2Style.TAB_HEIGHT)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var cat = str(item[1])
		btn.pressed.connect(_on_skills_tab.bind(cat))
		tabs.add_child(btn)
	_highlight_skills_tabs(tabs)



func _on_skills_tab(cat: String) -> void:
	cat = cat.strip_edges()
	if cat.is_empty():
		return
	ctrl._skills_tab = cat
	if ctrl._windows.has("skills"):
		var panel: PanelContainer = ctrl._windows["skills"]
		_highlight_skills_tabs(panel.get_meta("skills_tabs", null) as HBoxContainer)
		if panel.visible:
			ctrl._fill_window("skills")



func _highlight_skills_tabs(tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn = tabs.get_child(i) as Button
		if btn == null or i >= SKILL_TABS.size():
			continue
		var id = str(SKILL_TABS[i][1])
		L2Style.style_tab_button(btn, id == ctrl._skills_tab)



func _skill_icon_index(skill_id: String) -> int:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return -1
	for s in ctrl._server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			return int(s.get("icon_index", -1))
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("icon_index_of"):
			return int(cat.icon_index_of(skill_id))
		if cat != null and cat.has_method("get_skill"):
			return int(cat.get_skill(skill_id).get("icon_index", -1))
	return -1



func _skill_icon_ref(skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return ""
	for s in ctrl._server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			var r = str(s.get("icon_ref", "")).strip_edges()
			if not r.is_empty():
				return r
			var ic = str(s.get("icon", "")).strip_edges()
			if not ic.is_empty():
				return "content://icon/%s" % ic
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("icon_ref_of"):
			return str(cat.icon_ref_of(skill_id))
		if cat != null and cat.has_method("get_skill"):
			var def: Dictionary = cat.get_skill(skill_id)
			var r2 = str(def.get("icon_ref", "")).strip_edges()
			if not r2.is_empty():
				return r2
			var ic2 = str(def.get("icon", "")).strip_edges()
			if not ic2.is_empty():
				return "content://icon/%s" % ic2
	return ""



func _skill_display_name(skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	for s in ctrl._server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			var n = str(s.get("name", "")).strip_edges()
			return n if not n.is_empty() else skill_id
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("get_skill"):
			var def: Dictionary = cat.get_skill(skill_id)
			var n2 = str(def.get("name", "")).strip_edges()
			if not n2.is_empty():
				return n2
	return skill_id



func _skill_category(skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	for s in ctrl._server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			return _normalize_skill_category(s)
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("get_skill"):
			return _normalize_skill_category(cat.get_skill(skill_id))
	return "physical"



func _normalize_skill_category(def: Dictionary) -> String:
	if def.is_empty():
		return "physical"
	var cat = str(def.get("category", "")).strip_edges()
	if cat == "physical" or cat == "magic" or cat == "passive":
		return cat
	var eff = str(def.get("effect", ""))
	if eff.begins_with("passive"):
		return "passive"
	if eff == "heal":
		return "magic"
	return "physical"



func _is_passive_skill(skill_id: String) -> bool:
	return _skill_category(skill_id) == "passive"



func _fill_skills(body: VBoxContainer, _ch: Dictionary) -> void:
	## Grid + tabs (tabs live outside Scroll). SP + Learn row above grid.
	var panel: PanelContainer = ctrl._windows.get("skills") as PanelContainer
	if panel != null:
		_rebuild_skills_tab_bar(panel)
	var skills: Array = ctrl._server_skills
	if skills.is_empty():
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_skill_catalog"):
			skills = srv.snapshot_skill_catalog()
			ctrl._server_skills = skills.duplicate(true)
	# SP / Learn header
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(head)
	var sp_lbl = Label.new()
	sp_lbl.name = "SkillPointsLabel"
	sp_lbl.text = "技能点：%d" % ctrl._skill_points
	sp_lbl.add_theme_color_override("font_color", L2Style.COL_TEXT)
	sp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp_lbl)
	var learn_btn = Button.new()
	learn_btn.name = "LearnSkillButton"
	learn_btn.text = "学习"
	learn_btn.focus_mode = Control.FOCUS_NONE
	learn_btn.disabled = true
	learn_btn.pressed.connect(_on_learn_skill_pressed)
	head.add_child(learn_btn)
	var use_btn := Button.new()
	use_btn.name = "UseSelectedSkill"
	use_btn.text = "使用"
	use_btn.focus_mode = Control.FOCUS_NONE
	use_btn.disabled = ctrl._selected_skill_id.is_empty() or not ctrl._is_skill_known(ctrl._selected_skill_id) or _is_passive_skill(ctrl._selected_skill_id)
	use_btn.pressed.connect(func(): _on_skill_slot_pressed(ctrl._selected_skill_id))
	head.add_child(use_btn)
	var respec_btn = Button.new()
	respec_btn.name = "RespecSkillButton"
	respec_btn.text = "重置技能"
	respec_btn.focus_mode = Control.FOCUS_NONE
	respec_btn.tooltip_text = "重置已学技能并返还技能点（花费 50 金币）。保留普通攻击。"
	respec_btn.pressed.connect(_on_respec_skill_pressed)
	head.add_child(respec_btn)
	var sel_lbl = Label.new()
	sel_lbl.name = "SelectedSkillHint"
	sel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_lbl.text = ""
	sel_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
	sel_lbl.add_theme_font_size_override("font_size", 11)
	body.add_child(sel_lbl)
	_update_skills_learn_row(learn_btn, sel_lbl)
	var filtered: Array = []
	for s in skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if _normalize_skill_category(s) == ctrl._skills_tab:
			filtered.append(s)
	var cell_sz = ctrl._grid_cell_size()
	var cols = 4
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if filtered.is_empty():
		var empty = Label.new()
		empty.text = "（暂无技能）"
		empty.add_theme_color_override("font_color", L2Style.COL_MUTED)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(empty)
	else:
		var grid = GridContainer.new()
		grid.name = "SkillGrid"
		grid.columns = cols
		grid.add_theme_constant_override("h_separation", GRID_SEP)
		grid.add_theme_constant_override("v_separation", GRID_SEP)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		grid.mouse_filter = Control.MOUSE_FILTER_STOP
		body.add_child(grid)
		for i in range(filtered.size()):
			var cell = PanelContainer.new()
			cell.set_script(SkillSlot)
			cell.custom_minimum_size = cell_sz
			var sdef: Dictionary = filtered[i]
			var sid = str(sdef.get("id", ""))
			var sname = str(sdef.get("name", sid))
			var cat = _normalize_skill_category(sdef)
			var six = int(sdef.get("icon_index", _skill_icon_index(sid)))
			var sref = str(sdef.get("icon_ref", "")).strip_edges()
			if sref.is_empty():
				var sic = str(sdef.get("icon", "")).strip_edges()
				if not sic.is_empty():
					sref = "content://icon/%s" % sic
				else:
					sref = _skill_icon_ref(sid)
			var entry := VBoxContainer.new()
			entry.custom_minimum_size.x = 70
			entry.add_theme_constant_override("separation", 3)
			cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			entry.add_child(cell)
			var caption := Label.new()
			caption.text = sname
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.add_theme_font_size_override("font_size", 11)
			caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			caption.tooltip_text = sname
			entry.add_child(caption)
			grid.add_child(entry)
			cell.setup(sid, sname, cat, i, six, sref)
			var known = ctrl._is_skill_known(sid)
			if cell.has_method("set_known"):
				cell.set_known(known)
			cell.activated.connect(_on_skill_slot_selected)
			cell.custom_minimum_size = cell_sz
		_refresh_skill_window_cooldowns()
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		ctrl.call_deferred("_lock_window_size", panel)




func _on_skill_slot_pressed(skill_id: String) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	ctrl._selected_skill_id = skill_id
	_refresh_skills_learn_controls()
	if not ctrl._is_skill_known(skill_id):
		var sname = _skill_display_name(skill_id)
		var def = _skill_def(skill_id)
		var need_lv = maxi(int(def.get("learn_level", 1)), 1)
		var cost = maxi(int(def.get("sp_cost", 1)), 0)
		ctrl.append_system("未学会【%s】（需要 Lv.%d · %d 技能点）。选中后点「学习」。" % [sname, need_lv, cost])
		return
	if _is_passive_skill(skill_id):
		var sname2 = _skill_display_name(skill_id)
		var extra = ""
		for s in ctrl._server_skills:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			if str(s.get("id", "")) != skill_id:
				continue
			var atk_b = int(s.get("atk_bonus", 0))
			var def_b = int(s.get("def_bonus", 0))
			if atk_b != 0:
				extra = "（攻击+%d）" % atk_b
			elif def_b != 0:
				extra = "（防御+%d）" % def_b
			break
		ctrl.append_system("被动已生效 · 【%s】%s" % [sname2, extra])
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_use_skill"):
		ctrl._world_combat.request_use_skill(skill_id)
	else:
		ctrl.append_system("无法施放：%s" % skill_id)




func _on_skill_row_pressed(skill_id: String) -> void:
	## Compat alias for older call sites.
	_on_skill_slot_pressed(skill_id)



func _skill_def(skill_id: String) -> Dictionary:
	for s in ctrl._server_skills:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == skill_id:
			return s
	var srv = Net.server()
	if srv != null and srv.has_method("skill_def"):
		return srv.skill_def(skill_id)
	return {}



func _player_level_for_skills() -> int:
	var lv = int(ctrl._server_combat.get("level", 0))
	if lv <= 0 and not ctrl._character.is_empty():
		lv = int(ctrl._character.get("level", 1))
	return maxi(lv, 1)



func _update_skills_learn_row(learn_btn: Button, sel_lbl: Label) -> void:
	var sid = ctrl._selected_skill_id.strip_edges()
	if sid.is_empty():
		sel_lbl.text = "点击查看技能；拖到快捷栏可快速使用"
		learn_btn.disabled = true
		return
	var def = _skill_def(sid)
	var sname = str(def.get("name", _skill_display_name(sid)))
	if ctrl._is_skill_known(sid):
		sel_lbl.text = "已学会：%s" % sname
		learn_btn.disabled = true
		return
	var need_lv = maxi(int(def.get("learn_level", 1)), 1)
	var cost = maxi(int(def.get("sp_cost", 1)), 0)
	sel_lbl.text = "选中：%s · 需要 Lv.%d · %d SP" % [sname, need_lv, cost]
	learn_btn.disabled = not ctrl._can_learn_selected()



func _refresh_skills_learn_controls() -> void:
	if not ctrl._windows.has("skills"):
		return
	var panel: PanelContainer = ctrl._windows["skills"]
	if panel == null or not panel.visible:
		return
	var use: Button = panel.find_child("UseSelectedSkill", true, false)
	if use: use.disabled = not ctrl._is_skill_known(ctrl._selected_skill_id) or _is_passive_skill(ctrl._selected_skill_id)
	# Controls live inside scroll body; find by name.
	var learn_btn: Button = panel.find_child("LearnSkillButton", true, false) as Button
	var sel_lbl: Label = panel.find_child("SelectedSkillHint", true, false) as Label
	var sp_lbl: Label = panel.find_child("SkillPointsLabel", true, false) as Label
	if sp_lbl != null:
		sp_lbl.text = "技能点：%d" % ctrl._skill_points
	if learn_btn != null and sel_lbl != null:
		_update_skills_learn_row(learn_btn, sel_lbl)



func _on_learn_skill_pressed() -> void:
	var sid = ctrl._selected_skill_id.strip_edges()
	if sid.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_learn_skill"):
		ctrl._world_combat.request_learn_skill(sid)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_learn_skill"):
			var result: Dictionary = srv.try_learn_skill(sid)
			var acts_v: Variant = result.get("actions", [])
			if typeof(acts_v) == TYPE_ARRAY and ctrl._world_combat != null and ctrl._world_combat.has_method("apply_server_actions"):
				ctrl._world_combat.apply_server_actions(acts_v)
			elif typeof(acts_v) == TYPE_ARRAY:
				for a in acts_v:
					if typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "system_message":
						ctrl.append_system(str(a.get("text", "")))
					elif typeof(a) == TYPE_DICTIONARY and str(a.get("type", "")) == "skill_book_update":
						apply_skill_book(a)



func _on_respec_skill_pressed() -> void:
	preload("res://scripts/ui/game_window.gd").confirm_action(ctrl._windows["skills"], "花费 50 金币重置已学技能并返还技能点，保留普通攻击。", "确认重置技能", _confirm_skill_respec)


func _confirm_skill_respec() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_skill_respec"):
		ctrl._world_combat.request_skill_respec()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_skill_respec"):
		var result: Dictionary = srv.try_skill_respec()
		var acts_v: Variant = result.get("actions", [])
		if typeof(acts_v) == TYPE_ARRAY and ctrl._world_combat != null and ctrl._world_combat.has_method("apply_server_actions"):
			ctrl._world_combat.apply_server_actions(acts_v)
		elif typeof(acts_v) == TYPE_ARRAY:
			for a in acts_v:
				if typeof(a) != TYPE_DICTIONARY:
					continue
				var t = str(a.get("type", ""))
				if t == "system_message":
					ctrl.append_system(str(a.get("text", "")))
				elif t == "skill_book_update":
					apply_skill_book(a)
				elif t == "skill_respec":
					apply_skill_respec(a)
				elif t == "inventory_update" and a.has("gold"):
					ctrl._server_gold = int(a.get("gold", ctrl._server_gold))



func apply_skill_respec(action: Dictionary) -> void:
	var cleared_ids: Dictionary = {}
	var cleared_v: Variant = action.get("cleared", [])
	if typeof(cleared_v) == TYPE_ARRAY:
		for c in cleared_v:
			var cid = str(c).strip_edges()
			if not cid.is_empty():
				cleared_ids[cid] = true
	if cleared_ids.is_empty():
		# Also scrub any skill binding not currently known.
		for k in ctrl._hotbar_bindings.keys():
			var v: Variant = ctrl._hotbar_bindings[k]
			if typeof(v) != TYPE_DICTIONARY:
				continue
			if str(v.get("kind", "")) != "skill":
				continue
			var sid = str(v.get("id", "")).strip_edges()
			if sid.is_empty() or sid == "basic_attack":
				continue
			if not ctrl._is_skill_known(sid):
				cleared_ids[sid] = true
	var removed = false
	var keys: Array = ctrl._hotbar_bindings.keys()
	for k in keys:
		var bv: Variant = ctrl._hotbar_bindings[k]
		if typeof(bv) != TYPE_DICTIONARY:
			continue
		if str(bv.get("kind", "")) != "skill":
			continue
		var bid = str(bv.get("id", "")).strip_edges()
		if cleared_ids.has(bid) or (not bid.is_empty() and bid != "basic_attack" and not ctrl._is_skill_known(bid)):
			ctrl._hotbar_bindings.erase(k)
			removed = true
	if removed:
		_persist_hotbar_to_session()
		_refresh_hotbar_slot_visuals()



func on_hotbar_prev_pressed() -> void:
	hotbar_prev()


func on_hotbar_next_pressed() -> void:
	hotbar_next()




func _on_skill_slot_selected(skill_id: String) -> void:
	ctrl._selected_skill_id = skill_id
	_refresh_skills_learn_controls()
	var panel: Control = ctrl._windows["skills"]
	for cell in ctrl._iter_skill_cells(panel):
		cell._apply_visual()
		if cell.skill_id == skill_id: cell.add_theme_stylebox_override("panel", L2Style.row_box(true))
