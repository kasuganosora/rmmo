extends RefCounted
## 编辑器光/天气/光效预览（接口层）。纯逻辑，通过 ctrl 读写 editor_modulate / 各预览控件。
## 组内函数互相直接调用；被外置构建器调用的入口也保留在组合根作为委托。

const MapExt = preload("res://scripts/map/map_ext.gd")

static func fill_preset_opt(ctrl, opt: OptionButton, path: String, fallback: PackedStringArray) -> void:
	opt.clear()
	var names: Dictionary = {}
	if FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) == TYPE_DICTIONARY:
			var presets: Variant = (raw as Dictionary).get("presets", raw)
			if typeof(presets) == TYPE_DICTIONARY:
				for k in (presets as Dictionary).keys():
					var id := int(str(k))
					var def: Variant = (presets as Dictionary)[k]
					var label := str(k)
					if typeof(def) == TYPE_DICTIONARY:
						var n := str(def.get("name", ""))
						if n != "":
							label = n
					names[id] = label
	if names.is_empty():
		for i in range(fallback.size()):
			opt.add_item(str(fallback[i]), i)
		return
	var ids: Array = names.keys()
	ids.sort()
	for id in ids:
		opt.add_item("%s · %s" % [str(id), str(names[id])], int(id))

static func fill_bgm_opt(ctrl, current: String) -> void:
	if ctrl._set_bgm == null:
		return
	ctrl._set_bgm.clear()
	ctrl._set_bgm.add_item("（无）")
	ctrl._set_bgm.set_item_metadata(0, "")
	var pick := 0
	if ctrl.pack != null and ctrl.pack.has_method("list_assets"):
		for it in ctrl.pack.list_assets("audio/bgm"):
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var aid := str(it.get("id", ""))
			ctrl._set_bgm.add_item(aid)
			ctrl._set_bgm.set_item_metadata(ctrl._set_bgm.item_count - 1, aid)
			if aid == current:
				pick = ctrl._set_bgm.item_count - 1
	if current != "" and pick == 0:
		ctrl._set_bgm.add_item(current)
		ctrl._set_bgm.set_item_metadata(ctrl._set_bgm.item_count - 1, current)
		pick = ctrl._set_bgm.item_count - 1
	ctrl._set_bgm.select(pick)

static func set_far_scroll(ctrl, x: float, y: float) -> void:
	if ctrl.doc == null:
		return
	ctrl.doc.far_scroll = Vector2(x, y)
	ctrl.doc.dirty = true

static func on_toolbar_light(ctrl) -> void:
	if ctrl._light_syncing or ctrl.doc == null or ctrl._light_bar == null:
		return
	ctrl.doc.light_preset = int(ctrl._light_bar.get_item_id(ctrl._light_bar.selected)) if ctrl._light_bar.item_count > 0 else 0
	ctrl.doc.dirty = true
	if ctrl.pack:
		ctrl.pack.dirty = true
	apply_editor_light(ctrl)
	if ctrl._set_light:
		ctrl._light_syncing = true
		select_opt_id(ctrl, ctrl._set_light, int(ctrl.doc.light_preset))
		ctrl._light_syncing = false
	if ctrl._status:
		ctrl._status.text = "地图光照：%s（未写入磁盘，Ctrl+S 保存）" % ctrl._light_bar.get_item_text(ctrl._light_bar.selected)

static func sync_light_controls(ctrl) -> void:
	if ctrl.doc == null:
		return
	ctrl._light_syncing = true
	var id := int(ctrl.doc.light_preset) if "light_preset" in ctrl.doc else 0
	select_opt_id(ctrl, ctrl._light_bar, id)
	select_opt_id(ctrl, ctrl._set_light, id)
	ctrl._light_syncing = false

static func apply_editor_light(ctrl) -> void:
	apply_editor_atmosphere(ctrl)

static func on_toolbar_weather(ctrl) -> void:
	if ctrl._weather_bar == null:
		return
	var idx: int = ctrl._weather_bar.selected
	ctrl._preview_weather = "clear"
	if idx >= 0:
		ctrl._preview_weather = str(ctrl._weather_bar.get_item_metadata(idx))
	apply_editor_atmosphere(ctrl)
	if ctrl.map_field and ctrl.map_field.has_method("map_is_indoor") and ctrl.map_field.map_is_indoor() and ctrl._preview_weather != "clear":
		ctrl._status.text = "室内地图不出天气（昼夜光仍在）"
	elif ctrl._status:
		ctrl._status.text = "预览天气：%s（不写入地图）" % ctrl._weather_bar.get_item_text(ctrl._weather_bar.selected)

static func apply_editor_atmosphere(ctrl) -> void:
	var id := 0
	if ctrl.doc != null and "light_preset" in ctrl.doc:
		id = int(ctrl.doc.light_preset)
	var inten: float = 0.0 if ctrl._preview_weather == "clear" else float(ctrl._preview_weather_i)
	if ctrl.map_field != null and ctrl.map_field.has_method("set_atmosphere"):
		var atm: Dictionary = ctrl.map_field.set_atmosphere(id, ctrl._preview_weather, inten)
		if ctrl._editor_modulate:
			ctrl._editor_modulate.color = atm.get("modulate", MapExt.light_modulate(id))
		return
	if ctrl._editor_modulate:
		ctrl._editor_modulate.color = MapExt.light_modulate(id)

static func on_fx_color_changed(ctrl, c: Color) -> void:
	if ctrl._fx_syncing or ctrl.doc == null:
		return
	ctrl.doc.light_fx_color = c
	ctrl.doc.dirty = true
	if ctrl.pack:
		ctrl.pack.dirty = true
	sync_fx_color_controls(ctrl)
	apply_editor_fx_color(ctrl)
	if ctrl._status:
		ctrl._status.text = "光效颜色已改（未写入磁盘，Ctrl+S 保存）"

static func sync_fx_color_controls(ctrl) -> void:
	if ctrl.doc == null:
		return
	var c: Color = ctrl.doc.light_fx_color if "light_fx_color" in ctrl.doc else Color(1, 1, 1, 1)
	ctrl._fx_syncing = true
	if ctrl._fx_color_bar:
		ctrl._fx_color_bar.color = c
	if ctrl._fx_color:
		ctrl._fx_color.color = c
	if ctrl._set_fx_color:
		ctrl._set_fx_color.color = c
	ctrl._fx_syncing = false

static func apply_editor_fx_color(ctrl) -> void:
	if ctrl.map_field != null and ctrl.map_field.has_method("apply_light_fx_color"):
		ctrl.map_field.apply_light_fx_color()

static func select_opt_id(ctrl, opt: OptionButton, id: int) -> void:
	if opt == null:
		return
	for i in range(opt.item_count):
		if opt.get_item_id(i) == id:
			opt.select(i)
			return
