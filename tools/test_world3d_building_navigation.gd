extends "res://tools/test_world3d_medieval.gd"

func run() -> void:
	create_timer(180).timeout.connect(func():quit(2))
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Pass the saved medieval integration fixture path");quit(2);return
	var doc=Doc.open_file(args[0]);check(doc!=null,"load saved six-house regression document")
	if doc==null:quit(1);return
	var fixtures: Array=[]
	for value in doc.map_meta.building_instances.values():
		if value.position[0]>=150 or absf(value.position[2])>.01:continue
		fixtures.append({"parameters":value.parameters,"position":value.position,"yaw":value.yaw,"plan":Blueprint.generate(value.parameters)})
	fixtures.sort_custom(func(a,b):return a.position[0]<b.position[0])
	check(fixtures.size()==6,"all original layouts are represented")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(args[0]);var loaded: Array=await loader.finished
	check(loaded[0]!=null,"load streamed collision data")
	if loaded[0]!=null:await runtime_checks(loaded[0],fixtures)
	print("test_world3d_building_navigation: ","PASS" if failed==0 else "FAIL");quit(0 if failed==0 else 1)
