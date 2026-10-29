extends RefCounted
## UI panel: guild roster, invites, management.

var ctrl
var _actions: HBoxContainer
var _pending_request := ""
var _request_error := ""
var _request_serial := 0
var _guild_context := ""
var _transfer_target := ""
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")
const RequestPipeline = preload("res://scripts/net/request_pipeline.gd")
const GameWindow = preload("res://scripts/ui/game_window.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")

func _build_guild_panel() -> void:
	ctrl._guild_panel = PanelContainer.new()
	ctrl._guild_panel.name = "GuildPanel"
	ctrl._guild_panel.set_script(GameWindow)
	ctrl._guild_panel.screen_margin = 4.0
	ctrl._guild_panel.min_size = Vector2(300, 260)
	ctrl._guild_panel.default_size = Vector2(360, 460)
	ctrl._guild_panel.initial_dock = "none"
	ctrl._guild_panel.drag_anywhere = true
	ctrl.add_child(ctrl._guild_panel)
	var outer = GameWindow.build_body(ctrl._guild_panel, "公会", func(): ctrl._guild_panel.visible = false, "GuildTitle")
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 300)
	outer.add_child(scroll)
	ctrl._guild_body = VBoxContainer.new()
	ctrl._guild_body.name = "GuildBody"
	ctrl._guild_body.add_theme_constant_override("separation", 4)
	ctrl._guild_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ctrl._guild_body)
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.add_theme_constant_override("separation", 8)
	outer.add_child(_actions)
	ctrl._guild_panel.visible = false
	ctrl._apply_l2_chrome(ctrl._guild_panel)
	_refresh_guild_panel()
	ctrl.call_deferred("_nudge_guild")



func _nudge_guild() -> void:
	if ctrl._guild_panel == null:
		return
	ctrl._guild_panel.size = Vector2(360, 460)
	var vp = ctrl.get_viewport_rect().size
	ctrl._window_manager_logic.place_at(ctrl._guild_panel, Vector2(maxi(8, int(vp.x * 0.5 - 180)), 88))



func _toggle_guild_panel(force_open: bool = false) -> void:
	if ctrl._guild_panel == null:
		return
	ctrl._guild_panel.visible = true if force_open else not ctrl._guild_panel.visible
	if ctrl._guild_panel.visible:
		_ensure_guild_context()
		_sync_guild_snapshot()
		var srv = Net.server()
		if srv != null and srv.has_method("try_guild_refresh"):
			_dispatch_guild("try_guild_refresh")
		_refresh_guild_panel()
		ctrl._guild_panel.move_to_front()
		ctrl.call_deferred("_nudge_guild")


func _guild_identity() -> String:
	var srv = Net.server()
	if srv == null:
		return ""
	return str(srv.get_instance_id()) + (JSON.stringify(srv.context()) if srv.has_method("context") else "")


func _ensure_guild_context() -> void:
	var identity := _guild_identity()
	if identity == _guild_context:
		return
	_guild_context = identity
	_request_serial += 1
	_pending_request = ""
	_request_error = ""
	_transfer_target = ""
	ctrl._guild_state.clear()
	ctrl._guild_pending_invite.clear()


func _sync_guild_snapshot() -> void:
	var srv = Net.server()
	if srv != null and srv.has_method("snapshot_guild"):
		apply_guild_update({"guild": srv.snapshot_guild()})


func apply_guild_update(action: Dictionary) -> void:
	var gu_v: Variant = action.get("guild", action)
	if typeof(gu_v) != TYPE_DICTIONARY:
		return
	_ensure_guild_context()
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
	ctrl._guild_state = gu.duplicate(true)
	ctrl._guild_state["members"] = members_out
	# A full remote snapshot replaces incoming invites, including an empty list.
	# Legacy MockServer snapshots omit this key and still send guild_invite actions.
	if gu.has("invites") or not str(gu.get("id", "")).is_empty():
		ctrl._guild_pending_invite.clear()
		var invites: Variant = gu.get("invites", [])
		if invites is Array and not invites.is_empty() and invites[0] is Dictionary:
			ctrl._guild_pending_invite = invites[0].duplicate(true)
	if not members_out.any(func(member): return member.id == _transfer_target):
		_transfer_target = ""
	ctrl._refresh_name_with_title()
	if ctrl._guild_panel != null and ctrl._guild_panel.visible:
		_refresh_guild_panel()
	# Refresh character window 血盟 chip if open.
	if ctrl._windows.has("character"):
		var cw: Variant = ctrl._windows["character"]
		if cw is Control and (cw as Control).visible:
			ctrl._fill_window("character")



