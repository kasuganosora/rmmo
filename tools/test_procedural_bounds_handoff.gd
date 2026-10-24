extends "res://tools/test_native_road_preparation.gd"
const Bounds=preload("res://scripts/world3d/procedural_surface_bounds.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
func run()->void:
	var record:=road();record.road_mesh.kerbs=[part(true,true)]
	var arrays:Array=Road.arrays(record);var before:=var_to_bytes(arrays)
	var materials:Array=[];materials.resize(arrays.size())
	var expected:Mesh=Cpu.from_surfaces(arrays,materials)
	var worker:=Thread.new();worker.start(Bounds.bounds.bind(arrays))
	while worker.is_alive():await process_frame
	var box:AABB=worker.wait_to_finish()
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	var doc:=preload("res://scripts/world3d/world_document.gd").new();doc.load_immutable_records=true;queue._doc=doc
	queue._accept_prepared_records({"surface_arrays":{"road":arrays},"surface_bounds":{"road":box}})
	var node:=doc._mesh(record)
	check(node.mesh is Cpu and node.mesh.get_aabb()==expected.get_aabb(),"production handoff installs exact worker boundary")
	check(var_to_bytes(node.mesh.surfaces)==before,"production handoff preserves every geometry channel")
	check(queue.profile.worker_surface_bounds==1,"one worker boundary received for one procedural mesh")
	var old:=node.mesh;node.free();doc.load_surface_bounds.clear()
	var fallback:=doc._mesh(record)
	check(fallback.mesh.get_aabb()==old.get_aabb() and var_to_bytes(fallback.mesh.surfaces)==before,"legacy producer fallback yields identical geometry and bounds")
	fallback.free();queue.free()
	print("PROCEDURAL_BOUNDS_HANDOFF failures=",failures);quit(1 if failures else 0)
