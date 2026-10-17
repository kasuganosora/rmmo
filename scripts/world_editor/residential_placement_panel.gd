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
var site_enabled:CheckButton
var site_draft:VBoxContainer
var changes_view:TextEdit
var diagnostics:VBoxContainer
var preview_doc_id:=0
var preview_revision:=-1
var relocation_enabled:CheckButton
var building_choice:OptionButton
var old_access_choice:OptionButton
var relocation_body:VBoxContainer
var block_enabled:CheckButton
var block_draft:VBoxContainer
var entrance_choice:OptionButton
var entrance_feedback:Label
var support_choice:OptionButton

func setup(owner: VBoxContainer) -> void:
	panel=owner; editor=panel.editor
	add_theme_constant_override("separation",6)
	var toggle:=CheckButton.new(); toggle.text="冻结住宅与入户路"; add_child(toggle)
	var body:=VBoxContainer.new(); body.add_theme_constant_override("separation",6); add_child(body); body.hide()
	toggle.toggled.connect(func(open):
		body.visible=open
		if open: refresh_catalogs()
	)
	note(body,"选择已烘焙的单栋 townhouse／hall 住宅与普通直线／弯曲地面道路。路网须已有沿地形铺面，可包含已绑定桥梁；保持桥梁和河道不变，不直接接入桥面或桥头节点。在允许范围内检查标高和门前退距，保留邻物；默认保留地形，也可开启下方联合整地。")
	note(body,"住宅预制件（当前与共享素材库）")
	asset_choice=OptionButton.new(); asset_choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(asset_choice)
	var row:=HBoxContainer.new(); body.add_child(row)
	action(row,"取当前素材",use_selected_asset); action(row,"刷新列表",refresh_catalogs)
	relocation_enabled=CheckButton.new();relocation_enabled.text="迁移已有住宅（保留建筑与构件身份）";body.add_child(relocation_enabled)
	relocation_body=VBoxContainer.new();body.add_child(relocation_body);relocation_body.hide()
	building_choice=OptionButton.new();relocation_body.add_child(building_choice)
	action(relocation_body,"取当前选中建筑及原点",use_selected_building)
	old_access_choice=OptionButton.new();relocation_body.add_child(old_access_choice)
	old_access_choice.add_item("保留旧入户路（默认）");old_access_choice.set_item_metadata(0,"keep")
	old_access_choice.add_item("移除有归属且未改的旧支路");old_access_choice.set_item_metadata(1,"remove_owned")
	note(relocation_body,"附加旋转相对原朝向。默认保留旧路、旧地形；仅凭已有归属记录移除专属末端支路，保留公共接点和主路。旧、新地块需整地时在下方显式添加。")
	relocation_enabled.toggled.connect(func(enabled):
		invalidate_preview();relocation_body.visible=enabled;asset_choice.disabled=enabled;refresh_catalogs()
	)
	building_choice.item_selected.connect(func(_i):invalidate_preview();refresh_entrances())
	old_access_choice.item_selected.connect(func(_i):invalidate_preview())
	note(body,"接入已有道路")
	road_choice=OptionButton.new(); road_choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; body.add_child(road_choice)
	note(body,"接路入口（多入口时必须选择）")
	entrance_choice=OptionButton.new();entrance_choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;body.add_child(entrance_choice)
	entrance_choice.item_selected.connect(func(_i):invalidate_preview())
	action(body,"读取入口和支撑域",refresh_entrances)
	support_choice=OptionButton.new();body.add_child(support_choice)
	support_choice.add_item("沿用已保存结构／新住宅采用连续基础");support_choice.set_item_metadata(0,"auto")
	support_choice.add_item("明确采用连续基础");support_choice.set_item_metadata(1,"continuous")
	support_choice.add_item("柱墩支撑（保留楼下净空）");support_choice.set_item_metadata(2,"piers")
	support_choice.item_selected.connect(func(_i):invalidate_preview();refresh_entrances())
	entrance_feedback=note(body,"读取实际冻结入口；入口可用后仍需预览整套方案。")
	form=preload("res://scripts/world_editor/settings_form.gd").new(); body.add_child(form)
	var values:Dictionary={"position":[0,0,0]}
	values.merge(Placement.defaults(),true); values.erase("asset_id"); values.erase("road_edge_id")
	form.build(Placement.request_schema(),values,{"position":"住宅／素材放置点 XYZ（米）","yaw":"附加旋转（度）","elevation_min":"允许降低至（相对输入 Y，米）","elevation_max":"允许升高至（相对输入 Y，米）","setback_min":"门前退距下限（米）","setback_max":"门前退距上限（米）","width":"入户路宽度（米）"})
	action(body,"取画面中心表面坐标",use_view_center)
	block_enabled=CheckButton.new();block_enabled.text="多栋住宅：街区联合候选";body.add_child(block_enabled)
	block_draft=preload("res://scripts/world_editor/residential_block_panel.gd").new();body.add_child(block_draft);block_draft.setup(self);block_draft.hide()
	block_enabled.toggled.connect(func(value):invalidate_preview();block_draft.visible=value)
	site_enabled=CheckButton.new();site_enabled.text="同时整地：联合预览与一次应用";body.add_child(site_enabled)
	site_draft=preload("res://scripts/world_editor/residential_site_panel.gd").new();body.add_child(site_draft);site_draft.setup(self);site_draft.hide()
	site_draft.changed.connect(invalidate_preview)
	site_enabled.toggled.connect(func(value):
		invalidate_preview();site_draft.visible=value
		if value and site_draft.plots.is_empty() and not site_draft.ramp_enabled.button_pressed:site_draft.add_plot()
	)

	row=HBoxContainer.new(); body.add_child(row)
	preview_button=action(row,"预览并检查",preview)
	apply_button=action(row,"应用整套方案",apply_candidate); apply_button.disabled=true
	discard_button=action(row,"放弃预览",discard_preview); discard_button.disabled=true
	focus_button=action(body,"定位结果／冲突",focus_result); focus_button.disabled=true
	feedback=note(body,"先选择住宅与道路，再预览。预制件的住宅结构由共享校验确认。")
	diagnostics=preload("res://scripts/world_editor/diagnostic_panel.gd").new();body.add_child(diagnostics);diagnostics.setup(editor)
	changes_view=TextEdit.new();changes_view.editable=false;changes_view.custom_minimum_size.y=140;changes_view.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;body.add_child(changes_view);changes_view.hide()
	asset_choice.item_selected.connect(func(_i): invalidate_preview();refresh_entrances())
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
	if site_draft!=null:site_draft.refresh_catalogs()
	if building_choice!=null:
		var building_id:=selected(building_choice);building_choice.clear();building_choice.add_item("请选择已有住宅");building_choice.set_item_metadata(0,"")
		for id:String in editor._doc.map_meta.get("building_instances",{}):
			var value:Dictionary=editor._doc.map_meta.building_instances[id]
			if not value.get("baked",false) or value.parameters.get("template")!="house" or value.parameters.get("layout") not in ["townhouse","hall"]:continue
			building_choice.add_item(id);building_choice.set_item_metadata(building_choice.item_count-1,id)
			if id==building_id:building_choice.select(building_choice.item_count-1)
		if selected(building_choice)!=building_id:invalidate_preview("建筑列表已变化，请重新预览。")
	var asset_id:=selected(asset_choice); var road_id:=selected(road_choice)
	asset_choice.clear(); asset_choice.add_item("请选择住宅预制件"); asset_choice.set_item_metadata(0,"")
	for entry:Dictionary in editor.asset_items():
		if not entry.has("prefab_path"): continue
		var id:=Keys.key_for(entry)
		asset_choice.add_item(str(entry.get("label","未命名预制件"))); asset_choice.set_item_metadata(asset_choice.item_count-1,id)
		if id==asset_id: asset_choice.select(asset_choice.item_count-1)
	road_choice.clear(); road_choice.add_item("请选择已有道路"); road_choice.set_item_metadata(0,"")
	for edge:Dictionary in City.resolve(editor._doc.map_meta).roads.edges:
		if not Placement.supports_target(edge):continue
		road_choice.add_item("%s · %s · %s"%[str(edge.get("name",edge.id)),"弯路" if edge.has("controls") else "直路",str(edge.id)]); road_choice.set_item_metadata(road_choice.item_count-1,str(edge.id))
		if str(edge.id)==road_id: road_choice.select(road_choice.item_count-1)
	if selected(asset_choice)!=asset_id or selected(road_choice)!=road_id: invalidate_preview("素材或道路列表已变化，请重新预览。")
	refresh_entrances()

