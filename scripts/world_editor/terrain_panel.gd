extends VBoxContainer
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
const Compact=preload("res://scripts/world_editor/terrain_form_layout.gd")
var editor: Node3D
var choice: OptionButton
var create_fields: VBoxContainer
var brush_fields: VBoxContainer
var materials: OptionButton
var create_materials: OptionButton
var river_panel: VBoxContainer
var furrow_section: VBoxContainer
var terrain_result: Label
var saturation: SpinBox
var region_fields: VBoxContainer
var region_list: OptionButton
var furrow_fields: VBoxContainer
var info: Label
var tasks: TabContainer
var rock_banks
var begin_button: Button
var end_button: Button
var river_fields: VBoxContainer
var river_loaded:=""
var slope_fields: VBoxContainer
var slope_loaded:=""
var _river_bound_values:Dictionary={}
var _slope_bound_values:Dictionary={}
const River=preload("res://scripts/world3d/river_material_data.gd")
func note(text: String) -> Label:
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(label); return label
func button(text: String, callback: Callable) -> Button:
	var value:=Button.new(); value.text=text; value.pressed.connect(callback); add_child(value); return value
func report(result: Dictionary) -> void:
	editor._report_result(result,"地形操作完成","地形")
	if terrain_result!=null:
		terrain_result.text="地形操作完成" if result.ok else str(result.error)
		terrain_result.visible=true
	if result.ok: refresh(str(result.get("id",selected())))
func selected() -> String:
	return str(choice.get_item_metadata(choice.selected)) if choice.selected>=0 else ""
