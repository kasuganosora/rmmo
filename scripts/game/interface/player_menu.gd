extends RefCounted
## Interface layer: player right-click context menu.

static func _ensure_player_context_menu(ctrl) -> PopupMenu:
	if ctrl._player_ctx_menu != null and is_instance_valid(ctrl._player_ctx_menu):
		return ctrl._player_ctx_menu
	# Prefer GameHud-owned menu (CanvasLayer); fall back to a local PopupMenu.
	if ctrl.hud != null and ctrl.hud.has_method("ensure_player_context_menu"):
		ctrl._player_ctx_menu = ctrl.hud.ensure_player_context_menu()
		if ctrl._player_ctx_menu != null:
			return ctrl._player_ctx_menu
	ctrl._player_ctx_menu = PopupMenu.new()
	ctrl._player_ctx_menu.name = "PlayerContextMenu"
	ctrl.add_child(ctrl._player_ctx_menu)
	if not ctrl._player_ctx_menu.id_pressed.is_connected(ctrl._on_player_context_id):
		ctrl._player_ctx_menu.id_pressed.connect(ctrl._on_player_context_id)
	return ctrl._player_ctx_menu

static func _close_player_context_menu(ctrl) -> void:
	if ctrl.hud != null and ctrl.hud.has_method("close_player_context_menu"):
		ctrl.hud.close_player_context_menu()
		return
	if ctrl._player_ctx_menu != null and is_instance_valid(ctrl._player_ctx_menu) and ctrl._player_ctx_menu.visible:
		ctrl._player_ctx_menu.hide()

static func _open_player_context_menu(ctrl, marker: Node2D, screen_pos: Vector2) -> void:
	if marker == null:
		return
	var pid = str(marker.get_meta("player_id", "")).strip_edges()
	var dname = str(marker.get_meta("display_name", pid)).strip_edges()
	if dname.is_empty():
		dname = pid
	if ctrl.hud != null and ctrl.hud.has_method("open_player_context_menu"):
		ctrl.hud.open_player_context_menu(pid, dname, screen_pos)
		return
	var menu = ctrl._ensure_player_context_menu()
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	menu.clear()
	menu.set_meta("target_player_id", pid)
	menu.set_meta("target_display_name", dname)
	menu.add_item(dname, PCM.Action.HEADER)
	menu.set_item_disabled(0, true)
	menu.add_separator()
	var follow_id = ""
	if ctrl.is_following() and ctrl.get_follow_id() == pid:
		follow_id = pid
	for d in PCM.item_defs(follow_id):
		menu.add_item(str(d.get("text", "")), int(d.get("id", 0)))
	menu.position = Vector2i(int(screen_pos.x), int(screen_pos.y))
	menu.reset_size()
	menu.popup()

static func _on_player_context_id(ctrl, id: int) -> void:
	## Fallback handler when HUD does not own the menu.
	if ctrl.hud != null and ctrl.hud.has_method("_on_player_context_id"):
		ctrl.hud._on_player_context_id(id)
		return
	var PCM = preload("res://scripts/ui/player_context_menu.gd")
	var dname = ""
	var pid = ""
	if ctrl._player_ctx_menu != null:
		dname = str(ctrl._player_ctx_menu.get_meta("target_display_name", ""))
		pid = str(ctrl._player_ctx_menu.get_meta("target_player_id", ""))
	match id:
		PCM.Action.VIEW:
			if ctrl.hud != null and ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system("玩家【%s】（%s）" % [dname, pid])
		PCM.Action.INVITE:
			ctrl.request_party_invite(dname)
		PCM.Action.TRADE:
			ctrl.request_trade_open(dname)
		PCM.Action.DUEL:
			var duel_key = dname if not dname.is_empty() else pid
			ctrl.request_duel_challenge(duel_key)
		PCM.Action.WHISPER:
			if ctrl.hud != null and ctrl.hud.has_method("prefill_whisper"):
				ctrl.hud.prefill_whisper(dname)
			elif ctrl.hud != null and ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system("密语：在聊天框输入 /w %s 内容" % dname)
		PCM.Action.ADD_FRIEND:
			var add_key = dname if not dname.is_empty() else pid
			ctrl.request_friend_add(add_key)
		PCM.Action.INVITE_GUILD:
			var gkey = dname if not dname.is_empty() else pid
			ctrl.request_guild_invite(gkey)
		PCM.Action.FOLLOW:
			var fid = pid if not pid.is_empty() else dname
			if fid.is_empty():
				if ctrl.hud != null and ctrl.hud.has_method("append_system"):
					ctrl.hud.append_system("无法跟随。")
			elif ctrl.is_following() and ctrl._follow_id == fid:
				ctrl.stop_follow()
			else:
				ctrl.start_follow(fid)

