extends VBoxContainer
const F=preload("res://scripts/world3d/fortification_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor: Node3D
var host: VBoxContainer
var choice: OptionButton
var fields: VBoxContainer
var gate_fields: VBoxContainer
var gate_choice: OptionButton
var materials: Dictionary={}
var info: Label
var current: Dictionary={}
var preview: Dictionary={}
var tower_nodes: LineEdit
func setup(panel: VBoxContainer) -> void:
	host=panel; editor=host.editor
	var body: VBoxContainer=host.section("连续城墙与城门")
	host.note(body,"支持折线围城与圆形 / 椭圆城墙。环形可设中心和两轴半径，或点选包围范围两个对角；墙体沿弧线连续，自动布局按间距布塔并显示禁放圈；手动模式不受布局间距约束。可开启缓坡地基承托，地面须低于室内且不超过地基深度；城内侧门进入圆楼，经楼内旋梯到可行走楼顶和墙顶步道；不生成外置登墙梯。开放折线可选城内侧。")
	choice=OptionButton.new(); body.add_child(choice); choice.item_selected.connect(func(_i):load_region())
	host.button(body,"新建城墙",new_region)
	fields=Form.new(); body.add_child(fields)
	tower_nodes=LineEdit.new(); tower_nodes.placeholder_text="塔楼节点：留空每个拐点；例如 0,3,7；none 不布塔"; body.add_child(tower_nodes)
	tower_nodes.text_changed.connect(func(_v):invalidate())
	host.button(body,"点选路径 / 环形范围",func():host.report(editor._city.begin_fortification(float(fields.values().base_height))))
	for role in ["stone","trim","door","floor"]:
		host.note(body,{"floor":"圆楼石铺地面","stone":"墙身石材","trim":"压顶与拱圈石材","door":"城门木材"}[role])
		var menu:=OptionButton.new(); menu.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(menu); materials[role]=menu; menu.add_item("原色"); menu.set_item_metadata(0,"")
		for entry in editor._material_tool.library.entries(): menu.add_item(str(entry.material.name)); menu.set_item_metadata(menu.item_count-1,entry.material_id)
		menu.item_selected.connect(func(_i):invalidate())
	host.note(body,"折线城门用段号和比例；环形城门用角度：0° 东、90° 南、180° 西、270° 北，再随城墙旋转。切换形状后需更新或移除原城门方案。开度 0 关闭、1 打开。")
	gate_choice=OptionButton.new(); body.add_child(gate_choice); gate_choice.item_selected.connect(func(i):gate_form(current.gates[i]))
	gate_fields=Form.new(); body.add_child(gate_fields)
	host.button(body,"增加城门",func():current.gates.append(gate_fields.values().merged({"id":"gate_"+Crypto.new().generate_random_bytes(4).hex_encode()})); sync_gates(); invalidate())
	host.button(body,"更新所选城门方案",func():if gate_choice.item_count>0: current.gates[gate_choice.selected]=gate_fields.values().merged({"id":current.gates[gate_choice.selected].id}); sync_gates(); invalidate())
	host.button(body,"移除所选城门",func():if gate_choice.item_count>0: current.gates.remove_at(gate_choice.selected); sync_gates(); invalidate())
	host.button(body,"打开已生成的所选城门",func():set_gate(1))
	host.button(body,"关闭已生成的所选城门",func():set_gate(0))
	host.button(body,"预览城墙",show_preview); host.button(body,"应用城墙方案",apply)
	host.button(body,"烘焙现有城防为固定预制件",func():host.report(editor._fortifications.bake(current.id));refresh())
	host.button(body,"解除关联，保留现场",func():remove_region(true)); host.button(body,"删除城墙及城门",func():remove_region(false))
	info=host.note(body,""); new_region(); refresh()
func form() -> void:
	var schema:=F.settings_schema(); var values:=current.duplicate(true)
	tower_nodes.text="" if not current.has("tower_indices") else ("none" if current.tower_indices.is_empty() else ",".join(current.tower_indices.map(func(v):return str(int(v)))))
	for key in ["id","points","gates","stone_material_id","trim_material_id","door_material_id","floor_material_id","layout_version","tower_indices"]: schema.properties.erase(key); values.erase(key)
	fields.build(schema,values,{"tower_layout":"塔楼布局模式","tower_spacing":"自动布局目标间距（米，至少 50）","tower_door_open":"城楼内侧门开度（0～1）","arrow_slits":"城楼对外射击孔","wall_access":"圆楼内部楼梯与可行走楼顶","interior_side":"开放折线的城内侧","style":"城墙外观","name":"城墙名称","shape":"围墙形状","center_x":"环形中心 X","center_z":"环形中心 Z","radius_x":"环形 X 半径（相等为圆形）","radius_z":"环形 Z 半径","rotation":"环形朝向（度）","tower_count":"环形塔数（0：自动模式计算／手动模式 8 座）","closed":"折线闭合围城","base_height":"地面标高（米）","height":"墙高（米）","thickness":"墙厚（米）","terrain_foundation":"允许地基承托缓坡（地面不得穿入室内）","foundation":"地基下延（米）","corner_towers":"塔楼","battlements":"垛口与护墙"},{"tower_layout":[{"id":"automatic","name":"自动布局（应用间距禁区）"},{"id":"manual","name":"手动布置（不限制布局间距）"}],"interior_side":[{"id":"left","name":"路径左侧"},{"id":"right","name":"路径右侧"}],"style":[{"id":"plain","name":"基础墙体（旧版）"},{"id":"medieval_stone","name":"写实中世纪 · 石扶壁与压顶"}],"shape":[{"id":"path","name":"点选折线"},{"id":"ellipse","name":"圆形 / 椭圆围城"}]})
	for control in fields.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v):invalidate())
		elif control is CheckButton: control.toggled.connect(func(_v):invalidate())
		elif control is LineEdit: control.text_changed.connect(func(_v):invalidate())
		elif control is OptionButton: control.item_selected.connect(func(_i):gate_form(); invalidate())
	for role in materials:
		var menu: OptionButton=materials[role]; menu.select(0)
		for i in menu.item_count:
			if menu.get_item_metadata(i)==current[role+"_material_id"]: menu.select(i)
	sync_gates()
