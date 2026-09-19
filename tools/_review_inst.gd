extends SceneTree

func _init() -> void:
	var d := DirAccess.open("res://scripts/ui/panels")
	var files := []
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.ends_with(".gd"):
			files.append(fn)
		fn = d.get_next()
	d.list_dir_end()
	files.sort()
	var bad := 0
	for f in files:
		var sc = load("res://scripts/ui/panels/" + f)
		if sc == null:
			print("FAIL load ", f); bad += 1; continue
		var inst = sc.new(self)  # mock ctrl
		if inst == null:
			print("FAIL new ", f); bad += 1; continue
		if inst.get("ctrl") != self:
			print("FAIL ctrl-not-bound ", f); bad += 1; continue
		var n := 0
		for m in inst.get_method_list():
			var nm := String(m.name)
			if nm != "_init" and not nm.begins_with("_static") and not (m.flags & METHOD_FLAG_STATIC):
				n += 1
		if n == 0:
			print("FAIL no-instance-methods ", f); bad += 1; continue
		# ensure no leftover static funcs (instance refactor)
		for m in inst.get_method_list():
			if (m.flags & METHOD_FLAG_STATIC) and String(m.name) != "":
				print("FAIL has-static ", f, " ", m.name); bad += 1
	print("INST_OK=", bad == 0, " bad=", bad)
	quit()
