extends VBoxContainer
const Settings = preload("res://scripts/world3d/environment_settings.gd")
var editor: Node3D
var form: VBoxContainer
var _key := ""
const LABELS = {"preset": "时段（day 白天 / sunset 黄昏 / night 夜晚）", "sun_rotation": "主光方向（度）", "sun_color": "主光颜色", "sun_energy": "主光强度", "ambient_color": "环境光颜色", "ambient_energy": "环境光强度", "background_color": "天空背景颜色", "fog_enabled": "雾", "fog_density": "雾浓度", "fog_color": "雾颜色", "outline_enabled": "人物被遮挡时显示轮廓", "outline_color": "遮挡轮廓颜色", "outline_width": "遮挡轮廓宽度（像素）"}

func setup(host: Node3D) -> void:
	editor = host; add_theme_constant_override("separation", 7)
	var note := Label.new(); note.text = "应用后实时预览并保存到地图。切换时段会填入推荐光照值；仍可继续调整。遮挡轮廓用于游戏中的玩家角色。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	var apply_button := Button.new(); apply_button.text = "应用环境设置"; apply_button.pressed.connect(apply); add_child(apply_button)
	form = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(form)
	refresh()

func refresh() -> void:
	var values := Settings.resolve(editor._doc.map_meta)
	var key := JSON.stringify(values)
	if key == _key: return
	_key = key; fill(values)

func fill(values: Dictionary) -> void:
	var ordered := {}
	for key in ["preset", "sun_energy", "sun_color", "sun_rotation", "ambient_energy", "ambient_color", "background_color", "fog_enabled", "fog_density", "fog_color", "outline_enabled", "outline_color", "outline_width"]: ordered[key] = values[key]
	form.build(Settings.schema(), ordered, LABELS.merged({"preset": "时段"}, true), {"preset": [{"id":"day", "name":"白天"}, {"id":"sunset", "name":"黄昏"}, {"id":"night", "name":"夜晚"}]})
	form.fields.preset.item_selected.connect(func(index):
		var chosen: String = form.fields.preset.get_item_metadata(index)
		var current: Dictionary = form.values()
		current.merge(Settings.PRESETS[chosen].duplicate(true), true)
		fill(current)
	)

func apply() -> void:
	var result: Dictionary = editor._gameplay.set_environment(form.values())
	editor._status.text = "地图环境已应用，可撤销" if result.ok else str(result.error)