func refresh_entrances()->void:
	if entrance_choice==null:return
	var previous:=selected(entrance_choice);entrance_choice.clear()
	entrance_choice.add_item("自动（仅限唯一入口）");entrance_choice.set_item_metadata(0,"")
	var key:="building_id" if relocation_enabled.button_pressed else "asset_id"
	var id:=selected(building_choice if relocation_enabled.button_pressed else asset_choice)
	if id.is_empty():entrance_feedback.text="请先选择住宅。";return
	var args:Dictionary={key:id}
	if selected(support_choice)!="auto":args.support_mode=selected(support_choice)
	var result:Dictionary=editor._residential.inspect_entrances(args)
	if not result.ok:entrance_feedback.text=result.get("error","入口读取失败");return
	for row:Dictionary in result.entrances:
		entrance_choice.add_item(("通廊 · " if row.kind=="passage" else "房门 · ")+row.id+("" if row.ok else " · 检查未通过"))
		entrance_choice.set_item_metadata(entrance_choice.item_count-1,row.id)
		if row.id==previous:entrance_choice.select(entrance_choice.item_count-1)
	select_entrance(previous)
	entrance_feedback.text="%d 个入口；%s。"%[result.entrances.size(),"多入口需明确选择" if result.requires_selection else "唯一入口可自动选择"]
	if result.support.ok:entrance_feedback.text+=" 已识别 %d 个真实支撑域。"%result.support.components.size()
	else:entrance_feedback.text+=" "+result.support.get("error","支撑结构尚不支持")

