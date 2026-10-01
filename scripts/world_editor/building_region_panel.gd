extends VBoxContainer
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
var panel: VBoxContainer
var style: OptionButton
var mode: OptionButton
var density: OptionButton
var facing: OptionButton
var height: SpinBox
var pick: Button
var apply: Button
var refine: Button
var info: Label
var feedback: Label
var corners: Array=[]
var drawing := false
var dragging := false
var start := Vector3.ZERO
var finish := Vector3.ZERO
var seed := 1
var cached: Dictionary={}
var plans: Array=[]
var guide: MeshInstance3D

func setup(owner: VBoxContainer) -> void:
	panel=owner; add_theme_constant_override("separation",6)
	var title:=Label.new(); title.text="区域随机方案"; add_child(title)
	var note:=Label.new(); note.text="拖出地块，松手预览；换一案，再应用。自动避让已有物体。"; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	style=choice([["urban_village","城中村自建房"],["medieval","中世纪店屋"],["standard","普通住宅"]])
	var row:=HBoxContainer.new(); add_child(row)
	mode=choice([["single","单栋建筑"],["block","成片建筑"]],row)
	density=choice([["medium","常规间距"],["low","宽松间距"],["high","紧凑间距"]],row)
	facing=choice([[0,"正门朝 −Z"],[90,"正门朝 −X"],[180,"正门朝 +Z"],[-90,"正门朝 +X"]])
	height=SpinBox.new(); height.prefix="地面标高 Y"; height.min_value=-10000; height.max_value=10000; height.step=.1; add_child(height)
	row=HBoxContainer.new(); add_child(row)
	pick=action(row,"拖框选区域",begin_draw); action(row,"用选中地面",use_selection)
	row=HBoxContainer.new(); add_child(row)
	action(row,"换一案",reroll); apply=action(row,"应用方案",accept); apply.disabled=true
	row=HBoxContainer.new(); add_child(row)
	refine=action(row,"单栋微调",refine_one); refine.disabled=true; action(row,"清除区域",clear)
	info=Label.new(); info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(info)
	feedback=Label.new(); feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(feedback)
	for control in [style,mode,density,facing]: control.item_selected.connect(func(_index): preview())
	height.value_changed.connect(func(value):
		cancel_draw()
		for corner in corners: corner[1]=value
		refresh_guide(); preview()
	)
	panel.editor._dock_tabs.tab_changed.connect(func(index): if index!=8: cancel_draw())
	refresh_info()

func choice(options: Array, parent: Node = null) -> OptionButton:
	var control:=OptionButton.new(); control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for entry in options: control.add_item(entry[1]); control.set_item_metadata(control.item_count-1,entry[0])
	(parent if parent!=null else self).add_child(control); return control

func action(parent: Node, title: String, callback: Callable) -> Button:
	var control:=Button.new(); control.text=title; control.size_flags_horizontal=Control.SIZE_EXPAND_FILL; control.pressed.connect(callback); parent.add_child(control); return control

func request() -> Dictionary:
	return {"from":corners[0],"to":corners[1],"style":style.get_item_metadata(style.selected),"mode":mode.get_item_metadata(mode.selected),"density":density.get_item_metadata(density.selected),"yaw":facing.get_item_metadata(facing.selected),"seed":seed,"max_buildings":8}

func report(result: Dictionary) -> void:
	panel.report(result); feedback.text=panel.report_label.text

func refresh_info() -> void:
	info.text="尚未选择区域" if corners.size()!=2 else "区域 %.1f × %.1f 米 · 方案种子 %d"%[absf(corners[0][0]-corners[1][0]),absf(corners[0][2]-corners[1][2]),seed]

func invalidate_preview() -> void:
	cached.clear(); plans.clear()
	if apply!=null: apply.disabled=true
	if refine!=null: refine.disabled=true
	if feedback!=null: feedback.text=""

func preview() -> void:
	cancel_draw(); panel.clear_preview(); refresh_info()
	if corners.size()!=2: return
	var result: Dictionary=panel.editor._buildings.prepare_region(request())
	if not result.ok: report(result); return
	panel.show_preview(result,"",false)
	cached=request().duplicate(true); cached.plan_token=result.plan_token; plans=result.plans
	apply.disabled=false; refine.disabled=plans.size()!=1
	report({"ok":true,"message":"预览 %d 栋，跳过 %d 个放不下的位置。尚未写入地图。"%[plans.size(),result.region.skipped_slots]})

func reroll() -> void:
	if corners.size()!=2: report(Blueprint.fail("请先拖框或选择一块地面")); return
	seed=(seed+1)%2147483648; preview()

