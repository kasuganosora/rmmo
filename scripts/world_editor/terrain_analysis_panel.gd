extends VBoxContainer
const Analysis=preload("res://scripts/world_editor/terrain_analysis.gd")
var editor:Node3D
var terrain_panel:VBoxContainer
var fields:VBoxContainer
var info:Label
var show_button:Button
var hide_button:Button
func setup(value:Node3D,owner_panel:VBoxContainer)->void:
	editor=value;terrain_panel=owner_panel
	var note:=Label.new();note.text="查看所选地形的原生三角面。白线为等高线；红色为超过阈值的坡面，绿色为其余坡面；紫色标记相邻边界高差。洞格留空。此视图不改变地图，也不替代通行检查。";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
	fields=preload("res://scripts/world_editor/settings_form.gd").new();add_child(fields)
	fields.build(Analysis.schema(),{"interval":1.,"slope_threshold":.15,"contours":true,"slopes":true,"seams":true},{"interval":"等高距（米）","slope_threshold":"陡坡阈值（0.15 = 15%）","contours":"等高线","slopes":"坡度色层","seams":"邻块边界高差"})
	show_button=Button.new();show_button.text="显示／更新地形分析";add_child(show_button);show_button.pressed.connect(show_analysis)
	hide_button=Button.new();hide_button.text="关闭地形分析";add_child(hide_button);hide_button.pressed.connect(func():editor._terrain_analysis.configure({"enabled":false}))
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(info)
func show_analysis()->Dictionary:
	var args:Dictionary=fields.values();args.id=terrain_panel.selected();args.enabled=true
	var result:Dictionary=editor._terrain_analysis.configure(args)
	if not result.ok:info.text=str(result.error)
	return result
func _process(_delta:float)->void:
	if editor==null:return
	var state:Dictionary=editor._terrain_analysis.state()
	if not state.enabled:return
	var result:Dictionary=state.result
	info.text="地形已变化，覆盖层不可用："+str(result.get("error","")) if not result.get("ok",false) else "最大坡度 %.2f%%\n邻块边界最大高差 %.4f 米\n%d 条等高线段 · %d 个三角面\n随修改、撤销和重开自动刷新。"%[result.max_grade*100,result.max_boundary_step,state.line_count,state.triangle_count]
