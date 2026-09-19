extends SceneTree

func _init() -> void:
	# Preload player.gd so its whole preload graph (modules) is compiled.
	var p = preload("res://scripts/game/player.gd")
	print("PLAYER_PARSE_OK ", p != null)
	quit()
