extends SceneTree
## Navigation voxel alignment must not disconnect otherwise traversable platforms.
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
var failed:=0
func _init() -> void: call_deferred("run")

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("Building clearance test timeout"); quit(2))
	var base: Dictionary=Blueprint.medieval_presets()[0].parameters
	var cases: Array=[base,base.merged({"width":5.5,"floors":3},true),base.merged({"width":5.5,"depth":14,"floor_height":4.0},true)]
	for parameters in cases:
		for yaw in [0.0,37.0,90.0]:
			var plan:=Blueprint.generate(parameters); var doc:=Doc.new()
			if not plan.ok: print("FAIL: invalid clearance fixture ",plan); quit(1); return
			doc.add_box("ground",Vector3(65,-.1,30),Vector3(240,.2,200))
			var origin:=Vector3(15.07,0,12.11); var basis:=Basis(Vector3.UP,deg_to_rad(yaw))
			for record in plan.records:
				var copy: Dictionary=record.duplicate(true); copy.position=Blueprint.arr(origin+basis*Blueprint.vec(copy.position)); copy.rotation=Blueprint.arr((basis*Basis.from_euler(Blueprint.vec(copy.rotation)*PI/180)).get_euler()*180/PI); doc.records.append(copy)
			var specs: Array=[]
			for record in doc.records:
				var node:=doc._mesh(record); specs.append({"mesh":node.mesh,"transform":node.transform,"extras":node.get_meta("extras")}); node.free()
			var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); root.add_child(nav); nav.build(specs)
			while not nav.fully_ready: await process_frame
			var ok:=true
			for room in plan.rooms:
				var outcome: Dictionary=nav.find_path(origin+basis*Blueprint.vec(plan.entrance),origin+basis*Blueprint.vec(room.center))
				if not outcome.ok: ok=false; print("  inaccessible room ",room.id)
			print("%s: width=%s floors=%s height=%s yaw=%s"%["PASS" if ok else "FAIL",parameters.width,parameters.floors,parameters.floor_height,yaw])
			if not ok: failed+=1
			nav.free(); await process_frame
	print("test_world3d_building_clearance: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)
