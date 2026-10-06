extends VBoxContainer
const Tools=preload("res://scripts/world_editor/tree_tools.gd")
var editor:Node3D
var form:VBoxContainer
var ids:Array=[]
var key=""
func setup(host:Node3D)->void:
	editor=host
	var title=Label.new();title.text="参数化松树";add_child(title)
	var note=Label.new();note.text="以已验收树形为基础调整枝簇。应用后同步更新近、中、远景，可撤销。密度增加也会增加面数。";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=260;add_child(note)
	form=preload("res://scripts/world_editor/settings_form.gd").new();add_child(form)
	var button=Button.new();button.name="ApplyTreeSettings";button.text="应用树形参数";add_child(button);button.pressed.connect(apply)
func refresh()->void:
	ids=editor._selection_tools.ids.duplicate();visible=not ids.is_empty() and not editor._selection_tools.whole
	if not visible:key="";return
	var state:=Tools.describe(editor,str(ids[0]));visible=state.supported
	if not visible:key="";return
	var next_key=JSON.stringify([ids,state.settings])
	if key==next_key:return
	key=next_key
	form.build(Tools.TreeModel.schema(),state.settings,{"height":"树高（米，模型局部）","crown_scale":"冠幅倍率","trunk_scale":"树干粗细倍率","bare_trunk":"裸干长度（米，枝冠起点）","lean":"顶部倾斜（米，局部 X）","density":"枝簇密度（1 为验收版）","seed":"枝簇随机种子（0 为原排列）"})
func apply()->void:
	var result:=Tools.apply(editor,ids,form.values())
	editor._status.text="树形已更新，三级 LOD 同步，可撤销" if result.ok else str(result.error)
