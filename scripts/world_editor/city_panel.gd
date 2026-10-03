extends VBoxContainer
const Data = preload("res://scripts/world3d/city_layout.gd")
const Form = preload("res://scripts/world_editor/settings_form.gd")
var city: RefCounted
var editor: Node3D
var overview: Label
var reference: VBoxContainer
var reference_info: Label
var bookmarks: OptionButton
var bookmark_name: LineEdit
var road_form: VBoxContainer
var nodes: OptionButton
var edges: OptionButton
var node_form: VBoxContainer
var edge_form: VBoxContainer
var curve: CheckButton
var controls: VBoxContainer
var diagnostics: Label
var editing_section: VBoxContainer
var road_surface_panel: VBoxContainer
var block_panel: VBoxContainer
var scatter_panel: VBoxContainer
var waterway_panel: VBoxContainer
var bridge_panel: VBoxContainer
var fortification_panel: VBoxContainer
var tab_index := 9

func button(parent: Node, label_: String, action: Callable) -> Button:
	var item:=Button.new(); item.text=label_; item.pressed.connect(action); parent.add_child(item); return item
func note(parent: Node, text_: String) -> Label:
	var item:=Label.new(); item.text=text_; item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(item); return item
func section(title: String) -> VBoxContainer:
	var toggle:=Button.new(); toggle.text="▸ " + title; toggle.toggle_mode=true; toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT; add_child(toggle)
	var body:=VBoxContainer.new(); body.add_theme_constant_override("separation",6); add_child(body); body.hide(); toggle.toggled.connect(func(value):
		body.visible=value
		toggle.text=("▾ " if value else "▸ ") + title
	)
	return body
