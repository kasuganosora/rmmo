extends RefCounted
## UI panel: party roster, shared target, invites.

const StatusIconBar = preload("res://scripts/ui/status_icon_bar.gd")
const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _sync_party_self_statuses_from_player(ctrl) -> void:
	var self_id = ctrl._party_self_id_for_ui()
	var mem_v: Variant = ctrl._party_state.get("members", [])
	if typeof(mem_v) != TYPE_ARRAY:
		return
	var members: Array = mem_v
	for i in range(members.size()):
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = members[i]
		if str(md.get("id", "")) == self_id:
			md["statuses"] = ctrl._player_statuses.duplicate(true)
			members[i] = md
			ctrl._party_state["members"] = members
			return

static func apply_party_invite(ctrl, action: Dictionary) -> void:
	var dir = str(action.get("direction", ""))
	var status = str(action.get("status", ""))
	if dir == "in" and status == "pending":
		ctrl._show_invite_dialog(str(action.get("invite_id", "")), str(action.get("name", "玩家")))
	elif dir == "in" and status != "pending":
		ctrl._hide_invite_dialog()
	if ctrl._party_panel != null and ctrl._party_panel.visible:
		ctrl._refresh_party_panel()

static func _build_party_stub(ctrl) -> void:
	## Live party shell panel (debug stubs via MockServer try_party_*).
	ctrl._party_panel = PanelContainer.new()
	ctrl._party_panel.name = "PartyPanel"
	ctrl._party_panel.set_script(HudDrag)
	ctrl._party_panel.screen_margin = 4.0
	ctrl._party_panel.min_size = Vector2(180, 100)
	ctrl._party_panel.default_size = Vector2(260, 300)
	ctrl._party_panel.initial_dock = "top_left"
	ctrl._party_panel.drag_anywhere = true
	ctrl.add_child(ctrl._party_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 12)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._party_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_child(outer)
	var head = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(head)
	var title = Label.new()
	title.text = "队伍"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._party_panel.visible = false)
	head.add_child(close_btn)
	ctrl._party_body = VBoxContainer.new()
	ctrl._party_body.name = "PartyBody"
	ctrl._party_body.add_theme_constant_override("separation", 4)
	ctrl._party_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(ctrl._party_body)
	ctrl._party_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._party_panel)
	ctrl._refresh_party_panel()
	ctrl.call_deferred("_nudge_party")

static func _nudge_party(ctrl) -> void:
	if ctrl._party_panel:
		ctrl._party_panel.global_position = Vector2(8, 160)

static func _toggle_party_panel(ctrl) -> void:
	if ctrl._party_panel == null:
		return
	ctrl._party_panel.visible = not ctrl._party_panel.visible
	if ctrl._party_panel.visible:
		ctrl._refresh_party_panel()
		ctrl._party_panel.move_to_front()
		ctrl.call_deferred("_nudge_party")

static func _party_in_party(ctrl) -> bool:
	var pid = str(ctrl._party_state.get("party_id", "")).strip_edges()
	var mem_v: Variant = ctrl._party_state.get("members", [])
	if pid.is_empty():
		return false
	return typeof(mem_v) == TYPE_ARRAY and not (mem_v as Array).is_empty()