func select_entrance(id:String)->void:
	for i in entrance_choice.item_count:
		if entrance_choice.get_item_metadata(i)==id:entrance_choice.select(i);return
	# Preserve intent across source revisions/queue loading. Never silently
	# replace a vanished explicit entrance with a different automatic doorway.
	entrance_choice.add_item("入口已不可用 · "+id);entrance_choice.set_item_metadata(entrance_choice.item_count-1,id);entrance_choice.select(entrance_choice.item_count-1)

func house_request()->Dictionary:
	var result:Dictionary=form.values()
	result.asset_id=selected(asset_choice);result.road_edge_id=selected(road_choice)
	if not selected(entrance_choice).is_empty():result.entrance_id=selected(entrance_choice)
	if selected(support_choice)!="auto":result.support_mode=selected(support_choice)
	if relocation_enabled.button_pressed:
		result.erase("asset_id");result.building_id=selected(building_choice);result.old_access=selected(old_access_choice)
	return result

func request() -> Dictionary:
	if block_enabled.button_pressed:
		var block:Dictionary={"homes":block_draft.homes.duplicate(true)}
		if site_enabled.button_pressed:block.terrain=site_draft.request()
		return block
	var result:=house_request()
	if relocation_enabled.button_pressed:
		var migration:Dictionary={"residential":result}
		if site_enabled.button_pressed:migration.terrain=site_draft.request()
		return migration
	return {"residential":result,"terrain":site_draft.request()} if site_enabled.button_pressed else result

func service():
	if block_enabled.button_pressed:return editor._residential_block
	if relocation_enabled.button_pressed:return editor._residential_relocation
	return editor._residential_site if site_enabled.button_pressed else editor._residential

func use_selected_building()->void:
	refresh_catalogs()
	var ids:Array=[]
	for record:Dictionary in editor._selection_tools.records():
		var id:String=record.get("building",{}).get("id","")
		if not id.is_empty() and id not in ids:ids.append(id)
	if ids.size()!=1:report({"ok":false,"error":"请先选择一栋已有住宅。"});return
	for i in building_choice.item_count:
		if building_choice.get_item_metadata(i)==ids[0]:
			building_choice.select(i);relocation_enabled.button_pressed=true
			var values:Dictionary=form.values();values.position=editor._doc.map_meta.building_instances[ids[0]].position;values.yaw=0.;form.update_values(values)
			invalidate_preview("已读取建筑原点；请设置目标位置后预览。");return
	report({"ok":false,"error":"所选建筑不在本轮可靠迁移支持范围内。"})

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
	var result:Dictionary=service().preview(args)
	if result.ok:
		plan_token=str(result.plan_token)
		show_visual(service().preview_visual(plan_token))
		preview_doc_id=editor._doc.get_instance_id();preview_revision=editor._doc.authoring_revision
		apply_button.disabled=false; discard_button.disabled=false
	report(result)

func show_visual(records: Array) -> void:
	if records.is_empty(): return
	ghost=Node3D.new(); ghost.name="ResidentialPlacementPreview"; editor.add_child(ghost)
	for record:Dictionary in records:
		var visual:Node3D=editor._doc._asset(record) if record.get("kind")=="asset" else editor._doc._mesh(record)
		for mesh:MeshInstance3D in editor._doc.SurfaceMaterials.meshes(visual):
			mesh.transparency=.4;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(visual)
	# Preview meshes have no physics bodies and are outside the selectable view.

func apply_candidate() -> void:
	# Applying a pending SpinBox edit triggers invalidation before this guard.
	form.values()
	if plan_token.is_empty(): report({"ok":false,"error":"请先预览当前参数。"}); return
	if site_enabled.button_pressed:site_draft.request()
	if plan_token.is_empty():report({"ok":false,"error":"参数已变化，请重新预览。"});return
	var result:Dictionary=service().apply({"plan_token":plan_token})
	invalidate_preview("")
	report(result,true)

