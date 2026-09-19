extends SceneTree

func _init() -> void:
	var d := DirAccess.open("res://scripts/ui/panels")
	var files := []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			files.append(f)
		f = d.get_next()
	d.list_dir_end()
	files.sort()
	var bad := 0
	for fname in files:
		var sc = load("res://scripts/ui/panels/" + fname)
		if sc == null:
			bad += 1
			print("FAIL  ", fname)
		else:
			print("OK    ", fname)
	print("PANELS_OK=", bad == 0, " bad=", bad)
	quit()
