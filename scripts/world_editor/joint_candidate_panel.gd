extends VBoxContainer
## Queue snapshots of the existing UI forms; editing those forms never applies
## a step. Only the shared candidate service can publish the complete queue.
const Tools=preload("res://scripts/world_editor/joint_candidate_tools.gd")
const Data=preload("res://scripts/world3d/city_layout.gd")
var host:VBoxContainer
var editor:Node3D
var steps:Array=[]
var sources:OptionButton
var queue:ItemList
var feedback:Label
var details:Label
var diagnostics:VBoxContainer
var apply_button:Button
var token:=""
var revision:=-1
var document_id:=0
var serial:=0
var ghost:Node3D
var last_result:Dictionary={}
var path_form:VBoxContainer
const PARAM_LABELS={"id":"对象或区域","material_id":"路面材质","kerb_material_id":"路缘材质","kerb_enabled":"自动路缘","kerb_width":"路缘宽度","kerb_height":"路缘高度","offset":"离地偏移","thickness":"厚度","height":"高度","position":"位置","yaw":"朝向","width":"宽度","points":"路径点","nodes":"节点","edges":"线段","strokes":"整地区域","homes":"住宅","terrain":"联合整地","residential":"住宅接路","asset_id":"住宅资源","asset_ids":"植被资源","building_id":"已有建筑","road_edge_id":"接入道路","block_ids":"街区","max_buildings":"住宅上限","zones":"保留区","start":"起点","end":"终点","blend_margin":"柔边宽度","seed":"随机种子","count":"数量","spacing":"间距","polygon":"区域边界","ground_ids":"地面","bridges":"河道桥梁","prefab_id":"桥型","setback":"退让","lot_width":"地块宽度","lot_depth":"地块深度"}

func setup(value:VBoxContainer)->void:
	host=value;editor=host.editor
	var body:VBoxContainer=host.section("跨工具联合候选")
	host.note(body,"先在各工具面板填写参数，再加入此队列。可排序、替换或移除，整组通过后一次应用；地图或资源变化须重新预览。互相依赖的整地与住宅请用住宅联合面板作为一个步骤。")
	sources=OptionButton.new();body.add_child(sources)
	for pair:Array in [["terrain","联合整坡面板"],["ramp","两端坡道面板"],["node","当前道路节点"],["edge","当前道路线段"],["path","新道路起终点"],["surface","道路铺面面板"],["zone","当前保留区"],["residential","住宅联合面板"],["block","沿街住宅面板"],["reflow","已有街区更新"],["water","河道面板"],["bridge","桥梁面板"],["connect","所选河道桥梁接路"],["fort","城防面板"],["scatter","植被散布面板"]]:
		sources.add_item(pair[1]);sources.set_item_metadata(sources.item_count-1,pair[0])
	path_form=preload("res://scripts/world_editor/settings_form.gd").new();body.add_child(path_form)
	path_form.build(Data.object({"start":Data.S.vector(-100000,100000),"end":Data.S.vector(-100000,100000),"width":Data.S.number(1,60)}),{"start":[0,0,0],"end":[0,0,20],"width":4.},{"start":"道路起点（世界米）","end":"道路终点（世界米）","width":"道路宽度（米）"})
	path_form.hide();sources.item_selected.connect(func(_i):path_form.visible=sources.get_item_metadata(sources.selected)=="path")
	host.button(body,"将当前面板参数加入队列",func():capture(false))
	host.button(body,"用当前面板参数替换选中步骤",func():capture(true))
	queue=ItemList.new();queue.custom_minimum_size.y=170;body.add_child(queue);queue.item_selected.connect(func(_i):show_details())
	var row:=HFlowContainer.new();body.add_child(row)
	host.button(row,"上移",func():move_step(-1));host.button(row,"下移",func():move_step(1));host.button(row,"移除",remove_step)
	var detail_toggle:=CheckButton.new();detail_toggle.text="查看所选步骤参数与影响";body.add_child(detail_toggle)
	details=host.note(body,"");details.hide();detail_toggle.toggled.connect(func(on):details.visible=on)
	feedback=host.note(body,"队列为空。")
	host.button(body,"预览整组",preview)
	apply_button=host.button(body,"一次应用整组",apply_candidate);apply_button.disabled=true
	host.button(body,"放弃预览",func():invalidate("已放弃预览，队列保留。"))
	host.button(body,"清空队列",func():steps.clear();invalidate();refresh_queue())
	diagnostics=preload("res://scripts/world_editor/diagnostic_panel.gd").new();body.add_child(diagnostics);diagnostics.setup(editor)

