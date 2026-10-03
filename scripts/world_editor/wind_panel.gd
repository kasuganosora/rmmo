extends VBoxContainer
const Response = preload("res://scripts/world3d/wind_response.gd")
var editor: Node3D
var form: VBoxContainer
var ids: Array = []
var key := ""
var details: VBoxContainer
var toggle: Button
var enabled := false

func setup(host: Node3D) -> void:
	editor = host
	toggle = Button.new(); toggle.name = "ToggleWindSettings"; toggle.toggle_mode = true; toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT; add_child(toggle)
	details = VBoxContainer.new(); details.visible = false; add_child(details)
	toggle.toggled.connect(func(open): details.visible = open; _update_heading())
	_update_heading()
	var note := Label.new(); note.text = "选植被或布料，再设置固定边。网格需要足够细分；风速/风向在环境页调整。碰撞保持原形。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x = 260; details.add_child(note)
	form = preload("res://scripts/world_editor/settings_form.gd").new(); details.add_child(form)
	var button := Button.new(); button.text = "应用受风设置"; button.pressed.connect(apply); details.add_child(button)

func refresh() -> void:
	ids = editor._selection_tools.ids.duplicate()
	visible = not ids.is_empty() and not editor._selection_tools.whole
	if not visible: key = ""; return
	var record: Dictionary = editor._doc._find(str(ids[0]))
	var values := Response.resolve(record)
	enabled = values.get("profile", "off") != "off"
	_update_heading()
	var next_key := JSON.stringify([ids,values])
	if key == next_key: return
	key = next_key
	var meshes: Array = [{"id":"*","name":"所有网格（逐网格固定边）"}]
	if ids.size() == 1:
		for row in editor._wind_tools.catalog(str(ids[0])): meshes.append({"id":row.mesh,"name":row.mesh+("" if row.supported else "（暂不支持）")})
	form.build(Response.schema(),values,{"profile":"受风类型","mesh":"作用网格","amplitude":"摆幅基准（米）","stiffness":"刚度（0 软～1 硬）","anchor":"固定边（模型局部坐标）","shelter":"检测上方遮挡，室内停风"},
		{"mesh":meshes,"profile":[{"id":"off","name":"不受风"},{"id":"foliage","name":"植被：根部固定、枝叶摆动"},{"id":"cloth","name":"布料：固定边、波浪飘动"}],"anchor":[{"id":"bottom","name":"底部 -Y"},{"id":"top","name":"顶部 +Y"},{"id":"left","name":"左边 -X"},{"id":"right","name":"右边 +X"}]})

func apply() -> void:
	var result: Dictionary = editor._wind_tools.set_settings(ids,form.values())
	editor._status.text = "受风设置已应用，可撤销" if result.ok else str(result.error)

func _update_heading() -> void:
	toggle.text = ("▾ " if toggle.button_pressed else "▸ ") + "柔性物件受风" + (" · 已启用" if enabled else "")
