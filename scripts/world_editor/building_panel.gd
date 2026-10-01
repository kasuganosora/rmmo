extends VBoxContainer
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
var editor: Node3D
var form: VBoxContainer
var placement: VBoxContainer
var count: SpinBox
var columns: SpinBox
var gap: SpinBox
var chooser: OptionButton
var report_label: Label
var ghost: Node3D
var hidden_sources: Array = []
var street: VBoxContainer
var region: VBoxContainer
var details: VBoxContainer
var details_toggle: CheckButton
var bound_instance: Dictionary = {}
var placement_raw: Dictionary = {}
var placement_shown: Dictionary = {}

func button(text_: String, action: Callable) -> Button:
	var value := Button.new(); value.text = text_; value.pressed.connect(action); add_child(value); return value

func setup(host: Node3D) -> void:
	editor = host; add_theme_constant_override("separation",6)
	var hint := Label.new(); hint.text = "内外共用蓝图：普通、中世纪与城中村家庭自建房。支持平地沿街批量布置。"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(hint)
	chooser = OptionButton.new(); chooser.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(chooser)
	chooser.item_selected.connect(func(index):
		clear_preview()
		var id: String = chooser.get_item_metadata(index)
		if id.is_empty(): set_values(Blueprint.defaults(),[0,0,0],0)
		elif editor._buildings.instances().has(id):
			var value: Dictionary = editor._buildings.instances()[id]; set_values(value.parameters,value.position,value.yaw)
	)
	var presets := HBoxContainer.new(); add_child(presets)
	for key in Blueprint.LABELS:
		var control := Button.new(); control.text = Blueprint.LABELS[key]; presets.add_child(control)
		control.pressed.connect(func():
			var values := Blueprint.defaults(); values.template = key
			if key=="inn": values.rooms_per_floor = 3
			chooser.select(0); set_values(values,placement_values().position,placement_values().yaw)
		)
	var medieval := GridContainer.new(); medieval.columns=2; add_child(medieval)
	for preset in Blueprint.medieval_presets()+Blueprint.urban_presets():
		var control:=Button.new(); control.text=preset.name; control.size_flags_horizontal=Control.SIZE_EXPAND_FILL; medieval.add_child(control)
		control.pressed.connect(func(): chooser.select(0); set_values(preset.parameters,placement_values().position,placement_values().yaw))
	var actions := HBoxContainer.new(); add_child(actions)
	for entry in [["预览",preview],["生成一批",generate],["更新建筑",update_building]]:
		var action := Button.new(); action.text = entry[0]; action.pressed.connect(entry[1]); action.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(action)
	form = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(form)
	placement = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(placement)
	street=preload("res://scripts/world_editor/building_street_panel.gd").new(); street.setup(self); add_child(street)
	move_child(street,form.get_index())
	var batch := HBoxContainer.new(); add_child(batch)
	count = spin(batch,"数量",1,16,1); columns = spin(batch,"列",1,16,4); gap = spin(batch,"间距",1,30,2)
	button("聚焦所选建筑",focus)
	button("解除关联，保留普通物件",func(): remove(true))
	button("删除所选建筑",func(): remove(false))
	button("清除预览",clear_preview)
	report_label = Label.new(); report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(report_label)
	set_values(Blueprint.defaults(),[0,0,0],0); refresh_list()
	# Keep the full original workflow under an expandable section.
	details=VBoxContainer.new()
	for child in get_children(): remove_child(child); details.add_child(child)
	region=preload("res://scripts/world_editor/building_region_panel.gd").new(); add_child(region); region.setup(self)
	details_toggle=CheckButton.new(); details_toggle.text="详细参数与建筑管理"; add_child(details_toggle)
	add_child(details); details.hide(); details_toggle.toggled.connect(func(value): details.visible=value)

func spin(parent: Node, text_: String, minimum: float, maximum: float, value: float) -> SpinBox:
	var control := SpinBox.new(); control.prefix = text_; control.min_value = minimum; control.max_value = maximum; control.step = 1; control.value = value; control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(control); return control

