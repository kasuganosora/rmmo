extends VBoxContainer
## Shared diagnostic list for residential, terrain ramp and joint layout UI.
var editor:Node3D
var choices:OptionButton
var details:Label
var locate:Button
var token:=""
var info:Dictionary={}
const LABELS={"conflict":"几何冲突","unsupported":"暂不支持","search_exhausted":"范围内未找到候选","stale":"检查已过期","invalid_request":"参数无效","constraint":"约束未通过"}

func setup(owner_editor:Node3D)->void:
	editor=owner_editor
	choices=OptionButton.new();choices.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;add_child(choices);choices.item_selected.connect(func(_i):show_item())
	details=Label.new();details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(details)
	locate=Button.new();locate.text="定位并高亮此问题";add_child(locate);locate.pressed.connect(focus)
	var clear_button:=Button.new();clear_button.text="清除问题高亮";add_child(clear_button);clear_button.pressed.connect(func():editor._diagnostics.clear())
	hide()

func display(result:Dictionary)->void:
	info=result.get("diagnostic",{});token=result.get("diagnostic_token","");visible=not info.is_empty()
	choices.clear()
	if info.is_empty():return
	for item:Dictionary in info.items:choices.add_item(str(choices.item_count+1)+" · "+(item.message if not item.message.is_empty() else item.source))
	show_item()

func show_item()->void:
	if choices.selected<0:return
	var item:Dictionary=info.items[choices.selected]
	details.text=LABELS.get(info.category,info.category)+" · "+info.code+"\n"+item.message
	if not item.object_ids.is_empty():details.text+="\n对象："+", ".join(item.object_ids)
	if item.has("position"):details.text+="\n见证 XYZ："+str(item.position)
	for key:String in item.values:details.text+="\n"+key+"："+str(item.values[key])
	locate.disabled=not item.locatable
	if locate.disabled:details.text+="\n此项未提供可定位几何；可查看下一条具体见证。"

func focus()->void:
	var result:Dictionary=editor._diagnostics.focus({"diagnostic_token":token,"index":choices.selected})
	if not result.ok:details.text=str(result.error);locate.disabled=true
