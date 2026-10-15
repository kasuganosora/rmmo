extends VBoxContainer
## Frozen-house placement and its access road share one candidate transaction.
const Placement = preload("res://scripts/world_editor/residential_placement_tools.gd")
const City = preload("res://scripts/world3d/city_layout.gd")
const Keys = preload("res://scripts/world_editor/asset_thumbnails.gd")
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
var panel: VBoxContainer
var editor: Node3D
var asset_choice: OptionButton
var road_choice: OptionButton
var form: VBoxContainer
var preview_button: Button
var apply_button: Button
var discard_button: Button
var focus_button: Button
var feedback: Label
var plan_token := ""
var last_result: Dictionary = {}
var ghost: Node3D

func setup(owner: VBoxContainer) -> void:
	panel=owner; editor=panel.editor
	add_theme_constant_override("separation",6)
	var toggle:=CheckButton.new(); toggle.text="冻结住宅与入户路"; add_child(toggle)
	var body:=VBoxContainer.new(); body.add_theme_constant_override("separation",6); add_child(body); body.hide()
	toggle.toggled.connect(func(open):
		body.visible=open
		if open: refresh_catalogs()
	)
	note(body,"选择已烘焙的单栋 townhouse／hall 住宅与普通直线地面道路。路网须已有沿地形铺面且无桥梁绑定；在允许范围内检查标高和门前退距，保留邻物与地形。")
	note(body,"住宅预制件（当前与共享素材库）")
	asset_choice=OptionButton.new(); asset_choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(asset_choice)
	var row:=HBoxContainer.new(); body.add_child(row)
	action(row,"取当前素材",use_selected_asset); action(row,"刷新列表",refresh_catalogs)
	note(body,"接入已有道路")
	road_choice=OptionButton.new(); road_choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(road_choice)
	form=preload("res://scripts/world_editor/settings_form.gd").new(); body.add_child(form)
	var values:Dictionary={"position":[0,0,0]}
	values.merge(Placement.defaults(),true); values.erase("asset_id"); values.erase("road_edge_id")
	form.build(Placement.request_schema(),values,{"position":"住宅原点 XYZ（米）","yaw":"附加旋转（度）","elevation_min":"允许降低至（相对输入 Y，米）","elevation_max":"允许升高至（相对输入 Y，米）","setback_min":"门前退距下限（米）","setback_max":"门前退距上限（米）","width":"入户路宽度（米）"})
	action(body,"取画面中心表面坐标",use_view_center)
	row=HBoxContainer.new(); body.add_child(row)
	preview_button=action(row,"预览并检查",preview)
	apply_button=action(row,"应用整套方案",apply_candidate); apply_button.disabled=true
	discard_button=action(row,"放弃预览",discard_preview); discard_button.disabled=true
	focus_button=action(body,"定位结果／冲突",focus_result); focus_button.disabled=true
	feedback=note(body,"先选择住宅与道路，再预览。预制件的住宅结构由共享校验确认。")
	asset_choice.item_selected.connect(func(_i): invalidate_preview())
	road_choice.item_selected.connect(func(_i): invalidate_preview())
	for control in form.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v): invalidate_preview())
		elif control is HBoxContainer:
			for spin in control.get_children(): spin.value_changed.connect(func(_v): invalidate_preview())
	refresh_catalogs()

func note(parent: Node, text_: String) -> Label:
	var value:=Label.new(); value.text=text_; value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(value); return value

func action(parent: Node, text_: String, callback: Callable) -> Button:
	var value:=Button.new(); value.text=text_; value.size_flags_horizontal=Control.SIZE_EXPAND_FILL; value.pressed.connect(callback); parent.add_child(value); return value

func selected(control: OptionButton) -> String:
	return str(control.get_item_metadata(control.selected)) if control.selected>=0 else ""

func refresh_catalogs() -> void:
	if asset_choice==null or road_choice==null: return
	var asset_id:=selected(asset_choice); var road_id:=selected(road_choice)
	asset_choice.clear(); asset_choice.add_item("请选择住宅预制件"); asset_choice.set_item_metadata(0,"")
	for entry:Dictionary in editor.asset_items():
		if not entry.has("prefab_path"): continue
		var id:=Keys.key_for(entry)
		asset_choice.add_item(str(entry.get("label","未命名预制件"))); asset_choice.set_item_metadata(asset_choice.item_count-1,id)
		if id==asset_id: asset_choice.select(asset_choice.item_count-1)
	road_choice.clear(); road_choice.add_item("请选择已有道路"); road_choice.set_item_metadata(0,"")
	for edge:Dictionary in City.resolve(editor._doc.map_meta).roads.edges:
		road_choice.add_item("%s · %s"%[str(edge.get("name",edge.id)),str(edge.id)]); road_choice.set_item_metadata(road_choice.item_count-1,str(edge.id))
		if str(edge.id)==road_id: road_choice.select(road_choice.item_count-1)
	if selected(asset_choice)!=asset_id or selected(road_choice)!=road_id: invalidate_preview("素材或道路列表已变化，请重新预览。")

func request() -> Dictionary:
	var result:Dictionary=form.values()
	result.asset_id=selected(asset_choice); result.road_edge_id=selected(road_choice)
	return result

func use_selected_asset() -> void:
	refresh_catalogs()
	var entry:Dictionary=editor._selected()
	var id:=Keys.key_for(entry) if entry.has("prefab_path") else ""
	for index in asset_choice.item_count:
		if not id.is_empty() and asset_choice.get_item_metadata(index)==id:
			asset_choice.select(index); invalidate_preview(); return
	report({"ok":false,"error":"请先在素材面板选择住宅预制件，或使用上方列表。"})

