extends SceneTree

func _init() -> void:
	var bad := 0
	var facade = load("res://scripts/net/mock_server.gd")
	if facade == null:
		print("FAIL facade mock_server.gd"); bad += 1
	else:
		print("OK    facade mock_server.gd")
	var server = facade.new() if facade != null else null
	if server != null:
		for property in server.get_property_list():
			var key := str(property.name)
			if not key.ends_with("_module_logic"):
				continue
			var domain = server.get(key)
			if domain == null or domain.get("ctrl") != server:
				print("FAIL domain owner ", key)
				bad += 1
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
		print("OK    ", f)
	if server != null:
		server.free()
	print("SERVER_OK=", bad == 0, " bad=", bad)
	quit(0 if bad == 0 else 1)
