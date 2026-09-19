extends RefCounted
## Application layer: player gear look refresh and camera zoom.

const Net = preload("res://scripts/net/net.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

static func _refresh_player_gear_look(ctrl, equipment: Array) -> void:
	if ctrl.player == null or not ctrl.player.has_method("apply_gear_look"):
		return
	var ch: Dictionary = {}
	if Net.session() != null:
		ch = Net.session().active_character()
	var catalog = null
	var srv = Net.server()
	if srv != null:
		catalog = srv.get("item_catalog")
	ctrl.player.apply_gear_look(ch, equipment, catalog)

static func _apply_camera_zoom(ctrl) -> void:
	if ctrl.player == null or not ctrl.player.has_method("apply_camera_zoom"):
		return
	var gs = GameSettingsScript.get_i()
	var z = 1.0
	if gs != null:
		z = float(gs.camera_zoom)
	ctrl.player.apply_camera_zoom(z)