func setup(value: Node3D) -> void:
	editor=value; add_theme_constant_override("separation",8)
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	choice=OptionButton.new(); choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(choice); choice.item_selected.connect(func(_i):editor._terrain_brush.cancel(); refresh(selected()))
	button("使用当前选中的地形",func():
		var selected_records: Array=editor._selection_tools.records()
		if selected_records.size()!=1 or not selected_records[0].has("terrain_mesh"): report(Terrain.fail("请只选择一块可雕刻地形"))
		else: refresh(selected_records[0].uuid))
	var creation_start := get_child_count()
	create_fields=Form.new(); add_child(create_fields)
	create_fields.build(Terrain.create_schema(),{"name":"可雕刻地形","center":[0,0,0],"width":32.0,"depth":32.0,"cell_size":1.0,"bedrock_depth":16.0},{"name":"名称","center":"新建中心 / 地表标高（米）","width":"宽度 X（米）","depth":"长度 Z（米）","cell_size":"目标格距（米）","bedrock_depth":"底床深度（米）"})
	Compact.apply(create_fields,{"name":"名称","width":"宽度 X (m)","depth":"长度 Z (m)","cell_size":"格距 (m)","bedrock_depth":"底床深 (m)"})
	note("新地形底材")
	create_materials=OptionButton.new(); create_materials.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(create_materials)
	materials=OptionButton.new(); materials.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(materials); materials.add_item("地形原色"); materials.set_item_metadata(0,"")
	editor._material_panel.catalog_changed.connect(_refresh_material_choices)
	_refresh_material_choices()
	var convert_button:=button("转换选中地面",func():
		editor._terrain_brush.cancel()
		var selection: Array=editor._selection_tools.records()
		if selection.size()!=1: report(Terrain.fail("请只选择一个普通地面方块")); return
		var args: Dictionary=create_fields.values(); args.source_id=selection[0].uuid
		for key in ["center","width","depth"]: args.erase(key)
		args.material_id=create_materials.get_item_metadata(create_materials.selected); report(editor._terrain.create(args)))
	var create_button:=button("新建地形",func():editor._terrain_brush.cancel(); report(editor._terrain.create(create_fields.values().merged({"material_id":create_materials.get_item_metadata(create_materials.selected)}))))
	var surface_start:=get_child_count()
	note("地形底材")
	var saturation_label:=note("底材饱和度（0 灰 / 1 原色）")
	saturation=SpinBox.new(); saturation.min_value=0.; saturation.max_value=1.; saturation.step=.01; saturation.value=1.; add_child(saturation)
	button("应用所选整体材质",func():editor._terrain_brush.cancel(); report(editor._terrain.set_material(selected(),str(materials.get_item_metadata(materials.selected)),saturation.value)))
	button("仅应用底材饱和度",func():editor._finish_edits(); report(editor._terrain.set_material(selected(),null,saturation.value)))
	var region_start:=get_child_count()
	note("圈定地表材质区域").theme_type_variation="EditorHeading"
	var region_hint:=note("使用本页所选材质，拖框或点选多边形。区域随地形移动与雕刻。")
	region_hint.tooltip_text="锁定、隐藏或隔层地形不可涂改。每块支持底材与两种区域材质；河床与陡坡规则优先，删除区域会露出下层。"
	region_fields=Form.new(); add_child(region_fields)
	region_fields.build(preload("res://scripts/world3d/terrain_regions.gd").request_schema(),{"feather":5.,"opacity":1.},{"feather":"软边宽度（米）","opacity":"覆盖强度"})
	Compact.apply(region_fields,{"feather":"软边 (m)","opacity":"覆盖强度"})
	button("拖框刷地表区域",func():_begin_region(true))
	button("点选多边形区域",func():_begin_region(false))
	button("取消区域绘制",func():editor._ground_draw.cancel())
	region_list=OptionButton.new(); region_list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(region_list)
	region_list.item_selected.connect(func(_index):_refresh_furrows())
	var furrow_start:=get_child_count()
	note("为选定区域生成带碰撞的垄沟，田边平缓接回原地面。")
	furrow_fields=Form.new(); add_child(furrow_fields)
	furrow_fields.build(preload("res://scripts/world3d/terrain_furrows.gd").schemas(),{"spacing":1.6,"height":.18,"angle":0.,"margin":2.,"setback":0.},{"spacing":"垄距（米）","height":"垄高（米）","angle":"方向（0° 南北 / 90° 东西）","margin":"田边渐平距离（米）","setback":"田边留白（米）"})
	Compact.apply(furrow_fields,{"spacing":"垄距 (m)","height":"垄高 (m)","angle":"方向 (°)","margin":"渐平 (m)","setback":"留白 (m)"})
	button("应用区域垄沟",func():_apply_furrows(true))
	button("移除区域垄沟（保留土壤）",func():_apply_furrows(false))
	var delete_region_button:=button("删除选定地表区域",func():
		editor._finish_edits()
		if region_list.selected<0: return
		var id:=str(region_list.get_item_metadata(region_list.selected)); var ids: Array=[]
		for r in editor._doc.records:
			if r.get("terrain_regions",{}).get("regions",[]).any(func(p):return p.id==id): ids.append(r.uuid)
		report(preload("res://scripts/world_editor/terrain_region_tools.gd").apply(editor,{"id":id,"terrain_ids":ids},true)))
	var slope_start:=get_child_count()
	note("陡坡露岩").theme_type_variation="EditorHeading"
	note("缓坡保留底材，陡坡渐变为岩石。雕刻后自动更新；自然河岸已包含相同规则。")
	slope_fields=Form.new(); add_child(slope_fields)
	button("应用所选地形坡度材质",func():_apply_slope(true))
	button("停用所选地形坡度材质",func():_apply_slope(false))
	var river_material_start:=get_child_count()
	note("河岸与河床材质").theme_type_variation="EditorHeading"
	var river_hint:=note("多选河床、水面或护岸后统一设置；未多选时使用上方地形。")
	river_hint.tooltip_text="自然河岸按水深与坡度混合草、土、沙和岩石。砌石水渠保留原材质与 UV，仅增加水线湿痕；交错范围为 0 时关闭土层过渡。"
	river_fields=Form.new(); add_child(river_fields)
	var apply_river:=button("应用河道材质",func(): _apply_river(true))
	var remove_river:=button("停用材质效果",func(): _apply_river(false))
	var brush_start := get_child_count()
	var brush_hint := note("左键拖动雕刻，松开提交；Esc 取消。")
	brush_hint.tooltip_text = "整平使用世界高度；矩形宅基以宽深定义平面，外侧柔和过渡，强度 1 一次整平。平滑强度为混合比例。风化搬移陡坡到坡脚，建议小范围多次刷。"
	brush_fields=Form.new(); add_child(brush_fields)
	brush_fields.build(Terrain.stroke_schema(),{"cross_tiles":true,"mode":"raise","shape":"circle","plot_width":10.,"plot_depth":14.,"plot_yaw":0.,"blend_margin":2.,"radius":3.0,"strength":.5,"hardness":.25,"target_height":0.0,"iterations":8,"talus_angle":35.0,"erosion_seed":0},{"cross_tiles":"跨相邻地形并同步边界","mode":"工具","shape":"整平形状","plot_width":"宅基宽（米）","plot_depth":"宅基深（米）","plot_yaw":"宅基转向（度）","blend_margin":"平滑过渡宽（米）","radius":"半径（米）","strength":"强度","hardness":"硬度（0 软边 / 1 硬边）","target_height":"整平目标标高（米）","iterations":"风化迭代（1–32）","talus_angle":"风化稳定坡角（度）","erosion_seed":"风化随机种子"},{"shape":[{"id":"circle","name":"圆形"},{"id":"rectangle","name":"矩形宅基（平滑边缘）"}],"mode":[{"id":"raise","name":"隆起"},{"id":"lower","name":"下沉 / 挖坑"},{"id":"flatten","name":"整平"},{"id":"smooth","name":"平滑"},{"id":"hole","name":"挖穿洞口"},{"id":"fill","name":"补洞"},{"id":"erode","name":"风化 / 坡脚堆积"}]})
	Compact.apply(brush_fields,{"cross_tiles":"跨相邻地形同步边界","mode":"工具","radius":"半径 (m)","strength":"强度","hardness":"硬度","target_height":"目标高 (m)","iterations":"迭代次数","talus_angle":"稳定坡 (°)","erosion_seed":"随机种子"})
	for control in brush_fields.fields.values():
		if control is CheckButton: control.toggled.connect(func(_v):editor._terrain_brush.cancel())
		elif control is SpinBox: control.value_changed.connect(func(_v):editor._terrain_brush.cancel())
		elif control is OptionButton: control.item_selected.connect(func(_i):editor._terrain_brush.cancel())
	begin_button = button("启用当前地形笔刷",func():
		report(editor._terrain_brush.begin(selected(),brush_fields.values()))
		if editor._terrain_brush.active: editor._status.text="在画布中拖动地形笔刷；Esc 取消这一笔并退出")
	end_button = button("结束笔刷",func():editor._terrain_brush.cancel())
	info=note("")
	var existing := get_children()
	tasks = TabContainer.new(); tasks.name = "TerrainTasks"; tasks.size_flags_vertical=Control.SIZE_EXPAND_FILL; tasks.use_hidden_tabs_for_min_size=false; add_child(tasks)
	var sculpt:=_task_page("雕刻")
	var surface:=_task_page("表面")
	var rivers:=VBoxContainer.new(); rivers.name="河流"; tasks.add_child(rivers)
	var river_tasks:=TabContainer.new(); river_tasks.size_flags_vertical=Control.SIZE_EXPAND_FILL; river_tasks.use_hidden_tabs_for_min_size=false; rivers.add_child(river_tasks)
	river_panel=preload("res://scripts/world_editor/terrain_river_panel.gd").new(); river_tasks.add_child(river_panel); river_panel.setup(editor); river_panel.name="河道布局"
	var river_appearance:=_task_page("材质效果",river_tasks)
	var cave:=_task_page("洞穴")
	var volume_panel:=preload("res://scripts/world_editor/terrain_volume_panel.gd").new(); cave.body.add_child(volume_panel); volume_panel.setup(editor)
	var rock:=_task_page("岩岸")
	rock_banks=preload("res://scripts/world_editor/rock_bank_panel.gd").new(); rock.body.add_child(rock_banks); rock_banks.setup(editor)
	var create:=_task_page("新建")
	_move_range(existing,creation_start,surface_start,create.body)
	_move_range(existing,surface_start,region_start,surface.body)
	materials.reparent(surface.body); surface.body.move_child(materials,1)
	Compact.pair(saturation_label,saturation,"饱和度")
	var region_section:=_section(surface.body,"地表区域",true)
	_move_range(existing,region_start,furrow_start,region_section)
	furrow_section=_section(surface.body,"选定区域 · 农田垄沟")
	_move_range(existing,furrow_start,slope_start,furrow_section)
	delete_region_button.reparent(region_section)
	_move_range(existing,slope_start,river_material_start,_section(surface.body,"陡坡露岩"))
	_move_range(existing,river_material_start,brush_start,river_appearance.body)
	_move_range(existing,brush_start,existing.size(),sculpt.body)
	begin_button.reparent(sculpt.footer); end_button.reparent(sculpt.footer)
	create_button.reparent(create.footer); convert_button.reparent(create.footer)
	apply_river.reparent(river_appearance.footer); remove_river.reparent(river_appearance.footer)
	terrain_result=note(""); terrain_result.name="TerrainResult"; terrain_result.visible=false
	brush_fields.fields.mode.item_selected.connect(func(_index):_update_brush_fields())
	brush_fields.fields.shape.item_selected.connect(func(_index):_update_brush_fields())
	_update_brush_fields()
	refresh()

