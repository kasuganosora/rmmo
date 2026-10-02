extends VBoxContainer
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
const Form=preload("res://scripts/world_editor/settings_form.gd")
var editor: Node3D
var choice: OptionButton
var create_fields: VBoxContainer
var brush_fields: VBoxContainer
var materials: OptionButton
var info: Label
func note(text: String) -> Label:
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(label); return label
func button(text: String, callback: Callable) -> void:
	var value:=Button.new(); value.text=text; value.pressed.connect(callback); add_child(value)
func report(result: Dictionary) -> void:
	editor._status.text="地形操作完成" if result.ok else str(result.error)
	if result.ok: refresh(str(result.get("id",selected())))
func selected() -> String:
	return str(choice.get_item_metadata(choice.selected)) if choice.selected>=0 else ""
func setup(value: Node3D) -> void:
	editor=value; add_theme_constant_override("separation",8)
	note("地形雕刻").add_theme_font_size_override("font_size",18)
	note("选择现有普通地面并转换，或在空白区域新建。每块最多 64 × 64 格；整块是一个物件。挖洞会移除地面与碰撞，补洞保留原高度。")
	choice=OptionButton.new(); choice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(choice); choice.item_selected.connect(func(_i):editor._terrain_brush.cancel(); refresh(selected()))
	button("使用当前选中的地形",func():
		var selected_records: Array=editor._selection_tools.records()
		if selected_records.size()!=1 or not selected_records[0].has("terrain_mesh"): report(Terrain.fail("请只选择一块可雕刻地形"))
		else: refresh(selected_records[0].uuid))
	create_fields=Form.new(); add_child(create_fields)
	create_fields.build(Terrain.create_schema(),{"name":"可雕刻地形","center":[0,0,0],"width":32.0,"depth":32.0,"cell_size":1.0,"bedrock_depth":16.0},{"name":"名称","center":"新建中心 / 地表标高（米）","width":"宽度 X（米）","depth":"长度 Z（米）","cell_size":"目标格距（米）","bedrock_depth":"底床深度（米）"})
	materials=OptionButton.new(); materials.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(materials); materials.add_item("地形原色"); materials.set_item_metadata(0,"")
	for entry in editor._material_tool.library.entries(): materials.add_item(str(entry.material.name)); materials.set_item_metadata(materials.item_count-1,entry.material_id)
	button("将选中地面转换为可雕刻地形",func():
		editor._terrain_brush.cancel()
		var selection: Array=editor._selection_tools.records()
		if selection.size()!=1: report(Terrain.fail("请只选择一个普通地面方块")); return
		var args: Dictionary=create_fields.values(); args.source_id=selection[0].uuid
		for key in ["center","width","depth"]: args.erase(key)
		args.material_id=materials.get_item_metadata(materials.selected); report(editor._terrain.create(args)))
	button("在空白区域新建地形",func():editor._terrain_brush.cancel(); report(editor._terrain.create(create_fields.values().merged({"material_id":materials.get_item_metadata(materials.selected)}))))
	button("应用所选整体材质",func():editor._terrain_brush.cancel(); report(editor._terrain.set_material(selected(),str(materials.get_item_metadata(materials.selected)))))
	note("笔刷 · 左键拖动 / 松开提交 · Esc 取消这一笔\n整平高度使用世界坐标；强度是每次采样的米数，平滑时 0～1 为混合比例。挖洞按格子中心命中，格距决定洞口精度。")
	brush_fields=Form.new(); add_child(brush_fields)
	brush_fields.build(Terrain.stroke_schema(),{"mode":"raise","radius":3.0,"strength":.5,"hardness":.25,"target_height":0.0},{"mode":"工具","radius":"半径（米）","strength":"强度","hardness":"硬度（0 软边 / 1 硬边）","target_height":"整平目标标高（米）"},{"mode":[{"id":"raise","name":"隆起"},{"id":"lower","name":"下沉 / 挖坑"},{"id":"flatten","name":"整平"},{"id":"smooth","name":"平滑"},{"id":"hole","name":"挖穿洞口"},{"id":"fill","name":"补洞"}]})
	for control in brush_fields.fields.values():
		if control is SpinBox: control.value_changed.connect(func(_v):editor._terrain_brush.cancel())
		elif control is OptionButton: control.item_selected.connect(func(_i):editor._terrain_brush.cancel())
	button("启用当前地形笔刷",func():
		report(editor._terrain_brush.begin(selected(),brush_fields.values()))
		if editor._terrain_brush.active: editor._status.text="在画布中拖动地形笔刷；Esc 取消这一笔并退出")
	button("结束笔刷",func():editor._terrain_brush.cancel())
	info=note(""); refresh()
func refresh(preferred: String="") -> void:
	if choice==null: return
	var id:=preferred if not preferred.is_empty() else selected(); choice.clear()
	for row in editor._terrain.catalog().terrains:
		choice.add_item("%s · %d×%d · %d 洞格"%[row.name,row.columns,row.rows,row.holes]); choice.set_item_metadata(choice.item_count-1,row.id)
		if row.id==id: choice.select(choice.item_count-1)
	if info!=null: info.text="选定地形后启用笔刷。锁定、隐藏或隔层地形不可修改；笔刷侵入物件或挖掉其承托时整笔取消。底床不是洞穴系统。"
