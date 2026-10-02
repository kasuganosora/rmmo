extends RefCounted
## UI panel: mail box.

var ctrl
var _tabs: HBoxContainer
var _inbox: ScrollContainer
var _compose: VBoxContainer
var _send_button: Button
var _page := 0
var _sending := false
var _feedback: Label
var _feedback_state: Array = []
func _init(c):
	ctrl = c

const UIRequest = preload("res://scripts/ui/ui_request.gd")
const Net = preload("res://scripts/net/net.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const ItemGrid = preload("res://scripts/ui/item_grid.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _build_mail_panel() -> void:
	ctrl._mail_panel = PanelContainer.new()
	ctrl._mail_panel.name = "MailPanel"
	ctrl._mail_panel.set_script(GameWindow)
	ctrl._mail_panel.screen_margin = 4.0
	ctrl._mail_panel.min_size = Vector2(420, 320)
	ctrl._mail_panel.default_size = Vector2(520, 480)
	ctrl._mail_panel.initial_dock = "none"
	ctrl._mail_panel.drag_anywhere = true
	ctrl.add_child(ctrl._mail_panel)
	var outer = GameWindow.build_body(ctrl._mail_panel, "邮件", func(): ctrl._mail_panel.hide(), "MailTitle")
	_tabs = GameWindow.add_tabs(outer, ["收件箱", "写信"], _select_page)
	_inbox = ScrollContainer.new()
	_inbox.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_inbox)
	ctrl._mail_body = VBoxContainer.new()
	ctrl._mail_body.name = "MailBody"
	ctrl._mail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._mail_body.add_theme_constant_override("separation", 10)
	_inbox.add_child(ctrl._mail_body)
	_compose = VBoxContainer.new()
	_compose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_compose.add_theme_constant_override("separation", 5)
	outer.add_child(_compose)
	ctrl._mail_to_input = LineEdit.new()
	ctrl._mail_to_input.placeholder_text = "玩家名字"
	GameWindow.field(_compose, "收件人", ctrl._mail_to_input)
	ctrl._mail_subject_input = LineEdit.new()
	ctrl._mail_subject_input.placeholder_text = "信件主题"
	GameWindow.field(_compose, "主题", ctrl._mail_subject_input)
	ctrl._mail_body_input = TextEdit.new()
	ctrl._mail_body_input.placeholder_text = "写点什么…"
	ctrl._mail_body_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._mail_body_input.custom_minimum_size.y = 65
	_compose.add_child(ctrl._mail_body_input)
	ctrl._mail_gold_spin = SpinBox.new()
	ctrl._mail_gold_spin.min_value = 0
	ctrl._mail_gold_spin.max_value = 999999
	GameWindow.field(_compose, "附加金币", ctrl._mail_gold_spin)
	ctrl._add_label(_compose, "附加物品 · 从背包选择", 11, L2Style.COL_MUTED)
	ctrl._mail_item_id_input = ItemGrid.create(ctrl, _compose, "MailItemPicker", 82)
	ctrl._mail_item_id_input.size_flags_vertical = Control.SIZE_FILL
	ctrl._mail_item_qty_spin = SpinBox.new()
	ctrl._mail_item_qty_spin.min_value = 1
	ctrl._mail_item_qty_spin.value = 1
	GameWindow.field(_compose, "物品数量", ctrl._mail_item_qty_spin)
	ctrl._mail_item_id_input.item_selected.connect(func(_i): ctrl._mail_item_id_input.sync_quantity(ctrl._mail_item_qty_spin))
	_feedback = UIRequest.status(_compose, "MailStatus")
	ctrl._mail_to_input.text_changed.connect(func(_text): _clear_feedback_on_edit())
	ctrl._mail_subject_input.text_changed.connect(func(_text): _clear_feedback_on_edit())
	ctrl._mail_body_input.text_changed.connect(_clear_feedback_on_edit)
	ctrl._mail_gold_spin.value_changed.connect(func(_value): _clear_feedback_on_edit())
	ctrl._mail_item_qty_spin.value_changed.connect(func(_value): _clear_feedback_on_edit())
	ctrl._mail_item_id_input.item_selected.connect(func(_item): _clear_feedback_on_edit())
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	_compose.add_child(actions)
	_send_button = Button.new()
	_send_button.text = "发送邮件"
	_send_button.custom_minimum_size = Vector2(112, 30)
	L2Style.style_primary_button(_send_button)
	_send_button.pressed.connect(_on_mail_send)
	_send_button.disabled = true
	ctrl._mail_to_input.text_changed.connect(func(text): _send_button.disabled = _sending or text.strip_edges().is_empty())
	var clear_attachment := Button.new()
	clear_attachment.text = "取消附件"
	clear_attachment.pressed.connect(func(): ctrl._mail_item_id_input.select_key(""))
	actions.add_child(clear_attachment)
	actions.add_child(_send_button)
	_select_page(0)
	ctrl._mail_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._mail_panel)
	_refresh_mail_panel()
	ctrl.call_deferred("_nudge_mail")