func set_values(parameters: Dictionary, position: Array, yaw: float) -> void:
	clear_preview()
	bound_instance = instance_form_state(selected_id())
	var layout: String=parameters.get("layout","standard")
	var ordered := {"layout":layout}; ordered.merge(Blueprint.layout_defaults(layout)); ordered.merge(parameters,true)
	if layout=="urban_village":
		if ordered.template not in ["house","shop"]: ordered.template="house"
		for key in ordered.keys():
			if key not in ["layout","template","width","depth","floors","floor_height","seed","bedrooms","balcony","balcony_depth","facade_color","ground_canopy","roof_canopy","roof_tank","left_wall","right_wall"]: ordered.erase(key)
	elif layout=="standard":
		for key in Blueprint.defaults():
			if key!="layout" and not Blueprint.legacy_defaults().has(key): ordered.erase(key)
	else:
		ordered.erase("roof_height")
		for key in Blueprint.defaults():
			if not Blueprint.medieval_defaults().has(key): ordered.erase(key)
	var labels := {"layout":"布局","template":"建筑用途","width":"宽度（米）","depth":"进深（米）","floors":"层数","floor_height":"层高（米）","rooms_per_floor":"每层房间数","roof":"屋顶","roof_height":"屋顶升高","style":"外观","seed":"变化种子","roof_axis":"屋脊方向","roof_pitch":"屋顶坡度（度）","eaves":"出檐（米）","jetty":"上层临街挑出（米）","bay_width":"木架开间目标宽度","shutters":"开启式窗板","compound":"建筑组合","annex_width":"附属房宽度","annex_depth":"附属房进深","left_wall":"左侧外墙","right_wall":"右侧外墙"}
	var choices := {"layout":[{"id":"standard","name":"普通侧走廊"},{"id":"townhouse","name":"中世纪窄店屋"},{"id":"hall","name":"中世纪挑空大厅"}],"template":[{"id":"house","name":"民居"},{"id":"shop","name":"商住楼"},{"id":"inn","name":"旅馆"}],"roof":[{"id":"gable","name":"双坡屋顶"},{"id":"flat","name":"平屋顶"}],"style":[{"id":"timber","name":"木梁灰墙"},{"id":"plaster","name":"浅色灰墙"}],"roof_axis":[{"id":"depth","name":"沿进深（山墙朝街）"},{"id":"width","name":"沿宽度（檐口朝街）"}],"compound":[{"id":"none","name":"独栋"},{"id":"rear_workshop","name":"后院＋独立作坊"},{"id":"left_wing","name":"L 形左侧翼"},{"id":"courtyard","name":"U 形围院"}],"left_wall":[{"id":"open","name":"有窗外墙"},{"id":"party","name":"无窗邻接墙"}],"right_wall":[{"id":"open","name":"有窗外墙"},{"id":"party","name":"无窗邻接墙"}]}
	labels.merge({"bedrooms":"每层卧室数","balcony":"阳台","balcony_depth":"阳台进深（米）","facade_color":"外墙配色","ground_canopy":"入口雨棚","roof_canopy":"屋顶晾晒棚","roof_tank":"屋顶水箱"})
	choices.layout.append({"id":"urban_village","name":"城中村家庭自建房"})
	choices.merge({"balcony":[{"id":"none","name":"无阳台"},{"id":"front","name":"临街通长阳台"},{"id":"corner","name":"临街＋右侧转角阳台"}],"facade_color":[{"id":"white","name":"白墙红边"},{"id":"cream","name":"米黄墙金边"},{"id":"rose","name":"浅粉墙"},{"id":"green","name":"浅绿墙"}]})
	var schema:=Blueprint.schema()
	if layout=="urban_village":
		choices.template=[{"id":"house","name":"家庭住宅"},{"id":"shop","name":"底商上住"}]
		schema.properties.width.minimum=8.5
	else: schema.properties.floors.maximum=3
	form.build(schema,ordered,labels,choices)
	form.fields.layout.item_selected.connect(func(_index): set_values(form.values(),placement_values().position,placement_values().yaw))
	placement.build(editor._buildings.placement_schema(),{"position":position,"yaw":yaw},{"position":"建筑中心脚点 XYZ","yaw":"朝向（度）"})
	placement_raw={"position":position.duplicate(),"yaw":yaw}
	placement_shown=placement.values()

func placement_values() -> Dictionary:
	var values: Dictionary=placement.values()
	if placement_shown.is_empty(): return values
	# Display precision must not move a painted house when another parameter changes.
	for axis in 3:
		if values.position[axis]==placement_shown.position[axis]: values.position[axis]=placement_raw.position[axis]
	if values.yaw==placement_shown.yaw: values.yaw=placement_raw.yaw
	return values


func refresh_list(selected := "") -> void:
	if chooser==null: return
	var explicit := not selected.is_empty()
	if selected.is_empty() and chooser.selected>=0: selected = str(chooser.get_item_metadata(chooser.selected))
	chooser.clear(); chooser.add_item("新建建筑"); chooser.set_item_metadata(0,"")
	for id in editor._buildings.instances():
		var value: Dictionary = editor._buildings.instances()[id]
		chooser.add_item("%s · %s"%[Blueprint.LABELS[value.parameters.template],id.right(8)]); chooser.set_item_metadata(chooser.item_count-1,id)
		if id==selected: chooser.select(chooser.item_count-1)
	var current := instance_form_state(selected)
	if not current.is_empty() and (explicit or current!=bound_instance):
		var value: Dictionary = editor._buildings.instances()[selected]; set_values(value.parameters,value.position,value.yaw)
	elif current.is_empty() and not bound_instance.is_empty(): set_values(Blueprint.defaults(),[0,0,0],0)

func instance_form_state(id: String) -> Dictionary:
	if not editor._buildings.instances().has(id): return {}
	var value: Dictionary = editor._buildings.instances()[id]
	return {"id":id,"parameters":value.parameters.duplicate(true),"position":value.position.duplicate(),"yaw":value.yaw}

