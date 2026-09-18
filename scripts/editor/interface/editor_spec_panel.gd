extends RefCounted
## 规格面板（meta/settings/shadow/region/far/water/光效）的构建器（接口层）。
## 纯搭建逻辑；状态字段写入 ctrl，信号回调连回 ctrl 上的处理方法/辅助函数。

const MapExt = preload("res://scripts/map/map_ext.gd")

static func build_spec_panel(ctrl, parent: Node) -> void:
	ctrl._spec_box = VBoxContainer.new()
	ctrl._spec_box.add_theme_constant_override("separation", 4)
	parent.add_child(ctrl._spec_box)
	ctrl._spec_hint = Label.new()
	ctrl._spec_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl._spec_box.add_child(ctrl._spec_hint)
	ctrl._meta_box = HBoxContainer.new()
	ctrl._meta_box.add_theme_constant_override("separation", 4)
	ctrl._spec_box.add_child(ctrl._meta_box)
	spec_bit_btn(ctrl, ctrl._meta_box, "室内", MapExt.META_INDOOR)
	spec_bit_btn(ctrl, ctrl._meta_box, "水面", MapExt.META_WATER)
	spec_bit_btn(ctrl, ctrl._meta_box, "禁冲刺", MapExt.META_NO_DASH)
	spec_bit_btn(ctrl, ctrl._meta_box, "强制阻挡", MapExt.META_FORCE_BLOCK)
	spec_bit_btn(ctrl, ctrl._meta_box, "强制通行", MapExt.META_FORCE_PASS)
	ctrl._shadow_box = HBoxContainer.new()
	ctrl._shadow_box.add_theme_constant_override("separation", 4)
	ctrl._spec_box.add_child(ctrl._shadow_box)
	spec_shadow_btn(ctrl, ctrl._shadow_box, "↖", 1)
	spec_shadow_btn(ctrl, ctrl._shadow_box, "↗", 2)
	spec_shadow_btn(ctrl, ctrl._shadow_box, "↙", 4)
	spec_shadow_btn(ctrl, ctrl._shadow_box, "↘", 8)
	var rrow := HBoxContainer.new()
	rrow.name = "RegionRow"
	ctrl._spec_box.add_child(rrow)
	ctrl._add_lbl(rrow, "区域号")
	ctrl._region_spin = SpinBox.new()
	ctrl._region_spin.min_value = 0
	ctrl._region_spin.max_value = 255
	ctrl._region_spin.value = 1
	rrow.add_child(ctrl._region_spin)
	var srow := VBoxContainer.new()
	srow.name = "SettingsRow"
	ctrl._spec_box.add_child(srow)
	var lr := HBoxContainer.new()
	srow.add_child(lr)
	ctrl._add_lbl(lr, "光照")
	ctrl._light_opt = OptionButton.new()
	ctrl._light_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._fill_preset_opt(ctrl._light_opt, "res://data/map/light_presets.json", ["日间", "黄昏", "夜晚"])
	lr.add_child(ctrl._light_opt)
	var sr := HBoxContainer.new()
	srow.add_child(sr)
	ctrl._add_lbl(sr, "环境音")
	ctrl._sound_opt = OptionButton.new()
	ctrl._sound_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl._fill_preset_opt(ctrl._sound_opt, "res://data/map/sound_presets.json", ["无"])
	sr.add_child(ctrl._sound_opt)
	var fr := HBoxContainer.new()
	srow.add_child(fr)
	ctrl._add_lbl(fr, "脚步")
	ctrl._foot_opt = OptionButton.new()
	ctrl._foot_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in [["草地", 0], ["石板", 1], ["浅水", 2], ["木板", 3]]:
		ctrl._foot_opt.add_item(str(pair[0]), int(pair[1]))
	fr.add_child(ctrl._foot_opt)
	var frow := HBoxContainer.new()
	frow.name = "FarRow"
	ctrl._spec_box.add_child(frow)
	ctrl._add_lbl(frow, "远景滚动")
	ctrl._far_sx = SpinBox.new()
	ctrl._far_sx.min_value = -8
	ctrl._far_sx.max_value = 8
	ctrl._far_sx.step = 0.05
	ctrl._far_sx.allow_greater = true
	ctrl._far_sx.allow_lesser = true
	ctrl._far_sx.value_changed.connect(func(v): ctrl._set_far_scroll(v, ctrl._far_sy.value if ctrl._far_sy else 0.0))
	frow.add_child(ctrl._far_sx)
	ctrl._far_sy = SpinBox.new()
	ctrl._far_sy.min_value = -8
	ctrl._far_sy.max_value = 8
	ctrl._far_sy.step = 0.05
	ctrl._far_sy.allow_greater = true
	ctrl._far_sy.allow_lesser = true
	ctrl._far_sy.value_changed.connect(func(v): ctrl._set_far_scroll(ctrl._far_sx.value if ctrl._far_sx else 0.0, v))
	frow.add_child(ctrl._far_sy)
	var fxrow := HBoxContainer.new()
	fxrow.name = "LightFxRow"
	ctrl._spec_box.add_child(fxrow)
	ctrl._add_lbl(fxrow, "光效颜色")
	ctrl._fx_color = ColorPickerButton.new()
	ctrl._fx_color.custom_minimum_size = Vector2(48, 24)
	ctrl._fx_color.edit_alpha = true
	ctrl._fx_color.color = Color(1, 1, 1, 1)
	ctrl._fx_color.color_changed.connect(ctrl._on_fx_color_changed)
	fxrow.add_child(ctrl._fx_color)
	ctrl._water_thru = CheckBox.new()
	ctrl._water_thru.text = "水面可走"
	ctrl._water_thru.toggled.connect(func(on):
		if ctrl.doc:
			ctrl.doc.water_through = on
			ctrl.doc.dirty = true
	)
	ctrl._spec_box.add_child(ctrl._water_thru)
	ctrl._spec_box.visible = false


static func spec_bit_btn(ctrl, parent: Node, text: String, bit: int) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("bit", bit)
	b.pressed.connect(func():
		ctrl._spec_meta_bit = bit
		for c in ctrl._meta_box.get_children():
			if c is Button:
				c.set_pressed_no_signal(int(c.get_meta("bit", 0)) == bit)
	)
	parent.add_child(b)
	if bit == MapExt.META_INDOOR:
		b.set_pressed_no_signal(true)
		ctrl._spec_meta_bit = bit


static func spec_shadow_btn(ctrl, parent: Node, text: String, bit: int) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("bit", bit)
	b.set_pressed_no_signal(true)
	b.pressed.connect(ctrl._sync_shadow_brush)
	parent.add_child(b)
