extends VBoxContainer
const V=preload("res://scripts/world3d/terrain_volume.gd")
const Tools=preload("res://scripts/world_editor/terrain_volume_tools.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor:Node3D
var create_fields:VBoxContainer
var stroke_fields:VBoxContainer
var chosen:LineEdit
var result_label:Label
func setup(value:Node3D)->void:
	editor=value;name="洞穴 / 悬挑";add_theme_constant_override("separation",8)
	var help:=Label.new();help.text="体积地形保留洞顶，可挖横向隧道或堆出悬挑。尺寸是独立地块的编辑范围；分辨率越高细节越多。开挖路径使用世界坐标。";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(help)
	create_fields=Form.new();add_child(create_fields)
	create_fields.build(V.request_schema(),{"id":"volume_terrain","name":"洞穴地形","center":[0,4,0],"size":[16,8,16],"resolution":16,"seed":"box","material_id":""},{"id":"地块 ID","name":"名称","center":"中心（米）","size":"编辑范围 XYZ（米）","resolution":"每轴分辨率","seed":"初始形状","material_id":"地形材质 ID（留空原色）"},{"seed":[{"id":"box","name":"实心岩体"},{"id":"ellipsoid","name":"椭球山体"}]})
	add_button("新建体积地形",func():report(Tools.apply(editor,create_fields.values())))
	chosen=LineEdit.new();chosen.placeholder_text="目标体积地形 ID";add_child(chosen)
	add_button("使用选中的体积地形",func():
		var selected:Array=editor._selection_tools.records()
		if selected.size()==1 and selected[0].has("terrain_volume"):chosen.text=selected[0].uuid
		else:report({"ok":false,"error":"请只选择一块体积地形"}))
	stroke_fields=Form.new();add_child(stroke_fields)
	var schema:=V.stroke_schema();schema.properties.start=V.S.vector(-10000,10000);schema.properties.end=V.S.vector(-10000,10000)
	stroke_fields.build(schema,{"mode":"subtract","start":[-9,3,0],"end":[9,3,0],"radius":2.},{"mode":"笔画类型","start":"起点（世界 XYZ）","end":"终点（世界 XYZ）","radius":"半径（米）"},{"mode":[{"id":"subtract","name":"开挖隧道 / 洞穴"},{"id":"add","name":"堆积 / 悬挑"}]})
	add_button("校验并预览三角数",func():report(Tools.apply(editor,stroke(),true,true)))
	add_button("应用体积笔画",func():report(Tools.apply(editor,stroke(),true)))
	result_label=Label.new();result_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(result_label)
func stroke()->Dictionary:
	var args:Dictionary=stroke_fields.values();args.points=[args.start,args.end];args.erase("start");args.erase("end");args.id=chosen.text;return args
func add_button(label:String,callback:Callable)->void:
	var button:=Button.new();button.text=label;button.pressed.connect(callback);add_child(button)
func report(result:Dictionary)->void:
	result_label.text=("完成 · "+str(result.get("id",""))+" · "+str(result.get("triangles",""))) if result.ok else str(result.error)
	editor._status.text=result_label.text
	if result.ok:chosen.text=result.get("id",chosen.text)
