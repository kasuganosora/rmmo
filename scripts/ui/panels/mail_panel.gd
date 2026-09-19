extends RefCounted
## UI panel: mail box.

const Net = preload("res://scripts/net/net.gd")
const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

static func _build_mail_panel(ctrl) -> void:
	ctrl._mail_panel = PanelContainer.new()
	ctrl._mail_panel.name = "MailPanel"
	ctrl._mail_panel.set_script(HudDrag)
	ctrl._mail_panel.screen_margin = 4.0
	ctrl._mail_panel.min_size = Vector2(420, 320)
	ctrl._mail_panel.default_size = Vector2(520, 480)
	ctrl._mail_panel.initial_dock = "none"
	ctrl._mail_panel.drag_anywhere = true
	ctrl.add_child(ctrl._mail_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 12)
	marg.add_theme_constant_override("margin_top", 8)
	marg.add_theme_constant_override("margin_right", 12)
	marg.add_theme_constant_override("margin_bottom", 10)
	ctrl._mail_panel.add_child(marg)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	marg.add_child(outer)
	var head = HBoxContainer.new()
	outer.add_child(head)
	var title = Label.new()
	title.name = "MailTitle"
	title.text = "邮件"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn = Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): ctrl._mail_panel.visible = false)
	head.add_child(close_btn)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	outer.add_child(scroll)
	ctrl._mail_body = VBoxContainer.new()
	ctrl._mail_body.name = "MailBody"
	ctrl._mail_body.add_theme_constant_override("separation", 4)
	ctrl._mail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._mail_body)
	ctrl._add_label(outer, "写信", 12, L2Style.COL_TITLE)
	ctrl._mail_to_input = LineEdit.new()
	ctrl._mail_to_input.placeholder_text = "收件人（自己 / 好友 / 旅人）"
	outer.add_child(ctrl._mail_to_input)
	ctrl._mail_subject_input = LineEdit.new()
	ctrl._mail_subject_input.placeholder_text = "主题"
	outer.add_child(ctrl._mail_subject_input)
	ctrl._mail_body_input = TextEdit.new()
	ctrl._mail_body_input.custom_minimum_size = Vector2(0, 64)
	ctrl._mail_body_input.placeholder_text = "正文"
	outer.add_child(ctrl._mail_body_input)
	var attach_row = HBoxContainer.new()
	attach_row.add_theme_constant_override("separation", 6)
	outer.add_child(attach_row)
	ctrl._add_label(attach_row, "金币", 11, L2Style.COL_MUTED)
	ctrl._mail_gold_spin = SpinBox.new()
	ctrl._mail_gold_spin.min_value = 0
	ctrl._mail_gold_spin.max_value = 999999
	ctrl._mail_gold_spin.step = 1
	ctrl._mail_gold_spin.custom_minimum_size = Vector2(90, 0)
	attach_row.add_child(ctrl._mail_gold_spin)
	ctrl._add_label(attach_row, "物品ID", 11, L2Style.COL_MUTED)
	ctrl._mail_item_id_input = LineEdit.new()
	ctrl._mail_item_id_input.placeholder_text = "可选"
	ctrl._mail_item_id_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attach_row.add_child(ctrl._mail_item_id_input)
	ctrl._add_label(attach_row, "数量", 11, L2Style.COL_MUTED)
	ctrl._mail_item_qty_spin = SpinBox.new()
	ctrl._mail_item_qty_spin.min_value = 1
	ctrl._mail_item_qty_spin.max_value = 99
	ctrl._mail_item_qty_spin.value = 1
	ctrl._mail_item_qty_spin.custom_minimum_size = Vector2(70, 0)
	attach_row.add_child(ctrl._mail_item_qty_spin)
	var send_btn = Button.new()
	send_btn.text = "发送"
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(ctrl._on_mail_send)
	outer.add_child(send_btn)
	ctrl._mail_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._mail_panel)
	ctrl._refresh_mail_panel()
	ctrl.call_deferred("_nudge_mail")

