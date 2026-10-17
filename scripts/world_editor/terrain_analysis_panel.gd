extends VBoxContainer
const Analysis=preload("res://scripts/world_editor/terrain_analysis.gd")
var target:OptionButton
var catalog_token:=""
var error_text:=""
var editor:Node3D
var terrain_panel:VBoxContainer
var fields:VBoxContainer
var info:Label
var show_button:Button
var hide_button:Button
func setup(value:Node3D,owner_panel:VBoxContainer)->void:
	editor=value;terrain_panel=owner_panel
	var note:=Label.new();note.text="查看所选地形的原生三角面。白线为等高线；红色为超过阈值的坡面，绿色为其余坡面；紫色标记相邻边界高差。洞格留空。体积地形须选择标高范围和朝上／朝下／壁面，洞顶与壁面标红。此视图不改变地图，也不替代通行检查。";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
	target=OptionButton.new();add_child(target);refresh_targets()
	fields=preload("res://scripts/world_editor/settings_form.gd").new();add_child(fields)
	fields.build(Analysis.schema(),{"interval":1.,"slope_threshold":.15,"contours":true,"slopes":true,"seams":true,"surface":"all","height_min":-1000.,"height_max":2000.},{"interval":"等高距（米）","slope_threshold":"陡坡阈值（0.15 = 15%）","contours":"等高线","slopes":"坡度色层","seams":"邻块边界高差（仅高度场）","surface":"体积表面方向","height_min":"体积标高下限（世界米）","height_max":"体积标高上限（世界米）"},{"surface":[{"id":"all","name":"全部表面"},{"id":"upward","name":"朝上表面（含洞内地面）"},{"id":"downward","name":"朝下表面（含洞顶）"},{"id":"walls","name":"近垂直壁面"}]})
	show_button=Button.new();show_button.text="显示／更新地形分析";add_child(show_button);show_button.pressed.connect(show_analysis)
	hide_button=Button.new();hide_button.text="关闭地形分析";add_child(hide_button);hide_button.pressed.connect(func():editor._terrain_analysis.configure({"enabled":false}))
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(info)
func show_analysis()->Dictionary:
	var args:Dictionary=fields.values();args.id=selected_target();args.enabled=true
	if editor._doc._find(args.id).has("terrain_volume"):args.seams=false
	else:
		for key in ["surface","height_min","height_max"]:args.erase(key)
	var result:Dictionary=editor._terrain_analysis.configure(args)
	error_text="" if result.ok else str(result.error)
	if not error_text.is_empty():info.text=error_text
	return result
func selected_target()->String:
	return terrain_panel.selected() if target.selected<1 else str(target.get_item_metadata(target.selected))
func refresh_targets()->void:
	var previous:Variant=target.get_item_metadata(target.selected) if target.item_count>0 else ""
	target.clear();target.add_item("当前雕刻地块");target.set_item_metadata(0,"")
	for r:Dictionary in editor._doc.records:
		if not r.has("terrain_volume") or r.get("editor_hidden",false) or not editor._authoring.Settings.contains(r,editor._authoring.settings):continue
		target.add_item("体积 · "+str(r.get("editor_name",r.uuid)));target.set_item_metadata(target.item_count-1,r.uuid)
		if r.uuid==previous:target.select(target.item_count-1)
func _process(_delta:float)->void:
	if editor==null:return
	var token:String=editor._terrain_analysis.version()
	if token!=catalog_token:catalog_token=token;refresh_targets()
	var volume:bool=editor._doc._find(selected_target()).has("terrain_volume")
	for key in ["surface","height_min","height_max"]:fields.fields[key].visible=volume;fields._labels[key].visible=volume
	fields.fields.seams.visible=not volume;fields._labels.seams.visible=not volume
	if not error_text.is_empty():info.text=error_text;return
	var state:Dictionary=editor._terrain_analysis.state()
	if not state.enabled:return
	var result:Dictionary=state.result
	if result.get("source")=="native_volume_triangles" and result.get("ok",false):
		info.text="体积表面 · 标高 %.2f–%.2f 米\n朝上 %d / 朝下 %d / 壁面 %d\n最大倾角 %.2f° · 垂直面 %d\n%d 条等高线段 · %d 个三角面\n洞顶与壁面标红，不代表可通行。"%[result.height_range[0],result.height_range[1],result.surface_counts.upward,result.surface_counts.downward,result.surface_counts.walls,result.max_angle_degrees,result.vertical_triangles,state.line_count,result.selected_triangles]
		return
	info.text="地形已变化，覆盖层不可用："+str(result.get("error","")) if not result.get("ok",false) else "最大坡度 %.2f%%\n邻块边界最大高差 %.4f 米\n%d 条等高线段 · %d 个三角面\n随修改、撤销和重开自动刷新。"%[result.max_grade*100,result.max_boundary_step,state.line_count,state.triangle_count]