static func apply_party_update(ctrl, action: Dictionary) -> void:
	## From World action dispatch / local try_* fallback.
	var party_v: Variant = action.get("party", action)
	if typeof(party_v) != TYPE_DICTIONARY:
		return
	var party: Dictionary = party_v
	ctrl._party_state = {
		"party_id": str(party.get("party_id", "")),
		"leader": str(party.get("leader", "")),
		"members": [],
		"shared_target_id": str(party.get("shared_target_id", "")),
		"shared_target_name": str(party.get("shared_target_name", "")),
		"loot_mode": str(party.get("loot_mode", "ffa")).strip_edges().to_lower(),
	}
	var mem_v: Variant = party.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for m in mem_v:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = m
			var st_v: Variant = md.get("statuses", [])
			var st_arr: Array = []
			if typeof(st_v) == TYPE_ARRAY:
				for s in st_v:
					if typeof(s) == TYPE_DICTIONARY:
						st_arr.append((s as Dictionary).duplicate(true))
			cleaned.append({
				"id": str(md.get("id", "")),
				"name": str(md.get("name", "?")),
				"hp": int(md.get("hp", 0)),
				"hp_max": maxi(int(md.get("hp_max", 1)), 1),
				"online": bool(md.get("online", true)),
				"statuses": st_arr,
			})
		ctrl._party_state["members"] = cleaned
	ctrl._refresh_party_panel()
	ctrl._sync_radar_party_stubs()

static func _sync_radar_party_stubs(ctrl) -> void:
	if ctrl._radar == null:
		return
	var others = 0
	var mem_v: Variant = ctrl._party_state.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		others = maxi((mem_v as Array).size() - 1, 0)
	if "show_party_stubs" in ctrl._radar:
		ctrl._radar.show_party_stubs = others > 0
	if ctrl._radar.has_method("set_party_angles"):
		var angles: Array = []
		for i in range(mini(others, 4)):
			angles.append(2.0 + float(i) * 1.1)
		ctrl._radar.set_party_angles(angles)
	elif "_party_angles" in ctrl._radar:
		var angles2: Array = []
		for i2 in range(mini(others, 4)):
			angles2.append(2.0 + float(i2) * 1.1)
		if angles2.is_empty():
			angles2 = [2.1, 4.0]
		ctrl._radar._party_angles = angles2
		ctrl._radar.queue_redraw()