func _task_page(title:String, host:TabContainer=null)->Dictionary:
	var page:=VBoxContainer.new(); page.name=title; page.add_theme_constant_override("separation",8)
	(host if host!=null else tasks).add_child(page)
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; page.add_child(scroll)
	var body:=VBoxContainer.new(); body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",8); scroll.add_child(body)
	var footer:=VBoxContainer.new(); footer.name="Actions"; page.add_child(footer)
	return {"page":page,"body":body,"footer":footer}

func _move_range(children:Array, start:int, end:int, target:Node)->void:
	for index in range(start,end): children[index].reparent(target)

func _section(parent:Node, title:String, expanded:bool=false)->VBoxContainer:
	var toggle:=Button.new(); toggle.text=("▾ " if expanded else "▸ ")+title; toggle.toggle_mode=true; toggle.button_pressed=expanded; toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT; parent.add_child(toggle)
	var body:=VBoxContainer.new(); body.add_theme_constant_override("separation",8); body.visible=expanded; parent.add_child(body)
	toggle.toggled.connect(func(open):body.visible=open; toggle.text=("▾ " if open else "▸ ")+title)
	return body

func _update_brush_fields()->void:
	var mode:String=brush_fields.values().mode
	if mode!="flatten":brush_fields.fields.shape.select(0)
	var rectangle:bool=mode=="flatten" and brush_fields.values().shape=="rectangle"
	Compact.show_field(brush_fields,"shape",mode=="flatten")
	for key in ["plot_width","plot_depth","plot_yaw","blend_margin"]:Compact.show_field(brush_fields,key,rectangle)
	for key in ["radius","hardness"]:Compact.show_field(brush_fields,key,not rectangle)
	brush_fields.fields.strength.max_value=1. if rectangle else 20.
	for key in ["target_height","iterations","talus_angle","erosion_seed"]:
		var show:=mode=="flatten" if key=="target_height" else mode=="erode"
		Compact.show_field(brush_fields,key,show)

