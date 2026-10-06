extends VBoxContainer
const Data=preload("res://scripts/world3d/city_layout.gd")
const Scatter=preload("res://scripts/world3d/vegetation_scatter.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor: Node3D
var host: VBoxContainer
var choice: OptionButton
var fields: VBoxContainer
var assets: ItemList
var search: LineEdit
var info: Label
var current: Dictionary={}
var preview: Dictionary={}
var selected_assets: Array=[]

func setup(panel: VBoxContainer) -> void:
	host=panel; editor=host.editor
	var body: VBoxContainer=host.section("区域植被散布")
	host.note(body,"选择树木 / 灌木 GLB，圈定有地面承托的水平区域。自动避让物件、道路、禁植区和保留通道。完整树冠留在边界内；素材风格取决于所选模型。")
	choice=OptionButton.new(); body.add_child(choice); choice.item_selected.connect(func(_i):load_region())
	host.button(body,"新建散布区域",new_region)
	fields=Form.new(); body.add_child(fields)
	search=LineEdit.new(); search.placeholder_text="搜索素材名称 / 分类"; body.add_child(search); search.text_changed.connect(func(_v):refresh_assets())
	assets=ItemList.new(); assets.select_mode=ItemList.SELECT_MULTI; assets.custom_minimum_size.y=135; body.add_child(assets)
	assets.multi_selected.connect(func(index,selected):
		var id: String=assets.get_item_metadata(index)
		if selected and not selected_assets.has(id): selected_assets.append(id)
		elif not selected: selected_assets.erase(id)
		invalidate())
	host.note(body,"Ctrl 多选，最多混合 8 种模型；搜索不会清空已选项。")
	host.button(body,"清空素材选择",func():selected_assets=[]; refresh_assets(); invalidate())
	host.button(body,"点选区域边界",func():host.report(editor._city.begin_scatter(float(fields.values().height))))
	host.button(body,"使用已选街区边界",use_block)
	var row:=HFlowContainer.new(); body.add_child(row)
	host.button(row,"预览散布",show_preview)
	host.button(row,"换一个方案",func():fields.fields.seed.value=posmod(int(fields.fields.seed.value)+1,2147483647); show_preview())
	host.button(body,"应用散布方案",apply)
	host.button(body,"解除关联，保留植被",func():remove_region(true))
	host.button(body,"删除区域及生成植被",func():remove_region(false))
	info=host.note(body,"")
	new_region(); refresh()

func form() -> void:
	var schema:=Scatter.settings_schema()
	var values:=current.duplicate(true)
	for key in ["id","polygon","asset_ids"]: schema.properties.erase(key); values.erase(key)
	fields.build(schema,values,{"name":"区域名称","height":"地面标高（米）","seed":"随机种子","count":"目标株数（最多 256）","spacing":"中心最小间隔（米）","scale_min":"最小缩放","scale_max":"最大缩放","boundary_margin":"边界留空（米）","collision":"运行时碰撞"})
	for control in fields.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v):invalidate())
		elif control is CheckButton: control.toggled.connect(func(_v):invalidate())
		elif control is LineEdit: control.text_changed.connect(func(_v):invalidate())
func new_region() -> void:
	current=Scatter.defaults().merged({"id":"grove_"+Crypto.new().generate_random_bytes(6).hex_encode(),"polygon":[]})
	selected_assets=[]; form(); refresh_assets(); invalidate()
	if choice!=null and choice.item_count>0: choice.select(0)
func refresh() -> void:
	if choice==null: return
	choice.clear(); choice.add_item("新区域（尚未生成）"); choice.set_item_metadata(0,"")
	for region in editor._scatter.regions():
		choice.add_item("%s · %d 株"%[region.settings.name,region.parts.size()]); choice.set_item_metadata(choice.item_count-1,region.settings.id)
		if current.get("id")==region.settings.id: choice.select(choice.item_count-1)
	invalidate()
func load_region() -> void:
	if choice.selected==0: new_region(); return
	for region in editor._scatter.regions():
		if region.settings.id==choice.get_item_metadata(choice.selected):
			current=region.settings.duplicate(true); selected_assets=current.asset_ids.duplicate(); form(); refresh_assets(); invalidate(); return
func refresh_assets() -> void:
	assets.clear()
	for entry in editor._scatter.entries(search.text).slice(0,200):
		assets.add_item(str(entry.label)); var i:=assets.item_count-1
		assets.set_item_metadata(i,entry.asset_path); assets.set_item_tooltip(i,str(entry.get("category",""))+"\n"+entry.asset_path)
		if selected_assets.has(entry.asset_path): assets.select(i,false)
func request() -> Dictionary:
	return fields.values().merged({"id":current.id,"polygon":current.polygon,"asset_ids":selected_assets.duplicate()})
func set_polygon(points: Array) -> Dictionary:
	var candidate:=request(); candidate.polygon=points
	# Geometry can be drawn before choosing assets; validation uses a placeholder only here.
	if candidate.asset_ids.is_empty(): candidate.asset_ids=["pending"]
	if not Scatter.valid_settings(candidate): return Data.fail("区域边界无效或过大，请调整后重试")
	current.polygon=points.duplicate(true); invalidate()
	editor._scatter.overlay_plan={"settings":candidate,"placements":[]}
	info.text="边界已选定（%d 个点），请选择素材并预览。"%points.size()
	return {"ok":true}
func use_block() -> void:
	var panel: VBoxContainer=host.block_panel
	if panel.choice.item_count==0: host.report(Data.fail("先识别并选择一个街区")); return
	var id: String=panel.choice.get_item_metadata(panel.choice.selected)
	for block in panel.view_blocks:
		if block.id==id: fields.fields.height.value=block.height; host.report(set_polygon(block.polygon)); return
	host.report(Data.fail("请选择单个有效街区"))
func show_preview() -> void:
	var result: Dictionary=editor._scatter.summary(request()); host.report(result)
	if not result.ok: invalidate(); info.text=result.error; return
	preview=result; editor._scatter.overlay_plan=result
	info.text="可生成 %d / %d 株，缺额 %d；已选 %d 种模型。\n边界 %d · 无承托 %d · 物件/保留区 %d · 道路 %d · 间隔 %d · 隔层 %d"%[result.count,result.requested,result.shortfall,selected_assets.size(),result.skipped.boundary,result.skipped.unsupported,result.skipped.occupied,result.skipped.road,result.skipped.spacing,result.skipped.floor]
func apply() -> void:
	if preview.is_empty(): host.report(Data.fail("请先预览植被散布")); return
	host.report(editor._scatter.generate(request().merged({"plan_token":preview.plan_token})))
func remove_region(keep_objects: bool) -> void:
	var result: Dictionary=editor._scatter.remove(current.get("id",""),keep_objects); host.report(result)
	if result.ok: new_region(); refresh()
func invalidate() -> void:
	preview={}; editor._scatter.overlay_plan={}
	if info!=null: info.text="请选择素材和边界，再预览。已有手改物件会阻止重生成；可先解除关联。"
