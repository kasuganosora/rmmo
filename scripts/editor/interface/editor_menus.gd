extends RefCounted
## 编辑器菜单栏/工具栏构建器（接口层）。纯搭建逻辑，不持有状态；
## 状态字段写入传入的组合根 ctrl，信号回调连回 ctrl 上的处理方法。

const PaintTools = preload("res://scripts/editor/domain/paint_tools.gd")

static func build_menu_bar(ctrl) -> MenuBar:
	var bar := MenuBar.new()
	bar.flat = true
	bar.switch_on_hover = true
	ctrl._add_popup(bar, "文件", [
		["新建内容包", ctrl.MENU_FILE_NEW],
		["打开包…", ctrl.MENU_FILE_OPEN],
		["保存\tCtrl+S", ctrl.MENU_FILE_SAVE],
		["另存为…", ctrl.MENU_FILE_SAVE_AS],
		["打开工程 demo_map（副本）", ctrl.MENU_FILE_OPEN_DEMO],
		[],
		["导入 .rmpack…", ctrl.MENU_FILE_IMPORT],
		["导出 .rmpack…", ctrl.MENU_FILE_EXPORT],
		[],
		["返回", ctrl.MENU_FILE_LEAVE],
	])
	ctrl._add_popup(bar, "编辑", [
		["撤销\tCtrl+Z", ctrl.MENU_EDIT_UNDO],
		["重做\tCtrl+Y", ctrl.MENU_EDIT_REDO],
		[],
		["复制图块\tCtrl+C", ctrl.MENU_EDIT_COPY],
		["剪切图块\tCtrl+X", ctrl.MENU_EDIT_CUT],
		["粘贴图块\tCtrl+V", ctrl.MENU_EDIT_PASTE],
		["旋转选区剪贴板", 27],
		["水平翻转剪贴板", 28],
		["替换当前图块…", 29],
		["撤销历史…", 71],
		["复制实体", 25],
		["粘贴实体", 26],
	])
	ctrl._add_popup(bar, "地图", [
		["地图设置…", ctrl.MENU_MAP_SETTINGS],
		["重命名\tF2", 34],
		["新建子地图", ctrl.MENU_MAP_ADD],
		["复制地图\tCtrl+D", 35],
		["删除当前地图", ctrl.MENU_MAP_DEL],
		[],
		["实体编辑…", ctrl.MENU_ENTITY],
		["在此格放置宝箱事件", ctrl.MENU_MAP_CHEST],
		[],
		["参考图…", 37],
		["清除参考图", 38],
		["添加书签", 39],
	])
	ctrl._add_popup(bar, "素材", [
		["素材库…", ctrl.MENU_ASSET_LIB],
		["图块套…", ctrl.MENU_ASSET_TILESET],
		[],
		["导入图块 PNG…", ctrl.MENU_ASSET_TILE],
		["导入行走图 PNG…", ctrl.MENU_ASSET_CHAR],
		["导入音频…", ctrl.MENU_ASSET_AUDIO],
	])
	ctrl._add_popup(bar, "游戏", [
		["试玩\tF5", ctrl.MENU_GAME_PLAY],
		["从光标试玩\tShift+F5", ctrl.MENU_GAME_PLAY_CURSOR],
	])
	ctrl._mcp_popup = PopupMenu.new()
	ctrl._mcp_popup.name = "工具"
	ctrl._mcp_popup.add_check_item("启用 MCP 服务", ctrl.MENU_MCP_TOGGLE)
	ctrl._mcp_popup.id_pressed.connect(ctrl._on_menu)
	bar.add_child(ctrl._mcp_popup)
	return bar


