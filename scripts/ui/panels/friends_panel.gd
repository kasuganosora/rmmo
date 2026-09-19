extends RefCounted
## UI panel: friends list and whispers.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _build_friends_panel(ctrl) -> void:
	ctrl._friends_panel = PanelContainer.new()
	ctrl._friends_panel.name = "FriendsPanel"
	ctrl._friends_panel.set_script(HudDrag)
	ctrl._friends_panel.screen_margin = 4.0
	ctrl._friends_panel.min_size = Vector2(280, 220)
	ctrl._friends_panel.default_size = Vector2(340, 420)
	ctrl._friends_panel.initial_dock = "none"
	ctrl._friends_panel.drag_anywhere = true
	ctrl.add_child(ctrl._friends_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._friends_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "FriendsTitle"
	title.text = "好友"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._friends_panel.visible = false)
	head.add_child(close_btn)
	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	outer.add_child(add_row)
	ctrl._friends_add_input = LineEdit.new()
	ctrl._friends_add_input.placeholder_text = "输入玩家名字"
	ctrl._friends_add_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._friends_add_input.text_submitted.connect(func(t: String): ctrl._on_friend_add(t))
	add_row.add_child(ctrl._friends_add_input)
	var add_btn = Button.new()
	add_btn.text = "添加"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.pressed.connect(func(): ctrl._on_friend_add(ctrl._friends_add_input.text if ctrl._friends_add_input else ""))
	add_row.add_child(add_btn)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	outer.add_child(scroll)
	ctrl._friends_body = VBoxContainer.new()
	ctrl._friends_body.name = "FriendsBody"
	ctrl._friends_body.add_theme_constant_override("separation", 4)
	ctrl._friends_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._friends_body)
	ctrl._friends_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._friends_panel)
	ctrl._refresh_friends_panel()
	ctrl.call_deferred("_nudge_friends")

static func _nudge_friends(ctrl) -> void:
	if ctrl._friends_panel == null:
		return
	ctrl._friends_panel.size = Vector2(340, 420)
	var vp = ctrl.get_viewport_rect().size
	ctrl._friends_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 170)), 96)

static func _toggle_friends_panel(ctrl, force_open: bool = false) -> void:
	if ctrl._friends_panel == null:
		return
	if force_open:
		ctrl._friends_panel.visible = true
	else:
		ctrl._friends_panel.visible = not ctrl._friends_panel.visible
	if ctrl._friends_panel.visible:
		# Refresh online flags from server snapshot when opening.
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_friends"):
			ctrl.apply_friends_update({"type": "friends_update", "friends": srv.snapshot_friends()})
		ctrl._refresh_friends_panel()
		ctrl._friends_panel.move_to_front()
		ctrl.call_deferred("_nudge_friends")

