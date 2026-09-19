extends SceneTree

func _init() -> void:
	var bad := 0
	var facade = load("res://scripts/net/mock_server.gd")
	if facade == null:
		print("FAIL facade mock_server.gd"); bad += 1
	else:
		print("OK    facade mock_server.gd")
	var d := DirAccess.open("res://scripts/net/server")
	if d == null:
		print("SERVER_OK=", bad == 0, " (no server dir yet) bad=", bad)
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
		var sc = load("res://scripts/net/server/" + f)
		if sc == null:
			print("FAIL load ", f); bad += 1; continue
		var inst = sc.new(self)
		if inst == null or inst.get("ctrl") != self:
			print("FAIL init/ctrl ", f); bad += 1; continue
		for m in inst.get_method_list():
			if m.flags & METHOD_FLAG_STATIC:
				print("FAIL static ", f, " ", m.name); bad += 1
		print("OK    ", f)
	print("SERVER_OK=", bad == 0, " bad=", bad)
	quit()
