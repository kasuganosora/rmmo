extends VBoxContainer
const F=preload("res://scripts/world3d/fortification_data.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
const MaterialChoice=preload("res://scripts/world_editor/material_choice.gd")
const LABELS={"curve_tension":"样条弯曲强度（0～1）","follow_terrain":"随地形雕刻联动（城楼保持刚性）","tower_layout":"塔楼布局模式","tower_spacing":"自动布局目标间距（米，至少 50）","tower_door_open":"城楼内侧门开度（0～1）","arrow_slits":"城楼对外射击孔","wall_access":"圆楼内部楼梯与可行走楼顶","interior_side":"开放折线的城内侧","style":"城墙外观","name":"城墙名称","shape":"围墙形状","center_x":"环形中心 X","center_z":"环形中心 Z","radius_x":"环形 X 半径（相等为圆形）","radius_z":"环形 Z 半径","rotation":"环形朝向（度）","tower_count":"环形塔数（0：自动模式计算／手动模式 8 座）","closed":"折线闭合围城","base_height":"地面标高（米）","height":"墙高（米）","thickness":"墙厚（米）","terrain_foundation":"允许地基承托缓坡","foundation":"地基下延（米）","corner_towers":"生成塔楼","battlements":"垛口与护墙"}
const CHOICES={"tower_layout":[{"id":"automatic","name":"自动布局（应用间距禁区）"},{"id":"manual","name":"手动布置（不限制布局间距）"}],"interior_side":[{"id":"left","name":"路径左侧"},{"id":"right","name":"路径右侧"}],"style":[{"id":"plain","name":"基础墙体（旧版）"},{"id":"medieval_stone","name":"写实中世纪 · 石扶壁与压顶"}],"shape":[{"id":"spline","name":"控制点样条围墙"},{"id":"path","name":"点选折线"},{"id":"ellipse","name":"圆形 / 椭圆围城"}]}
const GROUPS=[
	{"name":"布局","fields":["name","shape","center_x","center_z","radius_x","radius_z","rotation","closed","interior_side","curve_tension","base_height"]},
	{"name":"结构","fields":["style","height","thickness","battlements","terrain_foundation","foundation"]},
	{"name":"塔楼","fields":["corner_towers","tower_layout","tower_spacing","tower_count","wall_access","arrow_slits","tower_door_open"]},
	{"name":"材质","fields":[]}, {"name":"城门","fields":[]}, {"name":"管理","fields":["follow_terrain"]}
]
const COMPACT_LABELS={"name":"名称","shape":"形状","center_x":"中心 X","center_z":"中心 Z","radius_x":"半径 X (m)","radius_z":"半径 Z (m)","rotation":"朝向 (°)","closed":"闭合路径","interior_side":"城内侧","curve_tension":"弯曲强度","base_height":"标高 (m)","style":"样式","height":"墙高 (m)","thickness":"墙厚 (m)","battlements":"垛口与护墙","terrain_foundation":"地基承托缓坡","foundation":"地基深度 (m)","corner_towers":"生成塔楼","tower_layout":"布局模式","tower_spacing":"间距 (m)","tower_count":"环形塔数","wall_access":"内部楼梯与楼顶通行","arrow_slits":"对外射击孔","tower_door_open":"内门开度","follow_terrain":"随地形雕刻联动"}
const GATE_LABELS={"kind":"通道类型","segment":"城墙段号","t":"段内位置","angle":"环上角度 (°)","width":"门宽 (m)","height":"门高 (m)","open":"门扇开度","grille":"水关双扇铁栅","water_depth":"墩基深度 (m)"}
var editor: Node3D
var host: VBoxContainer
var choice: OptionButton
var fields: VBoxContainer
var gate_fields: VBoxContainer
var gate_choice: OptionButton
var materials: Dictionary={}
var info: Label
var state: Label
var current: Dictionary={}
var preview: Dictionary={}
var tower_nodes: LineEdit
var tower_nodes_label: Label
var tasks: TabContainer
var pages: Array[VBoxContainer]=[]
var preview_button: Button
var apply_button: Button
var draw_button: Button
var bake_button: Button
var follow_button: Button
var detach_button: Button
var delete_button: Button
var gate_actions: Array[Button]=[]
var gate_open_button: Button
var gate_close_button: Button
var path_info: Label
var _existing:=false
var _frozen:=false
var _last_result_failed:=false
var _footer: HFlowContainer
var _bound_settings:Dictionary={}
var _bound_baked:=false
var _bound_document_id:=0

func setup(panel: VBoxContainer) -> void:
	host=panel; editor=host.editor
	name="FortificationTask"; size_flags_horizontal=Control.SIZE_EXPAND_FILL; size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var row:=HBoxContainer.new(); add_child(row)
	choice=OptionButton.new(); choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL; choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(choice); choice.item_selected.connect(func(_i):load_region())
	host.button(row,"新建",new_region)
	state=_hint(self,"")
	fields=Form.new(); fields.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(fields)
	_footer=HFlowContainer.new(); _footer.name="FortificationActions"; add_child(_footer)
	preview_button=host.button(_footer,"预览城墙",show_preview)
	apply_button=host.button(_footer,"应用城墙方案",apply)
	apply_button.add_theme_color_override("font_color",Color(.5,.85,1.0))
	info=host.note(self,""); info.name="FortificationResult"
	new_region(); refresh()

func _hint(parent:Node,text_:String,detail:String="") -> Label:
	var label:Label=host.note(parent,text_)
	label.autowrap_mode=TextServer.AUTOWRAP_OFF; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; label.clip_text=true
	label.tooltip_text=text_ if detail.is_empty() else detail
	label.theme_type_variation="EditorCaption"
	return label

func _compact_field(form_:VBoxContainer,key:String,parent:VBoxContainer,short_name:String) -> void:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",6); parent.add_child(row)
	var label:Label=form_._labels[key]; var control:Control=form_.fields[key]; var detail:String=label.text
	label.reparent(row); control.reparent(row); control.size_flags_horizontal=Control.SIZE_EXPAND_FILL; control.tooltip_text=detail
	label.tooltip_text=detail; label.text=short_name; label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.clip_text=true; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if control is CheckButton:
		label.hide(); control.text=short_name; control.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		label.custom_minimum_size.x=104; control.custom_minimum_size.x=120

func _compact_menu(parent:VBoxContainer,label_text:String,menu:Control,detail:String="") -> Label:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",6); parent.add_child(row)
	var label:=_hint(row,label_text,detail); label.theme_type_variation=""; label.custom_minimum_size.x=104
	menu.size_flags_horizontal=Control.SIZE_EXPAND_FILL; menu.custom_minimum_size.x=120; row.add_child(menu)
	menu.tooltip_text=detail if not detail.is_empty() else label_text
	return label

func form() -> void:
	var previous_tab:int=tasks.current_tab if is_instance_valid(tasks) else 0
	preview={}; editor._fortifications.overlay_plan={}
	var schema:=F.settings_schema(); var values:=current.duplicate(true)
	for key in ["id","points","gates","stone_material_id","trim_material_id","door_material_id","floor_material_id","layout_version","tower_indices"]: schema.properties.erase(key); values.erase(key)
	fields.build(schema,values,LABELS,CHOICES)
	# All controls remain descendants of SettingsForm: values() still commits
	# focused numeric text, and rebuilding frees every previous page and binding.
	tasks=TabContainer.new(); tasks.name="FortificationTasks"; tasks.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tasks.use_hidden_tabs_for_min_size=false; fields.add_child(tasks); pages.clear(); materials.clear(); gate_actions.clear()
	for group in GROUPS:
		var scroll:=ScrollContainer.new(); scroll.name=group.name; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; tasks.add_child(scroll)
		var page:=VBoxContainer.new(); page.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page.add_theme_constant_override("separation",6); scroll.add_child(page); pages.append(page)
		for key in group.fields:
			_compact_field(fields,key,page,COMPACT_LABELS[key])
	tasks.current_tab=clampi(previous_tab,0,tasks.get_tab_count()-1)
	path_info=_hint(pages[0],"")
	draw_button=host.button(pages[0],"点选路径 / 环形范围",func():report(editor._city.begin_fortification(float(fields.values().base_height)),"请在画布点选路径或环形范围"))
	_hint(pages[1],"地基须承托地面","地面须低于室内且不超过地基深度。城墙不生成外置登墙梯。")
	tower_nodes=LineEdit.new(); tower_nodes.placeholder_text="0,3,7 / none"
	tower_nodes_label=_compact_menu(pages[2],"塔楼节点",tower_nodes,"留空使用全部拐点；例如 0,3,7；none 不布塔。")
	tower_nodes.text="" if not current.has("tower_indices") else ("none" if current.tower_indices.is_empty() else ",".join(current.tower_indices.map(func(v):return str(int(v)))))
	tower_nodes.text_changed.connect(func(_v):invalidate())
	_hint(pages[2],"手动布塔不受间距约束","自动布局按间距布塔；手动模式不受布局间距约束。登墙通路经过圆楼内侧门、内部楼梯和楼顶。")
	for role in ["stone","trim","door","floor"]:
		var menu:=OptionButton.new(); menu.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; materials[role]=menu
		_compact_menu(pages[3],{"floor":"圆楼地面","stone":"墙身石材","trim":"压顶与拱圈","door":"城门木材"}[role],menu)
		MaterialChoice.bind_menu(menu,editor._material_panel,"原色"); MaterialChoice.choose(menu,str(current[role+"_material_id"]))
		menu.item_selected.connect(func(_i):invalidate())
	_hint(pages[4],"选择城门查看方案","已生成的城门可直接开合；新门方案须先增加或更新，再预览应用。")
	gate_choice=OptionButton.new(); gate_choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; pages[4].add_child(gate_choice)
	gate_choice.item_selected.connect(func(i):gate_form(current.gates[i]); _update_state())
	var gate_state:=HFlowContainer.new(); pages[4].add_child(gate_state)
	gate_open_button=host.button(gate_state,"打开城门",func():set_gate(1))
	gate_close_button=host.button(gate_state,"关闭城门",func():set_gate(0))
	gate_fields=Form.new(); pages[4].add_child(gate_fields)
	var gate_edit:=HFlowContainer.new(); pages[4].add_child(gate_edit)
	gate_actions.append(host.button(gate_edit,"增加城门",_add_gate))
	gate_actions.append(host.button(gate_edit,"更新方案",_update_gate))
	gate_actions.append(host.button(gate_edit,"移除此门",_remove_gate))
	_hint(pages[4],"位置随城墙形状定义","折线用段号和比例；环形用角度（0° 东、90° 南），再随城墙旋转。切换形状后需更新原城门方案。")
	follow_button=host.button(pages[5],"应用地形跟随",_apply_follow)
	_hint(pages[5],"地形跟随可独立应用","已生成城防可独立修改地形跟随；结构保持为固定预制件。新方案会随“应用城墙方案”保存此设置。")
	bake_button=host.button(pages[5],"烘焙为固定预制件",_bake)
	bake_button.tooltip_text="将旧版未烘焙城防转换为固定预制件；已烘焙结构不能拆改。"
	pages[5].add_child(HSeparator.new())
	_hint(pages[5],"移除与关联管理")
	detach_button=host.button(pages[5],"解除关联，保留现场",func():remove_region(true))
	detach_button.tooltip_text="仅旧版未烘焙城防可解除关联。固定预制件不支持拆散。"
	delete_button=host.button(pages[5],"删除整组城墙及城门",func():remove_region(false))
	delete_button.add_theme_color_override("font_color",Color(1.0,.65,.62))
	delete_button.tooltip_text="删除这组城防；可通过编辑器撤销恢复。"
	for key in fields.fields:
		var control:Control=fields.fields[key]
		if control is SpinBox: control.value_changed.connect(func(_v):invalidate())
		elif control is CheckButton: control.toggled.connect(func(_v):_field_changed(key))
		elif control is LineEdit: control.text_changed.connect(func(_v):invalidate())
		elif control is OptionButton: control.item_selected.connect(func(_i):_field_changed(key))
	sync_gates(); _update_state(); _update_field_visibility()

func _field_changed(key:String) -> void:
	if key=="shape":
		var gate:Dictionary=gate_fields.values()
		gate_form(gate)
	_update_field_visibility(); invalidate()

func _show_field(key:String,shown:bool) -> void:
	fields.fields[key].get_parent().visible=shown
	fields.fields[key].visible=shown; fields._labels[key].visible=shown and not fields.fields[key] is CheckButton

func _update_field_visibility() -> void:
	var values:Dictionary=fields.values()
	var ring:bool=values.shape=="ellipse"
	for key in ["center_x","center_z","radius_x","radius_z","rotation"]:_show_field(key,ring)
	_show_field("closed",not ring); _show_field("interior_side",not ring and not values.closed)
	_show_field("curve_tension",values.shape=="spline")
	for key in ["tower_layout","tower_door_open"]:_show_field(key,values.corner_towers)
	# Keep an enabled dependent option reachable so users can resolve invalid
	# combinations after disabling towers or choosing the legacy wall style.
	for key in ["wall_access","arrow_slits"]:_show_field(key,values.corner_towers or values[key])
	_show_field("tower_spacing",values.corner_towers and values.tower_layout=="automatic")
	_show_field("tower_count",values.corner_towers and ring)
	tower_nodes.visible=values.corner_towers and not ring; tower_nodes_label.visible=tower_nodes.visible; tower_nodes.get_parent().visible=tower_nodes.visible
	path_info.text="两点圈定环形范围" if ring else "已选 %d 个点 · Enter 完成"%current.points.size()
	path_info.tooltip_text="使用两点圈定环形范围，或直接填写中心与半径。" if ring else "Enter 完成，Esc 取消，Backspace 退一点。"

func _region() -> Dictionary:
	for region:Dictionary in editor._fortifications.regions():
		if region.settings.id==current.get("id",""):return region
	return {}

func _set_editable(control:Control,enabled:bool) -> void:
	if control is SpinBox:control.editable=enabled
	elif control is LineEdit:control.editable=enabled
	elif control is BaseButton:control.disabled=not enabled

func _update_state() -> void:
	var region:=_region(); _existing=not region.is_empty(); _frozen=region.get("baked",false)
	state.text="新建方案 · 先预览后应用" if not _existing else "已有城防 · 可预览修改"
	if _frozen:state.text="已烘焙 · 结构只读"
	state.tooltip_text=("可在“城门”开合门扇，在“管理”调整地形跟随。\n" if _frozen else "应用后成为固定预制件；旧版城防也可在“管理”中烘焙。\n")+"城防 ID："+str(current.get("id",""))
	for key in fields.fields:_set_editable(fields.fields[key],not _frozen or key=="follow_terrain")
	tower_nodes.editable=not _frozen
	for control in materials.values():control.disabled=_frozen
	for control in gate_fields.fields.values():_set_editable(control,not _frozen)
	draw_button.disabled=_frozen; preview_button.visible=not _frozen; apply_button.visible=not _frozen
	apply_button.disabled=preview.is_empty(); follow_button.disabled=not _existing
	bake_button.disabled=not _existing or _frozen; detach_button.disabled=not _existing or _frozen; delete_button.disabled=not _existing
	var has_gate:=gate_choice.item_count>0
	gate_open_button.disabled=not _existing or not has_gate; gate_close_button.disabled=not _existing or not has_gate
	for i in gate_actions.size():gate_actions[i].disabled=_frozen or (i>0 and not has_gate)
	gate_choice.disabled=not has_gate

func gate_form(value: Dictionary={}) -> void:
	var schema:=F.gate_schema(3.0 if _region().get("baked",false) else 5.0); schema.properties.erase("id"); schema.required=[]
	var values:={"grille":false,"water_depth":4.,"kind":"land","width":5.0,"height":5.0,"open":1.0}; values.merge(value,true); values.erase("id")
	if fields.values().get("shape","path")=="ellipse":
		values.erase("segment"); values.erase("t"); values.angle=values.get("angle",270.0); schema.properties.erase("segment"); schema.properties.erase("t")
	else:
		values.erase("angle"); values.segment=values.get("segment",0); values.t=values.get("t",.5); schema.properties.erase("angle")
	gate_fields.build(schema,values,{"grille":"水关双扇铁栅","water_depth":"水关墩基下延（米）","kind":"通道类型","segment":"城墙段号（从 0 起）","t":"段内位置（0～1）","angle":"环上角度（度）","width":"门洞宽（米）","height":"门洞净高（米）","open":"城门开度（0～1）"},{"kind":[{"id":"land","name":"陆地城门"},{"id":"water","name":"多孔水关"}]})
	for key in GATE_LABELS:
		if gate_fields.fields.has(key):_compact_field(gate_fields,key,gate_fields,GATE_LABELS[key])
	gate_fields.fields.kind.item_selected.connect(func(_i):_gate_visibility())
	_gate_visibility()
	for control in gate_fields.fields.values():_set_editable(control,not _region().get("baked",false))

func _gate_visibility() -> void:
	var water:bool=gate_fields.values().kind=="water"
	for key in ["grille","water_depth"]:
		gate_fields.fields[key].get_parent().visible=water
		gate_fields.fields[key].visible=water; gate_fields._labels[key].visible=water and not gate_fields.fields[key] is CheckButton

func sync_gates(selected_id:String="") -> void:
	if selected_id.is_empty() and gate_choice.item_count>0:selected_id=str(gate_choice.get_item_metadata(gate_choice.selected))
	gate_choice.clear()
	for g in current.gates:
		gate_choice.add_item("%s · %s"%[g.id,("%.1f°"%g.angle if g.has("angle") else "第 %d 段"%g.segment)]); gate_choice.set_item_metadata(gate_choice.item_count-1,g.id)
		if g.id==selected_id:gate_choice.select(gate_choice.item_count-1)
	gate_form(current.gates[gate_choice.selected] if not current.gates.is_empty() else {})

func _add_gate() -> void:
	if _frozen:return
	var id:="gate_"+Crypto.new().generate_random_bytes(4).hex_encode()
	current.gates.append(gate_fields.values().merged({"id":id})); sync_gates(id); invalidate()
func _update_gate() -> void:
	if _frozen or gate_choice.item_count==0:return
	current.gates[gate_choice.selected]=gate_fields.values().merged({"id":current.gates[gate_choice.selected].id}); sync_gates(); invalidate()
func _remove_gate() -> void:
	if _frozen or gate_choice.item_count==0:return
	current.gates.remove_at(gate_choice.selected); sync_gates(); invalidate()

func new_region() -> void:
	_bound_document_id=_document_id(); _bound_settings={}; _bound_baked=false
	current=F.defaults().merged({"id":"wall_"+Crypto.new().generate_random_bytes(6).hex_encode(),"points":[],"style":"medieval_stone","height":7.5,"thickness":3.5,"arrow_slits":true,"wall_access":true,"tower_count":0,"tower_layout":"automatic"},true)
	for pair in [["floor_material_id","pack:default:paving/sandstone_floor/material"],["trim_material_id","pack:default:walls/stone_tiles_facade/material"],["stone_material_id","pack:default:walls/castle_rubble/material"],["door_material_id","pack:default:wood/worn_planks/material"]]:
		if not editor._material_tool.library.find(pair[1]).is_empty():current[pair[0]]=pair[1]
	form(); tasks.current_tab=0; invalidate()
	if choice.item_count>0:choice.select(0)
func refresh() -> void:
	var was_existing:=_existing
	var document_changed:bool=_bound_document_id!=_document_id()
	choice.clear(); choice.add_item("新城墙（尚未生成）"); choice.set_item_metadata(0,"")
	var found:=false
	for r in editor._fortifications.regions():
		choice.add_item(r.settings.name+ (" · 已烘焙" if r.get("baked",false) else "")); choice.set_item_metadata(choice.item_count-1,r.settings.id)
		if current.get("id")==r.settings.id:
			found=true; choice.select(choice.item_count-1)
			# Road/bookmark/catalog refreshes must not replace a pending recipe,
			# material choice, gate edit, text caret or scroll position.
			if document_changed or _bound_settings!=r.settings or _bound_baked!=r.get("baked",false):_bind_region(r)
	if not found and (was_existing or document_changed):new_region()
	invalidate(false)

func _document_id() -> int:
	return editor._doc.get_instance_id() if editor._doc!=null else 0

func _bind_region(region:Dictionary) -> void:
	_bound_document_id=_document_id(); _bound_settings=region.settings.duplicate(true); _bound_baked=region.get("baked",false)
	# Gate arrays are draft state; never alias the document recipe before Apply.
	current=F.defaults().merged(region.settings.duplicate(true),true); form()

func load_region() -> void:
	if choice.selected==0:new_region(); return
	for r in editor._fortifications.regions():
		if r.settings.id==choice.get_item_metadata(choice.selected):
			_bind_region(r); invalidate()
			if _frozen:tasks.current_tab=4 if not current.gates.is_empty() else 5
			return
func set_points(points: Array) -> Dictionary:
	if _region().get("baked",false):return Data.fail("已烘焙城防结构只读；请新建方案")
	if points.size()<2:return Data.fail("至少点选两个城墙中心点")
	if fields.values().get("shape","path")=="ellipse":
		if points.size()!=2:return Data.fail("环形范围只需两个对角点")
		var a:=Vector2(points[0][0],points[0][1]); var b:=Vector2(points[1][0],points[1][1]); var radius:Vector2=(b-a).abs()*.5
		if radius.x<15 or radius.y<15 or radius.x>200 or radius.y>200:return Data.fail("环形两轴半径须为 15～200 米")
		# Capture all authored settings, including the separate material menus.
		# Only patch bounds in place: rebuilding would discard the gate draft,
		# hidden path tower text and each page's focus/scroll state.
		current=request(); var values:Dictionary=fields.values()
		var bounds:={"center_x":(a.x+b.x)*.5,"center_z":(a.y+b.y)*.5,"radius_x":radius.x,"radius_z":radius.y,"rotation":0.0,"closed":true}
		current.merge(bounds,true); current.points=[]; values.merge(bounds,true); fields.update_values(values)
		_update_field_visibility(); invalidate(); return {"ok":true}
	current.points=points.duplicate(true); _update_field_visibility(); invalidate(); return {"ok":true}
func request() -> Dictionary:
	var result:=current.merged(fields.values(),true); result.erase("layout_version"); result.erase("tower_indices")
	if result.shape!="ellipse":
		if not tower_nodes.text.strip_edges().is_empty():
			result.tower_indices=[]
			if tower_nodes.text.strip_edges()!="none":
				for part in tower_nodes.text.split(","):result.tower_indices.append(int(part) if part.strip_edges().is_valid_int() else -1)
		elif current.has("tower_indices"):
			# Clearing an explicit path selection restores towers at all nodes.
			result.tower_indices=range(result.points.size())
	for role in materials:result[role+"_material_id"]=materials[role].get_item_metadata(materials[role].selected)
	return result
func show_preview() -> void:
	if _region().get("baked",false):report(Data.fail("已烘焙城防结构只读；请新建方案")); return
	var result:Dictionary=editor._fortifications.summary(request())
	if not result.ok:
		invalidate(); report(result)
		if result.has("layout_zones"):editor._fortifications.overlay_plan=result
		return
	preview=result; editor._fortifications.overlay_plan=result; _update_state()
	report(result,"总长 %.1f 米 · %d 座塔楼 · %d 个构件 · %d 座城门"%[result.length,result.tower_count,result.count,result.gates.size()])
func apply() -> void:
	if preview.is_empty():report(Data.fail("请先预览城墙")); return
	var result:Dictionary=editor._fortifications.generate(request().merged({"plan_token":preview.plan_token}))
	if result.ok:refresh()
	report(result,"城墙方案已应用")
func set_gate(amount: float) -> void:
	if gate_choice.item_count==0:return
	var id:String=current.gates[gate_choice.selected].id
	var result:Dictionary=editor._fortifications.set_gate(current.id,id,amount)
	if result.ok:load_region()
	report(result,"城门已打开" if amount>0 else "城门已关闭")
func _apply_follow() -> void:
	var result:Dictionary=editor._fortifications.set_terrain_follow(current.id,fields.values().follow_terrain)
	if result.ok:refresh()
	report(result,"地形跟随设置已应用")
func _bake() -> void:
	var result:Dictionary=editor._fortifications.bake(current.id)
	if result.ok:refresh()
	report(result,"城防已烘焙为固定预制件")
func remove_region(keep: bool) -> void:
	var result:Dictionary=editor._fortifications.remove(current.id,keep)
	if result.ok:new_region(); refresh()
	report(result,"已解除关联并保留现场" if keep else "已删除这组城防，可撤销恢复")
func report(result:Dictionary,success:String="城防已更新") -> void:
	_last_result_failed=not result.get("ok",false)
	info.text=success if result.get("ok",false) else str(result.get("error","操作失败")); info.tooltip_text=info.text
	info.modulate=Color.WHITE if result.get("ok",false) else Color(1.0,.65,.62)
	editor._report_result(result,success,"城防")
func invalidate(clear_message:bool=true) -> void:
	preview={}; editor._fortifications.overlay_plan={}
	if info!=null and (clear_message or not _last_result_failed):
		info.text=""; info.modulate=Color.WHITE
		_last_result_failed=false
	_update_state()
