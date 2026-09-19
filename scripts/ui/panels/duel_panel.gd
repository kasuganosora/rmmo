extends RefCounted
## UI panel: duel banner.

var ctrl
func _init(c):
	ctrl = c

const Net = preload("res://scripts/net/net.gd")

func _on_duel_challenge(target_id_or_name: String) -> void:
	target_id_or_name = str(target_id_or_name).strip_edges()
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_duel_challenge"):
		ctrl._world_combat.request_duel_challenge(target_id_or_name)
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_duel_challenge"):
		_apply_duel_result_locally(srv.try_duel_challenge(target_id_or_name))



func _on_duel_forfeit() -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("request_duel_forfeit"):
		ctrl._world_combat.request_duel_forfeit()
		return
	var srv = Net.server()
	if srv != null and srv.has_method("try_duel_forfeit"):
		_apply_duel_result_locally(srv.try_duel_forfeit())



func _apply_duel_result_locally(result: Dictionary) -> void:
	for a in result.get("actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var t = str(a.get("type", ""))
		match t:
			"duel_update":
				apply_duel_update(a)
			"system_message":
				ctrl.append_system(str(a.get("text", "")))



func _build_duel_banner() -> void:
	ctrl._duel_banner = PanelContainer.new()
	ctrl._duel_banner.name = "DuelBanner"
	ctrl._duel_banner.visible = false
	ctrl.add_child(ctrl._duel_banner)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 10)
	marg.add_theme_constant_override("margin_top", 6)
	marg.add_theme_constant_override("margin_right", 10)
	marg.add_theme_constant_override("margin_bottom", 6)
	ctrl._duel_banner.add_child(marg)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	marg.add_child(row)
	ctrl._duel_label = Label.new()
	ctrl._duel_label.name = "DuelLabel"
	ctrl._duel_label.text = "决斗"
	ctrl._duel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl._duel_label)
	var forfeit_btn = Button.new()
	forfeit_btn.name = "DuelForfeitBtn"
	forfeit_btn.text = "认输"
	forfeit_btn.focus_mode = Control.FOCUS_NONE
	forfeit_btn.pressed.connect(_on_duel_forfeit)
	row.add_child(forfeit_btn)
	if ctrl.has_method("_apply_l2_chrome"):
		ctrl._apply_l2_chrome(ctrl._duel_banner)
	ctrl._duel_banner.position = Vector2(12, 72)
	ctrl._duel_banner.z_index = 40



func apply_duel_update(action: Dictionary) -> void:
	var d: Variant = action.get("duel", action)
	if typeof(d) != TYPE_DICTIONARY:
		return
	ctrl._duel_state = (d as Dictionary).duplicate(true)
	_refresh_duel_banner()



func _refresh_duel_banner() -> void:
	if ctrl._duel_banner == null:
		return
	var active = bool(ctrl._duel_state.get("active", false))
	ctrl._duel_banner.visible = active
	if not active:
		return
	var oname = str(ctrl._duel_state.get("opponent_name", "对手"))
	var hp = int(ctrl._duel_state.get("opponent_hp", 0))
	var hp_max = int(ctrl._duel_state.get("opponent_hp_max", 0))
	var left = _duel_remaining_sec()
	if ctrl._duel_label != null:
		ctrl._duel_label.text = "决斗 vs 【%s】  HP %d/%d  剩余 %ds" % [oname, hp, hp_max, left]
	ctrl._duel_banner.reset_size()
	ctrl._duel_banner.move_to_front()




func _duel_remaining_sec() -> int:
	if not bool(ctrl._duel_state.get("active", false)):
		return 0
	var ends = float(ctrl._duel_state.get("ends_at", 0.0))
	var now = Time.get_ticks_msec() / 1000.0
	return maxi(0, int(ceil(ends - now)))



func _tick_duel_banner(delta: float) -> void:
	if not bool(ctrl._duel_state.get("active", false)):
		return
	ctrl._duel_banner_acc += delta
	if ctrl._duel_banner_acc < 0.25:
		return
	ctrl._duel_banner_acc = 0.0
	_refresh_duel_banner()


