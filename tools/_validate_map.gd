extends SceneTree

func _init() -> void:
	var bad := 0
	var facade = load("res://scripts/map/map_field.gd")
	if facade == null:
		print("FAIL facade map_field.gd"); bad += 1
	else:
		print("OK    facade map_field.gd")
	var d := DirAccess.open("res://scripts/map/field")
	if d == null:
		print("MAP_OK=", bad == 0, " (no field dir yet) bad=", bad)
		quit()
		return
	var files := []
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(".gd"):
			files.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	files.sort()
	for f in files:
		var sc = load("res://scripts/map/field/" + f)
		if sc == null:
			print("FAIL load ", f); bad += 1; continue
		var inst = sc.new(self)
		if inst == null or inst.get("ctrl") != self:
			print("FAIL init/ctrl ", f); bad += 1; continue
		for m in inst.get_method_list():
			if m.flags & METHOD_FLAG_STATIC:
				print("FAIL static ", f, " ", m.name); bad += 1
		print("OK    ", f)
	print("MAP_OK=", bad == 0, " bad=", bad)
	quit()
