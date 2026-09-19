extends RefCounted
## UI panel: death / respawn dialog.

const L2Style = preload("res://scripts/ui/l2_style.gd")

static func show_death_dialog(ctrl) -> void:
	ctrl._build_death_dialog()
	if ctrl._death_panel:
		ctrl._death_panel.visible = true
		ctrl._death_panel.move_to_front()
		ctrl.call_deferred("_place_death_dialog")



static func hide_death_dialog(ctrl) -> void:
	if ctrl._death_panel:
		ctrl._death_panel.visible = false



static func _build_death_dialog(ctrl) -> void:
	if ctrl._death_panel != null and is_instance_valid(ctrl._death_panel):
		return
	ctrl._death_panel = PanelContainer.new()
	ctrl._death_panel.name = "DeathDialog"
	ctrl._death_panel.visible = false
	ctrl._death_panel.custom_minimum_size = Vector2(320, 180)
	L2Style.apply_panel(ctrl._death_panel)
	var marg = MarginContainer.new()
	marg.add_theme_constant_override("margin_left", 18)
	marg.add_theme_constant_override("margin_top", 16)
	marg.add_theme_constant_override("margin_right", 18)
	marg.add_theme_constant_override("margin_bottom", 18)
	ctrl._death_panel.add_child(marg)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	marg.add_child(col)
	var title = Label.new()
	title.text = "你死了"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	L2Style.style_title(title)
	col.add_child(title)
	var body = Label.new()
	body.text = "就地复活：半血\n回城复活：安全点满血"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", L2Style.COL_TEXT)
	col.add_child(body)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var here_btn = Button.new()
	here_btn.name = "HereBtn"
	here_btn.text = "就地复活"
	here_btn.focus_mode = Control.FOCUS_NONE
	here_btn.custom_minimum_size = Vector2(110, 28)
	L2Style.style_action_button(here_btn)
	here_btn.pressed.connect(func():
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_respawn"):
			ctrl._world_combat.request_respawn("here")
		ctrl.hide_death_dialog()
	)
	row.add_child(here_btn)
	var town_btn = Button.new()
	town_btn.name = "TownBtn"
	town_btn.text = "回城复活"
	town_btn.focus_mode = Control.FOCUS_NONE
	town_btn.custom_minimum_size = Vector2(110, 28)
	L2Style.style_action_button(town_btn)
	town_btn.pressed.connect(func():
		if ctrl._world_combat != null and ctrl._world_combat.has_method("request_respawn"):
			ctrl._world_combat.request_respawn("town")
		ctrl.hide_death_dialog()
	)
	row.add_child(town_btn)
	ctrl.add_child(ctrl._death_panel)
	ctrl.call_deferred("_place_death_dialog")



static func _place_death_dialog(ctrl) -> void:
	if ctrl._death_panel == null or not is_instance_valid(ctrl._death_panel):
		return
	var vp = ctrl.get_viewport().get_visible_rect().size
	ctrl._death_panel.size = Vector2(320, 190)
	ctrl._death_panel.global_position = Vector2((vp.x - 320.0) * 0.5, (vp.y - 190.0) * 0.4)


