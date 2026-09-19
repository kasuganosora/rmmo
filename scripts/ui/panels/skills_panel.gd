extends RefCounted
## UI panel: skills, hotbar, cooldowns, learn/respec.

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
const HOTBAR_PAGES := [
	["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
	["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "+"],
]

static func _session_hotbar_store(ctrl) -> Node:
	var net = ctrl.get_node_or_null("/root/Net")
	if net != null and net.has_method("session"):
		return net.session()
	return ctrl.get_node_or_null("/root/GameSession")



static func _restore_hotbar_from_session(ctrl) -> void:
	var sess = ctrl._session_hotbar_store()
	if sess == null:
		return
	ctrl._hotbar_page = clampi(int(sess.hotbar_page), 0, HOTBAR_PAGES.size() - 1)
	var raw: Variant = sess.hotbar_bindings
	if typeof(raw) != TYPE_DICTIONARY:
		ctrl._hotbar_bindings = {}
		return
	var src: Dictionary = raw
	var out: Dictionary = {}
	for k in src.keys():
		var v: Variant = src[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var kind = str(v.get("kind", "")).strip_edges()
		var id = str(v.get("id", "")).strip_edges()
		if kind.is_empty() or id.is_empty():
			continue
		out[str(k)] = {"kind": kind, "id": id}
	ctrl._hotbar_bindings = out



static func _persist_hotbar_to_session(ctrl) -> void:
	var sess = ctrl._session_hotbar_store()
	if sess == null:
		return
	sess.hotbar_page = ctrl._hotbar_page
	sess.hotbar_bindings = ctrl._hotbar_bindings.duplicate(true)



static func _get_hotbar_binding(ctrl, page: int, slot: int) -> Dictionary:
	var k = ctrl._hotbar_bind_key(page, slot)
	if ctrl._hotbar_bindings.has(k):
		var v: Variant = ctrl._hotbar_bindings[k]
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}



static func _set_hotbar_binding(ctrl, page: int, slot: int, kind: String, id: String) -> void:
	kind = kind.strip_edges()
	id = id.strip_edges()
	var k = ctrl._hotbar_bind_key(page, slot)
	if kind.is_empty() or id.is_empty():
		ctrl._hotbar_bindings.erase(k)
	else:
		ctrl._hotbar_bindings[k] = {"kind": kind, "id": id}
	ctrl._persist_hotbar_to_session()
	ctrl._refresh_hotbar_slot_visuals()



static func _clear_hotbar_binding(ctrl, page: int, slot: int) -> void:
	ctrl._hotbar_bindings.erase(ctrl._hotbar_bind_key(page, slot))
	ctrl._persist_hotbar_to_session()
	ctrl._refresh_hotbar_slot_visuals()
	ctrl.append_system("已清除快捷栏 %d 槽位 %d" % [page + 1, slot])



static func _layout_hotbar_side_nav(ctrl, prev: Node, next: Node) -> void:
	## Put < > on the sides of the slot row; hide page label / top nav row.
	if ctrl.hotbar == null:
		return
	if ctrl.hotbar_page_label != null:
		ctrl.hotbar_page_label.visible = false
	var nav = ctrl.find_child("HotbarNav", true, false) as Control
	if nav != null:
		nav.visible = false
	# Prefer a dedicated side-nav HBox wrapping prev | slots | next.
	var host = ctrl.hotbar.get_parent()
	if host == null:
		return
	var side = host.get_node_or_null("HotbarSideRow") as HBoxContainer
	if side == null:
		side = HBoxContainer.new()
		side.name = "HotbarSideRow"
		side.add_theme_constant_override("separation", 4)
		side.alignment = BoxContainer.ALIGNMENT_CENTER
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.add_child(side)
		# Place above menu / where Hotbar was.
		if ctrl.hotbar.get_parent() == host:
			host.move_child(side, ctrl.hotbar.get_index())
		ctrl.hotbar.reparent(side)
	if prev != null and is_instance_valid(prev):
		if prev.get_parent() != side:
			prev.reparent(side)
		side.move_child(prev, 0)
		prev.custom_minimum_size = Vector2(22, GRID_CELL)
		prev.text = "<"
	if ctrl.hotbar.get_parent() == side:
		side.move_child(ctrl.hotbar, mini(1, side.get_child_count() - 1))
	if next != null and is_instance_valid(next):
		if next.get_parent() != side:
			next.reparent(side)
		side.move_child(next, side.get_child_count() - 1)
		next.custom_minimum_size = Vector2(22, GRID_CELL)
		next.text = ">"



static func _hotbar_keycode_to_slot(ctrl, keycode: int) -> Vector2i:
	## Returns Vector2i(page, slot_index0) or (-1,-1).
	match keycode:
		KEY_F1: return Vector2i(0, 0)
		KEY_F2: return Vector2i(0, 1)
		KEY_F3: return Vector2i(0, 2)
		KEY_F4: return Vector2i(0, 3)
		KEY_F5: return Vector2i(0, 4)
		KEY_F6: return Vector2i(0, 5)
		KEY_F7: return Vector2i(0, 6)
		KEY_F8: return Vector2i(0, 7)
		KEY_F9: return Vector2i(0, 8)
		KEY_F10: return Vector2i(0, 9)
		KEY_F11: return Vector2i(0, 10)
		KEY_F12: return Vector2i(0, 11)
		KEY_QUOTELEFT: return Vector2i(1, 0)  # `
		KEY_1: return Vector2i(1, 1)
		KEY_2: return Vector2i(1, 2)
		KEY_3: return Vector2i(1, 3)
		KEY_4: return Vector2i(1, 4)
		KEY_5: return Vector2i(1, 5)
		KEY_6: return Vector2i(1, 6)
		KEY_7: return Vector2i(1, 7)
		KEY_8: return Vector2i(1, 8)
		KEY_9: return Vector2i(1, 9)
		KEY_0: return Vector2i(1, 10)
		KEY_MINUS, KEY_EQUAL: return Vector2i(1, 11)  # - / = / + (last slot)
	return Vector2i(-1, -1)



static func _try_hotbar_key(ctrl, keycode: int) -> bool:
	if ctrl._text_input_focused():
		return false
	var map = ctrl._hotbar_keycode_to_slot(keycode)
	if map.x < 0:
		return false
	var page: int = map.x
	var idx: int = map.y
	if page >= HOTBAR_PAGES.size() or idx >= HOTBAR_PAGES[page].size():
		return false
	var key = str(HOTBAR_PAGES[page][idx])
	ctrl._on_hotbar_pressed(page, idx + 1, key)
	return true



static func _build_hotbar(ctrl) -> void:
	# Immediate free so get_child_count() is accurate this frame.
	while ctrl.hotbar.get_child_count() > 0:
		var c: Node = ctrl.hotbar.get_child(0)
		ctrl.hotbar.remove_child(c)
		c.free()
	var keys: Array = HOTBAR_PAGES[ctrl._hotbar_page]
	for i in range(keys.size()):
		var slot = Button.new()
		slot.set_script(HotbarSlot)
		slot.custom_minimum_size = Vector2(GRID_CELL, GRID_CELL)
		var slot_n: int = i + 1
		slot.focus_mode = Control.FOCUS_NONE
		slot.configure(ctrl._hotbar_page, slot_n)
		slot.pressed.connect(ctrl._on_hotbar_pressed.bind(ctrl._hotbar_page, slot_n, str(keys[i])))
		slot.item_dropped.connect(ctrl._on_hotbar_item_dropped)
		slot.skill_dropped.connect(ctrl._on_hotbar_skill_dropped)
		slot.binding_cleared.connect(ctrl._on_hotbar_binding_cleared)
		ctrl.hotbar.add_child(slot)
		if slot.has_method("set_key_hint"):
			slot.set_key_hint(str(keys[i]))
	if ctrl.hotbar_page_label != null:
		ctrl.hotbar_page_label.visible = false
	ctrl._refresh_hotbar_slot_visuals()



static func _refresh_hotbar_slot_visuals(ctrl) -> void:
	ctrl._sync_equipment_cache()
	if ctrl.hotbar == null:
		return
	var keys: Array = HOTBAR_PAGES[ctrl._hotbar_page]
	var page0_hints = {
		1: "普通攻击",
		2: "强力打击",
		3: "轻度治疗",
		4: "小型生命药水",
		5: "小型魔法药水",
	}
	for i in range(ctrl.hotbar.get_child_count()):
		var btn = ctrl.hotbar.get_child(i) as Button
		if btn == null:
			continue
		var slot_n: int = i + 1
		var key_label = str(keys[i]) if i < keys.size() else str(slot_n)
		var bind = ctrl._get_hotbar_binding(ctrl._hotbar_page, slot_n)
		if btn.has_method("set_binding_visual"):
			if not bind.is_empty():
				var kind = str(bind.get("kind", ""))
				var bid = str(bind.get("id", ""))
				if kind == "item":
					var dname = ctrl._item_label(bid)
					var tip_name = ctrl._item_rarity_name_line(bid, dname)
					var q = ctrl._inventory_qty(bid)
					var eq_on = q <= 0 and ctrl._is_item_equipped(bid)
					var tip = "%s ×%d\n%s（右键清除）" % [tip_name, q, bid]
					if eq_on:
						tip = "%s（已装备）\n%s（右键清除）" % [tip_name, bid]
					tip = ctrl._equip_compare_tip(bid, tip)
					btn.set_binding_visual(
						"item",
						ctrl._letter_avatar(dname),
						q,
						tip,
						ctrl._item_icon_index(bid),
						ctrl._item_icon_ref(bid)
					)
				elif kind == "skill":
					var sname = ctrl._skill_display_name(bid)
					var tip_extra = "（被动）" if ctrl._is_passive_skill(bid) else ""
					btn.set_binding_visual(
						"skill",
						ctrl._letter_avatar(sname),
						0,
						"技能 %s%s（右键清除）" % [sname, tip_extra],
						ctrl._skill_icon_index(bid),
						ctrl._skill_icon_ref(bid)
					)
				else:
					btn.set_binding_visual("", "", 0, key_label)
			elif ctrl._hotbar_page == 0 and page0_hints.has(slot_n):
				btn.set_binding_visual(
					"",
					"",
					0,
					"%s %s（未绑定，按键仍可用默认）" % [key_label, str(page0_hints[slot_n])]
				)
			else:
				btn.set_binding_visual("", "", 0, "%s（可从背包拖入，右键清除）" % key_label)
		if btn.has_method("set_key_hint"):
			btn.set_key_hint(key_label)
		else:
			# Fallback if script not attached yet.
			btn.text = ""
			btn.tooltip_text = key_label
		var cd_id = ""
		var cd_kind = ""
		if not bind.is_empty():
			cd_kind = str(bind.get("kind", ""))
			cd_id = str(bind.get("id", "")).strip_edges()
		elif ctrl._hotbar_page == 0:
			match slot_n:
				1:
					cd_kind = "skill"
					cd_id = "basic_attack"
				2:
					cd_kind = "skill"
					cd_id = "power_strike"
				3:
					cd_kind = "skill"
					cd_id = "heal_light"
				4:
					cd_kind = "item"
					cd_id = "potion_hp_small"
				5:
					cd_kind = "item"
					cd_id = "potion_mp_small"
		if btn.has_method("set_bound_id"):
			btn.set_bound_id(cd_id)
		ctrl._apply_slot_cooldown_visual(btn, cd_kind, cd_id)
	ctrl._sync_hotbar_cast_overlays()



static func _on_hotbar_item_dropped(ctrl, page: int, slot: int, item_id: String) -> void:
	ctrl._set_hotbar_binding(page, slot, "item", item_id)
	ctrl.append_system("快捷栏绑定物品：%s → 页%d 槽%d" % [ctrl._item_label(item_id), page + 1, slot])



static func _on_hotbar_skill_dropped(ctrl, page: int, slot: int, skill_id: String) -> void:
	ctrl._set_hotbar_binding(page, slot, "skill", skill_id)
	ctrl.append_system("快捷栏绑定技能：%s → 页%d 槽%d" % [ctrl._skill_display_name(skill_id), page + 1, slot])



static func _on_hotbar_binding_cleared(ctrl, page: int, slot: int) -> void:
	ctrl._clear_hotbar_binding(page, slot)



static func _on_hotbar_pressed(ctrl, page: int, slot: int, key: String) -> void:
	var bind = ctrl._get_hotbar_binding(page, slot)
	if not bind.is_empty() and ctrl._world_combat != null:
		var kind = str(bind.get("kind", ""))
		var bid = str(bind.get("id", ""))
		if kind == "item" and ctrl._world_combat.has_method("request_use_item"):
			ctrl._world_combat.request_use_item(bid)
			return
		if kind == "skill":
			if ctrl._is_passive_skill(bid):
				ctrl.append_system("被动，无需施放")
				return
			if ctrl._world_combat.has_method("request_use_skill"):
				ctrl._world_combat.request_use_skill(bid)
				return
	# Page 0 default combat wiring when unbound.
	if page == 0 and ctrl._world_combat != null:
		match slot:
			1:
				if ctrl._world_combat.has_method("request_use_skill"):
					ctrl._world_combat.request_use_skill("basic_attack")
					return
			2:
				if ctrl._world_combat.has_method("request_use_skill"):
					ctrl._world_combat.request_use_skill("power_strike")
					return
			3:
				if ctrl._world_combat.has_method("request_use_skill"):
					ctrl._world_combat.request_use_skill("heal_light")
					return
			4:
				if ctrl._world_combat.has_method("request_use_item"):
					ctrl._world_combat.request_use_item("potion_hp_small")
					return
			5:
				if ctrl._world_combat.has_method("request_use_item"):
					ctrl._world_combat.request_use_item("potion_mp_small")
					return
	ctrl.append_system("快捷栏%d [%s] 槽位 %d（可从背包拖入）" % [page + 1, key, slot])



static func apply_skill_catalog(ctrl, skills: Array) -> void:
	ctrl._server_skills = skills.duplicate(true)
	if ctrl._windows.has("skills") and ctrl._windows["skills"].visible:
		ctrl._refresh_window_contents()




static func apply_skill_book(ctrl, book: Dictionary) -> void:
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



static func is_skill_known(ctrl, skill_id: String) -> bool:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return false
	if skill_id == "basic_attack":
		return true
	if ctrl._known_skills.is_empty():
		# Before first book sync, assume starters only once catalog applied.
		return ctrl._known_skills.has(skill_id)
	return ctrl._known_skills.has(skill_id)




static func _iter_skill_cells(ctrl, root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c == null:
			continue
		if c.has_method("set_cooldown") and c.has_method("tick_cooldown"):
			out.append(c)
	return out



static func _skill_window_grid(ctrl) -> Node:
	if not ctrl._windows.has("skills"):
		return null
	var panel: PanelContainer = ctrl._windows["skills"]
	if panel == null or not is_instance_valid(panel):
		return null
	return panel.find_child("SkillGrid", true, false)



static func _tick_skill_cell_cooldowns(ctrl, host: Node, delta: float) -> void:
	for cell in ctrl._iter_skill_cells(host):
		cell.tick_cooldown(delta)



static func _tick_skill_window_cooldowns(ctrl, delta: float) -> void:
	ctrl._tick_skill_cell_cooldowns(ctrl._skill_window_grid(), delta)



static func _apply_cooldown_to_skill_window(ctrl, id: String, remaining: float, total: float) -> void:
	ctrl._apply_cooldown_to_container(ctrl._skill_window_grid(), id, remaining, total)



static func _apply_cast_to_skill_window(ctrl, frac: float) -> void:
	ctrl._apply_cast_to_container(ctrl._skill_window_grid(), frac)



static func _refresh_skill_window_cooldowns(ctrl) -> void:
	var grid = ctrl._skill_window_grid()
	if grid == null:
		return
	for cell in ctrl._iter_skill_cells(grid):
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
	ctrl._sync_skill_cast_overlays()



static func _tick_hotbar_cooldowns(ctrl, delta: float) -> void:
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
	ctrl._tick_skill_cell_cooldowns(ctrl.hotbar, delta)
	ctrl._tick_skill_window_cooldowns(delta)



static func _apply_hotbar_cooldown_for_id(ctrl, id: String, remaining: float, total: float) -> void:
	if id.is_empty():
		return
	ctrl._apply_cooldown_to_container(ctrl.hotbar, id, remaining, total)
	ctrl._apply_cooldown_to_skill_window(id, remaining, total)



static func _sync_hotbar_cast_overlays(ctrl) -> void:
	ctrl._sync_skill_cast_overlays()



static func _sync_skill_cast_overlays(ctrl) -> void:
	var frac: float = -1.0
	if ctrl._cast_active and ctrl._cast_duration > 0.0 and not ctrl._cast_skill_id.is_empty():
		frac = clampf(ctrl._cast_elapsed / ctrl._cast_duration, 0.0, 1.0)
	ctrl._apply_cast_to_container(ctrl.hotbar, frac)
	ctrl._apply_cast_to_skill_window(frac)



static func note_skill_cooldown(ctrl, skill_id: String, remaining: float, cooldown: float = 0.0) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	var total: float = cooldown
	if total <= 0.0:
		total = remaining
	ctrl._skill_cd_hint[skill_id] = {"remaining": remaining, "cooldown": total}
	ctrl._apply_hotbar_cooldown_for_id(skill_id, remaining, total)
	if ctrl._windows.has("skills") and ctrl._windows["skills"].visible:
		ctrl._refresh_window_contents()


static func hotbar_prev(ctrl) -> void:
	ctrl._hotbar_page = (ctrl._hotbar_page + HOTBAR_PAGES.size() - 1) % HOTBAR_PAGES.size()
	ctrl._build_hotbar()
	ctrl._persist_hotbar_to_session()


static func hotbar_next(ctrl) -> void:
	ctrl._hotbar_page = (ctrl._hotbar_page + 1) % HOTBAR_PAGES.size()
	ctrl._build_hotbar()
	ctrl._persist_hotbar_to_session()


static func _lock_skills_window(ctrl, panel: PanelContainer) -> void:
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
	ctrl._rebuild_skills_tab_bar(panel)



static func _rebuild_skills_tab_bar(ctrl, panel: PanelContainer) -> void:
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
		btn.custom_minimum_size = Vector2(100, 30)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var cat = str(item[1])
		btn.pressed.connect(ctrl._on_skills_tab.bind(cat))
		tabs.add_child(btn)
	ctrl._highlight_skills_tabs(tabs)



static func _on_skills_tab(ctrl, cat: String) -> void:
	cat = cat.strip_edges()
	if cat.is_empty():
		return
	ctrl._skills_tab = cat
	if ctrl._windows.has("skills"):
		var panel: PanelContainer = ctrl._windows["skills"]
		ctrl._highlight_skills_tabs(panel.get_meta("skills_tabs", null) as HBoxContainer)
		if panel.visible:
			ctrl._fill_window("skills")



static func _highlight_skills_tabs(ctrl, tabs: HBoxContainer) -> void:
	if tabs == null:
		return
	for i in range(tabs.get_child_count()):
		var btn = tabs.get_child(i) as Button
		if btn == null or i >= SKILL_TABS.size():
			continue
		var id = str(SKILL_TABS[i][1])
		L2Style.style_tab_button(btn, id == ctrl._skills_tab)



static func _skill_icon_index(ctrl, skill_id: String) -> int:
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



static func _skill_icon_ref(ctrl, skill_id: String) -> String:
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



static func _skill_display_name(ctrl, skill_id: String) -> String:
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



static func _skill_category(ctrl, skill_id: String) -> String:
	skill_id = skill_id.strip_edges()
	for s in ctrl._server_skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("id", "")) == skill_id:
			return ctrl._normalize_skill_category(s)
	var srv = Net.server()
	if srv != null and srv.get("skill_catalog") != null:
		var cat = srv.skill_catalog
		if cat != null and cat.has_method("get_skill"):
			return ctrl._normalize_skill_category(cat.get_skill(skill_id))
	return "physical"



static func _normalize_skill_category(ctrl, def: Dictionary) -> String:
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



static func _is_passive_skill(ctrl, skill_id: String) -> bool:
	return ctrl._skill_category(skill_id) == "passive"



static func _fill_skills(ctrl, body: VBoxContainer, _ch: Dictionary) -> void:
	## Grid + tabs (tabs live outside Scroll). SP + Learn row above grid.
	var panel: PanelContainer = ctrl._windows.get("skills") as PanelContainer
	if panel != null:
		ctrl._rebuild_skills_tab_bar(panel)
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
	learn_btn.pressed.connect(ctrl._on_learn_skill_pressed)
	head.add_child(learn_btn)
	var respec_btn = Button.new()
	respec_btn.name = "RespecSkillButton"
	respec_btn.text = "重置技能"
	respec_btn.focus_mode = Control.FOCUS_NONE
	respec_btn.tooltip_text = "重置已学技能并返还技能点（花费 50 金币）。保留普通攻击。"
	respec_btn.pressed.connect(ctrl._on_respec_skill_pressed)
	head.add_child(respec_btn)
	var sel_lbl = Label.new()
	sel_lbl.name = "SelectedSkillHint"
	sel_lbl.text = ""
	sel_lbl.add_theme_color_override("font_color", L2Style.COL_MUTED)
	sel_lbl.add_theme_font_size_override("font_size", 11)
	body.add_child(sel_lbl)
	ctrl._update_skills_learn_row(learn_btn, sel_lbl)
	var filtered: Array = []
	for s in skills:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if ctrl._normalize_skill_category(s) == ctrl._skills_tab:
			filtered.append(s)
	var cell_sz = ctrl._grid_cell_size()
	var cols = SKILL_COLS
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
			var cat = ctrl._normalize_skill_category(sdef)
			var six = int(sdef.get("icon_index", ctrl._skill_icon_index(sid)))
			var sref = str(sdef.get("icon_ref", "")).strip_edges()
			if sref.is_empty():
				var sic = str(sdef.get("icon", "")).strip_edges()
				if not sic.is_empty():
					sref = "content://icon/%s" % sic
				else:
					sref = ctrl._skill_icon_ref(sid)
			grid.add_child(cell)
			cell.setup(sid, sname, cat, i, six, sref)
			var known = ctrl._is_skill_known(sid)
			if cell.has_method("set_known"):
				cell.set_known(known)
			cell.activated.connect(ctrl._on_skill_slot_pressed)
			cell.custom_minimum_size = cell_sz
		ctrl._refresh_skill_window_cooldowns()
	if panel != null and bool(panel.get_meta("fixed_size", false)):
		ctrl.call_deferred("_lock_window_size", panel)




static func _on_skill_slot_pressed(ctrl, skill_id: String) -> void:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return
	ctrl._selected_skill_id = skill_id
	ctrl._refresh_skills_learn_controls()
	if not ctrl._is_skill_known(skill_id):
		var sname = ctrl._skill_display_name(skill_id)
		var def = ctrl._skill_def(skill_id)
		var need_lv = maxi(int(def.get("learn_level", 1)), 1)
		var cost = maxi(int(def.get("sp_cost", 1)), 0)
		ctrl.append_system("未学会【%s】（需要 Lv.%d · %d 技能点）。选中后点「学习」。" % [sname, need_lv, cost])
		return
	if ctrl._is_passive_skill(skill_id):
		var sname2 = ctrl._skill_display_name(skill_id)
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




static func _on_skill_row_pressed(ctrl, skill_id: String) -> void:
	## Compat alias for older call sites.
	ctrl._on_skill_slot_pressed(skill_id)



static func _skill_def(ctrl, skill_id: String) -> Dictionary:
	for s in ctrl._server_skills:
		if typeof(s) == TYPE_DICTIONARY and str(s.get("id", "")) == skill_id:
			return s
	var srv = Net.server()
	if srv != null and srv.has_method("skill_def"):
		return srv.skill_def(skill_id)
	return {}



static func _player_level_for_skills(ctrl) -> int:
	var lv = int(ctrl._server_combat.get("level", 0))
	if lv <= 0 and not ctrl._character.is_empty():
		lv = int(ctrl._character.get("level", 1))
	return maxi(lv, 1)



static func _update_skills_learn_row(ctrl, learn_btn: Button, sel_lbl: Label) -> void:
	var sid = ctrl._selected_skill_id.strip_edges()
	if sid.is_empty():
		sel_lbl.text = "选择技能后可学习"
		learn_btn.disabled = true
		return
	var def = ctrl._skill_def(sid)
	var sname = str(def.get("name", ctrl._skill_display_name(sid)))
	if ctrl._is_skill_known(sid):
		sel_lbl.text = "已学会：%s" % sname
		learn_btn.disabled = true
		return
	var need_lv = maxi(int(def.get("learn_level", 1)), 1)
	var cost = maxi(int(def.get("sp_cost", 1)), 0)
	sel_lbl.text = "选中：%s · 需要 Lv.%d · %d SP" % [sname, need_lv, cost]
	learn_btn.disabled = not ctrl._can_learn_selected()



static func _refresh_skills_learn_controls(ctrl) -> void:
	if not ctrl._windows.has("skills"):
		return
	var panel: PanelContainer = ctrl._windows["skills"]
	if panel == null or not panel.visible:
		return
	# Controls live inside scroll body; find by name.
	var learn_btn: Button = panel.find_child("LearnSkillButton", true, false) as Button
	var sel_lbl: Label = panel.find_child("SelectedSkillHint", true, false) as Label
	var sp_lbl: Label = panel.find_child("SkillPointsLabel", true, false) as Label
	if sp_lbl != null:
		sp_lbl.text = "技能点：%d" % ctrl._skill_points
	if learn_btn != null and sel_lbl != null:
		ctrl._update_skills_learn_row(learn_btn, sel_lbl)



static func _on_learn_skill_pressed(ctrl) -> void:
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
						ctrl.apply_skill_book(a)



static func _on_respec_skill_pressed(ctrl) -> void:
	if not ctrl._skill_respec_armed:
		ctrl._skill_respec_armed = true
		ctrl.append_system("再点一次以确认重置技能（花费 50 金币）。")
		return
	ctrl._skill_respec_armed = false
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
					ctrl.apply_skill_book(a)
				elif t == "skill_respec":
					ctrl.apply_skill_respec(a)
				elif t == "inventory_update" and a.has("gold"):
					ctrl._server_gold = int(a.get("gold", ctrl._server_gold))



static func apply_skill_respec(ctrl, action: Dictionary) -> void:
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
		ctrl._persist_hotbar_to_session()
		ctrl._refresh_hotbar_slot_visuals()



static func on_hotbar_prev_pressed(ctrl) -> void:
	ctrl.hotbar_prev()


static func on_hotbar_next_pressed(ctrl) -> void:
	ctrl.hotbar_next()


