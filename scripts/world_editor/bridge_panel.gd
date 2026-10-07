extends VBoxContainer
const D=preload("res://scripts/world3d/bridge_data.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var host: VBoxContainer
var editor: Node3D
var fields: VBoxContainer
var presets: OptionButton
var info: Label
var name_field: LineEdit
var materials: Dictionary={}
var preview: Dictionary={}
var current_id: String
var road_edge_id:=""
var road_edges: OptionButton
func setup(panel: VBoxContainer) -> void:
	host=panel; editor=host.editor
	var body: VBoxContainer=host.section("写实石桥 · 预制件生成")
	host.note(body,"选择桥型，在两岸点选桥头；按长度排列石拱、桥墩与桥栏。拱高为 0 时桥面平直，两端始终保持同高。应用后成为固定网格预制件，加载时不重建拱孔；桥整体选取、移动和复制。")
	presets=OptionButton.new(); presets.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(presets); presets.item_selected.connect(func(_i):invalidate())
	road_edges=OptionButton.new(); road_edges.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(road_edges)
	host.button(body,"读取道路桥梁 / 转换旧桥面",load_road)
	host.note(body,"选择已有桥梁道路后，应用时同时裁掉桥下旧路板并保留引道与铺装。应用后桥型、拱高、深度和材质即固定；参数只供查看，新桥仍可在预览阶段调整。")
	fields=Form.new(); body.add_child(fields)
	host.button(body,"点选两岸桥头",func():host.report(editor._city.begin_bridge(float(fields.values().start[1]))))
	host.button(body,"读取选中的程序桥梁",load_selection)
	host.button(body,"烘焙此桥为固定预制件",func():host.report(editor._bridges.bake(current_id));invalidate())
	for role in ["deck","masonry","trim"]:
		host.note(body,{"deck":"桥面铺装","masonry":"桥身砌石","trim":"拱券 / 压顶"}[role])
		var menu:=OptionButton.new(); body.add_child(menu); materials[role]=menu; menu.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		preload("res://scripts/world_editor/material_choice.gd").bind_menu(menu,editor._material_panel,"跟随预制件 / 已有材质")
		menu.item_selected.connect(func(_i):invalidate())
	host.button(body,"预览实际石桥外观",show_preview)
	host.button(body,"应用桥梁",apply)
	host.button(body,"取消预览 / 新建下一座",new_bridge)
	name_field=LineEdit.new(); name_field.placeholder_text="自定义桥型名称"; body.add_child(name_field)
	host.button(body,"保存此桥型为预制件",save_prefab)
	info=host.note(body,""); refresh(); new_bridge()
func refresh() -> void:
	var previous: String="" if presets.item_count==0 else presets.get_item_metadata(presets.selected)
	presets.clear()
	for p in editor._bridges.library.entries():
		presets.add_item(p.name); presets.set_item_metadata(presets.item_count-1,p.id)
		if p.id==previous: presets.select(presets.item_count-1)
	var selected: String="" if road_edges.item_count==0 else road_edges.get_item_metadata(road_edges.selected)
	road_edges.clear()
	for edge in preload("res://scripts/world3d/city_layout.gd").resolve(editor._doc.map_meta).roads.edges:
		if edge.kind!="bridge" or edge.has("bridge_ref") or edge.has("controls"): continue
		road_edges.add_item(edge.get("name",edge.id)+(" · 已接石桥" if edge.has("stone_bridge") else " · 旧桥面")); road_edges.set_item_metadata(road_edges.item_count-1,edge.id)
		if edge.id==selected: road_edges.select(road_edges.item_count-1)
func build(values: Dictionary) -> void:
	values=values.duplicate(true); if not values.has("auto_clearance"): values.auto_clearance=true
	fields.build(D.request_schema(),values,{"start":"桥头 A（世界坐标，米）","end":"桥头 B（世界坐标，米）","width":"桥梁总宽（米）","depth":"桥墩向下深度（米）","camber":"桥面拱高（米，0 为平直）","arches":"拱孔数（0 自动）","auto_clearance":"按实际水位自动抬拱（主孔净高 ≥ 2.5 米 / 净宽 2 米）"})
	for control in fields.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v):invalidate())
		if control is CheckButton: control.toggled.connect(func(_v):invalidate())
		if control is HBoxContainer:
			for spin in control.get_children(): spin.value_changed.connect(func(_v):invalidate())
func new_bridge() -> void:
	road_edge_id=""
	current_id="bridge_"+Crypto.new().generate_random_bytes(6).hex_encode()
	build({"start":[-12,0,0],"end":[12,0,0],"width":6.,"depth":5.,"camber":0.,"arches":0})
	for menu in materials.values(): menu.select(0)
	invalidate()
func set_points(points: Array) -> Dictionary:
	if points.size()!=2: return {"ok":false,"error":"桥梁需要恰好两个桥头点"}
	var values: Dictionary=fields.values(); values.start=points[0]; values.end=points[1]; build(values); invalidate()
	return {"ok":true}
