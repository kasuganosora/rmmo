extends VBoxContainer
const Blocks=preload("res://scripts/world3d/city_blocks.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var host: VBoxContainer
var editor: Node3D
var choice: OptionButton
var fields: VBoxContainer
var info: Label
var picking: CheckButton
var preview: Dictionary={}
var view_blocks: Array=[]
var graph_token: String=""

func setup(panel: VBoxContainer) -> void:
	host=panel; editor=panel.editor
	var body: VBoxContainer=host.section("街区围合、临街地块与房屋")
	host.note(body,"识别闭合道路后选择街区，预览空地块房屋，再生成。绿色可生成；蓝色已关联；红色被占用或保留；灰色留待下一批。每批最多 16 栋。")
	host.button(body,"识别 / 刷新街区",scan)
	choice=OptionButton.new(); body.add_child(choice); choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	choice.item_selected.connect(func(_i): preview={}; editor._blocks.overlay_plan={})
	picking=CheckButton.new(); picking.text="在画布点选街区"; body.add_child(picking)
	fields=Form.new(); body.add_child(fields)
	var settings: Dictionary=Data.resolve(editor._doc.map_meta).get("block_layout",{}).get("settings",Blocks.defaults())
	fields.build(Blocks.settings_schema(),settings,{"lot_width":"临街地块宽（米）","lot_depth":"地块进深（米）","setback":"距路边退让（米）","gap":"地块间隔（米）","style":"建筑风格","seed":"随机方案种子","max_buildings":"本批栋数上限"},{"style":[{"id":"medieval","name":"中世纪"},{"id":"urban_village","name":"城中村"},{"id":"standard","name":"标准建筑"}]})
	var row:=HFlowContainer.new(); body.add_child(row)
	host.button(row,"预览方案",show_preview)
	host.button(row,"换一个方案",func(): fields.fields.seed.value=posmod(int(fields.fields.seed.value)+1,2147483647); show_preview())
	host.button(body,"生成空地块房屋",apply)
	host.button(body,"解除所选街区地块关联（保留房屋）",detach)
	info=host.note(body,"先识别街区。改变道路或地块尺寸后，应先解除旧地块关联；现有房屋继续作为障碍保留。")

func scan() -> void:
	var result: Dictionary=editor._blocks.catalog()
	if not result.ok: host.report(result); return
	view_blocks=result.blocks; graph_token=Data.token(Data.resolve(editor._doc.map_meta).roads)
	var previous: String="" if choice.item_count==0 else choice.get_item_metadata(choice.selected)
	choice.clear(); choice.add_item("全部闭合街区"); choice.set_item_metadata(0,"")
	for block in view_blocks:
		choice.add_item("街区 %d · %.0f m²%s"%[choice.item_count,block.area," [保护]" if block.protected else ""]); choice.set_item_metadata(choice.item_count-1,block.id)
		if block.id==previous: choice.select(choice.item_count-1)
	for id in result.orphaned_blocks:
		choice.add_item("旧街区（可解除关联） · "+id.right(8)); choice.set_item_metadata(choice.item_count-1,id)
	info.text="识别 %d 个街区，%d 条开放连接不围合。已有 %d 个地块关联。"%[view_blocks.size(),result.open_edges,result.bindings.size()]
	preview={}; editor._blocks.overlay_plan={}

func request() -> Dictionary:
	var args: Dictionary=fields.values()
	if choice.item_count>0 and not str(choice.get_item_metadata(choice.selected)).is_empty(): args.block_ids=[choice.get_item_metadata(choice.selected)]
	return args
func show_preview() -> void:
	var result: Dictionary=editor._blocks.summary(request())
	host.report(result)
	if not result.ok: preview={}; editor._blocks.overlay_plan={}; return
	preview=result; editor._blocks.overlay_plan=result
	var counts:={}
	for lot in result.lots: counts[lot.status]=int(counts.get(lot.status,0))+1
	info.text="%d 个临街地块 · 本批生成 %d 栋 · 保留已有 %d · 障碍 / 保留区 %d · 下一批 %d\n转角、窄地和无法接路的位置保持空白。"%[result.lots.size(),result.building_count,counts.get("retained",0)+counts.get("missing",0),counts.get("occupied",0)+counts.get("reserved",0)+counts.get("access_blocked",0),counts.get("pending",0)]
func apply() -> void:
	if preview.is_empty(): host.report(Data.fail("请先预览方案")); return
	var result: Dictionary=editor._blocks.generate(request().merged({"plan_token":preview.plan_token}))
	host.report(result)
	if result.ok: preview={}; editor._blocks.overlay_plan={}; scan()
func detach() -> void:
	var args:=request(); var ids: Array=args.get("block_ids",[])
	if ids.is_empty():
		for binding in Data.resolve(editor._doc.map_meta).get("block_layout",{}).get("lots",[]):
			if not ids.has(binding.block_id): ids.append(binding.block_id)
	if ids.is_empty(): host.report(Data.fail("没有地块关联")); return
	host.report(editor._blocks.detach(ids)); scan()

func pick(screen: Vector2) -> void:
	if graph_token!=Data.token(Data.resolve(editor._doc.map_meta).roads): scan()
	var best: Dictionary={}
	for block in view_blocks:
		var hit: Variant=Plane(Vector3.UP,float(block.height)).intersects_ray(editor._camera.project_ray_origin(screen),editor._camera.project_ray_normal(screen))
		if hit==null: continue
		if Geometry2D.is_point_in_polygon(Vector2(hit.x,hit.z),PackedVector2Array(Blocks.unpack(block.polygon))) and (best.is_empty() or block.area<best.area): best=block
	if best.is_empty(): return
	for i in choice.item_count:
		if choice.get_item_metadata(i)==best.id: choice.select(i); show_preview(); return

func invalidate() -> void:
	preview={}; editor._blocks.overlay_plan={}
	if info!=null and not view_blocks.is_empty(): info.text="地图已变化，请重新预览。"
