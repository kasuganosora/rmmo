extends VBoxContainer
const Schema = preload("res://scripts/world_editor/building_street.gd")
var panel: VBoxContainer
var enabled: CheckButton
var form: VBoxContainer
var points: Array=[]
var drawing := false
var pick: Button
var label: Label
var guide: MeshInstance3D

func setup(parent_panel: VBoxContainer) -> void:
	panel=parent_panel
	enabled=CheckButton.new(); enabled.text="沿街批量布置"; add_child(enabled)
	var body:=VBoxContainer.new(); add_child(body); body.hide()
	enabled.toggled.connect(func(value): body.visible=value; drawing=false; panel.clear_preview(); refresh())
	var note:=Label.new(); note.text="在位置 Y 的水平面点选道路中心线。只放建筑；道路用道路笔刷绘制。Esc 结束点选。"; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; body.add_child(note)
	var row:=HBoxContainer.new(); body.add_child(row)
	pick=Button.new(); pick.text="点选中心线"; row.add_child(pick)
	pick.pressed.connect(func():
		var ready: Dictionary=panel.editor._gameplay.guard()
		if not ready.ok: panel.report(ready); return
		panel.editor._placement_tools.cancel(); panel.editor._material_tool.cancel(); drawing=not drawing; refresh()
	)
	var back:=Button.new(); back.text="退一点"; row.add_child(back); back.pressed.connect(func(): if not points.is_empty(): points.pop_back(); refresh())
	var clear:=Button.new(); clear.text="清空"; row.add_child(clear); clear.pressed.connect(func(): points.clear(); refresh())
	label=Label.new(); body.add_child(label)
	form=preload("res://scripts/world_editor/settings_form.gd").new(); body.add_child(form)
	form.build(Schema.schema(),{"road_width":6.0,"setback":.6,"gap":1.0,"side":"both","width_variation":.12,"max_buildings":8},{"road_width":"道路宽度（米）","setback":"屋檐到道路退距","gap":"建筑间距","side":"生成侧别","width_variation":"宽度变化比例","max_buildings":"最多栋数"},{"side":[{"id":"both","name":"两侧"},{"id":"left","name":"左侧"},{"id":"right","name":"右侧"}]})
	refresh()

func request() -> Dictionary:
	var args: Dictionary=form.values(); args.points=points.duplicate(true); args.parameters=panel.form.values(); return args

func input(event: InputEvent) -> bool:
	if drawing and panel.editor._dock_tabs.current_tab!=8: drawing=false; refresh()
	if not drawing or not enabled.button_pressed: return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: drawing=false; refresh(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and panel.editor._canvas.get_global_rect().has_point(event.position):
		if event.pressed:
			var screen: Vector2=event.position-panel.editor._canvas.global_position
			var camera: Camera3D=panel.editor._camera
			var y: float=panel.placement.values().position[1]
			var hit: Variant=Plane(Vector3.UP,y).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
			if hit!=null:
				if points.size()>=32: panel.report({"ok":false,"error":"中心线最多 32 个点"})
				else: points.append([snappedf(hit.x,.1),y,snappedf(hit.z,.1)]); refresh()
		return true
	return false

func refresh() -> void:
	if label!=null: label.text="中心线：%d 个点"%points.size()
	if pick!=null: pick.text="结束点选" if drawing else "点选中心线"
	if is_instance_valid(guide): guide.free()
	guide=null
	if not enabled.button_pressed or points.size()<2: return
	var mesh:=ImmediateMesh.new(); var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color(1,.72,.15)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for i in points.size()-1:
		for value in [points[i],points[i+1]]: mesh.surface_add_vertex(Vector3(value[0],value[1]+.08,value[2]))
	mesh.surface_end(); guide=MeshInstance3D.new(); guide.mesh=mesh; panel.editor.add_child(guide)

func _exit_tree() -> void:
	if is_instance_valid(guide): guide.queue_free()