static func _refresh_party_panel(ctrl) -> void:
	if ctrl._party_body == null:
		return
	for c in ctrl._party_body.get_children():
		c.queue_free()
	var self_id = ctrl._party_self_id_for_ui()
	var leader = str(ctrl._party_state.get("leader", ""))
	if not ctrl._party_in_party():
		ctrl._add_label(ctrl._party_body, "（未组队）", 11, L2Style.COL_MUTED)
		var create_btn = Button.new()
		create_btn.text = "创建队伍"
		create_btn.focus_mode = Control.FOCUS_NONE
		create_btn.pressed.connect(ctrl._on_party_create)
		L2Style.style_action_button(create_btn)
		create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl._party_body.add_child(create_btn)
		return
	# Shared assist target
	var st_name = str(ctrl._party_state.get("shared_target_name", "")).strip_edges()
	var st_id = str(ctrl._party_state.get("shared_target_id", "")).strip_edges()
	if not st_id.is_empty() or not st_name.is_empty():
		var tip = "目标：%s" % (st_name if not st_name.is_empty() else st_id)
		var st_row = HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 4)
		ctrl._party_body.add_child(st_row)
		var stl = Label.new()
		stl.text = tip
		stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stl.add_theme_font_size_override("font_size", 11)
		stl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
		stl.autowrap_mode = TextServer.AUTOWRAP_OFF
		st_row.add_child(stl)
		var clr = Button.new()
		clr.text = "清除"
		clr.focus_mode = Control.FOCUS_NONE
		clr.custom_minimum_size = Vector2(40, 22)
		clr.pressed.connect(ctrl._on_party_clear_shared_target)
		st_row.add_child(clr)
	else:
		ctrl._add_label(ctrl._party_body, "目标：（无）· 点选怪物同步", 10, Color(0.55, 0.55, 0.6))
	var mem_v: Variant = ctrl._party_state.get("members", [])
	var members: Array = mem_v if typeof(mem_v) == TYPE_ARRAY else []
	for m in members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var mid = str(md.get("id", ""))
		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		ctrl._party_body.add_child(row)
		var name_row = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 4)
		row.add_child(name_row)
		var expanded = bool(ctrl._party_expanded.get(mid, false))
		var expand_btn = Button.new()
		expand_btn.text = "▼" if expanded else "▶"
		expand_btn.focus_mode = Control.FOCUS_NONE
		expand_btn.custom_minimum_size = Vector2(22, 20)
		expand_btn.tooltip_text = "展开状态" if not expanded else "收起状态"
		expand_btn.pressed.connect(ctrl._on_party_toggle_expand.bind(mid))
		name_row.add_child(expand_btn)
		var nm = str(md.get("name", "?"))
		if mid == leader:
			nm = "★" + nm
		if mid == self_id:
			nm += "（我）"
		if not bool(md.get("online", true)):
			nm += "（离线）"
		var nl = Label.new()
		nl.text = nm
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		nl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton:
				var mb = ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					ctrl._on_party_toggle_expand(mid)
		)
		name_row.add_child(nl)
		if mid != self_id and leader == self_id:
			var kick = Button.new()
			kick.text = "踢"
			kick.focus_mode = Control.FOCUS_NONE
			kick.custom_minimum_size = Vector2(28, 20)
			kick.pressed.connect(ctrl._on_party_kick.bind(mid))
			name_row.add_child(kick)
		var bar = ProgressBar.new()
		bar.min_value = 0
		bar.max_value = float(maxi(int(md.get("hp_max", 1)), 1))
		bar.value = float(clampi(int(md.get("hp", 0)), 0, int(bar.max_value)))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl._style_status_bar(bar, Color(0.35, 0.75, 0.4, 1.0))
		row.add_child(bar)
		var hp_lab = Label.new()
		hp_lab.text = "%d/%d" % [int(md.get("hp", 0)), int(md.get("hp_max", 1))]
		hp_lab.add_theme_font_size_override("font_size", 9)
		hp_lab.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
		hp_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hp_lab)
		if expanded:
			var st_v2: Variant = md.get("statuses", [])
			var st_list: Array = []
			if typeof(st_v2) == TYPE_ARRAY:
				for s2 in st_v2:
					if typeof(s2) == TYPE_DICTIONARY:
						st_list.append(s2)
			# Prefer server statuses; fall back to live player chips for self.
			if st_list.is_empty() and mid == self_id:
				st_list = ctrl._player_statuses.duplicate(true)
			if st_list.is_empty():
				var empty_lab = Label.new()
				empty_lab.text = "（无状态）"
				empty_lab.add_theme_font_size_override("font_size", 10)
				empty_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
				empty_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(empty_lab)
			else:
				var sbar = StatusIconBar.new()
				sbar.name = "PartyMemberStatuses"
				sbar.icon_size = 24.0
				sbar.allow_cancel = false
				sbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(sbar)
				sbar.apply_statuses(st_list)
	# Invite row
	var inv_row = HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 4)
	ctrl._party_body.add_child(inv_row)
	var inv_edit = LineEdit.new()
	inv_edit.name = "PartyInviteEdit"
	inv_edit.placeholder_text = "右键玩家，或输入名字"
	inv_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_edit.custom_minimum_size = Vector2(0, 24)
	inv_row.add_child(inv_edit)
	var inv_btn = Button.new()
	inv_btn.text = "邀请"
	inv_btn.focus_mode = Control.FOCUS_NONE
	inv_btn.disabled = leader != self_id
	inv_btn.pressed.connect(func():
		var name = inv_edit.text.strip_edges()
		ctrl._on_party_invite(name)
	)
	inv_row.add_child(inv_btn)
	# Loot mode (leader-only control)
	var loot_row = HBoxContainer.new()
	loot_row.add_theme_constant_override("separation", 4)
	ctrl._party_body.add_child(loot_row)
	var loot_lab = Label.new()
	loot_lab.text = "拾取"
	loot_lab.add_theme_font_size_override("font_size", 10)
	loot_lab.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	loot_row.add_child(loot_lab)
	var loot_opt = OptionButton.new()
	loot_opt.focus_mode = Control.FOCUS_NONE
	loot_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_opt.add_item("自由", 0)
	loot_opt.set_item_metadata(0, "ffa")
	loot_opt.add_item("队长", 1)
	loot_opt.set_item_metadata(1, "leader")
	loot_opt.add_item("轮流", 2)
	loot_opt.set_item_metadata(2, "round_robin")
	loot_opt.add_item("需求/贪婪", 3)
	loot_opt.set_item_metadata(3, "need_greed")
	var cur_mode = str(ctrl._party_state.get("loot_mode", "ffa")).strip_edges().to_lower()
	if cur_mode == "":
		cur_mode = "ffa"
	elif cur_mode == "roll":
		cur_mode = "need_greed"
	var sel_idx = 0
	match cur_mode:
		"leader":
			sel_idx = 1
		"round_robin":
			sel_idx = 2
		"need_greed":
			sel_idx = 3
		_:
			sel_idx = 0
	loot_opt.select(sel_idx)
	var is_leader = leader == self_id
	loot_opt.disabled = not is_leader
	loot_opt.tooltip_text = "队长可切换：自由拾取 / 队长分配 / 轮流拾取 / 需求贪婪"
	if is_leader:
		loot_opt.item_selected.connect(func(idx: int):
			var m = str(loot_opt.get_item_metadata(idx))
			ctrl._on_party_set_loot_mode(m)
		)
	loot_row.add_child(loot_opt)
	var leave_btn = Button.new()
	leave_btn.text = "离开队伍"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.custom_minimum_size = Vector2(0, 26)
	leave_btn.pressed.connect(ctrl._on_party_leave)
	ctrl._party_body.add_child(leave_btn)

