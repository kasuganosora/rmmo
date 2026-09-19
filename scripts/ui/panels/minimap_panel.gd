extends RefCounted
## UI panel: minimap, radar blips, pins, zoom.

const HudDrag = preload("res://scripts/ui/hud_draggable.gd")
const RadarView = preload("res://scripts/ui/radar_view.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const RADAR_BLIPS_INTERVAL_MS: int = 100
const RADAR_ENABLED := true

static func set_minimap_hint(ctrl, text: String) -> void:
	ctrl.minimap_label.text = text



static func _sync_radar(ctrl, force_hint: bool = false) -> void:
	if not RADAR_ENABLED:
		return
	if ctrl._radar == null or ctrl._radar_player == null:
		return
	var center: Vector2 = ctrl._radar_player.global_position
	var yaw: float = PI * 0.5
	if ctrl._radar_player.has_method("facing_angle"):
		yaw = float(ctrl._radar_player.facing_angle())
	if ctrl._radar.has_method("update_view"):
		ctrl._radar.update_view(center, yaw)
	ctrl._update_target_angle()
	var cell = Vector2i.ZERO
	if "cell" in ctrl._radar_player:
		cell = ctrl._radar_player.cell
	elif ctrl._radar_map_field != null and ctrl._radar_map_field.has_method("world_to_cell"):
		cell = ctrl._radar_map_field.world_to_cell(center)
	# Blips: throttle (wander NPCs); hint / map-window text only when cell changes.
	var now_ms: int = Time.get_ticks_msec()
	if force_hint or now_ms - ctrl._radar_blips_msec >= RADAR_BLIPS_INTERVAL_MS:
		ctrl._radar_blips_msec = now_ms
		ctrl._sync_radar_blips()
	if force_hint or cell != ctrl._radar_hint_cell:
		ctrl._radar_hint_cell = cell
		if ctrl.minimap_label != null and ctrl._radar.has_method("hint_text"):
			ctrl.minimap_label.text = str(ctrl._radar.hint_text())
		ctrl._refresh_map_window_info()



static func _sync_radar_blips(ctrl) -> void:
	if ctrl._radar == null or not ctrl._radar.has_method("set_entity_blips"):
		return
	var blips: Array = []
	if typeof(ctrl._radar_blip_source) == TYPE_CALLABLE:
		var result: Variant = ctrl._radar_blip_source.call()
		if typeof(result) == TYPE_ARRAY:
			blips = result
	elif ctrl._radar_blip_source is Node and is_instance_valid(ctrl._radar_blip_source):
		if ctrl._radar_blip_source.has_method("get_radar_blips"):
			var result2: Variant = ctrl._radar_blip_source.get_radar_blips()
			if typeof(result2) == TYPE_ARRAY:
				blips = result2
	ctrl._radar.set_entity_blips(blips)
	ctrl._sync_map_poi_markers()



static func _setup_radar(ctrl) -> void:
	if not RADAR_ENABLED:
		var panel = ctrl.get_node_or_null("MinimapPanel")
		if panel:
			panel.visible = false
		ctrl.set_process(false)
		return
	for c in ctrl.minimap_view_host.get_children():
		c.queue_free()
	ctrl.minimap_view_host.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl._radar = Control.new()
	ctrl._radar.set_script(RadarView)
	ctrl._radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl._radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ctrl._radar.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.minimap_view_host.add_child(ctrl._radar)
	ctrl._setup_radar_zoom_buttons()
	ctrl._apply_radar_view_radius_from_settings()
	ctrl._connect_radar_nav()



static func _connect_radar_nav(ctrl) -> void:
	if ctrl._radar == null or not is_instance_valid(ctrl._radar):
		return
	if ctrl._radar.has_signal("cell_clicked") and not ctrl._radar.cell_clicked.is_connected(ctrl._on_map_nav_cell):
		ctrl._radar.cell_clicked.connect(ctrl._on_map_nav_cell)
	if ctrl._radar.has_signal("cell_pinned") and not ctrl._radar.cell_pinned.is_connected(ctrl._on_map_pin_cell):
		ctrl._radar.cell_pinned.connect(ctrl._on_map_pin_cell)



static func _setup_radar_zoom_buttons(ctrl) -> void:
	if ctrl.minimap_view_host == null:
		return
	var row = HBoxContainer.new()
	row.name = "RadarZoomBtns"
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_constant_override("separation", 2)
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = -44
	row.offset_top = -22
	row.offset_right = -2
	row.offset_bottom = -2
	var mk = func(label: String, dir: int) -> void:
		var b = Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(20, 18)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.tooltip_text = "缩小" if dir > 0 else "放大"
		b.pressed.connect(func():
			var gs = GameSettingsScript.get_i()
			if gs != null and gs.has_method("cycle_radar_view_radius"):
				gs.cycle_radar_view_radius(dir)
		)
		row.add_child(b)
	# "-" = zoom out (larger radius); "+" = zoom in (smaller radius)
	mk.call("-", 1)
	mk.call("+", -1)
	ctrl.minimap_view_host.add_child(row)



static func _apply_radar_view_radius_from_settings(ctrl) -> void:
	if ctrl._radar == null or not is_instance_valid(ctrl._radar):
		return
	var gs = GameSettingsScript.get_i()
	if gs == null:
		return
	var r: float = 11.0
	if "radar_view_radius" in gs:
		r = float(gs.radar_view_radius)
	if ctrl._radar.has_method("set_view_radius"):
		ctrl._radar.set_view_radius(r)
	elif "view_radius_tiles" in ctrl._radar:
		ctrl._radar.view_radius_tiles = r



static func set_map_pin(ctrl, cell: Vector2i) -> void:
	ctrl._map_pin_cell = cell
	if ctrl._radar != null and is_instance_valid(ctrl._radar) and ctrl._radar.has_method("set_pin_cell"):
		ctrl._radar.set_pin_cell(cell)
	if ctrl._map_overview != null and is_instance_valid(ctrl._map_overview) and ctrl._map_overview.has_method("set_pin_cell"):
		ctrl._map_overview.set_pin_cell(cell)



static func apply_map_pins_update(ctrl, action: Dictionary) -> void:
	var snap_v: Variant = action.get("map_pins", action)
	var pins: Array = []
	if typeof(snap_v) == TYPE_DICTIONARY:
		var pv: Variant = snap_v.get("pins", [])
		if typeof(pv) == TYPE_ARRAY:
			pins = pv
	elif typeof(snap_v) == TYPE_ARRAY:
		pins = snap_v
	ctrl._map_pins = pins.duplicate(true)
	# Personal pins render via RadarPoi kind=pin; keep legacy cyan overlay off.
	ctrl._map_pin_cell = Vector2i(-9999, -9999)
	ctrl.set_map_pin(ctrl._map_pin_cell)
	ctrl._sync_map_poi_markers()



static func _on_map_pin_cell(ctrl, cell: Vector2i) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("toggle_map_pin"):
		ctrl._world_combat.toggle_map_pin(cell)
	else:
		if ctrl._map_pin_cell == cell:
			ctrl.set_map_pin(Vector2i(-9999, -9999))
		else:
			ctrl.set_map_pin(cell)



static func _on_clear_map_pins(ctrl) -> void:
	if ctrl._world_combat != null and ctrl._world_combat.has_method("clear_map_pins"):
		ctrl._world_combat.clear_map_pins()
	else:
		ctrl._map_pins.clear()
		ctrl.set_map_pin(Vector2i(-9999, -9999))
		ctrl.append_system("已清除全部标记")



static func _sync_map_overview_layout(ctrl, panel: PanelContainer, mount: Control, host: Control) -> void:
	if panel == null or mount == null or host == null:
		return
	if not is_instance_valid(panel) or not is_instance_valid(mount) or not is_instance_valid(host):
		return
	# Never raise custom_minimum_size to current avail — that locks grow-only resize.
	host.custom_minimum_size = Vector2.ZERO
	host.clip_contents = true
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if ctrl._map_overview != null and is_instance_valid(ctrl._map_overview):
		ctrl._map_overview.custom_minimum_size = Vector2.ZERO
		ctrl._map_overview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ctrl._map_overview.queue_redraw()
	# Keep panel floor at intended base min (HudDrag.min_size), not enlarged content.
	const MAP_MIN := Vector2(300, 280)
	if panel.min_size != MAP_MIN:
		panel.min_size = MAP_MIN
	if panel.custom_minimum_size != MAP_MIN:
		panel.custom_minimum_size = MAP_MIN



static func _make_radar_zoom_option(ctrl, gs: Node) -> OptionButton:
	var opt = OptionButton.new()
	L2Style.style_option(opt)
	var radii: Array = GameSettingsScript.RADAR_VIEW_RADII
	var cur: int = 11
	if gs != null and "radar_view_radius" in gs:
		cur = int(gs.radar_view_radius)
	var sel = 1
	for i in range(radii.size()):
		var r: int = int(radii[i])
		var label = "%d 格" % r
		match r:
			8:
				label = "近 (8)"
			11:
				label = "默认 (11)"
			16:
				label = "中 (16)"
			22:
				label = "远 (22)"
		opt.add_item(label, i)
		opt.set_item_metadata(i, r)
		if r == cur:
			sel = i
	opt.select(sel)
	opt.item_selected.connect(func(idx: int):
		if gs != null and gs.has_method("set_radar_view_radius"):
			gs.set_radar_view_radius(int(opt.get_item_metadata(idx)))
	)
	return opt


