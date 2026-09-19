extends RefCounted
## Application layer: game settings binding and push to HUD.

const Net = preload("res://scripts/net/net.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

static func _connect_game_settings(ctrl) -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	if not gs.changed.is_connected(ctrl._on_game_settings_changed):
		gs.changed.connect(ctrl._on_game_settings_changed)
	ctrl._on_game_settings_changed()

static func _on_game_settings_changed(ctrl) -> void:
	ctrl._push_auto_potion_settings()
	ctrl._push_pet_assist_settings()
	ctrl._apply_camera_zoom()
	for npc in ctrl._npcs:
		if npc != null and is_instance_valid(npc) and npc.has_method("_refresh_nameplate"):
			npc._refresh_nameplate()
	ctrl._refresh_remote_nameplates()
	ctrl._apply_atmosphere()

static func _push_auto_potion_settings(ctrl) -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var srv = Net.server() if Net != null else null
	if srv == null or not srv.has_method("try_set_auto_potion"):
		return
	srv.try_set_auto_potion(
		bool(gs.auto_potion_hp),
		int(gs.auto_potion_hp_pct),
		bool(gs.auto_potion_mp),
		int(gs.auto_potion_mp_pct),
	)

static func _push_pet_assist_settings(ctrl) -> void:
	var gs := GameSettingsScript.get_i()
	if gs == null:
		return
	var srv = Net.server() if Net != null else null
	if srv == null or not srv.has_method("try_set_pet_assist"):
		return
	srv.try_set_pet_assist(bool(gs.get("pet_assist")) if "pet_assist" in gs else true)

