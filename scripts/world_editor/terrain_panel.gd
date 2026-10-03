extends VBoxContainer
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor: Node3D
var choice: OptionButton
var create_fields: VBoxContainer
var brush_fields: VBoxContainer
var materials: OptionButton
var saturation: SpinBox
var region_fields: VBoxContainer
var region_list: OptionButton
var furrow_fields: VBoxContainer
var info: Label
var tasks: TabContainer
var begin_button: Button
var end_button: Button
var river_fields: VBoxContainer
var river_loaded:=""
var slope_fields: VBoxContainer
var slope_loaded:=""
const River=preload("res://scripts/world3d/river_material_data.gd")
func note(text: String) -> Label:
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(label); return label
func button(text: String, callback: Callable) -> Button:
	var value:=Button.new(); value.text=text; value.pressed.connect(callback); add_child(value); return value
func report(result: Dictionary) -> void:
	editor._status.text="地形操作完成" if result.ok else str(result.error)
	if result.ok: refresh(str(result.get("id",selected())))
func selected() -> String:
	return str(choice.get_item_metadata(choice.selected)) if choice.selected>=0 else ""
func setup(value: Node3D) -> void:
	editor=value; add_theme_constant_override("separation",8)
	note("地形雕刻").add_theme_font_size_override("font_size",18)
	note("先选地形，再启用笔刷。新建和转换在另一个页签中。")
	choice=OptionButton.new(); choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(choice); choice.item_selected.connect(func(_i):editor._terrain_brush.cancel(); refresh(selected()))
	button("使用当前选中的地形",func():
		var selected_records: Array=editor._selection_tools.records()
		if selected_records.size()!=1 or not selected_records[0].has("terrain_mesh"): report(Terrain.fail("请只选择一块可雕刻地形"))
		else: refresh(selected_records[0].uuid))
	var creation_start := get_child_count()
	create_fields=Form.new(); add_child(create_fields)
	create_fields.build(Terrain.create_schema(),{"name":"可雕刻地形","center":[0,0,0],"width":32.0,"depth":32.0,"cell_size":1.0,"bedrock_depth":16.0},{"name":"名称","center":"新建中心 / 地表标高（米）","width":"宽度 X（米）","depth":"长度 Z（米）","cell_size":"目标格距（米）","bedrock_depth":"底床深度（米）"})
	materials=OptionButton.new(); materials.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(materials); materials.add_item("地形原色"); materials.set_item_metadata(0,"")
	editor._material_panel.catalog_changed.connect(_refresh_material_choices)
	_refresh_material_choices()
	button("将选中地面转换为可雕刻地形",func():
		editor._terrain_brush.cancel()
		var selection: Array=editor._selection_tools.records()
		if selection.size()!=1: report(Terrain.fail("请只选择一个普通地面方块")); return
		var args: Dictionary=create_fields.values(); args.source_id=selection[0].uuid
		for key in ["center","width","depth"]: args.erase(key)
		args.material_id=materials.get_item_metadata(materials.selected); report(editor._terrain.create(args)))
	button("在空白区域新建地形",func():editor._terrain_brush.cancel(); report(editor._terrain.create(create_fields.values().merged({"material_id":materials.get_item_metadata(materials.selected)}))))
	note("底材饱和度（0 灰 / 1 原色）")
	saturation=SpinBox.new(); saturation.min_value=0.; saturation.max_value=1.; saturation.step=.01; saturation.value=1.; add_child(saturation)
	button("应用所选整体材质",func():editor._terrain_brush.cancel(); report(editor._terrain.set_material(selected(),str(materials.get_item_metadata(materials.selected)),saturation.value)))
	button("仅应用底材饱和度",func():editor._finish_edits(); report(editor._terrain.set_material(selected(),null,saturation.value)))
	note("圈定地表材质区域").add_theme_font_size_override("font_size",16)
	note("使用上方材质。拖框或点选多边形，跨块一次提交；锁定/隐藏/隔层地形不允许涂改。每块支持底材 + 两种区域材质，河床与陡坡规则优先。区域随地形移动和雕刻，删除会露出下层。")
	region_fields=Form.new(); add_child(region_fields)
	region_fields.build(preload("res://scripts/world3d/terrain_regions.gd").request_schema(),{"feather":5.,"opacity":1.},{"feather":"软边宽度（米）","opacity":"覆盖强度"})
	button("拖框刷地表区域",func():_begin_region(true))
	button("点选多边形区域",func():_begin_region(false))
	button("取消区域绘制",func():editor._ground_draw.cancel())
	region_list=OptionButton.new(); region_list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(region_list)
	region_list.item_selected.connect(func(_index):_refresh_furrows())
	note("选定上方区域后生成农田垄沟。沟底沿用原地面；垄脊带真实碰撞。区域边缘渐降回地面，避免侵入已有道路和物件。")
	furrow_fields=Form.new(); add_child(furrow_fields)
	furrow_fields.build(preload("res://scripts/world3d/terrain_furrows.gd").schemas(),{"spacing":1.6,"height":.18,"angle":0.,"margin":2.,"setback":0.},{"spacing":"垄距（米）","height":"垄高（米）","angle":"方向（0° 南北 / 90° 东西）","margin":"田边渐平距离（米）","setback":"田边留白（米）"})
	button("应用区域垄沟",func():_apply_furrows(true))
	button("移除区域垄沟（保留土壤）",func():_apply_furrows(false))
	button("删除选定地表区域（全部关联地形）",func():
		editor._finish_edits()
		if region_list.selected<0: return
		var id:=str(region_list.get_item_metadata(region_list.selected)); var ids: Array=[]
		for r in editor._doc.records:
			if r.get("terrain_regions",{}).get("regions",[]).any(func(p):return p.id==id): ids.append(r.uuid)
		report(preload("res://scripts/world_editor/terrain_region_tools.gd").apply(editor,{"id":id,"terrain_ids":ids},true)))
	note("通用地形 · 陡坡露岩").add_theme_font_size_override("font_size",16)
	note("缓坡保留原草地或泥土，陡坡渐变为岩石并使用三向投影。隆起、下沉和整平后自动更新，无须设置水位；自然河岸模式已包含相同规则。")
	slope_fields=Form.new(); add_child(slope_fields)
	button("应用所选地形坡度材质",func():_apply_slope(true))
	button("停用所选地形坡度材质",func():_apply_slope(false))
	note("河岸与河床 · 按水深渐变").add_theme_font_size_override("font_size",16)
	note("自然河岸按水深与坡度混合：缓岸草、土、沙不规则交错，陡壁自动露岩并使用三向投影。交错范围为 0 时关闭土层过渡。砌石水渠请选择岸墙/渠底，保留原材质与墙面 UV，只增加水线湿痕。可多选河床、水面与护岸整批应用；未多选时使用上方地形。")
	river_fields=Form.new(); add_child(river_fields)
	button("应用河床 / 水面 / 护岸材质",func(): _apply_river(true))
	button("停用所选河道材质效果",func(): _apply_river(false))
	var brush_start := get_child_count()
	var brush_hint := note("左键拖动雕刻，松开提交；Esc 取消。")
	brush_hint.tooltip_text = "整平使用世界高度；平滑强度为混合比例。风化搬移陡坡到坡脚，建议小范围多次刷。"
	brush_fields=Form.new(); add_child(brush_fields)
	brush_fields.build(Terrain.stroke_schema(),{"mode":"raise","radius":3.0,"strength":.5,"hardness":.25,"target_height":0.0,"iterations":8,"talus_angle":35.0,"erosion_seed":0},{"mode":"工具","radius":"半径（米）","strength":"强度","hardness":"硬度（0 软边 / 1 硬边）","target_height":"整平目标标高（米）","iterations":"风化迭代（1–32）","talus_angle":"风化稳定坡角（度）","erosion_seed":"风化随机种子"},{"mode":[{"id":"raise","name":"隆起"},{"id":"lower","name":"下沉 / 挖坑"},{"id":"flatten","name":"整平"},{"id":"smooth","name":"平滑"},{"id":"hole","name":"挖穿洞口"},{"id":"fill","name":"补洞"},{"id":"erode","name":"风化 / 坡脚堆积"}]})
	for control in brush_fields.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v):editor._terrain_brush.cancel())
		elif control is OptionButton: control.item_selected.connect(func(_i):editor._terrain_brush.cancel())
	begin_button = button("启用当前地形笔刷",func():
		report(editor._terrain_brush.begin(selected(),brush_fields.values()))
		if editor._terrain_brush.active: editor._status.text="在画布中拖动地形笔刷；Esc 取消这一笔并退出")
	end_button = button("结束笔刷",func():editor._terrain_brush.cancel())
	info=note("")
	var existing := get_children()
	tasks = TabContainer.new(); tasks.name = "TerrainTasks"; add_child(tasks)
	var sculpt := VBoxContainer.new(); sculpt.name = "雕刻地形"; sculpt.add_theme_constant_override("separation", 8); tasks.add_child(sculpt)
	var create := VBoxContainer.new(); create.name = "新建 / 转换"; create.add_theme_constant_override("separation", 8); tasks.add_child(create)
	for index in range(creation_start, brush_start): existing[index].reparent(create)
	for index in range(brush_start, existing.size()): existing[index].reparent(sculpt)
	sculpt.move_child(begin_button, 0); sculpt.move_child(end_button, 1)
	refresh()
