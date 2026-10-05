extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Preparer=preload("res://scripts/world3d/stream_collision_preparer.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	for partial in [false,true]:
		for whole_world in [true,false]:
			var host:=Node3D.new();root.add_child(host)
			var map:=Node3D.new();host.add_child(map)
			var preparer:=Preparer.new();map.add_child(preparer)
			var shape:=ConcavePolygonShape3D.new()
			shape.set_faces(PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK]))
			var shapes:Array=[];shapes.resize(10000 if partial else 1);shapes.fill(shape)
			var cpu:=Cpu.new();cpu.set_meta("runtime_terrain_shapes",shapes)
			var spec:={"uuid":"exit_fixture","mesh":cpu,"ground_batch_record":{"terrain_mesh":{}}}
			var ready:bool=preparer.prepare(spec,host)
			check(ready!=partial,"fixture reached partial/ready unpublished state: %s"%partial)
			var body:Node=preparer._terrain._body if partial else spec.get("prepared_body")
			var body_id:=body.get_instance_id()
			check(body.collision_layer==0 and body.collision_mask==0,"unpublished body stays disabled")
			print("EXIT whole_world=",whole_world," partial=",partial)
			if whole_world:host.free()
			else:map.free()
			await process_frame
			check(not is_instance_id_valid(body_id) and not spec.has("prepared_body"),"exit releases body and clears pending ownership")
			if not whole_world:
				check(host.get_child_count()==0,"surviving world has no orphaned physics")
				host.free()
	print("TERRAIN_COLLISION_EXIT failures=",failures)
	quit(1 if failures else 0)