func apply_guild_invite(action: Dictionary) -> void:
	_ensure_guild_context()
	# Remote invites are part of the authoritative snapshot; legacy notifications
	# must never resurrect an invite that was consumed, expired or revoked.
	if Net.is_real_server() or ctrl._guild_state.has("invites"):
		_sync_guild_snapshot()
		return
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
	var name_text := str(ctrl._guild_name_input.text) if is_instance_valid(ctrl._guild_name_input) else ""
	var invite_text := str(ctrl._guild_invite_input.text) if is_instance_valid(ctrl._guild_invite_input) else ""
	for host in [ctrl._guild_body, _actions]:
		if host == null:
			continue
		for child in host.get_children():
			host.remove_child(child)
			child.queue_free()
	ctrl._guild_name_input = null
	ctrl._guild_invite_input = null
	var srv = Net.server()
	var supported := bool(ctrl._guild_state.get("supported", true))
	var loaded := bool(ctrl._guild_state.get("loaded", true))
	if srv != null and srv.has_method("try_guild_refresh") and _actions != null:
		_add_button(_actions, "刷新", _dispatch_guild.bind("try_guild_refresh"), not supported)
	if not _pending_request.is_empty():
		_add_label("正在刷新公会…" if _pending_request == "try_guild_refresh" else "正在提交公会操作…", 12, L2Style.COL_MUTED)
	if not _request_error.is_empty():
		_add_label(_request_error, 12, L2Style.COL_GOLD)
	if not supported:
		_add_label("此服务器尚未提供公会管理。", 12, L2Style.COL_MUTED)
		return
	if not loaded:
		if _pending_request.is_empty():
			_add_label("公会资料尚未载入，请刷新重试。", 12, L2Style.COL_MUTED)
		return

	var gid := str(ctrl._guild_state.get("id", "")).strip_edges()
	var members: Array = ctrl._guild_state.get("members", [])
	var self_id := str(ctrl._guild_state.get("self_id", ""))
	if self_id.is_empty() and srv != null:
		if srv.has_method("_guild_self_id"):
			self_id = str(srv._guild_self_id())
		elif srv.has_method("_party_self_id"):
			self_id = str(srv._party_self_id())
	var is_leader := not gid.is_empty() and str(ctrl._guild_state.get("leader_id", "")) == self_id and not self_id.is_empty()
	var capacity := maxi(1, int(ctrl._guild_state.get("max_members", 20)))
	var invites: Variant = ctrl._guild_state.get("invites", [])
	if not ctrl._guild_state.has("invites") and not ctrl._guild_pending_invite.is_empty():
		invites = [ctrl._guild_pending_invite]
	if invites is Array:
		for invite in invites:
			if not invite is Dictionary or str(invite.get("status", "pending")) != "pending":
				continue
			var invite_id := str(invite.get("invite_id", "")).strip_edges()
			if invite_id.is_empty():
				continue
			_add_label("收到邀请：【%s】来自 %s" % [str(invite.get("guild_name", "?")), str(invite.get("from", "?"))], 12, L2Style.COL_GOLD)
			var invite_row := HBoxContainer.new()
			ctrl._guild_body.add_child(invite_row)
			_add_button(invite_row, "接受", _on_guild_invite_respond.bind(invite_id, true))
			_add_button(invite_row, "拒绝", _on_guild_invite_respond.bind(invite_id, false))

	if gid.is_empty():
		_add_label("你还没有公会。", 12, L2Style.COL_MUTED)
		_add_label("创建费用：%d 金币 · 人数上限：%d" % [int(ctrl._guild_state.get("creation_fee", 0)), capacity], 11, L2Style.COL_MUTED)
		var create_row := HBoxContainer.new()
		create_row.add_theme_constant_override("separation", 6)
		ctrl._guild_body.add_child(create_row)
		ctrl._guild_name_input = LineEdit.new()
		ctrl._guild_name_input.placeholder_text = "公会名称（2～12字）"
		ctrl._guild_name_input.text = name_text
		ctrl._guild_name_input.editable = _pending_request.is_empty()
		ctrl._guild_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl._guild_name_input.text_submitted.connect(func(_text: String): _on_guild_create_pressed())
		create_row.add_child(ctrl._guild_name_input)
		_add_button(create_row, "创建公会", _on_guild_create_pressed)
		return

	_add_label("公会：%s" % str(ctrl._guild_state.get("name", "")), 13, L2Style.COL_TITLE)
	_add_label("人数 %d / %d" % [members.size(), capacity], 11, L2Style.COL_MUTED)
	if is_leader:
		var can_invite := bool(ctrl._guild_state.get("can_invite", members.size() < capacity))
		var invite_row := HBoxContainer.new()
		invite_row.add_theme_constant_override("separation", 6)
		ctrl._guild_body.add_child(invite_row)
		ctrl._guild_invite_input = LineEdit.new()
		ctrl._guild_invite_input.placeholder_text = "输入名字邀请" if can_invite else "公会人数已满"
		ctrl._guild_invite_input.text = invite_text
		ctrl._guild_invite_input.editable = _pending_request.is_empty() and can_invite
		ctrl._guild_invite_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctrl._guild_invite_input.text_submitted.connect(_on_guild_invite)
		invite_row.add_child(ctrl._guild_invite_input)
		_add_button(invite_row, "邀请", func(): _on_guild_invite(ctrl._guild_invite_input.text), not can_invite)
		var outgoing: Variant = ctrl._guild_state.get("outgoing_invites", [])
		if outgoing is Array:
			for invite in outgoing:
				if invite is Dictionary and str(invite.get("status", "pending")) == "pending":
					_add_label("等待 %s 接受邀请" % str(invite.get("target_name", "?")), 11, L2Style.COL_MUTED)

	for member in members:
		var member_id := str(member.get("id", ""))
		var member_name := str(member.get("name", "?"))
		var rank := str(member.get("rank", "member"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.custom_minimum_size.y = 30
		ctrl._guild_body.add_child(row)
		var label := Label.new()
		label.text = "%s（%s）" % [member_name, "会长" if rank == "leader" else "成员"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)
		if is_leader and member_id != self_id and rank != "leader":
			if srv != null and srv.has_method("try_guild_transfer"):
				_add_button(row, "转让", _select_transfer.bind(member_id))
			_add_button(row, "踢出", _on_guild_kick.bind(member_id))
			if _transfer_target == member_id:
				_add_label("将会长转让给【%s】后，你将成为普通成员。" % member_name, 12, L2Style.COL_GOLD)
				var confirmation := HBoxContainer.new()
				ctrl._guild_body.add_child(confirmation)
				_add_button(confirmation, "确认转让", _on_guild_transfer.bind(member_id))
				_add_button(confirmation, "取消", _select_transfer.bind(""))

	var leader_must_transfer := is_leader and Net.is_real_server()
	if leader_must_transfer:
		_add_label("会长离会前需先转让会长，或解散公会。", 11, L2Style.COL_MUTED)
	if _actions != null:
		_add_button(_actions, "离开公会", _on_guild_leave, leader_must_transfer)
		if is_leader:
			_add_button(_actions, "解散公会", _on_guild_disband)


func _add_label(text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	ctrl._guild_body.add_child(label)


func _add_button(parent: Node, text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = disabled or not _pending_request.is_empty()
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _select_transfer(member_id: String) -> void:
	_transfer_target = member_id
	_refresh_guild_panel()


func _on_guild_transfer(member_id: String) -> void:
	if member_id.is_empty() or member_id != _transfer_target:
		return
	_transfer_target = ""
	_dispatch_guild("try_guild_transfer", [member_id])


func _on_guild_create_pressed() -> void:
	var guild_name := str(ctrl._guild_name_input.text).strip_edges() if is_instance_valid(ctrl._guild_name_input) else ""
	if guild_name.is_empty():
		ctrl.append_system("请输入公会名称。")
		return
	_dispatch_guild("try_guild_create", [guild_name])


func _on_guild_invite(target: String) -> void:
	target = target.strip_edges()
	if target.is_empty():
		ctrl.append_system("请输入要邀请的玩家名字。")
		return
	_dispatch_guild("try_guild_invite", [target])


func _on_guild_kick(member_id: String) -> void:
	if not member_id.strip_edges().is_empty():
		_dispatch_guild("try_guild_kick", [member_id.strip_edges()])


func _on_guild_leave() -> void:
	_dispatch_guild("try_guild_leave")


func _on_guild_disband() -> void:
	_dispatch_guild("try_guild_disband")


func _on_guild_invite_respond(invite_id: String, accept: bool) -> void:
	if not invite_id.strip_edges().is_empty():
		_dispatch_guild("try_guild_invite_respond", [invite_id.strip_edges(), accept])


func _dispatch_guild(method: String, args: Array = []) -> void:
	_ensure_guild_context()
	if not _pending_request.is_empty():
		return
	_pending_request = method
	_request_error = ""
	_request_serial += 1
	var serial := _request_serial
	var world = ctrl._world_combat
	var applies_actions: bool = is_instance_valid(world) and world.has_method("_apply_server_actions")
	var result := RequestPipeline.dispatch(world if applies_actions else null, method, args,
		func(reply: Dictionary): _guild_request_finished(reply, serial, applies_actions))
	# Pipeline validation failures return before invoking the applier.
	if not result.get("deferred", false) and not _pending_request.is_empty():
		_guild_request_finished(result, serial, applies_actions)
	_refresh_guild_panel()


func _guild_request_finished(result: Dictionary, serial: int, actions_applied: bool) -> void:
	if not is_instance_valid(ctrl):
		return
	_ensure_guild_context()
	if serial != _request_serial:
		_sync_guild_snapshot()
		_refresh_guild_panel()
		return
	_pending_request = ""
	if not actions_applied:
		_apply_guild_result_locally(result)
	if not bool(result.get("ok", false)):
		_request_error = str(result.get("error", "公会操作失败，请刷新后重试。"))
	_sync_guild_snapshot()
	_refresh_guild_panel()


func _apply_guild_result_locally(result: Dictionary) -> void:
	var actions: Variant = result.get("actions", [])
	if not actions is Array:
		return
	for action in actions:
		if not action is Dictionary:
			continue
		match str(action.get("type", "")):
			"guild_update":
				apply_guild_update(action)
			"guild_invite":
				apply_guild_invite(action)
			"system_message":
				var message := str(action.get("text", "")).strip_edges()
				if not message.is_empty():
					ctrl.append_system(message)