static func _party_self_id_for_ui(ctrl) -> String:
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		return str(srv._party_self_id())
	return "player"

static func _on_party_toggle_expand(ctrl, member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	var cur = bool(ctrl._party_expanded.get(member_id, false))
	ctrl._party_expanded[member_id] = not cur
	ctrl._refresh_party_panel()

static func _on_party_create(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_create"):
		ctrl._world_combat.request_party_create()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_create"):
		ctrl._apply_party_result_locally(srv.try_party_create())
	else:
		ctrl.append_system("无法创建队伍。")

static func _on_party_invite(ctrl, target: String = "") -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_invite"):
		ctrl._world_combat.request_party_invite(target)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_invite"):
		ctrl._apply_party_result_locally(srv.try_party_invite(target))
	else:
		ctrl.append_system("无法邀请。")

static func _on_party_kick(ctrl, member_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_kick"):
		ctrl._world_combat.request_party_kick(member_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_kick"):
		ctrl._apply_party_result_locally(srv.try_party_kick(member_id))
	else:
		ctrl.append_system("无法踢出。")

static func _on_party_clear_shared_target(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_clear_target"):
		ctrl._world_combat.request_party_clear_target()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_clear_target"):
		ctrl._apply_party_result_locally(srv.try_party_clear_target())

static func _on_party_debug_fill(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_debug_fill"):
		ctrl._world_combat.request_party_debug_fill()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_debug_fill"):
		var result: Dictionary = srv.try_party_debug_fill()
		ctrl._apply_party_result_locally(result)
	else:
		ctrl.append_system("无法创建调试队伍。")

static func _on_party_leave(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_leave"):
		ctrl._world_combat.request_party_leave()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_leave"):
		var result: Dictionary = srv.try_party_leave()
		ctrl._apply_party_result_locally(result)
	else:
		ctrl.append_system("无法离开队伍。")

static func _apply_party_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"party_update":
				ctrl.apply_party_update(action)
			"status_update":
				var tgt = str(action.get("target", "")).strip_edges().to_lower()
				if tgt == "player" or tgt == "":
					var st_v3: Variant = action.get("statuses", [])
					if typeof(st_v3) == TYPE_ARRAY:
						ctrl.apply_status_chips(st_v3)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

static func _sync_party_self_statuses_from_player(ctrl) -> void:
	var self_id = ctrl._party_self_id_for_ui()
	var mem_v: Variant = ctrl._party_state.get("members", [])
	if typeof(mem_v) != TYPE_ARRAY:
		return
	var members: Array = mem_v
	for i in range(members.size()):
		if typeof(members[i]) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = members[i]
		if str(md.get("id", "")) == self_id:
			md["statuses"] = ctrl._player_statuses.duplicate(true)
			members[i] = md
			ctrl._party_state["members"] = members
			return

static func apply_party_invite(ctrl, action: Dictionary) -> void:
	var dir = str(action.get("direction", ""))
	var status = str(action.get("status", ""))
	if dir == "in" and status == "pending":
		ctrl._show_invite_dialog(str(action.get("invite_id", "")), str(action.get("name", "玩家")))
	elif dir == "in" and status != "pending":
		ctrl._hide_invite_dialog()
	if ctrl._party_panel != null and ctrl._party_panel.visible:
		ctrl._refresh_party_panel()

static func _build_party_stub(ctrl) -> void:
	## Live party shell panel (debug stubs via MockServer try_party_*).
	ctrl._party_panel = PanelContainer.new()
	ctrl._party_panel.name = "PartyPanel"
	ctrl._party_panel.set_script(HudDrag)
	ctrl._party_panel.screen_margin = 4.0
	ctrl._party_panel.min_size = Vector2(180, 100)
	ctrl._party_panel.default_size = Vector2(260, 300)
	ctrl._party_panel.initial_dock = "top_left"
	ctrl._party_panel.drag_anywhere = true
	ctrl.add_child(ctrl._party_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 12)
	marg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl._party_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marg.add_child(outer)
	var head = HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(head)
	var title = Label.new()
	title.text = "队伍"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._party_panel.visible = false)
	head.add_child(close_btn)
	ctrl._party_body = VBoxContainer.new()
	ctrl._party_body.name = "PartyBody"
	ctrl._party_body.add_theme_constant_override("separation", 4)
	ctrl._party_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(ctrl._party_body)
	ctrl._party_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._party_panel)
	ctrl._refresh_party_panel()
	ctrl.call_deferred("_nudge_party")

static func _nudge_party(ctrl) -> void:
	if ctrl._party_panel:
		ctrl._party_panel.global_position = Vector2(8, 160)

static func _toggle_party_panel(ctrl) -> void:
	if ctrl._party_panel == null:
		return
	ctrl._party_panel.visible = not ctrl._party_panel.visible
	if ctrl._party_panel.visible:
		ctrl._refresh_party_panel()
		ctrl._party_panel.move_to_front()
		ctrl.call_deferred("_nudge_party")

static func _party_in_party(ctrl) -> bool:
	var pid = str(ctrl._party_state.get("party_id", "")).strip_edges()
	var mem_v: Variant = ctrl._party_state.get("members", [])
	if pid.is_empty():
		return false
	return typeof(mem_v) == TYPE_ARRAY and not (mem_v as Array).is_empty()

static func apply_party_update(ctrl, action: Dictionary) -> void:
	## From World action dispatch / local try_* fallback.
	var party_v: Variant = action.get("party", action)
	if typeof(party_v) != TYPE_DICTIONARY:
		return
	var party: Dictionary = party_v
	ctrl._party_state = {
		"party_id": str(party.get("party_id", "")),
		"leader": str(party.get("leader", "")),
		"members": [],
		"shared_target_id": str(party.get("shared_target_id", "")),
		"shared_target_name": str(party.get("shared_target_name", "")),
		"loot_mode": str(party.get("loot_mode", "ffa")).strip_edges().to_lower(),
	}
	var mem_v: Variant = party.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for m in mem_v:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var md: Dictionary = m
			var st_v: Variant = md.get("statuses", [])
			var st_arr: Array = []
			if typeof(st_v) == TYPE_ARRAY:
				for s in st_v:
					if typeof(s) == TYPE_DICTIONARY:
						st_arr.append((s as Dictionary).duplicate(true))
			cleaned.append({
				"id": str(md.get("id", "")),
				"name": str(md.get("name", "?")),
				"hp": int(md.get("hp", 0)),
				"hp_max": maxi(int(md.get("hp_max", 1)), 1),
				"online": bool(md.get("online", true)),
				"statuses": st_arr,
			})
		ctrl._party_state["members"] = cleaned
	ctrl._refresh_party_panel()
	ctrl._sync_radar_party_stubs()

static func _sync_radar_party_stubs(ctrl) -> void:
	if ctrl._radar == null:
		return
	var others = 0
	var mem_v: Variant = ctrl._party_state.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		others = maxi((mem_v as Array).size() - 1, 0)
	if "show_party_stubs" in ctrl._radar:
		ctrl._radar.show_party_stubs = others > 0
	if ctrl._radar.has_method("set_party_angles"):
		var angles: Array = []
		for i in range(mini(others, 4)):
			angles.append(2.0 + float(i) * 1.1)
		ctrl._radar.set_party_angles(angles)
	elif "_party_angles" in ctrl._radar:
		var angles2: Array = []
		for i2 in range(mini(others, 4)):
			angles2.append(2.0 + float(i2) * 1.1)
		if angles2.is_empty():
			angles2 = [2.1, 4.0]
		ctrl._radar._party_angles = angles2
		ctrl._radar.queue_redraw()

static func _refresh_party_panel(ctrl) -> void:
	if ctrl._party_body == null:
		return
	for c in ctrl._party_body.get_children():
		c.queue_free()
	var self_id = ctrl._party_self_id_for_ui()
	var leader = str(ctrl._party_state.get("leader", ""))
	if not ctrl._party_in_party():
		ctrl._add_label(ctrl._party_body, "（未组队）", 11, L2Style.COL_MUTED)
		var create_btn = Button.new()
		create_btn.text = "创建队伍"
		create_btn.focus_mode = Control.FOCUS_NONE
		create_btn.pressed.connect(ctrl._on_party_create)
		L2Style.style_action_button(create_btn)
		create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl._party_body.add_child(create_btn)
		return
	# Shared assist target
	var st_name = str(ctrl._party_state.get("shared_target_name", "")).strip_edges()
	var st_id = str(ctrl._party_state.get("shared_target_id", "")).strip_edges()
	if not st_id.is_empty() or not st_name.is_empty():
		var tip = "目标：%s" % (st_name if not st_name.is_empty() else st_id)
		var st_row = HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 4)
		ctrl._party_body.add_child(st_row)
		var stl = Label.new()
		stl.text = tip
		stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stl.add_theme_font_size_override("font_size", 11)
		stl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
		stl.autowrap_mode = TextServer.AUTOWRAP_OFF
		st_row.add_child(stl)
		var clr = Button.new()
		clr.text = "清除"
		clr.focus_mode = Control.FOCUS_NONE
		clr.custom_minimum_size = Vector2(40, 22)
		clr.pressed.connect(ctrl._on_party_clear_shared_target)
		st_row.add_child(clr)
	else:
		ctrl._add_label(ctrl._party_body, "目标：（无）· 点选怪物同步", 10, Color(0.55, 0.55, 0.6))
	var mem_v: Variant = ctrl._party_state.get("members", [])
	var members: Array = mem_v if typeof(mem_v) == TYPE_ARRAY else []
	for m in members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var mid = str(md.get("id", ""))
		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		ctrl._party_body.add_child(row)
		var name_row = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 4)
		row.add_child(name_row)
		var expanded = bool(ctrl._party_expanded.get(mid, false))
		var expand_btn = Button.new()
		expand_btn.text = "▼" if expanded else "▶"
		expand_btn.focus_mode = Control.FOCUS_NONE
		expand_btn.custom_minimum_size = Vector2(22, 20)
		expand_btn.tooltip_text = "展开状态" if not expanded else "收起状态"
		expand_btn.pressed.connect(ctrl._on_party_toggle_expand.bind(mid))
		name_row.add_child(expand_btn)
		var nm = str(md.get("name", "?"))
		if mid == leader:
			nm = "★" + nm
		if mid == self_id:
			nm += "（我）"
		if not bool(md.get("online", true)):
			nm += "（离线）"
		var nl = Label.new()
		nl.text = nm
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		nl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton:
				var mb = ev as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					ctrl._on_party_toggle_expand(mid)
		)
		name_row.add_child(nl)
		if mid != self_id and leader == self_id:
			var kick = Button.new()
			kick.text = "踢"
			kick.focus_mode = Control.FOCUS_NONE
			kick.custom_minimum_size = Vector2(28, 20)
			kick.pressed.connect(ctrl._on_party_kick.bind(mid))
			name_row.add_child(kick)
		var bar = ProgressBar.new()
		bar.min_value = 0
		bar.max_value = float(maxi(int(md.get("hp_max", 1)), 1))
		bar.value = float(clampi(int(md.get("hp", 0)), 0, int(bar.max_value)))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl._style_status_bar(bar, Color(0.35, 0.75, 0.4, 1.0))
		row.add_child(bar)
		var hp_lab = Label.new()
		hp_lab.text = "%d/%d" % [int(md.get("hp", 0)), int(md.get("hp_max", 1))]
		hp_lab.add_theme_font_size_override("font_size", 9)
		hp_lab.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
		hp_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hp_lab)
		if expanded:
			var st_v2: Variant = md.get("statuses", [])
			var st_list: Array = []
			if typeof(st_v2) == TYPE_ARRAY:
				for s2 in st_v2:
					if typeof(s2) == TYPE_DICTIONARY:
						st_list.append(s2)
			# Prefer server statuses; fall back to live player chips for self.
			if st_list.is_empty() and mid == self_id:
				st_list = ctrl._player_statuses.duplicate(true)
			if st_list.is_empty():
				var empty_lab = Label.new()
				empty_lab.text = "（无状态）"
				empty_lab.add_theme_font_size_override("font_size", 10)
				empty_lab.add_theme_color_override("font_color", L2Style.COL_MUTED)
				empty_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(empty_lab)
			else:
				var sbar = StatusIconBar.new()
				sbar.name = "PartyMemberStatuses"
				sbar.icon_size = 24.0
				sbar.allow_cancel = false
				sbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(sbar)
				sbar.apply_statuses(st_list)
	# Invite row
	var inv_row = HBoxContainer.new()
	inv_row.add_theme_constant_override("separation", 4)
	ctrl._party_body.add_child(inv_row)
	var inv_edit = LineEdit.new()
	inv_edit.name = "PartyInviteEdit"
	inv_edit.placeholder_text = "右键玩家，或输入名字"
	inv_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_edit.custom_minimum_size = Vector2(0, 24)
	inv_row.add_child(inv_edit)
	var inv_btn = Button.new()
	inv_btn.text = "邀请"
	inv_btn.focus_mode = Control.FOCUS_NONE
	inv_btn.disabled = leader != self_id
	inv_btn.pressed.connect(func():
		var name = inv_edit.text.strip_edges()
		ctrl._on_party_invite(name)
	)
	inv_row.add_child(inv_btn)
	# Loot mode (leader-only control)
	var loot_row = HBoxContainer.new()
	loot_row.add_theme_constant_override("separation", 4)
	ctrl._party_body.add_child(loot_row)
	var loot_lab = Label.new()
	loot_lab.text = "拾取"
	loot_lab.add_theme_font_size_override("font_size", 10)
	loot_lab.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	loot_row.add_child(loot_lab)
	var loot_opt = OptionButton.new()
	loot_opt.focus_mode = Control.FOCUS_NONE
	loot_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_opt.add_item("自由", 0)
	loot_opt.set_item_metadata(0, "ffa")
	loot_opt.add_item("队长", 1)
	loot_opt.set_item_metadata(1, "leader")
	loot_opt.add_item("轮流", 2)
	loot_opt.set_item_metadata(2, "round_robin")
	loot_opt.add_item("需求/贪婪", 3)
	loot_opt.set_item_metadata(3, "need_greed")
	var cur_mode = str(ctrl._party_state.get("loot_mode", "ffa")).strip_edges().to_lower()
	if cur_mode == "":
		cur_mode = "ffa"
	elif cur_mode == "roll":
		cur_mode = "need_greed"
	var sel_idx = 0
	match cur_mode:
		"leader":
			sel_idx = 1
		"round_robin":
			sel_idx = 2
		"need_greed":
			sel_idx = 3
		_:
			sel_idx = 0
	loot_opt.select(sel_idx)
	var is_leader = leader == self_id
	loot_opt.disabled = not is_leader
	loot_opt.tooltip_text = "队长可切换：自由拾取 / 队长分配 / 轮流拾取 / 需求贪婪"
	if is_leader:
		loot_opt.item_selected.connect(func(idx: int):
			var m = str(loot_opt.get_item_metadata(idx))
			ctrl._on_party_set_loot_mode(m)
		)
	loot_row.add_child(loot_opt)
	var leave_btn = Button.new()
	leave_btn.text = "离开队伍"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.custom_minimum_size = Vector2(0, 26)
	leave_btn.pressed.connect(ctrl._on_party_leave)
	ctrl._party_body.add_child(leave_btn)

static func _party_self_id_for_ui(ctrl) -> String:
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		return str(srv._party_self_id())
	return "player"

static func _on_party_toggle_expand(ctrl, member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	var cur = bool(ctrl._party_expanded.get(member_id, false))
	ctrl._party_expanded[member_id] = not cur
	ctrl._refresh_party_panel()

static func _on_party_create(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_create"):
		ctrl._world_combat.request_party_create()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_create"):
		ctrl._apply_party_result_locally(srv.try_party_create())
	else:
		ctrl.append_system("无法创建队伍。")

static func _on_party_invite(ctrl, target: String = "") -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_invite"):
		ctrl._world_combat.request_party_invite(target)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_invite"):
		ctrl._apply_party_result_locally(srv.try_party_invite(target))
	else:
		ctrl.append_system("无法邀请。")

static func _on_party_kick(ctrl, member_id: String) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_kick"):
		ctrl._world_combat.request_party_kick(member_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_kick"):
		ctrl._apply_party_result_locally(srv.try_party_kick(member_id))
	else:
		ctrl.append_system("无法踢出。")

static func _on_party_clear_shared_target(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_clear_target"):
		ctrl._world_combat.request_party_clear_target()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_clear_target"):
		ctrl._apply_party_result_locally(srv.try_party_clear_target())

static func _on_party_debug_fill(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_debug_fill"):
		ctrl._world_combat.request_party_debug_fill()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_debug_fill"):
		var result: Dictionary = srv.try_party_debug_fill()
		ctrl._apply_party_result_locally(result)
	else:
		ctrl.append_system("无法创建调试队伍。")

static func _on_party_leave(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_party_leave"):
		ctrl._world_combat.request_party_leave()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_party_leave"):
		var result: Dictionary = srv.try_party_leave()
		ctrl._apply_party_result_locally(result)
	else:
		ctrl.append_system("无法离开队伍。")

static func _apply_party_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"party_update":
				ctrl.apply_party_update(action)
			"status_update":
				var tgt = str(action.get("target", "")).strip_edges().to_lower()
				if tgt == "player" or tgt == "":
					var st_v3: Variant = action.get("statuses", [])
					if typeof(st_v3) == TYPE_ARRAY:
						ctrl.apply_status_chips(st_v3)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