func gate_form(value: Dictionary={}) -> void:
	var schema:=F.gate_schema(5.0); schema.properties.erase("id"); schema.required=[]
	var values:={"kind":"land","width":5.0,"height":5.0,"open":1.0}; values.merge(value,true); values.erase("id")
	if fields.values().get("shape","path")=="ellipse":
		values.erase("segment"); values.erase("t"); values.angle=values.get("angle",270.0); schema.properties.erase("segment"); schema.properties.erase("t")
	else:
		values.erase("angle"); values.segment=values.get("segment",0); values.t=values.get("t",.5); schema.properties.erase("angle")
	gate_fields.build(schema,values,{"kind":"通道类型（land 城门／water 水关无门扇）","segment":"城墙段号（从 0 起）","t":"段内位置（0～1）","angle":"环上角度（度）","width":"门洞宽（米）","height":"门洞最低净高（≥ 5 米）","open":"城门开度（0～1）"})
func sync_gates() -> void:
	var selected_id: String="" if gate_choice.item_count==0 else str(gate_choice.get_item_metadata(gate_choice.selected))
	gate_choice.clear()
	for g in current.gates:
		gate_choice.add_item("%s · %s"%[g.id,("%.1f°"%g.angle if g.has("angle") else "第 %d 段"%g.segment)]); gate_choice.set_item_metadata(gate_choice.item_count-1,g.id)
		if g.id==selected_id: gate_choice.select(gate_choice.item_count-1)
	gate_form(current.gates[gate_choice.selected] if not current.gates.is_empty() else {})
func new_region() -> void:
	current=F.defaults().merged({"id":"wall_"+Crypto.new().generate_random_bytes(6).hex_encode(),"points":[],"style":"medieval_stone","height":7.5,"thickness":3.5,"arrow_slits":true,"wall_access":true,"tower_count":0,"tower_layout":"automatic"})
	for pair in [["floor_material_id","pack:default:paving/sandstone_floor/material"],["trim_material_id","pack:default:walls/stone_tiles_facade/material"],["stone_material_id","pack:default:walls/castle_rubble/material"],["door_material_id","pack:default:wood/worn_planks/material"]]:
		if not editor._material_tool.library.find(pair[1]).is_empty(): current[pair[0]]=pair[1]
	form(); invalidate()
	if choice.item_count>0: choice.select(0)
