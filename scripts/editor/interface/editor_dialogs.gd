extends RefCounted
## 编辑器各窗口/对话框的构建器（接口层）。纯搭建逻辑；状态字段写入 ctrl，
## 信号回调连回 ctrl 上的处理方法。各处理方法（_on_assets_changed 等）保留在组合根。

const ResourceManager = preload("res://scripts/editor/infrastructure/resource_manager.gd")
const EntityInspector = preload("res://scripts/editor/interface/entity_inspector.gd")
const TilesetManager = preload("res://scripts/editor/interface/tileset_manager.gd")
const MapDocument = preload("res://scripts/editor/domain/map_document.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")

static func build_asset_window(ctrl) -> void:
	var rm = ResourceManager.new()
	rm.visible = false
	ctrl._asset_win = rm
	rm.assets_changed.connect(ctrl._on_assets_changed)
	rm.tileset_slot_assigned.connect(ctrl._on_rm_slot)
	ctrl.add_child(rm)

static func build_entity_window(ctrl) -> void:
	ctrl._entity_win = Window.new()
	ctrl._entity_win.title = "实体编辑"
	ctrl._entity_win.size = Vector2i(460, 680)
	ctrl._entity_win.visible = false
	ctrl._entity_win.close_requested.connect(func(): ctrl._entity_win.hide())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	ctrl._entity_win.add_child(margin)
	ctrl._inspector = EntityInspector.new()
	ctrl._inspector.changed.connect(ctrl._on_entity_changed)
	if ctrl._inspector.has_signal("jump_requested"):
		ctrl._inspector.jump_requested.connect(ctrl._on_entity_jump)
	margin.add_child(ctrl._inspector)
	ctrl.add_child(ctrl._entity_win)

static func build_tileset_window(ctrl) -> void:
	var tm = TilesetManager.new()
	tm.visible = false
	ctrl._tileset_win = tm
	tm.catalog_changed.connect(ctrl._on_tileset_catalog)
	tm.apply_requested.connect(ctrl._on_tileset_apply)
	ctrl.add_child(tm)

static func build_map_settings_dialog(ctrl) -> void:
	ctrl._set_dlg = ConfirmationDialog.new()
	ctrl._set_dlg.title = "地图设置"
	ctrl._set_dlg.min_size = Vector2i(380, 360)
	ctrl._set_dlg.ok_button_text = "确定"
	ctrl._set_dlg.cancel_button_text = "取消"
	ctrl._set_dlg.confirmed.connect(ctrl._apply_map_settings)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	ctrl._set_dlg.add_child(v)
	ctrl._add_lbl(v, "显示名")
	ctrl._set_name = LineEdit.new()
	v.add_child(ctrl._set_name)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	v.add_child(size_row)
	ctrl._add_lbl(size_row, "宽")
	ctrl._set_w = SpinBox.new()
	ctrl._set_w.min_value = 1
	ctrl._set_w.max_value = mini(MapDocument.MAX_SIDE, 10000)
	ctrl._set_w.value = 25
	size_row.add_child(ctrl._set_w)
	ctrl._add_lbl(size_row, "高")
	ctrl._set_h = SpinBox.new()
	ctrl._set_h.min_value = 1
	ctrl._set_h.max_value = mini(MapDocument.MAX_SIDE, 10000)
	ctrl._set_h.value = 20
	size_row.add_child(ctrl._set_h)
	ctrl._add_lbl(v, "图块套")
	ctrl._set_ts = OptionButton.new()
	v.add_child(ctrl._set_ts)
	ctrl._set_start = CheckBox.new()
	ctrl._set_start.text = "设为起始地图"
	v.add_child(ctrl._set_start)
	var far_row := HBoxContainer.new()
	v.add_child(far_row)
	ctrl._add_lbl(far_row, "远景滚动")
	ctrl._set_far_sx = SpinBox.new()
	ctrl._set_far_sx.min_value = -8
	ctrl._set_far_sx.max_value = 8
	ctrl._set_far_sx.step = 0.05
	ctrl._set_far_sx.allow_greater = true
	ctrl._set_far_sx.allow_lesser = true
	far_row.add_child(ctrl._set_far_sx)
	ctrl._set_far_sy = SpinBox.new()
	ctrl._set_far_sy.min_value = -8
	ctrl._set_far_sy.max_value = 8
	ctrl._set_far_sy.step = 0.05
	ctrl._set_far_sy.allow_greater = true
	ctrl._set_far_sy.allow_lesser = true
	far_row.add_child(ctrl._set_far_sy)
	ctrl._set_water = CheckBox.new()
	ctrl._set_water.text = "水面可走"
	v.add_child(ctrl._set_water)
	var env_row := HBoxContainer.new()
	v.add_child(env_row)
	ctrl._add_lbl(env_row, "环境")
	ctrl._set_env = OptionButton.new()
	ctrl._set_env.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._set_env.add_item("室外", 0)
	ctrl._set_env.set_item_metadata(0, MapExt.ENV_OUTDOOR)
	ctrl._set_env.add_item("室内", 1)
	ctrl._set_env.set_item_metadata(1, MapExt.ENV_INDOOR)
	ctrl._set_env.tooltip_text = "整张地图室内/室外，供天气系统使用（与格子「室内」标记不同）"
	env_row.add_child(ctrl._set_env)
	var bgm_row := HBoxContainer.new()
	v.add_child(bgm_row)
	ctrl._add_lbl(bgm_row, "BGM")
	ctrl._set_bgm = OptionButton.new()
	ctrl._set_bgm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bgm_row.add_child(ctrl._set_bgm)
	var light_row := HBoxContainer.new()
	v.add_child(light_row)
	ctrl._add_lbl(light_row, "光照")
	ctrl._set_light = OptionButton.new()
	ctrl._set_light.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._fill_preset_opt(ctrl._set_light, "map/light_presets.json", ["日间", "黄昏", "夜晚"])
	light_row.add_child(ctrl._set_light)
	var fx_row := HBoxContainer.new()
	v.add_child(fx_row)
	ctrl._add_lbl(fx_row, "光效颜色")
	ctrl._set_fx_color = ColorPickerButton.new()
	ctrl._set_fx_color.custom_minimum_size = Vector2(48, 24)
	ctrl._set_fx_color.edit_alpha = true
	ctrl._set_fx_color.color = Color(1, 1, 1, 1)
	fx_row.add_child(ctrl._set_fx_color)
	ctrl.add_child(ctrl._set_dlg)
