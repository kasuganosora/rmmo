extends RefCounted
## Domain module: atmosphere (weather FX, light, parallax, indoor/outdoor).

var ctrl
func _init(c):
	ctrl = c

const MapExt = preload("res://scripts/map/map_ext.gd")
const Weather = preload("res://scripts/map/weather.gd")
const WeatherFxScript = preload("res://scripts/map/weather_fx.gd")

func light_fx_color() -> Color:
	if ctrl.edit_doc != null and "light_fx_color" in ctrl.edit_doc:
		return ctrl.edit_doc.light_fx_color
	if ctrl.pack != null and "light_fx_color" in ctrl.pack:
		return ctrl.pack.light_fx_color
	if ctrl.pack != null and ctrl.pack.get("ext") != null and "light_color" in ctrl.pack.ext:
		return ctrl.pack.ext.light_color
	if ctrl.collision != null and ctrl.collision.ext != null and "light_color" in ctrl.collision.ext:
		return ctrl.collision.ext.light_color
	return Color(1, 1, 1, 1)



func apply_light_fx_color() -> void:
	var c = light_fx_color()
	for key in ctrl._chunks.keys():
		var ch: Node2D = ctrl._chunks[key]
		if ch != null and ch.has_method("set_fx_modulate"):
			ch.set_fx_modulate(c)



func set_bucket_alpha(bucket: String, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	ctrl.edit_bucket_alpha[bucket] = a
	for key in ctrl._chunks.keys():
		var ch: Node = ctrl._chunks[key]
		if ch == null:
			continue
		var spr: Sprite2D = ch.get_node_or_null(bucket) as Sprite2D
		if spr:
			var m: Color = spr.modulate
			m.a = a
			spr.modulate = m
		var anim: Sprite2D = ch.get_node_or_null(bucket + "Anim") as Sprite2D
		if anim:
			var m2: Color = anim.modulate
			m2.a = a
			anim.modulate = m2



func map_is_indoor() -> bool:
	if ctrl.edit_doc != null and "environment" in ctrl.edit_doc:
		return MapExt.normalize_environment(ctrl.edit_doc.environment) == MapExt.ENV_INDOOR
	if ctrl.pack != null and "environment" in ctrl.pack:
		return MapExt.normalize_environment(ctrl.pack.environment) == MapExt.ENV_INDOOR
	return false



func set_atmosphere(light_id: int, kind: String, intensity: float) -> Dictionary:
	ctrl._atm_light = light_id
	ctrl._atm_kind = str(kind)
	ctrl._atm_intensity = intensity
	var atm: Dictionary = Weather.compose(light_id, kind, intensity, map_is_indoor())
	ctrl.last_atmosphere = atm
	_ensure_weather_fx()
	if ctrl._weather_fx and ctrl._weather_fx.has_method("apply"):
		ctrl._weather_fx.apply(atm)
	_sync_weather_eaves()
	return atm



func weather_display_modulate() -> Color:
	if ctrl._weather_fx != null and is_instance_valid(ctrl._weather_fx) and ctrl._weather_fx.has_method("display_modulate"):
		return ctrl._weather_fx.display_modulate()
	var c: Variant = ctrl.last_atmosphere.get("modulate", Color.WHITE)
	if typeof(c) == TYPE_COLOR:
		return c
	return Color.WHITE



func _ensure_weather_fx() -> void:
	if ctrl._weather_fx != null and is_instance_valid(ctrl._weather_fx):
		return
	ctrl._weather_fx = WeatherFxScript.new()
	ctrl._weather_fx.name = "WeatherFx"
	ctrl._weather_fx.layer = Weather.CANVAS_ATMOSPHERE
	ctrl.add_child(ctrl._weather_fx)



func _sync_weather_eaves() -> void:
	if ctrl._weather_fx == null or not ctrl._weather_fx.has_method("set_eaves"):
		return
	var eaves = false
	if ctrl.collision != null and ctrl.collision.has_method("meta_at"):
		eaves = (int(ctrl.collision.meta_at(ctrl._obs_cell.x, ctrl._obs_cell.y)) & MapExt.META_INDOOR) != 0
	elif ctrl.edit_doc != null and ctrl.edit_doc.has_method("ext_tile"):
		eaves = (int(ctrl.edit_doc.ext_tile("meta", ctrl._obs_cell.x, ctrl._obs_cell.y)) & MapExt.META_INDOOR) != 0
	ctrl._weather_fx.set_eaves(eaves)



func far_scroll_vec() -> Vector2:
	if ctrl.edit_doc != null and "far_scroll" in ctrl.edit_doc:
		return ctrl.edit_doc.far_scroll
	if ctrl.pack != null and "ext" in ctrl.pack and ctrl.pack.ext != null and "far_scroll" in ctrl.pack.ext:
		return ctrl.pack.ext.far_scroll
	if ctrl.collision != null and ctrl.collision.ext != null and "far_scroll" in ctrl.collision.ext:
		return ctrl.collision.ext.far_scroll
	return Vector2.ZERO



func _apply_far_parallax() -> void:
	var sc = far_scroll_vec()
	var off = Vector2.ZERO
	if sc != Vector2.ZERO:
		var cam = ctrl.get_viewport().get_camera_2d() if ctrl.get_viewport() else null
		var origin = Vector2.ZERO
		if cam != null:
			origin = cam.get_screen_center_position()
		off = Vector2(origin.x * sc.x, origin.y * sc.y)
	for key in ctrl._chunks.keys():
		var ch: Node2D = ctrl._chunks[key]
		if ch != null and ch.has_method("set_below_offset"):
			ch.set_below_offset(off)



func _apply_indoor_from_cell(cell: Vector2i) -> void:
	var indoor = false
	if ctrl.collision != null and ctrl.collision.has_method("meta_at"):
		indoor = (int(ctrl.collision.meta_at(cell.x, cell.y)) & MapExt.META_INDOOR) != 0
	if indoor == ctrl._roof_hidden:
		return
	ctrl._roof_hidden = indoor
	for key in ctrl._chunks.keys():
		var ch: Node2D = ctrl._chunks[key]
		if ch != null and ch.has_method("set_roof_visible"):
			ch.set_roof_visible(not ctrl._roof_hidden)
	_sync_weather_eaves()