func selected()->int:
	return queue.get_selected_items()[0] if not queue.get_selected_items().is_empty() else -1

func current()->Dictionary:
	var name:String=sources.get_item_metadata(sources.selected)
	match name:
		"terrain":return {"apply_terrain_layout":editor._terrain_panel.terrain_layout.request()}
		"ramp":return {"apply_terrain_ramp":editor._terrain_panel.ramp.request()}
		"surface":return {"generate_road_surface":host.road_surface_panel.args()}
		"path":
			var p:Dictionary=path_form.values();return {"create_road_path":{"points":[p.start,p.end],"width":p.width}}
		"node","edge":
			var item:Dictionary=host.selected(host.city.data.roads.nodes if name=="node" else host.city.data.roads.edges,host.nodes if name=="node" else host.edges)
			if item.is_empty():return {}
			item.merge(host.node_form.values() if name=="node" else host.edge_form.values(),true)
			if name=="edge":
				if host.curve.button_pressed:
					var handles:Dictionary=host.controls.values();item.controls=[handles.handle_a,handles.handle_b]
				else:item.erase("controls")
			return {"update_road_graph":host.request().merged({"nodes" if name=="node" else "edges":[item]})}
		"zone":
			var z:Dictionary=host.road_surface_panel.selected()
			if z.is_empty():return {}
			z.merge(host.road_surface_panel.fields.values(),true)
			return {"update_planning_zones":{"expected_token":host.road_surface_panel.zone_token(),"zones":[z]}}
		"residential":
			var panel=editor._building_panel.residential
			var op:String="preview_residential_block" if panel.block_enabled.button_pressed else ("preview_residential_relocation" if panel.relocation_enabled.button_pressed else ("preview_residential_site" if panel.site_enabled.button_pressed else "preview_residential_placement"))
			return {op:panel.request()}
		"block":return {"generate_block_buildings":host.block_panel.request()}
		"reflow":return {"preview_block_update":host.block_panel.request()}
		"water":return {"generate_waterway":host.waterway_panel.request()}
		"bridge":return {"generate_bridge":host.bridge_panel.request()}
		"fort":return {"generate_fortification":host.fortification_panel.request()}
		"scatter":return {"generate_vegetation_scatter":host.scatter_panel.request()}
		"connect":
			var menu:OptionButton=host.road_surface_panel.bridges
			if menu.selected>=0:return {"connect_waterway_bridge":menu.get_item_metadata(menu.selected).duplicate(true)}
	return {}

func capture(replace:bool)->void:
	var row:=current();var index:=selected()
	if row.is_empty():feedback.text="请先在对应工具面板选择对象并填写参数。";return
	if replace and index<0:feedback.text="请先选择要替换的步骤。";return
	if not replace and steps.size()>=64:feedback.text="整组最多 64 步。";return
	serial+=1;row.id=steps[index].id if replace else "step_%d"%serial
	if replace:steps[index]=row.duplicate(true)
	else:steps.append(row.duplicate(true));index=steps.size()-1
	invalidate();refresh_queue(index)

func move_step(direction:int)->void:
	var index:=selected();var next:=index+direction
	if index<0 or next<0 or next>=steps.size():return
	var row:Dictionary=steps[index];steps.remove_at(index);steps.insert(next,row)
	invalidate();refresh_queue(next)

