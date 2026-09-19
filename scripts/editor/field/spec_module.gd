extends RefCounted
## Domain module: spec panel (sync, read, write, eyedrop).

var ctrl
func _init(c):
	ctrl = c

const MapExt = preload("res://scripts/map/map_ext.gd")

func _sync_spec_panel(spec: String, layer_name: String) -> void:
	ctrl._spec_kind = spec
	if ctrl.map_field:
		var overlay = spec if spec in ["meta", "settings", "shadow", "region"] else ""
		ctrl.map_field.edit_spec_kind = overlay
	var hide_pal = spec in ["meta", "settings", "shadow", "region"]
	if ctrl._palette:
		ctrl._palette.visible = not hide_pal
	if ctrl._spec_box == null:
		return
	var show = spec != ""
	ctrl._spec_box.visible = show
	if ctrl._meta_box:
		ctrl._meta_box.visible = spec == "meta"
	if ctrl._shadow_box:
		ctrl._shadow_box.visible = spec == "shadow"
	var region_row = ctrl._spec_box.get_node_or_null("RegionRow")
	if region_row:
		region_row.visible = spec == "region"
	var set_row = ctrl._spec_box.get_node_or_null("SettingsRow")
	if set_row:
		set_row.visible = spec == "settings"
	var far_row = ctrl._spec_box.get_node_or_null("FarRow")
	if far_row:
		far_row.visible = spec == "far"
	if ctrl._water_thru:
		ctrl._water_thru.visible = spec == "water"
	var fx_row = ctrl._spec_box.get_node_or_null("LightFxRow")
	if fx_row:
		fx_row.visible = spec == "light"
	if ctrl._spec_hint:
		match spec:
			"meta":
				ctrl._spec_hint.text = "格子标记：室内藏屋顶；强制阻挡/通行覆盖图块通行。"
			"settings":
				ctrl._spec_hint.text = "氛围：按格写入光照、环境音、脚步（走到该格时生效）。"
			"shadow":
				ctrl._spec_hint.text = "阴影：勾选四角后在地图上画（不是图块）。"
			"region":
				ctrl._spec_hint.text = "区域号：给格子编号，便于事件/脚本区分。"
			"far":
				ctrl._spec_hint.text = "远景：用图块板绘制。滚动 0 跟地图，>0 随镜头视差。"
			"water":
				ctrl._spec_hint.text = "水面：有图即挡路；勾选「水面可走」则整层不挡。"
			"roof":
				ctrl._spec_hint.text = "屋顶：室内标记格子上会自动隐藏。"
			"light":
				ctrl._spec_hint.text = "光效：叠在角色上方的加色层。颜色可自定，与地图光照无关。"
			_:
				ctrl._spec_hint.text = layer_name
	if spec == "far" and ctrl.doc and ctrl._far_sx and ctrl._far_sy:
		ctrl._far_sx.set_value_no_signal(ctrl.doc.far_scroll.x)
		ctrl._far_sy.set_value_no_signal(ctrl.doc.far_scroll.y)
	if spec == "water" and ctrl.doc and ctrl._water_thru:
		ctrl._water_thru.set_pressed_no_signal(ctrl.doc.water_through)
	if spec == "light":
		ctrl._sync_fx_color_controls()



func _spec_read(cell: Vector2i) -> int:
	if ctrl.doc == null:
		return 0
	match ctrl._spec_kind:
		"meta":
			return int(ctrl.doc.ext_tile("meta", cell.x, cell.y))
		"settings":
			return int(ctrl.doc.ext_tile("settings", cell.x, cell.y))
		"shadow":
			return int(ctrl.doc.tile(cell.x, cell.y, 4)) & 0x0f
		"region":
			return int(ctrl.doc.tile(cell.x, cell.y, 5))
		_:
			return 0



func _spec_write(cell: Vector2i, erase: bool) -> void:
	if ctrl.doc == null:
		return
	var cur = _spec_read(cell)
	var nxt = 0
	if ctrl._spec_kind == "meta":
		if erase:
			nxt = cur & ~ctrl._spec_meta_bit
		else:
			nxt = cur | ctrl._spec_meta_bit
			if ctrl._spec_meta_bit == MapExt.META_FORCE_BLOCK:
				nxt &= ~MapExt.META_FORCE_PASS
			elif ctrl._spec_meta_bit == MapExt.META_FORCE_PASS:
				nxt &= ~MapExt.META_FORCE_BLOCK
		if nxt != cur:
			ctrl.doc.set_ext_tile("meta", cell.x, cell.y, nxt)
	elif ctrl._spec_kind == "settings":
		nxt = 0 if erase else ctrl._spec_brush_value()
		if nxt != cur:
			ctrl.doc.set_ext_tile("settings", cell.x, cell.y, nxt)
	elif ctrl._spec_kind == "shadow":
		nxt = 0 if erase else (ctrl._spec_shadow & 0x0f)
		if nxt != cur:
			ctrl.doc.set_tile(cell.x, cell.y, 4, nxt)
	elif ctrl._spec_kind == "region":
		nxt = 0 if erase else ctrl._spec_brush_value()
		if nxt != cur:
			ctrl.doc.set_tile(cell.x, cell.y, 5, nxt)



func _spec_eyedrop(cell: Vector2i) -> void:
	var v = _spec_read(cell)
	match ctrl._spec_kind:
		"meta":
			if v != 0:
				if (v & MapExt.META_INDOOR) != 0:
					ctrl._spec_meta_bit = MapExt.META_INDOOR
				elif (v & MapExt.META_WATER) != 0:
					ctrl._spec_meta_bit = MapExt.META_WATER
				elif (v & MapExt.META_NO_DASH) != 0:
					ctrl._spec_meta_bit = MapExt.META_NO_DASH
				if ctrl._meta_box:
					for c in ctrl._meta_box.get_children():
						if c is Button:
							c.set_pressed_no_signal(int(c.get_meta("bit", 0)) == ctrl._spec_meta_bit)
		"settings":
			var light = v & 0xff
			var sound = (v >> 8) & 0xff
			var foot = (v >> 16) & 0xff
			ctrl._select_opt_id(ctrl._light_opt, light)
			ctrl._select_opt_id(ctrl._sound_opt, sound)
			ctrl._select_opt_id(ctrl._foot_opt, foot)
		"shadow":
			ctrl._spec_shadow = v & 0x0f
			if ctrl._shadow_box:
				for c in ctrl._shadow_box.get_children():
					if c is Button:
						c.set_pressed_no_signal(((ctrl._spec_shadow & int(c.get_meta("bit", 0))) != 0))
		"region":
			if ctrl._region_spin:
				ctrl._region_spin.value = v
	ctrl._status.text = "取样 %s = %d" % [ctrl._spec_kind, v]


