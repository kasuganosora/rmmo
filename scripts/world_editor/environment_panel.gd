extends VBoxContainer
const Settings = preload("res://scripts/world3d/environment_settings.gd")
var editor: Node3D
var form: VBoxContainer
var _key := ""
const LABELS = {"interior_cutaway":"第三人称先被楼板挡住时隐藏天花板及上层", "indoor_camera_distance":"第三人称室内相机最远距离（米）", "preset": "时段（day 白天 / sunset 黄昏 / night 夜晚）", "sun_rotation": "主光方向（度）", "sun_color": "主光颜色", "sun_energy": "主光强度", "sun_shadows": "太阳光投影", "ambient_occlusion": "环境遮蔽（接缝与接触处）", "ambient_color": "环境光颜色", "ambient_energy": "环境光强度", "background_color": "天空背景颜色", "fog_enabled": "雾", "fog_density": "雾浓度", "fog_color": "雾颜色", "outline_enabled": "人物被遮挡时显示轮廓", "outline_color": "遮挡轮廓颜色", "outline_width": "遮挡轮廓宽度（像素）"}

func setup(host: Node3D) -> void:
	editor = host; add_theme_constant_override("separation", 7)
	var note := Label.new(); note.text = "按主题调整参数，再点击上方「应用环境设置」。支持撤销。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	form = preload("res://scripts/world_editor/settings_form.gd").new(); add_child(form)
	refresh()

func refresh() -> void:
	var values := Settings.resolve(editor._doc.map_meta)
	var key := JSON.stringify(values)
	if key == _key: return
	_key = key; fill(values)

func fill(values: Dictionary) -> void:
	var ordered := {}
	for key in ["preset", "time_hours", "time_speed", "celestial_cycle", "weather", "weather_intensity", "wind_speed", "wind_direction", "weather_transition", "sky_enabled", "cloud_altitude", "cloud_thickness", "cloud_scale", "cirrus_amount", "star_intensity", "meteors_enabled", "meteor_frequency", "lightning_enabled", "thunder_enabled", "lightning_center", "lightning_radius", "environment_audio", "surface_wetness", "initial_wetness", "wetting_seconds", "drying_seconds", "puddle_strength", "sun_energy", "sun_color", "sun_rotation", "sun_shadows", "ambient_occlusion", "ambient_energy", "ambient_color", "background_color", "fog_enabled", "fog_density", "fog_color", "outline_enabled", "outline_color", "outline_width", "interior_cutaway", "indoor_camera_distance"]: ordered[key] = values[key]
	var weather_choices: Array = []
	var profile = preload("res://scripts/world3d/weather_profile.gd")
	for index in profile.KINDS.size(): weather_choices.append({"id":profile.KINDS[index], "name":profile.LABELS[index]})
	form.build(Settings.schema(), ordered, LABELS.merged({"preset":"时段", "time_hours":"世界时间（小时，0～24）", "time_speed":"时间倍率（游戏秒 / 秒，0 暂停）", "weather":"天气", "weather_intensity":"天气强度（0～1）", "wind_speed":"风速（米 / 秒）", "wind_direction":"风向（度）", "weather_transition":"天气过渡（秒）", "sky_enabled":"立体天空与流动云层", "cloud_altitude":"云底高度（世界米）", "cloud_thickness":"云层厚度（米）", "cloud_scale":"云团尺度（米）", "cirrus_amount":"高空薄云（0～1）", "star_intensity":"夜间星空亮度（0 关闭）", "meteors_enabled":"夜间流星", "meteor_frequency":"流星频率（次 / 分钟，0 关闭）", "lightning_enabled":"雷暴闪电", "celestial_cycle":"连续昼夜（关闭则使用手工主光）", "thunder_enabled":"按距离延迟的雷声", "lightning_center":"雷暴落点区域中心（世界坐标）", "lightning_radius":"雷暴落点区域半径（米）", "environment_audio":"雨声 / 屋顶雨声 / 风声 / 雷声", "surface_wetness":"本地地表湿润与积水", "initial_wetness":"进入地图时湿润度（本地初值）", "wetting_seconds":"湿润响应时间（秒）", "drying_seconds":"干燥响应时间（秒）", "puddle_strength":"积水反光强度"}, true), {"weather":weather_choices, "preset": [{"id":"day", "name":"白天"}, {"id":"sunset", "name":"黄昏"}, {"id":"night", "name":"夜晚"}]})
	form.group_fields([
		{"id":"time", "label":"时间与天气", "expanded":true, "fields":["preset","time_hours","weather","weather_intensity"]},
		{"id":"progression", "label":"时间推进与天气过渡", "fields":["time_speed","celestial_cycle","weather_transition"]},
		{"id":"wind", "label":"风与环境声音", "fields":["wind_speed","wind_direction","environment_audio"]},
		{"id":"sky", "label":"天空、云层与星空", "fields":["sky_enabled","cloud_altitude","cloud_thickness","cloud_scale","cirrus_amount","star_intensity","meteors_enabled","meteor_frequency"]},
		{"id":"storm", "label":"闪电与雷声", "fields":["lightning_enabled","thunder_enabled","lightning_center","lightning_radius"]},
		{"id":"wet", "label":"湿润与积水", "fields":["surface_wetness","initial_wetness","wetting_seconds","drying_seconds","puddle_strength"]},
		{"id":"light", "label":"光照与阴影", "fields":["sun_energy","sun_color","sun_rotation","sun_shadows","ambient_occlusion","ambient_energy","ambient_color","background_color"]},
		{"id":"fog", "label":"雾效", "fields":["fog_enabled","fog_density","fog_color"]},
		{"id":"camera", "label":"人物遮挡与室内视角", "fields":["outline_enabled","outline_color","outline_width","interior_cutaway","indoor_camera_distance"]}
	])
	form.fields.preset.item_selected.connect(func(index):
		var chosen: String = form.fields.preset.get_item_metadata(index)
		var current: Dictionary = form.values()
		current.merge(Settings.PRESETS[chosen].duplicate(true), true)
		current.time_hours = {"day":12.0,"sunset":18.0,"night":0.0}[chosen]
		fill(current)
	)
	form.fields.time_hours.value_changed.connect(func(hour):
		var current: Dictionary = form.values()
		var phase := Settings.time_preset(hour)
		if current.preset == phase: return
		current.preset = phase; current.merge(Settings.PRESETS[phase].duplicate(true),true)
		fill(current)
	)

func apply() -> void:
	var result: Dictionary = editor._gameplay.set_environment(form.values())
	editor._status.text = "地图环境已应用，可撤销" if result.ok else str(result.error)
