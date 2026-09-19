extends SceneTree

func _init() -> void:
	# Force compilation of the editor script and its entire preload graph.
	var s = preload("res://scripts/editor/content_editor.gd")
	print("EDITOR_PARSE_OK ", s != null)
	quit()