func refresh(preferred: String="") -> void:
	if choice==null: return
	var id:=preferred if not preferred.is_empty() else selected(); choice.clear()
	for row in editor._terrain.catalog().terrains:
		choice.add_item("%s · %d×%d · %d 洞格"%[row.name,row.columns,row.rows,row.holes]); choice.set_item_metadata(choice.item_count-1,row.id)
		if row.id==id: choice.select(choice.item_count-1)
	choice.disabled = choice.item_count == 0
	if choice.item_count == 0: choice.text = "暂无可雕刻地形"
	if info!=null: info.text="选定地形后启用笔刷。锁定、隐藏或隔层地形不可修改；笔刷侵入物件或挖掉其承托时整笔取消。底床不是洞穴系统。"
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
	if furrow_fields==null or region_list.selected<0: return
	var id:=str(region_list.get_item_metadata(region_list.selected))
	var values:={"spacing":1.6,"height":.18,"angle":0.,"margin":2.,"setback":0.}
	for r in editor._doc.records:
		for region in r.get("terrain_regions",{}).get("regions",[]):
			if region.id==id and region.has("furrows"):
				for key in values: values[key]=region.furrows.get(key,values[key])
				values.angle=wrapf(values.angle-r.rotation[1],-180.,180.)
				break
	for key in values: furrow_fields.fields[key].value=values[key]