func refresh(preferred: String="") -> void:
	if rock_banks!=null:rock_banks.refresh()
	if river_panel!=null:river_panel.refresh_catalog()
	if choice==null: return
	var id:=preferred if not preferred.is_empty() else selected(); choice.clear()
	for row in editor._terrain.catalog().terrains:
		choice.add_item("%s · %d×%d · %d 洞格"%[row.name,row.columns,row.rows,row.holes]); choice.set_item_metadata(choice.item_count-1,row.id)
		if row.id==id: choice.select(choice.item_count-1)
	choice.disabled = choice.item_count == 0
	if choice.item_count == 0: choice.text = "暂无可雕刻地形"
	if info!=null:
		info.text="锁定、隐藏或隔层地形不可修改。"; info.theme_type_variation="EditorCaption"
		info.tooltip_text="选定地形后启用笔刷。笔刷侵入物件或挖掉其承托时整笔取消。横向洞穴与悬挑请使用“洞穴”页签。"
	if saturation!=null: saturation.value=editor._doc._find(selected()).get("terrain_saturation",1.)
	_refresh_river()
	_refresh_slope()
	if region_list!=null:
		var selected_region:=str(region_list.get_item_metadata(region_list.selected)) if region_list.selected>=0 else ""
		region_list.clear()
		var seen:={}
		for r in editor._doc.records:
			for region in r.get("terrain_regions",{}).get("regions",[]):
				if seen.has(region.id): continue
				seen[region.id]=true
				var polygon:=preload("res://scripts/world3d/terrain_regions.gd").points(region)
				var center:=Vector2.ZERO
				for p in polygon: center+=p
				center/=polygon.size()
				var world:=Terrain.transform(r)*Vector3(center.x,0,center.y)
				region_list.add_item("%s · X%.0f Z%.0f"%[r.terrain_regions.materials[int(region.layer)].name,world.x,world.z])
				region_list.set_item_metadata(region_list.item_count-1,region.id)
				if region.id==selected_region: region_list.select(region_list.item_count-1)
		_refresh_furrows()

