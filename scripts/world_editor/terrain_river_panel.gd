extends VBoxContainer
const Tool=preload("res://scripts/world_editor/terrain_river_tools.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
const Compact=preload("res://scripts/world_editor/terrain_form_layout.gd")
var editor:Node3D
var settings:VBoxContainer
var coordinates:VBoxContainer
var point_list:ItemList
var terrain_ids:Array=[]
var points:Array=[]
var message:Label
var river_picker:OptionButton
var terrain_summary:Label
var apply_button:Button
var remove_button:Button
var _catalog:Array=[]
var _loaded_id:=""
var _last_catalog:=""
var _catalog_source:Variant=null
var _catalog_valid:=true
var _body:VBoxContainer

func setup(value:Node3D)->void:
	editor=value; name="中心线河道"; add_theme_constant_override("separation",8); size_flags_vertical=Control.SIZE_EXPAND_FILL
	var browse:=HBoxContainer.new(); add_child(browse)
	river_picker=OptionButton.new(); river_picker.name="ExistingRiverPicker"; river_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL; river_picker.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; browse.add_child(river_picker)
	river_picker.item_selected.connect(func(index):
		if index==0:new_river()
		else:load_river(str(river_picker.get_item_metadata(index))))
	button("新建",new_river,browse).tooltip_text="开始一个新的河道方案，不改动地图"
	button("编辑场景选中的河道",load_selected).tooltip_text="选择水面可定位所属河道；地形只属于一条河道时也可使用"
	var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(scroll)
	_body=VBoxContainer.new(); _body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _body.add_theme_constant_override("separation",8); scroll.add_child(_body)
	var hint:=Label.new(); hint.text="选地形 → 添加中心线点 → 生成河道"; hint.tooltip_text="按顺序添加中心线点。更新会保留无关雕刻，整次可撤销。"; hint.theme_type_variation="EditorCaption"; hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _body.add_child(hint)
	terrain_summary=Label.new(); terrain_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; _body.add_child(terrain_summary)
	button("使用选中的地形块",func():
		terrain_ids=editor._selection_tools.records().filter(func(r):return r.has("terrain_mesh")).map(func(r):return r.uuid)
		_refresh_terrain_summary()
		message.text="已选 %d 块地形"%terrain_ids.size(),_body)
	settings=Form.new(); _body.add_child(settings)
	settings.build(Tool.schema(),Tool.defaults(),{"id":"河道名称（字母、数字、下划线）","width":"水面宽度（米）","bank_width":"河岸过渡宽度（米）","water_level":"水位（世界高度）","depth":"水下深度（米）","curved":"平滑中心线","natural_materials":"自然沙土 / 岩石河岸"})
	settings.fields.id.tooltip_text="此名称也是保存的河道 ID。编辑已有河道时保持不变；另建请使用上方“新建”。"
	settings.fields.id.text_changed.connect(func(_text):_refresh_actions())
	settings.group_fields([{"id":"appearance","label":"河岸与水下细节","fields":["bank_width","depth","curved","natural_materials"]}])
	Compact.apply(settings,{"id":"河道名称","width":"水面宽 (m)","water_level":"水位 (m)","bank_width":"河岸宽 (m)","depth":"水深 (m)","curved":"平滑中心线","natural_materials":"自然河岸材质"})
	var points_heading:=Label.new(); points_heading.text="中心线控制点"; points_heading.theme_type_variation="EditorHeading"; _body.add_child(points_heading)
	point_list=ItemList.new(); point_list.custom_minimum_size.y=112; _body.add_child(point_list)
	point_list.item_selected.connect(func(index):coordinates.update_values({"point":points[index]}))
	coordinates=Form.new(); _body.add_child(coordinates)
	coordinates.build({"properties":{"point":Tool.W.arr(Tool.T.S.number(-10000,10000),2,2)}},{"point":[0,0]},{"point":"中心线点（X、Z 米）"})
	coordinates.fields.point.get_child(1).prefix="Z"
	var point_actions:=HFlowContainer.new(); _body.add_child(point_actions)
	button("追加点",func():points.append(coordinates.values().point);refresh();point_list.select(points.size()-1),point_actions)
	button("替换选中点",replace_point,point_actions)
	button("删除选中点",func():
		var selected:=point_list.get_selected_items()
		if not selected.is_empty():points.remove_at(selected[0]);refresh(),point_actions)
	remove_button=button("删除河道并恢复河床",func():
		var result:=Tool.apply(editor,{"id":settings.values().id},false,true)
		report(result)
		if result.ok:new_river(); message.text="河道已删除，河床已恢复；可撤销",_body)
	remove_button.tooltip_text="删除整条河道并恢复它修改的河床；一次撤销可恢复"
	var footer:=VBoxContainer.new(); footer.name="RiverActions"; footer.add_theme_constant_override("separation",6); add_child(footer)
	var actions:=HBoxContainer.new(); footer.add_child(actions)
	button("校验",func():report(Tool.apply(editor,args(),true)),actions)
	apply_button=button("生成河道",func():
		var result:=Tool.apply(editor,args())
		if result.ok:_loaded_id=str(settings.values().id);settings.fields.id.editable=false
		report(result),actions)
	apply_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	message=Label.new(); message.name="RiverResult"; message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; footer.add_child(message)
	refresh_catalog(); _refresh_terrain_summary(); _refresh_actions()

func args()->Dictionary:return settings.values().merged({"terrain_ids":terrain_ids,"points":points})

func refresh()->void:
	point_list.clear()
	for index in points.size():point_list.add_item("%d · X %.2f / Z %.2f"%[index+1,points[index][0],points[index][1]])
	_refresh_terrain_summary()

func replace_point()->void:
	var selected:=point_list.get_selected_items()
	if selected.is_empty():return
	points[selected[0]]=coordinates.values().point;refresh();point_list.select(selected[0])

func button(text:String,action:Callable,parent:Node=null)->Button:
	var b:=Button.new(); b.text=text; b.pressed.connect(action); (parent if parent!=null else self).add_child(b); return b

func report(result:Dictionary)->void:
	message.text="河道方案完成" if result.ok else str(result.error)
	editor._report_result(result,"河道方案完成","河流")
	if result.ok:refresh_catalog()

func refresh_catalog(force:bool=false)->void:
	if river_picker==null:return
	var source:Variant=editor._doc.map_meta.get("terrain_rivers",[])
	# Authoring transactions replace metadata. Selection refreshes may run often;
	# they must not revalidate every persisted terrain sample. Explicit loads do.
	if not force and is_same(source,_catalog_source):
		_select_loaded(); _refresh_actions(); return
	_catalog_source=source
	var catalog:=Tool.catalog(editor)
	_catalog_valid=catalog.ok
	if not catalog.ok:
		_catalog=[]; _last_catalog=""; river_picker.clear(); river_picker.add_item("河道数据无效"); river_picker.disabled=true
		if message!=null:message.text=str(catalog.error)
		_refresh_actions(); return
	var fingerprint:=JSON.stringify(catalog.rivers)
	if fingerprint==_last_catalog:
		_select_loaded(); _refresh_actions(); return
	_last_catalog=fingerprint; _catalog=catalog.rivers
	river_picker.clear(); river_picker.disabled=false; river_picker.add_item("新建河道方案"); river_picker.set_item_metadata(0,"")
	for request:Dictionary in _catalog:
		river_picker.add_item("%s · %d 点 · 宽 %.1f m"%[request.id,request.points.size(),request.get("width",8.)]); river_picker.set_item_metadata(river_picker.item_count-1,request.id)
		if request.id==_loaded_id:river_picker.select(river_picker.item_count-1)
	river_picker.tooltip_text="选择已保存的河道即可载入；选择和浏览不会修改地图"
	_refresh_actions()

func _select_loaded()->void:
	if not _catalog_valid:return
	river_picker.select(0)
	for index in river_picker.item_count:
		if river_picker.get_item_metadata(index)==_loaded_id:river_picker.select(index);break

func _refresh_terrain_summary()->void:
	if terrain_summary!=null:terrain_summary.text="目标地形：%d 块 · 中心线：%d 点"%[terrain_ids.size(),points.size()]

func _refresh_actions()->void:
	if settings==null or apply_button==null:return
	var id:String=settings.fields.id.text
	var exists:=_catalog.any(func(request):return request.id==id)
	apply_button.text="更新河道" if exists else "生成河道"
	remove_button.disabled=not exists

func new_river()->void:
	var values:=Tool.defaults(); var suffix:=1
	while _catalog.any(func(request):return request.id==values.id):
		suffix+=1; values.id="natural_river_%d"%suffix
	_loaded_id=""; terrain_ids=[]; points=[]; settings.update_values(values); settings.fields.id.editable=true; river_picker.select(0); refresh(); _refresh_actions()
	message.text="新的河道方案：先选择地形，再添加中心线点"

func load_river(id:String)->bool:
	refresh_catalog(true)
	if not _catalog_valid:return false
	for request:Dictionary in _catalog:
		if request.id!=id:continue
		terrain_ids=request.terrain_ids.duplicate(); points=request.points.duplicate(true)
		var values:Dictionary=Tool.defaults()
		for key in values:values[key]=request.get(key,values[key])
		settings.update_values(values); settings.fields.id.editable=false; _loaded_id=id
		for index in river_picker.item_count:
			if river_picker.get_item_metadata(index)==id:river_picker.select(index);break
		refresh(); _refresh_actions(); message.text="已载入 %s，可修改中心线和参数后更新"%id; return true
	message.text="没有此名称的可编辑河道"; return false

func load_existing()->void:
	load_river(str(settings.values().id))

func load_selected()->void:
	refresh_catalog(true)
	if not _catalog_valid:return
	var selected:Array=editor._selection_tools.records().map(func(record):return str(record.uuid))
	var water_matches:Array=[]; var terrain_matches:Array=[]
	# Match persistent ownership metadata, never guess from names or positions.
	for layer:Dictionary in editor._doc.map_meta.get("terrain_rivers",[]):
		if layer.water.any(func(part):return part.id in selected):water_matches.append(layer.id)
		elif layer.terrains.any(func(part):return part.after.uuid in selected):terrain_matches.append(layer.id)
	var matches:Array=water_matches if not water_matches.is_empty() else terrain_matches
	if matches.size()==1:load_river(str(matches[0]));return
	message.text="选中内容关联多条河道，请从上方列表选择" if matches.size()>1 else "请选择已有河道的水面，或仅属于该河道的地形"