static func _nudge_mail(ctrl) -> void:
	if ctrl._mail_panel == null:
		return
	ctrl._mail_panel.size = Vector2(520, 480)
	var vp = ctrl.get_viewport_rect().size
	ctrl._mail_panel.global_position = Vector2(maxi(8, int(vp.x * 0.5 - 260)), 72)

static func _toggle_mail_panel(ctrl, force_open: bool = false) -> void:
	if ctrl._mail_panel == null:
		return
	if force_open:
		ctrl._mail_panel.visible = true
	else:
		ctrl._mail_panel.visible = not ctrl._mail_panel.visible
	if ctrl._mail_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_mail"):
			ctrl.apply_mail_update({"type": "mail_update", "mail": srv.snapshot_mail()})
		ctrl._refresh_mail_panel()
		ctrl._mail_panel.move_to_front()
		ctrl.call_deferred("_nudge_mail")

static func apply_mail_update(ctrl, action: Dictionary) -> void:
	var mail_v: Variant = action.get("mail", action)
	if typeof(mail_v) != TYPE_DICTIONARY:
		if typeof(mail_v) == TYPE_ARRAY:
			ctrl._mail_state = {"mails": [], "count": 0, "max_mail": 30}
			var cleaned0: Array = []
			for e0 in mail_v:
				if typeof(e0) == TYPE_DICTIONARY:
					cleaned0.append((e0 as Dictionary).duplicate(true))
			ctrl._mail_state["mails"] = cleaned0
			ctrl._mail_state["count"] = cleaned0.size()
			if ctrl._mail_panel != null and ctrl._mail_panel.visible:
				ctrl._refresh_mail_panel()
		return
	var md: Dictionary = mail_v
	ctrl._mail_state = {
		"mails": [],
		"count": int(md.get("count", 0)),
		"max_mail": int(md.get("max_mail", 30)),
	}
	var list_v: Variant = md.get("mails", [])
	if typeof(list_v) == TYPE_ARRAY:
		var cleaned: Array = []
		for e in list_v:
			if typeof(e) == TYPE_DICTIONARY:
				cleaned.append((e as Dictionary).duplicate(true))
		ctrl._mail_state["mails"] = cleaned
		ctrl._mail_state["count"] = cleaned.size()
	if ctrl._mail_panel != null and ctrl._mail_panel.visible:
		ctrl._refresh_mail_panel()

static func _refresh_mail_panel(ctrl) -> void:
	if ctrl._mail_body == null:
		return
	for c in ctrl._mail_body.get_children():
		c.queue_free()
	var mails_v: Variant = ctrl._mail_state.get("mails", [])
	var mails: Array = mails_v if typeof(mails_v) == TYPE_ARRAY else []
	var cap = int(ctrl._mail_state.get("max_mail", 30))
	ctrl._add_label(ctrl._mail_body, "收件箱 %d / %d" % [mails.size(), cap], 11, L2Style.COL_MUTED)
	if mails.is_empty():
		ctrl._add_label(ctrl._mail_body, "（暂无邮件）", 12, L2Style.COL_MUTED)
		return
	for e in mails:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var mid = str(e.get("id", ""))
		var frm = str(e.get("from", "?"))
		var subj = str(e.get("subject", "（无主题）"))
		var is_read = bool(e.get("read", false))
		var claimed = bool(e.get("claimed", false))
		var gold = int(e.get("gold", 0))
		var items_v2: Variant = e.get("items", [])
		var items2: Array = items_v2 if typeof(items_v2) == TYPE_ARRAY else []
		var row = VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		ctrl._mail_body.add_child(row)
		var mark = "" if is_read else "● "
		var attach_hint = ""
		if not claimed and (gold > 0 or not items2.is_empty()):
			attach_hint = " [附件]"
		var nl = Label.new()
		nl.text = "%s%s ← %s%s" % [mark, subj, frm, attach_hint]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.7) if not is_read else L2Style.COL_TEXT)
		row.add_child(nl)
		var body_txt = str(e.get("body", "")).strip_edges()
		if not body_txt.is_empty():
			ctrl._add_label(row, body_txt, 10, L2Style.COL_MUTED)
		if gold > 0 or not items2.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			if gold > 0:
				parts.append("金币 %d" % gold)
			for it in items2:
				if typeof(it) != TYPE_DICTIONARY:
					continue
				var iid = str(it.get("id", ""))
				var q = int(it.get("qty", 0))
				if iid.is_empty() or q <= 0:
					continue
				parts.append("%s×%d" % [ctrl._item_label(iid), q])
			if parts.size() > 0:
				ctrl._add_label(row, "附件：%s%s" % [", ".join(parts), "（已领）" if claimed else ""], 10, L2Style.COL_GOLD)
		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		var read_btn = Button.new()
		read_btn.text = "阅读"
		read_btn.focus_mode = Control.FOCUS_NONE
		read_btn.custom_minimum_size = Vector2(48, 24)
		read_btn.pressed.connect(ctrl._on_mail_read.bind(mid))
		btn_row.add_child(read_btn)
		var claim_btn = Button.new()
		claim_btn.text = "收取"
		claim_btn.focus_mode = Control.FOCUS_NONE
		claim_btn.custom_minimum_size = Vector2(48, 24)
		claim_btn.disabled = claimed or (gold <= 0 and items2.is_empty())
		claim_btn.pressed.connect(ctrl._on_mail_claim.bind(mid))
		btn_row.add_child(claim_btn)
		var del_btn = Button.new()
		del_btn.text = "删除"
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.custom_minimum_size = Vector2(48, 24)
		del_btn.pressed.connect(ctrl._on_mail_delete.bind(mid))
		btn_row.add_child(del_btn)

