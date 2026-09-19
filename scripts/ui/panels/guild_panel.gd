extends RefCounted
## UI panel: guild roster, invites, management.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _build_guild_panel() -> void:
	ctrl._guild_panel = PanelContainer.new()
	ctrl._guild_panel.name = "GuildPanel"
	ctrl._guild_panel.set_script(HudDrag)
	ctrl._guild_panel.screen_margin = 4.0
	ctrl._guild_panel.min_size = Vector2(300, 260)
	ctrl._guild_panel.default_size = Vector2(360, 460)
	ctrl._guild_panel.initial_dock = "none"
	ctrl._guild_panel.drag_anywhere = true
	ctrl.add_child(ctrl._guild_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._guild_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "GuildTitle"
	title.text = "公会"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._guild_panel.visible = false)
	head.add_child(close_btn)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	outer.add_child(scroll)
	ctrl._guild_body = VBoxContainer.new()
	ctrl._guild_body.name = "GuildBody"
	ctrl._guild_body.add_theme_constant_override("separation", 4)
	ctrl._guild_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._guild_body)
	ctrl._guild_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._guild_panel)
	_refresh_guild_panel()
	ctrl.call_deferred("_nudge_guild")



func _nudge_guild() -> void:
	if ctrl._guild_panel == null:
		return
	ctrl._guild_panel.size = Vector2(360, 460)
	var vp = ctrl.get_viewport_rect().size
	ctrl._guild_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 180)), 88)



func _toggle_guild_panel(force_open: bool = false) -> void:
	if ctrl._guild_panel == null:
		return
	if force_open:
		ctrl._guild_panel.visible = true
	else:
		ctrl._guild_panel.visible = not ctrl._guild_panel.visible
	if ctrl._guild_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_guild"):
			apply_guild_update({"type": "guild_update", "guild": srv.snapshot_guild()})
		_refresh_guild_panel()
		ctrl._guild_panel.move_to_front()
		ctrl.call_deferred("_nudge_guild")



func apply_guild_update(action: Dictionary) -> void:
	var gu_v: Variant = action.get("guild", action)
	if typeof(gu_v) != TYPE_DICTIONARY:
		return
	var gu: Dictionary = gu_v
	var members_out: Array = []
	var mem_v: Variant = gu.get("members", [])
	if typeof(mem_v) == TYPE_ARRAY:
		for e in mem_v:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			members_out.append({
				"id": str(e.get("id", "")),
				"name": str(e.get("name", "?")),
				"rank": str(e.get("rank", "member")),
			})
	ctrl._guild_state = {
		"id": str(gu.get("id", "")),
		"name": str(gu.get("name", "")),
		"leader_id": str(gu.get("leader_id", "")),
		"members": members_out,
	}
	ctrl._refresh_name_with_title()
	if ctrl._guild_panel != null and ctrl._guild_panel.visible:
		_refresh_guild_panel()
	# Refresh character window 血盟 chip if open.
	if ctrl._windows.has("character"):
		var cw: Variant = ctrl._windows["character"]
		if cw is Control and (cw as Control).visible:
			ctrl._fill_window("character")



func apply_guild_invite(action: Dictionary) -> void:
	var status = str(action.get("status", "pending"))
	var invite_id = str(action.get("invite_id", "")).strip_edges()
	var gname = str(action.get("guild_name", "")).strip_edges()
	var from_name = str(action.get("from", "")).strip_edges()
	if status == "pending" and not invite_id.is_empty():
		ctrl._guild_pending_invite = {
			"invite_id": invite_id,
			"guild_name": gname,
			"from": from_name,
		}
		if ctrl._guild_panel != null and ctrl._guild_panel.visible:
			_refresh_guild_panel()
		ctrl.append_system("【%s】邀请你加入公会【%s】。" % [from_name if from_name != "" else "?", gname if gname != "" else "?"])
	else:
		if str(ctrl._guild_pending_invite.get("invite_id", "")) == invite_id:
			ctrl._guild_pending_invite.clear()
		if ctrl._guild_panel != null and ctrl._guild_panel.visible:
			_refresh_guild_panel()