func remove_step()->void:
	var index:=selected()
	if index<0:return
	steps.remove_at(index);invalidate();refresh_queue(mini(index,steps.size()-1))

func refresh_queue(index:int=-1)->void:
	queue.clear()
	for row:Dictionary in steps:queue.add_item("%d. %s · %s"%[queue.item_count+1,Tools.OPERATIONS.get(Tools.operation(row),"无效步骤"),row.id])
	if index>=0:queue.select(index)
	show_details()

func show_details()->void:
	var index:=selected()
	if index<0:details.text="";return
	var row:Dictionary=steps[index];var op:=Tools.operation(row)
	if op.is_empty():details.text="步骤无效，请替换或移除。";return
	var args:Dictionary=row[op]
	var lines:Array[String]=[]
	if last_result.get("ok",false) and index<last_result.get("steps",[]).size():
		var delta:Dictionary=last_result.steps[index].changes
		lines.append("此步预览：新增 %d / 更新 %d / 移除 %d"%[delta.added.size(),delta.updated.size(),delta.removed.size()])
	for key:String in args:
		if key in ["expected_token","expected_road_token","plan_token"]:continue
		var value:Variant=args[key]
		if not PARAM_LABELS.has(key):continue
		var display:=str(value)
		if value is Dictionary:display="%d 项参数"%value.size()
		elif value is Array and (value.size()>3 or value.any(func(v):return v is Dictionary or v is Array)):display="%d 项"%value.size()
		elif value is bool:display="开启" if value else "关闭"
		lines.append(PARAM_LABELS[key]+"："+display)
	details.text="已收集参数（修改原面板后可替换此步骤）：\n"+"\n".join(lines)

func invalidate(message:String="队列已变化，请重新预览整组。") -> void:
	if not token.is_empty():editor._joint_candidate.discard(token)
	token="";last_result={};apply_button.disabled=true
	if is_instance_valid(ghost):ghost.free()
	ghost=null;feedback.text=message
	if diagnostics!=null:diagnostics.display({})

func preview()->void:
	invalidate("")
	var result:Dictionary=editor._joint_candidate.preview({"steps":steps.duplicate(true)})
	last_result=editor._diagnostics.explain(result,"preview_joint_candidate");diagnostics.display(last_result)
	if not result.ok:
		feedback.text=("第 %d 步 %s："%[int(result.step_index)+1,result.step_id] if result.has("step_id") else "最终联合检查：")+str(result.error)
		if result.has("step_index"):queue.select(int(result.step_index))
		return
	token=result.plan_token;revision=editor._doc.authoring_revision;document_id=editor._doc.get_instance_id();apply_button.disabled=false
	feedback.text="%d 步通过 · 新增 %d / 更新 %d / 移除 %d\n道路、建筑、入口和保留区已完成最终检查。"%[result.step_count,result.changes.added.size(),result.changes.updated.size(),result.changes.removed.size()]
	show_details()
	ghost=Node3D.new();ghost.name="JointCandidatePreview";editor.add_child(ghost)
	for record:Dictionary in editor._joint_candidate.preview_visual(token):
		var visual:Node3D=editor._doc._asset(record) if record.get("kind")=="asset" else editor._doc._mesh(record)
		for mesh:MeshInstance3D in editor._doc.SurfaceMaterials.meshes(visual):mesh.transparency=.4;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(visual)

func apply_candidate()->void:
	if token.is_empty():feedback.text="请先预览整组。";return
	var result:Dictionary=editor._joint_candidate.apply({"plan_token":token})
	invalidate("整组已应用，可一次撤销；请保存地图。" if result.ok else str(result.error))
	host.report(result)
	if result.ok:steps.clear();refresh_queue()

func _process(_delta:float)->void:
	if not token.is_empty() and (editor._doc.get_instance_id()!=document_id or editor._doc.authoring_revision!=revision):invalidate("地图已变化，请重新预览整组。")

func _exit_tree()->void:
	if is_instance_valid(ghost):ghost.queue_free()
