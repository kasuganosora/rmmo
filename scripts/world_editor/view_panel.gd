extends VBoxContainer
const Settings = preload("res://scripts/world3d/editor_view_settings.gd")
var editor: Node3D
var floor_form: VBoxContainer
var spawn_form: VBoxContainer
func button(label_: String, callback: Callable) -> void:
	var item := Button.new(); item.text = label_; item.pressed.connect(callback); add_child(item)
func setup(host: Node3D) -> void:
	editor = host; add_theme_constant_override("separation",8)
	var hint := Label.new(); hint.text = "按物件所在高度隔离楼层。其他楼层不能选择；运行时仍显示整张地图。"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(hint)
	floor_form = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(floor_form)
	button("应用楼层范围",func(): report(editor._authoring.set_settings(floor_form.values())))
	var row := HBoxContainer.new(); add_child(row)
	for direction in [-1,1]:
		var move := Button.new(); move.text = "下一层" if direction == -1 else "上一层"; row.add_child(move)
		move.pressed.connect(func(): var s: Dictionary = editor._authoring.settings; report(editor._authoring.set_settings({"isolation":true,"base_height":s.base_height+direction*s.floor_height})))
	var title := Label.new(); title.text = "试玩出生点（脚点，米）"; add_child(title)
	spawn_form = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(spawn_form)
	button("应用出生点",func(): report(editor._authoring.set_settings(spawn_form.values())))
	button("点击地面选择出生点",editor._authoring.begin_pick)
	button("从此处开始临时试玩",editor._play)
	var note := Label.new(); note.text = "使用当前未保存内容的副本和独立游戏状态。退出试玩后回到原编辑状态，正式地图和角色进度不会被修改。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	refresh()
func refresh() -> void:
	if floor_form == null: return
	var s := Settings.resolve(editor._doc.map_meta)
	var floors := s.duplicate(true); floors.erase("spawn")
	floor_form.build(Settings.schema(),floors,{"isolation":"楼层隔离","base_height":"当前层起始高度","floor_height":"层高 / 范围高度","outside":"其他楼层显示"},{"outside":[{"id":"hide","name":"隐藏"},{"id":"dim","name":"淡化"}]})
	spawn_form.build(Settings.schema(),{"spawn":s.spawn},{"spawn":"XYZ"})
func report(result: Dictionary) -> void:
	editor._status.text = "楼层 / 出生点设置已应用，可撤销" if result.ok else str(result.error)
