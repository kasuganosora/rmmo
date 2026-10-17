extends VBoxContainer
## The UI emits exactly the same endpoint constraints as the 3D MCP tools.
const Tools=preload("res://scripts/world_editor/terrain_ramp_tools.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor:Node3D
var terrain_panel:VBoxContainer
var fields:VBoxContainer
var result_label:Label
var apply_button:Button
var preview_button:Button
var preview_result:Dictionary={}
var overlay:MeshInstance3D
var document_id:=0
var preview_revision:=-1

func note(text:String)->Label:
	var item:=Label.new();item.text=text;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(item);return item
func button(text:String,action:Callable)->Button:
	var item:=Button.new();item.text=text;item.pressed.connect(action);add_child(item);return item
func setup(value:Node3D,owner_panel:VBoxContainer,footer:VBoxContainer)->void:
	editor=value;terrain_panel=owner_panel;add_theme_constant_override("separation",8)
	note("设置两端位置与标高，生成全宽平直坡道。可以先取实际地面高度，再调整端点 Y。最大坡度 15%，长度 1–48 米。")
	fields=Form.new();add_child(fields)
	fields.build(Tools.schema(),{"start":[-5.,0.,0.],"end":[5.,1.,0.],"width":3.,"blend_margin":2.,"cross_tiles":true},{"start":"起点（世界 X / Y / Z 米）","end":"终点（世界 X / Y / Z 米）","width":"坡道净宽（米）","blend_margin":"外围柔和过渡（米）","cross_tiles":"同步相邻地形接缝"})
	preload("res://scripts/world_editor/terrain_form_layout.gd").apply(fields,{"width":"净宽 (m)","blend_margin":"柔边 (m)","cross_tiles":"同步相邻地形接缝"})
	for key:String in fields.fields:
		var control:Control=fields.fields[key]
		if control is HBoxContainer:
			for spin:SpinBox in control.get_children():spin.value_changed.connect(func(_v):invalidate())
		elif control is SpinBox:control.value_changed.connect(func(_v):invalidate())
		elif control is CheckButton:control.toggled.connect(func(_v):invalidate())
	button("起点：取此 X / Z 的地面高度",func():sample_endpoint("start"))
	button("终点：取此 X / Z 的地面高度",func():sample_endpoint("end"))
	button("起点：取当前视图中心地面",func():sample_endpoint("start",true))
	button("终点：取当前视图中心地面",func():sample_endpoint("end",true))
	button("将起点标高用于雕刻平台",func():
		var values:Dictionary=terrain_panel.brush_fields.values();values.target_height=fields.values().start[1];terrain_panel.brush_fields.update_values(values))
	preview_button=button("预览并检查坡道",func():execute(false))
	apply_button=button("应用已检查的坡道",func():execute(true));apply_button.disabled=true
	var cancel_button:=button("取消预览",invalidate)
	result_label=note("预览通过后可应用；一次撤销包含地形与跟随构件。外围柔边不保证通行，重复应用会继续调整柔边。")
	result_label.reparent(footer)
	var actions:=HBoxContainer.new();footer.add_child(actions)
	for item:Button in [preview_button,apply_button]:item.reparent(actions);item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preview_button.text="检查坡道";apply_button.text="应用坡道";cancel_button.reparent(footer)
	visibility_changed.connect(func():if not is_visible_in_tree():invalidate())
	refresh()
func request()->Dictionary:
	var args:Dictionary=fields.values();args.id=terrain_panel.selected();return args
func sample_endpoint(key:String,view_center:=false)->Dictionary:
	var values:Dictionary=fields.values();var point:Array=values[key]
	var x:float=editor._orbit_center.x if view_center else point[0]
	var z:float=editor._orbit_center.z if view_center else point[2]
	var result:=Tools.sample(editor,{"id":terrain_panel.selected(),"point":[x,z]})
	if result.ok:values[key]=result.position;fields.update_values(values);invalidate();result_label.text="实际地面标高：%.3f 米"%result.height
	else:result_label.text=str(result.error)
	return result
func invalidate()->void:
	preview_result.clear()
	if apply_button!=null:apply_button.disabled=true
	if is_instance_valid(overlay):overlay.queue_free();overlay=null
	if result_label!=null:result_label.text="参数或地图可能已变化，请重新检查坡道。"
func execute(commit:bool)->Dictionary:
	editor._finish_edits()
	var args:=request()
	if commit:
		if preview_result.is_empty():return Tools.fail("请先预览并检查坡道")
		args.expected_token=preview_result.token
	var result:=Tools.apply(editor,args) if commit else Tools.preview(editor,args)
	invalidate()
	if result.ok:
		if not commit:preview_result=result;preview_revision=editor._doc.authoring_revision;apply_button.disabled=false;show_preview(result)
		result_label.text=("已应用，可一次撤销。\n" if commit else "检查通过，地图尚未修改。\n")+"坡度 %.2f%% · 最大实际坡度 %.2f%%\n端点及全宽误差 ≤ %.4f m · 接缝 %.4f m\n挖方 %.2f m³ / 填方 %.2f m³\n网格保障外扩 %.2f m + 柔边 %.2f m\n影响 %d 个构件"%[result.grade*100,result.max_grade*100,result.max_height_error,result.max_seam_step,result.earthwork.cut_m3,result.earthwork.fill_m3,result.grid_padding,result.blend_margin,result.affected_ids.size()]
		result_label.tooltip_text="受影响构件：\n"+"\n".join(result.affected_ids)+"\n外围柔边不保证通行，重复应用会继续调整柔边。"
	else:result_label.text=str(result.get("error","坡道操作失败"))
	editor._report_result(result,"坡道已应用" if commit else "坡道检查通过","两端定高坡道")
	return result
func show_preview(result:Dictionary)->void:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var start:=Vector3(result.start[0],result.start[1],result.start[2]);var end:=Vector3(result.end[0],result.end[1],result.end[2])
	var direction:=(end-start)*Vector3(1,0,1);direction=direction.normalized()
	for i in 4:
		for p:Array in [result.corridor[i],result.corridor[(i+1)%4]]:
			var height:float=start.y+Vector3(p[0]-start.x,0,p[1]-start.z).dot(direction)*result.grade
			mesh.surface_add_vertex(Vector3(p[0],height+.025,p[1]))
	mesh.surface_add_vertex(start+Vector3.UP*.025);mesh.surface_add_vertex(end+Vector3.UP*.025);mesh.surface_end()
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.2,1.,.55);material.no_depth_test=true
	overlay=MeshInstance3D.new();overlay.mesh=mesh;overlay.material_override=material;overlay.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;editor.add_child(overlay)
func refresh()->void:
	if fields==null:return
	if document_id!=editor._doc.get_instance_id():
		document_id=editor._doc.get_instance_id()
		var x:float=editor._orbit_center.x;var z:float=editor._orbit_center.z
		fields.update_values({"start":[x-5.,0.,z],"end":[x+5.,1.,z],"width":3.,"blend_margin":2.,"cross_tiles":true})
	invalidate()
func _exit_tree()->void:
	if is_instance_valid(overlay):overlay.queue_free()
func _process(_delta:float)->void:
	if not preview_result.is_empty() and (document_id!=editor._doc.get_instance_id() or preview_revision!=editor._doc.authoring_revision):invalidate()
