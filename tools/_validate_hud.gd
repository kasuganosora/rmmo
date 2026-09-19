extends SceneTree

func _init() -> void:
	# Preload the HUD so its whole preload graph (panel modules) is compiled.
	var h = preload("res://scripts/ui/game_hud.gd")
	print("HUD_PARSE_OK ", h != null)
	quit()