func _refresh_furrows() -> void:
	if furrow_fields==null: return
	var has_region:=region_list.selected>=0
	if furrow_section!=null:
		var toggle:Button=furrow_section.get_parent().get_child(furrow_section.get_index()-1)
		toggle.disabled=not has_region
		toggle.tooltip_text="请先绘制地表区域" if not has_region else ""
		if not has_region:toggle.button_pressed=false
	if not has_region: return
	var id:=str(region_list.get_item_metadata(region_list.selected))
	var values:={"spacing":1.6,"height":.18,"angle":0.,"margin":2.,"setback":0.}
	for r in editor._doc.records:
		for region in r.get("terrain_regions",{}).get("regions",[]):
			if region.id==id and region.has("furrows"):
				for key in values: values[key]=region.furrows.get(key,values[key])
				values.angle=wrapf(values.angle-r.rotation[1],-180.,180.)
				break
	for key in values: furrow_fields.fields[key].value=values[key]

func _pending_values(form: VBoxContainer, bound: Dictionary) -> Dictionary:
	var pending:Dictionary={}
	var current:Dictionary=form.values()
	for key in current:
		var value:Variant=current[key]
		if bound.has(key) and value!=bound[key]:pending[key]=value
	return pending

func _refresh_slope(catalog_changed: bool = false) -> void:
	if slope_fields==null: return
	var config: Dictionary=editor._doc._find(selected()).get("terrain_slope_blend",{})
	var key:=selected()+JSON.stringify(config)
	if key==slope_loaded and not catalog_changed: return
	var pending: Dictionary=_pending_values(slope_fields,_slope_bound_values) if catalog_changed and key==slope_loaded else {}
	slope_loaded=key
	var values:={"steep_start":config.get("steep_start",40.0),"steep_end":config.get("steep_end",65.0),"rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"}
	for key_ in River.TRANSITION_DEFAULTS: values[key_]=config.get(key_,River.TRANSITION_DEFAULTS[key_] if config.is_empty() else 0.)
	values.transition_material_id=River.TRANSITION_MATERIAL
	var options: Array=[]
	# Reuse the material browser's validated, asynchronously published catalog.
	for entry in editor._material_panel._entries:
		options.append({"id":entry.material_id,"name":entry.material.name})
		if config.get("rock_material",{})==entry.material: values.rock_material_id=entry.material_id
		if config.get("transition_material",{})==entry.material: values.transition_material_id=entry.material_id
	_slope_bound_values=values.duplicate(true)
	values.merge(pending,true)
	if not catalog_changed and slope_fields.update_values(values):return
	slope_fields.build(River.slope_schema(),values,{"steep_start":"开始露岩坡度（度）","steep_end":"完全露岩坡度（度）","rock_material_id":"陡坡岩石材质","transition_material_id":"边缘土层 / 碎石材质","transition_width":"自然交错范围（米；0 关闭）","edge_noise":"边界不规则程度","height_blend_strength":"贴图高度混合强度"},{"rock_material_id":options,"transition_material_id":options})
	slope_fields.group_fields([{ "id":"transition", "label":"边缘自然过渡", "fields":["transition_material_id","transition_width","edge_noise","height_blend_strength"] }])
	Compact.apply(slope_fields,{"steep_start":"开始坡度 (°)","steep_end":"完全坡度 (°)","transition_width":"交错宽 (m)","edge_noise":"边界起伏","height_blend_strength":"高度混合"})