func request() -> Dictionary:
	var args: Dictionary=fields.values().merged({"id":current_id,"prefab_id":presets.get_item_metadata(presets.selected)})
	if not road_edge_id.is_empty(): args.road_edge_id=road_edge_id
	for role in materials:
		var id: String=materials[role].get_item_metadata(materials[role].selected)
		if not id.is_empty(): args[role+"_material_id"]=id
	return args
func show_preview() -> void:
	preview=editor._bridges.show_preview(request()); host.report(preview)
	if not preview.ok: info.text=preview.error; preview={}; return
	info.text="%.1f 米 · %d 孔 · 净宽 %.1f 米\n拱高 %.2f 米 · 最大坡度 %.1f%%\n一体网格 / 3 材质，确认外观后应用。"%[preview.length,preview.arches,preview.clear_width,preview.camber,preview.max_grade*100]
	if not road_edge_id.is_empty(): info.text+="\n保留道路连接；裁切 %d 块旧桥面。"%preview.trimmed_roads.size()
	if preview.navigation.applicable: info.text+="\n主通航孔：净高 %.2f 米 / 净宽 %.1f 米，按实际水位。"%[preview.navigation.clearance,preview.navigation.width]
func apply() -> void:
	if preview.is_empty(): host.report({"ok":false,"error":"请先预览桥梁"}); return
	host.report(editor._bridges.generate(request().merged({"plan_token":preview.plan_token})))
	invalidate()
func load_selection() -> void:
	var ids: Array=Array(editor._inspector.selection)
	if ids.size()!=1: host.report({"ok":false,"error":"请选择一座程序桥梁"}); return
	var r: Dictionary=editor._doc._find(ids[0])
	if not r.has("bridge_mesh"): host.report({"ok":false,"error":"所选物件不是程序桥梁"}); return
	load_record(r)
func load_record(r: Dictionary) -> void:
	road_edge_id=""
	for e in preload("res://scripts/world3d/city_layout.gd").resolve(editor._doc.map_meta).roads.edges:
		if e.get("stone_bridge",{}).get("id","")==r.uuid: road_edge_id=e.id
	current_id=r.uuid; var d: Dictionary=r.bridge_mesh
	var transform:=Transform3D(Basis.from_euler(Vector3(r.rotation[0],r.rotation[1],r.rotation[2])*PI/180).scaled(Vector3(r.size[0],r.size[1],r.size[2])),Vector3(r.position[0],r.position[1],r.position[2]))
	build({"start":D_vec(transform*Vector3(-d.length*.5,0,0)),"end":D_vec(transform*Vector3(d.length*.5,0,0)),"width":d.width*r.size[2],"depth":d.depth*r.size[1],"camber":d.camber*r.size[1],"arches":d.arches})
	for i in presets.item_count:
		if presets.get_item_metadata(i)==d.prefab_id: presets.select(i)
	# Loading another bridge must not carry over a pending material choice.
	# The shared operation retains this record's existing materials by default.
	for menu in materials.values(): menu.select(0)
	invalidate()
func load_road() -> void:
	if road_edges.item_count==0: host.report({"ok":false,"error":"先在道路骨架中绘制桥梁类型的直线路段"}); return
	var data:=preload("res://scripts/world3d/city_layout.gd").resolve(editor._doc.map_meta); var id: String=road_edges.get_item_metadata(road_edges.selected)
	var found: Array=data.roads.edges.filter(func(e):return e.id==id)
	if found.is_empty(): refresh(); return
	var edge: Dictionary=found[0]
	if edge.has("stone_bridge"):
		var record: Dictionary=editor._doc._find(edge.stone_bridge.id)
		if record.is_empty(): host.report({"ok":false,"error":"绑定的桥梁构件缺失，请先撤销删除"}); return
		load_record(record); return
	var nodes:={}
	for n in data.roads.nodes: nodes[n.id]=n
	var a:=Vector3(nodes[edge.from].position[0],nodes[edge.from].position[1]+.025,nodes[edge.from].position[2]); var b:=Vector3(nodes[edge.to].position[0],nodes[edge.to].position[1]+.025,nodes[edge.to].position[2]); var inset:=minf(12,a.distance_to(b)*.15); var direction:=(b-a).normalized()
	road_edge_id=id; current_id="stone_"+id
	build({"start":D_vec(a+direction*inset),"end":D_vec(b-direction*inset),"width":maxf(edge.width_start,edge.width_end)+1.2,"depth":5.,"camber":.6,"arches":0})
	for menu in materials.values(): menu.select(0)
	invalidate()
func save_prefab() -> void:
	var result: Dictionary=editor._bridges.save_prefab(current_id,name_field.text); host.report(result)
	if result.ok: refresh()
func invalidate() -> void:
	preview={}; editor._bridges.clear_preview()
	if info!=null: info.text="预览不修改地图；调整参数后重新预览。"
static func D_vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
