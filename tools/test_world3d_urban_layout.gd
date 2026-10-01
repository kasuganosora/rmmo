extends SceneTree
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
var failed:=0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("%s: %s"%["PASS" if ok else "FAIL",label]); if not ok: failed+=1

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("urban layout timeout"); quit(2))
	var base:=Blueprint.layout_defaults("urban_village")
	equipment_roundtrip(base)
	var cases: Array=[base,base.merged({"width":8.5,"depth":10,"floors":2,"bedrooms":1,"floor_height":4,"balcony":"none","roof_canopy":false},true),base.merged({"width":11,"depth":15,"floors":6,"bedrooms":3,"balcony":"corner","template":"shop"},true)]
	for invalid in [{"width":8.0},{"depth":10,"bedrooms":3},{"template":"inn"},{"roof":"gable"},{"compound":"left_wing"},{"jetty":.3},{"balcony":"corner","right_wall":"party"},{"rental_units":4}]:
		check(not Blueprint.generate(base.merged(invalid,true)).ok,"reject unsupported family layout "+str(invalid))
	check(not Blueprint.generate({"floors":4}).ok,"legacy floor limit remains three")
	for index in cases.size():
		var p: Dictionary=cases[index]; var plan:=Blueprint.generate(p)
		check(plan.ok,"urban family plan %d"%index)
		if not plan.ok: print(plan); quit(1); return
		check(plan.records.size()<=2000,"persistable parts %d"%plan.records.size())
		check(plan.stairs.size()==p.floors*2,"two flights per floor including rooftop access")
		var parts:={}
		for record in plan.records:
			check(false,"duplicate part "+record.building.part) if parts.has(record.building.part) else parts.set(record.building.part,true)
		var doc:=Doc.new(); doc.add_box("ground",Vector3(45,-.1,15),Vector3(160,.2,100))
		var origin:=Vector3(55,0,0) if index==1 else Vector3(.07,0,.11); var basis:=Basis(Vector3.UP,deg_to_rad(37 if index==2 else (-23 if index==1 else 0)))
		for record in plan.records:
			var copy: Dictionary=record.duplicate(true); copy.position=Blueprint.arr(origin+basis*Blueprint.vec(copy.position)); copy.rotation=Blueprint.arr((basis*Basis.from_euler(Blueprint.vec(copy.rotation)*PI/180)).get_euler()*180/PI); doc.records.append(copy)
		var specs: Array=[]
		for record in doc.records:
			var visual:=doc._mesh(record); specs.append({"mesh":visual.mesh,"transform":visual.transform,"extras":visual.get_meta("extras")}); visual.free()
		var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); root.add_child(nav); nav.build(specs)
		var deadline:=Time.get_ticks_msec()+25000
		while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
		check(nav.fully_ready,"navigation ready")
		if nav.fully_ready:
			for destination in plan.rooms+plan.terraces:
				var point:=origin+basis*Blueprint.vec(destination.center)
				var route: Dictionary=nav.find_path(origin+basis*Blueprint.vec(plan.entrance),point)
				check(route.ok,"case%d entry reaches %s"%[index,destination.id])
				if not route.ok: print("  target=",point," nearest=",NavigationServer3D.map_get_closest_point(nav.map,point))
		nav.free(); await process_frame
	print("test_world3d_urban_layout: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func equipment_roundtrip(parameters: Dictionary) -> void:
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("urban_equipment_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var library:=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("assets"))
	var parts: Array=Blueprint.generate(parameters).records.filter(func(r): return r.building.part=="roof/tank")
	parts[0].building.id="test_source"; parts[0].size=[2,3,1]
	var prefabs:=preload("res://scripts/world_editor/prefab_library.gd")
	var saved:=prefabs.capture(parts,library,"变形水箱")
	check(saved.ok,"cylinder equipment can be captured as a reusable prefab")
	if not saved.ok: return
	var packed:=prefabs.read(saved.entry)
	check(packed.ok and packed.records[0].building_shape=="cylinder" and not packed.records[0].has("building"),"prefab keeps cylinder mesh without live building ownership")
	var doc:=Doc.new(); var placed:=prefabs.place(doc,saved.entry,Vector3(4,0,3))
	check(placed.ok and doc.save(directory.path_join("map.gltf"))==OK,"resized cylinder prefab places and saves")
	var reopened: RefCounted=Doc.open_file(directory.path_join("map.gltf"))
	check(reopened!=null,"detached equipment reopens without a building registry")
	if reopened!=null:
		var visual: MeshInstance3D=reopened._mesh(reopened.records[0])
		check(visual.mesh.get_aabb().size.is_equal_approx(Vector3(2,3,1)) and visual.mesh.get_faces().size()>36,"nonuniform size and cylinder topology survive prefab and map roundtrip")
		visual.free()
	preload("res://scripts/world3d/gltf_map_io.gd")._remove_tree(directory)