func setup(host: Node3D) -> void:
	editor=host; city=host._city; city.panel=self; add_theme_constant_override("separation",8)
	add_theme_constant_override("margin_left",8)
	note(self,"标定底图、绘制道路并生成铺面，再识别街区、预览临街地块并分批生成房屋。骨架修改后需更新路面。")
	var row:=HFlowContainer.new(); add_child(row)
	button(row,"正交俯视",func(): report(city.set_camera({"projection":"top"})))
	button(row,"透视",func(): report(city.set_camera({"projection":"perspective"})))
	button(row,"适配全图",func(): report(city.focus({"target":"all","projection":"top"})))
	button(row,"聚焦选择",func(): report(city.focus({"target":"selection"})))
	overview=note(self,"")
	var views:=section("区域定位与视图书签")
	var region:=Form.new(); views.add_child(region)
	region.build(Data.object({"from":Data.S.vector(-100000,100000),"to":Data.S.vector(-100000,100000)}),{"from":[-600,0,-600],"to":[600,0,600]},{"from":"区域起点（米）","to":"区域终点（米）"})
	button(views,"定位此区域",func(): report(city.focus(region.values().merged({"target":"region","projection":"top"}))))
	bookmark_name=LineEdit.new(); bookmark_name.placeholder_text="书签名，例如：北城门"; views.add_child(bookmark_name)
	button(views,"收藏当前视角",func(): report(city.bookmark({"name":bookmark_name.text})))
	bookmarks=OptionButton.new(); views.add_child(bookmarks)
	var view_actions:=HBoxContainer.new(); views.add_child(view_actions)
	button(view_actions,"跳转",func(): if bookmarks.item_count>0: report(city.recall(bookmarks.get_item_metadata(bookmarks.selected))))
	button(view_actions,"移除",func(): if bookmarks.item_count>0: report(city.bookmark({"id":bookmarks.get_item_metadata(bookmarks.selected)},true)))
	var ref:=section("参考底图与比例标定")
	reference_info=note(ref,"未导入底图")
	button(ref,"导入参考图…",import_reference)
	reference=Form.new(); ref.add_child(reference)
	button(ref,"应用底图设置",func(): report(city.set_reference(reference.values())))
	button(ref,"移除底图",func(): report(city.set_reference({"remove":true})))
	note(ref,"底图锁定后仍可调透明度和显示。精确标定：填写图上两点像素坐标与对应的同高世界坐标。")
	var calibration:=Form.new(); ref.add_child(calibration)
	var fields:={"pixel_a":Data.v2(),"pixel_b":Data.v2(),"world_a":Data.S.vector(-100000,100000),"world_b":Data.S.vector(-100000,100000)}
	calibration.build(Data.object(fields),{"pixel_a":[0,0],"pixel_b":[100,0],"world_a":[0,0,0],"world_b":[100,0,0]},{"pixel_a":"图片点 A（像素 X/Y）","pixel_b":"图片点 B（像素 X/Y）","world_a":"对应世界点 A（米）","world_b":"对应世界点 B（米）"})
	button(ref,"用两对点标定",func(): var v: Dictionary=calibration.values(); report(city.calibrate({"pixels":[v.pixel_a,v.pixel_b],"world":[v.world_a,v.world_b]})))
	var roads:=section("绘制道路骨架")
	note(roads,"左键连续点选；Enter 整笔提交，Esc 取消，Backspace 退一点。端点靠近已有节点会吸附；穿过线段不会自动生成路口。两侧细线表示预留宽度。")
	road_form=Form.new(); roads.add_child(road_form)
	road_form.build(Data.object({"width":Data.S.number(1,60),"height":Data.S.number(-10000,10000),"kind":Data.choice(["ground","bridge"])}),{"width":8.0,"height":0.0,"kind":"ground"},{"width":"道路宽度（米）","height":"绘制平面高度（米）","kind":"通行层"},{"kind":[{"id":"ground","name":"地面道路"},{"id":"bridge","name":"桥梁 / 跨越"}]})
	button(roads,"开始点选道路",func(): var v: Dictionary=road_form.values(); report(city.begin_draw(v.width,v.height,v.kind)))
	var draw_actions:=HBoxContainer.new(); roads.add_child(draw_actions)
	button(draw_actions,"提交草案",func(): report(city.finish_draw()))
	button(draw_actions,"取消草案",func(): report(city.finish_draw(true)))
	var editing:=section("道路节点与线段属性"); editing_section=editing
	note(editing,"可直接在画布拖动节点，连接线随端点移动；Alt 暂停吸附，Esc 取消。标高和曲线控制柄可在下方精调。")
	nodes=OptionButton.new(); nodes.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; editing.add_child(nodes); nodes.item_selected.connect(func(_i): fill_node())
	node_form=Form.new(); editing.add_child(node_form)
	button(editing,"更新节点",apply_node)
	button(editing,"删除节点（需先移除连接线）",func(): if nodes.item_count>0: report(city.update_roads(request().merged({"remove_nodes":[nodes.get_item_metadata(nodes.selected)]}))))
	edges=OptionButton.new(); edges.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; editing.add_child(edges); edges.item_selected.connect(func(_i): fill_edge())
	edge_form=Form.new(); editing.add_child(edge_form)
	curve=CheckButton.new(); curve.text="使用三次曲线"; editing.add_child(curve)
	controls=Form.new(); editing.add_child(controls); curve.toggled.connect(func(on): controls.visible=on)
	button(editing,"更新线段",apply_edge)
	button(editing,"删除线段",func(): if edges.item_count>0: report(city.update_roads(request().merged({"remove_edges":[edges.get_item_metadata(edges.selected)]}))))
	road_surface_panel=preload("res://scripts/world_editor/road_panel.gd").new(); add_child(road_surface_panel); road_surface_panel.setup(self)
	block_panel=preload("res://scripts/world_editor/block_panel.gd").new(); add_child(block_panel); block_panel.setup(self)
	scatter_panel=preload("res://scripts/world_editor/scatter_panel.gd").new(); add_child(scatter_panel); scatter_panel.setup(self)
	waterway_panel=preload("res://scripts/world_editor/waterway_panel.gd").new(); add_child(waterway_panel); waterway_panel.setup(self)
	bridge_panel=preload("res://scripts/world_editor/bridge_panel.gd").new(); add_child(bridge_panel); bridge_panel.setup(self)
	fortification_panel=preload("res://scripts/world_editor/fortification_panel.gd").new(); add_child(fortification_panel); fortification_panel.setup(self)
	diagnostics=note(self,"")
	refresh()

func request() -> Dictionary:
	return {"expected_token":Data.token(Data.resolve(editor._doc.map_meta).roads)}
