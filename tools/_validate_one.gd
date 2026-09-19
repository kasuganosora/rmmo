extends SceneTree

func _init() -> void:
	var args = OS.get_cmdline_args()
	for a in args:
		if a.begins_with("res://"):
			var s = load(a)
			print("ONE %s -> %s" % [a, s != null])
	quit()