func refresh() -> void:
	choice.clear(); choice.add_item("新城墙（尚未生成）"); choice.set_item_metadata(0,"")
	for r in editor._fortifications.regions():
		choice.add_item(r.settings.name); choice.set_item_metadata(choice.item_count-1,r.settings.id)
		if current.get("id")==r.settings.id:
			choice.select(choice.item_count-1); current=F.defaults().merged(r.settings,true); form()
	invalidate()
func load_region() -> void:
	if choice.selected==0: new_region(); return
	for r in editor._fortifications.regions():
		if r.settings.id==choice.get_item_metadata(choice.selected): current=F.defaults().merged(r.settings,true); form(); invalidate(); return
func set_points(points: Array) -> Dictionary:
	if points.size()<2: return Data.fail("至少点选两个城墙中心点")
	if fields.values().get("shape","path")=="ellipse":
		if points.size()!=2: return Data.fail("环形范围只需两个对角点")
		var a:=Vector2(points[0][0],points[0][1]); var b:=Vector2(points[1][0],points[1][1]); var radius: Vector2=(b-a).abs()*.5
		if radius.x<15 or radius.y<15 or radius.x>200 or radius.y>200: return Data.fail("环形两轴半径须为 15～200 米")
		current.merge(fields.values(),true); current.center_x=(a.x+b.x)*.5; current.center_z=(a.y+b.y)*.5; current.radius_x=radius.x; current.radius_z=radius.y; current.rotation=0.0; current.closed=true; current.points=[]; form(); invalidate(); return {"ok":true}
	current.points=points.duplicate(true); invalidate(); return {"ok":true}
func request() -> Dictionary:
	var result:=current.merged(fields.values(),true); result.erase("layout_version")
	result.erase("tower_indices")
	if not tower_nodes.text.strip_edges().is_empty():
		result.tower_indices=[]
		if tower_nodes.text.strip_edges()!="none":
			for part in tower_nodes.text.split(","):
				result.tower_indices.append(int(part) if part.strip_edges().is_valid_int() else -1)
	elif current.has("tower_indices") and result.shape=="path":
		# Omitting an update field preserves the saved recipe. Send all nodes
		# explicitly when the user clears an existing selection in the UI.
		result.tower_indices=range(result.points.size())
	for role in materials: result[role+"_material_id"]=materials[role].get_item_metadata(materials[role].selected)
	return result
func show_preview() -> void:
	var result: Dictionary=editor._fortifications.summary(request()); host.report(result)
	if not result.ok:
		invalidate(); info.text=result.error
		if result.has("layout_zones"): editor._fortifications.overlay_plan=result
		return
	preview=result; editor._fortifications.overlay_plan=result; info.text="总长 %.1f 米 · %d 座塔楼 · %d 个构件 · %d 座城门"%[result.length,result.tower_count,result.count,result.gates.size()]
func apply() -> void:
	if preview.is_empty(): host.report(Data.fail("请先预览城墙")); return
	host.report(editor._fortifications.generate(request().merged({"plan_token":preview.plan_token})))
func set_gate(amount: float) -> void:
	if gate_choice.item_count==0: return
	var id: String=current.gates[gate_choice.selected].id
	var result: Dictionary=editor._fortifications.set_gate(current.id,id,amount); host.report(result)
	if result.ok: load_region()
func remove_region(keep: bool) -> void:
	var result: Dictionary=editor._fortifications.remove(current.id,keep); host.report(result)
	if result.ok: new_region(); refresh()
func invalidate() -> void:
	preview={}; editor._fortifications.overlay_plan={}
	if info!=null:
		info.text="点选中心线并预览，应用后成为固定预制件。结构不可拆改，城门仍可开合。"
		for r in editor._fortifications.regions():
			if r.settings.id==current.get("id","") and r.get("baked",false):info.text="已烘焙 · %d → %d 个构件。结构参数只供查看；城门仍可开合。"%[r.source_part_count,r.parts.size()]