func _nudge_mail() -> void:
	if ctrl._mail_panel == null:
		return
	ctrl._mail_panel.size = Vector2(520, 480)
	var vp = ctrl.get_viewport_rect().size
	ctrl._window_manager_logic.place_at(ctrl._mail_panel, Vector2(maxi(8, int(vp.x * 0.5 - 260)), 72))



func _toggle_mail_panel(force_open: bool = false) -> void:
	if ctrl._mail_panel == null:
		return
	if force_open:
		ctrl._mail_panel.visible = true
	else:
		ctrl._mail_panel.visible = not ctrl._mail_panel.visible
	if ctrl._mail_panel.visible:
		var srv = Net.server()
		if srv != null and srv.has_method("snapshot_mail"):
			apply_mail_update({"type": "mail_update", "mail": srv.snapshot_mail()})
		_refresh_mail_panel()
		ctrl._mail_panel.move_to_front()
		ctrl.call_deferred("_nudge_mail")



func apply_mail_update(action: Dictionary) -> void:
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
				_refresh_mail_panel()
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
		_refresh_mail_panel()



func _refresh_mail_panel() -> void:
	if ctrl._mail_body == null:
		return
	for c in ctrl._mail_body.get_children():
		ctrl._mail_body.remove_child(c)
		c.queue_free()
	_refresh_attachment_choices()
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
		var subject_button := Button.new()
		subject_button.text = "%s%s%s" % [mark, subj, attach_hint]
		subject_button.tooltip_text = "%s\n来自 %s" % [subj, frm]
		subject_button.custom_minimum_size.y = 30
		L2Style.style_row_button(subject_button, ctrl._mail_selected_id == mid)
		subject_button.pressed.connect(func():
			ctrl._mail_selected_id = "" if ctrl._mail_selected_id == mid else mid
			_refresh_mail_panel()
			if ctrl._mail_selected_id == mid: _on_mail_read(mid)
		)
		row.add_child(subject_button)
		ctrl._add_label(row, "来自 " + frm, 11, L2Style.COL_MUTED)
		if ctrl._mail_selected_id != mid: continue
		var body_txt = str(e.get("body", "")).strip_edges()
		if not body_txt.is_empty():
			ctrl._add_label(row, body_txt, 12, L2Style.COL_TEXT).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if gold > 0: ctrl._add_label(row, "金币 %d%s" % [gold, "（已领）" if claimed else ""], 11, L2Style.COL_GOLD)
		if not items2.is_empty():
			var attachments = ItemGrid.create(ctrl, row, "MailAttachments", 90)
			attachments.minimum_cells = 0
			attachments.set_items(items2)
			if claimed: ctrl._add_label(row, "附件已领取", 11, L2Style.COL_MUTED)
		var btn_row = HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 4)
		row.add_child(btn_row)
		var claim_btn = Button.new()
		claim_btn.text = "收取附件"
		claim_btn.focus_mode = Control.FOCUS_NONE
		claim_btn.custom_minimum_size = Vector2(48, 24)
		claim_btn.disabled = claimed or (gold <= 0 and items2.is_empty())
		claim_btn.pressed.connect(_on_mail_claim.bind(mid))
		btn_row.add_child(claim_btn)
		var del_btn = Button.new()
		del_btn.text = "删除"
		del_btn.focus_mode = Control.FOCUS_NONE
		del_btn.custom_minimum_size = Vector2(48, 24)
		del_btn.pressed.connect(_on_mail_delete.bind(mid))
		btn_row.add_child(del_btn)