func accept() -> void:
	if cached.is_empty(): return
	var result: Dictionary=panel.editor._buildings.generate_region(cached.duplicate(true))
	if result.ok: result.message="已生成 %d 栋建筑，可一次撤销。"%result.building_ids.size()
	report(result)
	if not result.ok: apply.disabled=true

func refine_one() -> void:
	if plans.size()!=1: return
	var plan: Dictionary=plans[0]
	panel.street.enabled.button_pressed=false; panel.count.value=1; panel.columns.value=1
	panel.chooser.select(0); panel.set_values(plan.parameters,plan.position,plan.yaw)
	panel.details_toggle.button_pressed=true; panel.preview()

func begin_draw() -> void:
	if drawing: cancel_draw(); return
	panel.editor._finish_edits()
	var ready: Dictionary=panel.editor._gameplay.guard()
	if not ready.ok: report(ready); return
	panel.street.drawing=false; panel.street.refresh()
	panel.clear_preview(); drawing=true; pick.text="取消框选"
	report({"ok":true,"message":"在地图上按住左键拖出区域；Esc 取消。"})

func cancel_draw() -> void:
	drawing=false; dragging=false
	if pick!=null: pick.text="拖框选区域"
	refresh_guide()

func clear() -> void:
	corners.clear(); cancel_draw(); panel.clear_preview(); refresh_info()

func use_selection() -> void:
	panel.editor._finish_edits()
	var ready: Dictionary=panel.editor._gameplay.guard()
	if not ready.ok: report(ready); return
	var records: Array=[]; var y := INF
	for id in panel.editor._selection_tools.ids:
		var record: Dictionary=panel.editor._doc._find(id)
		if not panel.editor._record_editable(record) or record.get("surface_id")!="ground": report(Blueprint.fail("请选择可编辑的水平地面物件")); return
		var rotation:=Basis.from_euler(Geometry.vector(record,"rotation")*PI/180)
		var top:=Geometry.bounds([record]).end.y
		if rotation.y.dot(Vector3.UP)<.999 or (y!=INF and absf(y-top)>.005): report(Blueprint.fail("选中的地面必须水平且顶面同高")); return
		y=top; records.append(record)
	if records.is_empty(): report(Blueprint.fail("请先选中地面物件，或直接使用拖框选区域")); return
	var bounds:=Geometry.bounds(records); height.set_value_no_signal(y)
	corners=[[bounds.position.x,y,bounds.position.z],[bounds.end.x,y,bounds.end.z]]
	panel.street.drawing=false; panel.street.refresh(); refresh_guide(); preview()
	panel.frame({"position":[bounds.position.x,y,bounds.position.z],"size":[bounds.size.x,8,bounds.size.z]})

func point(screen: Vector2) -> Variant:
	var camera: Camera3D=panel.editor._camera
	return Plane(Vector3.UP,height.value).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))

func input(event: InputEvent) -> bool:
	if not drawing: return false
	if event is InputEventKey:
		if event.pressed and event.keycode==KEY_ESCAPE: cancel_draw(); report({"ok":true,"message":"已取消区域框选。"})
		return true
	var canvas: Control=panel.editor._canvas
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed and canvas.get_global_rect().has_point(event.position):
			var hit: Variant=point(event.position-canvas.global_position)
			if hit!=null: start=hit; finish=hit; dragging=true; refresh_guide()
			return true
		if not event.pressed and dragging:
			if not canvas.get_global_rect().has_point(event.position): cancel_draw(); report(Blueprint.fail("已取消框选，请在地图画布内松开鼠标")); return true
			var hit: Variant=point(event.position-canvas.global_position)
			if hit==null: cancel_draw(); return true
			finish=hit; corners=[Blueprint.arr(start),Blueprint.arr(finish)]; cancel_draw(); preview(); return true
	if event is InputEventMouseMotion and dragging:
		if canvas.get_global_rect().has_point(event.position):
			var hit: Variant=point(event.position-canvas.global_position)
			if hit!=null: finish=hit; refresh_guide()
		return true
	return false

func refresh_guide() -> void:
	if is_instance_valid(guide): guide.free()
	guide=null
	if not dragging and corners.size()!=2: return
	var a:=start if dragging else Blueprint.vec(corners[0]); var b:=finish if dragging else Blueprint.vec(corners[1])
	var vertices: Array[Vector3]=[a,Vector3(b.x,a.y,a.z),b,Vector3(a.x,a.y,b.z),a]
	var mesh:=ImmediateMesh.new(); var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color(.3,.85,1); material.no_depth_test=true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for i in 4:
		for v in [vertices[i],vertices[i+1]]: mesh.surface_add_vertex(v+Vector3(0,.06,0))
	mesh.surface_end(); guide=MeshInstance3D.new(); guide.mesh=mesh; panel.editor.add_child(guide)

func _exit_tree() -> void:
	if is_instance_valid(guide): guide.queue_free()
