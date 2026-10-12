extends VBoxContainer
var editor:Node
func setup(owner:Node)->void:editor=owner
func refresh()->void:
	for child in get_children():remove_child(child);child.queue_free()
	visible=false
	if editor._selection_tools.ids.size()!=1:return
	var id:String=editor._selection_tools.ids[0]
	if editor._doc._find(id).get("kind")!="asset":return
	var found:Dictionary=preload("res://scripts/world_editor/model_component_tools.gd").list_components(editor,id)
	if not found.ok or found.components.is_empty():return
	visible=true
	var title:=Label.new();title.text="模型活动门 / 柜门";add_child(title)
	for row:Dictionary in found.components:
		var button:=Button.new();button.text=("关闭 · " if row.open>.5 else "打开 · ")+str(row.id).get_file()
		add_child(button)
		button.pressed.connect(func():
			var result:Dictionary=preload("res://scripts/world_editor/model_component_tools.gd").set_open(editor,id,row.id,0.0 if row.open>.5 else 1.0)
			editor._status.text="已调整柜门" if result.ok else result.error
			refresh()
		)
