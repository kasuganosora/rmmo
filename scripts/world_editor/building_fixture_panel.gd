extends VBoxContainer
var host: VBoxContainer
var chooser: OptionButton
var amount: SpinBox
var rows: Array=[]
var window_picker:OptionButton
var style_picker:OptionButton
var window_rows:Array=[]
const Actions=preload("res://scripts/world_editor/building_fixture_tools.gd")

func setup(panel: VBoxContainer) -> void:
	host=panel
	var label:=Label.new(); label.text="门窗开合（0 关闭 / 100 全开）"; add_child(label)
	chooser=OptionButton.new(); chooser.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(chooser)
	chooser.item_selected.connect(func(i): amount.value=100*rows[i].open)
	amount=SpinBox.new(); amount.min_value=0; amount.max_value=100; amount.step=5; add_child(amount)
	var apply:=Button.new(); apply.text="应用门窗状态"; add_child(apply)
	apply.pressed.connect(func():
		if chooser.selected>=0: host.report(Actions.set_open(host.editor,host.selected_id(),rows[chooser.selected].id,amount.value/100))
	)
	var hint:=Label.new();hint.text="单个窗口：替换窗扇格栅，保留洞口与石框";add_child(hint)
	window_picker=OptionButton.new();window_picker.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;add_child(window_picker)
	style_picker=OptionButton.new();add_child(style_picker)
	for pair in [["casement","横格窗扇"],["cross_lattice","十字斜撑窗扇"],["diamond_lattice","菱格窗扇"]]:
		style_picker.add_item(pair[1]);style_picker.set_item_metadata(style_picker.item_count-1,pair[0])
	window_picker.item_selected.connect(func(i):show_window_style(i))
	var change:=Button.new();change.name="ReplaceWindowStyle";change.text="替换这一扇窗口";add_child(change)
	change.pressed.connect(func():
		if window_picker.selected<0:return
		host.report(preload("res://scripts/world_editor/building_window_tools.gd").replace(host.editor,host.selected_id(),window_rows[window_picker.selected].id,str(style_picker.get_item_metadata(style_picker.selected))))
		refresh(host.selected_id())
	)

func refresh(id: String) -> void:
	var previous: String=rows[chooser.selected].id if chooser.selected>=0 and chooser.selected<rows.size() else ""
	var previous_window:String=window_rows[window_picker.selected].id if window_picker.selected>=0 and window_picker.selected<window_rows.size() else ""
	chooser.clear(); rows=[]
	window_picker.clear();window_rows=[]
	if id.is_empty(): hide(); return
	var result:=Actions.list_components(host.editor,id)
	if result.ok: rows=result.components
	visible=not rows.is_empty()
	for row in rows:
		chooser.add_item("%s · %s"%[{"door":"门","window":"玻璃窗扇","shutter":"外窗板"}[row.kind],row.id])
		if row.id==previous: chooser.select(chooser.item_count-1)
	if chooser.selected>=0: amount.value=100*rows[chooser.selected].open
	var windows:=preload("res://scripts/world_editor/building_window_tools.gd").list_windows(host.editor,id)
	if windows.ok:window_rows=windows.windows
	for window in window_rows:
		window_picker.add_item("第%d层 · %s"%[int(window.floor)+1,window.id])
		if window.id==previous_window:window_picker.select(window_picker.item_count-1)
	show_window_style(window_picker.selected)

func show_window_style(index:int)->void:
	if index<0 or index>=window_rows.size():return
	for i in style_picker.item_count:
		if style_picker.get_item_metadata(i)==window_rows[index].style:style_picker.select(i);return
	style_picker.select(0)
