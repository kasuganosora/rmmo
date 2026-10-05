extends "res://tools/test_ground_batching.gd"
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/house_revision_v10/checkpoint.json"))
	var compiler=preload("res://scripts/world_editor/building_tools.gd").new()
	var rows:Array=[]
	for house:Dictionary in source.houses:
		var originals:Array=source.records.filter(func(r):return r.get("building",{}).get("id","")==house.building_id)
		var before:=originals.duplicate(true)
		var plan:={"records":originals,"position":house.position,"yaw":house.get("yaw",0)}
		var start:=Time.get_ticks_msec();var result:Dictionary=compiler.freeze_plan(plan)
		check(result.ok,"bake "+house.building_id)
		if not result.ok:print(result);quit(1);return
		check(originals==before,"source untouched")
		var doc:=Doc.new();doc.records=plan.records
		var root3d:=Node3D.new();root.add_child(root3d)
		var scene:=doc.build();root3d.add_child(scene)
		Stream.sync(scene,root3d,B.vec(house.position))
		var library:Array=scene.get_meta("stream_library")
		check(library.size()==plan.records.size(),"no exploded source specs")
		var old_doc:=Doc.new();old_doc.load_box_meshes={};var expected:=0;var actual:=0
		for r:Dictionary in originals:
			if r.get("collision","block")=="none":continue
			var visual:=old_doc._mesh(r)
			var mesh:Mesh=visual.get_meta("collision_solid",visual.get_meta("paint_source",visual.mesh))
			expected+=Prefab.Cpu.capture(mesh).collision_faces().size();visual.free()
		for spec:Dictionary in library:
			if spec.extras.rmmo_collision!="none":actual+=Prefab.Cpu.capture(spec.get("collision_mesh",spec.mesh)).collision_faces().size()
		check(expected==actual,"exact collision triangles retained")
		var hide:Dictionary={}
		for spec:Dictionary in library:
			if int(spec.extras.get("building",{}).get("floor",0))>0:hide[spec.uuid]=true
		var cutaway:=preload("res://scripts/world3d/building_cutaway.gd").new();cutaway.map_root=scene;cutaway.apply_hidden(hide)
		for id:String in hide:check(not scene.get_meta("stream_meshes")[id].visible,"upper-floor component can be hidden")
		cutaway.restore()
		var candles:=preload("res://scripts/world3d/house_candle_lights.gd").new();root3d.add_child(candles);candles.bind_map(scene)
		check(candles.fixtures.size()==originals.filter(func(r):return r.get("building_shape")=="candle_sconce").size(),"night-light anchors retained")
		candles.set_hours(12);check(candles.lit_count()==0,"daytime lamps off")
		var fixtures:=Prefab.Fixtures.list_runtime(scene,house.building_id)
		check(fixtures.size()==Prefab.Fixtures.rows(originals,house.building_id).size(),"all moving leaves preserved")
		for fixture:Dictionary in fixtures.slice(0,2):
			check(Prefab.Fixtures.set_runtime(scene,house.building_id,fixture.id,1.,0.).ok,"open baked leaf")
			check(Prefab.Fixtures.set_runtime(scene,house.building_id,fixture.id,0.,0.).ok,"close baked leaf")
		var bodies:Dictionary=scene.get_meta("stream_bodies",{})
		rows.append({"house":house.building_id,"source_records":originals.size(),"baked_records":plan.records.size(),"fixtures":fixtures.size(),"render_nodes":scene.get_meta("stream_meshes").size(),"bodies":bodies.size(),"bake_and_check_ms":Time.get_ticks_msec()-start})
		print("PREFAB_RESULT ",JSON.stringify(rows.back()))
		root3d.free()
	var out:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/house_prefab.json",FileAccess.WRITE);out.store_string(JSON.stringify(rows,"\t"));out.close()
	print("HOUSE_PREFAB_FINISHED failures=",failed);quit(1 if failed else 0)