func refresh() -> void:
	var data: Dictionary=city.data
	if overview==null: return
	overview.text="%d 个道路节点 · %d 条线段 · %d 个视图书签"%[data.roads.nodes.size(),data.roads.edges.size(),data.bookmarks.size()]
	bookmarks.clear()
	for b in data.bookmarks: bookmarks.add_item(b.name); bookmarks.set_item_metadata(bookmarks.item_count-1,b.id)
	var ref: Dictionary=data.get("reference",{})
	reference_info.text="未导入底图" if ref.is_empty() else "%d × %d 像素 · %.3f 米 / 像素"%[ref.pixel_size[0],ref.pixel_size[1],ref.meters_per_pixel]
	var props: Dictionary=ref.duplicate(true); props.erase("path"); props.erase("pixel_size")
	reference.build(Data.reference_schema(),props,{"center":"图片中心（米）","meters_per_pixel":"米 / 像素","yaw":"旋转角度","opacity":"透明度","visible":"显示底图","locked":"锁定标定"})
	for pair in [[nodes,data.roads.nodes],[edges,data.roads.edges]]:
		var select: OptionButton=pair[0]; var previous: String="" if select.item_count==0 else str(select.get_item_metadata(select.selected)); select.clear()
		for item in pair[1]:
			select.add_item(str(item.get("name",item.id))+ (" [锁]" if item.get("locked",false) else "") + (" [隐藏]" if item.get("hidden",false) else "")); select.set_item_metadata(select.item_count-1,item.id)
			if item.id==previous: select.select(select.item_count-1)
	fill_node(); fill_edge()
	if road_surface_panel!=null: road_surface_panel.refresh()
	if block_panel!=null: block_panel.invalidate()
	if scatter_panel!=null: scatter_panel.refresh()
	if waterway_panel!=null: waterway_panel.refresh()
	if fortification_panel!=null: fortification_panel.refresh()
	var labels:={"unconnected_crossing":"交叉处未连接节点","grade_separated_crossing":"桥梁跨越（未连接）","height_conflict":"地面道路交叉标高不一致","self_crossing":"曲线自身交叉","overlapping_centerlines":"中心线重叠","steep_grade":"道路坡度超过 15%"}
	var lines:=PackedStringArray()
	var road_names:={}
	for edge in data.roads.edges: road_names[edge.id]=str(edge.get("name",edge.id))
	for warning in city.analysis.get("diagnostics",[]).slice(0,12):
		var involved: Array=warning.get("edges",[warning.get("edge_id","")])
		var names:=PackedStringArray()
		for id in involved: names.append(road_names.get(id,id))
		lines.append(str(labels.get(warning.code,warning.code))+" · "+" / ".join(names))
	diagnostics.text="道路诊断：无" if lines.is_empty() else "道路诊断（草案仍可保存）：\n"+"\n".join(lines)

func selected(table: Array, control: OptionButton) -> Dictionary:
	if control.item_count==0: return {}
	for item in table:
		if item.id==control.get_item_metadata(control.selected): return item.duplicate(true)
	return {}
func select_node(id: String) -> void:
	for i in nodes.item_count:
		if nodes.get_item_metadata(i)==id: nodes.select(i); fill_node(); return
func fill_node() -> void:
	var node:=selected(city.data.roads.nodes,nodes)
	var values:={} if node.is_empty() else {"position":node.position,"locked":node.get("locked",false),"hidden":node.get("hidden",false)}
	node_form.build(Data.node_schema(),values,{"position":"节点 XYZ（米）","locked":"锁定节点","hidden":"隐藏节点"})
func fill_edge() -> void:
	var edge:=selected(city.data.roads.edges,edges)
	var values:={} if edge.is_empty() else {"name":edge.get("name",""),"width_start":edge.width_start,"width_end":edge.width_end,"kind":edge.kind,"locked":edge.get("locked",false),"hidden":edge.get("hidden",false)}
	var schema:=Data.edge_schema(); schema.properties.erase("bridge_ref")
	edge_form.build(schema,values,{"name":"道路线段名称","width_start":"起点宽度（米）","width_end":"终点宽度（米）","kind":"通行层","locked":"锁定线段","hidden":"隐藏线段"},{"kind":[{"id":"ground","name":"地面道路"},{"id":"bridge","name":"桥梁 / 跨越"}]})
	curve.set_pressed_no_signal(edge.has("controls")); controls.visible=curve.button_pressed
	var handles:={}
	if not edge.is_empty():
		var a:=Data.vec(city.analysis.nodes[edge.from].position); var b:=Data.vec(city.analysis.nodes[edge.to].position)
		var c: Array=edge.get("controls",[Data.xyz(a.lerp(b,1.0/3)),Data.xyz(a.lerp(b,2.0/3))])
		handles={"handle_a":c[0],"handle_b":c[1]}
	controls.build(Data.object({"handle_a":Data.S.vector(-100000,100000),"handle_b":Data.S.vector(-100000,100000)}),handles,{"handle_a":"起点控制柄（世界米）","handle_b":"终点控制柄（世界米）"})
func apply_node() -> void:
	var node:=selected(city.data.roads.nodes,nodes)
	if node.is_empty(): return
	node.merge(node_form.values(),true); report(city.update_roads(request().merged({"nodes":[node]})))
func apply_edge() -> void:
	var edge:=selected(city.data.roads.edges,edges)
	if edge.is_empty(): return
	edge.merge(edge_form.values(),true)
	if curve.button_pressed:
		var v: Dictionary=controls.values(); edge.controls=[v.handle_a,v.handle_b]
	else: edge.erase("controls")
	report(city.update_roads(request().merged({"edges":[edge]})))
func import_reference() -> void:
	var dialog:=FileDialog.new(); dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 参考底图"]); dialog.current_dir=Data.Paths.external_root()
	dialog.file_selected.connect(func(path): report(city.set_reference({"path":path})); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered(Vector2i(900,600))
func report(result: Dictionary) -> void:
	editor._status.text="城镇布局已更新" if result.ok else str(result.error)
