extends SceneTree

func _init() -> void:
	# Preload world.gd FIRST so `class_name World` registers in the global class
	# registry before action_apply.gd (which types ctrl: World) is compiled.
	var w = preload("res://scripts/game/world.gd")
	var a = preload("res://scripts/game/application/action_apply.gd")
	print("WORLD_PARSE_OK ", a != null and w != null)
	quit()
