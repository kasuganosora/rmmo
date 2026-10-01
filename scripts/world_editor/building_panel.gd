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

func button(text_: String, action: Callable) -> Button:
	var value := Button.new(); value.text = text_; value.pressed.connect(action); add_child(value); return value

func setup(host: Node3D) -> void:
	editor = host; add_theme_constant_override("separation",6)
	var hint := Label.new(); hint.text = "同一蓝图生成外墙、房间、门窗与楼梯洞口。平地矩形建筑；门洞保持可通行。"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(hint)
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
			chooser.select(0); set_values(values,placement.values().position,placement.values().yaw)
		)
	var actions := HBoxContainer.new(); add_child(actions)
	for entry in [["预览",preview],["生成一批",generate],["更新建筑",update_building]]:
		var action := Button.new(); action.text = entry[0]; action.pressed.connect(entry[1]); action.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(action)
	form = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(form)
	placement = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(placement)
	var batch := HBoxContainer.new(); add_child(batch)
	count = spin(batch,"数量",1,16,1); columns = spin(batch,"列",1,16,4); gap = spin(batch,"间距",1,30,2)
	button("聚焦所选建筑",focus)
	button("解除关联，保留普通物件",func(): remove(true))
	button("删除所选建筑",func(): remove(false))
	button("清除预览",clear_preview)
	report_label = Label.new(); report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(report_label)
	set_values(Blueprint.defaults(),[0,0,0],0); refresh_list()

func spin(parent: Node, text_: String, minimum: float, maximum: float, value: float) -> SpinBox:
	var control := SpinBox.new(); control.prefix = text_; control.min_value = minimum; control.max_value = maximum; control.step = 1; control.value = value; control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(control); return control

func set_values(parameters: Dictionary, position: Array, yaw: float) -> void:
	clear_preview()
	var ordered := Blueprint.defaults(); ordered.merge(parameters,true)
	form.build(Blueprint.schema(),ordered,{"template":"建筑用途","width":"宽度（米）","depth":"进深（米）","floors":"层数","floor_height":"层高（米）","rooms_per_floor":"每层房间数","roof":"屋顶","roof_height":"屋顶升高","style":"外观","seed":"变化种子"},{"template":[{"id":"house","name":"民居"},{"id":"shop","name":"商住楼"},{"id":"inn","name":"旅馆"}],"roof":[{"id":"gable","name":"双坡屋顶"},{"id":"flat","name":"平屋顶"}],"style":[{"id":"timber","name":"木梁灰墙"},{"id":"plaster","name":"浅色灰墙"}]})
	placement.build(editor._buildings.placement_schema(),{"position":position,"yaw":yaw},{"position":"建筑中心脚点 XYZ","yaw":"朝向（度）"})

func refresh_list(selected := "") -> void:
	if chooser==null: return
	var explicit := not selected.is_empty()
	if selected.is_empty() and chooser.selected>=0: selected = str(chooser.get_item_metadata(chooser.selected))
	chooser.clear(); chooser.add_item("新建建筑"); chooser.set_item_metadata(0,"")
	for id in editor._buildings.instances():
		var value: Dictionary = editor._buildings.instances()[id]
		chooser.add_item("%s · %s"%[Blueprint.LABELS[value.parameters.template],id.right(8)]); chooser.set_item_metadata(chooser.item_count-1,id)
		if id==selected: chooser.select(chooser.item_count-1)
	if explicit and editor._buildings.instances().has(selected):
		var value: Dictionary = editor._buildings.instances()[selected]; set_values(value.parameters,value.position,value.yaw)

func args() -> Dictionary:
	var p: Dictionary = form.values(); var at: Dictionary = placement.values(); var lots: Array = []
	var basis := Basis(Vector3.UP,deg_to_rad(float(at.yaw)))
	for index in int(count.value):
		var offset := Vector3((index%int(columns.value))*(p.width+gap.value),0,floori(float(index)/columns.value)*(p.depth+gap.value))
		lots.append({"position":Blueprint.arr(Blueprint.vec(at.position)+basis*offset),"yaw":at.yaw,"seed_offset":index})
	return {"parameters":p,"placements":lots}

func preview() -> void:
	clear_preview()
	var replacing := selected_id()
	var request := args()
	if not replacing.is_empty(): request.placements = [placement.values()]
	var result: Dictionary = editor._buildings.prepare(request,replacing)
	if not result.ok: report(result); return
	if not replacing.is_empty():
		for id in editor._buildings.instances()[replacing].parts.values():
			var visual: Node3D = editor._view.get_node_or_null(NodePath(str(id)))
			if visual!=null: hidden_sources.append([visual,visual.visible]); visual.hide()
	ghost = Node3D.new(); ghost.name = "BuildingPreview"; editor.add_child(ghost)
	for plan in result.plans:
		for record in plan.records:
			var mesh: MeshInstance3D = editor._doc._mesh(record); mesh.transparency = .35; ghost.add_child(mesh)
	report({"ok":true,"message":"预览 %d 栋，未写入地图。参数改变后请重新预览。"%result.plans.size()})
	frame(result.plans[0].bounds)

func clear_preview() -> void:
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
	report(editor._buildings.generate(args()))

func update_building() -> void:
	var at: Dictionary = placement.values()
	report(editor._buildings.update(selected_id(),form.values(),at.position,at.yaw))

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
