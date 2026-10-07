extends VBoxContainer
const Data=preload("res://scripts/world3d/city_layout.gd")
const Zones=preload("res://scripts/world3d/planning_zones.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var host: VBoxContainer
var editor: Node3D
var settings: VBoxContainer
var kerb_material_select:OptionButton
var material_select: OptionButton
var status: Label
var choice: OptionButton
var fields: VBoxContainer
var token:=""
var bridges: OptionButton
var network_status: Label

func setup(value: VBoxContainer) -> void:
	host=value; editor=host.editor
	var roads: VBoxContainer=host.section("生成道路铺面与路口")
	host.note(roads,"支持水平曲线和带平坦接驳的直线坡道，坡度最多 15%。河道桥梁先接入路网，再从桥头朝外绘路；接桥铺面偏移固定为 0.025 米。")
	host.button(roads,"拆分同层交叉点",func(): host.report(editor._roads.split()))
	settings=Form.new(); roads.add_child(settings)
	sync_settings(preload("res://scripts/world3d/road_plan.gd").defaults())
	material_select=OptionButton.new(); material_select.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; roads.add_child(material_select)
	preload("res://scripts/world_editor/material_choice.gd").bind_menu(material_select,editor._material_panel,"原色 · 不绑定材质","pack:default:paving/historic_cobble/material")
	kerb_material_select=OptionButton.new();roads.add_child(kerb_material_select)
	preload("res://scripts/world_editor/material_choice.gd").bind_menu(kerb_material_select,editor._material_panel,"选择路缘材质","pack:default:paving/automatic_limestone_kerb/material")
	host.note(roads,"自动路缘：只沿道路外露边界铺设；路口内部及分块接缝留空。启用后修改道路同步更新；同层交叉自动拆分接点。宽度占用道路内侧空间。")
	status=host.note(roads,"")
	host.button(roads,"预览铺面变化",preview)
	host.button(roads,"应用铺面方案",apply_surface)
	host.button(roads,"解除关联，保留实体路面",func(): host.report(editor._roads.detach()); token="")
	bridges=OptionButton.new(); roads.add_child(bridges)
	host.button(roads,"将所选河道桥梁接入路网",func():
		if bridges.item_count>0:
			var ref: Dictionary=bridges.get_item_metadata(bridges.selected); host.report(editor._connections.connect_bridge(ref.waterway_id,ref.bridge_id)))
	host.button(roads,"解除所选桥梁路网绑定",func():
		if bridges.item_count>0:
			var ref: Dictionary=bridges.get_item_metadata(bridges.selected)
			for edge in Data.resolve(editor._doc.map_meta).roads.edges:
				if edge.get("bridge_ref",{})==ref: host.report(editor._connections.disconnect_bridge(edge.id)); return
			host.report(Data.fail("所选桥梁尚未接入路网")))
	network_status=host.note(roads,"")
	host.button(roads,"检查路网连通与接地",func():
		var result: Dictionary=editor._connections.audit(); host.report(result)
		network_status.text="%d 个连通分量 · %d 个断头节点\n缺少水平承托：%s\n%s"%[result.components.size(),result.dead_end_nodes.size(),str(result.unsupported_nodes),"铺面可生成" if result.buildability.ok else result.buildability.error])
	var zones: VBoxContainer=host.section("禁建区与保留通道")
	host.note(zones,"点选多边形边界，Enter 闭合。隐藏仅关闭辅助线，约束仍生效。禁植区和保留通道会排除区域植被散布；不会自动清除已有植被。")
	choice=OptionButton.new(); zones.add_child(choice); choice.item_selected.connect(func(_i):fill_zone())
	fields=Form.new(); zones.add_child(fields)
	host.button(zones,"绘制新区域",func(): var z: Dictionary=fields.values(); z.id="zone_"+Crypto.new().generate_random_bytes(6).hex_encode(); z.locked=false; z.hidden=false; host.report(editor._city.begin_zone(z)))
	host.button(zones,"重绘所选边界",func(): var z:=selected(); if not z.is_empty(): z.merge(fields.values(),true); host.report(editor._city.begin_zone(z)))
	host.button(zones,"更新所选属性",func(): var z:=selected(); if not z.is_empty(): z.merge(fields.values(),true); host.report(editor._roads.zones({"expected_token":zone_token(),"zones":[z]})))
	host.button(zones,"删除所选区域",func(): var z:=selected(); if not z.is_empty(): host.report(editor._roads.zones({"expected_token":zone_token(),"remove":[z.id]})))
	host.button(zones,"提交绘制",func(): host.report(editor._city.finish_draw()))
	host.button(zones,"取消绘制",func(): host.report(editor._city.finish_draw(true)))
	fill_zone()

func args() -> Dictionary:
	var result: Dictionary=settings.values(); result.material_id=material_select.get_item_metadata(material_select.selected);result.kerb_material_id=kerb_material_select.get_item_metadata(kerb_material_select.selected); return result
func preview() -> void:
	var result: Dictionary=editor._roads.summary(args()); host.report(result)
	if result.ok:
		token=result.plan_token
		status.text="%.1f 平方米 · %d 块\n新增 %d / 更新 %d / 移除 %d / 保留 %d"%[result.area,result.chunks,result.diff.added,result.diff.updated,result.diff.removed,result.diff.unchanged]
	else: token=""; status.text=str(result.error)
func apply_surface() -> void:
	if token.is_empty(): status.text="请先预览铺面变化"; return
	var request:=args(); request.plan_token=token
	var result: Dictionary=editor._roads.generate(request); host.report(result)
	if result.ok: token=""
func refresh() -> void:
	var data:=Data.resolve(editor._doc.map_meta); var manifest: Dictionary=data.get("road_surface",{})
	var selected_bridge: Dictionary={} if bridges.item_count==0 else bridges.get_item_metadata(bridges.selected)
	bridges.clear()
	for region in data.get("waterways",[]):
		for b in region.settings.bridges:
			bridges.add_item(region.settings.name+" / "+b.id); bridges.set_item_metadata(bridges.item_count-1,{"waterway_id":region.settings.id,"bridge_id":b.id})
			if bridges.get_item_metadata(bridges.item_count-1)==selected_bridge: bridges.select(bridges.item_count-1)
	status.text="尚未生成铺面" if manifest.is_empty() else ("骨架已变更，请更新铺面" if manifest.graph_token!=Data.token(data.roads) else "铺面与骨架一致 · %d 块"%manifest.parts.size())
	if not manifest.is_empty():
		sync_settings(manifest.settings)
		preload("res://scripts/world_editor/material_choice.gd").choose(kerb_material_select,str(manifest.settings.get("kerb_material_id","pack:default:paving/automatic_limestone_kerb/material")))
		preload("res://scripts/world_editor/material_choice.gd").choose(material_select,str(manifest.settings.material_id))
	var id: String="" if choice.item_count==0 else str(choice.get_item_metadata(choice.selected)); choice.clear()
	for zone in data.get("zones",[]):
		choice.add_item(str(zone.get("name",zone.id))+ (" [锁]" if zone.get("locked",false) else "")+ (" [隐藏]" if zone.get("hidden",false) else "")); choice.set_item_metadata(choice.item_count-1,zone.id)
		if zone.id==id: choice.select(choice.item_count-1)
	fill_zone()
func sync_settings(value: Dictionary) -> void:
	var schema: Dictionary=preload("res://scripts/world3d/road_plan.gd").settings_schema(); schema.properties.erase("material_id")
	schema.properties.erase("kerb_material_id")
	var values:Dictionary=preload("res://scripts/world3d/road_plan.gd").defaults().merged(value,true); values.erase("material_id");values.erase("kerb_material_id")
	settings.build(schema,values,{"thickness":"铺面厚度（米）","lift":"高于地面（米）","clearance":"通行净空（米）","kerb_enabled":"自动路缘与道路同步更新","kerb_width":"路缘宽度（米）","kerb_height":"路缘高出路面（米）"})
func selected() -> Dictionary:
	return host.selected(Data.resolve(editor._doc.map_meta).get("zones",[]),choice)
func zone_token() -> String: return JSON.stringify(Data.resolve(editor._doc.map_meta).get("zones",[])).sha256_text()
func fill_zone() -> void:
	var schema:=Zones.schema(); schema.properties.erase("id"); schema.properties.erase("polygon")
	var value:={"name":"保留区域","purpose":"no_build","min_y":-2,"max_y":100,"locked":false,"hidden":false}; value.merge(selected(),true)
	if not selected().is_empty() and not selected().has("name"): value.name=""
	value.erase("id"); value.erase("polygon")
	fields.build(schema,value,{"name":"区域名称","purpose":"用途","min_y":"底部高度（米）","max_y":"顶部高度（米）","locked":"锁定边界","hidden":"隐藏辅助线"},{"purpose":[{"id":"no_build","name":"禁止生成建筑"},{"id":"reserved_passage","name":"保留通道"},{"id":"no_vegetation","name":"禁止散布植被"}]})
