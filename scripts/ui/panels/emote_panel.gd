extends RefCounted
## UI panel: emote picker.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _on_remote_debug_spawn(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_remote_debug_spawn"):
		ctrl._world_combat.request_remote_debug_spawn("")
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_remote_debug_spawn"):
		var result: Dictionary = srv.try_remote_debug_spawn("")
		ctrl._apply_chat_result_locally(result)
		# Also ask world if bound
		if ctrl._world_combat != null:
			pass



static func _build_emote_panel(ctrl) -> void:
	ctrl._emote_panel = PanelContainer.new()
	ctrl._emote_panel.name = "EmotePanel"
	ctrl._emote_panel.set_script(HudDrag)
	ctrl._emote_panel.screen_margin = 4.0
	ctrl._emote_panel.min_size = Vector2(280, 200)
	ctrl._emote_panel.default_size = Vector2(340, 280)
	ctrl._emote_panel.initial_dock = "none"
	ctrl._emote_panel.drag_anywhere = true
	ctrl.add_child(ctrl._emote_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._emote_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "EmoteTitle"
	title.text = "表情"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._emote_panel.visible = false)
	head.add_child(close_btn)
	ctrl._emote_body = VBoxContainer.new()
	ctrl._emote_body.name = "EmoteBody"
	ctrl._emote_body.add_theme_constant_override("separation", 6)
	ctrl._emote_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(ctrl._emote_body)
	ctrl._emote_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._emote_panel)
	ctrl._refresh_emote_panel()
	ctrl.call_deferred("_nudge_emote")



static func _nudge_emote(ctrl) -> void:
	if ctrl._emote_panel == null:
		return
	ctrl._emote_panel.size = Vector2(340, 280)
	var vp = ctrl.get_viewport_rect().size
	ctrl._emote_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 170)), 96)



static func _toggle_emote_panel(ctrl, force_open: bool = false) -> void:
	if ctrl._emote_panel == null:
		return
	if force_open:
		ctrl._emote_panel.visible = true
	else:
		ctrl._emote_panel.visible = not ctrl._emote_panel.visible
	if ctrl._emote_panel.visible:
		ctrl._refresh_emote_panel()
		ctrl._emote_panel.move_to_front()
		ctrl.call_deferred("_nudge_emote")



static func _emote_catalog_rows(ctrl) -> Array:
	var srv = Net.server()
	if srv != null and srv.has_method("emote_catalog"):
		var live: Array = srv.emote_catalog()
		if not live.is_empty():
			return live
	# Static mirror of MockServer.EMOTE_CATALOG labels (fallback).
	return [
		{"id": "wave", "label": "挥手", "text": "（挥手）"},
		{"id": "laugh", "label": "大笑", "text": "哈哈哈"},
		{"id": "bow", "label": "鞠躬", "text": "（鞠躬）"},
		{"id": "cry", "label": "哭泣", "text": "（呜呜）"},
		{"id": "angry", "label": "生气", "text": "（哼！）"},
		{"id": "love", "label": "爱心", "text": "❤"},
		{"id": "cheer", "label": "加油", "text": "（加油！）"},
		{"id": "think", "label": "思考", "text": "（思考中…）"},
		{"id": "shrug", "label": "耸肩", "text": "（耸肩）"},
		{"id": "clap", "label": "鼓掌", "text": "（啪啪啪）"},
		{"id": "sleepy", "label": "困倦", "text": "（打哈欠）"},
		{"id": "wow", "label": "惊讶", "text": "（哇！）"},
	]



static func _refresh_emote_panel(ctrl) -> void:
	if ctrl._emote_body == null:
		return
	for c in ctrl._emote_body.get_children():
		c.queue_free()
	ctrl._add_label(ctrl._emote_body, "选择表情（服务器冷却）", 11, L2Style.COL_MUTED)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._emote_body.add_child(grid)
	var rows: Array = ctrl._emote_catalog_rows()
	if rows.is_empty():
		ctrl._add_label(ctrl._emote_body, "（暂无表情）", 12, L2Style.COL_MUTED)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var eid = str(row.get("id", "")).strip_edges()
		if eid.is_empty():
			continue
		var btn = Button.new()
		btn.text = str(row.get("label", eid))
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(96, 32)
		btn.pressed.connect(ctrl._on_emote_pressed.bind(eid))
		grid.add_child(btn)



static func _on_emote_pressed(ctrl, emote_id: String) -> void:
	emote_id = str(emote_id).strip_edges()
	if emote_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_emote"):
		ctrl._world_combat.request_emote(emote_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_emote"):
		ctrl._apply_emote_result_locally(srv.try_emote(emote_id))
	else:
		ctrl.append_system("无法使用表情。")



static func _apply_emote_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)
			"emote":
				# Without world host, still echo bubble text to system chat.
				var bubble = str(action.get("text", "")).strip_edges()
				if not bubble.is_empty():
					ctrl.append_system(bubble)



