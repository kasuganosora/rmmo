extends VBoxContainer
const W=preload("res://scripts/world3d/waterway_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor: Node3D
var host: VBoxContainer
var choice: OptionButton
var fields: VBoxContainer
var bridge_fields: VBoxContainer
var bridge_choice: OptionButton
var materials: Dictionary={}
var info: Label
var source_info: Label
var current: Dictionary={}
var preview: Dictionary={}
func setup(panel: VBoxContainer) -> void:
	host=panel; editor=host.editor
	var body: VBoxContainer=host.section("河道、河岸与石桥")
	host.note(body,"先选普通水平地面，再点选河道中心线。预览会检查开槽与现有物件冲突；应用后生成真实河槽、两岸及所选桥型。仅支持同标高平地，带手刷材质或事件的地面不能直接开槽。")
	choice=OptionButton.new(); body.add_child(choice); choice.item_selected.connect(func(_i):load_region())
	host.button(body,"新建河道",new_region)
	fields=Form.new(); body.add_child(fields)
	host.button(body,"使用当前选中的地面",use_selection)
	source_info=host.note(body,"")
	host.button(body,"点选河道中心线",func():host.report(editor._city.begin_waterway(float(fields.values().bank_height))))
	for role in ["bank","bed","bridge"]:
		host.note(body,{"bank":"河岸材质","bed":"河床材质","bridge":"桥面材质（旧式平桥同时用于栏杆）"}[role])
		var menu:=OptionButton.new(); menu.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(menu); materials[role]=menu
		preload("res://scripts/world_editor/material_choice.gd").bind_menu(menu,editor._material_panel,"原色")
		menu.item_selected.connect(func(_i):invalidate())
	host.note(body,"桥梁垂直穿过选定直线段，两端桥头与岸面齐平。段号从 0 起；0.5 表示该段中点。避开转角，净宽为桥宽减两侧 0.3 米栏杆。")
	host.note(body,"石桥主通航孔必须有 2 米净宽、距水面至少 2.5 米净高。此河道面板按填写的拱高校验；不足时请增加拱高、引道长度或水面落差。")
	bridge_choice=OptionButton.new(); body.add_child(bridge_choice); bridge_choice.item_selected.connect(func(i):bridge_form(current.bridges[i]))
	bridge_fields=Form.new(); body.add_child(bridge_fields)
	host.button(body,"新增桥梁",func():current.bridges.append(bridge_fields.values().merged({"id":"bridge_"+Crypto.new().generate_random_bytes(4).hex_encode()})); sync_bridges(); invalidate())
	host.button(body,"更新所选桥梁",func():if bridge_choice.item_count>0: current.bridges[bridge_choice.selected]=bridge_fields.values().merged({"id":current.bridges[bridge_choice.selected].id}); sync_bridges(); invalidate())
	host.button(body,"移除所选桥梁",func():if bridge_choice.item_count>0: current.bridges.remove_at(bridge_choice.selected); sync_bridges(); invalidate())
	host.button(body,"预览河道方案",show_preview)
	host.button(body,"应用河道方案",apply)
	host.button(body,"解除关联，保留现场",func():remove_region(true))
	host.button(body,"删除河道并恢复原地面",func():remove_region(false))
	info=host.note(body,""); new_region(); refresh()
func form() -> void:
	var schema:=W.settings_schema(); var values:=current.duplicate(true)
	for key in ["id","points","ground_ids","bridges","bank_material_id","bed_material_id","bridge_material_id"]: schema.properties.erase(key); values.erase(key)
	fields.build(schema,values,{"name":"河道名称","width":"河水宽度（米）","bank_width":"每侧岸宽（米）","bank_height":"地面标高（米）","water_drop":"水面低于岸顶（米）","depth":"水深（米）"})
	for control in fields.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v):invalidate())
		if control is LineEdit: control.text_changed.connect(func(_v):invalidate())
	for role in materials:
		preload("res://scripts/world_editor/material_choice.gd").choose(materials[role],str(current[role+"_material_id"]))
	source_info.text="挖河地面："+str(current.ground_ids)+"；中心线 %d 点"%current.points.size()
	sync_bridges()