func _apply_furrows(enabled: bool) -> void:
	editor._finish_edits()
	if region_list.selected<0: report(Terrain.fail("请先圈画并选择农田地表区域")); return
	var id:=str(region_list.get_item_metadata(region_list.selected)); var ids: Array=[]
	for r in editor._doc.records:
		if r.get("terrain_regions",{}).get("regions",[]).any(func(p):return p.id==id): ids.append(r.uuid)
	var args: Dictionary=furrow_fields.values() if enabled else {}
	args.merge({"id":id,"terrain_ids":ids,"enabled":enabled})
	report(preload("res://scripts/world_editor/terrain_furrow_tools.gd").apply(editor,args))

func _apply_slope(enabled: bool) -> void:
	editor._terrain_brush.cancel()
	var args: Dictionary=slope_fields.values() if enabled else {}
	args.enabled=enabled; args.terrain_ids=[]
	var records: Array=editor._selection_tools.records()
	if records.is_empty(): records=[editor._doc._find(selected())]
	for record in records:
		if not record.has("terrain_mesh"): report(Terrain.fail("请选择可雕刻地形")); return
		args.terrain_ids.append(record.uuid)
	report(preload("res://scripts/world_editor/river_material_tools.gd").apply_slope(editor,args))

func _refresh_river(catalog_changed: bool = false) -> void:
	if river_fields==null: return
	var record: Dictionary=editor._doc._find(selected())
	var config: Dictionary=record.get("terrain_depth_blend",{})
	var water_config: Dictionary={}
	var bank_config: Dictionary={}
	for r in editor._selection_tools.records():
		if r.has("water_depth_effect"): water_config=r.water_depth_effect; break
	for r in editor._selection_tools.records():
		if r.has("bank_wetness"): bank_config=r.bank_wetness; break
	var key:=selected()+JSON.stringify([config,water_config,bank_config])
	if key==river_loaded and not catalog_changed: return
	var pending: Dictionary=_pending_values(river_fields,_river_bound_values) if catalog_changed and key==river_loaded else {}
	river_loaded=key
	var values:=River.DEFAULTS.duplicate(true)
	values.wet_darkening=config.get("wet_darkening",0.)
	for key_ in River.TRANSITION_DEFAULTS: values[key_]=config.get(key_,River.TRANSITION_DEFAULTS[key_] if config.is_empty() else 0.)
	values.transition_material_id=River.TRANSITION_MATERIAL
	values.merge(water_config,true)
	for name_ in ["water_level","shore_start","shore_end","rock_start","rock_end","bank_profile","steep_start","steep_end","wet_height"]:
		if config.has(name_): values[name_]=config[name_]
	if not config.is_empty() and not config.has("bank_profile"): values.bank_profile="depth"
	values.merge(bank_config,true)
	var options: Array=[]
	values.sand_material_id="pack:default:terrain/bright_desert_sand/material"
	values.rock_material_id="pack:default:terrain/icelandic_jagged_slate/material"
	for entry in editor._material_panel._entries:
		options.append({"id":entry.material_id,"name":entry.material.name})
		for layer in ["sand","rock","transition"]:
			if config.get(layer+"_material",{})==entry.material: values[layer+"_material_id"]=entry.material_id
	_river_bound_values=values.duplicate(true)
	values.merge(pending,true)
	if not catalog_changed and river_fields.update_values(values):return
	river_fields.build(River.request_schema(),values,{"water_level":"水面世界标高（米）","shore_start":"岸上开始接回底材（米）","shore_end":"岸上完全恢复底材（米）","rock_start":"水下开始混入岩石（米）","rock_end":"水下完全转为岩石（米）","bank_profile":"自然河岸算法","steep_start":"开始露岩坡度（度）","steep_end":"完全露岩坡度（度）","wet_height":"河岸 / 岸墙湿痕高度（米）","wet_darkening":"自然河岸湿润变暗（0 关闭）","absorption":"河水浑浊 / 吸收系数","shallow_color":"浅水颜色","deep_color":"深水颜色","sand_material_id":"浅水沙地材质","rock_material_id":"深水岩石材质","transition_material_id":"边缘土层 / 碎石材质","transition_width":"自然交错范围（米；0 关闭）","edge_noise":"边界不规则程度","height_blend_strength":"贴图高度混合强度"},{"sand_material_id":options,"rock_material_id":options,"transition_material_id":options,"bank_profile":[{"id":"natural","name":"水深 + 坡度 · 三向投影"},{"id":"depth","name":"仅水深 · 旧版对照"}]})
	river_fields.group_fields([
		{"id":"bank", "label":"河岸与露岩", "expanded":true, "fields":["bank_profile","sand_material_id","rock_material_id","shore_start","shore_end","rock_start","rock_end","steep_start","steep_end"]},
		{"id":"transition", "label":"自然交错与湿痕", "fields":["transition_material_id","transition_width","edge_noise","height_blend_strength","wet_height","wet_darkening"]},
		{"id":"water", "label":"水面颜色与透明度", "fields":["absorption","shallow_color","deep_color"]}
	])
	Compact.apply(river_fields,{"water_level":"水位 (m)","bank_profile":"河岸算法","shore_start":"岸上起点 (m)","shore_end":"岸上终点 (m)","rock_start":"水下起点 (m)","rock_end":"水下终点 (m)","steep_start":"开始坡度 (°)","steep_end":"完全坡度 (°)","wet_height":"湿痕高 (m)","wet_darkening":"湿润变暗","absorption":"浑浊度","shallow_color":"浅水颜色","deep_color":"深水颜色","transition_width":"交错宽 (m)","edge_noise":"边界起伏","height_blend_strength":"高度混合"})