func parameters() -> Dictionary:
	# Hidden fields belong to the selected layout, not a previous layout's recipe.
	var visible: Dictionary=form.values()
	return Blueprint.layout_defaults(visible.layout).merged(visible,true)

func args() -> Dictionary:
	var p: Dictionary = parameters(); var at: Dictionary = placement_values(); var lots: Array = []
	var basis := Basis(Vector3.UP,deg_to_rad(float(at.yaw)))
	var plan := Blueprint.generate(p); var extent := Vector3(p.width,0,p.depth)
	if plan.ok: extent=preload("res://scripts/world_editor/selection_geometry.gd").bounds(plan.records).size
	for index in int(count.value):
		var offset := Vector3((index%int(columns.value))*(extent.x+gap.value),0,floori(float(index)/columns.value)*(extent.z+gap.value))
		lots.append({"position":Blueprint.arr(Blueprint.vec(at.position)+basis*offset),"yaw":at.yaw,"seed_offset":index})
	return {"parameters":p,"placements":lots}

func preview() -> void:
	clear_preview()
	var replacing := selected_id()
	var result: Dictionary
	if street.enabled.button_pressed: replacing=""; result=editor._buildings.prepare_street(street.request())
	else:
		var request := args()
		if not replacing.is_empty(): request.placements = [placement_values()]
		result=editor._buildings.prepare(request,replacing)
	if not result.ok: report(result); return
	show_preview(result,replacing)

func show_preview(result: Dictionary, replacing := "", fit := true) -> void:
	if not replacing.is_empty():
		for id in editor._buildings.instances()[replacing].parts.values():
			var visual: Node3D = editor._view.get_node_or_null(NodePath(str(id)))
			if visual!=null: hidden_sources.append([visual,visual.visible]); visual.hide()
	ghost = Node3D.new(); ghost.name = "BuildingPreview"; editor.add_child(ghost)
	for plan in result.plans:
		for record in plan.records:
			var mesh: MeshInstance3D = editor._doc._mesh(record); mesh.transparency = .35; ghost.add_child(mesh)
	report({"ok":true,"message":"预览 %d 栋，未写入地图。参数改变后请重新预览。"%result.plans.size()})
	var bounds:=AABB(Blueprint.vec(result.plans[0].bounds.position),Blueprint.vec(result.plans[0].bounds.size))
	for plan in result.plans: bounds=bounds.merge(AABB(Blueprint.vec(plan.bounds.position),Blueprint.vec(plan.bounds.size)))
	if fit: frame({"position":Blueprint.arr(bounds.position),"size":Blueprint.arr(bounds.size)})

func clear_preview() -> void:
	if region!=null: region.invalidate_preview()
	for pair in hidden_sources:
		if is_instance_valid(pair[0]): pair[0].visible = pair[1]
	hidden_sources.clear()
	if is_instance_valid(ghost):
		ghost.free()
		if report_label!=null:
			if editor._status.text==report_label.text: editor._status.text = "预览已清除。"
			report_label.text = "预览已清除。"
	ghost = null

func generate() -> void:
	report(editor._buildings.generate_street(street.request()) if street.enabled.button_pressed else editor._buildings.generate(args()))

func update_building() -> void:
	if street.enabled.button_pressed: report(Blueprint.fail("沿街模式用于新建；更新单栋请先关闭沿街模式")); return
	var at: Dictionary = placement_values()
	report(editor._buildings.update(selected_id(),parameters(),at.position,at.yaw))

func selected_id() -> String: return str(chooser.get_item_metadata(chooser.selected)) if chooser.selected>=0 else ""
func remove(detach: bool) -> void: report(editor._buildings.remove(selected_id(),detach))
func focus() -> void:
	if not editor._buildings.instances().has(selected_id()): report(Blueprint.fail("请先选择建筑")); return
	var value: Dictionary = editor._buildings.instances()[selected_id()]
	var records: Array = editor._doc.records.filter(func(record): return value.parts.values().has(record.uuid))
	var bounds := preload("res://scripts/world_editor/selection_geometry.gd").bounds(records)
	frame({"position":Blueprint.arr(bounds.position),"size":Blueprint.arr(bounds.size)})

func frame(bounds: Dictionary) -> void:
	var box := AABB(Blueprint.vec(bounds.position),Blueprint.vec(bounds.size)); editor._orbit_center = box.get_center()
	var extent := maxf(box.size.x,maxf(box.size.y,box.size.z))
	editor._camera.position = editor._orbit_center+Vector3(1, .85, -1).normalized()*extent*1.8
	editor._camera.look_at(editor._orbit_center)

func report(result: Dictionary) -> void:
	var text_: String = result.get("message","建筑操作完成，可撤销") if result.ok else str(result.error)
	if not result.ok and result.has("conflicts"): text_ += "（%d 处冲突）"%result.conflicts.size()
	report_label.text = text_; editor._status.text = text_