static func _on_mail_send(ctrl) -> void:
	var to = ctrl._mail_to_input.text.strip_edges() if ctrl._mail_to_input else ""
	var subject = ctrl._mail_subject_input.text.strip_edges() if ctrl._mail_subject_input else ""
	var body = ctrl._mail_body_input.text if ctrl._mail_body_input else ""
	var gold = int(ctrl._mail_gold_spin.value) if ctrl._mail_gold_spin else 0
	var item_id = ctrl._mail_item_id_input.text.strip_edges() if ctrl._mail_item_id_input else ""
	var qty = int(ctrl._mail_item_qty_spin.value) if ctrl._mail_item_qty_spin else 1
	if to.is_empty():
		ctrl.append_system("请填写收件人。")
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_send"):
		ctrl._world_combat.request_mail_send(to, subject, body, gold, item_id, qty)
	else:
		var srv = Net.server()
		if srv != null and srv.has_method("try_mail_send"):
			ctrl._apply_mail_result_locally(srv.try_mail_send(to, subject, body, gold, item_id, qty))
		else:
			ctrl.append_system("无法发送邮件。")
			return
	if ctrl._mail_to_input:
		ctrl._mail_to_input.text = ""
	if ctrl._mail_subject_input:
		ctrl._mail_subject_input.text = ""
	if ctrl._mail_body_input:
		ctrl._mail_body_input.text = ""
	if ctrl._mail_gold_spin:
		ctrl._mail_gold_spin.value = 0
	if ctrl._mail_item_id_input:
		ctrl._mail_item_id_input.text = ""
	if ctrl._mail_item_qty_spin:
		ctrl._mail_item_qty_spin.value = 1

static func _on_mail_read(ctrl, mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	ctrl._mail_selected_id = mail_id
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_read"):
		ctrl._world_combat.request_mail_read(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_read"):
		ctrl._apply_mail_result_locally(srv.try_mail_read(mail_id))

static func _on_mail_claim(ctrl, mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_claim"):
		ctrl._world_combat.request_mail_claim(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_claim"):
		ctrl._apply_mail_result_locally(srv.try_mail_claim(mail_id))

static func _on_mail_delete(ctrl, mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_delete"):
		ctrl._world_combat.request_mail_delete(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_delete"):
		ctrl._apply_mail_result_locally(srv.try_mail_delete(mail_id))

static func _apply_mail_result_locally(ctrl, result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"mail_update":
				ctrl.apply_mail_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)

