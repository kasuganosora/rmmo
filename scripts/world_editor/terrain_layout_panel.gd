extends VBoxContainer
## Editable draft for one final-state terrain/road transaction.
const Tools=preload("res://scripts/world_editor/terrain_layout_tools.gd")
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const City=preload("res://scripts/world3d/city_layout.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
const Compact=preload("res://scripts/world_editor/terrain_form_layout.gd")
var editor:Node3D
var terrain_panel:VBoxContainer
var plot_form:VBoxContainer
var center_form:VBoxContainer
var node_form:VBoxContainer
var plots:ItemList
var node_changes:ItemList
var nodes:OptionButton
var result_label:Label
var strokes:Array=[]
var road_nodes:Array=[]
var road_token:=""
var diagnostics:VBoxContainer
var document_id:=0

func label(text:String)->Label:
	var item:=Label.new();item.text=text;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(item);return item
func button(text:String,action:Callable)->void:
	var item:=Button.new();item.text=text;item.pressed.connect(action);add_child(item)
func setup(value:Node3D,owner_panel:VBoxContainer)->void:
	editor=value;terrain_panel=owner_panel;add_theme_constant_override("separation",8)
	label("组合平台、接坡与道路移位，统一检查最终布局。草案尚未改变地图；应用后可一次撤销。")
	center_form=Form.new();add_child(center_form)
	center_form.build(City.object({"center":{"type":"array","items":{"type":"number","minimum":-100000,"maximum":100000},"minItems":2,"maxItems":2}}),{"center":[0.,0.]},{"center":"整坡中心（世界 X / Z 米）"})
	center_form.fields.center.get_child(1).prefix="Z"
	button("中心取当前视图位置",func():center_form.update_values({"center":[editor._orbit_center.x,editor._orbit_center.z]}))
	plot_form=Form.new();add_child(plot_form)
	plot_form.build(Terrain.stroke_schema(),{"plot_width":10.,"plot_depth":14.,"plot_yaw":0.,"target_height":0.,"plot_grade":[0.,0.],"blend_margin":3.,"strength":1.,"cross_tiles":true},{"plot_width":"宽度（米）","plot_depth":"长度（米）","plot_yaw":"转向（度）","target_height":"中心标高（米）","plot_grade":"局部 X / Z 坡度（0.1 = 10%）","blend_margin":"柔和过渡（米）","strength":"整坡强度","cross_tiles":"跨相邻地形同步边界"})
	plot_form.fields.plot_grade.get_child(1).prefix="Z";plot_form.fields.strength.max_value=1.
	Compact.apply(plot_form,{"plot_width":"宽度 (m)","plot_depth":"长度 (m)","plot_yaw":"转向 (°)","target_height":"中心标高 (m)","blend_margin":"柔边 (m)","strength":"强度","cross_tiles":"跨块同步边界"})
	button("添加整坡区域（使用上方所选地形）",func():_put_plot(false))
	button("更新选中区域",func():_put_plot(true))
	plots=ItemList.new();plots.custom_minimum_size.y=90;add_child(plots);plots.item_selected.connect(_load_plot)
	button("删除选中区域",func():
		var chosen:=plots.get_selected_items()
		if not chosen.is_empty():strokes.remove_at(chosen[0]);_refresh_draft())
	label("需要一起移动的道路节点（可选）")
	nodes=OptionButton.new();nodes.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;add_child(nodes);nodes.item_selected.connect(func(_i):_load_node())
	node_form=Form.new();add_child(node_form)
	node_form.build(City.object({"position":City.S.vector(-100000,100000)}),{"position":[0.,0.,0.]},{"position":"节点最终位置（世界 X / Y / Z 米）"})
	button("加入 / 更新道路移位",_put_node)
	node_changes=ItemList.new();node_changes.custom_minimum_size.y=70;add_child(node_changes)
	node_changes.item_selected.connect(func(i):
		for n in nodes.item_count:
			if nodes.get_item_metadata(n)==road_nodes[i].id:nodes.select(n);break
		node_form.update_values({"position":road_nodes[i].position}))
	button("删除选中道路移位",func():
		var chosen:=node_changes.get_selected_items()
		if not chosen.is_empty():road_nodes.remove_at(chosen[0]);_refresh_draft())
	button("检查最终布局",func():_execute(false))
	button("应用联合调整",func():_execute(true))
	button("清空草案",clear_draft)
	result_label=label("")
	diagnostics=preload("res://scripts/world_editor/diagnostic_panel.gd").new();add_child(diagnostics);diagnostics.setup(editor)
	refresh()

func _pin()->void:
	if road_token.is_empty():road_token=City.token(City.resolve(editor._doc.map_meta).roads)
func _put_plot(replace:bool)->void:
	if terrain_panel.selected().is_empty():result_label.text="请先在上方选择地形。";return
	var chosen:=plots.get_selected_items()
	if replace and chosen.is_empty():result_label.text="请先选择要更新的整坡区域。";return
	if not replace and strokes.size()>=16:result_label.text="一组最多 16 个整坡区域。";return
	_pin()
	var stroke:Dictionary=plot_form.values()
	stroke.merge({"id":terrain_panel.selected(),"mode":"flatten","shape":"rectangle","points":[center_form.values().center]},true)
	if replace:strokes[chosen[0]]=stroke
	else:strokes.append(stroke)
	_refresh_draft()
func _load_plot(index:int)->void:
	var stroke:Dictionary=strokes[index]
	terrain_panel.refresh(stroke.id)
	center_form.update_values({"center":stroke.points[0]})
	var values:Dictionary=plot_form.values()
	for key in values:values[key]=stroke[key]
	plot_form.update_values(values)
func _load_node()->void:
	if nodes.selected<0:return
	var id:=str(nodes.get_item_metadata(nodes.selected))
	for node:Dictionary in road_nodes+City.resolve(editor._doc.map_meta).roads.nodes:
		if node.id==id:node_form.update_values({"position":node.position});return
func _put_node()->void:
	if nodes.selected<0:result_label.text="当前没有道路节点。";return
	_pin()
	var node:Dictionary={"id":str(nodes.get_item_metadata(nodes.selected)),"position":node_form.values().position}
	for i in road_nodes.size():
		if road_nodes[i].id==node.id:road_nodes[i]=node;_refresh_draft();return
	if road_nodes.size()>=64:result_label.text="一组最多移动 64 个道路节点。";return
	road_nodes.append(node);_refresh_draft()
func request()->Dictionary:
	var args:Dictionary={"strokes":strokes.duplicate(true)}
	if not road_nodes.is_empty():args.road_nodes=road_nodes.duplicate(true);args.expected_road_token=road_token
	return args
func _execute(commit:bool)->void:
	editor._finish_edits()
	var result:Dictionary=Tools.apply(editor,request()) if commit else Tools.preview(editor,request())
	result=editor._diagnostics.explain(result,"apply_terrain_layout" if commit else "preview_terrain_layout");diagnostics.display(result)
	if result.get("ok",false):
		if commit:clear_draft();terrain_panel.refresh()
		result_label.text="联合调整已应用，可一次撤销。" if commit else "最终布局检查通过，地图尚未修改。"
	else:result_label.text=str(result.get("error","联合调整失败"))
	editor._report_result(result,"联合整坡已应用" if commit else "最终布局检查通过","联合整坡")
func clear_draft()->void:
	strokes.clear();road_nodes.clear();road_token="";_refresh_draft()
	if result_label!=null:result_label.text="草案已清空。"
	if diagnostics!=null:diagnostics.display({})
func _refresh_draft()->void:
	if strokes.is_empty() and road_nodes.is_empty():road_token=""
	plots.clear();node_changes.clear()
	for i in strokes.size():
		var p:Dictionary=strokes[i]
		plots.add_item("%d · X %.2f / Z %.2f · 标高 %.2f"%[i+1,p.points[0][0],p.points[0][1],p.target_height])
	for node:Dictionary in road_nodes:node_changes.add_item("%s → %.2f, %.2f, %.2f"%[node.id,node.position[0],node.position[1],node.position[2]])
func refresh()->void:
	if nodes==null:return
	if document_id!=editor._doc.get_instance_id():document_id=editor._doc.get_instance_id();clear_draft()
	var selected_id:=str(nodes.get_item_metadata(nodes.selected)) if nodes.selected>=0 else ""
	nodes.clear()
	for node:Dictionary in City.resolve(editor._doc.map_meta).roads.nodes:
		nodes.add_item(str(node.get("name",node.id))+" · "+str(node.id));nodes.set_item_metadata(nodes.item_count-1,node.id)
		if node.id==selected_id:nodes.select(nodes.item_count-1)
	nodes.disabled=nodes.item_count==0;_load_node()
