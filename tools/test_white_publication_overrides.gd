extends "res://tools/profile_axel_game_pipeline.gd"
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
func _initialize()->void:run_white_test.call_deferred()
func effective(spec:Dictionary)->Array:
	var result:Array=[]
	for slot:int in spec.mesh.get_surface_count():
		var material:Material=spec.get("material_override")
		if material==null:
			var overrides:Array=spec.get("surface_overrides",[])
			material=overrides[slot] if slot<overrides.size() and overrides[slot]!=null else spec.mesh.surface_get_material(slot)
		result.append(material)
	return result
func legacy_whiten(spec:Dictionary)->void:
	var overrides:Array=[];var mesh:Mesh=spec.mesh
	for slot:int in mesh.get_surface_count():
		var material:Material=spec.get("material_override")
		if material==null:
			var original:Array=spec.get("surface_overrides",[])
			material=original[slot] if slot<original.size() and original[slot]!=null else mesh.surface_get_material(slot)
		overrides.append(Controls.white_material(material.cull_mode if material is BaseMaterial3D else BaseMaterial3D.CULL_BACK))
	spec.mesh=Controls.prepare_cpu_materials(mesh,overrides)
	spec.material_override=null;spec.surface_overrides=overrides
func run_white_test()->void:
	Controls.enable_white_materials();Controls.discard_map_textures=true
	for cpu:bool in [false,true]:
		for already:bool in [false,true]:
			for cull:int in 3:
				var box:=BoxMesh.new();var material:=StandardMaterial3D.new();material.cull_mode=cull;material.albedo_color=Color.BLACK
				box.material=Controls.white_material(cull) if already else material
				var mesh:Mesh=Cpu.capture(box) if cpu else box
				for variant:int in 3:
					var spec:={"mesh":mesh,"material_override":Controls.white_material((cull+1)%3) if variant==1 else null,"surface_overrides":[Controls.white_material((cull+2)%3)] if variant==2 else []}
					var expected:=spec.duplicate();legacy_whiten(expected);whiten_spec(spec)
					check(effective(spec)==effective(expected),"same white material/cull for CPU/GPU, original/global/surface overrides")
					check(Cpu.capture(spec.mesh).surfaces==Cpu.capture(expected.mesh).surfaces,"white publication preserves every geometry channel")
	var box:=BoxMesh.new();box.material=Controls.white_material();var mesh:Mesh=Cpu.capture(box)
	var results:Array=[]
	for fast:bool in [false,true,true,false]:
		var specs:Array=[]
		for i:int in 2200:specs.append({"mesh":mesh,"material_override":null,"surface_overrides":[]})
		var started:=Time.get_ticks_usec()
		for spec:Dictionary in specs:
			if fast:whiten_spec(spec)
			else:legacy_whiten(spec)
		var elapsed:=Time.get_ticks_usec()-started;var slots:=0
		for spec:Dictionary in specs:slots+=spec.surface_overrides.size()
		if fast:check(slots==0 and is_same(specs[0].mesh,mesh),"already-white CPU geometry needs no instance overrides or new owner")
		results.append({"fast":fast,"us":elapsed,"override_slots":slots})
	print("WHITE_PUBLICATION_OVERRIDES ",JSON.stringify({"trials":results,"failures":report.failures}));quit(0 if report.failures.is_empty() else 1)
