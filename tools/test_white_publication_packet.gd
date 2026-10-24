extends "res://tools/test_private_publication_packet.gd"
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
func whiten(spec:Dictionary)->void:
	var replacements:Array=[];var mesh:Mesh=spec.mesh
	for slot:int in mesh.surfaces.size():
		var material:Material=mesh.materials[slot]
		replacements.append(Controls.white_material(material.cull_mode))
	spec.mesh=Controls.prepare_cpu_materials(mesh,replacements);spec.material_override=null;spec.surface_overrides=[]
func run()->void:
	Controls.enable_white_materials();Controls.discard_map_textures=true
	var box:=BoxMesh.new();box.material=StandardMaterial3D.new();var original:Mesh=Cpu.capture(box)
	var source:=values(original);var prep:=Prep.new();prep.begin_runtime_owned(source)
	var slices:=0;var began:=Time.get_ticks_usec()
	while not prep.advance(500):slices+=1
	var prepare_us:=Time.get_ticks_usec()-began;var packet:RefCounted=prep.publication_packet
	check(prep.valid_runtime_owned(source),"private index completes with the exact source array")
	var original_surfaces:=var_to_bytes(original.surfaces);var projected:=0;began=Time.get_ticks_usec()
	var early:bool=packet.has_method("white_ready") and packet.call("white_ready",source)
	if not early:
		for spec:Dictionary in source:
			var before:Mesh=spec.mesh;whiten(spec)
			if not is_same(before,spec.mesh):projected+=1
	var callback_us:=Time.get_ticks_usec()-began
	var all_white:=true
	for spec:Dictionary in source:all_white=all_white and spec.mesh.materials==[Controls.white_material()] and spec.surface_overrides.is_empty()
	check(all_white,"all published CPU geometry is already white")
	check(var_to_bytes(original.surfaces)==original_surfaces and original.materials==[box.material],"source geometry and original material ownership remain unchanged")
	var control:=fixture(Nav);var fast:=fixture(Nav);control.append_specs(source)
	check(fast.append_specs(source,packet if early else null).ok and snapshot(fast)==snapshot(control),"prepared white geometry matches ordinary navigation ownership and bounds")
	if packet.has_method("white_ready"):
		check(early and projected==0,"publication callback performs no material projections")
		Controls.enable_white_materials();check(not packet.white_ready(source),"another white-material generation invalidates the readiness stamp")
	print("WHITE_PUBLICATION_PACKET ",JSON.stringify({"prepare_us":prepare_us,"slices":slices+1,"callback_us":callback_us,"late_projections":projected,"early":early,"failures":failures}))
	control.free();fast.free();prep.dispose();Controls.white_materials=false;quit(1 if failures else 0)
