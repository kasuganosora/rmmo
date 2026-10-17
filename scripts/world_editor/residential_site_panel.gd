extends VBoxContainer
## Editable terrain recipe within the residential panel; no raw JSON workflow.
signal changed
const Site=preload("res://scripts/world_editor/residential_site_tools.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var host:VBoxContainer
var editor:Node3D
var plots:Array=[]
var nodes:Array=[]
var plot_list:VBoxContainer
var node_list:VBoxContainer
var ramp_enabled:CheckButton
var ramp_form:VBoxContainer
var ramp_body:VBoxContainer

func setup(owner_panel:VBoxContainer)->void:
	host=owner_panel;editor=host.editor
	host.note(self,"先列出矩形整地，可追加一条两端定高坡道。按列表顺序整地，最后处理坡道；整组检查最终地形、住宅与接路。最多 64 项，外围柔边不保证通行。")
	plot_list=VBoxContainer.new();add_child(plot_list)
	host.action(self,"新增矩形整地",func():add_plot();changed.emit())
	node_list=VBoxContainer.new();add_child(node_list)
	host.action(self,"调整一个已有道路节点",func():add_node();changed.emit())
	ramp_enabled=CheckButton.new();ramp_enabled.text="附加两端定高坡道";add_child(ramp_enabled)
	ramp_body=VBoxContainer.new();add_child(ramp_body);ramp_body.hide()
	ramp_form=Form.new();ramp_body.add_child(ramp_form)
	var properties:Dictionary=Site.schema().properties.terrain.properties.ramp
	var values:Dictionary={"id":first_terrain(),"start":[-3.,0.,-8.],"end":[-3.,0.,-16.],"width":3.,"blend_margin":2.,"cross_tiles":true}
	ramp_form.build(properties,values,{"id":"坡道地形","start":"起点 XYZ（米）","end":"终点 XYZ（米）","width":"净宽（米）","blend_margin":"外围柔边（米）","cross_tiles":"同步相邻地形接缝"},{"id":terrain_choices()})
	ramp_form.group_fields([{"id":"ramp","label":"两端定高坡道参数","expanded":true,"fields":values.keys()}])
	bind_fields(ramp_form)
	for key:String in ["start","end"]:
		host.action(ramp_body,("起点" if key=="start" else "终点")+"：取当前 X/Z 地面标高",sample.bind(key))
	ramp_enabled.toggled.connect(func(value):ramp_body.visible=value;changed.emit())

func terrain_choices()->Array:
	return editor._terrain.catalog().get("terrains",[]).map(func(r):return {"id":r.id,"name":r.name+" · "+r.id})

func first_terrain()->String:
	var rows:=terrain_choices()
	return str(rows[0].id) if not rows.is_empty() else ""

func bind_fields(form:VBoxContainer)->void:
	for control:Control in form.fields.values():
		if control is SpinBox:control.value_changed.connect(func(_v):changed.emit())
		elif control is HBoxContainer:
			for spin:SpinBox in control.get_children():spin.value_changed.connect(func(_v):changed.emit())
		elif control is CheckButton:control.toggled.connect(func(_v):changed.emit())
		elif control is OptionButton:control.item_selected.connect(func(_v):changed.emit())
		elif control is LineEdit:control.text_changed.connect(func(_v):changed.emit())

func add_plot(stroke:Dictionary={})->void:
	if plots.size()>=Site.MAX_STEPS:return
	var position:Array=host.form.values().position
	var values:Dictionary={"id":first_terrain(),"center":[position[0],position[2]],"plot_width":14.,"plot_depth":16.,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":position[1],"strength":1.,"blend_margin":2.,"cross_tiles":true}
	for key:String in values:
		if stroke.has(key):values[key]=stroke[key]
	if stroke.has("points"):values.center=stroke.points[0]
	var spec:Dictionary=Site.schema().properties.terrain.properties.strokes.items.duplicate(true)
	spec.properties.center=spec.properties.points.items
	var box:=VBoxContainer.new();plot_list.add_child(box)
	var fields:=Form.new();box.add_child(fields)
	fields.build(spec,values,{"id":"目标地形","center":"矩形中心 X/Z（米）","plot_width":"矩形宽度（米）","plot_depth":"矩形深度（米）","plot_yaw":"矩形旋转（度）","plot_grade":"局部 X/Z 坡度","target_height":"中心标高（米）","strength":"整平强度","blend_margin":"外围柔边（米）","cross_tiles":"同步相邻地形接缝"},{"id":terrain_choices()})
	fields.group_fields([{"id":"plot","label":"矩形整地 %d"%(plots.size()+1),"expanded":true,"fields":values.keys()}])
	fields.fields.center.get_child(1).prefix="Z";fields.fields.plot_grade.get_child(1).prefix="Z"
	bind_fields(fields);plots.append(fields)
	host.action(box,"删除此矩形",func():plots.erase(fields);box.queue_free();changed.emit())

func add_node(move:Dictionary={})->void:
	if nodes.size()>=64:return
	var rows:Array=Site.Data.resolve(editor._doc.map_meta).roads.nodes
	var first:Dictionary=rows[0] if not rows.is_empty() else {"id":"","position":[0.,0.,0.]}
	var values:Dictionary={"id":move.get("id",first.id),"position":move.get("position",first.position)}
	var spec:Dictionary=Site.Layout.schema().properties.road_nodes.items
	var box:=VBoxContainer.new();node_list.add_child(box);var fields:=Form.new();box.add_child(fields)
	fields.build(spec,values,{"id":"已有道路节点","position":"节点最终 XYZ（米）"},{"id":rows.map(func(r):return {"id":r.id,"name":r.id})})
	fields.fields.id.item_selected.connect(func(_i):
		var id:String=fields.values().id
		var current:Array=Site.Data.resolve(editor._doc.map_meta).roads.nodes.filter(func(n):return n.id==id)
		if not current.is_empty():fields.update_values({"id":id,"position":current[0].position})
	)
	bind_fields(fields);nodes.append(fields)
	host.action(box,"删除此节点调整",func():nodes.erase(fields);box.queue_free();changed.emit())

func request()->Dictionary:
	var strokes:Array=[]
	for fields:VBoxContainer in plots:
		var values:Dictionary=fields.values();values.points=[values.center];values.erase("center");values.mode="flatten";values.shape="rectangle";strokes.append(values)
	var result:Dictionary={"strokes":strokes}
	if not nodes.is_empty():
		result.road_nodes=nodes.map(func(f):return f.values())
		result.expected_road_token=Site.Data.token(Site.Data.resolve(editor._doc.map_meta).roads)
	if ramp_enabled.button_pressed:result.ramp=ramp_form.values()
	return result

func sample(key:String)->void:
	var values:Dictionary=ramp_form.values();var point:Array=values[key]
	var result:=Site.Ramp.sample(editor,{"id":values.id,"point":[point[0],point[2]]})
	if result.ok:values[key]=result.position;ramp_form.update_values(values);changed.emit()
	else:host.report(result)

func refresh_catalogs()->void:
	# Keep requested IDs (including removed ones) visible so refresh cannot
	# silently redirect an authored stamp to a different tile or road node.
	for fields:VBoxContainer in plots+[ramp_form]+nodes:
		if fields==null:continue
		var control:OptionButton=fields.fields.id
		var id:String=str(control.get_item_metadata(control.selected)) if control.selected>=0 else ""
		var rows:Array=terrain_choices() if fields not in nodes else Site.Data.resolve(editor._doc.map_meta).roads.nodes.map(func(n):return {"id":n.id,"name":n.id})
		control.clear()
		for row:Dictionary in rows:
			control.add_item(row.name);control.set_item_metadata(control.item_count-1,row.id)
			if row.id==id:control.select(control.item_count-1)
		if not rows.any(func(r):return r.id==id):control.add_item(id+"（请选择有效目标）");control.set_item_metadata(control.item_count-1,id);control.select(control.item_count-1)