func invalidate_preview(message: String="参数已变化，请重新预览。") -> void:
	var had_preview:=not plan_token.is_empty()
	if had_preview and is_instance_valid(editor):
		editor._residential.discard(plan_token);editor._residential_site.discard(plan_token)
		editor._residential_relocation.discard(plan_token);editor._residential_block.discard(plan_token)
	plan_token=""
	if is_instance_valid(ghost): ghost.free()
	ghost=null
	if apply_button!=null: apply_button.disabled=true
	if discard_button!=null: discard_button.disabled=true
	last_result={}
	if diagnostics!=null:diagnostics.display({})
	if changes_view!=null:changes_view.hide();changes_view.text=""
	if focus_button!=null: focus_button.disabled=true
	if not message.is_empty() and feedback!=null: feedback.text=message; editor._status.text=message

func discard_preview() -> void:
	invalidate_preview("已放弃候选；地图未修改。")

func report(result: Dictionary, applied: bool=false) -> void:
	result=editor._diagnostics.explain(result,("apply_" if applied else "preview_")+("residential_block" if block_enabled.button_pressed else ("residential_relocation" if relocation_enabled.button_pressed else ("residential_site" if site_enabled.button_pressed else "residential_placement"))))
	diagnostics.display(result)
	last_result=result.duplicate(true)
	var text_:String
	if result.ok:
		if applied: text_="住宅与入户路已一起应用，可一次撤销。请按原生流程保存地图。"
		else:
			var p:Array=result.get("position",[]); var delta:Array=result.get("adjustment",[])
			text_="候选已通过共享校验，尚未写入地图。"
			if p.size()==3: text_+="\n最终位置：%.3f, %.3f, %.3f 米"%[p[0],p[1],p[2]]
			if delta.size()==3: text_+=" · 标高调整 %+.3f 米"%float(delta[1])
			if not result.has("homes"):text_+="\n门前退距 %.2f 米 · 路宽 %.2f 米"%[float(result.get("setback",0)),float(result.get("width",0))]
		if result.has("homes"):
			text_+="\n街区共 %d 栋，最终逐户入口与路缘检查通过。"%result.homes.size()
			for home:Dictionary in result.homes:
				text_+="\n%s · %s · 原点 (%.3f, %.3f, %.3f) · 退距 %.2f 米"%[home.id,"迁移保留身份" if home.operation=="relocate" else "新增",home.building_position[0],home.building_position[1],home.building_position[2],home.setback]
				if home.has("relocation"):text_+=" · 旧路"+("移除归属支路" if home.relocation.old_access.policy=="remove_owned" else "保留")
		if result.has("road_connection"):
			text_+="\n入口："+str(result.get("access",{}).get("entrance_id",""))
			if result.get("support",{}).get("support_mode")=="piers":text_+=" · 已验证真实柱墩与楼下 1.8 米净空。"
			var connection:Dictionary=result.road_connection
			text_+="\n接入%s · 接点 %.3f, %.3f, %.3f 米"%["弯路" if connection.kind=="cubic" else "直路",connection.position[0],connection.position[1],connection.position[2]]
			if connection.kind=="cubic" and connection.split:text_+="\n保留原曲线形状和宽度变化，接点拆分为两个可编辑路段。"
		if result.has("relocation"):
			var migration:Dictionary=result.relocation
			text_+="\n迁移原建筑 %s：保留构件、楼层和活动件身份。"%migration.building_id
			text_+="\n旧路："+("仅移除归属支路，保留公共接点。" if migration.old_access.policy=="remove_owned" else "全部保留，原路解除住宅归属。")
			text_+="\n旧地块：仅改变显式整地范围。"
		if result.has("changes"):
			var work:Dictionary=result.earthwork;var changes:Dictionary=result.changes
			text_+=("\n整地、住宅与接路已一起应用。" if applied else "\n最终整地与住宅接路联合检查通过。")
			text_+="\n挖方 %.2f m³ / 填方 %.2f m³ · 整地 %d 项\n新增 %d / 修改 %d / 删除 %d 个对象"%[work.cut_m3,work.fill_m3,result.terrain_operation_count,changes.added.size(),changes.updated.size(),changes.removed.size()]
			changes_view.text="新增：\n"+"\n".join(changes.added)+"\n修改：\n"+"\n".join(changes.updated)+"\n删除：\n"+"\n".join(changes.removed)+"\n道路影响：\n"+"\n".join(changes.road_ids)+"\n跟随构件：\n"+"\n".join(changes.follower_ids);changes_view.show()
		var bridge_count:int=result.get("bridges",{}).get("binding_count",0)
		if bridge_count>0:text_+="\n已校验并保留 %d 处桥梁绑定及关联河道。"%bridge_count
	else:
		text_=str(result.get("error","方案未通过"))
		if result.has("home_id"):text_="第 %d 户 %s："%[int(result.home_index)+1,result.home_id]+text_
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

func _process(_delta:float)->void:
	if not plan_token.is_empty() and (preview_doc_id!=editor._doc.get_instance_id() or preview_revision!=editor._doc.authoring_revision):invalidate_preview("地图已变化，请重新预览。")

func _exit_tree() -> void:
	invalidate_preview("")