func bridge_form(value: Dictionary={}) -> void:
	var schema:=W.bridge_schema(); schema.properties.erase("id"); schema.required=[]
	var values:={"segment":0,"t":.5,"width":5.0,"approach":3.0,"rail_height":1.1,"prefab_id":"stone_segmental","camber":0.0}; values.merge(value,true); values.erase("id")
	if not value.is_empty() and not value.has("prefab_id"): values.prefab_id="legacy_flat"
	var choices: Array=[{"id":"legacy_flat","name":"旧式平桥（兼容）"}]; choices.append_array(preload("res://scripts/world3d/bridge_data.gd").presets())
	bridge_fields.build(schema,values,{"segment":"河段编号（从 0 起）","t":"段内位置（0～1）","width":"桥梁总宽（米）","approach":"每端桥头长度（米）","rail_height":"栏杆高度（米）","prefab_id":"桥梁预制件","camber":"桥面拱高（米，0 为平直）"},{"prefab_id":choices})
func sync_bridges() -> void:
	bridge_choice.clear()
	for b in current.bridges: bridge_choice.add_item("%s · 第 %d 段 / %.2f"%[b.id,b.segment,b.t])
	bridge_form(current.bridges[0] if not current.bridges.is_empty() else {})
func new_region() -> void:
	current=W.defaults().merged({"id":"river_"+Crypto.new().generate_random_bytes(6).hex_encode(),"points":[],"ground_ids":[]}); form(); invalidate()
	if choice.item_count>0: choice.select(0)
func refresh() -> void:
	choice.clear(); choice.add_item("新河道（尚未生成）"); choice.set_item_metadata(0,"")
	for region in editor._waterways.regions():
		choice.add_item(region.settings.name); choice.set_item_metadata(choice.item_count-1,region.settings.id)
		if current.get("id")==region.settings.id: choice.select(choice.item_count-1)
	invalidate()
func load_region() -> void:
	if choice.selected==0: new_region(); return
	for region in editor._waterways.regions():
		if region.settings.id==choice.get_item_metadata(choice.selected): current=region.settings.duplicate(true); form(); invalidate(); return
func use_selection() -> void:
	current.ground_ids=Array(editor._inspector.selection); source_info.text="挖河地面："+str(current.ground_ids); invalidate()
func set_points(points: Array) -> Dictionary:
	if points.size()<2: return Data.fail("至少点选两个河道中心点")
	current.points=points.duplicate(true); source_info.text="挖河地面："+str(current.ground_ids)+"；中心线 %d 点"%points.size(); invalidate()
	return {"ok":true}
func request() -> Dictionary:
	var result:=current.merged(fields.values(),true)
	for role in materials: result[role+"_material_id"]=materials[role].get_item_metadata(materials[role].selected)
	return result
func show_preview() -> void:
	var result: Dictionary=editor._waterways.summary(request()); host.report(result)
	if not result.ok: invalidate(); info.text=result.error; return
	preview=result; editor._waterways.overlay_plan=result
	info.text="河长 %.1f 米 · 水面 %.1f 平方米\n%d 个构件 · %d 座桥；应用会替换选定地面的几何。"%[result.length,result.water_area,result.chunks,result.bridges.size()]
func apply() -> void:
	if preview.is_empty(): host.report(Data.fail("请先预览河道")); return
	host.report(editor._waterways.generate(request().merged({"plan_token":preview.plan_token})))
func remove_region(keep_objects: bool) -> void:
	var result: Dictionary=editor._waterways.remove(current.id,keep_objects); host.report(result)
	if result.ok: new_region(); refresh()
func invalidate() -> void:
	preview={}; editor._waterways.overlay_plan={}
	if info!=null: info.text="预览后应用；生成构件或挖河地面手改后会阻止重生成。"