func _refresh_guild_panel() -> void:
	if ctrl._guild_body == null:
		return
	for c in ctrl._guild_body.get_children():
		c.queue_free()
	ctrl._guild_name_input = null
	ctrl._guild_invite_input = null
	var gid = str(ctrl._guild_state.get("id", "")).strip_edges()
	var gname = str(ctrl._guild_state.get("name", "")).strip_edges()
	var leader_id = str(ctrl._guild_state.get("leader_id", "")).strip_edges()
	var members: Array = ctrl._guild_state.get("members", []) if typeof(ctrl._guild_state.get("members", [])) == TYPE_ARRAY else []
	var self_id = ""
	var srv = Net.server()
	if srv != null and srv.has_method("_guild_self_id"):
		self_id = str(srv._guild_self_id())
	elif srv != null and srv.has_method("_party_self_id"):
		self_id = str(srv._party_self_id())
	var is_leader = gid != "" and leader_id != "" and leader_id == self_id

	# Pending invite banner
	var pend_id = str(ctrl._guild_pending_invite.get("invite_id", "")).strip_edges()
	if not pend_id.is_empty():
		ctrl._add_label(ctrl._guild_body, "收到邀请：【%s】来自 %s" % [
			str(ctrl._guild_pending_invite.get("guild_name", "?")),
			str(ctrl._guild_pending_invite.get("from", "?")),
		], 12, L2Style.COL_GOLD)
		var prow = HBoxContainer.new()
		prow.add_theme_constant_override("separation", 6)
		ctrl._guild_body.add_child(prow)
		var acc = Button.new()
		acc.text = "接受"
		acc.focus_mode = Control.FOCUS_NONE
		acc.pressed.connect(func(): _on_guild_invite_respond(pend_id, true))
		prow.add_child(acc)
		var dec = Button.new()
		dec.text = "拒绝"
		dec.focus_mode = Control.FOCUS_NONE
		dec.pressed.connect(func(): _on_guild_invite_respond(pend_id, false))
		prow.add_child(dec)

	if gid.is_empty() or members.is_empty():
		ctrl._add_label(ctrl._guild_body, "你还没有公会。", 12, L2Style.COL_MUTED)
		var crow = HBoxContainer.new()
		crow.add_theme_constant_override("separation", 6)
		ctrl._guild_body.add_child(crow)
		ctrl._guild_name_input = LineEdit.new()
		ctrl._guild_name_input.placeholder_text = "公会名称（2～12字）"
		ctrl._guild_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(ctrl._guild_name_input)
		var create_btn = Button.new()
		create_btn.text = "创建公会"
		create_btn.focus_mode = Control.FOCUS_NONE
		create_btn.pressed.connect(_on_guild_create_pressed)
		crow.add_child(create_btn)
		return

	ctrl._add_label(ctrl._guild_body, "公会：%s" % gname, 13, L2Style.COL_TITLE)
	ctrl._add_label(ctrl._guild_body, "人数 %d / 20" % members.size(), 11, L2Style.COL_MUTED)

	if is_leader:
		var irow = HBoxContainer.new()
		irow.add_theme_constant_override("separation", 6)
		ctrl._guild_body.add_child(irow)
		ctrl._guild_invite_input = LineEdit.new()
		ctrl._guild_invite_input.placeholder_text = "输入名字邀请"
		ctrl._guild_invite_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl._guild_invite_input.text_submitted.connect(func(t: String): _on_guild_invite(t))
		irow.add_child(ctrl._guild_invite_input)
		var inv_btn = Button.new()
		inv_btn.text = "邀请"
		inv_btn.focus_mode = Control.FOCUS_NONE
		inv_btn.pressed.connect(func(): _on_guild_invite(ctrl._guild_invite_input.text if ctrl._guild_invite_input else ""))
		irow.add_child(inv_btn)

	for e in members:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var mid = str(e.get("id", ""))
		var mname = str(e.get("name", "?"))
		var rank = str(e.get("rank", "member"))
		var rank_cn = "会长" if rank == "leader" else "成员"
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		ctrl._guild_body.add_child(row)
		var nl = Label.new()
		nl.text = "%s（%s）" % [mname, rank_cn]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		row.add_child(nl)
		if is_leader and mid != self_id and rank != "leader":
			var kick_btn = Button.new()
			kick_btn.text = "踢出"
			kick_btn.focus_mode = Control.FOCUS_NONE
			kick_btn.custom_minimum_size = Vector2(48, 24)
			kick_btn.pressed.connect(_on_guild_kick.bind(mid))
			row.add_child(kick_btn)

	var brow = HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	ctrl._guild_body.add_child(brow)
	var leave_btn = Button.new()
	leave_btn.text = "离开公会"
	leave_btn.focus_mode = Control.FOCUS_NONE
	leave_btn.pressed.connect(_on_guild_leave)
	brow.add_child(leave_btn)
	if is_leader:
		var dis_btn = Button.new()
		dis_btn.text = "解散公会"
		dis_btn.focus_mode = Control.FOCUS_NONE
		dis_btn.pressed.connect(_on_guild_disband)
		brow.add_child(dis_btn)



func _on_guild_create_pressed() -> void:
	var n = ""
	if ctrl._guild_name_input != null:
		n = str(ctrl._guild_name_input.text).strip_edges()
	if n.is_empty():
		ctrl.append_system("请输入公会名称。")
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_guild_create"):
		ctrl._world_combat.request_guild_create(n)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_create"):
		_apply_guild_result_locally(srv.try_guild_create(n))
	else:
		ctrl.append_system("无法创建公会。")



func _on_guild_invite(target: String) -> void:
	target = str(target).strip_edges()
	if target.is_empty():
		ctrl.append_system("请输入要邀请的玩家名字。")
		return
	if ctrl._guild_invite_input != null:
		ctrl._guild_invite_input.text = ""
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_guild_invite"):
		ctrl._world_combat.request_guild_invite(target)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_invite"):
		_apply_guild_result_locally(srv.try_guild_invite(target))
	else:
		ctrl.append_system("无法邀请。")



func _on_guild_kick(member_id: String) -> void:
	member_id = str(member_id).strip_edges()
	if member_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_guild_kick"):
		ctrl._world_combat.request_guild_kick(member_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_kick"):
		_apply_guild_result_locally(srv.try_guild_kick(member_id))



func _on_guild_leave() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_guild_leave"):
		ctrl._world_combat.request_guild_leave()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_leave"):
		_apply_guild_result_locally(srv.try_guild_leave())



func _on_guild_disband() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_guild_disband"):
		ctrl._world_combat.request_guild_disband()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_disband"):
		_apply_guild_result_locally(srv.try_guild_disband())



func _on_guild_invite_respond(invite_id: String, accept: bool) -> void:
	invite_id = str(invite_id).strip_edges()
	if invite_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_guild_invite_respond"):
		ctrl._world_combat.request_guild_invite_respond(invite_id, accept)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_guild_invite_respond"):
		_apply_guild_result_locally(srv.try_guild_invite_respond(invite_id, accept))



func _apply_guild_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"guild_update":
				apply_guild_update(action)
			"guild_invite":
				apply_guild_invite(action)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)