static func build_toolbar(ctrl) -> Control:
	var wrap := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.11, 0.14, 1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	wrap.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	wrap.add_child(row)
	ctrl._mode_map_btn = ctrl._tb_toggle(row, "地图", true, func(): ctrl._set_mode(0))
	ctrl._mode_evt_btn = ctrl._tb_toggle(row, "事件", false, func(): ctrl._set_mode(1))
	ctrl._pass_btn = ctrl._tb_toggle(row, "通行", false, func(): ctrl._set_mode(2))
	row.add_child(ctrl._vsep())
	ctrl._tool_btns.clear()
	ctrl._tool_btns[PaintTools.Tool.PENCIL] = ctrl._tb_toggle(row, "铅笔", true, func(): ctrl._set_tool(PaintTools.Tool.PENCIL))
	ctrl._tool_btns[PaintTools.Tool.RECT] = ctrl._tb_toggle(row, "矩形", false, func(): ctrl._set_tool(PaintTools.Tool.RECT))
	ctrl._tool_btns[PaintTools.Tool.FILL] = ctrl._tb_toggle(row, "填充", false, func(): ctrl._set_tool(PaintTools.Tool.FILL))
	ctrl._tool_btns[PaintTools.Tool.EYEDROP] = ctrl._tb_toggle(row, "吸管", false, func(): ctrl._set_tool(PaintTools.Tool.EYEDROP))
	ctrl._tool_btns[PaintTools.Tool.ERASE] = ctrl._tb_toggle(row, "橡皮", false, func(): ctrl._set_tool(PaintTools.Tool.ERASE))
	ctrl._tool_btns[PaintTools.Tool.SELECT] = ctrl._tb_toggle(row, "选区", false, func(): ctrl._set_tool(PaintTools.Tool.SELECT))
	ctrl._tool_btns[PaintTools.Tool.LINE] = ctrl._tb_toggle(row, "线", false, func(): ctrl._set_tool(PaintTools.Tool.LINE))
	ctrl._tool_btns[PaintTools.Tool.POLYLINE] = ctrl._tb_toggle(row, "折线", false, func(): ctrl._set_tool(PaintTools.Tool.POLYLINE))
	ctrl._tool_btns[PaintTools.Tool.ELLIPSE] = ctrl._tb_toggle(row, "椭圆", false, func(): ctrl._set_tool(PaintTools.Tool.ELLIPSE))
	ctrl._tool_btns[PaintTools.Tool.RING] = ctrl._tb_toggle(row, "圆环", false, func(): ctrl._set_tool(PaintTools.Tool.RING))
	row.add_child(ctrl._vsep())
	ctrl._start_btn = ctrl._tb_toggle(row, "起始点", false, ctrl._toggle_start_tool)
	ctrl._pass_overlay_btn = ctrl._tb_toggle(row, "叠通行", false, ctrl._toggle_pass_overlay)
	row.add_child(ctrl._vsep())
	ctrl._tb_btn(row, "−", func(): ctrl._set_zoom(ctrl._zoom / 1.25))
	ctrl._zoom_lbl = Label.new()
	ctrl._zoom_lbl.text = "100%"
	ctrl._zoom_lbl.custom_minimum_size = Vector2(48, 0)
	ctrl._zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(ctrl._zoom_lbl)
	ctrl._tb_btn(row, "+", func(): ctrl._set_zoom(ctrl._zoom * 1.25))
	ctrl._tb_btn(row, "适应", ctrl._zoom_fit)
	row.add_child(ctrl._vsep())
	ctrl._add_lbl(row, "光照")
	ctrl._light_bar = OptionButton.new()
	ctrl._light_bar.focus_mode = Control.FOCUS_NONE
	ctrl._light_bar.custom_minimum_size = Vector2(110, 0)
	ctrl._fill_preset_opt(ctrl._light_bar, "map/light_presets.json", ["日间", "黄昏", "夜晚"])
	ctrl._light_bar.item_selected.connect(func(_i): ctrl._on_toolbar_light())
	row.add_child(ctrl._light_bar)
	ctrl._add_lbl(row, "天气")
	ctrl._weather_bar = OptionButton.new()
	ctrl._weather_bar.focus_mode = Control.FOCUS_NONE
	ctrl._weather_bar.custom_minimum_size = Vector2(88, 0)
	ctrl._weather_bar.tooltip_text = "预览天气（与光照叠乘，不写入地图）"
	for wrow in [["晴", "clear"], ["雨", "rain"], ["雷暴", "storm"], ["雪", "snow"], ["雾", "fog"]]:
		ctrl._weather_bar.add_item(str(wrow[0]))
		ctrl._weather_bar.set_item_metadata(ctrl._weather_bar.item_count - 1, str(wrow[1]))
	ctrl._weather_bar.item_selected.connect(func(_i): ctrl._on_toolbar_weather())
	row.add_child(ctrl._weather_bar)
	ctrl._add_lbl(row, "光效")
	ctrl._fx_color_bar = ColorPickerButton.new()
	ctrl._fx_color_bar.focus_mode = Control.FOCUS_NONE
	ctrl._fx_color_bar.custom_minimum_size = Vector2(36, 24)
	ctrl._fx_color_bar.edit_alpha = true
	ctrl._fx_color_bar.color = Color(1, 1, 1, 1)
	ctrl._fx_color_bar.tooltip_text = "光效颜色（加色层，与地图光照无关）"
	ctrl._fx_color_bar.color_changed.connect(ctrl._on_fx_color_changed)
	row.add_child(ctrl._fx_color_bar)
	return wrap