func _refresh_slope() -> void:
	if slope_fields==null: return
	var config: Dictionary=editor._doc._find(selected()).get("terrain_slope_blend",{})
	var key:=selected()+JSON.stringify(config)
	if key==slope_loaded: return
	slope_loaded=key
	var values:={"steep_start":config.get("steep_start",40.0),"steep_end":config.get("steep_end",65.0),"rock_material_id":"pack:default:terrain/icelandic_jagged_slate/material"}
	for key_ in River.TRANSITION_DEFAULTS: values[key_]=config.get(key_,River.TRANSITION_DEFAULTS[key_] if config.is_empty() else 0.)
	values.transition_material_id=River.TRANSITION_MATERIAL
	var options: Array=[]
	for entry in editor._material_tool.library.entries():
		options.append({"id":entry.material_id,"name":entry.material.name})
		if config.get("rock_material",{})==entry.material: values.rock_material_id=entry.material_id
		if config.get("transition_material",{})==entry.material: values.transition_material_id=entry.material_id
	slope_fields.build(River.slope_schema(),values,{"steep_start":"开始露岩坡度（度）","steep_end":"完全露岩坡度（度）","rock_material_id":"陡坡岩石材质","transition_material_id":"边缘土层 / 碎石材质","transition_width":"自然交错范围（米；0 关闭）","edge_noise":"边界不规则程度","height_blend_strength":"贴图高度混合强度"},{"rock_material_id":options,"transition_material_id":options})

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

func _refresh_river() -> void:
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
	if key==river_loaded: return
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
	for entry in editor._material_tool.library.entries():
		options.append({"id":entry.material_id,"name":entry.material.name})
		for layer in ["sand","rock","transition"]:
			if config.get(layer+"_material",{})==entry.material: values[layer+"_material_id"]=entry.material_id
	river_fields.build(River.request_schema(),values,{"water_level":"水面世界标高（米）","shore_start":"岸上开始接回底材（米）","shore_end":"岸上完全恢复底材（米）","rock_start":"水下开始混入岩石（米）","rock_end":"水下完全转为岩石（米）","bank_profile":"自然河岸算法","steep_start":"开始露岩坡度（度）","steep_end":"完全露岩坡度（度）","wet_height":"河岸 / 岸墙湿痕高度（米）","wet_darkening":"自然河岸湿润变暗（0 关闭）","absorption":"河水浑浊 / 吸收系数","shallow_color":"浅水颜色","deep_color":"深水颜色","sand_material_id":"浅水沙地材质","rock_material_id":"深水岩石材质","transition_material_id":"边缘土层 / 碎石材质","transition_width":"自然交错范围（米；0 关闭）","edge_noise":"边界不规则程度","height_blend_strength":"贴图高度混合强度"},{"sand_material_id":options,"rock_material_id":options,"transition_material_id":options,"bank_profile":[{"id":"natural","name":"水深 + 坡度 · 三向投影"},{"id":"depth","name":"仅水深 · 旧版对照"}]})

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
	var chosen := str(materials.get_item_metadata(materials.selected)) if materials.selected >= 0 else ""
	materials.clear(); materials.add_item("地形原色"); materials.set_item_metadata(0, "")
	for entry in editor._material_panel._entries:
		materials.add_item(str(entry.material.name)); materials.set_item_metadata(materials.item_count - 1, entry.material_id)
		if entry.material_id == chosen: materials.select(materials.item_count - 1)
