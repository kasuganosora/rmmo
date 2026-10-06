extends VBoxContainer
const Tools=preload("res://scripts/world_editor/rock_bank_tools.gd")
const Data=preload("res://scripts/world3d/rock_bank_mesh.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor
var fields
var point_fields
var point_list:ItemList
var choice:OptionButton
var points:Array=[]
var inner_heights:Array=[]
var inner_widths:Array=[]
var target:=""
var picking:=false
var preview:MeshInstance3D
func button(label:String,action:Callable)->void:
	var b:=Button.new();b.text=label;b.pressed.connect(action);add_child(b)
func setup(value)->void:
	editor=value;name="岩岸 / 岩壁"
	var note:=Label.new();note.text="按顺序指定岸顶折线；陆侧决定草顶朝向。点的 Y 是岸顶标高，内侧标高用于接回地形。预览不写入地图。";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
	choice=OptionButton.new();add_child(choice);choice.item_selected.connect(func(i):load_record(str(choice.get_item_metadata(i))))
	button("使用当前选中的岩岸",func():
		var rows:Array=editor._selection_tools.records()
		if rows.size()==1 and rows[0].has("rock_bank"):load_record(rows[0].uuid)
		else:editor._status.text="请只选择一段岩岸")
	button("新建岩岸草稿",func():target="";points=[];inner_heights=[];inner_widths=[];build_fields(Data.defaults());redraw_points();cancel())
	point_list=ItemList.new();point_list.custom_minimum_size.y=100;add_child(point_list);point_list.item_selected.connect(load_point)
	point_fields=Form.new();add_child(point_fields)
	point_fields.build({"properties":{"point":Data.S.vector(-100000,100000),"inner_y":Data.S.number(-1000,1000)}},{"point":[0,0,0],"inner_y":0.},{"point":"岸顶点（世界米）","inner_y":"陆侧接地标高"})
	button("追加坐标点",func():
		var p:Dictionary=point_fields.values();points.append(p.point);inner_heights.append(p.inner_y)
		if not inner_widths.is_empty():inner_widths.append(p.get("width",fields.values().cap_width))
		redraw_points();cancel())
	button("修改选中点",func():
		var selected:=point_list.get_selected_items()
		if selected.is_empty():return
		var p:Dictionary=point_fields.values();points[selected[0]]=p.point;inner_heights[selected[0]]=p.inner_y
		if p.has("width"):
			if inner_widths.is_empty():inner_widths=points.map(func(_p):return fields.values().cap_width)
			inner_widths[selected[0]]=p.width
		redraw_points();cancel())
	button("删除选中点",func():
		var selected:=point_list.get_selected_items()
		if selected.is_empty():return
		points.remove_at(selected[0]);inner_heights.remove_at(selected[0])
		if not inner_widths.is_empty():inner_widths.remove_at(selected[0])
		redraw_points();cancel())
	button("从地图拾取岸顶点（Esc 结束）",func():editor._finish_edits();editor._ground_draw.cancel();editor._terrain_brush.cancel();picking=true;editor._status.text="在地图依次点击岸顶；可在坐标栏调整高度。Esc 结束拾取")
	fields=Form.new();add_child(fields);build_fields(Data.defaults())
	button("所有点改用统一草顶宽度",func():inner_widths=[];cancel())
	button("预览岩岸",show_preview)
	button("保存岩岸",func():
		var result:=Tools.apply(editor,arguments())
		report(result)
		if result.ok:load_record(result.id))
	button("取消预览 / 拾取",cancel)
	button("删除当前岩岸",func():report(Tools.remove(editor,target)))
	visibility_changed.connect(func():if not is_visible_in_tree():cancel())
	refresh()
func build_fields(values:Dictionary)->void:
	var p:=Data.defaults().merged({"name":"可编辑岩岸"})
	for key in p:if values.has(key):p[key]=values[key]
	var choices:Array=[]
	for entry in editor._material_tool.library.entries():choices.append({"id":entry.material_id,"name":entry.material.name})
	for role in ["rock","top"]:
		var key:String=role+"_material_id";p[key]=values.get(key,"pack:default:terrain/beach_cliff/material" if role=="rock" else "pack:default:terrain/mossy_grass_vcjmej0s/material")
	fields.build(Data.schema(),p,{"name":"名称","height":"岩壁落差（米）","cap_width":"草顶宽度（米）","side":"陆侧","roughness":"岩面起伏（米）","seed":"岩面种子","water_level":"湿痕水位（米）","direction_mode":"草顶延伸方式","cap_angle":"固定方向（0° +X / 90° +Z）","rock_material_id":"岩壁 PBR","top_material_id":"草顶 PBR"},{"side":[{"id":"left","name":"沿路径左侧"},{"id":"right","name":"沿路径右侧"}],"direction_mode":[{"id":"normal","name":"垂直于岸线"},{"id":"fixed","name":"固定世界方向"}],"rock_material_id":choices,"top_material_id":choices})
func load_point(i:int)->void:
	point_fields.build({"properties":{"point":Data.S.vector(-100000,100000),"inner_y":Data.S.number(-1000,1000),"width":Data.S.number(.25,16)}},{"point":points[i],"inner_y":inner_heights[i],"width":inner_widths[i] if not inner_widths.is_empty() else fields.values().cap_width},{"point":"岸顶点（世界米）","inner_y":"陆侧接地标高","width":"此点草顶宽度（米）"})
func redraw_points()->void:
	point_list.clear()
	for i in points.size():point_list.add_item("%d · %.2f, %.2f, %.2f"%[i+1,points[i][0],points[i][1],points[i][2]])
func load_record(id:String)->void:
	var record:Dictionary=editor._doc._find(id)
	if not record.has("rock_bank"):return
	cancel();target=id;var values:=Tools.recipe(record);points=values.points.duplicate(true);inner_heights=values.inner_heights.duplicate();inner_widths=values.get("inner_widths",[]).duplicate()
	for role in ["rock","top"]:
		for entry in editor._material_tool.library.entries():
			if entry.material==record.rock_bank_materials[role]:values[role+"_material_id"]=entry.material_id;break
	build_fields(values);redraw_points()
func arguments()->Dictionary:
	var args:Dictionary=fields.values();args.points=points.duplicate(true);args.inner_heights=inner_heights.duplicate()
	if not inner_widths.is_empty():args.inner_widths=inner_widths.duplicate()
	if not target.is_empty():args.id=target
	return args
func report(result:Dictionary)->void:editor._status.text="岩岸操作完成" if result.ok else str(result.error)
func refresh()->void:
	cancel()
	if choice==null:return
	choice.clear()
	for row in Tools.catalog(editor).rock_banks:
		choice.add_item(row.name);choice.set_item_metadata(choice.item_count-1,row.id)
		if row.id==target:choice.select(choice.item_count-1)
	choice.disabled=choice.item_count==0
func cancel()->void:
	picking=false
	if is_instance_valid(preview):preview.queue_free()
	preview=null
func show_preview()->void:
	cancel();var result:=Tools.plan(editor._doc,arguments(),editor._material_tool.library,Callable(editor,"_record_editable"),func(r):return editor._authoring.Settings.contains(r,editor._authoring.settings))
	report(result)
	if not result.ok:return
	preview=MeshInstance3D.new();preview.mesh=Data.mesh(result.record);preview.position=Data.vec(result.record.position);editor.add_child(preview)
func input(event:InputEvent)->bool:
	if not picking:return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel();return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and editor._canvas.get_global_rect().has_point(event.position):
		if event.pressed:
			var point:Vector3=editor._ground_draw.pick(event.position-editor._canvas.global_position)
			if point.is_finite():
				points.append(Data.arr(point));inner_heights.append(point.y)
				if not inner_widths.is_empty():inner_widths.append(fields.values().cap_width)
				redraw_points()
		return true
	return false