func use_view_center() -> void:
	var screen:Vector2=editor._canvas.size*.5
	var origin:Vector3=editor._camera.project_ray_origin(screen)
	var ray:=PhysicsRayQueryParameters3D.create(origin,origin+editor._camera.project_ray_normal(screen)*editor._camera.far)
	var hit:Dictionary=editor.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.5:
		report({"ok":false,"error":"画面中心没有可拾取的朝上表面，请调整视角或填写 XYZ。"}); return
	var values:Dictionary=form.values(); values.position=Blueprint.arr(hit.position)
	form.update_values(values); invalidate_preview("已取画面中心坐标，请预览检查。")

func preview() -> void:
	# Flush a number still being typed before capturing the request.
	var args:=request()
	panel.clear_preview()
	var result:Dictionary=editor._residential.preview(args)
	if result.ok:
		plan_token=str(result.plan_token)
		show_visual(editor._residential.preview_visual(plan_token))
		apply_button.disabled=false; discard_button.disabled=false
	report(result)

func show_visual(records: Array) -> void:
	if records.is_empty(): return
	ghost=Node3D.new(); ghost.name="ResidentialPlacementPreview"; editor.add_child(ghost)
	for record:Dictionary in records:
		var visual:MeshInstance3D=editor._doc._mesh(record)
		visual.transparency=.4; visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(visual)
	# Preview meshes have no physics bodies and are outside the selectable view.

func apply_candidate() -> void:
	# Applying a pending SpinBox edit triggers invalidation before this guard.
	form.values()
	if plan_token.is_empty(): report({"ok":false,"error":"请先预览当前参数。"}); return
	var result:Dictionary=editor._residential.apply({"plan_token":plan_token})
	invalidate_preview("")
	report(result,true)

func invalidate_preview(message: String="参数已变化，请重新预览。") -> void:
	var had_preview:=not plan_token.is_empty()
	if had_preview and is_instance_valid(editor): editor._residential.discard(plan_token)
	plan_token=""
	if is_instance_valid(ghost): ghost.free()
	ghost=null
	if apply_button!=null: apply_button.disabled=true
	if discard_button!=null: discard_button.disabled=true
	last_result={}
	if focus_button!=null: focus_button.disabled=true
	if not message.is_empty() and feedback!=null: feedback.text=message; editor._status.text=message

func discard_preview() -> void:
	invalidate_preview("已放弃候选；地图未修改。")

func report(result: Dictionary, applied: bool=false) -> void:
	last_result=result.duplicate(true)
	var text_:String
	if result.ok:
		if applied: text_="住宅与入户路已一起应用，可一次撤销。请按原生流程保存地图。"
		else:
			var p:Array=result.get("position",[]); var delta:Array=result.get("adjustment",[])
			text_="候选已通过共享校验，尚未写入地图。"
			if p.size()==3: text_+="\n最终位置：%.3f, %.3f, %.3f 米"%[p[0],p[1],p[2]]
			if delta.size()==3: text_+=" · 标高调整 %+.3f 米"%float(delta[1])
			text_+="\n门前退距 %.2f 米 · 路宽 %.2f 米"%[float(result.get("setback",0)),float(result.get("width",0))]
	else:
		text_=str(result.get("error","方案未通过"))
		if result.has("code"): text_+="\n"+str(result.code)
		if result.has("stage"): text_+=" · "+str(result.stage)
		var last:Dictionary=result.get("last_failure",{})
		if not last.is_empty(): text_+="\n最后一次检查："+str(last.get("error",last.get("code","未通过")))
		var detail:=diagnostic(result)
		if detail.has("position"): text_+="\n见证位置："+str(detail.position)
		if detail.has("conflicts"): text_+="\n冲突物件："+str(detail.conflicts)
		elif detail.has("terrain_id"): text_+="\n地形："+str(detail.terrain_id)
	feedback.text=text_; editor._status.text=text_
	var location:=diagnostic(result)
	focus_button.disabled=not result.has("bounds") and not location.has("position") and location.get("conflicts",[]).is_empty() and not location.has("terrain_id") and not location.has("record_id")

func diagnostic(result: Dictionary, depth: int=0) -> Dictionary:
	# Search exhaustion and support intervals keep their concrete witness nested.
	if depth<8:
		for key in ["last_failure","terrain_contact","lower_witness","upper_witness","grade_witness","seam_witness","witness"]:
			if result.get(key) is Dictionary:
				var detail:=diagnostic(result[key],depth+1)
				if detail.has("position") or detail.has("conflicts") or detail.has("terrain_id") or detail.has("record_id"): return detail
	return result

func focus_result() -> void:
	if last_result.has("bounds"): panel.frame(last_result.bounds); return
	var location:=diagnostic(last_result)
	var point:Variant=location.get("position")
	if point is Array and point.size()==3:
		var p:=Blueprint.vec(point)
		panel.frame({"position":Blueprint.arr(p-Vector3(2,1,2)),"size":[4,4,4]}); return
	var ids:Array=location.get("conflicts",[]).duplicate()
	for key in ["terrain_id","record_id"]:
		if location.has(key): ids.append(str(location[key]))
	var records:Array=editor._doc.records.filter(func(record): return str(record.uuid) in ids)
	if not records.is_empty():
		var bounds:=preload("res://scripts/world_editor/selection_geometry.gd").bounds(records)
		panel.frame({"position":Blueprint.arr(bounds.position),"size":Blueprint.arr(bounds.size)})

func _exit_tree() -> void:
	invalidate_preview("")