func _apply_river(enabled: bool) -> void:
	editor._terrain_brush.cancel()
	var args: Dictionary=river_fields.values() if enabled else {}
	args.enabled=enabled; args.terrain_ids=[]; args.water_ids=[]; args.bank_ids=[]
	var records: Array=editor._selection_tools.records()
	if records.is_empty(): records=[editor._doc._find(selected())]
	for record in records:
		if record.has("terrain_mesh"): args.terrain_ids.append(record.uuid)
		elif record.has("channel_mesh") and record.get("surface_id")=="water": args.water_ids.append(record.uuid)
		elif River.bank_target(record): args.bank_ids.append(record.uuid)
		else: report(Terrain.fail("请仅选择河床、水面、普通护岸或渠底网格")); return
	report(preload("res://scripts/world_editor/river_material_tools.gd").apply(editor,args))

func _begin_region(box: bool) -> void:
	var args: Dictionary=region_fields.values(); args.material_id=materials.get_item_metadata(materials.selected)
	if str(args.material_id).is_empty(): report(Terrain.fail("请选择区域 PBR 材质")); return
	var result: Dictionary=editor._ground_draw.begin(args,box)
	if not result.ok: report(result); return
	editor._status.text="拖出矩形地表区域，松开应用 · Esc 取消" if box else "点选区域角点 · Enter 应用 · Backspace 回退 · Esc 取消"


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or begin_button == null: return
	begin_button.disabled = selected().is_empty() or editor._terrain_brush.active
	begin_button.text = "笔刷已启用" if editor._terrain_brush.active else "启用当前地形笔刷"
	end_button.disabled = not editor._terrain_brush.active

func _refresh_material_choices() -> void:
	for picker:OptionButton in [materials,create_materials]:
		if picker==null:continue
		var chosen:=str(picker.get_item_metadata(picker.selected)) if picker.selected>=0 else ""
		picker.clear(); picker.add_item("地形原色"); picker.set_item_metadata(0,"")
		for entry in editor._material_panel._entries:
			picker.add_item(str(entry.material.name)); picker.set_item_metadata(picker.item_count-1,entry.material_id)
			if entry.material_id==chosen:picker.select(picker.item_count-1)
	# Catalog publication must not discard a partly edited form or the selected
	# material. Document/selection changes still load the actual stored values.
	_refresh_river(true)
	_refresh_slope(true)
