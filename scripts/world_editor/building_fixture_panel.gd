extends VBoxContainer
var host: VBoxContainer
var chooser: OptionButton
var amount: SpinBox
var rows: Array=[]
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

func refresh(id: String) -> void:
	var previous: String=rows[chooser.selected].id if chooser.selected>=0 and chooser.selected<rows.size() else ""
	chooser.clear(); rows=[]
	if id.is_empty(): hide(); return
	var result:=Actions.list_components(host.editor,id)
	if result.ok: rows=result.components
	visible=not rows.is_empty()
	for row in rows:
		chooser.add_item("%s · %s"%[{"door":"门","window":"玻璃窗扇","shutter":"外窗板"}[row.kind],row.id])
		if row.id==previous: chooser.select(chooser.item_count-1)
	if chooser.selected>=0: amount.value=100*rows[chooser.selected].open