func _on_mail_send() -> void:
	if _sending: return
	var to = ctrl._mail_to_input.text.strip_edges() if ctrl._mail_to_input else ""
	var subject = ctrl._mail_subject_input.text.strip_edges() if ctrl._mail_subject_input else ""
	var body = ctrl._mail_body_input.text if ctrl._mail_body_input else ""
	var gold = int(ctrl._mail_gold_spin.value) if ctrl._mail_gold_spin else 0
	var item_id = str(ctrl._mail_item_id_input.selected_item().get("item_id", ""))
	var qty = int(ctrl._mail_item_qty_spin.value) if ctrl._mail_item_qty_spin else 1
	if to.is_empty():
		ctrl.append_system("请填写收件人。")
		return
	_sending = true
	UIRequest.lock_form(_compose, true)
	_send_button.text = "发送中…"
	UIRequest.set_status(_feedback, "正在发送，请等待结果…")
	UIRequest.dispatch(ctrl, "try_mail_send", [to, subject, body, gold, item_id, qty], _apply_mail_result_locally, _mail_send_finished)


func _mail_send_finished(result: Dictionary) -> void:
	_sending = false
	UIRequest.lock_form(_compose, false)
	_send_button.text = "发送邮件"
	_refresh_attachment_choices()
	UIRequest.set_status(_feedback, UIRequest.message(result, "邮件已发送"), not result.get("ok", false))
	_send_button.disabled = ctrl._mail_to_input.text.strip_edges().is_empty()
	if not result.get("ok", false):
		_feedback_state = _compose_state()
		return
	if ctrl._mail_to_input:
		ctrl._mail_to_input.text = ""
		_send_button.disabled = true
	if ctrl._mail_subject_input:
		ctrl._mail_subject_input.text = ""
	if ctrl._mail_body_input:
		ctrl._mail_body_input.text = ""
	if ctrl._mail_gold_spin:
		ctrl._mail_gold_spin.value = 0
	if ctrl._mail_item_id_input:
		ctrl._mail_item_id_input.select_key("")
		ctrl._mail_item_id_input.sync_quantity(ctrl._mail_item_qty_spin)
	if ctrl._mail_item_qty_spin:
		ctrl._mail_item_qty_spin.value = 1
	UIRequest.set_status(_feedback, "邮件已发送")
	_feedback_state = _compose_state()


func _clear_feedback_on_edit() -> void:
	# Ignore notifications that do not change the form associated with this result.
	if not _sending and _compose_state() != _feedback_state: _feedback.text = ""


func _compose_state() -> Array:
	return [ctrl._mail_to_input.text, ctrl._mail_subject_input.text, ctrl._mail_body_input.text, ctrl._mail_gold_spin.value, ctrl._mail_item_id_input.selected_key, ctrl._mail_item_qty_spin.value]



func _on_mail_read(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	ctrl._mail_selected_id = mail_id
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_read"):
		ctrl._world_combat.request_mail_read(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_read"):
		_apply_mail_result_locally(srv.try_mail_read(mail_id))



func _on_mail_claim(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_claim"):
		ctrl._world_combat.request_mail_claim(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_claim"):
		_apply_mail_result_locally(srv.try_mail_claim(mail_id))



func _on_mail_delete(mail_id: String) -> void:
	mail_id = str(mail_id).strip_edges()
	if mail_id.is_empty():
		return
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_mail_delete"):
		ctrl._world_combat.request_mail_delete(mail_id)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_mail_delete"):
		_apply_mail_result_locally(srv.try_mail_delete(mail_id))



func _apply_mail_result_locally(result: Dictionary) -> void:
	var actions_v: Variant = result.get("actions", [])
	if typeof(actions_v) != TYPE_ARRAY:
		return
	for a in actions_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = a
		match str(action.get("type", "")):
			"mail_update":
				apply_mail_update(action)
			"inventory_update":
				var items_v: Variant = action.get("items", [])
				var items: Array = items_v if typeof(items_v) == TYPE_ARRAY else []
				ctrl.apply_inventory_snapshot(items, int(action.get("gold", -1)))
			"system_message":
				var msg = str(action.get("text", "")).strip_edges()
				if not msg.is_empty():
					ctrl.append_system(msg)




func _refresh_attachment_choices() -> void:
	if ctrl._mail_item_id_input == null or _sending: return
	ctrl._mail_item_id_input.fill_inventory(ctrl._server_inventory)
	ctrl._mail_item_id_input.sync_quantity(ctrl._mail_item_qty_spin)
	ctrl._mail_gold_spin.max_value = maxi(0, ctrl._server_gold)


func _select_page(index: int) -> void:
	_page = index
	GameWindow.highlight_tabs(_tabs, index)
	_inbox.visible = index == 0
	_compose.visible = index == 1
	if index == 1: _refresh_attachment_choices()