static func apply_friends_update(ctrl, action: Dictionary) -> void:
	var fr_v: Variant = action.get("friends", action)
	if typeof(fr_v) != TYPE_DICTIONARY:
		# Allow raw array payload
		if typeof(fr_v) == TYPE_ARRAY:
			ctrl._friends_state = {"friends": [], "count": 0, "max_friends": 50}
			var cleaned0: Array = []
			for e0 in fr_v:
				if typeof(e0) == TYPE_DICTIONARY:
					cleaned0.append({
						"id": str(e0.get("id", "")),
						"name": str(e0.get("name", "?")),
						"online": bool(e0.get("online", false)),
					})
			ctrl._friends_state["friends"] = cleaned0
			ctrl._friends_state["count"] = cleaned0.size()
			if ctrl._friends_panel != null and ctrl._friends_panel.visible:
				ctrl._refresh_friends_panel()
		return
	var fr: Dictionary = fr_v
	ctrl._friends_state = {
		"friends": [],
		"count": int(fr.get("count", 0)),
		"max_friends": int(fr.get("max_friends", 50)),
	}
	var list_v: Variant = fr.get("friends", [])
	if typeof(list_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for e in list_v:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			cleaned.append({
				"id": str(e.get("id", "")),
				"name": str(e.get("name", "?")),
				"online": bool(e.get("online", false)),
			})
		ctrl._friends_state["friends"] = cleaned
		ctrl._friends_state["count"] = cleaned.size()
	if ctrl._friends_panel != null and ctrl._friends_panel.visible:
		ctrl._refresh_friends_panel()

static func _refresh_friends_panel(ctrl) -> void:
	if ctrl._friends_body == null:
		return
	for c in ctrl._friends_body.get_children():
		c.queue_free()
	var friends_v: Variant = ctrl._friends_state.get("friends", [])
	var friends: Array = friends_v if typeof(friends_v) == TYPE_ARRAY else []
	var cap = int(ctrl._friends_state.get("max_friends", 50))
	ctrl._add_label(ctrl._friends_body, "人数 %d / %d" % [friends.size(), cap], 11, L2Style.COL_MUTED)
	if friends.is_empty():
		ctrl._add_label(ctrl._friends_body, "（暂无好友）", 12, L2Style.COL_MUTED)
		return
	for e in friends:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var fid = str(e.get("id", ""))
		var fname = str(e.get("name", "?"))
		var online = bool(e.get("online", false))
		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		ctrl._friends_body.add_child(row)
		var name_row = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		row.add_child(name_row)
		var nl = Label.new()
		nl.text = "%s（%s）" % [fname, "在线" if online else "离线"]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75) if online else Color(0.65, 0.65, 0.7))
		name_row.add_child(nl)
		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		var whisper_btn = Button.new()
		whisper_btn.text = "私聊"
		whisper_btn.focus_mode = Control.FOCUS_NONE
		whisper_btn.custom_minimum_size = Vector2(48, 24)
		whisper_btn.pressed.connect(ctrl._on_friend_whisper.bind(fname))
		btn_row.add_child(whisper_btn)
		var invite_btn = Button.new()
		invite_btn.text = "邀请入队"
		invite_btn.focus_mode = Control.FOCUS_NONE
		invite_btn.custom_minimum_size = Vector2(72, 24)
		invite_btn.pressed.connect(ctrl._on_friend_invite.bind(fname))
		btn_row.add_child(invite_btn)
		var ginv_btn = Button.new()
		ginv_btn.text = "邀请入会"
		ginv_btn.focus_mode = Control.FOCUS_NONE
		ginv_btn.custom_minimum_size = Vector2(72, 24)
		ginv_btn.pressed.connect(ctrl._on_guild_invite.bind(fname))
		btn_row.add_child(ginv_btn)
		var del_btn = Button.new()
		del_btn.text = "删除"
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.custom_minimum_size = Vector2(48, 24)
		del_btn.pressed.connect(ctrl._on_friend_remove.bind(fid))
		btn_row.add_child(del_btn)

static func _on_friend_add(ctrl, name_or_id: String) -> void:
	name_or_id = str(name_or_id).strip_edges()
	if name_or_id.is_empty():
		ctrl.append_system("请输入要添加的玩家名字。")
		return
	if ctrl._friends_add_input != null:
		ctrl._friends_add_input.text = ""
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_friend_add"):
		ctrl._world_combat.request_friend_add(name_or_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_friend_add"):
		ctrl._apply_friends_result_locally(srv.try_friend_add(name_or_id))
	else:
		ctrl.append_system("无法添加好友。")

static func _on_friend_remove(ctrl, friend_id: String) -> void:
	friend_id = str(friend_id).strip_edges()
	if friend_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_friend_remove"):
		ctrl._world_combat.request_friend_remove(friend_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_friend_remove"):
		ctrl._apply_friends_result_locally(srv.try_friend_remove(friend_id))

static func _on_friend_whisper(ctrl, target_name: String) -> void:
	ctrl.prefill_whisper(str(ctrl.target_name).strip_edges())

static func _on_friend_invite(ctrl, target_name: String) -> void:
	ctrl._on_party_invite(str(ctrl.target_name).strip_edges())

static func _apply_friends_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"friends_update":
				ctrl.apply_friends_update(action)
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

