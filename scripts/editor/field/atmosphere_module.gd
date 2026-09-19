extends RefCounted
## Domain module: editor atmosphere (light, weather, fx-color, bgm controls).

var ctrl
func _init(c):
	ctrl = c

const EditorAtmosphere = preload("res://scripts/editor/interface/editor_atmosphere.gd")

func _fill_bgm_opt(current: String) -> void:
	EditorAtmosphere.fill_bgm_opt(ctrl, current)

func _on_toolbar_light() -> void:
	EditorAtmosphere.on_toolbar_light(ctrl)

func _sync_light_controls() -> void:
	EditorAtmosphere.sync_light_controls(ctrl)

func _apply_editor_light() -> void:
	EditorAtmosphere.apply_editor_light(ctrl)

func _on_toolbar_weather() -> void:
	EditorAtmosphere.on_toolbar_weather(ctrl)

func _apply_editor_atmosphere() -> void:
	EditorAtmosphere.apply_editor_atmosphere(ctrl)

func _on_fx_color_changed(c: Color) -> void:
	EditorAtmosphere.on_fx_color_changed(ctrl, c)

func _sync_fx_color_controls() -> void:
	EditorAtmosphere.sync_fx_color_controls(ctrl)

func _apply_editor_fx_color() -> void:
	EditorAtmosphere.apply_editor_fx_color(ctrl)
